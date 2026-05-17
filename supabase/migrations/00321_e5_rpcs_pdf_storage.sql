-- ============================================================================
-- R2 People · Sessao E5 · RPCs de gestao do storage de PDFs
-- ============================================================================
-- Funcoes:
--   rpc_import_jobs_get_pdf_url        · gera signed URL de 24h (RH)
--   rpc_import_worker_set_pdf_storage  · worker registra path apos upload (token)
--   rpc_import_jobs_cleanup_expired    · housekeeping · purga PDFs >30d archived
--
-- Convencoes:
--   - storage_path = tenant_id/job_id/original.pdf
--   - Signed URL: em ambiente real, gerar via supabase storage; aqui retornamos
--     a estrutura que a app vai usar para chamar storage.create_signed_url(...)
--   - cleanup_expired roda agendado (pg_cron em prod, manual em dev)
-- ============================================================================

-- ----------------------------------------------------------------------------
-- HELPER · monta path padrao
-- ----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION import_pdf_storage_path(p_tenant_id UUID, p_job_id UUID)
RETURNS TEXT
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT p_tenant_id::TEXT || '/' || p_job_id::TEXT || '/original.pdf';
$$;

-- ----------------------------------------------------------------------------
-- rpc_import_jobs_get_pdf_url · RH baixa o PDF original
-- ----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION rpc_import_jobs_get_pdf_url(p_job_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user app_users;
  v_job import_jobs;
BEGIN
  SELECT * INTO v_user FROM app_users WHERE id = current_user_id();
  IF v_user IS NULL THEN RETURN jsonb_build_object('error', 'not_authenticated'); END IF;
  IF NOT employees_can_read() THEN
    RETURN jsonb_build_object('error', 'permission_denied');
  END IF;

  SELECT * INTO v_job FROM import_jobs WHERE id = p_job_id;
  IF v_job IS NULL THEN
    RETURN jsonb_build_object('error', 'job_not_found');
  END IF;
  IF v_job.tenant_id <> v_user.tenant_id AND NOT is_super_admin() THEN
    RETURN jsonb_build_object('error', 'scope_outside_tenant');
  END IF;

  IF v_job.storage_path IS NULL THEN
    RETURN jsonb_build_object('error', 'pdf_not_stored');
  END IF;
  IF v_job.pdf_purged_at IS NOT NULL THEN
    RETURN jsonb_build_object(
      'error', 'pdf_purged',
      'purged_at', v_job.pdf_purged_at
    );
  END IF;

  -- Em Supabase real, gera signed URL com storage.create_signed_url(bucket, path, expires_in)
  -- Aqui retornamos os dados pra app chamar via supabase-js no client/server
  RETURN jsonb_build_object(
    'ok', TRUE,
    'bucket', 'import-pdfs',
    'path', v_job.storage_path,
    'expires_in', 86400,           -- 24h
    'file_name', v_job.source_file_name,
    'file_size', v_job.source_file_size,
    'uploaded_at', v_job.pdf_uploaded_at
  );
END;
$$;

-- ----------------------------------------------------------------------------
-- rpc_import_worker_set_pdf_storage · worker registra que subiu o PDF
-- Autenticado por worker_token (worker e anon mas valida o token do job)
-- ----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION rpc_import_worker_set_pdf_storage(
  p_job_id UUID,
  p_worker_token TEXT,
  p_storage_path TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_job import_jobs;
BEGIN
  SELECT * INTO v_job FROM import_jobs WHERE id = p_job_id;
  IF v_job IS NULL THEN
    RETURN jsonb_build_object('error', 'job_not_found');
  END IF;
  IF v_job.worker_token IS DISTINCT FROM p_worker_token THEN
    RETURN jsonb_build_object('error', 'invalid_token');
  END IF;

  -- Sanity check: path comeca com tenant_id correto
  IF (storage.foldername(p_storage_path))[1] <> v_job.tenant_id::TEXT THEN
    RETURN jsonb_build_object('error', 'path_tenant_mismatch');
  END IF;

  UPDATE import_jobs
    SET storage_path = p_storage_path,
        pdf_uploaded_at = now()
    WHERE id = p_job_id;

  RETURN jsonb_build_object('ok', TRUE, 'storage_path', p_storage_path);
END;
$$;

-- ----------------------------------------------------------------------------
-- rpc_import_jobs_cleanup_expired · housekeeping
-- Apaga do Storage e marca pdf_purged_at em jobs archivados ha 30+ dias.
-- Retorna a lista de paths apagados (para o caller invocar storage delete).
-- ----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION rpc_import_jobs_cleanup_expired()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user app_users;
  v_paths TEXT[];
  v_count INT;
BEGIN
  SELECT * INTO v_user FROM app_users WHERE id = current_user_id();
  IF v_user IS NULL THEN RETURN jsonb_build_object('error', 'not_authenticated'); END IF;
  IF NOT is_super_admin() THEN
    RETURN jsonb_build_object('error', 'permission_denied');
  END IF;

  -- Identifica jobs elegiveis e marca como purgados (lock implicito do UPDATE)
  WITH expired AS (
    SELECT id, storage_path
    FROM import_jobs
    WHERE storage_path IS NOT NULL
      AND pdf_purged_at IS NULL
      AND archived_at IS NOT NULL
      AND archived_at < now() - INTERVAL '30 days'
    FOR UPDATE SKIP LOCKED
  ),
  updated AS (
    UPDATE import_jobs j
    SET pdf_purged_at = now()
    FROM expired e
    WHERE j.id = e.id
    RETURNING e.storage_path
  )
  SELECT array_agg(storage_path), count(*)
  INTO v_paths, v_count
  FROM updated;

  -- Tambem apaga as linhas correspondentes em storage.objects
  -- (em Supabase real, isso e feito via API; aqui simulamos com DELETE)
  IF v_paths IS NOT NULL THEN
    DELETE FROM storage.objects
    WHERE bucket_id = 'import-pdfs'
      AND name = ANY(v_paths);
  END IF;

  RETURN jsonb_build_object(
    'ok', TRUE,
    'purged_count', COALESCE(v_count, 0),
    'paths', COALESCE(to_jsonb(v_paths), '[]'::JSONB)
  );
END;
$$;

-- ----------------------------------------------------------------------------
-- GRANTS
-- ----------------------------------------------------------------------------

GRANT EXECUTE ON FUNCTION import_pdf_storage_path TO authenticated, anon;
GRANT EXECUTE ON FUNCTION rpc_import_jobs_get_pdf_url TO authenticated;
GRANT EXECUTE ON FUNCTION rpc_import_worker_set_pdf_storage TO authenticated, anon;
GRANT EXECUTE ON FUNCTION rpc_import_jobs_cleanup_expired TO authenticated;

-- ----------------------------------------------------------------------------
-- rpc_import_worker_get_job_meta · worker pega tenant_id (para montar path)
-- ----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION rpc_import_worker_get_job_meta(
  p_job_id UUID,
  p_worker_token TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_job import_jobs;
BEGIN
  SELECT * INTO v_job FROM import_jobs WHERE id = p_job_id;
  IF v_job IS NULL THEN
    RETURN jsonb_build_object('error', 'job_not_found');
  END IF;
  IF v_job.worker_token IS DISTINCT FROM p_worker_token THEN
    RETURN jsonb_build_object('error', 'invalid_token');
  END IF;

  RETURN jsonb_build_object(
    'ok', TRUE,
    'tenant_id', v_job.tenant_id,
    'status', v_job.status,
    'storage_path_template', import_pdf_storage_path(v_job.tenant_id, v_job.id)
  );
END;
$$;

GRANT EXECUTE ON FUNCTION rpc_import_worker_get_job_meta TO authenticated, anon;

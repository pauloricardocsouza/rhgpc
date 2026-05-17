-- ============================================================================
-- R2 People · Testes Sessao E5 · Storage de PDFs
-- ============================================================================
-- 16 testes cobrindo:
--   T01-T03 · set_pdf_storage (worker side)
--   T04-T07 · get_pdf_url (app side)
--   T08-T10 · cleanup_expired (housekeeping)
--   T11-T12 · permissoes cross-tenant
--   T13-T14 · view de estatisticas
--   T15-T16 · idempotencia + path mismatch
-- ============================================================================

BEGIN;

-- ----------------------------------------------------------------------------
-- SETUP
-- ----------------------------------------------------------------------------

INSERT INTO tenants (id, slug, legal_name, display_name) VALUES
  ('00000000-0000-0000-e500-000000000001', 'tx-e5', 'Tenant X E5', 'X'),
  ('00000000-0000-0000-e500-000000000002', 'ty-e5', 'Tenant Y E5', 'Y');

INSERT INTO app_users (id, tenant_id, auth_user_id, email, full_name, role, employment_link, hired_at) VALUES
  ('00000000-0000-0000-e504-000000000001', '00000000-0000-0000-e500-000000000001',
   'e5aaaaaa-0000-0000-0000-000000000001', 'sa@e5.test', 'SA-E5', 'super_admin', 'clt', '2020-01-01'),
  ('00000000-0000-0000-e504-000000000003', '00000000-0000-0000-e500-000000000001',
   'e5aaaaaa-0000-0000-0000-000000000003', 'rh@x.test', 'RH-X', 'rh', 'clt', '2020-01-01'),
  ('00000000-0000-0000-e504-000000000005', '00000000-0000-0000-e500-000000000001',
   'e5aaaaaa-0000-0000-0000-000000000005', 'col@x.test', 'COL-X', 'colaborador', 'clt', '2020-01-01'),
  ('00000000-0000-0000-e504-000000000006', '00000000-0000-0000-e500-000000000002',
   'e5aaaaaa-0000-0000-0000-000000000006', 'rh@y.test', 'RH-Y', 'rh', 'clt', '2020-01-01');

-- RH-X cria um job
SELECT test_login('e5aaaaaa-0000-0000-0000-000000000003');

DO $$
DECLARE r JSONB;
BEGIN
  r := rpc_import_job_create(jsonb_build_object(
    'file_name', 'fichas-teste-e5.pdf',
    'file_size', '5242880',
    'pages_total', '16'
  ));
  PERFORM set_config('e5.job_id', r ->> 'id', FALSE);
  PERFORM set_config('e5.token', r ->> 'worker_token', FALSE);
END $$;

-- Tenant Y · job separado
SELECT test_login('e5aaaaaa-0000-0000-0000-000000000006');
DO $$
DECLARE r JSONB;
BEGIN
  r := rpc_import_job_create(jsonb_build_object(
    'file_name', 'tenant-y-pdf.pdf', 'file_size', '1000', 'pages_total', '3'
  ));
  PERFORM set_config('e5.job_y_id', r ->> 'id', FALSE);
  PERFORM set_config('e5.token_y', r ->> 'worker_token', FALSE);
END $$;

-- ============================================================================
-- T01 · helper de path gera formato esperado
-- ============================================================================

DO $$
DECLARE v_path TEXT;
DECLARE v_tenant UUID := '00000000-0000-0000-e500-000000000001';
DECLARE v_job UUID;
BEGIN
  v_job := current_setting('e5.job_id')::UUID;
  v_path := import_pdf_storage_path(v_tenant, v_job);
  IF v_path NOT LIKE v_tenant::TEXT || '/' || v_job::TEXT || '/original.pdf' THEN
    RAISE EXCEPTION 'T01 FAIL · path malformado · %', v_path;
  END IF;
  RAISE NOTICE 'PASS · T01 · path helper gera tenant_id/job_id/original.pdf';
END $$;

-- ============================================================================
-- T02 · worker set_pdf_storage com token correto
-- ============================================================================

DO $$
DECLARE v_path TEXT;
DECLARE r JSONB;
DECLARE v_job UUID;
BEGIN
  v_job := current_setting('e5.job_id')::UUID;
  v_path := import_pdf_storage_path('00000000-0000-0000-e500-000000000001', v_job);

  -- Simula o INSERT em storage.objects que o worker faria via API
  INSERT INTO storage.objects (bucket_id, name, metadata)
  VALUES ('import-pdfs', v_path, jsonb_build_object('size', 5242880, 'mimetype', 'application/pdf'));

  r := rpc_import_worker_set_pdf_storage(
    v_job,
    current_setting('e5.token'),
    v_path
  );

  IF (r ->> 'ok')::BOOLEAN <> TRUE THEN
    RAISE EXCEPTION 'T02 FAIL · r=%', r;
  END IF;
  RAISE NOTICE 'PASS · T02 · worker set_pdf_storage com token correto';
END $$;

-- ============================================================================
-- T03 · worker set_pdf_storage com token errado falha
-- ============================================================================

DO $$
DECLARE r JSONB;
DECLARE v_job UUID;
DECLARE v_path TEXT;
BEGIN
  v_job := current_setting('e5.job_id')::UUID;
  v_path := import_pdf_storage_path('00000000-0000-0000-e500-000000000001', v_job);
  r := rpc_import_worker_set_pdf_storage(v_job, 'token-errado-123', v_path);
  IF r ->> 'error' <> 'invalid_token' THEN
    RAISE EXCEPTION 'T03 FAIL · esperava invalid_token · veio %', r;
  END IF;
  RAISE NOTICE 'PASS · T03 · token errado bloqueado';
END $$;

-- ============================================================================
-- T04 · path tenant mismatch · worker tentando salvar em outro tenant
-- ============================================================================

DO $$
DECLARE r JSONB;
DECLARE v_job UUID;
BEGIN
  v_job := current_setting('e5.job_id')::UUID;
  -- Path falso apontando para outro tenant
  r := rpc_import_worker_set_pdf_storage(
    v_job, current_setting('e5.token'),
    '00000000-0000-0000-ffff-ffffffffffff/' || v_job::TEXT || '/original.pdf'
  );
  IF r ->> 'error' <> 'path_tenant_mismatch' THEN
    RAISE EXCEPTION 'T04 FAIL · esperava path_tenant_mismatch · veio %', r;
  END IF;
  RAISE NOTICE 'PASS · T04 · path tenant mismatch bloqueado';
END $$;

-- ============================================================================
-- T05 · RH consegue obter URL apos worker salvar
-- ============================================================================

SELECT test_login('e5aaaaaa-0000-0000-0000-000000000003');  -- RH-X

DO $$
DECLARE r JSONB;
DECLARE v_job UUID;
BEGIN
  v_job := current_setting('e5.job_id')::UUID;
  r := rpc_import_jobs_get_pdf_url(v_job);
  IF (r ->> 'ok')::BOOLEAN <> TRUE THEN
    RAISE EXCEPTION 'T05 FAIL · r=%', r;
  END IF;
  IF r ->> 'bucket' <> 'import-pdfs' THEN
    RAISE EXCEPTION 'T05 FAIL · bucket errado';
  END IF;
  IF r ->> 'path' IS NULL THEN
    RAISE EXCEPTION 'T05 FAIL · path ausente';
  END IF;
  IF (r ->> 'expires_in')::INT <> 86400 THEN
    RAISE EXCEPTION 'T05 FAIL · expires_in <> 86400';
  END IF;
  RAISE NOTICE 'PASS · T05 · RH obtem URL com bucket/path/expires';
END $$;

-- ============================================================================
-- T06 · Colaborador (read-only no employees) tambem pode obter URL
-- ============================================================================

SELECT test_login('e5aaaaaa-0000-0000-0000-000000000005');

DO $$
DECLARE r JSONB;
BEGIN
  r := rpc_import_jobs_get_pdf_url(current_setting('e5.job_id')::UUID);
  IF (r ->> 'ok')::BOOLEAN <> TRUE THEN
    RAISE EXCEPTION 'T06 FAIL · colaborador deveria poder obter URL (read-only) · r=%', r;
  END IF;
  RAISE NOTICE 'PASS · T06 · colaborador (read-only) pode obter URL';
END $$;

-- ============================================================================
-- T07 · Get URL em job sem PDF salvo
-- ============================================================================

SELECT test_login('e5aaaaaa-0000-0000-0000-000000000003');

DO $$
DECLARE r JSONB;
BEGIN
  -- Job_y_id ainda nao teve PDF setado
  -- mas o RH-X nem pode ver (cross-tenant) · entao cria um job novo no tenant X sem PDF
  r := rpc_import_job_create(jsonb_build_object(
    'file_name', 'sem-pdf.pdf', 'file_size', '100', 'pages_total', '1'
  ));
  PERFORM set_config('e5.job_no_pdf', r ->> 'id', FALSE);

  r := rpc_import_jobs_get_pdf_url(current_setting('e5.job_no_pdf')::UUID);
  IF r ->> 'error' <> 'pdf_not_stored' THEN
    RAISE EXCEPTION 'T07 FAIL · esperava pdf_not_stored · veio %', r;
  END IF;
  RAISE NOTICE 'PASS · T07 · job sem PDF retorna pdf_not_stored';
END $$;

-- ============================================================================
-- T08 · Cross-tenant · RH-Y nao consegue ver job de X
-- ============================================================================

SELECT test_login('e5aaaaaa-0000-0000-0000-000000000006');

DO $$
DECLARE r JSONB;
BEGIN
  r := rpc_import_jobs_get_pdf_url(current_setting('e5.job_id')::UUID);
  IF r ->> 'error' <> 'job_not_found' AND r ->> 'error' <> 'scope_outside_tenant' THEN
    RAISE EXCEPTION 'T08 FAIL · esperava job_not_found ou scope_outside_tenant · veio %', r;
  END IF;
  RAISE NOTICE 'PASS · T08 · cross-tenant bloqueado (% )', r ->> 'error';
END $$;

-- ============================================================================
-- T09 · Cleanup · so super_admin pode chamar
-- ============================================================================

SELECT test_login('e5aaaaaa-0000-0000-0000-000000000003');  -- RH

DO $$
DECLARE r JSONB;
BEGIN
  r := rpc_import_jobs_cleanup_expired();
  IF r ->> 'error' <> 'permission_denied' THEN
    RAISE EXCEPTION 'T09 FAIL · RH deveria ser bloqueado · veio %', r;
  END IF;
  RAISE NOTICE 'PASS · T09 · cleanup so para super_admin';
END $$;

-- ============================================================================
-- T10 · Cleanup com 0 expirados
-- ============================================================================

SELECT test_login('e5aaaaaa-0000-0000-0000-000000000001');  -- SA

DO $$
DECLARE r JSONB;
BEGIN
  r := rpc_import_jobs_cleanup_expired();
  IF (r ->> 'ok')::BOOLEAN <> TRUE THEN
    RAISE EXCEPTION 'T10 FAIL · r=%', r;
  END IF;
  IF (r ->> 'purged_count')::INT <> 0 THEN
    RAISE EXCEPTION 'T10 FAIL · esperava 0 purged · veio %', r;
  END IF;
  RAISE NOTICE 'PASS · T10 · cleanup com 0 jobs expirados';
END $$;

-- ============================================================================
-- T11 · Cleanup purga jobs archivados ha mais de 30 dias
-- ============================================================================

DO $$
DECLARE v_job UUID;
DECLARE r JSONB;
BEGIN
  v_job := current_setting('e5.job_id')::UUID;
  -- Marca o job como archived ha 40 dias
  UPDATE import_jobs
    SET archived_at = now() - INTERVAL '40 days'
    WHERE id = v_job;

  r := rpc_import_jobs_cleanup_expired();
  IF (r ->> 'purged_count')::INT <> 1 THEN
    RAISE EXCEPTION 'T11 FAIL · esperava 1 purged · veio %', r;
  END IF;
  -- Confere que job foi marcado
  IF (SELECT pdf_purged_at FROM import_jobs WHERE id = v_job) IS NULL THEN
    RAISE EXCEPTION 'T11 FAIL · pdf_purged_at nao foi setado';
  END IF;
  -- Confere que storage.objects foi limpo
  IF EXISTS (SELECT 1 FROM storage.objects WHERE bucket_id = 'import-pdfs' AND name LIKE '%' || v_job::TEXT || '%') THEN
    RAISE EXCEPTION 'T11 FAIL · storage.objects nao foi limpo';
  END IF;
  RAISE NOTICE 'PASS · T11 · cleanup purga jobs >30d e limpa storage';
END $$;

-- ============================================================================
-- T12 · Get URL em job purgado retorna pdf_purged
-- ============================================================================

SELECT test_login('e5aaaaaa-0000-0000-0000-000000000003');

DO $$
DECLARE r JSONB;
BEGIN
  r := rpc_import_jobs_get_pdf_url(current_setting('e5.job_id')::UUID);
  IF r ->> 'error' <> 'pdf_purged' THEN
    RAISE EXCEPTION 'T12 FAIL · esperava pdf_purged · veio %', r;
  END IF;
  IF r ->> 'purged_at' IS NULL THEN
    RAISE EXCEPTION 'T12 FAIL · purged_at ausente';
  END IF;
  RAISE NOTICE 'PASS · T12 · job purgado retorna pdf_purged com timestamp';
END $$;

-- ============================================================================
-- T13 · Cleanup nao purga jobs archivados ha <30 dias
-- ============================================================================

DO $$
DECLARE v_new_job UUID;
DECLARE v_token TEXT;
DECLARE r JSONB;
DECLARE v_path TEXT;
BEGIN
  -- Cria novo job, simula PDF, archive ha apenas 10 dias
  PERFORM test_login('e5aaaaaa-0000-0000-0000-000000000003');
  r := rpc_import_job_create(jsonb_build_object(
    'file_name', 'recente.pdf', 'file_size', '500', 'pages_total', '2'
  ));
  v_new_job := (r ->> 'id')::UUID;
  v_token := r ->> 'worker_token';
  v_path := import_pdf_storage_path('00000000-0000-0000-e500-000000000001', v_new_job);

  INSERT INTO storage.objects (bucket_id, name) VALUES ('import-pdfs', v_path);
  PERFORM rpc_import_worker_set_pdf_storage(v_new_job, v_token, v_path);
  UPDATE import_jobs SET archived_at = now() - INTERVAL '10 days' WHERE id = v_new_job;

  PERFORM test_login('e5aaaaaa-0000-0000-0000-000000000001');  -- SA
  r := rpc_import_jobs_cleanup_expired();

  IF (r ->> 'purged_count')::INT <> 0 THEN
    RAISE EXCEPTION 'T13 FAIL · job de 10 dias nao deveria ser purgado · r=%', r;
  END IF;
  RAISE NOTICE 'PASS · T13 · cleanup respeita janela de 30 dias';
END $$;

-- ============================================================================
-- T14 · View de stats
-- ============================================================================

DO $$
DECLARE v RECORD;
BEGIN
  SELECT * INTO v FROM import_pdfs_stats;
  -- Esperado: 1 em storage (o de T13), 1 apagado (o de T11)
  IF v.pdfs_em_storage <> 1 THEN
    RAISE EXCEPTION 'T14 FAIL · pdfs_em_storage esperava 1 · veio %', v.pdfs_em_storage;
  END IF;
  IF v.pdfs_apagados <> 1 THEN
    RAISE EXCEPTION 'T14 FAIL · pdfs_apagados esperava 1 · veio %', v.pdfs_apagados;
  END IF;
  RAISE NOTICE 'PASS · T14 · stats reflete em_storage=% apagados=%',
    v.pdfs_em_storage, v.pdfs_apagados;
END $$;

-- ============================================================================
-- T15 · Re-set storage path · idempotencia (worker reenvia o mesmo)
-- ============================================================================

DO $$
DECLARE v_new_job UUID;
DECLARE v_token TEXT;
DECLARE v_path TEXT;
DECLARE r JSONB;
BEGIN
  PERFORM test_login('e5aaaaaa-0000-0000-0000-000000000003');
  r := rpc_import_job_create(jsonb_build_object(
    'file_name', 'idempotente.pdf', 'file_size', '100', 'pages_total', '1'
  ));
  v_new_job := (r ->> 'id')::UUID;
  v_token := r ->> 'worker_token';
  v_path := import_pdf_storage_path('00000000-0000-0000-e500-000000000001', v_new_job);

  r := rpc_import_worker_set_pdf_storage(v_new_job, v_token, v_path);
  IF (r ->> 'ok')::BOOLEAN <> TRUE THEN
    RAISE EXCEPTION 'T15 FAIL · primeira chamada · r=%', r;
  END IF;

  -- Reenviar deve continuar dando ok (idempotente)
  r := rpc_import_worker_set_pdf_storage(v_new_job, v_token, v_path);
  IF (r ->> 'ok')::BOOLEAN <> TRUE THEN
    RAISE EXCEPTION 'T15 FAIL · segunda chamada · r=%', r;
  END IF;
  RAISE NOTICE 'PASS · T15 · set_pdf_storage idempotente';
END $$;

-- ============================================================================
-- T16 · Job inexistente
-- ============================================================================

DO $$
DECLARE r JSONB;
BEGIN
  r := rpc_import_worker_set_pdf_storage(
    '99999999-9999-9999-9999-999999999999',
    'qualquer-token',
    'fake/path'
  );
  IF r ->> 'error' <> 'job_not_found' THEN
    RAISE EXCEPTION 'T16 FAIL · esperava job_not_found · veio %', r;
  END IF;
  RAISE NOTICE 'PASS · T16 · job inexistente retorna job_not_found';
END $$;

-- ============================================================================
-- FECHAMENTO
-- ============================================================================

DO $$
BEGIN
  RAISE NOTICE '========================================';
  RAISE NOTICE '=== E5 · 16 testes executados · OK   ===';
  RAISE NOTICE '========================================';
END $$;

ROLLBACK;

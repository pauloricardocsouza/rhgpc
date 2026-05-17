-- ============================================================================
-- R2 People · Sessao E4 · RPCs de gestao de jobs de importacao
-- ============================================================================
-- Lado do app (RH revisa e aprova):
--   rpc_import_jobs_list      · lista jobs do tenant
--   rpc_import_jobs_get       · detalhe de um job
--   rpc_import_items_list     · lista items de um job (paginado, filtravel)
--   rpc_import_item_update    · RH edita o payload antes de aprovar
--   rpc_import_item_approve   · aprovacao individual · cria/linka employee
--   rpc_import_item_reject    · descarta com motivo
--   rpc_import_job_approve_all · aprova em batch (so items pending)
--   rpc_import_job_archive    · marca o job como concluido
--   rpc_import_job_create     · placeholder · worker chama via API, nao RPC
--
-- Lado do worker (sem auth de usuario, usa worker_token):
--   rpc_import_worker_update_job   · atualiza status/progresso
--   rpc_import_worker_push_items   · insere items em batch
-- ============================================================================

-- ============================================================================
-- LADO APP · listagem
-- ============================================================================

CREATE OR REPLACE FUNCTION rpc_import_jobs_list(
  p_status import_job_status DEFAULT NULL,
  p_limit  INT DEFAULT 20,
  p_offset INT DEFAULT 0
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user app_users;
  v_jobs JSONB;
  v_total INT;
BEGIN
  SELECT * INTO v_user FROM app_users WHERE id = current_user_id();
  IF v_user IS NULL THEN RETURN jsonb_build_object('error', 'not_authenticated'); END IF;
  IF NOT employees_can_read() THEN RETURN jsonb_build_object('error', 'permission_denied'); END IF;

  SELECT count(*) INTO v_total
  FROM import_jobs j
  WHERE (is_super_admin() OR j.tenant_id = v_user.tenant_id)
    AND (p_status IS NULL OR j.status = p_status);

  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'id', j.id,
    'tenant_id', j.tenant_id,
    'source_file_name', j.source_file_name,
    'source_file_size', j.source_file_size,
    'source_pages_total', j.source_pages_total,
    'status', j.status,
    'pages_processed', j.pages_processed,
    'pages_failed', j.pages_failed,
    'items_total', j.items_total,
    'items_approved', j.items_approved,
    'items_rejected', j.items_rejected,
    'items_duplicates', j.items_duplicates,
    'items_pending', (
      SELECT count(*) FROM import_job_items i
      WHERE i.job_id = j.id AND i.status = 'pending'
    ),
    'uploaded_by_name', (SELECT full_name FROM app_users WHERE id = j.uploaded_by),
    'created_at', j.created_at,
    'started_at', j.started_at,
    'completed_at', j.completed_at,
    'archived_at', j.archived_at
  ) ORDER BY j.created_at DESC), '[]'::JSONB)
  INTO v_jobs
  FROM import_jobs j
  WHERE (is_super_admin() OR j.tenant_id = v_user.tenant_id)
    AND (p_status IS NULL OR j.status = p_status)
  LIMIT p_limit OFFSET p_offset;

  RETURN jsonb_build_object(
    'ok', TRUE,
    'jobs', v_jobs,
    'total', v_total,
    'limit', p_limit,
    'offset', p_offset
  );
END;
$$;

-- ============================================================================
-- rpc_import_jobs_get
-- ============================================================================

CREATE OR REPLACE FUNCTION rpc_import_jobs_get(p_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user app_users;
  v_job JSONB;
BEGIN
  SELECT * INTO v_user FROM app_users WHERE id = current_user_id();
  IF v_user IS NULL THEN RETURN jsonb_build_object('error', 'not_authenticated'); END IF;
  IF NOT employees_can_read() THEN RETURN jsonb_build_object('error', 'permission_denied'); END IF;

  SELECT to_jsonb(j) || jsonb_build_object(
    'uploaded_by_name', (SELECT full_name FROM app_users WHERE id = j.uploaded_by),
    'items_pending', (SELECT count(*) FROM import_job_items WHERE job_id = j.id AND status = 'pending')
  )
  INTO v_job
  FROM import_jobs j
  WHERE j.id = p_id
    AND (is_super_admin() OR j.tenant_id = v_user.tenant_id);

  IF v_job IS NULL THEN
    RETURN jsonb_build_object('error', 'job_not_found');
  END IF;

  -- Remove worker_token do payload (nao deve trafegar para o frontend)
  v_job := v_job - 'worker_token';

  RETURN jsonb_build_object('ok', TRUE, 'job', v_job);
END;
$$;

-- ============================================================================
-- rpc_import_items_list · paginavel + filtravel por status
-- ============================================================================

CREATE OR REPLACE FUNCTION rpc_import_items_list(
  p_job_id UUID,
  p_status import_item_status DEFAULT NULL,
  p_limit  INT DEFAULT 50,
  p_offset INT DEFAULT 0
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user app_users;
  v_items JSONB;
  v_total INT;
  v_job import_jobs;
BEGIN
  SELECT * INTO v_user FROM app_users WHERE id = current_user_id();
  IF v_user IS NULL THEN RETURN jsonb_build_object('error', 'not_authenticated'); END IF;
  IF NOT employees_can_read() THEN RETURN jsonb_build_object('error', 'permission_denied'); END IF;

  SELECT * INTO v_job FROM import_jobs WHERE id = p_job_id;
  IF v_job IS NULL THEN RETURN jsonb_build_object('error', 'job_not_found'); END IF;
  IF v_job.tenant_id <> v_user.tenant_id AND NOT is_super_admin() THEN
    RETURN jsonb_build_object('error', 'job_not_found');
  END IF;

  SELECT count(*) INTO v_total
  FROM import_job_items i
  WHERE i.job_id = p_job_id
    AND (p_status IS NULL OR i.status = p_status);

  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'id', i.id,
    'job_id', i.job_id,
    'page_number', i.page_number,
    'status', i.status,
    'full_name', i.full_name,
    'cpf', i.cpf,
    'matricula_esocial', i.matricula_esocial,
    'job_title', i.job_title,
    'hire_date', i.hire_date,
    'termination_date', i.termination_date,
    'parser_alerts', i.parser_alerts,
    'confidence_score', i.confidence_score,
    'parsed_payload', i.parsed_payload,
    'approved_payload', i.approved_payload,
    'employee_id', i.employee_id,
    'duplicate_of', i.duplicate_of,
    'rejection_reason', i.rejection_reason,
    'approved_at', i.approved_at,
    'rejected_at', i.rejected_at,
    -- Detecta duplicata em tempo de leitura (CPF pode ter sido criado via outro fluxo)
    'duplicate_check', (
      SELECT jsonb_build_object('id', e.id, 'full_name', e.full_name)
      FROM employees e
      WHERE e.archived_at IS NULL
        AND e.tenant_id = i.tenant_id
        AND cpf_digits_only(e.cpf) = cpf_digits_only(i.cpf)
        AND cpf_digits_only(i.cpf) <> ''
      LIMIT 1
    )
  ) ORDER BY i.page_number), '[]'::JSONB)
  INTO v_items
  FROM import_job_items i
  WHERE i.job_id = p_job_id
    AND (p_status IS NULL OR i.status = p_status)
  LIMIT p_limit OFFSET p_offset;

  RETURN jsonb_build_object(
    'ok', TRUE,
    'items', v_items,
    'total', v_total,
    'limit', p_limit,
    'offset', p_offset
  );
END;
$$;

-- ============================================================================
-- rpc_import_item_update · RH edita campos do payload antes de aprovar
-- ============================================================================

CREATE OR REPLACE FUNCTION rpc_import_item_update(p_id UUID, p_patch JSONB)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user app_users;
  v_item import_job_items;
  v_new_payload JSONB;
BEGIN
  SELECT * INTO v_user FROM app_users WHERE id = current_user_id();
  IF v_user IS NULL THEN RETURN jsonb_build_object('error', 'not_authenticated'); END IF;
  IF NOT employees_can_write() THEN RETURN jsonb_build_object('error', 'permission_denied'); END IF;

  SELECT * INTO v_item FROM import_job_items WHERE id = p_id;
  IF v_item IS NULL THEN RETURN jsonb_build_object('error', 'item_not_found'); END IF;
  IF v_item.tenant_id <> v_user.tenant_id AND NOT is_super_admin() THEN
    RETURN jsonb_build_object('error', 'item_not_found');
  END IF;
  IF v_item.status NOT IN ('pending', 'edited') THEN
    RETURN jsonb_build_object('error', 'item_locked', 'status', v_item.status);
  END IF;

  -- Merge patch no payload existente
  v_new_payload := v_item.parsed_payload || p_patch;

  UPDATE import_job_items SET
    parsed_payload = v_new_payload,
    status = 'edited',
    -- Atualiza espelhos
    full_name = COALESCE(p_patch ->> 'full_name', full_name),
    cpf = COALESCE(p_patch ->> 'cpf', cpf),
    matricula_esocial = COALESCE(p_patch ->> 'matricula_esocial', matricula_esocial),
    job_title = COALESCE(p_patch ->> 'job_title', job_title),
    hire_date = COALESCE(NULLIF(p_patch ->> 'hire_date', '')::DATE, hire_date),
    termination_date = COALESCE(NULLIF(p_patch ->> 'termination_date', '')::DATE, termination_date)
  WHERE id = p_id;

  RETURN jsonb_build_object('ok', TRUE, 'id', p_id, 'status', 'edited');
END;
$$;

-- ============================================================================
-- rpc_import_item_approve · cria o employee ou linka como duplicata
-- ============================================================================

CREATE OR REPLACE FUNCTION rpc_import_item_approve(p_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user app_users;
  v_item import_job_items;
  v_existing UUID;
  v_create_result JSONB;
  v_new_id UUID;
  v_was_dup BOOLEAN := FALSE;
BEGIN
  SELECT * INTO v_user FROM app_users WHERE id = current_user_id();
  IF v_user IS NULL THEN RETURN jsonb_build_object('error', 'not_authenticated'); END IF;
  IF NOT employees_can_write() THEN RETURN jsonb_build_object('error', 'permission_denied'); END IF;

  SELECT * INTO v_item FROM import_job_items WHERE id = p_id;
  IF v_item IS NULL THEN RETURN jsonb_build_object('error', 'item_not_found'); END IF;
  IF v_item.tenant_id <> v_user.tenant_id AND NOT is_super_admin() THEN
    RETURN jsonb_build_object('error', 'item_not_found');
  END IF;
  IF v_item.status NOT IN ('pending', 'edited') THEN
    RETURN jsonb_build_object('error', 'item_already_decided', 'status', v_item.status);
  END IF;

  -- Cria/idempotenciza employee via RPC existente
  v_create_result := rpc_employees_create(
    v_item.parsed_payload || jsonb_build_object('source', 'pdf_ocr')
  );

  IF v_create_result ? 'error' THEN
    RETURN jsonb_build_object('error', 'create_failed', 'detail', v_create_result);
  END IF;

  v_new_id := (v_create_result ->> 'id')::UUID;
  v_was_dup := COALESCE((v_create_result ->> 'already_exists')::BOOLEAN, FALSE);

  -- Marca o item como aprovado/duplicata
  UPDATE import_job_items SET
    status = CASE WHEN v_was_dup THEN 'duplicate'::import_item_status
                  ELSE 'approved'::import_item_status END,
    approved_at = now(),
    approved_by = v_user.id,
    approved_payload = v_item.parsed_payload,
    employee_id = CASE WHEN NOT v_was_dup THEN v_new_id ELSE NULL END,
    duplicate_of = CASE WHEN v_was_dup THEN v_new_id ELSE NULL END
  WHERE id = p_id;

  -- Atualiza contadores no job
  UPDATE import_jobs SET
    items_approved   = items_approved   + CASE WHEN NOT v_was_dup THEN 1 ELSE 0 END,
    items_duplicates = items_duplicates + CASE WHEN v_was_dup THEN 1 ELSE 0 END
  WHERE id = v_item.job_id;

  RETURN jsonb_build_object(
    'ok', TRUE,
    'id', p_id,
    'employee_id', v_new_id,
    'duplicate', v_was_dup
  );
END;
$$;

-- ============================================================================
-- rpc_import_item_reject
-- ============================================================================

CREATE OR REPLACE FUNCTION rpc_import_item_reject(p_id UUID, p_reason TEXT DEFAULT NULL)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user app_users;
  v_item import_job_items;
BEGIN
  SELECT * INTO v_user FROM app_users WHERE id = current_user_id();
  IF v_user IS NULL THEN RETURN jsonb_build_object('error', 'not_authenticated'); END IF;
  IF NOT employees_can_write() THEN RETURN jsonb_build_object('error', 'permission_denied'); END IF;

  SELECT * INTO v_item FROM import_job_items WHERE id = p_id;
  IF v_item IS NULL THEN RETURN jsonb_build_object('error', 'item_not_found'); END IF;
  IF v_item.tenant_id <> v_user.tenant_id AND NOT is_super_admin() THEN
    RETURN jsonb_build_object('error', 'item_not_found');
  END IF;
  IF v_item.status NOT IN ('pending', 'edited') THEN
    RETURN jsonb_build_object('error', 'item_already_decided', 'status', v_item.status);
  END IF;

  UPDATE import_job_items SET
    status = 'rejected',
    rejected_at = now(),
    rejected_by = v_user.id,
    rejection_reason = p_reason
  WHERE id = p_id;

  UPDATE import_jobs SET items_rejected = items_rejected + 1
  WHERE id = v_item.job_id;

  RETURN jsonb_build_object('ok', TRUE, 'id', p_id);
END;
$$;

-- ============================================================================
-- rpc_import_job_approve_all · aprova todos os items pending/edited do job
-- ============================================================================

CREATE OR REPLACE FUNCTION rpc_import_job_approve_all(p_job_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user app_users;
  v_job import_jobs;
  v_item_id UUID;
  v_result JSONB;
  v_approved INT := 0;
  v_duplicates INT := 0;
  v_errors INT := 0;
BEGIN
  SELECT * INTO v_user FROM app_users WHERE id = current_user_id();
  IF v_user IS NULL THEN RETURN jsonb_build_object('error', 'not_authenticated'); END IF;
  IF NOT employees_can_write() THEN RETURN jsonb_build_object('error', 'permission_denied'); END IF;

  SELECT * INTO v_job FROM import_jobs WHERE id = p_job_id;
  IF v_job IS NULL THEN RETURN jsonb_build_object('error', 'job_not_found'); END IF;
  IF v_job.tenant_id <> v_user.tenant_id AND NOT is_super_admin() THEN
    RETURN jsonb_build_object('error', 'job_not_found');
  END IF;

  FOR v_item_id IN
    SELECT id FROM import_job_items
    WHERE job_id = p_job_id AND status IN ('pending', 'edited')
    ORDER BY page_number
  LOOP
    BEGIN
      v_result := rpc_import_item_approve(v_item_id);
      IF (v_result ->> 'ok')::BOOLEAN THEN
        IF (v_result ->> 'duplicate')::BOOLEAN THEN
          v_duplicates := v_duplicates + 1;
        ELSE
          v_approved := v_approved + 1;
        END IF;
      ELSE
        v_errors := v_errors + 1;
      END IF;
    EXCEPTION WHEN OTHERS THEN
      v_errors := v_errors + 1;
    END;
  END LOOP;

  RETURN jsonb_build_object(
    'ok', TRUE,
    'approved', v_approved,
    'duplicates', v_duplicates,
    'errors', v_errors
  );
END;
$$;

-- ============================================================================
-- rpc_import_job_archive · marca job como concluido (apos revisao)
-- ============================================================================

CREATE OR REPLACE FUNCTION rpc_import_job_archive(p_id UUID)
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
  IF NOT employees_can_write() THEN RETURN jsonb_build_object('error', 'permission_denied'); END IF;

  SELECT * INTO v_job FROM import_jobs WHERE id = p_id;
  IF v_job IS NULL THEN RETURN jsonb_build_object('error', 'job_not_found'); END IF;
  IF v_job.tenant_id <> v_user.tenant_id AND NOT is_super_admin() THEN
    RETURN jsonb_build_object('error', 'job_not_found');
  END IF;

  UPDATE import_jobs SET
    status = 'archived',
    archived_at = now()
  WHERE id = p_id;

  RETURN jsonb_build_object('ok', TRUE, 'id', p_id);
END;
$$;

-- ============================================================================
-- rpc_import_job_create · usado por app + worker
-- Retorna o worker_token usado pelo worker para reportar progresso
-- ============================================================================

CREATE OR REPLACE FUNCTION rpc_import_job_create(p_payload JSONB)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user app_users;
  v_id UUID;
  v_token TEXT;
BEGIN
  SELECT * INTO v_user FROM app_users WHERE id = current_user_id();
  IF v_user IS NULL THEN RETURN jsonb_build_object('error', 'not_authenticated'); END IF;
  IF NOT employees_can_write() THEN RETURN jsonb_build_object('error', 'permission_denied'); END IF;

  INSERT INTO import_jobs (
    tenant_id, uploaded_by,
    source_file_name, source_file_size, source_pages_total,
    status
  ) VALUES (
    v_user.tenant_id, v_user.id,
    p_payload ->> 'file_name',
    NULLIF(p_payload ->> 'file_size', '')::BIGINT,
    NULLIF(p_payload ->> 'pages_total', '')::INT,
    'pending'
  ) RETURNING id, worker_token INTO v_id, v_token;

  RETURN jsonb_build_object(
    'ok', TRUE,
    'id', v_id,
    'worker_token', v_token
  );
END;
$$;

-- ============================================================================
-- LADO WORKER · atualizacao de progresso (sem auth de usuario)
-- Cada chamada valida (job_id, worker_token).
-- ============================================================================

CREATE OR REPLACE FUNCTION rpc_import_worker_update_job(
  p_job_id UUID,
  p_worker_token TEXT,
  p_patch JSONB
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_job import_jobs;
  v_new_status import_job_status;
BEGIN
  SELECT * INTO v_job FROM import_jobs WHERE id = p_job_id;
  IF v_job IS NULL THEN RETURN jsonb_build_object('error', 'job_not_found'); END IF;
  IF v_job.worker_token <> p_worker_token THEN
    RETURN jsonb_build_object('error', 'invalid_worker_token');
  END IF;

  v_new_status := COALESCE(
    (p_patch ->> 'status')::import_job_status,
    v_job.status
  );

  UPDATE import_jobs SET
    status = v_new_status,
    pages_processed   = COALESCE((p_patch ->> 'pages_processed')::INT, pages_processed),
    pages_failed      = COALESCE((p_patch ->> 'pages_failed')::INT, pages_failed),
    source_pages_total = COALESCE((p_patch ->> 'pages_total')::INT, source_pages_total),
    error_log         = COALESCE(p_patch -> 'error_log', error_log),
    started_at        = CASE WHEN v_new_status = 'running'   AND started_at   IS NULL THEN now() ELSE started_at END,
    completed_at      = CASE WHEN v_new_status IN ('completed', 'failed') AND completed_at IS NULL THEN now() ELSE completed_at END
  WHERE id = p_job_id;

  RETURN jsonb_build_object('ok', TRUE, 'id', p_job_id);
END;
$$;

-- ============================================================================
-- rpc_import_worker_push_items
-- Recebe array de items extraidos e os insere em import_job_items.
-- ============================================================================

CREATE OR REPLACE FUNCTION rpc_import_worker_push_items(
  p_job_id UUID,
  p_worker_token TEXT,
  p_items JSONB
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_job import_jobs;
  v_item JSONB;
  v_inserted INT := 0;
BEGIN
  SELECT * INTO v_job FROM import_jobs WHERE id = p_job_id;
  IF v_job IS NULL THEN RETURN jsonb_build_object('error', 'job_not_found'); END IF;
  IF v_job.worker_token <> p_worker_token THEN
    RETURN jsonb_build_object('error', 'invalid_worker_token');
  END IF;

  IF jsonb_typeof(p_items) <> 'array' THEN
    RETURN jsonb_build_object('error', 'expected_array');
  END IF;

  FOR v_item IN SELECT * FROM jsonb_array_elements(p_items)
  LOOP
    INSERT INTO import_job_items (
      job_id, tenant_id, page_number, status,
      parsed_payload, full_name, cpf, matricula_esocial, job_title,
      hire_date, termination_date, parser_alerts, confidence_score
    ) VALUES (
      p_job_id, v_job.tenant_id,
      COALESCE((v_item ->> 'page_number')::INT, 1),
      'pending',
      v_item -> 'payload',
      v_item -> 'payload' ->> 'full_name',
      v_item -> 'payload' ->> 'cpf',
      v_item -> 'payload' ->> 'matricula_esocial',
      v_item -> 'payload' ->> 'job_title',
      NULLIF(v_item -> 'payload' ->> 'hire_date', '')::DATE,
      NULLIF(v_item -> 'payload' ->> 'termination_date', '')::DATE,
      COALESCE(v_item -> 'alerts', '[]'::JSONB),
      NULLIF(v_item ->> 'confidence', '')::SMALLINT
    );
    v_inserted := v_inserted + 1;
  END LOOP;

  -- Atualiza contador
  UPDATE import_jobs SET items_total = items_total + v_inserted
  WHERE id = p_job_id;

  RETURN jsonb_build_object('ok', TRUE, 'inserted', v_inserted);
END;
$$;

-- ============================================================================
-- GRANTS
-- ============================================================================

GRANT EXECUTE ON FUNCTION
  rpc_import_jobs_list,
  rpc_import_jobs_get,
  rpc_import_items_list,
  rpc_import_item_update,
  rpc_import_item_approve,
  rpc_import_item_reject,
  rpc_import_job_approve_all,
  rpc_import_job_archive,
  rpc_import_job_create,
  rpc_import_worker_update_job,
  rpc_import_worker_push_items
TO authenticated;

-- O worker chama via PostgREST anon · precisa de grant separado.
-- Na configuracao real de producao, criar role `worker_role` com permissoes minimas
-- e dar GRANT EXECUTE so dessas duas RPCs. Por enquanto, GRANT para anon (escopado
-- por worker_token nas proprias RPCs).
GRANT EXECUTE ON FUNCTION
  rpc_import_worker_update_job,
  rpc_import_worker_push_items
TO anon;

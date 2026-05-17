-- ============================================================================
-- R2 People · Testes Sessao E4 · Import Jobs
-- ============================================================================
-- 20 testes cobrindo:
--   - Criar job (RH) + worker token unico
--   - Worker push items (sem auth user, com token)
--   - Worker update job (status running -> completed)
--   - Token invalido bloqueia worker
--   - Listar jobs (paginado, filtravel)
--   - Listar items (com duplicate_check)
--   - Editar item (RH altera payload antes de aprovar)
--   - Aprovar item -> cria employee
--   - Aprovar item com CPF ja cadastrado -> marca como duplicate
--   - Rejeitar item com motivo
--   - Approve_all em batch
--   - Archive job
--   - Cross-tenant isolation
--   - Permissoes
-- ============================================================================

BEGIN;

-- ============================================================================
-- SETUP
-- ============================================================================

INSERT INTO tenants (id, slug, legal_name, display_name) VALUES
  ('33333333-0000-0000-0000-000000000001', 'tx', 'Tenant X', 'X'),
  ('33333333-0000-0000-0000-000000000002', 'ty', 'Tenant Y', 'Y');

INSERT INTO app_users (id, tenant_id, auth_user_id, email, full_name, role, employment_link, hired_at) VALUES
  ('44444444-0000-0000-0000-000000000003', '33333333-0000-0000-0000-000000000001',
   '55555555-0000-0000-0000-000000000003', 'rh@x.test', 'RH-X', 'rh', 'clt', '2020-01-01'),
  ('44444444-0000-0000-0000-000000000004', '33333333-0000-0000-0000-000000000001',
   '55555555-0000-0000-0000-000000000004', 'col@x.test', 'COL-X', 'colaborador', 'clt', '2020-01-01'),
  ('44444444-0000-0000-0000-000000000006', '33333333-0000-0000-0000-000000000002',
   '55555555-0000-0000-0000-000000000006', 'rh@y.test', 'RH-Y', 'rh', 'clt', '2020-01-01');

-- ============================================================================
-- T01-T02 · RH cria job · worker_token retornado
-- ============================================================================

SELECT test_login('55555555-0000-0000-0000-000000000003');

DO $$
DECLARE r JSONB;
BEGIN
  r := rpc_import_job_create(jsonb_build_object(
    'file_name', 'Ficha_de_Empregado_reduzido.pdf',
    'file_size', 3858881,
    'pages_total', 16
  ));
  IF (r ->> 'ok')::BOOLEAN <> TRUE THEN
    RAISE EXCEPTION 'T01 FAIL · r=%', r;
  END IF;
  IF (r ->> 'worker_token') IS NULL OR length(r ->> 'worker_token') < 30 THEN
    RAISE EXCEPTION 'T01 FAIL · token invalido · r=%', r;
  END IF;
  PERFORM set_config('e4.job_id', r ->> 'id', FALSE);
  PERFORM set_config('e4.worker_token', r ->> 'worker_token', FALSE);
  RAISE NOTICE 'PASS · T01 · RH cria job e recebe worker_token';
END $$;

-- T02 · colaborador NAO pode criar
SELECT test_login('55555555-0000-0000-0000-000000000004');
DO $$
DECLARE r JSONB;
BEGIN
  r := rpc_import_job_create(jsonb_build_object('file_name', 'x.pdf'));
  IF r ->> 'error' <> 'permission_denied' THEN
    RAISE EXCEPTION 'T02 FAIL · esperava permission_denied · veio %', r;
  END IF;
  RAISE NOTICE 'PASS · T02 · colaborador NAO pode criar job';
END $$;

-- ============================================================================
-- T03-T05 · Worker push items + update status
-- Esses RPCs sao SECURITY DEFINER e validam por token, nao por auth user.
-- Para os testes, deslogamos para simular "qualquer chamador".
-- ============================================================================

SELECT test_logout();

DO $$
DECLARE r JSONB;
DECLARE v_token TEXT;
BEGIN
  v_token := current_setting('e4.worker_token');

  -- T03 · worker informa que comecou
  r := rpc_import_worker_update_job(
    current_setting('e4.job_id')::UUID,
    v_token,
    jsonb_build_object('status', 'running', 'pages_processed', 4)
  );
  IF (r ->> 'ok')::BOOLEAN <> TRUE THEN
    RAISE EXCEPTION 'T03 FAIL · r=%', r;
  END IF;
  RAISE NOTICE 'PASS · T03 · worker atualiza job para running';

  -- T04 · token invalido bloqueia
  r := rpc_import_worker_update_job(
    current_setting('e4.job_id')::UUID,
    'token_falso_xxx',
    jsonb_build_object('status', 'completed')
  );
  IF r ->> 'error' <> 'invalid_worker_token' THEN
    RAISE EXCEPTION 'T04 FAIL · esperava invalid_worker_token · veio %', r;
  END IF;
  RAISE NOTICE 'PASS · T04 · token invalido bloqueia worker';

  -- T05 · push de 3 items
  r := rpc_import_worker_push_items(
    current_setting('e4.job_id')::UUID,
    v_token,
    jsonb_build_array(
      jsonb_build_object(
        'page_number', 1,
        'confidence', 95,
        'alerts', jsonb_build_array(),
        'payload', jsonb_build_object(
          'full_name', 'CARLOS ALBERTO IDALAN FERREIRA',
          'cpf', '921.753.765-91',
          'hire_date', '2019-10-10',
          'job_title', 'REPOSITOR',
          'matricula_esocial', '195'
        )
      ),
      jsonb_build_object(
        'page_number', 2,
        'confidence', 90,
        'alerts', jsonb_build_array(),
        'payload', jsonb_build_object(
          'full_name', 'CARLOS ANTONIO BARRETO ALMEIDA',
          'cpf', '826.795.175-04',
          'hire_date', '2017-11-16',
          'job_title', 'CONFERENTE',
          'matricula_esocial', '1010'
        )
      ),
      jsonb_build_object(
        'page_number', 8,
        'confidence', 75,
        'alerts', jsonb_build_array('rg_vazio'),
        'payload', jsonb_build_object(
          'full_name', 'CLEONICE CAMILO FERREIRA',
          'cpf', '044.278.795-27',
          'hire_date', '2025-12-22',
          'job_title', 'OPERADOR DE CAIXA'
        )
      )
    )
  );
  IF (r ->> 'inserted')::INT <> 3 THEN
    RAISE EXCEPTION 'T05 FAIL · esperava 3 inserted · veio %', r;
  END IF;
  RAISE NOTICE 'PASS · T05 · worker push 3 items';
END $$;

-- ============================================================================
-- T06 · Worker marca job como completed
-- ============================================================================

DO $$
DECLARE r JSONB;
BEGIN
  r := rpc_import_worker_update_job(
    current_setting('e4.job_id')::UUID,
    current_setting('e4.worker_token'),
    jsonb_build_object('status', 'completed', 'pages_processed', 16)
  );
  IF (r ->> 'ok')::BOOLEAN <> TRUE THEN
    RAISE EXCEPTION 'T06 FAIL · r=%', r;
  END IF;
  RAISE NOTICE 'PASS · T06 · worker marca job como completed';
END $$;

-- ============================================================================
-- T07-T09 · RH lista jobs e items
-- ============================================================================

SELECT test_login('55555555-0000-0000-0000-000000000003');  -- RH-X

DO $$
DECLARE r JSONB;
BEGIN
  r := rpc_import_jobs_list();
  IF (r ->> 'total')::INT <> 1 THEN
    RAISE EXCEPTION 'T07 FAIL · esperava 1 job · veio %', r ->> 'total';
  END IF;
  -- O job retornado NAO deve conter worker_token
  IF (r -> 'jobs' -> 0) ? 'worker_token' THEN
    RAISE EXCEPTION 'T07 FAIL · worker_token vazou na listagem';
  END IF;
  RAISE NOTICE 'PASS · T07 · RH lista jobs sem worker_token';

  -- T08 · get
  r := rpc_import_jobs_get(current_setting('e4.job_id')::UUID);
  IF (r ->> 'ok')::BOOLEAN <> TRUE THEN
    RAISE EXCEPTION 'T08 FAIL · r=%', r;
  END IF;
  IF (r -> 'job') ? 'worker_token' THEN
    RAISE EXCEPTION 'T08 FAIL · worker_token vazou no get';
  END IF;
  IF (r -> 'job' ->> 'items_total')::INT <> 3 THEN
    RAISE EXCEPTION 'T08 FAIL · items_total esperava 3 · veio %', r -> 'job' ->> 'items_total';
  END IF;
  RAISE NOTICE 'PASS · T08 · get retorna job sem worker_token';

  -- T09 · lista items
  r := rpc_import_items_list(current_setting('e4.job_id')::UUID);
  IF (r ->> 'total')::INT <> 3 THEN
    RAISE EXCEPTION 'T09 FAIL · esperava 3 items · veio %', r ->> 'total';
  END IF;
  RAISE NOTICE 'PASS · T09 · RH lista 3 items do job';
END $$;

-- ============================================================================
-- T10-T11 · Edit item (RH ajusta CPF antes de aprovar)
-- ============================================================================

DO $$
DECLARE r JSONB;
DECLARE v_item_id UUID;
BEGIN
  -- Pega o item da pagina 8 (CLEONICE) que tinha rg_vazio
  SELECT id INTO v_item_id
  FROM import_job_items
  WHERE job_id = current_setting('e4.job_id')::UUID
    AND page_number = 8;

  PERFORM set_config('e4.item_id_cleonice', v_item_id::TEXT, FALSE);

  -- Edita: adiciona RG que estava faltando
  r := rpc_import_item_update(v_item_id, jsonb_build_object(
    'rg', '12345678',
    'rg_issuer', 'SSP/BA'
  ));
  IF (r ->> 'ok')::BOOLEAN <> TRUE THEN
    RAISE EXCEPTION 'T10 FAIL · r=%', r;
  END IF;
  IF r ->> 'status' <> 'edited' THEN
    RAISE EXCEPTION 'T10 FAIL · status esperava edited · veio %', r;
  END IF;
  RAISE NOTICE 'PASS · T10 · RH edita item e status vira edited';

  -- T11 · verifica que o payload foi merged
  IF (SELECT parsed_payload -> 'rg' FROM import_job_items WHERE id = v_item_id) <> '"12345678"'::JSONB THEN
    RAISE EXCEPTION 'T11 FAIL · rg nao foi salvo no payload';
  END IF;
  RAISE NOTICE 'PASS · T11 · patch e merged no parsed_payload';
END $$;

-- ============================================================================
-- T12-T14 · Aprovar item (cria employee)
-- ============================================================================

DO $$
DECLARE r JSONB;
DECLARE v_item_id UUID;
DECLARE v_new_emp UUID;
BEGIN
  -- Pega o item da pagina 1 (CARLOS ALBERTO)
  SELECT id INTO v_item_id
  FROM import_job_items
  WHERE job_id = current_setting('e4.job_id')::UUID
    AND page_number = 1;

  r := rpc_import_item_approve(v_item_id);
  IF (r ->> 'ok')::BOOLEAN <> TRUE THEN
    RAISE EXCEPTION 'T12 FAIL · r=%', r;
  END IF;
  v_new_emp := (r ->> 'employee_id')::UUID;
  IF v_new_emp IS NULL THEN
    RAISE EXCEPTION 'T12 FAIL · employee_id nao retornado · r=%', r;
  END IF;
  IF (r ->> 'duplicate')::BOOLEAN <> FALSE THEN
    RAISE EXCEPTION 'T12 FAIL · esperava duplicate=false';
  END IF;
  RAISE NOTICE 'PASS · T12 · approve cria employee';

  -- T13 · employee realmente existe
  IF NOT EXISTS (SELECT 1 FROM employees WHERE id = v_new_emp AND full_name = 'CARLOS ALBERTO IDALAN FERREIRA') THEN
    RAISE EXCEPTION 'T13 FAIL · employee nao foi criado';
  END IF;
  RAISE NOTICE 'PASS · T13 · employee inserido em `employees`';

  -- T14 · item ficou com status approved e employee_id setado
  IF (SELECT status FROM import_job_items WHERE id = v_item_id) <> 'approved' THEN
    RAISE EXCEPTION 'T14 FAIL · status nao virou approved';
  END IF;
  IF (SELECT employee_id FROM import_job_items WHERE id = v_item_id) <> v_new_emp THEN
    RAISE EXCEPTION 'T14 FAIL · employee_id nao linkou';
  END IF;
  RAISE NOTICE 'PASS · T14 · item linkado ao employee criado';
END $$;

-- ============================================================================
-- T15 · Aprovar item cujo CPF ja existe -> marca como duplicate
-- ============================================================================

DO $$
DECLARE r JSONB;
DECLARE v_item_id UUID;
BEGIN
  -- Pega item pagina 2 (CARLOS ANTONIO)
  SELECT id INTO v_item_id
  FROM import_job_items
  WHERE job_id = current_setting('e4.job_id')::UUID AND page_number = 2;

  -- Cria primeiro um employee manualmente com o mesmo CPF
  INSERT INTO employees (tenant_id, full_name, hire_date, job_title, cpf)
  VALUES (
    '33333333-0000-0000-0000-000000000001'::UUID,
    'CARLOS ANTONIO (cadastrado antes)',
    '2017-11-16'::DATE,
    'CONFERENTE',
    '826.795.175-04'
  );

  -- Agora aprova o item · deve voltar como duplicate
  r := rpc_import_item_approve(v_item_id);
  IF (r ->> 'duplicate')::BOOLEAN <> TRUE THEN
    RAISE EXCEPTION 'T15 FAIL · esperava duplicate=true · veio %', r;
  END IF;
  IF (SELECT status FROM import_job_items WHERE id = v_item_id) <> 'duplicate' THEN
    RAISE EXCEPTION 'T15 FAIL · status nao virou duplicate';
  END IF;
  IF (SELECT duplicate_of FROM import_job_items WHERE id = v_item_id) IS NULL THEN
    RAISE EXCEPTION 'T15 FAIL · duplicate_of nao setado';
  END IF;
  RAISE NOTICE 'PASS · T15 · CPF existente vira duplicate com link';
END $$;

-- ============================================================================
-- T16 · Rejeitar item
-- ============================================================================

DO $$
DECLARE r JSONB;
DECLARE v_item_id UUID;
BEGIN
  v_item_id := current_setting('e4.item_id_cleonice')::UUID;
  r := rpc_import_item_reject(v_item_id, 'duplicidade conhecida');
  IF (r ->> 'ok')::BOOLEAN <> TRUE THEN
    RAISE EXCEPTION 'T16 FAIL · r=%', r;
  END IF;
  IF (SELECT status FROM import_job_items WHERE id = v_item_id) <> 'rejected' THEN
    RAISE EXCEPTION 'T16 FAIL · status nao virou rejected';
  END IF;
  IF (SELECT rejection_reason FROM import_job_items WHERE id = v_item_id) <> 'duplicidade conhecida' THEN
    RAISE EXCEPTION 'T16 FAIL · motivo nao salvo';
  END IF;
  RAISE NOTICE 'PASS · T16 · reject com motivo registrado';
END $$;

-- ============================================================================
-- T17 · Item ja decidido nao pode ser aprovado/editado de novo
-- ============================================================================

DO $$
DECLARE r JSONB;
DECLARE v_item_id UUID;
BEGIN
  v_item_id := current_setting('e4.item_id_cleonice')::UUID;
  r := rpc_import_item_approve(v_item_id);
  IF r ->> 'error' NOT IN ('item_already_decided', 'item_locked') THEN
    RAISE EXCEPTION 'T17 FAIL · esperava bloqueio · veio %', r;
  END IF;
  RAISE NOTICE 'PASS · T17 · item rejected nao pode ser aprovado depois';
END $$;

-- ============================================================================
-- T18 · approve_all (deve ser noop, todos ja decididos)
-- ============================================================================

-- Cria mais 2 items pendentes para testar
SELECT test_logout();
DO $$
DECLARE r JSONB;
BEGIN
  r := rpc_import_worker_push_items(
    current_setting('e4.job_id')::UUID,
    current_setting('e4.worker_token'),
    jsonb_build_array(
      jsonb_build_object(
        'page_number', 3,
        'confidence', 80,
        'payload', jsonb_build_object(
          'full_name', 'BATCH 1', 'cpf', '100.100.100-00',
          'hire_date', '2024-01-01', 'job_title', 'Op'
        )
      ),
      jsonb_build_object(
        'page_number', 4,
        'confidence', 80,
        'payload', jsonb_build_object(
          'full_name', 'BATCH 2', 'cpf', '200.200.200-00',
          'hire_date', '2024-01-01', 'job_title', 'Op'
        )
      )
    )
  );
END $$;

SELECT test_login('55555555-0000-0000-0000-000000000003');

DO $$
DECLARE r JSONB;
BEGIN
  r := rpc_import_job_approve_all(current_setting('e4.job_id')::UUID);
  IF (r ->> 'ok')::BOOLEAN <> TRUE THEN
    RAISE EXCEPTION 'T18 FAIL · r=%', r;
  END IF;
  IF (r ->> 'approved')::INT <> 2 THEN
    RAISE EXCEPTION 'T18 FAIL · esperava 2 approved · veio %', r;
  END IF;
  RAISE NOTICE 'PASS · T18 · approve_all aprovou 2 batch items';
END $$;

-- ============================================================================
-- T19 · Cross-tenant · RH-Y nao ve jobs de X
-- ============================================================================

SELECT test_login('55555555-0000-0000-0000-000000000006');  -- RH-Y

DO $$
DECLARE r JSONB;
BEGIN
  r := rpc_import_jobs_list();
  IF (r ->> 'total')::INT <> 0 THEN
    RAISE EXCEPTION 'T19 FAIL · cross-tenant · esperava 0 · veio %', r ->> 'total';
  END IF;

  r := rpc_import_jobs_get(current_setting('e4.job_id')::UUID);
  IF r ->> 'error' <> 'job_not_found' THEN
    RAISE EXCEPTION 'T19 FAIL · esperava job_not_found · veio %', r;
  END IF;
  RAISE NOTICE 'PASS · T19 · cross-tenant bloqueado';
END $$;

-- ============================================================================
-- T20 · Archive job
-- ============================================================================

SELECT test_login('55555555-0000-0000-0000-000000000003');  -- RH-X

DO $$
DECLARE r JSONB;
BEGIN
  r := rpc_import_job_archive(current_setting('e4.job_id')::UUID);
  IF (r ->> 'ok')::BOOLEAN <> TRUE THEN
    RAISE EXCEPTION 'T20 FAIL · r=%', r;
  END IF;
  IF (SELECT status FROM import_jobs WHERE id = current_setting('e4.job_id')::UUID) <> 'archived' THEN
    RAISE EXCEPTION 'T20 FAIL · status nao virou archived';
  END IF;
  RAISE NOTICE 'PASS · T20 · archive marca job como archived';
END $$;

DO $$
BEGIN
  RAISE NOTICE '========================================';
  RAISE NOTICE '=== E4 · 20 testes executados · OK   ===';
  RAISE NOTICE '========================================';
END $$;

ROLLBACK;

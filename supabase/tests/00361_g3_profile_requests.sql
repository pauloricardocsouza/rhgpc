-- ============================================================================
-- R2 People · Testes Sessao G3 · profile change requests
-- ============================================================================
-- 18 testes:
--   T01-T03  · create: not_authenticated / employee_not_linked / validations
--   T04-T05  · create: photo + cria com sucesso
--   T06      · create: pending_request_exists (dois para mesmo campo)
--   T07      · list (do proprio)
--   T08      · cancel: dono pode, e bloqueia recriacao por uq
--   T09      · cancel: nao pode cancelar approved
--   T10-T11  · pending_list (permissao + retorno)
--   T12-T14  · approve: aplica em employees (3 campos diferentes)
--   T15      · approve: emergency_contact (composto)
--   T16      · approve: photo · move pending_photo_path para employees
--   T17      · reject: razao obrigatoria + grava motivo
--   T18      · cross-tenant bloqueado
-- ============================================================================

BEGIN;

INSERT INTO tenants (id, slug, legal_name, display_name) VALUES
  ('93aaaaaa-0000-0000-0000-000000000001', 'tx-g3', 'Tenant X G3', 'X'),
  ('93aaaaaa-0000-0000-0000-000000000002', 'tx-g3-y', 'Tenant Y G3', 'Y');

INSERT INTO app_users (id, tenant_id, auth_user_id, email, full_name, role, manager_id,
                       employment_link, hired_at) VALUES
  ('93aaaaaa-0003-0000-0000-000000000003', '93aaaaaa-0000-0000-0000-000000000001',
   '93aaaaaa-aaa1-0000-0000-000000000003', 'rh@g3.test', 'RH G3', 'rh', NULL,
   'clt', '2020-01-01'),
  ('93aaaaaa-0003-0000-0000-000000000011', '93aaaaaa-0000-0000-0000-000000000001',
   '93aaaaaa-aaa1-0000-0000-000000000011', 'eu@g3.test', 'EU G3', 'colaborador', NULL,
   'clt', '2022-01-01'),
  -- Colaborador sem ficha vinculada
  ('93aaaaaa-0003-0000-0000-000000000012', '93aaaaaa-0000-0000-0000-000000000001',
   '93aaaaaa-aaa1-0000-0000-000000000012', 'sem@g3.test', 'SEM FICHA G3', 'colaborador', NULL,
   'clt', '2022-01-01'),
  -- RH do tenant Y
  ('93aaaaaa-0003-0000-0000-000000000088', '93aaaaaa-0000-0000-0000-000000000002',
   '93aaaaaa-aaa1-0000-0000-000000000088', 'rhy@g3.test', 'RH Y G3', 'rh', NULL,
   'clt', '2020-01-01');

INSERT INTO employees (id, tenant_id, full_name, job_title, hire_date, cpf,
                       phone_mobile, personal_email, residence_address, created_by) VALUES
  ('93aaaaaa-0004-0000-0000-000000000011', '93aaaaaa-0000-0000-0000-000000000001',
   'EU G3 FICHA', 'Operador', '2022-01-01', '90111111111',
   '71988887777', 'antigo@gmail.com', 'Rua A, 100',
   '93aaaaaa-0003-0000-0000-000000000003');

UPDATE app_users SET employee_id='93aaaaaa-0004-0000-0000-000000000011'
  WHERE id='93aaaaaa-0003-0000-0000-000000000011';

-- ============================================================================
-- T01 · not_authenticated
-- ============================================================================
DO $$ DECLARE r JSONB;
BEGIN
  PERFORM set_config('request.jwt.claim.sub', 'ffffffff-0000-0000-0000-000000000000', TRUE);
  r := rpc_my_profile_request_create('phone_mobile', '{"value":"71999998888"}'::JSONB);
  IF r ->> 'error' <> 'not_authenticated' THEN RAISE EXCEPTION 'T01 FAIL · %', r; END IF;
  RAISE NOTICE 'PASS · T01 · not_authenticated';
END $$;

-- ============================================================================
-- T02 · employee_not_linked
-- ============================================================================
SELECT test_login('93aaaaaa-aaa1-0000-0000-000000000012');
DO $$ DECLARE r JSONB;
BEGIN
  r := rpc_my_profile_request_create('phone_mobile', '{"value":"71999998888"}'::JSONB);
  IF r ->> 'error' <> 'employee_not_linked' THEN RAISE EXCEPTION 'T02 FAIL · %', r; END IF;
  RAISE NOTICE 'PASS · T02 · sem ficha vinculada bloqueado';
END $$;

-- ============================================================================
-- T03 · Validacoes: email_invalid, phone_invalid, address_invalid, emergency_*
-- ============================================================================
SELECT test_login('93aaaaaa-aaa1-0000-0000-000000000011');
DO $$ DECLARE r JSONB;
BEGIN
  r := rpc_my_profile_request_create('personal_email', '{"value":"semarroba"}'::JSONB);
  IF r ->> 'error' <> 'email_invalid' THEN RAISE EXCEPTION 'T03a · %', r; END IF;

  r := rpc_my_profile_request_create('phone_mobile', '{"value":"123"}'::JSONB);
  IF r ->> 'error' <> 'phone_invalid' THEN RAISE EXCEPTION 'T03b · %', r; END IF;

  r := rpc_my_profile_request_create('residence_address', '{"value":"a"}'::JSONB);
  IF r ->> 'error' <> 'address_invalid' THEN RAISE EXCEPTION 'T03c · %', r; END IF;

  r := rpc_my_profile_request_create('emergency_contact', '{"name":"a","phone":"71999998888"}'::JSONB);
  IF r ->> 'error' <> 'emergency_name_invalid' THEN RAISE EXCEPTION 'T03d · %', r; END IF;

  r := rpc_my_profile_request_create('emergency_contact', '{"name":"Mae","phone":"123"}'::JSONB);
  IF r ->> 'error' <> 'emergency_phone_invalid' THEN RAISE EXCEPTION 'T03e · %', r; END IF;

  RAISE NOTICE 'PASS · T03 · validacoes por campo';
END $$;

-- ============================================================================
-- T04 · photo sem pending_photo_path -> photo_path_required
-- ============================================================================
DO $$ DECLARE r JSONB;
BEGIN
  r := rpc_my_profile_request_create('photo', '{}'::JSONB);
  IF r ->> 'error' <> 'photo_path_required' THEN RAISE EXCEPTION 'T04 FAIL · %', r; END IF;
  RAISE NOTICE 'PASS · T04 · photo sem path bloqueado';
END $$;

-- ============================================================================
-- T05 · Create com sucesso (phone_mobile)
-- ============================================================================
DO $$ DECLARE r JSONB;
BEGIN
  r := rpc_my_profile_request_create('phone_mobile', '{"value":"71999998888"}'::JSONB);
  IF (r ->> 'ok')::BOOLEAN <> TRUE THEN RAISE EXCEPTION 'T05 FAIL · %', r; END IF;
  IF r ->> 'request_id' IS NULL THEN RAISE EXCEPTION 'T05 FAIL · request_id null'; END IF;
  RAISE NOTICE 'PASS · T05 · cria com sucesso';
END $$;

-- ============================================================================
-- T06 · pending_request_exists ao recriar o mesmo campo
-- ============================================================================
DO $$ DECLARE r JSONB;
BEGIN
  r := rpc_my_profile_request_create('phone_mobile', '{"value":"71988887777"}'::JSONB);
  IF r ->> 'error' <> 'pending_request_exists' THEN
    RAISE EXCEPTION 'T06 FAIL · %', r;
  END IF;
  RAISE NOTICE 'PASS · T06 · uniqueness por (employee, field, pending)';
END $$;

-- ============================================================================
-- T07 · Lista as proprias solicitacoes
-- ============================================================================
DO $$ DECLARE r JSONB; DECLARE first JSONB;
BEGIN
  r := rpc_my_profile_requests_list();
  IF jsonb_array_length(r -> 'items') <> 1 THEN
    RAISE EXCEPTION 'T07 FAIL · esperava 1 · veio %', jsonb_array_length(r -> 'items');
  END IF;
  first := (r -> 'items') -> 0;
  IF first ->> 'field' <> 'phone_mobile' THEN
    RAISE EXCEPTION 'T07 FAIL · field veio %', first ->> 'field';
  END IF;
  IF first -> 'old_value' ->> 'value' <> '71988887777' THEN
    RAISE EXCEPTION 'T07 FAIL · old_value mal capturado';
  END IF;
  RAISE NOTICE 'PASS · T07 · lista propria com old_value snapshot';
END $$;

-- ============================================================================
-- T08 · Cancel libera a unique e permite recriar
-- ============================================================================
DO $$ DECLARE r JSONB; DECLARE rid UUID;
BEGIN
  SELECT id INTO rid FROM employee_profile_change_requests
  WHERE requested_by = '93aaaaaa-0003-0000-0000-000000000011' AND status = 'pending';

  r := rpc_my_profile_request_cancel(rid);
  IF (r ->> 'ok')::BOOLEAN <> TRUE THEN RAISE EXCEPTION 'T08a FAIL · %', r; END IF;

  -- Pode recriar
  r := rpc_my_profile_request_create('phone_mobile', '{"value":"71990001111"}'::JSONB);
  IF (r ->> 'ok')::BOOLEAN <> TRUE THEN
    RAISE EXCEPTION 'T08b FAIL · apos cancel deveria recriar · %', r;
  END IF;
  RAISE NOTICE 'PASS · T08 · cancel libera unique';
END $$;

-- ============================================================================
-- T09 · Nao pode cancelar uma ja approved (preparacao)
-- ============================================================================
DO $$ DECLARE r JSONB; DECLARE rid UUID;
BEGIN
  -- Forca aprovacao direta via SQL pra simular
  SELECT id INTO rid FROM employee_profile_change_requests
  WHERE requested_by = '93aaaaaa-0003-0000-0000-000000000011' AND status = 'pending';
  UPDATE employee_profile_change_requests SET status='approved', reviewed_at=now() WHERE id=rid;

  r := rpc_my_profile_request_cancel(rid);
  IF r ->> 'error' <> 'cannot_cancel_after_review' THEN
    RAISE EXCEPTION 'T09 FAIL · %', r;
  END IF;
  -- Volta pra pending para nao quebrar testes seguintes
  UPDATE employee_profile_change_requests SET status='pending', reviewed_at=NULL WHERE id=rid;
  RAISE NOTICE 'PASS · T09 · cancel apos review bloqueado';
END $$;

-- ============================================================================
-- T10 · pending_list: colaborador nao tem permissao
-- ============================================================================
DO $$ DECLARE r JSONB;
BEGIN
  r := rpc_profile_requests_pending_list();
  IF r ->> 'error' <> 'permission_denied' THEN RAISE EXCEPTION 'T10 FAIL · %', r; END IF;
  RAISE NOTICE 'PASS · T10 · colaborador bloqueado em pending_list';
END $$;

-- ============================================================================
-- T11 · RH ve a fila com employee_name preenchido
-- ============================================================================
SELECT test_login('93aaaaaa-aaa1-0000-0000-000000000003');
DO $$ DECLARE r JSONB; DECLARE first JSONB;
BEGIN
  r := rpc_profile_requests_pending_list();
  IF jsonb_array_length(r -> 'items') <> 1 THEN
    RAISE EXCEPTION 'T11 FAIL · esperava 1 · veio %', jsonb_array_length(r -> 'items');
  END IF;
  first := (r -> 'items') -> 0;
  IF first ->> 'employee_name' <> 'EU G3 FICHA' THEN
    RAISE EXCEPTION 'T11 FAIL · employee_name veio %', first ->> 'employee_name';
  END IF;
  RAISE NOTICE 'PASS · T11 · RH ve fila enriquecida';
END $$;

-- ============================================================================
-- T12 · Approve aplica phone_mobile em employees
-- ============================================================================
DO $$ DECLARE r JSONB; DECLARE rid UUID; DECLARE val TEXT;
BEGIN
  SELECT id INTO rid FROM employee_profile_change_requests
  WHERE employee_id='93aaaaaa-0004-0000-0000-000000000011' AND status='pending';

  r := rpc_profile_request_approve(rid);
  IF (r ->> 'ok')::BOOLEAN <> TRUE THEN RAISE EXCEPTION 'T12 FAIL · %', r; END IF;

  SELECT phone_mobile INTO val FROM employees WHERE id='93aaaaaa-0004-0000-0000-000000000011';
  IF val <> '71990001111' THEN
    RAISE EXCEPTION 'T12 FAIL · phone_mobile esperava 71990001111 · veio %', val;
  END IF;
  RAISE NOTICE 'PASS · T12 · phone_mobile aplicado';
END $$;

-- ============================================================================
-- T13 · Approve aplica personal_email
-- ============================================================================
SELECT test_login('93aaaaaa-aaa1-0000-0000-000000000011');
DO $$ DECLARE r JSONB;
BEGIN
  r := rpc_my_profile_request_create('personal_email', '{"value":"novo@gmail.com"}'::JSONB);
  IF (r ->> 'ok')::BOOLEAN <> TRUE THEN RAISE EXCEPTION 'T13a · %', r; END IF;
END $$;

SELECT test_login('93aaaaaa-aaa1-0000-0000-000000000003');
DO $$ DECLARE r JSONB; DECLARE rid UUID; DECLARE val TEXT;
BEGIN
  SELECT id INTO rid FROM employee_profile_change_requests
  WHERE employee_id='93aaaaaa-0004-0000-0000-000000000011' AND status='pending';
  r := rpc_profile_request_approve(rid);
  SELECT personal_email INTO val FROM employees WHERE id='93aaaaaa-0004-0000-0000-000000000011';
  IF val <> 'novo@gmail.com' THEN RAISE EXCEPTION 'T13 FAIL · veio %', val; END IF;
  RAISE NOTICE 'PASS · T13 · personal_email aplicado';
END $$;

-- ============================================================================
-- T14 · Approve aplica residence_address
-- ============================================================================
SELECT test_login('93aaaaaa-aaa1-0000-0000-000000000011');
DO $$ DECLARE r JSONB;
BEGIN
  r := rpc_my_profile_request_create('residence_address',
    '{"value":"Rua Nova, 200, Apto 5, Bairro Z, Salvador BA"}'::JSONB);
END $$;
SELECT test_login('93aaaaaa-aaa1-0000-0000-000000000003');
DO $$ DECLARE rid UUID; DECLARE val TEXT;
BEGIN
  SELECT id INTO rid FROM employee_profile_change_requests
  WHERE employee_id='93aaaaaa-0004-0000-0000-000000000011' AND status='pending';
  PERFORM rpc_profile_request_approve(rid);
  SELECT residence_address INTO val FROM employees WHERE id='93aaaaaa-0004-0000-0000-000000000011';
  IF val NOT LIKE 'Rua Nova%' THEN RAISE EXCEPTION 'T14 FAIL · veio %', val; END IF;
  RAISE NOTICE 'PASS · T14 · residence_address aplicado';
END $$;

-- ============================================================================
-- T15 · Approve emergency_contact (composto)
-- ============================================================================
SELECT test_login('93aaaaaa-aaa1-0000-0000-000000000011');
DO $$
BEGIN
  PERFORM rpc_my_profile_request_create('emergency_contact',
    '{"name":"Maria Silva","phone":"71988889999","relation":"mae"}'::JSONB);
END $$;
SELECT test_login('93aaaaaa-aaa1-0000-0000-000000000003');
DO $$ DECLARE rid UUID; DECLARE e employees;
BEGIN
  SELECT id INTO rid FROM employee_profile_change_requests
  WHERE employee_id='93aaaaaa-0004-0000-0000-000000000011' AND status='pending';
  PERFORM rpc_profile_request_approve(rid);
  SELECT * INTO e FROM employees WHERE id='93aaaaaa-0004-0000-0000-000000000011';
  IF e.emergency_contact_name <> 'Maria Silva' OR e.emergency_contact_phone <> '71988889999'
      OR e.emergency_contact_relation <> 'mae' THEN
    RAISE EXCEPTION 'T15 FAIL · emergency veio %, %, %',
      e.emergency_contact_name, e.emergency_contact_phone, e.emergency_contact_relation;
  END IF;
  RAISE NOTICE 'PASS · T15 · emergency_contact aplicado';
END $$;

-- ============================================================================
-- T16 · Approve photo · move pending_photo_path para employees
-- ============================================================================
SELECT test_login('93aaaaaa-aaa1-0000-0000-000000000011');
DO $$
BEGIN
  PERFORM rpc_my_profile_request_create('photo', '{}'::JSONB,
    p_pending_photo_path => '93aaaaaa-0000-0000-0000-000000000001/93aaaaaa-0004-0000-0000-000000000011/abc.jpg');
END $$;
SELECT test_login('93aaaaaa-aaa1-0000-0000-000000000003');
DO $$ DECLARE rid UUID; DECLARE val TEXT;
BEGIN
  SELECT id INTO rid FROM employee_profile_change_requests
  WHERE employee_id='93aaaaaa-0004-0000-0000-000000000011' AND status='pending';
  PERFORM rpc_profile_request_approve(rid);
  SELECT photo_storage_path INTO val FROM employees WHERE id='93aaaaaa-0004-0000-0000-000000000011';
  IF val NOT LIKE '%abc.jpg' THEN RAISE EXCEPTION 'T16 FAIL · veio %', val; END IF;
  RAISE NOTICE 'PASS · T16 · photo aprovada migra para employees';
END $$;

-- ============================================================================
-- T17 · Reject exige razao e grava motivo
-- ============================================================================
SELECT test_login('93aaaaaa-aaa1-0000-0000-000000000011');
DO $$
BEGIN
  PERFORM rpc_my_profile_request_create('phone_home', '{"value":"7133221111"}'::JSONB);
END $$;
SELECT test_login('93aaaaaa-aaa1-0000-0000-000000000003');
DO $$ DECLARE rid UUID; DECLARE r JSONB; DECLARE reason TEXT;
BEGIN
  SELECT id INTO rid FROM employee_profile_change_requests
  WHERE employee_id='93aaaaaa-0004-0000-0000-000000000011' AND status='pending';

  -- Sem razao
  r := rpc_profile_request_reject(rid, '');
  IF r ->> 'error' <> 'reason_required' THEN RAISE EXCEPTION 'T17a · %', r; END IF;

  -- Com razao
  r := rpc_profile_request_reject(rid, 'numero parece invalido');
  IF (r ->> 'ok')::BOOLEAN <> TRUE THEN RAISE EXCEPTION 'T17b · %', r; END IF;
  SELECT rejection_reason INTO reason FROM employee_profile_change_requests WHERE id=rid;
  IF reason <> 'numero parece invalido' THEN
    RAISE EXCEPTION 'T17c · reason veio %', reason;
  END IF;
  RAISE NOTICE 'PASS · T17 · reject grava motivo';
END $$;

-- ============================================================================
-- T18 · Cross-tenant bloqueado em approve
-- ============================================================================
SELECT test_login('93aaaaaa-aaa1-0000-0000-000000000011');
DO $$
BEGIN
  PERFORM rpc_my_profile_request_create('phone_mobile', '{"value":"71912345678"}'::JSONB);
END $$;

SELECT test_login('93aaaaaa-aaa1-0000-0000-000000000088');  -- RH do tenant Y
DO $$ DECLARE rid UUID; DECLARE r JSONB;
BEGIN
  -- O RH Y nem deveria ver requests do tenant X, mas se chamar approve com ID,
  -- deve bater em cross_tenant_blocked
  SELECT id INTO rid FROM employee_profile_change_requests
  WHERE employee_id='93aaaaaa-0004-0000-0000-000000000011' AND status='pending';
  r := rpc_profile_request_approve(rid);
  IF r ->> 'error' <> 'cross_tenant_blocked' THEN
    RAISE EXCEPTION 'T18 FAIL · %', r;
  END IF;
  RAISE NOTICE 'PASS · T18 · cross-tenant bloqueado em approve';
END $$;

DO $$ BEGIN
  RAISE NOTICE '========================================';
  RAISE NOTICE '=== G3 · 18 testes executados · OK   ===';
  RAISE NOTICE '========================================';
END $$;

ROLLBACK;

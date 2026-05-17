-- ============================================================================
-- R2 People · Testes Sessao E1 · Employees
-- ============================================================================
-- Cobertura: 25+ testes
--   1. Permissoes · super_admin/diretoria/rh escrevem · lider/colaborador nao
--   2. Create · validacao de campos obrigatorios + idempotencia por CPF
--   3. Update · preserva campos nao passados
--   4. Filtros · search, status, employer_unit, working_unit, job_title
--   5. Get by id · retorna ficha + filhas
--   6. Salary/Vacation/Leave add
--   7. Cross-tenant isolation
--   8. Archive (soft-delete)
--   9. Import via JSON
-- ============================================================================

BEGIN;

-- ============================================================================
-- SETUP
-- ============================================================================

INSERT INTO tenants (id, slug, legal_name, display_name) VALUES
  ('00000000-0000-0000-E100-000000000001', 'tenant-x', 'Tenant X', 'X'),
  ('00000000-0000-0000-E100-000000000002', 'tenant-y', 'Tenant Y', 'Y');

INSERT INTO employer_units (id, tenant_id, code, legal_name) VALUES
  ('00000000-0000-0000-E101-000000000001', '00000000-0000-0000-E100-000000000001', 'X-EMP', 'X Employer'),
  ('00000000-0000-0000-E101-000000000002', '00000000-0000-0000-E100-000000000002', 'Y-EMP', 'Y Employer');

INSERT INTO working_units (id, tenant_id, employer_unit_id, code, display_name) VALUES
  ('00000000-0000-0000-E102-000000000001', '00000000-0000-0000-E100-000000000001',
   '00000000-0000-0000-E101-000000000001', 'X-WU', 'X WU');

INSERT INTO departments (id, tenant_id, code, display_name) VALUES
  ('00000000-0000-0000-E103-000000000001', '00000000-0000-0000-E100-000000000001', 'OPS', 'OPS');

INSERT INTO app_users (
  id, tenant_id, auth_user_id, email, full_name, role,
  employer_unit_id, working_unit_id, department_id, manager_id, employment_link, hired_at
) VALUES
  ('00000000-0000-0000-E104-000000000001', '00000000-0000-0000-E100-000000000001',
   'e1aaaaaa-aaaa-aaaa-aaaa-000000000001', 'sa@r2.test', 'SA', 'super_admin',
   NULL, NULL, NULL, NULL, 'clt', '2020-01-01'),
  ('00000000-0000-0000-E104-000000000002', '00000000-0000-0000-E100-000000000001',
   'e1aaaaaa-aaaa-aaaa-aaaa-000000000002', 'dir@x.test', 'DIR-X', 'diretoria',
   '00000000-0000-0000-E101-000000000001', '00000000-0000-0000-E102-000000000001',
   '00000000-0000-0000-E103-000000000001', NULL, 'clt', '2020-01-01'),
  ('00000000-0000-0000-E104-000000000003', '00000000-0000-0000-E100-000000000001',
   'e1aaaaaa-aaaa-aaaa-aaaa-000000000003', 'rh@x.test', 'RH-X', 'rh',
   '00000000-0000-0000-E101-000000000001', '00000000-0000-0000-E102-000000000001',
   '00000000-0000-0000-E103-000000000001',
   '00000000-0000-0000-E104-000000000002', 'clt', '2020-01-01'),
  ('00000000-0000-0000-E104-000000000004', '00000000-0000-0000-E100-000000000001',
   'e1aaaaaa-aaaa-aaaa-aaaa-000000000004', 'lid@x.test', 'LID-X', 'lider',
   '00000000-0000-0000-E101-000000000001', '00000000-0000-0000-E102-000000000001',
   '00000000-0000-0000-E103-000000000001',
   '00000000-0000-0000-E104-000000000002', 'clt', '2020-01-01'),
  ('00000000-0000-0000-E104-000000000005', '00000000-0000-0000-E100-000000000001',
   'e1aaaaaa-aaaa-aaaa-aaaa-000000000005', 'col@x.test', 'COL-X', 'colaborador',
   '00000000-0000-0000-E101-000000000001', '00000000-0000-0000-E102-000000000001',
   '00000000-0000-0000-E103-000000000001',
   '00000000-0000-0000-E104-000000000004', 'clt', '2020-01-01'),
  ('00000000-0000-0000-E104-000000000006', '00000000-0000-0000-E100-000000000002',
   'e1aaaaaa-aaaa-aaaa-aaaa-000000000006', 'rh@y.test', 'RH-Y', 'rh',
   NULL, NULL, NULL, NULL, 'clt', '2020-01-01');

CREATE OR REPLACE FUNCTION e1_assert(condition BOOLEAN, msg TEXT)
RETURNS VOID AS $$
BEGIN
  IF NOT condition THEN
    RAISE EXCEPTION 'FAIL · %', msg;
  ELSE
    RAISE NOTICE 'PASS · %', msg;
  END IF;
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- T01-T05 · Permissoes
-- ============================================================================

SELECT test_login('e1aaaaaa-aaaa-aaaa-aaaa-000000000005');  -- COL
SELECT e1_assert(
  rpc_employees_create(jsonb_build_object(
    'full_name', 'Test', 'hire_date', '2024-01-01', 'job_title', 'Op'
  )) ->> 'error' = 'permission_denied',
  'T01 · colaborador NAO pode criar funcionario'
);

SELECT test_login('e1aaaaaa-aaaa-aaaa-aaaa-000000000004');  -- LID
SELECT e1_assert(
  rpc_employees_create(jsonb_build_object(
    'full_name', 'Test', 'hire_date', '2024-01-01', 'job_title', 'Op'
  )) ->> 'error' = 'permission_denied',
  'T02 · lider NAO pode criar funcionario'
);

SELECT test_login('e1aaaaaa-aaaa-aaaa-aaaa-000000000003');  -- RH
SELECT e1_assert(
  (rpc_employees_create(jsonb_build_object(
    'full_name', 'Test RH', 'hire_date', '2024-01-01', 'job_title', 'Op', 'cpf', '111.111.111-11'
  )) ->> 'ok')::BOOLEAN = TRUE,
  'T03 · RH pode criar funcionario'
);

SELECT test_login('e1aaaaaa-aaaa-aaaa-aaaa-000000000002');  -- DIR
SELECT e1_assert(
  (rpc_employees_create(jsonb_build_object(
    'full_name', 'Test DIR', 'hire_date', '2024-01-01', 'job_title', 'Op', 'cpf', '222.222.222-22'
  )) ->> 'ok')::BOOLEAN = TRUE,
  'T04 · diretoria pode criar funcionario'
);

SELECT test_login('e1aaaaaa-aaaa-aaaa-aaaa-000000000001');  -- SA
SELECT e1_assert(
  (rpc_employees_create(jsonb_build_object(
    'full_name', 'Test SA', 'hire_date', '2024-01-01', 'job_title', 'Op', 'cpf', '333.333.333-33',
    'tenant_id', '00000000-0000-0000-E100-000000000001'
  )) ->> 'ok')::BOOLEAN = TRUE,
  'T05 · super_admin pode criar em qualquer tenant'
);

-- ============================================================================
-- T06-T08 · Validacao de campos obrigatorios
-- ============================================================================

SELECT test_login('e1aaaaaa-aaaa-aaaa-aaaa-000000000003');  -- RH

SELECT e1_assert(
  rpc_employees_create(jsonb_build_object(
    'hire_date', '2024-01-01', 'job_title', 'Op'
  )) ->> 'error' = 'full_name_required',
  'T06 · full_name obrigatorio'
);

SELECT e1_assert(
  rpc_employees_create(jsonb_build_object(
    'full_name', 'A', 'job_title', 'Op'
  )) ->> 'error' = 'hire_date_required',
  'T07 · hire_date obrigatoria'
);

SELECT e1_assert(
  rpc_employees_create(jsonb_build_object(
    'full_name', 'A', 'hire_date', '2024-01-01'
  )) ->> 'error' = 'job_title_required',
  'T08 · job_title obrigatorio'
);

-- ============================================================================
-- T09-T10 · Idempotencia por CPF
-- ============================================================================

DO $$
DECLARE v JSONB;
BEGIN
  v := rpc_employees_create(jsonb_build_object(
    'full_name', 'IDEMP TEST', 'hire_date', '2024-01-01', 'job_title', 'Op',
    'cpf', '999.999.999-99'
  ));
  IF (v ->> 'created')::BOOLEAN <> TRUE THEN
    RAISE EXCEPTION 'T09 FAIL · primeira create deveria retornar created=true';
  END IF;
  PERFORM set_config('e1.idemp_id', v ->> 'id', FALSE);
  RAISE NOTICE 'PASS · T09 · primeira create retorna created=true';

  v := rpc_employees_create(jsonb_build_object(
    'full_name', 'IDEMP TEST DUPLICATE', 'hire_date', '2024-01-01', 'job_title', 'Op',
    'cpf', '999.999.999-99'
  ));
  IF (v ->> 'already_exists')::BOOLEAN <> TRUE THEN
    RAISE EXCEPTION 'T10 FAIL · segunda create deveria retornar already_exists=true · v=%', v;
  END IF;
  IF (v ->> 'id') <> current_setting('e1.idemp_id') THEN
    RAISE EXCEPTION 'T10 FAIL · ids divergentes';
  END IF;
  RAISE NOTICE 'PASS · T10 · CPF duplicado retorna already_exists com mesmo id';
END $$;

-- ============================================================================
-- T11-T12 · Update preserva campos nao passados
-- ============================================================================

DO $$
DECLARE v_id UUID;
DECLARE r JSONB;
BEGIN
  v_id := current_setting('e1.idemp_id')::UUID;

  r := rpc_employees_update(v_id, jsonb_build_object('phone_mobile', '75-999998888'));
  IF (r ->> 'ok')::BOOLEAN <> TRUE THEN
    RAISE EXCEPTION 'T11 FAIL · update falhou · r=%', r;
  END IF;
  RAISE NOTICE 'PASS · T11 · update bem-sucedido';

  -- Verifica que job_title (nao passado) foi preservado e phone_mobile foi atualizado
  IF (SELECT phone_mobile FROM employees WHERE id = v_id) <> '75-999998888' THEN
    RAISE EXCEPTION 'T12 FAIL · phone_mobile nao atualizou';
  END IF;
  IF (SELECT job_title FROM employees WHERE id = v_id) <> 'Op' THEN
    RAISE EXCEPTION 'T12 FAIL · job_title foi perdido';
  END IF;
  RAISE NOTICE 'PASS · T12 · update preserva campos nao passados';
END $$;

-- ============================================================================
-- T13-T16 · Get by id + filhas
-- ============================================================================

DO $$
DECLARE v_id UUID;
DECLARE r JSONB;
BEGIN
  v_id := current_setting('e1.idemp_id')::UUID;
  r := rpc_employees_get_by_id(v_id);
  IF (r ->> 'ok')::BOOLEAN <> TRUE THEN
    RAISE EXCEPTION 'T13 FAIL · get_by_id retornou erro · r=%', r;
  END IF;
  RAISE NOTICE 'PASS · T13 · get_by_id retorna ok';

  IF r -> 'employee' IS NULL THEN
    RAISE EXCEPTION 'T14 FAIL · payload sem employee';
  END IF;
  RAISE NOTICE 'PASS · T14 · payload inclui employee';

  IF NOT (r ? 'salary_history') OR NOT (r ? 'vacations') OR NOT (r ? 'leaves') THEN
    RAISE EXCEPTION 'T15 FAIL · faltam filhas';
  END IF;
  RAISE NOTICE 'PASS · T15 · payload inclui salary_history, vacations, leaves';

  IF (r ->> 'employee')::JSONB ->> 'is_active' <> 'true' THEN
    RAISE EXCEPTION 'T16 FAIL · is_active nao computado';
  END IF;
  RAISE NOTICE 'PASS · T16 · is_active e calculado';
END $$;

-- ============================================================================
-- T17 · Lista com filtros
-- ============================================================================

DO $$
DECLARE r JSONB;
BEGIN
  r := rpc_employees_list(NULL, 'all');
  IF (r ->> 'total')::INT < 4 THEN
    RAISE EXCEPTION 'T17 FAIL · lista total esperava >=4 · veio %', r ->> 'total';
  END IF;
  RAISE NOTICE 'PASS · T17 · lista total >=4';
END $$;

DO $$
DECLARE r JSONB;
BEGIN
  r := rpc_employees_list('IDEMP');
  IF (r ->> 'total')::INT <> 1 THEN
    RAISE EXCEPTION 'T18 FAIL · esperava 1 · veio % · payload=%', r ->> 'total', r;
  END IF;
  RAISE NOTICE 'PASS · T18 · busca por nome retorna 1 resultado';
END $$;

DO $$
DECLARE r JSONB;
BEGIN
  r := rpc_employees_list('999.999.999-99');
  IF (r ->> 'total')::INT <> 1 THEN
    RAISE EXCEPTION 'T19 FAIL · esperava 1 · veio % · payload=%', r ->> 'total', r;
  END IF;
  RAISE NOTICE 'PASS · T19 · busca por CPF retorna 1 resultado';
END $$;

-- ============================================================================
-- T20-T21 · Salary add + filho aparece em get_by_id
-- ============================================================================

DO $$
DECLARE v_id UUID;
DECLARE r JSONB;
BEGIN
  v_id := current_setting('e1.idemp_id')::UUID;
  r := rpc_employees_salary_add(v_id, jsonb_build_object(
    'effective_date', '2024-06-01', 'amount', '1500.00', 'change_type', 'adjustment'
  ));
  IF (r ->> 'ok')::BOOLEAN <> TRUE THEN
    RAISE EXCEPTION 'T20 FAIL · salary_add · r=%', r;
  END IF;
  RAISE NOTICE 'PASS · T20 · salary_add ok';

  r := rpc_employees_get_by_id(v_id);
  IF jsonb_array_length(r -> 'salary_history') < 1 THEN
    RAISE EXCEPTION 'T21 FAIL · salary_history vazio · r=%', r;
  END IF;
  RAISE NOTICE 'PASS · T21 · salary_history populado apos add (% itens)',
    jsonb_array_length(r -> 'salary_history');
END $$;

-- ============================================================================
-- T22-T23 · Vacation + Leave add
-- ============================================================================

DO $$
DECLARE v_id UUID;
DECLARE r JSONB;
BEGIN
  v_id := current_setting('e1.idemp_id')::UUID;

  r := rpc_employees_vacation_add(v_id, jsonb_build_object(
    'kind', 'aquisitivo', 'start_date', '2024-01-01', 'end_date', '2024-12-31'
  ));
  IF (r ->> 'ok')::BOOLEAN <> TRUE THEN RAISE EXCEPTION 'T22 FAIL · r=%', r; END IF;
  RAISE NOTICE 'PASS · T22 · vacation_add ok';

  r := rpc_employees_leave_add(v_id, jsonb_build_object(
    'start_date', '2024-03-15', 'end_date', '2024-03-20', 'reason', 'doenca_comum', 'cid', 'A09'
  ));
  IF (r ->> 'ok')::BOOLEAN <> TRUE THEN RAISE EXCEPTION 'T23 FAIL · r=%', r; END IF;
  RAISE NOTICE 'PASS · T23 · leave_add ok';
END $$;

-- ============================================================================
-- T24 · Cross-tenant isolation · RH-Y nao acessa funcionarios de X
-- ============================================================================

SELECT test_login('e1aaaaaa-aaaa-aaaa-aaaa-000000000006');  -- RH-Y

DO $$
DECLARE r JSONB;
BEGIN
  r := rpc_employees_list(NULL, 'all');
  IF (r ->> 'total')::INT <> 0 THEN
    RAISE EXCEPTION 'T24 FAIL · RH-Y deveria ver 0 funcionarios · veio %', r ->> 'total';
  END IF;
  RAISE NOTICE 'PASS · T24 · RH-Y ve 0 funcionarios (isolamento cross-tenant)';
END $$;

-- T25 · RH-Y nao consegue acessar funcionario do tenant X
DO $$
DECLARE r JSONB;
BEGIN
  r := rpc_employees_get_by_id(current_setting('e1.idemp_id')::UUID);
  IF r ->> 'error' <> 'employee_not_found' THEN
    RAISE EXCEPTION 'T25 FAIL · esperava employee_not_found · veio %', r;
  END IF;
  RAISE NOTICE 'PASS · T25 · RH-Y bloqueado por cross-tenant (employee_not_found)';
END $$;

-- ============================================================================
-- T26 · Archive (soft-delete)
-- ============================================================================

SELECT test_login('e1aaaaaa-aaaa-aaaa-aaaa-000000000003');  -- RH-X

DO $$
DECLARE v_id UUID;
DECLARE r JSONB;
BEGIN
  v_id := current_setting('e1.idemp_id')::UUID;
  r := rpc_employees_archive(v_id);
  IF (r ->> 'ok')::BOOLEAN <> TRUE THEN
    RAISE EXCEPTION 'T26 FAIL · archive · r=%', r;
  END IF;

  -- Nao deve mais aparecer na lista
  IF (rpc_employees_list('IDEMP') ->> 'total')::INT <> 0 THEN
    RAISE EXCEPTION 'T26 FAIL · arquivado ainda aparece na lista';
  END IF;
  RAISE NOTICE 'PASS · T26 · archive ok · some da lista';
END $$;

-- ============================================================================
-- T27 · Import via JSON
-- ============================================================================

DO $$
DECLARE r JSONB;
BEGIN
  r := rpc_employees_import_xlsx(jsonb_build_array(
    jsonb_build_object('full_name', 'IMP A', 'hire_date', '2024-01-01', 'job_title', 'Op', 'cpf', '100.000.000-01'),
    jsonb_build_object('full_name', 'IMP B', 'hire_date', '2024-01-01', 'job_title', 'Op', 'cpf', '100.000.000-02'),
    jsonb_build_object('full_name', 'IMP DUP', 'hire_date', '2024-01-01', 'job_title', 'Op', 'cpf', '100.000.000-01'),
    jsonb_build_object('full_name', 'IMP INC')  -- vai falhar (sem hire_date)
  ));
  IF (r ->> 'created')::INT <> 2 THEN
    RAISE EXCEPTION 'T27 FAIL · esperava created=2 · veio %', r;
  END IF;
  IF (r ->> 'skipped')::INT <> 1 THEN
    RAISE EXCEPTION 'T27 FAIL · esperava skipped=1 · veio %', r;
  END IF;
  IF jsonb_array_length(r -> 'errors') <> 1 THEN
    RAISE EXCEPTION 'T27 FAIL · esperava 1 erro · veio %', r;
  END IF;
  RAISE NOTICE 'PASS · T27 · import_xlsx · 2 created, 1 skipped, 1 error';
END $$;

-- ============================================================================
-- T28 · Audit log foi populado em employees
-- ============================================================================

SELECT e1_assert(
  (SELECT count(*) FROM audit_log WHERE entity_table = 'employees' AND tenant_id = '00000000-0000-0000-E100-000000000001') > 0,
  'T28 · audit_log registrou operacoes em employees'
);

-- ============================================================================
-- T29 · Termination · atualiza status e fica em "terminated"
-- ============================================================================

DO $$
DECLARE v_id UUID;
DECLARE r JSONB;
BEGIN
  -- Pega um dos imports criados
  SELECT id INTO v_id FROM employees
  WHERE full_name = 'IMP A' AND tenant_id = '00000000-0000-0000-E100-000000000001';

  r := rpc_employees_update(v_id, jsonb_build_object(
    'termination_date', '2025-06-01',
    'termination_type', 'demitido_sem_justa_causa'
  ));
  IF (r ->> 'ok')::BOOLEAN <> TRUE THEN
    RAISE EXCEPTION 'T29 FAIL · update termination · r=%', r;
  END IF;

  -- Confere lista com filtro 'terminated'
  r := rpc_employees_list(NULL, 'terminated');
  IF (r ->> 'total')::INT < 1 THEN
    RAISE EXCEPTION 'T29 FAIL · filtro terminated nao retornou · r=%', r;
  END IF;
  RAISE NOTICE 'PASS · T29 · termination registrada e filtro terminated funciona';
END $$;

-- ============================================================================
-- T30 · Filtros combinados (employer_unit + status)
-- ============================================================================

DO $$
DECLARE r JSONB;
BEGIN
  r := rpc_employees_list(NULL, 'active', '00000000-0000-0000-E101-000000000001');
  -- Deve retornar 0+ · so testando que a query nao quebra
  IF (r ->> 'ok')::BOOLEAN <> TRUE THEN
    RAISE EXCEPTION 'T30 FAIL · r=%', r;
  END IF;
  RAISE NOTICE 'PASS · T30 · filtro combinado (employer_unit + status) executa';
END $$;

-- ============================================================================
-- FECHAMENTO
-- ============================================================================

DO $$
BEGIN
  RAISE NOTICE '========================================';
  RAISE NOTICE '=== E1 · 30 testes executados · OK   ===';
  RAISE NOTICE '========================================';
END $$;

ROLLBACK;

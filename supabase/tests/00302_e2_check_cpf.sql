-- ============================================================================
-- R2 People · Testes Sessao E2 · RPC check_cpf
-- ============================================================================
-- 6 testes:
--   T01: CPF nao existente · retorna exists=false
--   T02: CPF existente · retorna exists=true com id e nome
--   T03: CPF normalizado (com mascara igual sem mascara)
--   T04: CPF invalido (digitos curtos) · retorna invalid_format
--   T05: Cross-tenant · CPF do tenant Y nao aparece para usuario do X
--   T06: Permissao · colaborador tambem pode ler (only employees_can_read)
-- ============================================================================

BEGIN;

-- Setup
INSERT INTO tenants (id, slug, legal_name, display_name) VALUES
  ('11111111-0000-0000-0000-000000000001', 'tx', 'Tenant X', 'X'),
  ('11111111-0000-0000-0000-000000000002', 'ty', 'Tenant Y', 'Y');

INSERT INTO app_users (id, tenant_id, auth_user_id, email, full_name, role, employment_link, hired_at) VALUES
  ('22222222-0000-0000-0000-000000000003', '11111111-0000-0000-0000-000000000001',
   '33333333-0000-0000-0000-000000000003', 'rh@x.test', 'RH-X', 'rh', 'clt', '2020-01-01'),
  ('22222222-0000-0000-0000-000000000005', '11111111-0000-0000-0000-000000000001',
   '33333333-0000-0000-0000-000000000005', 'col@x.test', 'COL-X', 'colaborador', 'clt', '2020-01-01'),
  ('22222222-0000-0000-0000-000000000006', '11111111-0000-0000-0000-000000000002',
   '33333333-0000-0000-0000-000000000006', 'rh@y.test', 'RH-Y', 'rh', 'clt', '2020-01-01');

-- RH-X cria 1 funcionario no tenant X
SELECT test_login('33333333-0000-0000-0000-000000000003');
SELECT rpc_employees_create(jsonb_build_object(
  'full_name', 'JOAO DA SILVA', 'hire_date', '2024-01-01', 'job_title', 'Op',
  'cpf', '921.753.765-91', 'matricula_esocial', 'M001'
));

-- RH-Y cria 1 funcionario no tenant Y (mesmo CPF, escopo isolado)
SELECT test_login('33333333-0000-0000-0000-000000000006');
SELECT rpc_employees_create(jsonb_build_object(
  'full_name', 'MARIA DA SILVA', 'hire_date', '2024-01-01', 'job_title', 'Op',
  'cpf', '111.222.333-44', 'matricula_esocial', 'MY001'
));

-- Volta para RH-X
SELECT test_login('33333333-0000-0000-0000-000000000003');

-- ============================================================================
-- T01: CPF nao existente
-- ============================================================================

DO $$
DECLARE r JSONB;
BEGIN
  r := rpc_employees_check_cpf('999.888.777-66');
  IF (r ->> 'ok')::BOOLEAN <> TRUE THEN
    RAISE EXCEPTION 'T01 FAIL · r=%', r;
  END IF;
  IF (r ->> 'exists')::BOOLEAN <> FALSE THEN
    RAISE EXCEPTION 'T01 FAIL · esperava exists=false · veio %', r;
  END IF;
  RAISE NOTICE 'PASS · T01 · CPF inexistente retorna exists=false';
END $$;

-- ============================================================================
-- T02: CPF existente
-- ============================================================================

DO $$
DECLARE r JSONB;
BEGIN
  r := rpc_employees_check_cpf('921.753.765-91');
  IF (r ->> 'exists')::BOOLEAN <> TRUE THEN
    RAISE EXCEPTION 'T02 FAIL · esperava exists=true · veio %', r;
  END IF;
  IF r ->> 'full_name' <> 'JOAO DA SILVA' THEN
    RAISE EXCEPTION 'T02 FAIL · nome divergente · veio %', r ->> 'full_name';
  END IF;
  IF r ->> 'matricula_esocial' <> 'M001' THEN
    RAISE EXCEPTION 'T02 FAIL · matricula divergente · veio %', r ->> 'matricula_esocial';
  END IF;
  IF (r ->> 'is_active')::BOOLEAN <> TRUE THEN
    RAISE EXCEPTION 'T02 FAIL · is_active esperava true · veio %', r;
  END IF;
  RAISE NOTICE 'PASS · T02 · CPF existente retorna nome e matricula';
END $$;

-- ============================================================================
-- T03: CPF sem mascara (so digitos) deve casar com cadastrado com mascara
-- ============================================================================

DO $$
DECLARE r JSONB;
BEGIN
  r := rpc_employees_check_cpf('92175376591');  -- sem mascara
  IF (r ->> 'exists')::BOOLEAN <> TRUE THEN
    RAISE EXCEPTION 'T03 FAIL · esperava exists=true · veio %', r;
  END IF;
  RAISE NOTICE 'PASS · T03 · CPF sem mascara casa com cadastrado com mascara';
END $$;

-- ============================================================================
-- T04: CPF invalido (curto)
-- ============================================================================

DO $$
DECLARE r JSONB;
BEGIN
  r := rpc_employees_check_cpf('123');
  IF (r ->> 'exists')::BOOLEAN <> FALSE THEN
    RAISE EXCEPTION 'T04 FAIL · esperava exists=false · veio %', r;
  END IF;
  IF r ->> 'reason' <> 'invalid_format' THEN
    RAISE EXCEPTION 'T04 FAIL · esperava reason=invalid_format · veio %', r;
  END IF;
  RAISE NOTICE 'PASS · T04 · CPF curto retorna reason=invalid_format';
END $$;

-- ============================================================================
-- T05: Cross-tenant · CPF da MARIA (tenant Y) nao deve aparecer para RH-X
-- ============================================================================

DO $$
DECLARE r JSONB;
BEGIN
  r := rpc_employees_check_cpf('111.222.333-44');
  IF (r ->> 'exists')::BOOLEAN <> FALSE THEN
    RAISE EXCEPTION 'T05 FAIL · cross-tenant deveria isolar · veio %', r;
  END IF;
  RAISE NOTICE 'PASS · T05 · CPF de outro tenant retorna exists=false (isolamento)';
END $$;

-- ============================================================================
-- T06: Colaborador (read-only) tambem pode usar check_cpf
-- ============================================================================

SELECT test_login('33333333-0000-0000-0000-000000000005');  -- COL-X

DO $$
DECLARE r JSONB;
BEGIN
  r := rpc_employees_check_cpf('921.753.765-91');
  IF (r ->> 'exists')::BOOLEAN <> TRUE THEN
    RAISE EXCEPTION 'T06 FAIL · colaborador deveria poder ler · veio %', r;
  END IF;
  RAISE NOTICE 'PASS · T06 · colaborador pode usar check_cpf (read-only)';
END $$;

DO $$
BEGIN
  RAISE NOTICE '========================================';
  RAISE NOTICE '=== E2 · 6 testes executados · OK   ===';
  RAISE NOTICE '========================================';
END $$;

ROLLBACK;

-- ============================================================================
-- R2 People · Testes Sessao F6 · Dashboard Drilldown
-- ============================================================================
-- 15 testes:
--   T01-T02 · permissoes (colaborador/lider) e escopo
--   T03-T05 · kind=ninebox
--   T06-T07 · kind=employer_unit
--   T08     · kind=department
--   T09-T11 · kind=headcount_metric
--   T12-T13 · kind=pdis_by_manager
--   T14     · kind invalido + uuid invalido
--   T15     · isolamento cross-tenant
-- ============================================================================

BEGIN;

-- Reaproveita SETUP no estilo da F4 mas com prefixo f6
INSERT INTO tenants (id, slug, legal_name, display_name) VALUES
  ('f6aaaaaa-0000-0000-0000-000000000001', 'tx-f6', 'Tenant X F6', 'X'),
  ('f6aaaaaa-0000-0000-0000-000000000002', 'tx-f6-y', 'Tenant Y F6', 'Y');

INSERT INTO employer_units (id, tenant_id, code, legal_name, trade_name) VALUES
  ('f6aaaaaa-0001-0000-0000-000000000001', 'f6aaaaaa-0000-0000-0000-000000000001',
   'XEMP1', 'X Emp 1 Legal', 'ATP F6'),
  ('f6aaaaaa-0001-0000-0000-000000000002', 'f6aaaaaa-0000-0000-0000-000000000001',
   'XEMP2', 'X Emp 2 Legal', 'Cestao F6');

INSERT INTO departments (id, tenant_id, code, display_name) VALUES
  ('f6aaaaaa-0002-0000-0000-000000000001', 'f6aaaaaa-0000-0000-0000-000000000001',
   'OPS', 'Operacoes F6'),
  ('f6aaaaaa-0002-0000-0000-000000000002', 'f6aaaaaa-0000-0000-0000-000000000001',
   'FIN', 'Financeiro F6');

INSERT INTO app_users (id, tenant_id, auth_user_id, email, full_name, role, manager_id,
                       employment_link, hired_at) VALUES
  ('f6aaaaaa-0003-0000-0000-000000000001', 'f6aaaaaa-0000-0000-0000-000000000001',
   'f6aaaaaa-aaa1-0000-0000-000000000001', 'sa@f6.test', 'SA F6', 'super_admin', NULL,
   'clt', '2020-01-01'),
  ('f6aaaaaa-0003-0000-0000-000000000003', 'f6aaaaaa-0000-0000-0000-000000000001',
   'f6aaaaaa-aaa1-0000-0000-000000000003', 'rh@f6.test', 'RH F6', 'rh', NULL,
   'clt', '2020-01-01'),
  ('f6aaaaaa-0003-0000-0000-000000000010', 'f6aaaaaa-0000-0000-0000-000000000001',
   'f6aaaaaa-aaa1-0000-0000-000000000010', 'gera@f6.test', 'GER A F6', 'lider', NULL,
   'clt', '2020-01-01'),
  ('f6aaaaaa-0003-0000-0000-000000000011', 'f6aaaaaa-0000-0000-0000-000000000001',
   'f6aaaaaa-aaa1-0000-0000-000000000011', 'colaba1@f6.test', 'COLAB A1 F6', 'colaborador',
   'f6aaaaaa-0003-0000-0000-000000000010', 'clt', CURRENT_DATE - 20),
  ('f6aaaaaa-0003-0000-0000-000000000012', 'f6aaaaaa-0000-0000-0000-000000000001',
   'f6aaaaaa-aaa1-0000-0000-000000000012', 'colaba2@f6.test', 'COLAB A2 F6', 'colaborador',
   'f6aaaaaa-0003-0000-0000-000000000010', 'clt', '2021-01-01'),
  ('f6aaaaaa-0003-0000-0000-000000000099', 'f6aaaaaa-0000-0000-0000-000000000001',
   'f6aaaaaa-aaa1-0000-0000-000000000099', 'colabx@f6.test', 'COLAB X F6', 'colaborador',
   NULL, 'clt', '2021-01-01'),
  ('f6aaaaaa-0003-0000-0000-000000000088', 'f6aaaaaa-0000-0000-0000-000000000002',
   'f6aaaaaa-aaa1-0000-0000-000000000088', 'rhy@f6.test', 'RH Y F6', 'rh', NULL,
   'clt', '2020-01-01');

INSERT INTO employees (id, tenant_id, full_name, job_title, hire_date, termination_date,
                       cpf, employer_unit_id, department_id, created_by) VALUES
  ('f6aaaaaa-0004-0000-0000-000000000011', 'f6aaaaaa-0000-0000-0000-000000000001',
   'COLAB A1 F6 FICHA', 'Op', CURRENT_DATE - 20, NULL, '60111111111',
   'f6aaaaaa-0001-0000-0000-000000000001', 'f6aaaaaa-0002-0000-0000-000000000001',
   'f6aaaaaa-0003-0000-0000-000000000003'),
  ('f6aaaaaa-0004-0000-0000-000000000012', 'f6aaaaaa-0000-0000-0000-000000000001',
   'COLAB A2 F6 FICHA', 'Op', '2021-01-01', NULL, '60222222222',
   'f6aaaaaa-0001-0000-0000-000000000002', 'f6aaaaaa-0002-0000-0000-000000000002',
   'f6aaaaaa-0003-0000-0000-000000000003'),
  ('f6aaaaaa-0004-0000-0000-000000000099', 'f6aaaaaa-0000-0000-0000-000000000001',
   'COLAB X F6 FICHA', 'Op', '2021-01-01', CURRENT_DATE - 40, '60999999999',
   'f6aaaaaa-0001-0000-0000-000000000001', NULL,
   'f6aaaaaa-0003-0000-0000-000000000003');

UPDATE app_users SET employee_id='f6aaaaaa-0004-0000-0000-000000000011' WHERE id='f6aaaaaa-0003-0000-0000-000000000011';
UPDATE app_users SET employee_id='f6aaaaaa-0004-0000-0000-000000000012' WHERE id='f6aaaaaa-0003-0000-0000-000000000012';
UPDATE app_users SET employee_id='f6aaaaaa-0004-0000-0000-000000000099' WHERE id='f6aaaaaa-0003-0000-0000-000000000099';

-- Ninebox · A1 em (3,3) Future Star, A2 em (2,2)
INSERT INTO ninebox_cycles (id, tenant_id, name, status, start_date, end_date, created_by) VALUES
  ('f6aaaaaa-0005-0000-0000-000000000001', 'f6aaaaaa-0000-0000-0000-000000000001',
   'Ciclo F6', 'active', '2024-01-01', '2024-12-31',
   'f6aaaaaa-0003-0000-0000-000000000003');

INSERT INTO ninebox_evaluations (id, tenant_id, subject_id, manager_id, cycle_id,
                                  is_adhoc, status,
                                  grid_size_snapshot, potential_criteria_snapshot,
                                  performance_criteria_snapshot, box_labels_snapshot,
                                  final_box_row, final_box_col, final_box_label,
                                  finalized_at, created_by) VALUES
  ('f6aaaaaa-0006-0000-0000-000000000001', 'f6aaaaaa-0000-0000-0000-000000000001',
   'f6aaaaaa-0003-0000-0000-000000000011', 'f6aaaaaa-0003-0000-0000-000000000010',
   'f6aaaaaa-0005-0000-0000-000000000001',
   FALSE, 'finalized',
   '3x3', '[]'::jsonb, '[]'::jsonb, '[]'::jsonb,
   3, 3, 'Future Star', now() - INTERVAL '10 days',
   'f6aaaaaa-0003-0000-0000-000000000010'),
  ('f6aaaaaa-0006-0000-0000-000000000002', 'f6aaaaaa-0000-0000-0000-000000000001',
   'f6aaaaaa-0003-0000-0000-000000000012', 'f6aaaaaa-0003-0000-0000-000000000010',
   'f6aaaaaa-0005-0000-0000-000000000001',
   FALSE, 'finalized',
   '3x3', '[]'::jsonb, '[]'::jsonb, '[]'::jsonb,
   2, 2, 'Mantenedor+', now() - INTERVAL '5 days',
   'f6aaaaaa-0003-0000-0000-000000000010');

-- PDIs em atraso de A1 (2 em ciclos diferentes)
INSERT INTO pdi_cycles (id, tenant_id, code, display_name, start_date, end_date, active) VALUES
  ('f6aaaaaa-0007-0000-0000-000000000001', 'f6aaaaaa-0000-0000-0000-000000000001',
   'PDI2024F6', 'PDI 2024', '2024-01-01', '2024-12-31', TRUE),
  ('f6aaaaaa-0007-0000-0000-000000000002', 'f6aaaaaa-0000-0000-0000-000000000001',
   'PDI2023F6', 'PDI 2023', '2023-01-01', '2023-12-31', FALSE);

INSERT INTO pdis (id, tenant_id, user_id, cycle_id, manager_id_snapshot,
                  objective, status, start_date, end_date, created_by) VALUES
  ('f6aaaaaa-0008-0000-0000-000000000001', 'f6aaaaaa-0000-0000-0000-000000000001',
   'f6aaaaaa-0003-0000-0000-000000000011',
   'f6aaaaaa-0007-0000-0000-000000000001',
   'f6aaaaaa-0003-0000-0000-000000000010',
   'PDI 1 atrasado', 'active', '2024-01-01', CURRENT_DATE - 10,
   'f6aaaaaa-0003-0000-0000-000000000010'),
  ('f6aaaaaa-0008-0000-0000-000000000002', 'f6aaaaaa-0000-0000-0000-000000000001',
   'f6aaaaaa-0003-0000-0000-000000000011',
   'f6aaaaaa-0007-0000-0000-000000000002',
   'f6aaaaaa-0003-0000-0000-000000000010',
   'PDI antigo', 'active', '2023-01-01', CURRENT_DATE - 80,
   'f6aaaaaa-0003-0000-0000-000000000010');

-- ============================================================================
-- T01 · Colaborador comum bloqueado
-- ============================================================================

SELECT test_login('f6aaaaaa-aaa1-0000-0000-000000000099');

DO $$ DECLARE r JSONB;
BEGIN
  r := rpc_dashboard_drill('ninebox', NULL, 3, 3);
  IF r ->> 'error' <> 'permission_denied' THEN
    RAISE EXCEPTION 'T01 FAIL · veio %', r;
  END IF;
  RAISE NOTICE 'PASS · T01 · colaborador bloqueado';
END $$;

-- ============================================================================
-- T02 · Lider ve scope=hierarchy
-- ============================================================================

SELECT test_login('f6aaaaaa-aaa1-0000-0000-000000000010');

DO $$ DECLARE r JSONB;
BEGIN
  r := rpc_dashboard_drill('ninebox', NULL, 3, 3);
  IF r ->> 'scope' <> 'hierarchy' THEN
    RAISE EXCEPTION 'T02 FAIL · esperava hierarchy · veio %', r ->> 'scope';
  END IF;
  IF (r ->> 'universe_size')::INT <> 2 THEN
    RAISE EXCEPTION 'T02 FAIL · universe esperava 2 · veio %', r ->> 'universe_size';
  END IF;
  RAISE NOTICE 'PASS · T02 · lider scope=hierarchy';
END $$;

-- ============================================================================
-- T03 · ninebox (3,3) · 1 pessoa (A1)
-- ============================================================================

SELECT test_login('f6aaaaaa-aaa1-0000-0000-000000000003');  -- RH

DO $$ DECLARE r JSONB; DECLARE first JSONB;
BEGIN
  r := rpc_dashboard_drill('ninebox', NULL, 3, 3);
  IF r ->> 'scope' <> 'full' THEN
    RAISE EXCEPTION 'T03 FAIL · RH esperava full · veio %', r ->> 'scope';
  END IF;
  IF (r ->> 'count')::INT <> 1 THEN
    RAISE EXCEPTION 'T03 FAIL · esperava 1 · veio %', r ->> 'count';
  END IF;
  first := (r -> 'items') -> 0;
  IF first ->> 'full_name' <> 'COLAB A1 F6 FICHA' THEN
    RAISE EXCEPTION 'T03 FAIL · nome errado · veio %', first ->> 'full_name';
  END IF;
  IF first ->> 'chip_label' <> 'Future Star' THEN
    RAISE EXCEPTION 'T03 FAIL · chip_label esperava Future Star · veio %', first ->> 'chip_label';
  END IF;
  RAISE NOTICE 'PASS · T03 · ninebox (3,3) -> A1 com chip Future Star';
END $$;

-- ============================================================================
-- T04 · ninebox (2,2) · 1 pessoa (A2)
-- ============================================================================

DO $$ DECLARE r JSONB; DECLARE first JSONB;
BEGIN
  r := rpc_dashboard_drill('ninebox', NULL, 2, 2);
  IF (r ->> 'count')::INT <> 1 THEN
    RAISE EXCEPTION 'T04 FAIL · esperava 1 · veio %', r ->> 'count';
  END IF;
  first := (r -> 'items') -> 0;
  IF first ->> 'chip_label' <> 'Mantenedor+' THEN
    RAISE EXCEPTION 'T04 FAIL · chip esperava Mantenedor+';
  END IF;
  RAISE NOTICE 'PASS · T04 · ninebox (2,2) -> A2 com Mantenedor+';
END $$;

-- ============================================================================
-- T05 · ninebox params invalidos
-- ============================================================================

DO $$ DECLARE r JSONB;
BEGIN
  r := rpc_dashboard_drill('ninebox', NULL, NULL, NULL);
  IF r ->> 'error' <> 'invalid_value' THEN
    RAISE EXCEPTION 'T05 FAIL · esperava invalid_value · veio %', r;
  END IF;
  RAISE NOTICE 'PASS · T05 · ninebox sem row/col -> invalid_value';
END $$;

-- ============================================================================
-- T06 · employer_unit · ATP F6 (2 ativos)
-- ============================================================================

DO $$ DECLARE r JSONB;
BEGIN
  -- ATP F6 tem A1 ativo. COLAB_X tambem foi cadastrado ali mas esta desligado, nao conta.
  r := rpc_dashboard_drill('employer_unit', 'f6aaaaaa-0001-0000-0000-000000000001');
  IF (r ->> 'count')::INT <> 1 THEN
    RAISE EXCEPTION 'T06 FAIL · ATP esperava 1 ativo · veio %', r ->> 'count';
  END IF;
  RAISE NOTICE 'PASS · T06 · employer_unit filtra so ativos';
END $$;

-- ============================================================================
-- T07 · employer_unit · Cestao F6
-- ============================================================================

DO $$ DECLARE r JSONB; DECLARE first JSONB;
BEGIN
  r := rpc_dashboard_drill('employer_unit', 'f6aaaaaa-0001-0000-0000-000000000002');
  IF (r ->> 'count')::INT <> 1 THEN
    RAISE EXCEPTION 'T07 FAIL · Cestao esperava 1 · veio %', r ->> 'count';
  END IF;
  first := (r -> 'items') -> 0;
  IF first ->> 'unit_name' <> 'Cestao F6' THEN
    RAISE EXCEPTION 'T07 FAIL · unit_name errado · veio %', first ->> 'unit_name';
  END IF;
  RAISE NOTICE 'PASS · T07 · employer_unit retorna nome correto';
END $$;

-- ============================================================================
-- T08 · department · Operacoes F6
-- ============================================================================

DO $$ DECLARE r JSONB; DECLARE first JSONB;
BEGIN
  r := rpc_dashboard_drill('department', 'f6aaaaaa-0002-0000-0000-000000000001');
  IF (r ->> 'count')::INT <> 1 THEN
    RAISE EXCEPTION 'T08 FAIL · Operacoes esperava 1 · veio %', r ->> 'count';
  END IF;
  first := (r -> 'items') -> 0;
  IF first ->> 'department_name' <> 'Operacoes F6' THEN
    RAISE EXCEPTION 'T08 FAIL · dept name errado';
  END IF;
  RAISE NOTICE 'PASS · T08 · department retorna nome correto';
END $$;

-- ============================================================================
-- T09 · headcount_metric · total_active = 2
-- ============================================================================

DO $$ DECLARE r JSONB;
BEGIN
  r := rpc_dashboard_drill('headcount_metric', 'total_active');
  IF (r ->> 'count')::INT <> 2 THEN
    RAISE EXCEPTION 'T09 FAIL · total_active esperava 2 · veio %', r ->> 'count';
  END IF;
  RAISE NOTICE 'PASS · T09 · headcount total_active';
END $$;

-- ============================================================================
-- T10 · headcount_metric · hired_30d = 1 (A1)
-- ============================================================================

DO $$ DECLARE r JSONB; DECLARE first JSONB;
BEGIN
  r := rpc_dashboard_drill('headcount_metric', 'hired_30d');
  IF (r ->> 'count')::INT <> 1 THEN
    RAISE EXCEPTION 'T10 FAIL · hired_30d esperava 1 · veio %', r ->> 'count';
  END IF;
  first := (r -> 'items') -> 0;
  IF first ->> 'chip_label' <> 'Contratado em 30d' THEN
    RAISE EXCEPTION 'T10 FAIL · chip errado · veio %', first ->> 'chip_label';
  END IF;
  RAISE NOTICE 'PASS · T10 · hired_30d com chip correto';
END $$;

-- ============================================================================
-- T11 · headcount_metric · invalid_metric
-- ============================================================================

DO $$ DECLARE r JSONB;
BEGIN
  r := rpc_dashboard_drill('headcount_metric', 'foobar');
  IF r ->> 'error' <> 'invalid_metric' THEN
    RAISE EXCEPTION 'T11 FAIL · esperava invalid_metric · veio %', r;
  END IF;
  RAISE NOTICE 'PASS · T11 · metrica invalida bloqueada';
END $$;

-- ============================================================================
-- T12 · pdis_by_manager · GER A tem 2 PDIs vencidos
-- ============================================================================

DO $$ DECLARE r JSONB; DECLARE first JSONB;
BEGIN
  r := rpc_dashboard_drill('pdis_by_manager', 'f6aaaaaa-0003-0000-0000-000000000010');
  IF (r ->> 'count')::INT <> 2 THEN
    RAISE EXCEPTION 'T12 FAIL · esperava 2 PDIs · veio %', r ->> 'count';
  END IF;
  first := (r -> 'items') -> 0;
  -- PDI antigo (80d) vem antes (ORDER BY end_date ASC)
  IF first ->> 'objective' <> 'PDI antigo' THEN
    RAISE EXCEPTION 'T12 FAIL · primeiro PDI errado · veio %', first ->> 'objective';
  END IF;
  IF (first ->> 'days_overdue')::INT < 75 THEN
    RAISE EXCEPTION 'T12 FAIL · days_overdue muito baixo · veio %', first ->> 'days_overdue';
  END IF;
  RAISE NOTICE 'PASS · T12 · pdis_by_manager retorna 2 PDIs ordenados';
END $$;

-- ============================================================================
-- T13 · pdis_by_manager para gestor sem PDIs vencidos
-- ============================================================================

DO $$ DECLARE r JSONB;
BEGIN
  -- RH F6 nao tem PDIs como manager_snapshot
  r := rpc_dashboard_drill('pdis_by_manager', 'f6aaaaaa-0003-0000-0000-000000000003');
  IF (r ->> 'count')::INT <> 0 THEN
    RAISE EXCEPTION 'T13 FAIL · esperava 0 · veio %', r ->> 'count';
  END IF;
  RAISE NOTICE 'PASS · T13 · gestor sem PDIs retorna count=0';
END $$;

-- ============================================================================
-- T14 · kind invalido + uuid invalido
-- ============================================================================

DO $$ DECLARE r JSONB;
BEGIN
  r := rpc_dashboard_drill('frobnicate', 'x');
  IF r ->> 'error' <> 'unknown_kind' THEN
    RAISE EXCEPTION 'T14a FAIL · esperava unknown_kind · veio %', r;
  END IF;
  r := rpc_dashboard_drill('employer_unit', 'nao-eh-uuid');
  IF r ->> 'error' <> 'invalid_uuid' THEN
    RAISE EXCEPTION 'T14b FAIL · esperava invalid_uuid · veio %', r;
  END IF;
  RAISE NOTICE 'PASS · T14 · kind/uuid invalidos rejeitados';
END $$;

-- ============================================================================
-- T15 · Isolamento cross-tenant
-- ============================================================================

SELECT test_login('f6aaaaaa-aaa1-0000-0000-000000000088');  -- RH Y

DO $$ DECLARE r JSONB;
BEGIN
  -- Tenta filtrar por unidade do tenant X
  r := rpc_dashboard_drill('employer_unit', 'f6aaaaaa-0001-0000-0000-000000000001');
  IF (r ->> 'count')::INT <> 0 THEN
    RAISE EXCEPTION 'T15 FAIL · RH_Y nao deveria ver pessoas do tenant X · veio %', r ->> 'count';
  END IF;
  -- Mesmo cross-tenant em ninebox
  r := rpc_dashboard_drill('ninebox', NULL, 3, 3);
  IF (r ->> 'count')::INT <> 0 THEN
    RAISE EXCEPTION 'T15 FAIL · cross-tenant em ninebox · veio %', r ->> 'count';
  END IF;
  RAISE NOTICE 'PASS · T15 · isolamento cross-tenant';
END $$;

-- ============================================================================
DO $$ BEGIN
  RAISE NOTICE '========================================';
  RAISE NOTICE '=== F6 · 15 testes executados · OK   ===';
  RAISE NOTICE '========================================';
END $$;

ROLLBACK;

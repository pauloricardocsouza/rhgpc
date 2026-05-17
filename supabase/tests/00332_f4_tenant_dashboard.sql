-- ============================================================================
-- R2 People · Testes Sessao F4 · Tenant Dashboard
-- ============================================================================
-- 14 testes:
--   T01-T03 · escopos: super_admin/diretoria/rh ve 'full' vs lider ve 'hierarchy'
--   T04     · colaborador comum bloqueado
--   T05-T07 · headcount: total ativo, contratados/desligados 30d/90d, by_unit/dept
--   T08-T09 · ninebox_distribution (so finalizadas, ultima por subject)
--   T10-T11 · pdis_overdue_by_manager (agrupa, ordena)
--   T12-T13 · recognition rankings (publicos vs privados conforme role)
--   T14     · isolamento cross-tenant
-- ============================================================================

BEGIN;

-- ----------------------------------------------------------------------------
-- SETUP
-- ----------------------------------------------------------------------------

INSERT INTO tenants (id, slug, legal_name, display_name) VALUES
  ('f4aaaaaa-0000-0000-0000-000000000001', 'tx-f4', 'Tenant X F4', 'X'),
  ('f4aaaaaa-0000-0000-0000-000000000002', 'tx-f4-y', 'Tenant Y F4', 'Y');

INSERT INTO employer_units (id, tenant_id, code, legal_name) VALUES
  ('f4aaaaaa-0001-0000-0000-000000000001', 'f4aaaaaa-0000-0000-0000-000000000001',
   'XEMP1', 'X Emp 1'),
  ('f4aaaaaa-0001-0000-0000-000000000002', 'f4aaaaaa-0000-0000-0000-000000000001',
   'XEMP2', 'X Emp 2');

INSERT INTO departments (id, tenant_id, code, display_name) VALUES
  ('f4aaaaaa-0002-0000-0000-000000000001', 'f4aaaaaa-0000-0000-0000-000000000001',
   'OPS', 'Operacoes'),
  ('f4aaaaaa-0002-0000-0000-000000000002', 'f4aaaaaa-0000-0000-0000-000000000001',
   'FIN', 'Financeiro');

-- Hierarquia:
--   SA, DIR, RH
--   GERENTE_A
--     COLAB_A1, COLAB_A2
--   GERENTE_B (sem subordinados ativos)
--   COLAB_X (sem manager, role colaborador)
--   RH_Y (no tenant Y, cross-tenant)

INSERT INTO app_users (id, tenant_id, auth_user_id, email, full_name, role, manager_id,
                       employer_unit_id, working_unit_id, department_id,
                       employment_link, hired_at) VALUES
  ('f4aaaaaa-0003-0000-0000-000000000001', 'f4aaaaaa-0000-0000-0000-000000000001',
   'f4aaaaaa-aaa1-0000-0000-000000000001', 'sa@f4.test', 'SA F4', 'super_admin', NULL,
   NULL, NULL, NULL, 'clt', '2020-01-01'),
  ('f4aaaaaa-0003-0000-0000-000000000002', 'f4aaaaaa-0000-0000-0000-000000000001',
   'f4aaaaaa-aaa1-0000-0000-000000000002', 'dir@f4.test', 'DIR F4', 'diretoria', NULL,
   NULL, NULL, NULL, 'clt', '2020-01-01'),
  ('f4aaaaaa-0003-0000-0000-000000000003', 'f4aaaaaa-0000-0000-0000-000000000001',
   'f4aaaaaa-aaa1-0000-0000-000000000003', 'rh@f4.test', 'RH F4', 'rh', NULL,
   NULL, NULL, NULL, 'clt', '2020-01-01'),
  ('f4aaaaaa-0003-0000-0000-000000000010', 'f4aaaaaa-0000-0000-0000-000000000001',
   'f4aaaaaa-aaa1-0000-0000-000000000010', 'gera@f4.test', 'GER A F4', 'lider', NULL,
   'f4aaaaaa-0001-0000-0000-000000000001', NULL, 'f4aaaaaa-0002-0000-0000-000000000001',
   'clt', '2020-01-01'),
  ('f4aaaaaa-0003-0000-0000-000000000011', 'f4aaaaaa-0000-0000-0000-000000000001',
   'f4aaaaaa-aaa1-0000-0000-000000000011', 'colaba1@f4.test', 'COLAB A1 F4', 'colaborador',
   'f4aaaaaa-0003-0000-0000-000000000010',
   'f4aaaaaa-0001-0000-0000-000000000001', NULL, 'f4aaaaaa-0002-0000-0000-000000000001',
   'clt', '2024-12-01'),
  ('f4aaaaaa-0003-0000-0000-000000000012', 'f4aaaaaa-0000-0000-0000-000000000001',
   'f4aaaaaa-aaa1-0000-0000-000000000012', 'colaba2@f4.test', 'COLAB A2 F4', 'colaborador',
   'f4aaaaaa-0003-0000-0000-000000000010',
   'f4aaaaaa-0001-0000-0000-000000000002', NULL, 'f4aaaaaa-0002-0000-0000-000000000002',
   'clt', '2021-01-01'),
  ('f4aaaaaa-0003-0000-0000-000000000020', 'f4aaaaaa-0000-0000-0000-000000000001',
   'f4aaaaaa-aaa1-0000-0000-000000000020', 'gerb@f4.test', 'GER B F4', 'lider', NULL,
   'f4aaaaaa-0001-0000-0000-000000000002', NULL, NULL,
   'clt', '2020-01-01'),
  ('f4aaaaaa-0003-0000-0000-000000000099', 'f4aaaaaa-0000-0000-0000-000000000001',
   'f4aaaaaa-aaa1-0000-0000-000000000099', 'colabx@f4.test', 'COLAB X F4', 'colaborador',
   NULL, NULL, NULL, NULL, 'clt', '2021-01-01'),
  ('f4aaaaaa-0003-0000-0000-000000000088', 'f4aaaaaa-0000-0000-0000-000000000002',
   'f4aaaaaa-aaa1-0000-0000-000000000088', 'rhy@f4.test', 'RH Y F4', 'rh', NULL,
   NULL, NULL, NULL, 'clt', '2020-01-01');

-- Fichas para ter dados de headcount
INSERT INTO employees (id, tenant_id, full_name, job_title, hire_date, termination_date,
                       cpf, employer_unit_id, department_id, created_by) VALUES
  ('f4aaaaaa-0004-0000-0000-000000000011', 'f4aaaaaa-0000-0000-0000-000000000001',
   'COLAB A1 F4 FICHA', 'Op', CURRENT_DATE - 20, NULL, '40111111111',
   'f4aaaaaa-0001-0000-0000-000000000001', 'f4aaaaaa-0002-0000-0000-000000000001',
   'f4aaaaaa-0003-0000-0000-000000000003'),
  ('f4aaaaaa-0004-0000-0000-000000000012', 'f4aaaaaa-0000-0000-0000-000000000001',
   'COLAB A2 F4 FICHA', 'Op', '2021-01-01', NULL, '40222222222',
   'f4aaaaaa-0001-0000-0000-000000000002', 'f4aaaaaa-0002-0000-0000-000000000002',
   'f4aaaaaa-0003-0000-0000-000000000003'),
  -- COLAB_X: desligado ha 40 dias (entra em terminated_90d mas nao 30d)
  ('f4aaaaaa-0004-0000-0000-000000000099', 'f4aaaaaa-0000-0000-0000-000000000001',
   'COLAB X F4 FICHA', 'Op', '2021-01-01', CURRENT_DATE - 40, '40999999999',
   'f4aaaaaa-0001-0000-0000-000000000001', NULL,
   'f4aaaaaa-0003-0000-0000-000000000003');

UPDATE app_users SET employee_id = 'f4aaaaaa-0004-0000-0000-000000000011' WHERE id = 'f4aaaaaa-0003-0000-0000-000000000011';
UPDATE app_users SET employee_id = 'f4aaaaaa-0004-0000-0000-000000000012' WHERE id = 'f4aaaaaa-0003-0000-0000-000000000012';
UPDATE app_users SET employee_id = 'f4aaaaaa-0004-0000-0000-000000000099' WHERE id = 'f4aaaaaa-0003-0000-0000-000000000099';

-- Ciclo 9-Box e 2 avaliacoes finalizadas
INSERT INTO ninebox_cycles (id, tenant_id, name, status, start_date, end_date, created_by) VALUES
  ('f4aaaaaa-0005-0000-0000-000000000001', 'f4aaaaaa-0000-0000-0000-000000000001',
   'Ciclo F4', 'active', '2024-01-01', '2024-12-31',
   'f4aaaaaa-0003-0000-0000-000000000003');

INSERT INTO ninebox_evaluations (id, tenant_id, subject_id, manager_id, cycle_id,
                                  is_adhoc, status,
                                  grid_size_snapshot, potential_criteria_snapshot,
                                  performance_criteria_snapshot, box_labels_snapshot,
                                  final_box_row, final_box_col, final_box_label,
                                  finalized_at, created_by) VALUES
  ('f4aaaaaa-0006-0000-0000-000000000001', 'f4aaaaaa-0000-0000-0000-000000000001',
   'f4aaaaaa-0003-0000-0000-000000000011',
   'f4aaaaaa-0003-0000-0000-000000000010',
   'f4aaaaaa-0005-0000-0000-000000000001',
   FALSE, 'finalized',
   '3x3', '[]'::jsonb, '[]'::jsonb, '[]'::jsonb,
   3, 3, 'Future Star', now() - INTERVAL '10 days',
   'f4aaaaaa-0003-0000-0000-000000000010'),
  ('f4aaaaaa-0006-0000-0000-000000000002', 'f4aaaaaa-0000-0000-0000-000000000001',
   'f4aaaaaa-0003-0000-0000-000000000012',
   'f4aaaaaa-0003-0000-0000-000000000010',
   'f4aaaaaa-0005-0000-0000-000000000001',
   FALSE, 'finalized',
   '3x3', '[]'::jsonb, '[]'::jsonb, '[]'::jsonb,
   2, 2, 'Mantenedor+', now() - INTERVAL '5 days',
   'f4aaaaaa-0003-0000-0000-000000000010');

-- 2 ciclos PDI · um ativo, outro para o segundo PDI atrasado
INSERT INTO pdi_cycles (id, tenant_id, code, display_name, start_date, end_date, active) VALUES
  ('f4aaaaaa-0007-0000-0000-000000000001', 'f4aaaaaa-0000-0000-0000-000000000001',
   'PDI2024F4', 'PDI 2024', '2024-01-01', '2024-12-31', TRUE),
  ('f4aaaaaa-0007-0000-0000-000000000002', 'f4aaaaaa-0000-0000-0000-000000000001',
   'PDI2023F4', 'PDI 2023', '2023-01-01', '2023-12-31', FALSE);

-- 2 PDIs em atraso de COLAB_A1 (em ciclos diferentes pra nao bater constraint)
INSERT INTO pdis (id, tenant_id, user_id, cycle_id, manager_id_snapshot,
                  objective, status, start_date, end_date, created_by) VALUES
  ('f4aaaaaa-0008-0000-0000-000000000001', 'f4aaaaaa-0000-0000-0000-000000000001',
   'f4aaaaaa-0003-0000-0000-000000000011',
   'f4aaaaaa-0007-0000-0000-000000000001',
   'f4aaaaaa-0003-0000-0000-000000000010',
   'PDI 1 atrasado', 'active', '2024-01-01', CURRENT_DATE - 15,
   'f4aaaaaa-0003-0000-0000-000000000010'),
  ('f4aaaaaa-0008-0000-0000-000000000002', 'f4aaaaaa-0000-0000-0000-000000000001',
   'f4aaaaaa-0003-0000-0000-000000000011',
   'f4aaaaaa-0007-0000-0000-000000000002',
   'f4aaaaaa-0003-0000-0000-000000000010',
   'PDI antigo', 'active', '2023-01-01', CURRENT_DATE - 100,
   'f4aaaaaa-0003-0000-0000-000000000010');

-- Reconhecimentos
INSERT INTO recognitions (id, tenant_id, sender_id, recipient_id, message, is_private, created_at) VALUES
  -- COLAB_A1 recebe 2 publicos
  ('f4aaaaaa-0009-0000-0000-000000000001', 'f4aaaaaa-0000-0000-0000-000000000001',
   'f4aaaaaa-0003-0000-0000-000000000010', 'f4aaaaaa-0003-0000-0000-000000000011',
   'Otimo trabalho 1', FALSE, now() - INTERVAL '5 days'),
  ('f4aaaaaa-0009-0000-0000-000000000002', 'f4aaaaaa-0000-0000-0000-000000000001',
   'f4aaaaaa-0003-0000-0000-000000000010', 'f4aaaaaa-0003-0000-0000-000000000011',
   'Otimo trabalho 2', FALSE, now() - INTERVAL '10 days'),
  -- COLAB_A1 recebe 1 privado de GERENTE_B
  ('f4aaaaaa-0009-0000-0000-000000000003', 'f4aaaaaa-0000-0000-0000-000000000001',
   'f4aaaaaa-0003-0000-0000-000000000020', 'f4aaaaaa-0003-0000-0000-000000000011',
   'Mentoria privada', TRUE, now() - INTERVAL '15 days'),
  -- COLAB_A2 recebe 1 publico
  ('f4aaaaaa-0009-0000-0000-000000000004', 'f4aaaaaa-0000-0000-0000-000000000001',
   'f4aaaaaa-0003-0000-0000-000000000010', 'f4aaaaaa-0003-0000-0000-000000000012',
   'Bom', FALSE, now() - INTERVAL '7 days');

-- ============================================================================
-- T01 · super_admin ve scope=full
-- ============================================================================

SELECT test_login('f4aaaaaa-aaa1-0000-0000-000000000001');

DO $$
DECLARE r JSONB;
BEGIN
  r := rpc_tenant_dashboard();
  IF (r ->> 'ok')::BOOLEAN <> TRUE THEN
    RAISE EXCEPTION 'T01 FAIL · r=%', r;
  END IF;
  IF r ->> 'scope' <> 'full' THEN
    RAISE EXCEPTION 'T01 FAIL · esperava scope=full · veio %', r ->> 'scope';
  END IF;
  -- 8 app_users ativos no tenant X (SA, DIR, RH, GER_A, COLAB_A1, COLAB_A2, GER_B, COLAB_X)
  IF (r ->> 'universe_size')::INT <> 8 THEN
    RAISE EXCEPTION 'T01 FAIL · universe_size esperava 8 · veio %', r ->> 'universe_size';
  END IF;
  RAISE NOTICE 'PASS · T01 · super_admin ve scope=full universe=8';
END $$;

-- ============================================================================
-- T02 · diretoria + rh tambem veem scope=full
-- ============================================================================

SELECT test_login('f4aaaaaa-aaa1-0000-0000-000000000002');  -- DIR

DO $$
DECLARE r JSONB;
BEGIN
  r := rpc_tenant_dashboard();
  IF r ->> 'scope' <> 'full' THEN
    RAISE EXCEPTION 'T02 FAIL · diretoria esperava full · veio %', r ->> 'scope';
  END IF;
END $$;

SELECT test_login('f4aaaaaa-aaa1-0000-0000-000000000003');  -- RH

DO $$
DECLARE r JSONB;
BEGIN
  r := rpc_tenant_dashboard();
  IF r ->> 'scope' <> 'full' THEN
    RAISE EXCEPTION 'T02 FAIL · rh esperava full · veio %', r ->> 'scope';
  END IF;
  RAISE NOTICE 'PASS · T02 · diretoria + rh veem scope=full';
END $$;

-- ============================================================================
-- T03 · lider GERENTE_A ve scope=hierarchy com 2 subordinados
-- ============================================================================

SELECT test_login('f4aaaaaa-aaa1-0000-0000-000000000010');

DO $$
DECLARE r JSONB;
BEGIN
  r := rpc_tenant_dashboard();
  IF r ->> 'scope' <> 'hierarchy' THEN
    RAISE EXCEPTION 'T03 FAIL · lider esperava hierarchy · veio %', r ->> 'scope';
  END IF;
  IF (r ->> 'universe_size')::INT <> 2 THEN
    RAISE EXCEPTION 'T03 FAIL · universe_size esperava 2 · veio %', r ->> 'universe_size';
  END IF;
  RAISE NOTICE 'PASS · T03 · lider ve scope=hierarchy com 2 subordinados';
END $$;

-- ============================================================================
-- T04 · colaborador comum bloqueado
-- ============================================================================

SELECT test_login('f4aaaaaa-aaa1-0000-0000-000000000099');  -- COLAB_X

DO $$
DECLARE r JSONB;
BEGIN
  r := rpc_tenant_dashboard();
  IF r ->> 'error' <> 'permission_denied' THEN
    RAISE EXCEPTION 'T04 FAIL · esperava permission_denied · veio %', r;
  END IF;
  RAISE NOTICE 'PASS · T04 · colaborador comum bloqueado';
END $$;

-- ============================================================================
-- T05 · headcount total_active
-- ============================================================================

SELECT test_login('f4aaaaaa-aaa1-0000-0000-000000000003');  -- RH

DO $$
DECLARE r JSONB;
DECLARE h JSONB;
BEGIN
  r := rpc_tenant_dashboard();
  h := r -> 'headcount';
  -- 2 fichas ativas (COLAB_A1, COLAB_A2) + 1 desligada (COLAB_X)
  IF (h ->> 'total_active')::INT <> 2 THEN
    RAISE EXCEPTION 'T05 FAIL · total_active esperava 2 · veio %', h ->> 'total_active';
  END IF;
  IF (h ->> 'total_terminated')::INT <> 1 THEN
    RAISE EXCEPTION 'T05 FAIL · total_terminated esperava 1 · veio %', h ->> 'total_terminated';
  END IF;
  RAISE NOTICE 'PASS · T05 · headcount total_active=2 total_terminated=1';
END $$;

-- ============================================================================
-- T06 · headcount temporal · hired_30d e terminated_90d
-- ============================================================================

DO $$
DECLARE r JSONB;
DECLARE h JSONB;
BEGIN
  r := rpc_tenant_dashboard();
  h := r -> 'headcount';
  -- COLAB_A1 contratado ha 20d entra em hired_30d
  IF (h ->> 'hired_30d')::INT <> 1 THEN
    RAISE EXCEPTION 'T06 FAIL · hired_30d esperava 1 · veio %', h ->> 'hired_30d';
  END IF;
  -- COLAB_X desligado ha 40d entra em 90d mas nao em 30d
  IF (h ->> 'terminated_30d')::INT <> 0 THEN
    RAISE EXCEPTION 'T06 FAIL · terminated_30d esperava 0 · veio %', h ->> 'terminated_30d';
  END IF;
  IF (h ->> 'terminated_90d')::INT <> 1 THEN
    RAISE EXCEPTION 'T06 FAIL · terminated_90d esperava 1 · veio %', h ->> 'terminated_90d';
  END IF;
  RAISE NOTICE 'PASS · T06 · headcount temporal: hired_30d=1 terminated_90d=1';
END $$;

-- ============================================================================
-- T07 · by_employer_unit retorna agregacao
-- ============================================================================

DO $$
DECLARE r JSONB;
DECLARE units JSONB;
DECLARE total INT := 0;
DECLARE item JSONB;
BEGIN
  r := rpc_tenant_dashboard();
  units := r -> 'headcount' -> 'by_employer_unit';
  IF jsonb_array_length(units) <> 2 THEN
    RAISE EXCEPTION 'T07 FAIL · esperava 2 unidades · veio %', jsonb_array_length(units);
  END IF;
  FOR item IN SELECT * FROM jsonb_array_elements(units) LOOP
    total := total + (item ->> 'count')::INT;
  END LOOP;
  IF total <> 2 THEN
    RAISE EXCEPTION 'T07 FAIL · soma esperava 2 (ativos) · veio %', total;
  END IF;
  RAISE NOTICE 'PASS · T07 · by_employer_unit agrega corretamente';
END $$;

-- ============================================================================
-- T08 · ninebox_distribution agrega ultimas avaliacoes
-- ============================================================================

DO $$
DECLARE r JSONB;
DECLARE boxes JSONB;
DECLARE total INT := 0;
DECLARE item JSONB;
BEGIN
  r := rpc_tenant_dashboard();
  boxes := r -> 'ninebox_distribution';
  IF jsonb_array_length(boxes) <> 2 THEN
    RAISE EXCEPTION 'T08 FAIL · esperava 2 boxes distintas · veio %', jsonb_array_length(boxes);
  END IF;
  FOR item IN SELECT * FROM jsonb_array_elements(boxes) LOOP
    total := total + (item ->> 'count')::INT;
  END LOOP;
  IF total <> 2 THEN
    RAISE EXCEPTION 'T08 FAIL · total avaliados esperava 2 · veio %', total;
  END IF;
  RAISE NOTICE 'PASS · T08 · ninebox_distribution agrega 2 avaliacoes em 2 boxes';
END $$;

-- ============================================================================
-- T09 · ninebox so pega ultima finalizada por subject
-- ============================================================================

-- Adiciona uma 2a avaliacao para COLAB_A1 em outra caixa, mais recente
INSERT INTO ninebox_evaluations (id, tenant_id, subject_id, manager_id, cycle_id,
                                  is_adhoc, status,
                                  grid_size_snapshot, potential_criteria_snapshot,
                                  performance_criteria_snapshot, box_labels_snapshot,
                                  final_box_row, final_box_col, final_box_label,
                                  finalized_at, created_by) VALUES
  ('f4aaaaaa-0006-0000-0000-000000000003', 'f4aaaaaa-0000-0000-0000-000000000001',
   'f4aaaaaa-0003-0000-0000-000000000011',
   'f4aaaaaa-0003-0000-0000-000000000010',
   NULL,  -- adhoc, sem ciclo
   TRUE, 'finalized',
   '3x3', '[]'::jsonb, '[]'::jsonb, '[]'::jsonb,
   1, 1, 'Insuficiente', now() - INTERVAL '1 day',
   'f4aaaaaa-0003-0000-0000-000000000010');

DO $$
DECLARE r JSONB;
DECLARE boxes JSONB;
DECLARE has_insuf BOOLEAN := FALSE;
DECLARE has_future BOOLEAN := FALSE;
DECLARE item JSONB;
BEGIN
  r := rpc_tenant_dashboard();
  boxes := r -> 'ninebox_distribution';
  FOR item IN SELECT * FROM jsonb_array_elements(boxes) LOOP
    IF item ->> 'box_label' = 'Insuficiente' THEN has_insuf := TRUE; END IF;
    IF item ->> 'box_label' = 'Future Star' THEN has_future := TRUE; END IF;
  END LOOP;
  -- A nova adhoc (Insuficiente) deve substituir a antiga de COLAB_A1 (Future Star)
  IF NOT has_insuf THEN
    RAISE EXCEPTION 'T09 FAIL · esperava Insuficiente apos nova avaliacao';
  END IF;
  IF has_future THEN
    RAISE EXCEPTION 'T09 FAIL · Future Star nao deveria mais aparecer (substituida)';
  END IF;
  RAISE NOTICE 'PASS · T09 · ninebox usa a ultima finalizada por subject';
END $$;

-- ============================================================================
-- T10 · pdis_overdue_by_manager · agrupa por gestor
-- ============================================================================

DO $$
DECLARE r JSONB;
DECLARE pdis JSONB;
DECLARE first_mgr JSONB;
BEGIN
  r := rpc_tenant_dashboard();
  pdis := r -> 'pdis_overdue_by_manager';
  IF jsonb_array_length(pdis) <> 1 THEN
    RAISE EXCEPTION 'T10 FAIL · esperava 1 gestor · veio %', jsonb_array_length(pdis);
  END IF;
  first_mgr := pdis -> 0;
  IF (first_mgr ->> 'overdue_count')::INT <> 2 THEN
    RAISE EXCEPTION 'T10 FAIL · overdue_count esperava 2 · veio %', first_mgr ->> 'overdue_count';
  END IF;
  IF first_mgr ->> 'manager_name' <> 'GER A F4' THEN
    RAISE EXCEPTION 'T10 FAIL · gestor esperava GER A F4 · veio %', first_mgr ->> 'manager_name';
  END IF;
  RAISE NOTICE 'PASS · T10 · pdis_overdue_by_manager agrupa por gestor (GER A com 2)';
END $$;

-- ============================================================================
-- T11 · pdis_overdue_by_manager · worst_overdue_days
-- ============================================================================

DO $$
DECLARE r JSONB;
DECLARE first_mgr JSONB;
BEGIN
  r := rpc_tenant_dashboard();
  first_mgr := r -> 'pdis_overdue_by_manager' -> 0;
  -- PDI mais antigo eh CURRENT_DATE - 100, entao worst >= 100
  IF (first_mgr ->> 'worst_overdue_days')::INT < 95 THEN
    RAISE EXCEPTION 'T11 FAIL · worst_overdue_days esperava ~100 · veio %', first_mgr ->> 'worst_overdue_days';
  END IF;
  RAISE NOTICE 'PASS · T11 · worst_overdue_days captura o pior caso';
END $$;

-- ============================================================================
-- T12 · RH ve privados nos rankings
-- ============================================================================

DO $$
DECLARE r JSONB;
DECLARE top1 JSONB;
BEGIN
  r := rpc_tenant_dashboard();
  top1 := r -> 'recognition_top_recipients' -> 0;
  -- COLAB_A1 tem 2 publicos + 1 privado = 3
  IF (top1 ->> 'total')::INT <> 3 THEN
    RAISE EXCEPTION 'T12 FAIL · RH esperava 3 · veio %', top1 ->> 'total';
  END IF;
  IF (top1 ->> 'private_count')::INT <> 1 THEN
    RAISE EXCEPTION 'T12 FAIL · private_count esperava 1 · veio %', top1 ->> 'private_count';
  END IF;
  RAISE NOTICE 'PASS · T12 · RH ve total=3 com 1 privado';
END $$;

-- ============================================================================
-- T13 · Lider so ve seu escopo nos rankings
-- ============================================================================

SELECT test_login('f4aaaaaa-aaa1-0000-0000-000000000010');  -- GER A

DO $$
DECLARE r JSONB;
DECLARE recipients JSONB;
BEGIN
  r := rpc_tenant_dashboard();
  recipients := r -> 'recognition_top_recipients';
  -- GER A so ve seus 2 subordinados nos rankings
  -- COLAB_A1 e COLAB_A2 ambos com reconhecimentos publicos no escopo
  IF jsonb_array_length(recipients) <> 2 THEN
    RAISE EXCEPTION 'T13 FAIL · lider esperava 2 recipients · veio %', jsonb_array_length(recipients);
  END IF;
  RAISE NOTICE 'PASS · T13 · lider so ve recipients da sua subarvore';
END $$;

-- ============================================================================
-- T14 · Isolamento cross-tenant
-- ============================================================================

SELECT test_login('f4aaaaaa-aaa1-0000-0000-000000000088');  -- RH_Y (tenant Y)

DO $$
DECLARE r JSONB;
BEGIN
  r := rpc_tenant_dashboard();
  -- RH do tenant Y nao tem ninguem (universo_size deve ser 1 apenas ele se ativo, ou 0)
  -- Verificamos que nao vaza nada do tenant X
  IF (r ->> 'universe_size')::INT >= 5 THEN
    RAISE EXCEPTION 'T14 FAIL · RH_Y nao deveria ver universo grande · veio %', r ->> 'universe_size';
  END IF;
  -- E nenhum dado do tenant X
  IF jsonb_array_length(r -> 'pdis_overdue_by_manager') <> 0 THEN
    RAISE EXCEPTION 'T14 FAIL · RH_Y nao deveria ver pdis · veio %',
      jsonb_array_length(r -> 'pdis_overdue_by_manager');
  END IF;
  RAISE NOTICE 'PASS · T14 · isolamento cross-tenant ok';
END $$;

-- ============================================================================
-- FECHAMENTO
-- ============================================================================

DO $$
BEGIN
  RAISE NOTICE '========================================';
  RAISE NOTICE '=== F4 · 14 testes executados · OK   ===';
  RAISE NOTICE '========================================';
END $$;

ROLLBACK;

-- ============================================================================
-- R2 People · Testes Sessao F1 · Gestao por pessoa + Minha equipe
-- ============================================================================
-- 18 testes cobrindo:
--   T01-T02 · helper can_view_gestao_for_app_user
--   T03-T07 · rpc_employees_gestao_summary (permissoes)
--   T08-T11 · payload structure (todas as 4 secoes presentes)
--   T12-T14 · cross-tenant + edge cases
--   T15-T18 · rpc_my_team (diretos, indiretos, KPIs)
-- ============================================================================

BEGIN;

-- ----------------------------------------------------------------------------
-- SETUP
-- ----------------------------------------------------------------------------

INSERT INTO tenants (id, slug, legal_name, display_name) VALUES
  ('f1aaaaaa-0000-0000-0000-000000000001', 'tx-f1', 'Tenant X F1', 'X'),
  ('f1aaaaaa-0000-0000-0000-000000000002', 'ty-f1', 'Tenant Y F1', 'Y');

INSERT INTO employer_units (id, tenant_id, code, legal_name) VALUES
  ('f1aaaaaa-0001-0000-0000-000000000001', 'f1aaaaaa-0000-0000-0000-000000000001', 'XEMP', 'X Emp');

INSERT INTO working_units (id, tenant_id, employer_unit_id, code, display_name) VALUES
  ('f1aaaaaa-0002-0000-0000-000000000001', 'f1aaaaaa-0000-0000-0000-000000000001',
   'f1aaaaaa-0001-0000-0000-000000000001', 'XWU', 'X WU');

INSERT INTO departments (id, tenant_id, code, display_name) VALUES
  ('f1aaaaaa-0003-0000-0000-000000000001', 'f1aaaaaa-0000-0000-0000-000000000001', 'OPS', 'OPS');

-- Hierarquia:
--   SA (super_admin)
--   DIR_X (diretoria, tenant X)
--   RH_X (rh, tenant X)
--   GERENTE_X (lider, tenant X)
--     SUB1_X (colaborador, gerenciado por GERENTE_X)
--     SUB2_X (colaborador, gerenciado por GERENTE_X)
--       NETO_X (colaborador, gerenciado por SUB2 · subordinado indireto de GERENTE)
--   OUTRO_X (colaborador sem gerente, mesmo tenant)
--   RH_Y (rh, tenant Y · cross-tenant)

INSERT INTO app_users (id, tenant_id, auth_user_id, email, full_name, role, manager_id, employment_link, hired_at) VALUES
  ('f1aaaaaa-0004-0000-0000-000000000001', 'f1aaaaaa-0000-0000-0000-000000000001',
   'f1aaa999-aaaa-0000-0000-000000000001', 'sa@f1.test', 'SA-F1', 'super_admin', NULL, 'clt', '2020-01-01'),
  ('f1aaaaaa-0004-0000-0000-000000000002', 'f1aaaaaa-0000-0000-0000-000000000001',
   'f1aaa999-aaaa-0000-0000-000000000002', 'dir@x.test', 'DIR-X', 'diretoria', NULL, 'clt', '2020-01-01'),
  ('f1aaaaaa-0004-0000-0000-000000000003', 'f1aaaaaa-0000-0000-0000-000000000001',
   'f1aaa999-aaaa-0000-0000-000000000003', 'rh@x.test', 'RH-X', 'rh', NULL, 'clt', '2020-01-01'),
  ('f1aaaaaa-0004-0000-0000-000000000010', 'f1aaaaaa-0000-0000-0000-000000000001',
   'f1aaa999-aaaa-0000-0000-000000000010', 'gerente@x.test', 'GERENTE-X', 'lider',
   'f1aaaaaa-0004-0000-0000-000000000002', 'clt', '2020-01-01'),
  ('f1aaaaaa-0004-0000-0000-000000000011', 'f1aaaaaa-0000-0000-0000-000000000001',
   'f1aaa999-aaaa-0000-0000-000000000011', 'sub1@x.test', 'SUB1-X', 'colaborador',
   'f1aaaaaa-0004-0000-0000-000000000010', 'clt', '2021-01-01'),
  ('f1aaaaaa-0004-0000-0000-000000000012', 'f1aaaaaa-0000-0000-0000-000000000001',
   'f1aaa999-aaaa-0000-0000-000000000012', 'sub2@x.test', 'SUB2-X', 'lider',
   'f1aaaaaa-0004-0000-0000-000000000010', 'clt', '2021-01-01'),
  ('f1aaaaaa-0004-0000-0000-000000000013', 'f1aaaaaa-0000-0000-0000-000000000001',
   'f1aaa999-aaaa-0000-0000-000000000013', 'neto@x.test', 'NETO-X', 'colaborador',
   'f1aaaaaa-0004-0000-0000-000000000012', 'clt', '2022-01-01'),
  ('f1aaaaaa-0004-0000-0000-000000000020', 'f1aaaaaa-0000-0000-0000-000000000001',
   'f1aaa999-aaaa-0000-0000-000000000020', 'outro@x.test', 'OUTRO-X', 'colaborador',
   NULL, 'clt', '2021-01-01'),
  ('f1aaaaaa-0004-0000-0000-000000000099', 'f1aaaaaa-0000-0000-0000-000000000002',
   'f1aaa999-aaaa-0000-0000-000000000099', 'rh@y.test', 'RH-Y', 'rh', NULL, 'clt', '2020-01-01');

-- Cria fichas (employees) para SUB1 e SUB2 (linkadas via app_users.employee_id)
INSERT INTO employees (id, tenant_id, full_name, job_title, hire_date, cpf, created_by) VALUES
  ('f1aaaaaa-0005-0000-0000-000000000011', 'f1aaaaaa-0000-0000-0000-000000000001',
   'SUB1 X FICHA', 'Op', '2021-01-01', '11111111111',
   'f1aaaaaa-0004-0000-0000-000000000003'),
  ('f1aaaaaa-0005-0000-0000-000000000012', 'f1aaaaaa-0000-0000-0000-000000000001',
   'SUB2 X FICHA', 'Lider', '2021-01-01', '22222222222',
   'f1aaaaaa-0004-0000-0000-000000000003'),
  ('f1aaaaaa-0005-0000-0000-000000000013', 'f1aaaaaa-0000-0000-0000-000000000001',
   'NETO X FICHA', 'Op', '2022-01-01', '33333333333',
   'f1aaaaaa-0004-0000-0000-000000000003');

UPDATE app_users SET employee_id = 'f1aaaaaa-0005-0000-0000-000000000011'
  WHERE id = 'f1aaaaaa-0004-0000-0000-000000000011';
UPDATE app_users SET employee_id = 'f1aaaaaa-0005-0000-0000-000000000012'
  WHERE id = 'f1aaaaaa-0004-0000-0000-000000000012';
UPDATE app_users SET employee_id = 'f1aaaaaa-0005-0000-0000-000000000013'
  WHERE id = 'f1aaaaaa-0004-0000-0000-000000000013';

-- Ficha sem app_user vinculado (para T13)
INSERT INTO employees (id, tenant_id, full_name, job_title, hire_date, cpf, created_by) VALUES
  ('f1aaaaaa-0005-0000-0000-000000000099', 'f1aaaaaa-0000-0000-0000-000000000001',
   'SEM USUARIO', 'Op', '2023-01-01', '99999999999',
   'f1aaaaaa-0004-0000-0000-000000000003');

-- Seed minimo de modulos
-- 1 ninebox cycle ativo
INSERT INTO ninebox_cycles (id, tenant_id, name, status, start_date, end_date, created_by)
VALUES (
  'f1aaaaaa-0006-0000-0000-000000000001',
  'f1aaaaaa-0000-0000-0000-000000000001',
  'Ciclo F1 2024',
  'active',
  '2024-01-01',
  '2024-12-31',
  'f1aaaaaa-0004-0000-0000-000000000003'
);

-- 1 avaliacao finalizada de SUB1 por GERENTE_X
INSERT INTO ninebox_evaluations (
  id, tenant_id, subject_id, manager_id, cycle_id, is_adhoc, status,
  grid_size_snapshot, potential_criteria_snapshot, performance_criteria_snapshot, box_labels_snapshot,
  final_box_row, final_box_col, final_box_label, finalized_at, created_by
) VALUES (
  'f1aaaaaa-0007-0000-0000-000000000001',
  'f1aaaaaa-0000-0000-0000-000000000001',
  'f1aaaaaa-0004-0000-0000-000000000011',
  'f1aaaaaa-0004-0000-0000-000000000010',
  'f1aaaaaa-0006-0000-0000-000000000001',
  FALSE, 'finalized',
  '3x3', '[]'::jsonb, '[]'::jsonb, '[]'::jsonb,
  2, 2, 'Mantenedor', now() - INTERVAL '5 days',
  'f1aaaaaa-0004-0000-0000-000000000010'
);

-- 1 PDI ativo de SUB1
INSERT INTO pdi_cycles (id, tenant_id, code, display_name, start_date, end_date, active) VALUES
  ('f1aaaaaa-0008-0000-0000-000000000001', 'f1aaaaaa-0000-0000-0000-000000000001',
   'PDI2024', 'PDI 2024', '2024-01-01', '2024-12-31', TRUE);

INSERT INTO pdis (id, tenant_id, user_id, cycle_id, manager_id_snapshot,
                  objective, status, start_date, end_date, created_by)
VALUES (
  'f1aaaaaa-0009-0000-0000-000000000001',
  'f1aaaaaa-0000-0000-0000-000000000001',
  'f1aaaaaa-0004-0000-0000-000000000011',
  'f1aaaaaa-0008-0000-0000-000000000001',
  'f1aaaaaa-0004-0000-0000-000000000010',
  'Aprimorar comunicacao',
  'active',
  '2024-01-01', '2024-12-31',
  'f1aaaaaa-0004-0000-0000-000000000010'
);

-- 2 reconhecimentos para SUB1 (1 publico, 1 privado)
INSERT INTO recognitions (id, tenant_id, sender_id, recipient_id, message, is_private)
VALUES
  ('f1aaaaaa-000a-0000-0000-000000000001', 'f1aaaaaa-0000-0000-0000-000000000001',
   'f1aaaaaa-0004-0000-0000-000000000010', 'f1aaaaaa-0004-0000-0000-000000000011',
   'Excelente trabalho no projeto X', FALSE),
  ('f1aaaaaa-000a-0000-0000-000000000002', 'f1aaaaaa-0000-0000-0000-000000000001',
   'f1aaaaaa-0004-0000-0000-000000000020', 'f1aaaaaa-0004-0000-0000-000000000011',
   'Reconhecimento privado de mentoring', TRUE);

-- 1 onboarding de SUB1
INSERT INTO onboardings (id, tenant_id, user_id, manager_id_snapshot, display_name,
                         status, start_date, target_end_date, created_by)
VALUES (
  'f1aaaaaa-000b-0000-0000-000000000001',
  'f1aaaaaa-0000-0000-0000-000000000001',
  'f1aaaaaa-0004-0000-0000-000000000011',
  'f1aaaaaa-0004-0000-0000-000000000010',
  'Onboarding SUB1',
  'completed',
  '2021-01-01',
  '2021-03-01',
  'f1aaaaaa-0004-0000-0000-000000000003'
);

-- ============================================================================
-- T01-T02 · Helper can_view_gestao_for_app_user
-- ============================================================================

SELECT test_login('f1aaa999-aaaa-0000-0000-000000000010');  -- GERENTE-X

DO $$
BEGIN
  IF NOT can_view_gestao_for_app_user('f1aaaaaa-0004-0000-0000-000000000011') THEN
    RAISE EXCEPTION 'T01 FAIL · GERENTE deveria ver gestao de seu subordinado direto';
  END IF;
  RAISE NOTICE 'PASS · T01 · gerente direto pode ver gestao do subordinado';

  IF can_view_gestao_for_app_user('f1aaaaaa-0004-0000-0000-000000000013') THEN
    RAISE EXCEPTION 'T02 FAIL · GERENTE NAO deveria ver gestao do NETO (subordinado indireto)';
  END IF;
  RAISE NOTICE 'PASS · T02 · gerente NAO ve subordinado indireto via permissao direta';
END $$;

-- ============================================================================
-- T03 · Colaborador comum NAO ve gestao de outro
-- ============================================================================

SELECT test_login('f1aaa999-aaaa-0000-0000-000000000020');  -- OUTRO-X (sem manager, colaborador)

DO $$
DECLARE r JSONB;
BEGIN
  r := rpc_employees_gestao_summary('f1aaaaaa-0005-0000-0000-000000000011');
  IF r ->> 'error' <> 'permission_denied' THEN
    RAISE EXCEPTION 'T03 FAIL · esperava permission_denied · veio %', r;
  END IF;
  RAISE NOTICE 'PASS · T03 · colaborador comum bloqueado por permission_denied';
END $$;

-- ============================================================================
-- T04 · RH ve gestao de qualquer um no tenant
-- ============================================================================

SELECT test_login('f1aaa999-aaaa-0000-0000-000000000003');  -- RH-X

DO $$
DECLARE r JSONB;
BEGIN
  r := rpc_employees_gestao_summary('f1aaaaaa-0005-0000-0000-000000000011');
  IF (r ->> 'ok')::BOOLEAN <> TRUE THEN
    RAISE EXCEPTION 'T04 FAIL · r=%', r;
  END IF;
  RAISE NOTICE 'PASS · T04 · RH ve gestao de qualquer ficha do tenant';
END $$;

-- ============================================================================
-- T05 · Diretoria ve gestao
-- ============================================================================

SELECT test_login('f1aaa999-aaaa-0000-0000-000000000002');  -- DIR-X

DO $$
DECLARE r JSONB;
BEGIN
  r := rpc_employees_gestao_summary('f1aaaaaa-0005-0000-0000-000000000011');
  IF (r ->> 'ok')::BOOLEAN <> TRUE THEN
    RAISE EXCEPTION 'T05 FAIL · r=%', r;
  END IF;
  RAISE NOTICE 'PASS · T05 · diretoria ve gestao';
END $$;

-- ============================================================================
-- T06 · Super admin ve gestao
-- ============================================================================

SELECT test_login('f1aaa999-aaaa-0000-0000-000000000001');  -- SA

DO $$
DECLARE r JSONB;
BEGIN
  r := rpc_employees_gestao_summary('f1aaaaaa-0005-0000-0000-000000000011');
  IF (r ->> 'ok')::BOOLEAN <> TRUE THEN
    RAISE EXCEPTION 'T06 FAIL · r=%', r;
  END IF;
  RAISE NOTICE 'PASS · T06 · super_admin ve gestao';
END $$;

-- ============================================================================
-- T07 · Gestor direto ve gestao do seu subordinado
-- ============================================================================

SELECT test_login('f1aaa999-aaaa-0000-0000-000000000010');  -- GERENTE-X

DO $$
DECLARE r JSONB;
BEGIN
  r := rpc_employees_gestao_summary('f1aaaaaa-0005-0000-0000-000000000011');
  IF (r ->> 'ok')::BOOLEAN <> TRUE THEN
    RAISE EXCEPTION 'T07 FAIL · r=%', r;
  END IF;
  RAISE NOTICE 'PASS · T07 · gestor direto ve gestao';
END $$;

-- ============================================================================
-- T08 · Payload tem 4 secoes
-- ============================================================================

DO $$
DECLARE r JSONB;
BEGIN
  r := rpc_employees_gestao_summary('f1aaaaaa-0005-0000-0000-000000000011');
  IF NOT (r ? 'evaluations' AND r ? 'pdis' AND r ? 'recognitions' AND r ? 'onboardings') THEN
    RAISE EXCEPTION 'T08 FAIL · faltam secoes · r=%', r;
  END IF;
  RAISE NOTICE 'PASS · T08 · payload tem evaluations, pdis, recognitions, onboardings';
END $$;

-- ============================================================================
-- T09 · Avaliacao 9-Box aparece com box_label
-- ============================================================================

DO $$
DECLARE r JSONB;
DECLARE first_eval JSONB;
BEGIN
  r := rpc_employees_gestao_summary('f1aaaaaa-0005-0000-0000-000000000011');
  IF jsonb_array_length(r -> 'evaluations') <> 1 THEN
    RAISE EXCEPTION 'T09 FAIL · esperava 1 avaliacao · veio % · r=%',
      jsonb_array_length(r -> 'evaluations'), r;
  END IF;
  first_eval := (r -> 'evaluations') -> 0;
  IF first_eval ->> 'final_box_label' <> 'Mantenedor' THEN
    RAISE EXCEPTION 'T09 FAIL · box_label divergente · veio %', first_eval ->> 'final_box_label';
  END IF;
  RAISE NOTICE 'PASS · T09 · avaliacao 9-Box presente com box_label correto';
END $$;

-- ============================================================================
-- T10 · PDI aparece
-- ============================================================================

DO $$
DECLARE r JSONB;
BEGIN
  r := rpc_employees_gestao_summary('f1aaaaaa-0005-0000-0000-000000000011');
  IF jsonb_array_length(r -> 'pdis') <> 1 THEN
    RAISE EXCEPTION 'T10 FAIL · esperava 1 PDI · veio % · pdis=%',
      jsonb_array_length(r -> 'pdis'), r -> 'pdis';
  END IF;
  IF ((r -> 'pdis') -> 0) ->> 'status' <> 'active' THEN
    RAISE EXCEPTION 'T10 FAIL · status PDI divergente';
  END IF;
  RAISE NOTICE 'PASS · T10 · PDI ativo aparece';
END $$;

-- ============================================================================
-- T11 · Reconhecimentos: gestor ve publico + privado (sender ou recipient)
-- ============================================================================

DO $$
DECLARE r JSONB;
DECLARE count_priv INT := 0;
DECLARE count_total INT;
DECLARE i INT;
BEGIN
  r := rpc_employees_gestao_summary('f1aaaaaa-0005-0000-0000-000000000011');
  count_total := jsonb_array_length(r -> 'recognitions');
  -- Gerente nao e sender nem recipient do privado, MAS e gestor direto
  -- nao tem acesso ao privado (so super_admin/diretoria/rh).
  -- Logo esperamos 1 (so o publico).
  IF count_total <> 1 THEN
    RAISE EXCEPTION 'T11 FAIL · gerente direto esperava 1 reconhecimento (so publico) · veio %', count_total;
  END IF;
  RAISE NOTICE 'PASS · T11 · gerente ve apenas publicos (1 reconhecimento)';
END $$;

-- ============================================================================
-- T12 · RH ve privados tambem
-- ============================================================================

SELECT test_login('f1aaa999-aaaa-0000-0000-000000000003');  -- RH-X

DO $$
DECLARE r JSONB;
BEGIN
  r := rpc_employees_gestao_summary('f1aaaaaa-0005-0000-0000-000000000011');
  IF jsonb_array_length(r -> 'recognitions') <> 2 THEN
    RAISE EXCEPTION 'T12 FAIL · RH esperava 2 reconhecimentos · veio %', jsonb_array_length(r -> 'recognitions');
  END IF;
  RAISE NOTICE 'PASS · T12 · RH ve publicos + privados';
END $$;

-- ============================================================================
-- T13 · Ficha sem app_user retorna has_app_user=false
-- ============================================================================

DO $$
DECLARE r JSONB;
BEGIN
  r := rpc_employees_gestao_summary('f1aaaaaa-0005-0000-0000-000000000099');
  IF (r ->> 'ok')::BOOLEAN <> TRUE THEN
    RAISE EXCEPTION 'T13 FAIL · r=%', r;
  END IF;
  IF (r ->> 'has_app_user')::BOOLEAN <> FALSE THEN
    RAISE EXCEPTION 'T13 FAIL · esperava has_app_user=false';
  END IF;
  IF jsonb_array_length(r -> 'evaluations') <> 0 THEN
    RAISE EXCEPTION 'T13 FAIL · evaluations deveria ser []';
  END IF;
  RAISE NOTICE 'PASS · T13 · ficha sem app_user retorna estrutura vazia';
END $$;

-- ============================================================================
-- T14 · Cross-tenant · RH-Y nao acessa ficha de X
-- ============================================================================

SELECT test_login('f1aaa999-aaaa-0000-0000-000000000099');  -- RH-Y

DO $$
DECLARE r JSONB;
BEGIN
  r := rpc_employees_gestao_summary('f1aaaaaa-0005-0000-0000-000000000011');
  IF r ->> 'error' <> 'employee_not_found' THEN
    RAISE EXCEPTION 'T14 FAIL · esperava employee_not_found · veio %', r;
  END IF;
  RAISE NOTICE 'PASS · T14 · cross-tenant bloqueado';
END $$;

-- ============================================================================
-- T15 · rpc_my_team · GERENTE-X tem 2 diretos
-- ============================================================================

SELECT test_login('f1aaa999-aaaa-0000-0000-000000000010');  -- GERENTE-X

DO $$
DECLARE r JSONB;
BEGIN
  r := rpc_my_team(FALSE);
  IF (r ->> 'ok')::BOOLEAN <> TRUE THEN
    RAISE EXCEPTION 'T15 FAIL · r=%', r;
  END IF;
  IF jsonb_array_length(r -> 'team') <> 2 THEN
    RAISE EXCEPTION 'T15 FAIL · esperava 2 diretos · veio %', jsonb_array_length(r -> 'team');
  END IF;
  RAISE NOTICE 'PASS · T15 · GERENTE tem 2 subordinados diretos';
END $$;

-- ============================================================================
-- T16 · my_team com include_indirect=true · GERENTE tem 3 (2 diretos + 1 neto)
-- ============================================================================

DO $$
DECLARE r JSONB;
DECLARE has_depth_2 BOOLEAN := FALSE;
DECLARE item JSONB;
BEGIN
  r := rpc_my_team(TRUE);
  IF jsonb_array_length(r -> 'team') <> 3 THEN
    RAISE EXCEPTION 'T16 FAIL · esperava 3 · veio %', jsonb_array_length(r -> 'team');
  END IF;
  -- Verifica que tem alguem com depth=2 (NETO)
  FOR item IN SELECT * FROM jsonb_array_elements(r -> 'team') LOOP
    IF (item ->> 'depth')::INT = 2 THEN has_depth_2 := TRUE; END IF;
  END LOOP;
  IF NOT has_depth_2 THEN
    RAISE EXCEPTION 'T16 FAIL · esperava NETO com depth=2';
  END IF;
  RAISE NOTICE 'PASS · T16 · my_team(indirect) traz subordinados em 2+ niveis';
END $$;

-- ============================================================================
-- T17 · my_team enriquecido com KPIs (PDIs ativos + box_label)
-- ============================================================================

DO $$
DECLARE r JSONB;
DECLARE sub1 JSONB;
DECLARE item JSONB;
BEGIN
  r := rpc_my_team(FALSE);
  FOR item IN SELECT * FROM jsonb_array_elements(r -> 'team') LOOP
    IF item ->> 'app_user_name' = 'SUB1-X' THEN
      sub1 := item;
    END IF;
  END LOOP;
  IF sub1 IS NULL THEN
    RAISE EXCEPTION 'T17 FAIL · SUB1-X nao encontrado · team=%', r -> 'team';
  END IF;
  IF (sub1 ->> 'pdis_active')::INT <> 1 THEN
    RAISE EXCEPTION 'T17 FAIL · pdis_active esperava 1 · veio %', sub1 ->> 'pdis_active';
  END IF;
  IF sub1 ->> 'last_evaluation_box' <> 'Mantenedor' THEN
    RAISE EXCEPTION 'T17 FAIL · last_evaluation_box divergente · %', sub1 ->> 'last_evaluation_box';
  END IF;
  RAISE NOTICE 'PASS · T17 · KPIs enriquecidos (pdis_active=1, last_box=Mantenedor)';
END $$;

-- ============================================================================
-- T18 · Usuario sem subordinados retorna lista vazia (nao erro)
-- ============================================================================

SELECT test_login('f1aaa999-aaaa-0000-0000-000000000011');  -- SUB1 (colaborador comum)

DO $$
DECLARE r JSONB;
BEGIN
  r := rpc_my_team(FALSE);
  IF (r ->> 'ok')::BOOLEAN <> TRUE THEN
    RAISE EXCEPTION 'T18 FAIL · r=%', r;
  END IF;
  IF jsonb_array_length(r -> 'team') <> 0 THEN
    RAISE EXCEPTION 'T18 FAIL · esperava 0 · veio %', jsonb_array_length(r -> 'team');
  END IF;
  RAISE NOTICE 'PASS · T18 · usuario sem subordinados retorna team vazio';
END $$;

-- ============================================================================
-- FECHAMENTO
-- ============================================================================

DO $$
BEGIN
  RAISE NOTICE '========================================';
  RAISE NOTICE '=== F1 · 18 testes executados · OK   ===';
  RAISE NOTICE '========================================';
END $$;

ROLLBACK;

-- ============================================================================
-- R2 People · Testes Sessao G1 · Minha Jornada
-- ============================================================================
-- 14 testes:
--   T01 · not_authenticated
--   T02 · estrutura basica (ok, identity, kpis presentes)
--   T03 · identity inclui nome, cargo, unidade, depto, gestor
--   T04 · pdi_kpis: contagem por status correta
--   T05 · pdi_kpis: overdue conta apenas active+vencido
--   T06 · pdi_kpis: actions_total/completed somam
--   T07 · recog_kpis: separa recebidos x enviados
--   T08 · recog_kpis: 90d filtra por janela
--   T09 · last_ninebox: pega a mais recente finalizada
--   T10 · last_ninebox: ignora canceladas e nao finalizadas
--   T11 · onboarding_kpis (assignments)
--   T12 · isolamento cross-tenant (so dados do proprio user)
--   T13 · patch can_view_gestao_for_app_user · self-access permitido
--   T14 · patch nao quebra · usuario nao ve gestoes alheias
-- ============================================================================

BEGIN;

INSERT INTO tenants (id, slug, legal_name, display_name) VALUES
  ('91aaaaaa-0000-0000-0000-000000000001', 'tx-g1', 'Tenant X G1', 'X'),
  ('91aaaaaa-0000-0000-0000-000000000002', 'tx-g1-y', 'Tenant Y G1', 'Y');

INSERT INTO employer_units (id, tenant_id, code, legal_name, trade_name, city, state_uf) VALUES
  ('91aaaaaa-0001-0000-0000-000000000001', '91aaaaaa-0000-0000-0000-000000000001',
   'XEMP1', 'X Emp 1 Legal', 'ATP G1', 'Salvador', 'BA');

INSERT INTO departments (id, tenant_id, code, display_name) VALUES
  ('91aaaaaa-0002-0000-0000-000000000001', '91aaaaaa-0000-0000-0000-000000000001',
   'OPS', 'Operacoes G1');

INSERT INTO app_users (id, tenant_id, auth_user_id, email, full_name, role, manager_id,
                       employment_link, hired_at) VALUES
  ('91aaaaaa-0003-0000-0000-000000000010', '91aaaaaa-0000-0000-0000-000000000001',
   '91aaaaaa-aaa1-0000-0000-000000000010', 'gera@g1.test', 'GER A G1', 'lider', NULL,
   'clt', '2020-01-01'),
  -- Sujeito principal dos testes
  ('91aaaaaa-0003-0000-0000-000000000011', '91aaaaaa-0000-0000-0000-000000000001',
   '91aaaaaa-aaa1-0000-0000-000000000011', 'eu@g1.test', 'EU G1', 'colaborador',
   '91aaaaaa-0003-0000-0000-000000000010', 'clt', '2022-03-15'),
  -- Outro usuario para senders/recipients e cross-tenant test
  ('91aaaaaa-0003-0000-0000-000000000020', '91aaaaaa-0000-0000-0000-000000000001',
   '91aaaaaa-aaa1-0000-0000-000000000020', 'outro@g1.test', 'OUTRO G1', 'colaborador',
   NULL, 'clt', '2021-01-01'),
  ('91aaaaaa-0003-0000-0000-000000000088', '91aaaaaa-0000-0000-0000-000000000002',
   '91aaaaaa-aaa1-0000-0000-000000000088', 'y@g1.test', 'Y USER G1', 'colaborador', NULL,
   'clt', '2020-01-01');

INSERT INTO employees (id, tenant_id, full_name, job_title, hire_date, birth_date,
                       cpf, employer_unit_id, department_id, created_by) VALUES
  ('91aaaaaa-0004-0000-0000-000000000011', '91aaaaaa-0000-0000-0000-000000000001',
   'EU G1 FICHA', 'Analista Operacional', '2022-03-15', '1990-06-20',
   '70111111111', '91aaaaaa-0001-0000-0000-000000000001',
   '91aaaaaa-0002-0000-0000-000000000001',
   '91aaaaaa-0003-0000-0000-000000000010');

UPDATE app_users SET employee_id='91aaaaaa-0004-0000-0000-000000000011'
  WHERE id='91aaaaaa-0003-0000-0000-000000000011';

-- 3 ciclos PDI · 1 ativo, 2 fechados (para varios PDIs sem bater constraint)
INSERT INTO pdi_cycles (id, tenant_id, code, display_name, start_date, end_date, active) VALUES
  ('91aaaaaa-0007-0000-0000-000000000001', '91aaaaaa-0000-0000-0000-000000000001',
   'PDI2024G1', 'PDI 2024', '2024-01-01', '2024-12-31', TRUE),
  ('91aaaaaa-0007-0000-0000-000000000002', '91aaaaaa-0000-0000-0000-000000000001',
   'PDI2023G1', 'PDI 2023', '2023-01-01', '2023-12-31', FALSE),
  ('91aaaaaa-0007-0000-0000-000000000003', '91aaaaaa-0000-0000-0000-000000000001',
   'PDI2022G1', 'PDI 2022', '2022-01-01', '2022-12-31', FALSE);

-- 3 PDIs do EU: 1 ativo no prazo, 1 ativo vencido, 1 concluido
INSERT INTO pdis (id, tenant_id, user_id, cycle_id, manager_id_snapshot,
                  objective, status, start_date, end_date,
                  actions_total, actions_completed,
                  completed_at, created_by) VALUES
  ('91aaaaaa-0008-0000-0000-000000000001', '91aaaaaa-0000-0000-0000-000000000001',
   '91aaaaaa-0003-0000-0000-000000000011',
   '91aaaaaa-0007-0000-0000-000000000001',
   '91aaaaaa-0003-0000-0000-000000000010',
   'PDI ativo no prazo', 'active', '2024-01-01', CURRENT_DATE + 30,
   5, 2, NULL, '91aaaaaa-0003-0000-0000-000000000010'),
  ('91aaaaaa-0008-0000-0000-000000000002', '91aaaaaa-0000-0000-0000-000000000001',
   '91aaaaaa-0003-0000-0000-000000000011',
   '91aaaaaa-0007-0000-0000-000000000002',
   '91aaaaaa-0003-0000-0000-000000000010',
   'PDI ativo vencido', 'active', '2023-01-01', CURRENT_DATE - 10,
   4, 1, NULL, '91aaaaaa-0003-0000-0000-000000000010'),
  ('91aaaaaa-0008-0000-0000-000000000003', '91aaaaaa-0000-0000-0000-000000000001',
   '91aaaaaa-0003-0000-0000-000000000011',
   '91aaaaaa-0007-0000-0000-000000000003',
   '91aaaaaa-0003-0000-0000-000000000010',
   'PDI concluido', 'completed', '2022-01-01', '2022-12-31',
   3, 3, '2022-12-31 12:00:00+00', '91aaaaaa-0003-0000-0000-000000000010');

-- Reconhecimentos
INSERT INTO recognitions (id, tenant_id, sender_id, recipient_id, message, is_private, created_at) VALUES
  -- EU recebe 3 publicos: 2 recentes + 1 antigo
  ('91aaaaaa-0009-0000-0000-000000000001', '91aaaaaa-0000-0000-0000-000000000001',
   '91aaaaaa-0003-0000-0000-000000000010', '91aaaaaa-0003-0000-0000-000000000011',
   'Bom trabalho 1', FALSE, now() - INTERVAL '5 days'),
  ('91aaaaaa-0009-0000-0000-000000000002', '91aaaaaa-0000-0000-0000-000000000001',
   '91aaaaaa-0003-0000-0000-000000000020', '91aaaaaa-0003-0000-0000-000000000011',
   'Bom trabalho 2', FALSE, now() - INTERVAL '30 days'),
  ('91aaaaaa-0009-0000-0000-000000000003', '91aaaaaa-0000-0000-0000-000000000001',
   '91aaaaaa-0003-0000-0000-000000000010', '91aaaaaa-0003-0000-0000-000000000011',
   'Antigo', FALSE, now() - INTERVAL '200 days'),
  -- EU envia 2: 1 recente + 1 antigo
  ('91aaaaaa-0009-0000-0000-000000000004', '91aaaaaa-0000-0000-0000-000000000001',
   '91aaaaaa-0003-0000-0000-000000000011', '91aaaaaa-0003-0000-0000-000000000020',
   'Enviei agora', FALSE, now() - INTERVAL '10 days'),
  ('91aaaaaa-0009-0000-0000-000000000005', '91aaaaaa-0000-0000-0000-000000000001',
   '91aaaaaa-0003-0000-0000-000000000011', '91aaaaaa-0003-0000-0000-000000000020',
   'Enviei antigo', FALSE, now() - INTERVAL '120 days');

-- Ninebox: 2 finalizadas (mais antiga + mais recente), 1 cancelada
INSERT INTO ninebox_cycles (id, tenant_id, name, status, start_date, end_date, created_by) VALUES
  ('91aaaaaa-0005-0000-0000-000000000001', '91aaaaaa-0000-0000-0000-000000000001',
   'Ciclo G1', 'active', '2024-01-01', '2024-12-31',
   '91aaaaaa-0003-0000-0000-000000000010');

INSERT INTO ninebox_evaluations (id, tenant_id, subject_id, manager_id, cycle_id,
                                  is_adhoc, status,
                                  grid_size_snapshot, potential_criteria_snapshot,
                                  performance_criteria_snapshot, box_labels_snapshot,
                                  final_box_row, final_box_col, final_box_label,
                                  finalized_at, canceled_at, created_by) VALUES
  ('91aaaaaa-0006-0000-0000-000000000001', '91aaaaaa-0000-0000-0000-000000000001',
   '91aaaaaa-0003-0000-0000-000000000011', '91aaaaaa-0003-0000-0000-000000000010',
   '91aaaaaa-0005-0000-0000-000000000001',
   FALSE, 'finalized',
   '3x3', '[]'::jsonb, '[]'::jsonb, '[]'::jsonb,
   2, 2, 'Mantenedor+', now() - INTERVAL '60 days', NULL,
   '91aaaaaa-0003-0000-0000-000000000010'),
  ('91aaaaaa-0006-0000-0000-000000000002', '91aaaaaa-0000-0000-0000-000000000001',
   '91aaaaaa-0003-0000-0000-000000000011', '91aaaaaa-0003-0000-0000-000000000010',
   NULL,
   TRUE, 'finalized',
   '3x3', '[]'::jsonb, '[]'::jsonb, '[]'::jsonb,
   3, 3, 'Future Star', now() - INTERVAL '5 days', NULL,
   '91aaaaaa-0003-0000-0000-000000000010'),
  -- Cancelada (deve ser ignorada)
  ('91aaaaaa-0006-0000-0000-000000000003', '91aaaaaa-0000-0000-0000-000000000001',
   '91aaaaaa-0003-0000-0000-000000000011', '91aaaaaa-0003-0000-0000-000000000010',
   NULL,
   TRUE, 'finalized',
   '3x3', '[]'::jsonb, '[]'::jsonb, '[]'::jsonb,
   1, 1, 'Insuficiente', now() - INTERVAL '1 day', now(),
   '91aaaaaa-0003-0000-0000-000000000010');

-- ============================================================================
-- T01 · not_authenticated
-- ============================================================================

DO $$ DECLARE r JSONB;
BEGIN
  PERFORM set_config('request.jwt.claim.sub', 'ffffffff-0000-0000-0000-000000000000', TRUE);
  r := rpc_my_journey();
  IF r ->> 'error' <> 'not_authenticated' THEN
    RAISE EXCEPTION 'T01 FAIL · veio %', r;
  END IF;
  RAISE NOTICE 'PASS · T01 · usuario inexistente bloqueado';
END $$;

-- ============================================================================
-- T02 · Estrutura basica
-- ============================================================================

SELECT test_login('91aaaaaa-aaa1-0000-0000-000000000011');

DO $$ DECLARE r JSONB;
BEGIN
  r := rpc_my_journey();
  IF (r ->> 'ok')::BOOLEAN <> TRUE THEN
    RAISE EXCEPTION 'T02 FAIL · ok=false · %', r;
  END IF;
  IF NOT (r ? 'identity' AND r ? 'pdi_kpis' AND r ? 'recog_kpis'
          AND r ? 'last_ninebox' AND r ? 'onboarding_kpis') THEN
    RAISE EXCEPTION 'T02 FAIL · faltam campos · %', r;
  END IF;
  RAISE NOTICE 'PASS · T02 · estrutura completa';
END $$;

-- ============================================================================
-- T03 · Identity: nome/cargo/unidade/depto/gestor
-- ============================================================================

DO $$ DECLARE r JSONB; DECLARE id JSONB;
BEGIN
  r := rpc_my_journey();
  id := r -> 'identity';
  IF id ->> 'full_name' <> 'EU G1 FICHA' THEN
    RAISE EXCEPTION 'T03 FAIL · full_name veio %', id ->> 'full_name';
  END IF;
  IF id ->> 'job_title' <> 'Analista Operacional' THEN
    RAISE EXCEPTION 'T03 FAIL · job_title veio %', id ->> 'job_title';
  END IF;
  IF id -> 'employer_unit' ->> 'trade_name' <> 'ATP G1' THEN
    RAISE EXCEPTION 'T03 FAIL · unit veio %', id -> 'employer_unit';
  END IF;
  IF id -> 'department' ->> 'display_name' <> 'Operacoes G1' THEN
    RAISE EXCEPTION 'T03 FAIL · dept veio %', id -> 'department';
  END IF;
  IF id -> 'manager' ->> 'full_name' <> 'GER A G1' THEN
    RAISE EXCEPTION 'T03 FAIL · manager veio %', id -> 'manager';
  END IF;
  RAISE NOTICE 'PASS · T03 · identity completa com ficha/unidade/depto/gestor';
END $$;

-- ============================================================================
-- T04 · pdi_kpis: 1 active+prazo, 1 active+overdue, 1 completed
-- ============================================================================

DO $$ DECLARE r JSONB; DECLARE k JSONB;
BEGIN
  r := rpc_my_journey();
  k := r -> 'pdi_kpis';
  IF (k ->> 'active')::INT <> 2 THEN
    RAISE EXCEPTION 'T04 FAIL · active esperava 2 · veio %', k ->> 'active';
  END IF;
  IF (k ->> 'completed')::INT <> 1 THEN
    RAISE EXCEPTION 'T04 FAIL · completed esperava 1 · veio %', k ->> 'completed';
  END IF;
  IF (k ->> 'draft')::INT <> 0 OR (k ->> 'canceled')::INT <> 0 THEN
    RAISE EXCEPTION 'T04 FAIL · draft/canceled esperava 0 · veio %', k;
  END IF;
  RAISE NOTICE 'PASS · T04 · pdi_kpis contagem por status';
END $$;

-- ============================================================================
-- T05 · pdi_kpis: overdue = 1 (so o active vencido)
-- ============================================================================

DO $$ DECLARE r JSONB;
BEGIN
  r := rpc_my_journey();
  IF (r -> 'pdi_kpis' ->> 'overdue')::INT <> 1 THEN
    RAISE EXCEPTION 'T05 FAIL · overdue esperava 1 · veio %', r -> 'pdi_kpis' ->> 'overdue';
  END IF;
  RAISE NOTICE 'PASS · T05 · overdue conta so active+vencido';
END $$;

-- ============================================================================
-- T06 · pdi_kpis: actions_total=12, completed=6
-- ============================================================================

DO $$ DECLARE r JSONB; DECLARE k JSONB;
BEGIN
  r := rpc_my_journey();
  k := r -> 'pdi_kpis';
  -- PDIs: 5+4+3 = 12 total; 2+1+3 = 6 completed
  IF (k ->> 'actions_total')::INT <> 12 THEN
    RAISE EXCEPTION 'T06 FAIL · actions_total esperava 12 · veio %', k ->> 'actions_total';
  END IF;
  IF (k ->> 'actions_completed')::INT <> 6 THEN
    RAISE EXCEPTION 'T06 FAIL · actions_completed esperava 6 · veio %', k ->> 'actions_completed';
  END IF;
  RAISE NOTICE 'PASS · T06 · actions_total/completed somam';
END $$;

-- ============================================================================
-- T07 · recog_kpis: separa recebidos x enviados
-- ============================================================================

DO $$ DECLARE r JSONB; DECLARE k JSONB;
BEGIN
  r := rpc_my_journey();
  k := r -> 'recog_kpis';
  -- 3 recebidos (incluindo o antigo) e 2 enviados (incluindo o antigo)
  IF (k ->> 'received_total')::INT <> 3 THEN
    RAISE EXCEPTION 'T07 FAIL · received_total esperava 3 · veio %', k ->> 'received_total';
  END IF;
  IF (k ->> 'sent_total')::INT <> 2 THEN
    RAISE EXCEPTION 'T07 FAIL · sent_total esperava 2 · veio %', k ->> 'sent_total';
  END IF;
  RAISE NOTICE 'PASS · T07 · received_total=3 sent_total=2';
END $$;

-- ============================================================================
-- T08 · recog_kpis: janela 90d filtra
-- ============================================================================

DO $$ DECLARE r JSONB; DECLARE k JSONB;
BEGIN
  r := rpc_my_journey();
  k := r -> 'recog_kpis';
  -- 2 recebidos em 90d (5d e 30d), 1 enviado em 90d (10d)
  IF (k ->> 'received_90d')::INT <> 2 THEN
    RAISE EXCEPTION 'T08 FAIL · received_90d esperava 2 · veio %', k ->> 'received_90d';
  END IF;
  IF (k ->> 'sent_90d')::INT <> 1 THEN
    RAISE EXCEPTION 'T08 FAIL · sent_90d esperava 1 · veio %', k ->> 'sent_90d';
  END IF;
  RAISE NOTICE 'PASS · T08 · 90d filtra corretamente';
END $$;

-- ============================================================================
-- T09 · last_ninebox: pega a mais recente
-- ============================================================================

DO $$ DECLARE r JSONB; DECLARE n JSONB;
BEGIN
  r := rpc_my_journey();
  n := r -> 'last_ninebox';
  IF n IS NULL OR n = 'null'::JSONB THEN
    RAISE EXCEPTION 'T09 FAIL · esperava last_ninebox preenchida';
  END IF;
  IF n ->> 'box_label' <> 'Future Star' THEN
    RAISE EXCEPTION 'T09 FAIL · esperava Future Star · veio %', n ->> 'box_label';
  END IF;
  IF (n ->> 'is_adhoc')::BOOLEAN <> TRUE THEN
    RAISE EXCEPTION 'T09 FAIL · esperava is_adhoc true';
  END IF;
  RAISE NOTICE 'PASS · T09 · last_ninebox e a mais recente (adhoc)';
END $$;

-- ============================================================================
-- T10 · last_ninebox: ignora canceladas
-- ============================================================================

-- A cancelada eh a mais recente (1 dia atras); a RPC deve devolver a de 5 dias
DO $$ DECLARE r JSONB;
BEGIN
  r := rpc_my_journey();
  IF r -> 'last_ninebox' ->> 'box_label' = 'Insuficiente' THEN
    RAISE EXCEPTION 'T10 FAIL · nao deveria retornar a cancelada';
  END IF;
  RAISE NOTICE 'PASS · T10 · cancelada ignorada';
END $$;

-- ============================================================================
-- T11 · onboarding_kpis estrutura (mesmo sem assignments retorna zeros)
-- ============================================================================

DO $$ DECLARE r JSONB; DECLARE k JSONB;
BEGIN
  r := rpc_my_journey();
  k := r -> 'onboarding_kpis';
  IF NOT (k ? 'active' AND k ? 'completed' AND k ? 'tasks_total' AND k ? 'tasks_completed') THEN
    RAISE EXCEPTION 'T11 FAIL · faltam campos · %', k;
  END IF;
  -- Sem assignments cadastrados, esperamos zeros
  IF (k ->> 'active')::INT <> 0 OR (k ->> 'completed')::INT <> 0 THEN
    RAISE EXCEPTION 'T11 FAIL · esperava 0/0 · veio %', k;
  END IF;
  RAISE NOTICE 'PASS · T11 · onboarding_kpis tem estrutura mesmo sem dados';
END $$;

-- ============================================================================
-- T12 · isolamento cross-tenant
-- ============================================================================

SELECT test_login('91aaaaaa-aaa1-0000-0000-000000000088');

DO $$ DECLARE r JSONB;
BEGIN
  r := rpc_my_journey();
  -- Y nao deve ver dados do tenant X
  IF (r -> 'pdi_kpis' ->> 'active')::INT <> 0 THEN
    RAISE EXCEPTION 'T12 FAIL · Y_USER nao deveria ver PDIs · veio %', r -> 'pdi_kpis';
  END IF;
  IF (r -> 'recog_kpis' ->> 'received_total')::INT <> 0 THEN
    RAISE EXCEPTION 'T12 FAIL · Y_USER nao deveria ver recogs · veio %', r -> 'recog_kpis';
  END IF;
  IF r ->> 'last_ninebox' IS NOT NULL AND r -> 'last_ninebox' <> 'null'::JSONB THEN
    RAISE EXCEPTION 'T12 FAIL · Y_USER nao deveria ver ninebox · veio %', r -> 'last_ninebox';
  END IF;
  RAISE NOTICE 'PASS · T12 · isolamento cross-tenant';
END $$;

-- ============================================================================
-- T13 · Self-access via can_view_gestao_for_app_user (patch G1)
-- ============================================================================

SELECT test_login('91aaaaaa-aaa1-0000-0000-000000000011');  -- EU

DO $$ DECLARE allowed BOOLEAN;
BEGIN
  allowed := can_view_gestao_for_app_user('91aaaaaa-0003-0000-0000-000000000011');
  IF NOT allowed THEN
    RAISE EXCEPTION 'T13 FAIL · self-access deveria ser permitido';
  END IF;
  RAISE NOTICE 'PASS · T13 · proprio usuario consegue ver suas gestoes';
END $$;

-- ============================================================================
-- T14 · Self-access nao quebra · usuario nao pode ver outro alheio
-- ============================================================================

DO $$ DECLARE allowed BOOLEAN;
BEGIN
  -- EU tentando ver gestoes do OUTRO (nao e gestor, nao e RH/diretoria)
  allowed := can_view_gestao_for_app_user('91aaaaaa-0003-0000-0000-000000000020');
  IF allowed THEN
    RAISE EXCEPTION 'T14 FAIL · EU nao deveria ver OUTRO';
  END IF;
  RAISE NOTICE 'PASS · T14 · patch nao vaza acesso a terceiros';
END $$;

DO $$ BEGIN
  RAISE NOTICE '========================================';
  RAISE NOTICE '=== G1 · 14 testes executados · OK   ===';
  RAISE NOTICE '========================================';
END $$;

ROLLBACK;

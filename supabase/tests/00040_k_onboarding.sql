-- ============================================================================
-- R2 People · Testes Onboarding v1
-- ============================================================================
-- Cobre constraints, triggers, RPCs, RLS, workflow, denormalizacao,
-- templates, instanciacao com deep copy.
--
-- Pre-requisitos:
--   - r2_people_schema_base_v1.sql + seed
--   - r2_people_schema_onboarding_v1.sql + seed
--
-- Roda em transacao com ROLLBACK · nao deixa lixo.
-- ============================================================================

BEGIN;

-- ============================================================================
-- SETUP · 1 tenant + estrutura organizacional + 5 usuarios
-- ============================================================================

INSERT INTO tenants (id, slug, legal_name, display_name) VALUES
  ('00000000-0000-0000-A000-000000000001', 'onb-test', 'ONB Test', 'ONBT')
ON CONFLICT (id) DO NOTHING;

INSERT INTO employer_units (id, tenant_id, code, legal_name) VALUES
  ('00000000-0000-0000-A001-000000000001', '00000000-0000-0000-A000-000000000001', 'EMP', 'Emp ONB')
ON CONFLICT (id) DO NOTHING;

INSERT INTO working_units (id, tenant_id, employer_unit_id, code, display_name) VALUES
  ('00000000-0000-0000-A002-000000000001', '00000000-0000-0000-A000-000000000001',
   '00000000-0000-0000-A001-000000000001', 'WU', 'WU ONB')
ON CONFLICT (id) DO NOTHING;

-- DIR (1) · LID (3, gerido por DIR) · COL1 (4, gerido por LID) · COL2 (5, gerido por LID) · RH (2)
INSERT INTO app_users (
  id, tenant_id, auth_user_id, email, full_name, role,
  employer_unit_id, working_unit_id, manager_id, employment_link, hired_at
) VALUES
  ('00000000-0000-0000-A004-000000000001',
   '00000000-0000-0000-A000-000000000001', '77777777-7777-7777-7777-000000000001',
   'dir@onb-test.com', 'Diretor ONB', 'diretoria',
   '00000000-0000-0000-A001-000000000001', '00000000-0000-0000-A002-000000000001',
   NULL, 'clt', '2020-01-01'),
  ('00000000-0000-0000-A004-000000000002',
   '00000000-0000-0000-A000-000000000001', '77777777-7777-7777-7777-000000000002',
   'rh@onb-test.com', 'RH ONB', 'rh',
   '00000000-0000-0000-A001-000000000001', '00000000-0000-0000-A002-000000000001',
   '00000000-0000-0000-A004-000000000001', 'clt', '2020-01-01'),
  ('00000000-0000-0000-A004-000000000003',
   '00000000-0000-0000-A000-000000000001', '77777777-7777-7777-7777-000000000003',
   'lid@onb-test.com', 'Lider ONB', 'lider',
   '00000000-0000-0000-A001-000000000001', '00000000-0000-0000-A002-000000000001',
   '00000000-0000-0000-A004-000000000001', 'clt', '2020-01-01'),
  ('00000000-0000-0000-A004-000000000004',
   '00000000-0000-0000-A000-000000000001', '77777777-7777-7777-7777-000000000004',
   'col1@onb-test.com', 'Novo Colaborador 1', 'colaborador',
   '00000000-0000-0000-A001-000000000001', '00000000-0000-0000-A002-000000000001',
   '00000000-0000-0000-A004-000000000003', 'clt', '2026-05-01'),
  ('00000000-0000-0000-A004-000000000005',
   '00000000-0000-0000-A000-000000000001', '77777777-7777-7777-7777-000000000005',
   'col2@onb-test.com', 'Novo Colaborador 2', 'colaborador',
   '00000000-0000-0000-A001-000000000001', '00000000-0000-0000-A002-000000000001',
   '00000000-0000-0000-A004-000000000003', 'clt', '2026-05-01'),
  -- Usuarios extras para testes que criam multiplos onboardings
  ('00000000-0000-0000-A004-000000000006',
   '00000000-0000-0000-A000-000000000001', '77777777-7777-7777-7777-000000000006',
   'col3@onb-test.com', 'Novo Colaborador 3', 'colaborador',
   '00000000-0000-0000-A001-000000000001', '00000000-0000-0000-A002-000000000001',
   '00000000-0000-0000-A004-000000000003', 'clt', '2026-05-01'),
  ('00000000-0000-0000-A004-000000000007',
   '00000000-0000-0000-A000-000000000001', '77777777-7777-7777-7777-000000000007',
   'col4@onb-test.com', 'Novo Colaborador 4', 'colaborador',
   '00000000-0000-0000-A001-000000000001', '00000000-0000-0000-A002-000000000001',
   '00000000-0000-0000-A004-000000000003', 'clt', '2026-05-01'),
  ('00000000-0000-0000-A004-000000000008',
   '00000000-0000-0000-A000-000000000001', '77777777-7777-7777-7777-000000000008',
   'col5@onb-test.com', 'Novo Colaborador 5', 'colaborador',
   '00000000-0000-0000-A001-000000000001', '00000000-0000-0000-A002-000000000001',
   '00000000-0000-0000-A004-000000000003', 'clt', '2026-05-01'),
  ('00000000-0000-0000-A004-000000000009',
   '00000000-0000-0000-A000-000000000001', '77777777-7777-7777-7777-000000000009',
   'col6@onb-test.com', 'Novo Colaborador 6', 'colaborador',
   '00000000-0000-0000-A001-000000000001', '00000000-0000-0000-A002-000000000001',
   '00000000-0000-0000-A004-000000000003', 'clt', '2026-05-01')
ON CONFLICT (id) DO NOTHING;

CREATE OR REPLACE FUNCTION test_log(msg TEXT)
RETURNS TEXT AS $$
BEGIN RAISE NOTICE '%', msg; RETURN msg; END;
$$ LANGUAGE plpgsql;

-- Cancela onboardings ativos do tenant de teste para liberar users entre testes
CREATE OR REPLACE FUNCTION test_cleanup_onboardings()
RETURNS VOID AS $$
BEGIN
  UPDATE onboardings SET status = 'canceled', cancel_reason = 'test cleanup'
  WHERE tenant_id = '00000000-0000-0000-A000-000000000001'
    AND status IN ('not_started', 'in_progress');
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- TESTE 1 · Constraints basicas
-- ============================================================================

SELECT test_log('--- TESTE 1 · Constraints basicas ---');

DO $$
BEGIN
  -- display_name curto demais (< 3 chars)
  BEGIN
    INSERT INTO onb_templates (tenant_id, code, display_name, created_by)
    VALUES (
      '00000000-0000-0000-A000-000000000001',
      'X', 'AB',
      '00000000-0000-0000-A004-000000000002'
    );
    ASSERT FALSE, 'Nome curto deveria falhar';
  EXCEPTION WHEN check_violation THEN NULL;
  END;

  -- duracao invalida
  BEGIN
    INSERT INTO onb_templates (tenant_id, code, display_name, suggested_duration_days, created_by)
    VALUES (
      '00000000-0000-0000-A000-000000000001',
      'TEST', 'Teste valido', 0,
      '00000000-0000-0000-A004-000000000002'
    );
    ASSERT FALSE, 'Duracao 0 deveria falhar';
  EXCEPTION WHEN check_violation THEN NULL;
  END;

  -- end < start em onboarding
  BEGIN
    INSERT INTO onboardings (
      tenant_id, user_id, display_name, start_date, target_end_date, created_by
    ) VALUES (
      '00000000-0000-0000-A000-000000000001',
      '00000000-0000-0000-A004-000000000004',
      'Onboarding com datas invertidas',
      '2026-12-01', '2026-07-01',
      '00000000-0000-0000-A004-000000000002'
    );
    ASSERT FALSE, 'Datas invertidas deveriam falhar';
  EXCEPTION WHEN check_violation THEN NULL;
  END;
END $$;

SELECT test_log('OK · constraints basicas');

-- ============================================================================
-- TESTE 2 · Index parcial · 1 onboarding ativo por user
-- ============================================================================

SELECT test_log('--- TESTE 2 · 1 onboarding ativo por user ---');

DO $$
DECLARE
  v_onb1 UUID;
BEGIN
  INSERT INTO onboardings (tenant_id, user_id, display_name, start_date, target_end_date, created_by, status)
  VALUES (
    '00000000-0000-0000-A000-000000000001',
    '00000000-0000-0000-A004-000000000004',
    'Primeiro onboarding ativo',
    '2026-05-01', '2026-06-01',
    '00000000-0000-0000-A004-000000000002',
    'in_progress'
  ) RETURNING id INTO v_onb1;

  -- Segundo ativo do mesmo user · deve falhar
  BEGIN
    INSERT INTO onboardings (tenant_id, user_id, display_name, start_date, target_end_date, created_by, status)
    VALUES (
      '00000000-0000-0000-A000-000000000001',
      '00000000-0000-0000-A004-000000000004',
      'Segundo ativo · deveria falhar',
      '2026-06-01', '2026-07-01',
      '00000000-0000-0000-A004-000000000002',
      'in_progress'
    );
    ASSERT FALSE, 'Segundo onboarding ativo deveria falhar';
  EXCEPTION WHEN unique_violation THEN NULL;
  END;

  -- Cancelar o ativo libera para criar outro
  UPDATE onboardings SET status = 'canceled', cancel_reason = 'Reorganizacao' WHERE id = v_onb1;

  -- Agora consegue criar outro
  INSERT INTO onboardings (tenant_id, user_id, display_name, start_date, target_end_date, created_by, status)
  VALUES (
    '00000000-0000-0000-A000-000000000001',
    '00000000-0000-0000-A004-000000000004',
    'Segundo onboarding apos cancelar o primeiro',
    '2026-06-01', '2026-07-01',
    '00000000-0000-0000-A004-000000000002',
    'in_progress'
  );
END $$;

SELECT test_log('OK · index parcial bloqueia 2 onboardings ativos');

-- ============================================================================
-- TESTE 3 · Trigger denormaliza counts (incluindo required)
-- ============================================================================

SELECT test_log('--- TESTE 3 · Denormalizacao de counts ---');

DO $$
DECLARE
  v_onb UUID;
  v_stage UUID;
  v_total INT;
  v_completed INT;
  v_required INT;
  v_required_done INT;
BEGIN
  INSERT INTO onboardings (tenant_id, user_id, display_name, start_date, target_end_date, created_by)
  VALUES (
    '00000000-0000-0000-A000-000000000001',
    '00000000-0000-0000-A004-000000000005',
    'Onboarding para teste de denormalizacao',
    '2026-05-01', '2026-06-15',
    '00000000-0000-0000-A004-000000000002'
  ) RETURNING id INTO v_onb;

  INSERT INTO onboarding_stages (tenant_id, onboarding_id, display_name)
  VALUES ('00000000-0000-0000-A000-000000000001', v_onb, 'Stage A')
  RETURNING id INTO v_stage;

  -- 4 tasks: 3 required, 1 opcional
  INSERT INTO onboarding_tasks (tenant_id, onboarding_id, stage_id, title, is_required) VALUES
    ('00000000-0000-0000-A000-000000000001', v_onb, v_stage, 'Task 1 obrigatoria', TRUE),
    ('00000000-0000-0000-A000-000000000001', v_onb, v_stage, 'Task 2 obrigatoria', TRUE),
    ('00000000-0000-0000-A000-000000000001', v_onb, v_stage, 'Task 3 obrigatoria', TRUE),
    ('00000000-0000-0000-A000-000000000001', v_onb, v_stage, 'Task 4 opcional', FALSE);

  SELECT tasks_total, tasks_completed, tasks_required, tasks_required_done
  INTO v_total, v_completed, v_required, v_required_done
  FROM onboardings WHERE id = v_onb;

  ASSERT v_total = 4, format('total esperado 4, obtido %s', v_total);
  ASSERT v_required = 3, format('required esperado 3, obtido %s', v_required);
  ASSERT v_completed = 0, 'completed inicial = 0';
  ASSERT v_required_done = 0, 'required_done inicial = 0';

  -- Concluir 2 obrigatorias e 1 opcional
  UPDATE onboarding_tasks SET status = 'completed'
  WHERE onboarding_id = v_onb AND title IN ('Task 1 obrigatoria', 'Task 2 obrigatoria', 'Task 4 opcional');

  SELECT tasks_completed, tasks_required_done INTO v_completed, v_required_done
  FROM onboardings WHERE id = v_onb;

  ASSERT v_completed = 3, format('completed=3, obtido %s', v_completed);
  ASSERT v_required_done = 2, format('required_done=2, obtido %s', v_required_done);

  -- Reverter 1
  UPDATE onboarding_tasks SET status = 'pending'
  WHERE onboarding_id = v_onb AND title = 'Task 1 obrigatoria';

  SELECT tasks_completed, tasks_required_done INTO v_completed, v_required_done
  FROM onboardings WHERE id = v_onb;

  ASSERT v_completed = 2, format('completed apos revert=2, obtido %s', v_completed);
  ASSERT v_required_done = 1, format('required_done apos revert=1, obtido %s', v_required_done);
END $$;

SELECT test_log('OK · counts denormalizados (total/completed/required/required_done)');

-- ============================================================================
-- TESTE 4 · completed_at + completed_by automatico em tasks
-- ============================================================================

SELECT test_log('--- TESTE 4 · completed_at automatico em tasks ---');

DO $$
DECLARE
  v_onb UUID;
  v_stage UUID;
  v_task UUID;
  v_completed_at TIMESTAMPTZ;
  v_completed_by UUID;
BEGIN
  PERFORM set_config('request.jwt.claim.sub', '77777777-7777-7777-7777-000000000002', TRUE);

  INSERT INTO onboardings (tenant_id, user_id, display_name, start_date, target_end_date, created_by)
  VALUES (
    '00000000-0000-0000-A000-000000000001',
    '00000000-0000-0000-A004-000000000006',
    'Onboarding completed_at',
    '2026-05-01', '2026-06-15',
    '00000000-0000-0000-A004-000000000002'
  ) RETURNING id INTO v_onb;

  INSERT INTO onboarding_stages (tenant_id, onboarding_id, display_name)
  VALUES ('00000000-0000-0000-A000-000000000001', v_onb, 'Stage')
  RETURNING id INTO v_stage;

  INSERT INTO onboarding_tasks (tenant_id, onboarding_id, stage_id, title)
  VALUES ('00000000-0000-0000-A000-000000000001', v_onb, v_stage, 'Task para concluir')
  RETURNING id INTO v_task;

  SELECT completed_at INTO v_completed_at FROM onboarding_tasks WHERE id = v_task;
  ASSERT v_completed_at IS NULL, 'Inicio sem completed_at';

  UPDATE onboarding_tasks SET status = 'completed' WHERE id = v_task;

  SELECT completed_at, completed_by INTO v_completed_at, v_completed_by FROM onboarding_tasks WHERE id = v_task;
  ASSERT v_completed_at IS NOT NULL, 'completed_at deveria ter sido setado';
  ASSERT v_completed_by = '00000000-0000-0000-A004-000000000002', 'completed_by deveria ser RH';

  -- Reverter limpa ambos
  UPDATE onboarding_tasks SET status = 'pending' WHERE id = v_task;

  SELECT completed_at, completed_by INTO v_completed_at, v_completed_by FROM onboarding_tasks WHERE id = v_task;
  ASSERT v_completed_at IS NULL AND v_completed_by IS NULL, 'completed_at e completed_by deveriam ter sido limpos';
END $$;

SELECT test_log('OK · completed_at + completed_by automaticos');

-- ============================================================================
-- TESTE 5 · Timestamps de status em onboardings
-- ============================================================================

SELECT test_log('--- TESTE 5 · Timestamps de status em onboardings ---');

DO $$
DECLARE
  v_onb UUID;
  v_stage UUID;
  v_started TIMESTAMPTZ;
  v_completed TIMESTAMPTZ;
BEGIN
  INSERT INTO onboardings (tenant_id, user_id, display_name, start_date, target_end_date, created_by)
  VALUES (
    '00000000-0000-0000-A000-000000000001',
    '00000000-0000-0000-A004-000000000007',
    'Onboarding timestamps',
    '2026-05-01', '2026-06-01',
    '00000000-0000-0000-A004-000000000002'
  ) RETURNING id INTO v_onb;

  -- Cria stage e task para conseguir mover para in_progress
  INSERT INTO onboarding_stages (tenant_id, onboarding_id, display_name)
  VALUES ('00000000-0000-0000-A000-000000000001', v_onb, 'St')
  RETURNING id INTO v_stage;

  INSERT INTO onboarding_tasks (tenant_id, onboarding_id, stage_id, title, is_required)
  VALUES ('00000000-0000-0000-A000-000000000001', v_onb, v_stage, 'Tk1', FALSE);

  UPDATE onboardings SET status = 'in_progress' WHERE id = v_onb;
  SELECT started_at INTO v_started FROM onboardings WHERE id = v_onb;
  ASSERT v_started IS NOT NULL, 'started_at deveria ter sido setado';

  UPDATE onboardings SET status = 'completed' WHERE id = v_onb;
  SELECT completed_at INTO v_completed FROM onboardings WHERE id = v_onb;
  ASSERT v_completed IS NOT NULL, 'completed_at deveria ter sido setado';
END $$;

SELECT test_log('OK · timestamps de status');

-- ============================================================================
-- TESTE 6 · RPC template_create · happy path RH
-- ============================================================================

SELECT test_log('--- TESTE 6 · RPC template_create ---');

DO $$
DECLARE
  v_result JSONB;
  v_template_id UUID;
BEGIN
  PERFORM set_config('request.jwt.claim.sub', '77777777-7777-7777-7777-000000000002', TRUE);  -- RH

  v_result := rpc_onb_template_create(
    'TPL-CAIXA',
    'Onboarding Operador de Caixa',
    'Template para integracao de novos operadores de caixa',
    21
  );
  ASSERT v_result->>'ok' = 'true', format('Esperado ok, obtido %s', v_result::TEXT);
  v_template_id := (v_result->>'template_id')::UUID;
  ASSERT v_template_id IS NOT NULL, 'template_id deveria existir';

  -- Duplicar codigo deve falhar
  v_result := rpc_onb_template_create('TPL-CAIXA', 'Outro nome', NULL, 30);
  ASSERT v_result->>'error' = 'code_already_exists', 'Codigo duplicado deveria falhar';
END $$;

SELECT test_log('OK · template_create happy path + dedupe');

-- ============================================================================
-- TESTE 7 · RPC template_create · sem permissao bloqueia
-- ============================================================================

SELECT test_log('--- TESTE 7 · template_create sem permissao ---');

DO $$
DECLARE
  v_result JSONB;
BEGIN
  -- COL1 (sem manage_onboarding)
  PERFORM set_config('request.jwt.claim.sub', '77777777-7777-7777-7777-000000000004', TRUE);
  v_result := rpc_onb_template_create('TPL-X', 'Tentativa de colaborador', NULL, 30);
  ASSERT v_result->>'error' = 'permission_denied',
    format('Colaborador nao deveria criar, obtido %s', v_result::TEXT);

  -- LID (sem manage_onboarding · so view)
  PERFORM set_config('request.jwt.claim.sub', '77777777-7777-7777-7777-000000000003', TRUE);
  v_result := rpc_onb_template_create('TPL-X', 'Tentativa de lider', NULL, 30);
  ASSERT v_result->>'error' = 'permission_denied', 'Lider nao deveria criar';
END $$;

SELECT test_log('OK · template_create respeita permissao');

-- ============================================================================
-- TESTE 8 · template_stage_add + template_task_add (happy path)
-- ============================================================================

SELECT test_log('--- TESTE 8 · template_stage_add + task_add ---');

DO $$
DECLARE
  v_template_id UUID;
  v_stage_id UUID;
  v_task_id UUID;
  v_result JSONB;
BEGIN
  PERFORM set_config('request.jwt.claim.sub', '77777777-7777-7777-7777-000000000002', TRUE);  -- RH

  v_result := rpc_onb_template_create('TPL-T8', 'Template T8', NULL, 30);
  v_template_id := (v_result->>'template_id')::UUID;

  v_result := rpc_onb_template_stage_add(v_template_id, 'Documentacao', NULL, 0, 3);
  ASSERT v_result->>'ok' = 'true', 'stage_add deveria funcionar';
  v_stage_id := (v_result->>'stage_id')::UUID;

  v_result := rpc_onb_template_task_add(v_stage_id, 'Entregar RG', NULL, 'documentation', 0, TRUE);
  ASSERT v_result->>'ok' = 'true', 'task_add deveria funcionar';
  v_task_id := (v_result->>'task_id')::UUID;

  -- Title curto deve falhar
  v_result := rpc_onb_template_task_add(v_stage_id, 'XX');
  ASSERT v_result->>'error' = 'title_too_short', 'Title curto deveria falhar';
END $$;

SELECT test_log('OK · stage_add + task_add em template');

-- ============================================================================
-- TESTE 9 · onboarding_create_from_template (deep copy)
-- ============================================================================

SELECT test_log('--- TESTE 9 · create_from_template (deep copy) ---');

DO $$
DECLARE
  v_template_id UUID;
  v_stage_id UUID;
  v_onb_id UUID;
  v_result JSONB;
  v_count_stages INT;
  v_count_tasks INT;
BEGIN
  PERFORM set_config('request.jwt.claim.sub', '77777777-7777-7777-7777-000000000002', TRUE);  -- RH
  PERFORM test_cleanup_onboardings();

  -- Cria template com 2 stages e 4 tasks
  v_result := rpc_onb_template_create('TPL-T9', 'Template T9', NULL, 14);
  v_template_id := (v_result->>'template_id')::UUID;

  -- Publicar
  PERFORM rpc_onb_template_update(v_template_id, NULL, NULL, NULL, 'published');

  v_result := rpc_onb_template_stage_add(v_template_id, 'Documentacao', NULL, 0, 3);
  v_stage_id := (v_result->>'stage_id')::UUID;
  PERFORM rpc_onb_template_task_add(v_stage_id, 'Tarefa A', NULL, 'documentation', 0, TRUE);
  PERFORM rpc_onb_template_task_add(v_stage_id, 'Tarefa B', NULL, 'task', 1, TRUE);

  v_result := rpc_onb_template_stage_add(v_template_id, 'Treinamentos', NULL, 3, 7);
  v_stage_id := (v_result->>'stage_id')::UUID;
  PERFORM rpc_onb_template_task_add(v_stage_id, 'Treinamento 1', NULL, 'training', 0, TRUE);
  PERFORM rpc_onb_template_task_add(v_stage_id, 'Treinamento opcional', NULL, 'training', 3, FALSE);

  -- Instanciar
  v_result := rpc_onboarding_create_from_template(
    '00000000-0000-0000-A004-000000000005',
    v_template_id,
    'Onboarding COL2',
    '2026-06-01',
    'Notas iniciais do RH'
  );
  ASSERT v_result->>'ok' = 'true', format('Esperado ok, obtido %s', v_result::TEXT);
  v_onb_id := (v_result->>'onboarding_id')::UUID;

  -- Verificar deep copy
  SELECT count(*) INTO v_count_stages FROM onboarding_stages WHERE onboarding_id = v_onb_id;
  ASSERT v_count_stages = 2, format('Esperado 2 stages, obtido %s', v_count_stages);

  SELECT count(*) INTO v_count_tasks FROM onboarding_tasks WHERE onboarding_id = v_onb_id;
  ASSERT v_count_tasks = 4, format('Esperado 4 tasks, obtido %s', v_count_tasks);

  -- target_end_date = start_date + 14 dias
  ASSERT (SELECT target_end_date FROM onboardings WHERE id = v_onb_id) = '2026-06-15'::DATE,
    'target_end_date deveria ser start + 14';

  -- Counts denormalizados ja vem certos
  ASSERT (SELECT tasks_total FROM onboardings WHERE id = v_onb_id) = 4, 'tasks_total denormalizado';
  ASSERT (SELECT tasks_required FROM onboardings WHERE id = v_onb_id) = 3, 'tasks_required denormalizado';
END $$;

SELECT test_log('OK · create_from_template faz deep copy + denormaliza counts');

-- ============================================================================
-- TESTE 10 · create_from_template · template archived bloqueia
-- ============================================================================

SELECT test_log('--- TESTE 10 · template archived bloqueia ---');

DO $$
DECLARE
  v_template_id UUID;
  v_result JSONB;
BEGIN
  PERFORM set_config('request.jwt.claim.sub', '77777777-7777-7777-7777-000000000002', TRUE);
  PERFORM test_cleanup_onboardings();

  v_result := rpc_onb_template_create('TPL-T10', 'Archived', NULL, 7);
  v_template_id := (v_result->>'template_id')::UUID;
  PERFORM rpc_onb_template_update(v_template_id, NULL, NULL, NULL, 'archived');

  v_result := rpc_onboarding_create_from_template(
    '00000000-0000-0000-A004-000000000004',
    v_template_id,
    'Tentativa de criar com archived',
    '2026-06-01'
  );
  ASSERT v_result->>'error' = 'template_archived',
    format('Esperado template_archived, obtido %s', v_result::TEXT);
END $$;

SELECT test_log('OK · template archived bloqueia instanciacao');

-- ============================================================================
-- TESTE 11 · create_blank · sem template
-- ============================================================================

SELECT test_log('--- TESTE 11 · create_blank ---');

DO $$
DECLARE
  v_result JSONB;
  v_onb_id UUID;
BEGIN
  PERFORM set_config('request.jwt.claim.sub', '77777777-7777-7777-7777-000000000002', TRUE);
  PERFORM test_cleanup_onboardings();

  v_result := rpc_onboarding_create_blank(
    '00000000-0000-0000-A004-000000000004',
    'Onboarding manual sem template',
    '2026-06-01',
    '2026-07-01',
    'Notas'
  );
  ASSERT v_result->>'ok' = 'true', format('Esperado ok, obtido %s', v_result::TEXT);
  v_onb_id := (v_result->>'onboarding_id')::UUID;

  ASSERT (SELECT source_template_id FROM onboardings WHERE id = v_onb_id) IS NULL,
    'source_template_id deveria ser NULL';
END $$;

SELECT test_log('OK · create_blank sem template');

-- ============================================================================
-- TESTE 12 · create cross-tenant bloqueado
-- ============================================================================

SELECT test_log('--- TESTE 12 · cross-tenant bloqueado ---');

DO $$
DECLARE
  v_result JSONB;
BEGIN
  -- Cria outro tenant + user
  INSERT INTO tenants (id, slug, legal_name, display_name) VALUES
    ('00000000-0000-0000-B000-000000000001', 'other-onb', 'Other ONB', 'Other');

  INSERT INTO app_users (id, tenant_id, auth_user_id, email, full_name, hired_at)
  VALUES (
    '00000000-0000-0000-B004-000000000001',
    '00000000-0000-0000-B000-000000000001',
    '88888888-8888-8888-8888-000000000001',
    'externo@other-onb.com', 'Externo Other', '2024-01-01'
  );

  -- RH do tenant A tenta criar onboarding para Externo (tenant B)
  PERFORM set_config('request.jwt.claim.sub', '77777777-7777-7777-7777-000000000002', TRUE);
  v_result := rpc_onboarding_create_blank(
    '00000000-0000-0000-B004-000000000001',
    'Cross tenant invalido',
    '2026-06-01',
    '2026-07-01'
  );
  ASSERT v_result->>'error' = 'cross_tenant_blocked',
    format('Esperado cross_tenant_blocked, obtido %s', v_result::TEXT);
END $$;

SELECT test_log('OK · cross-tenant bloqueado');

-- ============================================================================
-- TESTE 13 · task_complete por owner (nao precisa de manage_onboarding)
-- ============================================================================

SELECT test_log('--- TESTE 13 · task_complete por owner ---');

DO $$
DECLARE
  v_template_id UUID;
  v_stage_id UUID;
  v_onb_id UUID;
  v_task_id UUID;
  v_result JSONB;
BEGIN
  PERFORM set_config('request.jwt.claim.sub', '77777777-7777-7777-7777-000000000002', TRUE);  -- RH cria
  PERFORM test_cleanup_onboardings();

  v_result := rpc_onb_template_create('TPL-T13', 'Template T13', NULL, 7);
  v_template_id := (v_result->>'template_id')::UUID;
  PERFORM rpc_onb_template_update(v_template_id, NULL, NULL, NULL, 'published');

  v_result := rpc_onb_template_stage_add(v_template_id, 'Stage', NULL, 0, 7);
  v_stage_id := (v_result->>'stage_id')::UUID;
  PERFORM rpc_onb_template_task_add(v_stage_id, 'Task obrigatoria 1', NULL, 'task', 0, TRUE);

  v_result := rpc_onboarding_create_from_template(
    '00000000-0000-0000-A004-000000000005',
    v_template_id,
    'Onb T13',
    '2026-06-01'
  );
  v_onb_id := (v_result->>'onboarding_id')::UUID;

  SELECT id INTO v_task_id FROM onboarding_tasks WHERE onboarding_id = v_onb_id LIMIT 1;

  -- COL2 (owner) conclui sua propria task
  PERFORM set_config('request.jwt.claim.sub', '77777777-7777-7777-7777-000000000005', TRUE);
  v_result := rpc_onboarding_task_complete(v_task_id, 'Concluida');
  ASSERT v_result->>'ok' = 'true', format('Owner deveria concluir, obtido %s', v_result::TEXT);

  -- Onboarding deve ter mudado de not_started para in_progress
  ASSERT (SELECT status FROM onboardings WHERE id = v_onb_id) = 'in_progress',
    'Status deveria virar in_progress';
END $$;

SELECT test_log('OK · owner conclui task + onboarding auto-inicia');

-- ============================================================================
-- TESTE 14 · task_complete por colega (peer) bloqueado
-- ============================================================================

SELECT test_log('--- TESTE 14 · peer nao pode concluir task ---');

DO $$
DECLARE
  v_template_id UUID;
  v_stage_id UUID;
  v_onb_id UUID;
  v_task_id UUID;
  v_result JSONB;
BEGIN
  PERFORM set_config('request.jwt.claim.sub', '77777777-7777-7777-7777-000000000002', TRUE);
  PERFORM test_cleanup_onboardings();

  v_result := rpc_onb_template_create('TPL-T14', 'Template T14', NULL, 7);
  v_template_id := (v_result->>'template_id')::UUID;
  PERFORM rpc_onb_template_update(v_template_id, NULL, NULL, NULL, 'published');

  v_result := rpc_onb_template_stage_add(v_template_id, 'Stage', NULL, 0, 7);
  v_stage_id := (v_result->>'stage_id')::UUID;
  PERFORM rpc_onb_template_task_add(v_stage_id, 'Task X', NULL, 'task', 0, TRUE);

  v_result := rpc_onboarding_create_from_template(
    '00000000-0000-0000-A004-000000000004',  -- COL1
    v_template_id,
    'Onb T14 do COL1',
    '2026-06-01'
  );
  v_onb_id := (v_result->>'onboarding_id')::UUID;

  SELECT id INTO v_task_id FROM onboarding_tasks WHERE onboarding_id = v_onb_id LIMIT 1;

  -- COL2 (peer) tenta concluir task do COL1
  PERFORM set_config('request.jwt.claim.sub', '77777777-7777-7777-7777-000000000005', TRUE);
  v_result := rpc_onboarding_task_complete(v_task_id);
  ASSERT v_result->>'error' = 'permission_denied',
    format('Peer nao deveria concluir, obtido %s', v_result::TEXT);
END $$;

SELECT test_log('OK · peer bloqueado de concluir task');

-- ============================================================================
-- TESTE 15 · change_status · validacoes
-- ============================================================================

SELECT test_log('--- TESTE 15 · change_status validacoes ---');

DO $$
DECLARE
  v_onb_id UUID;
  v_stage_id UUID;
  v_result JSONB;
BEGIN
  PERFORM set_config('request.jwt.claim.sub', '77777777-7777-7777-7777-000000000002', TRUE);
  PERFORM test_cleanup_onboardings();

  v_result := rpc_onboarding_create_blank(
    '00000000-0000-0000-A004-000000000005',
    'Onb T15',
    '2026-06-01',
    '2026-07-01'
  );
  v_onb_id := (v_result->>'onboarding_id')::UUID;

  -- not_started -> completed (invalido)
  v_result := rpc_onboarding_change_status(v_onb_id, 'completed');
  ASSERT v_result->>'error' = 'invalid_transition', 'not_started -> completed invalido';

  -- not_started -> in_progress (valido)
  v_result := rpc_onboarding_change_status(v_onb_id, 'in_progress');
  ASSERT v_result->>'status' = 'in_progress', 'not_started -> in_progress valido';

  -- Sem tasks required (vazio), pode concluir direto
  v_result := rpc_onboarding_change_status(v_onb_id, 'completed');
  ASSERT v_result->>'status' = 'completed', 'in_progress -> completed (sem required) valido';

  -- Tentar reabrir (locked)
  v_result := rpc_onboarding_change_status(v_onb_id, 'in_progress');
  ASSERT v_result->>'error' = 'onboarding_locked', 'completed -> qualquer e locked';
END $$;

SELECT test_log('OK · change_status valida transicoes e locked');

-- ============================================================================
-- TESTE 16 · change_status · required pendentes bloqueia conclusao
-- ============================================================================

SELECT test_log('--- TESTE 16 · required pendentes bloqueia conclusao ---');

DO $$
DECLARE
  v_template_id UUID;
  v_stage_id UUID;
  v_onb_id UUID;
  v_task_id UUID;
  v_result JSONB;
  v_task_ids UUID[];
BEGIN
  PERFORM set_config('request.jwt.claim.sub', '77777777-7777-7777-7777-000000000002', TRUE);
  PERFORM test_cleanup_onboardings();

  v_result := rpc_onb_template_create('TPL-T16', 'Template T16', NULL, 7);
  v_template_id := (v_result->>'template_id')::UUID;
  PERFORM rpc_onb_template_update(v_template_id, NULL, NULL, NULL, 'published');

  v_result := rpc_onb_template_stage_add(v_template_id, 'Stage', NULL, 0, 7);
  v_stage_id := (v_result->>'stage_id')::UUID;
  PERFORM rpc_onb_template_task_add(v_stage_id, 'Required A', NULL, 'task', 0, TRUE);
  PERFORM rpc_onb_template_task_add(v_stage_id, 'Required B', NULL, 'task', 1, TRUE);
  PERFORM rpc_onb_template_task_add(v_stage_id, 'Optional', NULL, 'task', 2, FALSE);

  v_result := rpc_onboarding_create_from_template(
    '00000000-0000-0000-A004-000000000005',
    v_template_id,
    'Onb T16',
    '2026-06-01'
  );
  v_onb_id := (v_result->>'onboarding_id')::UUID;

  -- Mover para in_progress
  PERFORM rpc_onboarding_change_status(v_onb_id, 'in_progress');

  -- Tentar concluir com 2 required pendentes
  v_result := rpc_onboarding_change_status(v_onb_id, 'completed');
  ASSERT v_result->>'error' = 'required_tasks_pending',
    format('Esperado required_tasks_pending, obtido %s', v_result::TEXT);
  ASSERT (v_result->>'pending')::INT = 2, 'Esperado pending=2';

  -- Concluir as obrigatorias
  SELECT array_agg(id) INTO v_task_ids
  FROM onboarding_tasks WHERE onboarding_id = v_onb_id AND is_required = TRUE;

  FOREACH v_task_id IN ARRAY v_task_ids LOOP
    PERFORM rpc_onboarding_task_complete(v_task_id);
  END LOOP;

  -- Agora consegue concluir
  v_result := rpc_onboarding_change_status(v_onb_id, 'completed');
  ASSERT v_result->>'status' = 'completed', 'Deveria conseguir concluir';
END $$;

SELECT test_log('OK · required pendentes bloqueiam conclusao');

-- ============================================================================
-- TESTE 17 · change_status · cancel exige razao
-- ============================================================================

SELECT test_log('--- TESTE 17 · cancel exige razao ---');

DO $$
DECLARE
  v_onb_id UUID;
  v_result JSONB;
BEGIN
  PERFORM set_config('request.jwt.claim.sub', '77777777-7777-7777-7777-000000000002', TRUE);
  PERFORM test_cleanup_onboardings();

  v_result := rpc_onboarding_create_blank(
    '00000000-0000-0000-A004-000000000004',
    'Onb T17',
    '2026-06-01',
    '2026-07-01'
  );
  v_onb_id := (v_result->>'onboarding_id')::UUID;

  v_result := rpc_onboarding_change_status(v_onb_id, 'canceled');
  ASSERT v_result->>'error' = 'cancel_reason_required', 'Sem razao deveria falhar';

  v_result := rpc_onboarding_change_status(v_onb_id, 'canceled', 'Mudanca de planos');
  ASSERT v_result->>'status' = 'canceled', 'Com razao valida deveria funcionar';
END $$;

SELECT test_log('OK · cancel exige razao');

-- ============================================================================
-- TESTE 18 · onboarding_can_read · helper
-- ============================================================================

SELECT test_log('--- TESTE 18 · onboarding_can_read ---');

DO $$
DECLARE
  v_onb_id UUID;
  v_result JSONB;
BEGIN
  PERFORM set_config('request.jwt.claim.sub', '77777777-7777-7777-7777-000000000002', TRUE);
  PERFORM test_cleanup_onboardings();
  v_result := rpc_onboarding_create_blank(
    '00000000-0000-0000-A004-000000000004',  -- COL1
    'Onb T18',
    '2026-06-01',
    '2026-07-01'
  );
  v_onb_id := (v_result->>'onboarding_id')::UUID;

  -- COL1 (owner) le
  PERFORM set_config('request.jwt.claim.sub', '77777777-7777-7777-7777-000000000004', TRUE);
  ASSERT onboarding_can_read(v_onb_id) = TRUE, 'COL1 (owner) deveria ler';

  -- COL2 (peer) NAO le
  PERFORM set_config('request.jwt.claim.sub', '77777777-7777-7777-7777-000000000005', TRUE);
  ASSERT onboarding_can_read(v_onb_id) = FALSE, 'COL2 (peer) NAO deveria ler';

  -- LID (manager) le
  PERFORM set_config('request.jwt.claim.sub', '77777777-7777-7777-7777-000000000003', TRUE);
  ASSERT onboarding_can_read(v_onb_id) = TRUE, 'LID (manager) deveria ler';

  -- DIR (manager indireto) le
  PERFORM set_config('request.jwt.claim.sub', '77777777-7777-7777-7777-000000000001', TRUE);
  ASSERT onboarding_can_read(v_onb_id) = TRUE, 'DIR (manager indireto) deveria ler';

  -- RH le
  PERFORM set_config('request.jwt.claim.sub', '77777777-7777-7777-7777-000000000002', TRUE);
  ASSERT onboarding_can_read(v_onb_id) = TRUE, 'RH deveria ler';
END $$;

SELECT test_log('OK · onboarding_can_read respeita owner/manager/RH/Dir');

-- ============================================================================
-- TESTE 19 · list por escopo
-- ============================================================================

SELECT test_log('--- TESTE 19 · list por escopo ---');

DO $$
DECLARE
  v_result JSONB;
  v_count INT;
BEGIN
  -- LID consegue 'team' (e tambem 'all' pois tem view_onboarding)
  PERFORM set_config('request.jwt.claim.sub', '77777777-7777-7777-7777-000000000003', TRUE);
  v_result := rpc_onboarding_list('team');
  v_count := jsonb_array_length(v_result->'items');
  ASSERT v_count >= 1, format('Lider deveria ver time, obtido %s', v_count);

  v_result := rpc_onboarding_list('all');
  ASSERT v_result->>'ok' = 'true', 'Lider tem view_onboarding · pode listar all';

  -- COL1 (sem nenhuma permissao do modulo) NAO consegue 'all'
  PERFORM set_config('request.jwt.claim.sub', '77777777-7777-7777-7777-000000000004', TRUE);
  v_result := rpc_onboarding_list('all');
  ASSERT v_result->>'error' = 'permission_denied',
    format('Colaborador sem perm nao deveria ler all, obtido %s', v_result::TEXT);

  -- Mas consegue 'own' (ate sem permissoes · escopo proprio)
  v_result := rpc_onboarding_list('own');
  ASSERT v_result->>'ok' = 'true', 'Colaborador deveria conseguir listar proprio';

  -- DIR consegue 'all'
  PERFORM set_config('request.jwt.claim.sub', '77777777-7777-7777-7777-000000000001', TRUE);
  v_result := rpc_onboarding_list('all');
  ASSERT v_result->>'ok' = 'true', 'Diretoria deveria conseguir all';
END $$;

SELECT test_log('OK · list por escopo respeita permissoes');

-- ============================================================================
-- TESTE 20 · get_by_id · enriquecido com stages e tasks
-- ============================================================================

SELECT test_log('--- TESTE 20 · get_by_id ---');

DO $$
DECLARE
  v_template_id UUID;
  v_stage_id UUID;
  v_onb_id UUID;
  v_result JSONB;
BEGIN
  PERFORM set_config('request.jwt.claim.sub', '77777777-7777-7777-7777-000000000002', TRUE);
  PERFORM test_cleanup_onboardings();

  v_result := rpc_onb_template_create('TPL-T20', 'Template T20', NULL, 14);
  v_template_id := (v_result->>'template_id')::UUID;
  PERFORM rpc_onb_template_update(v_template_id, NULL, NULL, NULL, 'published');

  v_result := rpc_onb_template_stage_add(v_template_id, 'Stage A', NULL, 0, 7);
  v_stage_id := (v_result->>'stage_id')::UUID;
  PERFORM rpc_onb_template_task_add(v_stage_id, 'Task 1', NULL, 'task', 0, TRUE);
  PERFORM rpc_onb_template_task_add(v_stage_id, 'Task 2', NULL, 'task', 2, TRUE);

  v_result := rpc_onboarding_create_from_template(
    '00000000-0000-0000-A004-000000000005',
    v_template_id,
    'Onb T20',
    '2026-06-01',
    'Notas do RH'
  );
  v_onb_id := (v_result->>'onboarding_id')::UUID;

  v_result := rpc_onboarding_get_by_id(v_onb_id);
  ASSERT v_result->>'ok' = 'true', 'get_by_id deveria funcionar';
  ASSERT v_result->'onboarding'->>'display_name' = 'Onb T20', 'display_name correto';
  ASSERT v_result->'onboarding'->>'source_template_name' = 'Template T20', 'template name enriquecido';
  ASSERT v_result->'onboarding'->>'manager_name' = 'Lider ONB', 'manager_name enriquecido';
  ASSERT jsonb_array_length(v_result->'stages') = 1, 'deveria ter 1 stage';
  ASSERT jsonb_array_length(v_result->'stages'->0->'tasks') = 2, 'stage deveria ter 2 tasks';
END $$;

SELECT test_log('OK · get_by_id retorna onboarding + stages + tasks');

-- ============================================================================
-- TESTE 21 · CASCADE de tenant deleta tudo
-- ============================================================================

SELECT test_log('--- TESTE 21 · CASCADE de tenant ---');

DO $$
DECLARE
  v_tenant UUID := '00000000-0000-0000-C000-000000000001';
  v_user UUID;
  v_template UUID;
  v_stage UUID;
  v_onb UUID;
  v_count INT;
BEGIN
  INSERT INTO tenants (id, slug, legal_name, display_name)
  VALUES (v_tenant, 'cascade-onb', 'Cascade ONB', 'CSC');

  INSERT INTO app_users (id, tenant_id, email, full_name, hired_at, role)
  VALUES (gen_random_uuid(), v_tenant, 'cascade@test.com', 'Cascade', '2024-01-01', 'rh')
  RETURNING id INTO v_user;

  INSERT INTO onb_templates (tenant_id, code, display_name, created_by)
  VALUES (v_tenant, 'CASCADE', 'Cascade Template', v_user)
  RETURNING id INTO v_template;

  INSERT INTO onb_template_stages (tenant_id, template_id, display_name)
  VALUES (v_tenant, v_template, 'Stage')
  RETURNING id INTO v_stage;

  INSERT INTO onb_template_tasks (tenant_id, template_id, stage_id, title)
  VALUES (v_tenant, v_template, v_stage, 'Cascade task');

  INSERT INTO onboardings (tenant_id, user_id, display_name, start_date, target_end_date, created_by)
  VALUES (v_tenant, v_user, 'Cascade onb', '2026-01-01', '2026-02-01', v_user)
  RETURNING id INTO v_onb;

  -- Delete tenant
  DELETE FROM tenants WHERE id = v_tenant;

  SELECT count(*) INTO v_count FROM onb_templates WHERE tenant_id = v_tenant;
  ASSERT v_count = 0, 'templates deveriam ter cascateado';

  SELECT count(*) INTO v_count FROM onb_template_stages WHERE tenant_id = v_tenant;
  ASSERT v_count = 0, 'template_stages deveriam ter cascateado';

  SELECT count(*) INTO v_count FROM onb_template_tasks WHERE tenant_id = v_tenant;
  ASSERT v_count = 0, 'template_tasks deveriam ter cascateado';

  SELECT count(*) INTO v_count FROM onboardings WHERE tenant_id = v_tenant;
  ASSERT v_count = 0, 'onboardings deveriam ter cascateado';
END $$;

SELECT test_log('OK · CASCADE de tenant deleta tudo');

-- ============================================================================
-- TESTE 22 · Idempotencia de seed (re-aplicar nao falha)
-- ============================================================================

SELECT test_log('--- TESTE 22 · Idempotencia ---');

DO $$
DECLARE
  v_before INT;
  v_after INT;
BEGIN
  SELECT count(*) INTO v_before FROM permissions WHERE module = 'onboarding';

  -- Re-inserir mesmas permissoes
  INSERT INTO permissions (code, module, description) VALUES
    ('view_onboarding',   'onboarding', 'Test re-insert'),
    ('manage_onboarding', 'onboarding', 'Test re-insert')
  ON CONFLICT (code) DO NOTHING;

  SELECT count(*) INTO v_after FROM permissions WHERE module = 'onboarding';
  ASSERT v_before = v_after, format('Re-aplicar nao deveria duplicar (antes %s, depois %s)', v_before, v_after);
END $$;

SELECT test_log('OK · idempotencia');

-- ============================================================================
-- FINAL
-- ============================================================================

SELECT test_log('=== TODOS OS TESTES PASSARAM ===');

ROLLBACK;

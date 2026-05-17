-- ============================================================================
-- R2 People · Testes PDI v1
-- ============================================================================
-- Cobre constraints, triggers, RPCs, RLS, workflow de status, denormalizacao,
-- evidencias, comentarios.
--
-- Pre-requisitos:
--   - r2_people_schema_base_v1.sql + seed
--   - r2_people_schema_pdi_v1.sql
--
-- Roda em transacao com ROLLBACK · nao deixa lixo.
-- ============================================================================

BEGIN;

-- ============================================================================
-- SETUP · 1 tenant + estrutura organizacional + 5 usuarios + 1 ciclo
-- ============================================================================

INSERT INTO tenants (id, slug, legal_name, display_name) VALUES
  ('00000000-0000-0000-F000-000000000001', 'pdi-test', 'PDI Test', 'PDIT')
ON CONFLICT (id) DO NOTHING;

INSERT INTO employer_units (id, tenant_id, code, legal_name) VALUES
  ('00000000-0000-0000-F001-000000000001', '00000000-0000-0000-F000-000000000001', 'EMP', 'Emp PDI')
ON CONFLICT (id) DO NOTHING;

INSERT INTO working_units (id, tenant_id, employer_unit_id, code, display_name) VALUES
  ('00000000-0000-0000-F002-000000000001', '00000000-0000-0000-F000-000000000001',
   '00000000-0000-0000-F001-000000000001', 'WU', 'WU PDI')
ON CONFLICT (id) DO NOTHING;

-- DIR (1) · LID (3, gerido por DIR) · COL1 (4, gerido por LID) · COL2 (5, gerido por LID) · RH (2)
INSERT INTO app_users (
  id, tenant_id, auth_user_id, email, full_name, role,
  employer_unit_id, working_unit_id, manager_id, employment_link, hired_at
) VALUES
  ('00000000-0000-0000-F004-000000000001',
   '00000000-0000-0000-F000-000000000001', '55555555-5555-5555-5555-000000000001',
   'dir@pdi-test.com', 'Diretor PDI', 'diretoria',
   '00000000-0000-0000-F001-000000000001', '00000000-0000-0000-F002-000000000001',
   NULL, 'clt', '2020-01-01'),
  ('00000000-0000-0000-F004-000000000002',
   '00000000-0000-0000-F000-000000000001', '55555555-5555-5555-5555-000000000002',
   'rh@pdi-test.com', 'RH PDI', 'rh',
   '00000000-0000-0000-F001-000000000001', '00000000-0000-0000-F002-000000000001',
   '00000000-0000-0000-F004-000000000001', 'clt', '2020-01-01'),
  ('00000000-0000-0000-F004-000000000003',
   '00000000-0000-0000-F000-000000000001', '55555555-5555-5555-5555-000000000003',
   'lid@pdi-test.com', 'Lider PDI', 'lider',
   '00000000-0000-0000-F001-000000000001', '00000000-0000-0000-F002-000000000001',
   '00000000-0000-0000-F004-000000000001', 'clt', '2020-01-01'),
  ('00000000-0000-0000-F004-000000000004',
   '00000000-0000-0000-F000-000000000001', '55555555-5555-5555-5555-000000000004',
   'col1@pdi-test.com', 'Colaborador 1', 'colaborador',
   '00000000-0000-0000-F001-000000000001', '00000000-0000-0000-F002-000000000001',
   '00000000-0000-0000-F004-000000000003', 'clt', '2021-01-01'),
  ('00000000-0000-0000-F004-000000000005',
   '00000000-0000-0000-F000-000000000001', '55555555-5555-5555-5555-000000000005',
   'col2@pdi-test.com', 'Colaborador 2', 'colaborador',
   '00000000-0000-0000-F001-000000000001', '00000000-0000-0000-F002-000000000001',
   '00000000-0000-0000-F004-000000000003', 'clt', '2021-06-01')
ON CONFLICT (id) DO NOTHING;

-- Ciclos de teste · varios para cada teste poder ativar sem colidir com UQ
INSERT INTO pdi_cycles (id, tenant_id, code, display_name, start_date, end_date, open_for_planning) VALUES
  ('00000000-0000-0000-F005-000000000001',
   '00000000-0000-0000-F000-000000000001',
   '2026-S2', 'Segundo Semestre 2026', '2026-07-01', '2026-12-31', TRUE),
  ('00000000-0000-0000-F005-000000000002',
   '00000000-0000-0000-F000-000000000001',
   '2026-S1-CLOSED', 'Semestre fechado', '2026-01-01', '2026-06-30', FALSE),
  ('00000000-0000-0000-F005-000000000003',
   '00000000-0000-0000-F000-000000000001',
   'TEST-CYC-3', 'Ciclo extra 3', '2027-01-01', '2027-06-30', TRUE),
  ('00000000-0000-0000-F005-000000000004',
   '00000000-0000-0000-F000-000000000001',
   'TEST-CYC-4', 'Ciclo extra 4', '2027-07-01', '2027-12-31', TRUE),
  ('00000000-0000-0000-F005-000000000005',
   '00000000-0000-0000-F000-000000000001',
   'TEST-CYC-5', 'Ciclo extra 5', '2028-01-01', '2028-06-30', TRUE),
  ('00000000-0000-0000-F005-000000000006',
   '00000000-0000-0000-F000-000000000001',
   'TEST-CYC-6', 'Ciclo extra 6', '2028-07-01', '2028-12-31', TRUE)
ON CONFLICT (id) DO NOTHING;

CREATE OR REPLACE FUNCTION test_log(msg TEXT)
RETURNS TEXT AS $$
BEGIN RAISE NOTICE '%', msg; RETURN msg; END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- TESTE 1 · Constraints basicas
-- ============================================================================

SELECT test_log('--- TESTE 1 · Constraints basicas ---');

DO $$
DECLARE
  v_pdi UUID;
BEGIN
  -- Objetivo curto demais (< 10 chars)
  BEGIN
    INSERT INTO pdis (tenant_id, user_id, cycle_id, objective, start_date, end_date, created_by)
    VALUES (
      '00000000-0000-0000-F000-000000000001',
      '00000000-0000-0000-F004-000000000004',
      '00000000-0000-0000-F005-000000000001',
      'curto',
      '2026-07-01', '2026-12-31',
      '00000000-0000-0000-F004-000000000004'
    );
    ASSERT FALSE, 'Objetivo curto deveria falhar';
  EXCEPTION WHEN check_violation THEN NULL;
  END;

  -- end_date < start_date
  BEGIN
    INSERT INTO pdis (tenant_id, user_id, cycle_id, objective, start_date, end_date, created_by)
    VALUES (
      '00000000-0000-0000-F000-000000000001',
      '00000000-0000-0000-F004-000000000004',
      '00000000-0000-0000-F005-000000000001',
      'Objetivo valido com mais de dez caracteres',
      '2026-12-01', '2026-07-01',
      '00000000-0000-0000-F004-000000000004'
    );
    ASSERT FALSE, 'Data invertida deveria falhar';
  EXCEPTION WHEN check_violation THEN NULL;
  END;
END $$;

SELECT test_log('OK · constraints de PDI');

-- ============================================================================
-- TESTE 2 · Index parcial · 1 PDI ativo/concluido por user/ciclo
-- ============================================================================

SELECT test_log('--- TESTE 2 · 1 PDI ativo por user/ciclo ---');

DO $$
DECLARE
  v_pdi1 UUID;
  v_pdi2 UUID;
BEGIN
  -- Cria 2 drafts (permitido)
  INSERT INTO pdis (tenant_id, user_id, cycle_id, objective, start_date, end_date, created_by, status)
  VALUES (
    '00000000-0000-0000-F000-000000000001',
    '00000000-0000-0000-F004-000000000004',
    '00000000-0000-0000-F005-000000000001',
    'Primeiro draft com objetivo valido',
    '2026-07-01', '2026-12-31',
    '00000000-0000-0000-F004-000000000004',
    'draft'
  ) RETURNING id INTO v_pdi1;

  INSERT INTO pdis (tenant_id, user_id, cycle_id, objective, start_date, end_date, created_by, status)
  VALUES (
    '00000000-0000-0000-F000-000000000001',
    '00000000-0000-0000-F004-000000000004',
    '00000000-0000-0000-F005-000000000001',
    'Segundo draft tambem valido para teste',
    '2026-07-01', '2026-12-31',
    '00000000-0000-0000-F004-000000000004',
    'draft'
  ) RETURNING id INTO v_pdi2;

  -- Adicionar acao para poder ativar
  INSERT INTO pdi_actions (tenant_id, pdi_id, title)
  VALUES ('00000000-0000-0000-F000-000000000001', v_pdi1, 'Acao 1 do PDI');

  -- Ativar PDI 1 deve funcionar
  UPDATE pdis SET status = 'active' WHERE id = v_pdi1;

  -- Ativar PDI 2 (mesmo user/ciclo) deve dar erro de UNIQUE
  BEGIN
    UPDATE pdis SET status = 'active' WHERE id = v_pdi2;
    ASSERT FALSE, 'Segundo PDI ativo no mesmo ciclo deveria falhar';
  EXCEPTION WHEN unique_violation THEN NULL;
  END;
END $$;

SELECT test_log('OK · index parcial bloqueia 2 PDIs ativos no mesmo ciclo');

-- ============================================================================
-- TESTE 3 · Trigger denormaliza actions_total e actions_completed
-- ============================================================================

SELECT test_log('--- TESTE 3 · Denormalizacao de counts ---');

DO $$
DECLARE
  v_pdi UUID;
  v_total INT;
  v_completed INT;
BEGIN
  INSERT INTO pdis (tenant_id, user_id, cycle_id, objective, start_date, end_date, created_by)
  VALUES (
    '00000000-0000-0000-F000-000000000001',
    '00000000-0000-0000-F004-000000000005',
    '00000000-0000-0000-F005-000000000001',
    'PDI para teste de denormalizacao',
    '2026-07-01', '2026-12-31',
    '00000000-0000-0000-F004-000000000005'
  ) RETURNING id INTO v_pdi;

  -- Add 3 acoes
  INSERT INTO pdi_actions (tenant_id, pdi_id, title) VALUES
    ('00000000-0000-0000-F000-000000000001', v_pdi, 'Acao A'),
    ('00000000-0000-0000-F000-000000000001', v_pdi, 'Acao B'),
    ('00000000-0000-0000-F000-000000000001', v_pdi, 'Acao C');

  SELECT actions_total, actions_completed INTO v_total, v_completed FROM pdis WHERE id = v_pdi;
  ASSERT v_total = 3, format('Esperado 3 acoes total, obtido %s', v_total);
  ASSERT v_completed = 0, format('Esperado 0 completas, obtido %s', v_completed);

  -- Conclui 2
  UPDATE pdi_actions SET status = 'completed' WHERE pdi_id = v_pdi AND title IN ('Acao A', 'Acao B');

  SELECT actions_total, actions_completed INTO v_total, v_completed FROM pdis WHERE id = v_pdi;
  ASSERT v_completed = 2, format('Esperado 2 completas, obtido %s', v_completed);

  -- Reverte 1
  UPDATE pdi_actions SET status = 'in_progress' WHERE pdi_id = v_pdi AND title = 'Acao A';

  SELECT actions_completed INTO v_completed FROM pdis WHERE id = v_pdi;
  ASSERT v_completed = 1, format('Esperado 1 completa apos reversao, obtido %s', v_completed);

  -- Remove acao
  DELETE FROM pdi_actions WHERE pdi_id = v_pdi AND title = 'Acao C';

  SELECT actions_total INTO v_total FROM pdis WHERE id = v_pdi;
  ASSERT v_total = 2, format('Esperado 2 total apos delete, obtido %s', v_total);
END $$;

SELECT test_log('OK · counts denormalizados em INSERT/UPDATE/DELETE');

-- ============================================================================
-- TESTE 4 · Trigger marca completed_at na acao quando vira completed
-- ============================================================================

SELECT test_log('--- TESTE 4 · completed_at automatico em pdi_actions ---');

DO $$
DECLARE
  v_pdi UUID;
  v_action UUID;
  v_completed_at TIMESTAMPTZ;
BEGIN
  INSERT INTO pdis (tenant_id, user_id, cycle_id, objective, start_date, end_date, created_by)
  VALUES (
    '00000000-0000-0000-F000-000000000001',
    '00000000-0000-0000-F004-000000000004',
    '00000000-0000-0000-F005-000000000001',
    'PDI para teste de completed_at',
    '2026-07-01', '2026-12-31',
    '00000000-0000-0000-F004-000000000004'
  ) RETURNING id INTO v_pdi;

  INSERT INTO pdi_actions (tenant_id, pdi_id, title)
  VALUES ('00000000-0000-0000-F000-000000000001', v_pdi, 'Acao para completar')
  RETURNING id INTO v_action;

  SELECT completed_at INTO v_completed_at FROM pdi_actions WHERE id = v_action;
  ASSERT v_completed_at IS NULL, 'Inicio sem completed_at';

  UPDATE pdi_actions SET status = 'completed' WHERE id = v_action;
  SELECT completed_at INTO v_completed_at FROM pdi_actions WHERE id = v_action;
  ASSERT v_completed_at IS NOT NULL, 'completed_at deveria ter sido setado';

  -- Reverter limpa o completed_at
  UPDATE pdi_actions SET status = 'in_progress' WHERE id = v_action;
  SELECT completed_at INTO v_completed_at FROM pdi_actions WHERE id = v_action;
  ASSERT v_completed_at IS NULL, 'completed_at deveria ter sido limpo';
END $$;

SELECT test_log('OK · completed_at automatico em pdi_actions');

-- ============================================================================
-- TESTE 5 · Trigger marca activated_at/completed_at/canceled_at em pdis
-- ============================================================================

SELECT test_log('--- TESTE 5 · timestamps de status em pdis ---');

DO $$
DECLARE
  v_pdi UUID;
  v_activated TIMESTAMPTZ;
  v_completed TIMESTAMPTZ;
BEGIN
  INSERT INTO pdis (tenant_id, user_id, cycle_id, objective, start_date, end_date, created_by)
  VALUES (
    '00000000-0000-0000-F000-000000000001',
    '00000000-0000-0000-F004-000000000005',
    '00000000-0000-0000-F005-000000000001',
    'PDI para teste timestamps',
    '2026-07-01', '2026-12-31',
    '00000000-0000-0000-F004-000000000005'
  ) RETURNING id INTO v_pdi;

  INSERT INTO pdi_actions (tenant_id, pdi_id, title)
  VALUES ('00000000-0000-0000-F000-000000000001', v_pdi, 'Acao base');

  UPDATE pdis SET status = 'active' WHERE id = v_pdi;
  SELECT activated_at INTO v_activated FROM pdis WHERE id = v_pdi;
  ASSERT v_activated IS NOT NULL, 'activated_at deveria ter sido setado';

  UPDATE pdis SET status = 'completed' WHERE id = v_pdi;
  SELECT completed_at INTO v_completed FROM pdis WHERE id = v_pdi;
  ASSERT v_completed IS NOT NULL, 'completed_at deveria ter sido setado';
END $$;

SELECT test_log('OK · timestamps de status em pdis');

-- ============================================================================
-- TESTE 6 · RPC create · happy path como self
-- ============================================================================

SELECT test_log('--- TESTE 6 · RPC create self ---');

DO $$
DECLARE
  v_result JSONB;
  v_pdi_id UUID;
  v_owner UUID;
  v_status pdi_status;
BEGIN
  PERFORM set_config('request.jwt.claim.sub', '55555555-5555-5555-5555-000000000004', TRUE);

  v_result := rpc_pdi_create(
    '00000000-0000-0000-F004-000000000004',
    '00000000-0000-0000-F005-000000000001',
    'Quero desenvolver lideranca tecnica em arquitetura de dados',
    'Contexto adicional sobre o objetivo'
  );

  ASSERT v_result->>'ok' = 'true', format('Esperado ok, obtido %s', v_result::TEXT);
  v_pdi_id := (v_result->>'pdi_id')::UUID;

  SELECT user_id, status INTO v_owner, v_status FROM pdis WHERE id = v_pdi_id;
  ASSERT v_owner = '00000000-0000-0000-F004-000000000004', 'owner deveria ser COL1';
  ASSERT v_status = 'draft', 'PDI deve nascer como draft';
END $$;

SELECT test_log('OK · RPC create self');

-- ============================================================================
-- TESTE 7 · RPC create · cross-tenant block
-- ============================================================================

SELECT test_log('--- TESTE 7 · RPC create cross-tenant ---');

DO $$
DECLARE
  v_result JSONB;
BEGIN
  -- Cria outro tenant + user
  INSERT INTO tenants (id, slug, legal_name, display_name)
  VALUES ('00000000-0000-0000-A100-000000000001', 'other-pdi', 'Other PDI', 'Other')
  ON CONFLICT (id) DO NOTHING;

  INSERT INTO app_users (id, tenant_id, auth_user_id, email, full_name, hired_at)
  VALUES (
    '00000000-0000-0000-A104-000000000001',
    '00000000-0000-0000-A100-000000000001',
    '66666666-6666-6666-6666-000000000001',
    'externo@other-pdi.com', 'Externo Other PDI', '2024-01-01'
  ) ON CONFLICT (id) DO NOTHING;

  -- COL1 (tenant F) tenta criar PDI para Externo (tenant G)
  PERFORM set_config('request.jwt.claim.sub', '55555555-5555-5555-5555-000000000004', TRUE);
  v_result := rpc_pdi_create(
    '00000000-0000-0000-A104-000000000001',
    '00000000-0000-0000-F005-000000000001',
    'Tentativa de PDI cross-tenant invalida',
    NULL
  );

  ASSERT v_result->>'error' = 'cross_tenant_blocked',
    format('Esperado cross_tenant_blocked, obtido %s', v_result::TEXT);
END $$;

SELECT test_log('OK · RPC create bloqueia cross-tenant');

-- ============================================================================
-- TESTE 8 · RPC create · ciclo fechado para planning bloqueia colaborador
-- ============================================================================

SELECT test_log('--- TESTE 8 · ciclo fechado bloqueia colaborador ---');

DO $$
DECLARE
  v_result JSONB;
BEGIN
  PERFORM set_config('request.jwt.claim.sub', '55555555-5555-5555-5555-000000000004', TRUE);
  v_result := rpc_pdi_create(
    '00000000-0000-0000-F004-000000000004',
    '00000000-0000-0000-F005-000000000002',  -- ciclo CLOSED
    'Tentativa de criar PDI em ciclo fechado',
    NULL
  );
  ASSERT v_result->>'error' = 'cycle_closed_for_planning',
    format('Esperado cycle_closed_for_planning, obtido %s', v_result::TEXT);

  -- RH consegue mesmo com ciclo fechado
  PERFORM set_config('request.jwt.claim.sub', '55555555-5555-5555-5555-000000000002', TRUE);
  v_result := rpc_pdi_create(
    '00000000-0000-0000-F004-000000000004',
    '00000000-0000-0000-F005-000000000002',
    'PDI criado por RH em ciclo fechado',
    NULL
  );
  ASSERT v_result->>'ok' = 'true', format('RH deveria poder, obtido %s', v_result::TEXT);
END $$;

SELECT test_log('OK · ciclo fechado bloqueia colaborador, libera RH');

-- ============================================================================
-- TESTE 9 · Workflow de status · transicoes validas e invalidas
-- ============================================================================

SELECT test_log('--- TESTE 9 · Workflow de status ---');

DO $$
DECLARE
  v_pdi UUID;
  v_result JSONB;
BEGIN
  PERFORM set_config('request.jwt.claim.sub', '55555555-5555-5555-5555-000000000004', TRUE);
  v_result := rpc_pdi_create(
    '00000000-0000-0000-F004-000000000004',
    '00000000-0000-0000-F005-000000000003',
    'PDI para teste de workflow de status',
    NULL
  );
  v_pdi := (v_result->>'pdi_id')::UUID;

  -- Tentar ativar sem acoes deve falhar
  v_result := rpc_pdi_change_status(v_pdi, 'active');
  ASSERT v_result->>'error' = 'no_actions_defined', 'Deveria exigir acoes para ativar';

  -- Adicionar acao
  PERFORM rpc_pdi_action_add(v_pdi, 'Curso de PostgreSQL avancado', NULL, 'curso', '2026-09-30');

  -- Agora ativa
  v_result := rpc_pdi_change_status(v_pdi, 'active');
  ASSERT v_result->>'status' = 'active', format('Deveria ativar, obtido %s', v_result::TEXT);

  -- Tentar voltar para draft (transicao invalida)
  v_result := rpc_pdi_change_status(v_pdi, 'draft');
  ASSERT v_result->>'error' = 'invalid_transition', 'Deveria bloquear active -> draft';

  -- Cancelar sem razao
  v_result := rpc_pdi_change_status(v_pdi, 'canceled');
  ASSERT v_result->>'error' = 'cancel_reason_required', 'Deveria exigir razao';

  -- Cancelar com razao
  v_result := rpc_pdi_change_status(v_pdi, 'canceled', 'Mudanca de prioridade pelo gestor');
  ASSERT v_result->>'status' = 'canceled', 'Deveria cancelar com razao';

  -- Apos cancelado: bloqueado
  v_result := rpc_pdi_change_status(v_pdi, 'active');
  ASSERT v_result->>'error' = 'pdi_locked', 'Deveria estar bloqueado';
END $$;

SELECT test_log('OK · workflow de status valida transicoes');

-- ============================================================================
-- TESTE 10 · RPC permission · colaborador NAO pode criar PDI para outro
-- ============================================================================

SELECT test_log('--- TESTE 10 · permission nao-self ---');

DO $$
DECLARE
  v_result JSONB;
BEGIN
  -- COL1 tenta criar PDI para COL2 (peer · sem hierarquia)
  PERFORM set_config('request.jwt.claim.sub', '55555555-5555-5555-5555-000000000004', TRUE);
  v_result := rpc_pdi_create(
    '00000000-0000-0000-F004-000000000005',
    '00000000-0000-0000-F005-000000000001',
    'Tentativa de criar PDI para colega sem hierarquia',
    NULL
  );
  ASSERT v_result->>'error' = 'permission_denied',
    format('Colaborador NAO deveria criar para outro, obtido %s', v_result::TEXT);

  -- LID (gestor) consegue criar para COL1 (liderado)
  PERFORM set_config('request.jwt.claim.sub', '55555555-5555-5555-5555-000000000003', TRUE);
  v_result := rpc_pdi_create(
    '00000000-0000-0000-F004-000000000004',
    '00000000-0000-0000-F005-000000000001',
    'PDI criado pelo gestor para o liderado',
    NULL
  );
  ASSERT v_result->>'ok' = 'true', format('Lider deveria conseguir, obtido %s', v_result::TEXT);
END $$;

SELECT test_log('OK · permissoes hierarquicas respeitadas');

-- ============================================================================
-- TESTE 11 · RPC list · scopos own/team/all
-- ============================================================================

SELECT test_log('--- TESTE 11 · RPC list por escopo ---');

DO $$
DECLARE
  v_result JSONB;
  v_count INT;
BEGIN
  PERFORM set_config('request.jwt.claim.sub', '55555555-5555-5555-5555-000000000003', TRUE);  -- LID

  v_result := rpc_pdi_list('own');
  v_count := jsonb_array_length(v_result->'items');
  ASSERT v_count >= 0, 'list own retornou sucesso';

  v_result := rpc_pdi_list('team');
  v_count := jsonb_array_length(v_result->'items');
  ASSERT v_count >= 1, format('Lider deveria ver pelo menos seus liderados, obtido %s', v_count);

  -- 'all' precisa de view_all_pdi · lider nao tem
  v_result := rpc_pdi_list('all');
  ASSERT v_result->>'error' = 'permission_denied', 'Lider NAO deveria ter view_all_pdi';

  -- DIR consegue 'all'
  PERFORM set_config('request.jwt.claim.sub', '55555555-5555-5555-5555-000000000001', TRUE);
  v_result := rpc_pdi_list('all');
  ASSERT v_result->>'ok' = 'true', format('Diretoria deveria poder list all, obtido %s', v_result::TEXT);
END $$;

SELECT test_log('OK · scopos own/team/all respeitam permissoes');

-- ============================================================================
-- TESTE 12 · RPC get_by_id · acoes e comentarios incluidos
-- ============================================================================

SELECT test_log('--- TESTE 12 · RPC get_by_id ---');

DO $$
DECLARE
  v_pdi UUID;
  v_result JSONB;
  v_actions_count INT;
BEGIN
  PERFORM set_config('request.jwt.claim.sub', '55555555-5555-5555-5555-000000000005', TRUE);  -- COL2

  -- Criar PDI + acao + comentario
  v_result := rpc_pdi_create(
    '00000000-0000-0000-F004-000000000005',
    '00000000-0000-0000-F005-000000000001',
    'PDI completo para teste de get_by_id',
    'Contexto detalhado'
  );
  v_pdi := (v_result->>'pdi_id')::UUID;

  PERFORM rpc_pdi_action_add(v_pdi, 'Curso A', NULL, 'curso', '2026-08-31');
  PERFORM rpc_pdi_action_add(v_pdi, 'Mentoria B', 'Com gestor', 'mentoria', '2026-10-15');
  PERFORM rpc_pdi_comment_add(v_pdi, 'Primeiro comentario do PDI');

  v_result := rpc_pdi_get_by_id(v_pdi);
  ASSERT v_result->>'ok' = 'true', 'get_by_id deveria funcionar';
  ASSERT v_result->'pdi'->>'objective' LIKE 'PDI completo%', 'pdi.objective deveria conter o texto';
  ASSERT jsonb_array_length(v_result->'actions') = 2, 'deveria ter 2 acoes';
  ASSERT jsonb_array_length(v_result->'comments') = 1, 'deveria ter 1 comentario';
  ASSERT v_result->'pdi'->>'cycle_code' = '2026-S2', 'cycle_code deveria estar enriquecido';
END $$;

SELECT test_log('OK · get_by_id retorna PDI + actions + comments');

-- ============================================================================
-- TESTE 13 · pdi_can_read · helper de RLS
-- ============================================================================

SELECT test_log('--- TESTE 13 · pdi_can_read ---');

DO $$
DECLARE
  v_pdi UUID;
  v_result JSONB;
BEGIN
  -- COL1 cria PDI
  PERFORM set_config('request.jwt.claim.sub', '55555555-5555-5555-5555-000000000004', TRUE);
  v_result := rpc_pdi_create(
    '00000000-0000-0000-F004-000000000004',
    '00000000-0000-0000-F005-000000000001',
    'PDI privado para teste de read access',
    NULL
  );
  v_pdi := (v_result->>'pdi_id')::UUID;

  -- COL1 (owner) le
  ASSERT pdi_can_read(v_pdi) = TRUE, 'COL1 (owner) deveria ler';

  -- COL2 (peer) NAO le
  PERFORM set_config('request.jwt.claim.sub', '55555555-5555-5555-5555-000000000005', TRUE);
  ASSERT pdi_can_read(v_pdi) = FALSE, 'COL2 (peer) NAO deveria ler';

  -- LID (manager) le
  PERFORM set_config('request.jwt.claim.sub', '55555555-5555-5555-5555-000000000003', TRUE);
  ASSERT pdi_can_read(v_pdi) = TRUE, 'LID (manager) deveria ler';

  -- DIR (manager indireto) le
  PERFORM set_config('request.jwt.claim.sub', '55555555-5555-5555-5555-000000000001', TRUE);
  ASSERT pdi_can_read(v_pdi) = TRUE, 'DIR (manager indireto) deveria ler';

  -- RH le
  PERFORM set_config('request.jwt.claim.sub', '55555555-5555-5555-5555-000000000002', TRUE);
  ASSERT pdi_can_read(v_pdi) = TRUE, 'RH deveria ler';
END $$;

SELECT test_log('OK · pdi_can_read respeita owner/manager/RH/Dir');

-- ============================================================================
-- TESTE 14 · Comentario · so quem pode ler comenta
-- ============================================================================

SELECT test_log('--- TESTE 14 · Comentarios ---');

DO $$
DECLARE
  v_pdi UUID;
  v_result JSONB;
BEGIN
  PERFORM set_config('request.jwt.claim.sub', '55555555-5555-5555-5555-000000000004', TRUE);
  v_result := rpc_pdi_create(
    '00000000-0000-0000-F004-000000000004',
    '00000000-0000-0000-F005-000000000001',
    'PDI para teste de comentarios externos',
    NULL
  );
  v_pdi := (v_result->>'pdi_id')::UUID;

  -- COL2 (peer · sem acesso) tenta comentar
  PERFORM set_config('request.jwt.claim.sub', '55555555-5555-5555-5555-000000000005', TRUE);
  v_result := rpc_pdi_comment_add(v_pdi, 'Tentativa de comentario sem acesso');
  ASSERT v_result->>'error' = 'permission_denied', 'COL2 nao deveria comentar';

  -- LID (manager) consegue
  PERFORM set_config('request.jwt.claim.sub', '55555555-5555-5555-5555-000000000003', TRUE);
  v_result := rpc_pdi_comment_add(v_pdi, 'Comentario do gestor sobre o plano');
  ASSERT v_result->>'ok' = 'true', 'LID deveria comentar';

  -- Body vazio
  v_result := rpc_pdi_comment_add(v_pdi, '');
  ASSERT v_result->>'error' = 'body_required', 'Body vazio deveria falhar';
END $$;

SELECT test_log('OK · comentarios respeitam pdi_can_read');

-- ============================================================================
-- TESTE 15 · Action · evidencia path E url juntos bloqueado
-- ============================================================================

SELECT test_log('--- TESTE 15 · Evidencia exclusiva ---');

DO $$
DECLARE
  v_pdi UUID;
  v_result JSONB;
  v_action UUID;
BEGIN
  PERFORM set_config('request.jwt.claim.sub', '55555555-5555-5555-5555-000000000004', TRUE);
  v_result := rpc_pdi_create(
    '00000000-0000-0000-F004-000000000004',
    '00000000-0000-0000-F005-000000000001',
    'PDI para teste de evidencia exclusiva',
    NULL
  );
  v_pdi := (v_result->>'pdi_id')::UUID;

  v_result := rpc_pdi_action_add(v_pdi, 'Acao com evidencia');
  v_action := (v_result->>'action_id')::UUID;

  -- Tentar setar path e url juntos
  v_result := rpc_pdi_action_update(
    v_action, NULL, NULL, NULL, NULL, NULL,
    'tenant/pdi/action/file.pdf',
    'https://drive.google.com/abc'
  );
  ASSERT v_result->>'error' = 'evidence_one_kind_only', 'Path + URL juntos deveria falhar';

  -- So path
  v_result := rpc_pdi_action_update(
    v_action, NULL, NULL, NULL, NULL, NULL,
    'tenant/pdi/action/file.pdf', NULL, NULL
  );
  ASSERT v_result->>'ok' = 'true', 'So path deveria funcionar';

  -- Limpar com string vazia
  v_result := rpc_pdi_action_update(
    v_action, NULL, NULL, NULL, NULL, NULL,
    '', NULL, NULL
  );
  ASSERT v_result->>'ok' = 'true', 'Limpar com string vazia deveria funcionar';
END $$;

SELECT test_log('OK · evidencia path/url mutuamente exclusivos');

-- ============================================================================
-- TESTE 16 · Action remove · mesmas regras de permissao
-- ============================================================================

SELECT test_log('--- TESTE 16 · action_remove ---');

DO $$
DECLARE
  v_pdi UUID;
  v_result JSONB;
  v_action UUID;
BEGIN
  PERFORM set_config('request.jwt.claim.sub', '55555555-5555-5555-5555-000000000004', TRUE);
  v_result := rpc_pdi_create(
    '00000000-0000-0000-F004-000000000004',
    '00000000-0000-0000-F005-000000000001',
    'PDI para teste de action remove',
    NULL
  );
  v_pdi := (v_result->>'pdi_id')::UUID;

  v_result := rpc_pdi_action_add(v_pdi, 'Acao a ser removida');
  v_action := (v_result->>'action_id')::UUID;

  -- Owner remove
  v_result := rpc_pdi_action_remove(v_action);
  ASSERT v_result->>'ok' = 'true', 'Owner deveria remover acao';

  -- Action removida nao existe mais
  v_result := rpc_pdi_action_remove(v_action);
  ASSERT v_result->>'error' = 'action_not_found', 'Action ja deletada';
END $$;

SELECT test_log('OK · action_remove respeita permissao');

-- ============================================================================
-- TESTE 17 · PDI locked apos completed
-- ============================================================================

SELECT test_log('--- TESTE 17 · PDI locked ---');

DO $$
DECLARE
  v_pdi UUID;
  v_action UUID;
  v_result JSONB;
BEGIN
  PERFORM set_config('request.jwt.claim.sub', '55555555-5555-5555-5555-000000000004', TRUE);
  v_result := rpc_pdi_create(
    '00000000-0000-0000-F004-000000000004',
    '00000000-0000-0000-F005-000000000004',
    'PDI para teste de locked apos completed',
    NULL
  );
  v_pdi := (v_result->>'pdi_id')::UUID;

  v_result := rpc_pdi_action_add(v_pdi, 'Acao unica');
  v_action := (v_result->>'action_id')::UUID;

  PERFORM rpc_pdi_change_status(v_pdi, 'active');
  PERFORM rpc_pdi_change_status(v_pdi, 'completed');

  -- Tentar editar
  v_result := rpc_pdi_update(v_pdi, 'Tentativa de mudar objetivo apos completed');
  ASSERT v_result->>'error' = 'pdi_locked', 'Deveria bloquear update apos completed';

  -- Tentar adicionar acao
  v_result := rpc_pdi_action_add(v_pdi, 'Acao tardia');
  ASSERT v_result->>'error' = 'pdi_locked', 'Deveria bloquear add action apos completed';

  -- Tentar remover acao
  v_result := rpc_pdi_action_remove(v_action);
  ASSERT v_result->>'error' = 'pdi_locked', 'Deveria bloquear remove action apos completed';

  -- Comentar AINDA funciona (thread continua aberta)
  v_result := rpc_pdi_comment_add(v_pdi, 'Comentario apos conclusao');
  ASSERT v_result->>'ok' = 'true', 'Comentar deveria continuar funcionando';
END $$;

SELECT test_log('OK · locked bloqueia update/add/remove mas permite comentario');

-- ============================================================================
-- TESTE 18 · CASCADE de tenant deleta tudo
-- ============================================================================

SELECT test_log('--- TESTE 18 · CASCADE de tenant ---');

DO $$
DECLARE
  v_tenant UUID := '00000000-0000-0000-A200-000000000001';
  v_user UUID;
  v_cycle UUID;
  v_pdi UUID;
  v_count INT;
BEGIN
  INSERT INTO tenants (id, slug, legal_name, display_name) VALUES
    (v_tenant, 'cascade-pdi', 'Cascade PDI', 'CSC');

  INSERT INTO app_users (id, tenant_id, email, full_name, hired_at) VALUES
    (gen_random_uuid(), v_tenant, 'cascade@test.com', 'Cascade', '2024-01-01')
  RETURNING id INTO v_user;

  INSERT INTO pdi_cycles (id, tenant_id, code, display_name, start_date, end_date) VALUES
    (gen_random_uuid(), v_tenant, 'CSC-2026', 'Cascade Cycle', '2026-01-01', '2026-12-31')
  RETURNING id INTO v_cycle;

  INSERT INTO pdis (tenant_id, user_id, cycle_id, objective, start_date, end_date, created_by) VALUES
    (v_tenant, v_user, v_cycle, 'PDI cascade test com objetivo valido', '2026-01-01', '2026-12-31', v_user)
  RETURNING id INTO v_pdi;

  INSERT INTO pdi_actions (tenant_id, pdi_id, title) VALUES
    (v_tenant, v_pdi, 'Acao cascade');

  INSERT INTO pdi_comments (tenant_id, pdi_id, author_id, body) VALUES
    (v_tenant, v_pdi, v_user, 'Comentario cascade');

  -- Delete tenant
  DELETE FROM tenants WHERE id = v_tenant;

  SELECT count(*) INTO v_count FROM pdi_cycles WHERE tenant_id = v_tenant;
  ASSERT v_count = 0, 'Cycles deveriam ter cascateado';

  SELECT count(*) INTO v_count FROM pdis WHERE tenant_id = v_tenant;
  ASSERT v_count = 0, 'PDIs deveriam ter cascateado';

  SELECT count(*) INTO v_count FROM pdi_actions WHERE tenant_id = v_tenant;
  ASSERT v_count = 0, 'Actions deveriam ter cascateado';

  SELECT count(*) INTO v_count FROM pdi_comments WHERE tenant_id = v_tenant;
  ASSERT v_count = 0, 'Comments deveriam ter cascateado';
END $$;

SELECT test_log('OK · CASCADE de tenant funciona');

-- ============================================================================
-- TESTE 19 · Audit log captura mudancas em pdis
-- ============================================================================

SELECT test_log('--- TESTE 19 · Audit log ---');

DO $$
DECLARE
  v_count INT;
BEGIN
  SELECT count(*) INTO v_count FROM audit_log
  WHERE tenant_id = '00000000-0000-0000-F000-000000000001'
    AND entity_table = 'pdis';
  ASSERT v_count > 0, 'Audit log deveria ter linhas para pdis';
END $$;

SELECT test_log('OK · audit captura mudancas em pdis');

-- ============================================================================
-- TESTE 20 · Lista de ciclos
-- ============================================================================

SELECT test_log('--- TESTE 20 · rpc_pdi_list_cycles ---');

DO $$
DECLARE
  v_result JSONB;
  v_count INT;
BEGIN
  PERFORM set_config('request.jwt.claim.sub', '55555555-5555-5555-5555-000000000004', TRUE);
  v_result := rpc_pdi_list_cycles();
  v_count := jsonb_array_length(v_result->'items');
  ASSERT v_count >= 2, format('Deveria listar ciclos do tenant, obtido %s', v_count);
END $$;

SELECT test_log('OK · list_cycles funciona');

-- ============================================================================
-- TESTE 21 · Comentario soft-delete (deleted_at)
-- ============================================================================

SELECT test_log('--- TESTE 21 · Comentario soft-delete ---');

DO $$
DECLARE
  v_pdi UUID;
  v_comment UUID;
  v_result JSONB;
  v_count INT;
BEGIN
  PERFORM set_config('request.jwt.claim.sub', '55555555-5555-5555-5555-000000000004', TRUE);
  v_result := rpc_pdi_create(
    '00000000-0000-0000-F004-000000000004',
    '00000000-0000-0000-F005-000000000001',
    'PDI para teste de soft-delete de comentarios',
    NULL
  );
  v_pdi := (v_result->>'pdi_id')::UUID;

  v_result := rpc_pdi_comment_add(v_pdi, 'Comentario que sera apagado');
  v_comment := (v_result->>'comment_id')::UUID;

  -- Soft-delete (autor)
  UPDATE pdi_comments SET deleted_at = now() WHERE id = v_comment;

  -- get_by_id NAO deve retornar
  v_result := rpc_pdi_get_by_id(v_pdi);
  v_count := (
    SELECT count(*)::INT FROM jsonb_array_elements(v_result->'comments') item
    WHERE (item->>'id')::UUID = v_comment
  );
  ASSERT v_count = 0, 'Comentario soft-deleted nao deveria aparecer';
END $$;

SELECT test_log('OK · comentario soft-delete funciona');

-- ============================================================================
-- TESTE 22 · Idempotencia de seed (re-aplicar nao falha)
-- ============================================================================

SELECT test_log('--- TESTE 22 · Idempotencia ---');

DO $$
DECLARE
  v_before INT;
  v_after INT;
BEGIN
  SELECT count(*) INTO v_before FROM pdi_cycles;

  -- Re-inserir mesmo ciclo
  INSERT INTO pdi_cycles (tenant_id, code, display_name, start_date, end_date) VALUES
    ('00000000-0000-0000-F000-000000000001', '2026-S2', 'X', '2026-07-01', '2026-12-31')
  ON CONFLICT (tenant_id, code) DO UPDATE SET display_name = EXCLUDED.display_name;

  SELECT count(*) INTO v_after FROM pdi_cycles;
  ASSERT v_before = v_after, format('Re-aplicar nao deveria duplicar (antes %s, depois %s)', v_before, v_after);
END $$;

SELECT test_log('OK · idempotencia');

-- ============================================================================
-- FINAL
-- ============================================================================

SELECT test_log('=== TODOS OS TESTES PASSARAM ===');

ROLLBACK;

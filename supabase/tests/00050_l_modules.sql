-- ============================================================================
-- R2 People · Testes Modules v1
-- ============================================================================
-- Cobre catalogo, ativacao por escopo, heranca (working > employer > tenant),
-- super_admin, idempotencia, RLS.
--
-- Pre-requisitos:
--   - r2_people_schema_base_v1.sql + seed
--   - r2_people_schema_modules_v1.sql + seed
--
-- Roda em transacao com ROLLBACK.
-- ============================================================================

BEGIN;

-- ============================================================================
-- SETUP
-- ============================================================================
-- Tenant A com 2 employers e 4 working_units · 1 super_admin global
--
-- Estrutura:
--   Super Admin R2 (sem tenant)
--   Tenant A (GPC simulado)
--     Employer 1 (ATP)
--       WU1 (ATP Varejo)
--       WU2 (ATP Atacado)
--     Employer 2 (Cestao)
--       WU3 (Cestao L1)
--       WU4 (Cestao Inhambupe)
--   Users: DIR(1), RH(2), LID(3), COL_WU1(4), COL_WU2(5), COL_WU3(6), COL_WU4(7)

-- Super admin: e um app_user mas SEM tenant_id obrigatorio.
-- A tabela base nao permite NULL em tenant_id, entao criamos um tenant especial 'r2_admin'.
INSERT INTO tenants (id, slug, legal_name, display_name) VALUES
  ('00000000-0000-0000-A000-000000000099', 'r2-admin', 'R2 Admin', 'R2'),
  ('00000000-0000-0000-A000-000000000001', 'mod-test', 'MOD Test', 'MODT')
ON CONFLICT (id) DO NOTHING;

INSERT INTO employer_units (id, tenant_id, code, legal_name) VALUES
  ('00000000-0000-0000-A001-000000000001', '00000000-0000-0000-A000-000000000001', 'EMP1', 'Emp 1 ATP'),
  ('00000000-0000-0000-A001-000000000002', '00000000-0000-0000-A000-000000000001', 'EMP2', 'Emp 2 Cestao')
ON CONFLICT (id) DO NOTHING;

INSERT INTO working_units (id, tenant_id, employer_unit_id, code, display_name) VALUES
  ('00000000-0000-0000-A002-000000000001', '00000000-0000-0000-A000-000000000001',
   '00000000-0000-0000-A001-000000000001', 'WU1', 'ATP Varejo'),
  ('00000000-0000-0000-A002-000000000002', '00000000-0000-0000-A000-000000000001',
   '00000000-0000-0000-A001-000000000001', 'WU2', 'ATP Atacado'),
  ('00000000-0000-0000-A002-000000000003', '00000000-0000-0000-A000-000000000001',
   '00000000-0000-0000-A001-000000000002', 'WU3', 'Cestao L1'),
  ('00000000-0000-0000-A002-000000000004', '00000000-0000-0000-A000-000000000001',
   '00000000-0000-0000-A001-000000000002', 'WU4', 'Cestao Inhambupe')
ON CONFLICT (id) DO NOTHING;

-- Employer + working para o tenant r2_admin (FK NOT NULL)
INSERT INTO employer_units (id, tenant_id, code, legal_name) VALUES
  ('00000000-0000-0000-A001-000000000099', '00000000-0000-0000-A000-000000000099', 'R2-EMP', 'R2 Emp')
ON CONFLICT (id) DO NOTHING;

INSERT INTO working_units (id, tenant_id, employer_unit_id, code, display_name) VALUES
  ('00000000-0000-0000-A002-000000000099', '00000000-0000-0000-A000-000000000099',
   '00000000-0000-0000-A001-000000000099', 'R2-WU', 'R2 WU')
ON CONFLICT (id) DO NOTHING;

INSERT INTO app_users (
  id, tenant_id, auth_user_id, email, full_name, role,
  employer_unit_id, working_unit_id, manager_id, employment_link, hired_at
) VALUES
  -- Super admin global (no tenant r2_admin)
  ('00000000-0000-0000-A004-000000000099',
   '00000000-0000-0000-A000-000000000099', '77777777-7777-7777-7777-000000000099',
   'super@r2.com', 'Super Admin R2', 'super_admin',
   '00000000-0000-0000-A001-000000000099', '00000000-0000-0000-A002-000000000099',
   NULL, 'pj', '2020-01-01'),

  -- Tenant A
  ('00000000-0000-0000-A004-000000000001',
   '00000000-0000-0000-A000-000000000001', '77777777-7777-7777-7777-000000000001',
   'dir@mod-test.com', 'Diretor MOD', 'diretoria',
   '00000000-0000-0000-A001-000000000001', '00000000-0000-0000-A002-000000000001',
   NULL, 'clt', '2020-01-01'),
  ('00000000-0000-0000-A004-000000000002',
   '00000000-0000-0000-A000-000000000001', '77777777-7777-7777-7777-000000000002',
   'rh@mod-test.com', 'RH MOD', 'rh',
   '00000000-0000-0000-A001-000000000001', '00000000-0000-0000-A002-000000000001',
   '00000000-0000-0000-A004-000000000001', 'clt', '2020-01-01'),
  ('00000000-0000-0000-A004-000000000003',
   '00000000-0000-0000-A000-000000000001', '77777777-7777-7777-7777-000000000003',
   'lid@mod-test.com', 'Lider MOD', 'lider',
   '00000000-0000-0000-A001-000000000001', '00000000-0000-0000-A002-000000000001',
   '00000000-0000-0000-A004-000000000001', 'clt', '2020-01-01'),
  -- Colaboradores em cada WU
  ('00000000-0000-0000-A004-000000000004',
   '00000000-0000-0000-A000-000000000001', '77777777-7777-7777-7777-000000000004',
   'col_wu1@mod-test.com', 'Colab WU1', 'colaborador',
   '00000000-0000-0000-A001-000000000001', '00000000-0000-0000-A002-000000000001',
   '00000000-0000-0000-A004-000000000003', 'clt', '2024-01-01'),
  ('00000000-0000-0000-A004-000000000005',
   '00000000-0000-0000-A000-000000000001', '77777777-7777-7777-7777-000000000005',
   'col_wu2@mod-test.com', 'Colab WU2', 'colaborador',
   '00000000-0000-0000-A001-000000000001', '00000000-0000-0000-A002-000000000002',
   '00000000-0000-0000-A004-000000000003', 'clt', '2024-01-01'),
  ('00000000-0000-0000-A004-000000000006',
   '00000000-0000-0000-A000-000000000001', '77777777-7777-7777-7777-000000000006',
   'col_wu3@mod-test.com', 'Colab WU3', 'colaborador',
   '00000000-0000-0000-A001-000000000002', '00000000-0000-0000-A002-000000000003',
   '00000000-0000-0000-A004-000000000003', 'clt', '2024-01-01'),
  ('00000000-0000-0000-A004-000000000007',
   '00000000-0000-0000-A000-000000000001', '77777777-7777-7777-7777-000000000007',
   'col_wu4@mod-test.com', 'Colab WU4', 'colaborador',
   '00000000-0000-0000-A001-000000000002', '00000000-0000-0000-A002-000000000004',
   '00000000-0000-0000-A004-000000000003', 'clt', '2024-01-01')
ON CONFLICT (id) DO NOTHING;

CREATE OR REPLACE FUNCTION test_log(msg TEXT)
RETURNS TEXT AS $$
BEGIN RAISE NOTICE '%', msg; RETURN msg; END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- TESTE 1 · Catalogo seed populado
-- ============================================================================

SELECT test_log('--- TESTE 1 · Catalogo seed ---');

DO $$
DECLARE
  v_count INT;
  v_core INT;
BEGIN
  SELECT count(*) INTO v_count FROM modules;
  ASSERT v_count = 5, format('Esperado 5 modulos, obtido %s', v_count);

  SELECT count(*) INTO v_core FROM modules WHERE is_core = TRUE;
  ASSERT v_core = 1, format('Esperado 1 modulo core (base), obtido %s', v_core);

  ASSERT EXISTS (SELECT 1 FROM modules WHERE code = 'climate');
  ASSERT EXISTS (SELECT 1 FROM modules WHERE code = 'recognition');
  ASSERT EXISTS (SELECT 1 FROM modules WHERE code = 'pdi');
  ASSERT EXISTS (SELECT 1 FROM modules WHERE code = 'onboarding');
  ASSERT EXISTS (SELECT 1 FROM modules WHERE code = 'base' AND is_core = TRUE);
END $$;

SELECT test_log('OK · catalogo seed (5 modulos, 1 core)');

-- ============================================================================
-- TESTE 2 · Constraints de codigo
-- ============================================================================

SELECT test_log('--- TESTE 2 · Constraints codigo ---');

DO $$
BEGIN
  -- Codigo invalido (maiusculas)
  BEGIN
    INSERT INTO modules (code, display_name) VALUES ('Climate', 'X');
    ASSERT FALSE, 'Maiusculas deveria falhar';
  EXCEPTION WHEN check_violation THEN NULL;
  END;

  -- Codigo invalido (com espaco)
  BEGIN
    INSERT INTO modules (code, display_name) VALUES ('my module', 'X');
    ASSERT FALSE, 'Espaco deveria falhar';
  EXCEPTION WHEN check_violation THEN NULL;
  END;

  -- Codigo invalido (comeca com numero)
  BEGIN
    INSERT INTO modules (code, display_name) VALUES ('9box', 'X');
    ASSERT FALSE, 'Comeca com numero deveria falhar';
  EXCEPTION WHEN check_violation THEN NULL;
  END;

  -- Codigo valido (com underscore)
  INSERT INTO modules (code, display_name) VALUES ('my_module', 'My Module');
  DELETE FROM modules WHERE code = 'my_module';
END $$;

SELECT test_log('OK · constraints de codigo');

-- ============================================================================
-- TESTE 3 · Constraint scope_match (exatamente um id)
-- ============================================================================

SELECT test_log('--- TESTE 3 · scope_match ---');

DO $$
BEGIN
  -- scope_kind=tenant mas com employer_unit preenchido
  BEGIN
    INSERT INTO module_activations (
      module_code, scope_kind, tenant_id, employer_unit_id, activated_by
    ) VALUES (
      'climate', 'tenant',
      '00000000-0000-0000-A000-000000000001',
      '00000000-0000-0000-A001-000000000001',
      '00000000-0000-0000-A004-000000000099'
    );
    ASSERT FALSE, 'Mistura de ids deveria falhar';
  EXCEPTION WHEN check_violation THEN NULL;
  END;

  -- scope_kind=employer mas sem id
  BEGIN
    INSERT INTO module_activations (
      module_code, scope_kind, activated_by
    ) VALUES (
      'climate', 'employer_unit',
      '00000000-0000-0000-A004-000000000099'
    );
    ASSERT FALSE, 'Sem id deveria falhar';
  EXCEPTION WHEN check_violation THEN NULL;
  END;
END $$;

SELECT test_log('OK · scope_match valida exatamente 1 id');

-- ============================================================================
-- TESTE 4 · is_super_admin helper
-- ============================================================================

SELECT test_log('--- TESTE 4 · is_super_admin ---');

DO $$
BEGIN
  -- Super admin = TRUE
  PERFORM set_config('request.jwt.claim.sub', '77777777-7777-7777-7777-000000000099', TRUE);
  ASSERT is_super_admin() = TRUE, 'Super admin deveria retornar TRUE';

  -- Diretoria = FALSE
  PERFORM set_config('request.jwt.claim.sub', '77777777-7777-7777-7777-000000000001', TRUE);
  ASSERT is_super_admin() = FALSE, 'Diretoria nao e super_admin';

  -- RH = FALSE
  PERFORM set_config('request.jwt.claim.sub', '77777777-7777-7777-7777-000000000002', TRUE);
  ASSERT is_super_admin() = FALSE, 'RH nao e super_admin';

  -- Sem auth = FALSE
  PERFORM set_config('request.jwt.claim.sub', '', TRUE);
  ASSERT is_super_admin() = FALSE, 'Anonimo nao e super_admin';
END $$;

SELECT test_log('OK · is_super_admin');

-- ============================================================================
-- TESTE 5 · Activate happy path por super_admin
-- ============================================================================

SELECT test_log('--- TESTE 5 · activate happy path ---');

DO $$
DECLARE
  v_result JSONB;
BEGIN
  PERFORM set_config('request.jwt.claim.sub', '77777777-7777-7777-7777-000000000099', TRUE);  -- super_admin

  v_result := rpc_module_activate(
    'climate',
    'tenant',
    '00000000-0000-0000-A000-000000000001',
    NULL, NULL,
    'Ativacao inicial Tenant A'
  );
  ASSERT v_result->>'ok' = 'true', format('Esperado ok, obtido %s', v_result::TEXT);
  ASSERT v_result->>'activation_id' IS NOT NULL, 'activation_id deveria existir';
END $$;

SELECT test_log('OK · activate happy path');

-- ============================================================================
-- TESTE 6 · Activate idempotente
-- ============================================================================

SELECT test_log('--- TESTE 6 · idempotencia ---');

DO $$
DECLARE
  v_result JSONB;
BEGIN
  PERFORM set_config('request.jwt.claim.sub', '77777777-7777-7777-7777-000000000099', TRUE);

  -- Re-ativar mesma combinacao retorna already_active
  v_result := rpc_module_activate(
    'climate', 'tenant',
    '00000000-0000-0000-A000-000000000001',
    NULL, NULL
  );
  ASSERT v_result->>'ok' = 'true', 'Re-ativacao deveria ser ok';
  ASSERT v_result->>'already_active' = 'true', format('Esperado already_active, obtido %s', v_result::TEXT);
END $$;

SELECT test_log('OK · idempotencia (already_active)');

-- ============================================================================
-- TESTE 7 · Sem permissao bloqueia
-- ============================================================================

SELECT test_log('--- TESTE 7 · permissao bloqueia ---');

DO $$
DECLARE
  v_result JSONB;
BEGIN
  -- Diretoria do tenant tenta ativar
  PERFORM set_config('request.jwt.claim.sub', '77777777-7777-7777-7777-000000000001', TRUE);
  v_result := rpc_module_activate('recognition', 'tenant', '00000000-0000-0000-A000-000000000001');
  ASSERT v_result->>'error' = 'permission_denied',
    format('Diretoria nao deveria ativar, obtido %s', v_result::TEXT);

  -- RH idem
  PERFORM set_config('request.jwt.claim.sub', '77777777-7777-7777-7777-000000000002', TRUE);
  v_result := rpc_module_activate('recognition', 'tenant', '00000000-0000-0000-A000-000000000001');
  ASSERT v_result->>'error' = 'permission_denied', 'RH nao deveria ativar';

  -- Colab idem
  PERFORM set_config('request.jwt.claim.sub', '77777777-7777-7777-7777-000000000004', TRUE);
  v_result := rpc_module_activate('recognition', 'tenant', '00000000-0000-0000-A000-000000000001');
  ASSERT v_result->>'error' = 'permission_denied', 'Colab nao deveria ativar';
END $$;

SELECT test_log('OK · so super_admin ativa');

-- ============================================================================
-- TESTE 8 · Validacoes do activate
-- ============================================================================

SELECT test_log('--- TESTE 8 · validacoes activate ---');

DO $$
DECLARE
  v_result JSONB;
BEGIN
  PERFORM set_config('request.jwt.claim.sub', '77777777-7777-7777-7777-000000000099', TRUE);

  -- Modulo inexistente
  v_result := rpc_module_activate('inexistente', 'tenant', '00000000-0000-0000-A000-000000000001');
  ASSERT v_result->>'error' = 'module_not_found', 'Modulo inexistente deveria falhar';

  -- Tenant inexistente
  v_result := rpc_module_activate('pdi', 'tenant', '00000000-0000-0000-FFFF-FFFFFFFFFFFF');
  ASSERT v_result->>'error' = 'tenant_not_found', 'Tenant inexistente deveria falhar';

  -- scope_kind=tenant sem tenant_id
  v_result := rpc_module_activate('pdi', 'tenant', NULL);
  ASSERT v_result->>'error' = 'tenant_id_required', 'tenant_id obrigatorio';

  -- scope_kind=employer_unit sem employer_unit_id
  v_result := rpc_module_activate('pdi', 'employer_unit');
  ASSERT v_result->>'error' = 'employer_unit_id_required', 'employer_unit_id obrigatorio';

  -- scope_kind=working_unit sem working_unit_id
  v_result := rpc_module_activate('pdi', 'working_unit');
  ASSERT v_result->>'error' = 'working_unit_id_required', 'working_unit_id obrigatorio';
END $$;

SELECT test_log('OK · validacoes activate');

-- ============================================================================
-- TESTE 9 · module_is_active · resolucao de heranca
-- ============================================================================

SELECT test_log('--- TESTE 9 · heranca tenant > employer > working ---');

DO $$
DECLARE
  v_result JSONB;
BEGIN
  PERFORM set_config('request.jwt.claim.sub', '77777777-7777-7777-7777-000000000099', TRUE);

  -- Limpar ativacoes do climate (T5 ativou no tenant)
  DELETE FROM module_activations WHERE module_code = 'climate';

  -- Nada ativo: nenhum WU enxerga
  ASSERT module_is_active('climate', '00000000-0000-0000-A002-000000000001') = FALSE, 'WU1 nao tem climate';
  ASSERT module_is_active('climate', '00000000-0000-0000-A002-000000000003') = FALSE, 'WU3 nao tem climate';

  -- Ativar so no working_unit WU1 (ATP Varejo)
  PERFORM rpc_module_activate('climate', 'working_unit', NULL, NULL, '00000000-0000-0000-A002-000000000001');

  ASSERT module_is_active('climate', '00000000-0000-0000-A002-000000000001') = TRUE, 'WU1 ativo';
  ASSERT module_is_active('climate', '00000000-0000-0000-A002-000000000002') = FALSE, 'WU2 nao herda de WU1';
  ASSERT module_is_active('climate', '00000000-0000-0000-A002-000000000003') = FALSE, 'WU3 nao herda de WU1';

  -- Ativar no employer EMP1 (ATP) · WU1 e WU2 deveriam ficar ativos por heranca
  PERFORM rpc_module_activate('climate', 'employer_unit', NULL, '00000000-0000-0000-A001-000000000001');

  ASSERT module_is_active('climate', '00000000-0000-0000-A002-000000000001') = TRUE, 'WU1 ainda ativo';
  ASSERT module_is_active('climate', '00000000-0000-0000-A002-000000000002') = TRUE, 'WU2 herda de EMP1';
  ASSERT module_is_active('climate', '00000000-0000-0000-A002-000000000003') = FALSE, 'WU3 nao herda de EMP1';
  ASSERT module_is_active('climate', '00000000-0000-0000-A002-000000000004') = FALSE, 'WU4 nao herda de EMP1';

  -- Ativar no tenant inteiro · todos ativos
  PERFORM rpc_module_activate('climate', 'tenant', '00000000-0000-0000-A000-000000000001');

  ASSERT module_is_active('climate', '00000000-0000-0000-A002-000000000001') = TRUE, 'WU1 ativo';
  ASSERT module_is_active('climate', '00000000-0000-0000-A002-000000000002') = TRUE, 'WU2 ativo';
  ASSERT module_is_active('climate', '00000000-0000-0000-A002-000000000003') = TRUE, 'WU3 ativo (herda do tenant)';
  ASSERT module_is_active('climate', '00000000-0000-0000-A002-000000000004') = TRUE, 'WU4 ativo (herda do tenant)';
END $$;

SELECT test_log('OK · heranca working > employer > tenant');

-- ============================================================================
-- TESTE 10 · Modulo core sempre ativo
-- ============================================================================

SELECT test_log('--- TESTE 10 · modulo core sempre ativo ---');

DO $$
BEGIN
  -- Sem nenhuma activation row para 'base'
  ASSERT NOT EXISTS (SELECT 1 FROM module_activations WHERE module_code = 'base'),
    'base nao deveria ter activations';

  -- Mesmo assim, esta ativo em qualquer WU
  ASSERT module_is_active('base', '00000000-0000-0000-A002-000000000001') = TRUE, 'base ativo em WU1';
  ASSERT module_is_active('base', '00000000-0000-0000-A002-000000000002') = TRUE, 'base ativo em WU2';
  ASSERT module_is_active('base', '00000000-0000-0000-A002-000000000003') = TRUE, 'base ativo em WU3';
  ASSERT module_is_active('base', '00000000-0000-0000-A002-000000000004') = TRUE, 'base ativo em WU4';
END $$;

SELECT test_log('OK · modulo core sempre ativo');

-- ============================================================================
-- TESTE 11 · Cannot deactivate core
-- ============================================================================

SELECT test_log('--- TESTE 11 · cannot deactivate core ---');

DO $$
DECLARE
  v_result JSONB;
BEGIN
  PERFORM set_config('request.jwt.claim.sub', '77777777-7777-7777-7777-000000000099', TRUE);

  v_result := rpc_module_deactivate('base', 'tenant', '00000000-0000-0000-A000-000000000001');
  ASSERT v_result->>'error' = 'cannot_deactivate_core_module',
    format('Esperado cannot_deactivate_core_module, obtido %s', v_result::TEXT);
END $$;

SELECT test_log('OK · core protegido de deactivate');

-- ============================================================================
-- TESTE 12 · Deactivate happy path
-- ============================================================================

SELECT test_log('--- TESTE 12 · deactivate ---');

DO $$
DECLARE
  v_result JSONB;
BEGIN
  PERFORM set_config('request.jwt.claim.sub', '77777777-7777-7777-7777-000000000099', TRUE);

  -- Deactivate climate no tenant (T9 ativou)
  v_result := rpc_module_deactivate('climate', 'tenant', '00000000-0000-0000-A000-000000000001');
  ASSERT v_result->>'ok' = 'true', 'deactivate ok';
  ASSERT (v_result->>'deleted')::INT = 1, 'esperado 1 deletado';

  -- Climate ainda ativo em WU1 (ativacao nivel WU permanece)
  ASSERT module_is_active('climate', '00000000-0000-0000-A002-000000000001') = TRUE, 'WU1 ainda ativo (working scope)';
  -- WU2 ainda ativo via employer
  ASSERT module_is_active('climate', '00000000-0000-0000-A002-000000000002') = TRUE, 'WU2 ainda ativo via employer';
  -- WU3 e WU4 voltam a inativos (so o tenant cobria)
  ASSERT module_is_active('climate', '00000000-0000-0000-A002-000000000003') = FALSE, 'WU3 inativo';
  ASSERT module_is_active('climate', '00000000-0000-0000-A002-000000000004') = FALSE, 'WU4 inativo';

  -- Re-deactivate (noop)
  v_result := rpc_module_deactivate('climate', 'tenant', '00000000-0000-0000-A000-000000000001');
  ASSERT v_result->>'noop' = 'true', 'Re-deactivate deveria ser noop';
END $$;

SELECT test_log('OK · deactivate so remove o nivel especifico');

-- ============================================================================
-- TESTE 13 · module_is_active_for_me
-- ============================================================================

SELECT test_log('--- TESTE 13 · module_is_active_for_me ---');

DO $$
BEGIN
  -- Limpar tudo do climate, recognition, pdi
  DELETE FROM module_activations WHERE module_code IN ('climate', 'recognition', 'pdi', 'onboarding');

  PERFORM set_config('request.jwt.claim.sub', '77777777-7777-7777-7777-000000000099', TRUE);

  -- Ativar pdi no employer EMP2 (Cestao)
  PERFORM rpc_module_activate('pdi', 'employer_unit', NULL, '00000000-0000-0000-A001-000000000002');

  -- COL_WU1 (no EMP1/ATP) NAO tem pdi
  PERFORM set_config('request.jwt.claim.sub', '77777777-7777-7777-7777-000000000004', TRUE);
  ASSERT module_is_active_for_me('pdi') = FALSE, 'COL_WU1 nao tem pdi (EMP1)';

  -- COL_WU3 (no EMP2/Cestao) TEM pdi
  PERFORM set_config('request.jwt.claim.sub', '77777777-7777-7777-7777-000000000006', TRUE);
  ASSERT module_is_active_for_me('pdi') = TRUE, 'COL_WU3 tem pdi (EMP2)';

  -- COL_WU4 (tambem no EMP2) TEM pdi
  PERFORM set_config('request.jwt.claim.sub', '77777777-7777-7777-7777-000000000007', TRUE);
  ASSERT module_is_active_for_me('pdi') = TRUE, 'COL_WU4 tem pdi (EMP2)';

  -- Super admin: vê tudo, mesmo sem ativacao
  PERFORM set_config('request.jwt.claim.sub', '77777777-7777-7777-7777-000000000099', TRUE);
  ASSERT module_is_active_for_me('recognition') = TRUE, 'Super admin sempre ve tudo';
END $$;

SELECT test_log('OK · module_is_active_for_me com heranca');

-- ============================================================================
-- TESTE 14 · rpc_my_active_modules
-- ============================================================================

SELECT test_log('--- TESTE 14 · my_active_modules ---');

DO $$
DECLARE
  v_result JSONB;
  v_codes TEXT;
  v_count INT;
BEGIN
  -- COL_WU3 (Cestao) tem pdi (do T13) e base (core)
  PERFORM set_config('request.jwt.claim.sub', '77777777-7777-7777-7777-000000000006', TRUE);
  v_result := rpc_my_active_modules();
  ASSERT v_result->>'ok' = 'true', 'my_active_modules ok';

  v_count := jsonb_array_length(v_result->'items');
  ASSERT v_count = 2, format('COL_WU3 deveria ver 2 modulos (base + pdi), obtido %s', v_count);

  -- Deveria conter base e pdi
  SELECT string_agg(item->>'code', ',' ORDER BY item->>'code') INTO v_codes
  FROM jsonb_array_elements(v_result->'items') item;
  ASSERT v_codes = 'base,pdi', format('Esperado base,pdi obtido %s', v_codes);

  -- COL_WU1 (ATP) so tem base (core) · pdi nao foi ativado para EMP1
  PERFORM set_config('request.jwt.claim.sub', '77777777-7777-7777-7777-000000000004', TRUE);
  v_result := rpc_my_active_modules();
  v_count := jsonb_array_length(v_result->'items');
  ASSERT v_count = 1, format('COL_WU1 so deveria ver base, obtido %s', v_count);

  -- Super admin ve todos os 5
  PERFORM set_config('request.jwt.claim.sub', '77777777-7777-7777-7777-000000000099', TRUE);
  v_result := rpc_my_active_modules();
  v_count := jsonb_array_length(v_result->'items');
  ASSERT v_count = 5, format('Super admin deveria ver 5, obtido %s', v_count);
END $$;

SELECT test_log('OK · rpc_my_active_modules com heranca + super_admin');

-- ============================================================================
-- TESTE 15 · rpc_module_check
-- ============================================================================

SELECT test_log('--- TESTE 15 · rpc_module_check ---');

DO $$
DECLARE
  v_result JSONB;
BEGIN
  -- COL_WU3 tem pdi
  PERFORM set_config('request.jwt.claim.sub', '77777777-7777-7777-7777-000000000006', TRUE);
  v_result := rpc_module_check('pdi');
  ASSERT v_result->>'is_active' = 'true', 'COL_WU3 tem pdi ativo';

  v_result := rpc_module_check('climate');
  ASSERT v_result->>'is_active' = 'false', 'COL_WU3 nao tem climate';
END $$;

SELECT test_log('OK · rpc_module_check');

-- ============================================================================
-- TESTE 16 · activations_by_tenant
-- ============================================================================

SELECT test_log('--- TESTE 16 · activations_by_tenant ---');

DO $$
DECLARE
  v_result JSONB;
  v_count INT;
BEGIN
  PERFORM set_config('request.jwt.claim.sub', '77777777-7777-7777-7777-000000000099', TRUE);

  v_result := rpc_module_activations_by_tenant('00000000-0000-0000-A000-000000000001');
  ASSERT v_result->>'ok' = 'true', 'activations_by_tenant ok';

  v_count := jsonb_array_length(v_result->'items');
  -- T13 ativou pdi no EMP2 (1 ativacao no tenant A)
  ASSERT v_count = 1, format('Esperado 1 ativacao no tenant A, obtido %s', v_count);

  -- Diretoria do tenant A pode ler
  PERFORM set_config('request.jwt.claim.sub', '77777777-7777-7777-7777-000000000001', TRUE);
  v_result := rpc_module_activations_by_tenant('00000000-0000-0000-A000-000000000001');
  ASSERT v_result->>'ok' = 'true', 'Diretoria pode ler proprio tenant';

  -- Diretoria de outro tenant (vamos simular: r2_admin) nao
  PERFORM set_config('request.jwt.claim.sub', '77777777-7777-7777-7777-000000000001', TRUE);
  v_result := rpc_module_activations_by_tenant('00000000-0000-0000-A000-000000000099');
  ASSERT v_result->>'error' = 'permission_denied', 'Diretoria nao ve outro tenant';
END $$;

SELECT test_log('OK · activations_by_tenant escopo correto');

-- ============================================================================
-- TESTE 17 · CASCADE de tenant deleta ativacoes
-- ============================================================================

SELECT test_log('--- TESTE 17 · CASCADE ---');

DO $$
DECLARE
  v_tenant_id UUID := '00000000-0000-0000-C000-000000000001';
  v_emp_id UUID := '00000000-0000-0000-C001-000000000001';
  v_count INT;
BEGIN
  INSERT INTO tenants (id, slug, legal_name, display_name)
  VALUES (v_tenant_id, 'cascade-mod', 'Cascade MOD', 'CSC');
  INSERT INTO employer_units (id, tenant_id, code, legal_name)
  VALUES (v_emp_id, v_tenant_id, 'CSC', 'CSC EMP');

  PERFORM set_config('request.jwt.claim.sub', '77777777-7777-7777-7777-000000000099', TRUE);
  PERFORM rpc_module_activate('climate', 'tenant', v_tenant_id);
  PERFORM rpc_module_activate('recognition', 'employer_unit', NULL, v_emp_id);

  SELECT count(*) INTO v_count FROM module_activations WHERE tenant_id = v_tenant_id;
  ASSERT v_count = 1, 'Esperado 1 ativacao tenant';

  -- Delete tenant cascateia
  DELETE FROM tenants WHERE id = v_tenant_id;

  SELECT count(*) INTO v_count FROM module_activations WHERE tenant_id = v_tenant_id;
  ASSERT v_count = 0, 'Ativacao do tenant deveria ter cascateado';

  SELECT count(*) INTO v_count FROM module_activations WHERE employer_unit_id = v_emp_id;
  ASSERT v_count = 0, 'Ativacao do employer deveria ter cascateado (via tenant)';
END $$;

SELECT test_log('OK · CASCADE limpa ativacoes');

-- ============================================================================
-- TESTE 18 · Idempotencia do seed
-- ============================================================================

SELECT test_log('--- TESTE 18 · idempotencia seed ---');

DO $$
DECLARE
  v_before INT;
  v_after INT;
BEGIN
  SELECT count(*) INTO v_before FROM modules;

  -- Re-aplicar mesmo seed (UPSERT)
  INSERT INTO modules (code, display_name, description, icon_name, is_core, display_order) VALUES
    ('climate', 'Clima Modificado', 'Outra desc', 'Icon', FALSE, 99)
  ON CONFLICT (code) DO UPDATE SET
    display_name = EXCLUDED.display_name,
    display_order = EXCLUDED.display_order;

  SELECT count(*) INTO v_after FROM modules;
  ASSERT v_before = v_after, format('Re-seed nao deveria criar duplicatas (antes %s, depois %s)', v_before, v_after);

  -- Verifica que o UPSERT atualizou
  ASSERT (SELECT display_name FROM modules WHERE code = 'climate') = 'Clima Modificado',
    'UPSERT deveria atualizar display_name';
END $$;

SELECT test_log('OK · idempotencia seed (UPSERT)');

-- ============================================================================
-- TESTE 19 · Helper module_is_active com working_unit_id NULL
-- ============================================================================

SELECT test_log('--- TESTE 19 · module_is_active edge cases ---');

DO $$
BEGIN
  -- working_unit_id NULL retorna FALSE (exceto para core)
  ASSERT module_is_active('climate', NULL) = FALSE, 'NULL retorna FALSE';
  ASSERT module_is_active('base', NULL) = TRUE, 'core retorna TRUE mesmo com NULL';

  -- Modulo inexistente retorna FALSE
  ASSERT module_is_active('nao_existe', '00000000-0000-0000-A002-000000000001') = FALSE, 'modulo inexistente';

  -- working_unit inexistente retorna FALSE
  ASSERT module_is_active('climate', '00000000-0000-0000-FFFF-FFFFFFFFFFFF') = FALSE, 'wu inexistente';
END $$;

SELECT test_log('OK · edge cases');

-- ============================================================================
-- TESTE 20 · UNIQUE por escopo
-- ============================================================================

SELECT test_log('--- TESTE 20 · UNIQUE por escopo ---');

DO $$
BEGIN
  -- Limpar
  DELETE FROM module_activations WHERE module_code = 'onboarding';

  -- Inserir uma ativacao no tenant
  INSERT INTO module_activations (
    module_code, scope_kind, tenant_id, activated_by
  ) VALUES (
    'onboarding', 'tenant',
    '00000000-0000-0000-A000-000000000001',
    '00000000-0000-0000-A004-000000000099'
  );

  -- Tentar inserir duplicado deve falhar
  BEGIN
    INSERT INTO module_activations (
      module_code, scope_kind, tenant_id, activated_by
    ) VALUES (
      'onboarding', 'tenant',
      '00000000-0000-0000-A000-000000000001',
      '00000000-0000-0000-A004-000000000099'
    );
    ASSERT FALSE, 'Duplicado deveria falhar';
  EXCEPTION WHEN unique_violation THEN NULL;
  END;

  -- Mas pode inserir o mesmo modulo em escopo diferente
  INSERT INTO module_activations (
    module_code, scope_kind, working_unit_id, activated_by
  ) VALUES (
    'onboarding', 'working_unit',
    '00000000-0000-0000-A002-000000000001',
    '00000000-0000-0000-A004-000000000099'
  );
END $$;

SELECT test_log('OK · UNIQUE por escopo permite mesmo modulo em niveis diferentes');

-- ============================================================================
-- FINAL
-- ============================================================================

SELECT test_log('=== TODOS OS TESTES PASSARAM ===');

ROLLBACK;

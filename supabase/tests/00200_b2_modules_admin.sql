-- ============================================================================
-- R2 People · Testes Sessao B2 · Admin de Modulos
-- ============================================================================
-- Cobertura:
--   1. Permissoes · super_admin, diretoria, RH/lider/colaborador
--   2. Activate · cria nova, idempotente em ja-ativa, reativa soft_disabled
--   3. Deactivate · soft-disable, bloqueia core, idempotente em ja-desativado
--   4. Reactivate · alias de activate em soft_disabled
--   5. Overview · super_admin global vs diretoria tenant-scoped
--   6. Impact summary · ninebox com avaliacoes abertas
--   7. Helpers · module_is_active_for_me e module_is_readonly_for_me
--   8. Integracao A1 · ninebox bloqueia escrita quando soft_disabled
--                      mas permite leitura via novo helper readonly
--   9. Cross-tenant · diretoria do tenant X nao admin tenant Y
-- ============================================================================

BEGIN;

-- ============================================================================
-- SETUP · 2 tenants para testar isolamento cross-tenant
-- ============================================================================

INSERT INTO tenants (id, slug, legal_name, display_name) VALUES
  ('00000000-0000-0000-B2A0-000000000001', 'tenant-x', 'Tenant X', 'X'),
  ('00000000-0000-0000-B2A0-000000000002', 'tenant-y', 'Tenant Y', 'Y');

INSERT INTO employer_units (id, tenant_id, code, legal_name) VALUES
  ('00000000-0000-0000-B2A1-000000000001', '00000000-0000-0000-B2A0-000000000001', 'X-EMP', 'X Employer'),
  ('00000000-0000-0000-B2A1-000000000002', '00000000-0000-0000-B2A0-000000000002', 'Y-EMP', 'Y Employer');

INSERT INTO working_units (id, tenant_id, employer_unit_id, code, display_name) VALUES
  ('00000000-0000-0000-B2A2-000000000001', '00000000-0000-0000-B2A0-000000000001', '00000000-0000-0000-B2A1-000000000001', 'X-WU', 'X WU'),
  ('00000000-0000-0000-B2A2-000000000002', '00000000-0000-0000-B2A0-000000000002', '00000000-0000-0000-B2A1-000000000002', 'Y-WU', 'Y WU');

INSERT INTO departments (id, tenant_id, code, display_name) VALUES
  ('00000000-0000-0000-B2A3-000000000001', '00000000-0000-0000-B2A0-000000000001', 'OPS', 'OPS'),
  ('00000000-0000-0000-B2A3-000000000002', '00000000-0000-0000-B2A0-000000000002', 'OPS', 'OPS');

-- Usuarios:
-- X-DIR (diretoria X), X-RH (rh X), X-LIDER, X-USR
-- Y-DIR (diretoria Y)
-- SA (super_admin)

INSERT INTO app_users (
  id, tenant_id, auth_user_id, email, full_name, role,
  employer_unit_id, working_unit_id, department_id,
  manager_id, employment_link, hired_at
) VALUES
  ('00000000-0000-0000-B2A4-00000000000D', '00000000-0000-0000-B2A0-000000000001', 'b2aa4444-4444-4444-4444-00000000000D', 'xdir@x.test', 'X DIR',  'diretoria',
    '00000000-0000-0000-B2A1-000000000001', '00000000-0000-0000-B2A2-000000000001', '00000000-0000-0000-B2A3-000000000001', NULL, 'clt', '2020-01-01'),
  ('00000000-0000-0000-B2A4-00000000000E', '00000000-0000-0000-B2A0-000000000001', 'b2aa4444-4444-4444-4444-00000000000E', 'xrh@x.test',  'X RH',   'rh',
    '00000000-0000-0000-B2A1-000000000001', '00000000-0000-0000-B2A2-000000000001', '00000000-0000-0000-B2A3-000000000001', '00000000-0000-0000-B2A4-00000000000D', 'clt', '2020-01-01'),
  ('00000000-0000-0000-B2A4-00000000000F', '00000000-0000-0000-B2A0-000000000001', 'b2aa4444-4444-4444-4444-00000000000F', 'xli@x.test',  'X LIDER','lider',
    '00000000-0000-0000-B2A1-000000000001', '00000000-0000-0000-B2A2-000000000001', '00000000-0000-0000-B2A3-000000000001', '00000000-0000-0000-B2A4-00000000000D', 'clt', '2020-01-01'),
  ('00000000-0000-0000-B2A4-000000000010', '00000000-0000-0000-B2A0-000000000001', 'b2aa4444-4444-4444-4444-000000000010', 'xu@x.test',   'X USR',  'colaborador',
    '00000000-0000-0000-B2A1-000000000001', '00000000-0000-0000-B2A2-000000000001', '00000000-0000-0000-B2A3-000000000001', '00000000-0000-0000-B2A4-00000000000F', 'clt', '2020-01-01'),
  ('00000000-0000-0000-B2A4-000000000020', '00000000-0000-0000-B2A0-000000000002', 'b2aa4444-4444-4444-4444-000000000020', 'ydir@y.test', 'Y DIR',  'diretoria',
    '00000000-0000-0000-B2A1-000000000002', '00000000-0000-0000-B2A2-000000000002', '00000000-0000-0000-B2A3-000000000002', NULL, 'clt', '2020-01-01'),
  ('00000000-0000-0000-B2A4-0000000000FF', '00000000-0000-0000-B2A0-000000000001', 'b2aa4444-4444-4444-4444-0000000000FF', 'sa@r2.test',  'SA',     'super_admin',
    NULL, NULL, NULL, NULL, 'clt', '2020-01-01');

-- Helper de assert
CREATE OR REPLACE FUNCTION b2_assert(condition BOOLEAN, msg TEXT)
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
-- T01-T04 · Permissoes do overview
-- ============================================================================

SELECT test_login('b2aa4444-4444-4444-4444-0000000000FF');  -- SA
SELECT b2_assert(
  (rpc_admin_modules_overview() ->> 'ok')::BOOLEAN = TRUE,
  'T01 · super_admin acessa overview'
);

SELECT test_login('b2aa4444-4444-4444-4444-00000000000D');  -- X-DIR
SELECT b2_assert(
  (rpc_admin_modules_overview() ->> 'ok')::BOOLEAN = TRUE,
  'T02 · diretoria acessa overview'
);

SELECT test_login('b2aa4444-4444-4444-4444-00000000000E');  -- X-RH
SELECT b2_assert(
  rpc_admin_modules_overview() ->> 'error' = 'permission_denied',
  'T03 · RH NAO acessa overview (so super_admin + diretoria)'
);

SELECT test_login('b2aa4444-4444-4444-4444-000000000010');  -- X-USR
SELECT b2_assert(
  rpc_admin_modules_overview() ->> 'error' = 'permission_denied',
  'T04 · colaborador NAO acessa overview'
);

-- ============================================================================
-- T05-T07 · Visao super_admin · global aggregates
-- ============================================================================

SELECT test_login('b2aa4444-4444-4444-4444-0000000000FF');  -- SA

DO $$
DECLARE v_resp JSONB;
DECLARE v_module JSONB;
BEGIN
  v_resp := rpc_admin_modules_overview();
  IF v_resp ->> 'role' <> 'super_admin' THEN
    RAISE EXCEPTION 'T05 FAIL · role = %', v_resp ->> 'role';
  END IF;
  RAISE NOTICE 'PASS · T05 · super_admin recebe role=super_admin';

  -- Verifica que cada modulo tem global_view (e nao tenant_view)
  FOR v_module IN SELECT * FROM jsonb_array_elements(v_resp -> 'modules')
  LOOP
    IF NOT (v_module ? 'global_view') THEN
      RAISE EXCEPTION 'T06 FAIL · modulo % sem global_view', v_module ->> 'code';
    END IF;
  END LOOP;
  RAISE NOTICE 'PASS · T06 · todos os modulos tem global_view para super_admin';

  -- Verifica que tenants_total >= 2 (criamos X e Y no setup)
  v_module := (v_resp -> 'modules' -> 0);
  IF (v_module -> 'global_view' ->> 'tenants_total')::INT < 2 THEN
    RAISE EXCEPTION 'T07 FAIL · tenants_total = %', v_module -> 'global_view' ->> 'tenants_total';
  END IF;
  RAISE NOTICE 'PASS · T07 · global_view conta tenants corretamente';
END $$;

-- ============================================================================
-- T08-T10 · Visao diretoria · tenant-scoped
-- ============================================================================

SELECT test_login('b2aa4444-4444-4444-4444-00000000000D');  -- X-DIR

DO $$
DECLARE v_resp JSONB;
DECLARE v_module JSONB;
BEGIN
  v_resp := rpc_admin_modules_overview();
  IF v_resp ->> 'role' <> 'diretoria' THEN
    RAISE EXCEPTION 'T08 FAIL · role=%', v_resp ->> 'role';
  END IF;
  RAISE NOTICE 'PASS · T08 · diretoria recebe role=diretoria';

  FOR v_module IN SELECT * FROM jsonb_array_elements(v_resp -> 'modules')
  LOOP
    IF NOT (v_module ? 'tenant_view') THEN
      RAISE EXCEPTION 'T09 FAIL · modulo % sem tenant_view', v_module ->> 'code';
    END IF;
    IF v_module ? 'global_view' THEN
      RAISE EXCEPTION 'T09 FAIL · modulo % com global_view (deveria ser apenas tenant_view)', v_module ->> 'code';
    END IF;
  END LOOP;
  RAISE NOTICE 'PASS · T09 · todos os modulos tem tenant_view (sem global_view)';

  -- tenant_view tem employer_units e working_units
  v_module := (v_resp -> 'modules' -> 0);
  IF NOT (v_module -> 'tenant_view' ? 'employer_units') OR NOT (v_module -> 'tenant_view' ? 'working_units') THEN
    RAISE EXCEPTION 'T10 FAIL · tenant_view sem employer/working units';
  END IF;
  RAISE NOTICE 'PASS · T10 · tenant_view inclui employer_units e working_units';
END $$;

-- ============================================================================
-- T11-T13 · Activate
-- ============================================================================

SELECT test_login('b2aa4444-4444-4444-4444-00000000000D');  -- X-DIR

-- T11 · ativa ninebox no tenant X
DO $$
DECLARE v_resp JSONB;
BEGIN
  v_resp := rpc_admin_module_activate('ninebox', 'tenant', '00000000-0000-0000-B2A0-000000000001');
  IF (v_resp ->> 'ok')::BOOLEAN <> TRUE THEN
    RAISE EXCEPTION 'T11 FAIL · resp=%', v_resp;
  END IF;
  IF (v_resp ->> 'created')::BOOLEAN <> TRUE THEN
    RAISE EXCEPTION 'T11 FAIL · esperava created=true · resp=%', v_resp;
  END IF;
  RAISE NOTICE 'PASS · T11 · diretoria ativa modulo no proprio tenant (created=true)';
END $$;

-- T12 · activate idempotente
SELECT b2_assert(
  (rpc_admin_module_activate('ninebox', 'tenant', '00000000-0000-0000-B2A0-000000000001') ->> 'already_active')::BOOLEAN = TRUE,
  'T12 · activate em escopo ja-ativo retorna already_active=true'
);

-- T13 · ativa em employer_unit (escopo diferente)
SELECT b2_assert(
  (rpc_admin_module_activate('ninebox', 'employer_unit', '00000000-0000-0000-B2A1-000000000001') ->> 'created')::BOOLEAN = TRUE,
  'T13 · ativa em employer_unit cria nova activation'
);

-- ============================================================================
-- T14-T17 · Deactivate
-- ============================================================================

-- T14 · desativa em employer_unit
DO $$
DECLARE v_resp JSONB;
BEGIN
  v_resp := rpc_admin_module_deactivate(
    'ninebox', 'employer_unit', '00000000-0000-0000-B2A1-000000000001',
    'Reorganizacao da estrutura'
  );
  IF (v_resp ->> 'disabled')::BOOLEAN <> TRUE THEN
    RAISE EXCEPTION 'T14 FAIL · resp=%', v_resp;
  END IF;
  RAISE NOTICE 'PASS · T14 · deactivate seta soft_disabled=true';
END $$;

-- T15 · soft_disabled=true e disabled_reason gravado
SELECT b2_assert(
  (SELECT soft_disabled FROM module_activations
   WHERE module_code = 'ninebox' AND scope_kind = 'employer_unit'
     AND employer_unit_id = '00000000-0000-0000-B2A1-000000000001') = TRUE
  AND
  (SELECT disabled_reason FROM module_activations
   WHERE module_code = 'ninebox' AND scope_kind = 'employer_unit'
     AND employer_unit_id = '00000000-0000-0000-B2A1-000000000001') = 'Reorganizacao da estrutura',
  'T15 · disabled_reason gravado, soft_disabled=true'
);

-- T16 · deactivate idempotente
SELECT b2_assert(
  (rpc_admin_module_deactivate('ninebox', 'employer_unit', '00000000-0000-0000-B2A1-000000000001') ->> 'already_disabled')::BOOLEAN = TRUE,
  'T16 · deactivate em escopo ja-desativado retorna already_disabled=true'
);

-- T17 · core nao pode ser desativado
SELECT b2_assert(
  rpc_admin_module_deactivate('base', 'tenant', '00000000-0000-0000-B2A0-000000000001') ->> 'error' = 'cannot_disable_core_module',
  'T17 · modulo core (base) nao pode ser desativado'
);

-- ============================================================================
-- T18-T19 · Reactivate
-- ============================================================================

-- T18 · reativa o employer_unit que foi desativado
DO $$
DECLARE v_resp JSONB;
BEGIN
  v_resp := rpc_admin_module_reactivate('ninebox', 'employer_unit', '00000000-0000-0000-B2A1-000000000001');
  IF (v_resp ->> 'reactivated')::BOOLEAN <> TRUE THEN
    RAISE EXCEPTION 'T18 FAIL · resp=%', v_resp;
  END IF;
  RAISE NOTICE 'PASS · T18 · reactivate volta soft_disabled para FALSE';
END $$;

-- T19 · reactivated_at e reactivated_by gravados
SELECT b2_assert(
  (SELECT soft_disabled FROM module_activations
   WHERE module_code = 'ninebox' AND scope_kind = 'employer_unit'
     AND employer_unit_id = '00000000-0000-0000-B2A1-000000000001') = FALSE
  AND
  (SELECT reactivated_at FROM module_activations
   WHERE module_code = 'ninebox' AND scope_kind = 'employer_unit'
     AND employer_unit_id = '00000000-0000-0000-B2A1-000000000001') IS NOT NULL,
  'T19 · soft_disabled=false e reactivated_at gravado'
);

-- ============================================================================
-- T20-T22 · Cross-tenant · diretoria de X NAO mexe em Y
-- ============================================================================

SELECT test_login('b2aa4444-4444-4444-4444-00000000000D');  -- X-DIR

SELECT b2_assert(
  rpc_admin_module_activate('ninebox', 'tenant', '00000000-0000-0000-B2A0-000000000002') ->> 'error' = 'scope_outside_tenant',
  'T20 · X-DIR nao ativa modulo no tenant Y (scope_outside_tenant)'
);

SELECT b2_assert(
  rpc_admin_module_activate('ninebox', 'employer_unit', '00000000-0000-0000-B2A1-000000000002') ->> 'error' = 'scope_outside_tenant',
  'T21 · X-DIR nao ativa em employer_unit do tenant Y'
);

-- T22 · super_admin pode mexer em qualquer tenant
SELECT test_login('b2aa4444-4444-4444-4444-0000000000FF');  -- SA
SELECT b2_assert(
  (rpc_admin_module_activate('ninebox', 'tenant', '00000000-0000-0000-B2A0-000000000002') ->> 'ok')::BOOLEAN = TRUE,
  'T22 · super_admin ativa modulo em qualquer tenant'
);

-- ============================================================================
-- T23-T25 · Helpers de ativacao com soft_disabled
-- ============================================================================

-- Setup: tenant X tem ninebox ativo (T11). Desativa em TODOS os escopos para isolar o teste.
SELECT test_login('b2aa4444-4444-4444-4444-00000000000D');  -- X-DIR
SELECT rpc_admin_module_deactivate('ninebox', 'tenant', '00000000-0000-0000-B2A0-000000000001', 'teste');
SELECT rpc_admin_module_deactivate('ninebox', 'employer_unit', '00000000-0000-0000-B2A1-000000000001', 'teste');

-- T23 · X-USR (no tenant X) module_is_active_for_me retorna FALSE
SELECT test_login('b2aa4444-4444-4444-4444-000000000010');  -- X-USR
SELECT b2_assert(
  module_is_active_for_me('ninebox') = FALSE,
  'T23 · usuario do tenant X com modulo soft_disabled · module_is_active_for_me retorna FALSE'
);

-- T24 · mas module_is_readonly_for_me retorna TRUE
SELECT b2_assert(
  module_is_readonly_for_me('ninebox') = TRUE,
  'T24 · mesmo user · module_is_readonly_for_me retorna TRUE (readonly)'
);

-- T25 · super_admin nunca em readonly
SELECT test_login('b2aa4444-4444-4444-4444-0000000000FF');  -- SA
SELECT b2_assert(
  module_is_readonly_for_me('ninebox') = FALSE,
  'T25 · super_admin nunca em readonly (passa por tudo)'
);

-- Reativa para os proximos testes
SELECT test_login('b2aa4444-4444-4444-4444-00000000000D');
SELECT rpc_admin_module_reactivate('ninebox', 'tenant', '00000000-0000-0000-B2A0-000000000001');

-- ============================================================================
-- T26-T29 · Impact summary
-- ============================================================================

-- T26 · ninebox no tenant X · sem avaliacoes ainda · impacts zerados
DO $$
DECLARE v_resp JSONB;
DECLARE v_total INT := 0;
DECLARE v_item JSONB;
BEGIN
  v_resp := rpc_admin_module_impact_summary(
    'ninebox', 'tenant', '00000000-0000-0000-B2A0-000000000001'
  );
  IF v_resp ->> 'error' IS NOT NULL THEN
    RAISE EXCEPTION 'T26 FAIL · resp=%', v_resp;
  END IF;
  -- Pelo menos 4 itens de impact (3 ninebox + 1 users_affected)
  IF jsonb_array_length(v_resp -> 'impact') < 4 THEN
    RAISE EXCEPTION 'T26 FAIL · impact items < 4 · resp=%', v_resp;
  END IF;
  RAISE NOTICE 'PASS · T26 · impact_summary retorna >=4 itens para ninebox';
END $$;

-- T27 · users_affected conta usuarios ativos no tenant X (5: X-DIR, X-RH, X-LIDER, X-USR, e o ninebox da A2 nao deixou nada)
DO $$
DECLARE v_resp JSONB;
DECLARE v_users INT;
DECLARE v_item JSONB;
BEGIN
  v_resp := rpc_admin_module_impact_summary(
    'ninebox', 'tenant', '00000000-0000-0000-B2A0-000000000001'
  );
  FOR v_item IN SELECT * FROM jsonb_array_elements(v_resp -> 'impact')
  LOOP
    IF v_item ->> 'kind' = 'users_affected' THEN
      v_users := (v_item ->> 'count')::INT;
    END IF;
  END LOOP;
  -- 4 usuarios no tenant X (X-DIR, X-RH, X-LIDER, X-USR · SA esta no tenant X tambem)
  IF v_users < 4 THEN
    RAISE EXCEPTION 'T27 FAIL · users_affected = %, esperado >= 4', v_users;
  END IF;
  RAISE NOTICE 'PASS · T27 · users_affected conta corretamente (% users)', v_users;
END $$;

-- T28 · cria avaliacao 9-Box aberta · impact aumenta
SELECT test_login('b2aa4444-4444-4444-4444-0000000000FF');

-- Settings simples
UPDATE ninebox_settings SET
  potential_criteria=jsonb_build_array(jsonb_build_object('name','P','weight',100)),
  performance_criteria=jsonb_build_array(jsonb_build_object('name','F','weight',100))
WHERE tenant_id='00000000-0000-0000-B2A0-000000000001';

-- Cria ciclo
DO $$
DECLARE v_cycle UUID;
BEGIN
  v_cycle := (rpc_ninebox_cycle_create('Ciclo X','2026-01-01','2026-12-31') ->> 'cycle_id')::UUID;
  PERFORM set_config('b2.cycle', v_cycle::TEXT, FALSE);
END $$;

-- Inicia eval para X-USR
SELECT test_login('b2aa4444-4444-4444-4444-00000000000F');  -- X-LIDER
SELECT rpc_ninebox_evaluation_start(
  '00000000-0000-0000-B2A4-000000000010',
  current_setting('b2.cycle')::UUID,
  FALSE
);

-- Re-checa impact
SELECT test_login('b2aa4444-4444-4444-4444-00000000000D');  -- X-DIR
DO $$
DECLARE v_resp JSONB;
DECLARE v_open INT := 0;
DECLARE v_cycles INT := 0;
DECLARE v_item JSONB;
BEGIN
  v_resp := rpc_admin_module_impact_summary(
    'ninebox', 'tenant', '00000000-0000-0000-B2A0-000000000001'
  );
  FOR v_item IN SELECT * FROM jsonb_array_elements(v_resp -> 'impact')
  LOOP
    IF v_item ->> 'kind' = 'ninebox_open_evaluations' THEN
      v_open := (v_item ->> 'count')::INT;
    ELSIF v_item ->> 'kind' = 'ninebox_active_cycles' THEN
      v_cycles := (v_item ->> 'count')::INT;
    END IF;
  END LOOP;
  IF v_open <> 1 OR v_cycles <> 1 THEN
    RAISE EXCEPTION 'T28 FAIL · open=% cycles=% (esperava 1,1)', v_open, v_cycles;
  END IF;
  RAISE NOTICE 'PASS · T28 · impact reflete avaliacao aberta e ciclo ativo (open=1, cycles=1)';
END $$;

-- T29 · diretoria de Y NAO faz impact_summary do tenant X
SELECT test_login('b2aa4444-4444-4444-4444-000000000020');  -- Y-DIR
SELECT b2_assert(
  rpc_admin_module_impact_summary('ninebox', 'tenant', '00000000-0000-0000-B2A0-000000000001') ->> 'error' = 'scope_outside_tenant',
  'T29 · Y-DIR nao consulta impact do tenant X'
);

-- ============================================================================
-- T30-T31 · Integracao com A1 · soft_disabled bloqueia escrita
-- ============================================================================

-- Desativa ninebox no tenant X (mantem dados em readonly)
SELECT test_login('b2aa4444-4444-4444-4444-00000000000D');  -- X-DIR
SELECT rpc_admin_module_deactivate('ninebox', 'tenant', '00000000-0000-0000-B2A0-000000000001', 'desativando');

-- T30 · X-LIDER nao consegue iniciar nova eval (gate A1)
SELECT test_login('b2aa4444-4444-4444-4444-00000000000F');  -- X-LIDER
SELECT b2_assert(
  rpc_ninebox_evaluation_start('00000000-0000-0000-B2A4-000000000010', current_setting('b2.cycle')::UUID, FALSE) ->> 'error' = 'module_inactive',
  'T30 · com soft_disabled, RPCs do ninebox retornam module_inactive'
);

-- T31 · mas a eval ja existente continua acessivel via SQL direto (readonly)
-- (a UI usaria module_is_readonly_for_me para mostrar em modo leitura)
SELECT b2_assert(
  module_is_readonly_for_me('ninebox') = TRUE,
  'T31 · X-LIDER em readonly mode quando ninebox esta soft_disabled'
);

-- ============================================================================
-- T32 · Modulo nao existe
-- ============================================================================

SELECT test_login('b2aa4444-4444-4444-4444-00000000000D');
SELECT b2_assert(
  rpc_admin_module_activate('inexistente', 'tenant', '00000000-0000-0000-B2A0-000000000001') ->> 'error' = 'module_not_found_or_inactive',
  'T32 · ativar modulo inexistente retorna erro'
);

-- ============================================================================
-- T33 · diretoria nao consegue ativar com escopo invalido (scope_id de outro tenant)
-- ============================================================================

SELECT b2_assert(
  rpc_admin_module_activate('ninebox', 'working_unit', '00000000-0000-0000-B2A2-000000000002') ->> 'error' = 'scope_outside_tenant',
  'T33 · ativar working_unit do outro tenant rejeitada'
);

-- ============================================================================
-- T34 · cobertura · diretoria pode ativar nas tres granularidades
-- ============================================================================

-- Reativa primeiro o tenant X
SELECT rpc_admin_module_reactivate('ninebox', 'tenant', '00000000-0000-0000-B2A0-000000000001');

DO $$
DECLARE v_t JSONB;
DECLARE v_e JSONB;
DECLARE v_w JSONB;
BEGIN
  v_t := rpc_admin_module_activate('ninebox', 'tenant',        '00000000-0000-0000-B2A0-000000000001');
  v_e := rpc_admin_module_activate('ninebox', 'employer_unit', '00000000-0000-0000-B2A1-000000000001');
  v_w := rpc_admin_module_activate('ninebox', 'working_unit',  '00000000-0000-0000-B2A2-000000000001');
  IF (v_t ->> 'ok')::BOOLEAN <> TRUE OR (v_e ->> 'ok')::BOOLEAN <> TRUE OR (v_w ->> 'ok')::BOOLEAN <> TRUE THEN
    RAISE EXCEPTION 'T34 FAIL · t=% e=% w=%', v_t, v_e, v_w;
  END IF;
  RAISE NOTICE 'PASS · T34 · diretoria ativa nas 3 granularidades (tenant, employer_unit, working_unit)';
END $$;

-- ============================================================================
-- T35 · Audit log registrou as alteracoes
-- ============================================================================

SELECT b2_assert(
  (SELECT count(*) FROM audit_log WHERE entity_table = 'module_activations' AND tenant_id = '00000000-0000-0000-B2A0-000000000001') > 0,
  'T35 · audit_log registrou alteracoes em module_activations'
);

-- ============================================================================
-- FECHAMENTO
-- ============================================================================

DO $$
BEGIN
  RAISE NOTICE '========================================';
  RAISE NOTICE '=== B2 · 35 testes executados · OK   ===';
  RAISE NOTICE '========================================';
END $$;

ROLLBACK;

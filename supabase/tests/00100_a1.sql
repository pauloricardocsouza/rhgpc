-- ============================================================================
-- R2 People · Testes Sessao A1 · Module checks nas RPCs
-- ============================================================================
-- Valida que TODAS as RPCs de Recognition, PDI e Onboarding respeitam o
-- check `module_is_active_for_me` injetado pelo patch A1.
--
-- Cobertura:
--   1. Tenant SEM ativacao -> bloqueia com module_inactive
--   2. Ativacao no escopo TENANT -> libera todos
--   3. Ativacao no escopo EMPLOYER_UNIT -> libera so working_units do employer
--   4. Ativacao no escopo WORKING_UNIT -> libera so essa wu
--   5. super_admin sempre passa (independente de ativacao)
--   6. Helper module_is_active_for_user resolve wu corretamente
--   7. Smoke test em uma RPC de cada modulo (Recognition + PDI + Onboarding)
--
-- Pre-requisitos:
--   - 00_local_setup.sql aplicado (auth.uid stub, roles)
--   - Schemas base, recognition, pdi, onboarding, modules aplicados
--   - Seeds correspondentes aplicados
--   - r2_people_patch_a1_module_checks.sql aplicado
--
-- Roda em BEGIN ... ROLLBACK · nao deixa lixo.
-- ============================================================================

BEGIN;

-- ============================================================================
-- SETUP · Cria tenant Z com dois employers (Z1, Z2) e tres working_units (W1, W2, W3)
-- ============================================================================
-- Estrutura:
--   tenant Z
--     employer_unit Z1
--       working_unit W1 (user U1)
--       working_unit W2 (user U2)
--     employer_unit Z2
--       working_unit W3 (user U3)
-- + super_admin SA (sem tenant)

INSERT INTO tenants (id, slug, legal_name, display_name) VALUES
  ('00000000-0000-0000-A1A0-000000000001', 'a1-test', 'Tenant A1', 'A1');

INSERT INTO employer_units (id, tenant_id, code, legal_name) VALUES
  ('00000000-0000-0000-A1A1-000000000001', '00000000-0000-0000-A1A0-000000000001', 'Z1', 'Employer Z1'),
  ('00000000-0000-0000-A1A1-000000000002', '00000000-0000-0000-A1A0-000000000001', 'Z2', 'Employer Z2');

INSERT INTO working_units (id, tenant_id, employer_unit_id, code, display_name) VALUES
  ('00000000-0000-0000-A1A2-000000000001', '00000000-0000-0000-A1A0-000000000001', '00000000-0000-0000-A1A1-000000000001', 'W1', 'Loja W1'),
  ('00000000-0000-0000-A1A2-000000000002', '00000000-0000-0000-A1A0-000000000001', '00000000-0000-0000-A1A1-000000000001', 'W2', 'Loja W2'),
  ('00000000-0000-0000-A1A2-000000000003', '00000000-0000-0000-A1A0-000000000001', '00000000-0000-0000-A1A1-000000000002', 'W3', 'Loja W3');

INSERT INTO departments (id, tenant_id, code, display_name) VALUES
  ('00000000-0000-0000-A1A3-000000000001', '00000000-0000-0000-A1A0-000000000001', 'COMERCIAL', 'Comercial');

-- 4 usuarios no tenant + 1 super_admin
INSERT INTO app_users (
  id, tenant_id, auth_user_id, email, full_name, role,
  employer_unit_id, working_unit_id, department_id,
  manager_id, employment_link, hired_at
) VALUES
  -- DIR no tenant (em W1)
  ('00000000-0000-0000-A1A4-000000000001',
   '00000000-0000-0000-A1A0-000000000001',
   'aaaa1111-1111-1111-1111-000000000001',
   'dir@a1.test', 'Diretor A1', 'diretoria',
   '00000000-0000-0000-A1A1-000000000001',
   '00000000-0000-0000-A1A2-000000000001',
   '00000000-0000-0000-A1A3-000000000001',
   NULL, 'clt', '2020-01-01'),

  -- U1 colaborador em W1
  ('00000000-0000-0000-A1A4-000000000002',
   '00000000-0000-0000-A1A0-000000000001',
   'aaaa1111-1111-1111-1111-000000000002',
   'u1@a1.test', 'User Um W1', 'colaborador',
   '00000000-0000-0000-A1A1-000000000001',
   '00000000-0000-0000-A1A2-000000000001',
   '00000000-0000-0000-A1A3-000000000001',
   '00000000-0000-0000-A1A4-000000000001', 'clt', '2020-01-01'),

  -- U2 colaborador em W2 (mesmo employer Z1)
  ('00000000-0000-0000-A1A4-000000000003',
   '00000000-0000-0000-A1A0-000000000001',
   'aaaa1111-1111-1111-1111-000000000003',
   'u2@a1.test', 'User Dois W2', 'colaborador',
   '00000000-0000-0000-A1A1-000000000001',
   '00000000-0000-0000-A1A2-000000000002',
   '00000000-0000-0000-A1A3-000000000001',
   '00000000-0000-0000-A1A4-000000000001', 'clt', '2020-01-01'),

  -- U3 colaborador em W3 (employer Z2)
  ('00000000-0000-0000-A1A4-000000000004',
   '00000000-0000-0000-A1A0-000000000001',
   'aaaa1111-1111-1111-1111-000000000004',
   'u3@a1.test', 'User Tres W3', 'colaborador',
   '00000000-0000-0000-A1A1-000000000002',
   '00000000-0000-0000-A1A2-000000000003',
   '00000000-0000-0000-A1A3-000000000001',
   '00000000-0000-0000-A1A4-000000000001', 'clt', '2020-01-01'),

  -- SA super_admin global (sem tenant_id real · usa tenant placeholder pra contornar NOT NULL)
  -- Em producao Supabase super_admin tera mecanismo proprio · aqui simulamos
  ('00000000-0000-0000-A1A4-0000000000FF',
   '00000000-0000-0000-A1A0-000000000001',
   'aaaa1111-1111-1111-1111-0000000000FF',
   'sa@r2.test', 'Super Admin R2', 'super_admin',
   NULL, NULL, NULL,
   NULL, 'clt', '2020-01-01');

-- ============================================================================
-- HELPER · contadores e logs
-- ============================================================================

CREATE OR REPLACE FUNCTION a1_assert(condition BOOLEAN, msg TEXT)
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
-- TESTE 1 · helper module_is_active_for_user resolve wu corretamente
-- ============================================================================
-- Sem ativacao · todos retornam FALSE
SELECT a1_assert(
  module_is_active_for_user('recognition', '00000000-0000-0000-A1A4-000000000002') = FALSE,
  'T01 · for_user(recognition, U1) retorna FALSE sem ativacao'
);

SELECT a1_assert(
  module_is_active_for_user('recognition', NULL) = FALSE,
  'T02 · for_user(recognition, NULL) retorna FALSE'
);

-- Modulo nao existe
SELECT a1_assert(
  module_is_active_for_user('inexistente', '00000000-0000-0000-A1A4-000000000002') = FALSE,
  'T03 · for_user com modulo inexistente retorna FALSE'
);

-- Modulo core (base) sempre TRUE
SELECT a1_assert(
  module_is_active_for_user('base', '00000000-0000-0000-A1A4-000000000002') = TRUE,
  'T04 · for_user(base, U1) retorna TRUE (modulo core)'
);

-- ============================================================================
-- TESTE 2 · sem ativacao · TODAS as RPCs retornam module_inactive
-- ============================================================================
SELECT test_login('aaaa1111-1111-1111-1111-000000000001');  -- DIR

-- Recognition
SELECT a1_assert(
  rpc_recognition_create('00000000-0000-0000-A1A4-000000000002',
                         'mensagem teste') ->> 'error' = 'module_inactive',
  'T05 · rpc_recognition_create bloqueia sem ativacao'
);

SELECT a1_assert(
  rpc_recognition_get_feed() ->> 'error' = 'module_inactive',
  'T06 · rpc_recognition_get_feed bloqueia sem ativacao'
);

SELECT a1_assert(
  rpc_recognition_get_stats() ->> 'error' = 'module_inactive',
  'T07 · rpc_recognition_get_stats bloqueia sem ativacao'
);

-- PDI
SELECT a1_assert(
  rpc_pdi_list_cycles() ->> 'error' = 'module_inactive',
  'T08 · rpc_pdi_list_cycles bloqueia sem ativacao'
);

SELECT a1_assert(
  rpc_pdi_list() ->> 'error' = 'module_inactive',
  'T09 · rpc_pdi_list bloqueia sem ativacao'
);

-- Onboarding
SELECT a1_assert(
  rpc_onb_template_list() ->> 'error' = 'module_inactive',
  'T10 · rpc_onb_template_list bloqueia sem ativacao'
);

SELECT a1_assert(
  rpc_onboarding_list() ->> 'error' = 'module_inactive',
  'T11 · rpc_onboarding_list bloqueia sem ativacao'
);

-- Resposta tem o campo "module" populado corretamente
SELECT a1_assert(
  rpc_recognition_get_feed() ->> 'module' = 'recognition',
  'T12 · payload de erro inclui module=recognition'
);

SELECT a1_assert(
  rpc_pdi_list_cycles() ->> 'module' = 'pdi',
  'T13 · payload de erro inclui module=pdi'
);

SELECT a1_assert(
  rpc_onboarding_list() ->> 'module' = 'onboarding',
  'T14 · payload de erro inclui module=onboarding'
);

-- ============================================================================
-- TESTE 3 · ativacao no escopo TENANT · libera todos os usuarios do tenant
-- ============================================================================
-- Setamos super_admin para fazer a ativacao
SELECT test_login('aaaa1111-1111-1111-1111-0000000000FF');  -- SA

-- Ativa Recognition no tenant inteiro
INSERT INTO module_activations (module_code, scope_kind, tenant_id, activated_by)
VALUES ('recognition', 'tenant',
        '00000000-0000-0000-A1A0-000000000001',
        '00000000-0000-0000-A1A4-0000000000FF');

-- U1 (W1) deve passar
SELECT test_login('aaaa1111-1111-1111-1111-000000000002');
SELECT a1_assert(
  rpc_recognition_get_feed() ->> 'ok' = 'true',
  'T15 · ativacao tenant libera U1 (W1)'
);

-- U2 (W2) deve passar
SELECT test_login('aaaa1111-1111-1111-1111-000000000003');
SELECT a1_assert(
  rpc_recognition_get_feed() ->> 'ok' = 'true',
  'T16 · ativacao tenant libera U2 (W2 mesmo employer)'
);

-- U3 (W3) deve passar tambem (employer Z2 diferente)
SELECT test_login('aaaa1111-1111-1111-1111-000000000004');
SELECT a1_assert(
  rpc_recognition_get_feed() ->> 'ok' = 'true',
  'T17 · ativacao tenant libera U3 (W3 employer diferente)'
);

-- PDI ainda nao foi ativado · deve continuar bloqueando
SELECT a1_assert(
  rpc_pdi_list_cycles() ->> 'error' = 'module_inactive',
  'T18 · ativacao de recognition NAO libera PDI'
);

-- ============================================================================
-- TESTE 4 · ativacao no escopo EMPLOYER_UNIT · so os WU do employer Z1 passam
-- ============================================================================
SELECT test_login('aaaa1111-1111-1111-1111-0000000000FF');  -- SA

-- Ativa PDI no employer Z1 (cobre W1 e W2, NAO cobre W3)
INSERT INTO module_activations (module_code, scope_kind, employer_unit_id, activated_by)
VALUES ('pdi', 'employer_unit',
        '00000000-0000-0000-A1A1-000000000001',
        '00000000-0000-0000-A1A4-0000000000FF');

SELECT test_login('aaaa1111-1111-1111-1111-000000000002');  -- U1 em W1
SELECT a1_assert(
  rpc_pdi_list_cycles() ->> 'ok' = 'true',
  'T19 · ativacao employer Z1 libera U1 (W1 dentro de Z1)'
);

SELECT test_login('aaaa1111-1111-1111-1111-000000000003');  -- U2 em W2
SELECT a1_assert(
  rpc_pdi_list_cycles() ->> 'ok' = 'true',
  'T20 · ativacao employer Z1 libera U2 (W2 dentro de Z1)'
);

SELECT test_login('aaaa1111-1111-1111-1111-000000000004');  -- U3 em W3 (Z2)
SELECT a1_assert(
  rpc_pdi_list_cycles() ->> 'error' = 'module_inactive',
  'T21 · ativacao employer Z1 NAO libera U3 (W3 fora de Z1)'
);

-- ============================================================================
-- TESTE 5 · ativacao no escopo WORKING_UNIT · so essa wu
-- ============================================================================
SELECT test_login('aaaa1111-1111-1111-1111-0000000000FF');  -- SA

-- Ativa Onboarding so em W3
INSERT INTO module_activations (module_code, scope_kind, working_unit_id, activated_by)
VALUES ('onboarding', 'working_unit',
        '00000000-0000-0000-A1A2-000000000003',
        '00000000-0000-0000-A1A4-0000000000FF');

SELECT test_login('aaaa1111-1111-1111-1111-000000000004');  -- U3 em W3
SELECT a1_assert(
  rpc_onboarding_list() ->> 'ok' = 'true',
  'T22 · ativacao working W3 libera U3'
);

SELECT test_login('aaaa1111-1111-1111-1111-000000000002');  -- U1 em W1
SELECT a1_assert(
  rpc_onboarding_list() ->> 'error' = 'module_inactive',
  'T23 · ativacao working W3 NAO libera U1 (W1 diferente)'
);

SELECT test_login('aaaa1111-1111-1111-1111-000000000003');  -- U2 em W2
SELECT a1_assert(
  rpc_onboarding_list() ->> 'error' = 'module_inactive',
  'T24 · ativacao working W3 NAO libera U2 (W2 diferente)'
);

-- ============================================================================
-- TESTE 6 · super_admin sempre passa (mesmo sem ativacao no proprio tenant)
-- ============================================================================
SELECT test_login('aaaa1111-1111-1111-1111-0000000000FF');  -- SA

-- Verificamos uma RPC de cada modulo
-- get_feed do recognition deve passar (tenant tem ativacao)
SELECT a1_assert(
  rpc_recognition_get_feed() ->> 'ok' = 'true',
  'T25 · super_admin passa em recognition (tenant ativo)'
);

-- pdi_list_cycles · super_admin sempre passa pelo gate de modulo
-- NOTA: pode falhar depois por permissao/business · so checamos que nao
-- deu module_inactive
SELECT a1_assert(
  COALESCE(rpc_pdi_list_cycles() ->> 'error', '') NOT IN ('module_inactive'),
  'T26 · super_admin nao bate em module_inactive (pdi)'
);

SELECT a1_assert(
  COALESCE(rpc_onboarding_list() ->> 'error', '') NOT IN ('module_inactive'),
  'T27 · super_admin nao bate em module_inactive (onboarding)'
);

-- ============================================================================
-- TESTE 7 · gate de auth ainda funciona (not_authenticated antes do check)
-- ============================================================================
SELECT test_logout();

SELECT a1_assert(
  rpc_recognition_get_feed() ->> 'error' = 'not_authenticated',
  'T28 · sem login retorna not_authenticated (precede module_inactive)'
);

SELECT a1_assert(
  rpc_pdi_list() ->> 'error' = 'not_authenticated',
  'T29 · sem login retorna not_authenticated (pdi)'
);

SELECT a1_assert(
  rpc_onboarding_list() ->> 'error' = 'not_authenticated',
  'T30 · sem login retorna not_authenticated (onboarding)'
);

-- ============================================================================
-- TESTE 8 · smoke test fim-a-fim · cria recognition apos modulo ativo
-- ============================================================================
-- Recognition esta ativo no tenant. U1 cria reconhecimento para U2.
SELECT test_login('aaaa1111-1111-1111-1111-000000000002');  -- U1

SELECT a1_assert(
  rpc_recognition_create(
    '00000000-0000-0000-A1A4-000000000003'::UUID,
    'Excelente trabalho na demo'
  ) ->> 'ok' = 'true',
  'T31 · smoke · U1 cria reconhecimento para U2 com modulo ativo'
);

-- ============================================================================
-- TESTE 9 · desativacao volta a bloquear
-- ============================================================================
SELECT test_login('aaaa1111-1111-1111-1111-0000000000FF');  -- SA

DELETE FROM module_activations
WHERE module_code = 'recognition' AND scope_kind = 'tenant';

SELECT test_login('aaaa1111-1111-1111-1111-000000000002');  -- U1
SELECT a1_assert(
  rpc_recognition_get_feed() ->> 'error' = 'module_inactive',
  'T32 · desativacao do recognition no tenant volta a bloquear'
);

-- ============================================================================
-- FECHAMENTO
-- ============================================================================

DO $$
BEGIN
  RAISE NOTICE '========================================';
  RAISE NOTICE '=== A1 · 32 testes executados · OK   ===';
  RAISE NOTICE '========================================';
END $$;

ROLLBACK;

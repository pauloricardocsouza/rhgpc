-- ============================================================================
-- R2 People · Testes Sessao B3 · Navbar dinamica
-- ============================================================================
-- Cobertura:
--   1. Catalogo por papel · contagens corretas para cada role
--   2. Auth · sem login retorna error
--   3. Filtragem · modulo inativo (sem activation) NAO aparece
--   4. Filtragem · modulo soft_disabled APARECE com readonly=true
--   5. Itens core (sem module_code) sempre aparecem
--   6. super_admin · ve tudo independente do estado dos modulos
--   7. Diferentes papeis veem listas diferentes
-- ============================================================================

BEGIN;

-- ============================================================================
-- SETUP · 1 tenant, varios usuarios cobrindo todos os papeis
-- ============================================================================

INSERT INTO tenants (id, slug, legal_name, display_name) VALUES
  ('00000000-0000-0000-B3A0-000000000001', 'tenant-b3', 'Tenant B3', 'B3');

INSERT INTO employer_units (id, tenant_id, code, legal_name) VALUES
  ('00000000-0000-0000-B3A1-000000000001', '00000000-0000-0000-B3A0-000000000001', 'B3-EMP', 'B3 Employer');

INSERT INTO working_units (id, tenant_id, employer_unit_id, code, display_name) VALUES
  ('00000000-0000-0000-B3A2-000000000001', '00000000-0000-0000-B3A0-000000000001', '00000000-0000-0000-B3A1-000000000001', 'B3-WU', 'B3 WU');

INSERT INTO departments (id, tenant_id, code, display_name) VALUES
  ('00000000-0000-0000-B3A3-000000000001', '00000000-0000-0000-B3A0-000000000001', 'OPS', 'OPS');

INSERT INTO app_users (
  id, tenant_id, auth_user_id, email, full_name, role,
  employer_unit_id, working_unit_id, department_id,
  manager_id, employment_link, hired_at
) VALUES
  ('00000000-0000-0000-B3A4-00000000000A', '00000000-0000-0000-B3A0-000000000001', 'b3aa4444-4444-4444-4444-00000000000A', 'sa@r2.test',  'SA',  'super_admin',
    NULL, NULL, NULL, NULL, 'clt', '2020-01-01'),
  ('00000000-0000-0000-B3A4-00000000000B', '00000000-0000-0000-B3A0-000000000001', 'b3aa4444-4444-4444-4444-00000000000B', 'dir@b3.test', 'DIR', 'diretoria',
    '00000000-0000-0000-B3A1-000000000001', '00000000-0000-0000-B3A2-000000000001', '00000000-0000-0000-B3A3-000000000001', NULL, 'clt', '2020-01-01'),
  ('00000000-0000-0000-B3A4-00000000000C', '00000000-0000-0000-B3A0-000000000001', 'b3aa4444-4444-4444-4444-00000000000C', 'rh@b3.test',  'RH',  'rh',
    '00000000-0000-0000-B3A1-000000000001', '00000000-0000-0000-B3A2-000000000001', '00000000-0000-0000-B3A3-000000000001', '00000000-0000-0000-B3A4-00000000000B', 'clt', '2020-01-01'),
  ('00000000-0000-0000-B3A4-00000000000D', '00000000-0000-0000-B3A0-000000000001', 'b3aa4444-4444-4444-4444-00000000000D', 'lid@b3.test', 'LID', 'lider',
    '00000000-0000-0000-B3A1-000000000001', '00000000-0000-0000-B3A2-000000000001', '00000000-0000-0000-B3A3-000000000001', '00000000-0000-0000-B3A4-00000000000B', 'clt', '2020-01-01'),
  ('00000000-0000-0000-B3A4-00000000000E', '00000000-0000-0000-B3A0-000000000001', 'b3aa4444-4444-4444-4444-00000000000E', 'col@b3.test', 'COL', 'colaborador',
    '00000000-0000-0000-B3A1-000000000001', '00000000-0000-0000-B3A2-000000000001', '00000000-0000-0000-B3A3-000000000001', '00000000-0000-0000-B3A4-00000000000D', 'clt', '2020-01-01');

-- Helper de assert
CREATE OR REPLACE FUNCTION b3_assert(condition BOOLEAN, msg TEXT)
RETURNS VOID AS $$
BEGIN
  IF NOT condition THEN
    RAISE EXCEPTION 'FAIL · %', msg;
  ELSE
    RAISE NOTICE 'PASS · %', msg;
  END IF;
END;
$$ LANGUAGE plpgsql;

-- Helper · conta itens por key na resposta da rpc
CREATE OR REPLACE FUNCTION b3_count_items(p_resp JSONB)
RETURNS INT AS $$
  SELECT COALESCE(jsonb_array_length(p_resp -> 'items'), 0);
$$ LANGUAGE sql IMMUTABLE;

CREATE OR REPLACE FUNCTION b3_has_item(p_resp JSONB, p_key TEXT)
RETURNS BOOLEAN AS $$
  SELECT EXISTS (
    SELECT 1 FROM jsonb_array_elements(p_resp -> 'items') AS i
    WHERE i ->> 'key' = p_key
  );
$$ LANGUAGE sql IMMUTABLE;

CREATE OR REPLACE FUNCTION b3_item_readonly(p_resp JSONB, p_key TEXT)
RETURNS BOOLEAN AS $$
  SELECT (i ->> 'readonly')::BOOLEAN
  FROM jsonb_array_elements(p_resp -> 'items') AS i
  WHERE i ->> 'key' = p_key;
$$ LANGUAGE sql IMMUTABLE;

-- ============================================================================
-- T01-T05 · Catalogo por papel (helper IMMUTABLE)
-- Conta os itens retornados por my_navbar_items_by_role para cada papel
-- ============================================================================

SELECT b3_assert(
  (SELECT count(*) FROM my_navbar_items_by_role('super_admin'))::INT = 13,
  'T01 · super_admin tem 13 itens no catalogo (incluindo admin/*)'
);

SELECT b3_assert(
  (SELECT count(*) FROM my_navbar_items_by_role('diretoria'))::INT = 11,
  'T02 · diretoria tem 11 itens (5 modulos + main + admin/modulos + admin/usuarios)'
);

SELECT b3_assert(
  (SELECT count(*) FROM my_navbar_items_by_role('rh'))::INT = 9,
  'T03 · rh tem 9 itens (sem admin/*)'
);

SELECT b3_assert(
  (SELECT count(*) FROM my_navbar_items_by_role('lider'))::INT = 6,
  'T04 · lider tem 6 itens'
);

SELECT b3_assert(
  (SELECT count(*) FROM my_navbar_items_by_role('colaborador'))::INT = 7,
  'T05 · colaborador tem 7 itens'
);

-- T06 · papel desconhecido retorna vazio
SELECT b3_assert(
  (SELECT count(*) FROM my_navbar_items_by_role('unknown_role'))::INT = 0,
  'T06 · papel desconhecido retorna catalogo vazio'
);

-- ============================================================================
-- T07-T08 · Auth
-- ============================================================================

SELECT test_logout();
SELECT b3_assert(
  rpc_my_navbar() ->> 'error' = 'not_authenticated',
  'T07 · sem login, rpc_my_navbar retorna not_authenticated'
);

SELECT test_login('b3aa4444-4444-4444-4444-00000000000E');  -- COL
SELECT b3_assert(
  (rpc_my_navbar() ->> 'ok')::BOOLEAN = TRUE,
  'T08 · com login valido, rpc_my_navbar retorna ok'
);

-- ============================================================================
-- T09-T11 · Sem nenhuma activation: so itens core aparecem
-- ============================================================================

-- COL e colaborador. Catalogo dele: 7 itens, sendo 5 com module_code.
-- Sem activations, esperado: 2 itens visiveis (home + my_profile)
SELECT test_login('b3aa4444-4444-4444-4444-00000000000E');
DO $$
DECLARE v_resp JSONB;
DECLARE v_count INT;
BEGIN
  v_resp := rpc_my_navbar();
  v_count := b3_count_items(v_resp);
  IF v_count <> 2 THEN
    RAISE EXCEPTION 'T09 FAIL · esperava 2 itens (home, my_profile) · veio %', v_count;
  END IF;
  IF NOT b3_has_item(v_resp, 'home') OR NOT b3_has_item(v_resp, 'my_profile') THEN
    RAISE EXCEPTION 'T09 FAIL · faltam home/my_profile · resp=%', v_resp;
  END IF;
  IF b3_has_item(v_resp, 'recognition') OR b3_has_item(v_resp, 'pdi') THEN
    RAISE EXCEPTION 'T09 FAIL · modulo inativo aparecendo · resp=%', v_resp;
  END IF;
  RAISE NOTICE 'PASS · T09 · colaborador sem activations: so itens core (home, my_profile)';
END $$;

-- T10 · super_admin com nenhum modulo ativo · ainda assim ve TODOS os itens
-- (super_admin sempre passa nos gates de modulo)
SELECT test_login('b3aa4444-4444-4444-4444-00000000000A');
DO $$
DECLARE v_resp JSONB;
BEGIN
  v_resp := rpc_my_navbar();
  IF b3_count_items(v_resp) <> 13 THEN
    RAISE EXCEPTION 'T10 FAIL · super_admin deve ver 13 itens · veio %', b3_count_items(v_resp);
  END IF;
  RAISE NOTICE 'PASS · T10 · super_admin ve todos os 13 itens mesmo sem activations';
END $$;

-- T11 · super_admin · readonly sempre false (mesmo se modulo soft_disabled)
DO $$
DECLARE v_resp JSONB;
DECLARE v_item JSONB;
BEGIN
  v_resp := rpc_my_navbar();
  FOR v_item IN SELECT * FROM jsonb_array_elements(v_resp -> 'items')
  LOOP
    IF (v_item ->> 'readonly')::BOOLEAN <> FALSE THEN
      RAISE EXCEPTION 'T11 FAIL · super_admin com readonly=true em %', v_item;
    END IF;
  END LOOP;
  RAISE NOTICE 'PASS · T11 · super_admin sempre tem readonly=false';
END $$;

-- ============================================================================
-- T12-T14 · Activations no tenant · modulos aparecem
-- ============================================================================

-- super_admin ativa recognition + ninebox no tenant
SELECT rpc_admin_module_activate('recognition', 'tenant', '00000000-0000-0000-B3A0-000000000001');
SELECT rpc_admin_module_activate('ninebox', 'tenant', '00000000-0000-0000-B3A0-000000000001');

-- Volta para colaborador
SELECT test_login('b3aa4444-4444-4444-4444-00000000000E');

-- T12 · colaborador agora ve recognition + ninebox + core (4 itens)
DO $$
DECLARE v_resp JSONB;
BEGIN
  v_resp := rpc_my_navbar();
  IF NOT b3_has_item(v_resp, 'recognition') THEN
    RAISE EXCEPTION 'T12 FAIL · recognition deveria aparecer · resp=%', v_resp;
  END IF;
  IF NOT b3_has_item(v_resp, 'ninebox') THEN
    RAISE EXCEPTION 'T12 FAIL · ninebox deveria aparecer · resp=%', v_resp;
  END IF;
  IF b3_has_item(v_resp, 'pdi') THEN
    RAISE EXCEPTION 'T12 FAIL · pdi NAO deveria aparecer (nao ativado) · resp=%', v_resp;
  END IF;
  RAISE NOTICE 'PASS · T12 · colaborador ve recognition+ninebox, mas nao pdi (nao ativo)';
END $$;

-- T13 · readonly=false para modulos ativos
SELECT b3_assert(
  b3_item_readonly(rpc_my_navbar(), 'recognition') = FALSE,
  'T13 · recognition aparece com readonly=false'
);

SELECT b3_assert(
  b3_item_readonly(rpc_my_navbar(), 'ninebox') = FALSE,
  'T14 · ninebox aparece com readonly=false'
);

-- ============================================================================
-- T15-T18 · soft_disabled · modulo aparece com readonly=true
-- ============================================================================

-- diretoria desativa ninebox no tenant (soft-disable)
SELECT test_login('b3aa4444-4444-4444-4444-00000000000B');  -- DIR
SELECT rpc_admin_module_deactivate(
  'ninebox', 'tenant', '00000000-0000-0000-B3A0-000000000001', 'teste B3'
);

-- Colaborador ainda ve ninebox, agora com readonly=true
SELECT test_login('b3aa4444-4444-4444-4444-00000000000E');

SELECT b3_assert(
  b3_has_item(rpc_my_navbar(), 'ninebox'),
  'T15 · ninebox soft_disabled ainda aparece no menu'
);

SELECT b3_assert(
  b3_item_readonly(rpc_my_navbar(), 'ninebox') = TRUE,
  'T16 · ninebox soft_disabled tem readonly=true (cadeado no frontend)'
);

-- T17 · recognition (que ainda esta ativo) tem readonly=false
SELECT b3_assert(
  b3_item_readonly(rpc_my_navbar(), 'recognition') = FALSE,
  'T17 · recognition ainda ativo · readonly=false'
);

-- T18 · super_admin nunca em readonly mesmo com soft_disabled
SELECT test_login('b3aa4444-4444-4444-4444-00000000000A');
SELECT b3_assert(
  b3_item_readonly(rpc_my_navbar(), 'ninebox') = FALSE,
  'T18 · super_admin · ninebox soft_disabled mas readonly=false (super_admin sempre passa)'
);

-- ============================================================================
-- T19-T20 · Reativacao remove o readonly
-- ============================================================================

SELECT test_login('b3aa4444-4444-4444-4444-00000000000B');  -- DIR
SELECT rpc_admin_module_reactivate('ninebox', 'tenant', '00000000-0000-0000-B3A0-000000000001');

SELECT test_login('b3aa4444-4444-4444-4444-00000000000E');  -- COL
SELECT b3_assert(
  b3_item_readonly(rpc_my_navbar(), 'ninebox') = FALSE,
  'T19 · ninebox reativado · readonly volta para false'
);

SELECT b3_assert(
  b3_has_item(rpc_my_navbar(), 'ninebox'),
  'T20 · ninebox reativado · continua visivel no menu'
);

-- ============================================================================
-- T21-T23 · Diferentes papeis · listas diferentes (com mesmas activations)
-- ============================================================================

-- diretoria · ve admin_modules e admin_usuarios
SELECT test_login('b3aa4444-4444-4444-4444-00000000000B');
SELECT b3_assert(
  b3_has_item(rpc_my_navbar(), 'admin_modules'),
  'T21 · diretoria ve admin_modules'
);

-- rh · NAO ve admin_*
SELECT test_login('b3aa4444-4444-4444-4444-00000000000C');
SELECT b3_assert(
  NOT b3_has_item(rpc_my_navbar(), 'admin_modules'),
  'T22 · rh NAO ve admin_modules'
);

-- lider · ve my_team mas nao admin_modules nem people (people e so para rh+)
SELECT test_login('b3aa4444-4444-4444-4444-00000000000D');
DO $$
DECLARE v_resp JSONB;
BEGIN
  v_resp := rpc_my_navbar();
  IF NOT b3_has_item(v_resp, 'my_team') THEN
    RAISE EXCEPTION 'T23 FAIL · lider deveria ver my_team';
  END IF;
  IF b3_has_item(v_resp, 'admin_modules') THEN
    RAISE EXCEPTION 'T23 FAIL · lider NAO deveria ver admin_modules';
  END IF;
  IF b3_has_item(v_resp, 'people') THEN
    RAISE EXCEPTION 'T23 FAIL · lider NAO deveria ver people (so rh+)';
  END IF;
  RAISE NOTICE 'PASS · T23 · lider ve my_team, nao ve admin_modules nem people';
END $$;

-- ============================================================================
-- T24 · Sections · garante que itens carregam o campo section
-- ============================================================================

SELECT test_login('b3aa4444-4444-4444-4444-00000000000A');  -- SA
DO $$
DECLARE v_resp JSONB;
DECLARE v_item JSONB;
DECLARE v_sections TEXT[] := '{}';
BEGIN
  v_resp := rpc_my_navbar();
  FOR v_item IN SELECT * FROM jsonb_array_elements(v_resp -> 'items')
  LOOP
    IF v_item ->> 'section' IS NULL THEN
      RAISE EXCEPTION 'T24 FAIL · item sem section: %', v_item;
    END IF;
    v_sections := array_append(v_sections, v_item ->> 'section');
  END LOOP;
  IF NOT ('main' = ANY(v_sections) AND 'modules' = ANY(v_sections) AND 'admin' = ANY(v_sections)) THEN
    RAISE EXCEPTION 'T24 FAIL · super_admin deveria ter sections main, modules e admin · sections=%', v_sections;
  END IF;
  RAISE NOTICE 'PASS · T24 · todos os itens tem section · super_admin cobre main/modules/admin';
END $$;

-- ============================================================================
-- T25 · Estrutura do item · campos obrigatorios
-- ============================================================================

DO $$
DECLARE v_resp JSONB;
DECLARE v_item JSONB;
BEGIN
  v_resp := rpc_my_navbar();
  FOR v_item IN SELECT * FROM jsonb_array_elements(v_resp -> 'items')
  LOOP
    IF v_item ->> 'key' IS NULL OR v_item ->> 'label' IS NULL OR v_item ->> 'icon' IS NULL OR v_item ->> 'path' IS NULL THEN
      RAISE EXCEPTION 'T25 FAIL · item incompleto: %', v_item;
    END IF;
    IF v_item ->> 'readonly' IS NULL THEN
      RAISE EXCEPTION 'T25 FAIL · item sem readonly: %', v_item;
    END IF;
  END LOOP;
  RAISE NOTICE 'PASS · T25 · todos os itens tem key/label/icon/path/readonly';
END $$;

-- ============================================================================
-- FECHAMENTO
-- ============================================================================

DO $$
BEGIN
  RAISE NOTICE '========================================';
  RAISE NOTICE '=== B3 · 25 testes executados · OK   ===';
  RAISE NOTICE '========================================';
END $$;

ROLLBACK;

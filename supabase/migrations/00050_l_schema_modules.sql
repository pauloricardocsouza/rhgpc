-- ============================================================================
-- R2 People · Schema Modules v1 (Sessao L)
-- ============================================================================
-- Sistema de modulos com ativacao gradual por escopo (tenant/employer/working).
--
-- Decisoes da Sessao L:
--   - Granularidade total: tenant > employer_unit > working_unit
--   - Super admin R2 controla tudo (role global, fora do tenant)
--   - Flag liga/desliga (sem datas/expiracao)
--   - Bloqueio total · 404 frontend / RLS bloqueia backend
--   - Heranca: ativo no tenant -> vale para tudo abaixo
--                ativo no employer -> vale para working_units desse employer
--                ativo no working -> vale so para essa loja
--
-- Pre-requisitos:
--   - r2_people_schema_base_v1.sql aplicado
--   - r2_people_seed_base_v1.sql aplicado
--
-- Ordem de aplicacao:
--   1. r2_people_schema_modules_v1.sql                (este arquivo)
--   2. r2_people_seed_modules_v1.sql                  (catalogo + super_admin)
--   3. r2_people_rls_policies_modules_tests.sql      (opcional)
-- ============================================================================

-- ============================================================================
-- ENUMS
-- ============================================================================

DO $$ BEGIN
  CREATE TYPE module_scope_kind AS ENUM ('tenant', 'employer_unit', 'working_unit');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- ============================================================================
-- ALTERAR app_user_role para incluir super_admin
-- ============================================================================
-- super_admin e role global da R2 (fora dos tenants do cliente)
-- nao tem tenant_id nem unidade · acessa tudo

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_enum e JOIN pg_type t ON t.oid = e.enumtypid
    WHERE t.typname = 'app_user_role' AND e.enumlabel = 'super_admin'
  ) THEN
    ALTER TYPE app_user_role ADD VALUE 'super_admin' BEFORE 'diretoria';
  END IF;
END $$;

-- ============================================================================
-- TABELAS
-- ============================================================================

-- Catalogo global de modulos (gerenciado pela R2)
CREATE TABLE IF NOT EXISTS modules (
  code            VARCHAR(40) PRIMARY KEY,            -- 'climate', 'recognition', 'pdi', 'onboarding'
  display_name    VARCHAR(120) NOT NULL,
  description     TEXT,
  icon_name       VARCHAR(40),                         -- referencia para frontend (lucide icon name)
  is_core         BOOLEAN NOT NULL DEFAULT FALSE,      -- core nao pode ser desligado (ex: base)
  display_order   INT NOT NULL DEFAULT 0,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT now(),

  CONSTRAINT modules_code_format CHECK (code ~ '^[a-z][a-z0-9_]+$'),
  CONSTRAINT modules_name_length CHECK (char_length(display_name) BETWEEN 3 AND 120)
);

CREATE INDEX IF NOT EXISTS idx_modules_order ON modules(display_order, code);

-- Ativacoes por escopo (tenant/employer/working)
-- A presenca de uma row significa "ativo". Ausencia = inativo.
-- A heranca e resolvida pela funcao module_is_active().
CREATE TABLE IF NOT EXISTS module_activations (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  module_code     VARCHAR(40) NOT NULL REFERENCES modules(code) ON DELETE CASCADE,

  scope_kind      module_scope_kind NOT NULL,

  -- Exatamente UM dos tres deve estar preenchido (CHECK abaixo)
  tenant_id       UUID REFERENCES tenants(id) ON DELETE CASCADE,
  employer_unit_id UUID REFERENCES employer_units(id) ON DELETE CASCADE,
  working_unit_id UUID REFERENCES working_units(id) ON DELETE CASCADE,

  -- Auditoria
  activated_by    UUID NOT NULL REFERENCES app_users(id),
  activated_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
  notes           TEXT,                                -- razao/observacao da ativacao

  CONSTRAINT module_activations_scope_match CHECK (
    (scope_kind = 'tenant'        AND tenant_id IS NOT NULL AND employer_unit_id IS NULL AND working_unit_id IS NULL)
    OR (scope_kind = 'employer_unit' AND tenant_id IS NULL AND employer_unit_id IS NOT NULL AND working_unit_id IS NULL)
    OR (scope_kind = 'working_unit'  AND tenant_id IS NULL AND employer_unit_id IS NULL AND working_unit_id IS NOT NULL)
  )
);

-- UNIQUE constraints por escopo
CREATE UNIQUE INDEX IF NOT EXISTS uq_module_activations_tenant
  ON module_activations(module_code, tenant_id) WHERE scope_kind = 'tenant';
CREATE UNIQUE INDEX IF NOT EXISTS uq_module_activations_employer
  ON module_activations(module_code, employer_unit_id) WHERE scope_kind = 'employer_unit';
CREATE UNIQUE INDEX IF NOT EXISTS uq_module_activations_working
  ON module_activations(module_code, working_unit_id) WHERE scope_kind = 'working_unit';

CREATE INDEX IF NOT EXISTS idx_module_activations_module ON module_activations(module_code);
CREATE INDEX IF NOT EXISTS idx_module_activations_tenant_lookup
  ON module_activations(tenant_id, module_code) WHERE scope_kind = 'tenant';
CREATE INDEX IF NOT EXISTS idx_module_activations_employer_lookup
  ON module_activations(employer_unit_id, module_code) WHERE scope_kind = 'employer_unit';
CREATE INDEX IF NOT EXISTS idx_module_activations_working_lookup
  ON module_activations(working_unit_id, module_code) WHERE scope_kind = 'working_unit';

-- ============================================================================
-- TRIGGERS · updated_at + audit
-- ============================================================================

DROP TRIGGER IF EXISTS trg_modules_updated_at ON modules;
CREATE TRIGGER trg_modules_updated_at BEFORE UPDATE ON modules
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

DROP TRIGGER IF EXISTS trg_audit_modules ON modules;
CREATE TRIGGER trg_audit_modules
  AFTER INSERT OR UPDATE OR DELETE ON modules
  FOR EACH ROW EXECUTE FUNCTION audit_change();

DROP TRIGGER IF EXISTS trg_audit_module_activations ON module_activations;
CREATE TRIGGER trg_audit_module_activations
  AFTER INSERT OR UPDATE OR DELETE ON module_activations
  FOR EACH ROW EXECUTE FUNCTION audit_change();

-- ============================================================================
-- HELPERS
-- ============================================================================

-- Verifica se o usuario logado e super_admin (role global da R2)
CREATE OR REPLACE FUNCTION is_super_admin()
RETURNS BOOLEAN
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_role app_user_role;
BEGIN
  v_role := current_user_role();
  IF v_role IS NULL THEN
    RETURN FALSE;
  END IF;
  RETURN v_role = 'super_admin';
END;
$$;

-- Verifica se o modulo esta ativo num escopo qualquer (working_unit_id)
-- Heranca: working_unit -> employer_unit (do working) -> tenant (do employer)
-- Se ANY um nivel acima estiver ativado, retorna TRUE.
-- Se for um modulo `is_core`, sempre TRUE.
CREATE OR REPLACE FUNCTION module_is_active(
  p_module_code VARCHAR,
  p_working_unit_id UUID
)
RETURNS BOOLEAN
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_is_core BOOLEAN;
  v_employer_id UUID;
  v_tenant_id UUID;
BEGIN
  -- Modulos core sao sempre ativos
  SELECT is_core INTO v_is_core FROM modules WHERE code = p_module_code;
  IF v_is_core IS NULL THEN
    RETURN FALSE;  -- modulo nao existe
  END IF;
  IF v_is_core = TRUE THEN
    RETURN TRUE;
  END IF;

  IF p_working_unit_id IS NULL THEN
    RETURN FALSE;
  END IF;

  -- Resolve employer_unit e tenant via working_unit
  SELECT employer_unit_id, tenant_id INTO v_employer_id, v_tenant_id
  FROM working_units WHERE id = p_working_unit_id;

  IF v_tenant_id IS NULL THEN
    RETURN FALSE;
  END IF;

  -- Verifica em ordem: working -> employer -> tenant
  RETURN EXISTS (
    SELECT 1 FROM module_activations
    WHERE module_code = p_module_code
      AND (
        (scope_kind = 'working_unit'  AND working_unit_id = p_working_unit_id)
        OR (scope_kind = 'employer_unit' AND employer_unit_id = v_employer_id)
        OR (scope_kind = 'tenant'         AND tenant_id = v_tenant_id)
      )
  );
END;
$$;

-- Versao "do usuario logado" · resolve a working_unit do app_user automaticamente
CREATE OR REPLACE FUNCTION module_is_active_for_me(
  p_module_code VARCHAR
)
RETURNS BOOLEAN
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID;
  v_role app_user_role;
  v_wu UUID;
BEGIN
  v_user_id := current_user_id();
  IF v_user_id IS NULL THEN
    RETURN FALSE;
  END IF;

  v_role := current_user_role();
  -- Super admin sempre ve tudo
  IF v_role = 'super_admin' THEN
    RETURN TRUE;
  END IF;

  SELECT working_unit_id INTO v_wu FROM app_users WHERE id = v_user_id;
  RETURN module_is_active(p_module_code, v_wu);
END;
$$;

-- ============================================================================
-- RPCs · CATALOGO (super_admin)
-- ============================================================================

CREATE OR REPLACE FUNCTION rpc_modules_catalog_list()
RETURNS JSONB
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_items JSONB;
BEGIN
  IF current_user_id() IS NULL THEN
    RETURN jsonb_build_object('error', 'not_authenticated');
  END IF;

  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'code', code,
    'display_name', display_name,
    'description', description,
    'icon_name', icon_name,
    'is_core', is_core,
    'display_order', display_order
  ) ORDER BY display_order, code), '[]'::jsonb) INTO v_items
  FROM modules;

  RETURN jsonb_build_object('ok', TRUE, 'items', v_items);
END;
$$;

-- ============================================================================
-- RPCs · ATIVACAO (super_admin)
-- ============================================================================

-- Ativa modulo num escopo (tenant/employer/working)
-- Idempotente: se ja existe, retorna noop.
CREATE OR REPLACE FUNCTION rpc_module_activate(
  p_module_code VARCHAR,
  p_scope_kind module_scope_kind,
  p_tenant_id UUID DEFAULT NULL,
  p_employer_unit_id UUID DEFAULT NULL,
  p_working_unit_id UUID DEFAULT NULL,
  p_notes TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_caller UUID;
  v_id UUID;
  v_already BOOLEAN;
BEGIN
  v_caller := current_user_id();
  IF v_caller IS NULL THEN
    RETURN jsonb_build_object('error', 'not_authenticated');
  END IF;
  IF NOT is_super_admin() THEN
    RETURN jsonb_build_object('error', 'permission_denied');
  END IF;

  -- Verifica modulo existe
  IF NOT EXISTS (SELECT 1 FROM modules WHERE code = p_module_code) THEN
    RETURN jsonb_build_object('error', 'module_not_found');
  END IF;

  -- Valida coerencia scope_kind <-> id fornecido
  IF p_scope_kind = 'tenant' AND p_tenant_id IS NULL THEN
    RETURN jsonb_build_object('error', 'tenant_id_required');
  END IF;
  IF p_scope_kind = 'employer_unit' AND p_employer_unit_id IS NULL THEN
    RETURN jsonb_build_object('error', 'employer_unit_id_required');
  END IF;
  IF p_scope_kind = 'working_unit' AND p_working_unit_id IS NULL THEN
    RETURN jsonb_build_object('error', 'working_unit_id_required');
  END IF;

  -- Valida que o id existe
  IF p_scope_kind = 'tenant' AND NOT EXISTS (SELECT 1 FROM tenants WHERE id = p_tenant_id) THEN
    RETURN jsonb_build_object('error', 'tenant_not_found');
  END IF;
  IF p_scope_kind = 'employer_unit' AND NOT EXISTS (SELECT 1 FROM employer_units WHERE id = p_employer_unit_id) THEN
    RETURN jsonb_build_object('error', 'employer_unit_not_found');
  END IF;
  IF p_scope_kind = 'working_unit' AND NOT EXISTS (SELECT 1 FROM working_units WHERE id = p_working_unit_id) THEN
    RETURN jsonb_build_object('error', 'working_unit_not_found');
  END IF;

  -- Idempotencia: ja existe?
  v_already := EXISTS (
    SELECT 1 FROM module_activations
    WHERE module_code = p_module_code
      AND scope_kind = p_scope_kind
      AND COALESCE(tenant_id, '00000000-0000-0000-0000-000000000000'::UUID) = COALESCE(p_tenant_id, '00000000-0000-0000-0000-000000000000'::UUID)
      AND COALESCE(employer_unit_id, '00000000-0000-0000-0000-000000000000'::UUID) = COALESCE(p_employer_unit_id, '00000000-0000-0000-0000-000000000000'::UUID)
      AND COALESCE(working_unit_id, '00000000-0000-0000-0000-000000000000'::UUID) = COALESCE(p_working_unit_id, '00000000-0000-0000-0000-000000000000'::UUID)
  );
  IF v_already THEN
    RETURN jsonb_build_object('ok', TRUE, 'already_active', TRUE);
  END IF;

  INSERT INTO module_activations (
    module_code, scope_kind, tenant_id, employer_unit_id, working_unit_id, activated_by, notes
  ) VALUES (
    p_module_code, p_scope_kind, p_tenant_id, p_employer_unit_id, p_working_unit_id, v_caller, p_notes
  )
  RETURNING id INTO v_id;

  RETURN jsonb_build_object('ok', TRUE, 'activation_id', v_id);
END;
$$;

-- Desativa modulo num escopo (so remove a row daquele escopo · nao desativa abaixo)
CREATE OR REPLACE FUNCTION rpc_module_deactivate(
  p_module_code VARCHAR,
  p_scope_kind module_scope_kind,
  p_tenant_id UUID DEFAULT NULL,
  p_employer_unit_id UUID DEFAULT NULL,
  p_working_unit_id UUID DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_deleted INT;
BEGIN
  IF current_user_id() IS NULL THEN
    RETURN jsonb_build_object('error', 'not_authenticated');
  END IF;
  IF NOT is_super_admin() THEN
    RETURN jsonb_build_object('error', 'permission_denied');
  END IF;

  -- Modulo core nao pode ser desativado
  IF EXISTS (SELECT 1 FROM modules WHERE code = p_module_code AND is_core = TRUE) THEN
    RETURN jsonb_build_object('error', 'cannot_deactivate_core_module');
  END IF;

  DELETE FROM module_activations
  WHERE module_code = p_module_code
    AND scope_kind = p_scope_kind
    AND COALESCE(tenant_id, '00000000-0000-0000-0000-000000000000'::UUID) = COALESCE(p_tenant_id, '00000000-0000-0000-0000-000000000000'::UUID)
    AND COALESCE(employer_unit_id, '00000000-0000-0000-0000-000000000000'::UUID) = COALESCE(p_employer_unit_id, '00000000-0000-0000-0000-000000000000'::UUID)
    AND COALESCE(working_unit_id, '00000000-0000-0000-0000-000000000000'::UUID) = COALESCE(p_working_unit_id, '00000000-0000-0000-0000-000000000000'::UUID);

  GET DIAGNOSTICS v_deleted = ROW_COUNT;

  IF v_deleted = 0 THEN
    RETURN jsonb_build_object('ok', TRUE, 'noop', TRUE);
  END IF;

  RETURN jsonb_build_object('ok', TRUE, 'deleted', v_deleted);
END;
$$;

-- Lista ativacoes de um tenant inteiro (todas as scopes)
-- Util para dashboard do super_admin ver o estado de uma empresa
CREATE OR REPLACE FUNCTION rpc_module_activations_by_tenant(
  p_tenant_id UUID
)
RETURNS JSONB
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_items JSONB;
BEGIN
  IF current_user_id() IS NULL THEN
    RETURN jsonb_build_object('error', 'not_authenticated');
  END IF;

  -- super_admin ve qualquer tenant; demais so o seu
  IF NOT is_super_admin() THEN
    IF current_tenant_id() <> p_tenant_id THEN
      RETURN jsonb_build_object('error', 'permission_denied');
    END IF;
  END IF;

  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'id', a.id,
    'module_code', a.module_code,
    'module_name', m.display_name,
    'scope_kind', a.scope_kind,
    'tenant_id', a.tenant_id,
    'employer_unit_id', a.employer_unit_id,
    'employer_unit_code', eu.code,
    'employer_unit_name', eu.legal_name,
    'working_unit_id', a.working_unit_id,
    'working_unit_code', wu.code,
    'working_unit_name', wu.display_name,
    'activated_at', a.activated_at,
    'notes', a.notes
  ) ORDER BY a.module_code, a.scope_kind), '[]'::jsonb) INTO v_items
  FROM module_activations a
  JOIN modules m ON m.code = a.module_code
  LEFT JOIN employer_units eu ON eu.id = a.employer_unit_id
  LEFT JOIN working_units wu ON wu.id = a.working_unit_id
  WHERE a.tenant_id = p_tenant_id
     OR a.employer_unit_id IN (SELECT id FROM employer_units WHERE tenant_id = p_tenant_id)
     OR a.working_unit_id IN (SELECT id FROM working_units WHERE tenant_id = p_tenant_id);

  RETURN jsonb_build_object('ok', TRUE, 'items', v_items);
END;
$$;

-- Lista modulos ativos para o usuario logado (resolve heranca)
-- Frontend chama isso para montar o menu/rotear
CREATE OR REPLACE FUNCTION rpc_my_active_modules()
RETURNS JSONB
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID;
  v_role app_user_role;
  v_items JSONB;
BEGIN
  v_user_id := current_user_id();
  IF v_user_id IS NULL THEN
    RETURN jsonb_build_object('error', 'not_authenticated');
  END IF;

  v_role := current_user_role();

  -- Super admin ve todos os modulos
  IF v_role = 'super_admin' THEN
    SELECT COALESCE(jsonb_agg(jsonb_build_object(
      'code', code,
      'display_name', display_name,
      'icon_name', icon_name,
      'is_core', is_core,
      'display_order', display_order,
      'is_active', TRUE
    ) ORDER BY display_order, code), '[]'::jsonb) INTO v_items
    FROM modules;
    RETURN jsonb_build_object('ok', TRUE, 'items', v_items);
  END IF;

  -- Demais: filtra por module_is_active_for_me
  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'code', m.code,
    'display_name', m.display_name,
    'icon_name', m.icon_name,
    'is_core', m.is_core,
    'display_order', m.display_order,
    'is_active', module_is_active_for_me(m.code)
  ) ORDER BY m.display_order, m.code), '[]'::jsonb) INTO v_items
  FROM modules m
  WHERE module_is_active_for_me(m.code) = TRUE;

  RETURN jsonb_build_object('ok', TRUE, 'items', v_items);
END;
$$;

-- Check direto se um modulo X esta ativo para mim (com scope resolvido)
-- Frontend chama em route guards
CREATE OR REPLACE FUNCTION rpc_module_check(p_module_code VARCHAR)
RETURNS JSONB
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF current_user_id() IS NULL THEN
    RETURN jsonb_build_object('error', 'not_authenticated');
  END IF;

  RETURN jsonb_build_object(
    'ok', TRUE,
    'code', p_module_code,
    'is_active', module_is_active_for_me(p_module_code)
  );
END;
$$;

-- ============================================================================
-- ROW-LEVEL SECURITY
-- ============================================================================

ALTER TABLE modules             ENABLE ROW LEVEL SECURITY;
ALTER TABLE module_activations  ENABLE ROW LEVEL SECURITY;

-- Catalogo de modulos: leitura aberta para todos autenticados (precisam saber o que existe)
DROP POLICY IF EXISTS modules_read_all ON modules;
CREATE POLICY modules_read_all ON modules
  FOR SELECT
  USING (current_user_id() IS NOT NULL);

-- Escrita no catalogo: so super_admin
DROP POLICY IF EXISTS modules_write_super_admin ON modules;
CREATE POLICY modules_write_super_admin ON modules
  FOR ALL
  USING (is_super_admin())
  WITH CHECK (is_super_admin());

-- Ativacoes: super_admin le tudo; demais so do seu tenant
DROP POLICY IF EXISTS module_activations_super_admin_read ON module_activations;
CREATE POLICY module_activations_super_admin_read ON module_activations
  FOR SELECT
  USING (is_super_admin());

DROP POLICY IF EXISTS module_activations_tenant_read ON module_activations;
CREATE POLICY module_activations_tenant_read ON module_activations
  FOR SELECT
  USING (
    tenant_id = current_tenant_id()
    OR employer_unit_id IN (SELECT id FROM employer_units WHERE tenant_id = current_tenant_id())
    OR working_unit_id IN (SELECT id FROM working_units WHERE tenant_id = current_tenant_id())
  );

-- Escrita: so super_admin
DROP POLICY IF EXISTS module_activations_write_super_admin ON module_activations;
CREATE POLICY module_activations_write_super_admin ON module_activations
  FOR ALL
  USING (is_super_admin())
  WITH CHECK (is_super_admin());

-- ============================================================================
-- GRANTS
-- ============================================================================

GRANT SELECT, INSERT, UPDATE, DELETE ON modules            TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON module_activations TO authenticated;

GRANT EXECUTE ON FUNCTION is_super_admin                      TO authenticated;
GRANT EXECUTE ON FUNCTION module_is_active                    TO authenticated;
GRANT EXECUTE ON FUNCTION module_is_active_for_me             TO authenticated;
GRANT EXECUTE ON FUNCTION rpc_modules_catalog_list            TO authenticated;
GRANT EXECUTE ON FUNCTION rpc_module_activate                 TO authenticated;
GRANT EXECUTE ON FUNCTION rpc_module_deactivate               TO authenticated;
GRANT EXECUTE ON FUNCTION rpc_module_activations_by_tenant    TO authenticated;
GRANT EXECUTE ON FUNCTION rpc_my_active_modules               TO authenticated;
GRANT EXECUTE ON FUNCTION rpc_module_check                    TO authenticated;

-- ============================================================================
-- COMENTARIOS
-- ============================================================================

COMMENT ON TABLE modules IS 'Catalogo global de modulos da plataforma (gerenciado pela R2)';
COMMENT ON TABLE module_activations IS 'Ativacoes por escopo (tenant/employer/working) com heranca';
COMMENT ON COLUMN modules.is_core IS 'Modulos core nao podem ser desativados (sempre ativos para todos)';
COMMENT ON FUNCTION module_is_active IS 'Resolve heranca: working -> employer -> tenant';
COMMENT ON FUNCTION module_is_active_for_me IS 'Versao do usuario logado (super_admin sempre TRUE)';
COMMENT ON FUNCTION is_super_admin IS 'Role global da R2 (fora dos tenants do cliente)';

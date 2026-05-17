-- ============================================================================
-- R2 People · Patch B2 · Soft-disable de modulos + admin policies
-- ============================================================================
-- Adiciona suporte a desativacao soft (readonly) ao inves de hard delete.
-- Atualiza helpers de ativacao para considerar o estado soft_disabled.
-- Libera escrita em module_activations para diretoria do tenant (alem do super_admin).
--
-- Decisoes da Sessao B2:
--   - Soft-disable preserva o registro em module_activations (mantem historia)
--   - Modulo soft-disabled passa NAO estar ativo (module_is_active_for_me retorna FALSE)
--   - Helper novo module_is_readonly_for_me indica "ativo mas em readonly"
--   - Reativacao volta soft_disabled para FALSE (preserva historico em audit_log)
--   - Policy de escrita liberada para diretoria do tenant (escopo proprio)
--
-- Pre-requisitos:
--   - Schemas H, H2, J, K, L aplicados
--   - Patch A1 aplicado
--   - Schema/seed Ninebox aplicados (A2)
--
-- Idempotente.
-- ============================================================================

-- ============================================================================
-- 1. ALTER TABLE module_activations · adiciona campos de soft-disable
-- ============================================================================

ALTER TABLE module_activations
  ADD COLUMN IF NOT EXISTS soft_disabled       BOOLEAN NOT NULL DEFAULT FALSE,
  ADD COLUMN IF NOT EXISTS disabled_at         TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS disabled_by         UUID REFERENCES app_users(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS disabled_reason     TEXT,
  ADD COLUMN IF NOT EXISTS reactivated_at      TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS reactivated_by      UUID REFERENCES app_users(id) ON DELETE SET NULL;

DO $$ BEGIN
  ALTER TABLE module_activations ADD CONSTRAINT chk_disabled_consistency
    CHECK (
      (soft_disabled = TRUE  AND disabled_at IS NOT NULL) OR
      (soft_disabled = FALSE)
    );
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- Indice util para queries de "ativacoes nao desabilitadas"
CREATE INDEX IF NOT EXISTS idx_module_activations_active
  ON module_activations(module_code, scope_kind)
  WHERE soft_disabled = FALSE;

COMMENT ON COLUMN module_activations.soft_disabled IS 'Sessao B2 · TRUE = readonly · helpers de ativacao retornam FALSE mas dados continuam acessiveis para leitura';
COMMENT ON COLUMN module_activations.disabled_reason IS 'Motivo registrado pelo admin no momento da desativacao';

-- ============================================================================
-- 2. Atualiza helpers de ativacao para considerar soft_disabled
-- ============================================================================

CREATE OR REPLACE FUNCTION module_is_active_for_user(
  p_module_code VARCHAR,
  p_user_id UUID
)
RETURNS BOOLEAN
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user app_users;
BEGIN
  IF p_user_id IS NULL THEN RETURN FALSE; END IF;

  SELECT * INTO v_user FROM app_users WHERE id = p_user_id;
  IF v_user IS NULL THEN RETURN FALSE; END IF;

  -- super_admin sempre passa
  IF v_user.role = 'super_admin' THEN RETURN TRUE; END IF;

  -- Modulos core (is_core=TRUE) sempre ativos para qualquer tenant
  IF EXISTS (SELECT 1 FROM modules WHERE code = p_module_code AND is_core = TRUE) THEN
    RETURN TRUE;
  END IF;

  -- Ativacao por tenant (mais amplo)
  IF EXISTS (
    SELECT 1 FROM module_activations
    WHERE module_code = p_module_code
      AND scope_kind = 'tenant'
      AND tenant_id = v_user.tenant_id
      AND soft_disabled = FALSE
  ) THEN RETURN TRUE; END IF;

  -- Ativacao por employer_unit
  IF v_user.employer_unit_id IS NOT NULL AND EXISTS (
    SELECT 1 FROM module_activations
    WHERE module_code = p_module_code
      AND scope_kind = 'employer_unit'
      AND employer_unit_id = v_user.employer_unit_id
      AND soft_disabled = FALSE
  ) THEN RETURN TRUE; END IF;

  -- Ativacao por working_unit
  IF v_user.working_unit_id IS NOT NULL AND EXISTS (
    SELECT 1 FROM module_activations
    WHERE module_code = p_module_code
      AND scope_kind = 'working_unit'
      AND working_unit_id = v_user.working_unit_id
      AND soft_disabled = FALSE
  ) THEN RETURN TRUE; END IF;

  RETURN FALSE;
END;
$$;

CREATE OR REPLACE FUNCTION module_is_active_for_me(p_module_code VARCHAR)
RETURNS BOOLEAN
LANGUAGE sql
STABLE SECURITY DEFINER
SET search_path = public
AS $$
  SELECT module_is_active_for_user(p_module_code, current_user_id());
$$;

-- ============================================================================
-- 3. Helper novo: module_is_readonly_for_me · TRUE quando o modulo TEVE ativacao
-- mas foi soft-disabled. Permite que UIs de leitura mostrem dados em readonly.
-- ============================================================================

CREATE OR REPLACE FUNCTION module_is_readonly_for_user(
  p_module_code VARCHAR,
  p_user_id UUID
)
RETURNS BOOLEAN
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user app_users;
  v_has_disabled BOOLEAN := FALSE;
  v_has_active BOOLEAN := FALSE;
BEGIN
  IF p_user_id IS NULL THEN RETURN FALSE; END IF;
  SELECT * INTO v_user FROM app_users WHERE id = p_user_id;
  IF v_user IS NULL THEN RETURN FALSE; END IF;

  -- super_admin: nunca em readonly (acessa tudo)
  IF v_user.role = 'super_admin' THEN RETURN FALSE; END IF;

  -- Core nunca fica em readonly
  IF EXISTS (SELECT 1 FROM modules WHERE code = p_module_code AND is_core = TRUE) THEN
    RETURN FALSE;
  END IF;

  -- Verifica se ha alguma ativacao soft_disabled no escopo do user
  -- E nao ha nenhuma ativa para sobrepor
  SELECT EXISTS (
    SELECT 1 FROM module_activations
    WHERE module_code = p_module_code
      AND soft_disabled = TRUE
      AND (
        (scope_kind = 'tenant' AND tenant_id = v_user.tenant_id) OR
        (scope_kind = 'employer_unit' AND employer_unit_id = v_user.employer_unit_id) OR
        (scope_kind = 'working_unit' AND working_unit_id = v_user.working_unit_id)
      )
  ) INTO v_has_disabled;

  IF NOT v_has_disabled THEN RETURN FALSE; END IF;

  -- Tem disabled mas tambem tem alguma active? (escopo concorrente sobrepoe)
  SELECT module_is_active_for_user(p_module_code, p_user_id) INTO v_has_active;
  IF v_has_active THEN RETURN FALSE; END IF;

  RETURN TRUE;
END;
$$;

CREATE OR REPLACE FUNCTION module_is_readonly_for_me(p_module_code VARCHAR)
RETURNS BOOLEAN
LANGUAGE sql
STABLE SECURITY DEFINER
SET search_path = public
AS $$
  SELECT module_is_readonly_for_user(p_module_code, current_user_id());
$$;

COMMENT ON FUNCTION module_is_readonly_for_me IS 'Sessao B2 · TRUE quando ha activation soft_disabled e nenhuma ativa sobrepoe · UI deve mostrar dados em readonly';

-- ============================================================================
-- 4. Atualiza policy de escrita em module_activations
-- super_admin (qualquer escopo) ou diretoria do tenant (apenas seu escopo)
-- ============================================================================

DROP POLICY IF EXISTS module_activations_write_super_admin ON module_activations;
DROP POLICY IF EXISTS module_activations_write_admin       ON module_activations;

CREATE POLICY module_activations_write_admin ON module_activations
  FOR ALL
  USING (
    is_super_admin()
    OR (
      EXISTS (
        SELECT 1 FROM app_users u
        WHERE u.id = current_user_id() AND u.role = 'diretoria'
          AND (
            (scope_kind = 'tenant' AND tenant_id = u.tenant_id) OR
            (scope_kind = 'employer_unit' AND employer_unit_id IN (
              SELECT id FROM employer_units WHERE tenant_id = u.tenant_id))
            OR (scope_kind = 'working_unit' AND working_unit_id IN (
              SELECT id FROM working_units WHERE tenant_id = u.tenant_id))
          )
      )
    )
  )
  WITH CHECK (
    is_super_admin()
    OR (
      EXISTS (
        SELECT 1 FROM app_users u
        WHERE u.id = current_user_id() AND u.role = 'diretoria'
          AND (
            (scope_kind = 'tenant' AND tenant_id = u.tenant_id) OR
            (scope_kind = 'employer_unit' AND employer_unit_id IN (
              SELECT id FROM employer_units WHERE tenant_id = u.tenant_id))
            OR (scope_kind = 'working_unit' AND working_unit_id IN (
              SELECT id FROM working_units WHERE tenant_id = u.tenant_id))
          )
      )
    )
  );

COMMENT ON POLICY module_activations_write_admin ON module_activations IS
  'Sessao B2 · super_admin escreve em qualquer escopo · diretoria escreve apenas no proprio tenant';

-- ============================================================================
-- 5. Trigger ninebox_on_activation deve respeitar soft_disabled
-- (ja respeita pois so dispara em INSERT, mas garante seed apenas se NEW.soft_disabled=FALSE)
-- ============================================================================

CREATE OR REPLACE FUNCTION ninebox_on_activation()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
  v_tenant UUID;
BEGIN
  IF NEW.module_code <> 'ninebox' THEN
    RETURN NEW;
  END IF;

  -- Sessao B2: nao popular defaults se a ativacao ja nasce soft_disabled
  IF NEW.soft_disabled = TRUE THEN
    RETURN NEW;
  END IF;

  v_tenant := COALESCE(
    NEW.tenant_id,
    (SELECT tenant_id FROM employer_units WHERE id = NEW.employer_unit_id),
    (SELECT tenant_id FROM working_units WHERE id = NEW.working_unit_id)
  );

  IF v_tenant IS NOT NULL THEN
    PERFORM ninebox_seed_defaults_for_tenant(v_tenant);
  END IF;

  RETURN NEW;
END;
$$;

-- ============================================================================
-- 6. Grants
-- ============================================================================

GRANT EXECUTE ON FUNCTION
  module_is_active_for_user,
  module_is_active_for_me,
  module_is_readonly_for_user,
  module_is_readonly_for_me
TO authenticated;

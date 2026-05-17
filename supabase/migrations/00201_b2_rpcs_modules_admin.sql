-- ============================================================================
-- R2 People · RPCs Sessao B2 · Admin de Modulos
-- ============================================================================
-- 5 RPCs para a pagina /admin/modulos:
--   - rpc_admin_modules_overview          · lista modulos com estado por escopo
--   - rpc_admin_module_activate           · ativa em um escopo
--   - rpc_admin_module_deactivate         · soft-disable em um escopo
--   - rpc_admin_module_reactivate         · re-ativa um soft-disabled
--   - rpc_admin_module_impact_summary     · counts de dados afetados (preview)
--
-- Quem acessa: super_admin (qualquer escopo) ou diretoria (proprio tenant).
--
-- Pre-requisitos:
--   - Patch B2 aplicado (r2_people_patch_b2_modules_admin.sql)
--
-- Idempotente.
-- ============================================================================

-- ============================================================================
-- HELPER · valida se o caller pode admin no escopo informado
-- Retorna texto de erro ou NULL se permitido
-- ============================================================================

CREATE OR REPLACE FUNCTION admin_modules_check_scope_access(
  p_scope_kind module_scope_kind,
  p_scope_id UUID
)
RETURNS TEXT
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user app_users;
  v_target_tenant UUID;
BEGIN
  SELECT * INTO v_user FROM app_users WHERE id = current_user_id();
  IF v_user IS NULL THEN RETURN 'not_authenticated'; END IF;

  -- super_admin sempre passa
  IF v_user.role = 'super_admin' THEN RETURN NULL; END IF;

  -- Apenas diretoria alem do super_admin
  IF v_user.role <> 'diretoria' THEN RETURN 'permission_denied'; END IF;

  -- diretoria so admin no proprio tenant
  v_target_tenant := CASE p_scope_kind
    WHEN 'tenant'        THEN p_scope_id
    WHEN 'employer_unit' THEN (SELECT tenant_id FROM employer_units WHERE id = p_scope_id)
    WHEN 'working_unit'  THEN (SELECT tenant_id FROM working_units  WHERE id = p_scope_id)
  END;

  IF v_target_tenant IS NULL THEN RETURN 'scope_not_found'; END IF;
  IF v_target_tenant <> v_user.tenant_id THEN RETURN 'scope_outside_tenant'; END IF;

  RETURN NULL;
END;
$$;

-- ============================================================================
-- rpc_admin_modules_overview · lista modulos com estado por escopo
-- 
-- Retorno:
-- {
--   ok: true,
--   modules: [
--     {
--       code, display_name, description, icon_name, is_core, display_order,
--       activations_count: int,
--       activations_disabled_count: int,
--       super_admin_view: { tenants_active: int, tenants_total: int, ... }   // so super_admin
--       my_tenant_view: {                                                     // diretoria
--         tenant_active: bool,
--         tenant_disabled: bool,
--         employer_units: [{ id, name, active, disabled }],
--         working_units: [{ id, name, active, disabled }]
--       }
--     }, ...
--   ]
-- }
-- ============================================================================

CREATE OR REPLACE FUNCTION rpc_admin_modules_overview()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user app_users;
  v_modules JSONB;
BEGIN
  SELECT * INTO v_user FROM app_users WHERE id = current_user_id();
  IF v_user IS NULL THEN
    RETURN jsonb_build_object('error', 'not_authenticated');
  END IF;

  IF v_user.role NOT IN ('super_admin', 'diretoria') THEN
    RETURN jsonb_build_object('error', 'permission_denied');
  END IF;

  IF v_user.role = 'super_admin' THEN
    -- VISAO SUPER_ADMIN · agregados globais
    SELECT COALESCE(jsonb_agg(jsonb_build_object(
      'code', m.code,
      'display_name', m.display_name,
      'description', m.description,
      'icon_name', m.icon_name,
      'is_core', m.is_core,
      'display_order', m.display_order,
      'global_view', jsonb_build_object(
        'tenants_total',           (SELECT count(*) FROM tenants),
        'tenants_active',          (SELECT count(DISTINCT tenant_id) FROM module_activations
                                    WHERE module_code = m.code AND scope_kind = 'tenant' AND soft_disabled = FALSE),
        'tenants_disabled',        (SELECT count(DISTINCT tenant_id) FROM module_activations
                                    WHERE module_code = m.code AND scope_kind = 'tenant' AND soft_disabled = TRUE),
        'employer_units_active',   (SELECT count(*) FROM module_activations
                                    WHERE module_code = m.code AND scope_kind = 'employer_unit' AND soft_disabled = FALSE),
        'working_units_active',    (SELECT count(*) FROM module_activations
                                    WHERE module_code = m.code AND scope_kind = 'working_unit' AND soft_disabled = FALSE),
        'activations_total',       (SELECT count(*) FROM module_activations
                                    WHERE module_code = m.code AND soft_disabled = FALSE)
      )
    ) ORDER BY m.display_order), '[]'::JSONB)
    INTO v_modules
    FROM modules m
    WHERE TRUE;
  ELSE
    -- VISAO DIRETORIA · estado no proprio tenant
    SELECT COALESCE(jsonb_agg(jsonb_build_object(
      'code', m.code,
      'display_name', m.display_name,
      'description', m.description,
      'icon_name', m.icon_name,
      'is_core', m.is_core,
      'display_order', m.display_order,
      'tenant_view', jsonb_build_object(
        'tenant_active', EXISTS (
          SELECT 1 FROM module_activations
          WHERE module_code = m.code AND scope_kind = 'tenant'
            AND tenant_id = v_user.tenant_id AND soft_disabled = FALSE
        ),
        'tenant_disabled', EXISTS (
          SELECT 1 FROM module_activations
          WHERE module_code = m.code AND scope_kind = 'tenant'
            AND tenant_id = v_user.tenant_id AND soft_disabled = TRUE
        ),
        'employer_units', (
          SELECT COALESCE(jsonb_agg(jsonb_build_object(
            'id', eu.id,
            'name', eu.legal_name,
            'code', eu.code,
            'active', EXISTS (
              SELECT 1 FROM module_activations a
              WHERE a.module_code = m.code AND a.scope_kind = 'employer_unit'
                AND a.employer_unit_id = eu.id AND a.soft_disabled = FALSE
            ),
            'disabled', EXISTS (
              SELECT 1 FROM module_activations a
              WHERE a.module_code = m.code AND a.scope_kind = 'employer_unit'
                AND a.employer_unit_id = eu.id AND a.soft_disabled = TRUE
            )
          ) ORDER BY eu.code), '[]'::JSONB)
          FROM employer_units eu WHERE eu.tenant_id = v_user.tenant_id
        ),
        'working_units', (
          SELECT COALESCE(jsonb_agg(jsonb_build_object(
            'id', wu.id,
            'name', wu.display_name,
            'code', wu.code,
            'employer_unit_id', wu.employer_unit_id,
            'active', EXISTS (
              SELECT 1 FROM module_activations a
              WHERE a.module_code = m.code AND a.scope_kind = 'working_unit'
                AND a.working_unit_id = wu.id AND a.soft_disabled = FALSE
            ),
            'disabled', EXISTS (
              SELECT 1 FROM module_activations a
              WHERE a.module_code = m.code AND a.scope_kind = 'working_unit'
                AND a.working_unit_id = wu.id AND a.soft_disabled = TRUE
            )
          ) ORDER BY wu.code), '[]'::JSONB)
          FROM working_units wu WHERE wu.tenant_id = v_user.tenant_id
        )
      )
    ) ORDER BY m.display_order), '[]'::JSONB)
    INTO v_modules
    FROM modules m
    WHERE TRUE;
  END IF;

  RETURN jsonb_build_object('ok', TRUE, 'modules', v_modules, 'role', v_user.role);
END;
$$;

-- ============================================================================
-- rpc_admin_module_activate · ativa o modulo em um escopo
-- Se ja existir uma ativacao no mesmo escopo (mesmo soft_disabled), reativa
-- ============================================================================

CREATE OR REPLACE FUNCTION rpc_admin_module_activate(
  p_module_code VARCHAR,
  p_scope_kind module_scope_kind,
  p_scope_id UUID
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user UUID := current_user_id();
  v_err TEXT;
  v_existing module_activations;
  v_act_id UUID;
BEGIN
  IF v_user IS NULL THEN
    RETURN jsonb_build_object('error', 'not_authenticated');
  END IF;

  v_err := admin_modules_check_scope_access(p_scope_kind, p_scope_id);
  IF v_err IS NOT NULL THEN
    RETURN jsonb_build_object('error', v_err);
  END IF;

  IF NOT EXISTS (SELECT 1 FROM modules WHERE code = p_module_code) THEN
    RETURN jsonb_build_object('error', 'module_not_found_or_inactive');
  END IF;

  -- Procura ativacao existente no escopo (ativa ou desativada)
  SELECT * INTO v_existing FROM module_activations
  WHERE module_code = p_module_code
    AND scope_kind = p_scope_kind
    AND (
      (p_scope_kind = 'tenant' AND tenant_id = p_scope_id) OR
      (p_scope_kind = 'employer_unit' AND employer_unit_id = p_scope_id) OR
      (p_scope_kind = 'working_unit' AND working_unit_id = p_scope_id)
    );

  IF v_existing.id IS NOT NULL THEN
    IF v_existing.soft_disabled = FALSE THEN
      RETURN jsonb_build_object('ok', TRUE, 'activation_id', v_existing.id, 'already_active', TRUE);
    ELSE
      -- Reativa via update (preserva historico via audit_log automatico)
      UPDATE module_activations SET
        soft_disabled = FALSE,
        reactivated_at = now(),
        reactivated_by = v_user,
        disabled_at = NULL,
        disabled_by = NULL,
        disabled_reason = NULL
      WHERE id = v_existing.id;
      RETURN jsonb_build_object('ok', TRUE, 'activation_id', v_existing.id, 'reactivated', TRUE);
    END IF;
  END IF;

  -- Cria ativacao nova
  INSERT INTO module_activations (
    module_code, scope_kind,
    tenant_id, employer_unit_id, working_unit_id,
    activated_by
  ) VALUES (
    p_module_code, p_scope_kind,
    CASE WHEN p_scope_kind = 'tenant'        THEN p_scope_id END,
    CASE WHEN p_scope_kind = 'employer_unit' THEN p_scope_id END,
    CASE WHEN p_scope_kind = 'working_unit'  THEN p_scope_id END,
    v_user
  ) RETURNING id INTO v_act_id;

  RETURN jsonb_build_object('ok', TRUE, 'activation_id', v_act_id, 'created', TRUE);
END;
$$;

-- ============================================================================
-- rpc_admin_module_deactivate · soft-disable do modulo no escopo
-- ============================================================================

CREATE OR REPLACE FUNCTION rpc_admin_module_deactivate(
  p_module_code VARCHAR,
  p_scope_kind module_scope_kind,
  p_scope_id UUID,
  p_reason TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user UUID := current_user_id();
  v_err TEXT;
  v_existing module_activations;
BEGIN
  IF v_user IS NULL THEN
    RETURN jsonb_build_object('error', 'not_authenticated');
  END IF;

  v_err := admin_modules_check_scope_access(p_scope_kind, p_scope_id);
  IF v_err IS NOT NULL THEN
    RETURN jsonb_build_object('error', v_err);
  END IF;

  -- Modulos core nao podem ser desativados
  IF EXISTS (SELECT 1 FROM modules WHERE code = p_module_code AND is_core = TRUE) THEN
    RETURN jsonb_build_object('error', 'cannot_disable_core_module');
  END IF;

  SELECT * INTO v_existing FROM module_activations
  WHERE module_code = p_module_code
    AND scope_kind = p_scope_kind
    AND (
      (p_scope_kind = 'tenant' AND tenant_id = p_scope_id) OR
      (p_scope_kind = 'employer_unit' AND employer_unit_id = p_scope_id) OR
      (p_scope_kind = 'working_unit' AND working_unit_id = p_scope_id)
    );

  IF v_existing.id IS NULL THEN
    RETURN jsonb_build_object('error', 'activation_not_found');
  END IF;

  IF v_existing.soft_disabled = TRUE THEN
    RETURN jsonb_build_object('ok', TRUE, 'activation_id', v_existing.id, 'already_disabled', TRUE);
  END IF;

  UPDATE module_activations SET
    soft_disabled = TRUE,
    disabled_at = now(),
    disabled_by = v_user,
    disabled_reason = p_reason
  WHERE id = v_existing.id;

  RETURN jsonb_build_object('ok', TRUE, 'activation_id', v_existing.id, 'disabled', TRUE);
END;
$$;

-- ============================================================================
-- rpc_admin_module_reactivate · alias semantico de activate (existing soft_disabled)
-- ============================================================================

CREATE OR REPLACE FUNCTION rpc_admin_module_reactivate(
  p_module_code VARCHAR,
  p_scope_kind module_scope_kind,
  p_scope_id UUID
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN rpc_admin_module_activate(p_module_code, p_scope_kind, p_scope_id);
END;
$$;

-- ============================================================================
-- rpc_admin_module_impact_summary · preview de dados afetados ANTES de desativar
-- Retorna counts especificos por modulo (varia conforme o modulo)
-- ============================================================================

CREATE OR REPLACE FUNCTION rpc_admin_module_impact_summary(
  p_module_code VARCHAR,
  p_scope_kind module_scope_kind,
  p_scope_id UUID
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_err TEXT;
  v_user app_users;
  v_target_tenant UUID;
  v_impact JSONB := '[]'::JSONB;
  v_count INT;
BEGIN
  SELECT * INTO v_user FROM app_users WHERE id = current_user_id();
  IF v_user IS NULL THEN
    RETURN jsonb_build_object('error', 'not_authenticated');
  END IF;

  v_err := admin_modules_check_scope_access(p_scope_kind, p_scope_id);
  IF v_err IS NOT NULL THEN
    RETURN jsonb_build_object('error', v_err);
  END IF;

  -- Resolve tenant alvo
  v_target_tenant := CASE p_scope_kind
    WHEN 'tenant'        THEN p_scope_id
    WHEN 'employer_unit' THEN (SELECT tenant_id FROM employer_units WHERE id = p_scope_id)
    WHEN 'working_unit'  THEN (SELECT tenant_id FROM working_units  WHERE id = p_scope_id)
  END;

  -- Counts por modulo
  IF p_module_code = 'ninebox' THEN
    SELECT count(*) INTO v_count FROM ninebox_evaluations
      WHERE tenant_id = v_target_tenant AND status NOT IN ('finalized','canceled');
    v_impact := v_impact || jsonb_build_array(jsonb_build_object(
      'kind', 'ninebox_open_evaluations',
      'label', 'Avaliacoes 9-Box em andamento (nao finalizadas)',
      'count', v_count
    ));

    SELECT count(*) INTO v_count FROM ninebox_cycles
      WHERE tenant_id = v_target_tenant AND status IN ('planning','active');
    v_impact := v_impact || jsonb_build_array(jsonb_build_object(
      'kind', 'ninebox_active_cycles',
      'label', 'Ciclos 9-Box abertos (planning ou active)',
      'count', v_count
    ));

    SELECT count(*) INTO v_count FROM ninebox_evaluation_snapshots s
      JOIN ninebox_evaluations e ON e.id = s.evaluation_id
      WHERE e.tenant_id = v_target_tenant;
    v_impact := v_impact || jsonb_build_array(jsonb_build_object(
      'kind', 'ninebox_snapshots',
      'label', 'Snapshots historicos (preservados em readonly)',
      'count', v_count
    ));

  ELSIF p_module_code = 'recognition' THEN
    SELECT count(*) INTO v_count FROM recognitions
      WHERE tenant_id = v_target_tenant AND hidden_at IS NULL;
    v_impact := v_impact || jsonb_build_array(jsonb_build_object(
      'kind', 'recognition_visible_posts',
      'label', 'Reconhecimentos visiveis no feed',
      'count', v_count
    ));

  ELSIF p_module_code = 'pdi' THEN
    -- Schema PDI tem pdi_plans · ajusto se nome diferir
    BEGIN
      EXECUTE 'SELECT count(*) FROM pdi_plans WHERE tenant_id = $1 AND status IN (''draft'',''active'')'
        INTO v_count USING v_target_tenant;
      v_impact := v_impact || jsonb_build_array(jsonb_build_object(
        'kind', 'pdi_active_plans',
        'label', 'Planos PDI em andamento',
        'count', v_count
      ));
    EXCEPTION WHEN OTHERS THEN
      v_impact := v_impact || jsonb_build_array(jsonb_build_object(
        'kind', 'pdi_active_plans', 'label', 'Planos PDI em andamento',
        'count', 0, 'note', 'tabela pdi_plans nao detectada'
      ));
    END;

  ELSIF p_module_code = 'onboarding' THEN
    BEGIN
      EXECUTE 'SELECT count(*) FROM onboarding_journeys WHERE tenant_id = $1 AND status NOT IN (''completed'',''canceled'')'
        INTO v_count USING v_target_tenant;
      v_impact := v_impact || jsonb_build_array(jsonb_build_object(
        'kind', 'onboarding_active_journeys',
        'label', 'Jornadas de onboarding ativas',
        'count', v_count
      ));
    EXCEPTION WHEN OTHERS THEN
      v_impact := v_impact || jsonb_build_array(jsonb_build_object(
        'kind', 'onboarding_active_journeys', 'label', 'Jornadas de onboarding ativas',
        'count', 0, 'note', 'tabela onboarding_journeys nao detectada'
      ));
    END;

  ELSIF p_module_code = 'climate' THEN
    BEGIN
      EXECUTE 'SELECT count(*) FROM climate_surveys WHERE tenant_id = $1 AND status IN (''draft'',''open'')'
        INTO v_count USING v_target_tenant;
      v_impact := v_impact || jsonb_build_array(jsonb_build_object(
        'kind', 'climate_open_surveys',
        'label', 'Pesquisas de clima abertas',
        'count', v_count
      ));
    EXCEPTION WHEN OTHERS THEN
      v_impact := v_impact || jsonb_build_array(jsonb_build_object(
        'kind', 'climate_open_surveys', 'label', 'Pesquisas de clima abertas',
        'count', 0, 'note', 'tabela climate_surveys nao detectada'
      ));
    END;
  END IF;

  -- Quantidade de usuarios no escopo (afetados perdem acesso de escrita)
  IF p_scope_kind = 'tenant' THEN
    SELECT count(*) INTO v_count FROM app_users WHERE tenant_id = p_scope_id AND active = TRUE;
  ELSIF p_scope_kind = 'employer_unit' THEN
    SELECT count(*) INTO v_count FROM app_users WHERE employer_unit_id = p_scope_id AND active = TRUE;
  ELSE
    SELECT count(*) INTO v_count FROM app_users WHERE working_unit_id = p_scope_id AND active = TRUE;
  END IF;

  v_impact := v_impact || jsonb_build_array(jsonb_build_object(
    'kind', 'users_affected',
    'label', 'Usuarios ativos no escopo',
    'count', v_count
  ));

  RETURN jsonb_build_object(
    'ok', TRUE,
    'module', p_module_code,
    'scope_kind', p_scope_kind,
    'scope_id', p_scope_id,
    'tenant_id', v_target_tenant,
    'impact', v_impact
  );
END;
$$;

-- ============================================================================
-- GRANTS
-- ============================================================================

GRANT EXECUTE ON FUNCTION
  rpc_admin_modules_overview,
  rpc_admin_module_activate,
  rpc_admin_module_deactivate,
  rpc_admin_module_reactivate,
  rpc_admin_module_impact_summary,
  admin_modules_check_scope_access
TO authenticated;

COMMENT ON FUNCTION rpc_admin_modules_overview IS 'Sessao B2 · lista modulos com estado por escopo · super_admin ve agregados, diretoria ve proprio tenant';
COMMENT ON FUNCTION rpc_admin_module_activate IS 'Sessao B2 · ativa modulo em escopo · idempotente · re-ativa se soft_disabled';
COMMENT ON FUNCTION rpc_admin_module_deactivate IS 'Sessao B2 · soft-disable · preserva historico · core nao pode ser desativado';
COMMENT ON FUNCTION rpc_admin_module_impact_summary IS 'Sessao B2 · preview de dados afetados antes de desativar';

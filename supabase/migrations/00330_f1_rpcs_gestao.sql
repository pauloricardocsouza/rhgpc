-- ============================================================================
-- R2 People · Sessao F1 · RPCs de gestao por pessoa
-- ============================================================================
-- 2 RPCs:
--   rpc_employees_gestao_summary(employee_id)
--     · retorna historico 9-Box, PDIs, reconhecimentos, onboarding
--     · permissao: super_admin, diretoria, rh OU gestor direto da pessoa
--
--   rpc_my_team(include_indirect)
--     · retorna pessoas que reportam ao usuario logado
--     · include_indirect = true · inclui subordinados de subordinados
--     · retorno enriquecido com KPIs simples (ultima avaliacao, PDIs ativos)
--
-- Padrao de erro:
--   { error: 'snake_case_code' }
--   employee_no_user_account · ficha sem app_user vinculado
--   employee_not_found       · ficha inexistente ou em outro tenant
--   permission_denied        · usuario nao tem direito de ver gestao
-- ============================================================================

-- ----------------------------------------------------------------------------
-- HELPER · resolve quem pode ver a gestao de uma pessoa
-- ----------------------------------------------------------------------------
-- Aceita employee_id ou app_user_id.
-- Permite:
--   - super_admin
--   - diretoria
--   - rh
--   - gestor direto (app_users.manager_id = current_user_id)
-- ----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION can_view_gestao_for_app_user(p_target_app_user_id UUID)
RETURNS BOOLEAN
LANGUAGE sql
STABLE SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM app_users me, app_users target
    WHERE me.id = current_user_id()
      AND target.id = p_target_app_user_id
      AND me.tenant_id = target.tenant_id
      AND (
        is_super_admin()
        OR me.role IN ('diretoria', 'rh')
        OR target.manager_id = me.id
      )
  );
$$;

GRANT EXECUTE ON FUNCTION can_view_gestao_for_app_user TO authenticated;

-- ----------------------------------------------------------------------------
-- rpc_employees_gestao_summary
-- ----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION rpc_employees_gestao_summary(p_employee_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user app_users;
  v_employee employees;
  v_target_app_user app_users;
  v_evaluations JSONB;
  v_pdis JSONB;
  v_recognitions JSONB;
  v_onboardings JSONB;
BEGIN
  SELECT * INTO v_user FROM app_users WHERE id = current_user_id();
  IF v_user IS NULL THEN RETURN jsonb_build_object('error', 'not_authenticated'); END IF;

  -- 1. Encontra a ficha e o usuario vinculado
  SELECT * INTO v_employee
  FROM employees
  WHERE id = p_employee_id
    AND archived_at IS NULL
    AND (is_super_admin() OR tenant_id = v_user.tenant_id);

  IF v_employee IS NULL THEN
    RETURN jsonb_build_object('error', 'employee_not_found');
  END IF;

  SELECT * INTO v_target_app_user
  FROM app_users
  WHERE employee_id = p_employee_id
    AND tenant_id = v_employee.tenant_id
  LIMIT 1;

  IF v_target_app_user IS NULL THEN
    -- Ficha sem usuario vinculado · retorna estrutura vazia (mas sucesso)
    RETURN jsonb_build_object(
      'ok', TRUE,
      'has_app_user', FALSE,
      'evaluations', '[]'::JSONB,
      'pdis', '[]'::JSONB,
      'recognitions', '[]'::JSONB,
      'onboardings', '[]'::JSONB
    );
  END IF;

  -- 2. Permissao
  IF NOT can_view_gestao_for_app_user(v_target_app_user.id) THEN
    RETURN jsonb_build_object('error', 'permission_denied');
  END IF;

  -- 3. Historico 9-Box (avaliacoes finalizadas)
  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'id', e.id,
    'cycle_id', e.cycle_id,
    'cycle_name', c.name,
    'status', e.status,
    'is_adhoc', e.is_adhoc,
    'final_box_label', e.final_box_label,
    'final_box_row', e.final_box_row,
    'final_box_col', e.final_box_col,
    'final_potential_score', e.final_potential_score,
    'final_performance_score', e.final_performance_score,
    'manager_name', m.full_name,
    'finalized_at', e.finalized_at,
    'created_at', e.created_at
  ) ORDER BY e.created_at DESC), '[]'::JSONB)
  INTO v_evaluations
  FROM ninebox_evaluations e
    LEFT JOIN ninebox_cycles c ON c.id = e.cycle_id
    LEFT JOIN app_users m ON m.id = e.manager_id
  WHERE e.subject_id = v_target_app_user.id
    AND e.canceled_at IS NULL;

  -- 4. PDIs (todos, ordenados do mais recente)
  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'id', p.id,
    'cycle_id', p.cycle_id,
    'cycle_name', c.display_name,
    'objective', p.objective,
    'status', p.status,
    'start_date', p.start_date,
    'end_date', p.end_date,
    'actions_total', p.actions_total,
    'actions_completed', p.actions_completed,
    'manager_name', m.full_name,
    'activated_at', p.activated_at,
    'completed_at', p.completed_at,
    'created_at', p.created_at
  ) ORDER BY p.created_at DESC), '[]'::JSONB)
  INTO v_pdis
  FROM pdis p
    LEFT JOIN pdi_cycles c ON c.id = p.cycle_id
    LEFT JOIN app_users m ON m.id = p.manager_id_snapshot
  WHERE p.user_id = v_target_app_user.id;

  -- 5. Reconhecimentos recebidos (publicos + privados onde o usuario consultor
  --    seja sender ou recipient · diretoria/rh/gestor veem tudo nao oculto)
  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'id', r.id,
    'message', r.message,
    'is_private', r.is_private,
    'sender_id', r.sender_id,
    'sender_name', s.full_name,
    'reactions_count', r.reactions_count,
    'created_at', r.created_at
  ) ORDER BY r.created_at DESC), '[]'::JSONB)
  INTO v_recognitions
  FROM recognitions r
    LEFT JOIN app_users s ON s.id = r.sender_id
  WHERE r.recipient_id = v_target_app_user.id
    AND r.hidden_at IS NULL
    AND (
      NOT r.is_private
      OR is_super_admin()
      OR v_user.role IN ('diretoria', 'rh')
      OR r.sender_id = v_user.id
      OR r.recipient_id = v_user.id
    );

  -- 6. Onboardings
  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'id', o.id,
    'display_name', o.display_name,
    'status', o.status,
    'start_date', o.start_date,
    'target_end_date', o.target_end_date,
    'tasks_total', o.tasks_total,
    'tasks_completed', o.tasks_completed,
    'tasks_required', o.tasks_required,
    'tasks_required_done', o.tasks_required_done,
    'started_at', o.started_at,
    'completed_at', o.completed_at,
    'created_at', o.created_at
  ) ORDER BY o.created_at DESC), '[]'::JSONB)
  INTO v_onboardings
  FROM onboardings o
  WHERE o.user_id = v_target_app_user.id
    AND o.canceled_at IS NULL;

  RETURN jsonb_build_object(
    'ok', TRUE,
    'has_app_user', TRUE,
    'app_user_id', v_target_app_user.id,
    'app_user_role', v_target_app_user.role,
    'evaluations', v_evaluations,
    'pdis', v_pdis,
    'recognitions', v_recognitions,
    'onboardings', v_onboardings
  );
END;
$$;

-- ----------------------------------------------------------------------------
-- rpc_my_team · lista de subordinados do usuario logado
-- ----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION rpc_my_team(p_include_indirect BOOLEAN DEFAULT FALSE)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user app_users;
  v_team JSONB;
BEGIN
  SELECT * INTO v_user FROM app_users WHERE id = current_user_id();
  IF v_user IS NULL THEN RETURN jsonb_build_object('error', 'not_authenticated'); END IF;

  -- CTE recursiva para subordinados diretos e (opcionalmente) indiretos
  WITH RECURSIVE subordinates AS (
    -- Base · diretos
    SELECT u.id, u.full_name, u.email, u.role, u.tenant_id, u.manager_id,
           u.employer_unit_id, u.working_unit_id, u.department_id,
           u.employee_id, 1 AS depth
    FROM app_users u
    WHERE u.manager_id = v_user.id
      AND u.tenant_id = v_user.tenant_id

    UNION ALL

    -- Recursivo · subordinados dos subordinados
    SELECT u.id, u.full_name, u.email, u.role, u.tenant_id, u.manager_id,
           u.employer_unit_id, u.working_unit_id, u.department_id,
           u.employee_id, s.depth + 1
    FROM app_users u
      JOIN subordinates s ON u.manager_id = s.id
    WHERE p_include_indirect
      AND s.depth < 10  -- protege contra ciclos
      AND u.tenant_id = v_user.tenant_id
  )
  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'id', s.id,
    'employee_id', s.employee_id,
    'full_name', e.full_name,           -- nome da ficha (mais detalhado)
    'app_user_name', s.full_name,
    'email', s.email,
    'role', s.role,
    'job_title', e.job_title,
    'employer_unit_name', eu.legal_name,
    'working_unit_name', wu.display_name,
    'depth', s.depth,
    'is_direct_report', s.depth = 1,
    'is_active', e.id IS NOT NULL AND e.termination_date IS NULL,
    -- KPIs leves · contadores rapidos
    'pdis_active', (
      SELECT count(*) FROM pdis p
      WHERE p.user_id = s.id AND p.status = 'active'
    ),
    'last_evaluation_box', (
      SELECT final_box_label FROM ninebox_evaluations ev
      WHERE ev.subject_id = s.id
        AND ev.status = 'finalized'
        AND ev.canceled_at IS NULL
      ORDER BY ev.finalized_at DESC LIMIT 1
    ),
    'recognitions_30d', (
      SELECT count(*) FROM recognitions r
      WHERE r.recipient_id = s.id
        AND r.hidden_at IS NULL
        AND r.created_at > now() - INTERVAL '30 days'
    ),
    'onboarding_active', EXISTS (
      SELECT 1 FROM onboardings o
      WHERE o.user_id = s.id
        AND o.status IN ('not_started', 'in_progress')
        AND o.canceled_at IS NULL
    )
  ) ORDER BY s.depth, e.full_name NULLS LAST, s.full_name), '[]'::JSONB)
  INTO v_team
  FROM subordinates s
    LEFT JOIN employees e ON e.id = s.employee_id AND e.archived_at IS NULL
    LEFT JOIN employer_units eu ON eu.id = s.employer_unit_id
    LEFT JOIN working_units wu ON wu.id = s.working_unit_id;

  RETURN jsonb_build_object(
    'ok', TRUE,
    'team', v_team,
    'include_indirect', p_include_indirect
  );
END;
$$;

-- ----------------------------------------------------------------------------
-- GRANTS
-- ----------------------------------------------------------------------------

GRANT EXECUTE ON FUNCTION rpc_employees_gestao_summary, rpc_my_team TO authenticated;

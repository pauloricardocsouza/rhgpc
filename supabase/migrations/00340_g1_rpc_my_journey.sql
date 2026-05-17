-- ============================================================================
-- R2 People · Sessao G1 · Minha Jornada
-- ============================================================================
-- 1. Atualiza can_view_gestao_for_app_user para incluir self-access · permite
--    que o proprio usuario veja seus PDIs/reconhecimentos/onboardings pela
--    mesma RPC ja usada pela tela /pessoas/[id] (rpc_employees_gestao_summary)
-- 2. rpc_my_journey() - snapshot agregado de identidade + KPIs
--
-- Decisao G1: combinar RPCs · rpc_my_journey traz dados agregados novos,
-- listas detalhadas reusam RPCs existentes da F1 (gestaoSummary) com self.
-- ============================================================================

-- ============================================================================
-- Patch da F1 · permitir self-access em can_view_gestao_for_app_user
-- ============================================================================
CREATE OR REPLACE FUNCTION public.can_view_gestao_for_app_user(p_target_app_user_id uuid)
RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $function$
  SELECT EXISTS (
    SELECT 1 FROM app_users me, app_users target
    WHERE me.id = current_user_id()
      AND target.id = p_target_app_user_id
      AND me.tenant_id = target.tenant_id
      AND (
        is_super_admin()
        OR me.role IN ('diretoria', 'rh')
        OR target.manager_id = me.id
        OR me.id = target.id   -- G1: permite que o proprio veja seus dados
      )
  );
$function$;

-- ============================================================================
-- rpc_my_journey() - snapshot agregado para /minha-jornada
-- ============================================================================

CREATE OR REPLACE FUNCTION rpc_my_journey()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user app_users;
  v_employee employees;
  v_employer_unit_id UUID;
  v_employer_unit_trade TEXT;
  v_employer_unit_legal TEXT;
  v_employer_unit_city TEXT;
  v_employer_unit_state TEXT;
  v_department_id UUID;
  v_department_name TEXT;
  v_working_unit_id UUID;
  v_working_unit_name TEXT;
  v_working_unit_city TEXT;
  v_working_unit_state TEXT;
  v_manager_id UUID;
  v_manager_email TEXT;
  v_manager_name TEXT;
  v_pdi_kpis JSONB;
  v_recog_kpis JSONB;
  v_last_ninebox JSONB;
  v_onboarding_kpis JSONB;
BEGIN
  SELECT * INTO v_user FROM app_users WHERE id = current_user_id();
  IF v_user IS NULL THEN RETURN jsonb_build_object('error', 'not_authenticated'); END IF;

  -- ===== Identidade (ficha + unidades) =====
  IF v_user.employee_id IS NOT NULL THEN
    SELECT * INTO v_employee FROM employees WHERE id = v_user.employee_id AND archived_at IS NULL;
  END IF;

  IF v_employee.employer_unit_id IS NOT NULL THEN
    SELECT id, trade_name, legal_name, city, state_uf
    INTO v_employer_unit_id, v_employer_unit_trade, v_employer_unit_legal,
         v_employer_unit_city, v_employer_unit_state
    FROM employer_units WHERE id = v_employee.employer_unit_id;
  END IF;
  IF v_employee.department_id IS NOT NULL THEN
    SELECT id, display_name INTO v_department_id, v_department_name
    FROM departments WHERE id = v_employee.department_id;
  END IF;
  IF v_employee.working_unit_id IS NOT NULL THEN
    SELECT id, display_name, city, state_uf
    INTO v_working_unit_id, v_working_unit_name, v_working_unit_city, v_working_unit_state
    FROM working_units WHERE id = v_employee.working_unit_id;
  END IF;
  IF v_user.manager_id IS NOT NULL THEN
    SELECT u.id, u.email, COALESCE(e.full_name, u.full_name)
    INTO v_manager_id, v_manager_email, v_manager_name
    FROM app_users u
      LEFT JOIN employees e ON e.id = u.employee_id AND e.archived_at IS NULL
    WHERE u.id = v_user.manager_id;
  END IF;

  -- ===== KPIs de PDI =====
  -- Contagem de PDIs do proprio usuario por status, + acoes pendentes/concluidas
  WITH my_pdis AS (
    SELECT id, status, actions_total, actions_completed, end_date
    FROM pdis WHERE user_id = v_user.id
  )
  SELECT jsonb_build_object(
    'active',     count(*) FILTER (WHERE status = 'active'),
    'completed',  count(*) FILTER (WHERE status = 'completed'),
    'draft',      count(*) FILTER (WHERE status = 'draft'),
    'canceled',   count(*) FILTER (WHERE status = 'canceled'),
    'overdue',    count(*) FILTER (WHERE status = 'active' AND end_date IS NOT NULL AND end_date < CURRENT_DATE),
    'actions_total',     COALESCE(sum(actions_total), 0),
    'actions_completed', COALESCE(sum(actions_completed), 0)
  ) INTO v_pdi_kpis FROM my_pdis;

  -- ===== KPIs de Reconhecimentos =====
  -- Recebidos vs enviados, totais e ultimos 90 dias.
  -- Privados sempre visiveis ao proprio (sender ou recipient).
  SELECT jsonb_build_object(
    'received_total',   count(*) FILTER (WHERE recipient_id = v_user.id),
    'received_90d',     count(*) FILTER (WHERE recipient_id = v_user.id
                                          AND created_at > now() - INTERVAL '90 days'),
    'sent_total',       count(*) FILTER (WHERE sender_id = v_user.id),
    'sent_90d',         count(*) FILTER (WHERE sender_id = v_user.id
                                          AND created_at > now() - INTERVAL '90 days')
  ) INTO v_recog_kpis
  FROM recognitions
  WHERE (recipient_id = v_user.id OR sender_id = v_user.id)
    AND hidden_at IS NULL;

  -- ===== Ultima 9-Box finalizada =====
  SELECT jsonb_build_object(
    'evaluation_id',  e.id,
    'box_label',      e.final_box_label,
    'box_row',        e.final_box_row,
    'box_col',        e.final_box_col,
    'finalized_at',   e.finalized_at,
    'cycle_name',     c.name,
    'is_adhoc',       e.is_adhoc
  ) INTO v_last_ninebox
  FROM ninebox_evaluations e
    LEFT JOIN ninebox_cycles c ON c.id = e.cycle_id
  WHERE e.subject_id = v_user.id
    AND e.status = 'finalized'
    AND e.canceled_at IS NULL
    AND e.final_box_label IS NOT NULL
  ORDER BY e.finalized_at DESC
  LIMIT 1;

  -- ===== KPIs de Onboarding =====
  -- Conta assignments por status (se a tabela existir e tiver assignment do usuario)
  BEGIN
    SELECT jsonb_build_object(
      'active',     count(*) FILTER (WHERE status IN ('not_started', 'in_progress')),
      'completed',  count(*) FILTER (WHERE status = 'completed'),
      'tasks_total',     COALESCE(sum(tasks_total), 0),
      'tasks_completed', COALESCE(sum(tasks_completed), 0)
    ) INTO v_onboarding_kpis
    FROM onboarding_assignments
    WHERE user_id = v_user.id;
  EXCEPTION WHEN undefined_table OR undefined_column THEN
    v_onboarding_kpis := jsonb_build_object(
      'active', 0, 'completed', 0, 'tasks_total', 0, 'tasks_completed', 0
    );
  END;

  -- ===== Retorno =====
  RETURN jsonb_build_object(
    'ok', TRUE,
    'identity', jsonb_build_object(
      'app_user_id',     v_user.id,
      'employee_id',     v_user.employee_id,
      'email',           v_user.email,
      'full_name',       COALESCE(v_employee.full_name, v_user.full_name),
      'role',            v_user.role,
      'job_title',       v_employee.job_title,
      'employment_link', v_user.employment_link,
      'hired_at',        v_user.hired_at,
      'hire_date',       v_employee.hire_date,
      'birth_date',      v_employee.birth_date,
      'employer_unit',   CASE WHEN v_employer_unit_id IS NOT NULL THEN
                          jsonb_build_object(
                            'id', v_employer_unit_id,
                            'trade_name', v_employer_unit_trade,
                            'legal_name', v_employer_unit_legal,
                            'city', v_employer_unit_city,
                            'state_uf', v_employer_unit_state
                          ) ELSE NULL END,
      'working_unit',    CASE WHEN v_working_unit_id IS NOT NULL THEN
                          jsonb_build_object(
                            'id', v_working_unit_id,
                            'trade_name', v_working_unit_name,
                            'city', v_working_unit_city,
                            'state_uf', v_working_unit_state
                          ) ELSE NULL END,
      'department',      CASE WHEN v_department_id IS NOT NULL THEN
                          jsonb_build_object(
                            'id', v_department_id,
                            'display_name', v_department_name
                          ) ELSE NULL END,
      'manager',         CASE WHEN v_manager_id IS NOT NULL THEN
                          jsonb_build_object(
                            'id', v_manager_id,
                            'email', v_manager_email,
                            'full_name', v_manager_name
                          ) ELSE NULL END
    ),
    'pdi_kpis',        v_pdi_kpis,
    'recog_kpis',      v_recog_kpis,
    'last_ninebox',    v_last_ninebox,
    'onboarding_kpis', v_onboarding_kpis
  );
END;
$$;

GRANT EXECUTE ON FUNCTION rpc_my_journey TO authenticated;

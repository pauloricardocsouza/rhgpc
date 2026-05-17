-- ============================================================================
-- R2 People · Sessao F6 · Dashboard Drilldown
-- ============================================================================
-- rpc_dashboard_drill(p_kind, p_value_text, p_value_int1, p_value_int2)
--
-- Retorna a lista de pessoas ou PDIs que compoem um agregado do dashboard.
-- Usa exatamente a mesma logica de escopo de rpc_tenant_dashboard:
--   - super_admin / diretoria / rh  -> scope='full'    (todo tenant ativo)
--   - lider                          -> scope='hierarchy' (subarvore)
--   - colaborador                    -> permission_denied
--
-- Tipos de drill suportados:
--   1. 'ninebox'           p_value_int1=row, p_value_int2=col
--   2. 'employer_unit'     p_value_text=unit_id (uuid)
--   3. 'department'        p_value_text=department_id (uuid)
--   4. 'headcount_metric'  p_value_text in (
--          'total_active','total_terminated',
--          'hired_30d','hired_90d',
--          'terminated_30d','terminated_90d')
--   5. 'pdis_by_manager'   p_value_text=manager_id (uuid)
--
-- Retorno comum:
--   - scope                 · 'full' | 'hierarchy'
--   - kind                  · echo do p_kind
--   - universe_size         · total no escopo
--   - count                 · total filtrado pelo drill
--   - items                 · array de objetos (estrutura varia por kind)
-- ============================================================================

CREATE OR REPLACE FUNCTION rpc_dashboard_drill(
  p_kind          TEXT,
  p_value_text    TEXT DEFAULT NULL,
  p_value_int1    INT  DEFAULT NULL,
  p_value_int2    INT  DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user app_users;
  v_scope TEXT;
  v_universe UUID[];
  v_items JSONB := '[]'::JSONB;
  v_count INT := 0;
  v_uuid_val UUID;
BEGIN
  -- ===== Autenticacao =====
  SELECT * INTO v_user FROM app_users WHERE id = current_user_id();
  IF v_user IS NULL THEN RETURN jsonb_build_object('error', 'not_authenticated'); END IF;

  -- ===== Escopo (mesma logica da F4) =====
  IF is_super_admin() OR v_user.role IN ('diretoria', 'rh') THEN
    v_scope := 'full';
    SELECT array_agg(id) INTO v_universe
    FROM app_users WHERE tenant_id = v_user.tenant_id AND active = TRUE;
  ELSIF v_user.role = 'lider' THEN
    v_scope := 'hierarchy';
    WITH RECURSIVE sub AS (
      SELECT u.id, 1 AS depth FROM app_users u
      WHERE u.manager_id = v_user.id
        AND u.tenant_id = v_user.tenant_id AND u.active = TRUE
      UNION ALL
      SELECT u.id, s.depth + 1 FROM app_users u
        JOIN sub s ON u.manager_id = s.id
      WHERE s.depth < 10 AND u.tenant_id = v_user.tenant_id AND u.active = TRUE
    )
    SELECT array_agg(DISTINCT id) INTO v_universe FROM sub;
    IF v_universe IS NULL THEN v_universe := ARRAY[]::UUID[]; END IF;
  ELSE
    RETURN jsonb_build_object('error', 'permission_denied');
  END IF;

  -- ===== Despachar por kind =====

  IF p_kind = 'ninebox' THEN
    -- Pessoas cuja ultima avaliacao finalizada cai em (row, col)
    IF p_value_int1 IS NULL OR p_value_int2 IS NULL THEN
      RETURN jsonb_build_object('error', 'invalid_value', 'detail', 'ninebox requer row e col');
    END IF;
    WITH latest_per_subject AS (
      SELECT DISTINCT ON (subject_id)
        subject_id, final_box_row, final_box_col, final_box_label, finalized_at
      FROM ninebox_evaluations
      WHERE subject_id = ANY(v_universe)
        AND status = 'finalized'
        AND canceled_at IS NULL
        AND final_box_label IS NOT NULL
      ORDER BY subject_id, finalized_at DESC
    )
    SELECT
      COALESCE(jsonb_agg(jsonb_build_object(
        'app_user_id', u.id,
        'employee_id', u.employee_id,
        'full_name', COALESCE(e.full_name, u.full_name),
        'job_title', e.job_title,
        'unit_name', eu.trade_name,
        'department_name', d.display_name,
        'chip_label', lps.final_box_label,
        'box_row', lps.final_box_row,
        'box_col', lps.final_box_col
      ) ORDER BY COALESCE(e.full_name, u.full_name)), '[]'::JSONB),
      count(*)
    INTO v_items, v_count
    FROM latest_per_subject lps
      JOIN app_users u ON u.id = lps.subject_id
      LEFT JOIN employees e ON e.id = u.employee_id AND e.archived_at IS NULL
      LEFT JOIN employer_units eu ON eu.id = e.employer_unit_id
      LEFT JOIN departments d ON d.id = e.department_id
    WHERE lps.final_box_row = p_value_int1
      AND lps.final_box_col = p_value_int2;

  ELSIF p_kind = 'employer_unit' THEN
    IF p_value_text IS NULL THEN
      RETURN jsonb_build_object('error', 'invalid_value');
    END IF;
    BEGIN v_uuid_val := p_value_text::UUID; EXCEPTION WHEN OTHERS THEN
      RETURN jsonb_build_object('error', 'invalid_uuid');
    END;
    SELECT
      COALESCE(jsonb_agg(jsonb_build_object(
        'app_user_id', u.id,
        'employee_id', u.employee_id,
        'full_name', COALESCE(e.full_name, u.full_name),
        'job_title', e.job_title,
        'unit_name', eu.trade_name,
        'department_name', d.display_name,
        'chip_label', eu.trade_name
      ) ORDER BY COALESCE(e.full_name, u.full_name)), '[]'::JSONB),
      count(*)
    INTO v_items, v_count
    FROM employees e
      JOIN app_users u ON u.employee_id = e.id
      LEFT JOIN employer_units eu ON eu.id = e.employer_unit_id
      LEFT JOIN departments d ON d.id = e.department_id
    WHERE u.id = ANY(v_universe)
      AND e.archived_at IS NULL
      AND e.termination_date IS NULL
      AND e.employer_unit_id = v_uuid_val;

  ELSIF p_kind = 'department' THEN
    IF p_value_text IS NULL THEN
      RETURN jsonb_build_object('error', 'invalid_value');
    END IF;
    BEGIN v_uuid_val := p_value_text::UUID; EXCEPTION WHEN OTHERS THEN
      RETURN jsonb_build_object('error', 'invalid_uuid');
    END;
    SELECT
      COALESCE(jsonb_agg(jsonb_build_object(
        'app_user_id', u.id,
        'employee_id', u.employee_id,
        'full_name', COALESCE(e.full_name, u.full_name),
        'job_title', e.job_title,
        'unit_name', eu.trade_name,
        'department_name', d.display_name,
        'chip_label', d.display_name
      ) ORDER BY COALESCE(e.full_name, u.full_name)), '[]'::JSONB),
      count(*)
    INTO v_items, v_count
    FROM employees e
      JOIN app_users u ON u.employee_id = e.id
      LEFT JOIN employer_units eu ON eu.id = e.employer_unit_id
      LEFT JOIN departments d ON d.id = e.department_id
    WHERE u.id = ANY(v_universe)
      AND e.archived_at IS NULL
      AND e.termination_date IS NULL
      AND e.department_id = v_uuid_val;

  ELSIF p_kind = 'headcount_metric' THEN
    IF p_value_text IS NULL THEN
      RETURN jsonb_build_object('error', 'invalid_value');
    END IF;
    IF p_value_text NOT IN (
      'total_active','total_terminated','hired_30d','hired_90d','terminated_30d','terminated_90d'
    ) THEN
      RETURN jsonb_build_object('error', 'invalid_metric', 'detail', p_value_text);
    END IF;

    SELECT
      COALESCE(jsonb_agg(jsonb_build_object(
        'app_user_id', u.id,
        'employee_id', u.employee_id,
        'full_name', COALESCE(e.full_name, u.full_name),
        'job_title', e.job_title,
        'unit_name', eu.trade_name,
        'department_name', d.display_name,
        'hire_date', e.hire_date,
        'termination_date', e.termination_date,
        'chip_label', CASE p_value_text
          WHEN 'total_active'     THEN 'Ativo'
          WHEN 'total_terminated' THEN 'Desligado'
          WHEN 'hired_30d'        THEN 'Contratado em 30d'
          WHEN 'hired_90d'        THEN 'Contratado em 90d'
          WHEN 'terminated_30d'   THEN 'Desligado em 30d'
          WHEN 'terminated_90d'   THEN 'Desligado em 90d'
        END
      ) ORDER BY
        CASE WHEN p_value_text LIKE 'hired%' THEN e.hire_date END DESC NULLS LAST,
        CASE WHEN p_value_text LIKE 'terminated%' THEN e.termination_date END DESC NULLS LAST,
        COALESCE(e.full_name, u.full_name)
      ), '[]'::JSONB),
      count(*)
    INTO v_items, v_count
    FROM employees e
      JOIN app_users u ON u.employee_id = e.id
      LEFT JOIN employer_units eu ON eu.id = e.employer_unit_id
      LEFT JOIN departments d ON d.id = e.department_id
    WHERE u.id = ANY(v_universe)
      AND e.archived_at IS NULL
      AND (
        (p_value_text = 'total_active'     AND e.termination_date IS NULL) OR
        (p_value_text = 'total_terminated' AND e.termination_date IS NOT NULL) OR
        (p_value_text = 'hired_30d'        AND e.hire_date > CURRENT_DATE - INTERVAL '30 days') OR
        (p_value_text = 'hired_90d'        AND e.hire_date > CURRENT_DATE - INTERVAL '90 days') OR
        (p_value_text = 'terminated_30d'   AND e.termination_date IS NOT NULL
                                           AND e.termination_date > CURRENT_DATE - INTERVAL '30 days') OR
        (p_value_text = 'terminated_90d'   AND e.termination_date IS NOT NULL
                                           AND e.termination_date > CURRENT_DATE - INTERVAL '90 days')
      );

  ELSIF p_kind = 'pdis_by_manager' THEN
    -- Lista PDIs vencidos do gestor especifico
    IF p_value_text IS NULL THEN
      RETURN jsonb_build_object('error', 'invalid_value');
    END IF;
    BEGIN v_uuid_val := p_value_text::UUID; EXCEPTION WHEN OTHERS THEN
      RETURN jsonb_build_object('error', 'invalid_uuid');
    END;
    SELECT
      COALESCE(jsonb_agg(jsonb_build_object(
        'pdi_id', p.id,
        'objective', p.objective,
        'app_user_id', p.user_id,
        'employee_id', u.employee_id,
        'full_name', COALESCE(e.full_name, u.full_name),
        'job_title', e.job_title,
        'unit_name', eu.trade_name,
        'end_date', p.end_date,
        'days_overdue', (CURRENT_DATE - p.end_date)::INT,
        'actions_total', p.actions_total,
        'actions_completed', p.actions_completed,
        'chip_label', (CURRENT_DATE - p.end_date)::TEXT || 'd em atraso'
      ) ORDER BY p.end_date ASC), '[]'::JSONB),
      count(*)
    INTO v_items, v_count
    FROM pdis p
      JOIN app_users u ON u.id = p.user_id
      LEFT JOIN employees e ON e.id = u.employee_id AND e.archived_at IS NULL
      LEFT JOIN employer_units eu ON eu.id = e.employer_unit_id
    WHERE p.user_id = ANY(v_universe)
      AND p.manager_id_snapshot = v_uuid_val
      AND p.status = 'active'
      AND p.end_date IS NOT NULL
      AND p.end_date < CURRENT_DATE;

  ELSE
    RETURN jsonb_build_object('error', 'unknown_kind', 'detail', p_kind);
  END IF;

  RETURN jsonb_build_object(
    'ok', TRUE,
    'scope', v_scope,
    'kind', p_kind,
    'universe_size', COALESCE(array_length(v_universe, 1), 0),
    'count', v_count,
    'items', v_items
  );
END;
$$;

GRANT EXECUTE ON FUNCTION rpc_dashboard_drill TO authenticated;

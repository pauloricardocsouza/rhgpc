-- ============================================================================
-- R2 People · Sessao F4 · Dashboard tenant-wide
-- ============================================================================
-- 1 RPC: rpc_tenant_dashboard
--
-- Escopos:
--   - super_admin / diretoria / rh:  full   (todo o tenant)
--   - lider (manager de alguem):      hierarchy (toda a subarvore propria)
--   - colaborador:                    permission_denied
--
-- Retorno:
--   scope                       · 'full' | 'hierarchy'
--   universe_size               · total de pessoas no escopo
--   headcount                   · totais e contadores temporais
--   ninebox_distribution        · 1 entrada por caixa com count
--   pdis_overdue_by_manager     · agrupado por gestor (top 10)
--   recognition_top_recipients  · top 10 (90d)
--   recognition_top_senders     · top 10 (90d)
--
-- Padrao: F4 nao re-implementa o que ja existe em rpc_my_team_dashboard.
-- Em vez disso, esta RPC e a versao corporativa.
-- ============================================================================

CREATE OR REPLACE FUNCTION rpc_tenant_dashboard()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user app_users;
  v_scope TEXT;
  v_universe UUID[];      -- IDs de app_users no escopo
  v_headcount JSONB;
  v_ninebox JSONB;
  v_pdis_by_manager JSONB;
  v_top_recipients JSONB;
  v_top_senders JSONB;
BEGIN
  SELECT * INTO v_user FROM app_users WHERE id = current_user_id();
  IF v_user IS NULL THEN RETURN jsonb_build_object('error', 'not_authenticated'); END IF;

  -- ===== Determina o escopo =====
  IF is_super_admin() OR v_user.role IN ('diretoria', 'rh') THEN
    v_scope := 'full';
    -- Todo o tenant
    SELECT array_agg(id) INTO v_universe
    FROM app_users
    WHERE tenant_id = v_user.tenant_id AND active = TRUE;
  ELSIF v_user.role = 'lider' THEN
    v_scope := 'hierarchy';
    -- Subarvore via CTE recursiva (10 niveis max)
    WITH RECURSIVE sub AS (
      SELECT u.id, 1 AS depth
      FROM app_users u
      WHERE u.manager_id = v_user.id
        AND u.tenant_id = v_user.tenant_id
        AND u.active = TRUE
      UNION ALL
      SELECT u.id, s.depth + 1
      FROM app_users u
        JOIN sub s ON u.manager_id = s.id
      WHERE s.depth < 10
        AND u.tenant_id = v_user.tenant_id
        AND u.active = TRUE
    )
    SELECT array_agg(DISTINCT id) INTO v_universe FROM sub;
    -- Se lider sem subordinados, ainda mostra dashboard vazio do escopo dele
    IF v_universe IS NULL THEN v_universe := ARRAY[]::UUID[]; END IF;
  ELSE
    RETURN jsonb_build_object('error', 'permission_denied');
  END IF;

  -- ===== Headcount =====
  -- Tres faixas: total ativo, contratados em 30/90 dias, desligados em 30/90 dias.
  -- Por unidade empregadora e departamento (top 10 cada).
  WITH eligible AS (
    SELECT e.*
    FROM employees e
      JOIN app_users u ON u.employee_id = e.id
    WHERE e.archived_at IS NULL
      AND u.id = ANY(v_universe)
  )
  SELECT jsonb_build_object(
    'total_active', count(*) FILTER (WHERE termination_date IS NULL),
    'total_terminated', count(*) FILTER (WHERE termination_date IS NOT NULL),
    'hired_30d', count(*) FILTER (WHERE hire_date > CURRENT_DATE - INTERVAL '30 days'),
    'hired_90d', count(*) FILTER (WHERE hire_date > CURRENT_DATE - INTERVAL '90 days'),
    'terminated_30d', count(*) FILTER (
      WHERE termination_date IS NOT NULL AND termination_date > CURRENT_DATE - INTERVAL '30 days'
    ),
    'terminated_90d', count(*) FILTER (
      WHERE termination_date IS NOT NULL AND termination_date > CURRENT_DATE - INTERVAL '90 days'
    ),
    'by_employer_unit', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
        'unit_id', eu.id, 'unit_name', eu.legal_name, 'count', cnt
      ) ORDER BY cnt DESC)
      FROM (
        SELECT employer_unit_id, count(*) AS cnt
        FROM eligible
        WHERE termination_date IS NULL AND employer_unit_id IS NOT NULL
        GROUP BY employer_unit_id
        ORDER BY count(*) DESC
        LIMIT 10
      ) g
        LEFT JOIN employer_units eu ON eu.id = g.employer_unit_id
    ), '[]'::JSONB),
    'by_department', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
        'department_id', d.id, 'department_name', d.display_name, 'count', cnt
      ) ORDER BY cnt DESC)
      FROM (
        SELECT department_id, count(*) AS cnt
        FROM eligible
        WHERE termination_date IS NULL AND department_id IS NOT NULL
        GROUP BY department_id
        ORDER BY count(*) DESC
        LIMIT 10
      ) g
        LEFT JOIN departments d ON d.id = g.department_id
    ), '[]'::JSONB)
  ) INTO v_headcount
  FROM eligible;

  -- ===== Distribuicao 9-Box =====
  -- Contagem por final_box_label da ultima avaliacao FINALIZADA de cada pessoa.
  SELECT COALESCE(jsonb_agg(row_to_json(t) ORDER BY t.box_label), '[]'::JSONB)
  INTO v_ninebox
  FROM (
    WITH latest_per_subject AS (
      SELECT DISTINCT ON (subject_id)
        subject_id, final_box_label, final_box_row, final_box_col
      FROM ninebox_evaluations
      WHERE subject_id = ANY(v_universe)
        AND status = 'finalized'
        AND canceled_at IS NULL
        AND final_box_label IS NOT NULL
      ORDER BY subject_id, finalized_at DESC
    )
    SELECT
      final_box_label AS box_label,
      final_box_row   AS box_row,
      final_box_col   AS box_col,
      count(*)        AS count
    FROM latest_per_subject
    GROUP BY final_box_label, final_box_row, final_box_col
  ) t;

  -- ===== PDIs atrasados por gestor =====
  -- Agrupa por manager_id_snapshot, top 10 com mais PDIs vencidos.
  SELECT COALESCE(jsonb_agg(row_to_json(t) ORDER BY t.overdue_count DESC), '[]'::JSONB)
  INTO v_pdis_by_manager
  FROM (
    SELECT
      p.manager_id_snapshot AS manager_id,
      COALESCE(em.full_name, m.full_name) AS manager_name,
      m.email AS manager_email,
      count(*) AS overdue_count,
      max(CURRENT_DATE - p.end_date) AS worst_overdue_days
    FROM pdis p
      LEFT JOIN app_users m ON m.id = p.manager_id_snapshot
      LEFT JOIN employees em ON em.id = m.employee_id AND em.archived_at IS NULL
    WHERE p.user_id = ANY(v_universe)
      AND p.status = 'active'
      AND p.end_date IS NOT NULL
      AND p.end_date < CURRENT_DATE
    GROUP BY p.manager_id_snapshot, em.full_name, m.full_name, m.email
    ORDER BY count(*) DESC, max(CURRENT_DATE - p.end_date) DESC
    LIMIT 10
  ) t;

  -- ===== Ranking de reconhecimentos (90d) =====
  -- Top 10 recipients. Privados filtrados conforme role.
  SELECT COALESCE(jsonb_agg(row_to_json(t) ORDER BY t.total DESC), '[]'::JSONB)
  INTO v_top_recipients
  FROM (
    SELECT
      r.recipient_id AS user_id,
      u.employee_id,
      COALESCE(e.full_name, u.full_name) AS user_name,
      e.job_title,
      count(*) AS total,
      count(*) FILTER (WHERE NOT r.is_private) AS public_count,
      count(*) FILTER (WHERE r.is_private) AS private_count
    FROM recognitions r
      JOIN app_users u ON u.id = r.recipient_id
      LEFT JOIN employees e ON e.id = u.employee_id AND e.archived_at IS NULL
    WHERE r.recipient_id = ANY(v_universe)
      AND r.hidden_at IS NULL
      AND r.created_at > now() - INTERVAL '90 days'
      AND (
        NOT r.is_private
        OR is_super_admin()
        OR v_user.role IN ('diretoria', 'rh')
        OR r.sender_id = v_user.id
        OR r.recipient_id = v_user.id
      )
    GROUP BY r.recipient_id, u.employee_id, e.full_name, u.full_name, e.job_title
    ORDER BY count(*) DESC
    LIMIT 10
  ) t;

  -- Top senders
  SELECT COALESCE(jsonb_agg(row_to_json(t) ORDER BY t.total DESC), '[]'::JSONB)
  INTO v_top_senders
  FROM (
    SELECT
      r.sender_id AS user_id,
      u.employee_id,
      COALESCE(e.full_name, u.full_name) AS user_name,
      e.job_title,
      count(*) AS total
    FROM recognitions r
      JOIN app_users u ON u.id = r.sender_id
      LEFT JOIN employees e ON e.id = u.employee_id AND e.archived_at IS NULL
    WHERE r.sender_id = ANY(v_universe)
      AND r.hidden_at IS NULL
      AND r.created_at > now() - INTERVAL '90 days'
      AND (
        NOT r.is_private
        OR is_super_admin()
        OR v_user.role IN ('diretoria', 'rh')
        OR r.sender_id = v_user.id
        OR r.recipient_id = v_user.id
      )
    GROUP BY r.sender_id, u.employee_id, e.full_name, u.full_name, e.job_title
    ORDER BY count(*) DESC
    LIMIT 10
  ) t;

  RETURN jsonb_build_object(
    'ok', TRUE,
    'scope', v_scope,
    'universe_size', COALESCE(array_length(v_universe, 1), 0),
    'headcount', v_headcount,
    'ninebox_distribution', v_ninebox,
    'pdis_overdue_by_manager', v_pdis_by_manager,
    'recognition_top_recipients', v_top_recipients,
    'recognition_top_senders', v_top_senders
  );
END;
$$;

GRANT EXECUTE ON FUNCTION rpc_tenant_dashboard TO authenticated;

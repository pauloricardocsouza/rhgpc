-- ============================================================================
-- R2 People · Sessao F3 · Dashboard de Minha Equipe
-- ============================================================================
-- 1 RPC complementar para a tela /minha-equipe.
-- A grade 9-Box e o headcount sao calculados no frontend a partir de
-- rpc_my_team. Esta RPC entrega o que e mais custoso de fazer no client:
--
--   - pdis_overdue:        PDIs com end_date passada ou progresso lento
--   - recognitions_top_recipients:  pessoas mais reconhecidas (90d)
--   - recognitions_top_senders:     gestores que mais reconhecem (90d)
--
-- Padrao: include_indirect (mesmo flag de rpc_my_team) determina o universo
-- de subordinados considerado.
--
-- Permissao: qualquer usuario autenticado pode chamar (cada um ve so
-- subordinados proprios via CTE recursiva).
-- ============================================================================

CREATE OR REPLACE FUNCTION rpc_my_team_dashboard(p_include_indirect BOOLEAN DEFAULT FALSE)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user app_users;
  v_subordinate_ids UUID[];
  v_pdis_overdue JSONB;
  v_top_recipients JSONB;
  v_top_senders JSONB;
BEGIN
  SELECT * INTO v_user FROM app_users WHERE id = current_user_id();
  IF v_user IS NULL THEN RETURN jsonb_build_object('error', 'not_authenticated'); END IF;

  -- 1. Resolve a subarvore de subordinados (mesma logica de rpc_my_team)
  WITH RECURSIVE subordinates AS (
    SELECT u.id, 1 AS depth
    FROM app_users u
    WHERE u.manager_id = v_user.id
      AND u.tenant_id = v_user.tenant_id

    UNION ALL

    SELECT u.id, s.depth + 1
    FROM app_users u
      JOIN subordinates s ON u.manager_id = s.id
    WHERE p_include_indirect
      AND s.depth < 10
      AND u.tenant_id = v_user.tenant_id
  )
  SELECT array_agg(DISTINCT id) INTO v_subordinate_ids FROM subordinates;

  -- Sem subordinados · retorna estrutura vazia
  IF v_subordinate_ids IS NULL OR array_length(v_subordinate_ids, 1) = 0 THEN
    RETURN jsonb_build_object(
      'ok', TRUE,
      'include_indirect', p_include_indirect,
      'pdis_overdue', '[]'::JSONB,
      'recognitions_top_recipients', '[]'::JSONB,
      'recognitions_top_senders', '[]'::JSONB
    );
  END IF;

  -- 2. PDIs em atraso · status='active' com end_date no passado
  --    Ordena pelos mais antigos primeiro
  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'pdi_id', p.id,
    'objective', p.objective,
    'user_id', p.user_id,
    'employee_id', u.employee_id,
    'user_name', COALESCE(e.full_name, u.full_name),
    'job_title', e.job_title,
    'cycle_name', c.display_name,
    'end_date', p.end_date,
    'days_overdue', (CURRENT_DATE - p.end_date)::INT,
    'actions_total', p.actions_total,
    'actions_completed', p.actions_completed,
    'progress_pct', CASE
      WHEN p.actions_total > 0 THEN
        ROUND((p.actions_completed::NUMERIC / p.actions_total) * 100)
      ELSE 0
    END
  ) ORDER BY p.end_date ASC), '[]'::JSONB)
  INTO v_pdis_overdue
  FROM pdis p
    JOIN app_users u ON u.id = p.user_id
    LEFT JOIN employees e ON e.id = u.employee_id AND e.archived_at IS NULL
    LEFT JOIN pdi_cycles c ON c.id = p.cycle_id
  WHERE p.user_id = ANY(v_subordinate_ids)
    AND p.status = 'active'
    AND p.end_date IS NOT NULL
    AND p.end_date < CURRENT_DATE;

  -- 3. Top recipients · pessoas da equipe que mais receberam (90d)
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
    WHERE r.recipient_id = ANY(v_subordinate_ids)
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

  -- 4. Top senders · pessoas da equipe que mais reconheceram (90d)
  --    Tambem so conta reconhecimentos visiveis ao chamador
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
    WHERE r.sender_id = ANY(v_subordinate_ids)
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
    'include_indirect', p_include_indirect,
    'team_size', array_length(v_subordinate_ids, 1),
    'pdis_overdue', v_pdis_overdue,
    'recognitions_top_recipients', v_top_recipients,
    'recognitions_top_senders', v_top_senders
  );
END;
$$;

GRANT EXECUTE ON FUNCTION rpc_my_team_dashboard TO authenticated;

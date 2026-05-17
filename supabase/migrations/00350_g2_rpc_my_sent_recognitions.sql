-- ============================================================================
-- R2 People · Sessao G2 · Feed de reconhecimentos enviados
-- ============================================================================
-- rpc_my_sent_recognitions(p_limit DEFAULT 10)
--
-- Retorna os reconhecimentos enviados pelo usuario autenticado, ordenados
-- do mais recente para o mais antigo. Inclui nome do destinatario e
-- employee_id para link direto para a ficha.
--
-- Permissao: qualquer authenticated ve apenas o que enviou.
-- ============================================================================

CREATE OR REPLACE FUNCTION rpc_my_sent_recognitions(p_limit INT DEFAULT 10)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID;
  v_items JSONB;
  v_safe_limit INT;
BEGIN
  v_user_id := current_user_id();
  IF v_user_id IS NULL THEN RETURN jsonb_build_object('error', 'not_authenticated'); END IF;

  -- Cap defensivo entre 1 e 50
  v_safe_limit := GREATEST(1, LEAST(50, COALESCE(p_limit, 10)));

  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'id',              r.id,
    'message',         r.message,
    'is_private',      r.is_private,
    'recipient_id',    r.recipient_id,
    'recipient_name',  COALESCE(e.full_name, u.full_name),
    'recipient_employee_id', u.employee_id,
    'recipient_job_title',   e.job_title,
    'reactions_count', r.reactions_count,
    'created_at',      r.created_at
  ) ORDER BY r.created_at DESC), '[]'::JSONB)
  INTO v_items
  FROM (
    SELECT * FROM recognitions
    WHERE sender_id = v_user_id
      AND hidden_at IS NULL
    ORDER BY created_at DESC
    LIMIT v_safe_limit
  ) r
    LEFT JOIN app_users u ON u.id = r.recipient_id
    LEFT JOIN employees e ON e.id = u.employee_id AND e.archived_at IS NULL;

  RETURN jsonb_build_object(
    'ok', TRUE,
    'items', v_items,
    'limit', v_safe_limit
  );
END;
$$;

GRANT EXECUTE ON FUNCTION rpc_my_sent_recognitions TO authenticated;

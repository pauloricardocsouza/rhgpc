-- ============================================================================
-- R2 People · Patch A1 · Module checks nas RPCs (Recognition + PDI + Onboarding)
-- ============================================================================
-- Sessao A1 (08/05/2026)
--
-- Adiciona o check `module_is_active_for_me(code)` no inicio de TODAS as RPCs
-- de Recognition, PDI e Onboarding. Se o modulo estiver inativo no escopo do
-- usuario logado, a RPC retorna:
--
--   { "error": "module_inactive", "module": "<code>" }
--
-- Climate (Sessao E) sera tratado em sessao futura quando o pacote E for
-- reanexado. HEC e fora do escopo do produto.
--
-- O check e injetado APOS o gate de autenticacao (not_authenticated) e ANTES
-- de qualquer outra validacao (permissao, business rules). Ordem semantica:
--
--   1. Auth (usuario logado?)         · 'not_authenticated'
--   2. Modulo ativo? (este patch)     · 'module_inactive'
--   3. Permissao da role              · 'permission_denied'
--   4. Validacoes de negocio          · varios codigos
--
-- Helper adicional: `module_is_active_for_user(code, target_user_id)` para
-- RPCs que precisem checar o modulo no escopo do usuario-alvo (ex: PDI de
-- liderado em outra working_unit). Por ora apenas declarado · uso em A1.x
-- futuro se a granularidade exigir.
--
-- Pre-requisitos:
--   - Sessao L (modules) aplicada (helper module_is_active_for_me existe)
--   - Schemas Recognition (H2), PDI (J), Onboarding (K) aplicados
--
-- Idempotente: usa CREATE OR REPLACE FUNCTION em todas as definicoes.
-- ============================================================================

-- ============================================================================
-- HELPER ADICIONAL · module_is_active_for_user
-- ============================================================================
-- Resolve a working_unit do user-alvo e delega para module_is_active.
-- Util para checks "no escopo do recurso" (ex: criar PDI para um liderado
-- em loja que nao tem o modulo ativo).
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
  v_wu UUID;
BEGIN
  IF p_user_id IS NULL THEN
    RETURN FALSE;
  END IF;
  SELECT working_unit_id INTO v_wu FROM app_users WHERE id = p_user_id;
  RETURN module_is_active(p_module_code, v_wu);
END;
$$;

GRANT EXECUTE ON FUNCTION module_is_active_for_user TO authenticated;

COMMENT ON FUNCTION module_is_active_for_user IS
  'Sessao A1 · Resolve wu do user-alvo e delega para module_is_active';

-- ============================================================================
-- RECOGNITION · 6 RPCs · CREATE OR REPLACE
-- ============================================================================

-- ----- rpc_recognition_create -----
CREATE OR REPLACE FUNCTION rpc_recognition_create(
  p_recipient_id UUID,
  p_message TEXT,
  p_is_private BOOLEAN DEFAULT FALSE
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_sender UUID;
  v_tenant UUID;
  v_recipient_tenant UUID;
  v_id UUID;
BEGIN
  v_sender := current_user_id();
  v_tenant := current_tenant_id();

  IF v_sender IS NULL OR v_tenant IS NULL THEN
    RETURN jsonb_build_object('error', 'not_authenticated');
  END IF;

  -- Sessao A1 · check de modulo ativo
  IF NOT module_is_active_for_me('recognition') THEN
    RETURN jsonb_build_object('error', 'module_inactive', 'module', 'recognition');
  END IF;

  IF NOT user_has_permission('create_recognition') THEN
    RETURN jsonb_build_object('error', 'permission_denied');
  END IF;

  -- Validacao: recipient existe e e do mesmo tenant
  SELECT tenant_id INTO v_recipient_tenant
  FROM app_users WHERE id = p_recipient_id AND active = TRUE;

  IF v_recipient_tenant IS NULL THEN
    RETURN jsonb_build_object('error', 'recipient_not_found');
  END IF;

  IF v_recipient_tenant <> v_tenant THEN
    RETURN jsonb_build_object('error', 'cross_tenant_blocked');
  END IF;

  IF p_recipient_id = v_sender THEN
    RETURN jsonb_build_object('error', 'cannot_self_recognize');
  END IF;

  IF p_message IS NULL OR char_length(trim(p_message)) < 3 THEN
    RETURN jsonb_build_object('error', 'message_too_short');
  END IF;

  IF char_length(p_message) > 1000 THEN
    RETURN jsonb_build_object('error', 'message_too_long');
  END IF;

  INSERT INTO recognitions (tenant_id, sender_id, recipient_id, message, is_private)
  VALUES (v_tenant, v_sender, p_recipient_id, trim(p_message), COALESCE(p_is_private, FALSE))
  RETURNING id INTO v_id;

  RETURN jsonb_build_object('ok', TRUE, 'recognition_id', v_id);
END;
$$;

-- ----- rpc_recognition_react -----
CREATE OR REPLACE FUNCTION rpc_recognition_react(
  p_recognition_id UUID,
  p_kind recognition_reaction_kind
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user UUID;
  v_tenant UUID;
  v_post_tenant UUID;
  v_post_hidden TIMESTAMPTZ;
  v_post_recipient UUID;
  v_post_private BOOLEAN;
BEGIN
  v_user := current_user_id();
  v_tenant := current_tenant_id();

  IF v_user IS NULL OR v_tenant IS NULL THEN
    RETURN jsonb_build_object('error', 'not_authenticated');
  END IF;

  -- Sessao A1 · check de modulo ativo
  IF NOT module_is_active_for_me('recognition') THEN
    RETURN jsonb_build_object('error', 'module_inactive', 'module', 'recognition');
  END IF;

  IF NOT user_has_permission('react_recognition') THEN
    RETURN jsonb_build_object('error', 'permission_denied');
  END IF;

  SELECT tenant_id, hidden_at, recipient_id, is_private
  INTO v_post_tenant, v_post_hidden, v_post_recipient, v_post_private
  FROM recognitions WHERE id = p_recognition_id;

  IF v_post_tenant IS NULL THEN
    RETURN jsonb_build_object('error', 'recognition_not_found');
  END IF;

  IF v_post_tenant <> v_tenant THEN
    RETURN jsonb_build_object('error', 'cross_tenant_blocked');
  END IF;

  IF v_post_hidden IS NOT NULL THEN
    RETURN jsonb_build_object('error', 'recognition_hidden');
  END IF;

  -- Privacy: se privado, so destinatario, lider do destinatario, RH e Diretoria reagem
  IF v_post_private = TRUE
     AND v_post_recipient <> v_user
     AND NOT user_is_manager_of(v_post_recipient)
     AND current_user_role() NOT IN ('rh', 'diretoria') THEN
    RETURN jsonb_build_object('error', 'recognition_private');
  END IF;

  IF p_kind IS NULL THEN
    DELETE FROM recognition_reactions
    WHERE recognition_id = p_recognition_id AND user_id = v_user;
    RETURN jsonb_build_object('ok', TRUE, 'action', 'removed');
  END IF;

  -- UPSERT: troca o emoji se ja reagiu
  INSERT INTO recognition_reactions (tenant_id, recognition_id, user_id, kind)
  VALUES (v_tenant, p_recognition_id, v_user, p_kind)
  ON CONFLICT (recognition_id, user_id)
  DO UPDATE SET kind = EXCLUDED.kind;

  RETURN jsonb_build_object('ok', TRUE, 'action', 'reacted', 'kind', p_kind);
END;
$$;

-- ----- rpc_recognition_get_feed -----
CREATE OR REPLACE FUNCTION rpc_recognition_get_feed(
  p_limit INT DEFAULT 20,
  p_before TIMESTAMPTZ DEFAULT NULL,
  p_recipient_id UUID DEFAULT NULL,
  p_sender_id UUID DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user UUID;
  v_tenant UUID;
  v_role app_user_role;
  v_items JSONB;
  v_limit INT;
BEGIN
  v_user := current_user_id();
  v_tenant := current_tenant_id();
  v_role := current_user_role();

  IF v_user IS NULL OR v_tenant IS NULL THEN
    RETURN jsonb_build_object('error', 'not_authenticated');
  END IF;

  -- Sessao A1 · check de modulo ativo
  IF NOT module_is_active_for_me('recognition') THEN
    RETURN jsonb_build_object('error', 'module_inactive', 'module', 'recognition');
  END IF;

  IF NOT user_has_permission('view_recognitions_public') THEN
    RETURN jsonb_build_object('error', 'permission_denied');
  END IF;

  v_limit := LEAST(GREATEST(COALESCE(p_limit, 20), 1), 100);

  SELECT COALESCE(jsonb_agg(item ORDER BY (item->>'created_at') DESC), '[]'::jsonb)
  INTO v_items
  FROM (
    SELECT jsonb_build_object(
      'id', r.id,
      'sender_id', r.sender_id,
      'sender_name', s.full_name,
      'sender_avatar', s.avatar_url,
      'recipient_id', r.recipient_id,
      'recipient_name', rec.full_name,
      'recipient_avatar', rec.avatar_url,
      'message', r.message,
      'is_private', r.is_private,
      'created_at', r.created_at,
      'reactions_count', r.reactions_count,
      'my_reaction', (
        SELECT kind FROM recognition_reactions
        WHERE recognition_id = r.id AND user_id = v_user
      ),
      'reactions_breakdown', (
        SELECT jsonb_object_agg(kind, cnt) FROM (
          SELECT kind, count(*) AS cnt FROM recognition_reactions
          WHERE recognition_id = r.id GROUP BY kind
        ) k
      )
    ) AS item
    FROM recognitions r
    JOIN app_users s ON s.id = r.sender_id
    JOIN app_users rec ON rec.id = r.recipient_id
    WHERE r.tenant_id = v_tenant
      AND r.hidden_at IS NULL
      AND (p_before IS NULL OR r.created_at < p_before)
      AND (p_recipient_id IS NULL OR r.recipient_id = p_recipient_id)
      AND (p_sender_id IS NULL OR r.sender_id = p_sender_id)
      -- Privacy
      AND (
        r.is_private = FALSE
        OR r.recipient_id = v_user
        OR r.sender_id = v_user
        OR v_role IN ('rh', 'diretoria')
        OR user_is_manager_of(r.recipient_id) = TRUE
      )
    ORDER BY r.created_at DESC
    LIMIT v_limit
  ) sub;

  RETURN jsonb_build_object(
    'ok', TRUE,
    'items', v_items,
    'limit', v_limit
  );
END;
$$;

-- ----- rpc_recognition_get_stats -----
CREATE OR REPLACE FUNCTION rpc_recognition_get_stats(
  p_period_days INT DEFAULT 30
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user UUID;
  v_tenant UUID;
  v_period_days INT;
  v_my_sent INT;
  v_my_received INT;
  v_total_period INT;
  v_active_users INT;
  v_total_users INT;
  v_top_recipients JSONB;
BEGIN
  v_user := current_user_id();
  v_tenant := current_tenant_id();

  IF v_user IS NULL OR v_tenant IS NULL THEN
    RETURN jsonb_build_object('error', 'not_authenticated');
  END IF;

  -- Sessao A1 · check de modulo ativo
  IF NOT module_is_active_for_me('recognition') THEN
    RETURN jsonb_build_object('error', 'module_inactive', 'module', 'recognition');
  END IF;

  IF NOT user_has_permission('view_recognitions_public') THEN
    RETURN jsonb_build_object('error', 'permission_denied');
  END IF;

  v_period_days := LEAST(GREATEST(COALESCE(p_period_days, 30), 1), 365);

  -- Eu enviei (no periodo)
  SELECT count(*) INTO v_my_sent FROM recognitions
  WHERE tenant_id = v_tenant
    AND sender_id = v_user
    AND hidden_at IS NULL
    AND created_at > now() - (v_period_days || ' days')::interval;

  -- Eu recebi (no periodo · inclui privados)
  SELECT count(*) INTO v_my_received FROM recognitions
  WHERE tenant_id = v_tenant
    AND recipient_id = v_user
    AND hidden_at IS NULL
    AND created_at > now() - (v_period_days || ' days')::interval;

  -- Total no periodo
  SELECT count(*) INTO v_total_period FROM recognitions
  WHERE tenant_id = v_tenant
    AND hidden_at IS NULL
    AND is_private = FALSE
    AND created_at > now() - (v_period_days || ' days')::interval;

  -- Usuarios que enviaram pelo menos 1 reconhecimento no periodo
  SELECT count(DISTINCT sender_id) INTO v_active_users FROM recognitions
  WHERE tenant_id = v_tenant
    AND hidden_at IS NULL
    AND created_at > now() - (v_period_days || ' days')::interval;

  SELECT count(*) INTO v_total_users FROM app_users
  WHERE tenant_id = v_tenant AND active = TRUE;

  -- Top 5 reconhecidos do periodo (so contagem publica · respeita privacidade)
  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'recipient_id', recipient_id,
    'recipient_name', recipient_name,
    'count', cnt
  ) ORDER BY cnt DESC), '[]'::jsonb)
  INTO v_top_recipients
  FROM (
    SELECT r.recipient_id, u.full_name AS recipient_name, count(*) AS cnt
    FROM recognitions r
    JOIN app_users u ON u.id = r.recipient_id
    WHERE r.tenant_id = v_tenant
      AND r.hidden_at IS NULL
      AND r.is_private = FALSE
      AND r.created_at > now() - (v_period_days || ' days')::interval
    GROUP BY r.recipient_id, u.full_name
    ORDER BY cnt DESC
    LIMIT 5
  ) t;

  RETURN jsonb_build_object(
    'ok', TRUE,
    'period_days', v_period_days,
    'my_sent', v_my_sent,
    'my_received', v_my_received,
    'total_period', v_total_period,
    'active_users', v_active_users,
    'total_users', v_total_users,
    'participation_rate', CASE WHEN v_total_users > 0
      THEN round((v_active_users::NUMERIC / v_total_users) * 100, 1)
      ELSE 0 END,
    'top_recipients', v_top_recipients
  );
END;
$$;

-- ----- rpc_recognition_report -----
CREATE OR REPLACE FUNCTION rpc_recognition_report(
  p_recognition_id UUID,
  p_reason TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user UUID;
  v_tenant UUID;
  v_post_tenant UUID;
BEGIN
  v_user := current_user_id();
  v_tenant := current_tenant_id();

  IF v_user IS NULL OR v_tenant IS NULL THEN
    RETURN jsonb_build_object('error', 'not_authenticated');
  END IF;

  -- Sessao A1 · check de modulo ativo
  IF NOT module_is_active_for_me('recognition') THEN
    RETURN jsonb_build_object('error', 'module_inactive', 'module', 'recognition');
  END IF;

  IF NOT user_has_permission('report_recognition') THEN
    RETURN jsonb_build_object('error', 'permission_denied');
  END IF;

  SELECT tenant_id INTO v_post_tenant FROM recognitions WHERE id = p_recognition_id;
  IF v_post_tenant IS NULL THEN
    RETURN jsonb_build_object('error', 'recognition_not_found');
  END IF;
  IF v_post_tenant <> v_tenant THEN
    RETURN jsonb_build_object('error', 'cross_tenant_blocked');
  END IF;

  IF p_reason IS NULL OR char_length(trim(p_reason)) < 3 THEN
    RETURN jsonb_build_object('error', 'reason_too_short');
  END IF;

  BEGIN
    INSERT INTO recognition_reports (tenant_id, recognition_id, reporter_id, reason)
    VALUES (v_tenant, p_recognition_id, v_user, trim(p_reason));
  EXCEPTION WHEN unique_violation THEN
    RETURN jsonb_build_object('error', 'already_reported');
  END;

  RETURN jsonb_build_object('ok', TRUE);
END;
$$;

-- ----- rpc_recognition_resolve_report -----
CREATE OR REPLACE FUNCTION rpc_recognition_resolve_report(
  p_report_id UUID,
  p_action TEXT,                    -- 'hide', 'keep', 'dismiss'
  p_resolution_notes TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user UUID;
  v_tenant UUID;
  v_report_tenant UUID;
  v_recognition_id UUID;
  v_status recognition_report_status;
BEGIN
  v_user := current_user_id();
  v_tenant := current_tenant_id();

  IF v_user IS NULL OR v_tenant IS NULL THEN
    RETURN jsonb_build_object('error', 'not_authenticated');
  END IF;

  -- Sessao A1 · check de modulo ativo
  IF NOT module_is_active_for_me('recognition') THEN
    RETURN jsonb_build_object('error', 'module_inactive', 'module', 'recognition');
  END IF;

  IF NOT user_has_permission('manage_recognition_reports') THEN
    RETURN jsonb_build_object('error', 'permission_denied');
  END IF;

  SELECT tenant_id, recognition_id INTO v_report_tenant, v_recognition_id
  FROM recognition_reports WHERE id = p_report_id;

  IF v_report_tenant IS NULL THEN
    RETURN jsonb_build_object('error', 'report_not_found');
  END IF;
  IF v_report_tenant <> v_tenant THEN
    RETURN jsonb_build_object('error', 'cross_tenant_blocked');
  END IF;

  IF p_action = 'hide' THEN
    v_status := 'resolved_hidden';
    UPDATE recognitions
    SET hidden_at = now(),
        hidden_by = v_user,
        hidden_reason = COALESCE(p_resolution_notes, 'moderacao')
    WHERE id = v_recognition_id;
  ELSIF p_action = 'keep' THEN
    v_status := 'resolved_kept';
  ELSIF p_action = 'dismiss' THEN
    v_status := 'dismissed';
  ELSE
    RETURN jsonb_build_object('error', 'invalid_action');
  END IF;

  UPDATE recognition_reports
  SET status = v_status,
      resolved_by = v_user,
      resolved_at = now(),
      resolution_notes = p_resolution_notes
  WHERE id = p_report_id;

  RETURN jsonb_build_object('ok', TRUE, 'status', v_status);
END;
$$;

-- ============================================================================
-- PDI · 10 RPCs · CREATE OR REPLACE
-- ============================================================================

-- ----- rpc_pdi_create -----
CREATE OR REPLACE FUNCTION rpc_pdi_create(
  p_user_id UUID,                    -- para quem e o PDI (pode ser self ou liderado)
  p_cycle_id UUID,
  p_objective TEXT,
  p_context TEXT DEFAULT NULL,
  p_start_date DATE DEFAULT NULL,
  p_end_date DATE DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_caller UUID;
  v_tenant UUID;
  v_role app_user_role;
  v_target_tenant UUID;
  v_target_manager UUID;
  v_cycle_tenant UUID;
  v_cycle_open BOOLEAN;
  v_cycle_start DATE;
  v_cycle_end DATE;
  v_pdi_id UUID;
BEGIN
  v_caller := current_user_id();
  v_tenant := current_tenant_id();
  v_role := current_user_role();

  IF v_caller IS NULL OR v_tenant IS NULL THEN
    RETURN jsonb_build_object('error', 'not_authenticated');
  END IF;

  -- Sessao A1 · check de modulo ativo
  IF NOT module_is_active_for_me('pdi') THEN
    RETURN jsonb_build_object('error', 'module_inactive', 'module', 'pdi');
  END IF;

  -- Owner e o user_id alvo
  SELECT tenant_id, manager_id INTO v_target_tenant, v_target_manager
  FROM app_users WHERE id = p_user_id AND active = TRUE;

  IF v_target_tenant IS NULL THEN
    RETURN jsonb_build_object('error', 'user_not_found');
  END IF;

  IF v_target_tenant <> v_tenant THEN
    RETURN jsonb_build_object('error', 'cross_tenant_blocked');
  END IF;

  -- Permissao para criar:
  -- - self: precisa de manage_self_pdi
  -- - para outro: precisa ser manager direto/indireto OU ter manage_all_pdi (rh/diretoria)
  IF p_user_id = v_caller THEN
    IF NOT user_has_permission('manage_self_pdi') THEN
      RETURN jsonb_build_object('error', 'permission_denied');
    END IF;
  ELSE
    IF NOT (user_is_manager_of(p_user_id) OR user_has_permission('manage_all_pdi')) THEN
      RETURN jsonb_build_object('error', 'permission_denied');
    END IF;
  END IF;

  -- Ciclo
  SELECT tenant_id, open_for_planning, start_date, end_date
  INTO v_cycle_tenant, v_cycle_open, v_cycle_start, v_cycle_end
  FROM pdi_cycles WHERE id = p_cycle_id AND active = TRUE;

  IF v_cycle_tenant IS NULL THEN
    RETURN jsonb_build_object('error', 'cycle_not_found');
  END IF;

  IF v_cycle_tenant <> v_tenant THEN
    RETURN jsonb_build_object('error', 'cross_tenant_blocked');
  END IF;

  IF NOT v_cycle_open AND v_role NOT IN ('rh', 'diretoria') THEN
    RETURN jsonb_build_object('error', 'cycle_closed_for_planning');
  END IF;

  -- Validacao de mensagem
  IF char_length(trim(p_objective)) < 10 THEN
    RETURN jsonb_build_object('error', 'objective_too_short');
  END IF;

  -- Datas default vem do ciclo
  IF p_start_date IS NULL THEN p_start_date := v_cycle_start; END IF;
  IF p_end_date IS NULL THEN p_end_date := v_cycle_end; END IF;

  IF p_end_date < p_start_date THEN
    RETURN jsonb_build_object('error', 'end_before_start');
  END IF;

  INSERT INTO pdis (
    tenant_id, user_id, cycle_id, manager_id_snapshot,
    objective, context, start_date, end_date, created_by
  ) VALUES (
    v_tenant, p_user_id, p_cycle_id, v_target_manager,
    trim(p_objective), p_context, p_start_date, p_end_date, v_caller
  )
  RETURNING id INTO v_pdi_id;

  RETURN jsonb_build_object('ok', TRUE, 'pdi_id', v_pdi_id);
END;
$$;

-- ----- rpc_pdi_update -----
CREATE OR REPLACE FUNCTION rpc_pdi_update(
  p_pdi_id UUID,
  p_objective TEXT DEFAULT NULL,
  p_context TEXT DEFAULT NULL,
  p_start_date DATE DEFAULT NULL,
  p_end_date DATE DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_caller UUID;
  v_owner UUID;
  v_status pdi_status;
  v_tenant UUID;
BEGIN
  v_caller := current_user_id();
  IF v_caller IS NULL THEN
    RETURN jsonb_build_object('error', 'not_authenticated');
  END IF;

  -- Sessao A1 · check de modulo ativo
  IF NOT module_is_active_for_me('pdi') THEN
    RETURN jsonb_build_object('error', 'module_inactive', 'module', 'pdi');
  END IF;

  SELECT user_id, status, tenant_id INTO v_owner, v_status, v_tenant
  FROM pdis WHERE id = p_pdi_id;

  IF v_owner IS NULL THEN
    RETURN jsonb_build_object('error', 'pdi_not_found');
  END IF;

  IF v_tenant <> current_tenant_id() THEN
    RETURN jsonb_build_object('error', 'cross_tenant_blocked');
  END IF;

  -- Bloqueia edicao apos completed/canceled
  IF v_status IN ('completed', 'canceled') THEN
    RETURN jsonb_build_object('error', 'pdi_locked', 'status', v_status);
  END IF;

  -- Permissao
  IF NOT (
    v_owner = v_caller
    OR user_is_manager_of(v_owner)
    OR user_has_permission('manage_all_pdi')
  ) THEN
    RETURN jsonb_build_object('error', 'permission_denied');
  END IF;

  IF p_objective IS NOT NULL AND char_length(trim(p_objective)) < 10 THEN
    RETURN jsonb_build_object('error', 'objective_too_short');
  END IF;

  UPDATE pdis SET
    objective = COALESCE(trim(p_objective), objective),
    context = CASE WHEN p_context IS NULL THEN context ELSE p_context END,
    start_date = COALESCE(p_start_date, start_date),
    end_date = COALESCE(p_end_date, end_date)
  WHERE id = p_pdi_id;

  RETURN jsonb_build_object('ok', TRUE);
END;
$$;

-- ----- rpc_pdi_change_status -----
CREATE OR REPLACE FUNCTION rpc_pdi_change_status(
  p_pdi_id UUID,
  p_new_status pdi_status,
  p_cancel_reason TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_caller UUID;
  v_owner UUID;
  v_old_status pdi_status;
  v_actions_total INT;
  v_tenant UUID;
BEGIN
  v_caller := current_user_id();
  IF v_caller IS NULL THEN
    RETURN jsonb_build_object('error', 'not_authenticated');
  END IF;

  -- Sessao A1 · check de modulo ativo
  IF NOT module_is_active_for_me('pdi') THEN
    RETURN jsonb_build_object('error', 'module_inactive', 'module', 'pdi');
  END IF;

  SELECT user_id, status, actions_total, tenant_id
  INTO v_owner, v_old_status, v_actions_total, v_tenant
  FROM pdis WHERE id = p_pdi_id;

  IF v_owner IS NULL THEN
    RETURN jsonb_build_object('error', 'pdi_not_found');
  END IF;

  IF v_tenant <> current_tenant_id() THEN
    RETURN jsonb_build_object('error', 'cross_tenant_blocked');
  END IF;

  -- Permissao igual a update
  IF NOT (
    v_owner = v_caller
    OR user_is_manager_of(v_owner)
    OR user_has_permission('manage_all_pdi')
  ) THEN
    RETURN jsonb_build_object('error', 'permission_denied');
  END IF;

  -- Validacao de transicao
  IF v_old_status = p_new_status THEN
    RETURN jsonb_build_object('error', 'no_change');
  END IF;

  IF v_old_status = 'draft' AND p_new_status NOT IN ('active', 'canceled') THEN
    RETURN jsonb_build_object('error', 'invalid_transition');
  END IF;

  IF v_old_status = 'active' AND p_new_status NOT IN ('completed', 'canceled') THEN
    RETURN jsonb_build_object('error', 'invalid_transition');
  END IF;

  IF v_old_status IN ('completed', 'canceled') THEN
    RETURN jsonb_build_object('error', 'pdi_locked');
  END IF;

  -- Pre-condicoes
  IF p_new_status = 'active' AND v_actions_total = 0 THEN
    RETURN jsonb_build_object('error', 'no_actions_defined');
  END IF;

  IF p_new_status = 'canceled' AND (p_cancel_reason IS NULL OR char_length(trim(p_cancel_reason)) < 3) THEN
    RETURN jsonb_build_object('error', 'cancel_reason_required');
  END IF;

  UPDATE pdis SET
    status = p_new_status,
    cancel_reason = CASE WHEN p_new_status = 'canceled' THEN trim(p_cancel_reason) ELSE cancel_reason END
  WHERE id = p_pdi_id;

  RETURN jsonb_build_object('ok', TRUE, 'status', p_new_status);
END;
$$;

-- ----- rpc_pdi_action_add -----
CREATE OR REPLACE FUNCTION rpc_pdi_action_add(
  p_pdi_id UUID,
  p_title TEXT,
  p_description TEXT DEFAULT NULL,
  p_kind pdi_action_kind DEFAULT 'outro',
  p_due_date DATE DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_caller UUID;
  v_owner UUID;
  v_status pdi_status;
  v_tenant UUID;
  v_action_id UUID;
  v_next_order INT;
BEGIN
  v_caller := current_user_id();
  IF v_caller IS NULL THEN
    RETURN jsonb_build_object('error', 'not_authenticated');
  END IF;

  -- Sessao A1 · check de modulo ativo
  IF NOT module_is_active_for_me('pdi') THEN
    RETURN jsonb_build_object('error', 'module_inactive', 'module', 'pdi');
  END IF;

  SELECT user_id, status, tenant_id INTO v_owner, v_status, v_tenant
  FROM pdis WHERE id = p_pdi_id;

  IF v_owner IS NULL THEN
    RETURN jsonb_build_object('error', 'pdi_not_found');
  END IF;
  IF v_tenant <> current_tenant_id() THEN
    RETURN jsonb_build_object('error', 'cross_tenant_blocked');
  END IF;
  IF v_status IN ('completed', 'canceled') THEN
    RETURN jsonb_build_object('error', 'pdi_locked');
  END IF;

  IF NOT (
    v_owner = v_caller
    OR user_is_manager_of(v_owner)
    OR user_has_permission('manage_all_pdi')
  ) THEN
    RETURN jsonb_build_object('error', 'permission_denied');
  END IF;

  IF char_length(trim(p_title)) < 3 THEN
    RETURN jsonb_build_object('error', 'title_too_short');
  END IF;

  SELECT COALESCE(MAX(display_order), 0) + 1 INTO v_next_order
  FROM pdi_actions WHERE pdi_id = p_pdi_id;

  INSERT INTO pdi_actions (
    tenant_id, pdi_id, title, description, kind, due_date, display_order
  ) VALUES (
    v_tenant, p_pdi_id, trim(p_title), p_description, p_kind, p_due_date, v_next_order
  )
  RETURNING id INTO v_action_id;

  RETURN jsonb_build_object('ok', TRUE, 'action_id', v_action_id);
END;
$$;

-- ----- rpc_pdi_action_update -----
CREATE OR REPLACE FUNCTION rpc_pdi_action_update(
  p_action_id UUID,
  p_title TEXT DEFAULT NULL,
  p_description TEXT DEFAULT NULL,
  p_kind pdi_action_kind DEFAULT NULL,
  p_due_date DATE DEFAULT NULL,
  p_status pdi_action_status DEFAULT NULL,
  p_evidence_path TEXT DEFAULT NULL,
  p_evidence_url TEXT DEFAULT NULL,
  p_evidence_note TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_caller UUID;
  v_pdi UUID;
  v_owner UUID;
  v_pdi_status pdi_status;
  v_tenant UUID;
BEGIN
  v_caller := current_user_id();
  IF v_caller IS NULL THEN
    RETURN jsonb_build_object('error', 'not_authenticated');
  END IF;

  -- Sessao A1 · check de modulo ativo
  IF NOT module_is_active_for_me('pdi') THEN
    RETURN jsonb_build_object('error', 'module_inactive', 'module', 'pdi');
  END IF;

  SELECT a.pdi_id, p.user_id, p.status, p.tenant_id
  INTO v_pdi, v_owner, v_pdi_status, v_tenant
  FROM pdi_actions a JOIN pdis p ON p.id = a.pdi_id
  WHERE a.id = p_action_id;

  IF v_pdi IS NULL THEN
    RETURN jsonb_build_object('error', 'action_not_found');
  END IF;
  IF v_tenant <> current_tenant_id() THEN
    RETURN jsonb_build_object('error', 'cross_tenant_blocked');
  END IF;
  IF v_pdi_status IN ('completed', 'canceled') THEN
    RETURN jsonb_build_object('error', 'pdi_locked');
  END IF;

  IF NOT (
    v_owner = v_caller
    OR user_is_manager_of(v_owner)
    OR user_has_permission('manage_all_pdi')
  ) THEN
    RETURN jsonb_build_object('error', 'permission_denied');
  END IF;

  IF p_title IS NOT NULL AND char_length(trim(p_title)) < 3 THEN
    RETURN jsonb_build_object('error', 'title_too_short');
  END IF;

  -- Validacao: nao permite path E url ao mesmo tempo
  IF p_evidence_path IS NOT NULL AND p_evidence_url IS NOT NULL THEN
    RETURN jsonb_build_object('error', 'evidence_one_kind_only');
  END IF;

  UPDATE pdi_actions SET
    title = COALESCE(trim(p_title), title),
    description = CASE WHEN p_description IS NULL THEN description ELSE p_description END,
    kind = COALESCE(p_kind, kind),
    due_date = CASE WHEN p_due_date IS NULL THEN due_date ELSE p_due_date END,
    status = COALESCE(p_status, status),
    evidence_path = CASE
      WHEN p_evidence_path IS NULL THEN evidence_path
      WHEN p_evidence_path = '' THEN NULL
      ELSE p_evidence_path
    END,
    evidence_url = CASE
      WHEN p_evidence_url IS NULL THEN evidence_url
      WHEN p_evidence_url = '' THEN NULL
      ELSE p_evidence_url
    END,
    evidence_note = CASE WHEN p_evidence_note IS NULL THEN evidence_note ELSE p_evidence_note END
  WHERE id = p_action_id;

  RETURN jsonb_build_object('ok', TRUE);
END;
$$;

-- ----- rpc_pdi_action_remove -----
CREATE OR REPLACE FUNCTION rpc_pdi_action_remove(
  p_action_id UUID
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_caller UUID;
  v_owner UUID;
  v_pdi_status pdi_status;
  v_tenant UUID;
BEGIN
  v_caller := current_user_id();
  IF v_caller IS NULL THEN
    RETURN jsonb_build_object('error', 'not_authenticated');
  END IF;

  -- Sessao A1 · check de modulo ativo
  IF NOT module_is_active_for_me('pdi') THEN
    RETURN jsonb_build_object('error', 'module_inactive', 'module', 'pdi');
  END IF;

  SELECT p.user_id, p.status, p.tenant_id
  INTO v_owner, v_pdi_status, v_tenant
  FROM pdi_actions a JOIN pdis p ON p.id = a.pdi_id
  WHERE a.id = p_action_id;

  IF v_owner IS NULL THEN
    RETURN jsonb_build_object('error', 'action_not_found');
  END IF;
  IF v_tenant <> current_tenant_id() THEN
    RETURN jsonb_build_object('error', 'cross_tenant_blocked');
  END IF;
  IF v_pdi_status IN ('completed', 'canceled') THEN
    RETURN jsonb_build_object('error', 'pdi_locked');
  END IF;

  IF NOT (
    v_owner = v_caller
    OR user_is_manager_of(v_owner)
    OR user_has_permission('manage_all_pdi')
  ) THEN
    RETURN jsonb_build_object('error', 'permission_denied');
  END IF;

  DELETE FROM pdi_actions WHERE id = p_action_id;

  RETURN jsonb_build_object('ok', TRUE);
END;
$$;

-- ----- rpc_pdi_comment_add -----
CREATE OR REPLACE FUNCTION rpc_pdi_comment_add(
  p_pdi_id UUID,
  p_body TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_caller UUID;
  v_tenant UUID;
  v_pdi_tenant UUID;
  v_comment_id UUID;
BEGIN
  v_caller := current_user_id();
  v_tenant := current_tenant_id();
  IF v_caller IS NULL OR v_tenant IS NULL THEN
    RETURN jsonb_build_object('error', 'not_authenticated');
  END IF;

  -- Sessao A1 · check de modulo ativo
  IF NOT module_is_active_for_me('pdi') THEN
    RETURN jsonb_build_object('error', 'module_inactive', 'module', 'pdi');
  END IF;

  -- So pode comentar quem pode ler
  IF NOT pdi_can_read(p_pdi_id) THEN
    RETURN jsonb_build_object('error', 'permission_denied');
  END IF;

  SELECT tenant_id INTO v_pdi_tenant FROM pdis WHERE id = p_pdi_id;

  IF char_length(trim(p_body)) < 1 THEN
    RETURN jsonb_build_object('error', 'body_required');
  END IF;
  IF char_length(p_body) > 2000 THEN
    RETURN jsonb_build_object('error', 'body_too_long');
  END IF;

  INSERT INTO pdi_comments (tenant_id, pdi_id, author_id, body)
  VALUES (v_pdi_tenant, p_pdi_id, v_caller, trim(p_body))
  RETURNING id INTO v_comment_id;

  RETURN jsonb_build_object('ok', TRUE, 'comment_id', v_comment_id);
END;
$$;

-- ----- rpc_pdi_list -----
CREATE OR REPLACE FUNCTION rpc_pdi_list(
  p_scope TEXT DEFAULT 'own',
  p_status pdi_status DEFAULT NULL,
  p_cycle_id UUID DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_caller UUID;
  v_tenant UUID;
  v_role app_user_role;
  v_items JSONB;
BEGIN
  v_caller := current_user_id();
  v_tenant := current_tenant_id();
  v_role := current_user_role();

  IF v_caller IS NULL OR v_tenant IS NULL THEN
    RETURN jsonb_build_object('error', 'not_authenticated');
  END IF;

  -- Sessao A1 · check de modulo ativo
  IF NOT module_is_active_for_me('pdi') THEN
    RETURN jsonb_build_object('error', 'module_inactive', 'module', 'pdi');
  END IF;

  -- Escopos:
  --   own  · so PDIs onde user_id = caller
  --   team · own + PDIs onde caller e manager (direto/indireto) do user_id
  --   all  · qualquer PDI do tenant (so com permissao view_all_pdi)
  IF p_scope = 'all' AND NOT user_has_permission('view_all_pdi') THEN
    RETURN jsonb_build_object('error', 'permission_denied');
  END IF;
  IF p_scope = 'team' AND NOT (user_has_permission('view_team_pdi') OR user_has_permission('view_all_pdi')) THEN
    RETURN jsonb_build_object('error', 'permission_denied');
  END IF;

  SELECT COALESCE(jsonb_agg(item ORDER BY (item->>'created_at') DESC), '[]'::jsonb) INTO v_items
  FROM (
    SELECT jsonb_build_object(
      'id', p.id,
      'user_id', p.user_id,
      'user_name', u.full_name,
      'user_job_title', u.job_title,
      'cycle_id', p.cycle_id,
      'cycle_code', c.code,
      'cycle_name', c.display_name,
      'objective', p.objective,
      'status', p.status,
      'start_date', p.start_date,
      'end_date', p.end_date,
      'actions_total', p.actions_total,
      'actions_completed', p.actions_completed,
      'progress_percent', CASE WHEN p.actions_total > 0
        THEN round((p.actions_completed::NUMERIC / p.actions_total) * 100)
        ELSE 0 END,
      'manager_id', p.manager_id_snapshot,
      'manager_name', mg.full_name,
      'created_at', p.created_at
    ) AS item
    FROM pdis p
    JOIN app_users u ON u.id = p.user_id
    JOIN pdi_cycles c ON c.id = p.cycle_id
    LEFT JOIN app_users mg ON mg.id = p.manager_id_snapshot
    WHERE p.tenant_id = v_tenant
      AND (p_status IS NULL OR p.status = p_status)
      AND (p_cycle_id IS NULL OR p.cycle_id = p_cycle_id)
      AND (
        p_scope = 'own' AND p.user_id = v_caller
        OR p_scope = 'team' AND (p.user_id = v_caller OR user_is_manager_of(p.user_id) = TRUE)
        OR p_scope = 'all'  -- ja validamos permissao acima
      )
  ) sub;

  RETURN jsonb_build_object('ok', TRUE, 'items', v_items);
END;
$$;

-- ----- rpc_pdi_get_by_id -----
CREATE OR REPLACE FUNCTION rpc_pdi_get_by_id(p_pdi_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_pdi JSONB;
  v_actions JSONB;
  v_comments JSONB;
  v_owner UUID;
  v_caller UUID;
BEGIN
  v_caller := current_user_id();
  IF v_caller IS NULL THEN
    RETURN jsonb_build_object('error', 'not_authenticated');
  END IF;

  -- Sessao A1 · check de modulo ativo
  IF NOT module_is_active_for_me('pdi') THEN
    RETURN jsonb_build_object('error', 'module_inactive', 'module', 'pdi');
  END IF;

  IF NOT pdi_can_read(p_pdi_id) THEN
    RETURN jsonb_build_object('error', 'permission_denied');
  END IF;

  SELECT jsonb_build_object(
    'id', p.id,
    'tenant_id', p.tenant_id,
    'user_id', p.user_id,
    'user_name', u.full_name,
    'user_job_title', u.job_title,
    'user_avatar_url', u.avatar_url,
    'cycle_id', p.cycle_id,
    'cycle_code', c.code,
    'cycle_name', c.display_name,
    'objective', p.objective,
    'context', p.context,
    'status', p.status,
    'start_date', p.start_date,
    'end_date', p.end_date,
    'actions_total', p.actions_total,
    'actions_completed', p.actions_completed,
    'progress_percent', CASE WHEN p.actions_total > 0
      THEN round((p.actions_completed::NUMERIC / p.actions_total) * 100)
      ELSE 0 END,
    'manager_id', p.manager_id_snapshot,
    'manager_name', mg.full_name,
    'cancel_reason', p.cancel_reason,
    'activated_at', p.activated_at,
    'completed_at', p.completed_at,
    'canceled_at', p.canceled_at,
    'created_by', p.created_by,
    'created_at', p.created_at,
    'updated_at', p.updated_at
  ) INTO v_pdi
  FROM pdis p
  JOIN app_users u ON u.id = p.user_id
  JOIN pdi_cycles c ON c.id = p.cycle_id
  LEFT JOIN app_users mg ON mg.id = p.manager_id_snapshot
  WHERE p.id = p_pdi_id;

  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'id', a.id,
    'title', a.title,
    'description', a.description,
    'kind', a.kind,
    'due_date', a.due_date,
    'status', a.status,
    'display_order', a.display_order,
    'evidence_path', a.evidence_path,
    'evidence_url', a.evidence_url,
    'evidence_note', a.evidence_note,
    'completed_at', a.completed_at,
    'created_at', a.created_at
  ) ORDER BY a.display_order), '[]'::jsonb) INTO v_actions
  FROM pdi_actions a WHERE a.pdi_id = p_pdi_id;

  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'id', c.id,
    'author_id', c.author_id,
    'author_name', au.full_name,
    'author_avatar_url', au.avatar_url,
    'body', c.body,
    'edited_at', c.edited_at,
    'created_at', c.created_at
  ) ORDER BY c.created_at), '[]'::jsonb) INTO v_comments
  FROM pdi_comments c
  JOIN app_users au ON au.id = c.author_id
  WHERE c.pdi_id = p_pdi_id AND c.deleted_at IS NULL;

  RETURN jsonb_build_object(
    'ok', TRUE,
    'pdi', v_pdi,
    'actions', v_actions,
    'comments', v_comments
  );
END;
$$;

-- ----- rpc_pdi_list_cycles -----
CREATE OR REPLACE FUNCTION rpc_pdi_list_cycles()
RETURNS JSONB
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_tenant UUID;
  v_items JSONB;
BEGIN
  v_tenant := current_tenant_id();
  IF v_tenant IS NULL THEN
    RETURN jsonb_build_object('error', 'not_authenticated');
  END IF;

  -- Sessao A1 · check de modulo ativo
  IF NOT module_is_active_for_me('pdi') THEN
    RETURN jsonb_build_object('error', 'module_inactive', 'module', 'pdi');
  END IF;

  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'id', id,
    'code', code,
    'display_name', display_name,
    'start_date', start_date,
    'end_date', end_date,
    'open_for_planning', open_for_planning
  ) ORDER BY start_date DESC), '[]'::jsonb) INTO v_items
  FROM pdi_cycles WHERE tenant_id = v_tenant AND active = TRUE;

  RETURN jsonb_build_object('ok', TRUE, 'items', v_items);
END;
$$;

-- ============================================================================
-- ONBOARDING · 15 RPCs · CREATE OR REPLACE
-- ============================================================================

-- ----- rpc_onb_template_create -----
CREATE OR REPLACE FUNCTION rpc_onb_template_create(
  p_code VARCHAR,
  p_display_name VARCHAR,
  p_description TEXT DEFAULT NULL,
  p_suggested_duration_days INT DEFAULT 30
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_caller UUID;
  v_tenant UUID;
  v_id UUID;
BEGIN
  v_caller := current_user_id();
  v_tenant := current_tenant_id();

  IF v_caller IS NULL OR v_tenant IS NULL THEN
    RETURN jsonb_build_object('error', 'not_authenticated');
  END IF;

  -- Sessao A1 · check de modulo ativo
  IF NOT module_is_active_for_me('onboarding') THEN
    RETURN jsonb_build_object('error', 'module_inactive', 'module', 'onboarding');
  END IF;

  IF NOT user_has_permission('manage_onboarding') THEN
    RETURN jsonb_build_object('error', 'permission_denied');
  END IF;

  IF char_length(trim(p_code)) < 2 THEN
    RETURN jsonb_build_object('error', 'code_too_short');
  END IF;
  IF char_length(trim(p_display_name)) < 3 THEN
    RETURN jsonb_build_object('error', 'name_too_short');
  END IF;

  INSERT INTO onb_templates (tenant_id, code, display_name, description, suggested_duration_days, created_by)
  VALUES (v_tenant, upper(trim(p_code)), trim(p_display_name), p_description, p_suggested_duration_days, v_caller)
  RETURNING id INTO v_id;

  RETURN jsonb_build_object('ok', TRUE, 'template_id', v_id);
EXCEPTION WHEN unique_violation THEN
  RETURN jsonb_build_object('error', 'code_already_exists');
END;
$$;

-- ----- rpc_onb_template_update -----
CREATE OR REPLACE FUNCTION rpc_onb_template_update(
  p_template_id UUID,
  p_display_name VARCHAR DEFAULT NULL,
  p_description TEXT DEFAULT NULL,
  p_suggested_duration_days INT DEFAULT NULL,
  p_status onboarding_template_status DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_tenant UUID;
  v_template_tenant UUID;
BEGIN
  v_tenant := current_tenant_id();
  IF current_user_id() IS NULL OR v_tenant IS NULL THEN
    RETURN jsonb_build_object('error', 'not_authenticated');
  END IF;

  -- Sessao A1 · check de modulo ativo
  IF NOT module_is_active_for_me('onboarding') THEN
    RETURN jsonb_build_object('error', 'module_inactive', 'module', 'onboarding');
  END IF;

  IF NOT user_has_permission('manage_onboarding') THEN
    RETURN jsonb_build_object('error', 'permission_denied');
  END IF;

  SELECT tenant_id INTO v_template_tenant FROM onb_templates WHERE id = p_template_id;
  IF v_template_tenant IS NULL THEN
    RETURN jsonb_build_object('error', 'template_not_found');
  END IF;
  IF v_template_tenant <> v_tenant THEN
    RETURN jsonb_build_object('error', 'cross_tenant_blocked');
  END IF;

  UPDATE onb_templates SET
    display_name = COALESCE(trim(p_display_name), display_name),
    description = CASE WHEN p_description IS NULL THEN description ELSE p_description END,
    suggested_duration_days = COALESCE(p_suggested_duration_days, suggested_duration_days),
    status = COALESCE(p_status, status)
  WHERE id = p_template_id;

  RETURN jsonb_build_object('ok', TRUE);
END;
$$;

-- ----- rpc_onb_template_stage_add -----
CREATE OR REPLACE FUNCTION rpc_onb_template_stage_add(
  p_template_id UUID,
  p_display_name VARCHAR,
  p_description TEXT DEFAULT NULL,
  p_offset_days_start INT DEFAULT 0,
  p_duration_days INT DEFAULT 7
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_tenant UUID;
  v_template_tenant UUID;
  v_stage_id UUID;
  v_next_order INT;
BEGIN
  v_tenant := current_tenant_id();
  IF current_user_id() IS NULL OR v_tenant IS NULL THEN
    RETURN jsonb_build_object('error', 'not_authenticated');
  END IF;

  -- Sessao A1 · check de modulo ativo
  IF NOT module_is_active_for_me('onboarding') THEN
    RETURN jsonb_build_object('error', 'module_inactive', 'module', 'onboarding');
  END IF;
  IF NOT user_has_permission('manage_onboarding') THEN
    RETURN jsonb_build_object('error', 'permission_denied');
  END IF;

  SELECT tenant_id INTO v_template_tenant FROM onb_templates WHERE id = p_template_id;
  IF v_template_tenant IS NULL THEN
    RETURN jsonb_build_object('error', 'template_not_found');
  END IF;
  IF v_template_tenant <> v_tenant THEN
    RETURN jsonb_build_object('error', 'cross_tenant_blocked');
  END IF;

  SELECT COALESCE(MAX(display_order), 0) + 1 INTO v_next_order
  FROM onb_template_stages WHERE template_id = p_template_id;

  INSERT INTO onb_template_stages (
    tenant_id, template_id, display_name, description,
    display_order, offset_days_start, duration_days
  ) VALUES (
    v_tenant, p_template_id, trim(p_display_name), p_description,
    v_next_order, p_offset_days_start, p_duration_days
  )
  RETURNING id INTO v_stage_id;

  RETURN jsonb_build_object('ok', TRUE, 'stage_id', v_stage_id);
END;
$$;

-- ----- rpc_onb_template_task_add -----
CREATE OR REPLACE FUNCTION rpc_onb_template_task_add(
  p_stage_id UUID,
  p_title VARCHAR,
  p_description TEXT DEFAULT NULL,
  p_kind onboarding_task_kind DEFAULT 'task',
  p_offset_days INT DEFAULT 0,
  p_is_required BOOLEAN DEFAULT TRUE
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_tenant UUID;
  v_stage_tenant UUID;
  v_template_id UUID;
  v_task_id UUID;
  v_next_order INT;
BEGIN
  v_tenant := current_tenant_id();
  IF current_user_id() IS NULL OR v_tenant IS NULL THEN
    RETURN jsonb_build_object('error', 'not_authenticated');
  END IF;

  -- Sessao A1 · check de modulo ativo
  IF NOT module_is_active_for_me('onboarding') THEN
    RETURN jsonb_build_object('error', 'module_inactive', 'module', 'onboarding');
  END IF;
  IF NOT user_has_permission('manage_onboarding') THEN
    RETURN jsonb_build_object('error', 'permission_denied');
  END IF;

  SELECT tenant_id, template_id INTO v_stage_tenant, v_template_id
  FROM onb_template_stages WHERE id = p_stage_id;
  IF v_stage_tenant IS NULL THEN
    RETURN jsonb_build_object('error', 'stage_not_found');
  END IF;
  IF v_stage_tenant <> v_tenant THEN
    RETURN jsonb_build_object('error', 'cross_tenant_blocked');
  END IF;

  IF char_length(trim(p_title)) < 3 THEN
    RETURN jsonb_build_object('error', 'title_too_short');
  END IF;

  SELECT COALESCE(MAX(display_order), 0) + 1 INTO v_next_order
  FROM onb_template_tasks WHERE stage_id = p_stage_id;

  INSERT INTO onb_template_tasks (
    tenant_id, template_id, stage_id, title, description, kind,
    offset_days, is_required, display_order
  ) VALUES (
    v_tenant, v_template_id, p_stage_id, trim(p_title), p_description, p_kind,
    p_offset_days, p_is_required, v_next_order
  )
  RETURNING id INTO v_task_id;

  RETURN jsonb_build_object('ok', TRUE, 'task_id', v_task_id);
END;
$$;

-- ----- rpc_onb_template_list -----
CREATE OR REPLACE FUNCTION rpc_onb_template_list()
RETURNS JSONB
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_tenant UUID;
  v_items JSONB;
BEGIN
  v_tenant := current_tenant_id();
  IF v_tenant IS NULL THEN
    RETURN jsonb_build_object('error', 'not_authenticated');
  END IF;

  -- Sessao A1 · check de modulo ativo
  IF NOT module_is_active_for_me('onboarding') THEN
    RETURN jsonb_build_object('error', 'module_inactive', 'module', 'onboarding');
  END IF;
  IF NOT (user_has_permission('view_onboarding') OR user_has_permission('manage_onboarding')) THEN
    RETURN jsonb_build_object('error', 'permission_denied');
  END IF;

  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'id', t.id,
    'code', t.code,
    'display_name', t.display_name,
    'description', t.description,
    'suggested_duration_days', t.suggested_duration_days,
    'status', t.status,
    'stages_count', (SELECT count(*) FROM onb_template_stages WHERE template_id = t.id),
    'tasks_count', (SELECT count(*) FROM onb_template_tasks WHERE template_id = t.id),
    'updated_at', t.updated_at
  ) ORDER BY t.updated_at DESC), '[]'::jsonb) INTO v_items
  FROM onb_templates t WHERE t.tenant_id = v_tenant;

  RETURN jsonb_build_object('ok', TRUE, 'items', v_items);
END;
$$;

-- ----- rpc_onb_template_get -----
CREATE OR REPLACE FUNCTION rpc_onb_template_get(p_template_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_tenant UUID;
  v_tpl JSONB;
  v_stages JSONB;
BEGIN
  v_tenant := current_tenant_id();
  IF v_tenant IS NULL THEN
    RETURN jsonb_build_object('error', 'not_authenticated');
  END IF;

  -- Sessao A1 · check de modulo ativo
  IF NOT module_is_active_for_me('onboarding') THEN
    RETURN jsonb_build_object('error', 'module_inactive', 'module', 'onboarding');
  END IF;
  IF NOT (user_has_permission('view_onboarding') OR user_has_permission('manage_onboarding')) THEN
    RETURN jsonb_build_object('error', 'permission_denied');
  END IF;

  SELECT jsonb_build_object(
    'id', t.id,
    'code', t.code,
    'display_name', t.display_name,
    'description', t.description,
    'suggested_duration_days', t.suggested_duration_days,
    'status', t.status,
    'created_at', t.created_at,
    'updated_at', t.updated_at
  ) INTO v_tpl
  FROM onb_templates t WHERE t.id = p_template_id AND t.tenant_id = v_tenant;

  IF v_tpl IS NULL THEN
    RETURN jsonb_build_object('error', 'template_not_found');
  END IF;

  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'id', s.id,
    'display_name', s.display_name,
    'description', s.description,
    'display_order', s.display_order,
    'offset_days_start', s.offset_days_start,
    'duration_days', s.duration_days,
    'tasks', (
      SELECT COALESCE(jsonb_agg(jsonb_build_object(
        'id', tk.id,
        'title', tk.title,
        'description', tk.description,
        'kind', tk.kind,
        'offset_days', tk.offset_days,
        'is_required', tk.is_required,
        'display_order', tk.display_order
      ) ORDER BY tk.display_order), '[]'::jsonb)
      FROM onb_template_tasks tk WHERE tk.stage_id = s.id
    )
  ) ORDER BY s.display_order), '[]'::jsonb) INTO v_stages
  FROM onb_template_stages s WHERE s.template_id = p_template_id;

  RETURN jsonb_build_object('ok', TRUE, 'template', v_tpl, 'stages', v_stages);
END;
$$;

-- ----- rpc_onboarding_create_from_template -----
CREATE OR REPLACE FUNCTION rpc_onboarding_create_from_template(
  p_user_id UUID,
  p_template_id UUID,
  p_display_name VARCHAR,
  p_start_date DATE,
  p_notes TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_caller UUID;
  v_tenant UUID;
  v_target_tenant UUID;
  v_target_manager UUID;
  v_template_tenant UUID;
  v_template_status onboarding_template_status;
  v_template_duration INT;
  v_onb_id UUID;
  v_target_end_date DATE;
  r_stage RECORD;
  r_task RECORD;
  v_new_stage_id UUID;
  v_stage_start DATE;
  v_stage_end DATE;
  v_task_due DATE;
BEGIN
  v_caller := current_user_id();
  v_tenant := current_tenant_id();

  IF v_caller IS NULL OR v_tenant IS NULL THEN
    RETURN jsonb_build_object('error', 'not_authenticated');
  END IF;

  -- Sessao A1 · check de modulo ativo
  IF NOT module_is_active_for_me('onboarding') THEN
    RETURN jsonb_build_object('error', 'module_inactive', 'module', 'onboarding');
  END IF;

  IF NOT user_has_permission('manage_onboarding') THEN
    RETURN jsonb_build_object('error', 'permission_denied');
  END IF;

  -- Valida user alvo (mesmo tenant, ativo)
  SELECT tenant_id, manager_id INTO v_target_tenant, v_target_manager
  FROM app_users WHERE id = p_user_id AND active = TRUE;
  IF v_target_tenant IS NULL THEN
    RETURN jsonb_build_object('error', 'user_not_found');
  END IF;
  IF v_target_tenant <> v_tenant THEN
    RETURN jsonb_build_object('error', 'cross_tenant_blocked');
  END IF;

  -- Valida template
  SELECT tenant_id, status, suggested_duration_days
  INTO v_template_tenant, v_template_status, v_template_duration
  FROM onb_templates WHERE id = p_template_id;
  IF v_template_tenant IS NULL THEN
    RETURN jsonb_build_object('error', 'template_not_found');
  END IF;
  IF v_template_tenant <> v_tenant THEN
    RETURN jsonb_build_object('error', 'cross_tenant_blocked');
  END IF;
  IF v_template_status = 'archived' THEN
    RETURN jsonb_build_object('error', 'template_archived');
  END IF;

  v_target_end_date := p_start_date + (v_template_duration || ' days')::INTERVAL;

  -- Cria onboarding raiz
  INSERT INTO onboardings (
    tenant_id, user_id, manager_id_snapshot, source_template_id,
    display_name, notes, start_date, target_end_date, created_by
  ) VALUES (
    v_tenant, p_user_id, v_target_manager, p_template_id,
    trim(p_display_name), p_notes, p_start_date, v_target_end_date, v_caller
  )
  RETURNING id INTO v_onb_id;

  -- Deep copy: stages
  FOR r_stage IN
    SELECT * FROM onb_template_stages
    WHERE template_id = p_template_id
    ORDER BY display_order
  LOOP
    v_stage_start := p_start_date + (r_stage.offset_days_start || ' days')::INTERVAL;
    v_stage_end := v_stage_start + (r_stage.duration_days || ' days')::INTERVAL;

    INSERT INTO onboarding_stages (
      tenant_id, onboarding_id, display_name, description,
      display_order, start_date, target_end_date
    ) VALUES (
      v_tenant, v_onb_id, r_stage.display_name, r_stage.description,
      r_stage.display_order, v_stage_start, v_stage_end
    )
    RETURNING id INTO v_new_stage_id;

    -- Deep copy: tasks da stage
    FOR r_task IN
      SELECT * FROM onb_template_tasks
      WHERE stage_id = r_stage.id
      ORDER BY display_order
    LOOP
      v_task_due := v_stage_start + (r_task.offset_days || ' days')::INTERVAL;

      INSERT INTO onboarding_tasks (
        tenant_id, onboarding_id, stage_id, title, description, kind,
        due_date, is_required, display_order
      ) VALUES (
        v_tenant, v_onb_id, v_new_stage_id, r_task.title, r_task.description, r_task.kind,
        v_task_due, r_task.is_required, r_task.display_order
      );
    END LOOP;
  END LOOP;

  RETURN jsonb_build_object('ok', TRUE, 'onboarding_id', v_onb_id);
EXCEPTION WHEN unique_violation THEN
  RETURN jsonb_build_object('error', 'user_already_has_active_onboarding');
END;
$$;

-- ----- rpc_onboarding_create_blank -----
CREATE OR REPLACE FUNCTION rpc_onboarding_create_blank(
  p_user_id UUID,
  p_display_name VARCHAR,
  p_start_date DATE,
  p_target_end_date DATE,
  p_notes TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_caller UUID;
  v_tenant UUID;
  v_target_tenant UUID;
  v_target_manager UUID;
  v_onb_id UUID;
BEGIN
  v_caller := current_user_id();
  v_tenant := current_tenant_id();

  IF v_caller IS NULL OR v_tenant IS NULL THEN
    RETURN jsonb_build_object('error', 'not_authenticated');
  END IF;

  -- Sessao A1 · check de modulo ativo
  IF NOT module_is_active_for_me('onboarding') THEN
    RETURN jsonb_build_object('error', 'module_inactive', 'module', 'onboarding');
  END IF;
  IF NOT user_has_permission('manage_onboarding') THEN
    RETURN jsonb_build_object('error', 'permission_denied');
  END IF;

  SELECT tenant_id, manager_id INTO v_target_tenant, v_target_manager
  FROM app_users WHERE id = p_user_id AND active = TRUE;
  IF v_target_tenant IS NULL THEN
    RETURN jsonb_build_object('error', 'user_not_found');
  END IF;
  IF v_target_tenant <> v_tenant THEN
    RETURN jsonb_build_object('error', 'cross_tenant_blocked');
  END IF;

  IF p_target_end_date < p_start_date THEN
    RETURN jsonb_build_object('error', 'end_before_start');
  END IF;

  INSERT INTO onboardings (
    tenant_id, user_id, manager_id_snapshot, source_template_id,
    display_name, notes, start_date, target_end_date, created_by
  ) VALUES (
    v_tenant, p_user_id, v_target_manager, NULL,
    trim(p_display_name), p_notes, p_start_date, p_target_end_date, v_caller
  )
  RETURNING id INTO v_onb_id;

  RETURN jsonb_build_object('ok', TRUE, 'onboarding_id', v_onb_id);
EXCEPTION WHEN unique_violation THEN
  RETURN jsonb_build_object('error', 'user_already_has_active_onboarding');
END;
$$;

-- ----- rpc_onboarding_stage_add -----
CREATE OR REPLACE FUNCTION rpc_onboarding_stage_add(
  p_onboarding_id UUID,
  p_display_name VARCHAR,
  p_description TEXT DEFAULT NULL,
  p_start_date DATE DEFAULT NULL,
  p_target_end_date DATE DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_tenant UUID;
  v_onb_tenant UUID;
  v_status onboarding_status;
  v_stage_id UUID;
  v_next_order INT;
BEGIN
  v_tenant := current_tenant_id();
  IF current_user_id() IS NULL OR v_tenant IS NULL THEN
    RETURN jsonb_build_object('error', 'not_authenticated');
  END IF;

  -- Sessao A1 · check de modulo ativo
  IF NOT module_is_active_for_me('onboarding') THEN
    RETURN jsonb_build_object('error', 'module_inactive', 'module', 'onboarding');
  END IF;
  IF NOT user_has_permission('manage_onboarding') THEN
    RETURN jsonb_build_object('error', 'permission_denied');
  END IF;

  SELECT tenant_id, status INTO v_onb_tenant, v_status
  FROM onboardings WHERE id = p_onboarding_id;
  IF v_onb_tenant IS NULL THEN
    RETURN jsonb_build_object('error', 'onboarding_not_found');
  END IF;
  IF v_onb_tenant <> v_tenant THEN
    RETURN jsonb_build_object('error', 'cross_tenant_blocked');
  END IF;
  IF v_status IN ('completed', 'canceled') THEN
    RETURN jsonb_build_object('error', 'onboarding_locked');
  END IF;

  SELECT COALESCE(MAX(display_order), 0) + 1 INTO v_next_order
  FROM onboarding_stages WHERE onboarding_id = p_onboarding_id;

  INSERT INTO onboarding_stages (
    tenant_id, onboarding_id, display_name, description,
    display_order, start_date, target_end_date
  ) VALUES (
    v_tenant, p_onboarding_id, trim(p_display_name), p_description,
    v_next_order, p_start_date, p_target_end_date
  )
  RETURNING id INTO v_stage_id;

  RETURN jsonb_build_object('ok', TRUE, 'stage_id', v_stage_id);
END;
$$;

-- ----- rpc_onboarding_task_add -----
CREATE OR REPLACE FUNCTION rpc_onboarding_task_add(
  p_stage_id UUID,
  p_title VARCHAR,
  p_description TEXT DEFAULT NULL,
  p_kind onboarding_task_kind DEFAULT 'task',
  p_due_date DATE DEFAULT NULL,
  p_is_required BOOLEAN DEFAULT TRUE
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_tenant UUID;
  v_stage_tenant UUID;
  v_onb_id UUID;
  v_status onboarding_status;
  v_task_id UUID;
  v_next_order INT;
BEGIN
  v_tenant := current_tenant_id();
  IF current_user_id() IS NULL OR v_tenant IS NULL THEN
    RETURN jsonb_build_object('error', 'not_authenticated');
  END IF;

  -- Sessao A1 · check de modulo ativo
  IF NOT module_is_active_for_me('onboarding') THEN
    RETURN jsonb_build_object('error', 'module_inactive', 'module', 'onboarding');
  END IF;
  IF NOT user_has_permission('manage_onboarding') THEN
    RETURN jsonb_build_object('error', 'permission_denied');
  END IF;

  SELECT s.tenant_id, s.onboarding_id, o.status
  INTO v_stage_tenant, v_onb_id, v_status
  FROM onboarding_stages s JOIN onboardings o ON o.id = s.onboarding_id
  WHERE s.id = p_stage_id;

  IF v_stage_tenant IS NULL THEN
    RETURN jsonb_build_object('error', 'stage_not_found');
  END IF;
  IF v_stage_tenant <> v_tenant THEN
    RETURN jsonb_build_object('error', 'cross_tenant_blocked');
  END IF;
  IF v_status IN ('completed', 'canceled') THEN
    RETURN jsonb_build_object('error', 'onboarding_locked');
  END IF;

  IF char_length(trim(p_title)) < 3 THEN
    RETURN jsonb_build_object('error', 'title_too_short');
  END IF;

  SELECT COALESCE(MAX(display_order), 0) + 1 INTO v_next_order
  FROM onboarding_tasks WHERE stage_id = p_stage_id;

  INSERT INTO onboarding_tasks (
    tenant_id, onboarding_id, stage_id, title, description, kind,
    due_date, is_required, display_order
  ) VALUES (
    v_tenant, v_onb_id, p_stage_id, trim(p_title), p_description, p_kind,
    p_due_date, p_is_required, v_next_order
  )
  RETURNING id INTO v_task_id;

  RETURN jsonb_build_object('ok', TRUE, 'task_id', v_task_id);
END;
$$;

-- ----- rpc_onboarding_task_complete -----
CREATE OR REPLACE FUNCTION rpc_onboarding_task_complete(
  p_task_id UUID,
  p_completion_note TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_caller UUID;
  v_tenant UUID;
  v_task_tenant UUID;
  v_onb_id UUID;
  v_owner UUID;
  v_status onboarding_status;
  v_task_status onboarding_task_status;
BEGIN
  v_caller := current_user_id();
  v_tenant := current_tenant_id();
  IF v_caller IS NULL OR v_tenant IS NULL THEN
    RETURN jsonb_build_object('error', 'not_authenticated');
  END IF;

  -- Sessao A1 · check de modulo ativo
  IF NOT module_is_active_for_me('onboarding') THEN
    RETURN jsonb_build_object('error', 'module_inactive', 'module', 'onboarding');
  END IF;

  SELECT t.tenant_id, t.onboarding_id, t.status, o.user_id, o.status
  INTO v_task_tenant, v_onb_id, v_task_status, v_owner, v_status
  FROM onboarding_tasks t JOIN onboardings o ON o.id = t.onboarding_id
  WHERE t.id = p_task_id;

  IF v_task_tenant IS NULL THEN
    RETURN jsonb_build_object('error', 'task_not_found');
  END IF;
  IF v_task_tenant <> v_tenant THEN
    RETURN jsonb_build_object('error', 'cross_tenant_blocked');
  END IF;
  IF v_status IN ('completed', 'canceled') THEN
    RETURN jsonb_build_object('error', 'onboarding_locked');
  END IF;

  -- Permissao: owner OR RH/Diretoria
  IF NOT (v_owner = v_caller OR user_has_permission('manage_onboarding')) THEN
    RETURN jsonb_build_object('error', 'permission_denied');
  END IF;

  IF v_task_status = 'completed' THEN
    RETURN jsonb_build_object('error', 'already_completed');
  END IF;

  UPDATE onboarding_tasks SET
    status = 'completed',
    completion_note = p_completion_note
  WHERE id = p_task_id;

  -- Auto-iniciar onboarding na primeira task concluida
  UPDATE onboardings SET status = 'in_progress'
  WHERE id = v_onb_id AND status = 'not_started';

  RETURN jsonb_build_object('ok', TRUE);
END;
$$;

-- ----- rpc_onboarding_task_uncomplete -----
CREATE OR REPLACE FUNCTION rpc_onboarding_task_uncomplete(
  p_task_id UUID
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_caller UUID;
  v_tenant UUID;
  v_task_tenant UUID;
  v_owner UUID;
  v_status onboarding_status;
BEGIN
  v_caller := current_user_id();
  v_tenant := current_tenant_id();
  IF v_caller IS NULL OR v_tenant IS NULL THEN
    RETURN jsonb_build_object('error', 'not_authenticated');
  END IF;

  -- Sessao A1 · check de modulo ativo
  IF NOT module_is_active_for_me('onboarding') THEN
    RETURN jsonb_build_object('error', 'module_inactive', 'module', 'onboarding');
  END IF;

  SELECT t.tenant_id, o.user_id, o.status
  INTO v_task_tenant, v_owner, v_status
  FROM onboarding_tasks t JOIN onboardings o ON o.id = t.onboarding_id
  WHERE t.id = p_task_id;

  IF v_task_tenant IS NULL THEN
    RETURN jsonb_build_object('error', 'task_not_found');
  END IF;
  IF v_task_tenant <> v_tenant THEN
    RETURN jsonb_build_object('error', 'cross_tenant_blocked');
  END IF;
  IF v_status IN ('completed', 'canceled') THEN
    RETURN jsonb_build_object('error', 'onboarding_locked');
  END IF;

  IF NOT (v_owner = v_caller OR user_has_permission('manage_onboarding')) THEN
    RETURN jsonb_build_object('error', 'permission_denied');
  END IF;

  UPDATE onboarding_tasks SET
    status = 'pending',
    completion_note = NULL
  WHERE id = p_task_id;

  RETURN jsonb_build_object('ok', TRUE);
END;
$$;

-- ----- rpc_onboarding_change_status -----
CREATE OR REPLACE FUNCTION rpc_onboarding_change_status(
  p_onboarding_id UUID,
  p_new_status onboarding_status,
  p_cancel_reason TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_tenant UUID;
  v_onb_tenant UUID;
  v_old_status onboarding_status;
  v_required INT;
  v_required_done INT;
BEGIN
  v_tenant := current_tenant_id();
  IF current_user_id() IS NULL OR v_tenant IS NULL THEN
    RETURN jsonb_build_object('error', 'not_authenticated');
  END IF;

  -- Sessao A1 · check de modulo ativo
  IF NOT module_is_active_for_me('onboarding') THEN
    RETURN jsonb_build_object('error', 'module_inactive', 'module', 'onboarding');
  END IF;
  IF NOT user_has_permission('manage_onboarding') THEN
    RETURN jsonb_build_object('error', 'permission_denied');
  END IF;

  SELECT tenant_id, status, tasks_required, tasks_required_done
  INTO v_onb_tenant, v_old_status, v_required, v_required_done
  FROM onboardings WHERE id = p_onboarding_id;
  IF v_onb_tenant IS NULL THEN
    RETURN jsonb_build_object('error', 'onboarding_not_found');
  END IF;
  IF v_onb_tenant <> v_tenant THEN
    RETURN jsonb_build_object('error', 'cross_tenant_blocked');
  END IF;

  IF v_old_status = p_new_status THEN
    RETURN jsonb_build_object('error', 'no_change');
  END IF;

  IF v_old_status IN ('completed', 'canceled') THEN
    RETURN jsonb_build_object('error', 'onboarding_locked');
  END IF;

  -- Transicoes validas:
  --   not_started -> in_progress, canceled
  --   in_progress -> completed, canceled
  IF v_old_status = 'not_started' AND p_new_status NOT IN ('in_progress', 'canceled') THEN
    RETURN jsonb_build_object('error', 'invalid_transition');
  END IF;
  IF v_old_status = 'in_progress' AND p_new_status NOT IN ('completed', 'canceled') THEN
    RETURN jsonb_build_object('error', 'invalid_transition');
  END IF;

  -- Para concluir, todas as required precisam estar done
  IF p_new_status = 'completed' AND v_required > v_required_done THEN
    RETURN jsonb_build_object('error', 'required_tasks_pending',
      'pending', v_required - v_required_done);
  END IF;

  IF p_new_status = 'canceled' AND (p_cancel_reason IS NULL OR char_length(trim(p_cancel_reason)) < 3) THEN
    RETURN jsonb_build_object('error', 'cancel_reason_required');
  END IF;

  UPDATE onboardings SET
    status = p_new_status,
    cancel_reason = CASE WHEN p_new_status = 'canceled' THEN trim(p_cancel_reason) ELSE cancel_reason END
  WHERE id = p_onboarding_id;

  RETURN jsonb_build_object('ok', TRUE, 'status', p_new_status);
END;
$$;

-- ----- rpc_onboarding_list -----
CREATE OR REPLACE FUNCTION rpc_onboarding_list(
  p_scope TEXT DEFAULT 'own',
  p_status onboarding_status DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_caller UUID;
  v_tenant UUID;
  v_items JSONB;
BEGIN
  v_caller := current_user_id();
  v_tenant := current_tenant_id();
  IF v_caller IS NULL OR v_tenant IS NULL THEN
    RETURN jsonb_build_object('error', 'not_authenticated');
  END IF;

  -- Sessao A1 · check de modulo ativo
  IF NOT module_is_active_for_me('onboarding') THEN
    RETURN jsonb_build_object('error', 'module_inactive', 'module', 'onboarding');
  END IF;

  IF p_scope = 'all' AND NOT (user_has_permission('view_onboarding') OR user_has_permission('manage_onboarding')) THEN
    RETURN jsonb_build_object('error', 'permission_denied');
  END IF;

  SELECT COALESCE(jsonb_agg(item ORDER BY (item->>'created_at') DESC), '[]'::jsonb) INTO v_items
  FROM (
    SELECT jsonb_build_object(
      'id', o.id,
      'user_id', o.user_id,
      'user_name', u.full_name,
      'user_job_title', u.job_title,
      'display_name', o.display_name,
      'status', o.status,
      'start_date', o.start_date,
      'target_end_date', o.target_end_date,
      'tasks_total', o.tasks_total,
      'tasks_completed', o.tasks_completed,
      'tasks_required', o.tasks_required,
      'tasks_required_done', o.tasks_required_done,
      'progress_percent', CASE WHEN o.tasks_total > 0
        THEN round((o.tasks_completed::NUMERIC / o.tasks_total) * 100)
        ELSE 0 END,
      'manager_id', o.manager_id_snapshot,
      'manager_name', mg.full_name,
      'source_template_id', o.source_template_id,
      'source_template_name', tpl.display_name,
      'created_at', o.created_at
    ) AS item
    FROM onboardings o
    JOIN app_users u ON u.id = o.user_id
    LEFT JOIN app_users mg ON mg.id = o.manager_id_snapshot
    LEFT JOIN onb_templates tpl ON tpl.id = o.source_template_id
    WHERE o.tenant_id = v_tenant
      AND (p_status IS NULL OR o.status = p_status)
      AND (
        p_scope = 'own' AND o.user_id = v_caller
        OR p_scope = 'team' AND (o.user_id = v_caller OR user_is_manager_of(o.user_id) = TRUE)
        OR p_scope = 'all'
      )
  ) sub;

  RETURN jsonb_build_object('ok', TRUE, 'items', v_items);
END;
$$;

-- ----- rpc_onboarding_get_by_id -----
CREATE OR REPLACE FUNCTION rpc_onboarding_get_by_id(p_onboarding_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_onb JSONB;
  v_stages JSONB;
BEGIN
  IF current_user_id() IS NULL THEN
    RETURN jsonb_build_object('error', 'not_authenticated');
  END IF;

  -- Sessao A1 · check de modulo ativo
  IF NOT module_is_active_for_me('onboarding') THEN
    RETURN jsonb_build_object('error', 'module_inactive', 'module', 'onboarding');
  END IF;

  IF NOT onboarding_can_read(p_onboarding_id) THEN
    RETURN jsonb_build_object('error', 'permission_denied');
  END IF;

  SELECT jsonb_build_object(
    'id', o.id,
    'tenant_id', o.tenant_id,
    'user_id', o.user_id,
    'user_name', u.full_name,
    'user_job_title', u.job_title,
    'user_avatar_url', u.avatar_url,
    'display_name', o.display_name,
    'notes', o.notes,
    'status', o.status,
    'start_date', o.start_date,
    'target_end_date', o.target_end_date,
    'tasks_total', o.tasks_total,
    'tasks_completed', o.tasks_completed,
    'tasks_required', o.tasks_required,
    'tasks_required_done', o.tasks_required_done,
    'progress_percent', CASE WHEN o.tasks_total > 0
      THEN round((o.tasks_completed::NUMERIC / o.tasks_total) * 100)
      ELSE 0 END,
    'manager_id', o.manager_id_snapshot,
    'manager_name', mg.full_name,
    'source_template_id', o.source_template_id,
    'source_template_name', tpl.display_name,
    'cancel_reason', o.cancel_reason,
    'started_at', o.started_at,
    'completed_at', o.completed_at,
    'canceled_at', o.canceled_at,
    'created_by', o.created_by,
    'created_at', o.created_at,
    'updated_at', o.updated_at
  ) INTO v_onb
  FROM onboardings o
  JOIN app_users u ON u.id = o.user_id
  LEFT JOIN app_users mg ON mg.id = o.manager_id_snapshot
  LEFT JOIN onb_templates tpl ON tpl.id = o.source_template_id
  WHERE o.id = p_onboarding_id;

  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'id', s.id,
    'display_name', s.display_name,
    'description', s.description,
    'display_order', s.display_order,
    'start_date', s.start_date,
    'target_end_date', s.target_end_date,
    'tasks', (
      SELECT COALESCE(jsonb_agg(jsonb_build_object(
        'id', t.id,
        'title', t.title,
        'description', t.description,
        'kind', t.kind,
        'due_date', t.due_date,
        'is_required', t.is_required,
        'status', t.status,
        'display_order', t.display_order,
        'completed_at', t.completed_at,
        'completed_by', t.completed_by,
        'completion_note', t.completion_note
      ) ORDER BY t.display_order), '[]'::jsonb)
      FROM onboarding_tasks t WHERE t.stage_id = s.id
    )
  ) ORDER BY s.display_order), '[]'::jsonb) INTO v_stages
  FROM onboarding_stages s WHERE s.onboarding_id = p_onboarding_id;

  RETURN jsonb_build_object('ok', TRUE, 'onboarding', v_onb, 'stages', v_stages);
END;
$$;


-- ============================================================================
-- VALIDACAO POS-PATCH (manual)
-- ============================================================================
-- SELECT count(*) FROM pg_proc WHERE proname LIKE 'rpc_recognition_%';  -- 6
-- SELECT count(*) FROM pg_proc WHERE proname LIKE 'rpc_pdi_%';          -- 10
-- SELECT count(*) FROM pg_proc WHERE proname LIKE 'rpc_onb%';           -- 15
-- SELECT count(*) FROM pg_proc WHERE proname LIKE 'rpc_onboarding_%';   -- (subset)
--
-- Teste rapido (com tenant sem modulo recognition ativo):
--   SELECT rpc_recognition_create('<recipient_uuid>', 'teste');
--   --> Esperado: {"error": "module_inactive", "module": "recognition"}
-- ============================================================================

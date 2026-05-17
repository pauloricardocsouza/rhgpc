-- ============================================================================
-- R2 People · Schema Recognition v1
-- ============================================================================
-- Modulo de reconhecimentos peer-to-peer
--
-- Decisoes da Sessao H2:
--   - Mensagem livre (nao categoriza por valor da empresa)
--   - 1 sender + 1 recipient (sem multi-destinatario)
--   - So reacoes (5 emojis), sem comentarios
--   - Publico + flag is_private para visibilidade restrita
--   - Sem pontos/moeda/saldo
--
-- Pre-requisitos:
--   - r2_people_schema_base_v1.sql aplicado
--   - r2_people_seed_base_v1.sql aplicado
--
-- Ordem de aplicacao:
--   1. r2_people_schema_recognition_v1.sql       (este arquivo)
--   2. r2_people_seed_recognition_v1.sql         (permissoes adicionais)
--   3. r2_people_rls_policies_recognition_tests.sql (opcional)
-- ============================================================================

-- ============================================================================
-- ENUMS
-- ============================================================================

DO $$ BEGIN
  CREATE TYPE recognition_reaction_kind AS ENUM ('clap', 'heart', 'celebrate', 'strong', 'star');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  CREATE TYPE recognition_report_status AS ENUM ('pending', 'resolved_hidden', 'resolved_kept', 'dismissed');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- ============================================================================
-- TABELAS
-- ============================================================================

-- Post de reconhecimento
CREATE TABLE IF NOT EXISTS recognitions (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id       UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,

  sender_id       UUID NOT NULL REFERENCES app_users(id) ON DELETE CASCADE,
  recipient_id    UUID NOT NULL REFERENCES app_users(id) ON DELETE CASCADE,

  message         TEXT NOT NULL,

  -- Visibilidade
  is_private      BOOLEAN NOT NULL DEFAULT FALSE,

  -- Moderacao · sem CASCADE para preservar registro do moderador apos deactivation
  hidden_at       TIMESTAMPTZ,
  hidden_by       UUID REFERENCES app_users(id) ON DELETE SET NULL,
  hidden_reason   TEXT,

  -- Snapshot de denormalizacao para o feed (atualizado por trigger)
  reactions_count INT NOT NULL DEFAULT 0,
  reports_count   INT NOT NULL DEFAULT 0,

  created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT now(),

  CONSTRAINT recognition_no_self CHECK (sender_id <> recipient_id),
  CONSTRAINT recognition_message_length CHECK (char_length(message) BETWEEN 3 AND 1000)
);

CREATE INDEX IF NOT EXISTS idx_recognitions_tenant ON recognitions(tenant_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_recognitions_recipient ON recognitions(recipient_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_recognitions_sender ON recognitions(sender_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_recognitions_visible ON recognitions(tenant_id, hidden_at, created_at DESC) WHERE hidden_at IS NULL;

-- Reacoes (1 por usuario por post · troca o emoji em UPSERT)
CREATE TABLE IF NOT EXISTS recognition_reactions (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id       UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,

  recognition_id  UUID NOT NULL REFERENCES recognitions(id) ON DELETE CASCADE,
  user_id         UUID NOT NULL REFERENCES app_users(id) ON DELETE CASCADE,

  kind            recognition_reaction_kind NOT NULL,

  created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),

  UNIQUE (recognition_id, user_id)
);

CREATE INDEX IF NOT EXISTS idx_recog_reactions_post ON recognition_reactions(recognition_id);
CREATE INDEX IF NOT EXISTS idx_recog_reactions_user ON recognition_reactions(user_id);

-- Denuncias de conteudo
CREATE TABLE IF NOT EXISTS recognition_reports (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id       UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,

  recognition_id  UUID NOT NULL REFERENCES recognitions(id) ON DELETE CASCADE,
  reporter_id     UUID NOT NULL REFERENCES app_users(id) ON DELETE CASCADE,

  reason          TEXT NOT NULL,
  status          recognition_report_status NOT NULL DEFAULT 'pending',

  resolved_by     UUID REFERENCES app_users(id) ON DELETE SET NULL,
  resolved_at     TIMESTAMPTZ,
  resolution_notes TEXT,

  created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT now(),

  CONSTRAINT report_reason_length CHECK (char_length(reason) BETWEEN 3 AND 500),
  -- 1 denuncia por usuario por post
  UNIQUE (recognition_id, reporter_id)
);

CREATE INDEX IF NOT EXISTS idx_recog_reports_status ON recognition_reports(tenant_id, status, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_recog_reports_post ON recognition_reports(recognition_id);

-- ============================================================================
-- TRIGGERS
-- ============================================================================

-- updated_at automatico
DROP TRIGGER IF EXISTS trg_recognitions_updated_at ON recognitions;
CREATE TRIGGER trg_recognitions_updated_at BEFORE UPDATE ON recognitions
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

DROP TRIGGER IF EXISTS trg_recog_reports_updated_at ON recognition_reports;
CREATE TRIGGER trg_recog_reports_updated_at BEFORE UPDATE ON recognition_reports
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- Audit em recognitions (post pode ser hidden por moderacao · auditavel)
DROP TRIGGER IF EXISTS trg_audit_recognitions ON recognitions;
CREATE TRIGGER trg_audit_recognitions
  AFTER INSERT OR UPDATE OR DELETE ON recognitions
  FOR EACH ROW EXECUTE FUNCTION audit_change();

-- Audit em recognition_reports (decisoes de moderacao)
DROP TRIGGER IF EXISTS trg_audit_recog_reports ON recognition_reports;
CREATE TRIGGER trg_audit_recog_reports
  AFTER INSERT OR UPDATE OR DELETE ON recognition_reports
  FOR EACH ROW EXECUTE FUNCTION audit_change();

-- Trigger denormaliza reactions_count e reports_count em recognitions
CREATE OR REPLACE FUNCTION recognition_update_counts()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_post UUID;
BEGIN
  IF TG_OP = 'INSERT' THEN
    v_post := NEW.recognition_id;
  ELSIF TG_OP = 'DELETE' THEN
    v_post := OLD.recognition_id;
  ELSE
    v_post := NEW.recognition_id;
  END IF;

  IF TG_TABLE_NAME = 'recognition_reactions' THEN
    UPDATE recognitions
    SET reactions_count = (SELECT count(*) FROM recognition_reactions WHERE recognition_id = v_post)
    WHERE id = v_post;
  ELSIF TG_TABLE_NAME = 'recognition_reports' THEN
    UPDATE recognitions
    SET reports_count = (SELECT count(*) FROM recognition_reports WHERE recognition_id = v_post)
    WHERE id = v_post;
  END IF;

  IF TG_OP = 'DELETE' THEN
    RETURN OLD;
  ELSE
    RETURN NEW;
  END IF;
END;
$$;

DROP TRIGGER IF EXISTS trg_recog_reactions_count ON recognition_reactions;
CREATE TRIGGER trg_recog_reactions_count
  AFTER INSERT OR DELETE ON recognition_reactions
  FOR EACH ROW EXECUTE FUNCTION recognition_update_counts();

DROP TRIGGER IF EXISTS trg_recog_reports_count ON recognition_reports;
CREATE TRIGGER trg_recog_reports_count
  AFTER INSERT OR DELETE ON recognition_reports
  FOR EACH ROW EXECUTE FUNCTION recognition_update_counts();

-- ============================================================================
-- RPCs
-- ============================================================================

-- Cria reconhecimento
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

-- Adiciona/troca/remove reacao
-- Se p_kind = NULL · remove a reacao do usuario
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

-- Feed paginado · filtra automaticamente itens hidden e privados que o caller nao pode ver
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

-- KPIs · usado em /reconhecimentos para mostrar resumo do mes
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

-- Denuncia post · qualquer usuario do tenant pode denunciar
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

-- RH/Diretoria resolve denuncia · pode esconder o post
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
-- ROW-LEVEL SECURITY
-- ============================================================================

ALTER TABLE recognitions          ENABLE ROW LEVEL SECURITY;
ALTER TABLE recognition_reactions ENABLE ROW LEVEL SECURITY;
ALTER TABLE recognition_reports   ENABLE ROW LEVEL SECURITY;

-- ===== RECOGNITIONS =====
-- Read: tenant + nao-hidden + (publico OU eu sou parte OU rh/dir OU lider do recipient)
DROP POLICY IF EXISTS recognitions_visible_read ON recognitions;
CREATE POLICY recognitions_visible_read ON recognitions
  FOR SELECT
  USING (
    tenant_id = current_tenant_id()
    AND hidden_at IS NULL
    AND (
      is_private = FALSE
      OR recipient_id = current_user_id()
      OR sender_id = current_user_id()
      OR current_user_role() IN ('rh', 'diretoria')
      OR user_is_manager_of(recipient_id) = TRUE
    )
  );

-- RH/Diretoria leem hidden tambem (para revisar denuncias)
DROP POLICY IF EXISTS recognitions_rh_dir_read_all ON recognitions;
CREATE POLICY recognitions_rh_dir_read_all ON recognitions
  FOR SELECT
  USING (
    tenant_id = current_tenant_id()
    AND current_user_role() IN ('rh', 'diretoria')
  );

-- Insert: so via RPC (que e SECURITY DEFINER)
-- Update direto: so RH/Diretoria (para hide manual fora de denuncia)
DROP POLICY IF EXISTS recognitions_rh_dir_update ON recognitions;
CREATE POLICY recognitions_rh_dir_update ON recognitions
  FOR UPDATE
  USING (
    tenant_id = current_tenant_id()
    AND current_user_role() IN ('rh', 'diretoria')
  )
  WITH CHECK (
    tenant_id = current_tenant_id()
    AND current_user_role() IN ('rh', 'diretoria')
  );

-- Delete direto: NUNCA (so soft via hidden_at)
-- Sender pode deletar SEU proprio post (escape hatch)
DROP POLICY IF EXISTS recognitions_sender_delete ON recognitions;
CREATE POLICY recognitions_sender_delete ON recognitions
  FOR DELETE
  USING (
    tenant_id = current_tenant_id()
    AND sender_id = current_user_id()
    AND hidden_at IS NULL
  );

-- ===== RECOGNITION_REACTIONS =====
-- Read: qualquer um do tenant que veria o post
DROP POLICY IF EXISTS recog_reactions_tenant_read ON recognition_reactions;
CREATE POLICY recog_reactions_tenant_read ON recognition_reactions
  FOR SELECT
  USING (tenant_id = current_tenant_id());

-- Self write: usuario gerencia suas reacoes
DROP POLICY IF EXISTS recog_reactions_self_write ON recognition_reactions;
CREATE POLICY recog_reactions_self_write ON recognition_reactions
  FOR ALL
  USING (
    tenant_id = current_tenant_id()
    AND user_id = current_user_id()
  )
  WITH CHECK (
    tenant_id = current_tenant_id()
    AND user_id = current_user_id()
  );

-- ===== RECOGNITION_REPORTS =====
-- Read: o reporter ve sua denuncia · RH/Diretoria veem todas
DROP POLICY IF EXISTS recog_reports_self_read ON recognition_reports;
CREATE POLICY recog_reports_self_read ON recognition_reports
  FOR SELECT
  USING (
    tenant_id = current_tenant_id()
    AND reporter_id = current_user_id()
  );

DROP POLICY IF EXISTS recog_reports_rh_dir_read ON recognition_reports;
CREATE POLICY recog_reports_rh_dir_read ON recognition_reports
  FOR SELECT
  USING (
    tenant_id = current_tenant_id()
    AND current_user_role() IN ('rh', 'diretoria')
  );

-- Insert: reporter cria sua denuncia
DROP POLICY IF EXISTS recog_reports_self_insert ON recognition_reports;
CREATE POLICY recog_reports_self_insert ON recognition_reports
  FOR INSERT
  WITH CHECK (
    tenant_id = current_tenant_id()
    AND reporter_id = current_user_id()
  );

-- Update: RH/Diretoria resolvem
DROP POLICY IF EXISTS recog_reports_rh_dir_update ON recognition_reports;
CREATE POLICY recog_reports_rh_dir_update ON recognition_reports
  FOR UPDATE
  USING (
    tenant_id = current_tenant_id()
    AND current_user_role() IN ('rh', 'diretoria')
  )
  WITH CHECK (
    tenant_id = current_tenant_id()
    AND current_user_role() IN ('rh', 'diretoria')
  );

-- ============================================================================
-- GRANTS
-- ============================================================================

GRANT SELECT, INSERT, UPDATE, DELETE ON recognitions          TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON recognition_reactions TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON recognition_reports   TO authenticated;

GRANT EXECUTE ON FUNCTION rpc_recognition_create         TO authenticated;
GRANT EXECUTE ON FUNCTION rpc_recognition_react          TO authenticated;
GRANT EXECUTE ON FUNCTION rpc_recognition_get_feed       TO authenticated;
GRANT EXECUTE ON FUNCTION rpc_recognition_get_stats      TO authenticated;
GRANT EXECUTE ON FUNCTION rpc_recognition_report         TO authenticated;
GRANT EXECUTE ON FUNCTION rpc_recognition_resolve_report TO authenticated;

-- ============================================================================
-- COMENTARIOS
-- ============================================================================

COMMENT ON TABLE recognitions IS 'Posts de reconhecimento peer-to-peer · 1 sender + 1 recipient · mensagem livre';
COMMENT ON TABLE recognition_reactions IS '1 reacao por usuario por post · UPSERT troca o emoji';
COMMENT ON TABLE recognition_reports IS 'Denuncias de conteudo · RH/Diretoria resolvem';

COMMENT ON COLUMN recognitions.is_private IS 'Se TRUE, so destinatario, lider do destinatario, RH e Diretoria veem';
COMMENT ON COLUMN recognitions.hidden_at IS 'Soft-delete por moderacao · ninguem ve exceto RH/Diretoria';
COMMENT ON COLUMN recognitions.reactions_count IS 'Denormalizado por trigger para feed performatico';
COMMENT ON COLUMN recognitions.reports_count IS 'Denormalizado por trigger para fila de moderacao';

COMMENT ON FUNCTION rpc_recognition_create IS 'Cria reconhecimento · valida sender != recipient e mesmo tenant';
COMMENT ON FUNCTION rpc_recognition_react IS 'Adiciona/troca/remove reacao · NULL kind remove';
COMMENT ON FUNCTION rpc_recognition_get_feed IS 'Feed paginado com filtros · respeita privacidade automaticamente';
COMMENT ON FUNCTION rpc_recognition_get_stats IS 'KPIs do periodo · participation rate + top 5 reconhecidos';
COMMENT ON FUNCTION rpc_recognition_report IS 'Denuncia post · 1 por reporter por post';
COMMENT ON FUNCTION rpc_recognition_resolve_report IS 'RH/Diretoria resolvem denuncia · acao hide/keep/dismiss';

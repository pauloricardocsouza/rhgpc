-- ============================================================================
-- R2 People · Schema PDI v1 (Sessao J)
-- ============================================================================
-- Modulo de Plano de Desenvolvimento Individual
--
-- Decisoes da Sessao J:
--   - Ciclos compartilhados como tabela propria (pdi_cycles por tenant)
--   - Workflow simples · 4 status: draft, active, completed, canceled
--   - Sem milestones · acoes diretas com due_date
--   - Evidencias em Supabase Storage (bucket pdi-evidence)
--   - Comentarios em PDI (nao por acao) · thread linear
--
-- Pre-requisitos:
--   - r2_people_schema_base_v1.sql aplicado
--   - r2_people_seed_base_v1.sql aplicado
--
-- Ordem de aplicacao:
--   1. r2_people_schema_pdi_v1.sql              (este arquivo)
--   2. r2_people_seed_pdi_v1.sql                (ciclos exemplo · opcional)
--   3. r2_people_storage_pdi_v1.sql             (bucket Supabase Storage)
--   4. r2_people_rls_policies_pdi_tests.sql     (opcional · validacao)
-- ============================================================================

-- ============================================================================
-- ENUMS
-- ============================================================================

DO $$ BEGIN
  CREATE TYPE pdi_status AS ENUM ('draft', 'active', 'completed', 'canceled');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  CREATE TYPE pdi_action_kind AS ENUM (
    'curso',
    'leitura',
    'mentoria',
    'projeto',
    'certificacao',
    'evento',
    'outro'
  );
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  CREATE TYPE pdi_action_status AS ENUM ('not_started', 'in_progress', 'completed', 'canceled');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- ============================================================================
-- TABELA · pdi_cycles (ciclos compartilhados por tenant)
-- ============================================================================

CREATE TABLE IF NOT EXISTS pdi_cycles (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id       UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,

  code            VARCHAR(40) NOT NULL,          -- '2026-S1', '2026-S2', '2026'
  display_name    VARCHAR(160) NOT NULL,         -- 'Primeiro semestre 2026'

  start_date      DATE NOT NULL,
  end_date        DATE NOT NULL,

  -- Janela em que e permitido criar/editar PDIs deste ciclo
  open_for_planning  BOOLEAN NOT NULL DEFAULT TRUE,

  active          BOOLEAN NOT NULL DEFAULT TRUE,

  created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT now(),

  UNIQUE (tenant_id, code),
  CONSTRAINT cycle_dates CHECK (end_date >= start_date)
);

CREATE INDEX IF NOT EXISTS idx_pdi_cycles_tenant ON pdi_cycles(tenant_id, active) WHERE active = TRUE;
CREATE INDEX IF NOT EXISTS idx_pdi_cycles_window ON pdi_cycles(tenant_id, start_date, end_date);

-- ============================================================================
-- TABELA · pdis (Plano de Desenvolvimento Individual)
-- ============================================================================

CREATE TABLE IF NOT EXISTS pdis (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id       UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,

  user_id         UUID NOT NULL REFERENCES app_users(id) ON DELETE CASCADE,
  cycle_id        UUID NOT NULL REFERENCES pdi_cycles(id),

  -- Snapshot do gestor no momento da criacao (auditoria · gestor pode mudar)
  manager_id_snapshot UUID REFERENCES app_users(id) ON DELETE SET NULL,

  -- Conteudo
  objective       TEXT NOT NULL,
  context         TEXT,

  status          pdi_status NOT NULL DEFAULT 'draft',

  -- Datas reais do PDI (podem diferir das do ciclo se o PDI for parcial)
  start_date      DATE NOT NULL,
  end_date        DATE NOT NULL,

  -- Snapshot denormalizado (atualizado por trigger sobre pdi_actions)
  actions_total       INT NOT NULL DEFAULT 0,
  actions_completed   INT NOT NULL DEFAULT 0,

  -- Marcadores de transicao
  activated_at    TIMESTAMPTZ,
  completed_at    TIMESTAMPTZ,
  canceled_at     TIMESTAMPTZ,
  cancel_reason   TEXT,

  created_by      UUID NOT NULL REFERENCES app_users(id),
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT now(),

  CONSTRAINT pdi_dates CHECK (end_date >= start_date),
  CONSTRAINT pdi_objective_length CHECK (char_length(objective) BETWEEN 10 AND 2000),
  CONSTRAINT pdi_context_length CHECK (context IS NULL OR char_length(context) <= 5000),

  -- 1 PDI ativo/concluido por user por ciclo (pode ter varios drafts)
  -- Drafts NAO entram no UNIQUE para permitir varios rascunhos
  -- (constraint via index parcial abaixo)
  UNIQUE (tenant_id, user_id, cycle_id, id)  -- placeholder
);

-- Index parcial: 1 unico PDI nao-draft por (tenant, user, cycle)
CREATE UNIQUE INDEX IF NOT EXISTS uq_pdis_one_active_per_cycle
  ON pdis (tenant_id, user_id, cycle_id)
  WHERE status IN ('active', 'completed');

CREATE INDEX IF NOT EXISTS idx_pdis_tenant ON pdis(tenant_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_pdis_user ON pdis(user_id, status, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_pdis_cycle ON pdis(cycle_id);
CREATE INDEX IF NOT EXISTS idx_pdis_status ON pdis(tenant_id, status, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_pdis_manager ON pdis(manager_id_snapshot) WHERE manager_id_snapshot IS NOT NULL;

-- ============================================================================
-- TABELA · pdi_actions
-- ============================================================================

CREATE TABLE IF NOT EXISTS pdi_actions (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id       UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  pdi_id          UUID NOT NULL REFERENCES pdis(id) ON DELETE CASCADE,

  title           VARCHAR(200) NOT NULL,
  description     TEXT,
  kind            pdi_action_kind NOT NULL DEFAULT 'outro',

  due_date        DATE,
  status          pdi_action_status NOT NULL DEFAULT 'not_started',

  display_order   INT NOT NULL DEFAULT 0,

  -- Evidencia · path no bucket pdi-evidence ou URL externa
  evidence_path   TEXT,                          -- ex: tenant-id/pdi-id/action-id/file.pdf
  evidence_url    TEXT,                          -- URL externa alternativa
  evidence_note   TEXT,                          -- nota sobre a evidencia

  completed_at    TIMESTAMPTZ,

  created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT now(),

  CONSTRAINT action_title_length CHECK (char_length(title) BETWEEN 3 AND 200),
  CONSTRAINT action_description_length CHECK (description IS NULL OR char_length(description) <= 2000),
  -- Pelo menos um dos dois (path ou URL) ou nenhum (sem evidencia)
  CONSTRAINT action_evidence_one_kind CHECK (
    NOT (evidence_path IS NOT NULL AND evidence_url IS NOT NULL)
  )
);

CREATE INDEX IF NOT EXISTS idx_pdi_actions_pdi ON pdi_actions(pdi_id, display_order);
CREATE INDEX IF NOT EXISTS idx_pdi_actions_due ON pdi_actions(tenant_id, due_date) WHERE status IN ('not_started', 'in_progress');

-- ============================================================================
-- TABELA · pdi_comments (thread linear por PDI)
-- ============================================================================

CREATE TABLE IF NOT EXISTS pdi_comments (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id       UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  pdi_id          UUID NOT NULL REFERENCES pdis(id) ON DELETE CASCADE,

  author_id       UUID NOT NULL REFERENCES app_users(id) ON DELETE CASCADE,
  body            TEXT NOT NULL,

  -- Soft-delete · autor pode editar/apagar seu comentario
  edited_at       TIMESTAMPTZ,
  deleted_at      TIMESTAMPTZ,
  deleted_by      UUID REFERENCES app_users(id) ON DELETE SET NULL,

  created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT now(),

  CONSTRAINT comment_body_length CHECK (char_length(body) BETWEEN 1 AND 2000)
);

CREATE INDEX IF NOT EXISTS idx_pdi_comments_pdi ON pdi_comments(pdi_id, created_at)
  WHERE deleted_at IS NULL;
CREATE INDEX IF NOT EXISTS idx_pdi_comments_author ON pdi_comments(author_id);

-- ============================================================================
-- TRIGGERS
-- ============================================================================

-- updated_at automatico
DROP TRIGGER IF EXISTS trg_pdi_cycles_updated_at ON pdi_cycles;
CREATE TRIGGER trg_pdi_cycles_updated_at BEFORE UPDATE ON pdi_cycles
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

DROP TRIGGER IF EXISTS trg_pdis_updated_at ON pdis;
CREATE TRIGGER trg_pdis_updated_at BEFORE UPDATE ON pdis
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

DROP TRIGGER IF EXISTS trg_pdi_actions_updated_at ON pdi_actions;
CREATE TRIGGER trg_pdi_actions_updated_at BEFORE UPDATE ON pdi_actions
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

DROP TRIGGER IF EXISTS trg_pdi_comments_updated_at ON pdi_comments;
CREATE TRIGGER trg_pdi_comments_updated_at BEFORE UPDATE ON pdi_comments
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- Audit em pdis e pdi_cycles (decisoes formais auditaveis)
DROP TRIGGER IF EXISTS trg_audit_pdis ON pdis;
CREATE TRIGGER trg_audit_pdis
  AFTER INSERT OR UPDATE OR DELETE ON pdis
  FOR EACH ROW EXECUTE FUNCTION audit_change();

DROP TRIGGER IF EXISTS trg_audit_pdi_cycles ON pdi_cycles;
CREATE TRIGGER trg_audit_pdi_cycles
  AFTER INSERT OR UPDATE OR DELETE ON pdi_cycles
  FOR EACH ROW EXECUTE FUNCTION audit_change();

-- Trigger denormaliza actions_total e actions_completed em pdis
CREATE OR REPLACE FUNCTION pdi_action_update_counts()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_pdi UUID;
BEGIN
  IF TG_OP = 'DELETE' THEN
    v_pdi := OLD.pdi_id;
  ELSE
    v_pdi := NEW.pdi_id;
  END IF;

  UPDATE pdis SET
    actions_total = (SELECT count(*) FROM pdi_actions WHERE pdi_id = v_pdi),
    actions_completed = (SELECT count(*) FROM pdi_actions WHERE pdi_id = v_pdi AND status = 'completed')
  WHERE id = v_pdi;

  -- Para UPDATE entre PDIs diferentes (raro mas possivel via reorder), atualiza tambem o antigo
  IF TG_OP = 'UPDATE' AND OLD.pdi_id <> NEW.pdi_id THEN
    UPDATE pdis SET
      actions_total = (SELECT count(*) FROM pdi_actions WHERE pdi_id = OLD.pdi_id),
      actions_completed = (SELECT count(*) FROM pdi_actions WHERE pdi_id = OLD.pdi_id AND status = 'completed')
    WHERE id = OLD.pdi_id;
  END IF;

  IF TG_OP = 'DELETE' THEN
    RETURN OLD;
  ELSE
    RETURN NEW;
  END IF;
END;
$$;

DROP TRIGGER IF EXISTS trg_pdi_action_counts ON pdi_actions;
CREATE TRIGGER trg_pdi_action_counts
  AFTER INSERT OR UPDATE OR DELETE ON pdi_actions
  FOR EACH ROW EXECUTE FUNCTION pdi_action_update_counts();

-- Trigger marca completed_at na acao quando status vira 'completed'
CREATE OR REPLACE FUNCTION pdi_action_set_completed_at()
RETURNS TRIGGER AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    IF NEW.status = 'completed' AND NEW.completed_at IS NULL THEN
      NEW.completed_at := clock_timestamp();
    END IF;
  ELSIF TG_OP = 'UPDATE' THEN
    IF NEW.status = 'completed' AND OLD.status <> 'completed' THEN
      NEW.completed_at := clock_timestamp();
    ELSIF NEW.status <> 'completed' THEN
      NEW.completed_at := NULL;
    END IF;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_pdi_action_completed_at ON pdi_actions;
CREATE TRIGGER trg_pdi_action_completed_at BEFORE INSERT OR UPDATE ON pdi_actions
  FOR EACH ROW EXECUTE FUNCTION pdi_action_set_completed_at();

-- Trigger marca activated_at, completed_at, canceled_at em pdis no UPDATE de status
CREATE OR REPLACE FUNCTION pdi_set_status_timestamps()
RETURNS TRIGGER AS $$
BEGIN
  IF TG_OP = 'UPDATE' THEN
    IF NEW.status = 'active' AND OLD.status <> 'active' AND NEW.activated_at IS NULL THEN
      NEW.activated_at := clock_timestamp();
    END IF;
    IF NEW.status = 'completed' AND OLD.status <> 'completed' AND NEW.completed_at IS NULL THEN
      NEW.completed_at := clock_timestamp();
    END IF;
    IF NEW.status = 'canceled' AND OLD.status <> 'canceled' AND NEW.canceled_at IS NULL THEN
      NEW.canceled_at := clock_timestamp();
    END IF;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_pdi_status_timestamps ON pdis;
CREATE TRIGGER trg_pdi_status_timestamps BEFORE UPDATE ON pdis
  FOR EACH ROW EXECUTE FUNCTION pdi_set_status_timestamps();

-- ============================================================================
-- HELPER · saber se o caller pode ler determinado PDI
-- ============================================================================

CREATE OR REPLACE FUNCTION pdi_can_read(p_pdi_id UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_caller UUID;
  v_role app_user_role;
  v_owner UUID;
  v_pdi_tenant UUID;
BEGIN
  v_caller := current_user_id();
  IF v_caller IS NULL THEN
    RETURN FALSE;
  END IF;

  SELECT user_id, tenant_id INTO v_owner, v_pdi_tenant
  FROM pdis WHERE id = p_pdi_id;

  IF v_owner IS NULL THEN
    RETURN FALSE;
  END IF;

  -- Mesmo tenant
  IF v_pdi_tenant <> current_tenant_id() THEN
    RETURN FALSE;
  END IF;

  -- Owner
  IF v_owner = v_caller THEN
    RETURN TRUE;
  END IF;

  -- RH/Diretoria leem todos do tenant
  v_role := current_user_role();
  IF v_role IN ('rh', 'diretoria') THEN
    RETURN TRUE;
  END IF;

  -- Manager (direto ou indireto) le do time
  IF user_is_manager_of(v_owner) = TRUE THEN
    RETURN TRUE;
  END IF;

  RETURN FALSE;
END;
$$;

-- ============================================================================
-- RPCs
-- ============================================================================

-- Cria PDI (sempre como 'draft' · ativacao via rpc_pdi_change_status)
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

-- Atualiza campos editaveis do PDI · so dono ou manager/RH/Dir podem
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

-- Muda status · valida transicoes legitimas
-- Transicoes validas:
--   draft -> active (precisa ter ao menos 1 acao)
--   active -> completed
--   active -> canceled (precisa cancel_reason)
--   draft -> canceled
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

-- Adiciona acao
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

-- Atualiza acao (campos editaveis · status, due_date, evidencia, etc)
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

-- Remove acao (permitido apenas em PDI nao concluido/cancelado)
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

-- Adiciona comentario
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

-- Lista PDIs por escopo
-- p_scope: 'own', 'team', 'all'
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

-- Le PDI completo (com acoes e comentarios)
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

-- Lista ciclos disponiveis para o tenant
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
-- ROW-LEVEL SECURITY
-- ============================================================================

ALTER TABLE pdi_cycles   ENABLE ROW LEVEL SECURITY;
ALTER TABLE pdis         ENABLE ROW LEVEL SECURITY;
ALTER TABLE pdi_actions  ENABLE ROW LEVEL SECURITY;
ALTER TABLE pdi_comments ENABLE ROW LEVEL SECURITY;

-- ===== PDI_CYCLES =====
DROP POLICY IF EXISTS pdi_cycles_tenant_read ON pdi_cycles;
CREATE POLICY pdi_cycles_tenant_read ON pdi_cycles
  FOR SELECT
  USING (tenant_id = current_tenant_id());

DROP POLICY IF EXISTS pdi_cycles_rh_dir_write ON pdi_cycles;
CREATE POLICY pdi_cycles_rh_dir_write ON pdi_cycles
  FOR ALL
  USING (
    tenant_id = current_tenant_id()
    AND current_user_role() IN ('rh', 'diretoria')
  )
  WITH CHECK (
    tenant_id = current_tenant_id()
    AND current_user_role() IN ('rh', 'diretoria')
  );

-- ===== PDIS =====
-- Read: owner OR manager OR RH/Dir
DROP POLICY IF EXISTS pdis_owner_read ON pdis;
CREATE POLICY pdis_owner_read ON pdis
  FOR SELECT
  USING (
    tenant_id = current_tenant_id()
    AND user_id = current_user_id()
  );

DROP POLICY IF EXISTS pdis_manager_read ON pdis;
CREATE POLICY pdis_manager_read ON pdis
  FOR SELECT
  USING (
    tenant_id = current_tenant_id()
    AND user_is_manager_of(user_id) = TRUE
  );

DROP POLICY IF EXISTS pdis_rh_dir_read ON pdis;
CREATE POLICY pdis_rh_dir_read ON pdis
  FOR SELECT
  USING (
    tenant_id = current_tenant_id()
    AND current_user_role() IN ('rh', 'diretoria')
  );

-- Write geral: owner OR manager OR RH/Dir
DROP POLICY IF EXISTS pdis_write ON pdis;
CREATE POLICY pdis_write ON pdis
  FOR ALL
  USING (
    tenant_id = current_tenant_id()
    AND (
      user_id = current_user_id()
      OR user_is_manager_of(user_id) = TRUE
      OR current_user_role() IN ('rh', 'diretoria')
    )
  )
  WITH CHECK (
    tenant_id = current_tenant_id()
    AND (
      user_id = current_user_id()
      OR user_is_manager_of(user_id) = TRUE
      OR current_user_role() IN ('rh', 'diretoria')
    )
  );

-- ===== PDI_ACTIONS · herda permissoes do PDI pai =====
DROP POLICY IF EXISTS pdi_actions_read ON pdi_actions;
CREATE POLICY pdi_actions_read ON pdi_actions
  FOR SELECT
  USING (
    tenant_id = current_tenant_id()
    AND pdi_can_read(pdi_id) = TRUE
  );

DROP POLICY IF EXISTS pdi_actions_write ON pdi_actions;
CREATE POLICY pdi_actions_write ON pdi_actions
  FOR ALL
  USING (
    tenant_id = current_tenant_id()
    AND EXISTS (
      SELECT 1 FROM pdis p
      WHERE p.id = pdi_actions.pdi_id
        AND (
          p.user_id = current_user_id()
          OR user_is_manager_of(p.user_id) = TRUE
          OR current_user_role() IN ('rh', 'diretoria')
        )
    )
  )
  WITH CHECK (
    tenant_id = current_tenant_id()
    AND EXISTS (
      SELECT 1 FROM pdis p
      WHERE p.id = pdi_actions.pdi_id
        AND (
          p.user_id = current_user_id()
          OR user_is_manager_of(p.user_id) = TRUE
          OR current_user_role() IN ('rh', 'diretoria')
        )
    )
  );

-- ===== PDI_COMMENTS · quem pode ler o PDI le os comentarios =====
DROP POLICY IF EXISTS pdi_comments_read ON pdi_comments;
CREATE POLICY pdi_comments_read ON pdi_comments
  FOR SELECT
  USING (
    tenant_id = current_tenant_id()
    AND deleted_at IS NULL
    AND pdi_can_read(pdi_id) = TRUE
  );

-- Insert: quem pode ler pode comentar (validado em RPC tambem)
DROP POLICY IF EXISTS pdi_comments_insert ON pdi_comments;
CREATE POLICY pdi_comments_insert ON pdi_comments
  FOR INSERT
  WITH CHECK (
    tenant_id = current_tenant_id()
    AND author_id = current_user_id()
    AND pdi_can_read(pdi_id) = TRUE
  );

-- Update/Delete: so o autor (soft-delete em deleted_at)
DROP POLICY IF EXISTS pdi_comments_self_update ON pdi_comments;
CREATE POLICY pdi_comments_self_update ON pdi_comments
  FOR UPDATE
  USING (
    tenant_id = current_tenant_id()
    AND author_id = current_user_id()
  )
  WITH CHECK (
    tenant_id = current_tenant_id()
    AND author_id = current_user_id()
  );

-- ============================================================================
-- GRANTS
-- ============================================================================

GRANT SELECT, INSERT, UPDATE, DELETE ON pdi_cycles   TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON pdis         TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON pdi_actions  TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON pdi_comments TO authenticated;

GRANT EXECUTE ON FUNCTION pdi_can_read              TO authenticated;
GRANT EXECUTE ON FUNCTION rpc_pdi_create            TO authenticated;
GRANT EXECUTE ON FUNCTION rpc_pdi_update            TO authenticated;
GRANT EXECUTE ON FUNCTION rpc_pdi_change_status     TO authenticated;
GRANT EXECUTE ON FUNCTION rpc_pdi_action_add        TO authenticated;
GRANT EXECUTE ON FUNCTION rpc_pdi_action_update     TO authenticated;
GRANT EXECUTE ON FUNCTION rpc_pdi_action_remove     TO authenticated;
GRANT EXECUTE ON FUNCTION rpc_pdi_comment_add       TO authenticated;
GRANT EXECUTE ON FUNCTION rpc_pdi_list              TO authenticated;
GRANT EXECUTE ON FUNCTION rpc_pdi_get_by_id         TO authenticated;
GRANT EXECUTE ON FUNCTION rpc_pdi_list_cycles       TO authenticated;

-- ============================================================================
-- COMENTARIOS
-- ============================================================================

COMMENT ON TABLE pdi_cycles IS 'Ciclos de PDI compartilhados por tenant (ex: 2026-S1, 2026-S2)';
COMMENT ON TABLE pdis IS 'Plano de Desenvolvimento Individual · 1 ativo por user por ciclo';
COMMENT ON TABLE pdi_actions IS 'Acoes do PDI · com evidencia opcional em Storage ou URL';
COMMENT ON TABLE pdi_comments IS 'Thread linear de comentarios por PDI · soft-delete em deleted_at';

COMMENT ON COLUMN pdis.manager_id_snapshot IS 'Snapshot do gestor na criacao · gestor pode mudar depois';
COMMENT ON COLUMN pdis.actions_total IS 'Denormalizado por trigger pdi_action_update_counts()';
COMMENT ON COLUMN pdis.actions_completed IS 'Denormalizado por trigger pdi_action_update_counts()';
COMMENT ON COLUMN pdi_actions.evidence_path IS 'Path no Supabase Storage bucket pdi-evidence (formato: tenant_id/pdi_id/action_id/file)';
COMMENT ON COLUMN pdi_actions.evidence_url IS 'URL externa alternativa (ex: link de drive)';

COMMENT ON FUNCTION pdi_can_read IS 'Helper RLS: caller e owner/manager/RH/Dir do PDI?';

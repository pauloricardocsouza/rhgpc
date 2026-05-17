-- ============================================================================
-- R2 People · Schema Onboarding v1 (Sessao K)
-- ============================================================================
-- Modulo de Onboarding (Integracao) · jornada apos admissao formal.
--
-- Decisoes da Sessao K:
--   - Templates opcionais reutilizaveis (com fallback para criacao manual)
--   - So pos-admissao (nao cobre pre-admissional)
--   - Stages agrupam tasks (ex: Documentacao, Treinamentos, Integracao)
--   - RH controla tudo · sem responsavel/padrinho distribuido
--   - Sem upload de documentos · so checklist de tarefas
--
-- Pre-requisitos:
--   - r2_people_schema_base_v1.sql aplicado
--   - r2_people_seed_base_v1.sql aplicado
--
-- Ordem de aplicacao:
--   1. r2_people_schema_onboarding_v1.sql            (este arquivo)
--   2. r2_people_seed_onboarding_v1.sql              (permissoes + template exemplo)
--   3. r2_people_rls_policies_onboarding_tests.sql   (opcional · validacao)
-- ============================================================================

-- ============================================================================
-- ENUMS
-- ============================================================================

DO $$ BEGIN
  CREATE TYPE onboarding_status AS ENUM ('not_started', 'in_progress', 'completed', 'canceled');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  CREATE TYPE onboarding_task_status AS ENUM ('pending', 'in_progress', 'completed', 'skipped');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  CREATE TYPE onboarding_task_kind AS ENUM (
    'documentation',     -- Documentacao (entrega de RG, CTPS, etc - sem upload, so check)
    'training',          -- Treinamento (curso, NR, integracao)
    'meeting',           -- Reuniao (com gestor, padrinho, RH)
    'system_access',     -- Liberar acesso a sistema (criar usuario, badge, email)
    'cultural',          -- Integracao cultural (boas-vindas, kit, manual)
    'compliance',        -- Compliance (politicas, codigo de conduta, LGPD)
    'task'               -- Tarefa generica
  );
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  CREATE TYPE onboarding_template_status AS ENUM ('draft', 'published', 'archived');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- ============================================================================
-- TABELAS DE TEMPLATE
-- ============================================================================

-- Template reutilizavel (ex: "Onboarding Operador de Loja", "Onboarding Coordenador")
CREATE TABLE IF NOT EXISTS onb_templates (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id       UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,

  code            VARCHAR(40) NOT NULL,           -- 'OPERADOR-LOJA', 'COORD-PEREC'
  display_name    VARCHAR(160) NOT NULL,
  description     TEXT,

  -- Duracao sugerida em dias · so referencia (cada onboarding tem suas datas)
  suggested_duration_days INT NOT NULL DEFAULT 30,

  status          onboarding_template_status NOT NULL DEFAULT 'draft',

  created_by      UUID NOT NULL REFERENCES app_users(id),
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT now(),

  UNIQUE (tenant_id, code),
  CONSTRAINT tpl_duration CHECK (suggested_duration_days BETWEEN 1 AND 365),
  CONSTRAINT tpl_name_length CHECK (char_length(display_name) BETWEEN 3 AND 160)
);

CREATE INDEX IF NOT EXISTS idx_onb_templates_tenant
  ON onb_templates(tenant_id, status, updated_at DESC);

-- Stages do template (Documentacao, Treinamentos, etc)
CREATE TABLE IF NOT EXISTS onb_template_stages (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id       UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  template_id     UUID NOT NULL REFERENCES onb_templates(id) ON DELETE CASCADE,

  display_name    VARCHAR(120) NOT NULL,
  description     TEXT,
  display_order   INT NOT NULL DEFAULT 0,

  -- Offset em dias desde o inicio do onboarding (referencia · pode ser ignorado)
  offset_days_start INT NOT NULL DEFAULT 0,
  duration_days     INT NOT NULL DEFAULT 7,

  created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT now(),

  CONSTRAINT tpl_stage_name_length CHECK (char_length(display_name) BETWEEN 2 AND 120),
  CONSTRAINT tpl_stage_offsets CHECK (offset_days_start >= 0 AND duration_days >= 1)
);

CREATE INDEX IF NOT EXISTS idx_onb_template_stages_template
  ON onb_template_stages(template_id, display_order);

-- Tasks do template
CREATE TABLE IF NOT EXISTS onb_template_tasks (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id       UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  template_id     UUID NOT NULL REFERENCES onb_templates(id) ON DELETE CASCADE,
  stage_id        UUID NOT NULL REFERENCES onb_template_stages(id) ON DELETE CASCADE,

  title           VARCHAR(200) NOT NULL,
  description     TEXT,
  kind            onboarding_task_kind NOT NULL DEFAULT 'task',

  -- Offset em dias dentro da stage (0 = primeiro dia da stage)
  offset_days     INT NOT NULL DEFAULT 0,

  -- Marca se a task e obrigatoria (nao pode ficar pendente para concluir o onboarding)
  is_required     BOOLEAN NOT NULL DEFAULT TRUE,

  display_order   INT NOT NULL DEFAULT 0,

  created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT now(),

  CONSTRAINT tpl_task_title_length CHECK (char_length(title) BETWEEN 3 AND 200),
  CONSTRAINT tpl_task_offset CHECK (offset_days >= 0)
);

CREATE INDEX IF NOT EXISTS idx_onb_template_tasks_stage
  ON onb_template_tasks(stage_id, display_order);

-- ============================================================================
-- TABELAS DE ONBOARDING (instancia individual)
-- ============================================================================

CREATE TABLE IF NOT EXISTS onboardings (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id       UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,

  -- Quem esta sendo integrado
  user_id         UUID NOT NULL REFERENCES app_users(id) ON DELETE CASCADE,

  -- Snapshots na criacao (gestor pode mudar)
  manager_id_snapshot UUID REFERENCES app_users(id) ON DELETE SET NULL,

  -- Origem · template ou manual (NULL = manual)
  source_template_id  UUID REFERENCES onb_templates(id) ON DELETE SET NULL,

  display_name    VARCHAR(160) NOT NULL,
  notes           TEXT,                         -- notas livres do RH

  status          onboarding_status NOT NULL DEFAULT 'not_started',

  start_date      DATE NOT NULL,
  target_end_date DATE NOT NULL,

  -- Snapshots denormalizados (atualizados por trigger sobre tasks)
  tasks_total       INT NOT NULL DEFAULT 0,
  tasks_completed   INT NOT NULL DEFAULT 0,
  tasks_required    INT NOT NULL DEFAULT 0,
  tasks_required_done INT NOT NULL DEFAULT 0,

  -- Marcadores de transicao
  started_at      TIMESTAMPTZ,
  completed_at    TIMESTAMPTZ,
  canceled_at     TIMESTAMPTZ,
  cancel_reason   TEXT,

  created_by      UUID NOT NULL REFERENCES app_users(id),
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT now(),

  CONSTRAINT onb_dates CHECK (target_end_date >= start_date),
  CONSTRAINT onb_name_length CHECK (char_length(display_name) BETWEEN 3 AND 160)
);

-- Index parcial: 1 onboarding ativo (not_started/in_progress) por user
CREATE UNIQUE INDEX IF NOT EXISTS uq_onboardings_one_active_per_user
  ON onboardings (tenant_id, user_id)
  WHERE status IN ('not_started', 'in_progress');

CREATE INDEX IF NOT EXISTS idx_onboardings_tenant ON onboardings(tenant_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_onboardings_user ON onboardings(user_id, status);
CREATE INDEX IF NOT EXISTS idx_onboardings_status ON onboardings(tenant_id, status, target_end_date);
CREATE INDEX IF NOT EXISTS idx_onboardings_manager ON onboardings(manager_id_snapshot)
  WHERE manager_id_snapshot IS NOT NULL;

-- Stages do onboarding (copia do template ou criadas manualmente)
CREATE TABLE IF NOT EXISTS onboarding_stages (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id       UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  onboarding_id   UUID NOT NULL REFERENCES onboardings(id) ON DELETE CASCADE,

  display_name    VARCHAR(120) NOT NULL,
  description     TEXT,
  display_order   INT NOT NULL DEFAULT 0,

  -- Datas concretas (calculadas no create se vier de template)
  start_date      DATE,
  target_end_date DATE,

  created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT now(),

  CONSTRAINT onb_stage_name_length CHECK (char_length(display_name) BETWEEN 2 AND 120)
);

CREATE INDEX IF NOT EXISTS idx_onboarding_stages_onb
  ON onboarding_stages(onboarding_id, display_order);

-- Tasks do onboarding
CREATE TABLE IF NOT EXISTS onboarding_tasks (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id       UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  onboarding_id   UUID NOT NULL REFERENCES onboardings(id) ON DELETE CASCADE,
  stage_id        UUID NOT NULL REFERENCES onboarding_stages(id) ON DELETE CASCADE,

  title           VARCHAR(200) NOT NULL,
  description     TEXT,
  kind            onboarding_task_kind NOT NULL DEFAULT 'task',

  due_date        DATE,
  is_required     BOOLEAN NOT NULL DEFAULT TRUE,
  status          onboarding_task_status NOT NULL DEFAULT 'pending',

  display_order   INT NOT NULL DEFAULT 0,

  -- Quem marcou como concluida
  completed_at    TIMESTAMPTZ,
  completed_by    UUID REFERENCES app_users(id) ON DELETE SET NULL,
  completion_note TEXT,

  created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT now(),

  CONSTRAINT onb_task_title_length CHECK (char_length(title) BETWEEN 3 AND 200)
);

CREATE INDEX IF NOT EXISTS idx_onboarding_tasks_stage
  ON onboarding_tasks(stage_id, display_order);
CREATE INDEX IF NOT EXISTS idx_onboarding_tasks_onb
  ON onboarding_tasks(onboarding_id, status);
CREATE INDEX IF NOT EXISTS idx_onboarding_tasks_due
  ON onboarding_tasks(tenant_id, due_date)
  WHERE status IN ('pending', 'in_progress');

-- ============================================================================
-- TRIGGERS · updated_at
-- ============================================================================

DROP TRIGGER IF EXISTS trg_onb_templates_updated_at ON onb_templates;
CREATE TRIGGER trg_onb_templates_updated_at BEFORE UPDATE ON onb_templates
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

DROP TRIGGER IF EXISTS trg_onb_template_stages_updated_at ON onb_template_stages;
CREATE TRIGGER trg_onb_template_stages_updated_at BEFORE UPDATE ON onb_template_stages
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

DROP TRIGGER IF EXISTS trg_onb_template_tasks_updated_at ON onb_template_tasks;
CREATE TRIGGER trg_onb_template_tasks_updated_at BEFORE UPDATE ON onb_template_tasks
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

DROP TRIGGER IF EXISTS trg_onboardings_updated_at ON onboardings;
CREATE TRIGGER trg_onboardings_updated_at BEFORE UPDATE ON onboardings
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

DROP TRIGGER IF EXISTS trg_onboarding_stages_updated_at ON onboarding_stages;
CREATE TRIGGER trg_onboarding_stages_updated_at BEFORE UPDATE ON onboarding_stages
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

DROP TRIGGER IF EXISTS trg_onboarding_tasks_updated_at ON onboarding_tasks;
CREATE TRIGGER trg_onboarding_tasks_updated_at BEFORE UPDATE ON onboarding_tasks
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- Audit nas decisoes formais
DROP TRIGGER IF EXISTS trg_audit_onb_templates ON onb_templates;
CREATE TRIGGER trg_audit_onb_templates
  AFTER INSERT OR UPDATE OR DELETE ON onb_templates
  FOR EACH ROW EXECUTE FUNCTION audit_change();

DROP TRIGGER IF EXISTS trg_audit_onboardings ON onboardings;
CREATE TRIGGER trg_audit_onboardings
  AFTER INSERT OR UPDATE OR DELETE ON onboardings
  FOR EACH ROW EXECUTE FUNCTION audit_change();

-- ============================================================================
-- TRIGGER · denormaliza counts em onboardings
-- ============================================================================

CREATE OR REPLACE FUNCTION onb_task_update_counts()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_onb UUID;
BEGIN
  IF TG_OP = 'DELETE' THEN
    v_onb := OLD.onboarding_id;
  ELSE
    v_onb := NEW.onboarding_id;
  END IF;

  UPDATE onboardings SET
    tasks_total          = (SELECT count(*) FROM onboarding_tasks WHERE onboarding_id = v_onb),
    tasks_completed      = (SELECT count(*) FROM onboarding_tasks WHERE onboarding_id = v_onb AND status = 'completed'),
    tasks_required       = (SELECT count(*) FROM onboarding_tasks WHERE onboarding_id = v_onb AND is_required = TRUE),
    tasks_required_done  = (SELECT count(*) FROM onboarding_tasks WHERE onboarding_id = v_onb AND is_required = TRUE AND status = 'completed')
  WHERE id = v_onb;

  -- Se a task mudou de onboarding (raro), atualiza ambos
  IF TG_OP = 'UPDATE' AND OLD.onboarding_id <> NEW.onboarding_id THEN
    UPDATE onboardings SET
      tasks_total          = (SELECT count(*) FROM onboarding_tasks WHERE onboarding_id = OLD.onboarding_id),
      tasks_completed      = (SELECT count(*) FROM onboarding_tasks WHERE onboarding_id = OLD.onboarding_id AND status = 'completed'),
      tasks_required       = (SELECT count(*) FROM onboarding_tasks WHERE onboarding_id = OLD.onboarding_id AND is_required = TRUE),
      tasks_required_done  = (SELECT count(*) FROM onboarding_tasks WHERE onboarding_id = OLD.onboarding_id AND is_required = TRUE AND status = 'completed')
    WHERE id = OLD.onboarding_id;
  END IF;

  IF TG_OP = 'DELETE' THEN
    RETURN OLD;
  ELSE
    RETURN NEW;
  END IF;
END;
$$;

DROP TRIGGER IF EXISTS trg_onb_task_counts ON onboarding_tasks;
CREATE TRIGGER trg_onb_task_counts
  AFTER INSERT OR UPDATE OR DELETE ON onboarding_tasks
  FOR EACH ROW EXECUTE FUNCTION onb_task_update_counts();

-- ============================================================================
-- TRIGGER · seta completed_at/completed_by automaticos em onboarding_tasks
-- ============================================================================

CREATE OR REPLACE FUNCTION onb_task_set_completion()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    IF NEW.status = 'completed' AND NEW.completed_at IS NULL THEN
      NEW.completed_at := clock_timestamp();
      NEW.completed_by := COALESCE(NEW.completed_by, current_user_id());
    END IF;
  ELSIF TG_OP = 'UPDATE' THEN
    IF NEW.status = 'completed' AND OLD.status <> 'completed' THEN
      NEW.completed_at := clock_timestamp();
      NEW.completed_by := COALESCE(NEW.completed_by, current_user_id());
    ELSIF NEW.status <> 'completed' AND OLD.status = 'completed' THEN
      NEW.completed_at := NULL;
      NEW.completed_by := NULL;
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_onb_task_completion ON onboarding_tasks;
CREATE TRIGGER trg_onb_task_completion BEFORE INSERT OR UPDATE ON onboarding_tasks
  FOR EACH ROW EXECUTE FUNCTION onb_task_set_completion();

-- ============================================================================
-- TRIGGER · timestamps de status em onboardings
-- ============================================================================

CREATE OR REPLACE FUNCTION onb_set_status_timestamps()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  IF TG_OP = 'UPDATE' THEN
    IF NEW.status = 'in_progress' AND OLD.status <> 'in_progress' AND NEW.started_at IS NULL THEN
      NEW.started_at := clock_timestamp();
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
$$;

DROP TRIGGER IF EXISTS trg_onb_status_timestamps ON onboardings;
CREATE TRIGGER trg_onb_status_timestamps BEFORE UPDATE ON onboardings
  FOR EACH ROW EXECUTE FUNCTION onb_set_status_timestamps();

-- ============================================================================
-- HELPER · saber se o caller pode ler determinado onboarding
-- ============================================================================

CREATE OR REPLACE FUNCTION onboarding_can_read(p_onb_id UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_caller UUID;
  v_role app_user_role;
  v_owner UUID;
  v_onb_tenant UUID;
BEGIN
  v_caller := current_user_id();
  IF v_caller IS NULL THEN
    RETURN FALSE;
  END IF;

  SELECT user_id, tenant_id INTO v_owner, v_onb_tenant
  FROM onboardings WHERE id = p_onb_id;

  IF v_owner IS NULL THEN
    RETURN FALSE;
  END IF;

  IF v_onb_tenant <> current_tenant_id() THEN
    RETURN FALSE;
  END IF;

  -- Owner (proprio novo colaborador)
  IF v_owner = v_caller THEN
    RETURN TRUE;
  END IF;

  -- RH/Diretoria leem todos do tenant
  v_role := current_user_role();
  IF v_role IN ('rh', 'diretoria') THEN
    RETURN TRUE;
  END IF;

  -- Manager (direto/indireto) le do time
  IF user_is_manager_of(v_owner) = TRUE THEN
    RETURN TRUE;
  END IF;

  RETURN FALSE;
END;
$$;

-- ============================================================================
-- RPCs · TEMPLATE
-- ============================================================================

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

-- Adiciona stage no template (com tasks opcionais)
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

-- ============================================================================
-- RPCs · ONBOARDING (instancia)
-- ============================================================================

-- Cria onboarding A PARTIR DE TEMPLATE (deep copy de stages e tasks)
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

-- Cria onboarding em branco (sem template) · stages e tasks adicionados manualmente depois
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

-- Adiciona stage manualmente em onboarding existente
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

-- Adiciona task manualmente em stage existente
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

-- Conclui task (marca como completed)
-- Owner do onboarding pode concluir suas proprias tasks; RH/Dir podem qualquer
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

-- Reverte conclusao de task
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

-- Mudar status do onboarding (concluir ou cancelar manualmente)
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

-- Lista onboardings por escopo
-- p_scope: 'own' | 'team' | 'all'
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

-- Le onboarding completo (com stages e tasks)
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
-- ROW-LEVEL SECURITY
-- ============================================================================

ALTER TABLE onb_templates        ENABLE ROW LEVEL SECURITY;
ALTER TABLE onb_template_stages  ENABLE ROW LEVEL SECURITY;
ALTER TABLE onb_template_tasks   ENABLE ROW LEVEL SECURITY;
ALTER TABLE onboardings          ENABLE ROW LEVEL SECURITY;
ALTER TABLE onboarding_stages    ENABLE ROW LEVEL SECURITY;
ALTER TABLE onboarding_tasks     ENABLE ROW LEVEL SECURITY;

-- ===== TEMPLATES (toda a familia) · leitura ampla, escrita restrita =====

DROP POLICY IF EXISTS onb_templates_tenant_read ON onb_templates;
CREATE POLICY onb_templates_tenant_read ON onb_templates
  FOR SELECT
  USING (
    tenant_id = current_tenant_id()
    AND (user_has_permission('view_onboarding') OR user_has_permission('manage_onboarding'))
  );

DROP POLICY IF EXISTS onb_templates_write ON onb_templates;
CREATE POLICY onb_templates_write ON onb_templates
  FOR ALL
  USING (
    tenant_id = current_tenant_id()
    AND user_has_permission('manage_onboarding')
  )
  WITH CHECK (
    tenant_id = current_tenant_id()
    AND user_has_permission('manage_onboarding')
  );

DROP POLICY IF EXISTS onb_template_stages_tenant_read ON onb_template_stages;
CREATE POLICY onb_template_stages_tenant_read ON onb_template_stages
  FOR SELECT
  USING (
    tenant_id = current_tenant_id()
    AND (user_has_permission('view_onboarding') OR user_has_permission('manage_onboarding'))
  );

DROP POLICY IF EXISTS onb_template_stages_write ON onb_template_stages;
CREATE POLICY onb_template_stages_write ON onb_template_stages
  FOR ALL
  USING (
    tenant_id = current_tenant_id()
    AND user_has_permission('manage_onboarding')
  )
  WITH CHECK (
    tenant_id = current_tenant_id()
    AND user_has_permission('manage_onboarding')
  );

DROP POLICY IF EXISTS onb_template_tasks_tenant_read ON onb_template_tasks;
CREATE POLICY onb_template_tasks_tenant_read ON onb_template_tasks
  FOR SELECT
  USING (
    tenant_id = current_tenant_id()
    AND (user_has_permission('view_onboarding') OR user_has_permission('manage_onboarding'))
  );

DROP POLICY IF EXISTS onb_template_tasks_write ON onb_template_tasks;
CREATE POLICY onb_template_tasks_write ON onb_template_tasks
  FOR ALL
  USING (
    tenant_id = current_tenant_id()
    AND user_has_permission('manage_onboarding')
  )
  WITH CHECK (
    tenant_id = current_tenant_id()
    AND user_has_permission('manage_onboarding')
  );

-- ===== ONBOARDINGS · owner/manager/RH-Dir leem; RH-Dir e owner (suas tasks) escrevem =====

DROP POLICY IF EXISTS onboardings_owner_read ON onboardings;
CREATE POLICY onboardings_owner_read ON onboardings
  FOR SELECT
  USING (
    tenant_id = current_tenant_id()
    AND user_id = current_user_id()
  );

DROP POLICY IF EXISTS onboardings_manager_read ON onboardings;
CREATE POLICY onboardings_manager_read ON onboardings
  FOR SELECT
  USING (
    tenant_id = current_tenant_id()
    AND user_is_manager_of(user_id) = TRUE
  );

DROP POLICY IF EXISTS onboardings_rh_dir_read ON onboardings;
CREATE POLICY onboardings_rh_dir_read ON onboardings
  FOR SELECT
  USING (
    tenant_id = current_tenant_id()
    AND (user_has_permission('view_onboarding') OR user_has_permission('manage_onboarding'))
  );

DROP POLICY IF EXISTS onboardings_write ON onboardings;
CREATE POLICY onboardings_write ON onboardings
  FOR ALL
  USING (
    tenant_id = current_tenant_id()
    AND user_has_permission('manage_onboarding')
  )
  WITH CHECK (
    tenant_id = current_tenant_id()
    AND user_has_permission('manage_onboarding')
  );

-- ===== STAGES · herdam permissoes do onboarding pai =====

DROP POLICY IF EXISTS onboarding_stages_read ON onboarding_stages;
CREATE POLICY onboarding_stages_read ON onboarding_stages
  FOR SELECT
  USING (
    tenant_id = current_tenant_id()
    AND onboarding_can_read(onboarding_id) = TRUE
  );

DROP POLICY IF EXISTS onboarding_stages_write ON onboarding_stages;
CREATE POLICY onboarding_stages_write ON onboarding_stages
  FOR ALL
  USING (
    tenant_id = current_tenant_id()
    AND user_has_permission('manage_onboarding')
  )
  WITH CHECK (
    tenant_id = current_tenant_id()
    AND user_has_permission('manage_onboarding')
  );

-- ===== TASKS · herda read; write inclui owner para concluir suas tasks =====

DROP POLICY IF EXISTS onboarding_tasks_read ON onboarding_tasks;
CREATE POLICY onboarding_tasks_read ON onboarding_tasks
  FOR SELECT
  USING (
    tenant_id = current_tenant_id()
    AND onboarding_can_read(onboarding_id) = TRUE
  );

DROP POLICY IF EXISTS onboarding_tasks_owner_complete ON onboarding_tasks;
CREATE POLICY onboarding_tasks_owner_complete ON onboarding_tasks
  FOR UPDATE
  USING (
    tenant_id = current_tenant_id()
    AND EXISTS (
      SELECT 1 FROM onboardings o
      WHERE o.id = onboarding_tasks.onboarding_id
        AND o.user_id = current_user_id()
        AND o.status NOT IN ('completed', 'canceled')
    )
  )
  WITH CHECK (
    tenant_id = current_tenant_id()
  );

DROP POLICY IF EXISTS onboarding_tasks_rh_dir_write ON onboarding_tasks;
CREATE POLICY onboarding_tasks_rh_dir_write ON onboarding_tasks
  FOR ALL
  USING (
    tenant_id = current_tenant_id()
    AND user_has_permission('manage_onboarding')
  )
  WITH CHECK (
    tenant_id = current_tenant_id()
    AND user_has_permission('manage_onboarding')
  );

-- ============================================================================
-- GRANTS
-- ============================================================================

GRANT SELECT, INSERT, UPDATE, DELETE ON onb_templates       TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON onb_template_stages TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON onb_template_tasks  TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON onboardings         TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON onboarding_stages   TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON onboarding_tasks    TO authenticated;

GRANT EXECUTE ON FUNCTION onboarding_can_read                       TO authenticated;
GRANT EXECUTE ON FUNCTION rpc_onb_template_create                   TO authenticated;
GRANT EXECUTE ON FUNCTION rpc_onb_template_update                   TO authenticated;
GRANT EXECUTE ON FUNCTION rpc_onb_template_stage_add                TO authenticated;
GRANT EXECUTE ON FUNCTION rpc_onb_template_task_add                 TO authenticated;
GRANT EXECUTE ON FUNCTION rpc_onb_template_list                     TO authenticated;
GRANT EXECUTE ON FUNCTION rpc_onb_template_get                      TO authenticated;
GRANT EXECUTE ON FUNCTION rpc_onboarding_create_from_template       TO authenticated;
GRANT EXECUTE ON FUNCTION rpc_onboarding_create_blank               TO authenticated;
GRANT EXECUTE ON FUNCTION rpc_onboarding_stage_add                  TO authenticated;
GRANT EXECUTE ON FUNCTION rpc_onboarding_task_add                   TO authenticated;
GRANT EXECUTE ON FUNCTION rpc_onboarding_task_complete              TO authenticated;
GRANT EXECUTE ON FUNCTION rpc_onboarding_task_uncomplete            TO authenticated;
GRANT EXECUTE ON FUNCTION rpc_onboarding_change_status              TO authenticated;
GRANT EXECUTE ON FUNCTION rpc_onboarding_list                       TO authenticated;
GRANT EXECUTE ON FUNCTION rpc_onboarding_get_by_id                  TO authenticated;

-- ============================================================================
-- COMENTARIOS
-- ============================================================================

COMMENT ON TABLE onb_templates IS 'Templates reutilizaveis de onboarding (opcionais)';
COMMENT ON TABLE onb_template_stages IS 'Etapas do template (Documentacao, Treinamentos, etc)';
COMMENT ON TABLE onb_template_tasks IS 'Tasks do template · copiadas para onboarding_tasks ao instanciar';
COMMENT ON TABLE onboardings IS 'Onboarding individual · 1 ativo por user (UNIQUE parcial)';
COMMENT ON TABLE onboarding_stages IS 'Etapas concretas do onboarding (com datas calculadas)';
COMMENT ON TABLE onboarding_tasks IS 'Tasks do onboarding · checklist de conclusao';

COMMENT ON COLUMN onboardings.source_template_id IS 'NULL se foi criado em branco';
COMMENT ON COLUMN onboardings.tasks_required IS 'Denormalizado · count(*) WHERE is_required=TRUE';
COMMENT ON COLUMN onboardings.manager_id_snapshot IS 'Snapshot do gestor na criacao';

COMMENT ON FUNCTION onboarding_can_read IS 'Helper RLS: caller e owner/manager/RH-Dir do onboarding?';

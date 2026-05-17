-- ============================================================================
-- R2 People · Schema 9-Box v1 · Sessao A2
-- ============================================================================
-- Modulo de avaliacao 9-Box (matriz potencial x performance)
--
-- Decisoes da Sessao A2:
--   - Grid configuravel por tenant (3x3 ou 5x5)
--   - 5 criterios livres por eixo (potencial / performance), com pesos
--   - Auto-avaliacao + gestor · gestor decide o score final (auto e input)
--   - Ciclos formais + avaliacoes ad-hoc fora de ciclo (cycle_id NULL)
--   - Justificativa obrigatoria SO em caixas extremas (toggle por tenant)
--   - Snapshot imutavel ao finalizar · audit_log generico para alteracoes
--   - Visibilidade: avaliado ve so a sua, gestor ve o time, RH ve tudo
--   - Default 3x3 com rotulos GE-McKinsey em PT-BR
--   - require_self_assessment configuravel por tenant
--
-- Pre-requisitos:
--   - r2_people_schema_base_v1.sql aplicado
--   - r2_people_seed_base_v1.sql aplicado
--   - r2_people_schema_modules_v1.sql aplicado (Sessao L)
--   - r2_people_seed_modules_v1.sql aplicado (modulo 'ninebox' precisa estar registrado · ver seed)
--   - r2_people_patch_a1_module_checks.sql aplicado (Sessao A1) · padrao de checks
--
-- Ordem de aplicacao:
--   1. r2_people_schema_ninebox_v1.sql           (este arquivo)
--   2. r2_people_seed_ninebox_v1.sql             (modulo + permissoes + defaults)
--   3. r2_people_rls_policies_ninebox_tests.sql  (opcional)
-- ============================================================================

-- ============================================================================
-- ENUMS
-- ============================================================================

DO $$ BEGIN
  CREATE TYPE ninebox_grid_size AS ENUM ('3x3', '5x5');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  CREATE TYPE ninebox_axis AS ENUM ('potential', 'performance');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  CREATE TYPE ninebox_evaluator_kind AS ENUM ('self', 'manager');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  CREATE TYPE ninebox_evaluation_status AS ENUM (
    'draft',         -- iniciada, ninguem submeteu
    'self_done',     -- self submeteu, aguarda gestor
    'manager_done',  -- gestor submeteu, aguarda finalizacao
    'finalized',     -- snapshot gerado, fechada
    'canceled'       -- cancelada antes de finalizar
  );
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  CREATE TYPE ninebox_cycle_status AS ENUM ('planning', 'active', 'closed');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- ============================================================================
-- TABELAS
-- ============================================================================

-- ----------------------------------------------------------------------------
-- ninebox_settings · 1 linha por tenant · default criado no seed do modulo
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS ninebox_settings (
  tenant_id                       UUID PRIMARY KEY REFERENCES tenants(id) ON DELETE CASCADE,
  grid_size                       ninebox_grid_size NOT NULL DEFAULT '3x3',

  -- Criterios por eixo (1-5 itens em cada lado · soma de pesos deve dar 100)
  -- Estrutura: [{name: text, weight: int (1-100)}, ...]
  potential_criteria              JSONB NOT NULL DEFAULT '[]'::JSONB,
  performance_criteria            JSONB NOT NULL DEFAULT '[]'::JSONB,

  -- Rotulos das caixas (texto exibido em cada celula)
  -- Estrutura: { "row_col": "label", ... } ex: { "1_1": "Risco", "3_3": "Estrela" }
  box_labels                      JSONB NOT NULL DEFAULT '{}'::JSONB,

  -- Politicas
  force_justification_extremes    BOOLEAN NOT NULL DEFAULT TRUE,
  min_justification_length        INT NOT NULL DEFAULT 50 CHECK (min_justification_length BETWEEN 0 AND 5000),
  require_self_assessment         BOOLEAN NOT NULL DEFAULT FALSE,

  created_at                      TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at                      TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_by                      UUID REFERENCES app_users(id) ON DELETE SET NULL,

  -- Validacao basica de criterios (max 5 cada · pode ser vazio antes da config)
  CONSTRAINT chk_potential_criteria_max5
    CHECK (jsonb_array_length(potential_criteria) BETWEEN 0 AND 5),
  CONSTRAINT chk_performance_criteria_max5
    CHECK (jsonb_array_length(performance_criteria) BETWEEN 0 AND 5)
);

COMMENT ON TABLE ninebox_settings IS 'Configuracao do 9-Box por tenant';
COMMENT ON COLUMN ninebox_settings.potential_criteria IS 'Array JSONB [{name, weight}] · max 5 itens · soma weight=100';
COMMENT ON COLUMN ninebox_settings.performance_criteria IS 'Array JSONB [{name, weight}] · max 5 itens · soma weight=100';
COMMENT ON COLUMN ninebox_settings.box_labels IS 'Object JSONB {"row_col": "label"} · row e col 1-indexed';

-- ----------------------------------------------------------------------------
-- ninebox_cycles · janelas de avaliacao formal por tenant
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS ninebox_cycles (
  id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id           UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,

  name                VARCHAR(100) NOT NULL,
  description         TEXT,
  reference_year      INT,

  start_date          DATE NOT NULL,
  end_date            DATE NOT NULL,
  status              ninebox_cycle_status NOT NULL DEFAULT 'planning',

  created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
  created_by          UUID REFERENCES app_users(id) ON DELETE SET NULL,
  closed_at           TIMESTAMPTZ,
  closed_by           UUID REFERENCES app_users(id) ON DELETE SET NULL,

  CONSTRAINT chk_dates CHECK (end_date >= start_date),
  CONSTRAINT chk_closed_when_status CHECK (
    (status = 'closed' AND closed_at IS NOT NULL) OR
    (status <> 'closed' AND closed_at IS NULL)
  )
);

CREATE INDEX IF NOT EXISTS idx_ninebox_cycles_tenant ON ninebox_cycles(tenant_id);
CREATE INDEX IF NOT EXISTS idx_ninebox_cycles_status ON ninebox_cycles(tenant_id, status);

COMMENT ON TABLE ninebox_cycles IS 'Janelas formais de avaliacao 9-Box';

-- ----------------------------------------------------------------------------
-- ninebox_evaluations · uma avaliacao de um subject (avaliado)
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS ninebox_evaluations (
  id                          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id                   UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,

  subject_id                  UUID NOT NULL REFERENCES app_users(id) ON DELETE CASCADE,
  manager_id                  UUID NOT NULL REFERENCES app_users(id) ON DELETE RESTRICT,

  cycle_id                    UUID REFERENCES ninebox_cycles(id) ON DELETE RESTRICT,
  is_adhoc                    BOOLEAN NOT NULL DEFAULT FALSE,

  status                      ninebox_evaluation_status NOT NULL DEFAULT 'draft',

  -- Snapshot de configuracao no momento de criacao (imutavel)
  -- Garante que mudancas em ninebox_settings nao quebram avaliacoes em curso
  grid_size_snapshot          ninebox_grid_size NOT NULL,
  potential_criteria_snapshot JSONB NOT NULL,
  performance_criteria_snapshot JSONB NOT NULL,
  box_labels_snapshot         JSONB NOT NULL DEFAULT '{}'::JSONB,

  -- Resultado final (preenchido pelo gestor · auto e input nao decide)
  final_potential_score       NUMERIC(5,2),
  final_performance_score     NUMERIC(5,2),
  final_box_row               INT,
  final_box_col               INT,
  final_box_label             VARCHAR(100),
  justification               TEXT,

  -- Timestamps
  created_at                  TIMESTAMPTZ NOT NULL DEFAULT now(),
  created_by                  UUID REFERENCES app_users(id) ON DELETE SET NULL,
  self_submitted_at           TIMESTAMPTZ,
  manager_submitted_at        TIMESTAMPTZ,
  finalized_at                TIMESTAMPTZ,
  canceled_at                 TIMESTAMPTZ,
  canceled_by                 UUID REFERENCES app_users(id) ON DELETE SET NULL,
  cancel_reason               TEXT,

  CONSTRAINT chk_adhoc_consistency CHECK (
    (is_adhoc = TRUE AND cycle_id IS NULL) OR
    (is_adhoc = FALSE AND cycle_id IS NOT NULL)
  ),
  CONSTRAINT chk_box_coords CHECK (
    (final_box_row IS NULL AND final_box_col IS NULL) OR
    (final_box_row BETWEEN 1 AND 5 AND final_box_col BETWEEN 1 AND 5)
  ),
  CONSTRAINT chk_self_not_manager CHECK (subject_id <> manager_id OR is_adhoc = TRUE)
  -- subject_id = manager_id permitido apenas em modo ad-hoc (autoaplicacao
  -- excepcional, ex: liderado avaliando a si mesmo durante calibracao especial)
);

-- 1 avaliacao por (tenant, subject, cycle) quando ha ciclo ativo
-- ad-hoc nao tem essa restricao (pode ter varias)
CREATE UNIQUE INDEX IF NOT EXISTS uq_ninebox_eval_subject_cycle
  ON ninebox_evaluations(tenant_id, subject_id, cycle_id)
  WHERE cycle_id IS NOT NULL AND status <> 'canceled';

CREATE INDEX IF NOT EXISTS idx_ninebox_eval_tenant_subject ON ninebox_evaluations(tenant_id, subject_id);
CREATE INDEX IF NOT EXISTS idx_ninebox_eval_manager ON ninebox_evaluations(manager_id);
CREATE INDEX IF NOT EXISTS idx_ninebox_eval_cycle ON ninebox_evaluations(cycle_id);
CREATE INDEX IF NOT EXISTS idx_ninebox_eval_status ON ninebox_evaluations(tenant_id, status);

COMMENT ON TABLE ninebox_evaluations IS 'Avaliacao 9-Box · 1 por (subject,cycle) ou ad-hoc';
COMMENT ON COLUMN ninebox_evaluations.grid_size_snapshot IS 'Snapshot da config no momento da criacao · imutavel';

-- ----------------------------------------------------------------------------
-- ninebox_evaluation_scores · notas detalhadas por criterio e avaliador
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS ninebox_evaluation_scores (
  id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  evaluation_id       UUID NOT NULL REFERENCES ninebox_evaluations(id) ON DELETE CASCADE,
  tenant_id           UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,

  axis                ninebox_axis NOT NULL,
  evaluator_kind      ninebox_evaluator_kind NOT NULL,

  criterion_index     INT NOT NULL CHECK (criterion_index BETWEEN 1 AND 5),
  criterion_name      VARCHAR(100) NOT NULL,
  criterion_weight    INT NOT NULL CHECK (criterion_weight BETWEEN 1 AND 100),

  score               NUMERIC(5,2) NOT NULL CHECK (score BETWEEN 1 AND 5),
  note                TEXT,

  created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at          TIMESTAMPTZ NOT NULL DEFAULT now(),

  UNIQUE (evaluation_id, axis, evaluator_kind, criterion_index)
);

CREATE INDEX IF NOT EXISTS idx_ninebox_scores_eval ON ninebox_evaluation_scores(evaluation_id);
CREATE INDEX IF NOT EXISTS idx_ninebox_scores_tenant ON ninebox_evaluation_scores(tenant_id);

COMMENT ON TABLE ninebox_evaluation_scores IS 'Notas por criterio em cada eixo · self e manager';

-- ----------------------------------------------------------------------------
-- ninebox_evaluation_snapshots · cópia imutável ao finalizar
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS ninebox_evaluation_snapshots (
  id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  evaluation_id       UUID NOT NULL REFERENCES ninebox_evaluations(id) ON DELETE CASCADE,
  tenant_id           UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  subject_id          UUID NOT NULL REFERENCES app_users(id) ON DELETE CASCADE,

  -- Payload completo da avaliacao no momento da finalizacao
  -- Inclui: settings_snapshot, scores (self + manager), final_box, justification, etc.
  snapshot_payload    JSONB NOT NULL,

  -- Versao do snapshot (toda re-finalizacao gera versao incrementada)
  version             INT NOT NULL DEFAULT 1,

  created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
  created_by          UUID REFERENCES app_users(id) ON DELETE SET NULL,

  UNIQUE (evaluation_id, version)
);

CREATE INDEX IF NOT EXISTS idx_ninebox_snap_subject ON ninebox_evaluation_snapshots(tenant_id, subject_id);
CREATE INDEX IF NOT EXISTS idx_ninebox_snap_eval ON ninebox_evaluation_snapshots(evaluation_id);

COMMENT ON TABLE ninebox_evaluation_snapshots IS 'Snapshot imutavel · gerado em finalize · 1+ por evaluation';

-- ============================================================================
-- TRIGGERS · updated_at em settings e scores
-- ============================================================================

CREATE OR REPLACE FUNCTION ninebox_set_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_ninebox_settings_updated ON ninebox_settings;
CREATE TRIGGER trg_ninebox_settings_updated
  BEFORE UPDATE ON ninebox_settings
  FOR EACH ROW EXECUTE FUNCTION ninebox_set_updated_at();

DROP TRIGGER IF EXISTS trg_ninebox_scores_updated ON ninebox_evaluation_scores;
CREATE TRIGGER trg_ninebox_scores_updated
  BEFORE UPDATE ON ninebox_evaluation_scores
  FOR EACH ROW EXECUTE FUNCTION ninebox_set_updated_at();

-- ============================================================================
-- HELPERS · funcoes internas reutilizadas pelas RPCs
-- ============================================================================

-- ----------------------------------------------------------------------------
-- ninebox_grid_max · 3 ou 5 dependendo do grid_size
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION ninebox_grid_max(p_grid_size ninebox_grid_size)
RETURNS INT
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT CASE p_grid_size WHEN '3x3' THEN 3 WHEN '5x5' THEN 5 END;
$$;

-- ----------------------------------------------------------------------------
-- ninebox_validate_criteria · valida estrutura JSONB de criterios
-- Retorna texto de erro ou NULL se valido
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION ninebox_validate_criteria(p_criteria JSONB)
RETURNS TEXT
LANGUAGE plpgsql
IMMUTABLE
AS $$
DECLARE
  v_total INT := 0;
  v_count INT;
  v_item JSONB;
  v_name TEXT;
  v_weight INT;
BEGIN
  IF jsonb_typeof(p_criteria) <> 'array' THEN
    RETURN 'criteria_must_be_array';
  END IF;

  v_count := jsonb_array_length(p_criteria);
  IF v_count < 1 OR v_count > 5 THEN
    RETURN 'criteria_count_must_be_1_to_5';
  END IF;

  FOR v_item IN SELECT * FROM jsonb_array_elements(p_criteria)
  LOOP
    v_name := v_item ->> 'name';
    IF v_name IS NULL OR length(trim(v_name)) = 0 THEN
      RETURN 'criterion_name_required';
    END IF;
    IF length(v_name) > 100 THEN
      RETURN 'criterion_name_too_long';
    END IF;

    BEGIN
      v_weight := (v_item ->> 'weight')::INT;
    EXCEPTION WHEN OTHERS THEN
      RETURN 'criterion_weight_must_be_int';
    END;

    IF v_weight IS NULL OR v_weight < 1 OR v_weight > 100 THEN
      RETURN 'criterion_weight_out_of_range';
    END IF;

    v_total := v_total + v_weight;
  END LOOP;

  IF v_total <> 100 THEN
    RETURN 'criteria_weights_must_sum_100';
  END IF;

  RETURN NULL;
END;
$$;

-- ----------------------------------------------------------------------------
-- ninebox_score_to_box · converte score 1-5 para coordenada da grid
-- 3x3: [1,2.33] -> 1, (2.33,3.67] -> 2, (3.67,5] -> 3
-- 5x5: floor mas no minimo 1, no maximo 5
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION ninebox_score_to_box(
  p_score NUMERIC,
  p_grid_size ninebox_grid_size
)
RETURNS INT
LANGUAGE plpgsql
IMMUTABLE
AS $$
DECLARE
  v_max INT;
BEGIN
  IF p_score IS NULL THEN RETURN NULL; END IF;
  v_max := ninebox_grid_max(p_grid_size);

  IF v_max = 3 THEN
    -- 1.00-2.33 -> 1, 2.34-3.66 -> 2, 3.67-5.00 -> 3
    IF p_score <= 2.33 THEN RETURN 1;
    ELSIF p_score <= 3.66 THEN RETURN 2;
    ELSE RETURN 3;
    END IF;
  ELSE
    -- 5x5: 1.00-1.80, 1.81-2.60, 2.61-3.40, 3.41-4.20, 4.21-5.00
    IF p_score <= 1.80 THEN RETURN 1;
    ELSIF p_score <= 2.60 THEN RETURN 2;
    ELSIF p_score <= 3.40 THEN RETURN 3;
    ELSIF p_score <= 4.20 THEN RETURN 4;
    ELSE RETURN 5;
    END IF;
  END IF;
END;
$$;

-- ----------------------------------------------------------------------------
-- ninebox_compute_axis_score · media ponderada das notas do gestor para um eixo
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION ninebox_compute_axis_score(
  p_evaluation_id UUID,
  p_axis ninebox_axis,
  p_evaluator ninebox_evaluator_kind
)
RETURNS NUMERIC
LANGUAGE sql
STABLE
AS $$
  SELECT ROUND(SUM(score * criterion_weight)::NUMERIC / NULLIF(SUM(criterion_weight), 0), 2)
  FROM ninebox_evaluation_scores
  WHERE evaluation_id = p_evaluation_id
    AND axis = p_axis
    AND evaluator_kind = p_evaluator;
$$;

-- ----------------------------------------------------------------------------
-- ninebox_is_extreme_box · TRUE se a caixa e canto da matriz
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION ninebox_is_extreme_box(
  p_row INT,
  p_col INT,
  p_grid_size ninebox_grid_size
)
RETURNS BOOLEAN
LANGUAGE plpgsql
IMMUTABLE
AS $$
DECLARE
  v_max INT;
BEGIN
  IF p_row IS NULL OR p_col IS NULL THEN RETURN FALSE; END IF;
  v_max := ninebox_grid_max(p_grid_size);
  RETURN (p_row = 1 OR p_row = v_max) AND (p_col = 1 OR p_col = v_max);
END;
$$;

-- ----------------------------------------------------------------------------
-- ninebox_can_view_evaluation · regras de visibilidade
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION ninebox_can_view_evaluation(p_evaluation_id UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user UUID := current_user_id();
  v_role app_user_role;
  v_subject UUID;
  v_manager UUID;
  v_eval_tenant UUID;
  v_user_tenant UUID;
BEGIN
  IF v_user IS NULL THEN RETURN FALSE; END IF;

  SELECT subject_id, manager_id, tenant_id
    INTO v_subject, v_manager, v_eval_tenant
  FROM ninebox_evaluations WHERE id = p_evaluation_id;
  IF v_subject IS NULL THEN RETURN FALSE; END IF;

  SELECT role, tenant_id INTO v_role, v_user_tenant FROM app_users WHERE id = v_user;

  -- super_admin global
  IF v_role = 'super_admin' THEN RETURN TRUE; END IF;

  -- so usuarios do mesmo tenant
  IF v_user_tenant <> v_eval_tenant THEN RETURN FALSE; END IF;

  -- avaliado ve a propria
  IF v_user = v_subject THEN RETURN TRUE; END IF;

  -- gestor direto da avaliacao
  IF v_user = v_manager THEN RETURN TRUE; END IF;

  -- diretoria/RH veem todas do tenant
  IF v_role IN ('diretoria', 'rh') THEN RETURN TRUE; END IF;

  -- gestor indireto · sobe a cadeia de manager_id ate raiz
  IF EXISTS (
    WITH RECURSIVE chain AS (
      SELECT id, manager_id FROM app_users WHERE id = v_subject
      UNION ALL
      SELECT u.id, u.manager_id FROM app_users u
        JOIN chain c ON u.id = c.manager_id
    )
    SELECT 1 FROM chain WHERE manager_id = v_user
  ) THEN
    RETURN TRUE;
  END IF;

  RETURN FALSE;
END;
$$;

-- ============================================================================
-- RPCs · 13 funcoes
-- ============================================================================

-- ----------------------------------------------------------------------------
-- rpc_ninebox_settings_get · obtem config do tenant atual
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION rpc_ninebox_settings_get()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user UUID := current_user_id();
  v_tenant UUID := current_tenant_id();
  v_settings ninebox_settings;
BEGIN
  IF v_user IS NULL OR v_tenant IS NULL THEN
    RETURN jsonb_build_object('error', 'not_authenticated');
  END IF;

  IF NOT module_is_active_for_me('ninebox') THEN
    RETURN jsonb_build_object('error', 'module_inactive', 'module', 'ninebox');
  END IF;

  SELECT * INTO v_settings FROM ninebox_settings WHERE tenant_id = v_tenant;
  IF v_settings IS NULL THEN
    -- nunca aconteceu o INSERT no seed/ativacao · cria default
    INSERT INTO ninebox_settings (tenant_id) VALUES (v_tenant)
    RETURNING * INTO v_settings;
  END IF;

  RETURN jsonb_build_object(
    'ok', TRUE,
    'settings', jsonb_build_object(
      'tenant_id', v_settings.tenant_id,
      'grid_size', v_settings.grid_size,
      'potential_criteria', v_settings.potential_criteria,
      'performance_criteria', v_settings.performance_criteria,
      'box_labels', v_settings.box_labels,
      'force_justification_extremes', v_settings.force_justification_extremes,
      'min_justification_length', v_settings.min_justification_length,
      'require_self_assessment', v_settings.require_self_assessment,
      'updated_at', v_settings.updated_at
    )
  );
END;
$$;

-- ----------------------------------------------------------------------------
-- rpc_ninebox_settings_update · so RH/diretoria
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION rpc_ninebox_settings_update(p_payload JSONB)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user UUID := current_user_id();
  v_tenant UUID := current_tenant_id();
  v_role app_user_role;
  v_err TEXT;
  v_grid ninebox_grid_size;
  v_potential JSONB;
  v_performance JSONB;
  v_labels JSONB;
  v_force_just BOOLEAN;
  v_min_just INT;
  v_require_self BOOLEAN;
BEGIN
  IF v_user IS NULL OR v_tenant IS NULL THEN
    RETURN jsonb_build_object('error', 'not_authenticated');
  END IF;

  IF NOT module_is_active_for_me('ninebox') THEN
    RETURN jsonb_build_object('error', 'module_inactive', 'module', 'ninebox');
  END IF;

  SELECT role INTO v_role FROM app_users WHERE id = v_user;
  IF v_role NOT IN ('super_admin', 'diretoria', 'rh') THEN
    RETURN jsonb_build_object('error', 'permission_denied');
  END IF;

  v_grid         := COALESCE((p_payload ->> 'grid_size')::ninebox_grid_size,
                             (SELECT grid_size FROM ninebox_settings WHERE tenant_id = v_tenant));
  v_potential    := COALESCE(p_payload -> 'potential_criteria',
                             (SELECT potential_criteria FROM ninebox_settings WHERE tenant_id = v_tenant));
  v_performance  := COALESCE(p_payload -> 'performance_criteria',
                             (SELECT performance_criteria FROM ninebox_settings WHERE tenant_id = v_tenant));
  v_labels       := COALESCE(p_payload -> 'box_labels',
                             (SELECT box_labels FROM ninebox_settings WHERE tenant_id = v_tenant));
  v_force_just   := COALESCE((p_payload ->> 'force_justification_extremes')::BOOLEAN,
                             (SELECT force_justification_extremes FROM ninebox_settings WHERE tenant_id = v_tenant));
  v_min_just     := COALESCE((p_payload ->> 'min_justification_length')::INT,
                             (SELECT min_justification_length FROM ninebox_settings WHERE tenant_id = v_tenant));
  v_require_self := COALESCE((p_payload ->> 'require_self_assessment')::BOOLEAN,
                             (SELECT require_self_assessment FROM ninebox_settings WHERE tenant_id = v_tenant));

  v_err := ninebox_validate_criteria(v_potential);
  IF v_err IS NOT NULL THEN
    RETURN jsonb_build_object('error', 'invalid_potential_criteria', 'detail', v_err);
  END IF;

  v_err := ninebox_validate_criteria(v_performance);
  IF v_err IS NOT NULL THEN
    RETURN jsonb_build_object('error', 'invalid_performance_criteria', 'detail', v_err);
  END IF;

  IF v_min_just < 0 OR v_min_just > 5000 THEN
    RETURN jsonb_build_object('error', 'invalid_min_justification_length');
  END IF;

  -- Bloqueia mudanca de grid_size se ha avaliacoes em curso
  IF v_grid <> (SELECT grid_size FROM ninebox_settings WHERE tenant_id = v_tenant)
     AND EXISTS (
       SELECT 1 FROM ninebox_evaluations
       WHERE tenant_id = v_tenant AND status NOT IN ('finalized', 'canceled')
     )
  THEN
    RETURN jsonb_build_object('error', 'grid_size_change_blocked_by_open_evaluations');
  END IF;

  UPDATE ninebox_settings SET
    grid_size = v_grid,
    potential_criteria = v_potential,
    performance_criteria = v_performance,
    box_labels = v_labels,
    force_justification_extremes = v_force_just,
    min_justification_length = v_min_just,
    require_self_assessment = v_require_self,
    updated_by = v_user
  WHERE tenant_id = v_tenant;

  RETURN jsonb_build_object('ok', TRUE);
END;
$$;

-- ----------------------------------------------------------------------------
-- rpc_ninebox_cycle_create · RH/diretoria · cria ciclo
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION rpc_ninebox_cycle_create(
  p_name VARCHAR,
  p_start_date DATE,
  p_end_date DATE,
  p_reference_year INT DEFAULT NULL,
  p_description TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user UUID := current_user_id();
  v_tenant UUID := current_tenant_id();
  v_role app_user_role;
  v_id UUID;
BEGIN
  IF v_user IS NULL OR v_tenant IS NULL THEN
    RETURN jsonb_build_object('error', 'not_authenticated');
  END IF;
  IF NOT module_is_active_for_me('ninebox') THEN
    RETURN jsonb_build_object('error', 'module_inactive', 'module', 'ninebox');
  END IF;

  SELECT role INTO v_role FROM app_users WHERE id = v_user;
  IF v_role NOT IN ('super_admin', 'diretoria', 'rh') THEN
    RETURN jsonb_build_object('error', 'permission_denied');
  END IF;

  IF p_name IS NULL OR length(trim(p_name)) = 0 THEN
    RETURN jsonb_build_object('error', 'name_required');
  END IF;
  IF p_start_date IS NULL OR p_end_date IS NULL OR p_end_date < p_start_date THEN
    RETURN jsonb_build_object('error', 'invalid_dates');
  END IF;

  INSERT INTO ninebox_cycles (
    tenant_id, name, description, reference_year,
    start_date, end_date, status, created_by
  ) VALUES (
    v_tenant, p_name, p_description, p_reference_year,
    p_start_date, p_end_date, 'planning', v_user
  ) RETURNING id INTO v_id;

  RETURN jsonb_build_object('ok', TRUE, 'cycle_id', v_id);
END;
$$;

-- ----------------------------------------------------------------------------
-- rpc_ninebox_cycle_update · RH/diretoria · atualiza nome, datas, status
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION rpc_ninebox_cycle_update(
  p_cycle_id UUID,
  p_payload JSONB
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user UUID := current_user_id();
  v_tenant UUID := current_tenant_id();
  v_role app_user_role;
  v_cycle ninebox_cycles;
  v_new_status ninebox_cycle_status;
BEGIN
  IF v_user IS NULL OR v_tenant IS NULL THEN
    RETURN jsonb_build_object('error', 'not_authenticated');
  END IF;
  IF NOT module_is_active_for_me('ninebox') THEN
    RETURN jsonb_build_object('error', 'module_inactive', 'module', 'ninebox');
  END IF;

  SELECT role INTO v_role FROM app_users WHERE id = v_user;
  IF v_role NOT IN ('super_admin', 'diretoria', 'rh') THEN
    RETURN jsonb_build_object('error', 'permission_denied');
  END IF;

  SELECT * INTO v_cycle FROM ninebox_cycles
    WHERE id = p_cycle_id AND tenant_id = v_tenant;
  IF v_cycle IS NULL THEN
    RETURN jsonb_build_object('error', 'cycle_not_found');
  END IF;

  IF v_cycle.status = 'closed' AND v_role NOT IN ('super_admin', 'diretoria') THEN
    RETURN jsonb_build_object('error', 'cycle_closed');
  END IF;

  v_new_status := COALESCE((p_payload ->> 'status')::ninebox_cycle_status, v_cycle.status);

  UPDATE ninebox_cycles SET
    name           = COALESCE(p_payload ->> 'name', v_cycle.name),
    description    = COALESCE(p_payload ->> 'description', v_cycle.description),
    reference_year = COALESCE((p_payload ->> 'reference_year')::INT, v_cycle.reference_year),
    start_date     = COALESCE((p_payload ->> 'start_date')::DATE, v_cycle.start_date),
    end_date       = COALESCE((p_payload ->> 'end_date')::DATE, v_cycle.end_date),
    status         = v_new_status,
    closed_at      = CASE WHEN v_new_status = 'closed' AND v_cycle.status <> 'closed'
                          THEN now()
                          WHEN v_new_status <> 'closed' THEN NULL
                          ELSE v_cycle.closed_at END,
    closed_by      = CASE WHEN v_new_status = 'closed' AND v_cycle.status <> 'closed'
                          THEN v_user
                          WHEN v_new_status <> 'closed' THEN NULL
                          ELSE v_cycle.closed_by END
  WHERE id = p_cycle_id;

  RETURN jsonb_build_object('ok', TRUE);
END;
$$;

-- ----------------------------------------------------------------------------
-- rpc_ninebox_cycle_list · qualquer user autenticado do tenant ve os ciclos
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION rpc_ninebox_cycle_list(p_status ninebox_cycle_status DEFAULT NULL)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user UUID := current_user_id();
  v_tenant UUID := current_tenant_id();
  v_cycles JSONB;
BEGIN
  IF v_user IS NULL OR v_tenant IS NULL THEN
    RETURN jsonb_build_object('error', 'not_authenticated');
  END IF;
  IF NOT module_is_active_for_me('ninebox') THEN
    RETURN jsonb_build_object('error', 'module_inactive', 'module', 'ninebox');
  END IF;

  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'id', id, 'name', name, 'description', description,
    'reference_year', reference_year,
    'start_date', start_date, 'end_date', end_date, 'status', status,
    'created_at', created_at, 'closed_at', closed_at
  ) ORDER BY start_date DESC), '[]'::JSONB) INTO v_cycles
  FROM ninebox_cycles
  WHERE tenant_id = v_tenant
    AND (p_status IS NULL OR status = p_status);

  RETURN jsonb_build_object('ok', TRUE, 'cycles', v_cycles);
END;
$$;

-- ----------------------------------------------------------------------------
-- rpc_ninebox_evaluation_start · gestor inicia avaliacao para liderado
-- (ou RH/dir para qualquer subject) · tira snapshot da config
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION rpc_ninebox_evaluation_start(
  p_subject_id UUID,
  p_cycle_id UUID DEFAULT NULL,
  p_is_adhoc BOOLEAN DEFAULT FALSE
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user UUID := current_user_id();
  v_tenant UUID := current_tenant_id();
  v_role app_user_role;
  v_subject app_users;
  v_cycle ninebox_cycles;
  v_settings ninebox_settings;
  v_manager_id UUID;
  v_eval_id UUID;
BEGIN
  IF v_user IS NULL OR v_tenant IS NULL THEN
    RETURN jsonb_build_object('error', 'not_authenticated');
  END IF;
  IF NOT module_is_active_for_me('ninebox') THEN
    RETURN jsonb_build_object('error', 'module_inactive', 'module', 'ninebox');
  END IF;

  SELECT * INTO v_subject FROM app_users WHERE id = p_subject_id AND tenant_id = v_tenant;
  IF v_subject IS NULL THEN
    RETURN jsonb_build_object('error', 'subject_not_found');
  END IF;

  -- escopo do recurso · modulo precisa estar ativo na wu do subject tambem
  IF NOT module_is_active_for_user('ninebox', p_subject_id) THEN
    RETURN jsonb_build_object('error', 'module_inactive_at_resource_scope', 'module', 'ninebox');
  END IF;

  SELECT role INTO v_role FROM app_users WHERE id = v_user;
  v_manager_id := v_subject.manager_id;

  -- Permissao: super_admin/diretoria/rh sempre, ou ser o manager do subject
  IF v_role NOT IN ('super_admin', 'diretoria', 'rh') AND v_user <> v_manager_id THEN
    RETURN jsonb_build_object('error', 'permission_denied');
  END IF;

  IF v_manager_id IS NULL THEN
    -- sem gestor cadastrado · forca o caller a ser o "manager" virtual (RH/dir)
    IF v_role NOT IN ('super_admin', 'diretoria', 'rh') THEN
      RETURN jsonb_build_object('error', 'subject_has_no_manager');
    END IF;
    v_manager_id := v_user;
  END IF;

  IF p_is_adhoc = FALSE THEN
    IF p_cycle_id IS NULL THEN
      RETURN jsonb_build_object('error', 'cycle_required_when_not_adhoc');
    END IF;
    SELECT * INTO v_cycle FROM ninebox_cycles
      WHERE id = p_cycle_id AND tenant_id = v_tenant;
    IF v_cycle IS NULL THEN
      RETURN jsonb_build_object('error', 'cycle_not_found');
    END IF;
    IF v_cycle.status NOT IN ('planning', 'active') THEN
      RETURN jsonb_build_object('error', 'cycle_not_open');
    END IF;
    -- ja existe avaliacao nao cancelada para esse subject neste ciclo?
    IF EXISTS (
      SELECT 1 FROM ninebox_evaluations
      WHERE tenant_id = v_tenant
        AND subject_id = p_subject_id
        AND cycle_id = p_cycle_id
        AND status <> 'canceled'
    ) THEN
      RETURN jsonb_build_object('error', 'evaluation_already_exists_for_cycle');
    END IF;
  END IF;

  SELECT * INTO v_settings FROM ninebox_settings WHERE tenant_id = v_tenant;
  IF v_settings IS NULL THEN
    INSERT INTO ninebox_settings (tenant_id) VALUES (v_tenant) RETURNING * INTO v_settings;
  END IF;

  IF jsonb_array_length(v_settings.potential_criteria) = 0
     OR jsonb_array_length(v_settings.performance_criteria) = 0 THEN
    RETURN jsonb_build_object('error', 'criteria_not_configured');
  END IF;

  INSERT INTO ninebox_evaluations (
    tenant_id, subject_id, manager_id, cycle_id, is_adhoc,
    status,
    grid_size_snapshot, potential_criteria_snapshot,
    performance_criteria_snapshot, box_labels_snapshot,
    created_by
  ) VALUES (
    v_tenant, p_subject_id, v_manager_id,
    CASE WHEN p_is_adhoc THEN NULL ELSE p_cycle_id END,
    p_is_adhoc,
    'draft',
    v_settings.grid_size, v_settings.potential_criteria,
    v_settings.performance_criteria, v_settings.box_labels,
    v_user
  ) RETURNING id INTO v_eval_id;

  RETURN jsonb_build_object('ok', TRUE, 'evaluation_id', v_eval_id);
END;
$$;

-- ----------------------------------------------------------------------------
-- ninebox_persist_scores · helper interno · grava notas de um avaliador
-- p_scores formato: [{axis, criterion_index, score, note}, ...]
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION ninebox_persist_scores(
  p_evaluation_id UUID,
  p_evaluator ninebox_evaluator_kind,
  p_scores JSONB
)
RETURNS TEXT  -- erro ou NULL
LANGUAGE plpgsql
AS $$
DECLARE
  v_eval ninebox_evaluations;
  v_item JSONB;
  v_axis ninebox_axis;
  v_idx INT;
  v_score NUMERIC;
  v_note TEXT;
  v_max INT;
  v_criterion JSONB;
  v_name TEXT;
  v_weight INT;
BEGIN
  SELECT * INTO v_eval FROM ninebox_evaluations WHERE id = p_evaluation_id;
  IF v_eval IS NULL THEN RETURN 'evaluation_not_found'; END IF;

  v_max := ninebox_grid_max(v_eval.grid_size_snapshot);

  -- Limpa notas anteriores do mesmo avaliador (re-submit substitui)
  DELETE FROM ninebox_evaluation_scores
    WHERE evaluation_id = p_evaluation_id AND evaluator_kind = p_evaluator;

  IF jsonb_typeof(p_scores) <> 'array' THEN
    RETURN 'scores_must_be_array';
  END IF;

  FOR v_item IN SELECT * FROM jsonb_array_elements(p_scores)
  LOOP
    BEGIN
      v_axis := (v_item ->> 'axis')::ninebox_axis;
    EXCEPTION WHEN OTHERS THEN RETURN 'invalid_axis'; END;

    v_idx := (v_item ->> 'criterion_index')::INT;
    IF v_idx IS NULL OR v_idx < 1 OR v_idx > 5 THEN
      RETURN 'invalid_criterion_index';
    END IF;

    BEGIN
      v_score := (v_item ->> 'score')::NUMERIC;
    EXCEPTION WHEN OTHERS THEN RETURN 'invalid_score'; END;
    IF v_score IS NULL OR v_score < 1 OR v_score > 5 THEN
      RETURN 'invalid_score_range';
    END IF;

    -- pega name+weight do snapshot do criterio
    v_criterion := CASE v_axis
      WHEN 'potential' THEN v_eval.potential_criteria_snapshot -> (v_idx - 1)
      WHEN 'performance' THEN v_eval.performance_criteria_snapshot -> (v_idx - 1)
    END;
    IF v_criterion IS NULL THEN RETURN 'criterion_index_out_of_snapshot'; END IF;

    v_name := v_criterion ->> 'name';
    v_weight := (v_criterion ->> 'weight')::INT;
    v_note := v_item ->> 'note';

    INSERT INTO ninebox_evaluation_scores (
      evaluation_id, tenant_id, axis, evaluator_kind,
      criterion_index, criterion_name, criterion_weight,
      score, note
    ) VALUES (
      p_evaluation_id, v_eval.tenant_id, v_axis, p_evaluator,
      v_idx, v_name, v_weight,
      v_score, v_note
    );
  END LOOP;

  -- Validacao: precisa ter notas de TODOS os criterios em ambos os eixos
  IF (SELECT count(*) FROM ninebox_evaluation_scores
      WHERE evaluation_id = p_evaluation_id
        AND evaluator_kind = p_evaluator
        AND axis = 'potential')
     <> jsonb_array_length(v_eval.potential_criteria_snapshot)
  THEN
    RETURN 'incomplete_potential_scores';
  END IF;

  IF (SELECT count(*) FROM ninebox_evaluation_scores
      WHERE evaluation_id = p_evaluation_id
        AND evaluator_kind = p_evaluator
        AND axis = 'performance')
     <> jsonb_array_length(v_eval.performance_criteria_snapshot)
  THEN
    RETURN 'incomplete_performance_scores';
  END IF;

  RETURN NULL;
END;
$$;

-- ----------------------------------------------------------------------------
-- rpc_ninebox_evaluation_self_submit · avaliado submete sua auto-avaliacao
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION rpc_ninebox_evaluation_self_submit(
  p_evaluation_id UUID,
  p_scores JSONB
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user UUID := current_user_id();
  v_tenant UUID := current_tenant_id();
  v_eval ninebox_evaluations;
  v_err TEXT;
BEGIN
  IF v_user IS NULL OR v_tenant IS NULL THEN
    RETURN jsonb_build_object('error', 'not_authenticated');
  END IF;
  IF NOT module_is_active_for_me('ninebox') THEN
    RETURN jsonb_build_object('error', 'module_inactive', 'module', 'ninebox');
  END IF;

  SELECT * INTO v_eval FROM ninebox_evaluations
    WHERE id = p_evaluation_id AND tenant_id = v_tenant;
  IF v_eval IS NULL THEN
    RETURN jsonb_build_object('error', 'evaluation_not_found');
  END IF;

  IF v_user <> v_eval.subject_id THEN
    RETURN jsonb_build_object('error', 'permission_denied');
  END IF;

  IF v_eval.status NOT IN ('draft', 'self_done') THEN
    RETURN jsonb_build_object('error', 'invalid_status_for_self_submit',
                              'current_status', v_eval.status);
  END IF;

  v_err := ninebox_persist_scores(p_evaluation_id, 'self', p_scores);
  IF v_err IS NOT NULL THEN
    RETURN jsonb_build_object('error', v_err);
  END IF;

  UPDATE ninebox_evaluations SET
    status = 'self_done',
    self_submitted_at = now()
  WHERE id = p_evaluation_id;

  RETURN jsonb_build_object('ok', TRUE);
END;
$$;

-- ----------------------------------------------------------------------------
-- rpc_ninebox_evaluation_manager_submit · gestor submete · gera box final
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION rpc_ninebox_evaluation_manager_submit(
  p_evaluation_id UUID,
  p_scores JSONB,
  p_justification TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user UUID := current_user_id();
  v_tenant UUID := current_tenant_id();
  v_role app_user_role;
  v_eval ninebox_evaluations;
  v_settings ninebox_settings;
  v_err TEXT;
  v_pot_score NUMERIC;
  v_perf_score NUMERIC;
  v_row INT;
  v_col INT;
  v_label VARCHAR;
  v_extreme BOOLEAN;
BEGIN
  IF v_user IS NULL OR v_tenant IS NULL THEN
    RETURN jsonb_build_object('error', 'not_authenticated');
  END IF;
  IF NOT module_is_active_for_me('ninebox') THEN
    RETURN jsonb_build_object('error', 'module_inactive', 'module', 'ninebox');
  END IF;

  SELECT * INTO v_eval FROM ninebox_evaluations
    WHERE id = p_evaluation_id AND tenant_id = v_tenant;
  IF v_eval IS NULL THEN
    RETURN jsonb_build_object('error', 'evaluation_not_found');
  END IF;

  SELECT role INTO v_role FROM app_users WHERE id = v_user;
  IF v_user <> v_eval.manager_id AND v_role NOT IN ('super_admin', 'diretoria', 'rh') THEN
    RETURN jsonb_build_object('error', 'permission_denied');
  END IF;

  IF v_eval.status NOT IN ('draft', 'self_done', 'manager_done')
     AND NOT (v_eval.status = 'finalized' AND v_role IN ('super_admin', 'diretoria', 'rh'))
  THEN
    RETURN jsonb_build_object('error', 'invalid_status_for_manager_submit',
                              'current_status', v_eval.status);
  END IF;

  -- Politica: se require_self_assessment, status precisa ser self_done
  SELECT * INTO v_settings FROM ninebox_settings WHERE tenant_id = v_tenant;
  IF v_settings.require_self_assessment AND v_eval.status = 'draft'
     AND v_role NOT IN ('super_admin', 'diretoria') THEN
    RETURN jsonb_build_object('error', 'self_assessment_required_first');
  END IF;

  v_err := ninebox_persist_scores(p_evaluation_id, 'manager', p_scores);
  IF v_err IS NOT NULL THEN
    RETURN jsonb_build_object('error', v_err);
  END IF;

  -- Calcula scores finais (gestor decide · auto e so input)
  v_pot_score  := ninebox_compute_axis_score(p_evaluation_id, 'potential', 'manager');
  v_perf_score := ninebox_compute_axis_score(p_evaluation_id, 'performance', 'manager');

  v_row := ninebox_score_to_box(v_pot_score, v_eval.grid_size_snapshot);   -- linha = potencial (verticalmente · 1 baixo)
  v_col := ninebox_score_to_box(v_perf_score, v_eval.grid_size_snapshot);  -- coluna = performance

  v_label := v_eval.box_labels_snapshot ->> (v_row || '_' || v_col);

  v_extreme := ninebox_is_extreme_box(v_row, v_col, v_eval.grid_size_snapshot);

  -- Justificativa obrigatoria em caixa extrema
  IF v_settings.force_justification_extremes AND v_extreme THEN
    IF p_justification IS NULL OR length(trim(p_justification)) < v_settings.min_justification_length THEN
      RETURN jsonb_build_object(
        'error', 'justification_required_for_extreme_box',
        'min_length', v_settings.min_justification_length,
        'box_row', v_row, 'box_col', v_col
      );
    END IF;
  END IF;

  UPDATE ninebox_evaluations SET
    status = 'manager_done',
    manager_submitted_at = now(),
    final_potential_score = v_pot_score,
    final_performance_score = v_perf_score,
    final_box_row = v_row,
    final_box_col = v_col,
    final_box_label = v_label,
    justification = COALESCE(p_justification, justification)
  WHERE id = p_evaluation_id;

  RETURN jsonb_build_object(
    'ok', TRUE,
    'final_potential_score', v_pot_score,
    'final_performance_score', v_perf_score,
    'final_box_row', v_row,
    'final_box_col', v_col,
    'final_box_label', v_label
  );
END;
$$;

-- ----------------------------------------------------------------------------
-- rpc_ninebox_evaluation_finalize · gera snapshot imutavel · status -> finalized
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION rpc_ninebox_evaluation_finalize(p_evaluation_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user UUID := current_user_id();
  v_tenant UUID := current_tenant_id();
  v_role app_user_role;
  v_eval ninebox_evaluations;
  v_payload JSONB;
  v_self_scores JSONB;
  v_manager_scores JSONB;
  v_next_version INT;
BEGIN
  IF v_user IS NULL OR v_tenant IS NULL THEN
    RETURN jsonb_build_object('error', 'not_authenticated');
  END IF;
  IF NOT module_is_active_for_me('ninebox') THEN
    RETURN jsonb_build_object('error', 'module_inactive', 'module', 'ninebox');
  END IF;

  SELECT * INTO v_eval FROM ninebox_evaluations
    WHERE id = p_evaluation_id AND tenant_id = v_tenant;
  IF v_eval IS NULL THEN
    RETURN jsonb_build_object('error', 'evaluation_not_found');
  END IF;

  SELECT role INTO v_role FROM app_users WHERE id = v_user;
  IF v_user <> v_eval.manager_id AND v_role NOT IN ('super_admin', 'diretoria', 'rh') THEN
    RETURN jsonb_build_object('error', 'permission_denied');
  END IF;

  IF v_eval.status <> 'manager_done' THEN
    RETURN jsonb_build_object('error', 'must_be_manager_done_first', 'current_status', v_eval.status);
  END IF;

  -- Coleta scores
  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'axis', axis, 'criterion_index', criterion_index,
    'criterion_name', criterion_name, 'criterion_weight', criterion_weight,
    'score', score, 'note', note
  )), '[]'::JSONB) INTO v_self_scores
  FROM ninebox_evaluation_scores
  WHERE evaluation_id = p_evaluation_id AND evaluator_kind = 'self';

  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'axis', axis, 'criterion_index', criterion_index,
    'criterion_name', criterion_name, 'criterion_weight', criterion_weight,
    'score', score, 'note', note
  )), '[]'::JSONB) INTO v_manager_scores
  FROM ninebox_evaluation_scores
  WHERE evaluation_id = p_evaluation_id AND evaluator_kind = 'manager';

  v_payload := jsonb_build_object(
    'evaluation_id', v_eval.id,
    'subject_id', v_eval.subject_id,
    'manager_id', v_eval.manager_id,
    'cycle_id', v_eval.cycle_id,
    'is_adhoc', v_eval.is_adhoc,
    'grid_size', v_eval.grid_size_snapshot,
    'potential_criteria', v_eval.potential_criteria_snapshot,
    'performance_criteria', v_eval.performance_criteria_snapshot,
    'box_labels', v_eval.box_labels_snapshot,
    'final_potential_score', v_eval.final_potential_score,
    'final_performance_score', v_eval.final_performance_score,
    'final_box_row', v_eval.final_box_row,
    'final_box_col', v_eval.final_box_col,
    'final_box_label', v_eval.final_box_label,
    'justification', v_eval.justification,
    'self_scores', v_self_scores,
    'manager_scores', v_manager_scores,
    'self_submitted_at', v_eval.self_submitted_at,
    'manager_submitted_at', v_eval.manager_submitted_at,
    'finalized_at', now(),
    'finalized_by', v_user
  );

  SELECT COALESCE(MAX(version), 0) + 1 INTO v_next_version
  FROM ninebox_evaluation_snapshots
  WHERE evaluation_id = p_evaluation_id;

  INSERT INTO ninebox_evaluation_snapshots (
    evaluation_id, tenant_id, subject_id, snapshot_payload, version, created_by
  ) VALUES (
    p_evaluation_id, v_tenant, v_eval.subject_id, v_payload, v_next_version, v_user
  );

  UPDATE ninebox_evaluations SET
    status = 'finalized',
    finalized_at = now()
  WHERE id = p_evaluation_id;

  RETURN jsonb_build_object('ok', TRUE, 'snapshot_version', v_next_version);
END;
$$;

-- ----------------------------------------------------------------------------
-- rpc_ninebox_evaluation_cancel · cancela evaluation
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION rpc_ninebox_evaluation_cancel(
  p_evaluation_id UUID,
  p_reason TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user UUID := current_user_id();
  v_tenant UUID := current_tenant_id();
  v_role app_user_role;
  v_eval ninebox_evaluations;
BEGIN
  IF v_user IS NULL OR v_tenant IS NULL THEN
    RETURN jsonb_build_object('error', 'not_authenticated');
  END IF;
  IF NOT module_is_active_for_me('ninebox') THEN
    RETURN jsonb_build_object('error', 'module_inactive', 'module', 'ninebox');
  END IF;

  SELECT * INTO v_eval FROM ninebox_evaluations
    WHERE id = p_evaluation_id AND tenant_id = v_tenant;
  IF v_eval IS NULL THEN
    RETURN jsonb_build_object('error', 'evaluation_not_found');
  END IF;

  SELECT role INTO v_role FROM app_users WHERE id = v_user;
  IF v_user <> v_eval.manager_id AND v_role NOT IN ('super_admin', 'diretoria', 'rh') THEN
    RETURN jsonb_build_object('error', 'permission_denied');
  END IF;

  IF v_eval.status IN ('finalized', 'canceled') THEN
    RETURN jsonb_build_object('error', 'cannot_cancel_in_status', 'current_status', v_eval.status);
  END IF;

  UPDATE ninebox_evaluations SET
    status = 'canceled',
    canceled_at = now(),
    canceled_by = v_user,
    cancel_reason = p_reason
  WHERE id = p_evaluation_id;

  RETURN jsonb_build_object('ok', TRUE);
END;
$$;

-- ----------------------------------------------------------------------------
-- rpc_ninebox_evaluation_get · respeita visibilidade por papel
-- - subject ve sua propria sem detalhes do team
-- - manager/RH/dir veem completa
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION rpc_ninebox_evaluation_get(p_evaluation_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user UUID := current_user_id();
  v_tenant UUID := current_tenant_id();
  v_eval ninebox_evaluations;
  v_self_scores JSONB;
  v_manager_scores JSONB;
  v_is_subject BOOLEAN;
BEGIN
  IF v_user IS NULL OR v_tenant IS NULL THEN
    RETURN jsonb_build_object('error', 'not_authenticated');
  END IF;
  IF NOT module_is_active_for_me('ninebox') THEN
    RETURN jsonb_build_object('error', 'module_inactive', 'module', 'ninebox');
  END IF;

  SELECT * INTO v_eval FROM ninebox_evaluations
    WHERE id = p_evaluation_id AND tenant_id = v_tenant;
  IF v_eval IS NULL THEN
    RETURN jsonb_build_object('error', 'evaluation_not_found');
  END IF;

  IF NOT ninebox_can_view_evaluation(p_evaluation_id) THEN
    RETURN jsonb_build_object('error', 'permission_denied');
  END IF;

  v_is_subject := (v_user = v_eval.subject_id);

  -- subject: ve so suas auto-avaliacoes (manager_scores filtradas)
  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'axis', axis, 'criterion_index', criterion_index,
    'criterion_name', criterion_name, 'criterion_weight', criterion_weight,
    'score', score, 'note', note
  )), '[]'::JSONB) INTO v_self_scores
  FROM ninebox_evaluation_scores
  WHERE evaluation_id = p_evaluation_id AND evaluator_kind = 'self';

  IF NOT v_is_subject THEN
    SELECT COALESCE(jsonb_agg(jsonb_build_object(
      'axis', axis, 'criterion_index', criterion_index,
      'criterion_name', criterion_name, 'criterion_weight', criterion_weight,
      'score', score, 'note', note
    )), '[]'::JSONB) INTO v_manager_scores
    FROM ninebox_evaluation_scores
    WHERE evaluation_id = p_evaluation_id AND evaluator_kind = 'manager';
  ELSE
    -- subject so ve manager_scores se a evaluation foi finalizada
    IF v_eval.status = 'finalized' THEN
      SELECT COALESCE(jsonb_agg(jsonb_build_object(
        'axis', axis, 'criterion_index', criterion_index,
        'criterion_name', criterion_name, 'criterion_weight', criterion_weight,
        'score', score, 'note', note
      )), '[]'::JSONB) INTO v_manager_scores
      FROM ninebox_evaluation_scores
      WHERE evaluation_id = p_evaluation_id AND evaluator_kind = 'manager';
    ELSE
      v_manager_scores := NULL;
    END IF;
  END IF;

  RETURN jsonb_build_object(
    'ok', TRUE,
    'evaluation', jsonb_build_object(
      'id', v_eval.id,
      'subject_id', v_eval.subject_id,
      'manager_id', v_eval.manager_id,
      'cycle_id', v_eval.cycle_id,
      'is_adhoc', v_eval.is_adhoc,
      'status', v_eval.status,
      'grid_size', v_eval.grid_size_snapshot,
      'potential_criteria', v_eval.potential_criteria_snapshot,
      'performance_criteria', v_eval.performance_criteria_snapshot,
      'box_labels', v_eval.box_labels_snapshot,
      'final_potential_score', v_eval.final_potential_score,
      'final_performance_score', v_eval.final_performance_score,
      'final_box_row', v_eval.final_box_row,
      'final_box_col', v_eval.final_box_col,
      'final_box_label', v_eval.final_box_label,
      'justification', v_eval.justification,
      'created_at', v_eval.created_at,
      'self_submitted_at', v_eval.self_submitted_at,
      'manager_submitted_at', v_eval.manager_submitted_at,
      'finalized_at', v_eval.finalized_at
    ),
    'self_scores', v_self_scores,
    'manager_scores', v_manager_scores,
    'view_as', CASE WHEN v_is_subject THEN 'subject' ELSE 'manager_or_admin' END
  );
END;
$$;

-- ----------------------------------------------------------------------------
-- rpc_ninebox_evaluation_list · lista visiveis ao caller
-- - subject ve so as proprias
-- - manager ve liderados diretos+indiretos
-- - RH/dir ve todas do tenant
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION rpc_ninebox_evaluation_list(
  p_cycle_id UUID DEFAULT NULL,
  p_status ninebox_evaluation_status DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user UUID := current_user_id();
  v_tenant UUID := current_tenant_id();
  v_role app_user_role;
  v_evals JSONB;
BEGIN
  IF v_user IS NULL OR v_tenant IS NULL THEN
    RETURN jsonb_build_object('error', 'not_authenticated');
  END IF;
  IF NOT module_is_active_for_me('ninebox') THEN
    RETURN jsonb_build_object('error', 'module_inactive', 'module', 'ninebox');
  END IF;

  SELECT role INTO v_role FROM app_users WHERE id = v_user;

  WITH visible AS (
    SELECT e.*,
           sub.full_name AS subject_name,
           mgr.full_name AS manager_name,
           c.name AS cycle_name
    FROM ninebox_evaluations e
    JOIN app_users sub ON sub.id = e.subject_id
    JOIN app_users mgr ON mgr.id = e.manager_id
    LEFT JOIN ninebox_cycles c ON c.id = e.cycle_id
    WHERE e.tenant_id = v_tenant
      AND (p_cycle_id IS NULL OR e.cycle_id = p_cycle_id)
      AND (p_status IS NULL OR e.status = p_status)
      AND (
        v_role IN ('super_admin', 'diretoria', 'rh')
        OR e.subject_id = v_user
        OR e.manager_id = v_user
        OR EXISTS (
          WITH RECURSIVE chain AS (
            SELECT id, manager_id FROM app_users WHERE id = e.subject_id
            UNION ALL
            SELECT u.id, u.manager_id FROM app_users u JOIN chain ch ON u.id = ch.manager_id
          )
          SELECT 1 FROM chain WHERE manager_id = v_user
        )
      )
  )
  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'id', id,
    'subject_id', subject_id, 'subject_name', subject_name,
    'manager_id', manager_id, 'manager_name', manager_name,
    'cycle_id', cycle_id, 'cycle_name', cycle_name,
    'is_adhoc', is_adhoc, 'status', status,
    'final_box_row', final_box_row, 'final_box_col', final_box_col,
    'final_box_label', final_box_label,
    'created_at', created_at, 'finalized_at', finalized_at
  ) ORDER BY created_at DESC), '[]'::JSONB) INTO v_evals
  FROM visible;

  RETURN jsonb_build_object('ok', TRUE, 'evaluations', v_evals);
END;
$$;

-- ----------------------------------------------------------------------------
-- rpc_ninebox_team_matrix · gestor/RH veem o time inteiro como pontos na matriz
-- p_scope: 'direct' (so liderados diretos) | 'all' (toda cadeia · default)
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION rpc_ninebox_team_matrix(
  p_cycle_id UUID DEFAULT NULL,
  p_scope TEXT DEFAULT 'all'
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user UUID := current_user_id();
  v_tenant UUID := current_tenant_id();
  v_role app_user_role;
  v_points JSONB;
BEGIN
  IF v_user IS NULL OR v_tenant IS NULL THEN
    RETURN jsonb_build_object('error', 'not_authenticated');
  END IF;
  IF NOT module_is_active_for_me('ninebox') THEN
    RETURN jsonb_build_object('error', 'module_inactive', 'module', 'ninebox');
  END IF;

  SELECT role INTO v_role FROM app_users WHERE id = v_user;
  -- Permite acesso a qualquer um que tenha liderados (verificacao via cadeia)
  -- ou role gerencial (lider, rh, diretoria, super_admin)
  IF v_role NOT IN ('super_admin', 'diretoria', 'rh', 'lider') THEN
    -- colaborador comum sem liderados nao acessa
    IF NOT EXISTS (SELECT 1 FROM app_users WHERE manager_id = v_user) THEN
      RETURN jsonb_build_object('error', 'permission_denied');
    END IF;
  END IF;

  WITH RECURSIVE my_team AS (
    SELECT id FROM app_users
      WHERE manager_id = v_user AND tenant_id = v_tenant
    UNION ALL
    SELECT u.id FROM app_users u
      JOIN my_team m ON u.manager_id = m.id
      WHERE p_scope = 'all'
  )
  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'evaluation_id', e.id,
    'subject_id', e.subject_id,
    'subject_name', sub.full_name,
    'box_row', e.final_box_row, 'box_col', e.final_box_col,
    'box_label', e.final_box_label,
    'potential_score', e.final_potential_score,
    'performance_score', e.final_performance_score,
    'status', e.status,
    'is_adhoc', e.is_adhoc
  )), '[]'::JSONB) INTO v_points
  FROM ninebox_evaluations e
  JOIN app_users sub ON sub.id = e.subject_id
  WHERE e.tenant_id = v_tenant
    AND e.status IN ('manager_done', 'finalized')
    AND (p_cycle_id IS NULL OR e.cycle_id = p_cycle_id)
    AND (
      v_role IN ('super_admin', 'diretoria', 'rh')
      OR e.subject_id IN (SELECT id FROM my_team)
    );

  RETURN jsonb_build_object('ok', TRUE, 'points', v_points);
END;
$$;

-- ----------------------------------------------------------------------------
-- rpc_ninebox_history · snapshots de um subject (evolucao no tempo)
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION rpc_ninebox_history(p_subject_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user UUID := current_user_id();
  v_tenant UUID := current_tenant_id();
  v_role app_user_role;
  v_subject app_users;
  v_history JSONB;
BEGIN
  IF v_user IS NULL OR v_tenant IS NULL THEN
    RETURN jsonb_build_object('error', 'not_authenticated');
  END IF;
  IF NOT module_is_active_for_me('ninebox') THEN
    RETURN jsonb_build_object('error', 'module_inactive', 'module', 'ninebox');
  END IF;

  SELECT * INTO v_subject FROM app_users
    WHERE id = p_subject_id AND tenant_id = v_tenant;
  IF v_subject IS NULL THEN
    RETURN jsonb_build_object('error', 'subject_not_found');
  END IF;

  SELECT role INTO v_role FROM app_users WHERE id = v_user;

  -- Permissao: o proprio subject, manager direto/indireto, ou RH/dir
  IF v_user <> p_subject_id
     AND v_role NOT IN ('super_admin', 'diretoria', 'rh') THEN
    IF NOT EXISTS (
      WITH RECURSIVE chain AS (
        SELECT id, manager_id FROM app_users WHERE id = p_subject_id
        UNION ALL
        SELECT u.id, u.manager_id FROM app_users u JOIN chain c ON u.id = c.manager_id
      )
      SELECT 1 FROM chain WHERE manager_id = v_user
    ) THEN
      RETURN jsonb_build_object('error', 'permission_denied');
    END IF;
  END IF;

  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'snapshot_id', s.id,
    'evaluation_id', s.evaluation_id,
    'version', s.version,
    'created_at', s.created_at,
    'cycle_id', s.snapshot_payload -> 'cycle_id',
    'final_box_row', s.snapshot_payload -> 'final_box_row',
    'final_box_col', s.snapshot_payload -> 'final_box_col',
    'final_box_label', s.snapshot_payload -> 'final_box_label',
    'final_potential_score', s.snapshot_payload -> 'final_potential_score',
    'final_performance_score', s.snapshot_payload -> 'final_performance_score'
  ) ORDER BY s.created_at DESC), '[]'::JSONB) INTO v_history
  FROM ninebox_evaluation_snapshots s
  WHERE s.tenant_id = v_tenant AND s.subject_id = p_subject_id;

  RETURN jsonb_build_object('ok', TRUE, 'history', v_history);
END;
$$;

-- ============================================================================
-- RLS · row-level security
-- ============================================================================

ALTER TABLE ninebox_settings                ENABLE ROW LEVEL SECURITY;
ALTER TABLE ninebox_cycles                  ENABLE ROW LEVEL SECURITY;
ALTER TABLE ninebox_evaluations             ENABLE ROW LEVEL SECURITY;
ALTER TABLE ninebox_evaluation_scores       ENABLE ROW LEVEL SECURITY;
ALTER TABLE ninebox_evaluation_snapshots    ENABLE ROW LEVEL SECURITY;

-- Settings · todos do tenant podem ler · so RH/dir escrevem
DROP POLICY IF EXISTS p_ninebox_settings_read ON ninebox_settings;
CREATE POLICY p_ninebox_settings_read ON ninebox_settings
  FOR SELECT USING (
    tenant_id = current_tenant_id()
    OR EXISTS (SELECT 1 FROM app_users WHERE id = current_user_id() AND role = 'super_admin')
  );

DROP POLICY IF EXISTS p_ninebox_settings_write ON ninebox_settings;
CREATE POLICY p_ninebox_settings_write ON ninebox_settings
  FOR ALL USING (
    tenant_id = current_tenant_id()
    AND EXISTS (
      SELECT 1 FROM app_users
      WHERE id = current_user_id()
        AND role IN ('super_admin', 'diretoria', 'rh')
    )
  );

-- Cycles · todos do tenant leem · RH/dir escrevem
DROP POLICY IF EXISTS p_ninebox_cycles_read ON ninebox_cycles;
CREATE POLICY p_ninebox_cycles_read ON ninebox_cycles
  FOR SELECT USING (
    tenant_id = current_tenant_id()
    OR EXISTS (SELECT 1 FROM app_users WHERE id = current_user_id() AND role = 'super_admin')
  );

DROP POLICY IF EXISTS p_ninebox_cycles_write ON ninebox_cycles;
CREATE POLICY p_ninebox_cycles_write ON ninebox_cycles
  FOR ALL USING (
    tenant_id = current_tenant_id()
    AND EXISTS (
      SELECT 1 FROM app_users
      WHERE id = current_user_id()
        AND role IN ('super_admin', 'diretoria', 'rh')
    )
  );

-- Evaluations · ler delegado a ninebox_can_view_evaluation · escrita via RPC
DROP POLICY IF EXISTS p_ninebox_eval_read ON ninebox_evaluations;
CREATE POLICY p_ninebox_eval_read ON ninebox_evaluations
  FOR SELECT USING (ninebox_can_view_evaluation(id));

DROP POLICY IF EXISTS p_ninebox_eval_write ON ninebox_evaluations;
CREATE POLICY p_ninebox_eval_write ON ninebox_evaluations
  FOR ALL USING (
    tenant_id = current_tenant_id()
    AND EXISTS (
      SELECT 1 FROM app_users
      WHERE id = current_user_id()
        AND role IN ('super_admin', 'diretoria', 'rh', 'lider')
    )
  );

-- Scores · seguem a mesma visibilidade da evaluation
DROP POLICY IF EXISTS p_ninebox_scores_read ON ninebox_evaluation_scores;
CREATE POLICY p_ninebox_scores_read ON ninebox_evaluation_scores
  FOR SELECT USING (ninebox_can_view_evaluation(evaluation_id));

DROP POLICY IF EXISTS p_ninebox_scores_write ON ninebox_evaluation_scores;
CREATE POLICY p_ninebox_scores_write ON ninebox_evaluation_scores
  FOR ALL USING (tenant_id = current_tenant_id());

-- Snapshots · readonly para quem ve a evaluation
DROP POLICY IF EXISTS p_ninebox_snap_read ON ninebox_evaluation_snapshots;
CREATE POLICY p_ninebox_snap_read ON ninebox_evaluation_snapshots
  FOR SELECT USING (ninebox_can_view_evaluation(evaluation_id));

DROP POLICY IF EXISTS p_ninebox_snap_write ON ninebox_evaluation_snapshots;
CREATE POLICY p_ninebox_snap_write ON ninebox_evaluation_snapshots
  FOR ALL USING (tenant_id = current_tenant_id());

-- ============================================================================
-- GRANTS
-- ============================================================================

GRANT SELECT ON ninebox_settings, ninebox_cycles, ninebox_evaluations,
                ninebox_evaluation_scores, ninebox_evaluation_snapshots TO authenticated;

GRANT EXECUTE ON FUNCTION
  rpc_ninebox_settings_get,
  rpc_ninebox_settings_update,
  rpc_ninebox_cycle_create,
  rpc_ninebox_cycle_update,
  rpc_ninebox_cycle_list,
  rpc_ninebox_evaluation_start,
  rpc_ninebox_evaluation_self_submit,
  rpc_ninebox_evaluation_manager_submit,
  rpc_ninebox_evaluation_finalize,
  rpc_ninebox_evaluation_cancel,
  rpc_ninebox_evaluation_get,
  rpc_ninebox_evaluation_list,
  rpc_ninebox_team_matrix,
  rpc_ninebox_history,
  ninebox_can_view_evaluation,
  ninebox_grid_max,
  ninebox_score_to_box,
  ninebox_is_extreme_box,
  ninebox_compute_axis_score,
  ninebox_validate_criteria
TO authenticated;

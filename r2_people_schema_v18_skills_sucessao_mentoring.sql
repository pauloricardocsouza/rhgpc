-- ============================================================================
-- R2 People · Schema SQL v18 · Skills + Sucessão + Mentoring + Carreira
-- ----------------------------------------------------------------------------
-- Materializa em SQL executável a spec M22 (Sucessão & Carreira).
--
-- Pré-requisito: schemas v9-v17 aplicados.
-- 100% idempotente.
-- ============================================================================

BEGIN;

-- ============================================================================
-- 1. SKILLS · catálogo + competências por cargo + assessment
-- ============================================================================

CREATE TABLE IF NOT EXISTS skills_catalog (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id       uuid NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  name            text NOT NULL,
  category        text NOT NULL CHECK (category IN ('hard','soft','language','tool','certification')),
  description     text,
  active          boolean DEFAULT true,
  created_at      timestamptz DEFAULT now(),
  UNIQUE (tenant_id, name)
);

CREATE INDEX IF NOT EXISTS idx_skills_active
  ON skills_catalog (tenant_id) WHERE active = true;

CREATE TABLE IF NOT EXISTS position_skills_required (
  position_id     uuid NOT NULL,
  skill_id        uuid NOT NULL REFERENCES skills_catalog(id) ON DELETE CASCADE,
  expected_level  int NOT NULL CHECK (expected_level BETWEEN 1 AND 5),
  weight          numeric DEFAULT 1,
  PRIMARY KEY (position_id, skill_id)
);

CREATE TABLE IF NOT EXISTS employee_skills (
  id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id           uuid NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  employee_id         uuid NOT NULL,
  skill_id            uuid NOT NULL REFERENCES skills_catalog(id),
  self_level          int CHECK (self_level BETWEEN 1 AND 5),
  leader_level        int CHECK (leader_level BETWEEN 1 AND 5),
  leader_id           uuid,
  last_assessed_at    timestamptz DEFAULT now(),
  evidence            text,
  UNIQUE (employee_id, skill_id)
);

CREATE INDEX IF NOT EXISTS idx_emp_skills_employee
  ON employee_skills (employee_id);

CREATE INDEX IF NOT EXISTS idx_emp_skills_recent
  ON employee_skills (tenant_id, last_assessed_at DESC);

-- ============================================================================
-- 2. SUCCESSION PLANS
-- ============================================================================

CREATE TABLE IF NOT EXISTS succession_plans (
  id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id           uuid NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  position_id         uuid NOT NULL,
  current_holder_id   uuid,
  criticality         text CHECK (criticality IN ('low','medium','high','critical')) DEFAULT 'medium',
  reviewed_at         timestamptz,
  reviewed_by         uuid REFERENCES auth.users(id),
  next_review_at      timestamptz,
  notes               text,
  created_at          timestamptz DEFAULT now(),
  UNIQUE (tenant_id, position_id)
);

CREATE INDEX IF NOT EXISTS idx_succession_critical
  ON succession_plans (tenant_id, criticality);

CREATE INDEX IF NOT EXISTS idx_succession_review_due
  ON succession_plans (next_review_at)
  WHERE next_review_at IS NOT NULL;

CREATE TABLE IF NOT EXISTS succession_candidates (
  id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  plan_id             uuid NOT NULL REFERENCES succession_plans(id) ON DELETE CASCADE,
  employee_id         uuid NOT NULL,
  priority            text NOT NULL CHECK (priority IN ('primary','secondary','tertiary')),
  readiness           text NOT NULL CHECK (readiness IN ('ready_now','ready_6m','ready_12m','ready_24m','exploratory')),
  skills_gap_summary  text,
  pdi_id              uuid,
  added_at            timestamptz DEFAULT now(),
  removed_at          timestamptz,
  notes               text,
  UNIQUE (plan_id, employee_id)
);

CREATE INDEX IF NOT EXISTS idx_succession_active
  ON succession_candidates (plan_id) WHERE removed_at IS NULL;

-- Trigger: agendar review 6 meses após cada update
CREATE OR REPLACE FUNCTION trg_succession_schedule_review()
RETURNS TRIGGER AS $$
BEGIN
  IF NEW.reviewed_at IS NOT NULL
     AND (OLD.reviewed_at IS DISTINCT FROM NEW.reviewed_at) THEN
    NEW.next_review_at := NEW.reviewed_at + interval '6 months';
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_succession_review ON succession_plans;
CREATE TRIGGER trg_succession_review
  BEFORE INSERT OR UPDATE ON succession_plans
  FOR EACH ROW EXECUTE FUNCTION trg_succession_schedule_review();

-- RPC · cargos críticos sem sucessor primário
CREATE OR REPLACE FUNCTION rpc_succession_gaps(p_tenant_id uuid)
RETURNS TABLE (
  position_id uuid,
  plan_id uuid,
  criticality text,
  has_primary boolean,
  candidate_count int
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN QUERY
  SELECT
    sp.position_id,
    sp.id,
    sp.criticality,
    EXISTS (SELECT 1 FROM succession_candidates sc
            WHERE sc.plan_id = sp.id AND sc.priority = 'primary' AND sc.removed_at IS NULL),
    (SELECT count(*)::int FROM succession_candidates sc
     WHERE sc.plan_id = sp.id AND sc.removed_at IS NULL)
  FROM succession_plans sp
  WHERE sp.tenant_id = p_tenant_id
    AND sp.criticality IN ('high','critical');
END;
$$;

-- RPC · readiness por plano
CREATE OR REPLACE FUNCTION rpc_succession_readiness(p_plan_id uuid)
RETURNS TABLE (
  employee_id uuid,
  priority text,
  readiness text,
  skills_gap_summary text,
  is_pdi_linked boolean
)
LANGUAGE plpgsql STABLE
AS $$
BEGIN
  RETURN QUERY
  SELECT
    sc.employee_id, sc.priority, sc.readiness, sc.skills_gap_summary,
    sc.pdi_id IS NOT NULL
  FROM succession_candidates sc
  WHERE sc.plan_id = p_plan_id AND sc.removed_at IS NULL
  ORDER BY
    CASE sc.priority WHEN 'primary' THEN 1 WHEN 'secondary' THEN 2 ELSE 3 END,
    CASE sc.readiness
      WHEN 'ready_now' THEN 1
      WHEN 'ready_6m' THEN 2
      WHEN 'ready_12m' THEN 3
      WHEN 'ready_24m' THEN 4
      ELSE 5
    END;
END;
$$;

-- ============================================================================
-- 3. MENTORING PROGRAM
-- ============================================================================

CREATE TABLE IF NOT EXISTS mentoring_profiles (
  id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id           uuid NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  user_id             uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  role                text NOT NULL CHECK (role IN ('mentor','mentee','both')),
  skills_offered      uuid[] DEFAULT ARRAY[]::uuid[],
  skills_seeking      uuid[] DEFAULT ARRAY[]::uuid[],
  availability        text,
  bio                 text,
  active              boolean DEFAULT true,
  joined_at           timestamptz DEFAULT now(),
  UNIQUE (tenant_id, user_id)
);

CREATE INDEX IF NOT EXISTS idx_mentor_active
  ON mentoring_profiles (tenant_id, role) WHERE active = true;

CREATE TABLE IF NOT EXISTS mentoring_pairs (
  id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id           uuid NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  mentor_id           uuid NOT NULL REFERENCES auth.users(id),
  mentee_id           uuid NOT NULL REFERENCES auth.users(id),
  initiated_by        uuid NOT NULL,
  status              text NOT NULL CHECK (status IN ('proposed','active','completed','cancelled')) DEFAULT 'proposed',
  topic               text,
  frequency           text CHECK (frequency IN ('weekly','biweekly','monthly','ad_hoc')),
  started_at          timestamptz,
  completed_at        timestamptz,
  mentor_feedback     text,
  mentee_feedback     text,
  mentor_rating       int CHECK (mentor_rating BETWEEN 1 AND 5),
  mentee_rating       int CHECK (mentee_rating BETWEEN 1 AND 5),
  notes               text
);

CREATE INDEX IF NOT EXISTS idx_mentoring_active
  ON mentoring_pairs (tenant_id, status) WHERE status = 'active';

CREATE INDEX IF NOT EXISTS idx_mentoring_user
  ON mentoring_pairs (mentor_id, mentee_id);

-- RPC · matching sugerido (top N mentors compatíveis)
CREATE OR REPLACE FUNCTION rpc_mentoring_match_suggest(
  p_mentee_user_id uuid,
  p_skill_id uuid DEFAULT NULL,
  p_limit int DEFAULT 3
) RETURNS TABLE (
  mentor_user_id uuid,
  skills_overlap_count int,
  fit_score numeric
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN QUERY
  SELECT
    mp.user_id,
    cardinality(COALESCE(mp.skills_offered, '{}')) AS skills_overlap_count,
    -- Score básico: skills_overlap + bonus por ser ativo + penalidade hierarquia
    (cardinality(COALESCE(mp.skills_offered, '{}'))::numeric
     + CASE WHEN mp.active THEN 2 ELSE 0 END
     -- TODO: filtrar mentores que são líder direto do mentee (penalizar)
    ) AS fit_score
  FROM mentoring_profiles mp
  WHERE mp.role IN ('mentor','both')
    AND mp.active = true
    AND mp.user_id != p_mentee_user_id
    AND (p_skill_id IS NULL OR p_skill_id = ANY(mp.skills_offered))
  ORDER BY fit_score DESC
  LIMIT p_limit;
END;
$$;

-- ============================================================================
-- 4. CARREIRA · self-request + paths
-- ============================================================================

CREATE TABLE IF NOT EXISTS career_interests (
  id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id           uuid NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  employee_id         uuid NOT NULL,
  target_position_id  uuid NOT NULL,
  motivation          text,
  expected_timeframe  text CHECK (expected_timeframe IN ('6m','12m','24m','3y_plus')),
  status              text CHECK (status IN ('declared','in_pdi','considered','approved','not_selected','withdrawn')) DEFAULT 'declared',
  pdi_id              uuid,
  declared_at         timestamptz DEFAULT now(),
  resolved_at         timestamptz,
  resolution_notes    text
);

CREATE INDEX IF NOT EXISTS idx_career_interest_active
  ON career_interests (target_position_id) WHERE status IN ('declared','in_pdi','considered');

CREATE INDEX IF NOT EXISTS idx_career_interest_employee
  ON career_interests (employee_id, declared_at DESC);

CREATE TABLE IF NOT EXISTS career_paths (
  id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id           uuid NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  name                text NOT NULL,
  description         text,
  active              boolean DEFAULT true
);

CREATE TABLE IF NOT EXISTS career_path_steps (
  id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  path_id             uuid NOT NULL REFERENCES career_paths(id) ON DELETE CASCADE,
  position_id         uuid NOT NULL,
  step_order          int NOT NULL,
  avg_time_months     int,
  required_skills     uuid[] DEFAULT ARRAY[]::uuid[],
  suggested_tracks    uuid[] DEFAULT ARRAY[]::uuid[],
  UNIQUE (path_id, step_order)
);

-- RPC · declarar interesse + criar PDI direcionado
CREATE OR REPLACE FUNCTION rpc_career_interest_declare(
  p_tenant_id uuid,
  p_employee_id uuid,
  p_target_position_id uuid,
  p_motivation text DEFAULT NULL,
  p_timeframe text DEFAULT '12m'
) RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE v_id uuid;
BEGIN
  INSERT INTO career_interests (
    tenant_id, employee_id, target_position_id, motivation, expected_timeframe
  ) VALUES (
    p_tenant_id, p_employee_id, p_target_position_id, p_motivation, p_timeframe
  ) RETURNING id INTO v_id;

  -- TODO: criar PDI direcionado se tabela 'pdi' existir + linkar pdi_id
  -- TODO: dispara notif M12 ao líder + RH

  RETURN v_id;
END;
$$;

-- RPC · próximo degrau sugerido
CREATE OR REPLACE FUNCTION rpc_career_next_step(p_employee_id uuid)
RETURNS TABLE (
  next_position_id uuid,
  path_name text,
  step_order int,
  realistic_timeframe text,
  required_skills_count int
)
LANGUAGE plpgsql STABLE
AS $$
BEGIN
  -- Esqueleto: descobre cargo atual do employee + busca próximo step
  -- no career_path correspondente
  RETURN;
END;
$$;

-- ============================================================================
-- 5. RPCs · análise agregada
-- ============================================================================

-- Skill matrix heatmap por time
CREATE OR REPLACE FUNCTION rpc_team_skills_heatmap(p_leader_user_id uuid)
RETURNS TABLE (
  employee_id uuid,
  skill_id uuid,
  expected_level int,
  actual_level int,
  gap int
)
LANGUAGE plpgsql STABLE
AS $$
BEGIN
  -- Esqueleto: cruza employee_skills + position_skills_required
  -- filtrado por subordinados diretos do líder
  RETURN;
END;
$$;

-- Gap agregado por skill no cargo (planejar treinamento)
CREATE OR REPLACE FUNCTION rpc_position_skills_gap(
  p_tenant_id uuid,
  p_position_id uuid
) RETURNS TABLE (
  skill_id uuid,
  expected_level int,
  avg_actual_level numeric,
  employees_below_count int
)
LANGUAGE plpgsql STABLE
AS $$
BEGIN
  RETURN QUERY
  SELECT
    psr.skill_id,
    psr.expected_level,
    ROUND(AVG(COALESCE(es.leader_level, es.self_level))::numeric, 2),
    COUNT(*) FILTER (WHERE COALESCE(es.leader_level, es.self_level) < psr.expected_level)::int
  FROM position_skills_required psr
  LEFT JOIN employee_skills es ON es.skill_id = psr.skill_id
    AND es.tenant_id = p_tenant_id
  WHERE psr.position_id = p_position_id
  GROUP BY psr.skill_id, psr.expected_level;
END;
$$;

-- ============================================================================
-- 6. RLS POLICIES
-- ============================================================================

DO $$
DECLARE
  t text;
  tenant_tables text[] := ARRAY[
    'skills_catalog','employee_skills',
    'mentoring_profiles','mentoring_pairs',
    'career_interests','career_paths'
  ];
BEGIN
  FOREACH t IN ARRAY tenant_tables LOOP
    EXECUTE format('ALTER TABLE %I ENABLE ROW LEVEL SECURITY', t);
    EXECUTE format('
      DROP POLICY IF EXISTS %I_tenant_isolation ON %I;
      CREATE POLICY %I_tenant_isolation ON %I
        FOR ALL
        USING (tenant_id = (current_setting(''app.tenant_id'', true))::uuid);',
      t, t, t, t);
  END LOOP;
END $$;

-- Sucessão é SENSÍVEL · só super_admin + RH sênior + diretoria
ALTER TABLE succession_plans ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS succession_view_restricted ON succession_plans;
CREATE POLICY succession_view_restricted ON succession_plans
  FOR ALL USING (
    tenant_id = (current_setting('app.tenant_id', true))::uuid
    AND (
      auth.jwt() ->> 'role' IN ('super_admin','dpo','diretoria','rh_senior')
      OR auth.role() = 'service_role'
      OR EXISTS (
        SELECT 1 FROM user_permissions
        WHERE user_id = auth.uid()
          AND permission = 'view_succession_plans'
      )
    )
  );

ALTER TABLE succession_candidates ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS succession_cand_via_plan ON succession_candidates;
CREATE POLICY succession_cand_via_plan ON succession_candidates
  FOR ALL USING (
    plan_id IN (SELECT id FROM succession_plans
                WHERE tenant_id = (current_setting('app.tenant_id', true))::uuid)
  );

-- Position skills required + career_path_steps · ler livre por tenant
ALTER TABLE position_skills_required ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS psr_via_skill ON position_skills_required;
CREATE POLICY psr_via_skill ON position_skills_required
  FOR SELECT USING (
    skill_id IN (SELECT id FROM skills_catalog
                 WHERE tenant_id = (current_setting('app.tenant_id', true))::uuid)
  );

ALTER TABLE career_path_steps ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS cps_via_path ON career_path_steps;
CREATE POLICY cps_via_path ON career_path_steps
  FOR SELECT USING (
    path_id IN (SELECT id FROM career_paths
                WHERE tenant_id = (current_setting('app.tenant_id', true))::uuid)
  );

-- ============================================================================
-- 7. GRANTs
-- ============================================================================

DO $$
DECLARE t text;
BEGIN
  FOREACH t IN ARRAY ARRAY[
    'skills_catalog','position_skills_required','employee_skills',
    'succession_plans','succession_candidates',
    'mentoring_profiles','mentoring_pairs',
    'career_interests','career_paths','career_path_steps'
  ] LOOP
    EXECUTE format('GRANT SELECT ON %I TO authenticated', t);
    EXECUTE format('GRANT ALL ON %I TO service_role', t);
  END LOOP;
END $$;

GRANT EXECUTE ON FUNCTION rpc_succession_gaps(uuid) TO service_role;
GRANT EXECUTE ON FUNCTION rpc_succession_readiness(uuid) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION rpc_mentoring_match_suggest(uuid, uuid, int) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION rpc_career_interest_declare(uuid, uuid, uuid, text, text) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION rpc_career_next_step(uuid) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION rpc_team_skills_heatmap(uuid) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION rpc_position_skills_gap(uuid, uuid) TO authenticated, service_role;

-- ============================================================================
-- 8. SEED · skills catalog padrão (template GPC varejo)
-- ============================================================================

DO $$
DECLARE v_tenant_id uuid;
BEGIN
  SELECT id INTO v_tenant_id FROM tenants LIMIT 1;
  IF v_tenant_id IS NULL THEN RETURN; END IF;

  INSERT INTO skills_catalog (tenant_id, name, category, description) VALUES
    -- Hard skills tech
    (v_tenant_id, 'SQL avançado', 'hard', 'Queries complexas, otimização, joins, window functions'),
    (v_tenant_id, 'Python pandas', 'hard', 'Análise de dados em pandas'),
    (v_tenant_id, 'Excel avançado', 'hard', 'PivotTable, fórmulas, Power Query'),
    -- Hard skills varejo
    (v_tenant_id, 'Operação PDV', 'hard', 'Sistema de venda, estorno, sangria'),
    (v_tenant_id, 'Gestão de estoque', 'hard', 'Ruptura, validade, planograma'),
    (v_tenant_id, 'Prevenção de perdas', 'hard', 'Identificação de risco e controle'),
    (v_tenant_id, 'KPIs operacionais', 'hard', 'Métricas de loja, ticket médio, conversão'),
    -- Hard skills financeiro
    (v_tenant_id, 'DRE / DFC', 'hard', 'Análise de demonstrações financeiras'),
    (v_tenant_id, 'Gestão de fluxo de caixa', 'hard', 'Projeção e controle'),
    -- Soft skills
    (v_tenant_id, 'Liderança', 'soft', 'Gestão de pessoas, delegação, coaching'),
    (v_tenant_id, 'Gestão de conflito', 'soft', 'Mediação e negociação interna'),
    (v_tenant_id, 'Comunicação', 'soft', 'Verbal, escrita, apresentação'),
    (v_tenant_id, 'Trabalho em equipe', 'soft', 'Colaboração e cooperação'),
    (v_tenant_id, 'Stakeholder management', 'soft', 'Influência cross-functional'),
    -- Languages
    (v_tenant_id, 'Inglês', 'language', 'Conversação e leitura técnica'),
    (v_tenant_id, 'Espanhol', 'language', 'Conversação'),
    -- Tools
    (v_tenant_id, 'Tableau / Power BI', 'tool', 'Visualização e dashboards'),
    (v_tenant_id, 'Senior HCM', 'tool', 'ERP de RH'),
    (v_tenant_id, 'Sistema Domínio', 'tool', 'ERP DP/contabilidade')
  ON CONFLICT (tenant_id, name) DO NOTHING;
END $$;

-- pwa_versions atualizada para v0.18
INSERT INTO pwa_versions (version, breaking, release_notes)
VALUES ('v0.18', false, 'Schema v18 · Skills + Sucessão + Mentoring + Carreira')
ON CONFLICT (version) DO NOTHING;

COMMIT;

-- ============================================================================
-- Fim do schema v18
-- ============================================================================

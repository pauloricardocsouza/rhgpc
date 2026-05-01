-- ============================================================
-- R2 People Platform - Schema PostgreSQL v2
-- Plataforma de Gestão de Desempenho e Feedback Contínuo
-- Compatível com Supabase (auth.users)
-- Multi-tenant via Row Level Security (RLS)
--
-- AJUSTES v2 vs v1:
--  - Multi-empresa por usuário (tabela user_companies)
--  - Login por username (e-mail sintético interno)
--  - Hierarquia de visibilidade configurável por empresa
--  - Anonimato em feedbacks configurável por empresa
--  - Removidos estados de calibração
-- ============================================================

CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- ============================================================
-- ENUMs
-- ============================================================

CREATE TYPE user_role AS ENUM ('super_admin', 'admin_rh', 'gestor', 'colaborador');
CREATE TYPE user_status AS ENUM ('active', 'inactive', 'on_leave');
-- v2: removido 'calibration'
CREATE TYPE cycle_status AS ENUM ('draft', 'active', 'in_review', 'closed');
CREATE TYPE cycle_type AS ENUM ('annual', 'semiannual', 'quarterly', 'custom');
CREATE TYPE review_type AS ENUM ('self', 'manager', 'peer', 'subordinate');
-- v2: removido 'calibrated'
CREATE TYPE review_status AS ENUM ('pending', 'in_progress', 'submitted');
CREATE TYPE feedback_type AS ENUM ('positive', 'constructive', 'request_response');
CREATE TYPE feedback_visibility AS ENUM ('private', 'shared_with_manager', 'public');
CREATE TYPE feedback_request_status AS ENUM ('pending', 'completed', 'declined', 'expired');

-- ============================================================
-- TENANT RAIZ: companies
-- settings agora carrega configurações de visibilidade e anonimato
-- ============================================================

CREATE TABLE companies (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name TEXT NOT NULL,
    slug TEXT NOT NULL UNIQUE,
    cnpj TEXT,
    logo_url TEXT,
    -- settings esperados:
    -- {
    --   "manager_visibility_depth": -1,        -- 1, 2, ... ou -1 (infinito)
    --   "allow_anonymous_feedback": true,
    --   "default_rating_scale": {"min": 1, "max": 5},
    --   "language": "pt-BR"
    -- }
    settings JSONB NOT NULL DEFAULT jsonb_build_object(
      'manager_visibility_depth', 1,
      'allow_anonymous_feedback', false,
      'default_rating_scale', jsonb_build_object('min', 1, 'max', 5),
      'language', 'pt-BR'
    ),
    plan TEXT DEFAULT 'free',
    active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    deleted_at TIMESTAMPTZ
);

CREATE INDEX idx_companies_slug ON companies(slug) WHERE deleted_at IS NULL;
CREATE INDEX idx_companies_active ON companies(active) WHERE deleted_at IS NULL;

-- ============================================================
-- ESTRUTURA ORGANIZACIONAL: departments
-- ============================================================

CREATE TABLE departments (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id UUID NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
    parent_id UUID REFERENCES departments(id) ON DELETE SET NULL,
    name TEXT NOT NULL,
    code TEXT,
    description TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    deleted_at TIMESTAMPTZ,
    UNIQUE(company_id, code)
);

CREATE INDEX idx_departments_company ON departments(company_id) WHERE deleted_at IS NULL;
CREATE INDEX idx_departments_parent ON departments(parent_id);

-- ============================================================
-- USUÁRIOS: users
-- v2: SEM company_id direto (foi para user_companies)
-- v2: campo username único globalmente, login real
-- v2: auth_email é o e-mail sintético usado só pelo Supabase Auth
-- ============================================================

CREATE TABLE users (
    id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    username TEXT NOT NULL UNIQUE,
    auth_email TEXT NOT NULL UNIQUE,  -- e-mail sintético (ex: joao.silva@r2-internal.local)
    full_name TEXT NOT NULL,
    avatar_url TEXT,
    cpf TEXT,                          -- documento real do colaborador
    contact_email TEXT,                -- e-mail real, opcional
    phone TEXT,
    profile_data JSONB DEFAULT '{}'::jsonb,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    deleted_at TIMESTAMPTZ
);

CREATE INDEX idx_users_username ON users(username) WHERE deleted_at IS NULL;
CREATE INDEX idx_users_cpf ON users(cpf) WHERE deleted_at IS NULL;

-- ============================================================
-- v2: user_companies (vínculo usuário-empresa)
-- Mesmo usuário pode ter papéis diferentes em empresas diferentes
-- ============================================================

CREATE TABLE user_companies (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    company_id UUID NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
    department_id UUID REFERENCES departments(id) ON DELETE SET NULL,
    manager_id UUID REFERENCES users(id) ON DELETE SET NULL,
    role user_role NOT NULL DEFAULT 'colaborador',
    job_title TEXT,
    status user_status NOT NULL DEFAULT 'active',
    hire_date DATE,
    is_default BOOLEAN DEFAULT FALSE,  -- empresa default ao logar
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    deleted_at TIMESTAMPTZ,
    UNIQUE(user_id, company_id)
);

CREATE INDEX idx_uc_user ON user_companies(user_id) WHERE deleted_at IS NULL;
CREATE INDEX idx_uc_company ON user_companies(company_id) WHERE deleted_at IS NULL;
CREATE INDEX idx_uc_manager ON user_companies(manager_id);
CREATE INDEX idx_uc_dept ON user_companies(department_id);
CREATE INDEX idx_uc_company_status ON user_companies(company_id, status) WHERE deleted_at IS NULL;

-- Apenas uma empresa default por usuário
CREATE UNIQUE INDEX idx_uc_one_default
  ON user_companies(user_id) WHERE is_default = TRUE AND deleted_at IS NULL;

-- ============================================================
-- COMPETÊNCIAS
-- ============================================================

CREATE TABLE competencies (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id UUID NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    description TEXT,
    category TEXT,
    weight NUMERIC(5,2) DEFAULT 1.0,
    active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(company_id, name)
);

CREATE INDEX idx_competencies_company ON competencies(company_id) WHERE active = TRUE;

-- ============================================================
-- CICLOS DE AVALIAÇÃO
-- v2: defaults do MVP (self + manager)
-- ============================================================

CREATE TABLE review_cycles (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id UUID NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    description TEXT,
    type cycle_type NOT NULL DEFAULT 'annual',
    start_date DATE NOT NULL,
    end_date DATE NOT NULL,
    self_review_enabled BOOLEAN DEFAULT TRUE,
    manager_review_enabled BOOLEAN DEFAULT TRUE,
    peer_review_enabled BOOLEAN DEFAULT FALSE,
    subordinate_review_enabled BOOLEAN DEFAULT FALSE,
    rating_scale_min INT DEFAULT 1,
    rating_scale_max INT DEFAULT 5,
    status cycle_status NOT NULL DEFAULT 'draft',
    created_by UUID REFERENCES users(id),
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    CHECK (end_date >= start_date),
    CHECK (rating_scale_max > rating_scale_min)
);

CREATE INDEX idx_cycles_company ON review_cycles(company_id);
CREATE INDEX idx_cycles_status ON review_cycles(company_id, status);

CREATE TABLE review_cycle_competencies (
    cycle_id UUID REFERENCES review_cycles(id) ON DELETE CASCADE,
    competency_id UUID REFERENCES competencies(id) ON DELETE CASCADE,
    display_order INT DEFAULT 0,
    PRIMARY KEY (cycle_id, competency_id)
);

-- ============================================================
-- AVALIAÇÕES
-- ============================================================

CREATE TABLE reviews (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id UUID NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
    cycle_id UUID NOT NULL REFERENCES review_cycles(id) ON DELETE CASCADE,
    reviewee_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    reviewer_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    review_type review_type NOT NULL,
    status review_status NOT NULL DEFAULT 'pending',
    overall_rating NUMERIC(4,2),
    overall_comments TEXT,
    submitted_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(cycle_id, reviewee_id, reviewer_id, review_type)
);

CREATE INDEX idx_reviews_cycle ON reviews(cycle_id);
CREATE INDEX idx_reviews_reviewee ON reviews(reviewee_id);
CREATE INDEX idx_reviews_reviewer ON reviews(reviewer_id);
CREATE INDEX idx_reviews_status ON reviews(company_id, status);

CREATE TABLE review_answers (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    review_id UUID NOT NULL REFERENCES reviews(id) ON DELETE CASCADE,
    competency_id UUID NOT NULL REFERENCES competencies(id) ON DELETE CASCADE,
    rating NUMERIC(4,2),
    comments TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(review_id, competency_id)
);

CREATE INDEX idx_answers_review ON review_answers(review_id);

-- ============================================================
-- FEEDBACK CONTÍNUO
-- v2: is_anonymous para anonimato configurável
-- ============================================================

CREATE TABLE feedback_requests (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id UUID NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
    requester_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    target_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    about_user_id UUID REFERENCES users(id) ON DELETE CASCADE,
    message TEXT,
    status feedback_request_status NOT NULL DEFAULT 'pending',
    expires_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    completed_at TIMESTAMPTZ
);

CREATE INDEX idx_feedback_req_target ON feedback_requests(target_id, status);
CREATE INDEX idx_feedback_req_requester ON feedback_requests(requester_id);

CREATE TABLE feedbacks (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id UUID NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
    from_user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    to_user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    request_id UUID REFERENCES feedback_requests(id) ON DELETE SET NULL,
    type feedback_type NOT NULL,
    competency_id UUID REFERENCES competencies(id) ON DELETE SET NULL,
    message TEXT NOT NULL,
    visibility feedback_visibility NOT NULL DEFAULT 'private',
    is_anonymous BOOLEAN NOT NULL DEFAULT FALSE,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_feedbacks_to ON feedbacks(to_user_id, created_at DESC);
CREATE INDEX idx_feedbacks_from ON feedbacks(from_user_id, created_at DESC);
CREATE INDEX idx_feedbacks_company ON feedbacks(company_id, created_at DESC);

-- ============================================================
-- ELOGIOS PÚBLICOS
-- ============================================================

CREATE TABLE praises (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id UUID NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
    from_user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    to_user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    competency_id UUID REFERENCES competencies(id) ON DELETE SET NULL,
    message TEXT NOT NULL,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_praises_company_date ON praises(company_id, created_at DESC);
CREATE INDEX idx_praises_to ON praises(to_user_id);

CREATE TABLE praise_reactions (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    praise_id UUID NOT NULL REFERENCES praises(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    reaction TEXT NOT NULL DEFAULT '👏',
    created_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(praise_id, user_id, reaction)
);

-- ============================================================
-- AUDITORIA (LGPD)
-- ============================================================

CREATE TABLE audit_log (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id UUID REFERENCES companies(id) ON DELETE CASCADE,
    user_id UUID REFERENCES users(id) ON DELETE SET NULL,
    action TEXT NOT NULL,
    entity_type TEXT NOT NULL,
    entity_id UUID,
    changes JSONB,
    ip_address INET,
    user_agent TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_audit_company_date ON audit_log(company_id, created_at DESC);
CREATE INDEX idx_audit_entity ON audit_log(entity_type, entity_id);
CREATE INDEX idx_audit_user ON audit_log(user_id, created_at DESC);

-- ============================================================
-- NOTIFICAÇÕES IN-APP
-- ============================================================

CREATE TABLE notifications (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id UUID NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    type TEXT NOT NULL,
    title TEXT NOT NULL,
    message TEXT,
    link_url TEXT,
    read_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_notifications_user ON notifications(user_id, read_at, created_at DESC);

-- ============================================================
-- HELPERS para RLS (v2: empresa ativa via JWT claim)
--
-- O frontend, ao trocar de empresa, atualiza um claim chamado
-- 'active_company_id' no JWT (ou via app_metadata após RPC).
-- Esta função lê esse claim. Se ausente, usa a empresa default.
-- ============================================================

CREATE OR REPLACE FUNCTION current_active_company_id()
RETURNS UUID
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
AS $$
DECLARE
  active_id UUID;
BEGIN
  -- Tenta ler do JWT claim
  active_id := (auth.jwt() ->> 'active_company_id')::UUID;

  -- Se não houver, pega a empresa default do usuário
  IF active_id IS NULL THEN
    SELECT company_id INTO active_id
    FROM user_companies
    WHERE user_id = auth.uid()
      AND is_default = TRUE
      AND deleted_at IS NULL
    LIMIT 1;
  END IF;

  -- Última opção: primeira empresa vinculada
  IF active_id IS NULL THEN
    SELECT company_id INTO active_id
    FROM user_companies
    WHERE user_id = auth.uid()
      AND deleted_at IS NULL
    ORDER BY created_at
    LIMIT 1;
  END IF;

  RETURN active_id;
END;
$$;

CREATE OR REPLACE FUNCTION current_user_role_in_active_company()
RETURNS user_role
LANGUAGE SQL
STABLE
SECURITY DEFINER
AS $$
  SELECT role FROM user_companies
  WHERE user_id = auth.uid()
    AND company_id = current_active_company_id()
    AND deleted_at IS NULL
  LIMIT 1;
$$;

-- Verifica se um usuário (target) é subordinado direto ou indireto do auth.uid()
-- na empresa ativa, respeitando manager_visibility_depth do company.settings
CREATE OR REPLACE FUNCTION is_subordinate_of_current_user(target_user_id UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
AS $$
DECLARE
  depth_limit INT;
  found BOOLEAN := FALSE;
BEGIN
  SELECT (settings->>'manager_visibility_depth')::INT INTO depth_limit
  FROM companies WHERE id = current_active_company_id();

  IF depth_limit IS NULL THEN depth_limit := 1; END IF;

  WITH RECURSIVE subs AS (
    SELECT user_id, manager_id, 1 AS depth
    FROM user_companies
    WHERE manager_id = auth.uid()
      AND company_id = current_active_company_id()
      AND deleted_at IS NULL
    UNION ALL
    SELECT uc.user_id, uc.manager_id, s.depth + 1
    FROM user_companies uc
    JOIN subs s ON uc.manager_id = s.user_id
    WHERE uc.company_id = current_active_company_id()
      AND uc.deleted_at IS NULL
      AND (depth_limit = -1 OR s.depth < depth_limit)
  )
  SELECT TRUE INTO found
  FROM subs WHERE user_id = target_user_id LIMIT 1;

  RETURN COALESCE(found, FALSE);
END;
$$;

-- ============================================================
-- ROW LEVEL SECURITY (RLS)
-- ============================================================

ALTER TABLE companies ENABLE ROW LEVEL SECURITY;
ALTER TABLE users ENABLE ROW LEVEL SECURITY;
ALTER TABLE user_companies ENABLE ROW LEVEL SECURITY;
ALTER TABLE departments ENABLE ROW LEVEL SECURITY;
ALTER TABLE competencies ENABLE ROW LEVEL SECURITY;
ALTER TABLE review_cycles ENABLE ROW LEVEL SECURITY;
ALTER TABLE review_cycle_competencies ENABLE ROW LEVEL SECURITY;
ALTER TABLE reviews ENABLE ROW LEVEL SECURITY;
ALTER TABLE review_answers ENABLE ROW LEVEL SECURITY;
ALTER TABLE feedback_requests ENABLE ROW LEVEL SECURITY;
ALTER TABLE feedbacks ENABLE ROW LEVEL SECURITY;
ALTER TABLE praises ENABLE ROW LEVEL SECURITY;
ALTER TABLE praise_reactions ENABLE ROW LEVEL SECURITY;
ALTER TABLE audit_log ENABLE ROW LEVEL SECURITY;
ALTER TABLE notifications ENABLE ROW LEVEL SECURITY;

-- companies: usuário vê só as empresas em que tem vínculo
CREATE POLICY companies_visibility ON companies
  FOR SELECT USING (
    id IN (SELECT company_id FROM user_companies
           WHERE user_id = auth.uid() AND deleted_at IS NULL)
  );

-- users: vê outros usuários que compartilham alguma empresa ativa
CREATE POLICY users_visibility ON users
  FOR SELECT USING (
    id = auth.uid()
    OR id IN (
      SELECT uc.user_id FROM user_companies uc
      WHERE uc.company_id = current_active_company_id()
        AND uc.deleted_at IS NULL
    )
  );

-- user_companies: vê só os vínculos da empresa ativa, ou seus próprios
CREATE POLICY uc_visibility ON user_companies
  FOR SELECT USING (
    user_id = auth.uid()
    OR company_id = current_active_company_id()
  );

-- departments: filtro pela empresa ativa
CREATE POLICY tenant_departments ON departments
  FOR SELECT USING (company_id = current_active_company_id());

-- competencies
CREATE POLICY tenant_competencies ON competencies
  FOR SELECT USING (company_id = current_active_company_id());

-- review_cycles
CREATE POLICY tenant_cycles ON review_cycles
  FOR SELECT USING (company_id = current_active_company_id());

-- reviews: reviewee, reviewer, gestor com visibilidade ou admin RH
CREATE POLICY reviews_visibility ON reviews
  FOR SELECT USING (
    company_id = current_active_company_id()
    AND (
      reviewee_id = auth.uid()
      OR reviewer_id = auth.uid()
      OR is_subordinate_of_current_user(reviewee_id)
      OR current_user_role_in_active_company() IN ('admin_rh', 'super_admin')
    )
  );

-- feedbacks: emissor, destinatário, gestor (se shared) ou admin RH
-- atenção: anonimato é tratado na CAMADA DE APLICAÇÃO ao montar a resposta
-- (esconder from_user_id quando is_anonymous = TRUE para quem não é admin)
CREATE POLICY feedbacks_visibility ON feedbacks
  FOR SELECT USING (
    company_id = current_active_company_id()
    AND (
      from_user_id = auth.uid()
      OR to_user_id = auth.uid()
      OR (visibility = 'shared_with_manager' AND EXISTS (
        SELECT 1 FROM user_companies uc
        WHERE uc.user_id = to_user_id
          AND uc.company_id = current_active_company_id()
          AND uc.manager_id = auth.uid()
      ))
      OR current_user_role_in_active_company() IN ('admin_rh', 'super_admin')
    )
  );

-- praises: visíveis para toda a empresa ativa
CREATE POLICY praises_visibility ON praises
  FOR SELECT USING (company_id = current_active_company_id());

-- notifications: só do próprio usuário
CREATE POLICY notifications_self ON notifications
  FOR SELECT USING (user_id = auth.uid());

-- (políticas de INSERT/UPDATE/DELETE: definir conforme regras de negócio)

-- ============================================================
-- TRIGGERS: updated_at automático
-- ============================================================

CREATE OR REPLACE FUNCTION trigger_set_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER set_updated_at BEFORE UPDATE ON companies
  FOR EACH ROW EXECUTE FUNCTION trigger_set_updated_at();
CREATE TRIGGER set_updated_at BEFORE UPDATE ON users
  FOR EACH ROW EXECUTE FUNCTION trigger_set_updated_at();
CREATE TRIGGER set_updated_at BEFORE UPDATE ON user_companies
  FOR EACH ROW EXECUTE FUNCTION trigger_set_updated_at();
CREATE TRIGGER set_updated_at BEFORE UPDATE ON departments
  FOR EACH ROW EXECUTE FUNCTION trigger_set_updated_at();
CREATE TRIGGER set_updated_at BEFORE UPDATE ON competencies
  FOR EACH ROW EXECUTE FUNCTION trigger_set_updated_at();
CREATE TRIGGER set_updated_at BEFORE UPDATE ON review_cycles
  FOR EACH ROW EXECUTE FUNCTION trigger_set_updated_at();
CREATE TRIGGER set_updated_at BEFORE UPDATE ON reviews
  FOR EACH ROW EXECUTE FUNCTION trigger_set_updated_at();
CREATE TRIGGER set_updated_at BEFORE UPDATE ON review_answers
  FOR EACH ROW EXECUTE FUNCTION trigger_set_updated_at();
CREATE TRIGGER set_updated_at BEFORE UPDATE ON feedbacks
  FOR EACH ROW EXECUTE FUNCTION trigger_set_updated_at();

-- ============================================================
-- VIEWS úteis (atualizadas para user_companies)
-- ============================================================

CREATE OR REPLACE VIEW v_user_hierarchy AS
WITH RECURSIVE hierarchy AS (
  SELECT
    uc.user_id, uc.manager_id, u.full_name,
    uc.company_id, uc.department_id,
    0 AS depth,
    ARRAY[uc.user_id] AS path
  FROM user_companies uc
  JOIN users u ON u.id = uc.user_id
  WHERE uc.manager_id IS NULL AND uc.deleted_at IS NULL
  UNION ALL
  SELECT
    uc.user_id, uc.manager_id, u.full_name,
    uc.company_id, uc.department_id,
    h.depth + 1,
    h.path || uc.user_id
  FROM user_companies uc
  JOIN users u ON u.id = uc.user_id
  JOIN hierarchy h ON uc.manager_id = h.user_id
                  AND uc.company_id = h.company_id
  WHERE uc.deleted_at IS NULL
)
SELECT * FROM hierarchy;

CREATE OR REPLACE VIEW v_cycle_progress AS
SELECT
  rc.id AS cycle_id,
  rc.company_id,
  rc.name AS cycle_name,
  rc.status AS cycle_status,
  COUNT(r.id) AS total_reviews,
  COUNT(r.id) FILTER (WHERE r.status = 'submitted') AS submitted_reviews,
  ROUND(
    100.0 * COUNT(r.id) FILTER (WHERE r.status = 'submitted')
    / NULLIF(COUNT(r.id), 0),
    2
  ) AS completion_rate
FROM review_cycles rc
LEFT JOIN reviews r ON r.cycle_id = rc.id
GROUP BY rc.id;

CREATE OR REPLACE VIEW v_reviewee_summary AS
SELECT
  r.cycle_id,
  r.reviewee_id,
  u.full_name AS reviewee_name,
  uc.department_id,
  COUNT(DISTINCT r.id) AS reviews_received,
  AVG(r.overall_rating) FILTER (WHERE r.review_type = 'self') AS self_rating,
  AVG(r.overall_rating) FILTER (WHERE r.review_type = 'manager') AS manager_rating,
  AVG(r.overall_rating) FILTER (WHERE r.review_type = 'peer') AS peer_rating,
  AVG(r.overall_rating) FILTER (WHERE r.review_type = 'subordinate') AS subordinate_rating,
  AVG(r.overall_rating) AS overall_avg
FROM reviews r
JOIN users u ON u.id = r.reviewee_id
LEFT JOIN user_companies uc
  ON uc.user_id = r.reviewee_id AND uc.company_id = r.company_id
WHERE r.status = 'submitted'
GROUP BY r.cycle_id, r.reviewee_id, u.full_name, uc.department_id;

-- ============================================================
-- FIM DO SCHEMA v2
-- ============================================================

-- ============================================================
-- R2 People Platform - Schema PostgreSQL
-- Plataforma de Gestão de Desempenho e Feedback Contínuo
-- Compatível com Supabase (auth.users)
-- Multi-tenant via Row Level Security (RLS)
-- ============================================================

CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- ============================================================
-- ENUMs
-- ============================================================

CREATE TYPE user_role AS ENUM ('super_admin', 'admin_rh', 'gestor', 'colaborador');
CREATE TYPE user_status AS ENUM ('active', 'inactive', 'on_leave');
CREATE TYPE cycle_status AS ENUM ('draft', 'active', 'in_review', 'calibration', 'closed');
CREATE TYPE cycle_type AS ENUM ('annual', 'semiannual', 'quarterly', 'custom');
CREATE TYPE review_type AS ENUM ('self', 'manager', 'peer', 'subordinate');
CREATE TYPE review_status AS ENUM ('pending', 'in_progress', 'submitted', 'calibrated');
CREATE TYPE feedback_type AS ENUM ('positive', 'constructive', 'request_response');
CREATE TYPE feedback_visibility AS ENUM ('private', 'shared_with_manager', 'public');
CREATE TYPE feedback_request_status AS ENUM ('pending', 'completed', 'declined', 'expired');

-- ============================================================
-- TENANT RAIZ: companies
-- ============================================================

CREATE TABLE companies (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name TEXT NOT NULL,
    slug TEXT NOT NULL UNIQUE,
    cnpj TEXT,
    logo_url TEXT,
    settings JSONB DEFAULT '{}'::jsonb,
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
-- Hierarquia via parent_id (suporta as 14 unidades da GPC)
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
-- Estende auth.users do Supabase
-- manager_id self-referencial dá hierarquia direta
-- ============================================================

CREATE TABLE users (
    id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    company_id UUID NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
    department_id UUID REFERENCES departments(id) ON DELETE SET NULL,
    manager_id UUID REFERENCES users(id) ON DELETE SET NULL,
    email TEXT NOT NULL,
    full_name TEXT NOT NULL,
    avatar_url TEXT,
    job_title TEXT,
    role user_role NOT NULL DEFAULT 'colaborador',
    status user_status NOT NULL DEFAULT 'active',
    hire_date DATE,
    profile_data JSONB DEFAULT '{}'::jsonb,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    deleted_at TIMESTAMPTZ,
    UNIQUE(company_id, email)
);

CREATE INDEX idx_users_company ON users(company_id) WHERE deleted_at IS NULL;
CREATE INDEX idx_users_manager ON users(manager_id);
CREATE INDEX idx_users_department ON users(department_id);
CREATE INDEX idx_users_status ON users(company_id, status) WHERE deleted_at IS NULL;

-- ============================================================
-- COMPETÊNCIAS: competencies (biblioteca por empresa)
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
-- CICLOS DE AVALIAÇÃO: review_cycles
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
-- AVALIAÇÕES: reviews + review_answers
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
-- FEEDBACK CONTÍNUO: feedback_requests + feedbacks
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
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_feedbacks_to ON feedbacks(to_user_id, created_at DESC);
CREATE INDEX idx_feedbacks_from ON feedbacks(from_user_id, created_at DESC);
CREATE INDEX idx_feedbacks_company ON feedbacks(company_id, created_at DESC);

-- ============================================================
-- ELOGIOS PÚBLICOS: praises + praise_reactions
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
-- AUDITORIA (LGPD): audit_log
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
-- NOTIFICAÇÕES IN-APP: notifications
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
-- HELPERS para RLS
-- ============================================================

CREATE OR REPLACE FUNCTION current_user_company_id()
RETURNS UUID
LANGUAGE SQL
STABLE
SECURITY DEFINER
AS $$
  SELECT company_id FROM users WHERE id = auth.uid();
$$;

CREATE OR REPLACE FUNCTION current_user_role()
RETURNS user_role
LANGUAGE SQL
STABLE
SECURITY DEFINER
AS $$
  SELECT role FROM users WHERE id = auth.uid();
$$;

-- ============================================================
-- ROW LEVEL SECURITY (RLS)
-- ============================================================

ALTER TABLE companies ENABLE ROW LEVEL SECURITY;
ALTER TABLE users ENABLE ROW LEVEL SECURITY;
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

-- Política básica: usuário só vê dados da sua empresa
CREATE POLICY tenant_isolation_users ON users
  FOR SELECT USING (company_id = current_user_company_id());

CREATE POLICY tenant_isolation_departments ON departments
  FOR SELECT USING (company_id = current_user_company_id());

CREATE POLICY tenant_isolation_competencies ON competencies
  FOR SELECT USING (company_id = current_user_company_id());

CREATE POLICY tenant_isolation_cycles ON review_cycles
  FOR SELECT USING (company_id = current_user_company_id());

-- Reviews: apenas reviewee, reviewer ou admin RH veem
CREATE POLICY reviews_visibility ON reviews
  FOR SELECT USING (
    company_id = current_user_company_id()
    AND (
      reviewee_id = auth.uid()
      OR reviewer_id = auth.uid()
      OR current_user_role() IN ('admin_rh', 'super_admin')
    )
  );

-- Feedbacks: emissor, destinatário, gestor do destinatário (se shared) ou admin RH
CREATE POLICY feedbacks_visibility ON feedbacks
  FOR SELECT USING (
    company_id = current_user_company_id()
    AND (
      from_user_id = auth.uid()
      OR to_user_id = auth.uid()
      OR (visibility = 'shared_with_manager' AND EXISTS (
        SELECT 1 FROM users u WHERE u.id = to_user_id AND u.manager_id = auth.uid()
      ))
      OR current_user_role() IN ('admin_rh', 'super_admin')
    )
  );

-- Elogios: visíveis para toda a empresa
CREATE POLICY praises_visibility ON praises
  FOR SELECT USING (company_id = current_user_company_id());

-- (políticas de INSERT/UPDATE/DELETE devem ser definidas em fase posterior,
--  geralmente seguindo o mesmo padrão de filtro por company_id e role)

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
-- VIEWS úteis
-- ============================================================

-- Hierarquia recursiva de subordinados
CREATE OR REPLACE VIEW v_user_hierarchy AS
WITH RECURSIVE hierarchy AS (
  SELECT
    id, manager_id, full_name, company_id, department_id,
    0 AS depth,
    ARRAY[id] AS path
  FROM users
  WHERE manager_id IS NULL AND deleted_at IS NULL
  UNION ALL
  SELECT
    u.id, u.manager_id, u.full_name, u.company_id, u.department_id,
    h.depth + 1,
    h.path || u.id
  FROM users u
  JOIN hierarchy h ON u.manager_id = h.id
  WHERE u.deleted_at IS NULL
)
SELECT * FROM hierarchy;

-- Progresso agregado de ciclo
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

-- Média de avaliação por colaborador em um ciclo
CREATE OR REPLACE VIEW v_reviewee_summary AS
SELECT
  r.cycle_id,
  r.reviewee_id,
  u.full_name AS reviewee_name,
  u.department_id,
  COUNT(DISTINCT r.id) AS reviews_received,
  AVG(r.overall_rating) FILTER (WHERE r.review_type = 'self') AS self_rating,
  AVG(r.overall_rating) FILTER (WHERE r.review_type = 'manager') AS manager_rating,
  AVG(r.overall_rating) FILTER (WHERE r.review_type = 'peer') AS peer_rating,
  AVG(r.overall_rating) FILTER (WHERE r.review_type = 'subordinate') AS subordinate_rating,
  AVG(r.overall_rating) AS overall_avg
FROM reviews r
JOIN users u ON u.id = r.reviewee_id
WHERE r.status = 'submitted'
GROUP BY r.cycle_id, r.reviewee_id, u.full_name, u.department_id;

-- ============================================================
-- FIM DO SCHEMA
-- ============================================================

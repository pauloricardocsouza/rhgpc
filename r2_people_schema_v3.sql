-- ============================================================================
-- R2 PEOPLE - SCHEMA v3 (PostgreSQL / Supabase)
-- ============================================================================
-- Plataforma SaaS de gestão de pessoas multi-tenant.
-- Modelo principal: separação tridimensional do vínculo empregatício
--   1. employer_unit_id  : CNPJ que assina a CTPS e paga a folha (legal/fiscal)
--   2. working_unit_id   : Filial onde a pessoa trabalha de fato (operacional)
--   3. department_id     : Área funcional dentro do tomador
-- Esta separação é essencial para clientes como o Grupo Pinto Cerqueira (GPC),
-- que possui empresas próprias (ATP, Cestão) e prestadoras (Labuta, Limpactiva,
-- Segure). Relatórios podem ser tirados por qualquer um dos três eixos.
--
-- Convenções:
--   - PKs em UUID (pgcrypto: gen_random_uuid)
--   - Timestamps em TIMESTAMPTZ
--   - Soft delete via deleted_at em tabelas que precisam preservar histórico
--   - RLS (Row Level Security) ativado em TODAS as tabelas com tenant
--   - Auditoria centralizada em audit_log (LGPD)
-- ============================================================================

CREATE EXTENSION IF NOT EXISTS pgcrypto;
CREATE EXTENSION IF NOT EXISTS pg_trgm;     -- para busca textual (ILIKE rápido)
CREATE EXTENSION IF NOT EXISTS unaccent;    -- busca insensível a acentos


-- ============================================================================
-- 1. TENANT (companies) E USUÁRIOS
-- ============================================================================

-- Cada cliente da plataforma é uma "company" (tenant).
-- O GPC é uma company. Outro PME que assinar o R2 People é outra company.
-- Todas as queries são filtradas por company_id via RLS.
CREATE TABLE companies (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  slug            TEXT UNIQUE NOT NULL,                                   -- 'gpc', 'hec', etc.
  name            TEXT NOT NULL,
  legal_name      TEXT,                                                   -- Razão social do grupo
  cnpj_root       TEXT,                                                   -- CNPJ raiz (8 primeiros dígitos)
  logo_url        TEXT,
  primary_color   TEXT DEFAULT '#2B4A7A',
  settings        JSONB NOT NULL DEFAULT '{}'::jsonb,                     -- preferências configuráveis
  active          BOOLEAN NOT NULL DEFAULT TRUE,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  deleted_at      TIMESTAMPTZ
);

COMMENT ON COLUMN companies.settings IS
  'JSONB com configurações específicas do tenant. Ex.:
   {
     "manager_visibility_depth": "recursive",
     "allow_anonymous_feedback": true,
     "evaluation_scale": 5,
     "language": "pt-BR",
     "require_2fa": false,
     "password_policy": {"min_length": 8, "require_special": true}
   }';


-- Usuários globais (autenticados via Supabase Auth).
-- Um mesmo usuário pode ter acesso a múltiplas companies via user_companies.
-- Login pode ser feito via username + senha (caso GPC, onde nem todos têm e-mail).
-- Para isso usamos um e-mail sintético {username}@{tenant_slug}.r2.local no Auth.
CREATE TABLE users (
  id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  auth_user_id     UUID UNIQUE,                                           -- referência ao auth.users do Supabase
  username         TEXT UNIQUE NOT NULL,                                  -- login global (ex: "fernanda.lima")
  auth_email       TEXT UNIQUE NOT NULL,                                  -- sintético para Auth: fernanda.lima@gpc.r2.local
  email            TEXT,                                                  -- e-mail real opcional do colaborador
  full_name        TEXT NOT NULL,
  social_name      TEXT,                                                  -- nome social (LGPD)
  preferred_name   TEXT,                                                  -- como prefere ser chamado(a)
  cpf              TEXT UNIQUE,                                           -- ÚNICO globalmente
  birth_date       DATE,
  gender           TEXT CHECK (gender IN ('M','F','O','N')),              -- N = não informado
  marital_status   TEXT,
  phone            TEXT,
  alt_phone        TEXT,
  rg_number        TEXT,
  rg_issuer        TEXT,
  rg_state         TEXT,
  ctps_number      TEXT,
  ctps_series      TEXT,
  pis              TEXT,
  voter_id         TEXT,
  cnh_number       TEXT,
  cnh_category     TEXT,
  cnh_expires_at   DATE,
  address_street   TEXT,
  address_city     TEXT,
  address_state    TEXT,
  address_zip      TEXT,
  mother_name      TEXT,
  nationality      TEXT DEFAULT 'Brasileira',
  birth_place      TEXT,
  photo_url        TEXT,
  bank_data        JSONB DEFAULT '{}'::jsonb,                             -- criptografado em repouso
  active           BOOLEAN NOT NULL DEFAULT TRUE,
  must_change_pwd  BOOLEAN NOT NULL DEFAULT TRUE,
  last_login_at    TIMESTAMPTZ,
  created_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
  deleted_at       TIMESTAMPTZ
);

CREATE INDEX idx_users_username      ON users (lower(username));
CREATE INDEX idx_users_full_name_trgm ON users USING gin (lower(unaccent(full_name)) gin_trgm_ops);
CREATE INDEX idx_users_cpf           ON users (cpf) WHERE cpf IS NOT NULL;

COMMENT ON COLUMN users.bank_data IS
  'Dados bancários em JSONB. Em produção, usar pgcrypto para criptografar campos sensíveis.
   Ex.: {"bank_code":"341","agency":"3471-2","account":"83291-4","account_type":"checking","pix_key":"042.815.392-67"}';



-- ============================================================================
-- 2. UNITS (filiais) · POLIMÓRFICAS: operacionais, prestadoras, administrativas
-- ============================================================================
-- Esta é a tabela mais crítica do schema. Modela 3 tipos de unidades:
--
-- 1. operational   : Filiais que operam o negócio próprio do cliente
--                    (ex: ATP-Varejo, Cestão L1, ATP S.Bonfim)
-- 2. service_provider : Prestadoras de serviço terceirizadas
--                    (ex: Labuta, Limpactiva, Segure)
-- 3. administrative : Escritórios corporativos / matriz
--                    (ex: GPC Matriz, GPC Financeiro, GPC TI)
--
-- Um colaborador tem dois apontamentos para units:
--   employer_unit_id  → unit que paga a folha (qualquer um dos 3 tipos)
--   working_unit_id   → unit operacional/administrativa onde está alocado
-- ============================================================================

CREATE TYPE unit_role AS ENUM ('operational', 'service_provider', 'administrative');

CREATE TABLE units (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id      UUID NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
  parent_id       UUID REFERENCES units(id),                              -- hierarquia (ATP-Var sob GPC-Matriz)
  code            TEXT NOT NULL,                                          -- 'CES-L1', 'LABUTA', 'GPC-TI'
  name            TEXT NOT NULL,
  role            unit_role NOT NULL,
  type            TEXT,                                                   -- subtipo livre: 'matriz', 'loja', 'cd', 'escr', etc.
  cnpj            TEXT,                                                   -- formato: 00.000.000/0000-00
  state_reg       TEXT,                                                   -- inscrição estadual
  address_street  TEXT,
  address_city    TEXT,
  address_state   TEXT,
  address_zip     TEXT,
  phone           TEXT,
  manager_user_id UUID REFERENCES users(id),                              -- gerente responsável
  opened_at       DATE,
  active          BOOLEAN NOT NULL DEFAULT TRUE,
  metadata        JSONB DEFAULT '{}'::jsonb,                              -- campos extensíveis por cliente
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  deleted_at      TIMESTAMPTZ,

  UNIQUE (company_id, code)
);

CREATE INDEX idx_units_company       ON units (company_id) WHERE deleted_at IS NULL;
CREATE INDEX idx_units_role          ON units (company_id, role) WHERE deleted_at IS NULL;
CREATE INDEX idx_units_parent        ON units (parent_id) WHERE parent_id IS NOT NULL;
CREATE INDEX idx_units_manager       ON units (manager_user_id) WHERE manager_user_id IS NOT NULL;

-- View útil: hierarquia completa via CTE recursiva (descendentes de qualquer unit)
CREATE OR REPLACE VIEW v_unit_descendants AS
WITH RECURSIVE tree AS (
  SELECT id AS root_id, id AS unit_id, 0 AS depth FROM units WHERE deleted_at IS NULL
  UNION ALL
  SELECT t.root_id, u.id, t.depth + 1
    FROM units u
    JOIN tree t ON u.parent_id = t.unit_id
   WHERE u.deleted_at IS NULL
)
SELECT root_id, unit_id, depth FROM tree;



-- ============================================================================
-- 3. ESTRUTURA FUNCIONAL: departamentos e cargos
-- ============================================================================

CREATE TABLE departments (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id      UUID NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
  parent_id       UUID REFERENCES departments(id),                        -- hierarquia (Compras dentro de Comercial)
  unit_id         UUID REFERENCES units(id),                              -- filial associada (NULL = multi-filial/transversal)
  leader_user_id  UUID REFERENCES users(id),                              -- líder do departamento
  code            TEXT NOT NULL,                                          -- 'FIN', 'COM', 'COM-COMP'
  name            TEXT NOT NULL,
  description     TEXT,
  active          BOOLEAN NOT NULL DEFAULT TRUE,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  deleted_at      TIMESTAMPTZ,

  UNIQUE (company_id, code)
);

CREATE INDEX idx_departments_company  ON departments (company_id) WHERE deleted_at IS NULL;
CREATE INDEX idx_departments_unit     ON departments (unit_id) WHERE unit_id IS NOT NULL;
CREATE INDEX idx_departments_parent   ON departments (parent_id) WHERE parent_id IS NOT NULL;
CREATE INDEX idx_departments_leader   ON departments (leader_user_id) WHERE leader_user_id IS NOT NULL;


CREATE TABLE positions (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id      UUID NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
  department_id   UUID REFERENCES departments(id),                        -- NULL = cargo genérico (qualquer depto)
  code            TEXT NOT NULL,                                          -- 'ANL-PL', 'OP-CX'
  name            TEXT NOT NULL,
  description     TEXT,
  level           TEXT NOT NULL,                                          -- Estagiário, Operacional, Júnior, ..., Diretoria
  cbo_code        TEXT,                                                   -- Classificação Brasileira de Ocupações
  min_salary      NUMERIC(12,2),
  mid_salary      NUMERIC(12,2),
  max_salary      NUMERIC(12,2),
  active          BOOLEAN NOT NULL DEFAULT TRUE,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  deleted_at      TIMESTAMPTZ,

  UNIQUE (company_id, code)
);

CREATE INDEX idx_positions_company  ON positions (company_id) WHERE deleted_at IS NULL;
CREATE INDEX idx_positions_dept     ON positions (department_id) WHERE department_id IS NOT NULL;



-- ============================================================================
-- 4. USER_COMPANIES · VÍNCULO MULTI-DIMENSIONAL
-- ============================================================================
-- Esta é a tabela que materializa o conceito central:
-- um usuário, em uma company, com vínculo separado entre EMPREGADOR e TOMADOR.
-- Um mesmo user pode ter múltiplos vínculos (multi-empresa, multi-cliente).
-- ============================================================================

CREATE TYPE contract_type AS ENUM ('clt', 'pj', 'estagio', 'aprendiz', 'temporario', 'terceirizado');
CREATE TYPE employee_status AS ENUM ('active', 'vacation', 'sick_leave', 'maternity_leave', 'inss_leave', 'suspended', 'terminated');
CREATE TYPE access_level AS ENUM ('admin','hr','manager','employee','readonly');

CREATE TABLE user_companies (
  id                    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id               UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  company_id            UUID NOT NULL REFERENCES companies(id) ON DELETE CASCADE,

  -- TRIPLO VÍNCULO ----------------------------------------------------------
  employer_unit_id      UUID NOT NULL REFERENCES units(id),               -- quem paga a folha (qualquer role)
  working_unit_id       UUID NOT NULL REFERENCES units(id),               -- onde trabalha (operational/administrative)
  department_id         UUID REFERENCES departments(id),                  -- área funcional
  position_id           UUID REFERENCES positions(id),                    -- cargo

  -- HIERARQUIA --------------------------------------------------------------
  manager_user_id       UUID REFERENCES users(id),                        -- gestor direto (FK em users, busca user_companies)
  alternate_approver_id UUID REFERENCES users(id),                        -- aprovador substituto

  -- DADOS TRABALHISTAS ------------------------------------------------------
  employee_code         TEXT,                                             -- matrícula no empregador (ERP TOTVS)
  contract_type         contract_type NOT NULL,
  hire_date             DATE NOT NULL,
  allocation_start_date DATE,                                             -- início no tomador atual (pode diferir de hire)
  termination_date      DATE,
  termination_reason    TEXT,
  weekly_hours          INTEGER DEFAULT 44,
  cost_center           TEXT,
  base_salary           NUMERIC(12,2),
  status                employee_status NOT NULL DEFAULT 'active',

  -- CONTROLE DE ACESSO ------------------------------------------------------
  access_level          access_level NOT NULL DEFAULT 'employee',         -- nível alto (compatibilidade)
  permission_profile_id UUID,                                             -- referência ao perfil detalhado (FK abaixo)
  is_active             BOOLEAN NOT NULL DEFAULT TRUE,

  -- METADADOS ---------------------------------------------------------------
  benefits              JSONB DEFAULT '{}'::jsonb,                        -- VR, VT, plano de saúde, etc.
  metadata              JSONB DEFAULT '{}'::jsonb,
  created_at            TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at            TIMESTAMPTZ NOT NULL DEFAULT now(),

  UNIQUE (user_id, company_id, employer_unit_id),
  CHECK (working_unit_id IS NOT NULL),
  CHECK (employer_unit_id IS NOT NULL)
);

CREATE INDEX idx_uc_user           ON user_companies (user_id);
CREATE INDEX idx_uc_company        ON user_companies (company_id);
CREATE INDEX idx_uc_employer       ON user_companies (employer_unit_id);
CREATE INDEX idx_uc_working        ON user_companies (working_unit_id);
CREATE INDEX idx_uc_department     ON user_companies (department_id);
CREATE INDEX idx_uc_position       ON user_companies (position_id);
CREATE INDEX idx_uc_manager        ON user_companies (manager_user_id);
CREATE INDEX idx_uc_status         ON user_companies (company_id, status);
CREATE INDEX idx_uc_active         ON user_companies (company_id, is_active) WHERE is_active = TRUE;

COMMENT ON TABLE user_companies IS
  'Tabela que materializa o vínculo de um usuário com uma company, separando:
   - Empregador (employer_unit_id): CNPJ que paga a folha (Labuta, GPC, ATP, etc.)
   - Tomador (working_unit_id): filial operacional onde trabalha (ATP-Varejo, Cestão L1, etc.)
   Esta separação é fundamental para clientes que usam terceirização.';



-- ============================================================================
-- 5. PERFIS DE ACESSO MULTIDIMENSIONAIS
-- ============================================================================
-- Cada perfil define:
--   1. Quais páginas pode acessar (e com quais permissões: ver, criar, editar...)
--   2. Qual o escopo de visibilidade em 4 dimensões independentes:
--      - employers : todos | específicos | apenas próprio
--      - units     : todos | específicos | apenas próprio
--      - depts     : todos | específicos | apenas próprio
--      - hierarchy : todos | recursive | direct | self
--   3. Permissões especiais (aprovar movimentações, exportar dados sensíveis, etc.)
--
-- As regras se combinam com AND lógico nas queries de visibilidade.
-- Exemplo: "RH Prestadora · Labuta" tem:
--   employers = specific:[Labuta]
--   units     = all
--   depts     = all
--   hierarchy = all
-- → Vê todos os funcionários da Labuta independente de filial onde trabalham.
--
-- "Gerente de Filial · Cestão L1" tem:
--   employers = all
--   units     = specific:[Cestão L1]
--   depts     = all
--   hierarchy = all
-- → Vê todos que trabalham no Cestão L1, mesmo terceirizados.
-- ============================================================================

CREATE TYPE scope_mode AS ENUM ('all', 'specific', 'self', 'recursive', 'direct', 'none');

CREATE TABLE permission_profiles (
  id                    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id            UUID NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
  code                  TEXT NOT NULL,                                    -- 'super_admin', 'rh_labuta', 'gerente_cestao_l1'
  name                  TEXT NOT NULL,
  description           TEXT,
  color                 TEXT DEFAULT '#2B4A7A',
  icon                  TEXT DEFAULT '⚙',
  is_system             BOOLEAN NOT NULL DEFAULT FALSE,                   -- system profiles não podem ser excluídos

  -- ESCOPO DE VISIBILIDADE EM 4 DIMENSÕES -----------------------------------
  employer_scope        scope_mode NOT NULL DEFAULT 'all',
  unit_scope            scope_mode NOT NULL DEFAULT 'all',
  department_scope      scope_mode NOT NULL DEFAULT 'all',
  hierarchy_scope       scope_mode NOT NULL DEFAULT 'all',

  -- PERMISSÕES ESPECIAIS (capacidades transversais) -------------------------
  special_permissions   TEXT[] NOT NULL DEFAULT '{}',
  -- exemplos: 'approve_movements', 'import_csv', 'export_sensitive',
  --           'reset_passwords', 'manage_profiles', 'view_audit',
  --           'override_scope', 'manage_cycles'

  active                BOOLEAN NOT NULL DEFAULT TRUE,
  created_at            TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at            TIMESTAMPTZ NOT NULL DEFAULT now(),

  UNIQUE (company_id, code)
);

-- FK retroativa de user_companies → permission_profiles
ALTER TABLE user_companies
  ADD CONSTRAINT fk_uc_profile
  FOREIGN KEY (permission_profile_id) REFERENCES permission_profiles(id);


-- Listagem das páginas do sistema (catálogo estático mantido pela aplicação)
CREATE TABLE system_pages (
  code           TEXT PRIMARY KEY,                                        -- 'colaboradores', 'movimentacoes', 'dashboard_rh'
  name           TEXT NOT NULL,
  category       TEXT NOT NULL,                                           -- 'geral', 'aval', 'feedback', 'gestor', 'admin'
  is_sensitive   BOOLEAN NOT NULL DEFAULT FALSE,                          -- requer auditoria de acesso
  available_perms TEXT[] NOT NULL                                         -- {'view','create','edit','delete','export','approve','reject'}
);


-- Permissões de cada perfil em cada página
CREATE TABLE profile_page_permissions (
  profile_id     UUID NOT NULL REFERENCES permission_profiles(id) ON DELETE CASCADE,
  page_code      TEXT NOT NULL REFERENCES system_pages(code),
  permissions    TEXT[] NOT NULL DEFAULT '{}',                            -- subset de available_perms
  PRIMARY KEY (profile_id, page_code)
);


-- Quando employer_scope = 'specific', listamos quais empregadores aqui
CREATE TABLE profile_employer_scope (
  profile_id     UUID NOT NULL REFERENCES permission_profiles(id) ON DELETE CASCADE,
  unit_id        UUID NOT NULL REFERENCES units(id),
  PRIMARY KEY (profile_id, unit_id)
);

-- Quando unit_scope = 'specific', listamos quais tomadores aqui
CREATE TABLE profile_unit_scope (
  profile_id     UUID NOT NULL REFERENCES permission_profiles(id) ON DELETE CASCADE,
  unit_id        UUID NOT NULL REFERENCES units(id),
  PRIMARY KEY (profile_id, unit_id)
);

-- Quando department_scope = 'specific', listamos quais departamentos aqui
CREATE TABLE profile_department_scope (
  profile_id     UUID NOT NULL REFERENCES permission_profiles(id) ON DELETE CASCADE,
  department_id  UUID NOT NULL REFERENCES departments(id),
  recursive      BOOLEAN NOT NULL DEFAULT FALSE,                          -- inclui sub-departamentos?
  PRIMARY KEY (profile_id, department_id)
);


-- Override individual: permite atribuir permissões/escopo extras a um usuário
-- além do que o perfil dele permite. Usado em casos excepcionais.
CREATE TABLE user_permission_overrides (
  id                 UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_company_id    UUID NOT NULL REFERENCES user_companies(id) ON DELETE CASCADE,
  granted_permissions TEXT[] NOT NULL DEFAULT '{}',                       -- permissões extras
  extra_unit_ids     UUID[] NOT NULL DEFAULT '{}',                        -- tomadores extras visíveis
  extra_employer_ids UUID[] NOT NULL DEFAULT '{}',                        -- empregadores extras visíveis
  reason             TEXT NOT NULL,                                       -- justificativa (auditável)
  granted_by_user_id UUID NOT NULL REFERENCES users(id),
  expires_at         TIMESTAMPTZ,                                         -- override temporário
  created_at         TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_overrides_uc ON user_permission_overrides (user_company_id);



-- ============================================================================
-- 6. COMPETÊNCIAS, CICLOS DE AVALIAÇÃO E AVALIAÇÕES
-- ============================================================================

CREATE TABLE competencies (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id  UUID NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
  name        TEXT NOT NULL,
  description TEXT,
  category    TEXT,                                                       -- 'comportamental', 'técnica', 'liderança'
  weight      NUMERIC(3,2) DEFAULT 1.0,                                   -- peso na nota final
  active      BOOLEAN NOT NULL DEFAULT TRUE,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_comp_company ON competencies (company_id) WHERE active = TRUE;


CREATE TYPE cycle_status AS ENUM ('draft', 'open', 'self_eval', 'manager_eval', 'calibration', 'closed', 'archived');

CREATE TABLE review_cycles (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id    UUID NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
  name          TEXT NOT NULL,                                            -- '2026.1', 'Ciclo Anual 2025'
  start_date    DATE NOT NULL,
  end_date      DATE NOT NULL,
  self_eval_deadline    DATE,
  manager_eval_deadline DATE,
  status        cycle_status NOT NULL DEFAULT 'draft',
  scale_max     INTEGER NOT NULL DEFAULT 5,                               -- escala 1 a 5 (configurável)
  allow_anonymous_peer  BOOLEAN NOT NULL DEFAULT FALSE,
  config        JSONB DEFAULT '{}'::jsonb,                                -- configurações específicas
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_cycles_company ON review_cycles (company_id, status);


-- Competências usadas em cada ciclo (snapshot, pois competências podem mudar)
CREATE TABLE cycle_competencies (
  cycle_id      UUID NOT NULL REFERENCES review_cycles(id) ON DELETE CASCADE,
  competency_id UUID NOT NULL REFERENCES competencies(id),
  weight        NUMERIC(3,2) DEFAULT 1.0,
  PRIMARY KEY (cycle_id, competency_id)
);


CREATE TYPE review_kind AS ENUM ('self', 'manager', 'peer', 'subordinate', 'calibration');
CREATE TYPE review_status AS ENUM ('pending', 'in_progress', 'submitted', 'reviewed');

CREATE TABLE reviews (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  cycle_id        UUID NOT NULL REFERENCES review_cycles(id) ON DELETE CASCADE,
  evaluatee_id    UUID NOT NULL REFERENCES users(id),                     -- avaliado
  evaluator_id    UUID REFERENCES users(id),                              -- avaliador (NULL para 'self')
  kind            review_kind NOT NULL,
  status          review_status NOT NULL DEFAULT 'pending',
  overall_score   NUMERIC(3,2),                                           -- nota final calculada (0-5)
  comments        TEXT,
  submitted_at    TIMESTAMPTZ,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_reviews_cycle      ON reviews (cycle_id);
CREATE INDEX idx_reviews_evaluatee  ON reviews (evaluatee_id, cycle_id);
CREATE INDEX idx_reviews_evaluator  ON reviews (evaluator_id) WHERE evaluator_id IS NOT NULL;


CREATE TABLE review_answers (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  review_id       UUID NOT NULL REFERENCES reviews(id) ON DELETE CASCADE,
  competency_id   UUID NOT NULL REFERENCES competencies(id),
  score           INTEGER NOT NULL CHECK (score >= 1 AND score <= 10),    -- escala configurável
  comment         TEXT,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),

  UNIQUE (review_id, competency_id)
);


-- 9-Box: posicionamento desempenho × potencial
CREATE TABLE nine_box_positions (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  cycle_id          UUID NOT NULL REFERENCES review_cycles(id) ON DELETE CASCADE,
  user_id           UUID NOT NULL REFERENCES users(id),
  performance       INTEGER NOT NULL CHECK (performance BETWEEN 1 AND 3), -- baixo/médio/alto
  potential         INTEGER NOT NULL CHECK (potential BETWEEN 1 AND 3),
  classification    TEXT,                                                 -- "Alto Desempenho", "Talento", etc.
  notes             TEXT,
  decided_by_user_id UUID REFERENCES users(id),
  decided_at        TIMESTAMPTZ,
  created_at        TIMESTAMPTZ NOT NULL DEFAULT now(),

  UNIQUE (cycle_id, user_id)
);



-- ============================================================================
-- 7. FEEDBACK CONTÍNUO E PRAISES (ELOGIOS)
-- ============================================================================

CREATE TYPE feedback_kind AS ENUM ('positive', 'constructive', 'recognition', 'request');

CREATE TABLE feedbacks (
  id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id   UUID NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
  from_user_id UUID REFERENCES users(id),                                 -- NULL se anônimo
  to_user_id   UUID NOT NULL REFERENCES users(id),
  kind         feedback_kind NOT NULL,
  content      TEXT NOT NULL,
  is_anonymous BOOLEAN NOT NULL DEFAULT FALSE,
  is_private   BOOLEAN NOT NULL DEFAULT TRUE,                             -- visível só para o destinatário
  competency_id UUID REFERENCES competencies(id),                         -- opcional: vincula a competência
  cycle_id     UUID REFERENCES review_cycles(id),                         -- opcional: contexto de ciclo
  created_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_fb_to_user    ON feedbacks (to_user_id, created_at DESC);
CREATE INDEX idx_fb_from_user  ON feedbacks (from_user_id, created_at DESC) WHERE from_user_id IS NOT NULL;


-- Feedback solicitado (quando usuário pede feedback de alguém)
CREATE TABLE feedback_requests (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id      UUID NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
  requester_id    UUID NOT NULL REFERENCES users(id),
  asked_to_id     UUID NOT NULL REFERENCES users(id),
  topic           TEXT,                                                   -- "Sobre minha apresentação ontem"
  status          TEXT NOT NULL DEFAULT 'pending',                        -- pending, fulfilled, declined
  feedback_id     UUID REFERENCES feedbacks(id),                          -- preenchido ao responder
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);


-- Mural público de elogios
CREATE TABLE praises (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id    UUID NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
  from_user_id  UUID NOT NULL REFERENCES users(id),
  to_user_id    UUID NOT NULL REFERENCES users(id),
  message       TEXT NOT NULL,
  reactions_count INTEGER NOT NULL DEFAULT 0,                             -- desnormalizado para performance
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_praises_company ON praises (company_id, created_at DESC);
CREATE INDEX idx_praises_to_user ON praises (to_user_id, created_at DESC);


CREATE TABLE praise_reactions (
  praise_id     UUID NOT NULL REFERENCES praises(id) ON DELETE CASCADE,
  user_id       UUID NOT NULL REFERENCES users(id),
  emoji         TEXT NOT NULL,                                            -- '❤', '👏', '🎉'
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (praise_id, user_id)
);



-- ============================================================================
-- 8. MOVIMENTAÇÕES DE PESSOAL (workflow com aprovação)
-- ============================================================================
-- Toda alteração de cargo, departamento, salário, filial ou desligamento
-- passa pelo fluxo: solicitante → líder direto → RH (final).
-- Cada movimentação tem snapshot do "antes" e "depois" em JSONB para auditoria.
-- ============================================================================

CREATE TYPE movement_type AS ENUM (
  'department_change',     -- mudança de setor
  'position_change',       -- mudança de função
  'unit_change',           -- mudança de filial (working_unit)
  'employer_change',       -- mudança de empregador (raro, ex: efetivação de terceirizado)
  'promotion',             -- promoção
  'salary_adjustment',     -- reajuste salarial
  'manager_change',        -- mudança de gestor
  'termination',           -- desligamento
  'leave',                 -- início de licença
  'return',                -- retorno de licença
  'rehire'                 -- recontratação
);

CREATE TYPE movement_status AS ENUM (
  'draft',                 -- rascunho do solicitante
  'pending_manager',       -- aguardando aprovação do líder
  'pending_hr',            -- aguardando aprovação do RH
  'approved',              -- aprovada e aplicada
  'rejected',              -- rejeitada
  'cancelled'              -- cancelada pelo solicitante
);

CREATE TYPE movement_priority AS ENUM ('normal', 'high', 'urgent');

CREATE TABLE personnel_movements (
  id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id          UUID NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
  user_company_id     UUID NOT NULL REFERENCES user_companies(id),        -- vínculo afetado
  type                movement_type NOT NULL,
  status              movement_status NOT NULL DEFAULT 'draft',
  priority            movement_priority NOT NULL DEFAULT 'normal',

  -- DADOS DA MOVIMENTAÇÃO ---------------------------------------------------
  before_snapshot     JSONB NOT NULL,                                     -- snapshot dos campos antes
  after_snapshot      JSONB NOT NULL,                                     -- valores propostos
  effective_date      DATE NOT NULL,                                      -- quando passa a valer
  justification       TEXT NOT NULL,

  -- WORKFLOW ----------------------------------------------------------------
  requested_by_user_id    UUID NOT NULL REFERENCES users(id),
  manager_decision_by     UUID REFERENCES users(id),
  manager_decision_at     TIMESTAMPTZ,
  manager_comment         TEXT,
  hr_decision_by          UUID REFERENCES users(id),
  hr_decision_at          TIMESTAMPTZ,
  hr_comment              TEXT,
  rejection_reason_code   TEXT,                                           -- 'salary_policy','no_budget','docs_incomplete','other'
  applied_at              TIMESTAMPTZ,                                    -- quando a mudança foi efetivada no banco
  reverted_at             TIMESTAMPTZ,                                    -- caso reversão
  reverted_by_user_id     UUID REFERENCES users(id),
  due_date                DATE,                                           -- prazo SLA da decisão do RH

  -- VALIDAÇÕES AUTOMÁTICAS (cache do dry-run) ------------------------------
  validation_status       TEXT,                                           -- 'ok', 'warn', 'fail'
  validation_details      JSONB DEFAULT '{}'::jsonb,

  created_at              TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at              TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_mov_company       ON personnel_movements (company_id);
CREATE INDEX idx_mov_uc            ON personnel_movements (user_company_id);
CREATE INDEX idx_mov_status        ON personnel_movements (company_id, status);
CREATE INDEX idx_mov_pending_hr    ON personnel_movements (company_id) WHERE status = 'pending_hr';
CREATE INDEX idx_mov_requested_by  ON personnel_movements (requested_by_user_id);
CREATE INDEX idx_mov_due_date      ON personnel_movements (due_date) WHERE status IN ('pending_manager','pending_hr');

COMMENT ON COLUMN personnel_movements.before_snapshot IS
  'Snapshot dos campos relevantes antes da mudança. Ex.: {"position_id":"uuid","base_salary":3650,"working_unit_id":"uuid"}';

COMMENT ON COLUMN personnel_movements.after_snapshot IS
  'Valores propostos. Mesma estrutura de before_snapshot. Ao aprovar, esses valores são aplicados em user_companies.';



-- ============================================================================
-- 9. IMPORTAÇÕES (rastreio de cargas em massa)
-- ============================================================================

CREATE TYPE import_status AS ENUM ('uploaded','validating','validated','executing','completed','partial','failed','reverted');

CREATE TABLE imports (
  id                 UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id         UUID NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
  type               TEXT NOT NULL,                                       -- 'colaboradores','filiais','cargos','departamentos','movimentacoes','historico'
  filename           TEXT NOT NULL,
  file_url           TEXT,                                                -- caminho no Supabase Storage
  file_size_bytes    BIGINT,
  status             import_status NOT NULL DEFAULT 'uploaded',
  total_rows         INTEGER NOT NULL DEFAULT 0,
  ok_rows            INTEGER NOT NULL DEFAULT 0,
  warn_rows          INTEGER NOT NULL DEFAULT 0,
  error_rows         INTEGER NOT NULL DEFAULT 0,
  validation_report  JSONB DEFAULT '[]'::jsonb,                           -- array com problemas por linha
  options            JSONB DEFAULT '{}'::jsonb,                           -- opções escolhidas no wizard
  imported_by_user_id UUID NOT NULL REFERENCES users(id),
  started_at         TIMESTAMPTZ,
  completed_at       TIMESTAMPTZ,
  reverted_at        TIMESTAMPTZ,                                         -- janela de 24h para reversão
  created_at         TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_imports_company ON imports (company_id, created_at DESC);



-- ============================================================================
-- 10. AUDITORIA (LGPD)
-- ============================================================================
-- Registro centralizado de todas as ações relevantes:
--   - Acessos a dados sensíveis (CPF, salário, dados bancários)
--   - Alterações em registros (CRUD)
--   - Login, logout, troca de senha
--   - Aprovações de movimentações
--   - Importações
--   - Exportações
-- Retenção mínima: 5 anos (configurável). Logs antigos arquivados em S3 frio.
-- ============================================================================

CREATE TYPE audit_action AS ENUM (
  'create','update','delete','login','logout','password_reset',
  'view_sensitive','export','import','approve','reject',
  'permission_grant','permission_revoke','impersonate'
);

CREATE TABLE audit_log (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id      UUID REFERENCES companies(id),                          -- pode ser NULL para ações globais
  actor_user_id   UUID REFERENCES users(id),                              -- quem fez a ação
  action          audit_action NOT NULL,
  table_name      TEXT,                                                   -- ex: 'user_companies'
  record_id       UUID,                                                   -- ID do registro afetado
  changes         JSONB DEFAULT '{}'::jsonb,                              -- {"before":{...},"after":{...}}
  reason          TEXT,                                                   -- justificativa quando aplicável
  ip_address      INET,
  user_agent      TEXT,
  session_id      TEXT,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_audit_company   ON audit_log (company_id, created_at DESC);
CREATE INDEX idx_audit_actor     ON audit_log (actor_user_id, created_at DESC) WHERE actor_user_id IS NOT NULL;
CREATE INDEX idx_audit_record    ON audit_log (table_name, record_id) WHERE record_id IS NOT NULL;
CREATE INDEX idx_audit_action    ON audit_log (action, created_at DESC);



-- ============================================================================
-- 11. NOTIFICAÇÕES (in-app)
-- ============================================================================

CREATE TYPE notification_kind AS ENUM (
  'feedback_received','review_pending','review_submitted',
  'movement_pending','movement_approved','movement_rejected',
  'cycle_opened','cycle_closing','birthday','work_anniversary',
  'new_team_member','praise_received','system'
);

CREATE TABLE notifications (
  id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id   UUID NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
  to_user_id   UUID NOT NULL REFERENCES users(id),
  kind         notification_kind NOT NULL,
  title        TEXT NOT NULL,
  body         TEXT,
  link         TEXT,                                                      -- URL relativa para abrir
  data         JSONB DEFAULT '{}'::jsonb,
  read_at      TIMESTAMPTZ,
  created_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_notif_user_unread ON notifications (to_user_id, created_at DESC) WHERE read_at IS NULL;



-- ============================================================================
-- 12. RLS · ROW LEVEL SECURITY
-- ============================================================================
-- Toda tabela com company_id tem RLS ativado. As policies usam funções
-- helper que leem o JWT claim 'active_company_id' para determinar o tenant
-- corrente do usuário, e cruzam com permission_profiles para escopo.
-- ============================================================================

-- Função helper: company_id corrente (do JWT)
CREATE OR REPLACE FUNCTION current_user_company_id()
RETURNS UUID
LANGUAGE SQL STABLE SECURITY DEFINER AS $$
  SELECT COALESCE(
    (current_setting('request.jwt.claims', true)::jsonb ->> 'active_company_id')::UUID,
    NULL
  )
$$;

-- Função helper: user_id do usuário autenticado
CREATE OR REPLACE FUNCTION current_user_id()
RETURNS UUID
LANGUAGE SQL STABLE SECURITY DEFINER AS $$
  SELECT u.id FROM users u
   WHERE u.auth_user_id = auth.uid()
   LIMIT 1
$$;

-- Função helper: o user X é subordinado direto ou indireto do current_user_id?
CREATE OR REPLACE FUNCTION is_subordinate_of_current_user(target_user_id UUID)
RETURNS BOOLEAN
LANGUAGE SQL STABLE SECURITY DEFINER AS $$
  WITH RECURSIVE chain AS (
    SELECT user_id FROM user_companies
     WHERE manager_user_id = current_user_id()
       AND company_id = current_user_company_id()
       AND is_active = TRUE
    UNION ALL
    SELECT uc.user_id FROM user_companies uc
      JOIN chain c ON uc.manager_user_id = c.user_id
     WHERE uc.company_id = current_user_company_id()
       AND uc.is_active = TRUE
  )
  SELECT EXISTS (SELECT 1 FROM chain WHERE user_id = target_user_id)
$$;

-- Função helper: o usuário tem permissão especial X?
CREATE OR REPLACE FUNCTION current_user_has_permission(perm TEXT)
RETURNS BOOLEAN
LANGUAGE SQL STABLE SECURITY DEFINER AS $$
  SELECT EXISTS (
    SELECT 1
      FROM user_companies uc
      JOIN permission_profiles pp ON pp.id = uc.permission_profile_id
     WHERE uc.user_id = current_user_id()
       AND uc.company_id = current_user_company_id()
       AND uc.is_active = TRUE
       AND perm = ANY(pp.special_permissions)
  )
$$;


-- Ativar RLS em todas as tabelas com tenant
ALTER TABLE companies                  ENABLE ROW LEVEL SECURITY;
ALTER TABLE units                      ENABLE ROW LEVEL SECURITY;
ALTER TABLE departments                ENABLE ROW LEVEL SECURITY;
ALTER TABLE positions                  ENABLE ROW LEVEL SECURITY;
ALTER TABLE user_companies             ENABLE ROW LEVEL SECURITY;
ALTER TABLE permission_profiles        ENABLE ROW LEVEL SECURITY;
ALTER TABLE profile_page_permissions   ENABLE ROW LEVEL SECURITY;
ALTER TABLE profile_employer_scope     ENABLE ROW LEVEL SECURITY;
ALTER TABLE profile_unit_scope         ENABLE ROW LEVEL SECURITY;
ALTER TABLE profile_department_scope   ENABLE ROW LEVEL SECURITY;
ALTER TABLE user_permission_overrides  ENABLE ROW LEVEL SECURITY;
ALTER TABLE competencies               ENABLE ROW LEVEL SECURITY;
ALTER TABLE review_cycles              ENABLE ROW LEVEL SECURITY;
ALTER TABLE cycle_competencies         ENABLE ROW LEVEL SECURITY;
ALTER TABLE reviews                    ENABLE ROW LEVEL SECURITY;
ALTER TABLE review_answers             ENABLE ROW LEVEL SECURITY;
ALTER TABLE nine_box_positions         ENABLE ROW LEVEL SECURITY;
ALTER TABLE feedbacks                  ENABLE ROW LEVEL SECURITY;
ALTER TABLE feedback_requests          ENABLE ROW LEVEL SECURITY;
ALTER TABLE praises                    ENABLE ROW LEVEL SECURITY;
ALTER TABLE praise_reactions           ENABLE ROW LEVEL SECURITY;
ALTER TABLE personnel_movements        ENABLE ROW LEVEL SECURITY;
ALTER TABLE imports                    ENABLE ROW LEVEL SECURITY;
ALTER TABLE audit_log                  ENABLE ROW LEVEL SECURITY;
ALTER TABLE notifications              ENABLE ROW LEVEL SECURITY;


-- POLICIES BÁSICAS (filtragem por tenant)
-- (As policies de escopo multidimensional ficam mais complexas; aqui mostro o padrão.)

CREATE POLICY tenant_isolation_units ON units
  USING (company_id = current_user_company_id());

CREATE POLICY tenant_isolation_departments ON departments
  USING (company_id = current_user_company_id());

CREATE POLICY tenant_isolation_positions ON positions
  USING (company_id = current_user_company_id());

CREATE POLICY tenant_isolation_competencies ON competencies
  USING (company_id = current_user_company_id());

CREATE POLICY tenant_isolation_cycles ON review_cycles
  USING (company_id = current_user_company_id());


-- POLICY de visibilidade multidimensional para user_companies
-- "Eu vejo um colaborador se OR:
--   - Sou ele mesmo
--   - Sou subordinado-de-mim (recursive)
--   - Meu perfil tem escopo de empregador que inclui o empregador dele
--   - Meu perfil tem escopo de tomador que inclui o tomador dele
--   - Meu perfil tem escopo de departamento que inclui o departamento dele"
-- (Simplificada; a implementação real combina os 4 escopos com regras de produto.)
CREATE POLICY user_companies_visibility ON user_companies
  USING (
    company_id = current_user_company_id()
    AND (
      -- Eu mesmo
      user_id = current_user_id()
      OR
      -- Subordinado direto/indireto
      is_subordinate_of_current_user(user_id)
      OR
      -- Meu perfil tem escopo de empregador "all" ou específico que inclui este empregador
      EXISTS (
        SELECT 1 FROM user_companies my
          JOIN permission_profiles pp ON pp.id = my.permission_profile_id
         WHERE my.user_id = current_user_id()
           AND my.company_id = current_user_company_id()
           AND my.is_active = TRUE
           AND (
             pp.employer_scope = 'all'
             OR (pp.employer_scope = 'specific' AND user_companies.employer_unit_id IN (
                 SELECT unit_id FROM profile_employer_scope WHERE profile_id = pp.id
             ))
             OR (pp.employer_scope = 'self' AND user_companies.employer_unit_id = my.employer_unit_id)
           )
           AND (
             pp.unit_scope = 'all'
             OR (pp.unit_scope = 'specific' AND user_companies.working_unit_id IN (
                 SELECT unit_id FROM profile_unit_scope WHERE profile_id = pp.id
             ))
             OR (pp.unit_scope = 'self' AND user_companies.working_unit_id = my.working_unit_id)
           )
      )
    )
  );


-- POLICY de notificações: cada usuário só vê as próprias
CREATE POLICY notif_owner_only ON notifications
  USING (to_user_id = current_user_id() AND company_id = current_user_company_id());


-- POLICY de feedbacks privados: só destinatário e remetente veem
CREATE POLICY feedback_visibility ON feedbacks
  USING (
    company_id = current_user_company_id()
    AND (
      is_private = FALSE
      OR to_user_id = current_user_id()
      OR from_user_id = current_user_id()
      OR current_user_has_permission('view_audit')
    )
  );


-- POLICY de audit_log: só RH com permissão view_audit
CREATE POLICY audit_log_visibility ON audit_log
  USING (
    company_id = current_user_company_id()
    AND (
      actor_user_id = current_user_id()
      OR current_user_has_permission('view_audit')
    )
  );



-- ============================================================================
-- 13. TRIGGERS · updated_at automático e auditoria
-- ============================================================================

CREATE OR REPLACE FUNCTION trg_set_updated_at()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$;

-- Aplicar em todas as tabelas com updated_at
DO $$
DECLARE t TEXT;
BEGIN
  FOR t IN
    SELECT table_name FROM information_schema.columns
     WHERE table_schema = 'public' AND column_name = 'updated_at'
  LOOP
    EXECUTE format(
      'CREATE TRIGGER set_updated_at BEFORE UPDATE ON %I FOR EACH ROW EXECUTE FUNCTION trg_set_updated_at();',
      t
    );
  END LOOP;
END $$;


-- Trigger genérico de auditoria (registra mudanças em tabelas críticas)
CREATE OR REPLACE FUNCTION trg_audit_changes()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
DECLARE
  v_action audit_action;
  v_company UUID;
BEGIN
  IF TG_OP = 'INSERT' THEN v_action := 'create';
  ELSIF TG_OP = 'UPDATE' THEN v_action := 'update';
  ELSIF TG_OP = 'DELETE' THEN v_action := 'delete';
  END IF;

  -- Tenta extrair company_id do registro
  IF TG_OP = 'DELETE' THEN
    BEGIN
      v_company := (to_jsonb(OLD)->>'company_id')::UUID;
    EXCEPTION WHEN others THEN v_company := NULL;
    END;
  ELSE
    BEGIN
      v_company := (to_jsonb(NEW)->>'company_id')::UUID;
    EXCEPTION WHEN others THEN v_company := NULL;
    END;
  END IF;

  INSERT INTO audit_log (company_id, actor_user_id, action, table_name, record_id, changes)
  VALUES (
    v_company,
    current_user_id(),
    v_action,
    TG_TABLE_NAME,
    COALESCE((to_jsonb(NEW)->>'id')::UUID, (to_jsonb(OLD)->>'id')::UUID),
    CASE
      WHEN TG_OP = 'INSERT' THEN jsonb_build_object('after', to_jsonb(NEW))
      WHEN TG_OP = 'UPDATE' THEN jsonb_build_object('before', to_jsonb(OLD), 'after', to_jsonb(NEW))
      WHEN TG_OP = 'DELETE' THEN jsonb_build_object('before', to_jsonb(OLD))
    END
  );

  RETURN COALESCE(NEW, OLD);
END;
$$;

-- Aplica auditoria nas tabelas mais sensíveis
CREATE TRIGGER audit_user_companies
  AFTER INSERT OR UPDATE OR DELETE ON user_companies
  FOR EACH ROW EXECUTE FUNCTION trg_audit_changes();

CREATE TRIGGER audit_personnel_movements
  AFTER INSERT OR UPDATE OR DELETE ON personnel_movements
  FOR EACH ROW EXECUTE FUNCTION trg_audit_changes();

CREATE TRIGGER audit_permission_profiles
  AFTER INSERT OR UPDATE OR DELETE ON permission_profiles
  FOR EACH ROW EXECUTE FUNCTION trg_audit_changes();

CREATE TRIGGER audit_user_permission_overrides
  AFTER INSERT OR UPDATE OR DELETE ON user_permission_overrides
  FOR EACH ROW EXECUTE FUNCTION trg_audit_changes();



-- ============================================================================
-- 14. VIEWS DE APOIO PARA RELATÓRIOS
-- ============================================================================

-- Headcount cruzado empregador × tomador (matriz)
CREATE OR REPLACE VIEW v_headcount_matrix AS
SELECT
  uc.company_id,
  emp.id          AS employer_unit_id,
  emp.code        AS employer_code,
  emp.name        AS employer_name,
  emp.role        AS employer_role,
  tom.id          AS working_unit_id,
  tom.code        AS working_code,
  tom.name        AS working_name,
  COUNT(*) FILTER (WHERE uc.is_active AND uc.status = 'active') AS active_count,
  COUNT(*) AS total_count
FROM user_companies uc
JOIN units emp ON emp.id = uc.employer_unit_id
JOIN units tom ON tom.id = uc.working_unit_id
GROUP BY uc.company_id, emp.id, emp.code, emp.name, emp.role, tom.id, tom.code, tom.name;


-- Visão consolidada do colaborador (ideal para listagens)
CREATE OR REPLACE VIEW v_employees AS
SELECT
  uc.id                AS user_company_id,
  uc.company_id,
  u.id                 AS user_id,
  u.username,
  u.full_name,
  u.email,
  u.cpf,
  u.photo_url,
  emp.id               AS employer_unit_id,
  emp.code             AS employer_code,
  emp.name             AS employer_name,
  emp.role             AS employer_role,
  tom.id               AS working_unit_id,
  tom.code             AS working_code,
  tom.name             AS working_name,
  d.id                 AS department_id,
  d.name               AS department_name,
  p.id                 AS position_id,
  p.name               AS position_name,
  p.level              AS position_level,
  uc.contract_type,
  uc.hire_date,
  uc.allocation_start_date,
  uc.base_salary,
  uc.status,
  uc.is_active,
  m.full_name          AS manager_name,
  uc.manager_user_id,
  EXTRACT(YEAR FROM age(uc.hire_date))::int * 12
    + EXTRACT(MONTH FROM age(uc.hire_date))::int AS tenure_months
FROM user_companies uc
JOIN users u             ON u.id = uc.user_id
JOIN units emp           ON emp.id = uc.employer_unit_id
JOIN units tom           ON tom.id = uc.working_unit_id
LEFT JOIN departments d  ON d.id = uc.department_id
LEFT JOIN positions p    ON p.id = uc.position_id
LEFT JOIN users m        ON m.id = uc.manager_user_id;


-- ============================================================================
-- FIM DO SCHEMA v3
-- ============================================================================
-- Próximos passos para produção:
--   1. Implementar policies RLS de escopo multidimensional completas
--      (combinando os 4 eixos: empregador, tomador, departamento, hierarquia)
--   2. Criar funções RPC para o report builder (axis-switch dinâmico)
--   3. Adicionar particionamento em audit_log por mês (após 100k linhas)
--   4. Configurar Supabase Realtime para notifications e movement workflow
--   5. Criar seed inicial com perfis system: Super Admin, Admin RH,
--      Líder, Coordenador, Colaborador, Auditor
-- ============================================================================

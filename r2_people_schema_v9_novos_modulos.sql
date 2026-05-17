-- =============================================================================
-- R2 People · Schema v9 · módulos novos
-- =============================================================================
-- Cobre os 8 módulos adicionados nas v2.6/2.7/2.8 da Camada 1 (HTMLs).
-- Estrutura blueprint pronta para portar pra Supabase quando ambiente
-- estiver disponível (ver docs/spec_*.md para passos individuais).
--
-- Módulos cobertos:
--   1. Notifications        · bell topbar + página /notificacoes
--   2. Comunicados          · feed editorial
--   3. Vagas internas       · jobboard + indicações
--   4. Treinamentos         · trilhas LMS
--   5. Climate (pulse)      · pesquisa semanal anônima
--   6. eNPS                 · NPS quinzenal
--   7. OKRs                 · objetivos + key results + check-ins
--   8. Cargos & Salários    · banda salarial estruturada
--
-- Convenções:
--   - Tudo é multi-tenant (tenant_id NOT NULL)
--   - Soft-delete via active boolean
--   - UUIDs com gen_random_uuid()
--   - TIMESTAMPTZ para datas (UTC)
--   - Sem em-dashes em comentários
--   - Sem acentos em comentários SQL
-- =============================================================================

-- =============================================================================
-- ENUMS
-- =============================================================================

DO $$ BEGIN CREATE TYPE notif_kind AS ENUM (
  'pdi', 'okr', 'recognition', 'oneonone', 'climate', 'enps',
  'movement', 'medical', 'vacation', 'communicate', 'system', 'mention'
); EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN CREATE TYPE comm_category AS ENUM (
  'rh', 'diretoria', 'ti', 'juridico', 'eventos', 'beneficios', 'comercial', 'outros'
); EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN CREATE TYPE job_kind AS ENUM (
  'clt_efetivo', 'estagio', 'jovem_aprendiz', 'pj', 'temporario', 'terceirizado'
); EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN CREATE TYPE job_status AS ENUM (
  'draft', 'open', 'on_hold', 'filled', 'cancelled'
); EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN CREATE TYPE indication_status AS ENUM (
  'awaiting_review', 'in_process', 'rejected', 'hired', 'in_experience', 'paid'
); EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN CREATE TYPE trail_kind AS ENUM (
  'mandatory', 'role_based', 'optional', 'leadership', 'compliance', 'soft_skills', 'technical'
); EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN CREATE TYPE enrollment_status AS ENUM (
  'enrolled', 'in_progress', 'completed', 'abandoned'
); EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN CREATE TYPE okr_period AS ENUM (
  'quarterly', 'yearly', 'custom'
); EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN CREATE TYPE okr_scope AS ENUM (
  'personal', 'team', 'company'
); EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN CREATE TYPE kr_status AS ENUM (
  'on_track', 'at_risk', 'behind', 'done', 'cancelled'
); EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN CREATE TYPE job_level AS ENUM (
  'junior', 'pleno', 'senior', 'especialista', 'lideranca'
); EXCEPTION WHEN duplicate_object THEN NULL; END $$;


-- =============================================================================
-- MODULO 1 · NOTIFICATIONS
-- =============================================================================
-- Tabela genérica de notificações in-app. Cada notif tem owner (destinatario),
-- kind, payload JSONB e link de acao opcional.

CREATE TABLE IF NOT EXISTS notifications (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id       UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,

  -- Quem recebe
  recipient_id    UUID NOT NULL REFERENCES app_users(id) ON DELETE CASCADE,

  kind            notif_kind NOT NULL,
  title           VARCHAR(200) NOT NULL,
  body            TEXT,

  -- Quem disparou (NULL para notif sistema)
  actor_user_id   UUID REFERENCES app_users(id),
  actor_name      VARCHAR(160),                       -- snapshot caso actor seja deletado

  -- Acao opcional (link relativo dentro do produto)
  action_url      TEXT,                                -- ex: '/atestados/validar/{id}'
  action_label    VARCHAR(80),                        -- ex: 'Validar agora'

  -- Payload livre (dados extras especificos por kind)
  payload         JSONB NOT NULL DEFAULT '{}'::jsonb,

  -- Lifecycle
  read_at         TIMESTAMPTZ,
  archived_at     TIMESTAMPTZ,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_notif_recipient_unread
  ON notifications(recipient_id, created_at DESC)
  WHERE read_at IS NULL AND archived_at IS NULL;

CREATE INDEX IF NOT EXISTS idx_notif_recipient_all
  ON notifications(recipient_id, created_at DESC)
  WHERE archived_at IS NULL;

CREATE INDEX IF NOT EXISTS idx_notif_tenant_kind
  ON notifications(tenant_id, kind, created_at DESC);

-- Configuracao de mute por usuario/kind (silenciar categorias)
CREATE TABLE IF NOT EXISTS notification_preferences (
  user_id         UUID PRIMARY KEY REFERENCES app_users(id) ON DELETE CASCADE,
  muted_kinds     TEXT[] NOT NULL DEFAULT ARRAY[]::TEXT[],   -- ex: ['communicate', 'enps']
  digest_mode     VARCHAR(20) NOT NULL DEFAULT 'realtime',   -- 'realtime' | 'daily' | 'weekly' | 'off'
  digest_hour     INT NOT NULL DEFAULT 9,                    -- 0-23 (hora local do tenant)
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);


-- =============================================================================
-- MODULO 2 · COMUNICADOS INTERNOS
-- =============================================================================

CREATE TABLE IF NOT EXISTS communicates (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id       UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,

  category        comm_category NOT NULL,
  title           VARCHAR(240) NOT NULL,
  excerpt         TEXT,                                -- resumo curto pra feed
  body            TEXT NOT NULL,                       -- markdown ou HTML sanitizado

  -- Quem publicou (RH ou Diretoria)
  author_id       UUID NOT NULL REFERENCES app_users(id),

  -- Visibilidade
  visibility      VARCHAR(20) NOT NULL DEFAULT 'all', -- 'all' | 'role' | 'unit' | 'custom'
  visible_roles   TEXT[],                              -- ex: ['rh', 'lider'] se visibility='role'
  visible_units   UUID[],                              -- working_units se 'unit'

  -- Destaques
  is_featured     BOOLEAN NOT NULL DEFAULT FALSE,
  is_priority     BOOLEAN NOT NULL DEFAULT FALSE,     -- mostra badge 'Importante'

  -- Engajamento (denormalizados, atualizados via trigger)
  view_count      INT NOT NULL DEFAULT 0,
  comment_count   INT NOT NULL DEFAULT 0,
  reaction_count  INT NOT NULL DEFAULT 0,

  -- Calendario (se o comunicado anuncia algo com data)
  event_date      DATE,
  event_location  VARCHAR(160),

  -- Lifecycle
  published_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
  archived_at     TIMESTAMPTZ,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_comm_tenant_published
  ON communicates(tenant_id, published_at DESC)
  WHERE archived_at IS NULL;

CREATE INDEX IF NOT EXISTS idx_comm_featured
  ON communicates(tenant_id, is_featured)
  WHERE is_featured = TRUE AND archived_at IS NULL;

CREATE TABLE IF NOT EXISTS communicate_views (
  communicate_id  UUID NOT NULL REFERENCES communicates(id) ON DELETE CASCADE,
  user_id         UUID NOT NULL REFERENCES app_users(id) ON DELETE CASCADE,
  viewed_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (communicate_id, user_id)
);

CREATE TABLE IF NOT EXISTS communicate_reactions (
  communicate_id  UUID NOT NULL REFERENCES communicates(id) ON DELETE CASCADE,
  user_id         UUID NOT NULL REFERENCES app_users(id) ON DELETE CASCADE,
  reaction        VARCHAR(20) NOT NULL,               -- 'thanks', 'love', 'celebrate', etc.
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (communicate_id, user_id)
);


-- =============================================================================
-- MODULO 3 · VAGAS INTERNAS + INDICACOES
-- =============================================================================

CREATE TABLE IF NOT EXISTS jobs (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id       UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,

  title           VARCHAR(160) NOT NULL,
  job_role_id     UUID,                                -- FK opcional pra cargo formal (M1 spec)
  working_unit_id UUID,                                -- onde a vaga e

  description     TEXT,
  requirements    TEXT,
  benefits        TEXT,

  kind            job_kind NOT NULL DEFAULT 'clt_efetivo',
  status          job_status NOT NULL DEFAULT 'open',

  -- Salario (range opcional · pode usar a banda do cargo se job_role_id)
  salary_min      NUMERIC(12,2),
  salary_max      NUMERIC(12,2),
  hide_salary     BOOLEAN NOT NULL DEFAULT FALSE,

  -- Localizacao
  remote          BOOLEAN NOT NULL DEFAULT FALSE,
  city            VARCHAR(120),
  state_uf        VARCHAR(2),

  -- Programa de indicacao
  internal_only   BOOLEAN NOT NULL DEFAULT FALSE,     -- so colaboradores podem ver/indicar
  referral_bonus  NUMERIC(10,2) DEFAULT 1500.00,      -- R$ pago se indicacao for contratada e passar 90d
  urgent          BOOLEAN NOT NULL DEFAULT FALSE,
  deadline        DATE,

  -- Owner (gerente da vaga)
  owner_user_id   UUID REFERENCES app_users(id),

  -- Lifecycle
  opened_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
  filled_at       TIMESTAMPTZ,
  filled_by_user_id UUID REFERENCES app_users(id),

  created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT now(),

  CONSTRAINT jobs_salary_order CHECK (
    salary_min IS NULL OR salary_max IS NULL OR salary_max >= salary_min
  )
);

CREATE INDEX IF NOT EXISTS idx_jobs_tenant_open
  ON jobs(tenant_id, status) WHERE status = 'open';

CREATE INDEX IF NOT EXISTS idx_jobs_urgent
  ON jobs(tenant_id, urgent, deadline) WHERE urgent = TRUE AND status = 'open';

CREATE TABLE IF NOT EXISTS job_applications (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id       UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,

  job_id          UUID NOT NULL REFERENCES jobs(id) ON DELETE CASCADE,
  applicant_id    UUID NOT NULL REFERENCES app_users(id) ON DELETE CASCADE,

  cover_letter    TEXT,
  cv_storage_path TEXT,

  status          VARCHAR(40) NOT NULL DEFAULT 'submitted',
  -- 'submitted' | 'in_review' | 'interview' | 'offer' | 'rejected' | 'withdrawn'

  rejected_reason TEXT,
  notes           TEXT,                                -- notas internas do RH

  applied_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT now(),

  UNIQUE (job_id, applicant_id)
);

CREATE TABLE IF NOT EXISTS job_indications (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id       UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,

  job_id          UUID NOT NULL REFERENCES jobs(id) ON DELETE CASCADE,

  -- Quem indicou (colaborador interno)
  referrer_id     UUID NOT NULL REFERENCES app_users(id) ON DELETE CASCADE,

  -- Candidato externo
  candidate_name  VARCHAR(160) NOT NULL,
  candidate_email VARCHAR(180) NOT NULL,
  candidate_phone VARCHAR(40),
  candidate_age   INT,
  relationship    VARCHAR(80),                         -- ex: 'ex-colega de trabalho'
  why_recommend   TEXT,

  status          indication_status NOT NULL DEFAULT 'awaiting_review',

  -- Apos contratacao, tracking
  hired_at        DATE,
  experience_end  DATE,                                -- hired_at + 90 dias
  bonus_amount    NUMERIC(10,2),                       -- valor que sera pago
  bonus_paid_at   DATE,

  created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT now(),

  -- Unique: primeiro a indicar leva (mesmo candidato em mesmo tenant)
  UNIQUE (tenant_id, candidate_email)
);

CREATE INDEX IF NOT EXISTS idx_indications_referrer
  ON job_indications(referrer_id, created_at DESC);


-- =============================================================================
-- MODULO 4 · TREINAMENTOS / TRILHAS
-- =============================================================================

CREATE TABLE IF NOT EXISTS training_trails (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id       UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,

  code            VARCHAR(60) NOT NULL,                -- 'LGPD-2026', 'POWERBI-101'
  title           VARCHAR(200) NOT NULL,
  description     TEXT,

  kind            trail_kind NOT NULL DEFAULT 'optional',
  estimated_hours INT NOT NULL DEFAULT 1,

  -- Categoria visual / capa
  cover_color     VARCHAR(20) DEFAULT 'navy',          -- navy | orange | teal | etc.
  cover_emoji     VARCHAR(10),

  -- Conformidade
  is_certificate  BOOLEAN NOT NULL DEFAULT FALSE,      -- gera certificado ao concluir
  passing_score   INT,                                 -- 0-100, se houver prova

  -- Prazo
  deadline_days   INT,                                 -- prazo a partir da inscricao
  recurrence_months INT,                               -- LGPD anual = 12

  -- Publico-alvo (se sugerida automaticamente)
  target_roles    TEXT[],                              -- ex: ['lider', 'rh']
  target_job_role_codes TEXT[],                        -- ex: ['ANALISTA-DADOS']

  active          BOOLEAN NOT NULL DEFAULT TRUE,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT now(),

  UNIQUE (tenant_id, code)
);

CREATE TABLE IF NOT EXISTS training_modules (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  trail_id        UUID NOT NULL REFERENCES training_trails(id) ON DELETE CASCADE,

  display_order   INT NOT NULL DEFAULT 0,
  title           VARCHAR(200) NOT NULL,
  description     TEXT,

  -- Conteudo (URL ou arquivo)
  content_kind    VARCHAR(20) NOT NULL,                -- 'video' | 'pdf' | 'html' | 'quiz' | 'external'
  content_url     TEXT,
  duration_min    INT,

  created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS training_enrollments (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id       UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,

  user_id         UUID NOT NULL REFERENCES app_users(id) ON DELETE CASCADE,
  trail_id        UUID NOT NULL REFERENCES training_trails(id) ON DELETE CASCADE,

  status          enrollment_status NOT NULL DEFAULT 'enrolled',
  modules_completed INT NOT NULL DEFAULT 0,
  modules_total   INT NOT NULL DEFAULT 0,              -- denorm pra perf
  progress_pct    NUMERIC(5,2) GENERATED ALWAYS AS (
    CASE WHEN modules_total > 0
      THEN ROUND((modules_completed::NUMERIC / modules_total) * 100, 2)
      ELSE 0
    END
  ) STORED,

  -- Tempo investido
  hours_spent     NUMERIC(6,2) NOT NULL DEFAULT 0,

  -- Certificado (se trail.is_certificate e completou)
  cert_issued_at  TIMESTAMPTZ,
  cert_url        TEXT,

  -- Lifecycle
  enrolled_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
  started_at      TIMESTAMPTZ,
  completed_at    TIMESTAMPTZ,
  deadline        DATE,                                -- copiado de trail no enroll

  UNIQUE (user_id, trail_id)
);

CREATE INDEX IF NOT EXISTS idx_enroll_user_status
  ON training_enrollments(user_id, status);


-- =============================================================================
-- MODULO 5 · CLIMA (PULSE SURVEY)
-- =============================================================================

CREATE TABLE IF NOT EXISTS pulse_surveys (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id       UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,

  -- Identificacao
  cycle_year      INT NOT NULL,
  cycle_week      INT NOT NULL,                        -- 1-52
  question        TEXT NOT NULL,                       -- ex: 'Como voce se sente esta semana?'

  -- Janela de resposta
  opens_at        TIMESTAMPTZ NOT NULL,
  closes_at       TIMESTAMPTZ NOT NULL,

  -- Stats agregados (atualizados via trigger ao fechar)
  responses_count INT NOT NULL DEFAULT 0,
  eligible_count  INT NOT NULL DEFAULT 0,              -- snapshot do headcount no opens_at
  participation_pct NUMERIC(5,2),
  mood_avg        NUMERIC(3,2),                        -- media 1-5

  closed_at       TIMESTAMPTZ,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),

  UNIQUE (tenant_id, cycle_year, cycle_week),
  CONSTRAINT pulse_dates_ordered CHECK (closes_at > opens_at)
);

-- Respostas individuais · ANONIMAS
-- IMPORTANTE: nao ha FK direto para app_users
-- Para garantir anonimato, armazena apenas hash do user + tenant + cycle_week.
-- Validacao de duplicata: unique(hash_response, pulse_id)
-- O hash impede que a mesma pessoa responda 2x mas nao revela quem ela e.
CREATE TABLE IF NOT EXISTS pulse_responses (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id       UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  pulse_id        UUID NOT NULL REFERENCES pulse_surveys(id) ON DELETE CASCADE,

  -- Hash anonimo · sha256(user_id || pulse_id || tenant_secret)
  response_hash   VARCHAR(64) NOT NULL,

  mood            INT NOT NULL,                        -- 1-5
  why_factors     TEXT[] NOT NULL DEFAULT ARRAY[]::TEXT[], -- max 3 fatores

  comment         TEXT,                                -- comentario opcional · ANONIMO

  -- Cohort (para agregacao sem identificar individuo)
  -- Estes campos sao denormalizados do app_user mas nao revelam quem e
  cohort_employer UUID,                                -- employer_unit_id
  cohort_working  UUID,                                -- working_unit_id
  cohort_dept     UUID,                                -- department_id
  cohort_role     app_user_role,                       -- role rbac

  submitted_at    TIMESTAMPTZ NOT NULL DEFAULT now(),

  CONSTRAINT pulse_mood_range CHECK (mood BETWEEN 1 AND 5),
  UNIQUE (pulse_id, response_hash)                    -- 1 resposta por pessoa por pulso
);

CREATE INDEX IF NOT EXISTS idx_pulse_resp_cohort
  ON pulse_responses(pulse_id, cohort_working);


-- =============================================================================
-- MODULO 6 · eNPS
-- =============================================================================

CREATE TABLE IF NOT EXISTS enps_surveys (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id       UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,

  cycle_year      INT NOT NULL,
  cycle_fortnight INT NOT NULL,                        -- 1-26 (quinzenas no ano)
  question        TEXT NOT NULL DEFAULT 'Em uma escala de 0 a 10, o quanto voce recomendaria esta empresa como um lugar pra trabalhar?',

  opens_at        TIMESTAMPTZ NOT NULL,
  closes_at       TIMESTAMPTZ NOT NULL,

  -- Stats agregados
  responses_count INT NOT NULL DEFAULT 0,
  eligible_count  INT NOT NULL DEFAULT 0,
  participation_pct NUMERIC(5,2),

  promoters_count INT NOT NULL DEFAULT 0,              -- notas 9-10
  passives_count  INT NOT NULL DEFAULT 0,              -- 7-8
  detractors_count INT NOT NULL DEFAULT 0,             -- 0-6
  enps_score      INT,                                 -- (promoters/total - detractors/total) * 100

  closed_at       TIMESTAMPTZ,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),

  UNIQUE (tenant_id, cycle_year, cycle_fortnight)
);

CREATE TABLE IF NOT EXISTS enps_responses (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id       UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  enps_id         UUID NOT NULL REFERENCES enps_surveys(id) ON DELETE CASCADE,

  response_hash   VARCHAR(64) NOT NULL,                -- mesmo padrao anonimo do pulse

  score           INT NOT NULL,                        -- 0-10
  why_positive    TEXT,                                -- 'o que mais te faria recomendar'
  why_negative    TEXT,                                -- 'o que melhorar pra recomendar mais'

  -- Cohort agregado
  cohort_employer UUID,
  cohort_working  UUID,

  submitted_at    TIMESTAMPTZ NOT NULL DEFAULT now(),

  CONSTRAINT enps_score_range CHECK (score BETWEEN 0 AND 10),
  UNIQUE (enps_id, response_hash)
);


-- =============================================================================
-- MODULO 7 · OKRs
-- =============================================================================

CREATE TABLE IF NOT EXISTS okr_cycles (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id       UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,

  name            VARCHAR(60) NOT NULL,                -- 'Q2/2026'
  period          okr_period NOT NULL DEFAULT 'quarterly',

  starts_at       DATE NOT NULL,
  ends_at         DATE NOT NULL,

  active          BOOLEAN NOT NULL DEFAULT TRUE,
  closed_at       TIMESTAMPTZ,

  created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (tenant_id, name)
);

CREATE TABLE IF NOT EXISTS okr_objectives (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id       UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  cycle_id        UUID NOT NULL REFERENCES okr_cycles(id),

  scope           okr_scope NOT NULL,                  -- personal | team | company

  title           TEXT NOT NULL,
  context         TEXT,                                -- por que esse objetivo

  -- Owner
  owner_user_id   UUID NOT NULL REFERENCES app_users(id),

  -- Cascateamento (objetivo derivado de outro)
  parent_objective_id UUID REFERENCES okr_objectives(id),

  -- Aprovador (lider direto, p.ex.)
  approved_by     UUID REFERENCES app_users(id),
  approved_at     TIMESTAMPTZ,

  -- Score consolidado (media dos KRs · atualizado via trigger)
  score           NUMERIC(3,2),                        -- 0.00-1.00
  status          kr_status,                           -- derivado: done/on_track/at_risk/behind

  display_order   INT NOT NULL DEFAULT 0,
  active          BOOLEAN NOT NULL DEFAULT TRUE,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_objectives_owner_cycle
  ON okr_objectives(owner_user_id, cycle_id);

CREATE TABLE IF NOT EXISTS okr_key_results (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  objective_id    UUID NOT NULL REFERENCES okr_objectives(id) ON DELETE CASCADE,
  tenant_id       UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,

  display_order   INT NOT NULL DEFAULT 0,
  title           TEXT NOT NULL,

  -- Metricas (3 modos: numerica, percentual, boolean)
  metric_kind     VARCHAR(20) NOT NULL DEFAULT 'numeric', -- 'numeric' | 'percent' | 'boolean'
  start_value     NUMERIC(15,2) NOT NULL DEFAULT 0,
  target_value    NUMERIC(15,2) NOT NULL,
  current_value   NUMERIC(15,2) NOT NULL DEFAULT 0,
  unit            VARCHAR(20),                         -- 'cases', 'horas', 'R$', etc.

  -- Score = (current - start) / (target - start), clamped 0-1
  score           NUMERIC(3,2) GENERATED ALWAYS AS (
    CASE
      WHEN target_value = start_value THEN 0
      ELSE LEAST(1, GREATEST(0, (current_value - start_value) / (target_value - start_value)))
    END
  ) STORED,

  status          kr_status NOT NULL DEFAULT 'on_track',
  due_date        DATE,

  created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS okr_checkins (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id       UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,

  user_id         UUID NOT NULL REFERENCES app_users(id),
  cycle_id        UUID NOT NULL REFERENCES okr_cycles(id),

  -- Check-in semanal
  iso_year        INT NOT NULL,
  iso_week        INT NOT NULL,                        -- 1-53

  confidence      INT NOT NULL,                        -- 1-5
  comment         TEXT,

  -- Snapshot dos KRs no momento do check-in (JSONB)
  kr_snapshots    JSONB NOT NULL DEFAULT '[]'::jsonb,

  created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),

  CONSTRAINT checkin_conf_range CHECK (confidence BETWEEN 1 AND 5),
  UNIQUE (user_id, cycle_id, iso_year, iso_week)
);


-- =============================================================================
-- MODULO 8 · CARGOS & SALARIOS (matriz estruturada)
-- =============================================================================
-- Estende a tabela job_roles do spec M1 (estrutura organizacional)
-- com bandas salariais por nivel.

CREATE TABLE IF NOT EXISTS salary_bands (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id       UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,

  -- Identificacao (cargo + nivel)
  job_role_id     UUID NOT NULL,                       -- FK job_roles (criada em M1)
  level           job_level NOT NULL,

  -- Banda
  min_value       NUMERIC(12,2) NOT NULL,              -- piso
  mid_value       NUMERIC(12,2),                       -- meio · opcional
  max_value       NUMERIC(12,2) NOT NULL,              -- teto

  -- Politica
  notes           TEXT,                                -- ex: 'requer 3+ anos exp'
  effective_from  DATE NOT NULL,
  effective_to    DATE,

  -- Auditoria
  approved_by     UUID REFERENCES app_users(id),
  approved_at     TIMESTAMPTZ,

  created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),

  UNIQUE (tenant_id, job_role_id, level, effective_from),
  CONSTRAINT band_value_order CHECK (
    min_value <= COALESCE(mid_value, min_value) AND COALESCE(mid_value, max_value) <= max_value
  )
);

CREATE INDEX IF NOT EXISTS idx_bands_role
  ON salary_bands(tenant_id, job_role_id, effective_from DESC);

-- Detector de gap (colaboradores pagos abaixo do piso da banda)
CREATE OR REPLACE VIEW v_salary_gaps AS
SELECT
  au.tenant_id,
  au.id AS employee_id,
  au.full_name,
  au.job_role_id,
  au.job_title,
  au.salary,
  sb.level,
  sb.min_value AS band_min,
  sb.max_value AS band_max,
  (sb.min_value - au.salary) AS gap_to_min,
  CASE
    WHEN au.salary < sb.min_value THEN 'below_min'
    WHEN au.salary > sb.max_value THEN 'above_max'
    ELSE 'in_band'
  END AS gap_status
FROM app_users au
JOIN salary_bands sb ON sb.tenant_id = au.tenant_id
                     AND sb.job_role_id = au.job_role_id
                     AND (sb.effective_to IS NULL OR sb.effective_to > CURRENT_DATE)
                     AND sb.effective_from <= CURRENT_DATE
WHERE au.active = TRUE
  AND au.salary IS NOT NULL;


-- =============================================================================
-- GRANTS · todas as tabelas para authenticated (RLS faz o filtro real)
-- =============================================================================

DO $$
DECLARE t TEXT;
BEGIN
  FOR t IN VALUES
    ('notifications'), ('notification_preferences'),
    ('communicates'), ('communicate_views'), ('communicate_reactions'),
    ('jobs'), ('job_applications'), ('job_indications'),
    ('training_trails'), ('training_modules'), ('training_enrollments'),
    ('pulse_surveys'), ('pulse_responses'),
    ('enps_surveys'), ('enps_responses'),
    ('okr_cycles'), ('okr_objectives'), ('okr_key_results'), ('okr_checkins'),
    ('salary_bands')
  LOOP
    EXECUTE format('GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE %I TO authenticated', t);
    EXECUTE format('ALTER TABLE %I ENABLE ROW LEVEL SECURITY', t);
  END LOOP;
END $$;


-- =============================================================================
-- NOTAS SOBRE RLS (a implementar em migration separada)
-- =============================================================================
-- notifications        · recipient_id = current_user_id() (cada um ve suas)
-- communicates         · tenant + visibility check (all/role/unit/custom)
-- jobs                 · tenant + status='open' (todos veem)
-- job_indications      · referrer_id = current_user_id() OR rh role
-- training_*           · tenant scope · user_id = self ou rh/lider
-- pulse_responses      · INSERT permitido pra qualquer authenticated · SELECT NUNCA pra ninguem (apenas via views agregadas)
-- enps_responses       · idem pulse (privacy enforced)
-- okr_*                · objective.owner_user_id = self OR scope='company' OR scope='team' AND lider/membro
-- salary_bands         · SELECT rh/diretoria · INSERT/UPDATE diretoria
-- v_salary_gaps        · rh/diretoria apenas
-- =============================================================================

-- =============================================================================
-- R2 People · Schema v10 · módulos restantes consolidados
-- =============================================================================
-- Cobre os módulos especificados nos spec_m2, spec_m10 e spec_d2_d3
-- (movimentações, auth enterprise, audit avançado, settings, history views).
--
-- Pré-requisitos: schemas v1 a v9 aplicados
--
-- Cobre 4 grandes áreas:
--   1. Movements      · workflow promoção/transferência/afastamento (spec_m2)
--   2. Auth enterprise · SSO, MFA, convites, login audit (spec_d2_d3)
--   3. Settings       · tenant configurações + webhooks + api keys (spec_m10)
--   4. History views  · audit pra histórico de consulta (spec_m11)
-- =============================================================================

-- =============================================================================
-- ENUMS
-- =============================================================================

DO $$ BEGIN CREATE TYPE movement_kind AS ENUM (
  'promotion', 'salary_adjustment', 'salary_adjustment_collective_bargain',
  'transfer_unit', 'transfer_department', 'transfer_manager', 'role_change',
  'admission', 'termination',
  'leave_medical', 'leave_maternity', 'leave_paternity', 'leave_other'
); EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN CREATE TYPE movement_status AS ENUM (
  'draft', 'pending_rh', 'approved', 'effective', 'rejected', 'canceled'
); EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN CREATE TYPE login_event_kind AS ENUM (
  'login_success', 'login_failure', 'logout',
  'mfa_required', 'mfa_success', 'mfa_failure',
  'password_reset_request', 'password_reset_complete',
  'sso_redirect', 'sso_callback', 'session_revoked'
); EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN CREATE TYPE sso_provider_kind AS ENUM ('saml', 'oidc'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE auth_mode AS ENUM ('magic_link', 'sso_only', 'sso_with_fallback'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;


-- =============================================================================
-- AREA 1 · MOVEMENTS (spec_m2)
-- =============================================================================

CREATE TABLE IF NOT EXISTS movements (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id       UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,

  protocol        VARCHAR(40) NOT NULL,                -- 'MOV-2026-0517-AB12C'

  employee_id     UUID NOT NULL REFERENCES app_users(id),
  kind            movement_kind NOT NULL,
  status          movement_status NOT NULL DEFAULT 'draft',

  -- Snapshot do estado anterior (preenchido ao criar · imutavel)
  before_data     JSONB NOT NULL,
  -- Estado proposto
  after_data      JSONB NOT NULL,

  -- Datas
  effective_date  DATE,
  notice_days     INT,

  -- Workflow
  requested_by    UUID NOT NULL REFERENCES app_users(id),
  requested_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
  approved_by     UUID REFERENCES app_users(id),
  approved_at     TIMESTAMPTZ,
  rejected_reason TEXT,

  justification   TEXT NOT NULL,
  rh_notes        TEXT,

  -- Vinculacao com origem (atestado, dissidio, etc.)
  source_kind     VARCHAR(40),                         -- 'medical_certificate' | 'collective_bargain' | 'manual'
  source_id       UUID,                                -- FK logica

  created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT now(),

  UNIQUE (tenant_id, protocol)
);

CREATE INDEX IF NOT EXISTS idx_mov_tenant_employee
  ON movements(tenant_id, employee_id, requested_at DESC);
CREATE INDEX IF NOT EXISTS idx_mov_status
  ON movements(tenant_id, status) WHERE status IN ('draft', 'pending_rh');
CREATE INDEX IF NOT EXISTS idx_mov_requester
  ON movements(requested_by);

-- Trigger de protocolo automatico
CREATE OR REPLACE FUNCTION mov_generate_protocol() RETURNS TRIGGER LANGUAGE plpgsql AS $$
DECLARE v_suffix TEXT;
BEGIN
  IF NEW.protocol IS NULL OR NEW.protocol = '' THEN
    v_suffix := upper(substr(encode(gen_random_bytes(3), 'hex'), 1, 5));
    NEW.protocol := 'MOV-' || to_char(now(), 'YYYY-MM-DD') || '-' || v_suffix;
  END IF;
  RETURN NEW;
END; $$;

DROP TRIGGER IF EXISTS trg_mov_protocol ON movements;
CREATE TRIGGER trg_mov_protocol BEFORE INSERT ON movements
  FOR EACH ROW EXECUTE FUNCTION mov_generate_protocol();

-- FK atrasada para vincular ao atestado quando M3 estiver aplicado
DO $$ BEGIN
  ALTER TABLE medical_certificates
    ADD CONSTRAINT fk_mc_movement
    FOREIGN KEY (auto_movement_id) REFERENCES movements(id) DEFERRABLE;
EXCEPTION WHEN duplicate_object THEN NULL; END $$;


-- =============================================================================
-- AREA 2 · AUTH ENTERPRISE (spec_d2_d3)
-- =============================================================================

-- SSO Providers
CREATE TABLE IF NOT EXISTS sso_providers (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id       UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,

  provider_kind   sso_provider_kind NOT NULL,
  display_name    VARCHAR(120) NOT NULL,

  supabase_provider_id VARCHAR(120) NOT NULL,

  email_domains   TEXT[] NOT NULL,
  metadata_url    TEXT,
  saml_metadata_xml TEXT,

  attribute_mapping JSONB NOT NULL DEFAULT '{}'::jsonb,

  auto_provision  BOOLEAN NOT NULL DEFAULT TRUE,
  default_role    app_user_role NOT NULL DEFAULT 'colaborador',

  active          BOOLEAN NOT NULL DEFAULT TRUE,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_sso_providers_tenant
  ON sso_providers(tenant_id) WHERE active = TRUE;
CREATE INDEX IF NOT EXISTS idx_sso_providers_domain
  ON sso_providers USING gin(email_domains);

-- MFA factors
CREATE TABLE IF NOT EXISTS user_mfa_factors (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id         UUID NOT NULL REFERENCES app_users(id) ON DELETE CASCADE,

  factor_kind     VARCHAR(20) NOT NULL,                -- 'totp' | 'webauthn'
  friendly_name   VARCHAR(80) NOT NULL,
  supabase_factor_id VARCHAR(120) NOT NULL,

  enrolled_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
  last_used_at    TIMESTAMPTZ,
  active          BOOLEAN NOT NULL DEFAULT TRUE,

  UNIQUE (user_id, friendly_name)
);

CREATE INDEX IF NOT EXISTS idx_mfa_user_active
  ON user_mfa_factors(user_id, active);

-- MFA recovery codes (bcrypt hash · 10 por user · 1-time use)
CREATE TABLE IF NOT EXISTS mfa_recovery_codes (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id         UUID NOT NULL REFERENCES app_users(id) ON DELETE CASCADE,
  code_hash       VARCHAR(120) NOT NULL,
  used_at         TIMESTAMPTZ,
  used_ip         INET,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_recovery_unused
  ON mfa_recovery_codes(user_id) WHERE used_at IS NULL;

-- Convites por email
CREATE TABLE IF NOT EXISTS tenant_invitations (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id       UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,

  email           VARCHAR(180) NOT NULL,
  invited_role    app_user_role NOT NULL DEFAULT 'colaborador',
  invited_by      UUID NOT NULL REFERENCES app_users(id),

  preset_data     JSONB,

  token           VARCHAR(64) NOT NULL UNIQUE,
  expires_at      TIMESTAMPTZ NOT NULL,

  accepted_at     TIMESTAMPTZ,
  accepted_by_user_id UUID REFERENCES app_users(id),
  revoked_at      TIMESTAMPTZ,
  revoked_by      UUID REFERENCES app_users(id),

  created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_invites_active
  ON tenant_invitations(tenant_id, email)
  WHERE accepted_at IS NULL AND revoked_at IS NULL AND expires_at > now();

-- Login audit
CREATE TABLE IF NOT EXISTS login_audit (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id       UUID,

  user_id         UUID REFERENCES app_users(id),
  email_attempted VARCHAR(180),

  event_kind      login_event_kind NOT NULL,
  failure_reason  VARCHAR(120),

  ip_address      INET,
  user_agent      TEXT,
  country         VARCHAR(2),

  session_id      UUID,
  auth_method     VARCHAR(20),
  mfa_used        BOOLEAN NOT NULL DEFAULT FALSE,

  created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_login_audit_user
  ON login_audit(user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_login_audit_tenant
  ON login_audit(tenant_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_login_audit_failures
  ON login_audit(email_attempted, created_at DESC)
  WHERE event_kind = 'login_failure';

-- Session revocations
CREATE TABLE IF NOT EXISTS session_revocations (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id         UUID NOT NULL REFERENCES app_users(id) ON DELETE CASCADE,

  reason          VARCHAR(60) NOT NULL,
  -- 'termination' | 'password_change' | 'mfa_change' | 'security_event' | 'admin_force'

  revoked_by      UUID REFERENCES app_users(id),
  revoked_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_session_rev_user
  ON session_revocations(user_id, revoked_at DESC);

-- Funcao: rate limit checker
CREATE OR REPLACE FUNCTION check_login_rate_limit(
  p_email VARCHAR,
  p_ip INET
) RETURNS BOOLEAN LANGUAGE plpgsql AS $$
DECLARE v_failures_recent INT;
BEGIN
  SELECT COUNT(*) INTO v_failures_recent
    FROM login_audit
    WHERE (email_attempted = p_email OR ip_address = p_ip)
      AND event_kind = 'login_failure'
      AND created_at > now() - INTERVAL '15 minutes';

  IF v_failures_recent >= 5 THEN
    INSERT INTO login_audit (email_attempted, ip_address, event_kind, failure_reason)
      VALUES (p_email, p_ip, 'login_failure', 'rate_limited');
    RETURN FALSE;
  END IF;

  RETURN TRUE;
END; $$;


-- =============================================================================
-- AREA 3 · SETTINGS (spec_m10)
-- =============================================================================

-- ALTER em tenants pra configuracoes operacionais
DO $$ BEGIN
  ALTER TABLE tenants
    ADD COLUMN IF NOT EXISTS settings JSONB NOT NULL DEFAULT '{}'::jsonb,
    ADD COLUMN IF NOT EXISTS branding_updated_at TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS settings_updated_by UUID REFERENCES app_users(id);
EXCEPTION WHEN duplicate_column THEN NULL; END $$;

-- Webhooks
CREATE TABLE IF NOT EXISTS tenant_webhooks (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id       UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,

  name            VARCHAR(120) NOT NULL,
  url             TEXT NOT NULL,
  secret          VARCHAR(120) NOT NULL,

  events          TEXT[] NOT NULL,

  active          BOOLEAN NOT NULL DEFAULT TRUE,
  last_success_at TIMESTAMPTZ,
  last_failure_at TIMESTAMPTZ,
  failure_count   INT NOT NULL DEFAULT 0,
  disabled_reason TEXT,

  created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT now(),

  UNIQUE (tenant_id, name)
);

-- API keys
CREATE TABLE IF NOT EXISTS tenant_api_keys (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id       UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,

  name            VARCHAR(120) NOT NULL,
  key_prefix      VARCHAR(20) NOT NULL,
  key_hash        VARCHAR(120) NOT NULL,

  scopes          TEXT[] NOT NULL,
  rate_limit_per_minute INT NOT NULL DEFAULT 60,

  last_used_at    TIMESTAMPTZ,
  expires_at      TIMESTAMPTZ,
  revoked_at      TIMESTAMPTZ,
  revoked_by      UUID REFERENCES app_users(id),

  created_by      UUID NOT NULL REFERENCES app_users(id),
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),

  UNIQUE (tenant_id, name)
);

CREATE INDEX IF NOT EXISTS idx_api_keys_active
  ON tenant_api_keys(tenant_id) WHERE revoked_at IS NULL;

-- Histórico de mudanças em settings
CREATE TABLE IF NOT EXISTS settings_history (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id       UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,

  changed_by      UUID NOT NULL REFERENCES app_users(id),
  section         VARCHAR(40) NOT NULL,

  before_data     JSONB,
  after_data      JSONB,

  ip_address      INET,
  changed_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_settings_history_tenant
  ON settings_history(tenant_id, changed_at DESC);


-- =============================================================================
-- AREA 4 · HISTORY VIEWS (spec_m11)
-- =============================================================================

CREATE TABLE IF NOT EXISTS history_views (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id       UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,

  viewer_id       UUID NOT NULL REFERENCES app_users(id),
  target_id       UUID NOT NULL REFERENCES app_users(id),

  categories      TEXT[],
  year_from       INT,
  year_to         INT,

  ip_address      INET,
  user_agent      TEXT,

  viewed_at       TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_history_views_viewer
  ON history_views(viewer_id, viewed_at DESC);
CREATE INDEX IF NOT EXISTS idx_history_views_target
  ON history_views(target_id, viewed_at DESC);

-- Cards de "Vistos recentemente" na tela de busca
CREATE TABLE IF NOT EXISTS recent_employee_views (
  user_id         UUID NOT NULL REFERENCES app_users(id) ON DELETE CASCADE,
  subject_id      UUID NOT NULL REFERENCES app_users(id) ON DELETE CASCADE,
  viewed_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, subject_id)
);

CREATE INDEX IF NOT EXISTS idx_recent_views_user
  ON recent_employee_views(user_id, viewed_at DESC);


-- =============================================================================
-- TRIGGERS · INTEGRACOES
-- =============================================================================

-- Trigger: força logout de todas as sessões pós-termination
CREATE OR REPLACE FUNCTION revoke_user_sessions_on_termination() RETURNS TRIGGER AS $$
BEGIN
  -- Registra revogação (Supabase Admin API delete sessions é feito no app code)
  INSERT INTO session_revocations (user_id, reason)
    VALUES (NEW.id, 'termination');
  RETURN NEW;
END; $$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_terminate_revoke_sessions ON app_users;
CREATE TRIGGER trg_terminate_revoke_sessions
  AFTER UPDATE OF terminated_at, active ON app_users
  FOR EACH ROW
  WHEN (OLD.active = TRUE AND NEW.active = FALSE)
  EXECUTE FUNCTION revoke_user_sessions_on_termination();

-- Trigger: limita recent_employee_views a 20 por user (deleta excedentes)
CREATE OR REPLACE FUNCTION trim_recent_views() RETURNS TRIGGER AS $$
BEGIN
  DELETE FROM recent_employee_views
    WHERE user_id = NEW.user_id
      AND viewed_at < (
        SELECT viewed_at FROM recent_employee_views
          WHERE user_id = NEW.user_id
          ORDER BY viewed_at DESC
          OFFSET 20 LIMIT 1
      );
  RETURN NEW;
END; $$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_trim_recent_views ON recent_employee_views;
CREATE TRIGGER trg_trim_recent_views
  AFTER INSERT ON recent_employee_views
  FOR EACH ROW EXECUTE FUNCTION trim_recent_views();


-- =============================================================================
-- GRANTS + RLS HABILITADO
-- =============================================================================

DO $$
DECLARE t TEXT;
BEGIN
  FOR t IN VALUES
    ('movements'),
    ('sso_providers'), ('user_mfa_factors'), ('mfa_recovery_codes'),
    ('tenant_invitations'), ('login_audit'), ('session_revocations'),
    ('tenant_webhooks'), ('tenant_api_keys'), ('settings_history'),
    ('history_views'), ('recent_employee_views')
  LOOP
    EXECUTE format('GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE %I TO authenticated', t);
    EXECUTE format('ALTER TABLE %I ENABLE ROW LEVEL SECURITY', t);
  END LOOP;
END $$;


-- =============================================================================
-- NOTAS SOBRE RLS (a implementar em migration separada)
-- =============================================================================
-- movements             · employee/manager/rh por escopo
-- sso_providers         · diretoria do tenant
-- user_mfa_factors      · self apenas
-- mfa_recovery_codes    · self apenas · INSERT/UPDATE só do system
-- tenant_invitations    · rh/diretoria do tenant
-- login_audit           · self (próprios eventos) + dpo (todos do tenant)
-- session_revocations   · self (própria) + admin
-- tenant_webhooks       · diretoria com manage_tenant_settings
-- tenant_api_keys       · diretoria (key_hash NUNCA retornado em SELECT)
-- settings_history      · rh/diretoria (audit)
-- history_views         · self (quem te viu) + dpo
-- recent_employee_views · self apenas
-- =============================================================================

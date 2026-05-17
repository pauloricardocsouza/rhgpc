-- ============================================================================
-- R2 People · Schema SQL v11 · Observability + Security + Compliance
-- ----------------------------------------------------------------------------
-- Materializa em SQL executável as specs D5 (observability), D6 (security)
-- e D7 (compliance LGPD playbook).
--
-- Inclui:
--   1. Observability (slo_violations, incidents, metric_snapshots)
--   2. Security (csp_violations, honeytoken_hits, security_events,
--               known_vulnerabilities)
--   3. Compliance LGPD (processing_activities, dsar_requests,
--               dsar_audit_trail, consents, retention_policies, retention_runs,
--               compliance_minutes, compliance_trainings)
--   4. RPCs principais (dsar_export skeleton, dsar_anonymize, rpc_emit_slo_alert)
--   5. RLS habilitada nas tabelas tenant-scoped, GRANTs apropriados
--   6. Triggers de revisão automática (ROPA next_review_at, DSAR deadlines)
--
-- Idempotente: cada CREATE usa IF NOT EXISTS, ENUMs criadas com guard,
-- triggers droppados antes de recriados.
--
-- Pré-requisitos: schema v10 já aplicado (tenants, auth.users, action_log).
-- ============================================================================

BEGIN;

-- ============================================================================
-- 1. OBSERVABILITY
-- ============================================================================

CREATE TABLE IF NOT EXISTS slo_violations (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  service         text NOT NULL,
  indicator       text NOT NULL,
  observed        numeric,
  target          numeric,
  budget_used_pct numeric,
  severity        text CHECK (severity IN ('warn','breach','exhaustion')) DEFAULT 'warn',
  detected_at     timestamptz NOT NULL DEFAULT now(),
  resolved_at     timestamptz,
  notes           text
);

CREATE INDEX IF NOT EXISTS idx_slo_violations_open
  ON slo_violations (detected_at DESC) WHERE resolved_at IS NULL;

CREATE TABLE IF NOT EXISTS incidents (
  id                       uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  title                    text NOT NULL,
  severity                 text NOT NULL CHECK (severity IN ('P1','P2','P3','P4')),
  started_at               timestamptz NOT NULL,
  detected_at              timestamptz NOT NULL,
  mitigated_at             timestamptz,
  resolved_at              timestamptz,
  affected_tenants         uuid[],
  affected_users_estimate  int,
  root_cause               text,
  contributing_factors     text[],
  postmortem_url           text,
  postmortem_published     boolean DEFAULT false,
  created_by               uuid REFERENCES auth.users(id),
  created_at               timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_incidents_open
  ON incidents (severity, started_at DESC) WHERE resolved_at IS NULL;

CREATE TABLE IF NOT EXISTS metric_snapshots (
  metric_name text NOT NULL,
  labels      jsonb NOT NULL DEFAULT '{}'::jsonb,
  value       numeric NOT NULL,
  taken_at    timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (metric_name, labels, taken_at)
);

CREATE INDEX IF NOT EXISTS idx_metric_snapshots_recent
  ON metric_snapshots (metric_name, taken_at DESC);

-- ============================================================================
-- 2. SECURITY
-- ============================================================================

CREATE TABLE IF NOT EXISTS csp_violations (
  id                 uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  document_uri       text,
  violated_directive text,
  blocked_uri        text,
  source_file        text,
  line_number        int,
  user_agent         text,
  user_id            uuid REFERENCES auth.users(id),
  tenant_id          uuid REFERENCES tenants(id),
  reported_at        timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_csp_recent ON csp_violations (reported_at DESC);
CREATE INDEX IF NOT EXISTS idx_csp_directive ON csp_violations (violated_directive, reported_at DESC);

CREATE TABLE IF NOT EXISTS honeytoken_hits (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  token_id    text NOT NULL,
  remote_ip   inet,
  user_agent  text,
  context     jsonb,
  hit_at      timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_honeytoken_recent ON honeytoken_hits (hit_at DESC);

CREATE TABLE IF NOT EXISTS security_events (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id    uuid NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  actor_id     uuid REFERENCES auth.users(id),
  target_id    uuid REFERENCES auth.users(id),
  event_type   text NOT NULL,
  before_data  jsonb,
  after_data   jsonb,
  reason       text,
  occurred_at  timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_security_events_tenant
  ON security_events (tenant_id, occurred_at DESC);

CREATE TABLE IF NOT EXISTS known_vulnerabilities (
  cve            text PRIMARY KEY,
  package_name   text NOT NULL,
  affected_range text NOT NULL,
  fixed_in       text,
  severity       text CHECK (severity IN ('low','medium','high','critical')),
  exploitable    boolean,
  in_use         boolean,
  status         text CHECK (status IN ('open','fixed','accepted','wont_fix')) DEFAULT 'open',
  detected_at    timestamptz NOT NULL DEFAULT now(),
  fixed_at       timestamptz,
  notes          text
);

CREATE INDEX IF NOT EXISTS idx_vuln_open ON known_vulnerabilities (severity, status) WHERE status = 'open';

-- ============================================================================
-- 3. COMPLIANCE LGPD
-- ============================================================================

-- 3.1 ENUMs

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'dsar_type') THEN
    CREATE TYPE dsar_type AS ENUM (
      'confirm','access','correct','anonymize','erase','portability',
      'recipients_info','consent_revoke','opposition'
    );
  END IF;
END $$;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'dsar_status') THEN
    CREATE TYPE dsar_status AS ENUM (
      'submitted','identity_pending','triage','in_progress',
      'completed','rejected','partial','expired'
    );
  END IF;
END $$;

-- 3.2 ROPA

CREATE TABLE IF NOT EXISTS processing_activities (
  id                     uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id              uuid REFERENCES tenants(id) ON DELETE CASCADE,
  name                   text NOT NULL,
  purpose                text NOT NULL,
  legal_basis            text NOT NULL,
  legal_basis_article    text,
  data_subjects          text[] NOT NULL,
  data_categories        text[] NOT NULL,
  sensitive_data         boolean NOT NULL DEFAULT false,
  recipients             text[],
  international_transfer boolean DEFAULT false,
  international_country  text,
  retention_policy       text NOT NULL,
  security_measures      text[],
  responsible_role       text,
  responsible_user_id    uuid REFERENCES auth.users(id),
  risk_assessment        text CHECK (risk_assessment IN ('low','medium','high','critical')) DEFAULT 'low',
  dpia_required          boolean DEFAULT false,
  dpia_doc_url           text,
  status                 text CHECK (status IN ('draft','active','suspended','retired')) DEFAULT 'draft',
  created_at             timestamptz NOT NULL DEFAULT now(),
  last_reviewed_at       timestamptz,
  next_review_at         timestamptz,
  reviewed_by            uuid REFERENCES auth.users(id)
);

CREATE INDEX IF NOT EXISTS idx_ropa_review_due
  ON processing_activities (next_review_at)
  WHERE status = 'active';

CREATE INDEX IF NOT EXISTS idx_ropa_tenant
  ON processing_activities (tenant_id, status);

-- 3.3 DSAR

CREATE TABLE IF NOT EXISTS dsar_requests (
  id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id           uuid REFERENCES tenants(id) ON DELETE SET NULL,
  subject_user_id     uuid REFERENCES auth.users(id),
  subject_email       text NOT NULL,
  subject_cpf_hash    text,
  type                dsar_type NOT NULL,
  status              dsar_status NOT NULL DEFAULT 'submitted',
  description         text,
  scope_details       jsonb,
  identity_proof_url  text,
  triaged_by          uuid REFERENCES auth.users(id),
  triaged_at          timestamptz,
  assigned_to         uuid REFERENCES auth.users(id),
  legal_deadline_at   timestamptz NOT NULL,
  target_deadline_at  timestamptz NOT NULL,
  response_url        text,
  response_summary    text,
  rejection_reason    text,
  hard_delete_at      timestamptz,
  created_at          timestamptz NOT NULL DEFAULT now(),
  completed_at        timestamptz,
  expires_at          timestamptz
);

CREATE INDEX IF NOT EXISTS idx_dsar_open
  ON dsar_requests (legal_deadline_at)
  WHERE status NOT IN ('completed','rejected','expired');

CREATE INDEX IF NOT EXISTS idx_dsar_subject_email
  ON dsar_requests (subject_email);

CREATE INDEX IF NOT EXISTS idx_dsar_tenant
  ON dsar_requests (tenant_id, status, created_at DESC);

CREATE TABLE IF NOT EXISTS dsar_audit_trail (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  dsar_id      uuid NOT NULL REFERENCES dsar_requests(id) ON DELETE CASCADE,
  actor_id     uuid REFERENCES auth.users(id),
  action       text NOT NULL,
  details      jsonb,
  occurred_at  timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_dsar_audit_dsar ON dsar_audit_trail (dsar_id, occurred_at DESC);

-- 3.4 Consents

CREATE TABLE IF NOT EXISTS consents (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id         uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  tenant_id       uuid REFERENCES tenants(id) ON DELETE CASCADE,
  purpose_code    text NOT NULL,
  granted         boolean NOT NULL,
  granted_at      timestamptz NOT NULL DEFAULT now(),
  revoked_at      timestamptz,
  expires_at      timestamptz,
  evidence_ip     inet,
  evidence_ua     text,
  evidence_method text,
  policy_version  text NOT NULL,
  notes           text
);

CREATE INDEX IF NOT EXISTS idx_consents_user ON consents (user_id, purpose_code, granted_at DESC);
CREATE INDEX IF NOT EXISTS idx_consents_active
  ON consents (user_id, purpose_code)
  WHERE granted = true AND revoked_at IS NULL;

-- 3.5 Retenção

CREATE TABLE IF NOT EXISTS retention_policies (
  id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  data_category       text NOT NULL UNIQUE,
  retention_hot       interval NOT NULL,
  retention_cold      interval NOT NULL,
  hard_delete_after   interval,
  legal_basis         text NOT NULL,
  applies_to_tables   text[] NOT NULL,
  reviewed_at         timestamptz,
  active              boolean DEFAULT true,
  created_at          timestamptz DEFAULT now()
);

CREATE TABLE IF NOT EXISTS retention_runs (
  id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  ran_at              timestamptz DEFAULT now(),
  policy_id           uuid REFERENCES retention_policies(id) ON DELETE SET NULL,
  rows_moved_to_cold  int DEFAULT 0,
  rows_hard_deleted   int DEFAULT 0,
  errors_count        int DEFAULT 0,
  notes               text
);

CREATE INDEX IF NOT EXISTS idx_retention_runs_recent ON retention_runs (ran_at DESC);

-- 3.6 Governança

CREATE TABLE IF NOT EXISTS compliance_minutes (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  meeting_type  text NOT NULL CHECK (meeting_type IN ('committee_monthly','dpo_cto_biweekly','tenant_review','adhoc')),
  meeting_date  date NOT NULL,
  attendees     text[],
  agenda        text,
  decisions     text,
  action_items  jsonb DEFAULT '[]'::jsonb,
  next_meeting  date,
  doc_url       text,
  created_by    uuid REFERENCES auth.users(id),
  created_at    timestamptz DEFAULT now()
);

CREATE TABLE IF NOT EXISTS compliance_trainings (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id         uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  audience        text NOT NULL,
  course_code     text NOT NULL,
  course_version  text NOT NULL,
  completed_at    timestamptz,
  score           numeric,
  expires_at      timestamptz NOT NULL,
  evidence_url    text,
  created_at      timestamptz DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_trainings_due
  ON compliance_trainings (user_id, expires_at)
  WHERE completed_at IS NOT NULL;

-- ============================================================================
-- 4. RLS POLICIES
-- ============================================================================
-- Tabelas tenant-scoped recebem RLS automática. Tabelas globais (incidents,
-- known_vulnerabilities, honeytoken_hits) ficam restritas a super_admin via
-- GRANT/REVOKE no nível de role.

DO $$
DECLARE
  t text;
  tenant_tables text[] := ARRAY[
    'processing_activities','dsar_requests','dsar_audit_trail',
    'consents','compliance_minutes','compliance_trainings',
    'csp_violations','security_events'
  ];
BEGIN
  FOREACH t IN ARRAY tenant_tables LOOP
    EXECUTE format('ALTER TABLE %I ENABLE ROW LEVEL SECURITY', t);
    -- Policy padrão: usuário só vê linhas do seu tenant.
    -- Cada tabela pode ter policies adicionais (ex: super_admin vê tudo).
    EXECUTE format('
      DROP POLICY IF EXISTS %I_tenant_isolation ON %I;
      CREATE POLICY %I_tenant_isolation ON %I
        FOR ALL
        USING (
          tenant_id IS NULL
          OR tenant_id = (current_setting(''app.tenant_id'', true))::uuid
        );', t, t, t, t);
  END LOOP;
END $$;

-- DSAR audit trail herda via dsar_requests
ALTER TABLE dsar_audit_trail ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS dsar_audit_via_request ON dsar_audit_trail;
CREATE POLICY dsar_audit_via_request ON dsar_audit_trail
  FOR ALL
  USING (
    dsar_id IN (
      SELECT id FROM dsar_requests
      WHERE tenant_id IS NULL
         OR tenant_id = (current_setting('app.tenant_id', true))::uuid
    )
  );

-- ============================================================================
-- 5. TRIGGERS
-- ============================================================================

-- 5.1 ROPA: agendar próxima revisão 12 meses após cada atualização
CREATE OR REPLACE FUNCTION trg_ropa_schedule_review()
RETURNS TRIGGER AS $$
BEGIN
  IF NEW.last_reviewed_at IS NOT NULL
     AND (OLD.last_reviewed_at IS DISTINCT FROM NEW.last_reviewed_at) THEN
    NEW.next_review_at := NEW.last_reviewed_at + interval '12 months';
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_ropa_review ON processing_activities;
CREATE TRIGGER trg_ropa_review
  BEFORE INSERT OR UPDATE ON processing_activities
  FOR EACH ROW EXECUTE FUNCTION trg_ropa_schedule_review();

-- 5.2 DSAR: calcular deadlines automaticamente na criação
CREATE OR REPLACE FUNCTION trg_dsar_set_deadlines()
RETURNS TRIGGER AS $$
BEGIN
  IF NEW.legal_deadline_at IS NULL THEN
    NEW.legal_deadline_at := NEW.created_at + interval '15 days';
  END IF;
  IF NEW.target_deadline_at IS NULL THEN
    -- SLA interno por tipo
    NEW.target_deadline_at := NEW.created_at + CASE NEW.type
      WHEN 'confirm'         THEN interval '5 days'
      WHEN 'access'          THEN interval '7 days'
      WHEN 'portability'     THEN interval '7 days'
      WHEN 'recipients_info' THEN interval '7 days'
      WHEN 'correct'         THEN interval '5 days'
      WHEN 'anonymize'       THEN interval '10 days'
      WHEN 'erase'           THEN interval '10 days'
      WHEN 'opposition'      THEN interval '10 days'
      WHEN 'consent_revoke'  THEN interval '1 day'
    END;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_dsar_deadlines ON dsar_requests;
CREATE TRIGGER trg_dsar_deadlines
  BEFORE INSERT ON dsar_requests
  FOR EACH ROW EXECUTE FUNCTION trg_dsar_set_deadlines();

-- 5.3 DSAR audit trail automático em transição de status
CREATE OR REPLACE FUNCTION trg_dsar_audit_status_change()
RETURNS TRIGGER AS $$
BEGIN
  IF (TG_OP = 'INSERT') THEN
    INSERT INTO dsar_audit_trail (dsar_id, actor_id, action, details)
    VALUES (NEW.id, NEW.subject_user_id, 'submitted',
            jsonb_build_object('type', NEW.type::text, 'status', NEW.status::text));
  ELSIF (TG_OP = 'UPDATE' AND OLD.status IS DISTINCT FROM NEW.status) THEN
    INSERT INTO dsar_audit_trail (dsar_id, actor_id, action, details)
    VALUES (NEW.id, NEW.assigned_to, 'status_changed',
            jsonb_build_object('from', OLD.status::text, 'to', NEW.status::text));
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_dsar_audit ON dsar_requests;
CREATE TRIGGER trg_dsar_audit
  AFTER INSERT OR UPDATE ON dsar_requests
  FOR EACH ROW EXECUTE FUNCTION trg_dsar_audit_status_change();

-- 5.4 Consents: append-only (UPDATE não permitido em granted/revoked_at)
CREATE OR REPLACE FUNCTION trg_consents_append_only()
RETURNS TRIGGER AS $$
BEGIN
  -- Permite apenas update do revoked_at (revogação)
  IF (OLD.granted IS DISTINCT FROM NEW.granted)
     OR (OLD.granted_at IS DISTINCT FROM NEW.granted_at)
     OR (OLD.evidence_ip IS DISTINCT FROM NEW.evidence_ip)
     OR (OLD.policy_version IS DISTINCT FROM NEW.policy_version) THEN
    RAISE EXCEPTION 'Consents are append-only. Insert a new row instead of modifying %', OLD.id;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_consents_immutable ON consents;
CREATE TRIGGER trg_consents_immutable
  BEFORE UPDATE ON consents
  FOR EACH ROW EXECUTE FUNCTION trg_consents_append_only();

-- ============================================================================
-- 6. RPCs principais
-- ============================================================================

-- 6.1 Disparar alerta de SLO (chamada pelo job de avaliação)
CREATE OR REPLACE FUNCTION rpc_emit_slo_violation(
  p_service text,
  p_indicator text,
  p_observed numeric,
  p_target numeric,
  p_budget_used_pct numeric
) RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_id uuid;
  v_severity text;
BEGIN
  v_severity := CASE
    WHEN p_budget_used_pct >= 100 THEN 'exhaustion'
    WHEN p_budget_used_pct >= 50  THEN 'breach'
    ELSE 'warn'
  END;

  INSERT INTO slo_violations (service, indicator, observed, target, budget_used_pct, severity)
  VALUES (p_service, p_indicator, p_observed, p_target, p_budget_used_pct, v_severity)
  RETURNING id INTO v_id;

  RETURN v_id;
END;
$$;

-- 6.2 Criar DSAR (chamada pelo app/portal público)
CREATE OR REPLACE FUNCTION rpc_dsar_create(
  p_tenant_id uuid,
  p_subject_email text,
  p_type dsar_type,
  p_description text DEFAULT NULL,
  p_scope_details jsonb DEFAULT NULL
) RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_id uuid;
  v_user uuid;
BEGIN
  -- Tenta linkar com auth.users via email
  SELECT id INTO v_user FROM auth.users WHERE email = p_subject_email LIMIT 1;

  INSERT INTO dsar_requests (
    tenant_id, subject_user_id, subject_email,
    type, description, scope_details, status
  ) VALUES (
    p_tenant_id, v_user, p_subject_email,
    p_type, p_description, p_scope_details,
    CASE WHEN v_user IS NULL THEN 'identity_pending'::dsar_status ELSE 'submitted'::dsar_status END
  ) RETURNING id INTO v_id;

  RETURN v_id;
END;
$$;

-- 6.3 Anonimizar dados (DSAR erase) — soft delete + agenda hard delete 30d
CREATE OR REPLACE FUNCTION rpc_dsar_anonymize(p_dsar_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user uuid;
BEGIN
  SELECT subject_user_id INTO v_user FROM dsar_requests WHERE id = p_dsar_id;
  IF v_user IS NULL THEN
    RAISE EXCEPTION 'DSAR % has no linked subject user', p_dsar_id;
  END IF;

  -- Soft delete em employees (mantém vínculos por compliance fiscal)
  -- Substitui PII por placeholders, mantém estrutura.
  UPDATE employees SET
    full_name   = '[ANONIMIZADO]',
    cpf         = NULL,
    rg          = NULL,
    email       = NULL,
    phone       = NULL,
    address     = NULL,
    photo_url   = NULL,
    deleted_at  = now()
  WHERE user_id = v_user;

  UPDATE dsar_requests SET
    status = 'completed',
    completed_at = now(),
    hard_delete_at = now() + interval '30 days',
    response_summary = 'Dados anonimizados. Hard delete agendado para 30 dias.'
  WHERE id = p_dsar_id;
END;
$$;

-- 6.4 Reverter DSAR-erase dentro da janela de grace (30d)
CREATE OR REPLACE FUNCTION rpc_dsar_revert(p_dsar_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_dsar dsar_requests;
BEGIN
  SELECT * INTO v_dsar FROM dsar_requests WHERE id = p_dsar_id;
  IF v_dsar.hard_delete_at IS NULL OR v_dsar.hard_delete_at < now() THEN
    RAISE EXCEPTION 'DSAR % cannot be reverted (no grace period or already hard-deleted)', p_dsar_id;
  END IF;

  UPDATE dsar_requests SET
    status = 'rejected',
    rejection_reason = 'Reverted by subject within grace period',
    hard_delete_at = NULL
  WHERE id = p_dsar_id;
END;
$$;

-- 6.5 Snapshot de métricas (job recorrente)
CREATE OR REPLACE FUNCTION rpc_metrics_snapshot()
RETURNS int
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_count int := 0;
BEGIN
  -- Tenants ativos
  INSERT INTO metric_snapshots (metric_name, labels, value)
  SELECT 'r2_tenants_active', '{}'::jsonb, COUNT(*)::numeric
  FROM tenants WHERE active = true;
  v_count := v_count + 1;

  -- DSARs em aberto
  INSERT INTO metric_snapshots (metric_name, labels, value)
  SELECT 'r2_dsar_open', '{}'::jsonb, COUNT(*)::numeric
  FROM dsar_requests
  WHERE status NOT IN ('completed','rejected','expired');
  v_count := v_count + 1;

  -- DSARs em atraso
  INSERT INTO metric_snapshots (metric_name, labels, value)
  SELECT 'r2_dsar_overdue', '{}'::jsonb, COUNT(*)::numeric
  FROM dsar_requests
  WHERE status NOT IN ('completed','rejected','expired')
    AND legal_deadline_at < now();
  v_count := v_count + 1;

  -- Incidentes abertos por severidade
  INSERT INTO metric_snapshots (metric_name, labels, value)
  SELECT 'r2_incidents_open', jsonb_build_object('severity', severity), COUNT(*)::numeric
  FROM incidents WHERE resolved_at IS NULL GROUP BY severity;
  GET DIAGNOSTICS v_count = ROW_COUNT;

  -- Vulnerabilidades open
  INSERT INTO metric_snapshots (metric_name, labels, value)
  SELECT 'r2_vulnerabilities_open', jsonb_build_object('severity', severity), COUNT(*)::numeric
  FROM known_vulnerabilities WHERE status = 'open' GROUP BY severity;

  RETURN v_count;
END;
$$;

-- ============================================================================
-- 7. SEED · políticas de retenção padrão
-- ============================================================================

INSERT INTO retention_policies (data_category, retention_hot, retention_cold, hard_delete_after, legal_basis, applies_to_tables)
VALUES
  ('medical_certificates',  interval '5 years',  interval '15 years', interval '20 years',
   'CLT art 6 + Lei 8.213', ARRAY['medical_certificates','medical_certificate_files']),
  ('payroll',               interval '5 years',  interval '25 years', NULL,
   'DL 5452 art 462 + IN RFB', ARRAY['payroll_runs','payroll_items']),
  ('personal_data_active',  interval '99 years', interval '5 years', NULL,
   'LGPD art 16 (mantém enquanto vínculo)', ARRAY['employees','users']),
  ('evaluations',           interval '5 years',  interval '0',        interval '5 years',
   'LGPD art 15 §3º', ARRAY['evaluations','evaluation_responses','pdi','one_on_ones']),
  ('login_audit',           interval '2 years',  interval '3 years',  NULL,
   'LGPD art 37', ARRAY['login_audit','action_log']),
  ('notifications',         interval '90 days',  interval '1 year',   interval '1 year',
   'sem obrigação legal', ARRAY['notifications'])
ON CONFLICT (data_category) DO NOTHING;

-- ============================================================================
-- 8. GRANTs
-- ============================================================================

-- Roles padrão Supabase: anon, authenticated, service_role
-- Aqui assumimos roles custom: app_user, app_dpo, app_super_admin

DO $$
DECLARE
  t text;
  read_only_tables text[] := ARRAY[
    'slo_violations','incidents','metric_snapshots',
    'csp_violations','honeytoken_hits','known_vulnerabilities'
  ];
  tenant_tables text[] := ARRAY[
    'processing_activities','dsar_requests','dsar_audit_trail',
    'consents','compliance_minutes','compliance_trainings',
    'security_events','retention_policies','retention_runs'
  ];
BEGIN
  -- Apenas DPO+SuperAdmin leem dados de observability/segurança global
  FOREACH t IN ARRAY read_only_tables LOOP
    EXECUTE format('REVOKE ALL ON %I FROM authenticated', t);
    EXECUTE format('GRANT SELECT ON %I TO service_role', t);
  END LOOP;

  -- Tenant-scoped: authenticated lê via RLS, service_role faz mutações
  FOREACH t IN ARRAY tenant_tables LOOP
    EXECUTE format('GRANT SELECT ON %I TO authenticated', t);
    EXECUTE format('GRANT ALL ON %I TO service_role', t);
  END LOOP;
END $$;

GRANT EXECUTE ON FUNCTION rpc_emit_slo_violation(text, text, numeric, numeric, numeric) TO service_role;
GRANT EXECUTE ON FUNCTION rpc_dsar_create(uuid, text, dsar_type, text, jsonb) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION rpc_dsar_anonymize(uuid) TO service_role;
GRANT EXECUTE ON FUNCTION rpc_dsar_revert(uuid) TO service_role;
GRANT EXECUTE ON FUNCTION rpc_metrics_snapshot() TO service_role;

COMMIT;

-- ============================================================================
-- Fim do schema v11
-- ============================================================================

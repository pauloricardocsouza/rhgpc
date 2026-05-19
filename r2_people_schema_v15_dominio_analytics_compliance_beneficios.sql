-- ============================================================================
-- R2 People · Schema SQL v15 · Domínio + Analytics + Compliance + Benefícios
-- ----------------------------------------------------------------------------
-- Materializa em SQL executável:
--   - Spec M16 (Integração Domínio · ID map + sync jobs + handlers extras)
--   - Spec M17 (People Analytics · view materializada + RPCs k-anonymity)
--   - Spec M18 (Compliance · ASO + EPI + treinamentos NR + termos + docs pessoais)
--   - Spec M19 (Benefícios · catálogo + adesão + dependentes + reembolso + convênios)
--
-- Pré-requisito: schemas v9-v14 aplicados.
-- 100% idempotente. Guards graceful (IF EXISTS) em refs cross-schema.
-- ============================================================================

BEGIN;

-- ============================================================================
-- 1. M16 · DOMÍNIO INTEGRATION
-- ============================================================================

ALTER TABLE inbound_webhook_endpoints
  ADD COLUMN IF NOT EXISTS integration_mode text
    CHECK (integration_mode IN ('webhook','api_polling','file_upload','ocr_pdf')),
  ADD COLUMN IF NOT EXISTS config_extra jsonb DEFAULT '{}'::jsonb,
  ADD COLUMN IF NOT EXISTS last_sync_at timestamptz,
  ADD COLUMN IF NOT EXISTS last_sync_status text
    CHECK (last_sync_status IN ('success','partial','failed','running','idle'));

CREATE TABLE IF NOT EXISTS dominio_id_map (
  tenant_id           uuid NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  entity_type         text NOT NULL CHECK (entity_type IN ('employee','branch','department','position','payroll_run','dependent')),
  r2_id               uuid NOT NULL,
  dominio_external_id text NOT NULL,
  first_seen_at       timestamptz NOT NULL DEFAULT now(),
  last_synced_at      timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (tenant_id, entity_type, dominio_external_id)
);

CREATE INDEX IF NOT EXISTS idx_dominio_id_map_r2
  ON dominio_id_map (tenant_id, entity_type, r2_id);

CREATE TABLE IF NOT EXISTS dominio_sync_jobs (
  id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  endpoint_id         uuid NOT NULL REFERENCES inbound_webhook_endpoints(id) ON DELETE CASCADE,
  tenant_id           uuid NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  sync_type           text NOT NULL,
  scheduled_for       timestamptz NOT NULL,
  started_at          timestamptz,
  finished_at         timestamptz,
  status              text NOT NULL DEFAULT 'pending'
    CHECK (status IN ('pending','running','success','failed','skipped')),
  records_processed   int,
  records_failed      int,
  error_summary       text,
  metadata            jsonb DEFAULT '{}'::jsonb
);

CREATE INDEX IF NOT EXISTS idx_dominio_sync_pending
  ON dominio_sync_jobs (scheduled_for) WHERE status = 'pending';

CREATE INDEX IF NOT EXISTS idx_dominio_sync_tenant_recent
  ON dominio_sync_jobs (tenant_id, started_at DESC);

-- 1.1 RPC resolve/link IDs
CREATE OR REPLACE FUNCTION rpc_dominio_resolve_id(
  p_tenant_id uuid,
  p_entity_type text,
  p_dominio_external_id text
) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE v_r2_id uuid;
BEGIN
  SELECT r2_id INTO v_r2_id FROM dominio_id_map
  WHERE tenant_id = p_tenant_id
    AND entity_type = p_entity_type
    AND dominio_external_id = p_dominio_external_id;
  RETURN v_r2_id;
END;
$$;

CREATE OR REPLACE FUNCTION rpc_dominio_link_id(
  p_tenant_id uuid,
  p_entity_type text,
  p_r2_id uuid,
  p_dominio_external_id text
) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  INSERT INTO dominio_id_map (tenant_id, entity_type, r2_id, dominio_external_id)
  VALUES (p_tenant_id, p_entity_type, p_r2_id, p_dominio_external_id)
  ON CONFLICT (tenant_id, entity_type, dominio_external_id) DO UPDATE
    SET r2_id = EXCLUDED.r2_id, last_synced_at = now();
END;
$$;

-- 1.2 Status agregado
CREATE OR REPLACE FUNCTION rpc_dominio_sync_status(p_tenant_id uuid)
RETURNS TABLE (
  endpoint_name text,
  integration_mode text,
  last_sync_at timestamptz,
  last_sync_status text,
  pending_jobs int,
  failed_last_24h int
)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  RETURN QUERY
  SELECT
    iwe.name,
    iwe.integration_mode,
    iwe.last_sync_at,
    iwe.last_sync_status,
    (SELECT count(*)::int FROM dominio_sync_jobs WHERE endpoint_id = iwe.id AND status='pending'),
    (SELECT count(*)::int FROM dominio_sync_jobs
      WHERE endpoint_id = iwe.id AND status='failed' AND started_at > now() - interval '24 hours')
  FROM inbound_webhook_endpoints iwe
  WHERE iwe.tenant_id = p_tenant_id
    AND iwe.source_system = 'dominio_api';
END;
$$;

-- ============================================================================
-- 2. M17 · PEOPLE ANALYTICS
-- ============================================================================

-- 2.1 Auto-declarações D&I (opcionais c/ consent)
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'employees') THEN
    EXECUTE $S$
      ALTER TABLE employees
        ADD COLUMN IF NOT EXISTS gender_self_declared text,
        ADD COLUMN IF NOT EXISTS race_self_declared text,
        ADD COLUMN IF NOT EXISTS pcd boolean DEFAULT false,
        ADD COLUMN IF NOT EXISTS pcd_type text;
    $S$;
  END IF;
END $$;

-- 2.2 View materializada de headcount diário (refresh noturno)
-- Esqueleto · ativar quando employees table consolidada
-- CREATE MATERIALIZED VIEW IF NOT EXISTS mv_headcount_daily AS ...
-- (deixado comentado · ativar em migration posterior quando employees consolidada)

-- 2.3 K-anonymity helper
CREATE OR REPLACE FUNCTION fn_apply_k_anonymity(
  p_data jsonb,
  p_min int DEFAULT 5
) RETURNS jsonb
LANGUAGE plpgsql AS $$
DECLARE v_result jsonb := '{}'::jsonb; v_key text; v_val numeric;
BEGIN
  FOR v_key, v_val IN SELECT key, value::numeric FROM jsonb_each_text(p_data) LOOP
    IF v_val >= p_min THEN
      v_result := v_result || jsonb_build_object(v_key, v_val);
    ELSE
      v_result := v_result || jsonb_build_object(v_key, '<5');
    END IF;
  END LOOP;
  RETURN v_result;
EXCEPTION
  WHEN others THEN RETURN p_data;
END;
$$;

-- 2.4 Tabela de exports auditados
CREATE TABLE IF NOT EXISTS analytics_exports (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id     uuid NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  user_id       uuid NOT NULL REFERENCES auth.users(id),
  export_type   text NOT NULL CHECK (export_type IN ('pdf','csv','xlsx','gslides')),
  dashboard     text NOT NULL,
  filters       jsonb,
  rows_count    int,
  file_url      text,
  occurred_at   timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_analytics_exports_tenant
  ON analytics_exports (tenant_id, occurred_at DESC);

-- ============================================================================
-- 3. M18 · COMPLIANCE & TREINAMENTOS
-- ============================================================================

-- 3.1 ASO
CREATE TABLE IF NOT EXISTS medical_exams_aso (
  id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id           uuid NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  employee_id         uuid NOT NULL,
  exam_type           text NOT NULL CHECK (exam_type IN ('admissional','periodico','retorno','mudanca_funcao','demissional')),
  exam_date           date NOT NULL,
  valid_until         date NOT NULL,
  physician_name      text NOT NULL,
  physician_crm       text NOT NULL,
  physician_uf        text NOT NULL,
  clinic_name         text,
  conclusion          text NOT NULL CHECK (conclusion IN ('apto','inapto','apto_com_restricao')),
  restrictions        text,
  pdf_storage_key     text,
  pdf_sha256          text,
  created_by          uuid REFERENCES auth.users(id),
  created_at          timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_aso_employee ON medical_exams_aso (employee_id, exam_date DESC);
CREATE INDEX IF NOT EXISTS idx_aso_expiring_soon ON medical_exams_aso (valid_until)
  WHERE conclusion IN ('apto','apto_com_restricao');

-- 3.2 EPI
CREATE TABLE IF NOT EXISTS epi_catalog (
  id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id           uuid NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  name                text NOT NULL,
  ca_number           text NOT NULL,
  ca_valid_until      date,
  description         text,
  active              boolean DEFAULT true,
  UNIQUE (tenant_id, name, ca_number)
);

CREATE TABLE IF NOT EXISTS epi_required_by_position (
  position_id         uuid NOT NULL,
  epi_id              uuid NOT NULL REFERENCES epi_catalog(id) ON DELETE CASCADE,
  qty_per_period      int NOT NULL DEFAULT 1,
  replacement_months  int NOT NULL DEFAULT 12,
  PRIMARY KEY (position_id, epi_id)
);

CREATE TABLE IF NOT EXISTS epi_deliveries (
  id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id           uuid NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  employee_id         uuid NOT NULL,
  epi_id              uuid NOT NULL REFERENCES epi_catalog(id),
  delivered_qty       int NOT NULL,
  delivered_at        timestamptz NOT NULL DEFAULT now(),
  delivered_by        uuid REFERENCES auth.users(id),
  next_replacement_at date,
  signature_hash      text,
  signature_timestamp timestamptz,
  signature_ip        inet,
  signature_pdf_key   text,
  notes               text
);

CREATE INDEX IF NOT EXISTS idx_epi_employee ON epi_deliveries (employee_id, delivered_at DESC);

-- 3.3 Compliance trainings (extensão da v11)
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'compliance_trainings') THEN
    EXECUTE $S$
      ALTER TABLE compliance_trainings
        ADD COLUMN IF NOT EXISTS norm text,
        ADD COLUMN IF NOT EXISTS modality text,
        ADD COLUMN IF NOT EXISTS workload_hours numeric,
        ADD COLUMN IF NOT EXISTS instructor_name text,
        ADD COLUMN IF NOT EXISTS instructor_credential text,
        ADD COLUMN IF NOT EXISTS certificate_pdf_key text,
        ADD COLUMN IF NOT EXISTS certificate_qr_code text,
        ADD COLUMN IF NOT EXISTS pass_score numeric;
    $S$;
  END IF;
END $$;

-- 3.4 Termos e políticas versionadas
CREATE TABLE IF NOT EXISTS policy_documents (
  id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id           uuid NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  policy_code         text NOT NULL,
  version             text NOT NULL,
  title               text NOT NULL,
  body_markdown       text,
  pdf_storage_key     text,
  pdf_sha256          text NOT NULL,
  required_for        text[] NOT NULL,
  renewal_period      interval,
  effective_from      date NOT NULL,
  superseded_by       uuid REFERENCES policy_documents(id),
  created_at          timestamptz NOT NULL DEFAULT now(),
  UNIQUE (tenant_id, policy_code, version)
);

CREATE TABLE IF NOT EXISTS policy_acceptances (
  id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id           uuid NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  user_id             uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  policy_id           uuid NOT NULL REFERENCES policy_documents(id) ON DELETE RESTRICT,
  accepted_at         timestamptz NOT NULL DEFAULT now(),
  ip                  inet,
  user_agent          text,
  geo_city            text,
  UNIQUE (user_id, policy_id)
);

CREATE INDEX IF NOT EXISTS idx_acceptances_user ON policy_acceptances (user_id, accepted_at DESC);

-- 3.5 Documentos pessoais
CREATE TABLE IF NOT EXISTS personal_documents (
  id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id           uuid NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  employee_id         uuid NOT NULL,
  doc_type            text NOT NULL,
  number              text,
  issuer              text,
  issued_at           date,
  valid_until         date,
  pdf_storage_key     text,
  notes               text,
  uploaded_at         timestamptz NOT NULL DEFAULT now(),
  uploaded_by         uuid REFERENCES auth.users(id)
);

CREATE INDEX IF NOT EXISTS idx_personal_docs_employee ON personal_documents (employee_id, doc_type);
CREATE INDEX IF NOT EXISTS idx_personal_docs_expiring
  ON personal_documents (valid_until)
  WHERE valid_until IS NOT NULL;

-- 3.6 LTCAT + classificação hazard
CREATE TABLE IF NOT EXISTS ltcat_documents (
  id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id           uuid NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  branch_id           uuid,
  effective_from      date NOT NULL,
  valid_until         date NOT NULL,
  responsible_engineer text NOT NULL,
  engineer_crea       text NOT NULL,
  pdf_storage_key     text,
  notes               text
);

CREATE TABLE IF NOT EXISTS position_hazard_classification (
  position_id         uuid PRIMARY KEY,
  is_periculosa       boolean DEFAULT false,
  periculosidade_basis text,
  is_insalubre        boolean DEFAULT false,
  insalubridade_grade text,
  insalubridade_basis text,
  epi_neutralizes     boolean DEFAULT false,
  neutralization_evidence_pdf text,
  reviewed_at         timestamptz,
  reviewed_by         uuid REFERENCES auth.users(id)
);

-- 3.7 Score de compliance (RPC)
CREATE OR REPLACE FUNCTION rpc_employee_compliance_score(
  p_tenant_id uuid,
  p_employee_id uuid
) RETURNS TABLE (score numeric, aso_status text, policies_pending int, docs_expiring int)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_aso_status text := 'missing';
  v_score numeric := 100;
  v_policies_pending int := 0;
  v_docs_expiring int := 0;
BEGIN
  -- ASO status
  SELECT
    CASE
      WHEN max(valid_until) IS NULL THEN 'missing'
      WHEN max(valid_until) < current_date THEN 'expired'
      WHEN max(valid_until) < current_date + interval '60 days' THEN 'expiring'
      ELSE 'ok'
    END
  INTO v_aso_status
  FROM medical_exams_aso
  WHERE tenant_id = p_tenant_id AND employee_id = p_employee_id
    AND conclusion IN ('apto','apto_com_restricao');

  IF v_aso_status = 'missing' THEN v_score := v_score - 30;
  ELSIF v_aso_status = 'expired' THEN v_score := v_score - 25;
  ELSIF v_aso_status = 'expiring' THEN v_score := v_score - 10;
  END IF;

  -- Documentos vencendo em 30d
  SELECT count(*) INTO v_docs_expiring
  FROM personal_documents
  WHERE tenant_id = p_tenant_id AND employee_id = p_employee_id
    AND valid_until IS NOT NULL
    AND valid_until BETWEEN current_date AND current_date + interval '30 days';

  v_score := v_score - LEAST(v_docs_expiring * 5, 25);

  RETURN QUERY SELECT GREATEST(v_score, 0)::numeric, v_aso_status, v_policies_pending, v_docs_expiring;
END;
$$;

-- ============================================================================
-- 4. M19 · BENEFÍCIOS & DEPENDENTES
-- ============================================================================

CREATE TABLE IF NOT EXISTS benefit_catalog (
  id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id           uuid NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  code                text NOT NULL,
  name                text NOT NULL,
  category            text NOT NULL CHECK (category IN ('saude','educacao','lazer','financeiro','alimentacao','transporte','familia','outros')),
  description_md      text,
  adhesion_type       text NOT NULL CHECK (adhesion_type IN ('automatic','opt_out','opt_in','requires_approval')),
  cost_employee_type  text CHECK (cost_employee_type IN ('free','fixed','percent_salary','coparticipation')),
  cost_employee_value numeric,
  cost_company_value  numeric,
  operator            text,
  partner_logo_url    text,
  rules_md            text,
  required_docs       text[],
  faq_md              text,
  active              boolean DEFAULT true,
  display_order       int DEFAULT 0,
  UNIQUE (tenant_id, code)
);

CREATE TABLE IF NOT EXISTS benefit_eligibility (
  benefit_id          uuid NOT NULL REFERENCES benefit_catalog(id) ON DELETE CASCADE,
  position_id         uuid,
  branch_id           uuid,
  department_id       uuid,
  min_months_company  int DEFAULT 0,
  PRIMARY KEY (benefit_id, position_id, branch_id, department_id)
);

CREATE TABLE IF NOT EXISTS benefit_subscriptions (
  id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id           uuid NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  employee_id         uuid NOT NULL,
  benefit_id          uuid NOT NULL REFERENCES benefit_catalog(id),
  status              text NOT NULL CHECK (status IN ('pending_approval','active','suspended','cancelled')) DEFAULT 'pending_approval',
  adhered_at          timestamptz NOT NULL DEFAULT now(),
  active_from         date,
  cancelled_at        timestamptz,
  cancellation_reason text,
  approved_by         uuid REFERENCES auth.users(id),
  approved_at         timestamptz,
  metadata            jsonb DEFAULT '{}'::jsonb
);

CREATE INDEX IF NOT EXISTS idx_benefit_subs_active
  ON benefit_subscriptions (employee_id) WHERE status = 'active';

CREATE TABLE IF NOT EXISTS dependents (
  id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id           uuid NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  employee_id         uuid NOT NULL,
  full_name           text NOT NULL,
  cpf                 text,
  birth_date          date NOT NULL,
  relationship        text NOT NULL CHECK (relationship IN ('conjuge','filho','filha','enteado','enteada','pai','mae','outro')),
  gender              text,
  pcd                 boolean DEFAULT false,
  pcd_type            text,
  document_pdf_key    text,
  includes_in_ir      boolean DEFAULT true,
  includes_in_health  boolean DEFAULT false,
  includes_in_va      boolean DEFAULT false,
  dependency_valid_until date,
  status              text CHECK (status IN ('active','removed')) DEFAULT 'active',
  added_at            timestamptz DEFAULT now(),
  removed_at          timestamptz,
  removed_reason      text
);

CREATE INDEX IF NOT EXISTS idx_dependents_employee
  ON dependents (employee_id) WHERE status = 'active';

-- 4.4 Convênios parceiros
CREATE TABLE IF NOT EXISTS partner_perks (
  id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id           uuid NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  partner_name        text NOT NULL,
  partner_logo_url    text,
  category            text,
  discount_pct        numeric,
  discount_description text,
  how_to_use_md       text,
  promo_code          text,
  url                 text,
  phone               text,
  address             text,
  city                text,
  state               text,
  active              boolean DEFAULT true,
  valid_until         date,
  display_order       int DEFAULT 0
);

CREATE TABLE IF NOT EXISTS partner_perk_clicks (
  id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id           uuid NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  perk_id             uuid NOT NULL REFERENCES partner_perks(id) ON DELETE CASCADE,
  user_id             uuid REFERENCES auth.users(id),
  clicked_at          timestamptz DEFAULT now()
);

CREATE TABLE IF NOT EXISTS partner_perk_ratings (
  id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  perk_id             uuid NOT NULL REFERENCES partner_perks(id) ON DELETE CASCADE,
  user_id             uuid NOT NULL REFERENCES auth.users(id),
  rating              int NOT NULL CHECK (rating BETWEEN 1 AND 5),
  comment             text,
  created_at          timestamptz DEFAULT now(),
  UNIQUE (perk_id, user_id)
);

-- 4.5 Reembolsos
CREATE TABLE IF NOT EXISTS reimbursement_policies (
  id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id           uuid NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  category            text NOT NULL,
  max_brl_cents_month int,
  max_brl_cents_year  int,
  requires_leader     boolean DEFAULT true,
  requires_rh         boolean DEFAULT true,
  eligible_positions  uuid[],
  deadline_days       int DEFAULT 30,
  description_md      text,
  active              boolean DEFAULT true,
  UNIQUE (tenant_id, category)
);

CREATE TABLE IF NOT EXISTS reimbursement_requests (
  id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id           uuid NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  employee_id         uuid NOT NULL,
  category            text NOT NULL,
  amount_brl_cents    int NOT NULL,
  expense_date        date NOT NULL,
  receipt_pdf_key     text NOT NULL,
  justification       text,
  status              text NOT NULL CHECK (status IN ('pending_leader','pending_rh','approved','rejected','paid')) DEFAULT 'pending_leader',
  leader_id           uuid REFERENCES auth.users(id),
  leader_decision_at  timestamptz,
  leader_notes        text,
  rh_id               uuid REFERENCES auth.users(id),
  rh_decision_at      timestamptz,
  rh_notes            text,
  payment_method      text,
  paid_at             timestamptz,
  dominio_event_id    text,
  created_at          timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_reimb_employee ON reimbursement_requests (employee_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_reimb_pending ON reimbursement_requests (status, created_at)
  WHERE status IN ('pending_leader','pending_rh');

-- 4.6 RPC reembolso decisão
CREATE OR REPLACE FUNCTION rpc_reimbursement_decide(
  p_request_id uuid,
  p_decision text,
  p_notes text DEFAULT NULL
) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE v_req reimbursement_requests;
BEGIN
  SELECT * INTO v_req FROM reimbursement_requests WHERE id = p_request_id FOR UPDATE;

  IF v_req.status = 'pending_leader' AND p_decision IN ('approve','reject') THEN
    UPDATE reimbursement_requests SET
      status = CASE WHEN p_decision = 'approve' THEN 'pending_rh' ELSE 'rejected' END,
      leader_id = auth.uid(),
      leader_decision_at = now(),
      leader_notes = p_notes
    WHERE id = p_request_id;
  ELSIF v_req.status = 'pending_rh' AND p_decision IN ('approve','reject') THEN
    UPDATE reimbursement_requests SET
      status = CASE WHEN p_decision = 'approve' THEN 'approved' ELSE 'rejected' END,
      rh_id = auth.uid(),
      rh_decision_at = now(),
      rh_notes = p_notes
    WHERE id = p_request_id;
  ELSE
    RAISE EXCEPTION 'Invalid decision flow for status %', v_req.status;
  END IF;
END;
$$;

-- ============================================================================
-- 5. RLS POLICIES
-- ============================================================================

DO $$
DECLARE t text;
BEGIN
  FOREACH t IN ARRAY ARRAY[
    'dominio_id_map','dominio_sync_jobs',
    'analytics_exports',
    'medical_exams_aso','epi_catalog','epi_deliveries',
    'policy_documents','policy_acceptances','personal_documents',
    'ltcat_documents',
    'benefit_catalog','benefit_subscriptions','dependents',
    'partner_perks','partner_perk_clicks','partner_perk_ratings',
    'reimbursement_policies','reimbursement_requests'
  ] LOOP
    EXECUTE format('ALTER TABLE %I ENABLE ROW LEVEL SECURITY', t);
    EXECUTE format('
      DROP POLICY IF EXISTS %I_tenant_isolation ON %I;
      CREATE POLICY %I_tenant_isolation ON %I
        FOR ALL
        USING (tenant_id = (current_setting(''app.tenant_id'', true))::uuid);',
      t, t, t, t);
  END LOOP;
END $$;

-- Exceções: epi_required_by_position e position_hazard_classification não têm tenant_id direto
-- (herdam via position_id). Policy específica:
ALTER TABLE epi_required_by_position ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS epi_required_via_position ON epi_required_by_position;
CREATE POLICY epi_required_via_position ON epi_required_by_position
  FOR SELECT USING (
    epi_id IN (SELECT id FROM epi_catalog
               WHERE tenant_id = (current_setting('app.tenant_id', true))::uuid)
  );

-- ============================================================================
-- 6. GRANTs
-- ============================================================================

DO $$
DECLARE t text;
BEGIN
  FOREACH t IN ARRAY ARRAY[
    'dominio_id_map','dominio_sync_jobs',
    'analytics_exports',
    'medical_exams_aso','epi_catalog','epi_required_by_position','epi_deliveries',
    'policy_documents','policy_acceptances','personal_documents',
    'ltcat_documents','position_hazard_classification',
    'benefit_catalog','benefit_eligibility','benefit_subscriptions','dependents',
    'partner_perks','partner_perk_clicks','partner_perk_ratings',
    'reimbursement_policies','reimbursement_requests'
  ] LOOP
    EXECUTE format('GRANT SELECT ON %I TO authenticated', t);
    EXECUTE format('GRANT ALL ON %I TO service_role', t);
  END LOOP;
END $$;

GRANT EXECUTE ON FUNCTION rpc_dominio_resolve_id(uuid, text, text) TO service_role;
GRANT EXECUTE ON FUNCTION rpc_dominio_link_id(uuid, text, uuid, text) TO service_role;
GRANT EXECUTE ON FUNCTION rpc_dominio_sync_status(uuid) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION fn_apply_k_anonymity(jsonb, int) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION rpc_employee_compliance_score(uuid, uuid) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION rpc_reimbursement_decide(uuid, text, text) TO authenticated, service_role;

-- ============================================================================
-- 7. SEED de políticas de reembolso padrão (exemplo)
-- ============================================================================

-- Será populado via UI tenant_admin, não em seed global.

COMMIT;

-- ============================================================================
-- Fim do schema v15
-- ============================================================================

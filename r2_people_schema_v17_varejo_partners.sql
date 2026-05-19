-- ============================================================================
-- R2 People · Schema SQL v17 · Varejo Multi-Loja + Partners + Mobile
-- ----------------------------------------------------------------------------
-- Materializa em SQL executável:
--   - Spec M21 (Varejo · trilhas operacionais + hall_of_fame + branch_absent
--               + sales_commissions_summary)
--   - Spec C4 (Partner Program · partners + referrals + commissions + materials)
--   - Spec D10 (Mobile · push_subscriptions + delivery_log + geo_events
--               + pwa_versions)
--
-- Pré-requisito: schemas v9-v16 aplicados.
-- 100% idempotente. Guards graceful para refs cross-schema.
-- ============================================================================

BEGIN;

-- ============================================================================
-- 1. M21 · TRILHAS OPERACIONAIS (caixa, repositor, ASG, etc)
-- ============================================================================

CREATE TABLE IF NOT EXISTS operational_tracks (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id       uuid NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  code            text NOT NULL,
  name            text NOT NULL,
  description     text,
  target_function text NOT NULL,
  total_hours     numeric,
  validity_months int,
  active          boolean DEFAULT true,
  created_at      timestamptz DEFAULT now(),
  UNIQUE (tenant_id, code)
);

CREATE TABLE IF NOT EXISTS operational_track_modules (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  track_id        uuid NOT NULL REFERENCES operational_tracks(id) ON DELETE CASCADE,
  name            text NOT NULL,
  description     text,
  display_order   int NOT NULL,
  video_url       text,
  pdf_url         text,
  quiz_questions  jsonb,
  pass_score      numeric DEFAULT 70,
  estimated_minutes int,
  UNIQUE (track_id, display_order)
);

CREATE TABLE IF NOT EXISTS employee_track_progress (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id       uuid NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  employee_id     uuid NOT NULL,
  track_id        uuid NOT NULL REFERENCES operational_tracks(id),
  module_id       uuid NOT NULL REFERENCES operational_track_modules(id),
  started_at      timestamptz,
  completed_at    timestamptz,
  quiz_score      numeric,
  attempts        int DEFAULT 0,
  UNIQUE (employee_id, module_id)
);

CREATE INDEX IF NOT EXISTS idx_track_progress_employee
  ON employee_track_progress (employee_id, track_id);

-- ============================================================================
-- 2. M21 · HALL OF FAME
-- ============================================================================

CREATE TABLE IF NOT EXISTS hall_of_fame (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id       uuid NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  category        text NOT NULL CHECK (category IN ('funcionario_mes','vendedor_mes','caixa_excelencia','repositor_mes','time_loja_mes')),
  period          text NOT NULL,
  branch_id       uuid,
  employee_id     uuid,
  score           numeric,
  reasoning       jsonb,
  awarded_at      timestamptz NOT NULL DEFAULT now(),
  published       boolean DEFAULT false
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_hof_unique
  ON hall_of_fame (tenant_id, category, period, COALESCE(branch_id, '00000000-0000-0000-0000-000000000000'::uuid), COALESCE(employee_id, '00000000-0000-0000-0000-000000000000'::uuid));

CREATE INDEX IF NOT EXISTS idx_hof_recent
  ON hall_of_fame (tenant_id, period DESC, category);

-- Função que calcula hall_of_fame mensal (cron · primeiro dia do mês)
CREATE OR REPLACE FUNCTION rpc_calculate_hall_of_fame(
  p_tenant_id uuid,
  p_period text
) RETURNS int
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_count int := 0;
BEGIN
  -- Esqueleto · implementação real cruza:
  -- * praises_received + evaluations + medical_certificates (funcionario_mes)
  -- * sales_commissions_summary (vendedor_mes)
  -- * pos_metrics (caixa_excelencia · velocidade/NPS)
  -- * reposition_metrics (repositor_mes · ruptura)
  -- * branch metrics agregadas (time_loja_mes)
  --
  -- Por brevidade, retorna 0 (implementar com dados reais por cliente)
  RETURN v_count;
END;
$$;

-- ============================================================================
-- 3. M21 · ABSENTEÍSMO POR LOJA (refresh noturno)
-- ============================================================================

CREATE TABLE IF NOT EXISTS branch_absenteeism_daily (
  tenant_id           uuid NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  branch_id           uuid NOT NULL,
  day                 date NOT NULL,
  headcount_expected  int NOT NULL,
  headcount_present   int NOT NULL,
  absent_certificate  int DEFAULT 0,
  absent_unjustified  int DEFAULT 0,
  absent_vacation     int DEFAULT 0,
  absent_dayoff       int DEFAULT 0,
  calculated_at       timestamptz DEFAULT now(),
  PRIMARY KEY (tenant_id, branch_id, day)
);

CREATE INDEX IF NOT EXISTS idx_absent_recent
  ON branch_absenteeism_daily (tenant_id, day DESC);

-- Função · taxa de absenteísmo em janela
CREATE OR REPLACE FUNCTION rpc_branch_absent_rate(
  p_tenant_id uuid,
  p_branch_id uuid,
  p_from date,
  p_to date
) RETURNS numeric
LANGUAGE plpgsql STABLE
AS $$
DECLARE v_rate numeric;
BEGIN
  SELECT
    CASE WHEN sum(headcount_expected) > 0
      THEN ROUND(
        sum(absent_certificate + absent_unjustified + absent_vacation + absent_dayoff)::numeric
        / sum(headcount_expected) * 100, 2)
      ELSE 0
    END
  INTO v_rate
  FROM branch_absenteeism_daily
  WHERE tenant_id = p_tenant_id
    AND branch_id = p_branch_id
    AND day BETWEEN p_from AND p_to;

  RETURN COALESCE(v_rate, 0);
END;
$$;

-- ============================================================================
-- 4. M21 · COMISSÕES DE VENDAS (do Domínio · M16 reflete)
-- ============================================================================

CREATE TABLE IF NOT EXISTS sales_commissions_summary (
  id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id           uuid NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  employee_id         uuid NOT NULL,
  period              text NOT NULL,
  meta_brl_cents      bigint,
  realizado_brl_cents bigint,
  comissao_brl_cents  bigint,
  pct_atingimento     numeric,
  rank_in_branch      int,
  rank_total_in_branch int,
  source              text DEFAULT 'erp_dominio',
  synced_at           timestamptz DEFAULT now(),
  UNIQUE (employee_id, period)
);

CREATE INDEX IF NOT EXISTS idx_commissions_period
  ON sales_commissions_summary (tenant_id, period);

-- ============================================================================
-- 5. C4 · PARTNERS
-- ============================================================================

CREATE TABLE IF NOT EXISTS partners (
  id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_name        text NOT NULL,
  cnpj                text UNIQUE NOT NULL,
  segment             text NOT NULL CHECK (segment IN ('contador','consultoria_rh','consultoria_gestao','revenda_software','outros')),
  tier                text NOT NULL CHECK (tier IN ('indicacao','bronze','silver','gold','platinum')) DEFAULT 'indicacao',
  status              text NOT NULL CHECK (status IN ('applied','qualifying','active','suspended','terminated')) DEFAULT 'applied',
  applied_at          timestamptz DEFAULT now(),
  qualified_at        timestamptz,
  activated_at        timestamptz,
  contract_pdf_key    text,
  contract_signed_at  timestamptz,
  primary_contact_name text NOT NULL,
  primary_contact_email text NOT NULL,
  primary_contact_phone text,
  bank_pix_key        text,
  metadata            jsonb DEFAULT '{}'::jsonb
);

CREATE INDEX IF NOT EXISTS idx_partners_active
  ON partners (status, tier) WHERE status = 'active';

CREATE TABLE IF NOT EXISTS partner_referrals (
  id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  partner_id          uuid NOT NULL REFERENCES partners(id) ON DELETE CASCADE,
  tenant_id           uuid REFERENCES tenants(id) ON DELETE SET NULL,
  referral_code       text UNIQUE NOT NULL,
  client_company_name text,
  client_contact_email text,
  status              text NOT NULL CHECK (status IN ('lead','demo_scheduled','trial','converted','churned')) DEFAULT 'lead',
  referred_at         timestamptz DEFAULT now(),
  converted_at        timestamptz,
  churned_at          timestamptz,
  initial_plan        text,
  first_year_discount_applied boolean DEFAULT false
);

CREATE INDEX IF NOT EXISTS idx_referrals_partner
  ON partner_referrals (partner_id, status);

CREATE TABLE IF NOT EXISTS partner_commissions (
  id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  partner_id          uuid NOT NULL REFERENCES partners(id) ON DELETE CASCADE,
  referral_id         uuid REFERENCES partner_referrals(id),
  tenant_id           uuid NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  period              text NOT NULL,
  mrr_brl_cents       int NOT NULL,
  commission_pct      numeric NOT NULL,
  commission_brl_cents int NOT NULL,
  bonus_brl_cents     int DEFAULT 0,
  status              text NOT NULL CHECK (status IN ('pending','approved','paid','clawback')) DEFAULT 'pending',
  paid_at             timestamptz,
  payment_ref         text,
  nf_pdf_key          text,
  UNIQUE (partner_id, tenant_id, period)
);

CREATE INDEX IF NOT EXISTS idx_partner_commissions_pending
  ON partner_commissions (status, period) WHERE status IN ('pending','approved');

CREATE TABLE IF NOT EXISTS partner_materials (
  id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  title               text NOT NULL,
  category            text NOT NULL CHECK (category IN ('pitch_deck','video','one_pager','case_study','webinar')),
  format              text NOT NULL,
  url                 text NOT NULL,
  target_segment      text[],
  required_tier       text DEFAULT 'bronze',
  uploaded_at         timestamptz DEFAULT now(),
  active              boolean DEFAULT true
);

CREATE TABLE IF NOT EXISTS partner_nps (
  id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  partner_id          uuid NOT NULL REFERENCES partners(id) ON DELETE CASCADE,
  contact_user_id     uuid REFERENCES auth.users(id),
  score               int NOT NULL CHECK (score BETWEEN 0 AND 10),
  comment             text,
  period              text NOT NULL,
  created_at          timestamptz DEFAULT now()
);

-- ============================================================================
-- 6. C4 · RPCs principais
-- ============================================================================

CREATE OR REPLACE FUNCTION rpc_partner_referral_link(p_partner_id uuid)
RETURNS text
LANGUAGE plpgsql STABLE
AS $$
DECLARE v_code text;
BEGIN
  SELECT 'https://solucoesr2.com.br/trial?ref=' ||
         lower(regexp_replace(company_name, '[^a-zA-Z0-9]+', '-', 'g')) ||
         '-' || substr(id::text, 1, 6)
  INTO v_code
  FROM partners WHERE id = p_partner_id;
  RETURN v_code;
END;
$$;

CREATE OR REPLACE FUNCTION rpc_partner_dashboard(p_partner_id uuid)
RETURNS TABLE (
  mrr_total bigint,
  mrr_growth_mom numeric,
  clients_active int,
  clients_churned_90d int,
  next_payment_brl numeric,
  tier text,
  tier_progress_pct numeric
)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  -- Esqueleto · agrega de partner_commissions + partner_referrals
  RETURN QUERY SELECT
    0::bigint, 0::numeric, 0, 0, 0::numeric,
    (SELECT tier FROM partners WHERE id = p_partner_id),
    0::numeric;
END;
$$;

CREATE OR REPLACE FUNCTION rpc_partner_calculate_monthly_commissions(p_period text)
RETURNS int
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE v_count int := 0;
BEGIN
  -- Esqueleto · itera partner_referrals converted, calcula MRR atual via
  -- subscriptions, aplica pct do tier do partner, insere em partner_commissions
  RETURN v_count;
END;
$$;

-- Clawback (cliente sai por fault do partner em < 6m)
CREATE OR REPLACE FUNCTION rpc_partner_clawback(
  p_partner_id uuid,
  p_tenant_id uuid,
  p_reason text
) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  UPDATE partner_commissions
  SET status = 'clawback'
  WHERE partner_id = p_partner_id
    AND tenant_id = p_tenant_id
    AND status = 'paid'
    AND paid_at > now() - interval '6 months';
END;
$$;

-- ============================================================================
-- 7. D10 · PUSH NOTIFICATIONS + GEO
-- ============================================================================

CREATE TABLE IF NOT EXISTS push_subscriptions (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id       uuid NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  user_id         uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  endpoint        text NOT NULL,
  p256dh_key      text NOT NULL,
  auth_key        text NOT NULL,
  user_agent      text,
  device_type     text CHECK (device_type IN ('ios','android','desktop','unknown')),
  app_version     text,
  enabled         boolean NOT NULL DEFAULT true,
  silenced_categories text[] DEFAULT ARRAY[]::text[],
  created_at      timestamptz DEFAULT now(),
  last_used_at    timestamptz DEFAULT now(),
  UNIQUE (user_id, endpoint)
);

CREATE INDEX IF NOT EXISTS idx_push_active
  ON push_subscriptions (user_id) WHERE enabled = true;

CREATE TABLE IF NOT EXISTS push_delivery_log (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id       uuid NOT NULL,
  user_id         uuid NOT NULL,
  subscription_id uuid REFERENCES push_subscriptions(id) ON DELETE SET NULL,
  category        text NOT NULL,
  title           text NOT NULL,
  body            text,
  payload         jsonb,
  status          text NOT NULL CHECK (status IN ('queued','sent','delivered','clicked','failed','expired')),
  sent_at         timestamptz,
  clicked_at      timestamptz,
  error_msg       text
);

CREATE INDEX IF NOT EXISTS idx_push_log_recent
  ON push_delivery_log (sent_at DESC);

CREATE TABLE IF NOT EXISTS geo_events (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id       uuid NOT NULL,
  user_id         uuid NOT NULL,
  event_type      text NOT NULL,
  lat             numeric(10,7),
  lng             numeric(10,7),
  accuracy_m      int,
  city            text,
  state           text,
  occurred_at     timestamptz DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_geo_user
  ON geo_events (user_id, occurred_at DESC);

CREATE TABLE IF NOT EXISTS pwa_versions (
  version         text PRIMARY KEY,
  released_at     timestamptz DEFAULT now(),
  breaking        boolean DEFAULT false,
  release_notes   text
);

-- RPC · registrar push
CREATE OR REPLACE FUNCTION rpc_push_register(
  p_tenant_id uuid,
  p_endpoint text,
  p_p256dh text,
  p_auth text,
  p_device_type text DEFAULT 'unknown',
  p_user_agent text DEFAULT NULL
) RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE v_id uuid;
BEGIN
  INSERT INTO push_subscriptions (
    tenant_id, user_id, endpoint, p256dh_key, auth_key, device_type, user_agent
  ) VALUES (
    p_tenant_id, auth.uid(), p_endpoint, p_p256dh, p_auth, p_device_type, p_user_agent
  )
  ON CONFLICT (user_id, endpoint) DO UPDATE
    SET p256dh_key = EXCLUDED.p256dh_key,
        auth_key = EXCLUDED.auth_key,
        enabled = true,
        last_used_at = now()
  RETURNING id INTO v_id;
  RETURN v_id;
END;
$$;

-- RPC · silenciar categoria
CREATE OR REPLACE FUNCTION rpc_push_silence_category(p_category text)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  UPDATE push_subscriptions
  SET silenced_categories = array_append(
    array_remove(silenced_categories, p_category), p_category)
  WHERE user_id = auth.uid();
END;
$$;

-- RPC · versão atual PWA (consultada pelo Service Worker)
CREATE OR REPLACE FUNCTION rpc_pwa_current_version()
RETURNS TABLE (version text, breaking boolean, notes text)
LANGUAGE plpgsql STABLE
AS $$
BEGIN
  RETURN QUERY
  SELECT v.version, v.breaking, v.release_notes
  FROM pwa_versions v
  ORDER BY v.released_at DESC
  LIMIT 1;
END;
$$;

-- ============================================================================
-- 8. RLS POLICIES
-- ============================================================================

DO $$
DECLARE
  t text;
  tenant_tables text[] := ARRAY[
    'operational_tracks','employee_track_progress',
    'hall_of_fame','branch_absenteeism_daily','sales_commissions_summary',
    'partner_referrals','partner_commissions',
    'push_subscriptions','push_delivery_log','geo_events'
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

-- Modules herda via track_id
ALTER TABLE operational_track_modules ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS otm_via_track ON operational_track_modules;
CREATE POLICY otm_via_track ON operational_track_modules
  FOR SELECT USING (
    track_id IN (SELECT id FROM operational_tracks
                 WHERE tenant_id = (current_setting('app.tenant_id', true))::uuid)
  );

-- Partners é global (não tenant-scoped) · só super_admin + próprio partner
ALTER TABLE partners ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS partners_super_admin ON partners;
CREATE POLICY partners_super_admin ON partners
  FOR ALL
  USING (
    auth.jwt() ->> 'role' = 'super_admin'
    OR auth.role() = 'service_role'
    OR auth.uid()::text = (metadata->>'partner_user_id')
  );

-- Materials e NPS · super_admin + partners ativos
ALTER TABLE partner_materials ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS pm_public_read ON partner_materials;
CREATE POLICY pm_public_read ON partner_materials
  FOR SELECT USING (active = true);

ALTER TABLE partner_nps ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS pn_super_admin ON partner_nps;
CREATE POLICY pn_super_admin ON partner_nps
  FOR ALL USING (
    auth.jwt() ->> 'role' IN ('super_admin','partner_manager')
    OR auth.role() = 'service_role'
  );

-- pwa_versions é público (todos consultam)
ALTER TABLE pwa_versions ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS pwa_public_read ON pwa_versions;
CREATE POLICY pwa_public_read ON pwa_versions
  FOR SELECT USING (true);

-- ============================================================================
-- 9. GRANTs
-- ============================================================================

DO $$
DECLARE t text;
BEGIN
  FOREACH t IN ARRAY ARRAY[
    'operational_tracks','operational_track_modules','employee_track_progress',
    'hall_of_fame','branch_absenteeism_daily','sales_commissions_summary',
    'partner_referrals','partner_commissions','partner_materials','partner_nps',
    'push_subscriptions','push_delivery_log','geo_events','pwa_versions'
  ] LOOP
    EXECUTE format('GRANT SELECT ON %I TO authenticated', t);
    EXECUTE format('GRANT ALL ON %I TO service_role', t);
  END LOOP;
END $$;

-- Partners (mais restrita)
GRANT SELECT ON partners TO authenticated;
GRANT ALL ON partners TO service_role;

GRANT EXECUTE ON FUNCTION rpc_calculate_hall_of_fame(uuid, text) TO service_role;
GRANT EXECUTE ON FUNCTION rpc_branch_absent_rate(uuid, uuid, date, date) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION rpc_partner_referral_link(uuid) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION rpc_partner_dashboard(uuid) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION rpc_partner_calculate_monthly_commissions(text) TO service_role;
GRANT EXECUTE ON FUNCTION rpc_partner_clawback(uuid, uuid, text) TO service_role;
GRANT EXECUTE ON FUNCTION rpc_push_register(uuid, text, text, text, text, text) TO authenticated;
GRANT EXECUTE ON FUNCTION rpc_push_silence_category(text) TO authenticated;
GRANT EXECUTE ON FUNCTION rpc_pwa_current_version() TO anon, authenticated;

-- ============================================================================
-- 10. SEED inicial · 6 trilhas operacionais padrão (template GPC varejo)
-- ============================================================================

-- Inserido apenas se houver pelo menos um tenant
DO $$
DECLARE v_tenant_id uuid;
BEGIN
  SELECT id INTO v_tenant_id FROM tenants LIMIT 1;
  IF v_tenant_id IS NULL THEN RETURN; END IF;

  INSERT INTO operational_tracks (tenant_id, code, name, target_function, total_hours, validity_months) VALUES
    (v_tenant_id, 'caixa_admissional', 'Operador de Caixa · Trilha Admissional', 'caixa', 12, 12),
    (v_tenant_id, 'repositor_admissional', 'Repositor · Trilha Admissional', 'repositor', 8, 12),
    (v_tenant_id, 'asg_admissional', 'ASG / Limpeza · Trilha Admissional', 'asg', 6, 12),
    (v_tenant_id, 'vigilante_admissional', 'Vigilante · Trilha Admissional', 'vigilante', 16, 24),
    (v_tenant_id, 'frente_caixa_sr', 'Frente de Caixa Sênior · Liderança', 'frente_caixa_sr', 20, 24),
    (v_tenant_id, 'gerente_loja', 'Gerente de Loja · Trilha Promoção', 'gerente_loja', 40, 36)
  ON CONFLICT (tenant_id, code) DO NOTHING;
END $$;

-- pwa_versions inicial
INSERT INTO pwa_versions (version, breaking, release_notes)
VALUES ('v0.17', false, 'Schema v17 · Varejo Multi-Loja + Partners + Mobile PWA')
ON CONFLICT (version) DO NOTHING;

COMMIT;

-- ============================================================================
-- Fim do schema v17
-- ============================================================================

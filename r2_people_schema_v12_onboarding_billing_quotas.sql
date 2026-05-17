-- ============================================================================
-- R2 People · Schema SQL v12 · Onboarding + Billing + Quotas
-- ----------------------------------------------------------------------------
-- Materializa em SQL executável:
--   - Spec M13 (Onboarding Wizard do tenant)
--   - Novas áreas de billing (planos, assinaturas, seats, quotas, usage)
--   - Helpers de enforcement (trigger que barra INSERT além do limite)
--
-- Estrutura:
--   1. Onboarding (tenant_onboarding + função state machine)
--   2. Billing (plans, subscriptions, invoices, payment_methods)
--   3. Quotas & Seats (tenant_quotas, quota_usage_log, seat_assignments)
--   4. Triggers de enforcement (block insert quando excede quota)
--   5. RPCs (advance/skip onboarding, get_quota_status, assign_seat)
--   6. Seeds de planos padrão (Starter/Pro/Enterprise)
--   7. RLS + GRANTs
--
-- Idempotente. Pré-requisito: schema v11 aplicado.
-- ============================================================================

BEGIN;

-- ============================================================================
-- 1. ONBOARDING (spec M13)
-- ============================================================================

CREATE TABLE IF NOT EXISTS tenant_onboarding (
  tenant_id            uuid PRIMARY KEY REFERENCES tenants(id) ON DELETE CASCADE,
  current_step         int  NOT NULL DEFAULT 1 CHECK (current_step BETWEEN 1 AND 11),
  steps_completed      int[] NOT NULL DEFAULT '{}',
  steps_skipped        int[] NOT NULL DEFAULT '{}',
  steps_optional_done  int[] NOT NULL DEFAULT '{}',
  started_at           timestamptz NOT NULL DEFAULT now(),
  completed_at         timestamptz,
  abandoned_at         timestamptz,
  last_step_at         timestamptz NOT NULL DEFAULT now(),
  metadata             jsonb NOT NULL DEFAULT '{}'::jsonb
);

CREATE INDEX IF NOT EXISTS idx_onboarding_open
  ON tenant_onboarding (last_step_at)
  WHERE completed_at IS NULL AND abandoned_at IS NULL;

CREATE INDEX IF NOT EXISTS idx_onboarding_abandoned
  ON tenant_onboarding (last_step_at)
  WHERE abandoned_at IS NULL AND completed_at IS NULL AND last_step_at < now() - interval '14 days';

-- Trigger: marca completed_at quando todos os passos obrigatórios (1-7) estão em steps_completed
CREATE OR REPLACE FUNCTION trg_onboarding_check_completion()
RETURNS TRIGGER AS $$
DECLARE
  required int[] := ARRAY[1,2,3,4,5,6,7];
BEGIN
  IF NEW.completed_at IS NULL
     AND (required <@ NEW.steps_completed) THEN
    NEW.completed_at := now();
  END IF;
  -- Reset abandoned se voltou a progredir
  IF NEW.abandoned_at IS NOT NULL
     AND NEW.last_step_at > OLD.last_step_at THEN
    NEW.abandoned_at := NULL;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_onboarding_completion ON tenant_onboarding;
CREATE TRIGGER trg_onboarding_completion
  BEFORE UPDATE ON tenant_onboarding
  FOR EACH ROW EXECUTE FUNCTION trg_onboarding_check_completion();

-- Trigger: ao criar tenant, auto-cria onboarding row
CREATE OR REPLACE FUNCTION trg_tenants_init_onboarding()
RETURNS TRIGGER AS $$
BEGIN
  INSERT INTO tenant_onboarding (tenant_id, steps_completed)
  VALUES (
    NEW.id,
    CASE
      WHEN NEW.cnpj IS NOT NULL AND NEW.legal_name IS NOT NULL THEN ARRAY[1,2]
      ELSE ARRAY[]::int[]
    END
  )
  ON CONFLICT (tenant_id) DO NOTHING;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Só cria o trigger se tabela tenants tem essas colunas (graceful)
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'tenants' AND column_name = 'cnpj'
  ) THEN
    DROP TRIGGER IF EXISTS trg_tenants_onboarding ON tenants;
    CREATE TRIGGER trg_tenants_onboarding
      AFTER INSERT ON tenants
      FOR EACH ROW EXECUTE FUNCTION trg_tenants_init_onboarding();
  END IF;
END $$;

-- ============================================================================
-- 2. BILLING · Plans, Subscriptions, Invoices
-- ============================================================================

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'billing_interval') THEN
    CREATE TYPE billing_interval AS ENUM ('monthly','quarterly','annual');
  END IF;
END $$;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'subscription_status') THEN
    CREATE TYPE subscription_status AS ENUM (
      'trial','active','past_due','canceled','expired','suspended'
    );
  END IF;
END $$;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'invoice_status') THEN
    CREATE TYPE invoice_status AS ENUM (
      'draft','open','paid','void','uncollectible','refunded'
    );
  END IF;
END $$;

CREATE TABLE IF NOT EXISTS plans (
  id                 uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  code               text NOT NULL UNIQUE,        -- 'starter','pro','enterprise'
  name               text NOT NULL,
  description        text,
  price_brl_cents    int  NOT NULL,
  per_seat_brl_cents int  DEFAULT 0,              -- preço adicional por seat acima do incluído
  interval           billing_interval NOT NULL DEFAULT 'monthly',
  included_seats     int  NOT NULL DEFAULT 0,
  max_seats          int,                          -- NULL = ilimitado
  features           jsonb NOT NULL DEFAULT '{}'::jsonb,
  is_active          boolean NOT NULL DEFAULT true,
  visible            boolean NOT NULL DEFAULT true, -- false = plano custom oculto
  created_at         timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS subscriptions (
  id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id           uuid NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  plan_id             uuid NOT NULL REFERENCES plans(id),
  status              subscription_status NOT NULL DEFAULT 'trial',
  trial_ends_at       timestamptz,
  current_period_start timestamptz NOT NULL DEFAULT now(),
  current_period_end   timestamptz NOT NULL,
  cancel_at           timestamptz,
  canceled_at         timestamptz,
  cancellation_reason text,
  extra_seats         int NOT NULL DEFAULT 0,      -- seats adquiridos além do plano
  metadata            jsonb DEFAULT '{}'::jsonb,
  created_at          timestamptz NOT NULL DEFAULT now(),
  updated_at          timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_subs_tenant ON subscriptions (tenant_id, status);
CREATE INDEX IF NOT EXISTS idx_subs_renewal ON subscriptions (current_period_end)
  WHERE status IN ('trial','active');

CREATE TABLE IF NOT EXISTS payment_methods (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id       uuid NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  type            text NOT NULL CHECK (type IN ('credit_card','pix','boleto','wire')),
  provider        text,                            -- 'stripe','asaas','manual'
  provider_ref    text,                            -- token/customer_id externo
  brand           text,                            -- visa/master/etc
  last4           text,
  exp_month       int,
  exp_year        int,
  holder_name     text,
  is_default      boolean NOT NULL DEFAULT false,
  added_at        timestamptz NOT NULL DEFAULT now(),
  removed_at      timestamptz
);

CREATE INDEX IF NOT EXISTS idx_payment_methods_default
  ON payment_methods (tenant_id) WHERE is_default = true AND removed_at IS NULL;

CREATE TABLE IF NOT EXISTS invoices (
  id                 uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id          uuid NOT NULL REFERENCES tenants(id) ON DELETE RESTRICT,
  subscription_id    uuid REFERENCES subscriptions(id) ON DELETE SET NULL,
  number             text NOT NULL UNIQUE,         -- INV-2026-000123
  status             invoice_status NOT NULL DEFAULT 'draft',
  amount_brl_cents   int  NOT NULL,
  tax_brl_cents      int  NOT NULL DEFAULT 0,
  discount_brl_cents int  NOT NULL DEFAULT 0,
  total_brl_cents    int  NOT NULL,
  currency           text NOT NULL DEFAULT 'BRL',
  period_start       date NOT NULL,
  period_end         date NOT NULL,
  issued_at          timestamptz NOT NULL DEFAULT now(),
  due_at             timestamptz NOT NULL,
  paid_at            timestamptz,
  void_at            timestamptz,
  payment_method_id  uuid REFERENCES payment_methods(id),
  provider_ref       text,                          -- ID externo Stripe/Asaas
  pdf_url            text,
  line_items         jsonb NOT NULL DEFAULT '[]'::jsonb,
  metadata           jsonb DEFAULT '{}'::jsonb,
  created_at         timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_invoices_tenant ON invoices (tenant_id, issued_at DESC);
CREATE INDEX IF NOT EXISTS idx_invoices_due ON invoices (due_at) WHERE status = 'open';

-- ============================================================================
-- 3. QUOTAS & SEATS
-- ============================================================================

CREATE TABLE IF NOT EXISTS tenant_quotas (
  tenant_id       uuid NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  resource        text NOT NULL,                   -- 'seats','employees','webhooks','storage_gb','api_calls_month'
  hard_limit      int,                              -- NULL = ilimitado
  soft_warn_at    int,                              -- alerta amarelo
  current_usage   int NOT NULL DEFAULT 0,
  last_calculated_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (tenant_id, resource)
);

CREATE INDEX IF NOT EXISTS idx_quotas_near_limit
  ON tenant_quotas (tenant_id)
  WHERE hard_limit IS NOT NULL AND current_usage >= (hard_limit * 0.8);

CREATE TABLE IF NOT EXISTS quota_usage_log (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id   uuid NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  resource    text NOT NULL,
  delta       int  NOT NULL,                       -- pode ser negativo (decremento)
  new_usage   int  NOT NULL,
  reason      text,
  actor_id    uuid REFERENCES auth.users(id),
  occurred_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_quota_log_tenant
  ON quota_usage_log (tenant_id, resource, occurred_at DESC);

-- Seat assignments: cada user "ocupa" um seat do tenant
CREATE TABLE IF NOT EXISTS seat_assignments (
  id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id      uuid NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  user_id        uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  assigned_at    timestamptz NOT NULL DEFAULT now(),
  assigned_by    uuid REFERENCES auth.users(id),
  revoked_at     timestamptz,
  revoked_by     uuid REFERENCES auth.users(id),
  revoke_reason  text,
  UNIQUE (tenant_id, user_id)                       -- 1 user = 1 seat por tenant
);

CREATE INDEX IF NOT EXISTS idx_seats_active
  ON seat_assignments (tenant_id) WHERE revoked_at IS NULL;

-- ============================================================================
-- 4. TRIGGERS DE ENFORCEMENT
-- ============================================================================

-- Helper: incrementa quota e bloqueia se ultrapassar hard_limit
CREATE OR REPLACE FUNCTION fn_quota_increment(
  p_tenant_id uuid,
  p_resource  text,
  p_delta     int,
  p_reason    text DEFAULT NULL,
  p_actor_id  uuid DEFAULT NULL
) RETURNS int
LANGUAGE plpgsql
AS $$
DECLARE
  v_quota     tenant_quotas%ROWTYPE;
  v_new       int;
BEGIN
  SELECT * INTO v_quota
  FROM tenant_quotas
  WHERE tenant_id = p_tenant_id AND resource = p_resource
  FOR UPDATE;

  IF NOT FOUND THEN
    -- Sem quota configurada → permite mas registra
    INSERT INTO tenant_quotas (tenant_id, resource, current_usage)
    VALUES (p_tenant_id, p_resource, GREATEST(p_delta, 0))
    RETURNING current_usage INTO v_new;
  ELSE
    v_new := GREATEST(v_quota.current_usage + p_delta, 0);
    IF v_quota.hard_limit IS NOT NULL AND v_new > v_quota.hard_limit THEN
      RAISE EXCEPTION 'Quota exceeded for resource % on tenant % (limit=%, attempted=%)',
        p_resource, p_tenant_id, v_quota.hard_limit, v_new
        USING ERRCODE = 'check_violation';
    END IF;
    UPDATE tenant_quotas
    SET current_usage = v_new, last_calculated_at = now()
    WHERE tenant_id = p_tenant_id AND resource = p_resource;
  END IF;

  INSERT INTO quota_usage_log (tenant_id, resource, delta, new_usage, reason, actor_id)
  VALUES (p_tenant_id, p_resource, p_delta, v_new, p_reason, p_actor_id);

  RETURN v_new;
END;
$$;

-- Trigger: ao criar seat_assignment ativa, incrementa quota 'seats'
CREATE OR REPLACE FUNCTION trg_seats_enforce_quota()
RETURNS TRIGGER AS $$
BEGIN
  IF TG_OP = 'INSERT' AND NEW.revoked_at IS NULL THEN
    PERFORM fn_quota_increment(NEW.tenant_id, 'seats', 1,
      'seat_assigned', NEW.assigned_by);
  ELSIF TG_OP = 'UPDATE' THEN
    IF OLD.revoked_at IS NULL AND NEW.revoked_at IS NOT NULL THEN
      PERFORM fn_quota_increment(NEW.tenant_id, 'seats', -1,
        'seat_revoked', NEW.revoked_by);
    ELSIF OLD.revoked_at IS NOT NULL AND NEW.revoked_at IS NULL THEN
      PERFORM fn_quota_increment(NEW.tenant_id, 'seats', 1,
        'seat_reassigned', NEW.assigned_by);
    END IF;
  ELSIF TG_OP = 'DELETE' AND OLD.revoked_at IS NULL THEN
    PERFORM fn_quota_increment(OLD.tenant_id, 'seats', -1,
      'seat_deleted', NULL);
  END IF;
  RETURN COALESCE(NEW, OLD);
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_seats_quota ON seat_assignments;
CREATE TRIGGER trg_seats_quota
  AFTER INSERT OR UPDATE OR DELETE ON seat_assignments
  FOR EACH ROW EXECUTE FUNCTION trg_seats_enforce_quota();

-- Trigger genérico opcional: ao criar employee, incrementa quota 'employees'
-- (só se a tabela existe — graceful)
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'employees') THEN
    EXECUTE $TRG$
      CREATE OR REPLACE FUNCTION trg_employees_enforce_quota()
      RETURNS TRIGGER AS $f$
      BEGIN
        IF TG_OP = 'INSERT' THEN
          PERFORM fn_quota_increment(NEW.tenant_id, 'employees', 1,
            'employee_created', NULL);
        ELSIF TG_OP = 'DELETE' THEN
          PERFORM fn_quota_increment(OLD.tenant_id, 'employees', -1,
            'employee_deleted', NULL);
        END IF;
        RETURN COALESCE(NEW, OLD);
      END;
      $f$ LANGUAGE plpgsql;

      DROP TRIGGER IF EXISTS trg_employees_quota ON employees;
      CREATE TRIGGER trg_employees_quota
        AFTER INSERT OR DELETE ON employees
        FOR EACH ROW EXECUTE FUNCTION trg_employees_enforce_quota();
    $TRG$;
  END IF;
END $$;

-- ============================================================================
-- 5. RPCs
-- ============================================================================

-- 5.1 Avançar passo do onboarding
CREATE OR REPLACE FUNCTION rpc_onboarding_advance(
  p_tenant_id uuid,
  p_step      int,
  p_response  jsonb DEFAULT '{}'::jsonb
) RETURNS tenant_onboarding
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_row tenant_onboarding;
BEGIN
  SELECT * INTO v_row FROM tenant_onboarding WHERE tenant_id = p_tenant_id
  FOR UPDATE;

  IF NOT FOUND THEN
    INSERT INTO tenant_onboarding (tenant_id, current_step)
    VALUES (p_tenant_id, p_step)
    RETURNING * INTO v_row;
  END IF;

  -- Não permite pular passos obrigatórios (1-7)
  IF p_step BETWEEN 1 AND 7
     AND p_step > 1
     AND NOT (ARRAY[p_step - 1] <@ v_row.steps_completed)
     AND NOT (ARRAY[p_step - 1] <@ v_row.steps_skipped) THEN
    RAISE EXCEPTION 'Cannot advance to step % without completing step %', p_step, p_step - 1;
  END IF;

  UPDATE tenant_onboarding SET
    steps_completed = array_append(
      array_remove(steps_completed, p_step), p_step
    ),
    current_step    = LEAST(p_step + 1, 11),
    last_step_at    = now(),
    metadata        = metadata || jsonb_build_object('step_' || p_step, p_response)
  WHERE tenant_id = p_tenant_id
  RETURNING * INTO v_row;

  RETURN v_row;
END;
$$;

-- 5.2 Pular passo (apenas opcionais 8-11)
CREATE OR REPLACE FUNCTION rpc_onboarding_skip(
  p_tenant_id uuid,
  p_step      int
) RETURNS tenant_onboarding
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_row tenant_onboarding;
BEGIN
  IF p_step BETWEEN 1 AND 7 THEN
    RAISE EXCEPTION 'Step % is required and cannot be skipped', p_step;
  END IF;

  UPDATE tenant_onboarding SET
    steps_skipped = array_append(array_remove(steps_skipped, p_step), p_step),
    current_step  = LEAST(p_step + 1, 11),
    last_step_at  = now()
  WHERE tenant_id = p_tenant_id
  RETURNING * INTO v_row;

  RETURN v_row;
END;
$$;

-- 5.3 Status do onboarding (usado pelo banner)
CREATE OR REPLACE FUNCTION rpc_onboarding_status(p_tenant_id uuid)
RETURNS TABLE (
  current_step      int,
  total_required    int,
  completed_count   int,
  completion_pct    numeric,
  is_completed      boolean,
  is_abandoned      boolean,
  next_action_label text
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_row tenant_onboarding;
  v_done int;
BEGIN
  SELECT * INTO v_row FROM tenant_onboarding WHERE tenant_id = p_tenant_id;
  IF NOT FOUND THEN
    RETURN QUERY SELECT 1, 7, 0, 0::numeric, false, false, 'Comece pelo Passo 1'::text;
    RETURN;
  END IF;

  v_done := (
    SELECT count(*)::int FROM unnest(v_row.steps_completed) s
    WHERE s BETWEEN 1 AND 7
  );

  RETURN QUERY SELECT
    v_row.current_step,
    7,
    v_done,
    ROUND((v_done::numeric / 7) * 100, 1),
    v_row.completed_at IS NOT NULL,
    v_row.abandoned_at IS NOT NULL,
    CASE
      WHEN v_row.completed_at IS NOT NULL THEN 'Setup completo · ver itens opcionais'
      WHEN v_row.abandoned_at IS NOT NULL THEN 'Setup abandonado · retomar'
      ELSE 'Continuar do Passo ' || v_row.current_step
    END;
END;
$$;

-- 5.4 Marcar abandono (job recorrente)
CREATE OR REPLACE FUNCTION rpc_onboarding_mark_abandoned()
RETURNS int
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_count int;
BEGIN
  UPDATE tenant_onboarding SET abandoned_at = now()
  WHERE completed_at IS NULL
    AND abandoned_at IS NULL
    AND last_step_at < now() - interval '14 days';
  GET DIAGNOSTICS v_count = ROW_COUNT;
  RETURN v_count;
END;
$$;

-- 5.5 Assign seat (incrementa quota automaticamente via trigger)
CREATE OR REPLACE FUNCTION rpc_seat_assign(
  p_tenant_id uuid,
  p_user_id   uuid,
  p_assigned_by uuid DEFAULT NULL
) RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_id uuid;
BEGIN
  INSERT INTO seat_assignments (tenant_id, user_id, assigned_by)
  VALUES (p_tenant_id, p_user_id, p_assigned_by)
  ON CONFLICT (tenant_id, user_id) DO UPDATE
    SET revoked_at = NULL, assigned_by = EXCLUDED.assigned_by
  RETURNING id INTO v_id;

  RETURN v_id;
END;
$$;

-- 5.6 Status de quota (UI billing)
CREATE OR REPLACE FUNCTION rpc_quota_status(p_tenant_id uuid)
RETURNS TABLE (
  resource    text,
  current_usage int,
  hard_limit  int,
  soft_warn_at int,
  pct_used    numeric,
  status      text
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN QUERY
  SELECT
    q.resource,
    q.current_usage,
    q.hard_limit,
    q.soft_warn_at,
    CASE WHEN q.hard_limit IS NULL OR q.hard_limit = 0 THEN 0::numeric
         ELSE ROUND((q.current_usage::numeric / q.hard_limit) * 100, 1) END,
    CASE
      WHEN q.hard_limit IS NULL THEN 'unlimited'
      WHEN q.current_usage >= q.hard_limit THEN 'exhausted'
      WHEN q.soft_warn_at IS NOT NULL AND q.current_usage >= q.soft_warn_at THEN 'warn'
      ELSE 'ok'
    END
  FROM tenant_quotas q
  WHERE q.tenant_id = p_tenant_id
  ORDER BY q.resource;
END;
$$;

-- ============================================================================
-- 6. SEED · Planos padrão
-- ============================================================================

INSERT INTO plans (code, name, description, price_brl_cents, per_seat_brl_cents,
                   interval, included_seats, max_seats, features) VALUES
  ('starter',
   'Starter',
   'Para pequenas empresas (até 25 pessoas) que querem digitalizar RH sem complicação.',
   29900,        -- R$ 299/mês
   1900,         -- R$ 19 por seat adicional
   'monthly',
   25,
   50,
   jsonb_build_object(
     'modules', jsonb_build_array('pessoas','atestados','ferias','avaliacao_basica','comunicados'),
     'webhooks_max', 2,
     'storage_gb', 5,
     'api_calls_month', 10000,
     'sso', false,
     'mfa_required', false,
     'support', 'email_business_hours'
   )
  ),
  ('pro',
   'Pro',
   'Para empresas em crescimento (até 200 pessoas) com necessidade de relatórios e workflows.',
   79900,        -- R$ 799/mês
   1500,         -- R$ 15 por seat adicional
   'monthly',
   100,
   500,
   jsonb_build_object(
     'modules', jsonb_build_array('pessoas','atestados','ferias','avaliacao','oneonones','okrs','pdi','clima','relatorios','comunicados','movimentacoes'),
     'webhooks_max', 10,
     'storage_gb', 50,
     'api_calls_month', 100000,
     'sso', false,
     'mfa_required', true,
     'support', 'email_priority + chat'
   )
  ),
  ('enterprise',
   'Enterprise',
   'Para organizações maduras (200+ pessoas), com SSO, SLA dedicado e Customer Success.',
   249900,       -- R$ 2.499/mês (preço base)
   1200,         -- R$ 12 por seat adicional
   'monthly',
   300,
   NULL,
   jsonb_build_object(
     'modules', jsonb_build_array('*'),    -- todos
     'webhooks_max', 50,
     'storage_gb', 500,
     'api_calls_month', 1000000,
     'sso', true,
     'mfa_required', true,
     'audit_log_extended', true,
     'support', 'cs_dedicado + sla_99.9'
   )
  )
ON CONFLICT (code) DO NOTHING;

-- ============================================================================
-- 7. RLS POLICIES
-- ============================================================================

DO $$
DECLARE
  t text;
  tenant_tables text[] := ARRAY[
    'tenant_onboarding','subscriptions','payment_methods','invoices',
    'tenant_quotas','quota_usage_log','seat_assignments'
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

-- Plans são públicos (todos veem catálogo)
ALTER TABLE plans ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS plans_public_read ON plans;
CREATE POLICY plans_public_read ON plans
  FOR SELECT USING (visible = true);

-- ============================================================================
-- 8. GRANTs
-- ============================================================================

GRANT SELECT ON plans TO anon, authenticated;
GRANT ALL ON plans TO service_role;

DO $$
DECLARE
  t text;
BEGIN
  FOREACH t IN ARRAY ARRAY[
    'tenant_onboarding','subscriptions','payment_methods','invoices',
    'tenant_quotas','quota_usage_log','seat_assignments'
  ] LOOP
    EXECUTE format('GRANT SELECT ON %I TO authenticated', t);
    EXECUTE format('GRANT ALL ON %I TO service_role', t);
  END LOOP;
END $$;

GRANT EXECUTE ON FUNCTION rpc_onboarding_advance(uuid, int, jsonb) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION rpc_onboarding_skip(uuid, int) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION rpc_onboarding_status(uuid) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION rpc_onboarding_mark_abandoned() TO service_role;
GRANT EXECUTE ON FUNCTION rpc_seat_assign(uuid, uuid, uuid) TO service_role;
GRANT EXECUTE ON FUNCTION rpc_quota_status(uuid) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION fn_quota_increment(uuid, text, int, text, uuid) TO service_role;

COMMIT;

-- ============================================================================
-- Fim do schema v12
-- ============================================================================

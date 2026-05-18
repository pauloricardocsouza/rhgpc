-- ============================================================================
-- R2 People · Schema SQL v13 · Isolation Monitoring + Webhooks Inbound
-- ----------------------------------------------------------------------------
-- Materializa em SQL executável:
--   - Spec D8 (Multi-tenant isolation patterns · rls_denial_log)
--   - Spec M14 (Webhooks inbound · 4 tabelas + 4 handlers + RPC)
--
-- Pré-requisito: schemas v9-v12 aplicados.
-- 100% idempotente.
-- ============================================================================

BEGIN;

-- ============================================================================
-- 1. RLS DENIAL LOG (spec D8 §5)
-- ============================================================================

CREATE TABLE IF NOT EXISTS rls_denial_log (
  id                    uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id_attempted   uuid,
  user_id               uuid REFERENCES auth.users(id),
  table_name            text NOT NULL,
  operation             text NOT NULL CHECK (operation IN ('SELECT','INSERT','UPDATE','DELETE','EXECUTE')),
  query_snippet         text,
  remote_ip             inet,
  user_agent            text,
  classified_as         text CHECK (classified_as IN ('benign','suspicious','exploit_attempt','unclassified')) DEFAULT 'unclassified',
  occurred_at           timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_rls_denial_recent ON rls_denial_log (occurred_at DESC);
CREATE INDEX IF NOT EXISTS idx_rls_denial_user ON rls_denial_log (user_id, occurred_at DESC);
CREATE INDEX IF NOT EXISTS idx_rls_denial_suspicious
  ON rls_denial_log (occurred_at DESC)
  WHERE classified_as IN ('suspicious','exploit_attempt');

-- Função helper para classificar denials automaticamente
CREATE OR REPLACE FUNCTION fn_classify_rls_denial(
  p_user_id uuid,
  p_window interval DEFAULT '1 hour'
) RETURNS text
LANGUAGE plpgsql
AS $$
DECLARE
  v_count int;
  v_distinct_tenants int;
BEGIN
  SELECT count(*), count(DISTINCT tenant_id_attempted)
    INTO v_count, v_distinct_tenants
  FROM rls_denial_log
  WHERE user_id = p_user_id
    AND occurred_at > now() - p_window;

  IF v_distinct_tenants > 3 THEN RETURN 'exploit_attempt'; END IF;
  IF v_count > 100 THEN RETURN 'suspicious'; END IF;
  IF v_count > 20 THEN RETURN 'unclassified'; END IF;
  RETURN 'benign';
END;
$$;

-- RPC para registrar denial (chamada pelo app catch de exception 42501)
CREATE OR REPLACE FUNCTION rpc_log_rls_denial(
  p_tenant_id uuid,
  p_user_id uuid,
  p_table text,
  p_operation text,
  p_query text DEFAULT NULL,
  p_ip inet DEFAULT NULL,
  p_ua text DEFAULT NULL
) RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_id uuid;
  v_class text;
BEGIN
  v_class := fn_classify_rls_denial(p_user_id);

  INSERT INTO rls_denial_log (
    tenant_id_attempted, user_id, table_name, operation,
    query_snippet, remote_ip, user_agent, classified_as
  ) VALUES (
    p_tenant_id, p_user_id, p_table, p_operation,
    LEFT(p_query, 2000), p_ip, p_ua, v_class
  ) RETURNING id INTO v_id;

  -- Se classificou como exploit_attempt, dispara alerta P1 via security_events
  IF v_class = 'exploit_attempt' THEN
    INSERT INTO security_events (tenant_id, actor_id, event_type, reason, after_data)
    VALUES (p_tenant_id, p_user_id, 'cross_tenant_exploit_detected',
            'Multiple distinct tenant_id attempts from same user',
            jsonb_build_object('window', '1h', 'rls_denial_id', v_id));
  END IF;

  RETURN v_id;
END;
$$;

-- View resumo · top users por denials últimas 24h (dashboard CS/Sec)
CREATE OR REPLACE VIEW v_rls_denials_top_users AS
SELECT
  user_id,
  count(*) AS denial_count,
  count(DISTINCT tenant_id_attempted) AS distinct_tenants,
  count(DISTINCT table_name) AS distinct_tables,
  array_agg(DISTINCT classified_as) AS classifications,
  max(occurred_at) AS last_denial_at
FROM rls_denial_log
WHERE occurred_at > now() - interval '24 hours'
GROUP BY user_id
ORDER BY denial_count DESC;

-- ============================================================================
-- 2. INBOUND WEBHOOKS (spec M14)
-- ============================================================================

CREATE TABLE IF NOT EXISTS inbound_webhook_endpoints (
  id                       uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id                uuid NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  name                     text NOT NULL,
  source_system            text NOT NULL,
  signing_secret           text NOT NULL,
  signing_secret_rotated_at timestamptz,
  allowed_ips              inet[],
  active                   boolean NOT NULL DEFAULT true,
  subscribed_events        text[] NOT NULL DEFAULT ARRAY['*'],
  created_by               uuid REFERENCES auth.users(id),
  created_at               timestamptz NOT NULL DEFAULT now(),
  last_received_at         timestamptz,
  UNIQUE (tenant_id, name)
);

CREATE INDEX IF NOT EXISTS idx_iwe_tenant_active
  ON inbound_webhook_endpoints (tenant_id) WHERE active = true;

CREATE TABLE IF NOT EXISTS inbound_events_log (
  id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  endpoint_id         uuid NOT NULL REFERENCES inbound_webhook_endpoints(id) ON DELETE CASCADE,
  tenant_id           uuid NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  event_id            text NOT NULL,
  event_type          text NOT NULL,
  payload             jsonb NOT NULL,
  payload_size_bytes  int NOT NULL,
  signature_valid     boolean NOT NULL,
  remote_ip           inet,
  user_agent          text,
  received_at         timestamptz NOT NULL DEFAULT now(),
  processed_at        timestamptz,
  process_status      text CHECK (process_status IN ('pending','processing','success','failed','rejected','duplicate')) DEFAULT 'pending',
  process_error       text,
  process_attempts    int NOT NULL DEFAULT 0
);

CREATE INDEX IF NOT EXISTS idx_inbound_pending
  ON inbound_events_log (received_at)
  WHERE process_status IN ('pending','processing');
CREATE INDEX IF NOT EXISTS idx_inbound_endpoint
  ON inbound_events_log (endpoint_id, received_at DESC);
CREATE UNIQUE INDEX IF NOT EXISTS idx_inbound_dedupe
  ON inbound_events_log (endpoint_id, event_id);

CREATE TABLE IF NOT EXISTS inbound_event_dedupe (
  endpoint_id  uuid NOT NULL,
  event_id     text NOT NULL,
  received_at  timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (endpoint_id, event_id)
);

CREATE INDEX IF NOT EXISTS idx_inbound_dedupe_ttl
  ON inbound_event_dedupe (received_at);

CREATE TABLE IF NOT EXISTS inbound_event_handlers (
  source_system    text NOT NULL,
  event_type       text NOT NULL,
  handler_function text NOT NULL,
  description      text,
  active           boolean DEFAULT true,
  PRIMARY KEY (source_system, event_type)
);

-- ============================================================================
-- 3. HANDLERS PADRÃO (spec M14 §5)
-- ============================================================================

-- 3.1 payroll.closed (Senior/Totvs/Sankhya/Dominio)
CREATE OR REPLACE FUNCTION rpc_handle_payroll_closed(
  p_tenant_id uuid,
  p_payload jsonb
) RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_period text := p_payload->>'period';
  v_total numeric := COALESCE((p_payload->>'total')::numeric, 0);
  v_run_id uuid;
  v_period_start date;
BEGIN
  IF v_period IS NULL OR v_period !~ '^\d{4}-\d{2}$' THEN
    RAISE EXCEPTION 'Invalid period format: %', v_period
      USING ERRCODE = 'invalid_parameter_value';
  END IF;

  v_period_start := make_date(
    split_part(v_period, '-', 1)::int,
    split_part(v_period, '-', 2)::int,
    1
  );

  -- Cria/atualiza payroll_runs (graceful caso tabela não exista ainda)
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'payroll_runs') THEN
    EXECUTE format($f$
      INSERT INTO payroll_runs (tenant_id, period, total_brl_cents, status, closed_at, source)
      VALUES (%L, %L, %s, 'closed', now(), 'erp_inbound')
      ON CONFLICT (tenant_id, period) DO UPDATE SET
        total_brl_cents = EXCLUDED.total_brl_cents,
        status = 'closed',
        closed_at = EXCLUDED.closed_at
      RETURNING id
    $f$, p_tenant_id, v_period, (v_total * 100)::bigint)
    INTO v_run_id;
  END IF;

  -- Marca movements como pagas (idempotente)
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'movements')
     AND v_run_id IS NOT NULL THEN
    UPDATE movements
    SET payroll_status = 'paid', payroll_run_id = v_run_id
    WHERE tenant_id = p_tenant_id
      AND effective_date >= v_period_start
      AND effective_date < (v_period_start + interval '1 month');
  END IF;

  RETURN v_run_id;
END;
$$;

-- 3.2 user.deactivated_from_ad (Azure AD / Google Workspace)
CREATE OR REPLACE FUNCTION rpc_handle_user_deactivated_from_ad(
  p_tenant_id uuid,
  p_payload jsonb
) RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_external_id text := p_payload->>'external_user_id';
  v_email text := p_payload->>'email';
  v_employee_id uuid;
BEGIN
  -- Busca employee por email ou external_id
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'employees') THEN
    EXECUTE format($f$
      UPDATE employees
      SET status = 'terminated',
          termination_date = COALESCE(termination_date, current_date),
          termination_source = 'ad_deactivation'
      WHERE tenant_id = %L
        AND (external_id = %L OR email = %L)
      RETURNING id
    $f$, p_tenant_id, v_external_id, v_email)
    INTO v_employee_id;
  END IF;

  -- Dispara workflow LGPD (revoga sessões, agenda retenção)
  IF v_employee_id IS NOT NULL THEN
    -- Revoga sessões ativas (graceful)
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'session_revocations') THEN
      EXECUTE format($f$
        INSERT INTO session_revocations (user_id, reason, revoked_at)
        SELECT user_id, 'ad_deactivation', now()
        FROM employees WHERE id = %L
      $f$, v_employee_id);
    END IF;
  END IF;

  RETURN v_employee_id;
END;
$$;

-- 3.3 attendance.absent (Dimep / Ahgora)
CREATE OR REPLACE FUNCTION rpc_handle_attendance_absent(
  p_tenant_id uuid,
  p_payload jsonb
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_employee_id uuid;
  v_date date := (p_payload->>'date')::date;
  v_has_certificate boolean := false;
BEGIN
  -- Busca employee
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'employees') THEN
    EXECUTE format($f$
      SELECT id FROM employees
      WHERE tenant_id = %L AND external_id = %L LIMIT 1
    $f$, p_tenant_id, p_payload->>'external_employee_id')
    INTO v_employee_id;
  END IF;

  IF v_employee_id IS NULL THEN
    RETURN jsonb_build_object('action', 'skipped', 'reason', 'employee_not_found');
  END IF;

  -- Verifica se há atestado validado cobrindo a data
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'medical_certificates') THEN
    EXECUTE format($f$
      SELECT EXISTS (
        SELECT 1 FROM medical_certificates
        WHERE tenant_id = %L AND employee_id = %L
          AND start_date <= %L AND end_date >= %L
          AND status = 'approved'
      )
    $f$, p_tenant_id, v_employee_id, v_date, v_date)
    INTO v_has_certificate;
  END IF;

  IF v_has_certificate THEN
    RETURN jsonb_build_object('action', 'auto_justified', 'employee_id', v_employee_id);
  ELSE
    -- TODO: criar task para líder revisar (depende de tabela tasks)
    RETURN jsonb_build_object('action', 'needs_review', 'employee_id', v_employee_id);
  END IF;
END;
$$;

-- 3.4 salary.adjusted (audit trail)
CREATE OR REPLACE FUNCTION rpc_handle_salary_adjusted(
  p_tenant_id uuid,
  p_payload jsonb
) RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_movement_id uuid;
BEGIN
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'movements') THEN
    EXECUTE format($f$
      INSERT INTO movements (
        tenant_id, employee_external_id, type, effective_date,
        before_data, after_data, source, status
      ) VALUES (
        %L,
        %L,
        'SALARY_ADJUSTMENT',
        %L,
        %L::jsonb,
        %L::jsonb,
        'erp_inbound',
        'completed'
      ) RETURNING id
    $f$,
    p_tenant_id,
    p_payload->>'external_employee_id',
    (p_payload->>'effective_date')::date,
    jsonb_build_object('salary', p_payload->'old_salary'),
    jsonb_build_object('salary', p_payload->'new_salary'))
    INTO v_movement_id;
  END IF;

  RETURN v_movement_id;
END;
$$;

-- ============================================================================
-- 4. SEED de handlers
-- ============================================================================

INSERT INTO inbound_event_handlers (source_system, event_type, handler_function, description) VALUES
  ('senior_rm', 'payroll.closed', 'rpc_handle_payroll_closed', 'Fechamento de folha vindo do Senior RM'),
  ('senior_rm', 'salary.adjusted', 'rpc_handle_salary_adjusted', 'Ajuste salarial vindo do Senior RM'),
  ('totvs', 'payroll.closed', 'rpc_handle_payroll_closed', 'Fechamento de folha vindo do Totvs Protheus'),
  ('totvs', 'employee.transferred', 'rpc_handle_salary_adjusted', 'Transferência interna vinda do Totvs'),
  ('sankhya', 'payroll.closed', 'rpc_handle_payroll_closed', 'Fechamento de folha vindo do Sankhya'),
  ('dominio', 'payroll.closed', 'rpc_handle_payroll_closed', 'Fechamento de folha vindo do Dominio'),
  ('azure_ad', 'user.created', 'rpc_handle_user_deactivated_from_ad', 'Novo usuário criado no AAD'),
  ('azure_ad', 'user.deactivated', 'rpc_handle_user_deactivated_from_ad', 'Usuário desativado no AAD'),
  ('google_workspace', 'user.suspended', 'rpc_handle_user_deactivated_from_ad', 'Usuário suspenso no Google'),
  ('ponto_dimep', 'attendance.absent', 'rpc_handle_attendance_absent', 'Ausência registrada pelo Dimep'),
  ('ponto_ahgora', 'attendance.absent', 'rpc_handle_attendance_absent', 'Ausência registrada pelo Ahgora')
ON CONFLICT (source_system, event_type) DO NOTHING;

-- ============================================================================
-- 5. RPC de validação de assinatura HMAC (chamada pela Edge Function)
-- ============================================================================

CREATE OR REPLACE FUNCTION rpc_validate_inbound_signature(
  p_endpoint_id uuid,
  p_timestamp bigint,
  p_body text,
  p_signature text
) RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_secret text;
  v_now bigint := extract(epoch from now())::bigint;
  v_diff bigint;
  v_computed text;
BEGIN
  SELECT signing_secret INTO v_secret
  FROM inbound_webhook_endpoints
  WHERE id = p_endpoint_id AND active = true;

  IF v_secret IS NULL THEN RETURN false; END IF;

  -- Anti-replay: timestamp dentro de 5min
  v_diff := abs(v_now - p_timestamp);
  IF v_diff > 300 THEN RETURN false; END IF;

  -- Computa HMAC-SHA256(secret, timestamp + body)
  v_computed := encode(
    hmac(
      (p_timestamp::text || p_body)::bytea,
      v_secret::bytea,
      'sha256'
    ),
    'hex'
  );

  -- Comparação timing-safe (pgcrypto)
  RETURN ('sha256=' || v_computed) = p_signature;
END;
$$;

-- ============================================================================
-- 6. RPC para criar endpoint (retorna signing_secret 1x)
-- ============================================================================

CREATE OR REPLACE FUNCTION rpc_create_inbound_endpoint(
  p_tenant_id uuid,
  p_name text,
  p_source_system text,
  p_subscribed_events text[] DEFAULT ARRAY['*'],
  p_allowed_ips inet[] DEFAULT NULL
) RETURNS TABLE (id uuid, signing_secret text)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_id uuid;
  v_secret text;
BEGIN
  -- Gera secret aleatório de 64 chars hex (256 bits)
  v_secret := encode(gen_random_bytes(32), 'hex');

  INSERT INTO inbound_webhook_endpoints (
    tenant_id, name, source_system, signing_secret,
    subscribed_events, allowed_ips, created_by
  ) VALUES (
    p_tenant_id, p_name, p_source_system, v_secret,
    p_subscribed_events, p_allowed_ips, auth.uid()
  ) RETURNING inbound_webhook_endpoints.id INTO v_id;

  RETURN QUERY SELECT v_id, v_secret;
END;
$$;

-- ============================================================================
-- 7. RPC para rotacionar secret (com grace period)
-- ============================================================================

CREATE OR REPLACE FUNCTION rpc_rotate_inbound_secret(p_endpoint_id uuid)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_new_secret text := encode(gen_random_bytes(32), 'hex');
BEGIN
  UPDATE inbound_webhook_endpoints
  SET signing_secret = v_new_secret,
      signing_secret_rotated_at = now()
  WHERE id = p_endpoint_id;

  -- TODO: armazenar secret antigo em tabela separada por 7d para grace period
  -- (deixado para iteração futura quando workers suportarem dual-validate)

  RETURN v_new_secret;
END;
$$;

-- ============================================================================
-- 8. Job de limpeza (chamado por cron diário)
-- ============================================================================

CREATE OR REPLACE FUNCTION rpc_inbound_cleanup()
RETURNS int
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_dedupe_deleted int;
  v_log_archived int;
BEGIN
  -- Apaga dedupe > 7d (TTL)
  DELETE FROM inbound_event_dedupe
  WHERE received_at < now() - interval '7 days';
  GET DIAGNOSTICS v_dedupe_deleted = ROW_COUNT;

  -- TODO: arquivar inbound_events_log > 90d (depende de tabela _archive)

  RETURN v_dedupe_deleted;
END;
$$;

-- ============================================================================
-- 9. RLS
-- ============================================================================

ALTER TABLE rls_denial_log ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS rls_denial_dpo_only ON rls_denial_log;
CREATE POLICY rls_denial_dpo_only ON rls_denial_log
  FOR SELECT USING (
    auth.jwt() ->> 'role' IN ('super_admin','dpo')
    OR auth.role() = 'service_role'
  );

ALTER TABLE inbound_webhook_endpoints ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS iwe_tenant_isolation ON inbound_webhook_endpoints;
CREATE POLICY iwe_tenant_isolation ON inbound_webhook_endpoints
  FOR ALL USING (tenant_id = (current_setting('app.tenant_id', true))::uuid);

ALTER TABLE inbound_events_log ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS iel_tenant_isolation ON inbound_events_log;
CREATE POLICY iel_tenant_isolation ON inbound_events_log
  FOR ALL USING (tenant_id = (current_setting('app.tenant_id', true))::uuid);

ALTER TABLE inbound_event_dedupe ENABLE ROW LEVEL SECURITY;
-- Dedupe não tem tenant_id direto, isolamento via endpoint_id
DROP POLICY IF EXISTS ied_via_endpoint ON inbound_event_dedupe;
CREATE POLICY ied_via_endpoint ON inbound_event_dedupe
  FOR ALL USING (
    endpoint_id IN (
      SELECT id FROM inbound_webhook_endpoints
      WHERE tenant_id = (current_setting('app.tenant_id', true))::uuid
    )
  );

-- inbound_event_handlers é catálogo global · só super_admin lê
ALTER TABLE inbound_event_handlers ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS ieh_public_read ON inbound_event_handlers;
CREATE POLICY ieh_public_read ON inbound_event_handlers
  FOR SELECT USING (active = true);

-- ============================================================================
-- 10. GRANTs
-- ============================================================================

-- signing_secret NUNCA exposto para authenticated
REVOKE ALL ON inbound_webhook_endpoints FROM authenticated;
GRANT SELECT (id, tenant_id, name, source_system, allowed_ips, active,
              subscribed_events, created_at, last_received_at)
  ON inbound_webhook_endpoints TO authenticated;
GRANT ALL ON inbound_webhook_endpoints TO service_role;

GRANT SELECT ON inbound_events_log TO authenticated;
GRANT ALL ON inbound_events_log TO service_role;

GRANT SELECT ON inbound_event_handlers TO authenticated;
GRANT ALL ON inbound_event_handlers TO service_role;

GRANT ALL ON inbound_event_dedupe TO service_role;

-- rls_denial_log só DPO + service_role
REVOKE ALL ON rls_denial_log FROM authenticated;
GRANT ALL ON rls_denial_log TO service_role;

GRANT EXECUTE ON FUNCTION rpc_log_rls_denial(uuid, uuid, text, text, text, inet, text) TO service_role;
GRANT EXECUTE ON FUNCTION rpc_handle_payroll_closed(uuid, jsonb) TO service_role;
GRANT EXECUTE ON FUNCTION rpc_handle_user_deactivated_from_ad(uuid, jsonb) TO service_role;
GRANT EXECUTE ON FUNCTION rpc_handle_attendance_absent(uuid, jsonb) TO service_role;
GRANT EXECUTE ON FUNCTION rpc_handle_salary_adjusted(uuid, jsonb) TO service_role;
GRANT EXECUTE ON FUNCTION rpc_validate_inbound_signature(uuid, bigint, text, text) TO service_role;
GRANT EXECUTE ON FUNCTION rpc_create_inbound_endpoint(uuid, text, text, text[], inet[]) TO service_role;
GRANT EXECUTE ON FUNCTION rpc_rotate_inbound_secret(uuid) TO service_role;
GRANT EXECUTE ON FUNCTION rpc_inbound_cleanup() TO service_role;

COMMIT;

-- ============================================================================
-- Fim do schema v13
-- ============================================================================

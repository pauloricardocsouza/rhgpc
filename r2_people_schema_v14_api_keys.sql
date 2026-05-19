-- ============================================================================
-- R2 People · Schema SQL v14 · API Pública (API keys + idempotency + usage)
-- ----------------------------------------------------------------------------
-- Materializa em SQL executável a spec D9:
--   1. api_keys (bcrypt hash + key_prefix lookup + scopes + allowed_ips + expiry)
--   2. idempotency_keys (TTL 24h por tenant)
--   3. api_usage_log (audit + billing per-request, particionado por mês recomendado)
--   4. RPCs: rpc_create_api_key, rpc_validate_api_key, rpc_revoke_api_key,
--            rpc_idempotency_check, rpc_idempotency_save, rpc_api_log_request
--   5. View v_api_keys_safe (sem key_hash, para UI)
--   6. RLS + GRANTs granulares (key_hash NUNCA exposto para authenticated)
--   7. Job de cleanup TTL idempotency
--
-- Pré-requisito: pgcrypto extension (gen_random_bytes, crypt, hmac).
-- 100% idempotente.
-- ============================================================================

BEGIN;

-- Garante pgcrypto (já vem com Supabase)
CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- ============================================================================
-- 1. API KEYS
-- ============================================================================

CREATE TABLE IF NOT EXISTS api_keys (
  id                       uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id                uuid NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  name                     text NOT NULL,
  key_hash                 text NOT NULL,                  -- bcrypt cost 12
  key_prefix               text NOT NULL,                  -- 'r2_live_5b8a' (12 chars)
  mode                     text NOT NULL CHECK (mode IN ('live','test')) DEFAULT 'live',
  scopes                   text[] NOT NULL DEFAULT ARRAY['read:*'],
  allowed_ips              inet[],
  rate_limit_override      int,                            -- req/min custom
  created_by               uuid REFERENCES auth.users(id),
  created_at               timestamptz NOT NULL DEFAULT now(),
  expires_at               timestamptz,
  revoked_at               timestamptz,
  revoked_by               uuid REFERENCES auth.users(id),
  revoke_reason            text,
  last_used_at             timestamptz,
  last_used_ip             inet,
  UNIQUE (tenant_id, name)
);

CREATE INDEX IF NOT EXISTS idx_api_keys_active
  ON api_keys (tenant_id, key_prefix)
  WHERE revoked_at IS NULL;

CREATE INDEX IF NOT EXISTS idx_api_keys_expiring_soon
  ON api_keys (expires_at)
  WHERE expires_at IS NOT NULL AND revoked_at IS NULL;

CREATE INDEX IF NOT EXISTS idx_api_keys_prefix
  ON api_keys (key_prefix)
  WHERE revoked_at IS NULL;

-- ============================================================================
-- 2. IDEMPOTENCY KEYS
-- ============================================================================

CREATE TABLE IF NOT EXISTS idempotency_keys (
  tenant_id        uuid NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  key              text NOT NULL,
  request_hash     text NOT NULL,                          -- sha256 hex do body
  response_status  int  NOT NULL,
  response_body    jsonb NOT NULL,
  created_at       timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (tenant_id, key)
);

CREATE INDEX IF NOT EXISTS idx_idempotency_ttl
  ON idempotency_keys (created_at);

-- ============================================================================
-- 3. API USAGE LOG
-- ============================================================================

CREATE TABLE IF NOT EXISTS api_usage_log (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id       uuid NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  api_key_id      uuid REFERENCES api_keys(id) ON DELETE SET NULL,
  user_id         uuid REFERENCES auth.users(id),
  method          text NOT NULL,
  path            text NOT NULL,
  status          int  NOT NULL,
  duration_ms     int,
  request_id      text,
  remote_ip       inet,
  user_agent      text,
  occurred_at     timestamptz NOT NULL DEFAULT now()
);

-- Particionamento mensal recomendado em prod (deixar como índice no MVP)
CREATE INDEX IF NOT EXISTS idx_api_usage_tenant_recent
  ON api_usage_log (tenant_id, occurred_at DESC);

CREATE INDEX IF NOT EXISTS idx_api_usage_key
  ON api_usage_log (api_key_id, occurred_at DESC);

CREATE INDEX IF NOT EXISTS idx_api_usage_errors
  ON api_usage_log (occurred_at DESC)
  WHERE status >= 400;

-- ============================================================================
-- 4. VIEW SAFE (sem key_hash, para UI)
-- ============================================================================

CREATE OR REPLACE VIEW v_api_keys_safe AS
SELECT
  id, tenant_id, name, key_prefix, mode, scopes, allowed_ips,
  rate_limit_override, created_by, created_at, expires_at,
  revoked_at, revoked_by, revoke_reason,
  last_used_at, last_used_ip,
  CASE
    WHEN revoked_at IS NOT NULL THEN 'revoked'
    WHEN expires_at IS NOT NULL AND expires_at < now() THEN 'expired'
    ELSE 'active'
  END AS status
FROM api_keys;

-- ============================================================================
-- 5. RPCs
-- ============================================================================

-- 5.1 Criar nova key (retorna chave 1x em texto claro)
CREATE OR REPLACE FUNCTION rpc_create_api_key(
  p_tenant_id    uuid,
  p_name         text,
  p_mode         text DEFAULT 'live',
  p_scopes       text[] DEFAULT ARRAY['read:*'],
  p_allowed_ips  inet[] DEFAULT NULL,
  p_expires_at   timestamptz DEFAULT NULL
) RETURNS TABLE (id uuid, api_key text)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_random text;
  v_full_key text;
  v_prefix text;
  v_hash text;
  v_id uuid;
BEGIN
  -- Valida mode
  IF p_mode NOT IN ('live','test') THEN
    RAISE EXCEPTION 'Invalid mode: %', p_mode USING ERRCODE = 'invalid_parameter_value';
  END IF;

  -- Gera key aleatória de 64 chars hex (256 bits de entropia)
  v_random := encode(gen_random_bytes(32), 'hex');
  v_full_key := 'r2_' || p_mode || '_' || v_random;
  v_prefix := substring(v_full_key from 1 for 12);

  -- bcrypt cost 12 (~250ms · OK para criação infrequente)
  v_hash := crypt(v_full_key, gen_salt('bf', 12));

  INSERT INTO api_keys (
    tenant_id, name, key_hash, key_prefix, mode, scopes,
    allowed_ips, expires_at, created_by
  ) VALUES (
    p_tenant_id, p_name, v_hash, v_prefix, p_mode, p_scopes,
    p_allowed_ips, p_expires_at, auth.uid()
  ) RETURNING api_keys.id INTO v_id;

  RETURN QUERY SELECT v_id, v_full_key;
END;
$$;

-- 5.2 Validar key (chamada por cada request da Edge Function)
CREATE OR REPLACE FUNCTION rpc_validate_api_key(p_key text)
RETURNS TABLE (
  tenant_id uuid,
  key_id    uuid,
  scopes    text[],
  mode      text,
  rate_limit_override int
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_prefix text;
  v_row    api_keys;
BEGIN
  -- Sanity check do formato
  IF p_key !~ '^r2_(live|test)_[0-9a-f]{64}$' THEN
    RETURN;
  END IF;

  v_prefix := substring(p_key from 1 for 12);

  -- Lookup por prefix (indexado · rápido)
  SELECT * INTO v_row FROM api_keys
  WHERE key_prefix = v_prefix
    AND revoked_at IS NULL
    AND (expires_at IS NULL OR expires_at > now());

  IF NOT FOUND THEN RETURN; END IF;

  -- Verifica bcrypt (~50-100ms, OK em cache de validação)
  IF crypt(p_key, v_row.key_hash) = v_row.key_hash THEN
    -- Atualiza last_used_* assíncrono (não bloqueia request)
    PERFORM pg_notify(
      'api_key_used',
      json_build_object('id', v_row.id, 'at', now())::text
    );

    RETURN QUERY SELECT
      v_row.tenant_id,
      v_row.id,
      v_row.scopes,
      v_row.mode,
      v_row.rate_limit_override;
  END IF;
END;
$$;

-- 5.3 Revogar key
CREATE OR REPLACE FUNCTION rpc_revoke_api_key(
  p_key_id uuid,
  p_reason text DEFAULT NULL
) RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  UPDATE api_keys
  SET revoked_at = now(),
      revoked_by = auth.uid(),
      revoke_reason = COALESCE(p_reason, 'manual_revoke')
  WHERE id = p_key_id
    AND revoked_at IS NULL;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'API key % not found or already revoked', p_key_id;
  END IF;
END;
$$;

-- 5.4 Idempotency check
CREATE OR REPLACE FUNCTION rpc_idempotency_check(
  p_tenant_id    uuid,
  p_key          text,
  p_request_hash text
) RETURNS TABLE (status int, body jsonb, conflict boolean)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_row idempotency_keys;
BEGIN
  SELECT * INTO v_row FROM idempotency_keys
  WHERE tenant_id = p_tenant_id AND key = p_key
    AND created_at > now() - interval '24 hours';

  IF NOT FOUND THEN
    RETURN QUERY SELECT NULL::int, NULL::jsonb, false;
    RETURN;
  END IF;

  -- Mesma key + body diferente = conflict (422)
  IF v_row.request_hash != p_request_hash THEN
    RETURN QUERY SELECT 422, NULL::jsonb, true;
    RETURN;
  END IF;

  -- Mesma key + mesmo body = retorna resposta cached
  RETURN QUERY SELECT v_row.response_status, v_row.response_body, false;
END;
$$;

-- 5.5 Idempotency save
CREATE OR REPLACE FUNCTION rpc_idempotency_save(
  p_tenant_id      uuid,
  p_key            text,
  p_request_hash   text,
  p_response_status int,
  p_response_body  jsonb
) RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  INSERT INTO idempotency_keys (
    tenant_id, key, request_hash, response_status, response_body
  ) VALUES (
    p_tenant_id, p_key, p_request_hash, p_response_status, p_response_body
  )
  ON CONFLICT (tenant_id, key) DO NOTHING;  -- mantém o primeiro write
END;
$$;

-- 5.6 Log request (chamado assíncrono no fim de cada request)
CREATE OR REPLACE FUNCTION rpc_api_log_request(
  p_tenant_id    uuid,
  p_api_key_id   uuid,
  p_user_id      uuid,
  p_method       text,
  p_path         text,
  p_status       int,
  p_duration_ms  int,
  p_request_id   text,
  p_remote_ip    inet,
  p_user_agent   text
) RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  INSERT INTO api_usage_log (
    tenant_id, api_key_id, user_id, method, path, status,
    duration_ms, request_id, remote_ip, user_agent
  ) VALUES (
    p_tenant_id, p_api_key_id, p_user_id, p_method, p_path, p_status,
    p_duration_ms, p_request_id, p_remote_ip, p_user_agent
  );
END;
$$;

-- 5.7 Cleanup idempotency TTL (cron diário)
CREATE OR REPLACE FUNCTION rpc_idempotency_cleanup()
RETURNS int
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE v_count int;
BEGIN
  DELETE FROM idempotency_keys
  WHERE created_at < now() - interval '24 hours';
  GET DIAGNOSTICS v_count = ROW_COUNT;
  RETURN v_count;
END;
$$;

-- 5.8 Stats por endpoint (para UI API Console)
CREATE OR REPLACE FUNCTION rpc_api_usage_stats(
  p_tenant_id uuid,
  p_days      int DEFAULT 7
) RETURNS TABLE (
  endpoint    text,
  request_count bigint,
  p50_ms      numeric,
  p95_ms      numeric,
  error_rate  numeric
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN QUERY
  SELECT
    method || ' ' || path AS endpoint,
    count(*) AS request_count,
    percentile_cont(0.5) WITHIN GROUP (ORDER BY duration_ms)::numeric AS p50_ms,
    percentile_cont(0.95) WITHIN GROUP (ORDER BY duration_ms)::numeric AS p95_ms,
    ROUND(
      (count(*) FILTER (WHERE status >= 400))::numeric / NULLIF(count(*), 0) * 100,
      2
    ) AS error_rate
  FROM api_usage_log
  WHERE tenant_id = p_tenant_id
    AND occurred_at > now() - (p_days || ' days')::interval
  GROUP BY method, path
  ORDER BY request_count DESC
  LIMIT 50;
END;
$$;

-- ============================================================================
-- 6. RLS POLICIES
-- ============================================================================

ALTER TABLE api_keys ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS api_keys_tenant_isolation ON api_keys;
CREATE POLICY api_keys_tenant_isolation ON api_keys
  FOR ALL
  USING (tenant_id = (current_setting('app.tenant_id', true))::uuid);

ALTER TABLE idempotency_keys ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS idempotency_tenant_isolation ON idempotency_keys;
CREATE POLICY idempotency_tenant_isolation ON idempotency_keys
  FOR ALL
  USING (tenant_id = (current_setting('app.tenant_id', true))::uuid);

ALTER TABLE api_usage_log ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS api_usage_tenant_isolation ON api_usage_log;
CREATE POLICY api_usage_tenant_isolation ON api_usage_log
  FOR SELECT
  USING (tenant_id = (current_setting('app.tenant_id', true))::uuid);

-- ============================================================================
-- 7. GRANTs · key_hash NUNCA exposto para authenticated
-- ============================================================================

-- api_keys: REVOKE all, depois GRANT SELECT por colunas (omitindo key_hash)
REVOKE ALL ON api_keys FROM authenticated;
GRANT SELECT (
  id, tenant_id, name, key_prefix, mode, scopes, allowed_ips,
  rate_limit_override, created_by, created_at, expires_at,
  revoked_at, revoked_by, revoke_reason, last_used_at, last_used_ip
) ON api_keys TO authenticated;
GRANT ALL ON api_keys TO service_role;

-- View safe acessível para authenticated
GRANT SELECT ON v_api_keys_safe TO authenticated;

-- idempotency e usage log
GRANT SELECT ON idempotency_keys TO authenticated;
GRANT ALL ON idempotency_keys TO service_role;
GRANT SELECT ON api_usage_log TO authenticated;
GRANT ALL ON api_usage_log TO service_role;

-- RPCs · maioria só service_role; UI invoca via edge function
GRANT EXECUTE ON FUNCTION rpc_create_api_key(uuid, text, text, text[], inet[], timestamptz)
  TO authenticated, service_role;  -- tenant_admin pode criar
GRANT EXECUTE ON FUNCTION rpc_validate_api_key(text)
  TO service_role;  -- só edge functions
GRANT EXECUTE ON FUNCTION rpc_revoke_api_key(uuid, text)
  TO authenticated, service_role;  -- tenant_admin pode revogar
GRANT EXECUTE ON FUNCTION rpc_idempotency_check(uuid, text, text)
  TO service_role;
GRANT EXECUTE ON FUNCTION rpc_idempotency_save(uuid, text, text, int, jsonb)
  TO service_role;
GRANT EXECUTE ON FUNCTION rpc_api_log_request(uuid, uuid, uuid, text, text, int, int, text, inet, text)
  TO service_role;
GRANT EXECUTE ON FUNCTION rpc_idempotency_cleanup() TO service_role;
GRANT EXECUTE ON FUNCTION rpc_api_usage_stats(uuid, int)
  TO authenticated, service_role;

COMMIT;

-- ============================================================================
-- Fim do schema v14
-- ============================================================================

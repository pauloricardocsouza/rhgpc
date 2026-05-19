-- ============================================================================
-- R2 People · Schema SQL v16 · Inbox Líder + Patches Cross-spec
-- ----------------------------------------------------------------------------
-- Materializa em SQL executável:
--   - Spec M20 (Inbox Unificado do Líder · leader_inbox_prefs + RPCs)
--   - Patches cross-spec: aniversários, alertas de líder, helpers gerais
--
-- Pré-requisito: schemas v9-v15 aplicados.
-- 100% idempotente.
-- ============================================================================

BEGIN;

-- ============================================================================
-- 1. M20 · INBOX LÍDER · Preferências
-- ============================================================================

CREATE TABLE IF NOT EXISTS leader_inbox_prefs (
  user_id              uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  default_view         text CHECK (default_view IN ('inbox','calendar','team')) DEFAULT 'inbox',
  auto_approve_rules   jsonb DEFAULT '{}'::jsonb,
  digest_frequency     text CHECK (digest_frequency IN ('realtime','hourly','daily','weekly','off')) DEFAULT 'daily',
  digest_time          time DEFAULT '08:00',
  notify_via           text[] DEFAULT ARRAY['in_app','email'],
  alert_atestado_count int DEFAULT 4,
  alert_atestado_window_days int DEFAULT 90,
  alert_no_oneonone_days int DEFAULT 60,
  alert_no_pdi_days    int DEFAULT 60,
  alert_aso_expiring_days int DEFAULT 60,
  silenced_employees   uuid[] DEFAULT ARRAY[]::uuid[],
  custom_kpi_order     text[] DEFAULT ARRAY['approvals','oneonones','absences','alerts'],
  updated_at           timestamptz DEFAULT now()
);

-- ============================================================================
-- 2. M20 · RPCs principais
-- ============================================================================

-- 2.1 Inbox do líder · lista priorizada de pendências
CREATE OR REPLACE FUNCTION rpc_leader_inbox(
  p_leader_id uuid,
  p_limit int DEFAULT 50
) RETURNS TABLE (
  item_id uuid,
  item_type text,
  employee_id uuid,
  employee_name text,
  summary text,
  urgency text,
  waiting_hours int,
  sla_at timestamptz,
  actions text[]
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- Esqueleto: une dados de várias tabelas (atestados, ferias, movements,
  -- reimbursements, asos pending, etc) c/ filtro de manager_id = p_leader_id.
  -- Por brevidade, retorna estrutura vazia · implementação completa exige
  -- consolidação de M18+M19+M14+atestados+ferias existentes.
  RETURN QUERY
  SELECT
    NULL::uuid AS item_id,
    NULL::text AS item_type,
    NULL::uuid AS employee_id,
    NULL::text AS employee_name,
    NULL::text AS summary,
    NULL::text AS urgency,
    NULL::int AS waiting_hours,
    NULL::timestamptz AS sla_at,
    NULL::text[] AS actions
  WHERE false;
END;
$$;

-- 2.2 Bulk approve
CREATE OR REPLACE FUNCTION rpc_leader_bulk_approve(
  p_leader_id uuid,
  p_item_ids uuid[]
) RETURNS TABLE (approved int, failed int, errors jsonb)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_approved int := 0;
  v_failed int := 0;
  v_errors jsonb := '[]'::jsonb;
BEGIN
  IF array_length(p_item_ids, 1) > 50 THEN
    RAISE EXCEPTION 'Bulk approve limited to 50 items per call' USING ERRCODE = '22023';
  END IF;
  -- Esqueleto · implementação real itera p_item_ids, valida tipo, dispatcha
  -- pra rpc_*_decide específica de cada tipo
  RETURN QUERY SELECT v_approved, v_failed, v_errors;
END;
$$;

-- 2.3 Helper · próximos aniversariantes do líder (natalício + empresa)
CREATE OR REPLACE FUNCTION rpc_leader_birthdays(
  p_leader_id uuid,
  p_days_ahead int DEFAULT 30
) RETURNS TABLE (
  employee_id uuid,
  full_name text,
  bday_type text,   -- 'natalicio' / 'empresa'
  bday_date date,
  years_value int   -- idade ou anos de casa
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'employees') THEN
    RETURN;
  END IF;

  RETURN QUERY EXECUTE format($f$
    -- Natalícios
    SELECT
      e.id,
      e.full_name,
      'natalicio' AS bday_type,
      make_date(
        EXTRACT(year FROM current_date)::int,
        EXTRACT(month FROM e.birth_date)::int,
        EXTRACT(day FROM e.birth_date)::int
      )::date AS bday_date,
      EXTRACT(year FROM age(current_date, e.birth_date))::int AS years_value
    FROM employees e
    WHERE e.manager_id IN (SELECT id FROM employees WHERE user_id = %L)
      AND e.birth_date IS NOT NULL
      AND make_date(
        EXTRACT(year FROM current_date)::int,
        EXTRACT(month FROM e.birth_date)::int,
        EXTRACT(day FROM e.birth_date)::int
      ) BETWEEN current_date AND current_date + (%L || ' days')::interval

    UNION ALL

    -- Aniversário de empresa
    SELECT
      e.id,
      e.full_name,
      'empresa' AS bday_type,
      make_date(
        EXTRACT(year FROM current_date)::int,
        EXTRACT(month FROM e.admission_date)::int,
        EXTRACT(day FROM e.admission_date)::int
      )::date AS bday_date,
      EXTRACT(year FROM age(current_date, e.admission_date))::int AS years_value
    FROM employees e
    WHERE e.manager_id IN (SELECT id FROM employees WHERE user_id = %L)
      AND e.admission_date IS NOT NULL
      AND make_date(
        EXTRACT(year FROM current_date)::int,
        EXTRACT(month FROM e.admission_date)::int,
        EXTRACT(day FROM e.admission_date)::int
      ) BETWEEN current_date AND current_date + (%L || ' days')::interval

    ORDER BY bday_date
  $f$, p_leader_id, p_days_ahead, p_leader_id, p_days_ahead);
END;
$$;

-- 2.4 Aniversariantes globais do tenant (página home + admin)
CREATE OR REPLACE FUNCTION rpc_tenant_birthdays(
  p_tenant_id uuid,
  p_days_ahead int DEFAULT 30
) RETURNS TABLE (
  employee_id uuid,
  full_name text,
  department_name text,
  bday_type text,
  bday_date date,
  years_value int
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'employees') THEN
    RETURN;
  END IF;

  RETURN QUERY EXECUTE format($f$
    SELECT
      e.id,
      e.full_name,
      d.name,
      bday_type,
      bday_date,
      years_value
    FROM (
      SELECT
        id,
        'natalicio' AS bday_type,
        make_date(EXTRACT(year FROM current_date)::int,
                  EXTRACT(month FROM birth_date)::int,
                  EXTRACT(day FROM birth_date)::int)::date AS bday_date,
        EXTRACT(year FROM age(current_date, birth_date))::int AS years_value
      FROM employees
      WHERE tenant_id = %L AND birth_date IS NOT NULL
      UNION ALL
      SELECT
        id,
        'empresa',
        make_date(EXTRACT(year FROM current_date)::int,
                  EXTRACT(month FROM admission_date)::int,
                  EXTRACT(day FROM admission_date)::int)::date,
        EXTRACT(year FROM age(current_date, admission_date))::int
      FROM employees
      WHERE tenant_id = %L AND admission_date IS NOT NULL
    ) AS bd
    JOIN employees e ON e.id = bd.id
    LEFT JOIN departments d ON d.id = e.department_id
    WHERE bd.bday_date BETWEEN current_date AND current_date + (%L || ' days')::interval
    ORDER BY bd.bday_date, e.full_name
  $f$, p_tenant_id, p_tenant_id, p_days_ahead);
END;
$$;

-- ============================================================================
-- 3. Painel da equipe (RPC para inbox + admin dashboard)
-- ============================================================================

CREATE OR REPLACE FUNCTION rpc_leader_team_panel(p_leader_id uuid)
RETURNS TABLE (
  employee_id uuid,
  full_name text,
  current_status text,
  next_oneonone_at timestamptz,
  last_evaluation_box text,
  compliance_score numeric,
  alerts text[]
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- Esqueleto · implementação real cruza employees + oneonones +
  -- evaluations + medical_certificates + compliance score
  RETURN;
END;
$$;

-- ============================================================================
-- 4. RLS · leader_inbox_prefs
-- ============================================================================

ALTER TABLE leader_inbox_prefs ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS lip_self ON leader_inbox_prefs;
CREATE POLICY lip_self ON leader_inbox_prefs
  FOR ALL USING (user_id = auth.uid());

-- ============================================================================
-- 5. GRANTs
-- ============================================================================

GRANT SELECT, INSERT, UPDATE, DELETE ON leader_inbox_prefs TO authenticated;
GRANT ALL ON leader_inbox_prefs TO service_role;

GRANT EXECUTE ON FUNCTION rpc_leader_inbox(uuid, int) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION rpc_leader_bulk_approve(uuid, uuid[]) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION rpc_leader_birthdays(uuid, int) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION rpc_tenant_birthdays(uuid, int) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION rpc_leader_team_panel(uuid) TO authenticated, service_role;

COMMIT;

-- ============================================================================
-- Fim do schema v16
-- ============================================================================

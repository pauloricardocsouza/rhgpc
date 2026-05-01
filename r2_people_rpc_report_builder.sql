-- ============================================================================
-- R2 PEOPLE - RPC FUNCTIONS PARA O REPORT BUILDER (PostgreSQL / Supabase)
-- ============================================================================
-- Biblioteca de funções RPC chamadas pelo frontend via supabase.rpc(name, args)
-- O parâmetro principal de TODAS as funções de relatório é `p_axis`:
--   'employer' → agrupa por employer_unit_id (CNPJ que paga a folha)
--   'taker'    → agrupa por working_unit_id (filial onde trabalha)
--
-- Esse parâmetro é o coração do produto: o mesmo dado pode ser visto
-- por 2 lentes válidas, e a função adapta dinamicamente o GROUP BY.
--
-- Convenções:
--   - Todas as funções rodam com SECURITY DEFINER para aplicar RLS uniformemente
--   - SET search_path = public garante que objetos sejam encontrados
--   - STABLE permite ao PG cachear resultados dentro de uma mesma query
--   - Funções recebem company_id implicitamente via current_user_company_id()
--   - Returns são SETOF/TABLE para facilitar o consumo pelo client
--
-- Padrão de chamada no frontend:
--   const { data, error } = await supabase.rpc('rpt_headcount_by_axis', {
--     p_axis: 'taker',
--     p_employer_filter: null,
--     p_taker_filter: null,
--     p_dept_filter: null,
--     p_status_filter: 'active'
--   });
-- ============================================================================

-- ============================================================================
-- 1. HELPERS DE INFRAESTRUTURA
-- ============================================================================

-- Tipo para o axis-switch (literal de string com check)
CREATE OR REPLACE FUNCTION normalize_axis(p_axis TEXT)
RETURNS TEXT
LANGUAGE plpgsql IMMUTABLE AS $$
BEGIN
  IF p_axis IS NULL OR p_axis NOT IN ('employer', 'taker') THEN
    RAISE EXCEPTION 'Invalid axis: %. Must be "employer" or "taker".', p_axis;
  END IF;
  RETURN p_axis;
END;
$$;

COMMENT ON FUNCTION normalize_axis IS
  'Valida o parâmetro axis. Lança exceção se valor for inválido.';


-- Resolve a unit_id de agrupamento conforme o axis escolhido
-- Esta função é o coração do switch dinâmico.
CREATE OR REPLACE FUNCTION resolve_axis_unit_id(
  p_axis TEXT,
  p_employer_unit_id UUID,
  p_working_unit_id UUID
) RETURNS UUID
LANGUAGE sql IMMUTABLE AS $$
  SELECT CASE
    WHEN p_axis = 'employer' THEN p_employer_unit_id
    WHEN p_axis = 'taker' THEN p_working_unit_id
    ELSE NULL
  END;
$$;

COMMENT ON FUNCTION resolve_axis_unit_id IS
  'Dado um axis e os 2 unit_ids do colaborador, retorna a que deve ser usada para agrupamento.';



-- ============================================================================
-- 2. RPT_HEADCOUNT_BY_AXIS · Headcount agrupado pelo eixo escolhido
-- ============================================================================
-- Caso de uso #1 do report builder. Usado em "Headcount por filial" (taker)
-- e "Headcount por empregador" (employer).
--
-- Frontend chama:
--   await supabase.rpc('rpt_headcount_by_axis', {p_axis: 'taker', ...})
--
-- Retorna: lista de unidades com contagens (active, vacation, leave, total)
-- ============================================================================

CREATE OR REPLACE FUNCTION rpt_headcount_by_axis(
  p_axis TEXT,
  p_employer_filter UUID[] DEFAULT NULL,
  p_taker_filter UUID[] DEFAULT NULL,
  p_dept_filter UUID[] DEFAULT NULL,
  p_status_filter TEXT DEFAULT 'active',
  p_reference_date DATE DEFAULT CURRENT_DATE
)
RETURNS TABLE (
  unit_id        UUID,
  unit_code      TEXT,
  unit_name      TEXT,
  unit_role      TEXT,
  active_count   INTEGER,
  vacation_count INTEGER,
  leave_count    INTEGER,
  total_count    INTEGER,
  avg_salary     NUMERIC(12,2),
  pct_of_total   NUMERIC(5,2)
)
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path = public AS $$
DECLARE
  v_axis    TEXT := normalize_axis(p_axis);
  v_company UUID := current_user_company_id();
  v_total   INTEGER;
BEGIN
  -- Total geral (denominador para pct_of_total)
  SELECT COUNT(*)::INTEGER INTO v_total
    FROM user_companies uc
    JOIN users u ON u.id = uc.user_id
   WHERE uc.company_id = v_company
     AND uc.is_active = TRUE
     AND u.deleted_at IS NULL
     AND (p_status_filter IS NULL OR p_status_filter = 'all' OR uc.status::TEXT = p_status_filter)
     AND (p_employer_filter IS NULL OR uc.employer_unit_id = ANY(p_employer_filter))
     AND (p_taker_filter IS NULL OR uc.working_unit_id = ANY(p_taker_filter))
     AND (p_dept_filter IS NULL OR uc.department_id = ANY(p_dept_filter));

  IF v_total = 0 THEN v_total := 1; END IF; -- evita divisão por zero

  RETURN QUERY
  SELECT
    units.id,
    units.code,
    units.name,
    units.role::TEXT,
    COUNT(*) FILTER (WHERE uc.status = 'active')::INTEGER          AS active_count,
    COUNT(*) FILTER (WHERE uc.status = 'vacation')::INTEGER        AS vacation_count,
    COUNT(*) FILTER (WHERE uc.status IN ('sick_leave','maternity_leave','inss_leave'))::INTEGER AS leave_count,
    COUNT(*)::INTEGER                                              AS total_count,
    COALESCE(AVG(uc.base_salary), 0)::NUMERIC(12,2)                AS avg_salary,
    (COUNT(*) * 100.0 / v_total)::NUMERIC(5,2)                     AS pct_of_total
  FROM user_companies uc
  JOIN users  u     ON u.id = uc.user_id
  JOIN units  units ON units.id = resolve_axis_unit_id(v_axis, uc.employer_unit_id, uc.working_unit_id)
  WHERE uc.company_id = v_company
    AND uc.is_active = TRUE
    AND u.deleted_at IS NULL
    AND (p_status_filter IS NULL OR p_status_filter = 'all' OR uc.status::TEXT = p_status_filter)
    AND (p_employer_filter IS NULL OR uc.employer_unit_id = ANY(p_employer_filter))
    AND (p_taker_filter   IS NULL OR uc.working_unit_id   = ANY(p_taker_filter))
    AND (p_dept_filter    IS NULL OR uc.department_id     = ANY(p_dept_filter))
  GROUP BY units.id, units.code, units.name, units.role
  ORDER BY total_count DESC;
END;
$$;

COMMENT ON FUNCTION rpt_headcount_by_axis IS
  'Headcount agrupado pelo eixo (employer/taker). Aceita filtros multidimensionais opcionais.
   Retorna por unidade: active, vacation, leave, total, salário médio e % do total filtrado.';



-- ============================================================================
-- 3. RPT_HEADCOUNT_MATRIX · Matriz cruzada empregador × tomador
-- ============================================================================
-- Caso de uso #2: a matriz da tela de Relatórios.
-- Aqui NÃO usa axis-switch porque o relatório SEMPRE mostra os dois eixos.
--
-- Retorna uma linha por par (empregador, tomador) com a contagem.
-- O frontend pivota localmente com Object.groupBy ou similar.
-- ============================================================================

CREATE OR REPLACE FUNCTION rpt_headcount_matrix(
  p_status_filter TEXT DEFAULT 'active'
)
RETURNS TABLE (
  employer_unit_id UUID,
  employer_code    TEXT,
  employer_name    TEXT,
  employer_role    TEXT,
  taker_unit_id    UUID,
  taker_code       TEXT,
  taker_name       TEXT,
  taker_role       TEXT,
  headcount        INTEGER,
  avg_salary       NUMERIC(12,2)
)
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path = public AS $$
DECLARE
  v_company UUID := current_user_company_id();
BEGIN
  RETURN QUERY
  SELECT
    emp.id,
    emp.code,
    emp.name,
    emp.role::TEXT,
    tom.id,
    tom.code,
    tom.name,
    tom.role::TEXT,
    COUNT(*)::INTEGER,
    COALESCE(AVG(uc.base_salary), 0)::NUMERIC(12,2)
  FROM user_companies uc
  JOIN users u    ON u.id = uc.user_id
  JOIN units emp  ON emp.id = uc.employer_unit_id
  JOIN units tom  ON tom.id = uc.working_unit_id
  WHERE uc.company_id = v_company
    AND uc.is_active = TRUE
    AND u.deleted_at IS NULL
    AND (p_status_filter IS NULL OR p_status_filter = 'all' OR uc.status::TEXT = p_status_filter)
  GROUP BY emp.id, emp.code, emp.name, emp.role, tom.id, tom.code, tom.name, tom.role
  ORDER BY emp.role, emp.name, tom.name;
END;
$$;

COMMENT ON FUNCTION rpt_headcount_matrix IS
  'Matriz empregador × tomador com headcount em cada interseção.
   Permite construir a tabela cruzada da tela de Relatórios sem pivotar no SQL.';



-- ============================================================================
-- 4. RPT_OUTSOURCING_PERCENTAGE · % de terceirização por filial
-- ============================================================================
-- Indicador específico que SÓ funciona com modelo de duplo eixo.
-- Para cada filial (taker), retorna quantos são próprios vs terceirizados.
-- ============================================================================

CREATE OR REPLACE FUNCTION rpt_outsourcing_percentage(
  p_taker_filter UUID[] DEFAULT NULL
)
RETURNS TABLE (
  taker_unit_id  UUID,
  taker_code     TEXT,
  taker_name     TEXT,
  total_count    INTEGER,
  own_count      INTEGER,
  outsourced_count INTEGER,
  outsourced_pct NUMERIC(5,2)
)
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path = public AS $$
DECLARE
  v_company UUID := current_user_company_id();
BEGIN
  RETURN QUERY
  SELECT
    tom.id,
    tom.code,
    tom.name,
    COUNT(*)::INTEGER                                                     AS total_count,
    COUNT(*) FILTER (WHERE emp.role <> 'service_provider')::INTEGER       AS own_count,
    COUNT(*) FILTER (WHERE emp.role  = 'service_provider')::INTEGER       AS outsourced_count,
    (
      COUNT(*) FILTER (WHERE emp.role = 'service_provider') * 100.0
      / NULLIF(COUNT(*), 0)
    )::NUMERIC(5,2)                                                       AS outsourced_pct
  FROM user_companies uc
  JOIN users u    ON u.id = uc.user_id
  JOIN units emp  ON emp.id = uc.employer_unit_id
  JOIN units tom  ON tom.id = uc.working_unit_id
  WHERE uc.company_id = v_company
    AND uc.is_active = TRUE
    AND uc.status = 'active'
    AND u.deleted_at IS NULL
    AND tom.role IN ('operational', 'administrative')
    AND (p_taker_filter IS NULL OR tom.id = ANY(p_taker_filter))
  GROUP BY tom.id, tom.code, tom.name
  ORDER BY outsourced_pct DESC;
END;
$$;

COMMENT ON FUNCTION rpt_outsourcing_percentage IS
  'Para cada filial (working_unit), retorna % de mão de obra terceirizada.
   Ex: GPC pode descobrir que ATP-Varejo tem 87% de terceirizados, Cestão L1 tem 72%.';



-- ============================================================================
-- 5. RPT_PAYROLL_BY_AXIS · Folha consolidada por eixo
-- ============================================================================
-- Soma de salários agrupada pelo eixo. Para o eixo employer, sai a folha
-- de cada CNPJ (necessário para conciliar com NF da prestadora). Para o
-- eixo taker, sai o custo de pessoal por filial (DRE local).
-- ============================================================================

CREATE OR REPLACE FUNCTION rpt_payroll_by_axis(
  p_axis TEXT,
  p_employer_filter UUID[] DEFAULT NULL,
  p_taker_filter UUID[] DEFAULT NULL,
  p_include_charges BOOLEAN DEFAULT FALSE
)
RETURNS TABLE (
  unit_id          UUID,
  unit_code        TEXT,
  unit_name        TEXT,
  unit_role        TEXT,
  headcount        INTEGER,
  base_payroll     NUMERIC(14,2),
  estimated_charges NUMERIC(14,2),
  total_cost       NUMERIC(14,2),
  avg_salary       NUMERIC(12,2),
  median_salary    NUMERIC(12,2)
)
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path = public AS $$
DECLARE
  v_axis      TEXT := normalize_axis(p_axis);
  v_company   UUID := current_user_company_id();
  v_charges_factor NUMERIC := CASE WHEN p_include_charges THEN 0.68 ELSE 0 END;
  -- 0.68 ≈ encargos médios CLT no Brasil (INSS patronal + FGTS + 13º + férias + etc.)
BEGIN
  RETURN QUERY
  SELECT
    units.id,
    units.code,
    units.name,
    units.role::TEXT,
    COUNT(*)::INTEGER                                                     AS headcount,
    COALESCE(SUM(uc.base_salary), 0)::NUMERIC(14,2)                       AS base_payroll,
    (COALESCE(SUM(uc.base_salary), 0) * v_charges_factor)::NUMERIC(14,2)  AS estimated_charges,
    (COALESCE(SUM(uc.base_salary), 0) * (1 + v_charges_factor))::NUMERIC(14,2) AS total_cost,
    COALESCE(AVG(uc.base_salary), 0)::NUMERIC(12,2)                       AS avg_salary,
    PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY uc.base_salary)::NUMERIC(12,2) AS median_salary
  FROM user_companies uc
  JOIN users u     ON u.id = uc.user_id
  JOIN units units ON units.id = resolve_axis_unit_id(v_axis, uc.employer_unit_id, uc.working_unit_id)
  WHERE uc.company_id = v_company
    AND uc.is_active = TRUE
    AND uc.status = 'active'
    AND u.deleted_at IS NULL
    AND uc.base_salary IS NOT NULL
    AND (p_employer_filter IS NULL OR uc.employer_unit_id = ANY(p_employer_filter))
    AND (p_taker_filter   IS NULL OR uc.working_unit_id   = ANY(p_taker_filter))
  GROUP BY units.id, units.code, units.name, units.role
  ORDER BY base_payroll DESC;
END;
$$;

COMMENT ON FUNCTION rpt_payroll_by_axis IS
  'Folha consolidada pelo eixo escolhido. Com p_include_charges=true, soma 68% de encargos
   estimados (CLT médio Brasil). Use eixo employer para conciliar NF de prestadora.
   Use eixo taker para custo de pessoal de DRE por filial.';



-- ============================================================================
-- 6. RPT_HEADCOUNT_EVOLUTION · Evolução histórica do headcount
-- ============================================================================
-- Série temporal mensal ou semanal. Útil para identificar crescimento,
-- sazonalidade (ex: contratação de natal no varejo) e turnover.
-- ============================================================================

CREATE OR REPLACE FUNCTION rpt_headcount_evolution(
  p_axis TEXT,
  p_unit_filter UUID[] DEFAULT NULL,
  p_start_date DATE DEFAULT (CURRENT_DATE - INTERVAL '12 months')::DATE,
  p_end_date DATE DEFAULT CURRENT_DATE,
  p_granularity TEXT DEFAULT 'month'  -- 'week' | 'month' | 'quarter'
)
RETURNS TABLE (
  period       DATE,
  unit_id      UUID,
  unit_code    TEXT,
  unit_name    TEXT,
  headcount    INTEGER,
  hires        INTEGER,
  terminations INTEGER,
  net_change   INTEGER
)
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path = public AS $$
DECLARE
  v_axis    TEXT := normalize_axis(p_axis);
  v_company UUID := current_user_company_id();
  v_trunc   TEXT;
BEGIN
  IF p_granularity NOT IN ('week', 'month', 'quarter') THEN
    RAISE EXCEPTION 'Invalid granularity: %. Must be week, month or quarter.', p_granularity;
  END IF;
  v_trunc := p_granularity;

  RETURN QUERY
  WITH periods AS (
    SELECT DATE_TRUNC(v_trunc, gs)::DATE AS period
      FROM generate_series(p_start_date, p_end_date, ('1 ' || v_trunc)::INTERVAL) gs
  ),
  axis_units AS (
    SELECT DISTINCT
      resolve_axis_unit_id(v_axis, uc.employer_unit_id, uc.working_unit_id) AS unit_id
    FROM user_companies uc
    WHERE uc.company_id = v_company
      AND (p_unit_filter IS NULL OR resolve_axis_unit_id(v_axis, uc.employer_unit_id, uc.working_unit_id) = ANY(p_unit_filter))
  ),
  base AS (
    SELECT p.period, au.unit_id
      FROM periods p
      CROSS JOIN axis_units au
  )
  SELECT
    b.period,
    b.unit_id,
    units.code,
    units.name,
    -- Headcount na data: contratado antes do fim do período E (não desligado OU desligado depois do período)
    (
      SELECT COUNT(*)::INTEGER
        FROM user_companies uc
       WHERE uc.company_id = v_company
         AND resolve_axis_unit_id(v_axis, uc.employer_unit_id, uc.working_unit_id) = b.unit_id
         AND uc.hire_date <= b.period
         AND (uc.termination_date IS NULL OR uc.termination_date > b.period)
    ) AS headcount,
    -- Admissões no período
    (
      SELECT COUNT(*)::INTEGER
        FROM user_companies uc
       WHERE uc.company_id = v_company
         AND resolve_axis_unit_id(v_axis, uc.employer_unit_id, uc.working_unit_id) = b.unit_id
         AND uc.hire_date >= b.period
         AND uc.hire_date < (b.period + ('1 ' || v_trunc)::INTERVAL)
    ) AS hires,
    -- Desligamentos no período
    (
      SELECT COUNT(*)::INTEGER
        FROM user_companies uc
       WHERE uc.company_id = v_company
         AND resolve_axis_unit_id(v_axis, uc.employer_unit_id, uc.working_unit_id) = b.unit_id
         AND uc.termination_date >= b.period
         AND uc.termination_date < (b.period + ('1 ' || v_trunc)::INTERVAL)
    ) AS terminations,
    -- Net = admissões − desligamentos
    (
      (SELECT COUNT(*) FROM user_companies uc
        WHERE uc.company_id = v_company
          AND resolve_axis_unit_id(v_axis, uc.employer_unit_id, uc.working_unit_id) = b.unit_id
          AND uc.hire_date >= b.period
          AND uc.hire_date < (b.period + ('1 ' || v_trunc)::INTERVAL))
      -
      (SELECT COUNT(*) FROM user_companies uc
        WHERE uc.company_id = v_company
          AND resolve_axis_unit_id(v_axis, uc.employer_unit_id, uc.working_unit_id) = b.unit_id
          AND uc.termination_date >= b.period
          AND uc.termination_date < (b.period + ('1 ' || v_trunc)::INTERVAL))
    )::INTEGER AS net_change
  FROM base b
  JOIN units ON units.id = b.unit_id
  ORDER BY b.period, units.code;
END;
$$;

COMMENT ON FUNCTION rpt_headcount_evolution IS
  'Série temporal de headcount com admissões, desligamentos e net change.
   Aceita granularidade week/month/quarter. Use para identificar sazonalidade no varejo.';



-- ============================================================================
-- 7. RPT_TURNOVER_BY_AXIS · Taxa de turnover por unidade
-- ============================================================================
-- Métrica clássica de RH: (desligamentos no período) / headcount médio
-- Calculada para cada unidade conforme o eixo escolhido.
-- ============================================================================

CREATE OR REPLACE FUNCTION rpt_turnover_by_axis(
  p_axis TEXT,
  p_start_date DATE DEFAULT (CURRENT_DATE - INTERVAL '12 months')::DATE,
  p_end_date DATE DEFAULT CURRENT_DATE,
  p_unit_filter UUID[] DEFAULT NULL
)
RETURNS TABLE (
  unit_id          UUID,
  unit_code        TEXT,
  unit_name        TEXT,
  headcount_start  INTEGER,
  headcount_end    INTEGER,
  headcount_avg    NUMERIC(8,2),
  hires            INTEGER,
  terminations     INTEGER,
  voluntary_term   INTEGER,
  involuntary_term INTEGER,
  turnover_pct     NUMERIC(5,2),
  voluntary_pct    NUMERIC(5,2)
)
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path = public AS $$
DECLARE
  v_axis    TEXT := normalize_axis(p_axis);
  v_company UUID := current_user_company_id();
BEGIN
  RETURN QUERY
  WITH per_unit AS (
    SELECT
      resolve_axis_unit_id(v_axis, uc.employer_unit_id, uc.working_unit_id) AS unit_id,

      -- Headcount no início do período
      COUNT(*) FILTER (
        WHERE uc.hire_date <= p_start_date
          AND (uc.termination_date IS NULL OR uc.termination_date > p_start_date)
      )::INTEGER AS hc_start,

      -- Headcount no fim do período
      COUNT(*) FILTER (
        WHERE uc.hire_date <= p_end_date
          AND (uc.termination_date IS NULL OR uc.termination_date > p_end_date)
      )::INTEGER AS hc_end,

      -- Admissões no período
      COUNT(*) FILTER (
        WHERE uc.hire_date BETWEEN p_start_date AND p_end_date
      )::INTEGER AS num_hires,

      -- Desligamentos no período
      COUNT(*) FILTER (
        WHERE uc.termination_date BETWEEN p_start_date AND p_end_date
      )::INTEGER AS num_terms,

      -- Voluntários (pedido de demissão / fim de contrato em comum acordo)
      COUNT(*) FILTER (
        WHERE uc.termination_date BETWEEN p_start_date AND p_end_date
          AND uc.termination_reason ILIKE ANY (ARRAY['%pedido%','%espontane%','%comum acordo%','%aposentad%'])
      )::INTEGER AS vol_terms,

      -- Involuntários (justa causa / sem justa causa pelo empregador)
      COUNT(*) FILTER (
        WHERE uc.termination_date BETWEEN p_start_date AND p_end_date
          AND uc.termination_reason ILIKE ANY (ARRAY['%justa causa%','%sem justa%','%dispens%','%demit%','%fim de contrato%'])
      )::INTEGER AS invol_terms

    FROM user_companies uc
    WHERE uc.company_id = v_company
      AND (p_unit_filter IS NULL OR
           resolve_axis_unit_id(v_axis, uc.employer_unit_id, uc.working_unit_id) = ANY(p_unit_filter))
    GROUP BY resolve_axis_unit_id(v_axis, uc.employer_unit_id, uc.working_unit_id)
  )
  SELECT
    pu.unit_id,
    units.code,
    units.name,
    pu.hc_start,
    pu.hc_end,
    ((pu.hc_start + pu.hc_end) / 2.0)::NUMERIC(8,2) AS headcount_avg,
    pu.num_hires,
    pu.num_terms,
    pu.vol_terms,
    pu.invol_terms,
    (pu.num_terms * 100.0 / NULLIF((pu.hc_start + pu.hc_end) / 2.0, 0))::NUMERIC(5,2) AS turnover_pct,
    (pu.vol_terms * 100.0 / NULLIF(pu.num_terms, 0))::NUMERIC(5,2) AS voluntary_pct
  FROM per_unit pu
  JOIN units ON units.id = pu.unit_id
  WHERE pu.unit_id IS NOT NULL
  ORDER BY turnover_pct DESC NULLS LAST;
END;
$$;

COMMENT ON FUNCTION rpt_turnover_by_axis IS
  'Turnover (taxa de saída) calculado pelo eixo escolhido. Diferencia voluntário vs involuntário.
   Useful para identificar filiais com problemas de retenção (taker) ou prestadoras com alta rotatividade (employer).';



-- ============================================================================
-- 8. RPT_AVG_TENURE_BY_AXIS · Tempo médio de casa por unidade
-- ============================================================================

CREATE OR REPLACE FUNCTION rpt_avg_tenure_by_axis(
  p_axis TEXT,
  p_unit_filter UUID[] DEFAULT NULL
)
RETURNS TABLE (
  unit_id        UUID,
  unit_code      TEXT,
  unit_name      TEXT,
  headcount      INTEGER,
  avg_tenure_months  NUMERIC(6,1),
  median_tenure_months NUMERIC(6,1),
  newcomers_pct  NUMERIC(5,2),  -- % com menos de 6 meses
  veterans_pct   NUMERIC(5,2)   -- % com mais de 5 anos
)
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path = public AS $$
DECLARE
  v_axis    TEXT := normalize_axis(p_axis);
  v_company UUID := current_user_company_id();
BEGIN
  RETURN QUERY
  SELECT
    resolve_axis_unit_id(v_axis, uc.employer_unit_id, uc.working_unit_id) AS unit_id,
    units.code,
    units.name,
    COUNT(*)::INTEGER,
    AVG(EXTRACT(EPOCH FROM age(CURRENT_DATE, uc.hire_date)) / (60*60*24*30))::NUMERIC(6,1)        AS avg_tenure_months,
    PERCENTILE_CONT(0.5) WITHIN GROUP (
      ORDER BY EXTRACT(EPOCH FROM age(CURRENT_DATE, uc.hire_date)) / (60*60*24*30)
    )::NUMERIC(6,1) AS median_tenure_months,
    (COUNT(*) FILTER (WHERE uc.hire_date > CURRENT_DATE - INTERVAL '6 months') * 100.0 / COUNT(*))::NUMERIC(5,2)   AS newcomers_pct,
    (COUNT(*) FILTER (WHERE uc.hire_date <= CURRENT_DATE - INTERVAL '5 years') * 100.0 / COUNT(*))::NUMERIC(5,2)   AS veterans_pct
  FROM user_companies uc
  JOIN units ON units.id = resolve_axis_unit_id(v_axis, uc.employer_unit_id, uc.working_unit_id)
  WHERE uc.company_id = v_company
    AND uc.is_active = TRUE
    AND uc.status = 'active'
    AND (p_unit_filter IS NULL OR
         resolve_axis_unit_id(v_axis, uc.employer_unit_id, uc.working_unit_id) = ANY(p_unit_filter))
  GROUP BY resolve_axis_unit_id(v_axis, uc.employer_unit_id, uc.working_unit_id), units.code, units.name
  ORDER BY avg_tenure_months DESC;
END;
$$;

COMMENT ON FUNCTION rpt_avg_tenure_by_axis IS
  'Tempo médio de casa por unidade conforme eixo. Inclui % de recém-chegados (<6m) e veteranos (5+ anos).';



-- ============================================================================
-- 9. RPT_SALARY_DISTRIBUTION · Pirâmide salarial em faixas
-- ============================================================================
-- Útil para análise de equidade interna. Categoriza colaboradores em
-- 5 faixas salariais e retorna contagem por unidade no eixo escolhido.
-- ============================================================================

CREATE OR REPLACE FUNCTION rpt_salary_distribution(
  p_axis TEXT,
  p_unit_filter UUID[] DEFAULT NULL
)
RETURNS TABLE (
  unit_id    UUID,
  unit_code  TEXT,
  unit_name  TEXT,
  band       TEXT,
  band_order INTEGER,
  headcount  INTEGER,
  pct        NUMERIC(5,2)
)
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path = public AS $$
DECLARE
  v_axis    TEXT := normalize_axis(p_axis);
  v_company UUID := current_user_company_id();
BEGIN
  RETURN QUERY
  WITH banded AS (
    SELECT
      resolve_axis_unit_id(v_axis, uc.employer_unit_id, uc.working_unit_id) AS unit_id,
      CASE
        WHEN uc.base_salary < 2000  THEN 'Até R$ 2.000'
        WHEN uc.base_salary < 3500  THEN 'R$ 2.000 a R$ 3.500'
        WHEN uc.base_salary < 5500  THEN 'R$ 3.500 a R$ 5.500'
        WHEN uc.base_salary < 10000 THEN 'R$ 5.500 a R$ 10.000'
        ELSE 'Acima de R$ 10.000'
      END AS band,
      CASE
        WHEN uc.base_salary < 2000  THEN 1
        WHEN uc.base_salary < 3500  THEN 2
        WHEN uc.base_salary < 5500  THEN 3
        WHEN uc.base_salary < 10000 THEN 4
        ELSE 5
      END AS band_order
    FROM user_companies uc
    WHERE uc.company_id = v_company
      AND uc.is_active = TRUE
      AND uc.status = 'active'
      AND uc.base_salary IS NOT NULL
      AND (p_unit_filter IS NULL OR
           resolve_axis_unit_id(v_axis, uc.employer_unit_id, uc.working_unit_id) = ANY(p_unit_filter))
  ),
  totals AS (
    SELECT b.unit_id, COUNT(*)::INTEGER AS unit_total
      FROM banded b
     GROUP BY b.unit_id
  )
  SELECT
    b.unit_id,
    units.code,
    units.name,
    b.band,
    b.band_order,
    COUNT(*)::INTEGER AS headcount,
    (COUNT(*) * 100.0 / NULLIF(t.unit_total, 0))::NUMERIC(5,2) AS pct
  FROM banded b
  JOIN totals t ON t.unit_id = b.unit_id
  JOIN units   ON units.id = b.unit_id
  GROUP BY b.unit_id, units.code, units.name, b.band, b.band_order, t.unit_total
  ORDER BY units.name, b.band_order;
END;
$$;

COMMENT ON FUNCTION rpt_salary_distribution IS
  'Distribuição de colaboradores em 5 faixas salariais por unidade.
   Use para detectar concentração excessiva em faixa baixa (precarização) ou alta (top heavy).';



-- ============================================================================
-- 10. RPT_REVIEW_SCORE_DISTRIBUTION · Distribuição de notas do ciclo
-- ============================================================================
-- Histograma das notas do gestor agrupado por unidade no eixo escolhido.
-- ============================================================================

CREATE OR REPLACE FUNCTION rpt_review_score_distribution(
  p_axis TEXT,
  p_cycle_id UUID,
  p_unit_filter UUID[] DEFAULT NULL
)
RETURNS TABLE (
  unit_id     UUID,
  unit_code   TEXT,
  unit_name   TEXT,
  score_band  TEXT,
  score_order INTEGER,
  headcount   INTEGER,
  pct         NUMERIC(5,2),
  unit_avg    NUMERIC(3,2)
)
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path = public AS $$
DECLARE
  v_axis    TEXT := normalize_axis(p_axis);
  v_company UUID := current_user_company_id();
BEGIN
  RETURN QUERY
  WITH scored AS (
    SELECT
      resolve_axis_unit_id(v_axis, uc.employer_unit_id, uc.working_unit_id) AS unit_id,
      r.overall_score,
      CASE
        WHEN r.overall_score < 2.0 THEN 1
        WHEN r.overall_score < 3.0 THEN 2
        WHEN r.overall_score < 3.5 THEN 3
        WHEN r.overall_score < 4.5 THEN 4
        ELSE 5
      END AS score_band,
      CASE
        WHEN r.overall_score < 2.0 THEN '1 · Insuficiente'
        WHEN r.overall_score < 3.0 THEN '2 · Precisa melhorar'
        WHEN r.overall_score < 3.5 THEN '3 · Atende'
        WHEN r.overall_score < 4.5 THEN '4 · Supera'
        ELSE                           '5 · Excepcional'
      END AS score_label
    FROM reviews r
    JOIN user_companies uc ON uc.user_id = r.evaluatee_id AND uc.company_id = v_company
    WHERE r.cycle_id = p_cycle_id
      AND r.kind = 'manager'
      AND r.status = 'submitted'
      AND r.overall_score IS NOT NULL
      AND (p_unit_filter IS NULL OR
           resolve_axis_unit_id(v_axis, uc.employer_unit_id, uc.working_unit_id) = ANY(p_unit_filter))
  ),
  totals AS (
    SELECT s.unit_id, COUNT(*)::INTEGER AS unit_total, AVG(s.overall_score)::NUMERIC(3,2) AS avg_score
      FROM scored s
     GROUP BY s.unit_id
  )
  SELECT
    s.unit_id,
    units.code,
    units.name,
    s.score_label,
    s.score_band,
    COUNT(*)::INTEGER,
    (COUNT(*) * 100.0 / NULLIF(t.unit_total, 0))::NUMERIC(5,2),
    t.avg_score
  FROM scored s
  JOIN totals t ON t.unit_id = s.unit_id
  JOIN units ON units.id = s.unit_id
  GROUP BY s.unit_id, units.code, units.name, s.score_label, s.score_band, t.unit_total, t.avg_score
  ORDER BY units.name, s.score_band;
END;
$$;

COMMENT ON FUNCTION rpt_review_score_distribution IS
  'Distribuição das notas do gestor de um ciclo em 5 faixas (1-5).
   Inclui média da unidade. Útil para detectar viés de avaliação por filial.';



-- ============================================================================
-- 11. RPT_NINEBOX_DISTRIBUTION · Posicionamento na matriz 9-Box
-- ============================================================================

CREATE OR REPLACE FUNCTION rpt_ninebox_distribution(
  p_cycle_id UUID,
  p_axis TEXT DEFAULT 'taker',
  p_unit_filter UUID[] DEFAULT NULL
)
RETURNS TABLE (
  performance     INTEGER,
  potential       INTEGER,
  classification  TEXT,
  headcount       INTEGER,
  pct             NUMERIC(5,2),
  user_ids        UUID[]
)
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path = public AS $$
DECLARE
  v_axis    TEXT := normalize_axis(p_axis);
  v_company UUID := current_user_company_id();
  v_total   INTEGER;
BEGIN
  -- Total para % do total
  SELECT COUNT(*)::INTEGER INTO v_total
    FROM nine_box_positions nb
    JOIN user_companies uc ON uc.user_id = nb.user_id AND uc.company_id = v_company
   WHERE nb.cycle_id = p_cycle_id
     AND (p_unit_filter IS NULL OR
          resolve_axis_unit_id(v_axis, uc.employer_unit_id, uc.working_unit_id) = ANY(p_unit_filter));
  IF v_total = 0 THEN v_total := 1; END IF;

  RETURN QUERY
  SELECT
    nb.performance,
    nb.potential,
    nb.classification,
    COUNT(*)::INTEGER AS headcount,
    (COUNT(*) * 100.0 / v_total)::NUMERIC(5,2) AS pct,
    ARRAY_AGG(nb.user_id ORDER BY nb.created_at) AS user_ids
  FROM nine_box_positions nb
  JOIN user_companies uc ON uc.user_id = nb.user_id AND uc.company_id = v_company
  WHERE nb.cycle_id = p_cycle_id
    AND (p_unit_filter IS NULL OR
         resolve_axis_unit_id(v_axis, uc.employer_unit_id, uc.working_unit_id) = ANY(p_unit_filter))
  GROUP BY nb.performance, nb.potential, nb.classification
  ORDER BY nb.potential DESC, nb.performance DESC;
END;
$$;

COMMENT ON FUNCTION rpt_ninebox_distribution IS
  'Conta quantos colaboradores há em cada uma das 9 células do 9-Box.
   Retorna user_ids para drill-down rápido.';



-- ============================================================================
-- 12. RPT_DASHBOARD_KPIS · KPIs consolidados do dashboard RH
-- ============================================================================
-- Agrupa todos os KPIs principais em UMA chamada para a tela home/dashboard.
-- Reduz o número de round-trips do frontend.
-- ============================================================================

CREATE OR REPLACE FUNCTION rpt_dashboard_kpis()
RETURNS TABLE (
  metric_key   TEXT,
  metric_label TEXT,
  metric_value NUMERIC,
  metric_unit  TEXT,
  trend_pct    NUMERIC(5,2),
  trend_direction TEXT
)
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path = public AS $$
DECLARE
  v_company UUID := current_user_company_id();
  v_today   DATE := CURRENT_DATE;
  v_30d_ago DATE := v_today - INTERVAL '30 days';
  v_60d_ago DATE := v_today - INTERVAL '60 days';

  v_active_now      INTEGER;
  v_active_30d_ago  INTEGER;
  v_outsourced_pct  NUMERIC;
  v_avg_salary      NUMERIC;
  v_pending_movs    INTEGER;
  v_open_cycles     INTEGER;
  v_unread_feedback INTEGER;
  v_avg_tenure      NUMERIC;
BEGIN
  -- Headcount ativo agora
  SELECT COUNT(*) INTO v_active_now
    FROM user_companies
   WHERE company_id = v_company AND is_active = TRUE AND status = 'active';

  -- Headcount há 30 dias (para trend)
  SELECT COUNT(*) INTO v_active_30d_ago
    FROM user_companies uc
   WHERE uc.company_id = v_company
     AND uc.hire_date <= v_30d_ago
     AND (uc.termination_date IS NULL OR uc.termination_date > v_30d_ago);

  -- % terceirização
  SELECT (COUNT(*) FILTER (WHERE u.role = 'service_provider') * 100.0 / NULLIF(COUNT(*), 0))
    INTO v_outsourced_pct
    FROM user_companies uc
    JOIN units u ON u.id = uc.employer_unit_id
   WHERE uc.company_id = v_company AND uc.is_active = TRUE AND uc.status = 'active';

  -- Salário médio
  SELECT AVG(base_salary) INTO v_avg_salary
    FROM user_companies
   WHERE company_id = v_company AND is_active = TRUE AND status = 'active' AND base_salary IS NOT NULL;

  -- Movimentações pendentes
  SELECT COUNT(*) INTO v_pending_movs
    FROM personnel_movements
   WHERE company_id = v_company AND status IN ('pending_manager', 'pending_hr');

  -- Ciclos abertos
  SELECT COUNT(*) INTO v_open_cycles
    FROM review_cycles
   WHERE company_id = v_company AND status IN ('open','self_eval','manager_eval','calibration');

  -- Feedbacks não lidos do usuário corrente
  SELECT COUNT(*) INTO v_unread_feedback
    FROM notifications
   WHERE company_id = v_company AND to_user_id = current_user_id()
     AND read_at IS NULL AND kind = 'feedback_received';

  -- Tempo médio de casa em meses
  SELECT AVG(EXTRACT(EPOCH FROM age(v_today, hire_date)) / (60*60*24*30))
    INTO v_avg_tenure
    FROM user_companies
   WHERE company_id = v_company AND is_active = TRUE AND status = 'active';

  -- Retorna como tabela longa de métricas
  RETURN QUERY VALUES
    ('headcount',         'Colaboradores ativos',       v_active_now::NUMERIC,                            'pessoas',
      ((v_active_now - v_active_30d_ago) * 100.0 / NULLIF(v_active_30d_ago, 0))::NUMERIC(5,2),
      CASE WHEN v_active_now > v_active_30d_ago THEN 'up'
           WHEN v_active_now < v_active_30d_ago THEN 'down' ELSE 'stable' END),
    ('outsourced_pct',    'Mão de obra terceirizada',   v_outsourced_pct::NUMERIC,                        '%',          NULL::NUMERIC, NULL::TEXT),
    ('avg_salary',        'Salário médio',              v_avg_salary::NUMERIC,                            'BRL',        NULL::NUMERIC, NULL::TEXT),
    ('pending_movements', 'Movimentações pendentes',    v_pending_movs::NUMERIC,                          'fluxos',     NULL::NUMERIC, NULL::TEXT),
    ('open_cycles',       'Ciclos de avaliação abertos',v_open_cycles::NUMERIC,                           'ciclos',     NULL::NUMERIC, NULL::TEXT),
    ('unread_feedback',   'Feedbacks não lidos',        v_unread_feedback::NUMERIC,                       'mensagens',  NULL::NUMERIC, NULL::TEXT),
    ('avg_tenure_months', 'Tempo médio de casa',        v_avg_tenure::NUMERIC(6,1),                       'meses',      NULL::NUMERIC, NULL::TEXT);
END;
$$;

COMMENT ON FUNCTION rpt_dashboard_kpis IS
  'KPIs consolidados do dashboard RH em uma única chamada. Inclui trend de 30 dias para headcount.';



-- ============================================================================
-- 13. EXEMPLOS DE CHAMADA NO FRONTEND (TypeScript / Supabase JS)
-- ============================================================================
/*

// 1. Headcount por filial (eixo TOMADOR)
const { data, error } = await supabase.rpc('rpt_headcount_by_axis', {
  p_axis: 'taker',
  p_status_filter: 'active'
});

// 2. Mesma análise pelo eixo EMPREGADOR (apenas mudando p_axis)
const { data, error } = await supabase.rpc('rpt_headcount_by_axis', {
  p_axis: 'employer',
  p_status_filter: 'active'
});

// 3. Filtrando só Cestão L1 (taker_filter passa array de UUIDs)
const { data, error } = await supabase.rpc('rpt_headcount_by_axis', {
  p_axis: 'employer',
  p_taker_filter: ['<uuid-cestao-l1>'],
  p_status_filter: 'active'
});
// Retorna a composição do Cestão L1 por empregador: 11 GPC + 63 Labuta + 9 Limpactiva + 8 Segure

// 4. Matriz cruzada para a tabela do report builder
const { data, error } = await supabase.rpc('rpt_headcount_matrix', {
  p_status_filter: 'active'
});
// Retorna 4×7 = até 28 linhas, frontend pivota

// 5. Folha consolidada da Labuta (eixo employer)
const { data, error } = await supabase.rpc('rpt_payroll_by_axis', {
  p_axis: 'employer',
  p_employer_filter: ['<uuid-labuta>'],
  p_include_charges: true
});
// Retorna folha base da Labuta + 68% de encargos estimados

// 6. Custo de pessoal por filial (eixo taker - DRE local)
const { data, error } = await supabase.rpc('rpt_payroll_by_axis', {
  p_axis: 'taker',
  p_include_charges: true
});

// 7. Evolução do headcount mensal últimos 12m
const { data, error } = await supabase.rpc('rpt_headcount_evolution', {
  p_axis: 'taker',
  p_granularity: 'month'
});

// 8. % de terceirização por filial
const { data, error } = await supabase.rpc('rpt_outsourcing_percentage');

// 9. Turnover por prestadora (qual prestadora rotativiza mais?)
const { data, error } = await supabase.rpc('rpt_turnover_by_axis', {
  p_axis: 'employer'
});

// 10. KPIs do dashboard em 1 chamada
const { data, error } = await supabase.rpc('rpt_dashboard_kpis');
// Retorna 7 métricas em formato long, ideal para popular cards da home

*/



-- ============================================================================
-- 14. PERMISSÕES (GRANT)
-- ============================================================================
-- Funções RPC ficam no schema 'public' para o cliente acessar via supabase.rpc.
-- A segurança fica nas RLS das tabelas que elas consultam.
-- ============================================================================

GRANT EXECUTE ON FUNCTION rpt_headcount_by_axis(TEXT, UUID[], UUID[], UUID[], TEXT, DATE)         TO authenticated;
GRANT EXECUTE ON FUNCTION rpt_headcount_matrix(TEXT)                                              TO authenticated;
GRANT EXECUTE ON FUNCTION rpt_outsourcing_percentage(UUID[])                                      TO authenticated;
GRANT EXECUTE ON FUNCTION rpt_payroll_by_axis(TEXT, UUID[], UUID[], BOOLEAN)                      TO authenticated;
GRANT EXECUTE ON FUNCTION rpt_headcount_evolution(TEXT, UUID[], DATE, DATE, TEXT)                 TO authenticated;
GRANT EXECUTE ON FUNCTION rpt_turnover_by_axis(TEXT, DATE, DATE, UUID[])                          TO authenticated;
GRANT EXECUTE ON FUNCTION rpt_avg_tenure_by_axis(TEXT, UUID[])                                    TO authenticated;
GRANT EXECUTE ON FUNCTION rpt_salary_distribution(TEXT, UUID[])                                   TO authenticated;
GRANT EXECUTE ON FUNCTION rpt_review_score_distribution(TEXT, UUID, UUID[])                       TO authenticated;
GRANT EXECUTE ON FUNCTION rpt_ninebox_distribution(UUID, TEXT, UUID[])                            TO authenticated;
GRANT EXECUTE ON FUNCTION rpt_dashboard_kpis()                                                    TO authenticated;



-- ============================================================================
-- FIM DA BIBLIOTECA RPC
-- ============================================================================
-- Notas para evolução:
--
-- 1. Cache: para tenants grandes (10k+ colaboradores), considere materializar
--    rpt_headcount_matrix em uma materialized view atualizada a cada 5min.
--
-- 2. Performance: as funções fazem JOIN com user_companies que tem RLS.
--    Em queries pesadas, considere helper que use SECURITY DEFINER e bypass RLS
--    aplicando filtros explicitamente no escopo do user (mais rápido em volume).
--
-- 3. Auditoria: para função sensível como rpt_payroll_by_axis, adicionar trigger
--    que registre o acesso em audit_log (LGPD - acesso a dados sensíveis).
--
-- 4. Internacionalização: as labels (band, score_label) estão hardcoded em PT-BR.
--    Em produção, mover para coluna locale na tabela companies.settings e
--    aceitar p_locale como parâmetro.
--
-- 5. Ciclos comparativos: adicionar p_compare_with_cycle_id em rpt_review_score_distribution
--    para diff entre ciclos.
-- ============================================================================

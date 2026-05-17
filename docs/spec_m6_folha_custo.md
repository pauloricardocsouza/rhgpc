# Spec · M6 · Folha & Custo

**Status:** pronto para execução em ambiente com Postgres 16
**Pré-requisitos:** M1 (Estrutura) aplicado · `units.tax_regime` populado
**Estimativa:** 2 sessões (~7-8h)

---

## 1. Objetivo

Portar para Next.js o módulo de Folha & Custo. **Três telas com escopos distintos** mas compartilhando legislação versionada:

| Tela origem | Página Next.js | Persona | Escopo |
|---|---|---|---|
| [r2_people_calculadora_custo.html](../r2_people_calculadora_custo.html) | `/folha/calculadora` | RH (Patrícia) | Custo de um colaborador |
| [r2_people_folha_por_filial.html](../r2_people_folha_por_filial.html) | `/folha/por-filial` | Diretoria (Renato) | Custo agregado por unidade |
| [r2_people_regime_tributario.html](../r2_people_regime_tributario.html) | `/admin/regime-tributario` | RH com `manage_tax_regime` | CRUD config fiscal por unidade |
| [r2_people_comparar_cenarios.html](../r2_people_comparar_cenarios.html) | `/folha/cenarios` | Diretoria | A/B de cenários (dissídio, etc.) |

---

## 2. Legislação 2026 versionada

**Decisão arquitetural:** constantes legais vão em **tabela `legal_tax_tables`** versionada por ano. Quando a Receita atualizar em janeiro/2027, alteração em **um único INSERT**.

### 2.1 Schema · migration 00440_m6_schema_legal_tables.sql

```sql
CREATE TABLE legal_tax_tables (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  legal_year      INT NOT NULL,
  table_kind      VARCHAR(40) NOT NULL,                -- 'inss_employee', 'irrf', 'inss_ceiling', 'minimum_wage', 'family_salary'
  data            JSONB NOT NULL,                      -- estrutura específica por table_kind
  effective_from  DATE NOT NULL,
  effective_to    DATE,                                -- NULL = vigente
  source          TEXT,                                -- 'Portaria Interministerial MPS/MF nº 13/2026'
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (legal_year, table_kind, effective_from)
);

-- INSS empregado progressivo 2026
INSERT INTO legal_tax_tables (legal_year, table_kind, data, effective_from, source) VALUES
(2026, 'inss_employee', '{
  "brackets": [
    {"min": 0,        "max": 1518.00,  "rate": 0.075, "deduction": 0},
    {"min": 1518.01,  "max": 2793.88,  "rate": 0.09,  "deduction": 24.32},
    {"min": 2793.89,  "max": 4190.83,  "rate": 0.12,  "deduction": 111.40},
    {"min": 4190.84,  "max": 8475.55,  "rate": 0.14,  "deduction": 198.49}
  ],
  "ceiling_salary": 8475.55,
  "ceiling_contribution": 988.09
}'::jsonb, '2026-01-01', 'Portaria Interministerial MPS/MF nº 13/2026');

-- IRRF 2026 com Lei 15.270/2025 (isenção até R$ 5k)
INSERT INTO legal_tax_tables (legal_year, table_kind, data, effective_from, source) VALUES
(2026, 'irrf', '{
  "isencao_full_until": 5000.00,
  "isencao_reducao_until": 7350.00,
  "reducao_formula": "max(0, 978.62 - 0.133145 * salary)",
  "tradicional_brackets": [
    {"min": 0,       "max": 2428.80, "rate": 0,     "deduction": 0},
    {"min": 2428.81, "max": 2826.65, "rate": 0.075, "deduction": 182.16},
    {"min": 2826.66, "max": 3751.05, "rate": 0.15,  "deduction": 394.16},
    {"min": 3751.06, "max": 4664.68, "rate": 0.225, "deduction": 675.49},
    {"min": 4664.69, "max": null,    "rate": 0.275, "deduction": 908.73}
  ],
  "dependente_deducao": 189.59
}'::jsonb, '2026-01-01', 'Lei 15.270/2025 + Tabela RFB');

-- Salário mínimo
INSERT INTO legal_tax_tables (legal_year, table_kind, data, effective_from, source) VALUES
(2026, 'minimum_wage', '{"value": 1621.00}'::jsonb, '2026-01-01', 'MP 1170/2025');
```

### 2.2 Função SQL pura `calc_inss(salary, year)`

```sql
CREATE OR REPLACE FUNCTION calc_inss(p_salary NUMERIC, p_year INT DEFAULT NULL)
RETURNS NUMERIC LANGUAGE plpgsql STABLE AS $$
DECLARE
  v_table JSONB; v_brackets JSONB; v_b JSONB;
  v_ceiling NUMERIC; v_ceiling_contrib NUMERIC; v_calc NUMERIC;
BEGIN
  IF p_year IS NULL THEN p_year := EXTRACT(YEAR FROM CURRENT_DATE)::INT; END IF;

  SELECT data INTO v_table FROM legal_tax_tables
    WHERE table_kind = 'inss_employee' AND legal_year = p_year
    LIMIT 1;

  v_brackets := v_table->'brackets';
  v_ceiling := (v_table->>'ceiling_salary')::NUMERIC;
  v_ceiling_contrib := (v_table->>'ceiling_contribution')::NUMERIC;

  IF p_salary >= v_ceiling THEN RETURN v_ceiling_contrib; END IF;

  FOR v_b IN SELECT * FROM jsonb_array_elements(v_brackets) LOOP
    IF p_salary >= (v_b->>'min')::NUMERIC AND p_salary <= (v_b->>'max')::NUMERIC THEN
      v_calc := p_salary * (v_b->>'rate')::NUMERIC - (v_b->>'deduction')::NUMERIC;
      RETURN GREATEST(0, v_calc);
    END IF;
  END LOOP;

  RETURN 0;
END; $$;

-- Análogo: calc_irrf, calc_encargos_lucro_real, calc_encargos_simples, calc_provisao_mensal
```

---

## 3. RPCs principais

```sql
-- 1. Calcular custo individual
rpc_calc_individual_cost(
  p_salary NUMERIC,
  p_tax_regime VARCHAR DEFAULT 'lucro_real',
  p_simples_anexo VARCHAR DEFAULT NULL,
  p_fap NUMERIC DEFAULT 1.0,
  p_rat_pct NUMERIC DEFAULT 2.0,
  p_benefits JSONB DEFAULT '{}',  -- {vr, va, plano_saude, odonto, seguro}
  p_variables JSONB DEFAULT '{}'  -- {comissao, he_50, he_100, noturno, periculosidade}
)
RETURNS JSONB  -- {liquido, encargos, provisoes, custo_total, breakdown_detalhado}

-- 2. Folha agregada por filial
rpc_payroll_by_unit(
  p_employer_unit_id UUID DEFAULT NULL,  -- NULL = consolidado tenant
  p_year INT DEFAULT NULL,
  p_month INT DEFAULT NULL,
  p_scenario JSONB DEFAULT '{}'  -- {dissidio_pct, merito_pct, headcount_reduce_pct, headcount_add_count}
)
RETURNS JSONB
  -- usa mv_payroll_by_unit como base + aplica overrides do scenario

-- 3. Comparar 2 cenários A vs B
rpc_compare_scenarios(p_scenario_a JSONB, p_scenario_b JSONB, p_scope JSONB)
  -- retorna delta % e absoluto por unidade

-- 4. CRUD regime tributário (movimentação fiscal sensível)
rpc_tax_regime_change(
  p_unit_id UUID,
  p_new_regime VARCHAR,
  p_new_simples_anexo VARCHAR DEFAULT NULL,
  p_effective_from DATE,
  p_justification TEXT,
  p_accountant_approved BOOLEAN,
  p_recalc_acknowledged BOOLEAN
)
  -- exige permission manage_tax_regime
  -- exige p_accountant_approved=TRUE AND p_recalc_acknowledged=TRUE
  -- audit log obrigatório com from/to chips
```

---

## 4. View materializada · `mv_payroll_by_unit`

```sql
CREATE MATERIALIZED VIEW mv_payroll_by_unit AS
SELECT
  au.tenant_id,
  au.employer_unit_id,
  eu.legal_name AS employer_name,
  eu.tax_regime,
  eu.simples_anexo,
  eu.fap,
  eu.rat_pct,
  au.working_unit_id,
  wu.display_name AS working_name,
  au.department_id,
  d.display_name AS department_name,
  COUNT(*) AS headcount,
  SUM(au.salary) AS salary_sum,
  AVG(au.salary) AS salary_avg,
  -- Encargos calculados via funções SQL
  SUM(
    CASE eu.tax_regime
      WHEN 'simples' THEN au.salary * 0.30
      WHEN 'lucro_real' THEN au.salary * 0.67
      ELSE au.salary * 0.5
    END
  ) AS total_cost_estimated_monthly,
  SUM(au.salary) * 12 + SUM(au.salary) * 0.0833 + SUM(au.salary) * 0.1111  -- bruto anual + 13o + ferias
    AS total_cost_estimated_annual
FROM app_users au
JOIN employer_units eu ON eu.id = au.employer_unit_id
LEFT JOIN working_units wu ON wu.id = au.working_unit_id
LEFT JOIN departments d ON d.id = au.department_id
WHERE au.active = TRUE
GROUP BY au.tenant_id, au.employer_unit_id, eu.legal_name, eu.tax_regime,
         eu.simples_anexo, eu.fap, eu.rat_pct,
         au.working_unit_id, wu.display_name, au.department_id, d.display_name;

CREATE INDEX idx_mv_pbu_tenant ON mv_payroll_by_unit(tenant_id);
CREATE INDEX idx_mv_pbu_employer ON mv_payroll_by_unit(employer_unit_id);

-- Refresh: job pg_cron 1x/dia ou trigger ao salvar mudança salarial
```

---

## 5. Páginas Next.js

### 5.1 `/folha/calculadora`

Referência: [r2_people_calculadora_custo.html](../r2_people_calculadora_custo.html)

- Toggle SIMPLES NACIONAL ↔ LUCRO REAL com banner contextual (GPC opera em ambos)
- Slider de salário com gradient
- 5 toggles de benefícios (VR, VA, plano saúde, odonto, seguro)
- Variáveis (comissão, HE 50%, HE 100%, adicionais)
- PLR rateado por mês
- Result panel gradient com líquido + anual + custo total
- Donut chart SVG inline (salário base · encargos · benefícios · provisões)
- Breakdown detalhado por seção
- Comparativo SIMPLES vs LUCRO REAL lado a lado

### 5.2 `/folha/por-filial`

Referência: [r2_people_folha_por_filial.html](../r2_people_folha_por_filial.html)

- 4 KPIs consolidados (367 colab, R$ X/mês, R$ Y/ano, R$ Z médio)
- Filtros por empregador
- **4 cenários componíveis:** dissídio %, mérito %, redução headcount %, contratações novas
- Impact banner consolidado em tempo real
- Bar chart horizontal das top 8 filiais por custo
- Heatmap mensal de sazonalidade (picos jul + dez)
- Tabela detalhada com drill-down por departamento

### 5.3 `/admin/regime-tributario`

Referência: [r2_people_regime_tributario.html](../r2_people_regime_tributario.html)

- 4 KPIs (14 unidades, 5 Lucro Real, 9 Simples, 3 alteradas em 2026)
- Banner warn se faturamento próximo do teto Simples (R$ 4,8mi)
- Tabela editável com badges coloridos por tipo
- CNPJ, Anexo Simples, FAP, RAT, Headcount, Faturamento por unidade
- **Modal de confirmação dupla** com cálculo de impacto em tempo real
- 2 checkboxes obrigatórios (aprovação contábil + ciência do recálculo)
- Audit log com 6 eventos cronológicos (regime, FAP, RAT, criação)

### 5.4 `/folha/cenarios`

Referência: [r2_people_comparar_cenarios.html](../r2_people_comparar_cenarios.html)

- Cenário A vs Cenário B lado a lado
- Inputs editáveis em cada lado
- Paired bars comparativos
- Diff table com delta % e absoluto
- Botão "Salvar como cenário" (futuro)

---

## 6. Testes · `supabase/tests/00440_m6_folha_custo.sql`

Meta: 40+ testes cobrindo:

1. `calc_inss(0)` = 0
2. `calc_inss(1518)` = 113.85 (7.5%)
3. `calc_inss(8475.55)` = 988.09 (teto)
4. `calc_inss(10000)` = 988.09 (acima do teto)
5. `calc_irrf(5000, 0_dep)` = 0 (isenção Lei 15.270)
6. `calc_irrf(6000, 0_dep)` redução ≈ R$ 179,75 (validado contra RFB)
7. `calc_irrf(7350, 0_dep)` redução = 0 (transição)
8. `calc_irrf(10000, 1_dep)` traz dedução de R$ 189,59
9. Encargos Lucro Real R$ 5000 ≈ R$ 3.350 (67%)
10. Encargos Simples Anexo III R$ 5000 ≈ R$ 1.500 (30%)
11. Provisão férias 11,11%, 13º 8,33%, multa rescisória 4%
12. RPC calc_individual_cost retorna estrutura completa
13. RPC payroll_by_unit consolidado tenant
14. RPC payroll_by_unit filtrado por employer
15. RPC compare_scenarios delta calculado corretamente
16. RPC tax_regime_change exige permission
17. RPC tax_regime_change exige ambos checkboxes
18. RPC tax_regime_change cria audit log
19. RPC tax_regime_change atualiza units.tax_regime
20-40: edge cases, divisão por zero protegida, cross-tenant, etc.

---

## 7. Critérios de aceitação

- [ ] Migrations 00440 + seed legal tables aplicam idempotentemente
- [ ] 40+ testes passando
- [ ] 4 páginas Next.js + componentes específicos
- [ ] Adapter em `src/lib/r2/payroll.ts`
- [ ] View materializada refresca em < 3s para tenant de 1000 colab
- [ ] Comparativo cálculos individual vs agregado bate (mesma fórmula)
- [ ] Tela de regime tributário com modal de confirmação dupla
- [ ] Audit log de toda mudança fiscal
- [ ] Sidebar nav-items adicionados condicionalmente por role
- [ ] Doc da sessão em `docs/sessao_m6.md`

---

## 8. Pontos de atenção

- **Lei 15.270/2025 é progressiva** (redução, não isenção pura): fórmula `978.62 - 0.133145 * salary` entre R$ 5k e R$ 7.350
- **Encargos Simples NÃO incluem INSS patronal nem RAT nem Sistema S** (estão no DAS) · só FGTS 8% + provisões
- **FAP varia 0,5 a 2,0** conforme histórico de acidentes da unidade
- **RAT 1% (baixo) a 3% (alto)** conforme grau de risco da atividade
- **Refresh view materializada** acionado por trigger ou cron · não calcular on-the-fly (50ms por colab × 367 = 18s)
- **Sazonalidade**: julho (1ª parcela 13º) e dezembro (13º completo + provisões consumidas) são picos · tela de folha deve mostrar isso explícito
- **Cuidado com divisão por zero** em filtros (headcount = 0)
- **Constantes legais futuras**: criar processo de atualização em janeiro de cada ano · INSERT em `legal_tax_tables` com novo `legal_year` + `effective_from`
- **Auditoria fiscal**: toda mudança em `units.tax_regime` deve ter justificativa e dupla confirmação
- **Faixa salarial do job_role** (M1) alimenta sugestão na calculadora · validar que `salary BETWEEN salary_min AND salary_max`

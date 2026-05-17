# Spec · M9 · Relatórios com switch EMP/TOM

**Status:** RPCs já parcialmente em `r2_people_rpc_report_builder.sql` · falta portar pra migrations + UI Next.js
**Pré-requisitos:** M1, M3, M4 idealmente aplicados (relatórios consomem dados)
**Estimativa:** 1-2 sessões (~5-6h)

---

## 1. Objetivo

Portar o **report builder** com switch EMP/TOM (estrutura tripartite) já desenhado no rhgpc.

| Tela origem | Página Next.js |
|---|---|
| `r2_people_relatorios.html` | `/admin/relatorios` |

---

## 2. Eixos de análise · switch EMP ↔ TOM

Diferença crítica do produto: relatórios podem ser olhados por **2 eixos distintos**:

### Eixo EMP (Empregador legal · CTPS)
Útil para folha, encargos, contabilidade fiscal:
- "Tudo da Labuta Ltda" · 142 colaboradores · custo X
- "Tudo da ATP Varejo Ltda" · 94 colaboradores · custo Y

### Eixo TOM (Tomador operacional · onde a pessoa trabalha)
Útil para operação, gestão de loja, planejamento de RH:
- "Tudo do Cestão Loja 1" · mix de CLT ATP + terceirizado Labuta · 78 pessoas
- "Tudo do CD Inhambupe" · mix de empresas · 62 pessoas

O switch fica visível no topo de cada relatório · usuário alterna a qualquer momento.

---

## 3. Categorias de relatório

```
1. Headcount
   - Por unidade (EMP ou TOM)
   - Por departamento
   - Por cargo
   - Por tipo de vínculo (CLT, estágio, terceirizado)
   - Por tempo de casa
   - Evolução mensal

2. Movimentação
   - Admissões / desligamentos no período
   - Promoções
   - Transferências
   - Turnover voluntário vs involuntário (com motivo)
   - Custo de turnover estimado

3. Folha e Custo
   - Folha consolidada (EMP) ou cost-by-location (TOM)
   - Encargos por regime tributário
   - Provisões mensais (férias, 13º, multa rescisória)
   - Comparativo períodos (mês vs mês, ano vs ano)

4. Vida e Saúde
   - Atestados por período (sem CID em lista · CID só pro DP)
   - Dias de afastamento agregados
   - Férias programadas vs realizadas
   - Estoque de aquisitivos vencendo (alerta)

5. Desempenho
   - Distribuição 9-Box por ciclo
   - Cobertura de PDI
   - Cobertura de 1:1s (metadados apenas · privacy)
   - eNPS por unidade

6. Engajamento
   - Adesão a treinamentos obrigatórios
   - Reconhecimentos enviados/recebidos
   - Indicações ativas

7. Compliance & Auditoria
   - Audit log filtrado
   - DSARs solicitados
   - Atestados sem validação > 7d (alerta)
   - Movimentos sem aprovação > 3d
```

---

## 4. Schema · views materializadas

Relatórios consomem **views materializadas** atualizadas diariamente (refresh às 6h via pg_cron):

```sql
-- migration: 00480_m9_views_relatorios.sql

-- Headcount por EMP+TOM+dept+role
CREATE MATERIALIZED VIEW mv_headcount AS
SELECT
  au.tenant_id,
  au.employer_unit_id, eu.code AS employer_code, eu.legal_name AS employer_name,
  au.working_unit_id, wu.code AS working_code, wu.display_name AS working_name,
  au.department_id, d.code AS dept_code, d.display_name AS dept_name,
  au.job_role_id, jr.display_name AS job_role_name,
  au.employment_link,
  COUNT(*) AS headcount,
  AVG(EXTRACT(YEAR FROM age(CURRENT_DATE, au.hired_at))) AS avg_tenure_years
FROM app_users au
LEFT JOIN employer_units eu ON eu.id = au.employer_unit_id
LEFT JOIN working_units wu ON wu.id = au.working_unit_id
LEFT JOIN departments d ON d.id = au.department_id
LEFT JOIN job_roles jr ON jr.id = au.job_role_id
WHERE au.active = TRUE
GROUP BY 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11;

CREATE INDEX ON mv_headcount(tenant_id, employer_unit_id);
CREATE INDEX ON mv_headcount(tenant_id, working_unit_id);

-- Movimentação (admissões/desligamentos/promoções)
CREATE MATERIALIZED VIEW mv_movements_summary AS
SELECT
  m.tenant_id,
  date_trunc('month', m.effective_date) AS month,
  m.kind,
  au.employer_unit_id,
  au.working_unit_id,
  au.department_id,
  COUNT(*) AS count
FROM movements m
JOIN app_users au ON au.id = m.employee_id
WHERE m.status = 'effective'
GROUP BY 1, 2, 3, 4, 5, 6;

-- Folha consolidada
CREATE MATERIALIZED VIEW mv_payroll_consolidated AS
SELECT
  au.tenant_id,
  au.employer_unit_id, eu.legal_name AS employer_name,
  au.working_unit_id, wu.display_name AS working_name,
  au.department_id, d.display_name AS dept_name,
  eu.tax_regime,
  COUNT(*) AS headcount,
  SUM(au.salary) AS gross_salary_total,
  SUM(au.salary * encargos_factor(eu.tax_regime)) AS encargos_total,
  SUM(au.salary * (1 + encargos_factor(eu.tax_regime))) AS total_cost_monthly,
  SUM(au.salary * (1 + encargos_factor(eu.tax_regime)) * 12 +
      au.salary * 0.1111 + au.salary * 0.0833) AS total_cost_annual
FROM app_users au
JOIN employer_units eu ON eu.id = au.employer_unit_id
LEFT JOIN working_units wu ON wu.id = au.working_unit_id
LEFT JOIN departments d ON d.id = au.department_id
WHERE au.active = TRUE
GROUP BY 1, 2, 3, 4, 5, 6, 7, 8;

-- Atestados sem CID (privacy)
CREATE MATERIALIZED VIEW mv_medical_summary AS
SELECT
  mc.tenant_id,
  date_trunc('month', mc.starts_at) AS month,
  au.employer_unit_id,
  au.working_unit_id,
  au.department_id,
  COUNT(*) AS certificates_count,
  SUM(mc.days_off) AS days_off_total,
  AVG(mc.days_off) AS avg_days_off
  -- IMPORTANTE: NUNCA inclui cid_code, doctor_name, etc.
FROM medical_certificates mc
JOIN app_users au ON au.id = mc.employee_id
WHERE mc.status = 'validated'
GROUP BY 1, 2, 3, 4, 5;
```

---

## 5. RPCs principais (portar de `rpc_report_builder.sql`)

```sql
-- 11 RPCs já desenhadas · adaptar pra schema atual:

rpc_report_headcount(p_axis, p_filter JSONB)
  -- p_axis: 'employer' | 'working' | 'department' | 'role'
  -- p_filter: { employer_ids: [...], date_range: {...}, ... }

rpc_report_turnover(p_axis, p_period)
  -- calcula entrada/saída/turnover voluntário/involuntário
  -- separa por motivo (cargo melhor, ambiente, salário, etc.)

rpc_report_payroll(p_axis, p_month)
  -- consolida folha · separa CLT/PJ/terceirizado

rpc_report_medical(p_axis, p_period)
  -- agregados de atestados · SEM CID
  -- tipo certificado, dias por categoria

rpc_report_vacations(p_period)
  -- programadas vs realizadas
  -- aquisitivos vencendo (alerta)

rpc_report_9box(p_cycle_id)
  -- distribuição da matriz no ciclo
  -- comparativo entre ciclos

rpc_report_pdi_coverage(p_axis)
  -- % de colaboradores com PDI ativo
  -- por unidade/dept

rpc_report_oneonones_coverage(p_axis)
  -- agregados de 1:1s (cadência, AIs abertos)
  -- SEM conteúdo · privacy enforced

rpc_report_enps(p_period, p_axis)
  -- score por unidade
  -- evolução temporal

rpc_report_indications(p_period)
  -- volume de indicações, contratações, bonus pago

rpc_report_audit(p_filter JSONB, p_limit INT)
  -- audit log filtrado
  -- exige permission 'view_audit_log'
```

---

## 6. Página Next.js · `/admin/relatorios`

Referência: [r2_people_relatorios.html](../r2_people_relatorios.html)

### Layout
```
+-----------------------------------------------------+
| Hub · 7 categorias (cards clicáveis)                |
|  [📊 Headcount]  [📈 Mov.]  [💰 Folha]  [🩺 Saúde]  |
|  [⭐ Desemp.]    [💬 Eng.]  [🔒 Comp.]              |
+-----------------------------------------------------+

Ao clicar em categoria:
+-----------------------------------------------------+
| Headcount · Atual                                   |
|  Switch: [EMPREGADOR] [TOMADOR] [DEPT] [CARGO]      |
|  Filtros: período | empresa | unidade | tipo víncul.|
|                                                     |
|  [Tabela ou chart conforme métrica]                 |
|                                                     |
|  Ações: [Exportar XLSX] [Exportar PDF] [Agendar]    |
+-----------------------------------------------------+
```

### Componentes
- `<CategoryHub />`: 7 cards
- `<ReportBuilder axis={...} filter={...}>`: container principal
- `<AxisSwitch />`: tabs EMP/TOM/DEPT/ROLE
- `<FilterBar />`: chips de filtro
- `<ReportTable />`: tabela com sort, paginação, agregação rolling
- `<ReportChart />`: chart adaptativo (bar/line/donut conforme metric)
- `<ExportButtons />`: XLSX, PDF, link compartilhável

### Caching
- Resultados de RPC cacheados em IndexedDB do browser por 1h
- Force-refresh via botão
- Loading state com skeleton

---

## 7. Export e agendamento

```sql
-- Tabela de relatórios agendados
CREATE TABLE scheduled_reports (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id       UUID NOT NULL,

  name            VARCHAR(160) NOT NULL,
  report_kind     VARCHAR(60) NOT NULL,
  filter          JSONB NOT NULL,
  axis            VARCHAR(20) NOT NULL,

  -- Agendamento
  schedule_cron   VARCHAR(60) NOT NULL,   -- '0 8 1 * *' = todo dia 1 às 8h
  format          VARCHAR(10) NOT NULL,   -- 'xlsx' | 'pdf' | 'csv'

  -- Destinatários
  recipients      UUID[] NOT NULL,        -- app_users
  email_extra     TEXT[],                 -- emails externos opcional

  active          BOOLEAN NOT NULL DEFAULT TRUE,
  created_by      UUID NOT NULL,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);
```

Worker FastAPI (já existe pra OCR) ganha endpoint:
- `POST /reports/generate` · recebe params, retorna URL signed do storage
- `pg_cron` agenda + worker executa + envia email

---

## 8. Testes · `supabase/tests/00480_m9_relatorios.sql`

Meta: 25+ testes:

1. mv_headcount calcula corretamente após admissões
2. Switch EMP retorna 4 empregadores GPC
3. Switch TOM retorna 14 unidades GPC
4. rpc_report_payroll soma encargos por regime
5. rpc_report_medical NÃO retorna cid_code (validar query)
6. rpc_report_audit exige permission
7. Cross-tenant blocked em todas RPCs
8. Refresh materialized view atualiza
9. RPC retorna empty para tenant sem dados (não erro)
10. Filtros combinados funcionam (period + employer + dept)
11-25: edge cases

---

## 9. Critérios de aceitação

- [ ] Migration 00480 + views materializadas aplicadas
- [ ] 11 RPCs adaptadas e testadas (25+ testes)
- [ ] Página `/admin/relatorios` com hub + builder funcionais
- [ ] Switch EMP/TOM funcional em todos os relatórios aplicáveis
- [ ] Export XLSX e PDF
- [ ] Adapter `src/lib/r2/reports.ts`
- [ ] Sidebar nav-item "Relatórios" condicional (RH+, diretoria)
- [ ] Doc da sessão em `docs/sessao_m9.md`

---

## 10. Pontos de atenção

- **Refresh das views**: cron diário às 6h · forçar manual quando RH precisa de dados frescos
- **Privacy em mv_medical_summary**: garantir que nenhuma view materializada inclui dados sensíveis (CID, notas privadas de 1:1, etc.)
- **Performance**: relatórios grandes (>10k linhas) podem exigir paginação backend · CSV em chunks
- **Export PDF**: usar Puppeteer no worker FastAPI ou html2canvas client-side
- **Agendamento**: cuidado com sobrecarga · limitar a 50 reports/dia por tenant
- **Compartilhamento de link**: link signed com expiração 7 dias · não cachear no CDN
- **Switch EMP/TOM**: alguns relatórios só fazem sentido em um eixo (folha → EMP) · esconder switch nesses casos
- **Filtros salvos**: usuário pode salvar combinação de filtros como "view personalizada"

# Spec M17 · People Analytics · Dashboards para Diretoria e Liderança

**Status**: especificação · pré-implementação
**Versão**: 1.0 · 18 de maio de 2026
**Escopo**: dashboards e métricas de pessoas (turnover, retenção, D&I, headcount evolution, faixa salarial agregada)
**Depende de**: schema v9+ (employees, movements), spec M16 (Integração Domínio · refletida em fonte de dados), spec D7 (LGPD agregado), spec D8 (RLS)

---

## 1. Por que People Analytics importa

Diretoria de PME brasileira hoje **não toma decisão de pessoas com dado**, toma com **intuição**:
- "Esse setor tá saindo muito gente" → sem turnover real
- "Equipe tá pequena pro volume" → sem headcount projetado
- "Não pago tão mal assim" → sem benchmark interno
- "Diversidade tá ok" → sem D&I agregado

R2 People entrega **dado confiável, atualizado e LGPD-safe** num dashboard único — diretoria abre uma vez por mês na reunião de board e tem o pulso da gente.

### 1.1 Personas alvo

| Persona | O que olha | Frequência |
|---|---|---|
| **Diretor/CFO** | Custo total, headcount, turnover, custo por filial | Mensal (reunião board) |
| **Coordenador RH** | Turnover por motivo, ASOs vencidos, D&I, treinamentos | Semanal |
| **Líder direto** | Sua equipe (sem benchmark de outras) | Diário |
| **DPO** | Quem acessa dados sensíveis, logs de export | Quando audita |

### 1.2 Princípios LGPD-first

- **Dados sensíveis (CID, salário individual)** só com permissão explícita
- **Faixas e agregados** sempre que possível (ex: "10 pessoas na faixa R$ 3-5k" em vez de lista nominal)
- **D&I via auto-declaração opcional** (raça, gênero, deficiência, orientação) com consent versionado
- **Anonimização forçada** quando agregado tem < 5 pessoas (k-anonymity)
- **Export logado** em `action_log` (audit DSAR-ready)

---

## 2. Categorias de métricas

### 2.1 Headcount

| Métrica | Cálculo | Dashboard |
|---|---|---|
| **Total ativo** | `count(employees WHERE status='active')` | Card grande |
| **Admissões/mês** | `count(movements WHERE type='ADMISSION' AND month=X)` | Linha tempo 12m |
| **Desligamentos/mês** | `count(movements WHERE type='TERMINATION' AND month=X)` | Linha tempo 12m |
| **Headcount net** | admissões − desligamentos | Sparkline |
| **Headcount projetado** | atual + admissões pendentes − terminações agendadas | Card |
| **Total por filial/depto/cargo** | `GROUP BY branch_id` | Barras horizontais |
| **% efetivo vs temporário** | `count(type='temporary') / count(*)` | Donut |

### 2.2 Turnover

| Métrica | Fórmula | Janela |
|---|---|---|
| **Turnover voluntário** | `(desligamentos_voluntários / headcount_médio) × 12 / meses` | 12m móvel |
| **Turnover involuntário** | `(desligamentos_involuntários / headcount_médio) × 12 / meses` | 12m móvel |
| **Turnover regretted** | sub-tipo de voluntário onde colaborador era "champion" no 9-Box | Sinal crítico |
| **Turnover por filial/depto** | break-down acima | Comparativo |
| **Motivo principal** | top 5 de `termination_reason` | Lista |
| **Tempo médio até saída** | `avg(termination_date − admission_date)` | Histograma |
| **Curva de sobrevivência** | % ainda na empresa em 6m / 12m / 24m / 36m após admissão | Linha |

**Benchmarks setor brasileiro** (referência interna):
- Varejo: ~50% a.a. (Cestão/ATP devem mirar < 35%)
- Indústria: ~15% a.a.
- Serviços: ~25% a.a.

### 2.3 Retenção

| Métrica | Definição |
|---|---|
| **Tempo médio de empresa** | `avg(now() − admission_date)` |
| **% com > 5 anos de casa** | indicador de carreira |
| **% com < 6 meses** (novos) | indicador de crescimento |
| **Tempo médio até primeira promoção** | dado de carreira |
| **Tempo médio entre promoções** | velocidade de carreira |
| **% de promoções internas vs contratações externas** | meta cultura |

### 2.4 D&I (Diversidade & Inclusão) · agregado e opcional

Cada colaborador tem campo opcional de auto-declaração (consent_required):

```sql
ALTER TABLE employees ADD COLUMN IF NOT EXISTS
  gender_self_declared text,          -- 'male','female','non-binary','prefer_not_to_say'
  race_self_declared   text,          -- IBGE: 'branca','preta','parda','amarela','indígena','prefer_not_to_say'
  pcd boolean DEFAULT false,          -- pessoa com deficiência
  pcd_type text,                      -- 'fisica','visual','auditiva','intelectual','multipla'
  age_bucket text;                    -- calculado: '18-24','25-34','35-44','45-54','55+'
```

Dashboards D&I:
- **Distribuição de gênero** total + por nível hierárquico (% mulheres em liderança)
- **Distribuição racial** total + por nível (gap PPI vs branca em liderança)
- **% PcD** total (meta legal Lei 8.213: 2-5% conforme tamanho)
- **Distribuição etária** por filial
- **Equidade salarial** (gap salarial por gênero/raça no mesmo cargo · agregado)
- **Pipeline diversidade** (% candidatos × admitidos × promovidos por categoria)

**k-anonymity**: se grupo agregado tem < 5 pessoas, mostra "menos de 5" em vez do número exato (evita reidentificação).

### 2.5 Faixa salarial (sem expor individual)

Diretor/CFO vê **distribuição agregada** por filial, departamento, cargo:

| Visualização | Conteúdo |
|---|---|
| **Histograma de faixas** | "10 pessoas em R$ 2-3k · 25 em R$ 3-5k · 8 em R$ 5-8k" |
| **Mediana por cargo** | "Analista Pleno: R$ 4.500 (mediana), R$ 4.200 (mínimo), R$ 5.100 (máximo) — 12 pessoas" |
| **Custo por filial** | "Cestão L1: R$ 287k/mês total (91 pessoas, média R$ 3.150)" |
| **Folha vs receita** | se cliente integrar dado de receita: % de folha sobre receita |
| **Compa-ratio** (futuro pós-MVP) | salário individual / mediana da banda |

**Dado vem do Domínio** (folha fechada), reflete em R2 mensalmente.

### 2.6 Engajamento (cruzado com analytics)

Cruzamentos poderosos:
- **eNPS por filial × turnover por filial** (correlação)
- **Avaliação 9-Box × tempo de empresa** (champions ficando vs indo)
- **PDI ativos × promoções nos últimos 12m** (PDI funciona?)
- **1:1s frequência × eNPS pessoal** (líderes que fazem 1:1 retêm mais?)
- **Atestados/mês × adoção do líder** (líderes pouco ativos têm + atestado?)

### 2.7 Absenteísmo

| Métrica | Cálculo |
|---|---|
| **Taxa de absenteísmo** | `(dias_ausentes / dias_úteis) × 100` |
| **Por filial/depto/cargo** | break-down |
| **Recorrência por colaborador** | "5 atestados em 6 meses" sinal de alerta |
| **Dias por tipo** | doença / atestado médico / outros |
| **Sazonalidade** | curva por mês |

Varejo é especialmente sensível: absenteísmo > 5% impacta operação.

---

## 3. UI · dashboard People Analytics

Página nova: `r2_people_analytics.html` (cockpit dedicado para diretoria/CFO/RH).

### 3.1 Estrutura

**Hero · resumo executivo**
- Headcount atual + Δ vs mês anterior
- Turnover 12m
- Custo total mensal (do Domínio)
- eNPS último ciclo

**5 abas principais**:

| Aba | Métricas |
|-----|----------|
| **Headcount** | Total + evolução 12m + por filial/depto + admissões/desligamentos + projeção |
| **Turnover & Retenção** | Voluntário/involuntário/regretted + curva sobrevivência + motivos + tempo médio |
| **D&I** | Gênero/raça/PcD/idade · totais + por nível hierárquico + equidade salarial |
| **Custo (do Domínio)** | Folha total + por filial + faixa salarial + encargos + tendência |
| **Engajamento** | eNPS + clima + cruzamentos c/ turnover |

### 3.2 Filtros globais

- Período (mês atual / 3m / 6m / 12m / custom)
- Empresa (EMP — empregador CTPS) · multi-select
- Tomador (TOM — unidade operacional) · multi-select
- Departamento
- Nível hierárquico (operacional / coordenação / gerência / diretoria)

### 3.3 Exports

- **PDF executivo** (formatado pra reunião de board)
- **CSV/XLSX** (dados brutos, sem PII se faixa < 5)
- **Apresentação Google Slides** (template auto-preenchido · roadmap)

Cada export é **logado em `action_log`** com user + filtros aplicados (audit LGPD).

### 3.4 Alerts proativos

- Turnover de uma filial > 1.5× mediana das outras → alerta no card
- Aumento > 30% MoM em alguma métrica → highlight
- Equidade salarial gap > 15% → alerta jurídico
- ASO vencido > 30d → alerta NR-7

---

## 4. Schema (tabelas e views)

### 4.1 Views materializadas (refresh diário)

```sql
-- Headcount snapshot diário
CREATE MATERIALIZED VIEW mv_headcount_daily AS
SELECT
  tenant_id,
  date_trunc('day', day) AS day,
  branch_id,
  department_id,
  count(*) FILTER (WHERE status='active') AS active,
  count(*) FILTER (WHERE status='terminated') AS terminated,
  count(*) FILTER (WHERE admission_date = day) AS admitted_today,
  count(*) FILTER (WHERE termination_date = day) AS terminated_today
FROM employees e
CROSS JOIN generate_series(now() - interval '24 months', now(), '1 day') AS day
WHERE e.admission_date <= day
GROUP BY tenant_id, day, branch_id, department_id;

CREATE UNIQUE INDEX idx_mv_headcount ON mv_headcount_daily (tenant_id, day, branch_id, department_id);

-- Refresh diário via cron
SELECT cron.schedule('refresh-headcount', '0 3 * * *',
  $$REFRESH MATERIALIZED VIEW CONCURRENTLY mv_headcount_daily$$);
```

### 4.2 Tabela de exports auditados

```sql
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

CREATE INDEX idx_analytics_exports_tenant
  ON analytics_exports (tenant_id, occurred_at DESC);
```

### 4.3 RPCs principais

```sql
-- Headcount em uma data
rpc_analytics_headcount(p_tenant_id, p_date, p_filters jsonb DEFAULT '{}')
  RETURNS TABLE (active int, by_branch jsonb, by_department jsonb)

-- Turnover anualizado
rpc_analytics_turnover(p_tenant_id, p_period_start, p_period_end, p_filters)
  RETURNS TABLE (
    voluntary_rate numeric,
    involuntary_rate numeric,
    regretted_count int,
    top_reasons jsonb,
    by_branch jsonb
  )

-- D&I com k-anonymity (< 5 vira "—")
rpc_analytics_diversity(p_tenant_id, p_filters)
  RETURNS TABLE (
    gender_distribution jsonb,
    race_distribution jsonb,
    pcd_pct numeric,
    age_distribution jsonb,
    leadership_breakdown jsonb
  )

-- Curva de sobrevivência (% que continua após N meses)
rpc_analytics_survival_curve(p_tenant_id, p_cohort_year)
  RETURNS TABLE (months_since_admission int, survival_pct numeric)

-- Custo (vem do Domínio, refletido)
rpc_analytics_cost(p_tenant_id, p_period_start, p_period_end, p_group_by)
  RETURNS TABLE (
    group_key text,
    total_brl_cents bigint,
    headcount int,
    average_brl_cents int,
    median_brl_cents int,
    encargos_pct numeric
  )
```

---

## 5. Permissões

| Métrica | Quem vê |
|---|---|
| Headcount total | qualquer authenticated |
| Headcount por filial/depto | lider+ |
| Turnover global | coord_rh+ |
| Turnover por filial | lider da filial (próprio) ou coord_rh+ |
| D&I agregado | rh+ |
| D&I auto-declarado (raça/gênero) | rh+ com permissão `view_diversity` |
| Faixa salarial agregada | coord_rh+ |
| Salário individual | nunca aparece neste módulo (gestão pelo Domínio) |
| Custo total | diretoria + cfo |
| Export PDF/CSV | super_admin + diretoria + dpo |

Permissões via `user_permissions` + checagem em cada RPC.

---

## 6. Cálculos especiais

### 6.1 k-anonymity

```sql
CREATE OR REPLACE FUNCTION fn_apply_k_anonymity(
  p_data jsonb,
  p_min int DEFAULT 5
) RETURNS jsonb
LANGUAGE plpgsql AS $$
DECLARE v_result jsonb := '{}'::jsonb; v_key text; v_val numeric;
BEGIN
  FOR v_key, v_val IN SELECT * FROM jsonb_each_text(p_data) LOOP
    IF v_val::numeric >= p_min THEN
      v_result := v_result || jsonb_build_object(v_key, v_val);
    ELSE
      v_result := v_result || jsonb_build_object(v_key, '<5');
    END IF;
  END LOOP;
  RETURN v_result;
END;
$$;
```

### 6.2 Turnover anualizado

```
Turnover_voluntário = (count(termination WHERE type='voluntary' AND occurred IN período) / headcount_médio_do_período) × (12 / meses_do_período)
```

`headcount_médio` = média de `mv_headcount_daily` no período.

### 6.3 Curva de sobrevivência (Kaplan-Meier simplificado)

Para cada coorte (ano de admissão), calcula % que ainda está ativo em cada mês desde a admissão.

---

## 7. Origem dos dados

| Dado | Origem | Refresh |
|---|---|---|
| Headcount, admissões, desligamentos | R2 People (`employees`, `movements`) | tempo real |
| D&I auto-declarado | R2 People (consent_required) | tempo real |
| Salário individual | **Domínio** (não armazenamos detalhado) | mensal (folha fechada) |
| Custo total folha | **Domínio** (refletido via M14 inbound `payroll.closed`) | mensal |
| Encargos | **Domínio** | mensal |
| Banco de horas | **Domínio** | semanal/diário |
| Absenteísmo | R2 People (atestados) + Domínio (banco horas) | tempo real / semanal |
| eNPS, clima | R2 People (pesquisas) | trimestral |
| Avaliações, 1:1s | R2 People | tempo real |

---

## 8. Performance

| Query | Target | Estratégia |
|---|---|---|
| Headcount snapshot hoje | < 50ms | `mv_headcount_daily` indexada |
| Turnover 12m por filial | < 200ms | views materializadas |
| Curva sobrevivência | < 500ms | pré-calculada noturna |
| D&I com k-anonymity | < 300ms | agrupamento + filter |
| Export CSV 10k linhas | < 5s | streaming + workers |

Cache de dashboards: 10min TTL (acceptable trade-off para dado quase-em-tempo-real).

---

## 9. Testes meta (mínimo 22)

### 9.1 Cálculos
- ✓ Turnover anualizado bate com fórmula manual em coorte conhecida
- ✓ Curva de sobrevivência respeita ordem temporal
- ✓ k-anonymity bloqueia agregado < 5
- ✓ Mediana salarial considera apenas ativos no período
- ✓ Headcount projetado soma admissões pendentes corretamente
- ✓ Sazonalidade detecta picos de absenteísmo em meses específicos

### 9.2 Permissões
- ✓ Líder não vê outras filiais
- ✓ Coord_rh sem `view_diversity` não vê raça/gênero auto-declarado
- ✓ Salário individual nunca aparece (mesmo para super_admin nesta tela)
- ✓ Export PDF logado em action_log

### 9.3 LGPD
- ✓ D&I só conta quem deu consent ativo
- ✓ Revogação de consent remove pessoa do agregado
- ✓ k-anonymity ativa quando grupo < 5
- ✓ Export sem PII por default (opt-in para incluir)

### 9.4 Performance
- ✓ Headcount snapshot < 50ms
- ✓ Refresh materialized view roda em < 30s para 10k employees
- ✓ Dashboard carrega < 2s em conexão 4G

### 9.5 UI
- ✓ Filtros aplicam em todos os cards simultaneamente
- ✓ Drill-down (clicar card) leva pra detalhe
- ✓ Tooltips explicam cada métrica (definição + cálculo)

### 9.6 Integração Domínio
- ✓ Receber `payroll.closed` (M14) atualiza custo do mês
- ✓ Sem Domínio integrado, cards de custo mostram "aguardando integração"
- ✓ Falha de sync Domínio gera badge "dados de X dias atrás"

---

## 10. Roadmap pós-MVP

1. **M+3 · benchmark setorial** (anônimo) — comparar turnover/eNPS com outras PMEs do mesmo setor (cliente opt-in)
2. **M+6 · forecasting** (ARIMA simples) — projeção de headcount em 6/12m
3. **M+9 · anomaly detection** (ML) — alertas automáticos de desvios
4. **M+12 · sugestões acionáveis** — "Você está perdendo 3× mais Analistas Plenos do que outras empresas do setor — quer abrir 1:1s com os ainda na empresa?"
5. **M+18 · Compa-ratio** + bandas salariais dinâmicas
6. **M+24 · turnover predictor** — score de risco de saída por colaborador (controvertido, exige consentimento adicional + revisão DPO)

---

## 11. UI mockup (a entregar como `r2_people_analytics.html`)

Sketch da página:

```
[Hero · resumo executivo]
  Headcount: 367 (▲ +3 vs mês anterior)
  Turnover 12m: 8.2% (▼ -1.4pp)
  Custo total: R$ 487k/mês (do Domínio)
  eNPS: 62 (▲ +5)

[Filtros globais: período + EMP/TOM + dept + nível]

[5 abas]:
  ▸ Headcount (default)
    - Linha 12m c/ admissões+desligamentos+net
    - Barras horizontais por filial (14 unidades)
    - Donut efetivo/temporário
    - Card de projeção próximos 3m

  ▸ Turnover & Retenção
    - 3 KPIs: voluntário/involuntário/regretted
    - Top 5 motivos de saída
    - Curva de sobrevivência (% após 6/12/24m)
    - Heatmap por filial × motivo

  ▸ D&I (c/ k-anonymity)
    - Donut gênero total
    - Pirâmide etária
    - Gap salarial por categoria (agregado)
    - Pipeline diversidade

  ▸ Custo (do Domínio)
    - Card total c/ trend 12m
    - Tabela por filial c/ headcount + média + total
    - Histograma de faixas salariais
    - % folha sobre receita (se integrado)

  ▸ Engajamento
    - eNPS por filial vs turnover
    - 9-Box agregado vs tempo de empresa
    - PDI ativos × promoções
    - Cards de cruzamentos
```

Persona principal: **Renato Pinto · Diretor Operações** (já existe no R2). Avatar gradiente navy → orange.

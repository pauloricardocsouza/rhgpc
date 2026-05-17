# Spec D5 · Observabilidade · Logs, Métricas, Traces e SLOs

**Status**: especificação · pré-implementação
**Versão**: 1.0 · 17 de maio de 2026
**Escopo**: instrumentação aplicacional, dashboards, SLOs, alertas, runbooks
**Depende de**: schema v10, spec M12 (queue), spec D4 (DR)

---

## 1. Três pilares + um anexo

| Pilar | Sinal | Ferramenta | Retenção |
|---|---|---|---|
| **Logs** | eventos discretos (linha de texto/JSON) | Logflare (frontal Supabase) → BigQuery (frio) | 30 dias hot · 1 ano frio |
| **Métricas** | séries numéricas agregadas | Prometheus + Grafana Cloud free tier | 13 meses |
| **Traces** | spans distribuídos com timing | OpenTelemetry → Tempo (Grafana) | 7 dias |
| **Profiles** (anexo) | flamegraphs CPU/heap on-demand | Pyroscope manual | só ad-hoc |

---

## 2. Logs estruturados

### 2.1 Formato canônico (JSON line)

```json
{
  "ts":         "2026-05-17T14:32:11.842Z",
  "level":      "info",
  "service":    "next-app",
  "tenant_id":  "5b...",
  "user_id":    "8a...",
  "request_id": "01HXYZ...",
  "span_id":    "abc123",
  "trace_id":   "def456",
  "msg":        "movement.created",
  "ctx": {
    "movement_id": "...",
    "type": "PROMOTION",
    "old_salary": 5500,
    "new_salary": 6200
  },
  "latency_ms": 142
}
```

**Regras**:
- Sempre incluir `tenant_id` e `request_id`.
- `level`: trace | debug | info | warn | error | fatal.
- Dado sensível (CID, CPF, senha) **nunca** em log — usar `[REDACTED]` ou hash truncado.
- Linter custom (`scripts/lint_logs.ts`) verifica regex de CPF/CID nos arquivos de código.

### 2.2 Categorias de log

| Categoria | Exemplo | Nível padrão |
|---|---|---|
| `audit` | toda ação que afeta dado pessoal | info |
| `security` | login fail, MFA usado, token revogado | warn |
| `payment` | billing events | info |
| `integration` | webhook recebido/enviado, RH externo | info |
| `system` | startup, shutdown, migration | info |
| `performance` | query > 500ms, render > 1s | warn |
| `error` | exception não tratada | error |

### 2.3 Pipeline

```
[Next.js app]  --pino-->  stdout JSON  --Vercel drain-->  [Logflare]
[Edge Function] --console.log JSON-->  [Logflare]
[Postgres]     --auto-->  [Supabase logs]  --shipper-->  [Logflare]
[Worker Python] --structlog-->  stdout  --container drain-->  [Logflare]

Logflare → BigQuery sink (toda meia-noite) para frio.
Queries quentes via dashboard Logflare LQL.
```

---

## 3. Métricas

### 3.1 RED + USE

Para cada serviço HTTP:
- **R**equests/s
- **E**rrors/s (5xx + 4xx separado)
- **D**uration p50/p95/p99

Para cada recurso (DB, queue, cache):
- **U**tilization
- **S**aturation
- **E**rrors

### 3.2 Métricas custom de negócio

| Métrica | Tipo | Labels |
|---|---|---|
| `r2_logins_total` | counter | tenant, role, outcome |
| `r2_mfa_challenges_total` | counter | tenant, outcome |
| `r2_movements_created_total` | counter | tenant, type |
| `r2_certificates_uploaded_total` | counter | tenant, validated |
| `r2_payroll_simulations_total` | counter | tenant |
| `r2_dsar_requests_total` | counter | tenant, type |
| `r2_active_users` | gauge | tenant, last_24h |
| `r2_seats_used_ratio` | gauge | tenant |
| `r2_storage_bytes` | gauge | tenant, bucket |
| `r2_webhook_queue_depth` | gauge | tenant, queue |
| `r2_rls_denials_total` | counter | tenant, table |

`r2_rls_denials_total` é um sinal de segurança importante — picos indicam tentativa de exploit ou bug em policy.

### 3.3 Exportador

`/api/metrics` em Next.js que retorna texto Prometheus, agregando:
- `nextjs_*` runtime nativo
- `pg_stat_statements` top 50 queries
- contadores custom mantidos em memória (zerados em deploy)
- gauges puxadas via `rpc_metrics_snapshot()` no Postgres

Prometheus scrape a cada 30s. Grafana Cloud free aceita até 10k séries — suficiente para 50 tenants iniciais.

---

## 4. Traces (OpenTelemetry)

### 4.1 Spans canônicos

Cada request HTTP gera trace com pelo menos:
- `http.request` (root)
  - `next.middleware` (auth, RLS context set)
  - `next.handler` (page/api function)
    - `pg.query` (uma span por query, com sql truncado + plan se > 100ms)
    - `external.fetch` (chamadas a SMTP, webhook, etc)
  - `next.render` (apenas SSR)

### 4.2 Sampling

- **100%** das requests com erro 5xx
- **100%** das requests com latência > 2 s
- **10%** sample uniforme do resto
- **0%** de health checks e `/api/metrics`

### 4.3 Trace ID propagation

- W3C Traceparent header em todas as fetch chamadas
- Worker Python continua o trace usando `OTEL_PROPAGATORS=tracecontext`

---

## 5. SLOs (Service Level Objectives)

| Serviço | Indicador | Objetivo (30d) | Budget mensal |
|---|---|---|---|
| Login | sucesso de autenticação | 99.5 % | 3.6 h |
| API leitura (GET /api/employees/*) | latência p95 < 500ms | 99.0 % | 7.2 h |
| API escrita (POST/PUT) | latência p95 < 1s + 200/2xx | 99.0 % | 7.2 h |
| Webhook outbound | entrega em ≤ 5 min | 99.5 % | 3.6 h |
| Upload de atestado | OCR completo em ≤ 30s | 95.0 % | 36 h |
| In-app notification | aparecer em ≤ 2 s | 99.5 % | 3.6 h |
| Disponibilidade global | uptime do app principal | 99.5 % | 3.6 h |

**Política de error budget**:
- Budget consumido < 50 %: feature freeze opcional, foco em ship.
- 50-100 %: feature freeze para o serviço impactado, foco em estabilização.
- > 100 %: **freeze obrigatório**, retrospectiva semanal até voltar abaixo.

---

## 6. Dashboards Grafana

### 6.1 `Overview · platform`
- Mapa de tenants ativos (heatmap)
- Total requests/s last 1h
- Erros por classe
- Top 10 tenants por consumo
- SLO burn rate visualizando consumo do budget

### 6.2 `Tenant · drill-down` (filtro por tenant_id)
- Users ativos 24h / 7d / 30d
- Features mais usadas
- Erros vistos por este tenant
- Quota usage (seats, storage, webhooks)
- DSAR requests pendentes

### 6.3 `Postgres health`
- Connections used / max
- Cache hit ratio
- Top slow queries (pg_stat_statements)
- Bloat por tabela
- Replication lag (quando aplicável)
- WAL generation rate

### 6.4 `Queue health` (depende de M12)
- Depth por fila
- Throughput in vs out
- Latency p50/p95 de cada classe
- DLQ size
- Webhook success rate por tenant

### 6.5 `Security`
- Logins fail/sucesso por janela
- MFA challenges
- RLS denials (sinal de exploit/bug)
- Top IPs por failures
- Sessões revogadas

### 6.6 `Business`
- MRR estimado por tenant (assinatura × preço)
- Funil de onboarding (de signup até primeiro movement)
- Trial → pago conversion
- Churn (tenants inativos 30d+)

---

## 7. Alertas (Grafana Alerting)

### 7.1 Severidades

| Sev | Canal | Quem | Exemplo |
|---|---|---|---|
| **P1 critical** | PagerDuty (24/7) + SMS | on-call | DB indisponível, taxa erro 5xx > 5 % |
| **P2 high** | Slack #r2-alerts + e-mail | on-call horário comercial | Latência p95 > 2x objetivo por 10 min |
| **P3 warn** | Slack #r2-monitoring | equipe toda | Queue depth > 5k, budget 50 % consumido |
| **P4 info** | Slack #r2-monitoring | informativo | Deploy concluído, snapshot DR feito |

### 7.2 Alertas mínimos (M0 lançamento)

1. **HTTP 5xx rate** > 1 %/5min → P2; > 5 %/5min → P1
2. **DB connections used** > 80 % → P2; > 95 % → P1
3. **Webhook queue depth** > 10k → P2
4. **Disco DB** > 80 % → P2; > 90 % → P1
5. **WAL lag** > 5 min → P1 (perde RPO)
6. **Falha de smoke test backup** → P2
7. **DSAR ticket pendente > 12 dias** (LGPD 15d) → P2 (DPO direto)
8. **RLS denials** spike > 10x baseline → P2 (possível exploit)
9. **Login fail** > 100/min de um único IP → P3 (já bloqueado, mas avisa)
10. **Latência p95 login** > 2s sustentado 5min → P3

---

## 8. Runbooks (links para wiki)

Cada alerta tem um runbook com 4 seções:
1. **Sintomas** · o que o alerta diz, gráficos relacionados
2. **Diagnóstico** · queries para confirmar/refutar causa
3. **Mitigação** · ações para reduzir impacto rapidamente
4. **Resolução** · correção definitiva e como prevenir

Exemplo de estrutura:

```markdown
# Runbook · DB connections > 95%

## Sintomas
- Alerta P1 disparado
- Usuários reportam "Internal Server Error" em massa
- Gráfico `pg_connections_used` no dashboard "Postgres health"

## Diagnóstico
```sql
SELECT state, count(*) FROM pg_stat_activity GROUP BY state;
SELECT pid, usename, application_name, query_start, state, query
FROM pg_stat_activity WHERE state != 'idle' ORDER BY query_start;
```
- Identificar app/usuário com mais conexões
- Procurar long-running queries

## Mitigação
- `SELECT pg_terminate_backend(pid)` em queries > 5min sem progresso
- Pausar workers de fila temporariamente

## Resolução
- Audit do código que vazou pool
- Considerar aumentar `max_connections` ou usar pgBouncer transaction mode
```

---

## 9. Tabelas no Postgres

```sql
-- SLO tracking
CREATE TABLE slo_violations (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  service     text NOT NULL,
  indicator   text NOT NULL,
  observed    numeric,
  target      numeric,
  budget_used_pct numeric,
  detected_at timestamptz NOT NULL DEFAULT now(),
  resolved_at timestamptz
);

-- Incidentes (postmortems indexados)
CREATE TABLE incidents (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  title           text NOT NULL,
  severity        text NOT NULL CHECK (severity IN ('P1','P2','P3','P4')),
  started_at      timestamptz NOT NULL,
  detected_at     timestamptz NOT NULL,
  mitigated_at    timestamptz,
  resolved_at     timestamptz,
  affected_tenants uuid[],
  affected_users_estimate int,
  root_cause      text,
  contributing_factors text[],
  postmortem_url  text,
  created_by      uuid REFERENCES auth.users(id),
  created_at      timestamptz NOT NULL DEFAULT now()
);

-- Métrica snapshot (cache de leituras pesadas pro dashboard)
CREATE TABLE metric_snapshots (
  metric_name text NOT NULL,
  labels      jsonb NOT NULL DEFAULT '{}',
  value       numeric NOT NULL,
  taken_at    timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (metric_name, labels, taken_at)
);

CREATE INDEX idx_metric_snapshots_recent ON metric_snapshots (metric_name, taken_at DESC);
```

---

## 10. Custos estimados (mensal, 50 tenants)

| Item | Provedor | Custo |
|---|---|---|
| Logflare (Pro 1B events/m) | Logflare | US$ 250 |
| BigQuery (frio + queries ad-hoc) | GCP | US$ 30 |
| Grafana Cloud (10k séries, 50GB logs) | Grafana | Free |
| Tempo (traces 7d, ~2M spans/dia) | Grafana | Free tier |
| PagerDuty (3 seats) | PagerDuty | US$ 60 |
| **Total** | | **~US$ 340/mês** |

A US$ 50/tenant/mês de ARPU em 50 tenants = US$ 2.500. Observability fica em ~14 % do revenue — aceitável.

---

## 11. Testes meta (mínimo 20)

- ✓ Log linter detecta CPF em código (`fail CI`)
- ✓ Pino redact strip campos `password|cpf|cid|token`
- ✓ Request ID propagado em todos os logs do request
- ✓ Trace ID propagado em todos os logs do request
- ✓ `/api/metrics` retorna exposition format válida
- ✓ Counter `r2_logins_total` incrementa em login real
- ✓ Span `pg.query` criado em cada query > 100ms
- ✓ Sampling 100% para 5xx mesmo com sample geral 10%
- ✓ Sampling 0% para `/api/metrics`
- ✓ SLO violation gravada em `slo_violations` quando budget < 0
- ✓ Alerta P1 dispara webhook PagerDuty (smoke test)
- ✓ Alerta P3 vai só pro Slack
- ✓ Quiet hours não bloqueia P1
- ✓ Métrica `r2_rls_denials_total` incrementa em policy denial
- ✓ Snapshot Postgres rodando a cada 1min sem lag > 10s
- ✓ Dashboard "Tenant drill-down" carrega < 2s para tenant de 367 users
- ✓ Trace search retorna span correto por trace_id em < 1s
- ✓ BigQuery sink rodando madrugada sem perda
- ✓ Retenção respeita 30d quente / 1y frio em Logflare
- ✓ Postmortem template gera issue automaticamente em incidents tabela

---

## 12. Roadmap pós-MVP

1. **Real User Monitoring (RUM)** — Sentry/SigNoz para sinais lado-cliente.
2. **Synthetic monitoring** — checks externos a cada 1min de fluxos críticos (login, abrir ficha, exportar relatório).
3. **Anomaly detection** ML-driven em métricas custom (queda inesperada de movements/dia, picos atípicos de uploads).
4. **Cost observability per tenant** — atribuir consumo de DB/storage/queue a cada tenant para billing por uso.
5. **Customer-facing status page** — `status.solucoesr2.com.br` automatizada via incidents tabela.

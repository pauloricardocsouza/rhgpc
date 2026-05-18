# Spec M14 · Webhooks Inbound · Receber Eventos de Sistemas Externos

**Status**: especificação · pré-implementação
**Versão**: 1.0 · 18 de maio de 2026
**Escopo**: motor de recebimento de eventos vindos de ERP de folha, sistema de ponto, AD/SSO, BI externo
**Depende de**: spec M12 (webhooks outbound), spec D6 (security/HMAC), spec D8 (isolamento), schema v9+ (tenant_webhooks)

---

## 1. Visão geral

Enquanto a spec M12 cobre **webhooks que R2 envia** (`movement.created` → ERP folha), este spec cobre o **inverso**: eventos do ERP/ponto/AD chegando ao R2 People. Casos de uso primários:

| Origem | Evento | Ação em R2 People |
|---|---|---|
| ERP folha (Senior/Totvs) | `payroll.closed` | Marca movement como pago, atualiza payroll_runs |
| Sistema ponto | `attendance.absent` | Cruza com atestados, sugere validação |
| AD/Azure AD | `user.created` | Cria placeholder de employee para onboarding |
| AD/Azure AD | `user.deactivated` | Marca employee como terminated + dispara workflow |
| ERP folha | `salary.adjusted` | Cria movement do tipo `SALARY_ADJUSTMENT` para audit |
| Sistema gestão | `branch.created` | Adiciona nova unidade no organograma |

---

## 2. Endpoint e segurança

### 2.1 Endpoint único por tenant

```
POST https://api.r2-people.com/v1/webhooks/inbound/{tenant_slug}
```

- **Sem auth por bearer token** — autenticação é via HMAC assinada (mesmo padrão dos outbound da M12)
- **Cada tenant** tem 1+ `inbound_webhook_endpoints` configurados com `signing_secret` próprio

### 2.2 HMAC inbound (signing)

Cliente (ERP) assina o body antes de enviar:

```
POST /v1/webhooks/inbound/gpc HTTP/1.1
Content-Type: application/json
X-R2-Source: senior-rm
X-R2-Event: payroll.closed
X-R2-Event-Id: erp-2026-05-18-001
X-R2-Timestamp: 1747512000
X-R2-Signature: sha256=8a3f9c2b...e7d1
User-Agent: SeniorRM-Webhook/2.4

{"period":"2026-05","total":487223.50,"employees_count":367}
```

R2 valida:
- `X-R2-Signature` confere com `HMAC_SHA256(signing_secret, timestamp + body)`
- `X-R2-Timestamp` está dentro de janela de 5 minutos (evita replay)
- `X-R2-Event-Id` é único (idempotência — guardado em `inbound_event_dedupe`)

Resposta padrão:
- `202 Accepted` — recebido, será processado async
- `400 Bad Request` — payload mal-formado, **não retentar**
- `401 Unauthorized` — assinatura inválida, **não retentar**
- `409 Conflict` — `event_id` já processado (idempotência), retornar `processed_at`
- `500 Internal Server Error` — erro nosso, **retentar com backoff**

### 2.3 IP allowlist (opcional)

Tenant pode opcionalmente configurar lista de IPs origem permitidos:

```sql
ALTER TABLE inbound_webhook_endpoints
  ADD COLUMN allowed_ips inet[] DEFAULT NULL;
```

Se NULL: aceita de qualquer IP (HMAC é suficiente). Se preenchido: rejeita IPs fora da lista com `403 Forbidden`.

---

## 3. Schema

```sql
-- Configuração de endpoints inbound
CREATE TABLE IF NOT EXISTS inbound_webhook_endpoints (
  id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id         uuid NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  name              text NOT NULL,         -- "ERP Folha Senior · prod"
  source_system     text NOT NULL,         -- 'senior_rm', 'totvs', 'sankhya', 'azure_ad', 'ponto_dimep', 'custom'
  signing_secret    text NOT NULL,         -- gerado pelo R2 e mostrado uma vez
  signing_secret_rotated_at timestamptz,
  allowed_ips       inet[],                -- IP allowlist opcional
  active            boolean NOT NULL DEFAULT true,
  subscribed_events text[] NOT NULL DEFAULT ARRAY['*'],  -- glob patterns
  created_by        uuid REFERENCES auth.users(id),
  created_at        timestamptz NOT NULL DEFAULT now(),
  last_received_at  timestamptz,
  UNIQUE (tenant_id, name)
);

-- Log de eventos recebidos (full audit, retenção 90 dias quente + 1 ano frio)
CREATE TABLE IF NOT EXISTS inbound_events_log (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  endpoint_id     uuid NOT NULL REFERENCES inbound_webhook_endpoints(id) ON DELETE CASCADE,
  tenant_id       uuid NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  event_id        text NOT NULL,         -- id fornecido pelo emissor
  event_type      text NOT NULL,         -- 'payroll.closed', etc
  payload         jsonb NOT NULL,
  payload_size_bytes int NOT NULL,
  signature_valid boolean NOT NULL,
  remote_ip       inet,
  user_agent      text,
  received_at     timestamptz NOT NULL DEFAULT now(),
  processed_at    timestamptz,
  process_status  text CHECK (process_status IN ('pending','processing','success','failed','rejected','duplicate')),
  process_error   text,
  process_attempts int NOT NULL DEFAULT 0
);

CREATE INDEX idx_inbound_pending ON inbound_events_log (received_at)
  WHERE process_status IN ('pending','processing');
CREATE INDEX idx_inbound_endpoint ON inbound_events_log (endpoint_id, received_at DESC);
CREATE UNIQUE INDEX idx_inbound_dedupe ON inbound_events_log (endpoint_id, event_id);

-- Dedupe rápido (cache em memória / TTL 7 dias)
CREATE TABLE IF NOT EXISTS inbound_event_dedupe (
  endpoint_id  uuid NOT NULL,
  event_id     text NOT NULL,
  received_at  timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (endpoint_id, event_id)
);

-- Mapeamento evento -> handler
CREATE TABLE IF NOT EXISTS inbound_event_handlers (
  source_system    text NOT NULL,
  event_type       text NOT NULL,
  handler_function text NOT NULL,         -- nome da RPC que processa
  description      text,
  active           boolean DEFAULT true,
  PRIMARY KEY (source_system, event_type)
);
```

---

## 4. Pipeline de processamento

```
[ERP externo]
    │ POST + HMAC
    ▼
[API Gateway / Edge Function]
    │ valida HMAC + timestamp + dedupe
    ▼
[INSERT em inbound_events_log] status='pending'
    │
    │ returns 202 Accepted (ou 409 dedupe)
    ▼
[pgmq queue 'q_inbound_events']
    │
    ▼
[worker-inbound]
    │ pega msg, busca handler em inbound_event_handlers
    │ chama handler_function(payload)
    │
    ├── success → UPDATE process_status='success', processed_at=now()
    ├── failed retentável → reque com backoff (até 5 tentativas)
    └── failed terminal → status='failed', alerta P3
```

---

## 5. Handlers padrão (RPCs)

### 5.1 `rpc_handle_payroll_closed`

```sql
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
  v_total numeric := (p_payload->>'total')::numeric;
  v_run_id uuid;
BEGIN
  -- Atualiza payroll_runs do tenant
  INSERT INTO payroll_runs (tenant_id, period, total_brl_cents, status, closed_at, source)
  VALUES (p_tenant_id, v_period, (v_total * 100)::int, 'closed', now(), 'erp_inbound')
  ON CONFLICT (tenant_id, period) DO UPDATE SET
    total_brl_cents = EXCLUDED.total_brl_cents,
    status = 'closed',
    closed_at = EXCLUDED.closed_at
  RETURNING id INTO v_run_id;

  -- Marca todas as movements do período como pagas
  UPDATE movements
  SET payroll_status = 'paid', payroll_run_id = v_run_id
  WHERE tenant_id = p_tenant_id
    AND effective_date >= make_date(
      split_part(v_period, '-', 1)::int,
      split_part(v_period, '-', 2)::int,
      1
    )
    AND effective_date < (make_date(
      split_part(v_period, '-', 1)::int,
      split_part(v_period, '-', 2)::int,
      1
    ) + interval '1 month');

  RETURN v_run_id;
END;
$$;
```

### 5.2 `rpc_handle_user_deactivated_from_ad`

Quando AD desativa usuário, R2 marca employee como terminated e dispara workflow LGPD (suspende acesso imediato, agenda hard delete CLT-compliant).

### 5.3 `rpc_handle_attendance_absent`

Quando ponto registra ausência:
1. Procura atestado validado para a data
2. Se sim: cria registro `attendance_justification` automaticamente
3. Se não: cria task pra líder "ausência sem justificativa: validar"

### 5.4 Outros handlers (skeleton)

- `rpc_handle_branch_created` (ERP cria filial → R2 adiciona unidade)
- `rpc_handle_salary_adjusted` (ERP ajusta salário → cria movement audit)
- `rpc_handle_certificate_validated` (sistema externo valida atestado → marca em R2)
- `rpc_handle_user_created_from_ad` (AD cria user → R2 cria placeholder employee)

---

## 6. UI · página `r2_people_webhooks_inbound.html` (parte do cockpit Notif)

Aba **Endpoints** (configuração):
- Lista de endpoints configurados c/ source_system, signing_secret (mostrado 1x), allowed_ips, subscribed_events
- Botão "+ Novo endpoint" com wizard de 3 passos (nome → sistema origem → eventos assinados)
- Botão "Rotacionar secret" com grace period 7d (chave antiga aceita por 7d antes de revogar)
- Botão "Testar HMAC" — manda payload de teste assinado para validar configuração

Aba **Eventos recebidos** (log):
- Tabela paginada `inbound_events_log` filtros: source, event_type, status, período
- Cada linha: timestamp, source, event_type, status badge, payload preview (JSON collapse), botão "Reprocessar"
- Click expande linha mostrando: full payload, signature_valid, IP, UA, attempts, error

Aba **Handlers** (catálogo):
- Lista `inbound_event_handlers` mostrando mapping source_system × event_type → função handler
- Coluna "Status" mostra se handler está ativo
- Click no handler abre código fonte (read-only) ou documentação

---

## 7. Idempotência e replay

### 7.1 Dedupe inicial

Antes de processar, checa em `inbound_event_dedupe`:

```sql
INSERT INTO inbound_event_dedupe (endpoint_id, event_id)
VALUES ($1, $2)
ON CONFLICT (endpoint_id, event_id) DO NOTHING
RETURNING 1;
```

Se retornou 0 linhas → já existe, retorna `409 Conflict` ao cliente sem reprocessar.

### 7.2 Replay manual

Admin pode forçar reprocessamento de evento via:

```sql
-- Marca para reprocessar (limpa status)
UPDATE inbound_events_log
SET process_status = 'pending', process_attempts = 0, process_error = NULL
WHERE id = $1;

-- Worker pega na próxima iteração
```

**Importante**: replay assume idempotência do handler. Cada handler precisa ser idempotente (testes meta cobrem isso).

### 7.3 Limpeza periódica

Cron mensal:
- Move `inbound_events_log` > 90d para `_archive`
- Apaga de `inbound_event_dedupe` registros > 7d (TTL curto, só serve para dedupe imediato)

---

## 8. Rate limiting inbound

Cada endpoint tem limites independentes:

| Janela | Limite default | Configurável? |
|---|---|---|
| Por endpoint, 1s | 50 events | sim |
| Por endpoint, 1min | 1.000 events | sim |
| Por endpoint, 1h | 30.000 events | sim |

Excesso → `429 Too Many Requests` com header `Retry-After`.

Plano Starter: cap absoluto 5k events/dia · Pro: 50k/dia · Enterprise: 1M/dia.

---

## 9. Observabilidade (integra spec D5)

| Métrica | Tipo | Labels |
|---|---|---|
| `r2_inbound_received_total` | counter | tenant, source, event_type |
| `r2_inbound_processed_total` | counter | tenant, source, event_type, status |
| `r2_inbound_processing_ms` | histogram | source, event_type |
| `r2_inbound_signature_invalid_total` | counter | tenant, source, remote_ip |
| `r2_inbound_dedupe_hits_total` | counter | tenant, source |
| `r2_inbound_queue_depth` | gauge | — |

Alertas:
- Signature invalid > 10/min do mesmo IP → P2 (possível ataque)
- Queue depth > 5k → P2
- Handler error rate > 5% último 1h → P3
- Endpoint sem eventos > 7d quando esperado ≥ 1/dia → P3 (cliente ERP parou de enviar?)

---

## 10. RLS

```sql
ALTER TABLE inbound_webhook_endpoints ENABLE ROW LEVEL SECURITY;
CREATE POLICY iwe_tenant_isolation ON inbound_webhook_endpoints
  FOR ALL USING (tenant_id = (current_setting('app.tenant_id', true))::uuid);

ALTER TABLE inbound_events_log ENABLE ROW LEVEL SECURITY;
CREATE POLICY iel_tenant_isolation ON inbound_events_log
  FOR ALL USING (tenant_id = (current_setting('app.tenant_id', true))::uuid);

-- signing_secret nunca vai pro client (só via RPC controlada)
REVOKE SELECT (signing_secret) ON inbound_webhook_endpoints FROM authenticated;
```

`signing_secret` é mostrado **uma única vez** na criação via RPC `rpc_create_inbound_endpoint()` que retorna o secret em texto claro. Depois disso, só `service_role` lê (workers validam HMAC).

---

## 11. Catálogo de fontes suportadas

| Sistema | Sigla | Eventos cobertos | Doc cliente |
|---|---|---|---|
| Senior RM | `senior_rm` | payroll.closed, salary.adjusted, branch.created | `docs/integrations/senior_rm.md` |
| Totvs Protheus | `totvs` | payroll.closed, employee.transferred | `docs/integrations/totvs.md` |
| Sankhya | `sankhya` | payroll.closed | `docs/integrations/sankhya.md` |
| Domínio Sistemas | `dominio` | payroll.closed | `docs/integrations/dominio.md` |
| Azure Active Directory | `azure_ad` | user.created, user.deactivated, group.assigned | `docs/integrations/azure_ad.md` |
| Google Workspace | `google_workspace` | user.created, user.suspended | `docs/integrations/google.md` |
| Dimep PontoSecullum | `ponto_dimep` | attendance.absent, attendance.delayed | `docs/integrations/dimep.md` |
| Ahgora | `ponto_ahgora` | attendance.absent | `docs/integrations/ahgora.md` |
| Custom | `custom` | qualquer evento contratado | `docs/integrations/custom_guide.md` |

Cada doc cliente inclui:
- URL do endpoint
- Como gerar/usar signing_secret
- Exemplo de request curl
- Exemplo de signing em Python/PHP/Node
- Códigos de resposta + retry policy

---

## 12. Testes meta (mínimo 25)

### 12.1 Segurança
- ✓ Request sem `X-R2-Signature` retorna 401
- ✓ Signature inválida retorna 401 e incrementa metric
- ✓ Timestamp > 5min antigo retorna 401 (anti-replay)
- ✓ IP fora de allowed_ips retorna 403
- ✓ Endpoint `active=false` retorna 410 Gone
- ✓ Dedupe: mesmo event_id retorna 409 sem reprocessar

### 12.2 Pipeline
- ✓ Request válido grava em `inbound_events_log` com status pending
- ✓ Worker processa pending em < 30s
- ✓ Handler de sucesso seta status=success + processed_at
- ✓ Handler de falha retenta com backoff exponencial
- ✓ Após 5 falhas → status=failed + alerta P3
- ✓ Queue depth visível em métrica

### 12.3 Handlers
- ✓ payroll.closed atualiza payroll_runs + marca movements como pagas
- ✓ user.deactivated marca employee terminated + dispara workflow LGPD
- ✓ attendance.absent cria justification se atestado existe, senão cria task líder
- ✓ Cada handler é idempotente (replay 2× = mesmo resultado)
- ✓ Handler com payload inválido marca rejected (não retenta)

### 12.4 Rate limit
- ✓ 51º request no mesmo segundo retorna 429
- ✓ Cap diário do plano respeitado (Starter 5k, Pro 50k)
- ✓ Reset de contador funciona após janela

### 12.5 RLS
- ✓ Tenant A não vê inbound_events_log do tenant B
- ✓ signing_secret bloqueado para role `authenticated` (só service_role lê)
- ✓ Replay manual respeita RLS (admin de A não replaya evento de B)

### 12.6 UI
- ✓ Criar endpoint mostra signing_secret 1x e nunca mais
- ✓ Rotacionar secret aceita ambos por 7d
- ✓ Testar HMAC valida config sem criar evento real

---

## 13. Roadmap pós-MVP

1. **Schema registry** (validação JSON schema por event_type)
2. **Webhook chaining** (evento inbound dispara webhook outbound automaticamente)
3. **Transform pipeline** (JSONPath/jq para mapear payload externo → estrutura R2)
4. **Replay em batch** (UI para reprocessar últimas 24h de um endpoint)
5. **DLQ inbound** (eventos failed armazenados separadamente para análise)
6. **Connector marketplace** (templates prontos para integrações comuns)

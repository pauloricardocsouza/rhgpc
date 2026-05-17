# Spec M12 · Notificações & Webhooks · Runtime de Entrega

**Status**: especificação · pré-implementação
**Versão**: 1.0 · 17 de maio de 2026
**Escopo**: motor de entrega de notificações in-app, e-mail, push e webhooks de saída
**Depende de**: schema v9 (`notifications`), schema v10 (`tenant_webhooks`), spec M10

---

## 1. Visão geral

O sistema precisa entregar três classes de mensagens com garantias e SLAs distintos:

| Classe | Exemplo | Canal padrão | Garantia | SLA |
|---|---|---|---|---|
| **In-app** | "Sua promoção foi aprovada" | sino + tela | at-least-once em <1s | imediato |
| **Transacional pessoal** | "Você foi marcado em um 1:1" | e-mail | at-least-once em <2min | 2 min |
| **Webhook de saída** | "movement.created" → ERP cliente | HTTP POST assinado | at-least-once com retry exponencial 24h | 5 min p95 |

Filas separadas por classe permitem **degradação graciosa**: webhook em retry não atrasa notificação in-app.

---

## 2. Arquitetura de filas

```
[App] --emit-->  [pg_notify(channel, payload)]
                     |
                     v
              [Worker dispatch] --classify--> 3 filas pgmq
                                                |  |  |
                                                v  v  v
                                          [in-app][email][webhook]
                                                |  |  |
                                                v  v  v
                                          [WS push][SMTP][HTTP+HMAC]
                                                |  |  |
                                                v  v  v
                                          [ack ou DLQ após N tentativas]
```

Usamos a extensão **pgmq** (PGMQ — Postgres Message Queue) já disponível em Supabase. Três filas:

- `q_notif_inapp` · 3 tentativas, visibility 30s
- `q_notif_email` · 5 tentativas, visibility 5min
- `q_notif_webhook` · 8 tentativas, visibility com backoff exponencial (30s → 24h)

DLQ separada por classe: `dlq_notif_*` para inspeção manual.

---

## 3. Tabelas auxiliares

```sql
-- Idempotência de webhook outbound
-- O cliente pode ver o mesmo evento N vezes (retry), mas o event_id é único
CREATE TABLE webhook_delivery_log (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  webhook_id      uuid NOT NULL REFERENCES tenant_webhooks(id) ON DELETE CASCADE,
  event_id        uuid NOT NULL,                  -- mesmo UUID em retries
  event_type      text NOT NULL,                  -- "movement.created", etc
  payload         jsonb NOT NULL,
  attempt         int  NOT NULL DEFAULT 1,
  status          text NOT NULL CHECK (status IN ('pending','success','failed','dead')),
  http_status     int,
  response_ms     int,
  response_body   text,                           -- truncado em 4KB
  error_msg       text,
  next_retry_at   timestamptz,
  delivered_at    timestamptz,
  created_at      timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX idx_webhook_log_pending ON webhook_delivery_log (next_retry_at)
  WHERE status = 'pending';
CREATE INDEX idx_webhook_log_event ON webhook_delivery_log (webhook_id, event_id);

-- E-mails enviados (auditoria + dedup)
CREATE TABLE email_delivery_log (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id       uuid NOT NULL REFERENCES tenants(id),
  user_id         uuid REFERENCES auth.users(id),
  to_addr         text NOT NULL,
  template        text NOT NULL,                  -- "movement_approved", etc
  context         jsonb,
  subject         text NOT NULL,
  provider        text NOT NULL,                  -- "sendgrid","resend","ses"
  provider_msg_id text,
  status          text NOT NULL CHECK (status IN ('queued','sent','bounced','complained','rejected')),
  attempt         int  NOT NULL DEFAULT 1,
  error_msg       text,
  sent_at         timestamptz,
  created_at      timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX idx_email_log_tenant ON email_delivery_log (tenant_id, created_at DESC);

-- Throttle por destinatário (evita spam)
-- Ex: máx 20 e-mails para o mesmo user em 1h
CREATE TABLE notification_throttle (
  user_id    uuid NOT NULL REFERENCES auth.users(id),
  bucket_at  timestamptz NOT NULL,                -- truncado pra hora
  count      int  NOT NULL DEFAULT 0,
  PRIMARY KEY (user_id, bucket_at)
);
```

---

## 4. Lifecycle de um evento

### 4.1 Emissão (no app)

```sql
-- O app insere em notifications + enfileira em todas as filas relevantes
SELECT rpc_emit_notification(
  p_tenant_id  := :tenant_id,
  p_event_type := 'movement.created',
  p_actor_id   := :actor_user_id,
  p_targets    := array[:approver_user_id],
  p_payload    := jsonb_build_object(
    'movement_id', :mov_id,
    'employee_name', :employee_name,
    'type', 'PROMOTION'
  ),
  p_priority   := 'normal'   -- 'low','normal','high','critical'
);
```

A RPC `rpc_emit_notification`:
1. INSERT em `notifications` (uma linha por target).
2. INSERT em `q_notif_inapp` (sempre, 1 mensagem por target).
3. Para cada target: verifica preferência → enfileira em `q_notif_email` se aplicável.
4. Busca webhooks do tenant que assinam `movement.created` → enfileira em `q_notif_webhook`.
5. Retorna `notification_id` para o app.

### 4.2 Processamento worker

Cada classe tem um worker dedicado (Edge Function ou container Node):

**worker-inapp**
```ts
while (true) {
  const msg = await pgmq.read('q_notif_inapp', visibility=30)
  if (!msg) { await sleep(1000); continue }
  try {
    // Realtime via Supabase channels
    await realtime.broadcast(`user:${msg.target_id}`, msg.payload)
    await pgmq.delete('q_notif_inapp', msg.msg_id)
  } catch (e) {
    if (msg.read_ct >= 3) await pgmq.archive('q_notif_inapp', msg.msg_id) // → DLQ
    // senão deixa expirar visibility e tenta de novo
  }
}
```

**worker-email**
```ts
while (true) {
  const msg = await pgmq.read('q_notif_email', visibility=300)
  if (!msg) continue

  // Throttle check
  const used = await throttleGet(msg.user_id, hour())
  if (used >= 20) {
    await pgmq.archive('q_notif_email', msg.msg_id)
    log('throttled', msg)
    continue
  }

  const tpl = await render(msg.template, msg.context)
  const provider = pickProvider() // failover sendgrid → resend
  try {
    const r = await provider.send({ to: msg.to_addr, subject: tpl.subject, html: tpl.html })
    await emailLog({ status: 'sent', provider_msg_id: r.id, ... })
    await throttleInc(msg.user_id, hour())
    await pgmq.delete('q_notif_email', msg.msg_id)
  } catch (e) {
    if (msg.read_ct >= 5) { await emailLog({ status: 'rejected', error_msg: e.message }); await pgmq.archive('q_notif_email', msg.msg_id) }
  }
}
```

**worker-webhook**
```ts
while (true) {
  const msg = await pgmq.read('q_notif_webhook', visibility = backoff(msg.read_ct))
  if (!msg) continue

  const wh = await loadWebhook(msg.webhook_id)
  if (!wh.active) { await pgmq.delete('q_notif_webhook', msg.msg_id); continue }

  const body = JSON.stringify(msg.payload)
  const sig  = hmacSha256(wh.signing_secret, msg.event_id + body)   // X-R2-Signature

  const t0 = Date.now()
  try {
    const r = await fetch(wh.url, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'X-R2-Event': msg.event_type,
        'X-R2-Event-Id': msg.event_id,
        'X-R2-Signature': sig,
        'User-Agent': 'R2People-Webhook/1.0'
      },
      body
    })
    const ok = r.status >= 200 && r.status < 300
    await deliveryLog({
      webhook_id: msg.webhook_id,
      event_id: msg.event_id,
      attempt: msg.read_ct,
      status: ok ? 'success' : 'failed',
      http_status: r.status,
      response_ms: Date.now() - t0,
      response_body: (await r.text()).slice(0, 4000)
    })
    if (ok) await pgmq.delete('q_notif_webhook', msg.msg_id)
    else if (msg.read_ct >= 8) await markDead(msg)
    // else: expira visibility, próximo retry com backoff maior
  } catch (e) {
    await deliveryLog({ status:'failed', error_msg: e.message, attempt: msg.read_ct })
    if (msg.read_ct >= 8) await markDead(msg)
  }
}

function backoff(attempt: number): number {
  // 30s, 1min, 5min, 15min, 1h, 3h, 12h, 24h
  return [30, 60, 300, 900, 3600, 10800, 43200, 86400][attempt - 1] || 86400
}
```

---

## 5. HMAC signing (webhook outbound)

Para o cliente verificar autenticidade:

```python
# Lado do cliente
import hmac, hashlib

def verify(req):
    signing_secret = os.getenv('R2_WEBHOOK_SECRET')
    event_id = req.headers['X-R2-Event-Id']
    body = req.body
    expected = hmac.new(
        signing_secret.encode(),
        (event_id + body).encode(),
        hashlib.sha256
    ).hexdigest()
    return hmac.compare_digest(expected, req.headers['X-R2-Signature'])
```

Documentação cliente: `docs/webhook_integration_guide.md` (a criar).

---

## 6. Catálogo de eventos

| Evento | Trigger | Payload-resumo | Audiência típica |
|---|---|---|---|
| `movement.created` | INSERT em movements | id, employee_id, type, effective_date | ERP folha, BI |
| `movement.approved` | UPDATE movements SET status='approved' | id, approved_by | ERP folha |
| `employee.admitted` | INSERT em employees | id, full_name, position_id, admission_date | ERP folha, AD |
| `employee.terminated` | UPDATE employees SET status='terminated' | id, termination_date, type | ERP folha, AD, revogar SSO |
| `certificate.uploaded` | INSERT em medical_certificates | id, employee_id, days, type | sistema ponto |
| `certificate.validated` | UPDATE status='approved' | id, validated_by | sistema ponto |
| `payroll.simulated` | rpc_simulate_payroll | total_cost, headcount, period | dashboard externo |
| `oneonone.scheduled` | INSERT em oneonones | id, leader_id, member_id, scheduled_at | calendário |
| `okr.checkin` | INSERT em okr_checkins | okr_id, progress, confidence | BI |
| `nps.responded` | INSERT em nps_responses (anônimo) | tenant_id, score_bucket | BI agregado |

Lista versionada em código e expostas via `GET /api/webhook-events`.

---

## 7. Preferências por usuário

Tabela `user_notification_prefs` (já no schema v9) extendida:

```sql
ALTER TABLE user_notification_prefs ADD COLUMN IF NOT EXISTS
  quiet_hours_start time,
  quiet_hours_end   time,
  quiet_timezone    text DEFAULT 'America/Sao_Paulo',
  digest_mode       text CHECK (digest_mode IN ('realtime','hourly','daily','off')) DEFAULT 'realtime';
```

- **Quiet hours**: e-mails dentro da janela são empilhados e enviados em digest no fim do quiet.
- **Digest mode 'daily'**: tudo do dia consolidado em 1 e-mail às 08:00 BRT.
- **'off'**: só in-app, nunca e-mail (exceto críticos: termo de aceite, MFA recovery).

---

## 8. RPCs principais

```sql
-- Emitir
rpc_emit_notification(p_tenant_id, p_event_type, p_actor_id, p_targets[], p_payload, p_priority)
  RETURNS uuid[]

-- Marcar lida (in-app)
rpc_mark_notification_read(p_notification_id) RETURNS void

-- Marcar todas lidas
rpc_mark_all_read(p_tenant_id) RETURNS int

-- Reenviar webhook (admin)
rpc_replay_webhook(p_delivery_log_id) RETURNS uuid

-- Estatísticas para dashboard admin
rpc_webhook_stats(p_tenant_id, p_days int DEFAULT 7)
  RETURNS TABLE (webhook_id uuid, total int, success int, failed int, p50_ms int, p95_ms int)
```

---

## 9. UI · página `r2_people_notificacoes_admin.html` (a criar)

Aba 1 · **Webhooks**: lista CRUD com health badge (verde/amarelo/vermelho), botão "Testar", botão "Replay último 24h".

Aba 2 · **E-mails enviados**: log paginado com filtro por user/template/status, ações "Reenviar" e "Marcar como bounced".

Aba 3 · **Filas**: counts ao vivo de `q_notif_*` e DLQs, com botão "Reprocessar DLQ" (only super_admin).

Aba 4 · **Stats**: gráfico de latência p50/p95, taxa de erro por evento, top destinatários, top webhooks falhando.

---

## 10. Testes meta (mínimo 30)

### 10.1 Emissão
- ✓ Emit cria 1 linha em `notifications` por target
- ✓ Emit não enfileira e-mail se `digest_mode = 'off'`
- ✓ Emit sempre enfileira webhook se tenant tem hook ativo
- ✓ Crítico bypassa preferências (force send)

### 10.2 Worker in-app
- ✓ Mensagem visível em <1s no canal Realtime
- ✓ Após 3 falhas → DLQ
- ✓ Idempotente (mesmo msg_id processado 2x → 1 broadcast)

### 10.3 Worker e-mail
- ✓ Throttle bloqueia 21º e-mail/hora por user
- ✓ Failover SendGrid → Resend em erro 5xx
- ✓ Quiet hours respeitadas (postpone até fim)
- ✓ Digest diário agrega N eventos em 1 e-mail

### 10.4 Worker webhook
- ✓ HMAC válido com event_id + body
- ✓ Backoff exponencial respeitado entre retries
- ✓ Após 8 falhas → status='dead' + DLQ
- ✓ `webhook.active=false` descarta sem tentar
- ✓ Response > 4KB é truncado no log

### 10.5 Idempotência ponta-a-ponta
- ✓ Cliente recebe mesmo event_id em retries (header X-R2-Event-Id estável)
- ✓ Replay manual via RPC reusa event_id original
- ✓ DELETE em tenant_webhooks cascateia → drain de fila

### 10.6 Compliance
- ✓ Email com dado sensível (CID, salário) só vai se `email_safe = true` no template
- ✓ Webhook payload nunca contém CID exceto se hook tem flag `allow_medical_data` (auditado)

---

## 11. Métricas / observabilidade

| Métrica | Tipo | Alerta |
|---|---|---|
| `notif_queue_depth{class}` | gauge | depth > 10k por 5min |
| `notif_processed_total{class,status}` | counter | erro > 10 %/5min |
| `webhook_delivery_ms_p95` | histogram | > 30s |
| `webhook_dead_total` | counter | > 0 em 1h → revisar |
| `email_bounce_rate` | ratio | > 5 % por dia |

Exportadas via `pg_stat_statements` + agregação na função `rpc_metrics_export()` consumida por Logflare.

---

## 12. Roadmap pós-MVP

1. **Push mobile** (PWA + Firebase Cloud Messaging) — novo worker `worker-push`.
2. **SMS** para 2FA e alertas críticos (Zenvia/Twilio com fallback).
3. **WhatsApp Business** via WAHA — canal preferencial de muitos colaboradores.
4. **In-app rich notifications** (com ação inline: aprovar/rejeitar sem sair do sino).
5. **Webhook signing por tenant rotação** — botão "Rotate secret" com grace period 24h.

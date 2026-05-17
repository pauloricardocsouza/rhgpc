# Spec · M10 · Configurações do tenant

**Status:** UI já existe (`r2_people_configuracoes.html` · 6 abas) · falta backend completo
**Pré-requisitos:** D1 (Auth), M1 (Estrutura), B2 (módulos admin) aplicados
**Estimativa:** 1 sessão (~3-4h)

---

## 1. Objetivo

Portar para Next.js a tela de **Configurações do tenant** · controle administrativo de:

| Aba | O que controla |
|---|---|
| **Geral** | Nome, fuso horário, idioma, data de criação |
| **Branding** | Logo, cores primárias, slogan |
| **Notificações** | Quais eventos disparam notif in-app, digest mode |
| **Integrações** | Webhooks, API keys, SSO providers (link pro D2) |
| **Billing** | Plano contratado, próxima fatura, método de pagamento |
| **Workspace** | Configurações de cada módulo ativo |

| Tela origem | Página Next.js |
|---|---|
| `r2_people_configuracoes.html` | `/admin/configuracoes` |

---

## 2. Schema · migration 00500_m10_tenant_settings.sql

A tabela `tenants` (criada em H base) tem apenas campos básicos. Estender:

```sql
-- ALTER em tenants pra adicionar configuracoes operacionais
ALTER TABLE tenants
  ADD COLUMN IF NOT EXISTS settings JSONB NOT NULL DEFAULT '{}'::jsonb,
  -- Estrutura esperada do JSONB:
  -- {
  --   "branding": {
  --     "primary_color": "#2E476F",
  --     "secondary_color": "#F58634",
  --     "logo_url": "...",
  --     "favicon_url": "...",
  --     "slogan": "Cuidando de quem cuida"
  --   },
  --   "notifications": {
  --     "default_digest": "realtime",
  --     "available_kinds": [...]
  --   },
  --   "billing": {
  --     "plan": "business",
  --     "payment_method": "boleto",
  --     "next_invoice_date": "2026-06-15"
  --   },
  --   "auth": {
  --     "mode": "magic_link" | "sso_only" | "sso_with_fallback",
  --     "session_duration_hours": 720,
  --     "mfa_required_roles": ["super_admin"]
  --   },
  --   "modules_config": {
  --     "vacations": { "allow_self_request": true, "min_notice_days": 30 },
  --     "atestados": { "auto_movement_threshold_days": 3 },
  --     "okrs": { "checkin_cadence_days": 7 },
  --     ...
  --   }
  -- }
  ADD COLUMN IF NOT EXISTS branding_updated_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS settings_updated_by UUID REFERENCES app_users(id);

-- Tabela separada de webhooks (1:N)
CREATE TABLE IF NOT EXISTS tenant_webhooks (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id       UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,

  name            VARCHAR(120) NOT NULL,
  url             TEXT NOT NULL,
  secret          VARCHAR(120) NOT NULL,               -- HMAC signing

  -- Eventos que disparam o webhook
  events          TEXT[] NOT NULL,
  -- ex: ['movement.approved', 'medical.validated', 'vacation.scheduled']

  -- Status
  active          BOOLEAN NOT NULL DEFAULT TRUE,
  last_success_at TIMESTAMPTZ,
  last_failure_at TIMESTAMPTZ,
  failure_count   INT NOT NULL DEFAULT 0,
  disabled_reason TEXT,

  created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT now(),

  UNIQUE (tenant_id, name)
);

-- API keys (pra integrações server-to-server)
CREATE TABLE IF NOT EXISTS tenant_api_keys (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id       UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,

  name            VARCHAR(120) NOT NULL,
  key_prefix      VARCHAR(20) NOT NULL,                -- 'gpc_live_AB12...' · primeiros chars
  key_hash        VARCHAR(120) NOT NULL,               -- bcrypt do key completo

  -- Permissões scopadas (subset das do role catalog)
  scopes          TEXT[] NOT NULL,
  -- ex: ['employees:read', 'movements:read', 'vacations:write']

  -- Rate limit
  rate_limit_per_minute INT NOT NULL DEFAULT 60,

  -- Lifecycle
  last_used_at    TIMESTAMPTZ,
  expires_at      TIMESTAMPTZ,                         -- NULL = nunca
  revoked_at      TIMESTAMPTZ,
  revoked_by      UUID REFERENCES app_users(id),

  created_by      UUID NOT NULL REFERENCES app_users(id),
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),

  UNIQUE (tenant_id, name)
);

CREATE INDEX idx_api_keys_active
  ON tenant_api_keys(tenant_id)
  WHERE revoked_at IS NULL;

-- Histórico de mudanças (audit)
CREATE TABLE IF NOT EXISTS settings_history (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id       UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,

  changed_by      UUID NOT NULL REFERENCES app_users(id),
  section         VARCHAR(40) NOT NULL,                -- 'branding' | 'notifications' | 'billing' | etc.

  before_data     JSONB,
  after_data      JSONB,

  ip_address      INET,
  changed_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_settings_history_tenant
  ON settings_history(tenant_id, changed_at DESC);
```

---

## 3. RPCs

```sql
-- 1. Buscar settings completo (filtra por permissão)
rpc_tenant_settings_get()
  -- Retorna settings JSONB · alguns campos só pra diretoria (billing, integrações)
  -- Colaborador vê só branding + notif config

-- 2. Atualizar seção de settings
rpc_tenant_settings_update(p_section VARCHAR, p_data JSONB)
  -- exige permission 'manage_tenant_settings' (geralmente diretoria)
  -- valida schema por seção (ex: branding requer cores hex válidas)
  -- registra em settings_history
  -- atualiza branding_updated_at se section='branding'
  -- propaga pra CDN se logo mudou (chamada Edge function)

-- 3. Upload de logo
rpc_tenant_logo_upload(p_file_path TEXT, p_kind VARCHAR)
  -- p_kind: 'logo' | 'favicon' | 'logo_dark'
  -- valida tamanho (max 500KB)
  -- atualiza settings.branding.{kind}_url

-- 4. Webhooks CRUD
rpc_webhook_create(p_name, p_url, p_events TEXT[])
  -- gera secret aleatório, retorna UNA VEZ (mostrar pro user, não armazenar plain)
rpc_webhook_test(p_webhook_id)
  -- dispara evento test pra validar conectividade
rpc_webhook_rotate_secret(p_webhook_id)
  -- gera novo secret · invalidando o antigo

-- 5. API Keys CRUD
rpc_api_key_create(p_name, p_scopes TEXT[], p_expires_at)
  -- gera key 'gpc_live_<32 bytes hex>'
  -- retorna UNA VEZ (depois só prefix visível)
rpc_api_key_revoke(p_key_id, p_reason)

-- 6. Histórico de mudanças
rpc_settings_history(p_section, p_limit)
  -- audit trail por seção
```

---

## 4. Página Next.js · `/admin/configuracoes`

Referência: [r2_people_configuracoes.html](../r2_people_configuracoes.html)

### Estrutura · 6 tabs

```
┌─ Tabs sticky no topo ─────────────────────────────────────┐
│ [Geral] [Branding] [Notificações] [Integrações]           │
│ [Billing] [Workspace]                                     │
└───────────────────────────────────────────────────────────┘
```

### Aba 1 · Geral

Campos:
- Nome legal (read-only após criação · contato R2 pra mudar)
- Nome fantasia
- Slug (read-only · imutável)
- CNPJ (validado)
- Fuso horário (select com brasília default)
- Idioma (PT-BR fixo no MVP)
- Created at (read-only)

### Aba 2 · Branding

- Logo principal (upload + preview)
- Logo dark mode (upload opcional)
- Favicon (16x16 ou SVG)
- Cor primária (color picker)
- Cor secundária (color picker)
- Slogan (max 80 chars)
- Preview ao vivo (mini sidebar atualizando)

### Aba 3 · Notificações

- Eventos catalogados (lista de switches):
  - `pdi.approved` · "Quando PDI for aprovado"
  - `okr.checkin_due` · "Quando check-in OKR vencer"
  - `medical.validated` · "Quando atestado for validado"
  - `vacation.approved` · "Quando férias forem aprovadas"
  - `movement.requested` · "Quando movimentação for solicitada"
  - `recognition.received` · "Quando receber reconhecimento"
  - etc.
- Digest mode padrão tenant (realtime / daily / weekly / off)
- Hora do digest (0-23)

### Aba 4 · Integrações

- **Webhooks**
  - Tabela: nome, URL, eventos, status, última execução
  - Botão "+ Novo webhook"
  - Modal de teste com payload exemplo
- **API Keys**
  - Tabela: nome, prefix, scopes, criada em, último uso
  - Botão "+ Nova chave" · mostra UMA vez
  - Botão "Revogar" com confirmação
- **SSO providers** (link pra D2)
  - Lista de provedores configurados
  - Status, último login bem-sucedido

### Aba 5 · Billing (diretoria only)

- Plano atual + upgrade/downgrade
- Próxima fatura (data + valor)
- Método de pagamento (boleto/cartão/PIX)
- Histórico de faturas (download PDF)
- Headcount cobrado vs disponível no plano

### Aba 6 · Workspace

Configurações por módulo (depende de quais módulos ativos):

**Férias:**
- Aviso prévio mínimo (default 30d CLT)
- Permite autoatendimento (boolean)
- Fracionamento max permitido (1-3)

**Atestados:**
- Threshold pra auto-movimento (default 3 dias)
- Permitir submissão pelo próprio colaborador (boolean)
- Storage retention extra (padrão 5 anos CLT)

**OKRs:**
- Cadência de check-ins (semanal/quinzenal/mensal)
- Sentimento confidence obrigatório (boolean)

**1:1s:**
- Cadência padrão da empresa (semanal/quinzenal)
- Content lock após X dias (default 7)

**Clima/eNPS:**
- Frequência pulse (semanal default)
- Frequência eNPS (quinzenal default)
- Min responses por coorte pra exibir (default 5)

---

## 5. Validações

```sql
-- Função auxiliar pra validar JSONB de cada seção
CREATE OR REPLACE FUNCTION validate_settings_section(
  p_section VARCHAR,
  p_data JSONB
) RETURNS BOOLEAN LANGUAGE plpgsql AS $$
BEGIN
  CASE p_section
    WHEN 'branding' THEN
      -- Cores devem ser hex válido
      IF p_data->>'primary_color' !~ '^#[0-9A-Fa-f]{6}$' THEN
        RAISE EXCEPTION 'invalid_color_format';
      END IF;
    WHEN 'notifications' THEN
      -- digest_mode deve ser valor permitido
      IF NOT (p_data->>'default_digest' IN ('realtime', 'daily', 'weekly', 'off')) THEN
        RAISE EXCEPTION 'invalid_digest_mode';
      END IF;
    WHEN 'billing' THEN
      -- Apenas planos válidos
      IF NOT (p_data->>'plan' IN ('starter', 'business', 'enterprise')) THEN
        RAISE EXCEPTION 'invalid_plan';
      END IF;
    -- ... outras
  END CASE;
  RETURN TRUE;
END; $$;
```

---

## 6. Webhooks · entrega e retry

Worker FastAPI (já existe pra OCR) ganha endpoint:

```python
# worker/webhooks.py
@app.post("/webhooks/dispatch")
async def dispatch_webhook(event: WebhookEvent):
    """Dispara webhook com HMAC signing e retry exponencial."""
    payload = {
        "event": event.kind,
        "tenant_id": event.tenant_id,
        "data": event.data,
        "timestamp": event.timestamp.isoformat(),
    }
    signature = hmac.new(
        webhook.secret.encode(),
        json.dumps(payload).encode(),
        hashlib.sha256,
    ).hexdigest()

    headers = {
        "X-GPC-Signature": signature,
        "X-GPC-Event": event.kind,
        "Content-Type": "application/json",
    }

    # 3 tentativas com backoff exponencial (1s, 5s, 25s)
    for attempt in range(3):
        try:
            resp = httpx.post(webhook.url, json=payload, headers=headers, timeout=10)
            if resp.status_code < 400:
                await mark_webhook_success(webhook.id)
                return
        except Exception as e:
            if attempt < 2:
                await asyncio.sleep(5 ** attempt)
            else:
                await mark_webhook_failure(webhook.id, str(e))
                # Desabilita webhook após 10 falhas consecutivas
                if webhook.failure_count >= 10:
                    await disable_webhook(webhook.id, "too_many_failures")
```

---

## 7. Testes · `supabase/tests/00500_m10_settings.sql`

Meta: 25+ testes:

1. Update branding com cor inválida = falha
2. Update billing com plano inválido = falha
3. Update sem permission = bloqueado
4. settings_history registra cada update
5. Webhook create gera secret e retorna 1x
6. Webhook rotate_secret invalida o anterior
7. API key create retorna full key apenas 1x
8. API key revoke marca revoked_at
9. Cross-tenant blocked em todas RPCs
10. Logo upload >500KB = falha
11. Tenant settings get filtra campos por role
12-25: edge cases

---

## 8. Critérios de aceitação

- [ ] Migration 00500 aplica
- [ ] 25+ testes passando
- [ ] 6 abas funcionais
- [ ] Upload de logo com preview
- [ ] Webhooks com test ping
- [ ] API keys gerenciáveis (criar/revogar)
- [ ] Color pickers ao vivo no preview
- [ ] settings_history com audit visível
- [ ] Adapter `src/lib/r2/settings.ts`
- [ ] Doc em `docs/sessao_m10.md`

---

## 9. Pontos de atenção

- **Branding cache**: ao mudar logo, invalidar CDN cache (chamada Edge function ou regenerar token de versão)
- **Webhook secret**: armazenar em texto plano OU bcrypt? Plain é necessário pra signing · gerar 256 bits aleatório, manter em coluna criptografada
- **API key vault**: usar Supabase Vault pra armazenar key_hash bcrypt · nunca log
- **Settings JSONB vs colunas**: deixei JSONB pra flexibilidade · trade-off: schema mais frouxo. Validações via função
- **Rate limit por API key**: implementar com Redis ou tabela auxiliar (counter por minuto)
- **Multi-region**: branding pode variar por região no futuro · estrutura JSONB facilita
- **Tenant suspension**: se billing falhar 30d+, marcar tenant.status='suspended' (cobrir em M10 ou middleware)

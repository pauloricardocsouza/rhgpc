# Spec D9 · API Pública · REST + GraphQL + SDKs + Rate-limit

**Status**: especificação · pré-implementação
**Versão**: 1.0 · 18 de maio de 2026
**Escopo**: API REST v1, GraphQL endpoint, SDKs oficiais, autenticação, rate-limit, versionamento, deprecation policy
**Depende de**: schema v9+ (RBAC), spec D6 (security), spec D8 (multi-tenant isolation), spec M12 (webhooks outbound), spec M14 (inbound)

---

## 1. Objetivos

1. **Cliente integra em 1 hora**: REST simples, exemplos curl + 4 SDKs prontos, docs pública navegável.
2. **Backward compat por 24 meses**: versionamento explícito (`/v1/`, `/v2/`), deprecation com 12m de aviso.
3. **Rate-limit justo e transparente**: limites por tenant + headers RFC 6585 + dashboard de uso.
4. **GraphQL para queries complexas**: alternativa única para BI/relatórios sem N+1.
5. **Multi-tenant isolation by default**: nenhum endpoint expõe dados cross-tenant.

---

## 2. Arquitetura

```
                   Internet
                      │
                      ▼
              ┌───────────────┐
              │  CloudFlare   │  WAF + DDoS + rate-limit IP global
              └───────┬───────┘
                      │
                      ▼
              ┌───────────────┐
              │  Edge Function│  Auth (JWT/API key) + tenant_id extract
              │  /v1/*  /v2/* │  + rate-limit tenant + signature HMAC
              │  /graphql     │
              └───────┬───────┘
                      │ SET app.tenant_id = X (RLS isolation)
                      ▼
              ┌───────────────┐
              │  Postgres     │  RLS aplica filtro
              │  + RPCs       │
              └───────────────┘
```

---

## 3. Autenticação (3 métodos)

### 3.1 JWT (preferred para apps client-side)

Padrão Supabase Auth. JWT contém claim `tenant_id`. Header:

```
Authorization: Bearer eyJhbGc...
```

JWT expira em 1h, refresh via `POST /v1/auth/refresh`. Refresh token expira em 30d.

### 3.2 API Key (preferred para integrações server-to-server)

Gerada via UI por `tenant_admin`. Formato:

```
r2_live_5b8a3f9c2b...e7d1   (live keys)
r2_test_abc...               (test keys, não cobram billing)
```

Header:

```
Authorization: ApiKey r2_live_5b8a3f9c2b...e7d1
```

Cada API key tem:
- `name` (label legível, ex: "ERP Senior · prod")
- `scopes` (array de permissões, ex: `["read:employees","write:movements"]`)
- `allowed_ips` (opcional, allowlist)
- `rate_limit_override` (opcional, custom para integração de alta demanda)
- `expires_at` (opcional)
- `last_used_at` (telemetria)

Armazenada como **bcrypt hash** no banco (nunca em plain text). Mostrada **uma única vez** na criação.

### 3.3 OAuth 2.0 (futuro · pós-MVP)

Apps de terceiros (marketplace) usam OAuth com authorization code flow. Tenant_admin autoriza app com scopes específicos.

---

## 4. REST API v1

### 4.1 Convenções

- **Base URL**: `https://api.r2-people.com/v1`
- **Content-Type**: `application/json; charset=utf-8`
- **Encoding**: UTF-8 sempre
- **Datas**: ISO 8601 com timezone (`2026-05-18T14:32:00-03:00`)
- **IDs**: UUID v4 (sem hifens em URL é aceito mas com é preferido)
- **Paginação**: cursor-based (`?cursor=eyJp...&limit=50`)
- **Errors**: RFC 7807 Problem Details

### 4.2 Headers padrão de resposta

```
HTTP/1.1 200 OK
Content-Type: application/json
X-Request-Id: 01HXY...
X-Tenant-Id: 5b8a3f...                    (echo do tenant)
X-RateLimit-Limit: 1000
X-RateLimit-Remaining: 847
X-RateLimit-Reset: 1747512300
Cache-Control: no-store, private
```

### 4.3 Endpoints v1 · resource model

| Resource | Endpoints |
|---|---|
| `/v1/employees` | GET list, POST create, GET/PATCH/DELETE :id |
| `/v1/employees/:id/movements` | GET list, POST create |
| `/v1/movements` | GET list, GET :id (filtro `?employee_id=`) |
| `/v1/medical-certificates` | GET list (com CID redacted por default), POST upload |
| `/v1/medical-certificates/:id` | GET (com `?include=cid` se permissão) |
| `/v1/vacations` | GET list, POST request, PATCH :id |
| `/v1/payroll-runs` | GET list, GET :id |
| `/v1/evaluations` | GET, POST, PATCH |
| `/v1/okrs` | GET, POST, PATCH |
| `/v1/oneonones` | GET, POST, PATCH |
| `/v1/notifications` | GET list (do user logado) |
| `/v1/users` | GET list (com `view_all_users` perm), POST invite |
| `/v1/tenants/current` | GET (info do tenant atual) |
| `/v1/tenants/current/settings` | GET, PATCH |
| `/v1/webhooks` | GET list, POST, PATCH/DELETE :id (outbound) |
| `/v1/webhooks/inbound` | GET list, POST create endpoint (M14) |
| `/v1/api-keys` | GET list, POST create (retorna key 1x), DELETE :id |
| `/v1/audit-log` | GET (`?since=` + filtros, apenas DPO/admin) |
| `/v1/dsar` | POST create (público, sem auth), GET list (DPO) |
| `/v1/quotas` | GET (status atual de cada quota do tenant) |
| `/v1/health` | GET (status simples para uptime check) |

### 4.4 Exemplo · GET /v1/employees

**Request**:
```
GET /v1/employees?status=active&limit=50&cursor=eyJpZCI6Ii4uLiJ9
Authorization: ApiKey r2_live_...
```

**Response 200**:
```json
{
  "data": [
    {
      "id": "5b8a3f9c-...",
      "external_id": "GPC-001",
      "full_name": "Fernanda Lima",
      "email": "fernanda.lima@gpc.com.br",
      "position": {"id": "...", "title": "Analista Pleno"},
      "department": {"id": "...", "name": "Cestão L1"},
      "branch": {"id": "...", "name": "Cestão Loja 1"},
      "admission_date": "2024-03-15",
      "status": "active",
      "manager_id": "...",
      "created_at": "2024-03-15T09:00:00-03:00",
      "_links": {
        "self": "/v1/employees/5b8a3f9c-...",
        "movements": "/v1/employees/5b8a3f9c-.../movements"
      }
    }
  ],
  "meta": {
    "count": 50,
    "total_estimate": 367
  },
  "links": {
    "next": "/v1/employees?status=active&limit=50&cursor=eyJpZCI6Ii4uLjkifQ",
    "prev": null
  }
}
```

### 4.5 Exemplo · POST /v1/movements

```json
POST /v1/movements
Content-Type: application/json

{
  "employee_id": "5b8a3f9c-...",
  "type": "PROMOTION",
  "effective_date": "2026-06-01",
  "before": {
    "position_id": "...",
    "salary_brl_cents": 550000
  },
  "after": {
    "position_id": "...",
    "salary_brl_cents": 620000
  },
  "reason": "Reconhecimento de impacto Q1/2026"
}
```

**Response 201 Created**:
```json
{
  "data": {
    "id": "...",
    "protocol": "GPC-MOV-2026-0042",
    "status": "pending_approval",
    "created_at": "2026-05-18T14:32:00-03:00",
    "_links": {
      "self": "/v1/movements/...",
      "approve": "/v1/movements/.../approve"
    }
  }
}
```

### 4.6 Errors padrão (RFC 7807)

```json
HTTP/1.1 422 Unprocessable Entity
Content-Type: application/problem+json

{
  "type": "https://docs.r2-people.com/errors/validation",
  "title": "Validation failed",
  "status": 422,
  "detail": "Field 'employee_id' is required",
  "instance": "/v1/movements",
  "request_id": "01HXY...",
  "errors": [
    {"field": "employee_id", "code": "required"},
    {"field": "effective_date", "code": "must_be_future"}
  ]
}
```

Códigos HTTP usados:
- `200 OK`, `201 Created`, `204 No Content`
- `400 Bad Request` (malformed JSON)
- `401 Unauthorized` (token inválido/expirado)
- `403 Forbidden` (token válido sem permissão)
- `404 Not Found`
- `409 Conflict` (idempotência ou estado inválido)
- `422 Unprocessable Entity` (validação)
- `429 Too Many Requests` (rate limit)
- `500 Internal Server Error`
- `503 Service Unavailable` (DR mode, manutenção)

### 4.7 Idempotência

Endpoints `POST` aceitam header opcional `Idempotency-Key`:

```
POST /v1/movements
Idempotency-Key: 5b8a3f9c-7e2k-...

(mesma key + mesmo body em 24h → retorna mesma resposta original)
```

Armazenado em `idempotency_keys (key, tenant_id, response_body, response_status, created_at)`.

---

## 5. GraphQL endpoint

### 5.1 Quando usar GraphQL vs REST

| Use REST | Use GraphQL |
|---|---|
| Server-to-server simples | App mobile que precisa de N campos específicos |
| Webhook delivery | BI/relatórios com muitos joins |
| Idempotência crítica | Real-time subscriptions |
| Cache HTTP | Composição de várias queries em uma round-trip |

### 5.2 Endpoint

```
POST https://api.r2-people.com/graphql
Authorization: Bearer ...
```

### 5.3 Schema (extrato)

```graphql
type Employee {
  id: ID!
  externalId: String
  fullName: String!
  email: String
  position: Position
  department: Department
  branch: Branch
  manager: Employee
  admissionDate: Date
  status: EmployeeStatus!
  movements(first: Int, after: String): MovementConnection!
  medicalCertificates(includeCid: Boolean): [MedicalCertificate!]!
  currentSalary(viewerHasPermission: Boolean!): Int  # null se sem permissão
}

type Query {
  employee(id: ID!): Employee
  employees(filter: EmployeeFilter, first: Int, after: String): EmployeeConnection!
  me: Employee!
  tenant: Tenant!
  quotas: [QuotaStatus!]!
}

type Mutation {
  createMovement(input: CreateMovementInput!): MovementPayload!
  approveMovement(id: ID!): MovementPayload!
  submitMedicalCertificate(input: SubmitMedicalInput!): MedicalCertificatePayload!
}

type Subscription {
  notificationsForUser(userId: ID!): Notification!
  movementsForTenant(tenantId: ID!): Movement!
}
```

### 5.4 Limites

- Max query depth: 8
- Max query complexity: 1000 (via `graphql-cost-analysis`)
- Subscriptions: max 5 simultâneas por user
- Per-field rate-limit independente (mutations: 100/min, queries: 1000/min)

---

## 6. Rate-limit · 3 camadas

| Camada | Limite default | Headers |
|---|---|---|
| Por IP global (CloudFlare) | 600 req/min | `CF-Ray` |
| Por API key (tenant) | conforme plano (ver §6.1) | `X-RateLimit-*` |
| Por endpoint individual | rota específica (ex: upload 20/h) | `X-RateLimit-Endpoint-*` |

### 6.1 Limites por plano

| Plano | API calls/mês | Burst/min | Webhooks outbound | Inbound endpoints |
|---|---|---|---|---|
| Starter | 10k | 60 | 2 | 1 |
| Pro | 100k | 600 | 10 | 5 |
| Enterprise | 1M | 6000 | 50 | 20 |

Excesso 429 com:
```
HTTP/1.1 429 Too Many Requests
Retry-After: 30
X-RateLimit-Limit: 600
X-RateLimit-Remaining: 0
X-RateLimit-Reset: 1747512330
```

### 6.2 Burst handling

Sliding window 1 minuto. Cliente bem comportado faz backoff exponencial conforme `Retry-After`.

---

## 7. Versionamento

### 7.1 Política

- **Major version no path** (`/v1/`, `/v2/`)
- **Mudanças backward-compatible** (campos novos opcionais) **não** quebram v1
- **Breaking changes** exigem nova major version
- **v(N-1) suportada por 24 meses** após release de vN
- **Deprecation header** nos últimos 6 meses: `Deprecation: true` + `Sunset: Sat, 31 Dec 2027 23:59:59 GMT`

### 7.2 Changelog público

`https://docs.r2-people.com/changelog`

Cada release inclui:
- Data
- Endpoints adicionados
- Campos novos
- Bugs corrigidos
- Deprecations (com data de remoção)

---

## 8. SDKs oficiais

### 8.1 Linguagens MVP

| SDK | Repo | Status |
|---|---|---|
| **TypeScript** | `@r2-people/sdk` | M0 (lançamento) |
| **Python** | `r2-people` | M0 |
| **PHP** | `r2-people/sdk-php` | M+3 |
| **Go** | `github.com/r2-people/sdk-go` | M+6 |

### 8.2 Exemplo · TypeScript

```typescript
import { R2People } from '@r2-people/sdk';

const client = new R2People({
  apiKey: process.env.R2_API_KEY,
  // ou: jwt: '...'
});

// REST-style
const employees = await client.employees.list({
  status: 'active',
  limit: 50
});

const movement = await client.movements.create({
  employeeId: 'abc-...',
  type: 'PROMOTION',
  effectiveDate: '2026-06-01',
  // ...
}, { idempotencyKey: crypto.randomUUID() });

// GraphQL
const result = await client.gql(`
  query MyTeam($managerId: ID!) {
    employee(id: $managerId) {
      fullName
      directReports {
        fullName
        currentSalary(viewerHasPermission: true)
      }
    }
  }
`, { managerId: 'xyz-...' });

// Webhooks helper
client.webhooks.verifyOutbound({
  signature: req.headers['x-r2-signature'],
  eventId: req.headers['x-r2-event-id'],
  body: req.body,
  secret: process.env.R2_WEBHOOK_SECRET
});
```

### 8.3 Exemplo · Python

```python
from r2_people import R2People

client = R2People(api_key=os.getenv("R2_API_KEY"))

# REST
employees = client.employees.list(status="active", limit=50)

mov = client.movements.create(
    employee_id="abc-...",
    type="PROMOTION",
    effective_date="2026-06-01",
    idempotency_key=str(uuid4())
)

# Webhook handler (Django/Flask helper)
@app.route("/webhooks/r2", methods=["POST"])
def handle_webhook():
    if not client.webhooks.verify_outbound(request):
        return "", 401
    event = request.json
    # ...
    return "", 200
```

### 8.4 Garantias dos SDKs

- Types completos (TS strict, Python typing, Go interfaces)
- Auto-retry com backoff exponencial em 5xx e 429
- Idempotency-Key auto-gerada se não fornecida em POST
- Telemetria opcional (opt-in) anonimizada
- Versionados em sync com a API (`v1.2.3` SDK ↔ `v1` API)

---

## 9. Documentação pública

### 9.1 Sites

- **`docs.r2-people.com`** · referência completa, gerada do OpenAPI
- **`docs.r2-people.com/graphql`** · explorer interativo (Apollo Sandbox)
- **`docs.r2-people.com/sdks`** · guias específicos por linguagem
- **`docs.r2-people.com/recipes`** · casos de uso end-to-end (folha integration, AD sync, etc)

### 9.2 OpenAPI spec

`docs.r2-people.com/openapi.json` (v3.1) — fonte de verdade. SDKs são gerados parcialmente dele.

### 9.3 Postman collection

Atualizada a cada release, importável em 1 clique.

---

## 10. Schema (tabelas novas)

```sql
-- API keys
CREATE TABLE IF NOT EXISTS api_keys (
  id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id           uuid NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  name                text NOT NULL,
  key_hash            text NOT NULL,           -- bcrypt
  key_prefix          text NOT NULL,           -- 'r2_live_5b8a' (8 chars para identificar sem expor)
  mode                text CHECK (mode IN ('live','test')) DEFAULT 'live',
  scopes              text[] NOT NULL DEFAULT ARRAY['read:*'],
  allowed_ips         inet[],
  rate_limit_override int,                     -- req/min custom
  created_by          uuid REFERENCES auth.users(id),
  created_at          timestamptz NOT NULL DEFAULT now(),
  expires_at          timestamptz,
  revoked_at          timestamptz,
  last_used_at        timestamptz,
  last_used_ip        inet,
  UNIQUE (tenant_id, name)
);

CREATE INDEX IF NOT EXISTS idx_api_keys_active
  ON api_keys (tenant_id, key_prefix) WHERE revoked_at IS NULL;

-- Idempotência
CREATE TABLE IF NOT EXISTS idempotency_keys (
  key              text NOT NULL,
  tenant_id        uuid NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  request_hash     text NOT NULL,              -- sha256 do body
  response_status  int  NOT NULL,
  response_body    jsonb NOT NULL,
  created_at       timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (tenant_id, key)
);

-- TTL 24h
CREATE INDEX IF NOT EXISTS idx_idempotency_ttl ON idempotency_keys (created_at);

-- API usage log (audit + billing)
CREATE TABLE IF NOT EXISTS api_usage_log (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id       uuid NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  api_key_id      uuid REFERENCES api_keys(id),
  user_id         uuid REFERENCES auth.users(id),
  method          text NOT NULL,
  path            text NOT NULL,
  status          int  NOT NULL,
  duration_ms     int,
  request_id      text,
  occurred_at     timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_api_usage_tenant
  ON api_usage_log (tenant_id, occurred_at DESC);

-- Particionamento mensal recomendado em prod
```

---

## 11. RLS e GRANTs

```sql
ALTER TABLE api_keys ENABLE ROW LEVEL SECURITY;
CREATE POLICY api_keys_tenant_isolation ON api_keys
  FOR ALL USING (tenant_id = (current_setting('app.tenant_id', true))::uuid);

-- key_hash NUNCA exposto para authenticated
REVOKE ALL ON api_keys FROM authenticated;
GRANT SELECT (id, tenant_id, name, key_prefix, mode, scopes, allowed_ips,
              created_at, expires_at, revoked_at, last_used_at)
  ON api_keys TO authenticated;
GRANT ALL ON api_keys TO service_role;

ALTER TABLE idempotency_keys ENABLE ROW LEVEL SECURITY;
CREATE POLICY idempotency_tenant_isolation ON idempotency_keys
  FOR ALL USING (tenant_id = (current_setting('app.tenant_id', true))::uuid);

ALTER TABLE api_usage_log ENABLE ROW LEVEL SECURITY;
CREATE POLICY api_usage_tenant_isolation ON api_usage_log
  FOR SELECT USING (tenant_id = (current_setting('app.tenant_id', true))::uuid);
GRANT ALL ON api_usage_log TO service_role;
```

---

## 12. RPCs

```sql
-- Cria API key, retorna a key em texto 1 única vez
CREATE OR REPLACE FUNCTION rpc_create_api_key(
  p_tenant_id uuid,
  p_name text,
  p_mode text DEFAULT 'live',
  p_scopes text[] DEFAULT ARRAY['read:*'],
  p_allowed_ips inet[] DEFAULT NULL,
  p_expires_at timestamptz DEFAULT NULL
) RETURNS TABLE (id uuid, api_key text)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_random text := encode(gen_random_bytes(32), 'hex');  -- 64 chars hex
  v_full_key text := 'r2_' || p_mode || '_' || v_random;
  v_prefix text := substring(v_full_key from 1 for 12);  -- 'r2_live_5b8a'
  v_hash text;
  v_id uuid;
BEGIN
  v_hash := crypt(v_full_key, gen_salt('bf', 12));   -- bcrypt cost 12

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

-- Valida API key + retorna scopes (chamada pela Edge Function em cada request)
CREATE OR REPLACE FUNCTION rpc_validate_api_key(p_key text)
RETURNS TABLE (tenant_id uuid, key_id uuid, scopes text[])
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_prefix text := substring(p_key from 1 for 12);
  v_row api_keys;
BEGIN
  SELECT * INTO v_row FROM api_keys
  WHERE key_prefix = v_prefix
    AND revoked_at IS NULL
    AND (expires_at IS NULL OR expires_at > now());

  IF NOT FOUND THEN RETURN; END IF;

  IF crypt(p_key, v_row.key_hash) = v_row.key_hash THEN
    UPDATE api_keys SET last_used_at = now() WHERE id = v_row.id;
    RETURN QUERY SELECT v_row.tenant_id, v_row.id, v_row.scopes;
  END IF;
END;
$$;

-- Cleanup idempotency keys (job diário)
CREATE OR REPLACE FUNCTION rpc_idempotency_cleanup()
RETURNS int
LANGUAGE plpgsql AS $$
DECLARE v_count int;
BEGIN
  DELETE FROM idempotency_keys WHERE created_at < now() - interval '24 hours';
  GET DIAGNOSTICS v_count = ROW_COUNT;
  RETURN v_count;
END;
$$;

GRANT EXECUTE ON FUNCTION rpc_create_api_key(uuid, text, text, text[], inet[], timestamptz) TO service_role;
GRANT EXECUTE ON FUNCTION rpc_validate_api_key(text) TO service_role;
GRANT EXECUTE ON FUNCTION rpc_idempotency_cleanup() TO service_role;
```

---

## 13. Observabilidade

| Métrica | Labels | Alerta |
|---|---|---|
| `r2_api_requests_total` | tenant, method, path, status | spike 5xx > 1%/5min |
| `r2_api_duration_ms` | tenant, path (histogram) | p95 > 500ms |
| `r2_api_keys_active_total` | tenant | — |
| `r2_api_rate_limit_hit_total` | tenant, api_key | spike > 100/h |
| `r2_api_idempotency_hits_total` | tenant | — |
| `r2_graphql_complexity` | tenant (histogram) | rejeições > 5%/h |

---

## 14. Testes meta (mínimo 30)

### 14.1 Auth
- ✓ Request sem `Authorization` retorna 401
- ✓ JWT expirado retorna 401
- ✓ API key revogada retorna 401
- ✓ API key fora de `allowed_ips` retorna 403
- ✓ API key sem scope necessário retorna 403
- ✓ test key não cobra billing (mode='test')

### 14.2 Isolamento
- ✓ Tenant A não vê employees do tenant B via API
- ✓ JWT do tenant A não pode usar API key do tenant B
- ✓ GraphQL subscription respeita tenant_id (canal por tenant)

### 14.3 Rate-limit
- ✓ Burst > limite retorna 429 com `Retry-After`
- ✓ Headers `X-RateLimit-*` presentes em todas respostas
- ✓ Reset acontece no rollover da janela
- ✓ Plano Starter limita em 10k/mês
- ✓ Override per-key respeitado

### 14.4 Idempotência
- ✓ Mesma `Idempotency-Key` em 24h retorna resposta original
- ✓ Idempotency-Key com body diferente retorna 422
- ✓ TTL 24h limpo via cron

### 14.5 Versionamento
- ✓ v1 e v2 coexistem
- ✓ Header `Deprecation` retornado em endpoints depreciados
- ✓ Endpoint removido > sunset retorna 410 Gone

### 14.6 GraphQL
- ✓ Query com depth > 8 rejeitada
- ✓ Query com complexity > 1000 rejeitada
- ✓ Subscription respeita auth + tenant
- ✓ Mutation isolada por tenant via RLS

### 14.7 SDK
- ✓ TS SDK reconecta após 429 com backoff
- ✓ Python SDK valida webhook signature
- ✓ Verify helper aceita timestamp dentro da janela

---

## 15. Roadmap pós-MVP

1. **OAuth 2.0** para apps de terceiros (marketplace)
2. **API mTLS** para clientes Enterprise com exigência regulatória
3. **Bulk endpoints** (`POST /v1/employees/bulk` para criar 1000 de uma vez)
4. **Webhooks bi-direcionais** (cliente publica, R2 transforma e devolve)
5. **GraphQL Federation** para integrar com schemas externos do cliente
6. **SDKs adicionais**: Ruby, .NET, Java, Kotlin (mobile)
7. **API gateway próprio** (sair do Cloudflare/Edge functions para próprio K8s) em escala 10x

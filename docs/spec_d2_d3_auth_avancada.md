# Spec · D2 + D3 · Auth avançada (SSO + MFA + auditoria de login)

**Status:** D1 (Supabase Auth básico) deve estar aplicado · este spec adiciona enterprise-grade
**Pré-requisitos:** D1 implementado
**Estimativa:** 2 sessões (~6-8h)

---

## 1. Objetivo

D1 (em `spec_d1_auth.md`) cobriu Supabase Auth básico (magic link + Google OAuth + middleware). Este spec adiciona o que clientes enterprise pedem:

| Feature | Quando precisa |
|---|---|
| **SSO SAML/OIDC** | Cliente já tem Microsoft Entra ID, Okta, Google Workspace |
| **MFA TOTP** | Compliance / dados sensíveis / clientes regulados |
| **Convites por email** | Onboarding controlado · sem auto-signup |
| **Auditoria de login** | LGPD + investigações de acesso indevido |
| **Rate limiting** | Proteção contra brute force / scraping |
| **Force logout cross-device** | Quando colaborador é desligado, sessão expira em todos os devices |

---

## 2. SSO SAML/OIDC

### 2.1 Configuração

Supabase suporta SSO via SAML 2.0 e OIDC (Pro plan ou superior).

```sql
-- migration: 00510_d2_sso_config.sql

-- Tabela de provedores SSO por tenant
CREATE TABLE sso_providers (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id       UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,

  -- Identificação
  provider_kind   VARCHAR(20) NOT NULL,                -- 'saml' | 'oidc'
  display_name    VARCHAR(120) NOT NULL,               -- 'Microsoft Entra GPC'

  -- Config Supabase (provider_id retornado por supabase admin)
  supabase_provider_id VARCHAR(120) NOT NULL,

  -- Domínios permitidos (auto-roteia login com email @gpc.com.br pra Entra)
  email_domains   TEXT[] NOT NULL,                     -- ['gpc.com.br', 'cestao.com.br']

  -- Configuração da identidade (URL discovery OIDC ou metadata SAML)
  metadata_url    TEXT,                                 -- OIDC discovery
  saml_metadata_xml TEXT,                              -- SAML raw metadata

  -- Mapping de atributos
  attribute_mapping JSONB NOT NULL DEFAULT '{}'::jsonb,
  -- { "email": "email", "name": "name", "role_claim": "groups" }

  -- Auto-provision
  auto_provision  BOOLEAN NOT NULL DEFAULT TRUE,       -- cria app_user automaticamente
  default_role    app_user_role NOT NULL DEFAULT 'colaborador',

  active          BOOLEAN NOT NULL DEFAULT TRUE,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_sso_providers_tenant ON sso_providers(tenant_id) WHERE active = TRUE;
CREATE INDEX idx_sso_providers_domain ON sso_providers USING gin(email_domains);
```

### 2.2 Fluxo

1. Cliente abre `/login` e digita email `joao@gpc.com.br`
2. Frontend chama `rpc_resolve_sso_provider(p_email)`:
   - Extrai domain (`gpc.com.br`)
   - Busca em `sso_providers` where `'gpc.com.br' = ANY(email_domains)` AND active
3. Se encontrou SSO, redireciona pro provider (Entra/Okta)
4. Provider autentica e callback retorna JWT com claims
5. Trigger `on_auth_user_created` (de D1) cria `app_users` se `auto_provision=TRUE`
6. Usuario entra logado

### 2.3 Atribuição de role via SAML groups

Mapping JSONB permite mapear grupos do AD pra roles do produto:

```json
{
  "email": "email",
  "name": "name",
  "role_claim": "groups",
  "role_map": {
    "GPC-Diretoria": "diretoria",
    "GPC-RH": "rh",
    "GPC-Lideres": "lider",
    "GPC-Geral": "colaborador"
  }
}
```

Trigger lê o claim `groups` do JWT, busca no `role_map` e atribui role correspondente.

### 2.4 Convivência com magic link

Tenant pode permitir:
- **SSO only**: nega magic link (mais seguro)
- **SSO + magic link**: magic link como fallback se SSO down
- **Magic link only**: SSO desabilitado (default pra tenants sem SSO config)

Flag em `tenant_settings.auth_mode`.

---

## 3. MFA TOTP

### 3.1 Tabela

```sql
-- migration: 00520_d3_mfa_config.sql

CREATE TABLE user_mfa_factors (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id         UUID NOT NULL REFERENCES app_users(id) ON DELETE CASCADE,

  factor_kind     VARCHAR(20) NOT NULL,                -- 'totp' | 'webauthn' (futuro)
  friendly_name   VARCHAR(80) NOT NULL,                -- 'Authy iPhone', 'Yubikey'

  -- Secret (cifrado em repouso)
  -- Supabase Auth ja faz isso · esta tabela e referencia
  supabase_factor_id VARCHAR(120) NOT NULL,

  enrolled_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
  last_used_at    TIMESTAMPTZ,
  active          BOOLEAN NOT NULL DEFAULT TRUE,

  UNIQUE (user_id, friendly_name)
);

CREATE INDEX idx_mfa_user_active ON user_mfa_factors(user_id, active);

-- Policy: tenant pode exigir MFA pra certos papeis
ALTER TABLE tenant_settings
  ADD COLUMN IF NOT EXISTS mfa_required_roles app_user_role[] DEFAULT ARRAY[]::app_user_role[];
  -- ex: ['super_admin', 'diretoria', 'rh']
```

### 3.2 Fluxo de enrollment

1. Usuario abre `/configuracoes/seguranca`
2. Clica "Adicionar fator MFA"
3. Frontend chama `supabase.auth.mfa.enroll({ factorType: 'totp' })`
4. Recebe QR code e secret
5. Usuario escaneia em Authy/Google Auth/1Password
6. Insere código de 6 dígitos pra verificar
7. `supabase.auth.mfa.challenge` + `verify` confirma
8. Backend cria row em `user_mfa_factors` com `supabase_factor_id`

### 3.3 Fluxo de login com MFA

1. Email + magic link como hoje
2. Apos sessão criada, trigger detecta `user_mfa_factors` ativos
3. Se tem, exige fator MFA antes de prosseguir
4. Usuario insere código de 6 dígitos
5. `supabase.auth.mfa.verify` retorna AAL2 token
6. Middleware checa AAL2 pra rotas sensíveis

### 3.4 Recovery codes

Ao adicionar 1º fator, sistema gera 10 recovery codes:
- Mostra UMA vez
- Usuario deve guardar (avisar pra imprimir)
- Cada code é usável 1x · após uso fica invalido
- Permite login se perder dispositivo TOTP

```sql
CREATE TABLE mfa_recovery_codes (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id         UUID NOT NULL REFERENCES app_users(id) ON DELETE CASCADE,

  -- Hash bcrypt do code (nunca armazena plain)
  code_hash       VARCHAR(120) NOT NULL,
  used_at         TIMESTAMPTZ,                         -- NULL = disponivel
  used_ip         INET,

  created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_recovery_unused ON mfa_recovery_codes(user_id)
  WHERE used_at IS NULL;
```

---

## 4. Convites por email (controlado · sem auto-signup)

### 4.1 Tabela

```sql
-- migration: 00530_d2_tenant_invitations.sql

CREATE TABLE tenant_invitations (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id       UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,

  email           VARCHAR(180) NOT NULL,
  invited_role    app_user_role NOT NULL DEFAULT 'colaborador',
  invited_by      UUID NOT NULL REFERENCES app_users(id),

  -- Pré-preenchimento opcional do app_user a criar
  preset_data     JSONB,
  -- { full_name, employer_unit_id, working_unit_id, department_id, job_role_id, manager_id }

  -- Token único (URL: /aceitar-convite?token=...)
  token           VARCHAR(64) NOT NULL UNIQUE,
  expires_at      TIMESTAMPTZ NOT NULL,                -- default now() + 7d

  -- Status
  accepted_at     TIMESTAMPTZ,
  accepted_by_user_id UUID REFERENCES app_users(id),   -- preenchido ao aceitar
  revoked_at      TIMESTAMPTZ,
  revoked_by      UUID REFERENCES app_users(id),

  created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_invites_tenant ON tenant_invitations(tenant_id, email)
  WHERE accepted_at IS NULL AND revoked_at IS NULL AND expires_at > now();
```

### 4.2 Fluxo

1. RH abre `/admin/usuarios/convidar`
2. Insere email + role + dados pré-preenchidos opcionais
3. Sistema gera token (32 bytes random hex), envia email com link
4. Pessoa recebe email "Você foi convidado pro GPC People"
5. Clica no link `/aceitar-convite?token=...`
6. Sistema:
   - Valida token (existe, não expirou, não foi aceito, não revogado)
   - Mostra form com email pré-preenchido + nome (se preset)
   - Pessoa confirma + escolhe senha (ou usa SSO se domain corresponder)
7. Cria `app_users` com role e dados do convite
8. Marca convite como `accepted_at`

### 4.3 Variantes

- **Auto-signup**: sem convite, qualquer pessoa com email `@dominio.com` pode criar conta (config por tenant)
- **Convite obrigatório**: padrão · só quem tem convite válido entra
- **SSO obrigatório**: nem convite tradicional · só SSO

---

## 5. Auditoria de login

```sql
-- migration: 00540_d2_login_audit.sql

CREATE TABLE login_audit (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id       UUID,                                -- pode ser NULL se login falhou antes de identificar tenant

  -- Identificação
  user_id         UUID REFERENCES app_users(id),       -- NULL se falhou
  email_attempted VARCHAR(180),                        -- snapshot do que foi tentado

  -- Tipo
  event_kind      VARCHAR(40) NOT NULL,
  -- 'login_success' | 'login_failure' | 'logout' | 'mfa_required' | 'mfa_success'
  -- | 'mfa_failure' | 'password_reset_request' | 'password_reset_complete'
  -- | 'sso_redirect' | 'sso_callback' | 'session_revoked'

  failure_reason  VARCHAR(120),                        -- 'wrong_password' | 'mfa_invalid' | 'rate_limited'

  -- Contexto
  ip_address      INET,
  user_agent      TEXT,
  country         VARCHAR(2),                          -- 'BR' (via geo IP)

  -- Sessão
  session_id      UUID,
  auth_method     VARCHAR(20),                         -- 'magic_link' | 'google_oauth' | 'saml' | 'oidc'
  mfa_used        BOOLEAN NOT NULL DEFAULT FALSE,

  created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_login_audit_user ON login_audit(user_id, created_at DESC);
CREATE INDEX idx_login_audit_tenant ON login_audit(tenant_id, created_at DESC);
CREATE INDEX idx_login_audit_failures ON login_audit(email_attempted, created_at DESC)
  WHERE event_kind = 'login_failure';
```

### Eventos auditados

Todo evento de auth gera row em `login_audit`. Útil para:
- **DPO** investigar acesso suspeito
- **Detectar brute force** (várias falhas mesmo email/IP em curta janela)
- **Compliance LGPD** Art. 18 (titular pode pedir histórico de acessos à sua conta)
- **Investigação de incidente** (após reportar suspeita de vazamento)

### Painel admin

`/admin/seguranca` mostra:
- Tentativas de login últimas 24h (gráfico)
- Top IPs com falha
- Logins de geo incomum (login fora do Brasil pra colab brasileiro)
- Sessões ativas com possibilidade de revogar

---

## 6. Rate limiting

Implementar em camadas:

### 6.1 Layer 1 · Supabase Auth (interno)

Supabase já tem rate limiting nativo:
- 30 emails/hora por endereço (magic link)
- 60 OAuth callbacks/hora por IP
- Configurável no painel pro plano Pro+

### 6.2 Layer 2 · Database-level (custom)

```sql
-- Função que checa e registra tentativas
CREATE OR REPLACE FUNCTION check_login_rate_limit(
  p_email VARCHAR,
  p_ip INET
) RETURNS BOOLEAN LANGUAGE plpgsql AS $$
DECLARE v_failures_recent INT;
BEGIN
  SELECT COUNT(*) INTO v_failures_recent
    FROM login_audit
    WHERE (email_attempted = p_email OR ip_address = p_ip)
      AND event_kind = 'login_failure'
      AND created_at > now() - INTERVAL '15 minutes';

  -- Bloqueia se >= 5 falhas em 15min
  IF v_failures_recent >= 5 THEN
    INSERT INTO login_audit (email_attempted, ip_address, event_kind, failure_reason)
      VALUES (p_email, p_ip, 'login_failure', 'rate_limited');
    RETURN FALSE;
  END IF;

  RETURN TRUE;
END; $$;
```

Frontend chama antes do `signInWithOtp`. Se retorna FALSE, mostra mensagem "Muitas tentativas · tente em 15min".

### 6.3 Layer 3 · CDN / WAF (Vercel/Cloudflare)

Bloqueio em camada externa:
- Cloudflare regras de bot management
- Vercel firewall (geoblock, rate por IP)
- Não cobertura nesta spec (config infra)

---

## 7. Force logout cross-device

Quando colaborador é desligado, sessões em todos os dispositivos devem expirar imediatamente.

```sql
-- migration: 00550_d2_session_revocation.sql

CREATE TABLE session_revocations (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id         UUID NOT NULL REFERENCES app_users(id) ON DELETE CASCADE,

  reason          VARCHAR(60) NOT NULL,
  -- 'termination' | 'password_change' | 'mfa_change' | 'security_event' | 'admin_force'

  revoked_by      UUID REFERENCES app_users(id),
  revoked_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Quando termination acontece em app_users:
CREATE TRIGGER trg_terminate_revoke_sessions
  AFTER UPDATE OF terminated_at, active ON app_users
  FOR EACH ROW
  WHEN (OLD.active = TRUE AND NEW.active = FALSE)
  EXECUTE FUNCTION revoke_user_sessions();

CREATE OR REPLACE FUNCTION revoke_user_sessions() RETURNS TRIGGER AS $$
BEGIN
  -- Registra revogacao
  INSERT INTO session_revocations (user_id, reason)
    VALUES (NEW.id, 'termination');

  -- Chama Supabase Admin API pra deletar todas as sessoes
  -- (na pratica isso e feito no codigo do worker · trigger so registra)
  RETURN NEW;
END; $$ LANGUAGE plpgsql;
```

Middleware checa `session_revocations` antes de aceitar JWT:

```ts
// src/middleware.ts (estende o de D1)
const { data: revocations } = await supabase
  .from('session_revocations')
  .select('revoked_at')
  .eq('user_id', session.user.id)
  .gt('revoked_at', session.created_at) // só revogações após criação da sessão
  .limit(1);

if (revocations && revocations.length > 0) {
  // Sessão revogada · força logout
  await supabase.auth.signOut();
  return NextResponse.redirect(new URL('/login?reason=revoked', req.url));
}
```

---

## 8. Páginas Next.js

### 8.1 `/admin/seguranca` (novo · super_admin + diretoria)

- KPIs de segurança últimas 24h
- Top tentativas falhas (email, IP)
- Sessões ativas no tenant com botão "Revogar"
- Configuração SSO
- Lista de convites pendentes
- Toggle MFA obrigatório por role

### 8.2 `/configuracoes/seguranca` (todos)

- Adicionar/remover fatores MFA
- Recovery codes (gerar novos)
- Sessões ativas (próprias) com botão "Sair deste dispositivo"
- Histórico de logins (próprios) últimas 30d

### 8.3 `/aceitar-convite?token=...` (público · pré-login)

- Form de aceite
- Validação do token
- Escolha de senha (se não usar SSO)

---

## 9. Testes · meta 40+

1. Convite gerado e válido por 7d
2. Convite expirado bloqueado
3. Convite revogado bloqueado
4. Convite aceito cria app_user com role correto
5. MFA enrollment funcional
6. MFA verify com código válido = OK
7. MFA verify com código errado = falha + audit
8. Recovery code consume uma vez, bloqueia segundo uso
9. SSO domain mapping route
10. Login audit registrado em cada evento
11. Rate limit bloqueia após 5 falhas em 15min
12. Force logout pós-termination revoga sessões
13. MFA obrigatório por role bloqueia login sem 2º fator
14. SAML group → role mapping correto
15-40: edge cases

---

## 10. Critérios de aceitação

- [ ] Migrations 00510-00550 aplicam
- [ ] 40+ testes passando
- [ ] Configuração SSO funcional (testar com Microsoft Entra)
- [ ] MFA TOTP testado com Authy real
- [ ] Convites gerados e aceitos via email
- [ ] Login audit registra todos eventos
- [ ] Rate limiting bloqueia tentativas excessivas
- [ ] Force logout pós-termination funcional
- [ ] Páginas `/admin/seguranca` e `/configuracoes/seguranca`
- [ ] Adapter `src/lib/r2/auth.ts` (estende o de D1)
- [ ] Doc da sessão em `docs/sessao_d2_d3.md`

---

## 11. Pontos de atenção

- **SSO requer Supabase Pro plan**: validar com cliente antes de cobrar enterprise
- **MFA recovery codes**: avisar usuário pra imprimir/salvar · NUNCA mostra de novo
- **Login audit pode crescer rápido**: particionar por mês ou TTL 1 ano
- **Rate limit muito agressivo gera falsos positivos**: ajustar threshold por tenant
- **SAML metadata exchange**: requer ida-e-volta com cliente · documentar processo
- **Session revocation race condition**: trigger pode rodar antes do Supabase Admin call · OK usar checagem no middleware como segundo guard
- **Geo IP**: usar serviço externo (MaxMind GeoLite2) · cuidado com LGPD ao armazenar país
- **WebAuthn (passkey)**: roadmap futuro · spec D4

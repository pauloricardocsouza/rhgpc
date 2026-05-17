# Spec D6 · Segurança Aplicacional

**Status**: especificação · pré-implementação
**Versão**: 1.0 · 17 de maio de 2026
**Escopo**: hardening, headers HTTP, OWASP Top 10, gestão de segredos, pen-test, resposta a incidente
**Depende de**: spec D2/D3 (auth), spec D4 (DR), spec D5 (observability)

---

## 1. Princípios

1. **Defense in depth** · falhar uma camada não compromete o sistema.
2. **Secure by default** · nada exposto por escolha; opt-in para superfície adicional.
3. **Least privilege** · cada token, cada role, cada policy expõe o mínimo necessário.
4. **Auditável** · toda decisão de segurança gera log e métrica.
5. **Recuperável** · cada falha tem runbook publicado e drill periódico.

---

## 2. HTTP security headers (Next.js middleware)

```ts
// middleware.ts
const securityHeaders = {
  'Strict-Transport-Security': 'max-age=63072000; includeSubDomains; preload',
  'X-Content-Type-Options': 'nosniff',
  'X-Frame-Options': 'DENY',
  'Referrer-Policy': 'strict-origin-when-cross-origin',
  'Permissions-Policy': 'camera=(self), microphone=(), geolocation=(), payment=()',
  'Cross-Origin-Opener-Policy': 'same-origin',
  'Cross-Origin-Resource-Policy': 'same-origin',
  'Cross-Origin-Embedder-Policy': 'require-corp',
  'Content-Security-Policy': csp(),
}

function csp(): string {
  const nonce = crypto.randomBytes(16).toString('base64')
  return [
    `default-src 'self'`,
    `script-src 'self' 'nonce-${nonce}' https://*.supabase.co`,
    `style-src 'self' 'unsafe-inline' https://fonts.googleapis.com`,  // unsafe-inline removido em v2 quando todos os componentes migrarem
    `font-src 'self' https://fonts.gstatic.com`,
    `img-src 'self' data: blob: https://*.supabase.co https://rh.solucoesr2.com.br`,
    `connect-src 'self' https://*.supabase.co wss://*.supabase.co https://*.logflare.app`,
    `frame-src 'none'`,
    `object-src 'none'`,
    `base-uri 'self'`,
    `form-action 'self'`,
    `frame-ancestors 'none'`,
    `upgrade-insecure-requests`,
    `report-uri /api/csp-report`,
    `report-to csp-endpoint`
  ].join('; ')
}
```

**Validação**: cada deploy roda `securityheaders.com` API e bloqueia se score < A. Endpoint `/api/csp-report` grava em `csp_violations` para auditoria.

---

## 3. Cookies

| Cookie | Atributos obrigatórios | Lifetime |
|---|---|---|
| `sb-access-token` | HttpOnly · Secure · SameSite=Lax · Path=/ | 1h (refresh via supabase client) |
| `sb-refresh-token` | HttpOnly · Secure · SameSite=Strict · Path=/api/auth | 30d |
| `r2-prefs` | Secure · SameSite=Lax · Path=/ | 1y (preferências UI, sem PII) |
| `r2-csrf` | Secure · SameSite=Strict · HttpOnly | sessão |

Cookies de tracking/marketing: **proibidos**. Substituídos por server-side analytics anonimizadas.

---

## 4. CSRF

- Endpoints mutativos (POST/PUT/DELETE) exigem header `X-R2-CSRF-Token` que bate com cookie `r2-csrf` (double-submit pattern).
- Token rotaciona a cada login e em mudança de role.
- Excecoes: webhook **inbound** (autenticado via HMAC, não usa cookies).

---

## 5. OWASP Top 10 (2021) · matriz de mitigação

| # | Categoria | Risco no R2 People | Mitigação |
|---|---|---|---|
| **A01** | Broken Access Control | RLS quebrada expõe dados cross-tenant | (1) RLS em 100 % das tabelas com `tenant_id`; (2) testes de policy obrigatórios; (3) métrica `r2_rls_denials_total` monitorada |
| **A02** | Cryptographic Failures | senhas, JWT secret, signing keys | (1) bcrypt cost 12 para senhas; (2) JWT HS256 com secret ≥ 256 bits; (3) HMAC SHA-256 para webhooks; (4) TLS 1.3 obrigatório |
| **A03** | Injection | SQL injection via dynamic queries | (1) **só** queries parametrizadas (`pg`/`supabase` client); (2) `pg_format` para nomes; (3) linter rejeita `'+'` em SQL strings |
| **A04** | Insecure Design | leak de CID em logs ou notificações | (1) data classification em código (`@sensitive` decorator); (2) email templates com `email_safe = true` para sensíveis; (3) threat model documentado |
| **A05** | Security Misconfiguration | env vars commitadas, debug em prod | (1) git-secrets pre-commit; (2) `NODE_ENV=production` obrigatório; (3) `/api/admin/*` requer role check; (4) error boundary não vaza stack |
| **A06** | Vulnerable Components | dependências com CVE | (1) Renovate bot semanal; (2) `npm audit --production` no CI bloqueia high+; (3) Snyk integrado |
| **A07** | Identification & Auth Failures | brute force, credential stuffing | (1) rate-limit 3-camadas (IP/email/global · spec D2/D3); (2) MFA obrigatório roles privilegiadas; (3) password mínimo 12 chars, zxcvbn ≥ 3 |
| **A08** | Software & Data Integrity | supply chain attack, deploy malicioso | (1) deploy só via GitHub Actions com OIDC; (2) `npm ci` (lockfile estrito); (3) commits assinados GPG por mantenedores |
| **A09** | Logging & Monitoring Failures | incidente passa despercebido | spec D5 cobre; alertas para anomalias |
| **A10** | SSRF | API que faz fetch a URLs do tenant (webhook test) | (1) whitelist de schemes (http/https only); (2) bloqueio de IPs privados/link-local; (3) timeout 5s |

---

## 6. Secrets management

### 6.1 Storage

- Produção: **Doppler** ou **GitHub Environments + 1Password Connect**.
- Nunca em `.env` versionado. `.env.example` apenas com placeholders.
- Pre-commit hook `git-secrets` com patterns Anthropic/Supabase/Stripe.

### 6.2 Rotação

| Secret | Frequência | Como |
|---|---|---|
| `JWT_SECRET` | 90 dias | Procedimento `rotate_jwt_secret.md` (grace 24h dual-validate) |
| Webhook signing | sob demanda | Botão UI no admin tenant (grace 7d) |
| `DB_PASSWORD` | 180 dias | Migration + reconnect, no impacto se feito em janela |
| SMTP API key | anual ou sob suspeita | Provider painel |
| Service role key | anual | Supabase dashboard |
| OAuth client_secret | anual | Provider painel |

### 6.3 Detecção de leak

- GitHub secret scanning + push protection ativos.
- Scan periódico de logs Logflare via regex (jobs noturnos).
- Honeytoken: 1 fake API key embutida em comentário de código que dispara alerta P1 se for usada.

---

## 7. Input validation

- **Server-side sempre**, client-side é UX.
- Zod schemas para todo body de API. Rejeitar payloads desconhecidos com 400.
- Limites de tamanho: JSON ≤ 100 KB, upload ≤ 10 MB (atestados), texto livre ≤ 10k chars.
- Sanitização HTML em comunicados via DOMPurify + lista branca de tags.
- Validação de domínio em e-mails (MX lookup opcional).
- Validação de CPF/CNPJ por algoritmo (não apenas regex).

---

## 8. Rate limiting (resumo de D2/D3)

| Camada | Limite | Janela | Ação ao exceder |
|---|---|---|---|
| Global por IP | 600 req | 1 min | 429 + `Retry-After` |
| Por usuário autenticado | 6000 req | 1 min | 429 |
| Login por email | 5 tentativas | 15 min | bloqueio + email warning |
| Login por IP | 20 tentativas | 1 min | bloqueio temporário 1h |
| Reset password | 3 emails | 1h | silent ignore (não vaza enumeration) |
| Upload de atestado | 20 | 1h por user | 429 |
| Webhook test | 10 | 1h por tenant | 429 |

Implementado via Upstash Redis (sliding window) ou tabela `rate_limit_buckets` no Postgres para tenant-scoped.

---

## 9. Upload de arquivos (atestados, fotos, docs)

1. **Tipo MIME validado** server-side via `file-type` (não confia em content-type do header).
2. **Whitelist**: PDF, JPG, PNG, HEIC (atestados); JPG/PNG (fotos perfil).
3. **Tamanho máximo**: 10 MB.
4. **Antivírus**: ClamAV scan em worker antes de marcar `validated = true`. Bloqueia se positivo.
5. **OCR client-side** (Tesseract WASM) → texto extraído enviado, original opcional armazenado encriptado.
6. **Storage RLS**: `storage.objects` policy força `tenant_id` no path (`{tenant_id}/atestados/{employee_id}/{file}`).
7. **Signed URLs** com TTL 15 min para download. Nunca URL pública.
8. **EXIF stripping** de imagens antes de salvar (remove GPS).

---

## 10. Pen-test e bug bounty

### 10.1 Pen-test

- Antes do GA: pen-test externo de 5 dias-pessoa por consultoria certificada (CREST/OSCP).
- Anual recorrente.
- Escopo: app web, API, autenticação, RLS, webhooks inbound, integrações.
- Relatório arquivado + plano de remediação com prazos (P1: 7d, P2: 30d, P3: 90d).

### 10.2 Bug bounty (pós-GA)

- Programa privado em HackerOne com 5-10 pesquisadores convidados.
- Escopo claro: `*.solucoesr2.com.br`, exclusões (DOS, social engineering, account creation spam).
- Pagamento por severidade: P1 R$ 10k, P2 R$ 3k, P3 R$ 800, P4 R$ 200.
- SLA de resposta: 48h triagem, 30d fix para P1/P2.

---

## 11. Resposta a incidente de segurança

### 11.1 Fases (NIST SP 800-61)

1. **Preparação** · runbooks, contatos, ferramentas prontas.
2. **Detecção & Análise** · alerta dispara → confirmar falso positivo ou escalar.
3. **Contenção, Erradicação, Recuperação** · isolar → remover → restaurar.
4. **Pós-incidente** · postmortem em 5 dias úteis, ações de melhoria.

### 11.2 Quem aciona o quê

| Severidade | Quem é acionado | Quem comunica externamente |
|---|---|---|
| P1 (vazamento confirmado dado sensível) | CTO + DPO + Jurídico + CEO | DPO comunica ANPD em 48h + clientes afetados |
| P2 (vulnerabilidade explorável sem evidência de uso) | CTO + DPO | Após fix, postmortem público resumido |
| P3 (vulnerabilidade teórica) | CTO + DevSec | Disclosure responsável quando aplicável |
| P4 (config hardening) | DevSec | n/a |

### 11.3 Playbook · suspeita de vazamento

1. Confirmar via logs (`login_audit`, `action_log`)
2. Determinar escopo: quais tenants, quais users, quais dados
3. Revogar sessões dos atores comprometidos
4. Rotacionar todos os secrets potencialmente expostos
5. Snapshot forense (não destruir evidência)
6. Acionar DPO para avaliação Art. 48 LGPD
7. Se confirmado → comunicar ANPD em até 48h via formulário oficial
8. Comunicar titulares afetados em linguagem simples (modelo `templates/breach_notification.md`)
9. Postmortem público em até 30d (com redaction)

---

## 12. Tabelas

```sql
-- CSP violations
CREATE TABLE csp_violations (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  document_uri  text,
  violated_directive text,
  blocked_uri   text,
  source_file   text,
  line_number   int,
  user_agent    text,
  user_id       uuid,
  reported_at   timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX idx_csp_recent ON csp_violations (reported_at DESC);

-- Honeytoken hits
CREATE TABLE honeytoken_hits (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  token_id    text NOT NULL,
  remote_ip   inet,
  user_agent  text,
  context     jsonb,
  hit_at      timestamptz NOT NULL DEFAULT now()
);

-- Audit de mudanças de role/permissão (sensível)
CREATE TABLE security_events (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id    uuid NOT NULL REFERENCES tenants(id),
  actor_id     uuid REFERENCES auth.users(id),
  target_id    uuid REFERENCES auth.users(id),
  event_type   text NOT NULL,  -- role_changed, mfa_reset, password_reset_admin, key_rotated
  before_data  jsonb,
  after_data   jsonb,
  reason       text,
  occurred_at  timestamptz NOT NULL DEFAULT now()
);

-- Vulnerabilidades conhecidas em deps (sync Snyk/Dependabot)
CREATE TABLE known_vulnerabilities (
  cve            text PRIMARY KEY,
  package_name   text NOT NULL,
  affected_range text NOT NULL,
  fixed_in       text,
  severity       text CHECK (severity IN ('low','medium','high','critical')),
  exploitable    boolean,
  in_use         boolean,
  status         text CHECK (status IN ('open','fixed','accepted','wont_fix')),
  detected_at    timestamptz NOT NULL DEFAULT now(),
  fixed_at       timestamptz
);
```

---

## 13. Checklist de hardening pré-GA

- [ ] Todos headers da §2 retornando em `/`, `/api/*`, edge functions
- [ ] CSP score A+ em securityheaders.com
- [ ] SSL Labs score A+ (TLS 1.3, HSTS preload)
- [ ] CSRF token validado em 100 % dos POSTs mutativos
- [ ] RLS habilitada em 100 % das tabelas com `tenant_id` (auto-check via meta-query)
- [ ] `pg_stat_statements` confirma 0 queries com string interpolation
- [ ] Test suite cobre 100 % das RLS policies (1 test deny + 1 test allow por policy)
- [ ] MFA obrigatório para roles `super_admin`, `dpo`, `tenant_admin`
- [ ] Honeytoken plantado e alertando
- [ ] Renovate/Dependabot rodando weekly
- [ ] git-secrets pre-commit ativo
- [ ] Pen-test externo realizado e P1/P2 corrigidos
- [ ] Bug bounty privado configurado
- [ ] Runbook de incidente revisado
- [ ] DPO assinou política de privacidade (LGPD compliance)
- [ ] Logflare alerta em CSP violation P2
- [ ] Cookies só com Secure + HttpOnly + SameSite
- [ ] Upload com ClamAV
- [ ] Signed URLs com TTL ≤ 15 min
- [ ] Service role key **nunca** no client

---

## 14. Testes meta (mínimo 25)

- ✓ HSTS retornado com max-age ≥ 1y
- ✓ CSP bloqueia inline `<script>` sem nonce
- ✓ X-Frame-Options DENY (anti-clickjacking)
- ✓ POST sem CSRF token → 403
- ✓ Cookie sem Secure rejeitado em prod
- ✓ Tentativa de leitura cross-tenant → RLS denial → 404 (não 403, anti-enumeration)
- ✓ SQL injection clássica em filtro → query parametrizada não permite
- ✓ Upload com MIME spoofed → rejeitado por file-type
- ✓ Upload com payload EICAR (ClamAV test) → rejeitado
- ✓ EXIF GPS stripado em foto
- ✓ Signed URL expirada → 401
- ✓ Login 6º fail em 15min → bloqueado
- ✓ Brute force IP 21º fail → bloqueado
- ✓ MFA admin sem token → 401
- ✓ JWT expirado → 401, refresh tenta automaticamente
- ✓ JWT modificado → 401
- ✓ Webhook inbound sem HMAC → 401
- ✓ Webhook inbound HMAC inválido → 401
- ✓ SSRF tentando 127.0.0.1 → bloqueado
- ✓ SSRF tentando file:// → bloqueado
- ✓ Password fraca (zxcvbn < 3) → rejeitada
- ✓ Senha em log → linter falha CI
- ✓ npm audit high → CI falha
- ✓ Honeytoken acionado → alerta P1
- ✓ CSP violation grava em tabela

---

## 15. Roadmap pós-MVP

1. **mTLS** para integrações high-value (folha externa).
2. **Audit log assinado** (hash chain, tipo blockchain-light) para garantia de não-tampering.
3. **HSM** (Hardware Security Module) para signing keys de webhook e JWT.
4. **WebAuthn / Passkeys** como alternativa a TOTP para 2FA.
5. **Confidential computing** (Postgres on TEE) para dados ultra-sensíveis.
6. **DLP** (Data Loss Prevention) com regex+ML monitorando exports.

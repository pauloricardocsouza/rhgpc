# Spec D8 · Multi-tenant Isolation Patterns · RLS Testing & Attack Matrix

**Status**: especificação · pré-implementação
**Versão**: 1.0 · 18 de maio de 2026
**Escopo**: padrões arquiteturais de isolamento, framework de testes RLS, matriz de ataques cross-tenant, monitoramento de violações
**Depende de**: schema v9+ (RLS em 100% das tabelas com `tenant_id`), spec D6 (Security), spec D7 (Compliance LGPD)

---

## 1. Princípios duros (não-negociáveis)

1. **Default deny.** Toda tabela com `tenant_id` tem RLS habilitada. Sem policy = sem acesso.
2. **Isolation by construction.** Erro de policy precisa ser detectado em CI, não em produção.
3. **No bypass por aplicação.** O front-end não decide isolamento. O banco decide.
4. **RLS deniais são sinal de segurança.** Spike de denials = potencial exploit, alerta P2.
5. **Service role é exceção, não regra.** Cada uso de `service_role` é justificado e auditado.

---

## 2. Padrões de policy por categoria

### 2.1 Tabelas tenant-scoped (default)

**Padrão A · Isolamento total**

```sql
CREATE POLICY tbl_tenant_isolation ON some_table
  FOR ALL
  USING (tenant_id = (current_setting('app.tenant_id', true))::uuid)
  WITH CHECK (tenant_id = (current_setting('app.tenant_id', true))::uuid);
```

- USING controla SELECT/UPDATE/DELETE
- WITH CHECK impede INSERT/UPDATE em outro tenant
- `current_setting('app.tenant_id', true)` é definido pela app via `set_config()` antes de cada query

### 2.2 Tabelas com hierarquia (líder vê subordinados)

**Padrão B · Hierarquia + tenant**

```sql
CREATE POLICY emp_tenant_and_visibility ON employees
  FOR SELECT
  USING (
    tenant_id = (current_setting('app.tenant_id', true))::uuid
    AND (
      -- Self
      user_id = auth.uid()
      -- Subordinado direto
      OR manager_id = (SELECT id FROM employees WHERE user_id = auth.uid() LIMIT 1)
      -- Role RH/diretoria com permissão de view all
      OR EXISTS (
        SELECT 1 FROM user_permissions
        WHERE user_id = auth.uid()
          AND permission = 'view_all_employees'
          AND tenant_id = employees.tenant_id
      )
    )
  );
```

### 2.3 Tabelas globais (sem tenant_id)

**Padrão C · Só super_admin / service_role**

```sql
CREATE POLICY plans_public_read ON plans FOR SELECT USING (visible = true);
CREATE POLICY incidents_super_admin ON incidents FOR ALL
  USING (
    auth.jwt() ->> 'role' = 'super_admin'
    OR auth.role() = 'service_role'
  );
```

### 2.4 Tabelas filhas de tenant (via FK)

**Padrão D · Herdar via JOIN**

```sql
-- dsar_audit_trail herda tenant_id de dsar_requests
CREATE POLICY dsar_audit_via_parent ON dsar_audit_trail
  FOR ALL
  USING (
    dsar_id IN (
      SELECT id FROM dsar_requests
      WHERE tenant_id = (current_setting('app.tenant_id', true))::uuid
    )
  );
```

### 2.5 Tabelas com dado sensível (CID, salário)

**Padrão E · Tenant + permissão específica**

```sql
CREATE POLICY mc_view_cid ON medical_certificates
  FOR SELECT
  USING (
    tenant_id = (current_setting('app.tenant_id', true))::uuid
    AND (
      -- Owner sempre vê seu próprio
      user_id = auth.uid()
      -- DPO/RH com perm explícita
      OR EXISTS (
        SELECT 1 FROM user_permissions
        WHERE user_id = auth.uid()
          AND permission IN ('view_medical_cid', 'dpo_full_access')
          AND tenant_id = medical_certificates.tenant_id
      )
    )
  );

-- CID nunca aparece em SELECT sem permissão (column-level fora do MVP)
-- Solução MVP: VIEW que esconde CID para roles sem permissão
CREATE VIEW v_medical_certificates_safe AS
SELECT
  id, tenant_id, user_id, days, type, validated_at, validated_by,
  CASE
    WHEN EXISTS (
      SELECT 1 FROM user_permissions
      WHERE user_id = auth.uid()
        AND permission IN ('view_medical_cid', 'dpo_full_access')
    ) THEN cid
    ELSE NULL
  END AS cid
FROM medical_certificates;
```

---

## 3. Framework de testes RLS

### 3.1 Estrutura `supabase/tests/rls/`

Cada tabela tem arquivo `<tabela>_rls_test.sql`:

```sql
-- Exemplo: supabase/tests/rls/employees_rls_test.sql
BEGIN;

SELECT plan(8); -- pgtap

-- Seed
INSERT INTO tenants (id, slug) VALUES
  ('a1111111-1111-1111-1111-111111111111', 'tenant_a'),
  ('b2222222-2222-2222-2222-222222222222', 'tenant_b');
INSERT INTO auth.users (id, email) VALUES
  ('aaa', 'user_a@a.com'), ('bbb', 'user_b@b.com');
INSERT INTO employees (id, tenant_id, user_id, full_name) VALUES
  ('e_a', 'a1111111...', 'aaa', 'Funcionário A'),
  ('e_b', 'b2222222...', 'bbb', 'Funcionário B');

-- Test 1 · User A vê seu próprio
SELECT set_config('app.tenant_id', 'a1111111-1111-1111-1111-111111111111', false);
SELECT set_config('request.jwt.claims', '{"sub":"aaa"}', false);
SELECT ok(
  (SELECT count(*) FROM employees WHERE id = 'e_a') = 1,
  'User A vê seu próprio funcionário'
);

-- Test 2 · User A NÃO vê funcionário do tenant B
SELECT ok(
  (SELECT count(*) FROM employees WHERE id = 'e_b') = 0,
  'User A não vê funcionário do tenant B (RLS bloqueia)'
);

-- Test 3 · User A NÃO pode INSERT em tenant B
PREPARE bad_insert AS
  INSERT INTO employees (tenant_id, user_id, full_name)
  VALUES ('b2222222-2222-2222-2222-222222222222', 'aaa', 'fake');
SELECT throws_ok(
  'EXECUTE bad_insert',
  '42501', -- insufficient_privilege
  'permission denied',
  'User A não pode INSERT em tenant B'
);

-- Test 4 · User A NÃO pode UPDATE funcionário tenant B
PREPARE bad_update AS UPDATE employees SET full_name = 'pwned' WHERE id = 'e_b';
SELECT lives_ok('EXECUTE bad_update', 'UPDATE não falha mas...');
SELECT ok(
  (SELECT full_name FROM employees WHERE id = 'e_b'
   AND tenant_id = 'b2222222-2222-2222-2222-222222222222') = 'Funcionário B',
  'UPDATE não afetou linha do tenant B (RLS WITH CHECK bloqueou)'
);

-- ... (4 testes adicionais cobrindo DELETE, hierarquia, etc)

ROLLBACK;
SELECT * FROM finish();
```

### 3.2 Regra de cobertura

- **Cada tabela com tenant_id**: mínimo 4 testes (SELECT allow, SELECT deny, INSERT deny, UPDATE deny cross-tenant).
- **Tabelas com hierarquia**: + 2 testes (líder vê subordinado, líder não vê fora hierarquia).
- **Tabelas sensíveis (CID, salário)**: + 2 testes (com permissão vê, sem permissão não vê).
- **Tabelas filhas**: + 1 teste (herda RLS do pai).

### 3.3 CI bloqueante

```yaml
# .github/workflows/test.yml
- name: Run pgtap RLS tests
  run: |
    supabase test db
    # Falha CI se algum teste falhou
```

Pull request **não pode** ser merged se algum teste RLS falhar.

---

## 4. Attack matrix · cenários simulados

A matriz lista **20 ataques cross-tenant** que precisam falhar (todos cobertos por testes automatizados).

### 4.1 SELECT

| # | Ataque | Vetor | Resultado esperado |
|---|---|---|---|
| 1 | Listar employees de outro tenant | `SELECT * FROM employees` sem set_config | 0 linhas |
| 2 | Buscar employee_id específico de outro tenant | `WHERE id = 'known_uuid'` | 0 linhas |
| 3 | Listar atestados com CID de outro tenant | `SELECT cid FROM medical_certificates` | NULL ou 0 linhas |
| 4 | Listar movements de outro tenant | `SELECT * FROM movements` | 0 linhas |
| 5 | Listar payroll de outro tenant | `SELECT * FROM payroll_runs` | 0 linhas |
| 6 | Listar invoices de outro tenant | `SELECT * FROM invoices` | 0 linhas |
| 7 | Listar dsar_requests de outro tenant | `SELECT * FROM dsar_requests` | 0 linhas |
| 8 | Listar consents de outro tenant | `SELECT * FROM consents` | só os do user_id próprio |

### 4.2 INSERT (escalation)

| # | Ataque | Vetor | Resultado esperado |
|---|---|---|---|
| 9 | INSERT employee em tenant alheio | `INSERT (tenant_id='b...', ...)` com tenant_id='a' setado | erro 42501 |
| 10 | INSERT movement aprovação para outro funcionário | `INSERT movement(employee_id=external)` | erro 42501 |
| 11 | INSERT user_permission `view_all` em outro tenant | tentativa de escalation | erro 42501 |
| 12 | INSERT seat_assignment em tenant alheio | violação quota | erro 42501 |

### 4.3 UPDATE (data tampering)

| # | Ataque | Vetor | Resultado esperado |
|---|---|---|---|
| 13 | UPDATE employee.salary de outro tenant | `UPDATE WHERE id='external'` | 0 rows affected |
| 14 | UPDATE atestado.validated de outro tenant | tentativa de validar atestado alheio | 0 rows |
| 15 | UPDATE consents.granted=true em nome de outro user | `UPDATE consents WHERE user_id='other'` | 0 rows |
| 16 | UPDATE dsar_request.status para evitar SLA | tentativa de adiar prazo legal | 0 rows |

### 4.4 DELETE

| # | Ataque | Vetor | Resultado esperado |
|---|---|---|---|
| 17 | DELETE employee de outro tenant | `DELETE WHERE id='external'` | 0 rows |
| 18 | DELETE login_audit (cobrir rastro) | RLS bloqueia delete para roles não-DPO | erro |

### 4.5 RPC bypass

| # | Ataque | Vetor | Resultado esperado |
|---|---|---|---|
| 19 | Chamar RPC com tenant_id arbitrário | `rpc_create_movement(tenant_id='external', ...)` | erro de validação na RPC |
| 20 | Chamar `service_role` RPC sem autorização | usar token comum em RPC privilegiada | erro 401 |

---

## 5. Monitoramento de violações (sinal de exploit)

### 5.1 Métrica `r2_rls_denials_total`

Coletada via trigger ou exception handler:

```sql
CREATE OR REPLACE FUNCTION fn_log_rls_denial()
RETURNS event_trigger AS $$
BEGIN
  -- Quando RLS bloqueia uma operação, registra
  INSERT INTO rls_denial_log (
    tenant_id_attempted,
    table_name,
    operation,
    user_id,
    occurred_at
  ) VALUES (
    current_setting('app.tenant_id', true),
    TG_TABLE_NAME,
    TG_OP,
    auth.uid(),
    now()
  );
END;
$$ LANGUAGE plpgsql;
```

Alternativa: postgres logs com `log_statement = 'error'` + parser que extrai violações 42501 e envia para Logflare como métrica.

### 5.2 Tabela `rls_denial_log`

```sql
CREATE TABLE IF NOT EXISTS rls_denial_log (
  id                    uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id_attempted   uuid,
  user_id               uuid REFERENCES auth.users(id),
  table_name            text NOT NULL,
  operation             text NOT NULL CHECK (operation IN ('SELECT','INSERT','UPDATE','DELETE','EXECUTE')),
  query_snippet         text,
  remote_ip             inet,
  user_agent            text,
  classified_as         text CHECK (classified_as IN ('benign','suspicious','exploit_attempt','unclassified')) DEFAULT 'unclassified',
  occurred_at           timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX idx_rls_denial_recent ON rls_denial_log (occurred_at DESC);
CREATE INDEX idx_rls_denial_user ON rls_denial_log (user_id, occurred_at DESC);
```

### 5.3 Alertas (spec D5)

| Condição | Severity | Ação |
|---|---|---|
| Baseline RLS denials (< 50/dia em prod) | — | normal, possibly bot/scan |
| Spike > 10× baseline em 5 min | P2 | investigar IP/user |
| Mesmo `user_id` causa > 100 denials em 1h | P2 | bloquear user temporariamente + revisar |
| Múltiplos `tenant_id_attempted` distintos do mesmo user | P1 | possível exploit cross-tenant, acionar DPO |
| Denial em tabela sensível (medical_certificates, payroll, dsar) | P2 | escalar para Security |

---

## 6. Auditoria periódica · checklist

A cada release major + uma vez por trimestre:

- [ ] **100% das tabelas com `tenant_id`** têm RLS habilitada (query SELECT em `pg_tables` + check)
- [ ] **100% das tabelas com RLS** têm pelo menos 1 policy `FOR ALL`
- [ ] **Todas as policies usam `current_setting('app.tenant_id')`** (anti-pattern: hard-coded UUID)
- [ ] **Nenhuma policy usa `USING (true)`** (anti-pattern: bypass)
- [ ] **`service_role`** só é usado em RPCs marcadas `SECURITY DEFINER` com `search_path` setado
- [ ] **Cada policy tem teste pgtap correspondente**
- [ ] **Attack matrix completa** rodando em CI (20 testes verdes)
- [ ] **Métrica `r2_rls_denials_total`** está sendo coletada
- [ ] **Alertas configurados** para spikes/cross-tenant attempts

Auto-check via:

```sql
-- Tabelas com tenant_id mas SEM RLS
SELECT t.table_name
FROM information_schema.tables t
JOIN information_schema.columns c
  ON c.table_name = t.table_name AND c.column_name = 'tenant_id'
WHERE t.table_schema = 'public'
  AND t.table_name NOT IN (
    SELECT tablename FROM pg_tables WHERE rowsecurity = true
  );
-- Deve retornar 0 linhas
```

---

## 7. Anti-patterns proibidos

```sql
-- ❌ NUNCA fazer
CREATE POLICY bypass ON some_table FOR ALL USING (true);

-- ❌ NUNCA fazer (hard-coded tenant)
CREATE POLICY hard ON some_table FOR ALL
  USING (tenant_id = '01234567-89ab-cdef-0123-456789abcdef');

-- ❌ NUNCA fazer (usa app-level filter, não RLS)
SELECT * FROM employees WHERE tenant_id = $1; -- $1 vem do front-end

-- ❌ NUNCA fazer (service_role via app)
const supabase = createClient(URL, SERVICE_ROLE_KEY); // no client side!

-- ✅ SEMPRE fazer
SET app.tenant_id = '...'; -- via middleware
SELECT * FROM employees; -- RLS resolve isolamento
```

---

## 8. Service role · justificativas válidas

Os únicos lugares onde `service_role` é aceitável:

1. **Jobs cron** (retention, smoke tests, métricas snapshot)
2. **Webhooks signing/HMAC** (workers que precisam acessar tenant_webhooks)
3. **Rate limit global** (verificar contadores cross-tenant)
4. **DPO operations** (DSAR cross-tenant scan)
5. **Migrations e DDL**

Cada uso é **logado em `security_events`** com `actor_id = 'system'` + `reason`.

---

## 9. Multi-tenant em outros camadas

### 9.1 Storage (Supabase)

```
gpc/atestados/12345678-../arquivo.pdf
└── slug ── tipo ── tenant_id ── arquivo
```

Policy de storage:

```sql
CREATE POLICY storage_tenant_isolation ON storage.objects
  FOR SELECT USING (
    bucket_id = 'atestados'
    AND (storage.foldername(name))[1] = (current_setting('app.tenant_id', true))
  );
```

### 9.2 Realtime (Supabase channels)

Cada canal é prefixado por tenant_id:

```ts
// ✅ Correto
realtime.channel(`tenant:${tenant_id}:notifications`)

// ❌ Errado (canal global vaza eventos cross-tenant)
realtime.channel('notifications')
```

JWT contém `tenant_id` claim → Supabase Realtime filtra automaticamente.

### 9.3 Edge Functions / Workers

Cada worker recebe `tenant_id` explícito como parâmetro e seta via `set_config()` antes da primeira query:

```ts
export async function processWebhook(payload: { tenant_id: string, event: any }) {
  await db.query(`SELECT set_config('app.tenant_id', $1, false)`, [payload.tenant_id]);
  // ... resto do código com isolamento garantido
}
```

---

## 10. Testes meta (mínimo 25)

### 10.1 Cobertura básica
- ✓ 100% das tabelas tenant-scoped têm RLS habilitada
- ✓ 100% das tabelas com RLS têm ≥ 1 policy
- ✓ 0 policies usam `USING (true)`
- ✓ 0 policies hard-codeiam tenant_id
- ✓ Auto-check de cobertura roda em CI semanal

### 10.2 Attack matrix (20 testes)
- ✓ Cada um dos 20 ataques da §4 falha conforme esperado
- ✓ Suite roda em < 30s em CI

### 10.3 Hierarquia
- ✓ Líder vê funcionário subordinado
- ✓ Líder NÃO vê funcionário de outro líder
- ✓ RH com `view_all` vê todos do tenant
- ✓ Diretoria vê agregado consolidado, não dados individuais

### 10.4 Dado sensível
- ✓ User comum não vê CID nem em SELECT direto, nem em VIEW
- ✓ RH com permissão view_medical_cid vê CID
- ✓ DPO sempre vê (full_access)
- ✓ Líder NUNCA vê (mesmo do próprio subordinado)
- ✓ Logger registra acesso a CID em action_log

### 10.5 Service role
- ✓ service_role nunca aparece em código client-side (lint check)
- ✓ Cada RPC SECURITY DEFINER tem search_path setado
- ✓ Cada uso de service_role gera `security_events`

### 10.6 Storage
- ✓ Upload em path tenant_id alheio falha
- ✓ Download de arquivo de outro tenant falha (mesmo com URL conhecida)
- ✓ Listing bucket sem tenant_id retorna vazio

---

## 11. Runbook · suspeita de exploit cross-tenant

1. **Detecção**: alerta P1 dispara (multi-tenant_id distinct do mesmo user)
2. **Isolamento imediato**: bloquear user via `auth.admin.updateUserById(id, { ban_duration: '24h' })`
3. **Snapshot forense**: dump de `rls_denial_log` últimas 24h do user
4. **Análise**: pattern de queries indica scan/exploit deliberado?
5. **Comunicação interna**: CTO + DPO acionados em < 30min
6. **Confirmação**: se dados foram vazados → comunicação ANPD em 48h (Art. 48 LGPD)
7. **Revogação**: rotacionar JWT secret, invalidar todas as sessões do tenant alvo
8. **Post-mortem**: registrar em `incidents` (spec D5) com classificação P1
9. **Hardening**: novos testes RLS para cobrir o vetor explorado

---

## 12. Roadmap pós-MVP

1. **Column-level security** nativo (PostgreSQL 16+) para CID/salário/CPF
2. **Per-tenant encryption keys** (cada tenant tem chave própria, derivada via KMS)
3. **Schema-per-tenant** opção Enterprise (isolamento físico, não só lógico)
4. **Read replica per tenant** Enterprise (analytics sem impactar prod)
5. **DLP automatizado** (Data Loss Prevention) escaneando exports por padrões PII
6. **Honey-tenant** (tenant fake plantado, qualquer acesso = alerta P1 imediato)

# R2 People · Schema base v1 (Sessao H)

Schema fundacional do R2 People · cobre Sessoes A-D consolidadas em um unico arquivo SQL aplicavel em projeto Supabase novo.

**Pre-requisito de**: schema Climate v8, schema PDI (futuro), e qualquer modulo posterior.

---

## O que entra

### Tabelas (8 + 1 catalogo)

| Tabela | Resumo | RLS |
|---|---|---|
| `tenants` | Empresa cliente · multi-tenant rigido | Self-read · Diretoria edita |
| `employer_units` | Entidade juridica (CNPJ) | Tenant-read · RH/Diretoria escreve |
| `working_units` | Loja fisica / CD / escritorio | Tenant-read · RH/Diretoria escreve |
| `departments` | Hierarquia organizacional opcional | Tenant-read · RH/Diretoria escreve |
| `app_users` | Pessoas (vinculo 1:1 com auth.users) | Self + Manager + RH/Diretoria |
| `app_user_external_ids` | Matricula em sistemas externos | Self-read · RH/Diretoria escreve |
| `permissions` | Catalogo global · 25 permissoes | Todos leem ativos |
| `role_permissions` | Matriz role x permission | Todos leem |
| `audit_log` | Trilha de auditoria | RH/Diretoria leem · escrita so via trigger |

### Enums (7)

`tenant_status`, `app_user_role`, `employment_link`, `unit_type`, `audit_action`, `permission_scope`, `idp_provider`

### Funcoes helper (5)

| Funcao | Descricao |
|---|---|
| `current_user_id()` | Retorna `app_users.id` do usuario autenticado · NULL se nao autenticado |
| `current_tenant_id()` | Retorna `tenant_id` do usuario autenticado |
| `current_user_role()` | Retorna a role (`colaborador`/`lider`/`rh`/`diretoria`) |
| `user_has_permission(perm)` | Consulta a matriz role_permissions |
| `user_is_manager_of(subordinado_id)` | Sobe a cadeia `manager_id` (max 10 niveis) e checa se o caller esta no caminho |

Todas com `SECURITY DEFINER` e leitura via `auth.uid()`.

### Triggers automaticos (8)

- 6 triggers `set_updated_at()` em todas as tabelas com `updated_at` (usa `clock_timestamp()` para funcionar dentro de transacoes longas)
- 4 triggers `audit_change()` em `app_users`, `employer_units`, `working_units`, `departments`

### Policies RLS (18)

Cobrem `tenants`, `employer_units`, `working_units`, `departments`, `app_users`, `app_user_external_ids`, `permissions`, `role_permissions`, `audit_log`.

### Catalogo de permissoes (25)

Distribuidas por modulo:

| Modulo | Quantidade | Exemplos |
|---|---|---|
| `core` | 9 | view_tenant, manage_tenant, view_audit_log, manage_departments |
| `people` | 7 | view_self_profile, view_team_profiles, manage_users, manage_user_roles |
| `pdi` | 6 | view_self_pdi, view_team_pdi, view_all_pdi, manage_all_pdi |
| `climate` | 3 | respond_climate, manage_climate, view_climate_results |

### Matriz role x permission (68 entradas)

| Role | # permissoes | Alcance |
|---|---|---|
| `colaborador` | 9 | Self only · responde clima, faz proprio PDI |
| `lider` | 12 | Self + team · ve PDIs do time |
| `rh` | 22 | Tudo de gestao + criar pulsos clima · NAO ve resultados consolidados |
| `diretoria` | 25 | Tudo + ver resultados de clima + alterar roles + editar tenant |

---

## Ordem de aplicacao no Supabase

```
1. r2_people_schema_base_v1.sql            ← este pacote (Sessao H)
2. r2_people_seed_base_v1.sql              ← este pacote (Sessao H)
3. r2_people_rls_policies_base_tests.sql   ← opcional · valida o schema (Sessao H)

4. r2_people_schema_climate_v8.sql         ← Sessao E
5. r2_people_seed_climate_v8.sql           ← Sessao E
6. r2_people_rls_policies_climate_tests.sql ← Sessao E (opcional)

(modulos PDI, Reconhecimentos, 9-Box virao em sessoes futuras)
```

Cada arquivo SQL e idempotente (usa `CREATE IF NOT EXISTS`, `ON CONFLICT`, `DROP TRIGGER IF EXISTS`).

---

## Como aplicar

### 1. Criar projeto Supabase

Veja `r2_people_supabase_setup.md` (entregue na Sessao G). Resumo:

- Crie projeto em https://supabase.com/dashboard
- Regiao: `South America (Sao Paulo)`
- Anote URL, anon key, service_role key

### 2. Aplicar schema base

No SQL Editor do Supabase Dashboard, copie e cole na ordem:

1. Conteudo de `r2_people_schema_base_v1.sql` · clique em **Run** · espere "Success. No rows returned"
2. Conteudo de `r2_people_seed_base_v1.sql` · clique em Run · vai mostrar 5 INSERTs (25 + 4 roles)

### 3. Validar

```sql
-- Devem retornar:
SELECT count(*) FROM tenants;            -- 0
SELECT count(*) FROM permissions;        -- 25
SELECT count(*) FROM role_permissions;   -- 68
SELECT count(*) FROM information_schema.tables WHERE table_schema = 'public';   -- 9
SELECT count(*) FROM pg_policies WHERE schemaname = 'public';                   -- 18
```

### 4. Rodar testes (opcional)

Cole `r2_people_rls_policies_base_tests.sql` no SQL Editor. Os testes rodam dentro de uma transacao com `BEGIN ... ROLLBACK` no fim · nao deixam dados.

Voce devera ver no log do Supabase 20 NOTICEs `--- TESTE N · ...` e ao fim `=== TODOS OS TESTES PASSARAM ===`.

### 5. Criar primeiro tenant + admin

Apos aplicar o schema, voce precisa de:

- 1 tenant (a empresa cliente)
- 1 employer_unit (CNPJ inicial)
- 1 working_unit (loja/escritorio)
- 1 department (opcional)
- 1 user com role `diretoria` (para liberar acesso ao painel admin)
- 1 entrada em `auth.users` do Supabase Auth (criada via Supabase Dashboard > Authentication > Users)
- Vincular `auth.users.id` ao campo `app_users.auth_user_id`

Exemplo minimo (rodar como `service_role` apenas):

```sql
-- 1. Criar tenant
INSERT INTO tenants (id, slug, legal_name, display_name)
VALUES (gen_random_uuid(), 'gpc', 'Grupo Pinto Cerqueira', 'GPC')
RETURNING id;
-- copiar o id retornado para usar nas proximas

-- 2. Employer unit
INSERT INTO employer_units (tenant_id, code, legal_name, cnpj)
VALUES ('<TENANT_ID>', 'ATP', 'ATP Varejo Ltda', '12345678000190');

-- 3. Working unit (precisa do employer_unit_id da query anterior)
INSERT INTO working_units (tenant_id, employer_unit_id, code, display_name)
VALUES ('<TENANT_ID>', '<EMPLOYER_UNIT_ID>', 'L1', 'ATP L1');

-- 4. Department
INSERT INTO departments (tenant_id, code, display_name)
VALUES ('<TENANT_ID>', 'DIRETORIA', 'Diretoria');

-- 5. Criar usuario no Supabase Auth pelo Dashboard
--    Authentication > Users > Add User > "diretor@empresa.com.br" + senha
--    Copiar o auth_user_id gerado

-- 6. Criar app_user vinculado
INSERT INTO app_users (
  tenant_id, auth_user_id, email, full_name, role,
  employer_unit_id, working_unit_id, department_id,
  employment_link, hired_at
) VALUES (
  '<TENANT_ID>', '<AUTH_USER_ID>',
  'diretor@empresa.com.br', 'Diretor Inicial', 'diretoria',
  '<EMPLOYER_UNIT_ID>', '<WORKING_UNIT_ID>', '<DEPT_ID>',
  'clt', '2024-01-01'
);
```

Apos isso, qualquer query autenticada como esse usuario tera acesso completo ao tenant via RLS.

---

## Decisoes arquiteturais importantes

### Por que 2 tabelas para "unidade"?

`employer_units` (entidade juridica) e separado de `working_units` (loja fisica) porque uma pessoa pode ser contratada por uma CNPJ X e trabalhar em uma loja Y. No GPC isso e comum (ex.: contratada por ATP Varejo trabalhando na L1 de Cestao). Reportagem fiscal usa `employer_unit`, alocacao operacional usa `working_unit`.

### Por que `manager_id` self-ref e nao tabela `team_memberships`?

Hierarquia de gestao no R2 People e estrita: cada pessoa tem UM gestor direto (ou nenhum). Nao temos matriciamento formal. Self-ref e suficiente e performatica.

A funcao `user_is_manager_of()` resolve hierarquia indireta (gestor do gestor) com limite de 10 niveis.

### Por que `audit_log.tenant_id` e DEFERRABLE?

Quando deletamos um tenant, o cascade dispara DELETEs em todas as tabelas filhas. Cada DELETE dispara o trigger `audit_change()` que tenta inserir em `audit_log`. Se a FK fosse imediata, o INSERT do trigger falharia porque o tenant ja esta marcado para delete na mesma transacao.

`DEFERRABLE INITIALLY DEFERRED` posterga a checagem para o final da transacao · ai a coluna `tenant_id` ja foi posta como NULL pelo cascade ON DELETE SET NULL e tudo funciona.

### Por que `set_updated_at()` usa `clock_timestamp()`?

`now()` retorna o timestamp do **inicio da transacao**. Se voce faz INSERT + UPDATE na mesma transacao, ambos recebem o mesmo timestamp e fica impossivel distinguir.

`clock_timestamp()` retorna o momento real da chamada · garante que UPDATEs sempre tem timestamp posterior ao INSERT.

### Por que permissoes nao tem `tenant_id`?

O catalogo de permissoes e **global** · todas as empresas do SaaS usam as mesmas. Tenants podem customizar a matriz `role_permissions` no futuro (tabela override pendente), mas o vocabulario de permissoes e fixo.

### Por que `auth_user_id` e UNIQUE global e nao por tenant?

Uma `auth.users` do Supabase representa UMA identidade. Em principio, uma pessoa pode pertencer a mais de um tenant (ex.: consultor que atende varias empresas), mas isso seria UM `auth.users` mapeando para multiplos `app_users`.

Decisao desta versao: simplificar e exigir 1:1. Se for preciso multi-tenant por usuario depois, o caminho e:

1. Criar tabela `app_user_tenant_links (auth_user_id, tenant_id, role, ...)`
2. Tornar `app_users.auth_user_id` nullable e nao-UNIQUE
3. Ajustar `current_tenant_id()` para ler de uma claim do JWT em vez do app_users

---

## Pendencias conscientes

- **Migration de dados** se voce ja tiver app_users no schema antigo (Climate v8 standalone)
- **Schema PDI** ainda nao integra com este schema base (esta esperando Sessao I+)
- **Storage** para avatars (campo `avatar_url` aceita URL externa por enquanto)
- **Multi-tenant por usuario** (descrito acima · adiar)
- **Audit retention policy** (cleanup periodico do audit_log apos N anos)
- **i18n de permissoes** (campo description so em PT-BR atualmente)
- **Logs de login/logout** via audit_log nao tem trigger ainda · precisa ser inserido manualmente no fluxo de auth do app

---

## Validacao realizada

Schema, seed e testes foram aplicados em PostgreSQL 16 local com stub para `auth.uid()`:

| Verificacao | Resultado |
|---|---|
| Schema aplica sem erros | OK |
| Seed insere 25 permissoes + 68 role_permissions | OK |
| Schema cria 9 tabelas, 7 enums, 18 policies, 18 triggers | OK |
| 20 testes em `r2_people_rls_policies_base_tests.sql` | 20/20 passam |

Os testes cobrem: helpers, matriz de permissoes, constraints de email/CPF/CNPJ/self-manager/terminated_at, UNIQUE composto, soft-delete, trigger updated_at, trigger audit_change, CASCADE de tenant, hierarquia de departments, JSONB, auth_user_id UNIQUE.

---

DESENVOLVIDO POR R2 SOLUCOES EMPRESARIAIS · 2026

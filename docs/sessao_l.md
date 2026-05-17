# R2 People · Sessão L · Schema Modules

Sistema de **módulos com ativação gradual** por escopo (tenant > employer_unit > working_unit), controlado pelo **super_admin R2** (role global).

## Por que isso importa

Implantação gradual em GPC fica muito mais fácil. R2 pode liberar:

- **Onboarding em todo o GPC** desde o início (jornada de admissão é universal)
- **PDI só no Cestão Inhambupe primeiro** (piloto numa loja antes de expandir)
- **Climate em todas as ATPs** (testar em uma rede inteira antes de Cestão)
- **Recognition em employer_unit ATP** (todas as lojas ATP, mas não Cestão ainda)

Cada módulo desativado fica oculto no menu e bloqueado por RLS no backend.

## Resumo

Sexto módulo da plataforma. Cobre:

- Catálogo global de módulos (gerenciado pela R2)
- Ativações por escopo `tenant`, `employer_unit` ou `working_unit`
- **Herança automática**: ativo no tenant cobre tudo abaixo
- Role `super_admin` global (fora dos tenants)
- Modulos `is_core` (como `base`) sempre ativos
- Helpers `is_super_admin()` e `module_is_active(code, wu_id)` para uso em outras policies

## Decisões da Sessão L

| Decisão | Valor |
|---|---|
| Granularidade | tenant + employer_unit + working_unit |
| Quem libera | Super admin R2 (global, fora dos tenants) |
| Modelo | Flag liga/desliga (sem datas) |
| Bloqueio | 404 frontend / RLS bloqueia backend |
| Catálogo | 4 módulos atuais + base (core) |
| Herança | Working > Employer > Tenant (qualquer nível ativo = TRUE) |

## Pré-requisitos

- `r2_people_schema_base_v1.sql` (Sessão H) aplicado
- `r2_people_seed_base_v1.sql` aplicado

## Arquivos

| Arquivo | Conteúdo |
|---|---|
| `r2_people_schema_modules_v1.sql` | 1 enum, 2 tabelas, 6 RPCs, 3 helpers, 5 policies, 3 triggers, 7 indexes |
| `r2_people_seed_modules_v1.sql` | 5 módulos no catálogo (base + 4 funcionais) |
| `r2_people_rls_policies_modules_tests.sql` | 20 testes (catálogo, herança, super_admin, idempotência) |

## Ordem de aplicação

```bash
psql -f r2_people_schema_modules_v1.sql
psql -f r2_people_seed_modules_v1.sql
psql -f r2_people_rls_policies_modules_tests.sql   # opcional · validação
```

## Estrutura

### Catálogo

```
modules
├── base          (is_core=TRUE  · sempre ativo)
├── climate       (Clima Organizacional)
├── recognition   (Reconhecimentos)
├── pdi           (Plano de Desenvolvimento Individual)
└── onboarding    (Jornada de admissão)
```

### Ativação

Cada row em `module_activations` representa uma ativação num escopo:

```
module_activations
├── module_code (FK modules.code)
├── scope_kind  (tenant | employer_unit | working_unit)
└── exatamente um de:
    ├── tenant_id
    ├── employer_unit_id
    └── working_unit_id
```

Constraint `module_activations_scope_match` garante coerência entre `scope_kind` e qual ID está preenchido.

### Herança

Quando alguém pergunta "o módulo X está ativo para a working_unit Y?", a função `module_is_active(code, wu_id)` resolve assim:

```
1. Se modules.is_core = TRUE -> retorna TRUE (sempre)
2. Procura activation no working_unit_id = Y
3. Procura activation no employer_unit_id (do parent de Y)
4. Procura activation no tenant_id (do parent do parent)
5. Se NENHUM dos 3 -> retorna FALSE
```

## Enums

- `module_scope_kind` · `tenant`, `employer_unit`, `working_unit`
- Adicionado `super_admin` ao enum `app_user_role` existente

## RPCs

| RPC | Quem pode | O que faz |
|---|---|---|
| `rpc_modules_catalog_list()` | Qualquer autenticado | Lista catálogo global de módulos |
| `rpc_module_activate(code, scope, tenant?, employer?, working?, notes?)` | **Só super_admin** | Ativa módulo no escopo (idempotente) |
| `rpc_module_deactivate(code, scope, tenant?, employer?, working?)` | **Só super_admin** | Desativa do escopo (não cascateia) · core protegido |
| `rpc_module_activations_by_tenant(tenant_id)` | Super_admin (qualquer) ou diretoria do próprio tenant | Lista todas ativações do tenant inteiro |
| `rpc_my_active_modules()` | Qualquer autenticado | Lista módulos ativos para o usuário (resolve herança) |
| `rpc_module_check(code)` | Qualquer autenticado | Booleano se módulo está ativo para mim |

## Helpers

| Helper | Uso |
|---|---|
| `is_super_admin()` | Verifica se caller é super_admin global |
| `module_is_active(code, wu_id)` | Resolução de herança · uso geral |
| `module_is_active_for_me(code)` | Versão do usuário logado · super_admin sempre TRUE |

## RLS · Resumo

### `modules` (catálogo)
- **Read** · qualquer autenticado (precisa saber o que existe)
- **Write** · só `super_admin`

### `module_activations`
- **Read** · super_admin vê tudo; demais só do próprio tenant
- **Write** · só `super_admin`

## Ativando para GPC · exemplos

### Liberar Onboarding para todo o GPC

```sql
SELECT rpc_module_activate(
  'onboarding',
  'tenant',
  '<tenant_gpc_uuid>',
  NULL, NULL,
  'Liberacao inicial GPC · Q2 2026'
);
```

### Piloto de PDI só no Cestão Inhambupe

```sql
SELECT rpc_module_activate(
  'pdi',
  'working_unit',
  NULL, NULL,
  '<wu_cestao_inhambupe_uuid>',
  'Piloto PDI · 30 dias'
);
```

### Estender PDI para todas as lojas Cestão (employer_unit Cestão)

```sql
SELECT rpc_module_activate(
  'pdi',
  'employer_unit',
  NULL,
  '<emp_cestao_uuid>',
  NULL,
  'Expansao PDI apos sucesso piloto'
);
```

### Listar o estado do GPC

```sql
SELECT rpc_module_activations_by_tenant('<tenant_gpc_uuid>');
```

### Frontend · ler menu do usuário logado

```typescript
const { items } = await supabase.rpc('rpc_my_active_modules');
// items: [{ code: 'base', display_name: 'Base', is_core: true, is_active: true }, ...]
const sidebarItems = items.filter(m => !m.is_core); // esconder core
```

### Frontend · route guard

```typescript
// app/clima/page.tsx
const { is_active } = await supabase.rpc('rpc_module_check', { p_module_code: 'climate' });
if (!is_active) notFound();  // 404
```

## Testes (20)

| # | Cobertura |
|---|---|
| 1 | Catálogo seed (5 módulos, 1 core) |
| 2 | Constraints de código (`^[a-z][a-z0-9_]+$`) |
| 3 | `scope_match` (exatamente 1 ID) |
| 4 | Helper `is_super_admin` (super=TRUE; outros e anônimo=FALSE) |
| 5 | Activate happy path por super_admin |
| 6 | Idempotência (`already_active=true` na re-ativação) |
| 7 | Sem permissão bloqueia (diretoria, RH, colab) |
| 8 | Validações (módulo inexistente, IDs faltantes/inválidos) |
| 9 | Herança working > employer > tenant (todos os 4 níveis testados) |
| 10 | Módulo core sempre ativo (sem activation row) |
| 11 | `cannot_deactivate_core_module` |
| 12 | Deactivate só remove o nível específico (não cascateia) |
| 13 | `module_is_active_for_me` (usuário logado) |
| 14 | `rpc_my_active_modules` (super_admin vê tudo, demais filtrados) |
| 15 | `rpc_module_check` |
| 16 | `activations_by_tenant` (super_admin qualquer, diretoria só próprio) |
| 17 | CASCADE de tenant deleta ativações |
| 18 | Idempotência do seed (UPSERT) |
| 19 | Edge cases (NULL working_unit_id, módulo inexistente) |
| 20 | UNIQUE por escopo (mesmo módulo permitido em níveis diferentes) |

Resultado: **20/20 verde** · 0 erros.

## Como integrar nos outros schemas

Para que cada módulo respeite a ativação, basta adicionar nas RPCs/RLS um check:

```sql
-- Em rpc_pdi_create_for_user, por exemplo:
IF NOT module_is_active_for_me('pdi') THEN
  RETURN jsonb_build_object('error', 'module_inactive');
END IF;
```

Ou adicionar predicate em policies RLS (dependendo do caso de uso).

## Próximos passos

- Adicionar checks `module_is_active_for_me()` nas RPCs dos módulos existentes (Climate, Recognition, PDI, Onboarding)
- Frontend · página `/admin/modulos` (super_admin only) com matriz tenant×módulo×escopo
- Frontend · navbar dinâmica via `rpc_my_active_modules`
- Frontend · 404 page para módulos desativados

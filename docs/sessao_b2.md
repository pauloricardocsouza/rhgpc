# R2 People · Sessão B2 · Página `/admin/modulos`

Página de administração de módulos com soft-disable, três níveis de granularidade e fluxo de confirmação consciente.

## Conteúdo do pacote

| Arquivo | Tamanho | Descrição |
|---|---|---|
| `r2_people_patch_b2_modules_admin.sql` | ~7 KB | Patch: soft_disabled em `module_activations`, helpers atualizados, novo helper `module_is_readonly_for_me`, policy de write liberada para diretoria |
| `r2_people_rpcs_b2_modules_admin.sql` | ~17 KB | 5 RPCs admin + 1 helper interno |
| `r2_people_b2_tests.sql` | ~17 KB | 35 testes em `BEGIN ... ROLLBACK` |
| `frontend/page.tsx` | ~14 KB | Componente React (Next.js App Router + Supabase + Tailwind + lucide-react) |
| `README_B2.md` | este arquivo | Documentação |

## Decisões de design fechadas

1. **Acesso**: super_admin (R2) + diretoria do tenant
2. **Granularidade**: tenant + employer_unit + working_unit (3 escopos)
3. **Desativação**: soft-disable · dados visíveis em readonly · reativável a qualquer momento
4. **Layout**: card por módulo, toggle expande detalhes
5. **Visão super_admin**: contadores agregados (X tenants, Y unidades)
6. **Confirmação**: aviso + lista de impactos + checkbox "Entendo as consequências"

## Backend

### Mudanças no schema

`module_activations` ganhou 6 colunas:
- `soft_disabled BOOLEAN DEFAULT FALSE`
- `disabled_at TIMESTAMPTZ`
- `disabled_by UUID REFERENCES app_users`
- `disabled_reason TEXT`
- `reactivated_at TIMESTAMPTZ`
- `reactivated_by UUID REFERENCES app_users`

Novo índice `idx_module_activations_active` filtra `WHERE soft_disabled = FALSE` para queries de "ativações vigentes".

### Helpers atualizados

| Helper | Comportamento |
|---|---|
| `module_is_active_for_user(code, user_id)` | Considera apenas activations com `soft_disabled = FALSE` |
| `module_is_active_for_me(code)` | Wrapper para o user logado |
| `module_is_readonly_for_user(code, user_id)` | **Novo** · TRUE quando há activation `soft_disabled` e nenhuma ativa sobrepõe |
| `module_is_readonly_for_me(code)` | **Novo** · wrapper |

Hierarquia de escopo: `tenant > employer_unit > working_unit`. Uma activation ativa em escopo mais específico **sobrepõe** uma soft_disabled em escopo mais amplo.

### RPCs (5)

| RPC | Descrição |
|---|---|
| `rpc_admin_modules_overview()` | Lista todos os módulos com estado por escopo. super_admin recebe `global_view`, diretoria recebe `tenant_view` com employer_units e working_units |
| `rpc_admin_module_activate(code, scope_kind, scope_id)` | Cria nova activation OU reativa uma soft_disabled · idempotente |
| `rpc_admin_module_deactivate(code, scope_kind, scope_id, reason)` | Soft-disable · grava `disabled_reason` · core não pode ser desativado |
| `rpc_admin_module_reactivate(code, scope_kind, scope_id)` | Alias semântico de activate em activation soft_disabled |
| `rpc_admin_module_impact_summary(code, scope_kind, scope_id)` | Preview de dados afetados antes de desativar (counts por módulo: avaliações abertas, ciclos ativos, etc.) |

### Permissões e isolamento

- super_admin: escreve em qualquer escopo
- diretoria: escreve apenas no próprio tenant (validado via `admin_modules_check_scope_access`)
- RH/lider/colaborador: erro `permission_denied`

Policy `module_activations_write_admin` substituiu a antiga `module_activations_write_super_admin`, agora aceitando diretoria do tenant.

## Frontend

Single-file `frontend/page.tsx` para `app/admin/modulos/page.tsx` (Next.js App Router).

### Stack assumida

- Next.js 14+ App Router
- Supabase JS client em `@/lib/supabase`
- Tailwind CSS (utility classes)
- lucide-react para ícones

### Estrutura visual

```
┌─────────────────────────────────────────────────┐
│ Gestão de Módulos                               │
│ Visão global · todos os tenants                 │
├─────────────────────────────────────────────────┤
│ [▶] [icon] Base                          CORE   │
│            Cadastros essenciais                  │
│                                                  │
│ [▼] [icon] 9-Box                                │
│            Avaliação matricial                   │
│  ┌───────────────────────────────────────────┐ │
│  │ TENANT (toda a organização)                │ │
│  │ ✓  Ativação no nível do tenant   [Desativar]│ │
│  │                                              │ │
│  │ EMPLOYER UNITS                              │ │
│  │ ✓  Empresa Matriz (EMP-01)       [Desativar]│ │
│  │ ⚠  Empresa Filial (EMP-02)        [Reativar]│ │
│  │                                              │ │
│  │ WORKING UNITS                               │ │
│  │ ✗  Loja Centro                       [Ativar]│ │
│  └───────────────────────────────────────────┘ │
└─────────────────────────────────────────────────┘
```

### Modal de confirmação

Ao clicar em "Desativar", abre modal com:
- Avisos sobre o efeito de readonly
- Lista de dados afetados (vinda de `rpc_admin_module_impact_summary`)
- Campo de motivo (opcional)
- Checkbox de consentimento (botão fica disabled até marcar)
- Botão "Desativar módulo" em vermelho

### Visões por papel

**super_admin** vê para cada módulo:
- 6 stats agregados (tenants_total, tenants_active, tenants_disabled, employer_units_active, working_units_active, activations_total)
- Sem ações inline (gestão fica via diretoria de cada tenant)

**diretoria** vê para cada módulo:
- 3 blocos de escopo (tenant + employer_units + working_units)
- Botões "Ativar" / "Desativar" / "Reativar" por linha
- Module core (`base`) é mostrado mas botões substituídos por "core · sempre ativo"

### Integração

```bash
# Move o componente para app/admin/modulos/page.tsx
cp frontend/page.tsx app/admin/modulos/page.tsx

# Garante que createClient existe em @/lib/supabase
# Garante shadcn/ui ou Tailwind CSS configurado
```

O componente usa apenas `supabase.auth.getUser()`, `supabase.from('app_users').select(...)` e `supabase.rpc(...)` — sem dependências de UI library específica (apenas Tailwind classes + lucide-react).

## Suite de testes (35)

Roda em `BEGIN ... ROLLBACK` · setup com 2 tenants (X e Y) para validar isolamento.

| Bloco | Testes | Cobertura |
|---|---|---|
| T01-T04 | Permissões do overview | super_admin, diretoria, RH, colaborador |
| T05-T07 | Visão super_admin | role correta, global_view presente, contadores |
| T08-T10 | Visão diretoria | role correta, tenant_view sem global_view, employer/working units |
| T11-T13 | Activate | created=true, idempotente, escopos diferentes |
| T14-T17 | Deactivate | soft_disabled=true, reason gravado, idempotente, core protegido |
| T18-T19 | Reactivate | soft_disabled=false, reactivated_at gravado |
| T20-T22 | Cross-tenant | diretoria X não admin tenant Y, super_admin sim |
| T23-T25 | Helpers | active_for_me=FALSE com soft_disabled, readonly_for_me=TRUE, super_admin nunca readonly |
| T26-T29 | Impact summary | retorna >=4 itens, conta usuários, reflete avaliações abertas, isolamento cross-tenant |
| T30-T31 | Integração A1 | RPCs ninebox bloqueiam quando soft_disabled, readonly_for_me ativo |
| T32-T34 | Edge cases | módulo inexistente, escopo inválido, 3 granularidades funcionam |
| T35 | Auditoria | audit_log registra alterações |

```
PASS: 35
FAIL: 0
```

## Validação pós-aplicação

```sql
-- Tabelas e colunas
SELECT column_name FROM information_schema.columns
WHERE table_name = 'module_activations' AND column_name IN
  ('soft_disabled','disabled_at','disabled_by','disabled_reason','reactivated_at','reactivated_by');
-- 6 linhas

-- RPCs
SELECT proname FROM pg_proc WHERE proname LIKE 'rpc_admin_module%';
-- 5 funcoes

-- Helpers
SELECT proname FROM pg_proc
WHERE proname IN ('module_is_active_for_user','module_is_active_for_me',
                  'module_is_readonly_for_user','module_is_readonly_for_me',
                  'admin_modules_check_scope_access');
-- 5 funcoes

-- Policy atualizada
SELECT policyname FROM pg_policies WHERE tablename = 'module_activations';
-- Inclui module_activations_write_admin (no lugar do antigo write_super_admin)
```

## Ordem de aplicação

```bash
# Aplicar primeiro tudo até A2 (Sessão A2 · 9-Box)
psql -f r2_people_patch_b2_modules_admin.sql        # Sessão B2 · NOVO
psql -f r2_people_rpcs_b2_modules_admin.sql         # Sessão B2 · NOVO
```

## Próximos passos sugeridos

- **B3 Navbar dinâmica** (~0.5 sessão) · usa `module_is_active_for_me` e `module_is_readonly_for_me` para mostrar links com badge "readonly" quando aplicável
- **C4 Adapter Modules** (~0.5 sessão) · cliente TypeScript que envolve as RPCs com tipos
- **Climate** · replicar A1 nas 7 RPCs · precisa pacote E reanexado
- **B1 Frontend Onboarding** (~2 sessões)
- **C1/C2/C3 Adapters** · Recognition, PDI, Onboarding
- **D1 Supabase Auth real** (~2 sessões)

## Convenções mantidas

- Sem em-dashes, sem acentos em comentários SQL
- PT-BR no UI e display_names
- Mensagens de erro em snake_case ASCII
- Idempotente em activate/deactivate/reactivate (já-está-no-estado retorna `ok=true`)
- `BEGIN ... ROLLBACK` em todos os testes
- Soft-disable preserva histórico, audit_log registra mudanças automaticamente

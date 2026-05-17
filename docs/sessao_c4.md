# Sessão C4 · Adapter TypeScript

Cliente TypeScript tipado para todas as RPCs do banco, em `src/lib/r2/`.

## Por que existe

Sem o adapter, cada componente do frontend chama `supabase.rpc('rpc_admin_module_activate', { p_module_code: ..., p_scope_kind: ..., p_scope_id: ... })` direto, e:

- Erros de nome de parâmetro só aparecem em runtime
- Tipos de retorno são `any`
- Lógica de tratamento de erro fica espalhada por todo lugar
- Se uma RPC for renomeada ou seus parâmetros mudarem, é caça-erros no código inteiro

Com o adapter, o consumidor chama `Modules.activate(code, scopeKind, scopeId)` e recebe um objeto tipado. Erros viram `RpcError` capturáveis com `try/catch`. Renomear uma RPC se torna mudança em um arquivo só.

## Estrutura

| Arquivo | Conteúdo |
|---|---|
| `base.ts` | `RpcError`, `callRpc<T>`, `callRpcSafe<T>`, enums (`ModuleScopeKind`, `NineboxCycleStatus`, etc.) |
| `modules.ts` | B2 · `Modules.{getOverview, activate, deactivate, reactivate, getImpactSummary, getCatalog, listMyActive, checkActive}` |
| `navbar.ts` | B3 · `Navbar.get()` |
| `ninebox.ts` | A2 · `Ninebox.{getSettings, updateSettings, createCycle, listCycles, updateCycle, startEvaluation, selfSubmit, managerSubmit, finalize, cancel, getEvaluation, listEvaluations, getTeamMatrix, getHistory}` |
| `recognition.ts` | H2 · `Recognition.{create, getFeed, getStats, react, report, resolveReport}` |
| `pdi.ts` | J · `Pdi.{create, getById, list, listCycles, update, changeStatus, addAction, updateAction, removeAction, addComment}` |
| `onboarding.ts` | K · `Onboarding.{template.*, createBlank, createFromTemplate, list, getById, changeStatus, addStage, addTask, completeTask, uncompleteTask}` |
| `index.ts` | Re-exports + namespace `R2` agregador |

## Padrões

### Sucesso
RPCs retornam o payload tipado direto, sem o wrapper `{ ok: true }` (o `callRpc` desempacota):

```ts
const r = await Modules.getOverview()
// r.role: 'super_admin' | 'diretoria' | 'rh' | 'lider' | 'colaborador'
// r.modules: ModuleSummary[]
```

### Erro
Joga `RpcError` com `code` (snake_case do banco) + `details`:

```ts
try {
  await Modules.deactivate('base', 'tenant', tenantId)
} catch (err) {
  if (err instanceof RpcError) {
    if (err.code === 'cannot_disable_core_module') { /* ... */ }
    if (err.code === 'scope_outside_tenant')        { /* ... */ }
    if (err.code === 'permission_denied')           { /* ... */ }
  }
}
```

### Versão safe (sem throw)
Para pattern matching em vez de try/catch:

```ts
import { callRpcSafe } from '@/lib/r2'

const r = await callRpcSafe('rpc_my_navbar')
if ('error' in r) {
  // r.error = 'not_authenticated' | etc
} else {
  // r.role, r.items
}
```

### Namespace `R2` agregador
Para reduzir imports:

```ts
import { R2 } from '@/lib/r2'

const navbar    = await R2.Navbar.get()
const overview  = await R2.Modules.getOverview()
const cycles    = await R2.Ninebox.listCycles('active')
```

## Validação

```bash
npx tsc --noEmit --strict
# zero erros
```

Cobertura: 57 RPCs do banco, 1084 linhas de TS, strict mode passa.

## Convenções respeitadas

- Sem em-dashes
- Comentários em inglês simples (sem acentos)
- camelCase no TS, snake_case nos parâmetros da RPC (mantém o nome `p_*` do banco)
- Tipos espelham 1:1 os enums e estruturas do schema
- Re-exports planos via `export *` para que `import { X } from '@/lib/r2'` funcione direto

## Próximos refinamentos

- **C1** · expansão de `recognition.ts` com tipos completos de Reaction e Report
- **C2** · expansão de `pdi.ts` com tipos detalhados de Evidence (storage)
- **C3** · expansão de `onboarding.ts` com tipos completos de templates e progresso
- **D1** · ajuste do client Supabase para usar auth real (cookies em vez de stubs)

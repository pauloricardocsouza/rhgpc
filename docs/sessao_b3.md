# R2 People · Sessão B3 · Navbar dinâmica

Sidebar colapsável com itens filtrados pelo papel do usuário e estado dos módulos. Módulos inativos somem do menu, módulos em readonly aparecem com cadeado.

## Conteúdo do pacote

| Arquivo | Tamanho | Descrição |
|---|---|---|
| `r2_people_rpc_b3_navbar.sql` | ~9 KB | RPC `rpc_my_navbar()` + helper `my_navbar_items_by_role` |
| `r2_people_b3_tests.sql` | ~13 KB | 25 testes em `BEGIN ... ROLLBACK` |
| `frontend/useNavbar.ts` | ~3 KB | Hook React com cache em sessionStorage (TTL 5min) |
| `frontend/Sidebar.tsx` | ~6 KB | Sidebar colapsável (240px expandida, 64px colapsada) |
| `frontend/AppShell.tsx` | ~0.6 KB | Wrapper de layout |
| `README_B3.md` | este arquivo | |

## Decisões fechadas

1. **Módulo inativo**: esconde completamente do menu
2. **Módulo readonly (soft_disabled)**: aparece com cadeado ao lado do nome
3. **Itens por papel**: hardcoded no backend (no helper SQL `my_navbar_items_by_role`)
4. **Layout**: sidebar colapsável (ícones quando fechada)
5. **Origem dos dados**: 1 RPC única `rpc_my_navbar()` retorna lista pronta

## Backend

### RPC `rpc_my_navbar()`

Retorna:

```json
{
  "ok": true,
  "role": "diretoria",
  "items": [
    {
      "key": "home",
      "label": "Inicio",
      "icon": "Home",
      "path": "/",
      "section": "main",
      "module_code": null,
      "readonly": false
    },
    {
      "key": "ninebox",
      "label": "9-Box",
      "icon": "Grid3x3",
      "path": "/ninebox",
      "section": "modules",
      "module_code": "ninebox",
      "readonly": true
    }
  ]
}
```

### Catálogo por papel

Implementado em `my_navbar_items_by_role(role TEXT)` (IMMUTABLE, retorna SETOF JSONB):

| Papel | Itens | Sections |
|---|---|---|
| `super_admin` | 13 | main + modules + admin (incluindo /admin/tenants e /admin/auditoria) |
| `diretoria` | 11 | main + modules + admin (admin/modulos + admin/usuarios) |
| `rh` | 9 | main + modules (sem admin) |
| `lider` | 6 | main (com /meu-time) + modules relevantes |
| `colaborador` | 7 | main (com /meu-perfil) + módulos pessoais |

Para adicionar novos itens ou ajustar visibilidade, edite o `CASE WHEN p_role = ... RETURN QUERY VALUES (...)` no helper.

### Lógica de filtragem

Para cada item do catálogo:
1. Se `module_code IS NULL` (item core): aparece sempre
2. Se `module_is_active_for_user(module_code, user) = TRUE`: aparece com `readonly: false`
3. Se `module_is_readonly_for_user(module_code, user) = TRUE`: aparece com `readonly: true`
4. Caso contrário: omitido

`super_admin` sempre passa em ambos os helpers, então vê todos os itens com `readonly: false`.

## Frontend

### `useNavbar()` hook

```typescript
const { loading, error, role, items, refresh } = useNavbar()
```

- Cache em `sessionStorage` (key `r2p:navbar:v1`, TTL 5 min)
- `refresh()` invalida cache e refaz fetch (chame após operações que mudam módulos: ativar/desativar)
- `clearNavbarCache()` exportado para uso após logout

### `<Sidebar />`

Sidebar vertical com:
- Header com logo + botão de toggle (chevron)
- Sections agrupadas (Principal / Módulos / Administração)
- Item ativo destacado via `usePathname()` (Next.js)
- Estado collapsed persistido em `localStorage` (key `r2p:sidebar:collapsed`)
- Footer com badge do papel atual
- Cadeado amber em itens readonly (no estado colapsado, ponto amber abaixo do ícone)

Estados:
- 240px expandida (icone + label)
- 64px colapsada (só icone, tooltip via `title`)

### `<AppShell>`

Wrapper simples: `<Sidebar />` + `<main>` flexbox.

```tsx
// app/(authenticated)/layout.tsx
import { AppShell } from '@/components/AppShell'

export default function Layout({ children }) {
  return <AppShell>{children}</AppShell>
}
```

### Integração

```bash
# Copiar componentes
mkdir -p src/components/navbar
cp frontend/useNavbar.ts src/components/navbar/
cp frontend/Sidebar.tsx src/components/navbar/
cp frontend/AppShell.tsx src/components/navbar/
```

Após integrar B2 (admin/modulos), chame `refresh()` do hook após cada `rpc_admin_module_activate/deactivate` para refletir mudanças imediatamente:

```tsx
const { refresh } = useNavbar()
// apos ativar/desativar:
await refresh()
```

## Suite de testes (25)

| Bloco | Testes | Cobertura |
|---|---|---|
| T01-T06 | Catálogo por papel | Contagens corretas para cada role + papel desconhecido |
| T07-T08 | Auth | Sem login retorna `not_authenticated`, com login retorna `ok` |
| T09-T11 | Sem activations | Apenas itens core, super_admin vê tudo, readonly sempre false p/ super_admin |
| T12-T14 | Activations no tenant | Módulo ativo aparece com readonly=false |
| T15-T18 | soft_disabled | Módulo aparece com readonly=true, super_admin não fica em readonly |
| T19-T20 | Reactivate | readonly volta para false |
| T21-T23 | Diferentes papéis | diretoria/rh/lider veem listas diferentes |
| T24-T25 | Estrutura | sections corretas, todos os campos obrigatórios presentes |

```
PASS: 25
FAIL: 0
```

## Validação pós-aplicação

```sql
-- Função existe
SELECT proname FROM pg_proc WHERE proname IN ('rpc_my_navbar', 'my_navbar_items_by_role');

-- Catálogo por papel (counts)
SELECT 'super_admin' AS role, count(*) FROM my_navbar_items_by_role('super_admin')
UNION ALL SELECT 'diretoria', count(*) FROM my_navbar_items_by_role('diretoria')
UNION ALL SELECT 'rh', count(*) FROM my_navbar_items_by_role('rh')
UNION ALL SELECT 'lider', count(*) FROM my_navbar_items_by_role('lider')
UNION ALL SELECT 'colaborador', count(*) FROM my_navbar_items_by_role('colaborador');
-- 13, 11, 9, 6, 7
```

## Ordem de aplicação

```bash
# Aplicar primeiro tudo até B2
psql -f r2_people_rpc_b3_navbar.sql      # Sessão B3 · NOVO
```

## Próximas frentes do roadmap

- **C4 Adapter Modules** (~0.5 sessão) · cliente TypeScript que envolve as RPCs (incluindo `rpc_my_navbar`) com tipos
- **Climate** · replicar A1 nas 7 RPCs · precisa pacote E reanexado
- **B1 Frontend Onboarding** (~2 sessões)
- **C1/C2/C3 Adapters** · Recognition, PDI, Onboarding
- **D1 Supabase Auth real** (~2 sessões)

## Convenções mantidas

- Sem em-dashes
- Sem acentos em comentários SQL
- PT-BR no UI (labels da navbar)
- Mensagens de erro em snake_case ASCII
- BEGIN/ROLLBACK em testes
- Idempotente (CREATE OR REPLACE)
- Cache TTL 5min em sessionStorage para reduzir round-trips

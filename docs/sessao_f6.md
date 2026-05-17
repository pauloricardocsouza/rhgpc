# Sessão F6 · Drilldown a partir do dashboard

Torna 4 elementos do `/dashboard` clicáveis (caixas 9-Box, KPIs de headcount, barras por unidade/depto, gestores com PDIs atrasados) e adiciona a rota `/dashboard/drill/[kind]/[value]` que mostra a lista de pessoas (ou PDIs) por trás de cada agregado, respeitando o mesmo escopo do dashboard original.

## Decisões fechadas

| Decisão | Escolha | Razão |
|---|---|---|
| Elementos clicáveis | 9-Box + barras + KPIs + tabela PDIs por gestor | Cobertura total dos agregados da F4 |
| Resultados | Rota dedicada `/dashboard/drill/[kind]/[value]` | URL compartilhável e diretamente linkável; volta com browser back |
| Linha da lista | Nome + cargo + unidade + chip de pertinência | Suficiente para identificar; clique abre ficha completa |
| Backend | Nova RPC `rpc_dashboard_drill` reaproveitando lógica de escopo | Lógica de escopo idêntica à F4 sem duplicação |

## O que entrega

| Componente | Arquivo | Linhas |
|---|---|---|
| RPC backend | `supabase/migrations/00333_f6_rpc_dashboard_drill.sql` | 272 |
| Testes | `supabase/tests/00333_f6_dashboard_drill.sql` | 385 |
| Página dinâmica | `src/app/dashboard/drill/[kind]/[value]/page.tsx` | 363 |
| Dashboard atualizado | `src/app/dashboard/page.tsx` | +30 (Links nos 4 elementos) |
| Adapter | `src/lib/r2/employees.ts` | +70 |

### Backend · `rpc_dashboard_drill`

Assinatura:
```sql
rpc_dashboard_drill(
  p_kind          TEXT,
  p_value_text    TEXT DEFAULT NULL,
  p_value_int1    INT  DEFAULT NULL,
  p_value_int2    INT  DEFAULT NULL
)
```

5 kinds suportados:

| Kind | Parâmetros | O que retorna |
|---|---|---|
| `ninebox` | `int1=row`, `int2=col` (1-indexados) | Pessoas cuja última avaliação finalizada caiu naquela caixa |
| `employer_unit` | `value=unit_id` (uuid) | Pessoas ativas naquela unidade |
| `department` | `value=department_id` (uuid) | Pessoas ativas naquele departamento |
| `headcount_metric` | `value=metric` (string) | Pessoas correspondentes à métrica (`total_active`, `hired_30d`, `terminated_30d`, etc) |
| `pdis_by_manager` | `value=manager_id` (uuid) | PDIs ativos com end_date vencida sob aquele gestor |

Escopo aplicado em todas:
- `super_admin` / `diretoria` / `rh` → universe = todo o tenant ativo
- `lider` → CTE recursiva da subárvore (até 10 níveis)
- `colaborador` → `permission_denied`

Tratamento de erro: `unknown_kind`, `invalid_value`, `invalid_uuid`, `invalid_metric`.

Retorno padrão:
```json
{
  "ok": true,
  "scope": "full" | "hierarchy",
  "kind": "ninebox",
  "universe_size": 367,
  "count": 4,
  "items": [...]
}
```

### Frontend · página dinâmica

Convenção de URL (segmentos):
- `/dashboard/drill/ninebox/3-3` (codifica `row-col`)
- `/dashboard/drill/employer_unit/<uuid>`
- `/dashboard/drill/department/<uuid>`
- `/dashboard/drill/headcount_metric/total_active`
- `/dashboard/drill/pdis_by_manager/<uuid>`

A página decodifica o segmento `value` (especialmente o `r-c` do ninebox), invoca a RPC e renderiza:
- Header com ícone, título do filtro e descrição em PT-BR
- Banner amber se `scope=hierarchy`
- Lista de resultados:
  - **PersonRow** para os 4 kinds de pessoa: nome, cargo, unidade, departamento (quando há), chip à direita, link para ficha
  - **PdiRow** para `pdis_by_manager`: nome da pessoa, objetivo, datas, progresso, chip com dias de atraso

Empty state amigável. Tela 403 idêntica à da F4 quando `permission_denied`.

### Dashboard original · Links adicionados

| Componente | Mudança |
|---|---|
| `NineboxGrid` | Cada caixa com `count > 0` envolvida em `<Link href="/dashboard/drill/ninebox/{r}-{c}">` |
| `BigKpi` | Recebe prop `metric`; quando presente e `value > 0`, vira `<Link>` para `/dashboard/drill/headcount_metric/{metric}` |
| `UnitBars` | Recebe prop `drillKind` (`employer_unit` ou `department`); cada linha vira `<Link>` |
| `PdisOverdueByManager` | Cada linha com `manager_id` vira `<Link>` para `/dashboard/drill/pdis_by_manager/{uuid}` |

Cells/rows clicáveis ganham `cursor-pointer hover:opacity-80` / `hover:bg-zinc-50` para indicar interatividade.

## Testes (15/15 PASS)

| Teste | Cobertura |
|---|---|
| T01 | Colaborador comum recebe `permission_denied` |
| T02 | Líder vê `scope=hierarchy` com universo correto |
| T03 | ninebox (3,3) retorna pessoa correta com chip "Future Star" |
| T04 | ninebox (2,2) retorna outra pessoa com "Mantenedor+" |
| T05 | ninebox sem row/col → `invalid_value` |
| T06 | employer_unit filtra só ativos (desligado não conta) |
| T07 | employer_unit retorna `unit_name` corretamente |
| T08 | department retorna `department_name` corretamente |
| T09 | headcount_metric `total_active` agrega corretamente |
| T10 | headcount_metric `hired_30d` filtra recém-contratados |
| T11 | headcount_metric inválido → `invalid_metric` |
| T12 | pdis_by_manager retorna PDIs ordenados pelo mais antigo |
| T13 | Gestor sem PDIs vencidos → `count=0` |
| T14 | kind inválido → `unknown_kind`; UUID inválido → `invalid_uuid` |
| T15 | Isolamento cross-tenant validado em 2 kinds |

## Validação

```bash
# Backend
psql -f supabase/tests/00333_f6_dashboard_drill.sql  # 15/15 PASS

# Regressão completa
30 + 6 + 20 + 16 + 18 + 12 + 14 + 15 = 131/131 PASS

# Frontend
tsc --noEmit --strict  # exit 0
```

## Fluxo prático

1. RH abre `/dashboard`, vê que há 23 pessoas em "Future Star"
2. Clica na caixa → vai pra `/dashboard/drill/ninebox/3-3`
3. Lista mostra 23 nomes com cargo e unidade, ordenados por nome
4. Identifica uma pessoa de interesse, clica → vai pra `/pessoas/<uuid>`
5. Volta no browser, clica em "Por unidade empregadora · ATP Varejo (145)"
6. Vai pra `/dashboard/drill/employer_unit/<uuid>` → lista das 145 pessoas
7. Volta no dashboard, vê que o gestor "João Silva" tem 7 PDIs atrasados (badge vermelho)
8. Clica → `/dashboard/drill/pdis_by_manager/<uuid>` → vê os 7 PDIs ordenados do mais antigo, cada um com chip "62d em atraso" etc

**Líder de loja** acessa o mesmo URL:
- Resultados limitados à sua subárvore (banner amber)
- Pode acabar vendo `count=0` se o filtro escolhido não tem ninguém na hierarquia dele

**Colaborador comum** tenta um drill URL diretamente → tela 403.

## Próximas frentes sugeridas

- **G1** · Tela do colaborador (visão "minha jornada" pessoal)
- **D1** · Supabase Auth real (libera deploy)
- **F7** · Inline edit de Onboarding tasks
- **F8** · Filtros adicionais no drill (busca por nome, paginação se >50)
- **H1** · Exportar resultado do drill para CSV/XLSX

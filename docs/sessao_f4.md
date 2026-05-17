# Sessão F4 · Dashboard tenant-wide (`/dashboard`)

Rota dedicada para RH, diretoria e líderes verem indicadores corporativos: headcount, grade 9-Box agregada, PDIs atrasados por gestor e ranking de reconhecimentos. Líderes veem a mesma estrutura mas com escopo reduzido à sua subárvore.

## Decisões fechadas

| Decisão | Escolha | Razão |
|---|---|---|
| Rota | `/dashboard` top-level | Curta, memorável, separada de `/admin` (que pode crescer com outras coisas) |
| Conteúdo | Headcount + 9-Box + PDIs por gestor + ranking + (unidade/depto) | Sinais corporativos essenciais sem encher de gráfico |
| Acesso | super_admin / diretoria / rh = full; lider = hierarchy; colaborador bloqueado | Líderes precisam visão executiva da sua área sem comprometer privacidade tenant-wide |
| Backend | Nova RPC dedicada `rpc_tenant_dashboard` | Agregação pesada · centralizar em uma RPC reduz round-trips e facilita cache |

## O que entrega

| Componente | Arquivo | Linhas |
|---|---|---|
| RPC backend | `supabase/migrations/00332_f4_rpc_tenant_dashboard.sql` | 245 |
| Testes | `supabase/tests/00332_f4_tenant_dashboard.sql` | 509 |
| Página `/dashboard` | `src/app/dashboard/page.tsx` | 522 |
| Adapter | `src/lib/r2/employees.ts` | +60 |

### Backend · `rpc_tenant_dashboard()`

Determina escopo no início:
- `super_admin / diretoria / rh` → escopo full (todo o tenant ativo)
- `lider` → escopo hierarchy (CTE recursiva até 10 níveis)
- `colaborador` → `permission_denied`

Universo é um array de `app_user_id` que serve de filtro para todos os agregados subsequentes.

**5 listas retornadas:**

1. **`headcount`** com:
   - `total_active`, `total_terminated`
   - `hired_30d`, `hired_90d`, `terminated_30d`, `terminated_90d`
   - `by_employer_unit` · top 10 com `unit_name` e `count`
   - `by_department` · top 10 com `department_name` e `count`

2. **`ninebox_distribution`** · agrupa por `final_box_label`, mas usando **`DISTINCT ON (subject_id)`** + `ORDER BY finalized_at DESC` para pegar somente a última avaliação finalizada de cada pessoa (evita inflar contagem se há múltiplas).

3. **`pdis_overdue_by_manager`** · agrupa por `manager_id_snapshot`, calcula `overdue_count` e `worst_overdue_days`, ordena por contagem descendente, top 10.

4. **`recognition_top_recipients`** · top 10 com `total / public_count / private_count` (90d).

5. **`recognition_top_senders`** · top 10 emissores (90d).

Filtro de reconhecimentos privados respeita o padrão: super_admin / diretoria / rh / sender / recipient veem.

### Frontend · `/dashboard`

**Header:** título + contagem `universe_size` + banner amber quando `scope=hierarchy`.

**Seção Headcount:**
- 4 KPI grandes coloridos (Ativos verde, Contratados 30d azul, Desligados 30d vermelho se >0, Total desligados)
- Cards de distribuição por unidade e departamento com barras horizontais (largura ∝ contagem, mostra também %)

**Grid de 3 cards:**
1. **9-Box** · grade 3x3 colorida (mesmo padrão visual da F3, mas usando `box_row/box_col` 1-indexados retornados pela RPC)
2. **PDIs por gestor** · lista com badge colorido (vermelho ≥5 PDIs, âmbar ≥2) e "pior atraso"
3. **Reconhecimentos** · rankings de recipients e senders, com badge 🔒 indicando privados

Linhas dos rankings clicáveis vão para `/pessoas/[employee_id]`.

### Tela 403

Quando RPC retorna `permission_denied`, mostra tela amigável com link "Voltar para o início".

## Testes (14/14 PASS)

| Teste | Cobertura |
|---|---|
| T01 | super_admin → scope=full, universe completo |
| T02 | diretoria + rh → scope=full |
| T03 | lider → scope=hierarchy com subárvore correta |
| T04 | colaborador → permission_denied |
| T05 | headcount `total_active` / `total_terminated` |
| T06 | headcount temporal `hired_30d` / `terminated_30d` / `terminated_90d` |
| T07 | `by_employer_unit` agrega corretamente |
| T08 | `ninebox_distribution` agrega por caixa |
| T09 | 9-Box usa a última avaliação finalizada por pessoa (substituindo a anterior) |
| T10 | `pdis_overdue_by_manager` agrupa por gestor |
| T11 | `worst_overdue_days` captura o pior caso |
| T12 | RH vê privados com `private_count` |
| T13 | Líder vê só seu escopo nos rankings |
| T14 | Isolamento cross-tenant |

## Validação

```bash
# Backend
psql -f supabase/tests/00332_f4_tenant_dashboard.sql  # 14/14 PASS

# Regressão completa
30 + 6 + 20 + 16 + 18 + 12 + 14 = 116/116 PASS

# Frontend
tsc --noEmit --strict  # exit 0
```

## Fluxo prático

1. RH abre `/dashboard`
2. Vê no topo: 367 ativos, 12 contratados nos últimos 30d, 3 desligados em 30d
3. Distribuição por unidade: ATP Varejo 145, Cestão L1 98, ATP Atacado 76, Cestão Inhambupe 48
4. Grade 9-Box: 23 "Future Star", 78 "Mantenedor+", 12 "Insuficiente"
5. PDIs atrasados: Gerente João Silva tem 7 PDIs atrasados (badge vermelho)
6. Clica em "Carlos Alberto" no ranking de reconhecidos → vai pra ficha dele

**Líder de loja** acessa o mesmo `/dashboard`:
- Banner amber: "Escopo reduzido: você está vendo apenas a sua subárvore"
- Universo de 12 pessoas
- Mesmos cards, mas só dados da sua equipe

**Colaborador comum** tenta `/dashboard`:
- Tela "Acesso restrito" com botão "Voltar para o início"

## Próximas frentes sugeridas

- **F5** · Inline edit das seções de gestão (editar PDI sem sair da ficha)
- **G1** · Tela do colaborador (visão "minha jornada" pessoal)
- **D1** · Supabase Auth real (substitui stubs, deixa repo deployable)
- **F6** · Drilldown a partir do dashboard (clicar em uma caixa 9-Box → lista de pessoas naquela posição)

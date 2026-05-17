# Sessão F3 · Dashboard agregado de `/minha-equipe`

Coloca um painel agregado no topo de `/minha-equipe` mostrando a distribuição da equipe na grade 9-Box, PDIs em atraso e ranking de reconhecimentos dos últimos 90 dias. Cards com link direto para a ficha de cada pessoa.

## Decisões fechadas

| Decisão | Escolha | Razão |
|---|---|---|
| Onde | Topo da própria `/minha-equipe` | Mesmo contexto, sem fragmentar navegação |
| Conteúdo | 9-Box + PDIs atrasados + ranking reconhecimentos | Os 3 sinais que o gestor quer ver primeiro |
| Escopo | Toggle de indiretos compartilhado | Mesmo toggle afeta dashboard E lista; consistência |
| Backend | Híbrido: 9-Box do `rpc_my_team`, resto de RPC nova | 9-Box já tem `last_evaluation_box` no team; PDIs+reconhecimentos exigem joins pesados melhor centralizar |

## O que entrega

| Componente | Arquivo | Linhas |
|---|---|---|
| RPC backend | `supabase/migrations/00331_f3_rpc_team_dashboard.sql` | 164 |
| Testes | `supabase/tests/00331_f3_team_dashboard.sql` | 442 |
| Componente dashboard | `src/components/team/TeamDashboard.tsx` | 394 |
| Adapter | `src/lib/r2/employees.ts` | +50 |
| Integração na página | `src/app/minha-equipe/page.tsx` | +20 |

### Backend · `rpc_my_team_dashboard(include_indirect)`

Resolve a mesma CTE recursiva de `rpc_my_team` (até 10 níveis se incluir indiretos), e agrega 3 listas:

1. **`pdis_overdue`** — PDIs com `status='active'` e `end_date < CURRENT_DATE`. Cada item traz `objective`, `user_name`, `job_title`, `cycle_name`, `end_date`, `days_overdue`, `actions_total/completed`, `progress_pct`. Ordenado pelo mais antigo primeiro.

2. **`recognitions_top_recipients`** — Top 10 pessoas da equipe que mais receberam reconhecimentos nos últimos 90 dias. Inclui `public_count` e `private_count`. Privados filtrados conforme regra padrão (super_admin / diretoria / RH / sender / recipient veem).

3. **`recognitions_top_senders`** — Top 10 pessoas da equipe que mais reconheceram (mesma janela de 90 dias).

`team_size` retorna a quantidade de subordinados considerados.

Casos cobertos:
- Sem subordinados → arrays vazios com `ok=true`
- `not_authenticated` se usuário não existe
- Subordinados indiretos só entram quando `p_include_indirect=true`

### Frontend · `TeamDashboard`

3 cards lado a lado em desktop, empilhados em mobile:

1. **Distribuição 9-Box** — grade 3x3 colorida (verde / âmbar / vermelho conforme posição GE-McKinsey). Conta `last_evaluation_box` de cada membro do `team` retornado pelo `myTeam()`. Mostra `X / Y avaliadas`. Empty state quando ninguém tem avaliação.

2. **PDIs em atraso** — lista compacta, max 10 visíveis, scroll para mais. Cada linha tem:
   - Nome da pessoa
   - Chip colorido com dias vencidos (vermelho >30d, âmbar >7d, neutro o resto)
   - Objetivo truncado
   - Barra de progresso de ações
   - Card inteiro é link para `/pessoas/[employee_id]`

3. **Ranking de reconhecimentos** — 2 sub-seções:
   - **Mais reconhecidos**: top 5 com badge 🔒 quando há privados (só RH/admin vê)
   - **Mais reconheceram**: top 5 senders
   - Cada linha clicável para a ficha

Tipos novos no adapter: `PdiOverdueItem`, `RecognitionRanking`, `MyTeamDashboardResult`. Função `myTeamDashboard(includeIndirect)` exportada como `R2.myTeamDashboard`.

## Testes (12/12 PASS)

| Teste | Cobertura |
|---|---|
| T01 | Usuário sem subordinados → arrays vazios |
| T02 | Payload completo · `team_size` correto |
| T03 | `pdis_overdue` só inclui ativos com end vencida |
| T04 | Ordenação · mais antigo primeiro |
| T05 | `days_overdue` e `progress_pct` corretos |
| T06 | Gerente vê só públicos (privado filtrado) |
| T07 | Top senders agrega corretamente |
| T08 | RH vê privados (com `private_count`) |
| T09 | `include_indirect=true` engloba subárvore |
| T10 | Isolamento entre gestores diferentes |
| T11 | Reconhecimentos >90d filtrados da janela |
| T12 | `not_authenticated` quando usuário inexistente |

## Validação

```bash
# Backend
psql -f supabase/tests/00331_f3_team_dashboard.sql  # 12/12 PASS

# Regressão completa
30 + 6 + 20 + 16 + 18 + 12 = 102/102 PASS

# Frontend
tsc --noEmit --strict  # exit 0
```

## Fluxo prático

1. Gestor abre `/minha-equipe`
2. Vê no topo:
   - Grade 9-Box: 2 pessoas em "Future Star", 3 em "Mantenedor+", 1 em "Insuficiente"
   - PDIs em atraso: 4 itens, o mais antigo com 60 dias de atraso (badge vermelho)
   - Reconhecimentos: SUB1 lidera com 12, GERENTE_X enviou 8 nos últimos 90 dias
3. Clica em "SUB1" no ranking → vai direto pra ficha dele (mesma rota /pessoas/[id], onde já vê as 4 seções da F1)
4. Liga o toggle "incluir indiretos" → dashboard recalcula e a grade ganha mais 6 pessoas

## Próximas frentes

- **F2** · Ações do gestor (botões "Criar PDI", "Reconhecer", "Iniciar 9-Box ad-hoc") direto da ficha
- **F4** · Dashboard tenant-wide para RH/diretoria (toda a empresa, não só "minha equipe")
- **D1** · Supabase Auth real

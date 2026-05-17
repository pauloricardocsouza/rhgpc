# Sessão F1 · Gestão por pessoa + Minha equipe

Conecta os módulos já prontos (9-Box, PDI, reconhecimentos, onboarding) à ficha de empregado, dando ao gestor uma visão consolidada por pessoa e uma lista de quem reporta a ele.

## Decisões fechadas

| Decisão | Escolha | Razão |
|---|---|---|
| Onde | Estender `/pessoas/[id]` com seções colapsáveis | Reusa contexto já carregado, sem fragmentar navegação |
| Conteúdo | 4 seções: 9-Box, PDIs, reconhecimentos, onboarding | Histórico de gestão completo numa só tela |
| Permissão | super_admin + diretoria + RH + gestor direto | Filtra no backend (RPC), e UI esconde silenciosamente para os demais |
| Lista de equipe | `/minha-equipe` dedicada | Entrypoint claro para o gestor ver seus liderados |

## O que entrega

| Componente | Arquivo | Linhas |
|---|---|---|
| RPCs backend | `supabase/migrations/00330_f1_rpcs_gestao.sql` | 306 |
| Testes | `supabase/tests/00330_f1_gestao.sql` | 490 |
| Componente de seções | `src/components/employees/GestaoSections.tsx` | 421 |
| Rota `/minha-equipe` | `src/app/minha-equipe/page.tsx` | 254 |
| Adapter (`gestaoSummary`, `myTeam`) | `src/lib/r2/employees.ts` | +90 |

### Backend

**Helper de permissão:**
- `can_view_gestao_for_app_user(target_app_user_id)` · retorna TRUE se o usuário logado é super_admin, diretoria, RH ou gestor direto (`manager_id`) do alvo. Stable, SECURITY DEFINER.

**`rpc_employees_gestao_summary(employee_id)`:**
- Resolve a ficha → procura `app_users.employee_id` (link da E1) → valida permissão → agrega 4 listas:
  - **evaluations**: 9-Box finalizadas/em andamento (do `ninebox_evaluations` por `subject_id`) com cycle, box, score, avaliador
  - **pdis**: PDIs por `user_id`, com ciclo, objetivo, progresso de ações
  - **recognitions**: reconhecimentos recebidos · privados só visíveis para super_admin / diretoria / RH / sender / recipient
  - **onboardings**: onboardings por `user_id` (exclui canceled)
- Caso `has_app_user=false`: retorna estrutura vazia mas com `ok=true` (UI mostra banner amarelo "ficha sem usuário vinculado")
- Erros: `not_authenticated`, `permission_denied`, `employee_not_found`

**`rpc_my_team(include_indirect)`:**
- CTE recursiva limitada a 10 níveis para evitar loops
- Retorna `[{ id, employee_id, full_name (do employees), app_user_name, email, role, job_title, employer_unit_name, working_unit_name, depth, is_direct_report, is_active, pdis_active, last_evaluation_box, recognitions_30d, onboarding_active }]`
- KPIs calculados inline (subqueries pequenas, indexáveis)
- `include_indirect=true` retorna a subárvore inteira

### Frontend

**`GestaoSections`** (consumido por `/pessoas/[id]`):
- 4 cards colapsáveis (abertos por padrão)
- Cada um mostra empty state apropriado se vazio
- **Recognitions**: badge "Privado" + contador de reações
- **PDIs**: barra de progresso de ações
- **Onboardings**: barra de progresso de tarefas + badge de obrigatórias
- **Evaluations**: tabela com ciclo, caixa, status, avaliador, data
- Se backend retorna `permission_denied`: componente esconde-se completamente (setHidden(true)) · usuário comum nem vê que essas seções existem
- Se `has_app_user=false`: banner amarelo explicando

**`/minha-equipe`:**
- Grid de cards (1/2/3 colunas conforme breakpoint)
- Avatar colorido determinístico pelo nome
- Toggle "Incluir subordinados indiretos" (chama com `include_indirect=true`)
- Cada card mostra 4 KPIs com ícone (PDIs ativos, última caixa, reconhecimentos 30d, onboarding em curso)
- Click navega para `/pessoas/[employee_id]` (que já mostra as seções de gestão)
- Empty state amigável

## Testes (18/18 PASS)

| Teste | Cobertura |
|---|---|
| T01 | Helper · gerente direto pode ver |
| T02 | Helper · gerente NÃO vê neto (subordinado indireto) |
| T03 | Colaborador comum → `permission_denied` |
| T04 | RH vê qualquer ficha do tenant |
| T05 | Diretoria vê |
| T06 | Super_admin vê |
| T07 | Gestor direto vê seu subordinado |
| T08 | Payload tem `evaluations`/`pdis`/`recognitions`/`onboardings` |
| T09 | Avaliação 9-Box com `final_box_label` |
| T10 | PDI ativo aparece |
| T11 | Gerente vê só reconhecimentos públicos (1) |
| T12 | RH vê públicos + privados (2) |
| T13 | Ficha sem app_user → `has_app_user=false` |
| T14 | Cross-tenant → `employee_not_found` |
| T15 | `my_team` retorna 2 diretos |
| T16 | `my_team(include_indirect=true)` traz 3 (com NETO em depth=2) |
| T17 | KPIs enriquecidos (`pdis_active=1`, `last_box=Mantenedor`) |
| T18 | Usuário sem subordinados → array vazio (não erro) |

## Validação

```bash
# Backend
psql -f supabase/tests/00330_f1_gestao.sql  # 18/18 PASS

# Regressão completa
30 (E1) + 6 (E2) + 20 (E4) + 16 (E5) + 18 (F1) = 90/90 PASS

# Frontend
tsc --noEmit --strict
# exit 0 · zero erros
```

## Fluxo prático

1. **Gestor de loja** clica em "Minha equipe" no menu
2. Vê 12 cards de pessoas que reportam a ele · 3 com PDIs ativos, 1 com reconhecimento recente, 1 ainda em onboarding
3. Clica num card → abre a ficha completa de "JOÃO DA SILVA"
4. Rola até as seções "Histórico de avaliações 9-Box" / "PDIs" / "Reconhecimentos" / "Onboardings"
5. Vê que João foi avaliado como "Mantenedor" no último ciclo, tem 1 PDI ativo sobre comunicação, recebeu 2 reconhecimentos no mês

**Colaborador comum** vendo a ficha de outro colega: as 4 seções de gestão simplesmente não aparecem · só vê a parte cadastral.

## Próximos passos

- **F2** · Ações do gestor a partir de `/pessoas/[id]` (botões "Criar PDI", "Reconhecer", "Iniciar avaliação 9-Box ad-hoc")
- **F3** · Dashboard agregado em `/minha-equipe`: distribuição na grade 9-Box, PDIs em atraso, etc
- **D1** · Supabase Auth real (libera deploy)

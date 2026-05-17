# Sessão G1 · Minha Jornada (`/minha-jornada`)

Primeira tela voltada ao **colaborador**. Mostra um snapshot pessoal: identidade básica, KPIs de PDIs/reconhecimentos/9-Box, dados pessoais (read-only), meus PDIs com gestão limitada de ações, reconhecimentos recebidos e enviados, e onboardings em curso.

## Decisões fechadas

| Decisão | Escolha | Razão |
|---|---|---|
| Rota | `/minha-jornada` | PT-BR, alinhado com a comunicação do produto |
| Conteúdo | Tudo + dados pessoais (sem editar) | Visão completa do colaborador sobre si mesmo |
| Edição própria | Marcar ações de PDI como concluídas | Backend já permite (`v_owner = v_caller`); RH/gestor mantém demais |
| Backend | Combinar: `rpc_my_journey` para KPIs + reuso de RPCs existentes | RPC nova só para o que era pesado; listas vêm de `gestaoSummary` (com patch para self-access) |

## O que entrega

| Componente | Arquivo | Linhas |
|---|---|---|
| RPC nova + patch F1 | `supabase/migrations/00340_g1_rpc_my_journey.sql` | 214 |
| Testes | `supabase/tests/00340_g1_my_journey.sql` | 406 |
| Página | `src/app/minha-jornada/page.tsx` | 534 |
| Card PDI modo dono | `src/components/employees/PdiCardEditable.tsx` | +20 (prop `viewerIsOwner`) |
| Adapter | `src/lib/r2/employees.ts` | +95 (tipos + `myJourney`) |

### Backend

**Patch F1 · `can_view_gestao_for_app_user`**

A função original (sessão F1) tinha 3 regras (super_admin, RH/diretoria, manager direto) mas faltava o caso **`me.id = target.id`** (o próprio dono). Adicionado:

```sql
me.id = target.id   -- G1: permite que o proprio veja seus dados
```

Isso permite reusar `rpc_employees_gestao_summary` na tela `/minha-jornada` sem criar uma RPC paralela só para o caso self.

**RPC nova · `rpc_my_journey()`**

Retorna 5 blocos:
- `identity` — app_user_id, employee_id, email, full_name, role, job_title, employment_link, hire_date, birth_date, employer_unit, working_unit, department, manager
- `pdi_kpis` — active, completed, draft, canceled, overdue, actions_total, actions_completed
- `recog_kpis` — received_total, received_90d, sent_total, sent_90d
- `last_ninebox` — última avaliação finalizada (ignora canceladas e pendentes)
- `onboarding_kpis` — active, completed, tasks_total, tasks_completed (com `EXCEPTION WHEN undefined_table` para tolerar absence de tabela)

Sem permissões especiais — qualquer usuário autenticado vê os próprios dados. Isolamento de tenant garantido pelo filtro `tenant_id`.

### Frontend

**Header pessoal** com avatar de iniciais, nome, cargo, unidade, departamento, gestor. Banner amber se não há `employee_id` vinculado.

**KPIs** em 4 cards: PDIs ativos (verde se em dia / amber se há overdue), ações concluídas/totais, reconhecimentos em 90d, última caixa 9-Box (com cor da grade GE-McKinsey).

**Dados pessoais** read-only: email, admissão, nascimento, vínculo, unidade de trabalho, função.

**Meus PDIs** usa `PdiCardEditable` com a **prop nova `viewerIsOwner`**:
- Esconde botão "editar" (lápis)
- Esconde chips de mudança de status
- Esconde botão "+ Adicionar ação"
- Esconde lixeira de remover ação
- **Mantém** o toggle circular para marcar a própria ação como concluída ↔ em andamento
- Mostra nota explicativa: "Edições no objetivo, datas ou status do PDI ficam com seu gestor ou com o RH"

**Reconhecimentos recebidos** lista os reconhecimentos com o nome do remetente, data e badge 🔒 se privado.

**Reconhecimentos que eu enviei** mostra apenas contagens (total + 90d). Feed detalhado precisaria de outra RPC (`rpc_recognition_get_feed` filtrada por `sender_id`), fica para próxima sessão.

**Onboardings** com nome, status e barra de progresso.

## Permissões e edição própria

Backend já permitia o dono marcar próprias ações (verificado em `rpc_pdi_action_update`):

```sql
IF NOT (
  v_owner = v_caller          -- dono
  OR user_is_manager_of(v_owner)
  OR user_has_permission('manage_all_pdi')
) THEN
  RETURN 'permission_denied';
END IF;
```

A página G1 só **exibe** controles para gestor/RH — para o dono, mostra apenas o toggle de ação. Mas se o dono *tentasse* editar objetivo (via DevTools/API), o backend bloquearia com `permission_denied` mesmo assim.

## Testes (14/14 PASS)

| Teste | Cobertura |
|---|---|
| T01 | `not_authenticated` quando usuário não existe |
| T02 | Estrutura completa retornada |
| T03 | Identity inclui nome/cargo/unidade/depto/gestor |
| T04 | `pdi_kpis` contagem por status |
| T05 | `overdue` conta só `active` com end_date passada |
| T06 | `actions_total` e `actions_completed` somam |
| T07 | `recog_kpis` separa received vs sent |
| T08 | Janela 90d filtra corretamente |
| T09 | `last_ninebox` retorna a mais recente |
| T10 | Canceladas e não-finalizadas ignoradas |
| T11 | `onboarding_kpis` tem estrutura mesmo sem assignments |
| T12 | Isolamento cross-tenant |
| T13 | Patch F1 · self-access permitido em `can_view_gestao_for_app_user` |
| T14 | Patch não vaza acesso a terceiros |

## Validação

```bash
# Backend
psql -f supabase/tests/00340_g1_my_journey.sql        # 14/14 PASS
psql -f supabase/tests/00330_f1_gestao.sql            # 18/18 PASS (sem regressão pelo patch)

# Regressão completa
30 + 6 + 20 + 16 + 18 + 12 + 14 + 15 + 14 = 145/145 PASS

# Frontend
tsc --noEmit --strict  # exit 0
```

## Fluxo prático

1. Colaborador "JOÃO DA SILVA" faz login, vai pra `/minha-jornada`
2. Vê header com seu nome, "Analista Operacional · ATP Salvador · Operações · Gestor: Carlos Pinto"
3. KPIs mostram: 1 PDI ativo (em dia, verde), 3/5 ações, 2 reconhecimentos em 90d, última 9-Box "Mantenedor+" (amber)
4. Rola para "Meus PDIs", expande o card → vê as 5 ações
5. Marca a ação "Curso de Excel avançado" como concluída → barra de progresso vira 4/5 imediatamente
6. Não vê botão de editar o objetivo do PDI (correto: isso é do gestor)
7. Rola até "Reconhecimentos recebidos" → vê 2 cartões, um com badge privado
8. Vê em "Onboardings": "Integração ATP · in_progress · 8/12 tarefas"

**Usuário sem ficha vinculada** (`employee_id = NULL`):
- Header mostra banner amber pedindo ao RH para concluir cadastro
- KPIs aparecem com base no `app_user` (PDIs, reconhecimentos, 9-Box ainda funcionam)
- Seções "Meus PDIs", "Reconhecimentos recebidos", "Onboardings" mostram empty state pedindo vinculação

## Próximas frentes sugeridas

- **G2** · Feed detalhado de reconhecimentos enviados (nova RPC `rpc_my_sent_recognitions`)
- **G3** · Self-edit limitado de dados pessoais (email pessoal, telefone, endereço)
- **D1** · Supabase Auth real (libera deploy)
- **F7** · Inline edit de Onboarding tasks
- **H1** · Notificações push quando alguém reconhece o usuário

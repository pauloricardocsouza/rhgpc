# R2 People · Sessão K · Schema Onboarding

Módulo de **Onboarding** (jornada de admissão) para a plataforma R2 People.

## Resumo

Quinto módulo de schema da plataforma. Cobre:

- Templates reutilizáveis de jornada (opcionais, com fallback para criação manual)
- Onboarding individual instanciado a partir de template (deep copy) ou em branco
- Stages que agrupam tasks (Documentação, Treinamentos, Integração Cultural, etc.)
- Workflow de status (`not_started → in_progress → completed/canceled`)
- Auto-início no primeiro `task_complete`
- Bloqueio de conclusão se houver tasks `is_required` pendentes
- Denormalização de progresso (`tasks_total/completed/required/required_done`)

## Decisões da Sessão K

1. **Templates opcionais** · pode criar onboarding com template OU em branco
2. **Só pós-admissão** · não cobre fase pré-admissional
3. **Stages com tasks** · checklists agrupadas por etapa
4. **RH controla tudo** · sem padrinho/responsabilidades distribuídas
5. **Sem upload de documentos** · só checklist (kind `documentation` é só registro de entrega)

## Pré-requisitos

- `r2_people_schema_base_v1.sql` (Sessão H) aplicado
- `r2_people_seed_base_v1.sql` aplicado

## Arquivos

| Arquivo | Conteúdo |
|---|---|
| `r2_people_schema_onboarding_v1.sql` | 4 enums, 6 tabelas, 15 RPCs, 4 helpers, 15 policies, 18 triggers, 19 indexes |
| `r2_people_seed_onboarding_v1.sql` | 2 permissões + 5 atribuições por role + template exemplo "Operador de Loja" |
| `r2_people_rls_policies_onboarding_tests.sql` | 22 testes (constraints, triggers, RPCs, RLS, workflow, deep copy) |

## Ordem de aplicação

```bash
psql -f r2_people_schema_onboarding_v1.sql
psql -f r2_people_seed_onboarding_v1.sql
psql -f r2_people_rls_policies_onboarding_tests.sql   # opcional · validação
```

## Tabelas

### Templates (reutilizáveis)

| Tabela | Conteúdo |
|---|---|
| `onb_templates` | Template raiz · `code` único por tenant, `status` (draft/published/archived), `suggested_duration_days` |
| `onb_template_stages` | Etapas do template · `display_order`, `offset_days_start`, `duration_days` |
| `onb_template_tasks` | Tasks da etapa · `kind`, `offset_days` (relativo à stage), `is_required` |

### Onboarding (instância)

| Tabela | Conteúdo |
|---|---|
| `onboardings` | Onboarding individual · `user_id`, `manager_id_snapshot`, `source_template_id` (NULL = manual), `status`, datas, contadores denormalizados |
| `onboarding_stages` | Etapas da instância · `start_date`/`target_end_date` calculadas no deep copy |
| `onboarding_tasks` | Tasks executáveis · `status`, `due_date`, `completed_at/by`, `completion_note` |

## Constraints chave

- **`uq_onboardings_one_active_per_user`** · UNIQUE parcial em `(tenant_id, user_id)` WHERE status IN ('not_started', 'in_progress'). Garante apenas 1 onboarding ativo por user.
- `onb_templates.suggested_duration_days BETWEEN 1 AND 365`
- `onboardings.target_end_date >= start_date`
- `display_name` mínimo 3 chars em template e onboarding · 2 chars em stage

## Enums

- `onboarding_status` · `not_started`, `in_progress`, `completed`, `canceled`
- `onboarding_task_status` · `pending`, `in_progress`, `completed`, `skipped`
- `onboarding_task_kind` · `documentation`, `training`, `meeting`, `system_access`, `cultural`, `compliance`, `task`
- `onboarding_template_status` · `draft`, `published`, `archived`

## RPCs · Templates

| RPC | Quem pode | O que faz |
|---|---|---|
| `rpc_onb_template_create(code, name, desc, duration)` | RH/Diretoria | Cria template (draft) |
| `rpc_onb_template_update(id, name, desc, duration, status)` | RH/Diretoria | Atualiza · publica/arquiva |
| `rpc_onb_template_stage_add(template, name, desc, offset, duration)` | RH/Diretoria | Adiciona stage |
| `rpc_onb_template_task_add(stage, title, desc, kind, offset, required)` | RH/Diretoria | Adiciona task |
| `rpc_onb_template_list()` | Líder/RH/Dir | Lista templates do tenant |
| `rpc_onb_template_get(id)` | Líder/RH/Dir | Retorna template + stages + tasks |

## RPCs · Onboarding

| RPC | Quem pode | O que faz |
|---|---|---|
| `rpc_onboarding_create_from_template(user, template, name, start_date, notes)` | RH/Diretoria | Cria com **deep copy** de stages e tasks (datas calculadas via offsets) |
| `rpc_onboarding_create_blank(user, name, start, end, notes)` | RH/Diretoria | Cria onboarding em branco para preenchimento manual |
| `rpc_onboarding_stage_add(onboarding, name, desc, start, end)` | RH/Diretoria | Adiciona stage manual |
| `rpc_onboarding_task_add(stage, title, desc, kind, due, required)` | RH/Diretoria | Adiciona task manual |
| `rpc_onboarding_task_complete(task_id, note)` | **Owner** OR RH/Diretoria | Conclui task · auto-inicia onboarding |
| `rpc_onboarding_task_uncomplete(task_id)` | **Owner** OR RH/Diretoria | Reverte conclusão |
| `rpc_onboarding_change_status(id, new_status, cancel_reason)` | RH/Diretoria | Move status · valida transições e required pendentes |
| `rpc_onboarding_list(scope, status)` | scope `own` (todos) · `team` (líder+) · `all` (view/manage perms) | Lista enriquecida |
| `rpc_onboarding_get_by_id(id)` | Owner/Manager/RH/Dir | Retorna onboarding + stages + tasks |

## Permissões

| Code | Role default |
|---|---|
| `view_onboarding` | lider, rh, diretoria |
| `manage_onboarding` | rh, diretoria |

`colaborador` não precisa de permissão · acessa o próprio onboarding via RLS owner.

## RLS · Resumo

### Templates (toda a família)
- **Read** · `view_onboarding` OR `manage_onboarding`
- **Write** · `manage_onboarding`

### Onboardings
- **Read** · owner OR manager (direto/indireto) OR `view_onboarding`/`manage_onboarding`
- **Write** · `manage_onboarding`

### Tasks
- **Read** · herda de `onboarding_can_read()` (owner/manager/perm)
- **Write** · `manage_onboarding` OU owner do onboarding ativo (para auto-conclusão)

## Workflow de status

```
        ┌─────────────┐
        │ not_started │
        └──────┬──────┘
               │ task_complete (auto) OR change_status manual
               ▼
        ┌─────────────┐
        │ in_progress │
        └──────┬──────┘
               │ change_status (precisa todas required done)
               ▼
        ┌─────────────┐
        │  completed  │
        └─────────────┘

(qualquer ativo) → canceled (com cancel_reason ≥ 3 chars)
(completed/canceled) → LOCKED (sem mudanças)
```

## Triggers

| Trigger | Função |
|---|---|
| `trg_*_updated_at` | Mantém `updated_at` em todas as tabelas |
| `trg_audit_onb_templates`, `trg_audit_onboardings` | Audit em decisões formais |
| `trg_onb_task_counts` | Denormaliza `tasks_total/completed/required/required_done` em `onboardings` |
| `trg_onb_task_completion` | Seta `completed_at` + `completed_by` automaticamente em tasks |
| `trg_onb_status_timestamps` | Seta `started_at`, `completed_at`, `canceled_at` em onboardings |

## Deep copy · `create_from_template`

Quando um onboarding é criado a partir de template:

1. Cria registro em `onboardings` com `source_template_id` preenchido e `target_end_date = start_date + suggested_duration_days`
2. Para cada stage do template:
   - Calcula `start_date = onboarding.start_date + stage.offset_days_start`
   - Calcula `target_end_date = stage_start + stage.duration_days`
   - Cria registro em `onboarding_stages`
3. Para cada task da stage:
   - Calcula `due_date = stage_start + task.offset_days`
   - Cria registro em `onboarding_tasks`
4. Trigger de counts dispara automaticamente e popula contadores no onboarding

Templates podem ser editados/arquivados depois sem afetar onboardings já instanciados.

## Template exemplo · "Operador de Loja" (GPC)

Aplicado pelo seed se houver tenant + usuário RH/Dir disponível. Estrutura:

| Stage | Tasks | Required |
|---|---|---|
| Documentação (dias 1-3) | 5 tasks (RG/CTPS, contrato, código de conduta, biometria, crachá/uniforme) | 5/5 |
| Treinamentos (dias 3-15) | 6 tasks (NR-5/12, segurança alimentar, PDV/Winthor, atendimento, prevenção de perdas, shadowing) | 5/6 |
| Integração Cultural (dias 1-30) | 5 tasks (boas-vindas RH, reunião gestor, tour, almoço, feedback 30 dias) | 4/5 |
| **Total** | **16 tasks** | **14/16 required** |

Duração sugerida: **30 dias**.

## Testes (22)

| # | Cobertura |
|---|---|
| 1 | Constraints básicas (nome curto, duração inválida, datas invertidas) |
| 2 | UNIQUE parcial · 1 onboarding ativo por user · cancel libera |
| 3 | Trigger de denormalização (total/completed/required/required_done) |
| 4 | `completed_at` + `completed_by` automáticos em tasks |
| 5 | Timestamps de status em onboardings |
| 6 | RPC `template_create` happy path + dedupe |
| 7 | RPC `template_create` sem permissão (lider e colaborador bloqueados) |
| 8 | `template_stage_add` + `template_task_add` |
| 9 | `create_from_template` faz deep copy + denormaliza |
| 10 | Template archived bloqueia instanciação |
| 11 | `create_blank` sem template (`source_template_id IS NULL`) |
| 12 | Cross-tenant bloqueado |
| 13 | `task_complete` por owner + auto-início |
| 14 | Peer (colega) bloqueado de concluir task de outro |
| 15 | `change_status` valida transições (not_started→completed inválido) |
| 16 | Required pendentes bloqueiam conclusão |
| 17 | `cancel` exige razão (≥ 3 chars) |
| 18 | Helper `onboarding_can_read` (owner/manager/RH/Dir) |
| 19 | `list` por escopo respeita permissões (own/team/all) |
| 20 | `get_by_id` enriquece com stages + tasks |
| 21 | CASCADE de tenant deleta tudo |
| 22 | Idempotência do seed |

Resultado: **22/22 verde** · 0 erros.

## Próximos passos

- Adapter Supabase no app Next.js (substituir mocks de PDI/Recognition/Onboarding)
- Frontend Onboarding (lista de templates, criar onboarding, checklist do colaborador, dashboard RH)
- Schema 9-Box (avaliação de potencial × performance)

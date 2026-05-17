# R2 People · Sessão A2 · Módulo 9-Box

Módulo de avaliação matricial **Potencial × Performance** com ciclos formais, snapshot histórico imutável e visibilidade controlada por papel/hierarquia.

## Conteúdo do pacote

| Arquivo | Tamanho | Descrição |
|---|---|---|
| `r2_people_schema_ninebox_v1.sql` | ~58 KB | Schema completo: 6 enums, 5 tabelas, 9 helpers, 14 RPCs, 10 RLS policies |
| `r2_people_seed_ninebox_v1.sql` | ~6 KB | Catálogo do módulo, 8 permissões, matriz role × permission, defaults 3x3 GE-McKinsey PT-BR, trigger de seed na ativação |
| `r2_people_ninebox_tests.sql` | ~25 KB | 40 testes em `BEGIN ... ROLLBACK` cobrindo lifecycle completo, visibilidade, justificativas, snapshots e gate A1 |
| `00_local_setup.sql` | (já entregue na A1) | Setup Postgres dev local · `auth.uid()` stub, roles `anon`/`authenticated`, helpers `test_login`/`test_logout` |
| `README_A2.md` | este arquivo | Documentação |

## Decisões de design fechadas

1. **Grid configurável** por tenant: 3x3 ou 5x5
2. **Critérios livres** por eixo: 1 a 5 itens com `name` + `weight`, soma deve dar 100
3. **Auto-avaliação + gestor**: gestor decide o score final (auto é só input para reflexão)
4. **Ciclos formais + ad-hoc**: `cycle_id` opcional · ad-hoc tem `is_adhoc=TRUE` e `cycle_id=NULL`
5. **Justificativa obrigatória só em caixas extremas** (cantos), toggle por tenant (`force_justification_extremes`)
6. **`min_justification_length`** default 50 chars, configurável por tenant
7. **`require_self_assessment`** toggle por tenant (default FALSE) · diretoria pode bypassar
8. **Snapshot imutável** ao finalizar · re-finalize gera versão incrementada (auditoria)
9. **Default ao ativar**: 3x3, 3 critérios em cada eixo, rótulos GE-McKinsey em PT-BR
10. **Visibilidade**: avaliado vê só a sua, gestor (direto/indireto) vê o time, RH/diretoria veem tudo, super_admin tudo
11. **Roles** seguem o enum `app_user_role` oficial: `colaborador`, `lider`, `rh`, `diretoria` (+ `super_admin` via Sessão L)

## Tabelas (5)

| Tabela | Conteúdo |
|---|---|
| `ninebox_settings` | 1 linha por tenant · grid_size, critérios, rótulos, políticas |
| `ninebox_cycles` | janelas formais de avaliação (planning/active/closed) |
| `ninebox_evaluations` | uma avaliação de um subject · contém snapshot da config no momento de criação (imutável) |
| `ninebox_evaluation_scores` | linha por (evaluation × axis × criterion × evaluator_kind) |
| `ninebox_evaluation_snapshots` | cópia imutável do payload completo ao finalizar · versionado |

## RPCs (14)

| RPC | Quem chama | Função |
|---|---|---|
| `rpc_ninebox_settings_get` | Qualquer user logado | Retorna config do tenant |
| `rpc_ninebox_settings_update` | RH/diretoria/super_admin | Atualiza config (validações de pesos e critérios) |
| `rpc_ninebox_cycle_create` | RH/diretoria/super_admin | Cria ciclo |
| `rpc_ninebox_cycle_update` | RH/diretoria/super_admin | Atualiza ciclo (closed só por dir/SA) |
| `rpc_ninebox_cycle_list` | Qualquer user logado | Lista ciclos do tenant |
| `rpc_ninebox_evaluation_start` | Manager direto, RH/dir/SA | Inicia avaliação · tira snapshot da config |
| `rpc_ninebox_evaluation_self_submit` | Subject | Auto-avaliação (input para gestor) |
| `rpc_ninebox_evaluation_manager_submit` | Manager, RH/dir/SA | Avaliação final · calcula box, valida justificativa |
| `rpc_ninebox_evaluation_finalize` | Manager, RH/dir/SA | Gera snapshot v1+ · status → finalized |
| `rpc_ninebox_evaluation_cancel` | Manager, RH/dir/SA | Cancela (não permitido em finalized) |
| `rpc_ninebox_evaluation_get` | Quem pode ver (helper) | Detalhe · subject não vê manager_scores até finalize |
| `rpc_ninebox_evaluation_list` | Quem pode ver (helper) | Lista · respeita hierarquia |
| `rpc_ninebox_team_matrix` | Lider+, RH/dir/SA, ou quem tem liderados | Time como pontos na matriz |
| `rpc_ninebox_history` | Subject, manager direto/indireto, RH/dir/SA | Snapshots históricos de um subject |

## Helpers internos (9)

- `ninebox_grid_max(grid_size)` → 3 ou 5
- `ninebox_validate_criteria(jsonb)` → erro ou NULL
- `ninebox_score_to_box(score, grid_size)` → coordenada 1..N
- `ninebox_compute_axis_score(eval_id, axis, evaluator)` → média ponderada
- `ninebox_is_extreme_box(row, col, grid_size)` → BOOLEAN
- `ninebox_can_view_evaluation(eval_id)` → BOOLEAN (regra de visibilidade)
- `ninebox_persist_scores(eval_id, evaluator, scores)` → erro ou NULL (helper interno)
- `ninebox_seed_defaults_for_tenant(tenant_id)` → seed (idempotente)
- `ninebox_on_activation()` → trigger function · popula defaults na primeira ativação

## Permissões (8) e matriz role × permission

| Permissão | colaborador | lider | rh | diretoria |
|---|:---:|:---:|:---:|:---:|
| view_ninebox_self | ✓ | ✓ | ✓ | ✓ |
| view_ninebox_team |  | ✓ | ✓ | ✓ |
| view_ninebox_all |  |  | ✓ | ✓ |
| manage_ninebox_settings |  |  | ✓ | ✓ |
| manage_ninebox_cycles |  |  | ✓ | ✓ |
| evaluate_ninebox_subject |  | ✓ | ✓ | ✓ |
| finalize_ninebox |  | ✓ | ✓ | ✓ |
| view_ninebox_history |  | ✓ | ✓ | ✓ |
| **TOTAL** | **1** | **5** | **8** | **8** |

22 vínculos · super_admin acessa tudo via `is_super_admin()` checks.

## Mapeamento score → caixa

**3x3** (thresholds 2.33 / 3.66):
| Score | Box |
|---|---|
| 1.00 - 2.33 | 1 |
| 2.34 - 3.66 | 2 |
| 3.67 - 5.00 | 3 |

**5x5** (thresholds 1.80 / 2.60 / 3.40 / 4.20):
| Score | Box |
|---|---|
| 1.00 - 1.80 | 1 |
| 1.81 - 2.60 | 2 |
| 2.61 - 3.40 | 3 |
| 3.41 - 4.20 | 4 |
| 4.21 - 5.00 | 5 |

## Rótulos default (3x3 PT-BR · adaptação GE-McKinsey)

| | Performance baixa (1) | Performance média (2) | Performance alta (3) |
|---|---|---|---|
| **Potencial alto (3)** | Diamante bruto | Forte potencial | Estrela |
| **Potencial médio (2)** | Enigma | Mantenedor | Profissional de impacto |
| **Potencial baixo (1)** | Risco de saída | Performer eficaz | Performer sólido |

## Integração com Sessão A1

Toda RPC do módulo passa pelo gate de A1:

```sql
IF NOT module_is_active_for_me('ninebox') THEN
  RETURN jsonb_build_object('error', 'module_inactive', 'module', 'ninebox');
END IF;
```

Validado pelo T40.

## Ordem de aplicação

```bash
psql -f r2_people_schema_base_v1.sql
psql -f r2_people_seed_base_v1.sql
psql -f r2_people_schema_recognition_v1.sql
psql -f r2_people_seed_recognition_v1.sql
psql -f r2_people_schema_pdi_v1.sql
psql -f r2_people_seed_pdi_v1.sql
psql -f r2_people_schema_onboarding_v1.sql
psql -f r2_people_seed_onboarding_v1.sql
psql -f r2_people_schema_modules_v1.sql
psql -f r2_people_seed_modules_v1.sql
psql -f r2_people_patch_a1_module_checks.sql      # Sessão A1
psql -f r2_people_schema_ninebox_v1.sql           # Sessão A2 · NOVO
psql -f r2_people_seed_ninebox_v1.sql             # Sessão A2 · NOVO
```

## Suite de testes (40)

Roda em `BEGIN ... ROLLBACK` · não deixa lixo. Usa setup do tenant A2 com hierarquia DIR → LIDER1 (WU1) → [USR1, USR2 em WU1]; DIR → LIDER2 (WU2) → [USR3 em WU2]; RH (WU1); SA super_admin.

Cobertura por bloco:
- T01-T03 · Setup · ativação dispara seed_defaults via trigger
- T04-T07 · Settings update · validações de pesos e contagem de critérios, permissão
- T08-T10 · Cycles · CRUD básico
- T11-T16 · Lifecycle completo · start → self → manager → finalize com snapshot v1
- T17-T19 · Justificativa em caixas extremas · obrigatória, comprimento mínimo
- T20-T24 · Visibilidade · subject, manager direto/indireto, RH, diretoria
- T25-T26 · Re-finalize gera v2 (auditoria)
- T27-T28 · Ad-hoc sem cycle_id
- T29-T31 · Cancel
- T32 · Erro em subject inexistente
- T33-T35 · `team_matrix` · cobertura por papel
- T36-T37 · `history` · respeita visibilidade
- T38-T39 · `require_self_assessment` toggle (e bypass de diretoria)
- T40 · Gate A1 · módulo inativo bloqueia

```
PASS: 40
FAIL: 0
```

## Validações de pós-aplicação

```sql
SELECT count(*) FROM modules WHERE code = 'ninebox';                         -- 1
SELECT count(*) FROM permissions WHERE module = 'ninebox' AND active;        -- 8
SELECT role, count(*) FROM role_permissions
  WHERE permission_code IN (SELECT code FROM permissions WHERE module = 'ninebox')
  GROUP BY role ORDER BY role;
--   colaborador  1
--   diretoria    8
--   lider        5
--   rh           8

-- Tabelas, helpers, RPCs, policies
SELECT count(*) FROM information_schema.tables WHERE table_name LIKE 'ninebox%';   -- 5
SELECT count(*) FROM pg_proc WHERE proname LIKE 'rpc_ninebox%';                    -- 14
SELECT count(*) FROM pg_policies WHERE tablename LIKE 'ninebox%';                  -- 10
```

## Próximos passos sugeridos (escolha de Ricardo)

- **Climate** · replicar A1 nas 7 RPCs (precisa pacote E reanexado)
- **C4 Adapter Modules** · ~0.5 sessão · desbloqueia B3
- **B1 Frontend Onboarding** · ~2 sessões
- **B2 Página `/admin/modulos`** · ~1 sessão
- **B3 Navbar dinâmica** · ~0.5 sessão
- **D1 Supabase Auth real** · ~2 sessões
- **C1/C2/C3 Adapters** · Recognition, PDI, Onboarding

## Convenções mantidas

- Sem em-dashes
- Sem acentos em comentários SQL
- Idioma PT-BR no código de produto (display_name, descriptions)
- Mensagens de erro em snake_case ASCII (parsing no frontend)
- UUIDs de teste com prefixo `00000000-0000-0000-A2A4-...`
- `BEGIN ... ROLLBACK` em todos os arquivos de teste
- `CREATE OR REPLACE FUNCTION` em todas as RPCs (idempotente)
- `ON CONFLICT DO UPDATE` em seeds (idempotente)

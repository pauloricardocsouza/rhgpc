# R2 People · Sessão A1 · Module Checks nas RPCs

**Data**: 08/05/2026
**Versão**: A1.v1
**Frente**: A · Backend (continua o trabalho da Sessão L)
**Escopo**: Recognition + PDI + Onboarding (Climate fica para sessão futura)

## O que esta sessão entrega

Adiciona o gate de módulo ativo em **31 RPCs** dos schemas Recognition, PDI e Onboarding via patch standalone idempotente. Quando o super_admin desativa um módulo no tenant/employer/working_unit, o backend passa a bloquear todas as chamadas mesmo se o frontend insistir.

| Módulo | RPCs alteradas |
|---|---|
| Recognition | 6 |
| PDI | 10 |
| Onboarding | 15 |
| **Total** | **31** |

Climate (Sessão E) ficou de fora porque o pacote E não está no `r2_people_master_pack.zip` atual. Quando você reanexar a Sessão E, basta replicar o mesmo padrão dessa sessão para fechar.

## O que mudou em cada RPC

Logo após o gate de autenticação existente, o patch injeta:

```sql
-- Sessao A1 · check de modulo ativo
IF NOT module_is_active_for_me('<code>') THEN
  RETURN jsonb_build_object('error', 'module_inactive', 'module', '<code>');
END IF;
```

Onde `<code>` é `recognition`, `pdi` ou `onboarding`.

### Ordem semântica das validações

```
1. auth (current_user_id IS NULL?)        → 'not_authenticated'
2. módulo ativo (este patch)              → 'module_inactive'
3. permissão da role                       → 'permission_denied'
4. business rules                          → vários códigos
```

### Payload de erro

```json
{ "error": "module_inactive", "module": "recognition" }
```

O frontend pode usar `error === 'module_inactive'` para redirecionar para a página 404 de módulo desativado (pendência B3 do plano).

## Helper adicional

```sql
module_is_active_for_user(p_module_code VARCHAR, p_user_id UUID) RETURNS BOOLEAN
```

Resolve a `working_unit_id` do user-alvo via `app_users` e delega para `module_is_active`. Útil para futuros checks "no escopo do recurso" (ex: criar PDI para um liderado em loja que não tem o módulo ativo). Ainda não usado dentro das RPCs deste patch porque os 31 casos atuais são satisfeitos pelo `module_is_active_for_me` do caller (validação suficiente para o gate principal). Pode ser usado em A1.x futuro se a granularidade exigir bloqueio por escopo de recurso, ex: bloquear `rpc_pdi_create` quando o módulo está ativo para o líder mas inativo na loja do liderado.

## Comportamento por escopo de ativação

| Cenário | U1 (W1, employer Z1) | U2 (W2, employer Z1) | U3 (W3, employer Z2) |
|---|---|---|---|
| Sem ativação | bloqueia | bloqueia | bloqueia |
| Ativo no tenant | libera | libera | libera |
| Ativo no employer Z1 | libera | libera | bloqueia |
| Ativo no working W3 | bloqueia | bloqueia | libera |

`super_admin` sempre passa pelo gate independente de ativação (`module_is_active_for_me` retorna `TRUE` quando o caller é super_admin · ver `sessao_l/r2_people_schema_modules_v1.sql:225`).

## Arquivos da entrega

| Arquivo | Tamanho | Descrição |
|---|---|---|
| `r2_people_patch_a1_module_checks.sql` | ~70 KB | Patch idempotente · helper + 31 RPCs reescritas |
| `r2_people_a1_tests.sql` | ~12 KB | 32 testes em BEGIN ... ROLLBACK |
| `00_local_setup.sql` | ~1 KB | Setup do Postgres dev local (auth.uid stub, roles) · NÃO aplicar em produção |
| `README_A1.md` | este arquivo | |

## Como aplicar no Supabase

```bash
# 1. Aplica o patch (idempotente · pode rodar varias vezes)
psql -f r2_people_patch_a1_module_checks.sql

# 2. (opcional) valida com o test suite
psql -f r2_people_a1_tests.sql
```

O patch usa `CREATE OR REPLACE FUNCTION` em todas as definições, então pode ser reaplicado sem efeitos colaterais. Se você precisar voltar atrás, basta reaplicar os schemas v1 originais (`sessao_h2/r2_people_schema_recognition_v1.sql` etc.) que sobrescrevem com as versões sem o check.

## Validação local feita nesta sessão

Postgres 16 rodando em `/tmp/pgdata`, porta 5433, db `r2_test`. Schemas aplicados na ordem H → H2 → J → K → L, seeds aplicados, patch A1 aplicado. **32/32 testes passando**.

```
T01-T04 · helper module_is_active_for_user resolve wu corretamente
T05-T14 · sem ativação · todas as RPCs bloqueiam, payload tem 'module' populado
T15-T18 · ativação no tenant · libera todos os WUs, módulo X não libera Y
T19-T21 · ativação no employer · libera só WUs do employer (herança)
T22-T24 · ativação no working · libera só essa WU (granularidade fina)
T25-T27 · super_admin sempre passa
T28-T30 · gate de auth precede gate de módulo
T31-T32 · smoke fim-a-fim · cria recognition após ativar, desativar volta a bloquear
```

## RPCs alteradas (lista completa)

### Recognition (6)
- `rpc_recognition_create`
- `rpc_recognition_react`
- `rpc_recognition_get_feed`
- `rpc_recognition_get_stats`
- `rpc_recognition_report`
- `rpc_recognition_resolve_report`

### PDI (10)
- `rpc_pdi_create`
- `rpc_pdi_update`
- `rpc_pdi_change_status`
- `rpc_pdi_action_add`
- `rpc_pdi_action_update`
- `rpc_pdi_action_remove`
- `rpc_pdi_comment_add`
- `rpc_pdi_list`
- `rpc_pdi_get_by_id`
- `rpc_pdi_list_cycles`

### Onboarding (15)
- `rpc_onb_template_create`
- `rpc_onb_template_update`
- `rpc_onb_template_stage_add`
- `rpc_onb_template_task_add`
- `rpc_onb_template_list`
- `rpc_onb_template_get`
- `rpc_onboarding_create_from_template`
- `rpc_onboarding_create_blank`
- `rpc_onboarding_stage_add`
- `rpc_onboarding_task_add`
- `rpc_onboarding_task_complete`
- `rpc_onboarding_task_uncomplete`
- `rpc_onboarding_change_status`
- `rpc_onboarding_list`
- `rpc_onboarding_get_by_id`

## Próximos passos sugeridos

1. **Climate** · replicar este padrão nas 7 RPCs de Climate (Sessão E) · ~0,3 sessão · pendente reanexar pacote E.
2. **Frontend tratamento do erro** · adicionar interceptor no `SupabaseRpcClient` que detecta `error === 'module_inactive'` e redireciona para página 404 de módulo desativado · faz sentido casado com B3 (navbar dinâmica).
3. **A2 · Schema 9-Box** · próximo módulo do roadmap.
4. **C4 · Adapter Modules** · habilita o frontend a consumir `rpc_my_active_modules` para a navbar dinâmica.

Recomendação: A2 ou C4 a seguir, conforme prioridade.

## Estado consolidado pós-A1

| Sessão | Módulo | Tabelas | RPCs | Module-check |
|---|---|---|---|---|
| E | Climate | 5 | 7 | PENDENTE |
| H | Base | 9 | 5 | n/a (módulo core) |
| H2 | Recognition | 3 | 6 | OK |
| J | PDI | 4 | 10 | OK |
| K | Onboarding | 6 | 15 | OK |
| L | Modules | 2 | 6 | n/a (próprio sistema) |
| **A1** | **(patch · 31 RPCs alteradas)** | **0** | **+1 helper** | **OK** |

Total acumulado: 29 tabelas, 17 enums, 53 RPCs originais + 1 helper novo, 59 policies RLS. Os schemas continuam intactos · este patch só reescreve funções via CREATE OR REPLACE.

# R2 People · Schema PDI v1 (Sessao J)

Modulo de Plano de Desenvolvimento Individual · ultimo modulo do app a ganhar suporte SQL no Supabase. Espelha e estende o que estava apenas no MockRpcClient ate a Sessao I.

**Pre-requisitos**
- `r2_people_schema_base_v1.sql` aplicado (Sessao H)
- `r2_people_seed_base_v1.sql` aplicado (Sessao H)

---

## Decisoes de design

| Decisao | Escolha |
|---|---|
| Ciclos como entidade propria | Sim · `pdi_cycles` por tenant |
| Workflow de status | Simples · 4 status (draft / active / completed / canceled) |
| Marcos (milestones) entre acoes | Nao · so acoes diretas com due_date |
| Evidencias de conclusao | Sim · upload no Supabase Storage (bucket `pdi-evidence`) |
| Comentarios | Sim · thread linear por PDI (nao por acao) |

---

## O que entra

### Enums (3)

| Enum | Valores |
|---|---|
| `pdi_status` | `draft`, `active`, `completed`, `canceled` |
| `pdi_action_kind` | `curso`, `leitura`, `mentoria`, `projeto`, `certificacao`, `evento`, `outro` |
| `pdi_action_status` | `not_started`, `in_progress`, `completed`, `canceled` |

### Tabelas (4)

| Tabela | Funcao | Particularidades |
|---|---|---|
| `pdi_cycles` | Ciclos compartilhados por tenant (2026-S1, 2026, etc.) | UNIQUE (tenant, code) + CHECK datas + `open_for_planning` |
| `pdis` | PDI individual | UNIQUE parcial: 1 PDI nao-draft por user/ciclo + denormalizacao actions_total/completed + snapshot manager_id |
| `pdi_actions` | Acoes do PDI | CHECK title 3-200 chars + evidencia path OU url (mutuamente exclusivos) + auto completed_at |
| `pdi_comments` | Thread linear de comentarios | Soft-delete via `deleted_at` |

### RPCs (10)

| RPC | Quem chama | Resumo |
|---|---|---|
| `rpc_pdi_create` | Owner / manager / RH-Dir | Cria PDI sempre como `draft`. Valida ciclo, hierarquia, mensagem |
| `rpc_pdi_update` | Mesmas regras | Edita objetivo/contexto/datas. Bloqueado em completed/canceled |
| `rpc_pdi_change_status` | Mesmas regras | Valida transicoes: draft -> active (precisa actions), active -> completed/canceled. cancel exige reason |
| `rpc_pdi_action_add` | Mesmas regras | Adiciona acao com display_order incrementado |
| `rpc_pdi_action_update` | Mesmas regras | Edita campos da acao incluindo evidencia. String vazia limpa |
| `rpc_pdi_action_remove` | Mesmas regras | Remove acao (bloqueado em PDI locked) |
| `rpc_pdi_comment_add` | Quem pode ler o PDI | Adiciona comentario. Continua funcionando mesmo em PDI locked |
| `rpc_pdi_list` | Qualquer | Lista por scope: own / team / all (validacao de permissao incluida) |
| `rpc_pdi_get_by_id` | pdi_can_read | Retorna PDI + actions + comments enriquecidos |
| `rpc_pdi_list_cycles` | Qualquer auth | Lista ciclos ativos do tenant |

### Helpers (1 + 3 trigger functions)

| Funcao | Descricao |
|---|---|
| `pdi_can_read(pdi_id)` | TRUE se caller e owner / manager direto/indireto / RH / Diretoria |
| `pdi_action_update_counts()` | Trigger denormaliza actions_total / actions_completed |
| `pdi_action_set_completed_at()` | Trigger BEFORE UPDATE seta/limpa completed_at automaticamente |
| `pdi_set_status_timestamps()` | Trigger BEFORE UPDATE seta activated_at / completed_at / canceled_at |

### Triggers (16)

- 4 `set_updated_at()` (tabelas)
- 2 `audit_change()` (pdis e pdi_cycles · decisoes formais auditaveis)
- 1 `pdi_action_update_counts()` em pdi_actions
- 1 `pdi_action_set_completed_at()` em pdi_actions (BEFORE)
- 1 `pdi_set_status_timestamps()` em pdis (BEFORE)
- (resto sao internos do schema base)

### Policies RLS (11)

| Tabela | Policies |
|---|---|
| `pdi_cycles` | tenant_read, rh_dir_write |
| `pdis` | owner_read, manager_read, rh_dir_read, write (combinada) |
| `pdi_actions` | read (via pdi_can_read), write (via EXISTS pdi com permissao) |
| `pdi_comments` | read (via pdi_can_read), insert, self_update |

### Indexes (18)

Cobrem busca tipica: por tenant + data, por user + status, por ciclo, por status (fila), por manager, por due_date, parcial UNIQUE de PDI ativo, etc.

### Storage bucket

- `pdi-evidence` privado · 10 MB por arquivo · MIME types: pdf, png, jpg, webp, docx, xlsx, pptx, txt, csv
- 4 policies (read, insert, update, delete) seguindo formato de path `{tenant_id}/{pdi_id}/{action_id}/{file}`

### Permissoes

Ja existiam no catalogo base (Sessao H):
- `view_self_pdi`, `manage_self_pdi` (colaborador+)
- `view_team_pdi`, `manage_team_pdi` (lider+)
- `view_all_pdi`, `manage_all_pdi` (rh+, diretoria)

Esta sessao nao adiciona novas permissoes · so usa as existentes.

---

## Modelo de permissoes

**Quem pode CRIAR PDI?**

```
self_pdi (todos os roles tem)  -> criar PDI para si mesmo
manager (hierarquia direta ou indireta)  -> criar para liderado
manage_all_pdi (rh, diretoria)  -> criar para qualquer um
```

**Quem pode LER PDI?**

`pdi_can_read(pdi_id)` retorna TRUE se:
- caller == owner do PDI
- caller e RH ou Diretoria
- caller e manager (direto ou indireto, max 10 niveis) do owner

**Quem pode EDITAR PDI?**

Owner OR manager OR RH/Diretoria · igual ao read mas exclui peers (colaboradores nao-relacionados).

**Quem pode COMENTAR?**

Quem pode LER. Comentarios continuam funcionando mesmo em PDI completed/canceled (thread fica aberta para reflexao final).

---

## Workflow de status

```
                  +---------+
                  |  draft  |
                  +----+----+
                       |
            (precisa de >= 1 acao)
                       |
                  +----v----+
        +---------+ active +---------+
        |         +----+----+         |
   (cancel_reason)    |        (transicao normal)
        |             |                |
+-------v---+    +----v-----+    +-----v-----+
| canceled  |    | active   |    | completed |
+-----------+    +----------+    +-----------+
   (LOCKED)                          (LOCKED)
```

PDIs em `completed` ou `canceled` sao **locked** · nao aceitam edicao de objective/datas, add/remove/update de actions. Comentarios continuam aberto.

---

## Como aplicar

### 1. Pre-requisitos no Supabase

Aplicar antes:
```
1. r2_people_schema_base_v1.sql
2. r2_people_seed_base_v1.sql
```

### 2. Aplicar PDI

No SQL Editor do Supabase Dashboard, em ordem:
```
3. r2_people_schema_pdi_v1.sql              (este pacote)
4. r2_people_seed_pdi_v1.sql                (ciclos exemplo · opcional)
5. r2_people_storage_pdi_v1.sql             (bucket Storage · so no Supabase real)
6. r2_people_rls_policies_pdi_tests.sql     (opcional · valida)
```

### 3. Validar

```sql
SELECT count(*) FROM information_schema.tables
WHERE table_schema='public' AND table_name LIKE 'pdi%';                  -- 4

SELECT count(*) FROM information_schema.routines
WHERE routine_schema='public' AND routine_name LIKE 'rpc_pdi%';          -- 10

SELECT count(*) FROM pg_policies
WHERE schemaname='public' AND tablename LIKE 'pdi%';                     -- 11

SELECT id FROM storage.buckets WHERE id = 'pdi-evidence';                -- pdi-evidence
```

### 4. Smoke test manual

```sql
-- Logado como diretoria
SET LOCAL request.jwt.claim.sub = '<seu-auth-user-id>';

-- Listar ciclos
SELECT rpc_pdi_list_cycles();

-- Criar PDI
SELECT rpc_pdi_create(
  '<seu-app-user-id>',
  '<cycle-id-do-list-cycles>',
  'Quero desenvolver lideranca tecnica em arquitetura de dados',
  'Contexto adicional opcional'
);

-- Adicionar acao
SELECT rpc_pdi_action_add(
  '<pdi-id-retornado>',
  'Curso PostgreSQL avancado',
  'Por udemy ou alura',
  'curso',
  '2026-09-30'
);

-- Ativar
SELECT rpc_pdi_change_status('<pdi-id>', 'active');

-- Listar meus PDIs
SELECT rpc_pdi_list('own');
```

### 5. Upload de evidencia (so com Supabase Storage)

Path obrigatorio: `{tenant_id}/{pdi_id}/{action_id}/{filename}`

Apos o upload via Supabase Storage SDK, salvar o path retornado em `pdi_actions.evidence_path`:

```sql
SELECT rpc_pdi_action_update(
  '<action-id>',
  NULL, NULL, NULL, NULL, 'completed',
  'tenant-id/pdi-id/action-id/certificado.pdf',  -- path no bucket
  NULL,                                            -- nao usar URL externa junto
  'Certificado de conclusao do curso'
);
```

---

## Decisoes arquiteturais

### Por que `manager_id_snapshot` em vez de FK dinamica?

Quando o PDI e criado, fica registrado quem era o gestor naquele momento. Se a pessoa for transferida para outro time depois, o PDI mantem o vinculo com o gestor da epoca para historico. A consulta atual (RLS / `user_is_manager_of`) continua usando a hierarquia atual via `app_users.manager_id`.

### Por que `evidence_path` E `evidence_url` separados?

Dois cenarios diferentes:
- **Path**: arquivo dentro do bucket `pdi-evidence` (controlado pelo R2 People)
- **URL**: link externo (Google Drive, certificado online, etc.)

A constraint `action_evidence_one_kind` garante que so um esta preenchido por vez. String vazia (`''`) limpa o campo via RPC update.

### Por que UNIQUE parcial em vez de UNIQUE total?

```sql
CREATE UNIQUE INDEX uq_pdis_one_active_per_cycle
  ON pdis (tenant_id, user_id, cycle_id)
  WHERE status IN ('active', 'completed');
```

A pessoa pode ter VARIOS rascunhos no mesmo ciclo (esta planejando, comparando alternativas), mas SO UM ativo + concluido. Index parcial permite isso de forma elegante.

### Por que comentarios nao tem trigger de audit?

Volume. Em apps de gestao de pessoas, comentarios podem chegar a centenas por mes por PDI. Auditar cada um polui o audit_log. Decisoes formais (criar / mudar status / cancelar) sao auditadas, comentarios nao.

Se for necessario reverter um comentario apagado, o `soft-delete` via `deleted_at` mantem o registro · so RLS o esconde do feed.

### Por que `pdi_can_read` como SECURITY DEFINER?

Para usar dentro de RLS policies sem causar recursao infinita. As policies de `pdi_actions` e `pdi_comments` referenciam `pdi_can_read` que internamente le `pdis`. Se a funcao nao fosse SECURITY DEFINER, ela cairia nas policies de `pdis` e poderia causar loops.

### Por que action.completed_at e via trigger BEFORE?

`pdi_action_set_completed_at()` roda em BEFORE INSERT/UPDATE para que o `completed_at` ja entre na linha junto com a mudanca de `status`. Isso evita um UPDATE adicional disparando triggers em cascata (que seria o caso com AFTER).

### Por que ciclos podem ser fechados para planning?

`open_for_planning = FALSE` impede colaboradores de criarem novos PDIs naquele ciclo. RH/Diretoria conseguem (override por permissao) para casos excepcionais (ex.: um novo contratado entrando no meio do semestre).

### Por que Storage bucket privado e nao publico?

Evidencias sao confidenciais (certificados, projetos internos, documentos pessoais). Bucket privado obriga acesso autenticado e respeita RLS. Para download, o frontend gera signed URLs temporarias via Supabase Storage SDK.

---

## Validacao realizada

Schema, seed e testes aplicados em PostgreSQL 16 local com stub de `auth.uid()`:

| Verificacao | Resultado |
|---|---|
| Schema aplica sem erros | OK |
| 4 tabelas, 10 RPCs, 4 helpers, 11 policies, 16 triggers, 18 indexes | OK |
| 22 testes em `r2_people_rls_policies_pdi_tests.sql` | 22/22 passam |

Cobertura dos testes:
1. Constraints basicas (objetivo curto, end < start)
2. Index parcial · 1 PDI ativo por (user, cycle)
3. Denormalizacao de counts em INSERT/UPDATE/DELETE
4. completed_at automatico em pdi_actions
5. Timestamps de status em pdis (activated_at, completed_at, canceled_at)
6. RPC create happy path (self)
7. RPC create cross-tenant block
8. Ciclo fechado bloqueia colaborador / libera RH
9. Workflow de status valida transicoes (no_actions, no_change, invalid_transition, cancel_reason_required)
10. Permissoes nao-self (peer bloqueado, gestor permitido)
11. RPC list por scope (own, team, all com permissao)
12. RPC get_by_id retorna PDI + actions + comments enriquecidos
13. pdi_can_read respeita owner/manager/RH/Dir
14. Comentarios respeitam pdi_can_read
15. Evidencia path/url mutuamente exclusivos
16. action_remove respeita permissao
17. PDI locked apos completed bloqueia update/add/remove mas permite comentario
18. CASCADE de tenant deleta tudo
19. Audit log captura mudancas em pdis
20. rpc_pdi_list_cycles funciona
21. Comentario soft-delete (nao aparece em get_by_id)
22. Idempotencia do seed

---

## Storage bucket · nota tecnica

O arquivo `r2_people_storage_pdi_v1.sql` depende do schema `storage` do Supabase (criado automaticamente em projetos Supabase reais, nao existe em PostgreSQL standalone).

Em PostgreSQL local, este arquivo da erro silenciosamente · nao roda mas tambem nao quebra os outros. Para testar localmente, comente as referencias a `storage.objects` e `storage.buckets`.

No Supabase Dashboard:
1. Abra SQL Editor
2. Cole `r2_people_storage_pdi_v1.sql`
3. Run · vai criar o bucket `pdi-evidence` e 4 policies em `storage.objects`
4. Verifique em Storage > Buckets que `pdi-evidence` aparece como privado, 10 MB

---

## Pendencias conscientes

- **Adapter Supabase para PDI no app Next.js** · ainda usa MockRpcClient
- **Notificacoes** quando PDI e ativado / aprovado / proximo do prazo
- **Anexos** em comentarios (atualmente so texto)
- **Edicao de comentario** (UI · backend ja suporta via UPDATE de body + edited_at)
- **Reordenar acoes** (display_order ja existe · so falta UI)
- **Exportar PDI** para PDF/docx
- **Search full-text** em objective/context/comments
- **Notificacao por prazo** (acoes vencendo em N dias)
- **Multi-tenant nos tipos do app** (atualmente mock usa TENANT_GPC fixo)

---

## Estado consolidado da plataforma apos esta sessao

| Camada | Status |
|---|---|
| Schema base (Sessao H) | OK |
| Schema Climate (Sessao E) | OK |
| Schema Recognition (Sessao H2) | OK |
| Schema PDI (Sessao J) | OK |
| Frontend mock | OK (Sessoes F, G, I) |
| Adapter Supabase Climate | OK (Sessao G) |
| Adapter Supabase PDI/Recognition | Pendente |
| Supabase Auth real | Pendente |

**Total de objetos SQL** entregues ate agora:
- 4 schemas modulares (Base, Climate, Recognition, PDI)
- 21 tabelas
- 12 enums
- 32 RPCs/helpers
- 39 policies RLS
- 1 Storage bucket
- 80+ testes automatizados

---

DESENVOLVIDO POR R2 SOLUCOES EMPRESARIAIS · 2026

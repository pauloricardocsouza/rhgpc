# R2 People · Schema Recognition v1

Modulo de reconhecimentos peer-to-peer · permite colaboradores celebrarem uns aos outros publicamente dentro do tenant.

**Pre-requisitos**
- `r2_people_schema_base_v1.sql` aplicado
- `r2_people_seed_base_v1.sql` aplicado

---

## Decisoes de design

| Decisao | Escolha |
|---|---|
| Categorizacao por valor da empresa | Nao · mensagem livre |
| Multiplos destinatarios | Nao · 1 sender + 1 recipient |
| Engajamento social | So reacoes (5 emojis) · sem comentarios |
| Visibilidade | Publico + flag `is_private` para casos sensiveis |
| Pontos / moeda virtual | Nao tem · sem gamification |

Resultado: schema enxuto (3 tabelas + 6 RPCs) que atende o caso de uso sem inflar.

---

## O que entra

### Enums (2)

| Enum | Valores |
|---|---|
| `recognition_reaction_kind` | `clap`, `heart`, `celebrate`, `strong`, `star` |
| `recognition_report_status` | `pending`, `resolved_hidden`, `resolved_kept`, `dismissed` |

### Tabelas (3)

| Tabela | Funcao | Particularidades |
|---|---|---|
| `recognitions` | Post (sender, recipient, message, is_private) | CHECK no_self + CHECK message 3-1000 chars + soft-delete via `hidden_at` + counts denormalizados |
| `recognition_reactions` | 1 reacao por usuario por post | UNIQUE (recognition_id, user_id) + UPSERT troca emoji |
| `recognition_reports` | Denuncias de moderacao | UNIQUE (recognition_id, reporter_id) + status workflow |

### RPCs (6)

| RPC | Quem chama | Resumo |
|---|---|---|
| `rpc_recognition_create` | Qualquer (com `create_recognition`) | Cria post · valida sender ≠ recipient + mesmo tenant + tamanho |
| `rpc_recognition_react` | Qualquer (com `react_recognition`) | Adiciona/troca/remove reacao · respeita privacidade |
| `rpc_recognition_get_feed` | Qualquer (com `view_recognitions_public`) | Feed paginado (max 100/pagina) com privacidade aplicada |
| `rpc_recognition_get_stats` | Qualquer (com `view_recognitions_public`) | KPIs do periodo · my_sent, my_received, top 5, participation rate |
| `rpc_recognition_report` | Qualquer (com `report_recognition`) | Denuncia · 1 por reporter por post |
| `rpc_recognition_resolve_report` | RH/Diretoria (com `manage_recognition_reports`) | Acao `hide` / `keep` / `dismiss` |

### Triggers (4)

- 2 `set_updated_at()` em `recognitions` e `recognition_reports`
- 2 `audit_change()` (auditados em `audit_log`)
- 2 `recognition_update_counts()` denormalizando `reactions_count` e `reports_count` em recognitions

### Policies RLS (10)

| Tabela | Policies |
|---|---|
| `recognitions` | visible_read (com privacy), rh_dir_read_all (inclui hidden), rh_dir_update, sender_delete |
| `recognition_reactions` | tenant_read, self_write |
| `recognition_reports` | self_read (reporter), rh_dir_read, self_insert, rh_dir_update |

### Permissoes adicionadas (5)

| Permission | Modulo | Colab | Lider | RH | Dir |
|---|---|---|---|---|---|
| `view_recognitions_public` | recognition | sim | sim | sim | sim |
| `create_recognition` | recognition | sim | sim | sim | sim |
| `react_recognition` | recognition | sim | sim | sim | sim |
| `report_recognition` | recognition | sim | sim | sim | sim |
| `manage_recognition_reports` | recognition | nao | nao | sim | sim |

---

## Modelo de privacidade

Posts publicos sao vistos por todos do tenant. Posts marcados `is_private = TRUE` sao vistos por:

- O destinatario (`recipient_id`)
- O remetente (`sender_id`)
- Lideres do destinatario (gestor direto + indireto, ate 10 niveis · via `user_is_manager_of()`)
- Qualquer usuario com role `rh` ou `diretoria`

Aplicado em duas camadas:

1. **RLS policy** `recognitions_visible_read` filtra na leitura via SELECT
2. **RPC `rpc_recognition_get_feed`** filtra via WHERE explicito (defesa em profundidade · garante que mesmo se a policy fosse alterada, o feed continua respeitando privacidade)

Posts ocultos por moderacao (`hidden_at IS NOT NULL`) ficam invisiveis a todos exceto RH/Diretoria (que veem para revisar denuncias).

---

## Modelo de moderacao

```
[colaborador] denuncia post
    -> recognition_reports (status='pending')
    -> reports_count++ no post (via trigger)

[rh ou diretoria] resolve denuncia · 3 acoes:
    'hide'      -> post.hidden_at = now()
                  recognition_reports.status = 'resolved_hidden'
    'keep'      -> post permanece visivel
                  recognition_reports.status = 'resolved_kept'
    'dismiss'   -> denuncia descartada (sem acao)
                  recognition_reports.status = 'dismissed'
```

Toda decisao de moderacao fica auditada em `audit_log` (via trigger `audit_change()` em `recognition_reports`).

---

## Como aplicar

### 1. Pre-requisitos no Supabase

Aplique antes:

```
1. r2_people_schema_base_v1.sql
2. r2_people_seed_base_v1.sql
```

### 2. Aplicar Recognition

No SQL Editor do Supabase Dashboard, em ordem:

```
3. r2_people_schema_recognition_v1.sql
4. r2_people_seed_recognition_v1.sql
5. r2_people_rls_policies_recognition_tests.sql   (opcional)
```

### 3. Validar

```sql
-- Devem retornar:
SELECT count(*) FROM information_schema.tables
WHERE table_schema = 'public' AND table_name LIKE 'recognition%';        -- 3

SELECT count(*) FROM information_schema.routines
WHERE routine_schema = 'public' AND routine_name LIKE 'rpc_recognition%'; -- 6

SELECT count(*) FROM pg_policies
WHERE schemaname = 'public' AND tablename LIKE 'recognition%';            -- 10

SELECT count(*) FROM permissions WHERE module = 'recognition';            -- 5

SELECT role, count(*) FROM role_permissions rp
JOIN permissions p ON p.code = rp.permission_code
WHERE p.module = 'recognition'
GROUP BY role ORDER BY role;
-- colaborador 4 / lider 4 / rh 5 / diretoria 5
```

### 4. Smoke teste manual

```sql
-- Como diretoria
SET LOCAL request.jwt.claim.sub = '<auth_user_id_de_um_diretor>';

-- Listar feed
SELECT rpc_recognition_get_feed(20);

-- Stats do mes
SELECT rpc_recognition_get_stats(30);

-- Criar reconhecimento
SELECT rpc_recognition_create(
  '<id_de_outro_user_no_mesmo_tenant>',
  'Excelente trabalho fechando o trimestre',
  FALSE  -- publico
);
```

---

## Decisoes arquiteturais importantes

### Por que `reactions_count` e `reports_count` sao denormalizados?

O feed paginado precisa exibir contagem de reacoes em cada item. Sem denormalizacao, cada item exigiria um subquery agregado · custoso para feeds com 50+ itens.

Trigger `recognition_update_counts()` mantem o snapshot atualizado em INSERT/DELETE de `recognition_reactions` e `recognition_reports`. Custo: 1 UPDATE adicional por reacao/denuncia.

### Por que `is_private` e nao "audiencia configuravel"?

Em conversa com o caso de uso (GPC: ~600 colaboradores), audiencia configuravel (escolher exatamente quem ve) seria ruido. A regra `is_private = TRUE -> recipient + manager chain + RH/Dir` cobre o caso real ("feedback construtivo que nao quero exibir publicamente") sem complexidade extra.

Se no futuro precisar de "feedback so para o gestor direto", basta adicionar uma flag `is_manager_only` ou um enum `audience` (`public/private/manager_only`).

### Por que NAO ha comentarios?

Comentarios viram thread, viram drama, viram moderacao infinita. Reacoes (5 emojis) cobrem ~95% do que comentarios entregariam (validacao social) sem o overhead de moderacao.

Se for solicitado depois, a tabela `recognition_comments` se encaixa facilmente · mesmo padrao de `recognition_reactions` (com FK para post + author + body).

### Por que `hidden_at` em vez de DELETE?

Auditoria. Quando um post e ocultado, queremos:

- Saber quem ocultou (`hidden_by`) e quando (`hidden_at`)
- Saber a razao (`hidden_reason`)
- Permitir reverter (UPDATE `hidden_at = NULL`) sem perder o conteudo
- Nao quebrar denuncias existentes (`recognition_reports` tem FK CASCADE para o post)

### Por que feed_RPC duplica a logica de privacidade da RLS?

Defesa em profundidade. Se algum dia a RLS policy for alterada por engano (ex.: um DBA roda um migration que dropa a policy), o RPC ainda filtra. Ambas as camadas usam `user_is_manager_of()` e o mesmo conjunto de regras.

Custo: pequena duplicacao de logica. Beneficio: dificil escapar acidentalmente.

### Por que `sender_delete` policy permite o autor deletar seu post?

Escape hatch para arrependimento imediato (typo, mensagem mandada errada). Limitado a:

- Sender == caller
- Post nao foi `hidden_at` (se ja foi moderado, nao pode mais sumir o registro)

Em deletes legitimos, o cascade remove reactions e reports tambem.

### Por que enum `recognition_reaction_kind` e nao tabela?

Os 5 emojis sao fixos pelo produto · nao queremos cliente customizar. Enum e mais leve, indexavel, e o app pode mapear emojis sem hit no banco.

### Por que `audit_change()` ainda funciona aqui apesar de tenant_id em audit_log ser DEFERRABLE?

A FK DEFERRABLE so afeta o momento da checagem (fim da transacao). Inserts normais funcionam imediatamente · so e diferida quando estamos no meio de um cascade de tenant.

---

## Limitacoes conhecidas / nao implementado

- **Notificacoes**: o destinatario nao recebe notificacao automatica · isso fica para um modulo de notifications futuro
- **Trending / streaks**: nao calculamos "quem esta em streak de reconhecimentos" · pode ser computado em view materializada depois
- **Search full-text na mensagem**: nao tem · se virar requisito, adicionar `tsvector` em `recognitions.message`
- **Media (imagens, gifs)**: nao tem · texto puro
- **Mencoes a outros usuarios**: nao tem · `@nome` nao e parseado
- **Visibilidade por departamento**: nao tem · so publico vs privado vs hidden
- **Edit do post**: nao tem · sender pode deletar e recriar (mensagem ficou imutavel apos criacao)
- **Limite de posts por dia**: nao tem rate-limiting · qualquer um pode criar quantos quiser

---

## Validacao realizada

Schema, seed e testes aplicados em PostgreSQL 16 local com stub de `auth.uid()`:

| Verificacao | Resultado |
|---|---|
| Schema aplica sem erros | OK |
| Seed adiciona 5 perms + matriz 4/4/5/5 | OK |
| 3 tabelas, 6 RPCs, 10 policies criados | OK |
| 18 testes em `r2_people_rls_policies_recognition_tests.sql` | 18/18 passam |

Cobertura dos testes:
1. Constraint `sender != recipient`
2. Mensagem 3-1000 chars
3. UNIQUE (post, user) em reactions + UPSERT troca emoji
4. Trigger `reactions_count` denormalizado funciona
5. Trigger `reports_count` denormalizado funciona
6. UNIQUE (post, reporter) em reports
7. RPC create bloqueia self-recognize
8. RPC create bloqueia cross-tenant
9. RPC create happy path
10. RPC react: adicionar / trocar / remover
11. RPC report + bloqueio de duplicata + razao curta
12. RPC resolve_report: permission_denied para colaborador, hide oculta o post
13. RPC get_feed: privacidade respeitada (recipient ve, manager ve, RH/Dir ve, outros nao)
14. RPC get_feed: hidden posts ocultos
15. RPC get_stats: KPIs com estrutura esperada
16. Catalogo de permissoes Recognition consistente (4/4/5/5)
17. CASCADE de user remove reactions
18. Idempotencia do seed

---

DESENVOLVIDO POR R2 SOLUCOES EMPRESARIAIS · 2026

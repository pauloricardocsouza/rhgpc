# Sessão G2 · Feed de reconhecimentos enviados

Lista as 10 mais recentes solicitações de reconhecimento enviadas pelo próprio usuário, em uma nova página `/meus-reconhecimentos` com 2 abas (recebidos/enviados). Mantém os cards de contagem da G1, e adiciona o link "Ver feed completo →".

## Decisões fechadas

| Decisão | Escolha | Razão |
|---|---|---|
| Profundidade | Top 10 mais recentes · sem paginação | Cobertura suficiente para uso pessoal; paginação fica para G2-bis se demanda surgir |
| Onde mostrar | Página `/meus-reconhecimentos` com abas | Não polui a `/minha-jornada`; URL compartilhável; query param `?tab=sent` pré-seleciona aba |
| Conteúdo do item | Destinatário (com link) + mensagem + data + privado + reações | Compacto, com link direto para a ficha do destinatário quando disponível |

## O que entrega

| Componente | Arquivo | Linhas |
|---|---|---|
| RPC backend | `supabase/migrations/00350_g2_rpc_my_sent_recognitions.sql` | 60 |
| Testes | `supabase/tests/00350_g2_my_sent_recognitions.sql` | 178 |
| Página com abas | `src/app/meus-reconhecimentos/page.tsx` | 244 |
| Adapter | `src/lib/r2/employees.ts` | +28 |
| Links na `/minha-jornada` | `src/app/minha-jornada/page.tsx` | +6 (headerLink) |

### Backend · `rpc_my_sent_recognitions(p_limit DEFAULT 10)`

- Filtra por `sender_id = current_user_id()` e `hidden_at IS NULL`
- Ordena por `created_at DESC`
- Enriquece com nome do destinatário (preferindo `employees.full_name` sobre `app_users.full_name`), `recipient_employee_id` para link, `recipient_job_title`
- Cap defensivo de limit entre 1 e 50

## Testes (7/7 PASS)

| Teste | Cobertura |
|---|---|
| T01 | `not_authenticated` |
| T02 | Sem reconhecimentos → array vazio |
| T03 | Enriquecimento com nome da ficha e employee_id |
| T04 | Ordenação DESC por created_at |
| T05 | Cap de limit entre 1 e 50 |
| T06 | `hidden_at` filtrado |
| T07 | Isolamento por sender_id |

## Fluxo prático

1. Colaborador na `/minha-jornada` vê card "Reconhecimentos que eu enviei" com 2 KPIs
2. Clica em "Ver feed completo →"
3. Vai pra `/meus-reconhecimentos` na aba "Recebidos" (default)
4. Troca para "Enviados" → vê os 10 mais recentes que enviou
5. Cada item mostra nome+cargo do destinatário, mensagem, data, badge 🔒 se privado, contagem de reações
6. Clica em um nome com `recipient_employee_id` → vai pra ficha do destinatário

# R2 People · Prompt de Migração

**Versão:** 17/mai/2026 · após sessão G2+G3
**Stack:** Postgres 16 (Supabase) + Next.js 14 (App Router, TS strict) + FastAPI worker (OCR)
**Cliente-âncora:** Grupo Pinto Cerqueira (GPC) · 367 colaboradores · 14 unidades · 4 empregadores
**Estado:** **170/170 testes backend** · **TS strict 0 erros** · ~13k linhas TS/TSX, ~25k linhas SQL

---

## 1. Visão geral do produto

R2 People é um SaaS multi-tenant de gestão de pessoas para empresas brasileiras de médio porte. Substitui planilhas e processos manuais por uma plataforma única para:

- **Ficha de empregado** (cadastro completo, importação de fichas Domínio via OCR)
- **9-Box** (avaliações de potencial × desempenho, com escala 3x3 ou 5x5, ciclos formais e ad-hoc)
- **PDI** (Plano de Desenvolvimento Individual, com ações, evidências e ciclos)
- **Reconhecimentos** (públicos ou privados, com feed e ranking)
- **Onboarding** (templates de jornada de integração com tarefas)
- **Dashboards** (equipe, tenant-wide com drilldown)
- **Tela do colaborador** (Minha Jornada, com edição limitada e workflow de solicitações)

Cada tenant ativa/desativa **módulos** independentemente. RBAC com 5 papéis: `super_admin`, `diretoria`, `rh`, `lider`, `colaborador`.

**Decisões de produto importantes:**
- Hospitais (HEC/Liga Álvaro Bahia) **fora do escopo**
- Folha, banco de horas e cartão Flash são **integrações futuras pausadas** (telas correspondentes não construídas)
- Diaristas/eventuais como `tipo_vinculo` próprio (pausado)
- GPC é cliente-âncora · validação contínua com Karla (RH), Lucas (Serviços Compartilhados), Carlos (Comercial), Sandra (Varejo), Daniel (Rural), Pedro/Vitor (TI)

---

## 2. Arquitetura

### Backend (Postgres puro)
- Todas as operações via **RPCs SECURITY DEFINER** com `SET search_path = public`
- Cada RPC retorna `JSONB` (não usa exceções para erros de negócio — retorna `{"error": "code"}`)
- Padrão: chamar `current_user_id()` → carregar `app_users` → validar permissão → executar
- **RLS desativado em prod** (uso intencional); segurança em camada RPC
- `current_user_id()` lê de `request.jwt.claim.sub` (Supabase Auth)
- Audit log em tabela `audit_logs` (genérica)

### Frontend (Next.js 14)
- App Router (`src/app/`)
- TS strict, sem `any`
- Tailwind (utility-first, sem componentes pre-prontos)
- `lucide-react` para ícones
- `xlsx` (SheetJS) para importação de planilhas
- Adapter centralizado em `src/lib/r2/` que envolve cada RPC

### Worker (Python FastAPI)
- Único componente fora do Postgres
- OCR de fichas Domínio (PDF → tesseract → parser regex → push em batches)
- Server-Sent Events (`/jobs/{id}/stream`) para progresso
- Upload do PDF original para bucket privado `import-pdfs`

### Convenções universais
- **Sem em-dashes** (`—`) em qualquer output (texto, comentários, SQL). Usar `-` para hífen, `:` para cláusula, `·` para separador.
- **Sem acentos** em comentários SQL (compatibilidade de encoding antigo)
- **PT-BR** em UI/labels; `snake_case ASCII` em códigos de erro
- **`BEGIN; ... ROLLBACK;`** em todos os testes (isolamento)
- **`CREATE OR REPLACE`** / `ON CONFLICT` (idempotência)
- **UUIDs em testes**: prefixos hex válidos (0-9, a-f). Quando precisar de "etiqueta" semântica, usar `00aaaaaa-...`, `91aaaaaa-...`, `f3aaaaaa-...` etc.
- **`SELECT test_login()`** fora de `DO`; **`PERFORM test_login()`** dentro
- **Validar JS** com `node --check`; **validar TS** com `tsc --noEmit --strict`
- **`APP_VERSION` bump + `?v=X.Y` cache-bust** em HTMLs (outros projetos do Ricardo seguem isso; aqui é Next.js então não se aplica)
- Footer "DESENVOLVIDO POR R2 SOLUÇÕES EMPRESARIAIS · vX.Y" em projetos single-file (não em R2 People)

---

## 3. Estado consolidado por sessão

| Sessão | Tipo | Testes | Conteúdo |
|---|---|---|---|
| H · base | backend | — | Schema base: tenants, app_users, employer_units, departments, working_units, employees core |
| H2 · recognition | backend | — | Schema + RPCs de reconhecimentos |
| J · PDI | backend | — | Schema + RPCs de PDIs (planos + ações + ciclos) |
| K · onboarding | backend | — | Schema + RPCs de onboarding (templates + assignments + tasks) |
| L · modules | backend | — | Schema de módulos por tenant (ativos/inativos por feature) |
| A1 · módulos patch | backend | — | `module_is_active_for_me()`, checks distribuídos |
| A2 · ninebox | backend | — | Schema + RPCs de avaliações 9-Box (ciclos, scores, finalize) |
| B2 · admin módulos | backend | — | RPCs admin para super_admin ligar/desligar módulos por tenant |
| B3 · navbar | backend | — | `rpc_navbar()` retorna itens da navbar conforme role + módulos |
| C4 · adapter TS | frontend | strict 0 | Adapter completo para 57 RPCs em `src/lib/r2/` |
| E1 · ficha | full | 30 | Tabela `employees` completa (40+ colunas), 9 RPCs, tela LinkedIn-style |
| E2 · /pessoas/novo | full | 6 | Validação CPF mod 11, CEP, formulário em 5 seções |
| E4 · OCR | full | 20 | Worker Python: pdftoppm 300dpi → tesseract → parser → push batches |
| E5 · storage PDFs | full | 16 | Bucket privado `import-pdfs`, 30d retenção, view de stats |
| E6 · preview PDF | frontend | — | Modal full-screen com react-pdf, pdf.js via CDN |
| F1 · gestão + equipe | full | 18 | `rpc_employees_gestao_summary`, `rpc_my_team`, página /minha-equipe |
| F2 · ações do gestor | frontend | — | Dropdown "+ Ação": Criar PDI / Reconhecer / 9-Box ad-hoc |
| F3 · dashboard equipe | full | 12 | `rpc_my_team_dashboard`: PDIs atrasados + ranking reconhec. |
| F4 · dashboard tenant | full | 14 | `rpc_tenant_dashboard`: scope full/hierarchy, headcount, 9-Box agregado |
| F5 · inline edit PDIs | full | — | `PdiCardEditable` com modo view↔edit, gestão de ações inline |
| F6 · drilldown | full | 15 | `rpc_dashboard_drill` (5 kinds), página `/dashboard/drill/[kind]/[value]` |
| G1 · minha jornada | full | 14 | `rpc_my_journey`, página `/minha-jornada`, patch self-access F1 |
| G2 · feed enviados | full | 7 | `rpc_my_sent_recognitions`, página `/meus-reconhecimentos` (abas) |
| G3 · solicitações pessoais | full | 18 | 6 RPCs + tabela `employee_profile_change_requests`, workflow aprovação |

**Total backend:** 170/170 testes
**Total frontend:** strict 0 erros · ~13k linhas TS/TSX

---

## 4. Lógica do sistema (referências rápidas)

### Hierarquia de roles

```
super_admin > diretoria, rh > lider > colaborador
```

`super_admin` é cross-tenant (Anthropic/R2 staff). `diretoria` e `rh` são tenant-wide. `lider` tem subordinados (recursivo, até 10 níveis). `colaborador` vê só dados próprios.

### Funções helper essenciais (backend)

| Função | O que faz |
|---|---|
| `current_user_id()` | Retorna `id` de `app_users` do caller (via JWT) |
| `current_tenant_id()` | Tenant do caller |
| `is_super_admin()` | Bool |
| `user_is_manager_of(target_id)` | Caller é manager direto OU indireto (CTE recursiva) |
| `user_has_permission(perm)` | Verifica permissões granulares (raramente usado) |
| `module_is_active_for_me(module)` | Bool · checa se o módulo está ativo para o tenant |
| `can_view_gestao_for_app_user(target_id)` | F1 helper: ver dados de gestão (com patch G1 incluindo self-access) |

### Padrão de RPC de leitura

```sql
CREATE OR REPLACE FUNCTION rpc_xyz(...)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public AS $$
DECLARE v_user app_users;
BEGIN
  SELECT * INTO v_user FROM app_users WHERE id = current_user_id();
  IF v_user IS NULL THEN RETURN jsonb_build_object('error', 'not_authenticated'); END IF;

  -- Verificação de módulo se aplicável
  IF NOT module_is_active_for_me('ninebox') THEN
    RETURN jsonb_build_object('error', 'module_inactive', 'module', 'ninebox');
  END IF;

  -- Verificação de permissão
  IF NOT (is_super_admin() OR v_user.role IN ('diretoria', 'rh')) THEN
    RETURN jsonb_build_object('error', 'permission_denied');
  END IF;

  -- Query
  ...

  RETURN jsonb_build_object('ok', TRUE, 'items', v_items);
END;
$$;

GRANT EXECUTE ON FUNCTION rpc_xyz TO authenticated;
```

### Códigos de erro padronizados

`not_authenticated`, `module_inactive`, `permission_denied`, `cross_tenant_blocked`, `not_found` (com sufixo: `pdi_not_found`, `employee_not_found`), `invalid_value`, `invalid_uuid`, `invalid_status`, `cycle_not_open`, `cancel_reason_required`, etc.

### Filtro de reconhecimentos privados

Reconhecimentos com `is_private=TRUE` só são visíveis para:
- `super_admin`
- `diretoria`, `rh`
- `sender_id` (quem enviou)
- `recipient_id` (quem recebeu)

Implementado em todas as RPCs que retornam reconhecimentos (F3, F4, G1, G2).

### CTE recursiva de subárvore (F4, F6, G1)

```sql
WITH RECURSIVE sub AS (
  SELECT u.id, 1 AS depth FROM app_users u
  WHERE u.manager_id = v_user.id AND u.tenant_id = v_user.tenant_id AND u.active = TRUE
  UNION ALL
  SELECT u.id, s.depth + 1 FROM app_users u
    JOIN sub s ON u.manager_id = s.id
  WHERE s.depth < 10 AND u.tenant_id = v_user.tenant_id AND u.active = TRUE
)
SELECT array_agg(DISTINCT id) FROM sub;
```

Limita a 10 níveis para evitar loops em hierarquias mal configuradas.

### Schema 9-Box

- `final_box_row` e `final_box_col` são **1-indexed** (1-3 para grade 3x3, 1-5 para 5x5)
- Constraint `chk_box_coords` valida intervalo
- `box_labels_snapshot` JSONB captura nomes das caixas no momento da finalização (imutável)
- `final_box_label` é texto livre (vem do snapshot)

### Schema PDI

- `pdis` tem `user_id` (dono), `manager_id_snapshot`, `cycle_id`, `objective`, `context`, `status`, `start_date`, `end_date`, `actions_total`, `actions_completed`
- `pdi_actions` tem `pdi_id`, `title`, `description`, `kind` (enum: curso/leitura/mentoria/projeto/certificacao/evento/outro), `due_date`, `status` (enum: not_started/in_progress/completed/canceled), `display_order`, `evidence_path/url/note`
- Constraint `uq_pdis_one_active_per_cycle` impede 2 PDIs ativos por usuário no mesmo ciclo
- Trigger atualiza `actions_total/completed` automaticamente

### Schema Recognitions

- `recognitions` simples: `sender_id`, `recipient_id`, `message`, `is_private`, `hidden_at`, `created_at`
- Reactions em tabela separada (não muito usada ainda)
- Self-recognition bloqueada na RPC `rpc_recognition_create`

### Schema Profile Change Requests (G3)

- Workflow `pending` → `approved` / `rejected` / `canceled`
- Partial unique index: apenas 1 `pending` por `(employee_id, field)`
- `old_value` e `new_value` são JSONB para suportar campos compostos (endereço, contato emergência)
- Validação por campo via helper `pcr_validate_value(field, new_value)`

---

## 5. Onde estamos

**Funcionalidades completas:**
- ✅ Cadastro de colaboradores manual e via OCR
- ✅ Avaliação 9-Box (criação, scores, finalização, ad-hoc)
- ✅ PDI (criação, edição, ações, mudança de status, evidências)
- ✅ Reconhecimentos (público/privado, feed)
- ✅ Onboarding (modelos + assignments, mas tela de edição inline pendente)
- ✅ Dashboards (equipe + tenant + drilldown)
- ✅ Telas do colaborador (jornada, reconhecimentos próprios, solicitações)
- ✅ Admin de módulos e aprovações
- ✅ Importação Excel de colaboradores
- ✅ Storage de PDFs originais com retenção

**Status de produção:**
- Backend pronto para deploy em Supabase de produção (migrations idempotentes)
- Frontend roda local com stub de Supabase Auth (não testado em prod)
- Worker OCR roda local com tesseract+poppler instalados; precisa de container Docker para deploy
- **Falta: Supabase Auth real (D1)** — atualmente o frontend usa `createClient()` stub

---

## 6. Pendências e roadmap

### Críticas para deploy

**D1 · Supabase Auth real** — substituir `src/lib/supabase.ts` stub por SDK real do Supabase. Configurar:
- Magic link / OAuth (Google) no painel
- Trigger que cria `app_users` quando um usuário se cadastra (precisa associar a tenant)
- Sessão persistente
- Middleware Next.js para proteger rotas

Sem isso o produto não vai pra produção.

### Sessões em backlog

| Sessão | Prioridade | Descrição |
|---|---|---|
| **D1** · Auth real | **Crítica** | Supabase Auth + middleware + onboarding de tenant |
| **F7** · Onboarding inline edit | Alta | Inline edit de tasks de onboarding (similar à F5 de PDI) |
| **G4** · Upload real de foto | Média | Componente de upload no `ProfileChangeRequestModal` (atualmente placeholder) |
| **G5** · Notificações | Média | Webhook/email quando solicitação aprovada/rejeitada/recebe reconhecimento |
| **H1** · Notificações in-app | Média | Bell icon, lista de notificações, marcação como lida |
| **I1** · Exportação CSV/XLSX | Baixa | Exportar listas (drill, equipe, gestão) para Excel |
| **I2** · Filtros e busca | Baixa | Busca por nome em /pessoas, filtros em /dashboard |
| **I3** · Paginação | Baixa | Paginação nas listas que crescem (>50 itens) |

### Pendências técnicas no Comercial GPC (projeto separado, não R2 People)

Lembrete do contexto multi-projeto do Ricardo:
- Bug CP5 Evolução Mensal aguardando print do DevTools
- Processamento page remodelação (sessão dedicada)
- Análise Dinâmica pivot rewrite (sessão dedicada)
- Excesso de Estoque "Maior mês de venda" (ETL backend ready)

### Biblo (projeto separado)

- Ricardo precisa rodar `gerar_audios.py --apenas-en` (pendente desde v0.5.33)

---

## 7. Como continuar (instruções para próxima sessão Claude)

### Setup local Postgres

```bash
# Sandbox reseta /tmp/pgdata; recriar quando necessário
su - postgres -c "/usr/lib/postgresql/16/bin/pg_ctl -D /tmp/pgdata -l /tmp/pgdata/server.log start"

# Aplicar tudo do zero
export PGOPTS="-h /tmp -p 5433 -U claude -d r2_full"
for m in supabase/migrations/*.sql; do
  su - postgres -c "/usr/lib/postgresql/16/bin/psql $PGOPTS -v ON_ERROR_STOP=1 -f $m"
done

# Rodar todos os testes
for t in supabase/tests/*.sql; do
  su - postgres -c "/usr/lib/postgresql/16/bin/psql $PGOPTS -v ON_ERROR_STOP=1 -f $t" > /tmp/out.txt
  pass=$(grep -c 'PASS' /tmp/out.txt)
  echo "$t · PASS=$pass"
done
```

### Validar TS strict

```bash
# Copia src/ para sandbox + stub do supabase + tsconfig + npm install minimal
# (script completo em /tmp/tscheck_final do último rodízio)
cd /tmp/tscheck && tsc --noEmit --strict
```

### Antes de cada sessão nova

1. **Ler a doc da sessão anterior** em `docs/sessao_*.md`
2. **Confirmar com Ricardo as decisões** (rota, escopo, padrão UI, permissão, backend)
3. **Aplicar migrations e rodar regressão completa** (verificar se sandbox foi resetado)
4. **Implementar backend primeiro** (RPC + testes), depois adapter, depois frontend
5. **Validar TS strict** antes de fechar
6. **Doc + commit + zip** ao final
7. **Sempre perguntar antes de iniciar próxima sessão**

### Padrões de código que devem ser mantidos

- Componentes React em `'use client'` quando usam hooks
- `useCallback` + `useEffect` para fetches; `cancelled` flag
- Erros como `RpcError` com `.code`; mapear para PT-BR no UI
- Empty states amigáveis em todas as listas
- Loading states (Loader2 da lucide com `animate-spin`)
- Banner amber para avisos não-bloqueantes (ex: ficha não vinculada, escopo reduzido)
- Tela 403 amigável (não erro técnico) para `permission_denied`
- Cores semânticas: emerald=bom, amber=atenção, red=alerta, blue=info, zinc=neutro

### Arquivos a ler primeiro

- `README.md` · índice das sessões
- `docs/sessao_g3.md` · última sessão fechada
- `src/lib/r2/index.ts` · ponto de entrada do adapter (mostra tudo que está exposto)
- `src/lib/r2/employees.ts` · maior módulo, agrega F1/F3/F4/F6/G1/G2/G3
- `supabase/migrations/` em ordem numérica para entender o build incremental

---

## 8. Anotações de contexto (Ricardo)

- **Família:** Mari (esposa), Davi (filho 7 anos, escola bilíngue)
- **Empresa:** R2 Soluções Empresariais, Bahia, BR
- **Cliente principal:** Grupo Pinto Cerqueira (GPC) — supermercados ATP Varejo, ATP Atacado, Cestão L1, Cestão Inhambupe
- **Estilo:** PT-BR no produto, single-file deliverables quando possível, comunicação direta, sem em-dashes
- **Outros projetos paralelos** (consultar se Ricardo mencionar):
  - Comercial GPC (dashboard SPA, Firebase, v4.64)
  - FC Filadelfia (cash flow v7.7)
  - Biblo PWA (PT/EN para Davi, v0.5.33)
  - Organograma GPC (dash.solucoesr2.com.br)
  - WinThor BI SQL (Oracle, 9 queries em produção)
  - GPC CFO/Financial Dashboards (Chart.js ES5 para iOS Safari)

---

## 9. Arquivos no repositório

Veja `r2_people_repo.zip` (anexado). Estrutura:

```
r2_people_repo/
├── README.md
├── docs/                            # 24 docs de sessões + sessao_g3.md
├── src/
│   ├── app/                         # Next.js App Router
│   │   ├── admin/
│   │   │   ├── modulos/page.tsx
│   │   │   └── aprovacoes/page.tsx  # G3
│   │   ├── dashboard/
│   │   │   ├── page.tsx             # F4
│   │   │   └── drill/[kind]/[value]/page.tsx  # F6
│   │   ├── meus-reconhecimentos/page.tsx  # G2
│   │   ├── minha-equipe/page.tsx    # F1/F3
│   │   ├── minha-jornada/page.tsx   # G1 (+G3 integrada)
│   │   └── pessoas/
│   │       ├── page.tsx             # E1
│   │       ├── novo/page.tsx        # E2
│   │       ├── [id]/page.tsx        # E1/F1/F2/F5
│   │       └── importar/...         # E4
│   ├── components/
│   │   ├── employees/               # 9 componentes
│   │   ├── imports/                 # 2 componentes
│   │   ├── navbar/                  # 3 componentes
│   │   ├── profile/                 # 2 componentes G3
│   │   └── team/                    # 1 componente F3
│   └── lib/
│       ├── r2/                      # Adapter completo (10 módulos)
│       ├── supabase.ts              # Stub (substituir em D1)
│       └── validation.ts            # CPF mod 11, CEP, datas
├── supabase/
│   ├── 00_local_setup.sql           # Setup do ambiente local
│   ├── migrations/                  # 26 arquivos, ordem numérica
│   └── tests/                       # 17 arquivos, 170 testes
└── worker/                          # FastAPI OCR
    ├── README.md
    └── worker.py                    # 517 linhas
```

---

**Última atualização:** 17/mai/2026 · após sessão G2+G3
**Próxima sessão recomendada:** D1 · Supabase Auth real

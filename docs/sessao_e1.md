# Sessão E1 · Ficha de Empregado

Backend + frontend completos para gestão de pessoas (`/pessoas`). Substitui digitação manual: RH importa XLSX gerado pelo extrator OCR de fichas Domínio e tem o cadastro populado em minutos.

## O que entrega

### Backend

| Componente | Arquivo | Linhas |
|---|---|---|
| Schema | `supabase/migrations/00300_e1_schema_employees.sql` | 468 |
| RPCs | `supabase/migrations/00301_e1_rpcs_employees.sql` | 733 |
| Testes | `supabase/tests/00300_e1_employees.sql` | 457 |

**4 tabelas:** `employees`, `employee_salary_history`, `employee_vacations`, `employee_leaves`
**8 enums:** marital_status, race_color, education_level, salary_unit, dismissal_type, leave_reason, vacation_kind, employee_sex
**9 RPCs:** list, get_by_id, create, update, salary_add, vacation_add, leave_add, archive, import_xlsx
**RLS:** leitura por tenant; escrita só para super_admin, diretoria e rh
**Audit:** trigger em todas as 4 tabelas registra cada INSERT/UPDATE/DELETE

### Frontend

| Componente | Arquivo | Linhas |
|---|---|---|
| Lista | `src/app/pessoas/page.tsx` | 318 |
| Detalhe | `src/app/pessoas/[id]/page.tsx` | 653 |
| Dialog editar | `src/components/employees/EditSectionDialog.tsx` | 178 |
| Dialog importar | `src/components/employees/ImportDialog.tsx` | 363 |
| Adapter TS | `src/lib/r2/employees.ts` | 474 |

## Comportamento

### `/pessoas` (lista)

- Busca livre por nome, CPF ou matrícula (debounce 300 ms)
- Filtro segmentado de status: Todos / Ativos / Desligados
- Filtro de cargo livre
- Cards 4-col com avatar colorido determinístico, nome, cargo, matrícula, empresa
- Badge vermelho "Desligado" quando `termination_date` está preenchida
- Linha discreta com data de admissão (verde) ou desligamento (vermelho)
- Botões "Importar" e "Nova ficha" no topo
- Paginação "carregar mais"

### `/pessoas/[id]` (detalhe estilo LinkedIn)

- Header com banner gradiente, avatar grande circular, nome, cargo + CBO, empresa, badge de status
- **Sidebar fixa** com identidade essencial: CPF · RG · nascimento · email · celular · residencial · endereço
- **Main com 6 seções colapsáveis:**
  1. Dados pessoais (filiação, naturalidade, estado civil, sexo, raça, escolaridade, deficiência, beneficiários)
  2. Documentos (CPF, RG, CTPS, PIS, título eleitoral, CNH, doc militar)
  3. Vínculo (cargo, função, CBO, admissão, salário inicial, jornada, intervalo, FGTS, rescisão)
  4. Histórico salarial (tabela cronológica com cargo + tipo)
  5. Férias (tipo, início, fim, "paga na rescisão")
  6. Afastamentos (saída, retorno, motivo, CID)
- **Edição:** botão "Editar" em cada seção abre dialog modal com formulário tipado. Selects para enums. Salvar dispara `Employees.update` que grava audit_log automático.

### Importação

- Dialog em 2 modos: XLSX (funcional) ou PDF (stub direcionando para script local)
- XLSX: parser com SheetJS no frontend, preview de 8 linhas, idempotência por CPF + tenant
- Após import, mostra resumo: criados / pulados (já existiam) / erros com motivo

## Decisões fechadas

- **PK UUID interno**, não matrícula (matrícula pode mudar em transferência entre empresas do grupo, UUID é estável)
- **Soft-delete** via `archived_at`, sem DELETE direto
- **Birth city + birth state** colunas separadas para queries demográficas
- **Telefones** sem máscara (só dígitos)
- **Salário inicial** preenchido em `employees` cria primeira linha automática em `salary_history` com `change_type='initial'`
- **Idempotência de create** por (tenant_id, CPF) retorna `already_exists: true` com mesmo ID
- **termination_date NULL** = ativo, IS NOT NULL = desligado
- **source** rastreia origem: `manual`, `xlsx_import`, `pdf_ocr`

## Testes

30/30 passam · cobertura:
- T01-T05: permissões (col/lider negados, rh/diretoria/super_admin permitem)
- T06-T08: validação de campos obrigatórios
- T09-T10: idempotência por CPF
- T11-T12: update preserva campos não passados
- T13-T16: get_by_id retorna employee + salary_history + vacations + leaves
- T17-T19: filtros de lista (search por nome, search por CPF, total geral)
- T20-T21: salary_add popula histórico
- T22-T23: vacation_add + leave_add
- T24-T25: cross-tenant isolation
- T26: archive some da lista
- T27: import_xlsx em batch (2 created, 1 skipped, 1 error)
- T28: audit_log populado
- T29: termination + filtro 'terminated'
- T30: filtros combinados

```bash
psql -f supabase/tests/00300_e1_employees.sql
# === E1 · 30 testes executados · OK   ===
```

## Validação TypeScript

```bash
tsc --noEmit --strict
# exit 0 · zero erros
```

Cobertura strict: `lib/r2/employees.ts` + `app/pessoas/page.tsx` + `app/pessoas/[id]/page.tsx` + `components/employees/*` (1986 linhas TS/TSX).

## Próximos passos

- **D1** · Supabase Auth real (cookies, middleware, app_users.employee_id linkage)
- **E2** · Página `/pessoas/novo` (criação manual via formulário)
- **E3** · OCR no servidor via edge function (substituir o stub de import PDF)
- **E4** · Mapeamento de naturalidade do extrator (string "ALAGOINHAS - BA") → birth_city + birth_state separados
- **E5** · Endpoint para upload direto do PDF Domínio (dispara worker assíncrono que extrai e popula)

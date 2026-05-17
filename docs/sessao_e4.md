# Sessão E4 · OCR server-side (PDF Domínio)

Fluxo completo de importação de fichas via OCR no servidor: usuário faz upload do PDF do Domínio, um worker Python processa em background, e o RH revisa lote a lote antes de gravar nas fichas reais.

## Arquitetura

```
[Frontend Next.js]
    │
    │ 1. Imports.create(file_name, file_size)  →  {id, worker_token}
    │
    │ 2. POST multipart /upload (file + id + token)
    ↓
[Worker FastAPI Python]
    │
    │ 3. Pipeline async: pdftoppm 300 DPI → tesseract → parser regex+crop
    │
    │ 4. Para cada ficha extraída:
    │    rpc_import_worker_push_items(items, worker_token)
    │
    │ 5. Atualiza progresso:
    │    rpc_import_worker_update_job(status, pages_processed, ...)
    ↓
[Postgres · staging]
    │
    │ Frontend faz polling de Imports.get(id) a cada 3s
    │
    │ Quando status='completed':
    │   - Tela de revisão mostra items
    │   - RH aprova/edita/rejeita
    │   - approve → cria linha em employees (com idempotência por CPF)
```

**Decisões fechadas:**

| Decisão | Escolha | Razão |
|---|---|---|
| Onde rodar OCR | Worker Python separado (FastAPI + tesseract nativo) | 3-5x mais rápido que tesseract.wasm; sem timeout de 150s de Edge Function |
| Processamento | Assíncrono via SSE/polling | Lotes grandes (1000+ páginas) levariam ~25min, inviável síncrono |
| Confiabilidade | Staging com revisão | Erros de OCR (5-10%) seriam gravados direto em `employees` sem isso |
| Telas | Lista de jobs + tela dedicada de revisão | Workflow mais claro que pop-up de revisão |

## O que entrega

### Backend (1.328 linhas SQL)

| Componente | Arquivo | Linhas |
|---|---|---|
| Schema | `supabase/migrations/00310_e4_schema_import_jobs.sql` | 233 |
| RPCs | `supabase/migrations/00311_e4_rpcs_import.sql` | 627 |
| Testes | `supabase/tests/00310_e4_import_jobs.sql` | 468 |

**2 tabelas + 2 enums:**
- `import_jobs` · 1 linha por upload de PDF · status, contadores agregados, error_log
- `import_job_items` · 1 linha por ficha extraída · payload completo, confidence_score, parser_alerts
- Enums `import_job_status` (pending/running/completed/failed/reviewing/archived) e `import_item_status` (pending/approved/rejected/duplicate/edited)
- `worker_token` único por job (24 bytes hex) autoriza o worker a postar updates sem JWT

**11 RPCs:**

Lado do app (RH):
- `rpc_import_jobs_list` · lista filtrável por status
- `rpc_import_jobs_get` · detalhe com contadores
- `rpc_import_items_list` · items do job com paginação + filtro por status, marca duplicatas existentes
- `rpc_import_item_update` · RH edita campos antes da aprovação · status vira `edited`
- `rpc_import_item_approve` · cria registro em `employees` · idempotência por CPF
- `rpc_import_item_reject` · descarte com motivo opcional
- `rpc_import_job_approve_all` · aprova todos os pendentes em batch
- `rpc_import_job_archive` · arquiva o job
- `rpc_import_job_create` · cria job · retorna `{id, worker_token}`

Lado do worker (`GRANT EXECUTE TO anon`, autenticado pelo token):
- `rpc_import_worker_update_job` · valida token, atualiza progresso e status
- `rpc_import_worker_push_items` · valida token, insere items extraídos

### Worker Python (461 linhas)

`worker/worker.py` · FastAPI:
- `POST /upload` · multipart com (file, job_id, worker_token) · retorna 202
- `GET /jobs/{job_id}/stream` · SSE com eventos de progresso (started, page, page_error, completed, failed)
- `GET /health` · liveness probe
- Modo standalone (sem `SUPABASE_ANON_KEY`) pula chamadas RPC para desenvolvimento local

**Pipeline:**
1. `pdftoppm` 300 DPI por página
2. `tesseract -l por --psm 6` para texto full-page
3. `ocr_crop` para campos críticos (nome em x=40-1110, beneficiários em x=1135-2400) com `--psm 7`
4. Parser regex com âncoras (FILIAÇÃO, BRASIL, Em DD/MM/AAAA, etc)
5. `compute_confidence`: 100 - 10×alerts - 5×campos_críticos_vazios
6. Push em batches de 10 items para reduzir chamadas RPC

Container-ready com `requirements.txt` e instruções no `README.md` do worker.

### Frontend (1.227 linhas TSX)

| Componente | Arquivo | Linhas |
|---|---|---|
| Adapter `Imports` | `src/lib/r2/imports.ts` | 225 |
| Lista de jobs | `src/app/pessoas/importar/page.tsx` | 371 |
| Tela de revisão | `src/app/pessoas/importar/[jobId]/page.tsx` | 631 |

**`/pessoas/importar` (lista de jobs):**
- Caixa de upload com drag-and-drop · valida extensão .pdf
- Faz upload em 2 etapas: `Imports.create` → POST para o worker
- Lista os jobs agrupados por status: Em processamento / Pendentes revisão / Arquivados
- Cada linha mostra arquivo, status, contadores (pages, fichas, aprovadas/rejeitadas/duplicatas, falhas), tempo relativo
- Barra de progresso live em jobs `running`
- Auto-refresh de 5s enquanto há job em andamento
- Link "Ver" abre `/pessoas/importar/[jobId]`

**`/pessoas/importar/[jobId]` (revisão):**
- Header com nome do arquivo, status, contadores agregados
- Barra de progresso live (3s polling) enquanto OCR roda
- Lista colapsável de aviso do worker (page_error, exceptions)
- Filtros segmentados: Todos / Pendentes / Aprovadas / Rejeitadas / Duplicatas
- Para cada item:
  - Dot de confiança colorido (verde ≥80% / amarelo ≥50% / vermelho <50%)
  - Nome, status badge, contagem de alertas
  - CPF mono, cargo, admissão, desligamento, página de origem
  - Acordeon expansível com payload completo + grid de campos
  - Botões inline: Editar / Aprovar / Rejeitar
  - Aprovado → link "Ver ficha" para `/pessoas/[id]`
  - Duplicata → link "Ver existente"
- Botões de topo: Aprovar todos pendentes / Arquivar job

**Formulário de edição inline:**
- Aparece dentro do acordeon ao clicar em "Editar"
- 6 campos críticos: nome, CPF, cargo, admissão, celular, nascimento
- Calcula diff e envia apenas o que mudou via `rpc_import_item_update`

### Integração com ImportDialog

O dialog antigo em `/pessoas` que tinha um stub do PDF agora aponta para `/pessoas/importar` com mensagem clara: "OCR no servidor pronto. Use a tela dedicada que processa em background com revisão lote a lote."

## Validação

```bash
# Backend
psql -f supabase/tests/00310_e4_import_jobs.sql
# 20/20 PASS

# Regressão completa do projeto
psql -f supabase/tests/00300_e1_employees.sql  # 30/30
psql -f supabase/tests/00302_e2_check_cpf.sql  # 6/6
psql -f supabase/tests/00310_e4_import_jobs.sql # 20/20
# Total: 56/56 PASS

# Frontend
tsc --noEmit --strict
# exit 0 · zero erros
```

## Teste E2E do worker (validado anteriormente)

Upload do `Ficha_de_Empregado_reduzido.pdf` (16 páginas):
- Tempo total: **~80 segundos** (5s/página)
- Resultado: 16 items extraídos, 1 com alerta (Cleonice · RG legitimamente vazio)
- Push em batches de 10 funcionou
- SSE entregou 18 eventos (1 started + 16 page + 1 completed)

## Fluxo prático

1. **RH:** abre `/pessoas/importar` → clica na caixa, seleciona o PDF
2. **Sistema:** cria job no banco, faz upload para o worker, redireciona para `/pessoas/importar/[id]`
3. **Worker:** processa em background, vai postando items conforme extrai (visíveis em tempo real)
4. **RH:** vê a tela com progresso "12/16 páginas", já consegue revisar os primeiros itens enquanto os outros chegam
5. **Quando completed:** RH expande items com confidence baixo, edita o que precisa, aprova individualmente ou clica em "Aprovar todos"
6. **Backend:** ao aprovar, cria registro em `employees` (idempotente por CPF · duplicatas viram link para ficha existente)
7. **RH:** ao finalizar, arquiva o job · `/pessoas` agora tem todas as fichas importadas

## Próximos passos

- **E5** · Storage real do PDF (S3/Supabase Storage) para download e re-OCR posterior
- **E6** · Pré-visualização da página do PDF ao revisar cada item (RH compara o que o OCR leu com o original)
- **E7** · Detecção mais robusta de campos via vision LLM em items com confidence <50% (fallback do tesseract)
- **D1** · Supabase Auth real (worker autentica via service role; frontend via cookies)

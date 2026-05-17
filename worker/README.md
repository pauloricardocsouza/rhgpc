# R2 People · OCR Worker

Servidor FastAPI que processa PDFs de "Registro de Empregado" do sistema Domínio, faz OCR com `tesseract`, parseia os campos da ficha e empurra os resultados para o backend Supabase via RPC.

## Pré-requisitos

```bash
# Ubuntu/Debian
sudo apt install tesseract-ocr tesseract-ocr-por poppler-utils

# Python deps
pip install -r requirements.txt
```

## Configuração

Variáveis de ambiente:

| Variável | Default | Descrição |
|---|---|---|
| `SUPABASE_URL` | `http://localhost:54321` | URL do Supabase |
| `SUPABASE_ANON_KEY` | (vazio) | Chave anon · vazio = modo dev sem callback |
| `WORKER_PORT` | `8787` | Porta HTTP |
| `WORKER_TMP_DIR` | `/tmp/r2-worker` | Diretório de trabalho (arquivos temporários) |

## Rodar

```bash
# Dev
uvicorn worker:app --reload --host 0.0.0.0 --port 8787

# Prod (4 workers, 1 por core)
uvicorn worker:app --host 0.0.0.0 --port 8787 --workers 4
```

## API

### `GET /health`
Probe de liveness. Retorna `{ok, tesseract, pdftoppm, active_jobs}`.

### `POST /upload`
Multipart form:
- `job_id` (string) — UUID do job criado via `rpc_import_job_create`
- `worker_token` (string) — token retornado por aquela RPC
- `pdf` (file) — PDF do Domínio

Resposta `202`: `{ok: true, job_id, size}`.

O processamento roda em background. Não bloqueia a resposta.

### `GET /jobs/{job_id}/stream`
Server-Sent Events com eventos de progresso. Cada evento é uma linha `event: <kind>` + `data: <json>`.

Tipos de evento:
- `started` — `{pages_total}`
- `page` — `{page, total, name, confidence, alerts}` (uma por página processada)
- `page_error` — `{page, error}` (página falhou)
- `completed` — `{pages_processed}`
- `failed` — `{error}`

Fecha automaticamente após `completed` ou `failed`. Heartbeat a cada 30s.

## Pipeline

1. **Render** com `pdftoppm -png -r 300` (300 DPI A4 = 2481×3509)
2. **OCR full-page** com `tesseract -l por --psm 6`
3. **OCR de crop** para nome (40,410,1110,475) e beneficiários (1135,410,2400,475) com `--psm 7` — resolve o problema de campos concatenados na mesma linha visual
4. **Parser regex** extrai matrícula, CPF, RG, datas, cargo, CBO, salário
5. **Confidence score** = 100 − 10·len(alerts) − 5·(campos críticos vazios)
6. **Push em batches** de 10 items via `rpc_import_worker_push_items`
7. **Upload do PDF original** para o bucket `import-pdfs` no Supabase Storage (sessão E5)
8. **Update final** marca job como `completed` ou `failed`

### Storage do PDF (E5)

Após o OCR, o worker chama `rpc_import_worker_get_job_meta` para descobrir o `tenant_id` e o path destino, faz `POST /storage/v1/object/import-pdfs/<path>` e em seguida `rpc_import_worker_set_pdf_storage` para registrar o path no job.

O path segue o formato `<tenant_id>/<job_id>/original.pdf` para permitir as policies de RLS no Storage por tenant.

A falha do upload é tratada como best-effort: loga e segue · não interrompe o job nem reverte o `completed`.

PDFs são apagados automaticamente 30 dias após `archived_at` via `rpc_import_jobs_cleanup_expired` (chamada por pg_cron ou job agendado).

## Segurança

O worker chama o Supabase como `anon`, mas as RPCs `rpc_import_worker_*` validam `worker_token` no banco. Cada job tem token único de 48 bytes hex. Sem o token correto, o write é rejeitado.

**Não exponha o worker diretamente na internet sem rate limit.** Em produção, coloque atrás de um reverse-proxy (nginx, Cloudflare) com limite de tamanho de upload e taxa.

## Limitações conhecidas

- **Tempo:** ~5s por página em CPU comum. 1000 páginas = ~80min.
  Para acelerar, escale horizontalmente (várias instâncias do worker, balanceando jobs).
- **Memória:** cada página a 300 DPI ocupa ~25MB. Processa uma por vez, mas o PDF inteiro fica em disco durante a execução.
- **Layout fixo:** o parser depende dos bboxes do template do Domínio. Templates de outros ERPs precisariam de bboxes próprios.

## Teste local

```bash
# Sobe o worker em modo standalone (sem Supabase)
uvicorn worker:app --port 8787 &

# Upload um PDF
curl -X POST http://localhost:8787/upload \
  -F "job_id=test-001" \
  -F "worker_token=fake" \
  -F "pdf=@/caminho/para/arquivo.pdf"

# Acompanha o progresso
curl -N http://localhost:8787/jobs/test-001/stream
```

Sem `SUPABASE_ANON_KEY` o worker pula as chamadas RPC e só transmite via SSE — útil para validar o pipeline OCR antes de integrar.

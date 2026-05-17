# Sessão E5 · Storage de PDFs originais

Preserva o PDF original do Domínio no Supabase Storage para auditoria, prepara o terreno para preview (E6) e fallback Vision LLM (E7), com retenção automática de 30 dias após arquivamento.

## Decisões fechadas

| Decisão | Escolha | Razão |
|---|---|---|
| Quem salva | Worker, após processar | Worker já tem o arquivo em memória, evita round-trip extra do frontend |
| Onde | Bucket privado `import-pdfs` | RLS por tenant via path; signed URLs de 24h |
| O que | Só PDF original | PNGs de páginas ocupariam 10-50x o tamanho do PDF; podem ser regerados sob demanda |
| Retenção | 30 dias após archive | Auditoria curta sem custo perpétuo |
| Path | `tenant_id/job_id/original.pdf` | Primeiro segmento permite policy de Storage por tenant |

## O que entrega

### Backend (749 linhas)

| Componente | Arquivo | Linhas |
|---|---|---|
| Schema + bucket + RLS | `supabase/migrations/00320_e5_schema_pdf_storage.sql` | 108 |
| RPCs | `supabase/migrations/00321_e5_rpcs_pdf_storage.sql` | 222 |
| Testes | `supabase/tests/00320_e5_pdf_storage.sql` | 419 |

**Adições ao schema:**
- `import_jobs.storage_path` · path no bucket (NULL se não salvo)
- `import_jobs.pdf_uploaded_at` · timestamp do upload pelo worker
- `import_jobs.pdf_purged_at` · timestamp do housekeeping
- Bucket `import-pdfs` privado, limite 300 MB, só MIME `application/pdf`
- Policy `import_pdfs_read_tenant` · SELECT em `storage.objects` validando primeiro segmento do path com `current_tenant_id()`
- View `import_pdfs_stats` para dashboards de admin
- Índice parcial `idx_import_jobs_purge_candidates` para o housekeeping ser eficiente em escala

**4 novas RPCs:**

| RPC | Quem chama | Função |
|---|---|---|
| `rpc_import_worker_get_job_meta` | Worker (anon + token) | Retorna `tenant_id` + path template antes do upload |
| `rpc_import_worker_set_pdf_storage` | Worker (anon + token) | Registra `storage_path` após PUT no Storage · valida tenant no path |
| `rpc_import_jobs_get_pdf_url` | Frontend (RH/colaborador) | Retorna bucket+path para gerar signed URL via supabase-js |
| `rpc_import_jobs_cleanup_expired` | super_admin (cron) | Marca como purgado + remove de `storage.objects` jobs archived >30d |

**Validações cobertas pelos testes (16/16 passam):**
- Token errado → `invalid_token`
- Path com tenant errado → `path_tenant_mismatch`
- Job sem PDF → `pdf_not_stored`
- Job purgado → `pdf_purged` (com timestamp)
- Cross-tenant → `scope_outside_tenant` / `job_not_found`
- RH bloqueado de chamar cleanup (só super_admin)
- Cleanup com 0 expirados é idempotente
- Cleanup só purga jobs >30d, não toca em jobs recentes
- Set storage idempotente
- View `import_pdfs_stats` reflete contadores corretos

### Worker Python (+56 linhas)

`worker/worker.py` ganhou a função `_upload_pdf_to_storage`:
- Chamada após `rpc_import_worker_push_items` final, antes de marcar `completed`
- Pega `tenant_id` via `rpc_import_worker_get_job_meta`
- Faz `POST /storage/v1/object/import-pdfs/<path>` com `x-upsert: true`
- Registra path via `rpc_import_worker_set_pdf_storage`
- Best-effort: falhas logam mas não revertem o `completed`

### Frontend (120 linhas)

`src/components/imports/DownloadPdfButton.tsx`:
- Aceita `jobId`, opcional `available` e `unavailableReason`
- Chama `Imports.getPdfUrl` → `supabase.storage.from(bucket).createSignedUrl(path, 86400, { download: file_name })`
- Abre signed URL em nova aba (download disparado pelo header)
- Estados: loading, erro inline com mensagem amigável para `pdf_not_stored` / `pdf_purged`
- Integrado no header de `/pessoas/importar/[jobId]`

Adapter `R2.Imports`:
- `getPdfUrl(jobId)` → `{ bucket, path, expires_in, file_name, file_size, uploaded_at }`
- `cleanupExpired()` → `{ purged_count, paths }`

## Validação

```bash
# Backend
psql -f supabase/tests/00320_e5_pdf_storage.sql  # 16/16 PASS

# Regressão completa
psql -f supabase/tests/00300_e1_employees.sql   # 30/30
psql -f supabase/tests/00302_e2_check_cpf.sql   #  6/6
psql -f supabase/tests/00310_e4_import_jobs.sql # 20/20
psql -f supabase/tests/00320_e5_pdf_storage.sql # 16/16
# Total: 72/72 PASS

# Frontend
tsc --noEmit --strict
# exit 0 · zero erros

# Worker
python3 -c "import ast; ast.parse(open('worker/worker.py').read())"
# OK
```

## Housekeeping (produção)

Em ambiente real, agendar com `pg_cron`:

```sql
SELECT cron.schedule(
  'r2-import-pdf-cleanup',
  '0 3 * * *',  -- 03:00 todo dia
  $$ SELECT rpc_import_jobs_cleanup_expired() $$
);
```

Ou rodar manual via uma rota admin chamando `Imports.cleanupExpired()`.

A view `import_pdfs_stats` permite monitorar:
- `pdfs_em_storage` · quantos PDFs ativos (não purgados)
- `pdfs_apagados` · total já purgados
- `pdfs_elegiveis_purge` · prontos para próximo cleanup
- `bytes_em_storage` · footprint atual

## Próximos passos

- **E6** · Preview do PDF na tela de revisão (usar a mesma signed URL, exibir página por página com pdf.js, lado a lado com os campos extraídos)
- **E7** · Fallback Vision LLM em items com confidence <50% · baixa página do PDF via signed URL e re-extrai
- **D1** · Supabase Auth real (worker autenticando com service_role em vez de anon+token, embora token continue válido como reforço)

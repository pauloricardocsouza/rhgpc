-- ============================================================================
-- R2 People · Sessao E5 · Storage de PDFs originais
-- ============================================================================
-- Adiciona suporte para preservar o PDF de origem dos jobs de OCR.
--
-- Estrategia:
--   - Worker faz upload do PDF para o bucket `import-pdfs` apos processar
--   - Path: tenant_id/job_id/original.pdf
--   - Job armazena o storage_path para gerar signed URLs
--   - Retencao: 30 dias apos archive · housekeeping function apaga do Storage
--
-- Decisoes:
--   - Bucket privado (signed URLs com 24h de validade)
--   - Path inclui tenant_id no prefixo para policy de Storage funcionar
--   - storage_path nullable: jobs antigos (pre-E5) ou que falharam no upload
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. Bucket import-pdfs
-- ----------------------------------------------------------------------------

INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'import-pdfs',
  'import-pdfs',
  FALSE,                            -- privado
  314572800,                        -- 300 MB · suficiente para PDFs grandes do Dominio
  ARRAY['application/pdf']
)
ON CONFLICT (id) DO NOTHING;

-- ----------------------------------------------------------------------------
-- 2. Colunas em import_jobs
-- ----------------------------------------------------------------------------

ALTER TABLE import_jobs
  ADD COLUMN IF NOT EXISTS storage_path TEXT,
  ADD COLUMN IF NOT EXISTS pdf_uploaded_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS pdf_purged_at TIMESTAMPTZ;

COMMENT ON COLUMN import_jobs.storage_path IS
  'Path no bucket import-pdfs · formato tenant_id/job_id/original.pdf · NULL se nao foi salvo';
COMMENT ON COLUMN import_jobs.pdf_uploaded_at IS
  'Quando o worker terminou de subir o PDF para o Storage';
COMMENT ON COLUMN import_jobs.pdf_purged_at IS
  'Quando o housekeeping apagou o PDF do Storage (apos 30d de archive)';

-- Indice para o job de retencao (acha jobs archivados ha mais de 30 dias e ainda com PDF)
CREATE INDEX IF NOT EXISTS idx_import_jobs_purge_candidates
  ON import_jobs(archived_at)
  WHERE storage_path IS NOT NULL AND pdf_purged_at IS NULL AND archived_at IS NOT NULL;

-- ----------------------------------------------------------------------------
-- 3. RLS no bucket
-- ----------------------------------------------------------------------------
-- Policies sao gerenciadas em storage.objects. Padrao:
--   - SELECT: usuario do tenant pode ver objetos cujo primeiro segmento do path
--     bate com o tenant_id
--   - INSERT/UPDATE/DELETE: apenas via service_role (worker autenticado por token)
--
-- Em Supabase real, a coluna name e o caminho completo no bucket.
-- ----------------------------------------------------------------------------

-- Limpa policies existentes pra ser idempotente
DROP POLICY IF EXISTS "import_pdfs_read_tenant" ON storage.objects;
DROP POLICY IF EXISTS "import_pdfs_write_none" ON storage.objects;

-- Leitura: somente usuarios do mesmo tenant (e RH/diretoria, validado adiante na RPC)
-- O proprio frontend nao baixa direto · vai pela RPC que gera signed URL com auth
-- Mas se houver acesso direto via supabase-js, restringe por tenant.
CREATE POLICY "import_pdfs_read_tenant" ON storage.objects
  FOR SELECT
  USING (
    bucket_id = 'import-pdfs'
    AND (
      is_super_admin()
      OR (
        -- Primeiro segmento do path = tenant_id
        (storage.foldername(name))[1] = current_tenant_id()::TEXT
      )
    )
  );

-- Nenhuma policy de INSERT/UPDATE/DELETE para usuario regular.
-- Worker usa service_role (em Supabase real) ou anon + token (no nosso setup).
-- Aqui nao criamos policy permissiva: writes vao via RPC com SECURITY DEFINER.

-- ----------------------------------------------------------------------------
-- 4. View auxiliar · stats de Storage
-- ----------------------------------------------------------------------------

CREATE OR REPLACE VIEW import_pdfs_stats AS
SELECT
  COUNT(*) FILTER (WHERE storage_path IS NOT NULL AND pdf_purged_at IS NULL) AS pdfs_em_storage,
  COUNT(*) FILTER (WHERE pdf_purged_at IS NOT NULL) AS pdfs_apagados,
  COUNT(*) FILTER (
    WHERE storage_path IS NOT NULL
      AND pdf_purged_at IS NULL
      AND archived_at IS NOT NULL
      AND archived_at < now() - INTERVAL '30 days'
  ) AS pdfs_elegiveis_purge,
  SUM(source_file_size) FILTER (WHERE storage_path IS NOT NULL AND pdf_purged_at IS NULL) AS bytes_em_storage
FROM import_jobs;

GRANT SELECT ON import_pdfs_stats TO authenticated;

COMMENT ON VIEW import_pdfs_stats IS
  'Sessao E5 · estatisticas de uso do bucket import-pdfs · usado em dashboards de admin';

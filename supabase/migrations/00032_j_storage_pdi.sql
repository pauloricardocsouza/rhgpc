-- ============================================================================
-- R2 People · Storage PDI v1
-- ============================================================================
-- Cria o bucket Supabase Storage para evidencias de acoes do PDI e suas policies.
--
-- Pre-requisito: r2_people_schema_pdi_v1.sql aplicado
--
-- IMPORTANTE: este script depende do schema 'storage' do Supabase
-- (criado automaticamente em projetos Supabase). Em PostgreSQL standalone
-- nao funciona · use apenas no Dashboard do Supabase.
--
-- Convencao de path: {tenant_id}/{pdi_id}/{action_id}/{filename}
-- Exemplo: 00000000-...-A000.../pdi-001/action-007/certificado.pdf
-- ============================================================================

-- ============================================================================
-- BUCKET
-- ============================================================================

INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'pdi-evidence',
  'pdi-evidence',
  FALSE,                              -- privado · nao acessivel sem auth
  10485760,                           -- 10 MB por arquivo
  ARRAY[
    'application/pdf',
    'image/png', 'image/jpeg', 'image/webp',
    'application/vnd.openxmlformats-officedocument.wordprocessingml.document', -- docx
    'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',      -- xlsx
    'application/vnd.openxmlformats-officedocument.presentationml.presentation', -- pptx
    'text/plain', 'text/csv'
  ]
)
ON CONFLICT (id) DO UPDATE SET
  public = EXCLUDED.public,
  file_size_limit = EXCLUDED.file_size_limit,
  allowed_mime_types = EXCLUDED.allowed_mime_types;

-- ============================================================================
-- POLICIES
-- ============================================================================
-- O acesso ao bucket e controlado via storage.objects.
-- Path esperado: '{tenant_id}/{pdi_id}/{action_id}/{filename}'
-- A primeira pasta e o tenant_id · usamos isso para isolamento.

-- ===== READ =====
-- Quem pode ler o PDI pode baixar evidencias dele
DROP POLICY IF EXISTS pdi_evidence_read ON storage.objects;
CREATE POLICY pdi_evidence_read ON storage.objects
  FOR SELECT
  USING (
    bucket_id = 'pdi-evidence'
    AND (
      -- Path: tenant_id/pdi_id/...
      -- A primeira pasta e o tenant
      (storage.foldername(name))[1] = current_tenant_id()::TEXT
      -- E a segunda pasta e um pdi que o caller pode ler
      AND pdi_can_read(((storage.foldername(name))[2])::UUID) = TRUE
    )
  );

-- ===== INSERT (upload) =====
-- Owner do PDI ou manager ou RH/Dir podem fazer upload
DROP POLICY IF EXISTS pdi_evidence_insert ON storage.objects;
CREATE POLICY pdi_evidence_insert ON storage.objects
  FOR INSERT
  WITH CHECK (
    bucket_id = 'pdi-evidence'
    AND (storage.foldername(name))[1] = current_tenant_id()::TEXT
    AND EXISTS (
      SELECT 1 FROM pdis p
      WHERE p.id = ((storage.foldername(name))[2])::UUID
        AND p.tenant_id = current_tenant_id()
        AND p.status NOT IN ('completed', 'canceled')
        AND (
          p.user_id = current_user_id()
          OR user_is_manager_of(p.user_id) = TRUE
          OR current_user_role() IN ('rh', 'diretoria')
        )
    )
  );

-- ===== UPDATE (replace) =====
-- Mesmas regras do insert
DROP POLICY IF EXISTS pdi_evidence_update ON storage.objects;
CREATE POLICY pdi_evidence_update ON storage.objects
  FOR UPDATE
  USING (
    bucket_id = 'pdi-evidence'
    AND (storage.foldername(name))[1] = current_tenant_id()::TEXT
    AND EXISTS (
      SELECT 1 FROM pdis p
      WHERE p.id = ((storage.foldername(name))[2])::UUID
        AND p.tenant_id = current_tenant_id()
        AND p.status NOT IN ('completed', 'canceled')
        AND (
          p.user_id = current_user_id()
          OR user_is_manager_of(p.user_id) = TRUE
          OR current_user_role() IN ('rh', 'diretoria')
        )
    )
  );

-- ===== DELETE =====
-- Owner do PDI, manager ou RH/Dir
DROP POLICY IF EXISTS pdi_evidence_delete ON storage.objects;
CREATE POLICY pdi_evidence_delete ON storage.objects
  FOR DELETE
  USING (
    bucket_id = 'pdi-evidence'
    AND (storage.foldername(name))[1] = current_tenant_id()::TEXT
    AND EXISTS (
      SELECT 1 FROM pdis p
      WHERE p.id = ((storage.foldername(name))[2])::UUID
        AND p.tenant_id = current_tenant_id()
        AND p.status NOT IN ('completed', 'canceled')
        AND (
          p.user_id = current_user_id()
          OR user_is_manager_of(p.user_id) = TRUE
          OR current_user_role() IN ('rh', 'diretoria')
        )
    )
  );

-- ============================================================================
-- COMENTARIOS
-- ============================================================================

COMMENT ON POLICY pdi_evidence_read ON storage.objects IS
  'PDI Evidence: leitura herda regras de pdi_can_read · path = tenant_id/pdi_id/...';

COMMENT ON POLICY pdi_evidence_insert ON storage.objects IS
  'PDI Evidence: upload por owner/manager/RH/Dir · so em PDIs nao concluidos/cancelados';

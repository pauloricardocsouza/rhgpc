-- ============================================================================
-- R2 People · Sessao E4 · Schema de staging para OCR de fichas
-- ============================================================================
-- Permite que um worker externo (Python + tesseract) suba os resultados
-- da extracao OCR e o RH revise lote a lote antes de promover para `employees`.
--
-- Tabelas:
--   import_jobs       · 1 linha por upload (PDF do Dominio) com status do lote
--   import_job_items  · 1 linha por ficha extraida com payload parseado e status
--
-- Estados do job:
--   pending   · upload feito, worker ainda nao processou
--   running   · worker processando paginas
--   completed · todas extraidas com sucesso (mas ainda pendente revisao)
--   failed    · worker travou ou abortou
--   reviewing · RH abriu a revisao (visual cue)
--   archived  · revisao concluida, todas as fichas aprovadas/descartadas
--
-- Estados do item:
--   pending   · extracao OK, aguardando aprovacao do RH
--   approved  · RH aprovou e item virou linha em `employees` (employee_id setado)
--   rejected  · RH descartou a ficha
--   duplicate · CPF ja existia em `employees` no momento do approve · linkado
--   edited    · RH editou antes de aprovar (registrado em audit)
-- ============================================================================

-- ----------------------------------------------------------------------------
-- ENUMS
-- ----------------------------------------------------------------------------

DO $$ BEGIN
  CREATE TYPE import_job_status AS ENUM (
    'pending', 'running', 'completed', 'failed', 'reviewing', 'archived'
  );
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  CREATE TYPE import_item_status AS ENUM (
    'pending', 'approved', 'rejected', 'duplicate', 'edited'
  );
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- ----------------------------------------------------------------------------
-- TABELA · import_jobs
-- ----------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS import_jobs (
  id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id           UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  uploaded_by         UUID REFERENCES app_users(id) ON DELETE SET NULL,
  source_file_name    TEXT NOT NULL,
  source_file_size    BIGINT,
  source_pages_total  INT,
  status              import_job_status NOT NULL DEFAULT 'pending',

  -- Progresso live
  pages_processed     INT NOT NULL DEFAULT 0,
  pages_failed        INT NOT NULL DEFAULT 0,
  items_total         INT NOT NULL DEFAULT 0,
  items_approved      INT NOT NULL DEFAULT 0,
  items_rejected      INT NOT NULL DEFAULT 0,
  items_duplicates    INT NOT NULL DEFAULT 0,

  -- Erros agregados (lista de mensagens do worker)
  error_log           JSONB DEFAULT '[]'::JSONB,

  created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
  started_at          TIMESTAMPTZ,
  completed_at        TIMESTAMPTZ,
  archived_at         TIMESTAMPTZ,

  -- Token compartilhado entre worker e backend para autorizar updates
  -- (worker nao tem auth user, usa esse token via secret header)
  worker_token        TEXT NOT NULL DEFAULT encode(gen_random_bytes(24), 'hex')
);

CREATE INDEX IF NOT EXISTS idx_import_jobs_tenant_status
  ON import_jobs(tenant_id, status);

CREATE INDEX IF NOT EXISTS idx_import_jobs_uploaded_by
  ON import_jobs(uploaded_by, created_at DESC);

COMMENT ON TABLE import_jobs IS 'Sessao E4 · 1 linha por upload de PDF para OCR · staging antes de virar employees';
COMMENT ON COLUMN import_jobs.worker_token IS 'Token unico do job · permite worker externo atualizar progresso sem auth de usuario';

-- ----------------------------------------------------------------------------
-- TABELA · import_job_items
-- ----------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS import_job_items (
  id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  job_id              UUID NOT NULL REFERENCES import_jobs(id) ON DELETE CASCADE,
  tenant_id           UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  page_number         INT NOT NULL,                  -- pagina(s) do PDF de origem
  status              import_item_status NOT NULL DEFAULT 'pending',

  -- Payload parseado · espelha EmployeePayload com TODOS os campos opcionais
  parsed_payload      JSONB NOT NULL,

  -- Resumo para listagem rapida (sem precisar parsear o JSON)
  full_name           TEXT,
  cpf                 TEXT,
  matricula_esocial   TEXT,
  job_title           TEXT,
  hire_date           DATE,
  termination_date    DATE,

  -- Alertas extraidos do parser (rg_vazio, cpf_invalido, etc.)
  parser_alerts       JSONB DEFAULT '[]'::JSONB,

  -- Score de confianca (0-100) calculado pelo worker
  -- pondera campos preenchidos vs alertas
  confidence_score    SMALLINT,

  -- Linkagem apos aprovacao
  approved_at         TIMESTAMPTZ,
  approved_by         UUID REFERENCES app_users(id) ON DELETE SET NULL,
  approved_payload    JSONB,  -- snapshot do payload na hora de aprovar (pode ter sido editado)
  employee_id         UUID REFERENCES employees(id) ON DELETE SET NULL,
  duplicate_of        UUID REFERENCES employees(id) ON DELETE SET NULL,

  rejected_at         TIMESTAMPTZ,
  rejected_by         UUID REFERENCES app_users(id) ON DELETE SET NULL,
  rejection_reason    TEXT,

  created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at          TIMESTAMPTZ NOT NULL DEFAULT now(),

  CONSTRAINT chk_one_decision CHECK (
    -- Item nao pode estar aprovado E rejeitado ao mesmo tempo
    NOT (approved_at IS NOT NULL AND rejected_at IS NOT NULL)
  )
);

CREATE INDEX IF NOT EXISTS idx_import_items_job_status
  ON import_job_items(job_id, status);

CREATE INDEX IF NOT EXISTS idx_import_items_cpf
  ON import_job_items(tenant_id, cpf) WHERE cpf IS NOT NULL;

-- Trigger updated_at
CREATE OR REPLACE FUNCTION import_items_set_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at := now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_import_items_updated_at ON import_job_items;
CREATE TRIGGER trg_import_items_updated_at
  BEFORE UPDATE ON import_job_items
  FOR EACH ROW
  EXECUTE FUNCTION import_items_set_updated_at();

-- Audit
DROP TRIGGER IF EXISTS trg_import_jobs_audit ON import_jobs;
CREATE TRIGGER trg_import_jobs_audit
  AFTER INSERT OR UPDATE OR DELETE ON import_jobs
  FOR EACH ROW EXECUTE FUNCTION audit_change();

DROP TRIGGER IF EXISTS trg_import_items_audit ON import_job_items;
CREATE TRIGGER trg_import_items_audit
  AFTER INSERT OR UPDATE OR DELETE ON import_job_items
  FOR EACH ROW EXECUTE FUNCTION audit_change();

-- ----------------------------------------------------------------------------
-- RLS
-- ----------------------------------------------------------------------------

ALTER TABLE import_jobs       ENABLE ROW LEVEL SECURITY;
ALTER TABLE import_job_items  ENABLE ROW LEVEL SECURITY;

-- Read: tenant inteiro pode ver (para o uploader e RH revisarem)
DROP POLICY IF EXISTS import_jobs_read ON import_jobs;
CREATE POLICY import_jobs_read ON import_jobs
  FOR SELECT
  USING (is_super_admin() OR tenant_id = current_tenant_id());

DROP POLICY IF EXISTS import_jobs_write ON import_jobs;
CREATE POLICY import_jobs_write ON import_jobs
  FOR ALL
  USING (
    is_super_admin()
    OR (
      tenant_id = current_tenant_id()
      AND EXISTS (
        SELECT 1 FROM app_users u
        WHERE u.id = current_user_id() AND u.role IN ('diretoria', 'rh')
      )
    )
  )
  WITH CHECK (
    is_super_admin()
    OR (
      tenant_id = current_tenant_id()
      AND EXISTS (
        SELECT 1 FROM app_users u
        WHERE u.id = current_user_id() AND u.role IN ('diretoria', 'rh')
      )
    )
  );

DROP POLICY IF EXISTS import_items_read ON import_job_items;
CREATE POLICY import_items_read ON import_job_items
  FOR SELECT
  USING (is_super_admin() OR tenant_id = current_tenant_id());

DROP POLICY IF EXISTS import_items_write ON import_job_items;
CREATE POLICY import_items_write ON import_job_items
  FOR ALL
  USING (
    is_super_admin()
    OR (
      tenant_id = current_tenant_id()
      AND EXISTS (
        SELECT 1 FROM app_users u
        WHERE u.id = current_user_id() AND u.role IN ('diretoria', 'rh')
      )
    )
  )
  WITH CHECK (
    is_super_admin()
    OR (
      tenant_id = current_tenant_id()
      AND EXISTS (
        SELECT 1 FROM app_users u
        WHERE u.id = current_user_id() AND u.role IN ('diretoria', 'rh')
      )
    )
  );

GRANT SELECT, INSERT, UPDATE, DELETE ON import_jobs, import_job_items TO authenticated;

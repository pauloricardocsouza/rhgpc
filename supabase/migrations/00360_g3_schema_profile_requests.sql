-- ============================================================================
-- R2 People · Sessao G3 · Solicitacoes de alteracao de dados pessoais
-- ============================================================================
-- Workflow:
--   1. Colaborador cria uma solicitacao para mudar 1 campo da propria ficha
--      (telefone, email pessoal, endereco, contato de emergencia, foto)
--   2. Solicitacao fica pending; RH/diretoria/super_admin podem aprovar ou
--      rejeitar
--   3. Quando aprovada: o valor e copiado para employees + audit log
--   4. Quando rejeitada: razao obrigatoria
--
-- Storage:
--   - Bucket privado 'employee-photos' para fotos pendentes/aprovadas
--   - Path: <tenant_id>/<employee_id>/<request_id>.jpg
-- ============================================================================

-- ============================================================================
-- Colunas novas em employees (faltavam)
-- ============================================================================
ALTER TABLE employees ADD COLUMN IF NOT EXISTS personal_email     TEXT;
ALTER TABLE employees ADD COLUMN IF NOT EXISTS emergency_contact_name      TEXT;
ALTER TABLE employees ADD COLUMN IF NOT EXISTS emergency_contact_phone     TEXT;
ALTER TABLE employees ADD COLUMN IF NOT EXISTS emergency_contact_relation  TEXT;
ALTER TABLE employees ADD COLUMN IF NOT EXISTS photo_storage_path          TEXT;

-- ============================================================================
-- Enums
-- ============================================================================
DO $$ BEGIN
  CREATE TYPE profile_change_field AS ENUM (
    'phone_mobile',
    'phone_home',
    'personal_email',
    'residence_address',
    'emergency_contact',
    'photo'
  );
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  CREATE TYPE profile_change_status AS ENUM (
    'pending',
    'approved',
    'rejected',
    'canceled'
  );
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- ============================================================================
-- Tabela de solicitacoes
-- ============================================================================
CREATE TABLE IF NOT EXISTS employee_profile_change_requests (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id       UUID NOT NULL REFERENCES tenants(id),
  employee_id     UUID NOT NULL REFERENCES employees(id),
  requested_by    UUID NOT NULL REFERENCES app_users(id),
  field           profile_change_field NOT NULL,

  -- old_value e new_value sao JSONB para suportar campos compostos (endereco,
  -- contato de emergencia). Campos simples viram {"value": "..."}.
  old_value       JSONB,
  new_value       JSONB NOT NULL,

  -- Para field='photo': caminho no storage do arquivo pendente
  pending_photo_path TEXT,

  status          profile_change_status NOT NULL DEFAULT 'pending',
  reviewed_by     UUID REFERENCES app_users(id),
  reviewed_at     TIMESTAMPTZ,
  rejection_reason TEXT,

  created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Apenas 1 solicitacao pendente por colaborador+campo
-- (UNIQUE constraint normal nao funciona porque mesmas chaves resolvidas
--  podem coexistir; usamos partial index unico para a janela pending)
CREATE UNIQUE INDEX IF NOT EXISTS uq_pcr_one_pending_per_field
  ON employee_profile_change_requests (employee_id, field)
  WHERE status = 'pending';

CREATE INDEX IF NOT EXISTS idx_pcr_pending_by_tenant
  ON employee_profile_change_requests (tenant_id, status, created_at DESC)
  WHERE status = 'pending';

CREATE INDEX IF NOT EXISTS idx_pcr_by_employee
  ON employee_profile_change_requests (employee_id, created_at DESC);

-- ============================================================================
-- Bucket 'employee-photos' (idempotente)
-- Storage real seria criado via supabase CLI / dashboard;
-- a tabela storage.buckets pode nao existir em ambiente local.
-- ============================================================================
DO $$ BEGIN
  INSERT INTO storage.buckets (id, name, public)
  VALUES ('employee-photos', 'employee-photos', FALSE)
  ON CONFLICT (id) DO NOTHING;
EXCEPTION WHEN undefined_table OR invalid_schema_name THEN
  -- Ambiente local sem schema storage; ignora silenciosamente
  NULL;
END $$;

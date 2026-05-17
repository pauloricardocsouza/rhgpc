-- ============================================================================
-- R2 People · Sessao E1 · Schema Employees (Ficha de Empregado)
-- ============================================================================
-- Adiciona tabela `employees` com todos os campos da ficha Domínio,
-- mais 3 tabelas filhas para histórico salarial, férias e afastamentos.
--
-- IMPORTANTE: tabela separada de `app_users`. Um colaborador da ficha pode
-- ainda não ter conta de acesso ao R2 People; um app_user pode ser um usuário
-- externo (super_admin da R2) que não tem ficha de empregado. Liga-se via
-- `employee_id` opcional em app_users (FK adicionada no fim).
--
-- Decisoes:
--   - PK = UUID interno · matricula_esocial e cpf sao únicos por tenant
--   - Soft-delete via `archived_at` (não usar DELETE direto)
--   - Cidade/UF de naturalidade em colunas separadas para queries futuras
--   - Telefones normalizados sem máscara (só dígitos)
--   - Endereço como text livre + CEP (geocoding fica para sessão futura)
--   - Rescisão como sub-objeto: data_saida + tipo + motivo
--
-- Idempotente. Pre-requisitos: schemas H, L aplicados.
-- ============================================================================

-- ============================================================================
-- 1. ENUMS
-- ============================================================================

DO $$ BEGIN
  CREATE TYPE marital_status AS ENUM (
    'solteiro', 'casado', 'divorciado', 'viuvo', 'separado', 'uniao_estavel', 'nao_informado'
  );
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  CREATE TYPE race_color AS ENUM (
    'branca', 'preta', 'parda', 'amarela', 'indigena', 'nao_informada'
  );
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  CREATE TYPE education_level AS ENUM (
    'analfabeto',
    'fundamental_1_5_incompleto',
    'fundamental_1_5_completo',
    'fundamental_6_9_incompleto',
    'fundamental_6_9_completo',
    'medio_incompleto',
    'medio_completo',
    'superior_incompleto',
    'superior_completo',
    'pos_graduacao',
    'mestrado',
    'doutorado',
    'nao_informado'
  );
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  CREATE TYPE salary_unit AS ENUM ('mes', 'hora', 'dia', 'semana', 'quinzena');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  CREATE TYPE dismissal_type AS ENUM (
    'demitido_sem_justa_causa',
    'demitido_com_justa_causa',
    'pedido_demissao',
    'rescisao_indireta',
    'termino_contrato_experiencia',
    'termino_contrato_determinado',
    'aposentadoria',
    'falecimento',
    'rescisao_acordo',
    'rescisao_antecipada_contrato',
    'outro'
  );
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  CREATE TYPE leave_reason AS ENUM (
    'acidente_trabalho', 'doenca_comum', 'doenca_ocupacional', 'auxilio_maternidade',
    'auxilio_paternidade', 'servico_militar', 'outro'
  );
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  CREATE TYPE vacation_kind AS ENUM ('aquisitivo', 'gozo', 'abono_pecuniario');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  CREATE TYPE employee_sex AS ENUM ('masculino', 'feminino', 'nao_informado');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- ============================================================================
-- 2. TABELA · employees
-- ============================================================================

CREATE TABLE IF NOT EXISTS employees (
  id                    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id             UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  employer_unit_id      UUID REFERENCES employer_units(id) ON DELETE SET NULL,
  working_unit_id       UUID REFERENCES working_units(id) ON DELETE SET NULL,
  department_id         UUID REFERENCES departments(id) ON DELETE SET NULL,

  -- Identificacao primaria
  matricula_esocial     VARCHAR(40),
  ficha_numero          VARCHAR(20),
  full_name             TEXT NOT NULL,
  beneficiaries         TEXT,

  -- Documentos
  cpf                   VARCHAR(14),
  rg                    VARCHAR(30),
  rg_issue_date         DATE,
  rg_issuer             VARCHAR(20),
  voter_id              VARCHAR(20),
  voter_zone            VARCHAR(10),
  voter_section         VARCHAR(10),
  ctps_number           VARCHAR(30),
  ctps_serie            VARCHAR(15),
  ctps_issue_date       DATE,
  ctps_uf               CHAR(2),
  pis                   VARCHAR(20),
  military_doc          VARCHAR(40),
  cnh                   VARCHAR(20),
  cnh_category          VARCHAR(5),

  -- Pessoal
  birth_date            DATE,
  birth_city            VARCHAR(80),
  birth_state           CHAR(2),
  nationality           VARCHAR(40) DEFAULT 'BRASIL',
  marital_status        marital_status DEFAULT 'nao_informado',
  sex                   employee_sex DEFAULT 'nao_informado',
  race_color            race_color DEFAULT 'nao_informada',
  education             education_level DEFAULT 'nao_informado',
  has_disability        BOOLEAN DEFAULT FALSE,
  disability_description TEXT,
  father_name           TEXT,
  mother_name           TEXT,

  -- Contato e residencia
  residence_address     TEXT,
  residence_cep         VARCHAR(9),
  phone_home            VARCHAR(20),
  phone_mobile          VARCHAR(20),
  email                 VARCHAR(255),

  -- Vinculo / cargo
  job_title             VARCHAR(120) NOT NULL,
  job_function          VARCHAR(120),
  cbo                   VARCHAR(10),
  hire_date             DATE NOT NULL,
  initial_salary        NUMERIC(12,2),
  salary_unit           salary_unit DEFAULT 'mes',
  work_schedule_start   TIME,
  work_schedule_end     TIME,
  break_start           TIME,
  break_end             TIME,
  fgts_opt_in_date      DATE,
  bank_account          VARCHAR(60),

  -- Rescisao
  termination_date      DATE,
  termination_type      dismissal_type,
  termination_reason    TEXT,

  -- Meta
  created_at            TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at            TIMESTAMPTZ NOT NULL DEFAULT now(),
  archived_at           TIMESTAMPTZ,  -- soft-delete
  created_by            UUID REFERENCES app_users(id) ON DELETE SET NULL,
  updated_by            UUID REFERENCES app_users(id) ON DELETE SET NULL,
  source                VARCHAR(40) DEFAULT 'manual'  -- 'manual' | 'xlsx_import' | 'pdf_ocr'
);

-- Unicidade por tenant
CREATE UNIQUE INDEX IF NOT EXISTS uq_employees_cpf_tenant
  ON employees(tenant_id, cpf) WHERE cpf IS NOT NULL AND archived_at IS NULL;

CREATE UNIQUE INDEX IF NOT EXISTS uq_employees_matricula_tenant
  ON employees(tenant_id, matricula_esocial) WHERE matricula_esocial IS NOT NULL AND archived_at IS NULL;

-- Indices de busca
CREATE INDEX IF NOT EXISTS idx_employees_tenant_active
  ON employees(tenant_id) WHERE archived_at IS NULL;

CREATE INDEX IF NOT EXISTS idx_employees_tenant_termination
  ON employees(tenant_id, termination_date) WHERE archived_at IS NULL;

CREATE INDEX IF NOT EXISTS idx_employees_employer_unit
  ON employees(employer_unit_id) WHERE archived_at IS NULL;

CREATE INDEX IF NOT EXISTS idx_employees_working_unit
  ON employees(working_unit_id) WHERE archived_at IS NULL;

-- Extensao trgm para busca por nome (similar a "ILIKE %x%")
CREATE EXTENSION IF NOT EXISTS pg_trgm;

CREATE INDEX IF NOT EXISTS idx_employees_full_name_trgm
  ON employees USING gin (lower(full_name) gin_trgm_ops);

COMMENT ON TABLE employees IS 'Sessao E1 · Ficha de empregado · espelha o Registro de Empregado do Dominio';
COMMENT ON COLUMN employees.source IS 'Origem do registro · manual, xlsx_import, pdf_ocr';

-- ============================================================================
-- 3. TABELAS FILHAS
-- ============================================================================

-- Historico salarial
CREATE TABLE IF NOT EXISTS employee_salary_history (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  employee_id       UUID NOT NULL REFERENCES employees(id) ON DELETE CASCADE,
  tenant_id         UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  effective_date    DATE NOT NULL,
  amount            NUMERIC(12,2) NOT NULL,
  unit              salary_unit NOT NULL DEFAULT 'mes',
  job_title         VARCHAR(120),
  job_function      VARCHAR(120),
  cbo               VARCHAR(10),
  change_type       VARCHAR(40) DEFAULT 'adjustment',  -- adjustment, promotion, dissidio, initial
  observations      TEXT,
  created_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
  created_by        UUID REFERENCES app_users(id) ON DELETE SET NULL
);

CREATE INDEX IF NOT EXISTS idx_salary_history_employee
  ON employee_salary_history(employee_id, effective_date DESC);

COMMENT ON TABLE employee_salary_history IS 'Sessao E1 · historico cronologico de salarios e mudancas de cargo';

-- Ferias
CREATE TABLE IF NOT EXISTS employee_vacations (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  employee_id       UUID NOT NULL REFERENCES employees(id) ON DELETE CASCADE,
  tenant_id         UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  kind              vacation_kind NOT NULL,
  start_date        DATE NOT NULL,
  end_date          DATE NOT NULL,
  paid_on_termination BOOLEAN DEFAULT FALSE,
  observations      TEXT,
  created_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
  created_by        UUID REFERENCES app_users(id) ON DELETE SET NULL,

  CONSTRAINT chk_vacation_dates CHECK (end_date >= start_date)
);

CREATE INDEX IF NOT EXISTS idx_vacations_employee
  ON employee_vacations(employee_id, start_date DESC);

-- Afastamentos
CREATE TABLE IF NOT EXISTS employee_leaves (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  employee_id       UUID NOT NULL REFERENCES employees(id) ON DELETE CASCADE,
  tenant_id         UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  start_date        DATE NOT NULL,
  end_date          DATE,                       -- NULL = ainda afastado
  reason            leave_reason NOT NULL DEFAULT 'doenca_comum',
  description       TEXT,
  cid               VARCHAR(10),                -- CID-10
  inss_benefit      VARCHAR(40),                -- numero do beneficio se houver
  created_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
  created_by        UUID REFERENCES app_users(id) ON DELETE SET NULL,

  CONSTRAINT chk_leave_dates CHECK (end_date IS NULL OR end_date >= start_date)
);

CREATE INDEX IF NOT EXISTS idx_leaves_employee
  ON employee_leaves(employee_id, start_date DESC);

CREATE INDEX IF NOT EXISTS idx_leaves_ongoing
  ON employee_leaves(employee_id) WHERE end_date IS NULL;

-- ============================================================================
-- 4. TRIGGER updated_at + audit
-- ============================================================================

CREATE OR REPLACE FUNCTION employees_set_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at := now();
  NEW.updated_by := COALESCE(current_user_id(), OLD.updated_by);
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_employees_updated_at ON employees;
CREATE TRIGGER trg_employees_updated_at
  BEFORE UPDATE ON employees
  FOR EACH ROW
  EXECUTE FUNCTION employees_set_updated_at();

-- Audit log de mudancas em employees usando o helper generico
DROP TRIGGER IF EXISTS trg_employees_audit ON employees;
CREATE TRIGGER trg_employees_audit
  AFTER INSERT OR UPDATE OR DELETE ON employees
  FOR EACH ROW
  EXECUTE FUNCTION audit_change();

DROP TRIGGER IF EXISTS trg_salary_history_audit ON employee_salary_history;
CREATE TRIGGER trg_salary_history_audit
  AFTER INSERT OR UPDATE OR DELETE ON employee_salary_history
  FOR EACH ROW
  EXECUTE FUNCTION audit_change();

DROP TRIGGER IF EXISTS trg_vacations_audit ON employee_vacations;
CREATE TRIGGER trg_vacations_audit
  AFTER INSERT OR UPDATE OR DELETE ON employee_vacations
  FOR EACH ROW
  EXECUTE FUNCTION audit_change();

DROP TRIGGER IF EXISTS trg_leaves_audit ON employee_leaves;
CREATE TRIGGER trg_leaves_audit
  AFTER INSERT OR UPDATE OR DELETE ON employee_leaves
  FOR EACH ROW
  EXECUTE FUNCTION audit_change();

-- ============================================================================
-- 5. RLS · acesso por tenant + papel
-- ============================================================================

ALTER TABLE employees                   ENABLE ROW LEVEL SECURITY;
ALTER TABLE employee_salary_history     ENABLE ROW LEVEL SECURITY;
ALTER TABLE employee_vacations          ENABLE ROW LEVEL SECURITY;
ALTER TABLE employee_leaves             ENABLE ROW LEVEL SECURITY;

-- Leitura: super_admin tudo, demais apenas no proprio tenant
DROP POLICY IF EXISTS employees_read ON employees;
CREATE POLICY employees_read ON employees
  FOR SELECT
  USING (
    is_super_admin()
    OR tenant_id = current_tenant_id()
  );

-- Escrita: super_admin, diretoria e RH (todos no proprio tenant)
DROP POLICY IF EXISTS employees_write ON employees;
CREATE POLICY employees_write ON employees
  FOR ALL
  USING (
    is_super_admin()
    OR (
      tenant_id = current_tenant_id()
      AND EXISTS (
        SELECT 1 FROM app_users u
        WHERE u.id = current_user_id() AND u.role IN ('diretoria','rh')
      )
    )
  )
  WITH CHECK (
    is_super_admin()
    OR (
      tenant_id = current_tenant_id()
      AND EXISTS (
        SELECT 1 FROM app_users u
        WHERE u.id = current_user_id() AND u.role IN ('diretoria','rh')
      )
    )
  );

-- Mesmo padrao para tabelas filhas
DROP POLICY IF EXISTS salary_history_read ON employee_salary_history;
CREATE POLICY salary_history_read ON employee_salary_history
  FOR SELECT
  USING (
    is_super_admin()
    OR tenant_id = current_tenant_id()
  );

DROP POLICY IF EXISTS salary_history_write ON employee_salary_history;
CREATE POLICY salary_history_write ON employee_salary_history
  FOR ALL
  USING (
    is_super_admin()
    OR (
      tenant_id = current_tenant_id()
      AND EXISTS (
        SELECT 1 FROM app_users u
        WHERE u.id = current_user_id() AND u.role IN ('diretoria','rh')
      )
    )
  )
  WITH CHECK (
    is_super_admin()
    OR (
      tenant_id = current_tenant_id()
      AND EXISTS (
        SELECT 1 FROM app_users u
        WHERE u.id = current_user_id() AND u.role IN ('diretoria','rh')
      )
    )
  );

DROP POLICY IF EXISTS vacations_read ON employee_vacations;
CREATE POLICY vacations_read ON employee_vacations
  FOR SELECT
  USING (
    is_super_admin()
    OR tenant_id = current_tenant_id()
  );

DROP POLICY IF EXISTS vacations_write ON employee_vacations;
CREATE POLICY vacations_write ON employee_vacations
  FOR ALL
  USING (
    is_super_admin()
    OR (
      tenant_id = current_tenant_id()
      AND EXISTS (
        SELECT 1 FROM app_users u
        WHERE u.id = current_user_id() AND u.role IN ('diretoria','rh')
      )
    )
  )
  WITH CHECK (
    is_super_admin()
    OR (
      tenant_id = current_tenant_id()
      AND EXISTS (
        SELECT 1 FROM app_users u
        WHERE u.id = current_user_id() AND u.role IN ('diretoria','rh')
      )
    )
  );

DROP POLICY IF EXISTS leaves_read ON employee_leaves;
CREATE POLICY leaves_read ON employee_leaves
  FOR SELECT
  USING (
    is_super_admin()
    OR tenant_id = current_tenant_id()
  );

DROP POLICY IF EXISTS leaves_write ON employee_leaves;
CREATE POLICY leaves_write ON employee_leaves
  FOR ALL
  USING (
    is_super_admin()
    OR (
      tenant_id = current_tenant_id()
      AND EXISTS (
        SELECT 1 FROM app_users u
        WHERE u.id = current_user_id() AND u.role IN ('diretoria','rh')
      )
    )
  )
  WITH CHECK (
    is_super_admin()
    OR (
      tenant_id = current_tenant_id()
      AND EXISTS (
        SELECT 1 FROM app_users u
        WHERE u.id = current_user_id() AND u.role IN ('diretoria','rh')
      )
    )
  );

-- ============================================================================
-- 6. LIGACAO opcional · app_users.employee_id
-- ============================================================================

ALTER TABLE app_users
  ADD COLUMN IF NOT EXISTS employee_id UUID REFERENCES employees(id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS idx_app_users_employee_id
  ON app_users(employee_id) WHERE employee_id IS NOT NULL;

COMMENT ON COLUMN app_users.employee_id IS 'Sessao E1 · liga app_users a ficha de empregado · opcional (super_admin nao tem ficha)';

GRANT SELECT, INSERT, UPDATE, DELETE ON employees, employee_salary_history, employee_vacations, employee_leaves TO authenticated;

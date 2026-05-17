-- ============================================================================
-- R2 People · Schema base v1
-- ============================================================================
-- Sessoes A-D consolidadas em um unico arquivo
--
-- Cobre:
--   A. Tenants e configuracao
--   B. Estrutura organizacional (employer_units, working_units, departments)
--   C. Pessoas (app_users + external_ids)
--   D. Permissoes (catalogo + role_permissions) e auditoria
--
-- Pre-requisitos no projeto Supabase:
--   - Extension uuid-ossp (geralmente ja vem habilitada)
--   - Extension pgcrypto (para gen_random_uuid() usado nos defaults)
--
-- Ordem de aplicacao:
--   1. r2_people_schema_base_v1.sql       (este arquivo)
--   2. r2_people_seed_base_v1.sql         (permissoes + role_permissions)
--   3. r2_people_rls_policies_base_tests.sql (opcional · validacao)
--   4. Schemas de modulos (Climate v8, PDI, etc.)
--
-- Convencoes:
--   - Toda tabela de dominio tem tenant_id NOT NULL (multi-tenant rigido)
--   - Toda tabela tem created_at, updated_at (com trigger automatico)
--   - Soft-delete via campo "active" boolean (nao DELETE fisico)
--   - IDs sao UUID v4 com gen_random_uuid()
--   - Timestamps em TIMESTAMPTZ (sempre UTC, conversao no cliente)
-- ============================================================================

-- Extensoes necessarias (idempotente)
CREATE EXTENSION IF NOT EXISTS pgcrypto;
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- ============================================================================
-- BLOCO A · ENUMS GLOBAIS
-- ============================================================================

DO $$ BEGIN
  CREATE TYPE tenant_status AS ENUM ('active', 'suspended', 'archived');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  CREATE TYPE app_user_role AS ENUM ('colaborador', 'lider', 'rh', 'diretoria');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  CREATE TYPE employment_link AS ENUM (
    'clt',                -- Funcionario CLT
    'pj',                 -- Pessoa juridica (contrato)
    'intern',             -- Estagiario
    'apprentice',         -- Aprendiz
    'eventual',           -- Diarista, eventual, intermitente
    'pro_labore',         -- Socio com pro-labore
    'external_commission' -- Representante externo, agente comissionado
  );
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  CREATE TYPE unit_type AS ENUM (
    'matriz',
    'filial',
    'cd',                 -- Centro de distribuicao
    'office',             -- Escritorio corporativo
    'rural',              -- Operacao rural
    'other'
  );
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  CREATE TYPE audit_action AS ENUM ('insert', 'update', 'delete', 'login', 'logout', 'permission_check');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  CREATE TYPE permission_scope AS ENUM ('global', 'self', 'team', 'tenant');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  CREATE TYPE idp_provider AS ENUM ('email', 'google', 'microsoft', 'magic_link', 'other');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- ============================================================================
-- BLOCO B · TENANTS
-- ============================================================================

CREATE TABLE IF NOT EXISTS tenants (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),

  slug            VARCHAR(64) NOT NULL UNIQUE,        -- ex.: 'gpc', 'r2'
  legal_name      VARCHAR(200) NOT NULL,              -- razao social do grupo
  display_name    VARCHAR(120) NOT NULL,              -- nome de exibicao

  status          tenant_status NOT NULL DEFAULT 'active',
  plan            VARCHAR(60),                        -- 'starter', 'business', 'enterprise'

  -- Configuracao
  default_locale  VARCHAR(10) NOT NULL DEFAULT 'pt-BR',
  default_tz      VARCHAR(60) NOT NULL DEFAULT 'America/Bahia',
  features        JSONB NOT NULL DEFAULT '{}'::jsonb, -- flags por modulo

  -- Branding (opcional)
  primary_color   VARCHAR(7),                          -- '#2B4A7A'
  logo_url        TEXT,

  created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT now(),

  CONSTRAINT tenant_slug_lower CHECK (slug = lower(slug)),
  CONSTRAINT tenant_slug_format CHECK (slug ~ '^[a-z0-9][a-z0-9_-]*$')
);

CREATE INDEX IF NOT EXISTS idx_tenants_status ON tenants(status) WHERE status = 'active';

-- ============================================================================
-- BLOCO C · EMPLOYER UNITS (entidades juridicas / CNPJs)
-- ============================================================================

CREATE TABLE IF NOT EXISTS employer_units (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id       UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,

  code            VARCHAR(40) NOT NULL,                -- ex.: 'ATP-VAREJO', 'CESTAO-L1'
  legal_name      VARCHAR(200) NOT NULL,              -- razao social
  trade_name      VARCHAR(160),                        -- nome fantasia
  cnpj            VARCHAR(14),                         -- so digitos · pode ser NULL para entidades sem CNPJ
  ie              VARCHAR(20),                         -- inscricao estadual

  unit_type       unit_type NOT NULL DEFAULT 'matriz',
  active          BOOLEAN NOT NULL DEFAULT TRUE,

  -- Endereco principal (resumo · enderecos detalhados podem ir em tabela futura)
  city            VARCHAR(120),
  state_uf        VARCHAR(2),

  -- Configuracao por unidade (override de tenant)
  settings        JSONB NOT NULL DEFAULT '{}'::jsonb,

  created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT now(),

  UNIQUE (tenant_id, code),
  CONSTRAINT employer_cnpj_digits CHECK (cnpj IS NULL OR cnpj ~ '^[0-9]{14}$')
);

CREATE INDEX IF NOT EXISTS idx_employer_units_tenant ON employer_units(tenant_id);
CREATE INDEX IF NOT EXISTS idx_employer_units_active ON employer_units(tenant_id, active) WHERE active = TRUE;

-- ============================================================================
-- BLOCO C2 · WORKING UNITS (loja fisica · onde a pessoa trabalha)
-- ============================================================================

CREATE TABLE IF NOT EXISTS working_units (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id       UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  employer_unit_id UUID NOT NULL REFERENCES employer_units(id), -- a pessoa contratada por X trabalha em Y

  code            VARCHAR(40) NOT NULL,                -- ex.: 'L1', 'L2', 'CD-INHAMBUPE'
  display_name    VARCHAR(160) NOT NULL,
  unit_type       unit_type NOT NULL DEFAULT 'filial',
  active          BOOLEAN NOT NULL DEFAULT TRUE,

  city            VARCHAR(120),
  state_uf        VARCHAR(2),

  -- Capacidade operacional (informativo)
  headcount_target INT,

  settings        JSONB NOT NULL DEFAULT '{}'::jsonb,

  created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT now(),

  UNIQUE (tenant_id, code),
  CONSTRAINT working_employer_same_tenant CHECK (employer_unit_id IS NOT NULL)
);

CREATE INDEX IF NOT EXISTS idx_working_units_tenant ON working_units(tenant_id);
CREATE INDEX IF NOT EXISTS idx_working_units_employer ON working_units(employer_unit_id);

-- ============================================================================
-- BLOCO C3 · DEPARTMENTS (estrutura organizacional)
-- ============================================================================

CREATE TABLE IF NOT EXISTS departments (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id       UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,

  code            VARCHAR(40) NOT NULL,                -- 'COMERCIAL', 'PERECIVEIS', 'TI'
  display_name    VARCHAR(160) NOT NULL,
  parent_id       UUID REFERENCES departments(id),     -- hierarquia simples

  active          BOOLEAN NOT NULL DEFAULT TRUE,

  -- Para departamentos vinculados a uma unidade especifica (opcional)
  working_unit_id UUID REFERENCES working_units(id),

  display_order   INT NOT NULL DEFAULT 0,
  settings        JSONB NOT NULL DEFAULT '{}'::jsonb,

  created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT now(),

  UNIQUE (tenant_id, code)
);

CREATE INDEX IF NOT EXISTS idx_departments_tenant ON departments(tenant_id);
CREATE INDEX IF NOT EXISTS idx_departments_parent ON departments(parent_id) WHERE parent_id IS NOT NULL;

-- ============================================================================
-- BLOCO D · APP_USERS (pessoas)
-- ============================================================================

CREATE TABLE IF NOT EXISTS app_users (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id       UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,

  -- Vinculo com auth.users do Supabase (1:1 quando autenticado via Supabase Auth)
  -- NULL para usuarios nao-autenticaveis (intermitentes, externos, etc.)
  auth_user_id    UUID UNIQUE,                         -- referencia logica para auth.users.id

  email           VARCHAR(180) NOT NULL,
  full_name       VARCHAR(180) NOT NULL,
  short_name      VARCHAR(80),                         -- como a pessoa prefere ser chamada
  cpf             VARCHAR(11),                         -- so digitos · opcional

  role            app_user_role NOT NULL DEFAULT 'colaborador',

  -- Estrutura organizacional (todas opcionais para casos limites)
  employer_unit_id UUID REFERENCES employer_units(id),
  working_unit_id  UUID REFERENCES working_units(id),
  department_id    UUID REFERENCES departments(id),

  job_title       VARCHAR(160),
  manager_id      UUID REFERENCES app_users(id),       -- self-ref para hierarquia

  -- Vinculo trabalhista
  employment_link employment_link NOT NULL DEFAULT 'clt',
  hired_at        DATE,
  terminated_at   DATE,

  active          BOOLEAN NOT NULL DEFAULT TRUE,

  -- Configuracao por usuario (preferencias, locale override, etc.)
  preferences     JSONB NOT NULL DEFAULT '{}'::jsonb,

  -- Avatar
  avatar_url      TEXT,

  -- Idioma preferido (override do tenant)
  locale          VARCHAR(10),

  created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  last_login_at   TIMESTAMPTZ,

  UNIQUE (tenant_id, email),
  CONSTRAINT user_cpf_digits CHECK (cpf IS NULL OR cpf ~ '^[0-9]{11}$'),
  CONSTRAINT user_email_lower CHECK (email = lower(email)),
  CONSTRAINT user_terminated_after_hired CHECK (terminated_at IS NULL OR hired_at IS NULL OR terminated_at >= hired_at),
  CONSTRAINT user_no_self_manager CHECK (manager_id IS NULL OR manager_id <> id)
);

CREATE INDEX IF NOT EXISTS idx_app_users_tenant ON app_users(tenant_id);
CREATE INDEX IF NOT EXISTS idx_app_users_auth ON app_users(auth_user_id) WHERE auth_user_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_app_users_manager ON app_users(manager_id) WHERE manager_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_app_users_active ON app_users(tenant_id, active) WHERE active = TRUE;
CREATE INDEX IF NOT EXISTS idx_app_users_dept ON app_users(department_id) WHERE department_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_app_users_employer ON app_users(employer_unit_id) WHERE employer_unit_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_app_users_working ON app_users(working_unit_id) WHERE working_unit_id IS NOT NULL;

-- ============================================================================
-- BLOCO D2 · APP_USER_EXTERNAL_IDS (matricula em sistemas externos)
-- ============================================================================

CREATE TABLE IF NOT EXISTS app_user_external_ids (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id       UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  user_id         UUID NOT NULL REFERENCES app_users(id) ON DELETE CASCADE,

  system          VARCHAR(60) NOT NULL,                -- 'winthor', 'folha_pagamento', 'flash_card', 'ponto_eletronico'
  external_id     VARCHAR(120) NOT NULL,
  notes           TEXT,

  created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT now(),

  UNIQUE (tenant_id, user_id, system)
);

CREATE INDEX IF NOT EXISTS idx_user_ext_ids_user ON app_user_external_ids(user_id);
CREATE INDEX IF NOT EXISTS idx_user_ext_ids_lookup ON app_user_external_ids(tenant_id, system, external_id);

-- ============================================================================
-- BLOCO E · PERMISSIONS (catalogo + matriz por role)
-- ============================================================================

CREATE TABLE IF NOT EXISTS permissions (
  code            VARCHAR(80) PRIMARY KEY,             -- 'view_pdi', 'manage_climate', etc.
  description     VARCHAR(240) NOT NULL,
  scope           permission_scope NOT NULL DEFAULT 'tenant',
  module          VARCHAR(60) NOT NULL,                -- 'core', 'pdi', 'climate', 'people'
  active          BOOLEAN NOT NULL DEFAULT TRUE,

  created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_permissions_module ON permissions(module) WHERE active = TRUE;

-- Matriz role x permission (catalogo global · nao por tenant)
-- Cada tenant pode customizar isso futuramente em uma tabela override (nao implementada ainda)
CREATE TABLE IF NOT EXISTS role_permissions (
  role            app_user_role NOT NULL,
  permission_code VARCHAR(80) NOT NULL REFERENCES permissions(code) ON DELETE CASCADE,

  PRIMARY KEY (role, permission_code)
);

CREATE INDEX IF NOT EXISTS idx_role_permissions_perm ON role_permissions(permission_code);

-- ============================================================================
-- BLOCO F · AUDIT LOG
-- ============================================================================

CREATE TABLE IF NOT EXISTS audit_log (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  -- tenant_id pode ser NULL apos exclusao do tenant (mantem o registro auditavel)
  -- DEFERRABLE permite que cascades de DELETE em tenant nao causem violacao de FK
  -- enquanto triggers de audit em tabelas filhas ainda inserem antes do cascade chegar em audit_log
  tenant_id       UUID REFERENCES tenants(id) ON DELETE SET NULL DEFERRABLE INITIALLY DEFERRED,

  -- Quem
  actor_user_id   UUID REFERENCES app_users(id),       -- pode ser NULL para acoes do sistema
  actor_email     VARCHAR(180),                        -- snapshot caso o usuario seja deletado

  -- O que
  action          audit_action NOT NULL,
  entity_table    VARCHAR(80),
  entity_id       UUID,

  -- Detalhe (diff resumido)
  before_data     JSONB,
  after_data      JSONB,

  -- Contexto
  ip_address      INET,
  user_agent      TEXT,
  session_id      UUID,

  created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Index para consulta tipica: "tudo que fulano fez nos ultimos N dias"
CREATE INDEX IF NOT EXISTS idx_audit_actor ON audit_log(tenant_id, actor_user_id, created_at DESC);
-- Index para "historico de mudancas em uma entidade"
CREATE INDEX IF NOT EXISTS idx_audit_entity ON audit_log(tenant_id, entity_table, entity_id, created_at DESC);
-- Index para "todas as acoes de tenant em janela"
CREATE INDEX IF NOT EXISTS idx_audit_tenant_time ON audit_log(tenant_id, created_at DESC);

-- ============================================================================
-- FUNCOES HELPER
-- ============================================================================

-- Le o auth.uid() (UUID do auth.users do Supabase Auth) e retorna o app_users.id correspondente
-- Retorna NULL se nao houver mapeamento
CREATE OR REPLACE FUNCTION current_user_id()
RETURNS UUID
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_auth UUID;
  v_app_user_id UUID;
BEGIN
  v_auth := auth.uid();
  IF v_auth IS NULL THEN
    RETURN NULL;
  END IF;

  SELECT id INTO v_app_user_id
  FROM app_users
  WHERE auth_user_id = v_auth AND active = TRUE
  LIMIT 1;

  RETURN v_app_user_id;
END;
$$;

-- Retorna o tenant_id do usuario autenticado
CREATE OR REPLACE FUNCTION current_tenant_id()
RETURNS UUID
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_auth UUID;
  v_tenant UUID;
BEGIN
  v_auth := auth.uid();
  IF v_auth IS NULL THEN
    RETURN NULL;
  END IF;

  SELECT tenant_id INTO v_tenant
  FROM app_users
  WHERE auth_user_id = v_auth AND active = TRUE
  LIMIT 1;

  RETURN v_tenant;
END;
$$;

-- Retorna a role do usuario autenticado · NULL se nao autenticado
CREATE OR REPLACE FUNCTION current_user_role()
RETURNS app_user_role
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_auth UUID;
  v_role app_user_role;
BEGIN
  v_auth := auth.uid();
  IF v_auth IS NULL THEN
    RETURN NULL;
  END IF;

  SELECT role INTO v_role
  FROM app_users
  WHERE auth_user_id = v_auth AND active = TRUE
  LIMIT 1;

  RETURN v_role;
END;
$$;

-- Verifica se o usuario autenticado tem uma permissao
CREATE OR REPLACE FUNCTION user_has_permission(p_permission VARCHAR)
RETURNS BOOLEAN
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_role app_user_role;
  v_has BOOLEAN;
BEGIN
  v_role := current_user_role();
  IF v_role IS NULL THEN
    RETURN FALSE;
  END IF;

  SELECT EXISTS (
    SELECT 1 FROM role_permissions rp
    JOIN permissions p ON p.code = rp.permission_code
    WHERE rp.role = v_role
      AND rp.permission_code = p_permission
      AND p.active = TRUE
  ) INTO v_has;

  RETURN v_has;
END;
$$;

-- Verifica se o usuario X e gestor (direto ou indireto) do usuario Y
-- Util para policies de "leader pode ver seu time"
CREATE OR REPLACE FUNCTION user_is_manager_of(p_subordinate_id UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_caller UUID;
  v_current UUID;
  v_max_depth INT := 10;  -- evita loop em hierarquia corrompida
BEGIN
  v_caller := current_user_id();
  IF v_caller IS NULL OR p_subordinate_id IS NULL THEN
    RETURN FALSE;
  END IF;

  v_current := p_subordinate_id;
  WHILE v_max_depth > 0 LOOP
    SELECT manager_id INTO v_current
    FROM app_users
    WHERE id = v_current;

    IF v_current IS NULL THEN
      RETURN FALSE;
    END IF;

    IF v_current = v_caller THEN
      RETURN TRUE;
    END IF;

    v_max_depth := v_max_depth - 1;
  END LOOP;

  RETURN FALSE;
END;
$$;

-- Trigger generico para manter updated_at
-- Usa clock_timestamp() (nao now()) para que UPDATEs na mesma transacao
-- recebam timestamps diferentes do INSERT
CREATE OR REPLACE FUNCTION set_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at := clock_timestamp();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Trigger generico para audit_log
-- Aplicacao: CREATE TRIGGER trg_audit_X AFTER INSERT OR UPDATE OR DELETE ON tabela
--           FOR EACH ROW EXECUTE FUNCTION audit_change();
CREATE OR REPLACE FUNCTION audit_change()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_action audit_action;
  v_before JSONB;
  v_after JSONB;
  v_tenant UUID;
  v_actor UUID;
  v_actor_email VARCHAR(180);
  v_entity_id UUID;
BEGIN
  -- Determinar acao
  IF TG_OP = 'INSERT' THEN
    v_action := 'insert';
    v_after := to_jsonb(NEW);
    v_entity_id := (to_jsonb(NEW)->>'id')::UUID;
  ELSIF TG_OP = 'UPDATE' THEN
    v_action := 'update';
    v_before := to_jsonb(OLD);
    v_after := to_jsonb(NEW);
    v_entity_id := (to_jsonb(NEW)->>'id')::UUID;
  ELSIF TG_OP = 'DELETE' THEN
    v_action := 'delete';
    v_before := to_jsonb(OLD);
    v_entity_id := (to_jsonb(OLD)->>'id')::UUID;
  END IF;

  -- Tentar pegar tenant_id da linha
  IF v_after IS NOT NULL AND v_after ? 'tenant_id' THEN
    v_tenant := (v_after->>'tenant_id')::UUID;
  ELSIF v_before IS NOT NULL AND v_before ? 'tenant_id' THEN
    v_tenant := (v_before->>'tenant_id')::UUID;
  END IF;

  IF v_tenant IS NULL THEN
    -- Nao tem tenant_id · nao auditamos (provavelmente tabela global como permissions)
    IF TG_OP = 'DELETE' THEN
      RETURN OLD;
    ELSE
      RETURN NEW;
    END IF;
  END IF;

  v_actor := current_user_id();
  IF v_actor IS NOT NULL THEN
    SELECT email INTO v_actor_email FROM app_users WHERE id = v_actor;
  END IF;

  INSERT INTO audit_log (
    tenant_id, actor_user_id, actor_email, action,
    entity_table, entity_id, before_data, after_data
  ) VALUES (
    v_tenant, v_actor, v_actor_email, v_action,
    TG_TABLE_NAME, v_entity_id, v_before, v_after
  );

  IF TG_OP = 'DELETE' THEN
    RETURN OLD;
  ELSE
    RETURN NEW;
  END IF;
END;
$$;

-- ============================================================================
-- TRIGGERS · updated_at automatico
-- ============================================================================

DROP TRIGGER IF EXISTS trg_tenants_updated_at ON tenants;
CREATE TRIGGER trg_tenants_updated_at BEFORE UPDATE ON tenants
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

DROP TRIGGER IF EXISTS trg_employer_units_updated_at ON employer_units;
CREATE TRIGGER trg_employer_units_updated_at BEFORE UPDATE ON employer_units
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

DROP TRIGGER IF EXISTS trg_working_units_updated_at ON working_units;
CREATE TRIGGER trg_working_units_updated_at BEFORE UPDATE ON working_units
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

DROP TRIGGER IF EXISTS trg_departments_updated_at ON departments;
CREATE TRIGGER trg_departments_updated_at BEFORE UPDATE ON departments
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

DROP TRIGGER IF EXISTS trg_app_users_updated_at ON app_users;
CREATE TRIGGER trg_app_users_updated_at BEFORE UPDATE ON app_users
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

DROP TRIGGER IF EXISTS trg_app_user_external_ids_updated_at ON app_user_external_ids;
CREATE TRIGGER trg_app_user_external_ids_updated_at BEFORE UPDATE ON app_user_external_ids
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- ============================================================================
-- TRIGGERS · audit em tabelas sensiveis
-- ============================================================================

DROP TRIGGER IF EXISTS trg_audit_app_users ON app_users;
CREATE TRIGGER trg_audit_app_users
  AFTER INSERT OR UPDATE OR DELETE ON app_users
  FOR EACH ROW EXECUTE FUNCTION audit_change();

DROP TRIGGER IF EXISTS trg_audit_employer_units ON employer_units;
CREATE TRIGGER trg_audit_employer_units
  AFTER INSERT OR UPDATE OR DELETE ON employer_units
  FOR EACH ROW EXECUTE FUNCTION audit_change();

DROP TRIGGER IF EXISTS trg_audit_working_units ON working_units;
CREATE TRIGGER trg_audit_working_units
  AFTER INSERT OR UPDATE OR DELETE ON working_units
  FOR EACH ROW EXECUTE FUNCTION audit_change();

DROP TRIGGER IF EXISTS trg_audit_departments ON departments;
CREATE TRIGGER trg_audit_departments
  AFTER INSERT OR UPDATE OR DELETE ON departments
  FOR EACH ROW EXECUTE FUNCTION audit_change();

-- ============================================================================
-- ROW-LEVEL SECURITY
-- ============================================================================

ALTER TABLE tenants                ENABLE ROW LEVEL SECURITY;
ALTER TABLE employer_units         ENABLE ROW LEVEL SECURITY;
ALTER TABLE working_units          ENABLE ROW LEVEL SECURITY;
ALTER TABLE departments            ENABLE ROW LEVEL SECURITY;
ALTER TABLE app_users              ENABLE ROW LEVEL SECURITY;
ALTER TABLE app_user_external_ids  ENABLE ROW LEVEL SECURITY;
ALTER TABLE permissions            ENABLE ROW LEVEL SECURITY;
ALTER TABLE role_permissions       ENABLE ROW LEVEL SECURITY;
ALTER TABLE audit_log              ENABLE ROW LEVEL SECURITY;

-- ===== TENANTS =====
-- Usuario autenticado le apenas seu proprio tenant
DROP POLICY IF EXISTS tenants_self_read ON tenants;
CREATE POLICY tenants_self_read ON tenants
  FOR SELECT
  USING (id = current_tenant_id());

-- Apenas Diretoria pode atualizar configuracao do tenant
DROP POLICY IF EXISTS tenants_diretoria_update ON tenants;
CREATE POLICY tenants_diretoria_update ON tenants
  FOR UPDATE
  USING (id = current_tenant_id() AND current_user_role() = 'diretoria')
  WITH CHECK (id = current_tenant_id() AND current_user_role() = 'diretoria');

-- ===== EMPLOYER UNITS =====
DROP POLICY IF EXISTS employer_units_tenant_read ON employer_units;
CREATE POLICY employer_units_tenant_read ON employer_units
  FOR SELECT
  USING (tenant_id = current_tenant_id());

DROP POLICY IF EXISTS employer_units_rh_dir_write ON employer_units;
CREATE POLICY employer_units_rh_dir_write ON employer_units
  FOR ALL
  USING (
    tenant_id = current_tenant_id()
    AND current_user_role() IN ('rh', 'diretoria')
  )
  WITH CHECK (
    tenant_id = current_tenant_id()
    AND current_user_role() IN ('rh', 'diretoria')
  );

-- ===== WORKING UNITS =====
DROP POLICY IF EXISTS working_units_tenant_read ON working_units;
CREATE POLICY working_units_tenant_read ON working_units
  FOR SELECT
  USING (tenant_id = current_tenant_id());

DROP POLICY IF EXISTS working_units_rh_dir_write ON working_units;
CREATE POLICY working_units_rh_dir_write ON working_units
  FOR ALL
  USING (
    tenant_id = current_tenant_id()
    AND current_user_role() IN ('rh', 'diretoria')
  )
  WITH CHECK (
    tenant_id = current_tenant_id()
    AND current_user_role() IN ('rh', 'diretoria')
  );

-- ===== DEPARTMENTS =====
DROP POLICY IF EXISTS departments_tenant_read ON departments;
CREATE POLICY departments_tenant_read ON departments
  FOR SELECT
  USING (tenant_id = current_tenant_id());

DROP POLICY IF EXISTS departments_rh_dir_write ON departments;
CREATE POLICY departments_rh_dir_write ON departments
  FOR ALL
  USING (
    tenant_id = current_tenant_id()
    AND current_user_role() IN ('rh', 'diretoria')
  )
  WITH CHECK (
    tenant_id = current_tenant_id()
    AND current_user_role() IN ('rh', 'diretoria')
  );

-- ===== APP_USERS =====
-- Self-read: qualquer usuario le seu proprio registro
DROP POLICY IF EXISTS app_users_self_read ON app_users;
CREATE POLICY app_users_self_read ON app_users
  FOR SELECT
  USING (id = current_user_id());

-- Manager-read: lider le seus liderados (direto e indireto)
DROP POLICY IF EXISTS app_users_manager_read ON app_users;
CREATE POLICY app_users_manager_read ON app_users
  FOR SELECT
  USING (
    tenant_id = current_tenant_id()
    AND user_is_manager_of(id) = TRUE
  );

-- RH/Diretoria leem todos do tenant
DROP POLICY IF EXISTS app_users_rh_dir_read ON app_users;
CREATE POLICY app_users_rh_dir_read ON app_users
  FOR SELECT
  USING (
    tenant_id = current_tenant_id()
    AND current_user_role() IN ('rh', 'diretoria')
  );

-- Self-update: usuario pode atualizar campos limitados do proprio perfil (preferences, avatar, short_name, locale)
-- A validacao de quais campos sao alteraveis fica em RPC dedicada (rpc_user_update_self) · aqui apenas garantimos id=self
DROP POLICY IF EXISTS app_users_self_update ON app_users;
CREATE POLICY app_users_self_update ON app_users
  FOR UPDATE
  USING (id = current_user_id())
  WITH CHECK (id = current_user_id());

-- RH/Diretoria fazem CRUD completo
DROP POLICY IF EXISTS app_users_rh_dir_write ON app_users;
CREATE POLICY app_users_rh_dir_write ON app_users
  FOR ALL
  USING (
    tenant_id = current_tenant_id()
    AND current_user_role() IN ('rh', 'diretoria')
  )
  WITH CHECK (
    tenant_id = current_tenant_id()
    AND current_user_role() IN ('rh', 'diretoria')
  );

-- ===== APP_USER_EXTERNAL_IDS =====
DROP POLICY IF EXISTS user_ext_ids_self_read ON app_user_external_ids;
CREATE POLICY user_ext_ids_self_read ON app_user_external_ids
  FOR SELECT
  USING (user_id = current_user_id());

DROP POLICY IF EXISTS user_ext_ids_rh_dir_all ON app_user_external_ids;
CREATE POLICY user_ext_ids_rh_dir_all ON app_user_external_ids
  FOR ALL
  USING (
    tenant_id = current_tenant_id()
    AND current_user_role() IN ('rh', 'diretoria')
  )
  WITH CHECK (
    tenant_id = current_tenant_id()
    AND current_user_role() IN ('rh', 'diretoria')
  );

-- ===== PERMISSIONS (catalogo global · todos leem, ninguem escreve via RLS) =====
DROP POLICY IF EXISTS permissions_all_read ON permissions;
CREATE POLICY permissions_all_read ON permissions
  FOR SELECT
  USING (active = TRUE);

DROP POLICY IF EXISTS role_permissions_all_read ON role_permissions;
CREATE POLICY role_permissions_all_read ON role_permissions
  FOR SELECT
  USING (TRUE);

-- ===== AUDIT_LOG =====
-- Apenas RH e Diretoria leem · ninguem escreve direto (so trigger via SECURITY DEFINER)
DROP POLICY IF EXISTS audit_log_rh_dir_read ON audit_log;
CREATE POLICY audit_log_rh_dir_read ON audit_log
  FOR SELECT
  USING (
    tenant_id = current_tenant_id()
    AND current_user_role() IN ('rh', 'diretoria')
  );

-- Negar INSERT/UPDATE/DELETE direto · so via funcao trigger SECURITY DEFINER
-- (Nao criamos policy de write · o RLS bloqueia tudo que nao tem policy)

-- ============================================================================
-- GRANTS
-- ============================================================================

-- Schema public e padrao no Supabase. Todas as tabelas precisam de GRANT explicito
-- para os roles 'authenticated' e 'anon' poderem usar.

GRANT USAGE ON SCHEMA public TO authenticated, anon;

GRANT SELECT ON tenants               TO authenticated;
GRANT SELECT, UPDATE ON tenants       TO authenticated; -- update so passa pela policy
GRANT SELECT, INSERT, UPDATE, DELETE ON employer_units        TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON working_units         TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON departments           TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON app_users             TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON app_user_external_ids TO authenticated;
GRANT SELECT ON permissions           TO authenticated, anon;
GRANT SELECT ON role_permissions      TO authenticated, anon;
GRANT SELECT ON audit_log             TO authenticated;

-- ============================================================================
-- COMENTARIOS
-- ============================================================================

COMMENT ON TABLE tenants IS 'Empresa cliente · multi-tenant rigido';
COMMENT ON TABLE employer_units IS 'Entidade juridica (CNPJ) que contrata pessoas';
COMMENT ON TABLE working_units IS 'Local fisico onde a pessoa atua (loja, CD, escritorio)';
COMMENT ON TABLE departments IS 'Departamentos do tenant · hierarquia opcional';
COMMENT ON TABLE app_users IS 'Pessoas do sistema · vinculo 1:1 opcional com auth.users';
COMMENT ON TABLE app_user_external_ids IS 'Matricula em sistemas externos (WinThor, folha, ponto, Flash)';
COMMENT ON TABLE permissions IS 'Catalogo global de permissoes nomeadas';
COMMENT ON TABLE role_permissions IS 'Matriz role x permission · catalogo global';
COMMENT ON TABLE audit_log IS 'Trilha de auditoria · escrita apenas via trigger SECURITY DEFINER';

COMMENT ON FUNCTION current_user_id IS 'Retorna o app_users.id do usuario autenticado · NULL se nao autenticado';
COMMENT ON FUNCTION current_tenant_id IS 'Retorna o tenant_id do usuario autenticado';
COMMENT ON FUNCTION current_user_role IS 'Retorna a role do usuario autenticado';
COMMENT ON FUNCTION user_has_permission IS 'Verifica se a role do usuario tem a permissao indicada';
COMMENT ON FUNCTION user_is_manager_of IS 'Verifica se o usuario autenticado e gestor (direto ou indireto, max 10 niveis) do subordinado indicado';

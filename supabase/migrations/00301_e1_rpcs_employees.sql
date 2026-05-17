-- ============================================================================
-- R2 People · Sessao E1 · RPCs Employees
-- ============================================================================
-- 9 RPCs publicas para gestao da ficha de empregado.
--
-- Padrao de retorno:
--   - Sucesso:  { ok: true, ...payload }
--   - Erro:     { error: 'snake_case_code', ...details }
--
-- Pre-requisitos: schema E1 aplicado.
-- Idempotente.
-- ============================================================================

-- ============================================================================
-- HELPER · normaliza CPF removendo mascara
-- ============================================================================

CREATE OR REPLACE FUNCTION cpf_digits_only(p_cpf TEXT)
RETURNS TEXT
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT regexp_replace(coalesce(p_cpf, ''), '\D', '', 'g');
$$;

-- ============================================================================
-- HELPER · valida permissao de leitura/escrita em employees
-- ============================================================================

CREATE OR REPLACE FUNCTION employees_can_read()
RETURNS BOOLEAN
LANGUAGE sql
STABLE SECURITY DEFINER
SET search_path = public
AS $$
  SELECT is_super_admin() OR EXISTS (
    SELECT 1 FROM app_users
    WHERE id = current_user_id()
      AND tenant_id = current_tenant_id()
  );
$$;

CREATE OR REPLACE FUNCTION employees_can_write()
RETURNS BOOLEAN
LANGUAGE sql
STABLE SECURITY DEFINER
SET search_path = public
AS $$
  SELECT is_super_admin() OR EXISTS (
    SELECT 1 FROM app_users
    WHERE id = current_user_id()
      AND tenant_id = current_tenant_id()
      AND role IN ('diretoria', 'rh')
  );
$$;

-- ============================================================================
-- rpc_employees_list · lista com filtros + paginacao
-- ============================================================================

CREATE OR REPLACE FUNCTION rpc_employees_list(
  p_search           TEXT DEFAULT NULL,         -- busca por nome, CPF, matricula
  p_status           TEXT DEFAULT 'all',         -- 'active', 'terminated', 'all'
  p_employer_unit_id UUID DEFAULT NULL,
  p_working_unit_id  UUID DEFAULT NULL,
  p_job_title        TEXT DEFAULT NULL,
  p_limit            INT  DEFAULT 50,
  p_offset           INT  DEFAULT 0
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user app_users;
  v_total INT;
  v_employees JSONB;
  v_search_norm TEXT;
BEGIN
  SELECT * INTO v_user FROM app_users WHERE id = current_user_id();
  IF v_user IS NULL THEN RETURN jsonb_build_object('error', 'not_authenticated'); END IF;

  IF NOT employees_can_read() THEN
    RETURN jsonb_build_object('error', 'permission_denied');
  END IF;

  v_search_norm := lower(trim(coalesce(p_search, '')));

  -- Count total
  SELECT count(*)
  INTO v_total
  FROM employees e
  WHERE e.archived_at IS NULL
    AND (is_super_admin() OR e.tenant_id = v_user.tenant_id)
    AND (
      p_status = 'all'
      OR (p_status = 'active'     AND e.termination_date IS NULL)
      OR (p_status = 'terminated' AND e.termination_date IS NOT NULL)
    )
    AND (p_employer_unit_id IS NULL OR e.employer_unit_id = p_employer_unit_id)
    AND (p_working_unit_id  IS NULL OR e.working_unit_id  = p_working_unit_id)
    AND (p_job_title IS NULL OR e.job_title ILIKE '%' || p_job_title || '%')
    AND (
      v_search_norm = ''
      OR lower(e.full_name) LIKE '%' || v_search_norm || '%'
      OR (cpf_digits_only(v_search_norm) <> ''
          AND cpf_digits_only(e.cpf) LIKE '%' || cpf_digits_only(v_search_norm) || '%')
      OR e.matricula_esocial ILIKE '%' || v_search_norm || '%'
    );

  -- Page
  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'id', e.id,
    'matricula_esocial', e.matricula_esocial,
    'full_name', e.full_name,
    'cpf', e.cpf,
    'job_title', e.job_title,
    'cbo', e.cbo,
    'hire_date', e.hire_date,
    'termination_date', e.termination_date,
    'termination_type', e.termination_type,
    'employer_unit_id', e.employer_unit_id,
    'employer_unit_name', (SELECT legal_name FROM employer_units WHERE id = e.employer_unit_id),
    'working_unit_id', e.working_unit_id,
    'working_unit_name', (SELECT display_name FROM working_units WHERE id = e.working_unit_id),
    'phone_mobile', e.phone_mobile,
    'is_active', e.termination_date IS NULL,
    'source', e.source
  ) ORDER BY e.full_name), '[]'::JSONB)
  INTO v_employees
  FROM employees e
  WHERE e.archived_at IS NULL
    AND (is_super_admin() OR e.tenant_id = v_user.tenant_id)
    AND (
      p_status = 'all'
      OR (p_status = 'active'     AND e.termination_date IS NULL)
      OR (p_status = 'terminated' AND e.termination_date IS NOT NULL)
    )
    AND (p_employer_unit_id IS NULL OR e.employer_unit_id = p_employer_unit_id)
    AND (p_working_unit_id  IS NULL OR e.working_unit_id  = p_working_unit_id)
    AND (p_job_title IS NULL OR e.job_title ILIKE '%' || p_job_title || '%')
    AND (
      v_search_norm = ''
      OR lower(e.full_name) LIKE '%' || v_search_norm || '%'
      OR (cpf_digits_only(v_search_norm) <> ''
          AND cpf_digits_only(e.cpf) LIKE '%' || cpf_digits_only(v_search_norm) || '%')
      OR e.matricula_esocial ILIKE '%' || v_search_norm || '%'
    )
  LIMIT p_limit OFFSET p_offset;

  RETURN jsonb_build_object(
    'ok', TRUE,
    'employees', v_employees,
    'total', v_total,
    'limit', p_limit,
    'offset', p_offset
  );
END;
$$;

-- ============================================================================
-- rpc_employees_get_by_id · detalhe completo + filhas
-- ============================================================================

CREATE OR REPLACE FUNCTION rpc_employees_get_by_id(p_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user app_users;
  v_employee JSONB;
  v_salary  JSONB;
  v_vacations JSONB;
  v_leaves JSONB;
BEGIN
  SELECT * INTO v_user FROM app_users WHERE id = current_user_id();
  IF v_user IS NULL THEN RETURN jsonb_build_object('error', 'not_authenticated'); END IF;
  IF NOT employees_can_read() THEN
    RETURN jsonb_build_object('error', 'permission_denied');
  END IF;

  SELECT to_jsonb(e)
        || jsonb_build_object(
          'employer_unit_name', (SELECT legal_name FROM employer_units WHERE id = e.employer_unit_id),
          'working_unit_name',  (SELECT display_name FROM working_units WHERE id = e.working_unit_id),
          'department_name',    (SELECT display_name FROM departments WHERE id = e.department_id),
          'is_active', e.termination_date IS NULL
        )
  INTO v_employee
  FROM employees e
  WHERE e.id = p_id
    AND e.archived_at IS NULL
    AND (is_super_admin() OR e.tenant_id = v_user.tenant_id);

  IF v_employee IS NULL THEN
    RETURN jsonb_build_object('error', 'employee_not_found');
  END IF;

  SELECT COALESCE(jsonb_agg(to_jsonb(s) ORDER BY s.effective_date), '[]'::JSONB)
  INTO v_salary
  FROM employee_salary_history s
  WHERE s.employee_id = p_id;

  SELECT COALESCE(jsonb_agg(to_jsonb(v) ORDER BY v.start_date), '[]'::JSONB)
  INTO v_vacations
  FROM employee_vacations v
  WHERE v.employee_id = p_id;

  SELECT COALESCE(jsonb_agg(to_jsonb(l) ORDER BY l.start_date DESC), '[]'::JSONB)
  INTO v_leaves
  FROM employee_leaves l
  WHERE l.employee_id = p_id;

  RETURN jsonb_build_object(
    'ok', TRUE,
    'employee', v_employee,
    'salary_history', v_salary,
    'vacations', v_vacations,
    'leaves', v_leaves
  );
END;
$$;

-- ============================================================================
-- rpc_employees_create · cria nova ficha
-- ============================================================================

CREATE OR REPLACE FUNCTION rpc_employees_create(p_payload JSONB)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user app_users;
  v_id UUID;
  v_existing_id UUID;
  v_tenant UUID;
BEGIN
  SELECT * INTO v_user FROM app_users WHERE id = current_user_id();
  IF v_user IS NULL THEN RETURN jsonb_build_object('error', 'not_authenticated'); END IF;
  IF NOT employees_can_write() THEN
    RETURN jsonb_build_object('error', 'permission_denied');
  END IF;

  -- Campos obrigatorios
  IF (p_payload ->> 'full_name') IS NULL OR (p_payload ->> 'full_name') = '' THEN
    RETURN jsonb_build_object('error', 'full_name_required');
  END IF;
  IF (p_payload ->> 'hire_date') IS NULL THEN
    RETURN jsonb_build_object('error', 'hire_date_required');
  END IF;
  IF (p_payload ->> 'job_title') IS NULL OR (p_payload ->> 'job_title') = '' THEN
    RETURN jsonb_build_object('error', 'job_title_required');
  END IF;

  -- Tenant
  v_tenant := COALESCE(
    (p_payload ->> 'tenant_id')::UUID,
    v_user.tenant_id
  );

  -- Validacao cross-tenant (apenas super_admin pode setar tenant diferente)
  IF v_tenant <> v_user.tenant_id AND NOT is_super_admin() THEN
    RETURN jsonb_build_object('error', 'scope_outside_tenant');
  END IF;

  -- Idempotencia por CPF · se ja existe, retorna o id existente
  IF p_payload ? 'cpf' AND (p_payload ->> 'cpf') IS NOT NULL THEN
    SELECT id INTO v_existing_id
    FROM employees
    WHERE tenant_id = v_tenant
      AND cpf = (p_payload ->> 'cpf')
      AND archived_at IS NULL;
    IF v_existing_id IS NOT NULL THEN
      RETURN jsonb_build_object('ok', TRUE, 'id', v_existing_id, 'already_exists', TRUE);
    END IF;
  END IF;

  INSERT INTO employees (
    tenant_id, employer_unit_id, working_unit_id, department_id,
    matricula_esocial, ficha_numero, full_name, beneficiaries,
    cpf, rg, rg_issue_date, rg_issuer,
    voter_id, voter_zone, voter_section,
    ctps_number, ctps_serie, ctps_issue_date, ctps_uf,
    pis, military_doc, cnh, cnh_category,
    birth_date, birth_city, birth_state, nationality,
    marital_status, sex, race_color, education,
    has_disability, disability_description,
    father_name, mother_name,
    residence_address, residence_cep, phone_home, phone_mobile, email,
    job_title, job_function, cbo,
    hire_date, initial_salary, salary_unit,
    work_schedule_start, work_schedule_end, break_start, break_end,
    fgts_opt_in_date, bank_account,
    termination_date, termination_type, termination_reason,
    source, created_by, updated_by
  ) VALUES (
    v_tenant,
    NULLIF(p_payload ->> 'employer_unit_id', '')::UUID,
    NULLIF(p_payload ->> 'working_unit_id', '')::UUID,
    NULLIF(p_payload ->> 'department_id', '')::UUID,
    p_payload ->> 'matricula_esocial',
    p_payload ->> 'ficha_numero',
    p_payload ->> 'full_name',
    p_payload ->> 'beneficiaries',
    p_payload ->> 'cpf',
    p_payload ->> 'rg',
    NULLIF(p_payload ->> 'rg_issue_date', '')::DATE,
    p_payload ->> 'rg_issuer',
    p_payload ->> 'voter_id',
    p_payload ->> 'voter_zone',
    p_payload ->> 'voter_section',
    p_payload ->> 'ctps_number',
    p_payload ->> 'ctps_serie',
    NULLIF(p_payload ->> 'ctps_issue_date', '')::DATE,
    p_payload ->> 'ctps_uf',
    p_payload ->> 'pis',
    p_payload ->> 'military_doc',
    p_payload ->> 'cnh',
    p_payload ->> 'cnh_category',
    NULLIF(p_payload ->> 'birth_date', '')::DATE,
    p_payload ->> 'birth_city',
    p_payload ->> 'birth_state',
    COALESCE(p_payload ->> 'nationality', 'BRASIL'),
    COALESCE((p_payload ->> 'marital_status')::marital_status, 'nao_informado'),
    COALESCE((p_payload ->> 'sex')::employee_sex, 'nao_informado'),
    COALESCE((p_payload ->> 'race_color')::race_color, 'nao_informada'),
    COALESCE((p_payload ->> 'education')::education_level, 'nao_informado'),
    COALESCE((p_payload ->> 'has_disability')::BOOLEAN, FALSE),
    p_payload ->> 'disability_description',
    p_payload ->> 'father_name',
    p_payload ->> 'mother_name',
    p_payload ->> 'residence_address',
    p_payload ->> 'residence_cep',
    p_payload ->> 'phone_home',
    p_payload ->> 'phone_mobile',
    p_payload ->> 'email',
    p_payload ->> 'job_title',
    p_payload ->> 'job_function',
    p_payload ->> 'cbo',
    (p_payload ->> 'hire_date')::DATE,
    NULLIF(p_payload ->> 'initial_salary', '')::NUMERIC,
    COALESCE((p_payload ->> 'salary_unit')::salary_unit, 'mes'),
    NULLIF(p_payload ->> 'work_schedule_start', '')::TIME,
    NULLIF(p_payload ->> 'work_schedule_end', '')::TIME,
    NULLIF(p_payload ->> 'break_start', '')::TIME,
    NULLIF(p_payload ->> 'break_end', '')::TIME,
    NULLIF(p_payload ->> 'fgts_opt_in_date', '')::DATE,
    p_payload ->> 'bank_account',
    NULLIF(p_payload ->> 'termination_date', '')::DATE,
    NULLIF(p_payload ->> 'termination_type', '')::dismissal_type,
    p_payload ->> 'termination_reason',
    COALESCE(p_payload ->> 'source', 'manual'),
    v_user.id,
    v_user.id
  ) RETURNING id INTO v_id;

  -- Insere salario inicial em employee_salary_history se informado
  IF (p_payload ->> 'initial_salary') IS NOT NULL THEN
    INSERT INTO employee_salary_history (
      employee_id, tenant_id, effective_date, amount, unit, job_title, cbo, change_type, created_by
    ) VALUES (
      v_id, v_tenant, (p_payload ->> 'hire_date')::DATE,
      (p_payload ->> 'initial_salary')::NUMERIC,
      COALESCE((p_payload ->> 'salary_unit')::salary_unit, 'mes'),
      p_payload ->> 'job_title',
      p_payload ->> 'cbo',
      'initial',
      v_user.id
    );
  END IF;

  RETURN jsonb_build_object('ok', TRUE, 'id', v_id, 'created', TRUE);
END;
$$;

-- ============================================================================
-- rpc_employees_update · atualiza campos
-- Recebe o id + JSONB com os campos a alterar. Audit automatico via trigger.
-- ============================================================================

CREATE OR REPLACE FUNCTION rpc_employees_update(p_id UUID, p_payload JSONB)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user app_users;
  v_employee employees;
BEGIN
  SELECT * INTO v_user FROM app_users WHERE id = current_user_id();
  IF v_user IS NULL THEN RETURN jsonb_build_object('error', 'not_authenticated'); END IF;
  IF NOT employees_can_write() THEN
    RETURN jsonb_build_object('error', 'permission_denied');
  END IF;

  SELECT * INTO v_employee FROM employees WHERE id = p_id AND archived_at IS NULL;
  IF v_employee IS NULL THEN
    RETURN jsonb_build_object('error', 'employee_not_found');
  END IF;
  IF v_employee.tenant_id <> v_user.tenant_id AND NOT is_super_admin() THEN
    RETURN jsonb_build_object('error', 'scope_outside_tenant');
  END IF;

  -- Update preservando o que nao foi passado
  UPDATE employees SET
    employer_unit_id       = COALESCE(NULLIF(p_payload ->> 'employer_unit_id', '')::UUID, employer_unit_id),
    working_unit_id        = COALESCE(NULLIF(p_payload ->> 'working_unit_id', '')::UUID, working_unit_id),
    department_id          = COALESCE(NULLIF(p_payload ->> 'department_id', '')::UUID, department_id),
    matricula_esocial      = COALESCE(p_payload ->> 'matricula_esocial', matricula_esocial),
    ficha_numero           = COALESCE(p_payload ->> 'ficha_numero', ficha_numero),
    full_name              = COALESCE(p_payload ->> 'full_name', full_name),
    beneficiaries          = COALESCE(p_payload ->> 'beneficiaries', beneficiaries),
    cpf                    = COALESCE(p_payload ->> 'cpf', cpf),
    rg                     = COALESCE(p_payload ->> 'rg', rg),
    rg_issue_date          = COALESCE(NULLIF(p_payload ->> 'rg_issue_date', '')::DATE, rg_issue_date),
    rg_issuer              = COALESCE(p_payload ->> 'rg_issuer', rg_issuer),
    voter_id               = COALESCE(p_payload ->> 'voter_id', voter_id),
    voter_zone             = COALESCE(p_payload ->> 'voter_zone', voter_zone),
    voter_section          = COALESCE(p_payload ->> 'voter_section', voter_section),
    ctps_number            = COALESCE(p_payload ->> 'ctps_number', ctps_number),
    ctps_serie             = COALESCE(p_payload ->> 'ctps_serie', ctps_serie),
    ctps_issue_date        = COALESCE(NULLIF(p_payload ->> 'ctps_issue_date', '')::DATE, ctps_issue_date),
    ctps_uf                = COALESCE(p_payload ->> 'ctps_uf', ctps_uf),
    pis                    = COALESCE(p_payload ->> 'pis', pis),
    military_doc           = COALESCE(p_payload ->> 'military_doc', military_doc),
    cnh                    = COALESCE(p_payload ->> 'cnh', cnh),
    cnh_category           = COALESCE(p_payload ->> 'cnh_category', cnh_category),
    birth_date             = COALESCE(NULLIF(p_payload ->> 'birth_date', '')::DATE, birth_date),
    birth_city             = COALESCE(p_payload ->> 'birth_city', birth_city),
    birth_state            = COALESCE(p_payload ->> 'birth_state', birth_state),
    nationality            = COALESCE(p_payload ->> 'nationality', nationality),
    marital_status         = COALESCE((p_payload ->> 'marital_status')::marital_status, marital_status),
    sex                    = COALESCE((p_payload ->> 'sex')::employee_sex, sex),
    race_color             = COALESCE((p_payload ->> 'race_color')::race_color, race_color),
    education              = COALESCE((p_payload ->> 'education')::education_level, education),
    has_disability         = COALESCE((p_payload ->> 'has_disability')::BOOLEAN, has_disability),
    disability_description = COALESCE(p_payload ->> 'disability_description', disability_description),
    father_name            = COALESCE(p_payload ->> 'father_name', father_name),
    mother_name            = COALESCE(p_payload ->> 'mother_name', mother_name),
    residence_address      = COALESCE(p_payload ->> 'residence_address', residence_address),
    residence_cep          = COALESCE(p_payload ->> 'residence_cep', residence_cep),
    phone_home             = COALESCE(p_payload ->> 'phone_home', phone_home),
    phone_mobile           = COALESCE(p_payload ->> 'phone_mobile', phone_mobile),
    email                  = COALESCE(p_payload ->> 'email', email),
    job_title              = COALESCE(p_payload ->> 'job_title', job_title),
    job_function           = COALESCE(p_payload ->> 'job_function', job_function),
    cbo                    = COALESCE(p_payload ->> 'cbo', cbo),
    hire_date              = COALESCE(NULLIF(p_payload ->> 'hire_date', '')::DATE, hire_date),
    initial_salary         = COALESCE(NULLIF(p_payload ->> 'initial_salary', '')::NUMERIC, initial_salary),
    salary_unit            = COALESCE((p_payload ->> 'salary_unit')::salary_unit, salary_unit),
    work_schedule_start    = COALESCE(NULLIF(p_payload ->> 'work_schedule_start', '')::TIME, work_schedule_start),
    work_schedule_end      = COALESCE(NULLIF(p_payload ->> 'work_schedule_end', '')::TIME, work_schedule_end),
    break_start            = COALESCE(NULLIF(p_payload ->> 'break_start', '')::TIME, break_start),
    break_end              = COALESCE(NULLIF(p_payload ->> 'break_end', '')::TIME, break_end),
    fgts_opt_in_date       = COALESCE(NULLIF(p_payload ->> 'fgts_opt_in_date', '')::DATE, fgts_opt_in_date),
    bank_account           = COALESCE(p_payload ->> 'bank_account', bank_account),
    termination_date       = CASE WHEN p_payload ? 'termination_date'
                                  THEN NULLIF(p_payload ->> 'termination_date', '')::DATE
                                  ELSE termination_date END,
    termination_type       = CASE WHEN p_payload ? 'termination_type'
                                  THEN NULLIF(p_payload ->> 'termination_type', '')::dismissal_type
                                  ELSE termination_type END,
    termination_reason     = CASE WHEN p_payload ? 'termination_reason'
                                  THEN p_payload ->> 'termination_reason'
                                  ELSE termination_reason END
  WHERE id = p_id;

  RETURN jsonb_build_object('ok', TRUE, 'id', p_id, 'updated', TRUE);
END;
$$;

-- ============================================================================
-- rpc_employees_salary_add · adiciona linha no historico salarial
-- ============================================================================

CREATE OR REPLACE FUNCTION rpc_employees_salary_add(p_employee_id UUID, p_payload JSONB)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user app_users;
  v_employee employees;
  v_id UUID;
BEGIN
  SELECT * INTO v_user FROM app_users WHERE id = current_user_id();
  IF v_user IS NULL THEN RETURN jsonb_build_object('error', 'not_authenticated'); END IF;
  IF NOT employees_can_write() THEN
    RETURN jsonb_build_object('error', 'permission_denied');
  END IF;

  SELECT * INTO v_employee FROM employees WHERE id = p_employee_id AND archived_at IS NULL;
  IF v_employee IS NULL THEN RETURN jsonb_build_object('error', 'employee_not_found'); END IF;
  IF v_employee.tenant_id <> v_user.tenant_id AND NOT is_super_admin() THEN
    RETURN jsonb_build_object('error', 'scope_outside_tenant');
  END IF;

  IF (p_payload ->> 'effective_date') IS NULL OR (p_payload ->> 'amount') IS NULL THEN
    RETURN jsonb_build_object('error', 'missing_required_fields');
  END IF;

  INSERT INTO employee_salary_history (
    employee_id, tenant_id, effective_date, amount, unit,
    job_title, job_function, cbo, change_type, observations, created_by
  ) VALUES (
    p_employee_id, v_employee.tenant_id,
    (p_payload ->> 'effective_date')::DATE,
    (p_payload ->> 'amount')::NUMERIC,
    COALESCE((p_payload ->> 'unit')::salary_unit, 'mes'),
    p_payload ->> 'job_title',
    p_payload ->> 'job_function',
    p_payload ->> 'cbo',
    COALESCE(p_payload ->> 'change_type', 'adjustment'),
    p_payload ->> 'observations',
    v_user.id
  ) RETURNING id INTO v_id;

  RETURN jsonb_build_object('ok', TRUE, 'id', v_id);
END;
$$;

-- ============================================================================
-- rpc_employees_vacation_add
-- ============================================================================

CREATE OR REPLACE FUNCTION rpc_employees_vacation_add(p_employee_id UUID, p_payload JSONB)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user app_users;
  v_employee employees;
  v_id UUID;
BEGIN
  SELECT * INTO v_user FROM app_users WHERE id = current_user_id();
  IF v_user IS NULL THEN RETURN jsonb_build_object('error', 'not_authenticated'); END IF;
  IF NOT employees_can_write() THEN RETURN jsonb_build_object('error', 'permission_denied'); END IF;

  SELECT * INTO v_employee FROM employees WHERE id = p_employee_id AND archived_at IS NULL;
  IF v_employee IS NULL THEN RETURN jsonb_build_object('error', 'employee_not_found'); END IF;
  IF v_employee.tenant_id <> v_user.tenant_id AND NOT is_super_admin() THEN
    RETURN jsonb_build_object('error', 'scope_outside_tenant');
  END IF;

  IF (p_payload ->> 'kind') IS NULL OR (p_payload ->> 'start_date') IS NULL OR (p_payload ->> 'end_date') IS NULL THEN
    RETURN jsonb_build_object('error', 'missing_required_fields');
  END IF;

  INSERT INTO employee_vacations (
    employee_id, tenant_id, kind, start_date, end_date,
    paid_on_termination, observations, created_by
  ) VALUES (
    p_employee_id, v_employee.tenant_id,
    (p_payload ->> 'kind')::vacation_kind,
    (p_payload ->> 'start_date')::DATE,
    (p_payload ->> 'end_date')::DATE,
    COALESCE((p_payload ->> 'paid_on_termination')::BOOLEAN, FALSE),
    p_payload ->> 'observations',
    v_user.id
  ) RETURNING id INTO v_id;

  RETURN jsonb_build_object('ok', TRUE, 'id', v_id);
END;
$$;

-- ============================================================================
-- rpc_employees_leave_add
-- ============================================================================

CREATE OR REPLACE FUNCTION rpc_employees_leave_add(p_employee_id UUID, p_payload JSONB)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user app_users;
  v_employee employees;
  v_id UUID;
BEGIN
  SELECT * INTO v_user FROM app_users WHERE id = current_user_id();
  IF v_user IS NULL THEN RETURN jsonb_build_object('error', 'not_authenticated'); END IF;
  IF NOT employees_can_write() THEN RETURN jsonb_build_object('error', 'permission_denied'); END IF;

  SELECT * INTO v_employee FROM employees WHERE id = p_employee_id AND archived_at IS NULL;
  IF v_employee IS NULL THEN RETURN jsonb_build_object('error', 'employee_not_found'); END IF;
  IF v_employee.tenant_id <> v_user.tenant_id AND NOT is_super_admin() THEN
    RETURN jsonb_build_object('error', 'scope_outside_tenant');
  END IF;

  IF (p_payload ->> 'start_date') IS NULL THEN
    RETURN jsonb_build_object('error', 'start_date_required');
  END IF;

  INSERT INTO employee_leaves (
    employee_id, tenant_id, start_date, end_date, reason, description, cid, inss_benefit, created_by
  ) VALUES (
    p_employee_id, v_employee.tenant_id,
    (p_payload ->> 'start_date')::DATE,
    NULLIF(p_payload ->> 'end_date', '')::DATE,
    COALESCE((p_payload ->> 'reason')::leave_reason, 'doenca_comum'),
    p_payload ->> 'description',
    p_payload ->> 'cid',
    p_payload ->> 'inss_benefit',
    v_user.id
  ) RETURNING id INTO v_id;

  RETURN jsonb_build_object('ok', TRUE, 'id', v_id);
END;
$$;

-- ============================================================================
-- rpc_employees_archive · soft-delete
-- ============================================================================

CREATE OR REPLACE FUNCTION rpc_employees_archive(p_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user app_users;
  v_employee employees;
BEGIN
  SELECT * INTO v_user FROM app_users WHERE id = current_user_id();
  IF v_user IS NULL THEN RETURN jsonb_build_object('error', 'not_authenticated'); END IF;
  IF NOT employees_can_write() THEN RETURN jsonb_build_object('error', 'permission_denied'); END IF;

  SELECT * INTO v_employee FROM employees WHERE id = p_id AND archived_at IS NULL;
  IF v_employee IS NULL THEN RETURN jsonb_build_object('error', 'employee_not_found'); END IF;
  IF v_employee.tenant_id <> v_user.tenant_id AND NOT is_super_admin() THEN
    RETURN jsonb_build_object('error', 'scope_outside_tenant');
  END IF;

  UPDATE employees SET archived_at = now() WHERE id = p_id;
  RETURN jsonb_build_object('ok', TRUE, 'id', p_id, 'archived', TRUE);
END;
$$;

-- ============================================================================
-- rpc_employees_import_xlsx · recebe JSONB com lista de fichas
-- (o XLSX e parseado no frontend e enviado como JSON)
-- Retorna o resumo de importacao: created, skipped (ja existem), errors
-- ============================================================================

CREATE OR REPLACE FUNCTION rpc_employees_import_xlsx(p_records JSONB)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user app_users;
  v_record JSONB;
  v_result JSONB;
  v_created INT := 0;
  v_skipped INT := 0;
  v_errors JSONB := '[]'::JSONB;
  v_idx INT := 0;
BEGIN
  SELECT * INTO v_user FROM app_users WHERE id = current_user_id();
  IF v_user IS NULL THEN RETURN jsonb_build_object('error', 'not_authenticated'); END IF;
  IF NOT employees_can_write() THEN RETURN jsonb_build_object('error', 'permission_denied'); END IF;

  IF jsonb_typeof(p_records) <> 'array' THEN
    RETURN jsonb_build_object('error', 'expected_array');
  END IF;

  FOR v_record IN SELECT * FROM jsonb_array_elements(p_records)
  LOOP
    v_idx := v_idx + 1;
    BEGIN
      -- Adiciona source='xlsx_import' antes de criar
      v_record := v_record || jsonb_build_object('source', 'xlsx_import');
      v_result := rpc_employees_create(v_record);
      IF v_result ? 'error' THEN
        v_errors := v_errors || jsonb_build_array(jsonb_build_object(
          'index', v_idx,
          'error', v_result ->> 'error',
          'full_name', v_record ->> 'full_name'
        ));
      ELSIF (v_result ->> 'already_exists')::BOOLEAN THEN
        v_skipped := v_skipped + 1;
      ELSE
        v_created := v_created + 1;
      END IF;
    EXCEPTION WHEN OTHERS THEN
      v_errors := v_errors || jsonb_build_array(jsonb_build_object(
        'index', v_idx,
        'error', 'exception: ' || SQLERRM,
        'full_name', v_record ->> 'full_name'
      ));
    END;
  END LOOP;

  RETURN jsonb_build_object(
    'ok', TRUE,
    'total', v_idx,
    'created', v_created,
    'skipped', v_skipped,
    'errors', v_errors
  );
END;
$$;

-- ============================================================================
-- GRANTS
-- ============================================================================

GRANT EXECUTE ON FUNCTION
  rpc_employees_list,
  rpc_employees_get_by_id,
  rpc_employees_create,
  rpc_employees_update,
  rpc_employees_salary_add,
  rpc_employees_vacation_add,
  rpc_employees_leave_add,
  rpc_employees_archive,
  rpc_employees_import_xlsx,
  cpf_digits_only,
  employees_can_read,
  employees_can_write
TO authenticated;

-- ============================================================================
-- R2 People · Sessao G3 · RPCs de alteracao de dados pessoais
-- ============================================================================
-- 5 RPCs:
--   - rpc_my_profile_request_create(field, new_value, photo_path?)
--   - rpc_my_profile_requests_list()
--   - rpc_my_profile_request_cancel(request_id)
--   - rpc_profile_requests_pending_list()      [RH+diretoria+SA]
--   - rpc_profile_request_approve(request_id)  [RH+diretoria+SA]
--   - rpc_profile_request_reject(request_id, reason) [RH+diretoria+SA]
--
-- Permissoes:
--   - create/cancel: o proprio colaborador (employee_id da sua app_user)
--   - list (proprias): qualquer authenticated
--   - pending_list/approve/reject: super_admin + diretoria + rh
-- ============================================================================

-- ----------------------------------------------------------------------------
-- Helper: validacao de new_value por field
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION pcr_validate_value(
  p_field profile_change_field,
  p_value JSONB
) RETURNS TEXT
LANGUAGE plpgsql IMMUTABLE
AS $$
DECLARE
  v_str TEXT;
BEGIN
  IF p_value IS NULL THEN RETURN 'value_required'; END IF;

  IF p_field IN ('phone_mobile', 'phone_home') THEN
    v_str := p_value ->> 'value';
    IF v_str IS NULL OR length(trim(v_str)) < 8 THEN RETURN 'phone_invalid'; END IF;
  ELSIF p_field = 'personal_email' THEN
    v_str := p_value ->> 'value';
    IF v_str IS NULL OR v_str !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' THEN RETURN 'email_invalid'; END IF;
  ELSIF p_field = 'residence_address' THEN
    v_str := p_value ->> 'value';
    IF v_str IS NULL OR length(trim(v_str)) < 5 THEN RETURN 'address_invalid'; END IF;
  ELSIF p_field = 'emergency_contact' THEN
    -- Esperado: { name, phone, relation }
    IF (p_value ->> 'name') IS NULL OR length(trim(p_value ->> 'name')) < 2 THEN
      RETURN 'emergency_name_invalid';
    END IF;
    IF (p_value ->> 'phone') IS NULL OR length(trim(p_value ->> 'phone')) < 8 THEN
      RETURN 'emergency_phone_invalid';
    END IF;
    -- relation e opcional
  ELSIF p_field = 'photo' THEN
    -- Esperado: nada significativo no value (o path vai em pending_photo_path)
    NULL;
  ELSE
    RETURN 'unknown_field';
  END IF;
  RETURN NULL;
END;
$$;

-- ----------------------------------------------------------------------------
-- Helper: snapshot do valor atual em employees para old_value
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION pcr_snapshot_current_value(
  p_employee_id UUID,
  p_field profile_change_field
) RETURNS JSONB
LANGUAGE plpgsql STABLE
AS $$
DECLARE
  v_e employees;
BEGIN
  SELECT * INTO v_e FROM employees WHERE id = p_employee_id;
  IF v_e IS NULL THEN RETURN NULL; END IF;

  IF p_field = 'phone_mobile' THEN
    RETURN jsonb_build_object('value', v_e.phone_mobile);
  ELSIF p_field = 'phone_home' THEN
    RETURN jsonb_build_object('value', v_e.phone_home);
  ELSIF p_field = 'personal_email' THEN
    RETURN jsonb_build_object('value', v_e.personal_email);
  ELSIF p_field = 'residence_address' THEN
    RETURN jsonb_build_object('value', v_e.residence_address);
  ELSIF p_field = 'emergency_contact' THEN
    RETURN jsonb_build_object(
      'name',     v_e.emergency_contact_name,
      'phone',    v_e.emergency_contact_phone,
      'relation', v_e.emergency_contact_relation
    );
  ELSIF p_field = 'photo' THEN
    RETURN jsonb_build_object('storage_path', v_e.photo_storage_path);
  END IF;
  RETURN NULL;
END;
$$;

-- ============================================================================
-- rpc_my_profile_request_create
-- ============================================================================
CREATE OR REPLACE FUNCTION rpc_my_profile_request_create(
  p_field             profile_change_field,
  p_new_value         JSONB,
  p_pending_photo_path TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user      app_users;
  v_employee  employees;
  v_validation TEXT;
  v_old_value JSONB;
  v_request_id UUID;
BEGIN
  SELECT * INTO v_user FROM app_users WHERE id = current_user_id();
  IF v_user IS NULL THEN RETURN jsonb_build_object('error', 'not_authenticated'); END IF;
  IF v_user.employee_id IS NULL THEN
    RETURN jsonb_build_object('error', 'employee_not_linked');
  END IF;

  SELECT * INTO v_employee FROM employees
    WHERE id = v_user.employee_id AND archived_at IS NULL
      AND tenant_id = v_user.tenant_id;
  IF v_employee IS NULL THEN
    RETURN jsonb_build_object('error', 'employee_not_found');
  END IF;

  v_validation := pcr_validate_value(p_field, p_new_value);
  IF v_validation IS NOT NULL THEN
    RETURN jsonb_build_object('error', v_validation);
  END IF;

  -- Para 'photo' o pending_photo_path eh obrigatorio
  IF p_field = 'photo' AND p_pending_photo_path IS NULL THEN
    RETURN jsonb_build_object('error', 'photo_path_required');
  END IF;

  v_old_value := pcr_snapshot_current_value(v_employee.id, p_field);

  BEGIN
    INSERT INTO employee_profile_change_requests (
      tenant_id, employee_id, requested_by, field,
      old_value, new_value, pending_photo_path
    )
    VALUES (
      v_user.tenant_id, v_employee.id, v_user.id, p_field,
      v_old_value, p_new_value, p_pending_photo_path
    )
    RETURNING id INTO v_request_id;
  EXCEPTION WHEN unique_violation THEN
    RETURN jsonb_build_object('error', 'pending_request_exists');
  END;

  RETURN jsonb_build_object('ok', TRUE, 'request_id', v_request_id);
END;
$$;
GRANT EXECUTE ON FUNCTION rpc_my_profile_request_create TO authenticated;

-- ============================================================================
-- rpc_my_profile_requests_list
-- ============================================================================
CREATE OR REPLACE FUNCTION rpc_my_profile_requests_list(p_limit INT DEFAULT 20)
RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user app_users;
  v_items JSONB;
  v_safe INT;
BEGIN
  SELECT * INTO v_user FROM app_users WHERE id = current_user_id();
  IF v_user IS NULL THEN RETURN jsonb_build_object('error', 'not_authenticated'); END IF;
  v_safe := GREATEST(1, LEAST(100, COALESCE(p_limit, 20)));

  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'id',                  r.id,
    'field',               r.field,
    'old_value',           r.old_value,
    'new_value',           r.new_value,
    'pending_photo_path',  r.pending_photo_path,
    'status',              r.status,
    'rejection_reason',    r.rejection_reason,
    'reviewed_at',         r.reviewed_at,
    'reviewer_name',       COALESCE(re.full_name, ru.full_name),
    'created_at',          r.created_at
  ) ORDER BY r.created_at DESC), '[]'::JSONB)
  INTO v_items
  FROM (
    SELECT * FROM employee_profile_change_requests
    WHERE requested_by = v_user.id
    ORDER BY created_at DESC
    LIMIT v_safe
  ) r
    LEFT JOIN app_users ru ON ru.id = r.reviewed_by
    LEFT JOIN employees re ON re.id = ru.employee_id AND re.archived_at IS NULL;

  RETURN jsonb_build_object('ok', TRUE, 'items', v_items);
END;
$$;
GRANT EXECUTE ON FUNCTION rpc_my_profile_requests_list TO authenticated;

-- ============================================================================
-- rpc_my_profile_request_cancel
-- ============================================================================
CREATE OR REPLACE FUNCTION rpc_my_profile_request_cancel(p_request_id UUID)
RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user app_users;
  v_req  employee_profile_change_requests;
BEGIN
  SELECT * INTO v_user FROM app_users WHERE id = current_user_id();
  IF v_user IS NULL THEN RETURN jsonb_build_object('error', 'not_authenticated'); END IF;

  SELECT * INTO v_req FROM employee_profile_change_requests WHERE id = p_request_id;
  IF v_req IS NULL THEN RETURN jsonb_build_object('error', 'request_not_found'); END IF;
  IF v_req.tenant_id <> v_user.tenant_id THEN
    RETURN jsonb_build_object('error', 'cross_tenant_blocked');
  END IF;
  IF v_req.requested_by <> v_user.id THEN
    RETURN jsonb_build_object('error', 'permission_denied');
  END IF;
  IF v_req.status <> 'pending' THEN
    RETURN jsonb_build_object('error', 'cannot_cancel_after_review');
  END IF;

  UPDATE employee_profile_change_requests
    SET status = 'canceled', updated_at = now()
    WHERE id = p_request_id;

  RETURN jsonb_build_object('ok', TRUE);
END;
$$;
GRANT EXECUTE ON FUNCTION rpc_my_profile_request_cancel TO authenticated;

-- ============================================================================
-- rpc_profile_requests_pending_list (RH/diretoria/SA)
-- ============================================================================
CREATE OR REPLACE FUNCTION rpc_profile_requests_pending_list()
RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user app_users;
  v_items JSONB;
BEGIN
  SELECT * INTO v_user FROM app_users WHERE id = current_user_id();
  IF v_user IS NULL THEN RETURN jsonb_build_object('error', 'not_authenticated'); END IF;

  IF NOT (is_super_admin() OR v_user.role IN ('diretoria', 'rh')) THEN
    RETURN jsonb_build_object('error', 'permission_denied');
  END IF;

  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'id',                  r.id,
    'employee_id',         r.employee_id,
    'employee_name',       e.full_name,
    'employee_job_title',  e.job_title,
    'field',               r.field,
    'old_value',           r.old_value,
    'new_value',           r.new_value,
    'pending_photo_path',  r.pending_photo_path,
    'requested_by_name',   COALESCE(re.full_name, ru.full_name),
    'created_at',          r.created_at
  ) ORDER BY r.created_at ASC), '[]'::JSONB)
  INTO v_items
  FROM employee_profile_change_requests r
    JOIN employees e ON e.id = r.employee_id
    LEFT JOIN app_users ru ON ru.id = r.requested_by
    LEFT JOIN employees re ON re.id = ru.employee_id AND re.archived_at IS NULL
  WHERE r.tenant_id = v_user.tenant_id
    AND r.status = 'pending';

  RETURN jsonb_build_object('ok', TRUE, 'items', v_items);
END;
$$;
GRANT EXECUTE ON FUNCTION rpc_profile_requests_pending_list TO authenticated;

-- ============================================================================
-- rpc_profile_request_approve
-- ============================================================================
CREATE OR REPLACE FUNCTION rpc_profile_request_approve(p_request_id UUID)
RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user app_users;
  v_req  employee_profile_change_requests;
  v_emp  employees;
  v_new  JSONB;
BEGIN
  SELECT * INTO v_user FROM app_users WHERE id = current_user_id();
  IF v_user IS NULL THEN RETURN jsonb_build_object('error', 'not_authenticated'); END IF;
  IF NOT (is_super_admin() OR v_user.role IN ('diretoria', 'rh')) THEN
    RETURN jsonb_build_object('error', 'permission_denied');
  END IF;

  SELECT * INTO v_req FROM employee_profile_change_requests WHERE id = p_request_id
    FOR UPDATE;
  IF v_req IS NULL THEN RETURN jsonb_build_object('error', 'request_not_found'); END IF;
  IF v_req.tenant_id <> v_user.tenant_id AND NOT is_super_admin() THEN
    RETURN jsonb_build_object('error', 'cross_tenant_blocked');
  END IF;
  IF v_req.status <> 'pending' THEN
    RETURN jsonb_build_object('error', 'already_reviewed');
  END IF;

  SELECT * INTO v_emp FROM employees WHERE id = v_req.employee_id;
  IF v_emp IS NULL OR v_emp.archived_at IS NOT NULL THEN
    RETURN jsonb_build_object('error', 'employee_not_found');
  END IF;

  v_new := v_req.new_value;

  -- Aplica o valor em employees
  IF v_req.field = 'phone_mobile' THEN
    UPDATE employees SET phone_mobile = v_new ->> 'value', updated_at = now()
      WHERE id = v_emp.id;
  ELSIF v_req.field = 'phone_home' THEN
    UPDATE employees SET phone_home = v_new ->> 'value', updated_at = now()
      WHERE id = v_emp.id;
  ELSIF v_req.field = 'personal_email' THEN
    UPDATE employees SET personal_email = v_new ->> 'value', updated_at = now()
      WHERE id = v_emp.id;
  ELSIF v_req.field = 'residence_address' THEN
    UPDATE employees SET residence_address = v_new ->> 'value', updated_at = now()
      WHERE id = v_emp.id;
  ELSIF v_req.field = 'emergency_contact' THEN
    UPDATE employees SET
      emergency_contact_name     = v_new ->> 'name',
      emergency_contact_phone    = v_new ->> 'phone',
      emergency_contact_relation = v_new ->> 'relation',
      updated_at = now()
    WHERE id = v_emp.id;
  ELSIF v_req.field = 'photo' THEN
    UPDATE employees SET
      photo_storage_path = v_req.pending_photo_path,
      updated_at = now()
    WHERE id = v_emp.id;
  END IF;

  UPDATE employee_profile_change_requests
    SET status = 'approved', reviewed_by = v_user.id,
        reviewed_at = now(), updated_at = now()
    WHERE id = p_request_id;

  RETURN jsonb_build_object('ok', TRUE, 'request_id', p_request_id);
END;
$$;
GRANT EXECUTE ON FUNCTION rpc_profile_request_approve TO authenticated;

-- ============================================================================
-- rpc_profile_request_reject
-- ============================================================================
CREATE OR REPLACE FUNCTION rpc_profile_request_reject(
  p_request_id UUID,
  p_reason     TEXT
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user app_users;
  v_req  employee_profile_change_requests;
BEGIN
  SELECT * INTO v_user FROM app_users WHERE id = current_user_id();
  IF v_user IS NULL THEN RETURN jsonb_build_object('error', 'not_authenticated'); END IF;
  IF NOT (is_super_admin() OR v_user.role IN ('diretoria', 'rh')) THEN
    RETURN jsonb_build_object('error', 'permission_denied');
  END IF;

  IF p_reason IS NULL OR length(trim(p_reason)) < 3 THEN
    RETURN jsonb_build_object('error', 'reason_required');
  END IF;

  SELECT * INTO v_req FROM employee_profile_change_requests WHERE id = p_request_id
    FOR UPDATE;
  IF v_req IS NULL THEN RETURN jsonb_build_object('error', 'request_not_found'); END IF;
  IF v_req.tenant_id <> v_user.tenant_id AND NOT is_super_admin() THEN
    RETURN jsonb_build_object('error', 'cross_tenant_blocked');
  END IF;
  IF v_req.status <> 'pending' THEN
    RETURN jsonb_build_object('error', 'already_reviewed');
  END IF;

  UPDATE employee_profile_change_requests
    SET status = 'rejected', reviewed_by = v_user.id,
        reviewed_at = now(), rejection_reason = trim(p_reason),
        updated_at = now()
    WHERE id = p_request_id;

  RETURN jsonb_build_object('ok', TRUE);
END;
$$;
GRANT EXECUTE ON FUNCTION rpc_profile_request_reject TO authenticated;

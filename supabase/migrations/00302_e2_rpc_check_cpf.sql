-- ============================================================================
-- R2 People · Sessao E2 · RPC auxiliar para check de duplicação por CPF
-- ============================================================================
-- Permite ao frontend verificar se um CPF já está cadastrado antes do submit,
-- mostrando "CPF já cadastrado · ver ficha" sem precisar tentar criar e
-- receber um already_exists.
--
-- Permissões: mesma de employees_can_read (todos no tenant veem).
-- ============================================================================

CREATE OR REPLACE FUNCTION rpc_employees_check_cpf(p_cpf TEXT)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user app_users;
  v_existing employees;
  v_cpf_clean TEXT;
BEGIN
  SELECT * INTO v_user FROM app_users WHERE id = current_user_id();
  IF v_user IS NULL THEN RETURN jsonb_build_object('error', 'not_authenticated'); END IF;

  IF NOT employees_can_read() THEN
    RETURN jsonb_build_object('error', 'permission_denied');
  END IF;

  v_cpf_clean := cpf_digits_only(p_cpf);
  IF length(v_cpf_clean) <> 11 THEN
    RETURN jsonb_build_object('ok', TRUE, 'exists', FALSE, 'reason', 'invalid_format');
  END IF;

  -- Busca por CPF (com ou sem mascara) no tenant atual
  SELECT * INTO v_existing
  FROM employees
  WHERE archived_at IS NULL
    AND (is_super_admin() OR tenant_id = v_user.tenant_id)
    AND cpf_digits_only(cpf) = v_cpf_clean
  LIMIT 1;

  IF v_existing IS NULL THEN
    RETURN jsonb_build_object('ok', TRUE, 'exists', FALSE);
  END IF;

  RETURN jsonb_build_object(
    'ok', TRUE,
    'exists', TRUE,
    'id', v_existing.id,
    'full_name', v_existing.full_name,
    'matricula_esocial', v_existing.matricula_esocial,
    'is_active', v_existing.termination_date IS NULL,
    'archived', FALSE
  );
END;
$$;

GRANT EXECUTE ON FUNCTION rpc_employees_check_cpf TO authenticated;

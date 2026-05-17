-- ============================================================================
-- R2 People · Sessao B3 · Navbar dinamica
-- ============================================================================
-- 1 RPC + 1 helper interno
--   - rpc_my_navbar() · retorna lista de itens prontos para a sidebar
--   - my_navbar_items_by_role(role) · helper interno · catalogo fixo por papel
--
-- Decisoes da Sessao B3:
--   - Itens fixos por papel (super_admin/diretoria/rh/lider/colaborador)
--   - Modulo inativo (sem activation): item desaparece do menu
--   - Modulo soft_disabled: item aparece com flag readonly=true
--   - Itens "core" (sem module_code) sempre aparecem se o papel tiver acesso
--   - Layout da sidebar e dependencia do frontend (sidebar colapsavel)
--
-- Pre-requisitos:
--   - Schemas H, H2, J, K, L aplicados
--   - Patches A1, B2 aplicados
--
-- Idempotente.
-- ============================================================================

-- ============================================================================
-- HELPER · my_navbar_items_by_role
-- Catalogo fixo de itens da navbar por papel
-- Retorna SETOF jsonb com a forma:
--   { key, label, icon, path, module_code (nullable), section }
-- A logica de filtragem por modulo_active e flagging de readonly fica na RPC.
-- ============================================================================

CREATE OR REPLACE FUNCTION my_navbar_items_by_role(p_role TEXT)
RETURNS SETOF JSONB
LANGUAGE plpgsql
IMMUTABLE
AS $$
BEGIN
  -- super_admin · ve absolutamente tudo, incluindo gestao global
  IF p_role = 'super_admin' THEN
    RETURN QUERY VALUES
      ('{"key":"home","label":"Inicio","icon":"Home","path":"/","section":"main","module_code":null}'::JSONB),
      ('{"key":"people","label":"Pessoas","icon":"Users","path":"/pessoas","section":"main","module_code":null}'::JSONB),
      ('{"key":"orgchart","label":"Organograma","icon":"Network","path":"/organograma","section":"main","module_code":null}'::JSONB),
      ('{"key":"recognition","label":"Reconhecimentos","icon":"Award","path":"/reconhecimentos","section":"modules","module_code":"recognition"}'::JSONB),
      ('{"key":"pdi","label":"PDI","icon":"TrendingUp","path":"/pdi","section":"modules","module_code":"pdi"}'::JSONB),
      ('{"key":"onboarding","label":"Onboarding","icon":"UserPlus","path":"/onboarding","section":"modules","module_code":"onboarding"}'::JSONB),
      ('{"key":"ninebox","label":"9-Box","icon":"Grid3x3","path":"/ninebox","section":"modules","module_code":"ninebox"}'::JSONB),
      ('{"key":"climate","label":"Clima","icon":"Activity","path":"/clima","section":"modules","module_code":"climate"}'::JSONB),
      ('{"key":"reports","label":"Relatorios","icon":"BarChart3","path":"/relatorios","section":"main","module_code":null}'::JSONB),
      ('{"key":"admin_modules","label":"Modulos","icon":"Layers","path":"/admin/modulos","section":"admin","module_code":null}'::JSONB),
      ('{"key":"admin_tenants","label":"Tenants","icon":"Building2","path":"/admin/tenants","section":"admin","module_code":null}'::JSONB),
      ('{"key":"admin_users","label":"Usuarios","icon":"UserCog","path":"/admin/usuarios","section":"admin","module_code":null}'::JSONB),
      ('{"key":"admin_audit","label":"Auditoria","icon":"FileSearch","path":"/admin/auditoria","section":"admin","module_code":null}'::JSONB);
    RETURN;
  END IF;

  -- diretoria · operacao do tenant + admin de modulos
  IF p_role = 'diretoria' THEN
    RETURN QUERY VALUES
      ('{"key":"home","label":"Inicio","icon":"Home","path":"/","section":"main","module_code":null}'::JSONB),
      ('{"key":"people","label":"Pessoas","icon":"Users","path":"/pessoas","section":"main","module_code":null}'::JSONB),
      ('{"key":"orgchart","label":"Organograma","icon":"Network","path":"/organograma","section":"main","module_code":null}'::JSONB),
      ('{"key":"recognition","label":"Reconhecimentos","icon":"Award","path":"/reconhecimentos","section":"modules","module_code":"recognition"}'::JSONB),
      ('{"key":"pdi","label":"PDI","icon":"TrendingUp","path":"/pdi","section":"modules","module_code":"pdi"}'::JSONB),
      ('{"key":"onboarding","label":"Onboarding","icon":"UserPlus","path":"/onboarding","section":"modules","module_code":"onboarding"}'::JSONB),
      ('{"key":"ninebox","label":"9-Box","icon":"Grid3x3","path":"/ninebox","section":"modules","module_code":"ninebox"}'::JSONB),
      ('{"key":"climate","label":"Clima","icon":"Activity","path":"/clima","section":"modules","module_code":"climate"}'::JSONB),
      ('{"key":"reports","label":"Relatorios","icon":"BarChart3","path":"/relatorios","section":"main","module_code":null}'::JSONB),
      ('{"key":"admin_modules","label":"Modulos","icon":"Layers","path":"/admin/modulos","section":"admin","module_code":null}'::JSONB),
      ('{"key":"admin_users","label":"Usuarios","icon":"UserCog","path":"/admin/usuarios","section":"admin","module_code":null}'::JSONB);
    RETURN;
  END IF;

  -- rh · operacao do dia-a-dia, sem admin de modulos
  IF p_role = 'rh' THEN
    RETURN QUERY VALUES
      ('{"key":"home","label":"Inicio","icon":"Home","path":"/","section":"main","module_code":null}'::JSONB),
      ('{"key":"people","label":"Pessoas","icon":"Users","path":"/pessoas","section":"main","module_code":null}'::JSONB),
      ('{"key":"orgchart","label":"Organograma","icon":"Network","path":"/organograma","section":"main","module_code":null}'::JSONB),
      ('{"key":"recognition","label":"Reconhecimentos","icon":"Award","path":"/reconhecimentos","section":"modules","module_code":"recognition"}'::JSONB),
      ('{"key":"pdi","label":"PDI","icon":"TrendingUp","path":"/pdi","section":"modules","module_code":"pdi"}'::JSONB),
      ('{"key":"onboarding","label":"Onboarding","icon":"UserPlus","path":"/onboarding","section":"modules","module_code":"onboarding"}'::JSONB),
      ('{"key":"ninebox","label":"9-Box","icon":"Grid3x3","path":"/ninebox","section":"modules","module_code":"ninebox"}'::JSONB),
      ('{"key":"climate","label":"Clima","icon":"Activity","path":"/clima","section":"modules","module_code":"climate"}'::JSONB),
      ('{"key":"reports","label":"Relatorios","icon":"BarChart3","path":"/relatorios","section":"main","module_code":null}'::JSONB);
    RETURN;
  END IF;

  -- lider · ve seu time + modulos onde participa como gestor
  IF p_role = 'lider' THEN
    RETURN QUERY VALUES
      ('{"key":"home","label":"Inicio","icon":"Home","path":"/","section":"main","module_code":null}'::JSONB),
      ('{"key":"my_team","label":"Meu Time","icon":"Users","path":"/meu-time","section":"main","module_code":null}'::JSONB),
      ('{"key":"recognition","label":"Reconhecimentos","icon":"Award","path":"/reconhecimentos","section":"modules","module_code":"recognition"}'::JSONB),
      ('{"key":"pdi","label":"PDI","icon":"TrendingUp","path":"/pdi","section":"modules","module_code":"pdi"}'::JSONB),
      ('{"key":"ninebox","label":"9-Box","icon":"Grid3x3","path":"/ninebox","section":"modules","module_code":"ninebox"}'::JSONB),
      ('{"key":"climate","label":"Clima","icon":"Activity","path":"/clima","section":"modules","module_code":"climate"}'::JSONB);
    RETURN;
  END IF;

  -- colaborador · sua area pessoal + auto-avaliacao quando aplicavel
  IF p_role = 'colaborador' THEN
    RETURN QUERY VALUES
      ('{"key":"home","label":"Inicio","icon":"Home","path":"/","section":"main","module_code":null}'::JSONB),
      ('{"key":"my_profile","label":"Meu Perfil","icon":"User","path":"/meu-perfil","section":"main","module_code":null}'::JSONB),
      ('{"key":"recognition","label":"Reconhecimentos","icon":"Award","path":"/reconhecimentos","section":"modules","module_code":"recognition"}'::JSONB),
      ('{"key":"pdi","label":"Meu PDI","icon":"TrendingUp","path":"/pdi","section":"modules","module_code":"pdi"}'::JSONB),
      ('{"key":"ninebox","label":"Auto-avaliacao","icon":"Grid3x3","path":"/ninebox/auto","section":"modules","module_code":"ninebox"}'::JSONB),
      ('{"key":"onboarding","label":"Meu Onboarding","icon":"UserPlus","path":"/onboarding","section":"modules","module_code":"onboarding"}'::JSONB),
      ('{"key":"climate","label":"Pesquisa de Clima","icon":"Activity","path":"/clima","section":"modules","module_code":"climate"}'::JSONB);
    RETURN;
  END IF;

  -- Papel desconhecido: retorna vazio
  RETURN;
END;
$$;

COMMENT ON FUNCTION my_navbar_items_by_role IS 'Sessao B3 · catalogo fixo de itens da navbar por papel · IMMUTABLE';

-- ============================================================================
-- rpc_my_navbar · retorna a navbar pronta para o user logado
-- ============================================================================

CREATE OR REPLACE FUNCTION rpc_my_navbar()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user app_users;
  v_items JSONB := '[]'::JSONB;
  v_item JSONB;
  v_module TEXT;
  v_active BOOLEAN;
  v_readonly BOOLEAN;
BEGIN
  SELECT * INTO v_user FROM app_users WHERE id = current_user_id();
  IF v_user IS NULL THEN
    RETURN jsonb_build_object('error', 'not_authenticated');
  END IF;

  -- Itera o catalogo do papel e filtra/marca conforme estado dos modulos
  FOR v_item IN SELECT * FROM my_navbar_items_by_role(v_user.role::TEXT)
  LOOP
    v_module := v_item ->> 'module_code';

    IF v_module IS NULL THEN
      -- Item core (sem dependencia de modulo) · sempre aparece
      v_items := v_items || jsonb_build_array(
        v_item || jsonb_build_object('readonly', FALSE)
      );
    ELSE
      -- Item de modulo · checa estado
      v_active   := module_is_active_for_user(v_module, v_user.id);
      v_readonly := module_is_readonly_for_user(v_module, v_user.id);

      IF v_active THEN
        -- Modulo ativo: aparece, readonly=false
        v_items := v_items || jsonb_build_array(
          v_item || jsonb_build_object('readonly', FALSE)
        );
      ELSIF v_readonly THEN
        -- Modulo soft_disabled: aparece com flag readonly=true (cadeado no frontend)
        v_items := v_items || jsonb_build_array(
          v_item || jsonb_build_object('readonly', TRUE)
        );
      END IF;
      -- Caso contrario (nao ativo nem readonly): item omitido do resultado
    END IF;
  END LOOP;

  RETURN jsonb_build_object(
    'ok', TRUE,
    'role', v_user.role,
    'items', v_items
  );
END;
$$;

COMMENT ON FUNCTION rpc_my_navbar IS 'Sessao B3 · navbar do user logado · papel define itens base, modulos filtram/marcam readonly';

GRANT EXECUTE ON FUNCTION rpc_my_navbar, my_navbar_items_by_role TO authenticated;

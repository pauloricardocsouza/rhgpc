-- ============================================================================
-- R2 PEOPLE - POLÍTICAS RLS DETALHADAS (PostgreSQL / Supabase)
-- ============================================================================
-- Esta é a implementação completa das políticas Row Level Security que
-- materializam o modelo de visibilidade multidimensional do R2 People.
--
-- Cada usuário tem um permission_profile que define escopo em 4 dimensões:
--   1. employer_scope    : all | specific | self | none
--   2. unit_scope        : all | specific | self | none
--   3. department_scope  : all | specific | self | none
--   4. hierarchy_scope   : all | recursive | direct | self | none
--
-- A regra para um usuário X enxergar o registro de outro usuário Y é:
--   visible(X, Y) = (employer_match) AND (unit_match) AND (dept_match) AND (hierarchy_match)
--
-- Cada match tem semântica própria:
--   employer_match: Y.employer_unit_id está no escopo de empregador de X
--   unit_match:     Y.working_unit_id está no escopo de tomador de X
--   dept_match:     Y.department_id está no escopo de departamento de X
--   hierarchy_match: Y é subordinado de X conforme hierarchy_scope
--
-- Special permissions (override_scope, view_audit) podem ampliar o acesso.
--
-- IMPORTANTE: Este arquivo SUBSTITUI as policies básicas do schema_v3.sql.
-- Execute-o APÓS o schema base para refinar a segurança.
-- ============================================================================

BEGIN;

-- ============================================================================
-- 1. HELPERS REFINADOS DE PERMISSÃO
-- ============================================================================

-- Pega o user_company corrente (vínculo ativo do usuário no tenant ativo).
-- Se o usuário tem múltiplos vínculos no mesmo tenant (raro), pega o primeiro ativo.
CREATE OR REPLACE FUNCTION current_user_company()
RETURNS user_companies
LANGUAGE SQL STABLE SECURITY DEFINER
SET search_path = public AS $$
  SELECT uc.*
    FROM user_companies uc
   WHERE uc.user_id = current_user_id()
     AND uc.company_id = current_user_company_id()
     AND uc.is_active = TRUE
   ORDER BY uc.created_at ASC
   LIMIT 1;
$$;


-- Pega o profile corrente do usuário (já com special_permissions resolvido).
CREATE OR REPLACE FUNCTION current_user_profile()
RETURNS permission_profiles
LANGUAGE SQL STABLE SECURITY DEFINER
SET search_path = public AS $$
  SELECT pp.*
    FROM permission_profiles pp
    JOIN user_companies uc ON uc.permission_profile_id = pp.id
   WHERE uc.user_id = current_user_id()
     AND uc.company_id = current_user_company_id()
     AND uc.is_active = TRUE
   ORDER BY uc.created_at ASC
   LIMIT 1;
$$;


-- ============================================================================
-- 2. CHECAGENS POR DIMENSÃO DE ESCOPO
-- ============================================================================

-- Verifica se o usuário corrente pode ver um registro com determinado employer_unit_id
-- Combina o escopo do profile + os overrides individuais ativos do user_company.
CREATE OR REPLACE FUNCTION can_see_employer(p_employer_unit_id UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path = public AS $$
DECLARE
  v_my_uc      user_companies;
  v_my_profile permission_profiles;
  v_extra_emp  UUID[];
BEGIN
  v_my_uc := current_user_company();
  v_my_profile := current_user_profile();

  IF v_my_uc IS NULL OR v_my_profile IS NULL THEN
    RETURN FALSE;
  END IF;

  -- override_scope dá acesso amplo (super admin temporário, suporte, etc.)
  IF 'override_scope' = ANY(v_my_profile.special_permissions) THEN
    RETURN TRUE;
  END IF;

  -- Aplica modo do profile
  CASE v_my_profile.employer_scope
    WHEN 'all' THEN
      RETURN TRUE;
    WHEN 'self' THEN
      IF v_my_uc.employer_unit_id = p_employer_unit_id THEN RETURN TRUE; END IF;
    WHEN 'specific' THEN
      IF EXISTS (
        SELECT 1 FROM profile_employer_scope pes
         WHERE pes.profile_id = v_my_profile.id
           AND pes.unit_id = p_employer_unit_id
      ) THEN RETURN TRUE; END IF;
    WHEN 'none' THEN
      NULL; -- não retorna true, mas verifica overrides abaixo
    ELSE
      NULL;
  END CASE;

  -- Verifica override individual do user_company (extra_employer_ids)
  SELECT extra_employer_ids INTO v_extra_emp
    FROM user_permission_overrides upo
   WHERE upo.user_company_id = v_my_uc.id
     AND (upo.expires_at IS NULL OR upo.expires_at > now())
   LIMIT 1;

  IF v_extra_emp IS NOT NULL AND p_employer_unit_id = ANY(v_extra_emp) THEN
    RETURN TRUE;
  END IF;

  RETURN FALSE;
END;
$$;

COMMENT ON FUNCTION can_see_employer IS
  'Retorna TRUE se o usuário corrente pode ver registros do empregador X.
   Considera profile.employer_scope + special_permissions + extra_employer_ids do override individual.';


-- Verifica se o usuário corrente pode ver um registro com determinado working_unit_id
CREATE OR REPLACE FUNCTION can_see_unit(p_working_unit_id UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path = public AS $$
DECLARE
  v_my_uc      user_companies;
  v_my_profile permission_profiles;
  v_extra_units UUID[];
BEGIN
  v_my_uc := current_user_company();
  v_my_profile := current_user_profile();

  IF v_my_uc IS NULL OR v_my_profile IS NULL THEN
    RETURN FALSE;
  END IF;

  IF 'override_scope' = ANY(v_my_profile.special_permissions) THEN
    RETURN TRUE;
  END IF;

  CASE v_my_profile.unit_scope
    WHEN 'all' THEN
      RETURN TRUE;
    WHEN 'self' THEN
      IF v_my_uc.working_unit_id = p_working_unit_id THEN RETURN TRUE; END IF;
    WHEN 'specific' THEN
      -- Match direto
      IF EXISTS (
        SELECT 1 FROM profile_unit_scope pus
         WHERE pus.profile_id = v_my_profile.id
           AND pus.unit_id = p_working_unit_id
      ) THEN RETURN TRUE; END IF;
      -- Também aceita unidades filhas (gerente regional vê todas as filiais sob ele)
      IF EXISTS (
        SELECT 1
          FROM profile_unit_scope pus
          JOIN v_unit_descendants vud ON vud.root_id = pus.unit_id
         WHERE pus.profile_id = v_my_profile.id
           AND vud.unit_id = p_working_unit_id
      ) THEN RETURN TRUE; END IF;
    WHEN 'none' THEN
      NULL;
    ELSE
      NULL;
  END CASE;

  -- Override individual
  SELECT extra_unit_ids INTO v_extra_units
    FROM user_permission_overrides upo
   WHERE upo.user_company_id = v_my_uc.id
     AND (upo.expires_at IS NULL OR upo.expires_at > now())
   LIMIT 1;

  IF v_extra_units IS NOT NULL AND p_working_unit_id = ANY(v_extra_units) THEN
    RETURN TRUE;
  END IF;

  RETURN FALSE;
END;
$$;


-- Verifica escopo de departamento. Suporta hierarquia recursiva quando
-- profile_department_scope.recursive = TRUE.
CREATE OR REPLACE FUNCTION can_see_department(p_department_id UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path = public AS $$
DECLARE
  v_my_uc      user_companies;
  v_my_profile permission_profiles;
BEGIN
  v_my_uc := current_user_company();
  v_my_profile := current_user_profile();

  IF v_my_uc IS NULL OR v_my_profile IS NULL THEN
    RETURN FALSE;
  END IF;

  IF 'override_scope' = ANY(v_my_profile.special_permissions) THEN
    RETURN TRUE;
  END IF;

  -- NULL em department_id é considerado visível para 'all' e 'specific' não-recursivo,
  -- mas não para 'self' (sem dept não há "próprio departamento")
  IF p_department_id IS NULL THEN
    IF v_my_profile.department_scope IN ('all', 'none') THEN
      RETURN v_my_profile.department_scope = 'all';
    END IF;
    RETURN FALSE;
  END IF;

  CASE v_my_profile.department_scope
    WHEN 'all' THEN
      RETURN TRUE;
    WHEN 'self' THEN
      IF v_my_uc.department_id = p_department_id THEN RETURN TRUE; END IF;
    WHEN 'specific' THEN
      -- Match direto
      IF EXISTS (
        SELECT 1 FROM profile_department_scope pds
         WHERE pds.profile_id = v_my_profile.id
           AND pds.department_id = p_department_id
      ) THEN RETURN TRUE; END IF;
      -- Match recursivo (sub-departamentos)
      IF EXISTS (
        WITH RECURSIVE descendants AS (
          SELECT pds.department_id, pds.recursive
            FROM profile_department_scope pds
           WHERE pds.profile_id = v_my_profile.id
          UNION ALL
          SELECT d.id, dr.recursive
            FROM departments d
            JOIN descendants dr ON d.parent_id = dr.department_id
           WHERE dr.recursive = TRUE
        )
        SELECT 1 FROM descendants WHERE department_id = p_department_id
      ) THEN RETURN TRUE; END IF;
    WHEN 'none' THEN
      NULL;
    ELSE
      NULL;
  END CASE;

  RETURN FALSE;
END;
$$;


-- Verifica escopo de hierarquia (relação líder ↔ liderado)
CREATE OR REPLACE FUNCTION can_see_hierarchy(p_user_id UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path = public AS $$
DECLARE
  v_my_uc      user_companies;
  v_my_profile permission_profiles;
BEGIN
  v_my_uc := current_user_company();
  v_my_profile := current_user_profile();

  IF v_my_uc IS NULL OR v_my_profile IS NULL THEN
    RETURN FALSE;
  END IF;

  IF 'override_scope' = ANY(v_my_profile.special_permissions) THEN
    RETURN TRUE;
  END IF;

  -- Eu mesmo sempre é "self"
  IF p_user_id = current_user_id() THEN
    RETURN TRUE;
  END IF;

  CASE v_my_profile.hierarchy_scope
    WHEN 'all' THEN
      RETURN TRUE;
    WHEN 'self' THEN
      RETURN FALSE;  -- só vê a si mesmo (já tratado acima)
    WHEN 'direct' THEN
      RETURN EXISTS (
        SELECT 1 FROM user_companies uc
         WHERE uc.user_id = p_user_id
           AND uc.company_id = v_my_uc.company_id
           AND uc.manager_user_id = current_user_id()
           AND uc.is_active = TRUE
      );
    WHEN 'recursive' THEN
      -- CTE recursiva: subordinados diretos + indiretos
      RETURN EXISTS (
        WITH RECURSIVE chain AS (
          SELECT uc.user_id
            FROM user_companies uc
           WHERE uc.manager_user_id = current_user_id()
             AND uc.company_id = v_my_uc.company_id
             AND uc.is_active = TRUE
          UNION ALL
          SELECT uc2.user_id
            FROM user_companies uc2
            JOIN chain c ON uc2.manager_user_id = c.user_id
           WHERE uc2.company_id = v_my_uc.company_id
             AND uc2.is_active = TRUE
        )
        SELECT 1 FROM chain WHERE user_id = p_user_id
      );
    WHEN 'none' THEN
      RETURN FALSE;
    ELSE
      RETURN FALSE;
  END CASE;
END;
$$;


-- ============================================================================
-- 3. FUNÇÃO MASTER DE VISIBILIDADE
-- ============================================================================
-- Esta é a função que materializa toda a regra. Recebe os 4 IDs do registro
-- alvo e retorna TRUE se o usuário corrente pode vê-lo.
-- A regra é: TODOS os 4 escopos devem retornar TRUE simultaneamente.
-- A função é otimizada para curto-circuito (false-fail-fast).
-- ============================================================================

CREATE OR REPLACE FUNCTION can_see_user_company(
  p_target_user_id        UUID,
  p_target_employer_id    UUID,
  p_target_working_id     UUID,
  p_target_department_id  UUID
) RETURNS BOOLEAN
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path = public AS $$
DECLARE
  v_my_uc      user_companies;
  v_my_profile permission_profiles;
BEGIN
  v_my_uc := current_user_company();
  v_my_profile := current_user_profile();

  IF v_my_uc IS NULL OR v_my_profile IS NULL THEN
    RETURN FALSE;
  END IF;

  -- Atalho 1: o próprio registro
  IF p_target_user_id = current_user_id() THEN
    RETURN TRUE;
  END IF;

  -- Atalho 2: override_scope
  IF 'override_scope' = ANY(v_my_profile.special_permissions) THEN
    RETURN TRUE;
  END IF;

  -- Atalho 3: subordinado direto/indireto SEMPRE é visível, independente
  -- dos outros 3 escopos. Líder vê seu time mesmo que esteja em outro tomador.
  IF v_my_profile.hierarchy_scope IN ('direct', 'recursive', 'all')
     AND can_see_hierarchy(p_target_user_id) THEN
    RETURN TRUE;
  END IF;

  -- Regra principal: AND dos 4 escopos
  -- Curto-circuito: para no primeiro FALSE.
  IF NOT can_see_employer(p_target_employer_id) THEN
    RETURN FALSE;
  END IF;

  IF NOT can_see_unit(p_target_working_id) THEN
    RETURN FALSE;
  END IF;

  IF NOT can_see_department(p_target_department_id) THEN
    RETURN FALSE;
  END IF;

  -- hierarchy_match: se chegou aqui sem hierarquia, exige all
  IF v_my_profile.hierarchy_scope = 'all' THEN
    RETURN TRUE;
  END IF;

  RETURN FALSE;
END;
$$;

COMMENT ON FUNCTION can_see_user_company IS
  'Função-master de visibilidade. Retorna TRUE se o usuário corrente pode ver
   um registro de user_companies com os IDs alvo informados. Combina os 4 escopos com AND.
   Subordinados (hierarchy) sempre visíveis independente dos outros escopos.';



-- ============================================================================
-- 4. POLICIES POR TABELA
-- ============================================================================
-- Limpa policies anteriores e recria com a nova lógica multidimensional.
-- ============================================================================

-- Drop policies anteriores das tabelas que vamos refinar
DROP POLICY IF EXISTS user_companies_visibility    ON user_companies;
DROP POLICY IF EXISTS tenant_isolation_units       ON units;
DROP POLICY IF EXISTS tenant_isolation_departments ON departments;
DROP POLICY IF EXISTS tenant_isolation_positions   ON positions;
DROP POLICY IF EXISTS tenant_isolation_competencies ON competencies;
DROP POLICY IF EXISTS tenant_isolation_cycles      ON review_cycles;
DROP POLICY IF EXISTS notif_owner_only             ON notifications;
DROP POLICY IF EXISTS feedback_visibility          ON feedbacks;
DROP POLICY IF EXISTS audit_log_visibility         ON audit_log;


-- ----------------------------------------------------------------------------
-- 4.1 user_companies · coração da visibilidade do produto
-- ----------------------------------------------------------------------------
-- Policy SELECT: aplica a função master.
-- Policy INSERT/UPDATE: requer permissão admin (special_permissions inclui
-- approve_movements ou import_csv) ou ser o RH responsável pelo empregador.

CREATE POLICY user_companies_select ON user_companies
  FOR SELECT
  USING (
    company_id = current_user_company_id()
    AND can_see_user_company(user_id, employer_unit_id, working_unit_id, department_id)
  );

CREATE POLICY user_companies_insert ON user_companies
  FOR INSERT
  WITH CHECK (
    company_id = current_user_company_id()
    AND (
      current_user_has_permission('import_csv')
      OR current_user_has_permission('approve_movements')
      OR (
        -- RH da prestadora pode criar vínculos do próprio empregador
        EXISTS (
          SELECT 1 FROM permission_profiles pp
            JOIN user_companies myuc ON myuc.permission_profile_id = pp.id
           WHERE myuc.user_id = current_user_id()
             AND myuc.company_id = current_user_company_id()
             AND myuc.is_active = TRUE
             AND pp.employer_scope = 'specific'
             AND EXISTS (
               SELECT 1 FROM profile_employer_scope pes
                WHERE pes.profile_id = pp.id
                  AND pes.unit_id = NEW.employer_unit_id
             )
        )
      )
    )
  );

CREATE POLICY user_companies_update ON user_companies
  FOR UPDATE
  USING (
    company_id = current_user_company_id()
    AND can_see_user_company(user_id, employer_unit_id, working_unit_id, department_id)
    AND (
      current_user_has_permission('approve_movements')
      OR (manager_user_id = current_user_id())  -- gestor direto pode editar
      OR user_id = current_user_id()             -- o próprio pode editar campos limitados
    )
  );

CREATE POLICY user_companies_delete ON user_companies
  FOR DELETE
  USING (
    company_id = current_user_company_id()
    AND current_user_has_permission('approve_movements')
  );


-- ----------------------------------------------------------------------------
-- 4.2 users · tabela global de pessoas
-- ----------------------------------------------------------------------------
-- Visibilidade derivada: vejo um user se vejo PELO MENOS UM user_company dele
-- no tenant atual.

ALTER TABLE users ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS users_select ON users;
CREATE POLICY users_select ON users
  FOR SELECT
  USING (
    id = current_user_id()
    OR EXISTS (
      SELECT 1 FROM user_companies uc
       WHERE uc.user_id = users.id
         AND uc.company_id = current_user_company_id()
         AND can_see_user_company(uc.user_id, uc.employer_unit_id, uc.working_unit_id, uc.department_id)
    )
  );

DROP POLICY IF EXISTS users_update_self ON users;
CREATE POLICY users_update_self ON users
  FOR UPDATE
  USING (
    id = current_user_id()
    OR current_user_has_permission('reset_passwords')
  );


-- ----------------------------------------------------------------------------
-- 4.3 units, departments, positions · estruturais (tenant-isolated)
-- ----------------------------------------------------------------------------
-- Estes são metadados estruturais visíveis a TODOS os usuários do tenant
-- (todos precisam ver o nome da própria filial, departamento, etc.).
-- Edição requer permissão administrativa.

CREATE POLICY units_select ON units
  FOR SELECT
  USING (company_id = current_user_company_id());

CREATE POLICY units_modify ON units
  FOR ALL
  USING (
    company_id = current_user_company_id()
    AND (current_user_has_permission('manage_profiles') OR current_user_has_permission('approve_movements'))
  );


CREATE POLICY departments_select ON departments
  FOR SELECT
  USING (company_id = current_user_company_id());

CREATE POLICY departments_modify ON departments
  FOR ALL
  USING (
    company_id = current_user_company_id()
    AND (current_user_has_permission('manage_profiles') OR current_user_has_permission('approve_movements'))
  );


CREATE POLICY positions_select ON positions
  FOR SELECT
  USING (company_id = current_user_company_id());

CREATE POLICY positions_modify ON positions
  FOR ALL
  USING (
    company_id = current_user_company_id()
    AND (current_user_has_permission('manage_profiles') OR current_user_has_permission('approve_movements'))
  );


-- ----------------------------------------------------------------------------
-- 4.4 permission_profiles e profile_*_scope · só admins enxergam
-- ----------------------------------------------------------------------------

DROP POLICY IF EXISTS profiles_select ON permission_profiles;
CREATE POLICY profiles_select ON permission_profiles
  FOR SELECT
  USING (
    company_id = current_user_company_id()
    AND (
      current_user_has_permission('manage_profiles')
      OR current_user_has_permission('view_audit')
      OR id = (SELECT permission_profile_id FROM current_user_company())
    )
  );

DROP POLICY IF EXISTS profiles_modify ON permission_profiles;
CREATE POLICY profiles_modify ON permission_profiles
  FOR ALL
  USING (
    company_id = current_user_company_id()
    AND current_user_has_permission('manage_profiles')
    AND is_system = FALSE  -- profiles system NÃO podem ser editados
  );


-- profile_page_permissions, profile_employer_scope, profile_unit_scope, profile_department_scope:
-- mesma regra que permission_profiles
CREATE POLICY ppp_select ON profile_page_permissions FOR SELECT
  USING (EXISTS (SELECT 1 FROM permission_profiles pp WHERE pp.id = profile_id AND pp.company_id = current_user_company_id()));
CREATE POLICY ppp_modify ON profile_page_permissions FOR ALL
  USING (current_user_has_permission('manage_profiles'));

CREATE POLICY pes_select ON profile_employer_scope FOR SELECT
  USING (EXISTS (SELECT 1 FROM permission_profiles pp WHERE pp.id = profile_id AND pp.company_id = current_user_company_id()));
CREATE POLICY pes_modify ON profile_employer_scope FOR ALL
  USING (current_user_has_permission('manage_profiles'));

CREATE POLICY pus_select ON profile_unit_scope FOR SELECT
  USING (EXISTS (SELECT 1 FROM permission_profiles pp WHERE pp.id = profile_id AND pp.company_id = current_user_company_id()));
CREATE POLICY pus_modify ON profile_unit_scope FOR ALL
  USING (current_user_has_permission('manage_profiles'));

CREATE POLICY pds_select ON profile_department_scope FOR SELECT
  USING (EXISTS (SELECT 1 FROM permission_profiles pp WHERE pp.id = profile_id AND pp.company_id = current_user_company_id()));
CREATE POLICY pds_modify ON profile_department_scope FOR ALL
  USING (current_user_has_permission('manage_profiles'));


-- user_permission_overrides: visíveis para quem concedeu, para o próprio user
-- e para auditoria.
DROP POLICY IF EXISTS upo_select ON user_permission_overrides;
CREATE POLICY upo_select ON user_permission_overrides
  FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM user_companies uc
       WHERE uc.id = user_company_id
         AND (uc.user_id = current_user_id()
              OR current_user_has_permission('manage_profiles')
              OR current_user_has_permission('view_audit')
         )
    )
  );

DROP POLICY IF EXISTS upo_modify ON user_permission_overrides;
CREATE POLICY upo_modify ON user_permission_overrides
  FOR ALL
  USING (current_user_has_permission('manage_profiles'));


-- ----------------------------------------------------------------------------
-- 4.5 Avaliação: cycles, reviews, review_answers, nine_box
-- ----------------------------------------------------------------------------

CREATE POLICY cycles_select ON review_cycles
  FOR SELECT
  USING (company_id = current_user_company_id());

CREATE POLICY cycles_modify ON review_cycles
  FOR ALL
  USING (
    company_id = current_user_company_id()
    AND current_user_has_permission('manage_cycles')
  );


-- cycle_competencies: deriva de review_cycles
DROP POLICY IF EXISTS cc_select ON cycle_competencies;
CREATE POLICY cc_select ON cycle_competencies
  FOR SELECT
  USING (EXISTS (SELECT 1 FROM review_cycles c WHERE c.id = cycle_id AND c.company_id = current_user_company_id()));

DROP POLICY IF EXISTS cc_modify ON cycle_competencies;
CREATE POLICY cc_modify ON cycle_competencies
  FOR ALL
  USING (current_user_has_permission('manage_cycles'));


-- reviews: visível para o avaliado, o avaliador e quem tem visibilidade do
-- avaliado pelo modelo multidimensional.
DROP POLICY IF EXISTS reviews_select ON reviews;
CREATE POLICY reviews_select ON reviews
  FOR SELECT
  USING (
    -- Sou o avaliado
    evaluatee_id = current_user_id()
    -- Sou o avaliador
    OR evaluator_id = current_user_id()
    -- Vejo o avaliado pelo modelo multi-dimensional
    OR EXISTS (
      SELECT 1 FROM user_companies uc
       WHERE uc.user_id = reviews.evaluatee_id
         AND uc.company_id = current_user_company_id()
         AND can_see_user_company(uc.user_id, uc.employer_unit_id, uc.working_unit_id, uc.department_id)
    )
  );

-- Apenas o avaliador escolhido pode editar (e o próprio para self-eval)
DROP POLICY IF EXISTS reviews_modify ON reviews;
CREATE POLICY reviews_modify ON reviews
  FOR UPDATE
  USING (
    evaluator_id = current_user_id()
    OR (kind = 'self' AND evaluatee_id = current_user_id())
    OR current_user_has_permission('manage_cycles')
  );


-- review_answers: deriva de reviews
DROP POLICY IF EXISTS ra_select ON review_answers;
CREATE POLICY ra_select ON review_answers
  FOR SELECT
  USING (EXISTS (SELECT 1 FROM reviews r WHERE r.id = review_id));

DROP POLICY IF EXISTS ra_modify ON review_answers;
CREATE POLICY ra_modify ON review_answers
  FOR ALL
  USING (
    EXISTS (
      SELECT 1 FROM reviews r
       WHERE r.id = review_id
         AND (r.evaluator_id = current_user_id()
              OR (r.kind = 'self' AND r.evaluatee_id = current_user_id())
              OR current_user_has_permission('manage_cycles'))
    )
  );


-- nine_box_positions: visível como reviews; só gestor + RH posicionam
DROP POLICY IF EXISTS nb_select ON nine_box_positions;
CREATE POLICY nb_select ON nine_box_positions
  FOR SELECT
  USING (
    -- Sou o avaliado e a empresa permite que eu veja meu 9-Box
    (
      user_id = current_user_id()
      AND EXISTS (
        SELECT 1 FROM companies c
         WHERE c.id = current_user_company_id()
           AND COALESCE(c.settings->>'nine_box_visible_to_employee', 'false')::BOOLEAN = TRUE
      )
    )
    -- Sou líder do avaliado (qualquer nível)
    OR can_see_hierarchy(user_id)
    -- Tenho permissão de gerenciar ciclos (RH/admin)
    OR current_user_has_permission('manage_cycles')
  );


-- ----------------------------------------------------------------------------
-- 4.6 Feedback contínuo e mural
-- ----------------------------------------------------------------------------

-- Feedbacks privados: só destinatário, remetente e RH com view_audit
-- Feedbacks públicos: todos do tenant veem
CREATE POLICY feedback_select ON feedbacks
  FOR SELECT
  USING (
    company_id = current_user_company_id()
    AND (
      is_private = FALSE
      OR to_user_id = current_user_id()
      OR (from_user_id = current_user_id() AND is_anonymous = FALSE)
      OR current_user_has_permission('view_audit')
    )
  );

DROP POLICY IF EXISTS feedback_insert ON feedbacks;
CREATE POLICY feedback_insert ON feedbacks
  FOR INSERT
  WITH CHECK (
    company_id = current_user_company_id()
    AND (
      from_user_id = current_user_id()  -- mesmo se anônimo, registramos quem enviou
      OR (is_anonymous = TRUE AND from_user_id IS NULL)
    )
  );


-- feedback_requests
DROP POLICY IF EXISTS fr_select ON feedback_requests;
CREATE POLICY fr_select ON feedback_requests
  FOR SELECT
  USING (
    company_id = current_user_company_id()
    AND (requester_id = current_user_id() OR asked_to_id = current_user_id())
  );

DROP POLICY IF EXISTS fr_insert ON feedback_requests;
CREATE POLICY fr_insert ON feedback_requests
  FOR INSERT
  WITH CHECK (company_id = current_user_company_id() AND requester_id = current_user_id());


-- praises: TODOS do tenant veem (mural público)
DROP POLICY IF EXISTS praises_select ON praises;
CREATE POLICY praises_select ON praises
  FOR SELECT
  USING (company_id = current_user_company_id());

DROP POLICY IF EXISTS praises_insert ON praises;
CREATE POLICY praises_insert ON praises
  FOR INSERT
  WITH CHECK (
    company_id = current_user_company_id()
    AND from_user_id = current_user_id()
  );


-- praise_reactions: visíveis para quem vê o praise; cada user gerencia as próprias
DROP POLICY IF EXISTS pr_select ON praise_reactions;
CREATE POLICY pr_select ON praise_reactions
  FOR SELECT
  USING (
    EXISTS (SELECT 1 FROM praises p WHERE p.id = praise_id AND p.company_id = current_user_company_id())
  );

DROP POLICY IF EXISTS pr_modify ON praise_reactions;
CREATE POLICY pr_modify ON praise_reactions
  FOR ALL
  USING (user_id = current_user_id());


-- ----------------------------------------------------------------------------
-- 4.7 Movimentações de pessoal · workflow tripartite
-- ----------------------------------------------------------------------------
-- Visibilidade:
--   1. Solicitante sempre vê
--   2. Afetado (target user_company) sempre vê após aprovação
--   3. Manager do afetado vê para aprovar
--   4. RH com approve_movements vê tudo do tenant
-- ----------------------------------------------------------------------------

DROP POLICY IF EXISTS mov_select ON personnel_movements;
CREATE POLICY mov_select ON personnel_movements
  FOR SELECT
  USING (
    company_id = current_user_company_id()
    AND (
      requested_by_user_id = current_user_id()
      OR EXISTS (
        SELECT 1 FROM user_companies uc
         WHERE uc.id = user_company_id
           AND (
             uc.user_id = current_user_id()
             OR uc.manager_user_id = current_user_id()
             OR can_see_user_company(uc.user_id, uc.employer_unit_id, uc.working_unit_id, uc.department_id)
           )
      )
      OR current_user_has_permission('approve_movements')
    )
  );

DROP POLICY IF EXISTS mov_insert ON personnel_movements;
CREATE POLICY mov_insert ON personnel_movements
  FOR INSERT
  WITH CHECK (
    company_id = current_user_company_id()
    AND requested_by_user_id = current_user_id()
  );

DROP POLICY IF EXISTS mov_update ON personnel_movements;
CREATE POLICY mov_update ON personnel_movements
  FOR UPDATE
  USING (
    company_id = current_user_company_id()
    AND (
      -- Solicitante pode editar enquanto draft
      (requested_by_user_id = current_user_id() AND status = 'draft')
      -- Manager do afetado pode aprovar/rejeitar quando pending_manager
      OR (
        EXISTS (SELECT 1 FROM user_companies uc WHERE uc.id = user_company_id AND uc.manager_user_id = current_user_id())
        AND status = 'pending_manager'
      )
      -- RH sempre pode (com permission approve_movements)
      OR current_user_has_permission('approve_movements')
    )
  );


-- ----------------------------------------------------------------------------
-- 4.8 Imports · só quem rodou + RH
-- ----------------------------------------------------------------------------

DROP POLICY IF EXISTS imp_select ON imports;
CREATE POLICY imp_select ON imports
  FOR SELECT
  USING (
    company_id = current_user_company_id()
    AND (
      imported_by_user_id = current_user_id()
      OR current_user_has_permission('import_csv')
      OR current_user_has_permission('view_audit')
    )
  );

DROP POLICY IF EXISTS imp_insert ON imports;
CREATE POLICY imp_insert ON imports
  FOR INSERT
  WITH CHECK (
    company_id = current_user_company_id()
    AND imported_by_user_id = current_user_id()
    AND current_user_has_permission('import_csv')
  );


-- ----------------------------------------------------------------------------
-- 4.9 Audit log · extremamente restrito (LGPD)
-- ----------------------------------------------------------------------------
-- Cada user vê apenas:
--   - Suas próprias ações (transparência LGPD - direito de acesso)
--   - DPO/auditor com view_audit vê tudo
-- ----------------------------------------------------------------------------

CREATE POLICY audit_select ON audit_log
  FOR SELECT
  USING (
    (company_id = current_user_company_id() OR company_id IS NULL)
    AND (
      actor_user_id = current_user_id()
      OR current_user_has_permission('view_audit')
    )
  );

-- Audit log é APPEND-ONLY: ninguém pode atualizar nem deletar
-- (A imutabilidade é garantida ainda por: trigger BEFORE UPDATE/DELETE que rejeita)
DROP TRIGGER IF EXISTS audit_log_immutable ON audit_log;
CREATE OR REPLACE FUNCTION trg_reject_audit_modification()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  RAISE EXCEPTION 'audit_log is append-only. Modification denied (LGPD Art. 37).';
END;
$$;
CREATE TRIGGER audit_log_immutable
  BEFORE UPDATE OR DELETE ON audit_log
  FOR EACH ROW EXECUTE FUNCTION trg_reject_audit_modification();


-- ----------------------------------------------------------------------------
-- 4.10 Notifications · cada user só vê as próprias
-- ----------------------------------------------------------------------------

CREATE POLICY notif_owner ON notifications
  FOR ALL
  USING (
    to_user_id = current_user_id()
    AND company_id = current_user_company_id()
  );


-- ----------------------------------------------------------------------------
-- 4.11 Companies · usuário só vê o próprio tenant
-- ----------------------------------------------------------------------------

ALTER TABLE companies ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS companies_select ON companies;
CREATE POLICY companies_select ON companies
  FOR SELECT
  USING (id = current_user_company_id());

DROP POLICY IF EXISTS companies_update ON companies;
CREATE POLICY companies_update ON companies
  FOR UPDATE
  USING (
    id = current_user_company_id()
    AND current_user_has_permission('manage_profiles')
  );


COMMIT;



-- ============================================================================
-- 5. CENÁRIOS DE TESTE · VALIDAÇÃO DAS POLICIES
-- ============================================================================
-- Os comentários a seguir documentam o comportamento esperado em casos
-- reais do GPC. Use estes cenários para criar testes de regressão.
-- ============================================================================

/*
═══════════════════════════════════════════════════════════════════════════════
CENÁRIO 1 · Fernanda Lima (Colaboradora · perfil "colaborador")
═══════════════════════════════════════════════════════════════════════════════
Profile: colaborador (employer=self, unit=self, dept=self, hierarchy=self)
Empregador: Labuta · Tomador: Cestão L1 · Depto: Financeiro · Manager: João Carvalho

DEVE VER:
  ✓ A si mesma (atalho 1)
  ✓ Reviews onde é evaluatee ou evaluator
  ✓ Feedbacks privados recebidos ou enviados por ela
  ✓ Todos os praises (mural público)
  ✓ Suas próprias notifications
  ✓ Auditoria das suas próprias ações
  ✓ Companies, units, departments, positions (metadados estruturais)

NÃO DEVE VER:
  ✗ Outros colaboradores (nenhum vínculo de hierarquia)
  ✗ Salário do Carlos Eduardo (também Labuta no Cestão L1)
  ✗ Reviews de terceiros
  ✗ Movimentações de outros
  ✗ Auditoria de outros usuários
  ✗ Permission profiles (a não ser o seu próprio)


═══════════════════════════════════════════════════════════════════════════════
CENÁRIO 2 · João Carvalho (Líder Financeiro · perfil "lider")
═══════════════════════════════════════════════════════════════════════════════
Profile: lider (employer=all, unit=all, dept=all, hierarchy=recursive)
Subordinados diretos: Beatriz Lopes, Helena Cardoso, Fernanda Lima, Daniela Vieira,
                      Gabriel Pinto, Natália Ferreira

DEVE VER:
  ✓ Todos os 6 subordinados diretos (atalho 3 hierarquia)
  ✓ Subordinados indiretos (se houver na cadeia)
  ✓ Reviews dos liderados em qualquer ciclo
  ✓ Movimentações pendentes para sua decisão (status=pending_manager)
  ✓ Movimentações que ele criou
  ✓ Feedbacks que enviou ou recebeu

NÃO DEVE VER:
  ✗ Salários de pessoas fora da cadeia dele (ex: Pedro Lima da ATP-Varejo)
  ✗ Permission profiles (não tem manage_profiles)
  ✗ Imports de outros usuários
  ✗ Auditoria geral da empresa (apenas suas ações)

EDGE CASE · atalho 3 da função-master:
  Mesmo se Helena Cardoso fosse mudada para outro tomador, o João continuaria
  vendo ela porque "subordinado direto sempre é visível, independente dos outros 3 escopos".


═══════════════════════════════════════════════════════════════════════════════
CENÁRIO 3 · Larissa Pereira (RH da Labuta · perfil "rh_prestadora_labuta")
═══════════════════════════════════════════════════════════════════════════════
Profile: rh_prestadora_labuta
  employer_scope = specific:[Labuta]
  unit_scope     = all
  dept_scope     = all
  hierarchy_scope = all
Special permissions: approve_movements, export_sensitive

DEVE VER:
  ✓ Os 247 colaboradores cuja employer = Labuta (em qualquer filial GPC)
  ✓ Salário, dados bancários e CPF deles (via export_sensitive)
  ✓ Movimentações pendentes desses 247
  ✓ Pode aprovar movimentações deles

NÃO DEVE VER:
  ✗ Colaboradores GPC próprios (employer = GPC-MAT, fora do escopo)
  ✗ Colaboradores Limpactiva ou Segure
  ✗ Permission profiles (não tem manage_profiles)
  ✗ Audit log geral

QUERY MENTAL para validar:
  "SELECT COUNT(*) FROM user_companies WHERE company_id = GPC"
   deve retornar 247 (apenas Labuta).


═══════════════════════════════════════════════════════════════════════════════
CENÁRIO 4 · Sandra Gomes (Gerente Cestão L1 · perfil "gerente_filial_cestao_l1")
═══════════════════════════════════════════════════════════════════════════════
Profile: gerente_filial_cestao_l1
  employer_scope = all
  unit_scope     = specific:[Cestão L1]
  dept_scope     = all
  hierarchy_scope = recursive

DEVE VER:
  ✓ Todos os 91 colaboradores que TRABALHAM no Cestão L1, INDEPENDENTE de empregador
    (11 GPC + 63 Labuta + 9 Limpactiva + 8 Segure)
  ✓ Reviews dos 91 (ela avalia os de hierarquia direta + vê os outros para contexto)
  ✓ Pode aprovar movimentações de subordinados diretos

EDGE CASE INTERESSANTE:
  José da Silva (auxiliar limpeza Limpactiva, alocado Cestão L1) é VISÍVEL para Sandra
  via o filtro de unit_scope=specific=[Cestão L1], MAS Sandra NÃO é manager dele
  (manager_user_id = NULL na user_companies, gestão da Limpactiva é externa).
  Por isso Sandra pode VER mas NÃO pode aprovar movimentações de José.

NÃO DEVE VER:
  ✗ Colaboradores que trabalham em ATP-Varejo (mesmo que sejam da Labuta)
  ✗ Outros gerentes


═══════════════════════════════════════════════════════════════════════════════
CENÁRIO 5 · Carla Moreira (DPO/Auditor · perfil "auditor_dpo")
═══════════════════════════════════════════════════════════════════════════════
Profile: auditor_dpo (todos all + special_permissions=[view_audit, export_sensitive])

DEVE VER:
  ✓ Audit log COMPLETO do tenant (única persona que vê tudo)
  ✓ User_companies de todos (para investigar DSAR)
  ✓ Feedbacks privados (sob view_audit, com auditoria do próprio acesso registrada!)

OBSERVAÇÃO IMPORTANTE:
  O acesso da Carla a feedbacks privados ou dados sensíveis DEVE gerar entrada
  em audit_log com action='view_sensitive'. Isso é responsabilidade da APLICAÇÃO
  (registrar via insert explícito), não da policy RLS. RLS apenas concede acesso.


═══════════════════════════════════════════════════════════════════════════════
CENÁRIO 6 · User com user_permission_overrides ativo
═══════════════════════════════════════════════════════════════════════════════
Suponha: Helena Cardoso (Analista Financeira) recebeu temporariamente acesso a
um relatório especial via override:
  extra_employer_ids = [Labuta]
  expires_at = '2026-12-31'
  reason = 'Apoio temporário ao RH Labuta no fechamento de Q4'

A função can_see_employer(Labuta) retornará TRUE para Helena enquanto o
override estiver válido. As demais dimensões continuam restritas, então ela
verá colaboradores Labuta APENAS dentro dos outros escopos do profile dela.

═══════════════════════════════════════════════════════════════════════════════
*/


-- ============================================================================
-- 6. SUITE DE TESTES BÁSICOS (uso opcional - para CI/CD)
-- ============================================================================
-- Para validar policies em ambiente de teste, simule users com:
--   SET LOCAL request.jwt.claims = '{"active_company_id": "uuid-tenant", "sub": "auth_user_id"}';
-- e execute:
--   SELECT current_user_id(), current_user_company_id();
--   SELECT COUNT(*) FROM user_companies; -- deve retornar conforme escopo
-- ============================================================================

-- Função de diagnóstico: lista o resumo de visibilidade do usuário corrente
CREATE OR REPLACE FUNCTION my_visibility_summary()
RETURNS TABLE (
  metric         TEXT,
  count          INTEGER
)
LANGUAGE plpgsql STABLE SECURITY INVOKER
SET search_path = public AS $$
BEGIN
  RETURN QUERY VALUES
    ('Visible user_companies',     (SELECT COUNT(*)::INTEGER FROM user_companies)),
    ('Visible reviews',            (SELECT COUNT(*)::INTEGER FROM reviews)),
    ('Visible movements',          (SELECT COUNT(*)::INTEGER FROM personnel_movements)),
    ('My private feedbacks',       (SELECT COUNT(*)::INTEGER FROM feedbacks WHERE is_private = TRUE)),
    ('Public praises (tenant)',    (SELECT COUNT(*)::INTEGER FROM praises)),
    ('My audit entries',           (SELECT COUNT(*)::INTEGER FROM audit_log));
END;
$$;

GRANT EXECUTE ON FUNCTION my_visibility_summary() TO authenticated;

COMMENT ON FUNCTION my_visibility_summary IS
  'Função de diagnóstico: retorna o que o usuário corrente consegue enxergar
   em cada tabela. Útil para validar policies durante desenvolvimento.
   IMPORTANTE: SECURITY INVOKER (não DEFINER) para respeitar RLS.';


-- ============================================================================
-- FIM DO ARQUIVO
-- ============================================================================
-- Notas para evolução:
--
-- 1. Performance: a função can_see_user_company faz até 4 subqueries por linha.
--    Em queries com muitas linhas (10k+), isso vira problema. Considere:
--    a) Materialized view diária com flags pré-computados por (target × user)
--    b) Cache em Redis / Edge function para chamadas repetidas
--    c) Particionar user_companies por employer_unit_id
--
-- 2. Hierarchy_scope='recursive' usa CTE recursiva. Para tenants gigantes
--    (50k+), considere closure table pré-calculada com triggers em
--    user_companies.manager_user_id.
--
-- 3. Para suportar "delegação temporária" (gerente X delega permissão para Y
--    durante férias), basta criar user_permission_overrides com expires_at.
--
-- 4. Para multi-empresa (mesmo user em vários tenants), o JWT claim
--    active_company_id resolve ambiguidade. O frontend troca de tenant
--    re-autenticando ou via update do claim.
-- ============================================================================

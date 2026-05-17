-- ============================================================================
-- R2 People · Seed Ninebox v1
-- ============================================================================
-- Adiciona o modulo 'ninebox' ao catalogo, registra permissoes e popula
-- a matriz role x permission.
--
-- Pre-requisitos:
--   - r2_people_schema_base_v1.sql aplicado
--   - r2_people_seed_base_v1.sql aplicado
--   - r2_people_schema_modules_v1.sql aplicado (Sessao L)
--   - r2_people_seed_modules_v1.sql aplicado
--   - r2_people_schema_ninebox_v1.sql aplicado
--
-- Idempotente.
-- ============================================================================

-- ============================================================================
-- CATALOGO · adiciona o modulo ninebox
-- ============================================================================

INSERT INTO modules (code, display_name, description, icon_name, is_core, display_order) VALUES
  ('ninebox',
   '9-Box',
   'Avaliacao matricial de potencial vs performance com ciclos, calibracao e snapshot historico',
   'Grid3x3',
   FALSE,
   50)
ON CONFLICT (code) DO UPDATE SET
  display_name = EXCLUDED.display_name,
  description = EXCLUDED.description,
  icon_name = EXCLUDED.icon_name,
  is_core = EXCLUDED.is_core,
  display_order = EXCLUDED.display_order;

-- ============================================================================
-- PERMISSOES · 8 permissoes do modulo ninebox
-- ============================================================================

INSERT INTO permissions (code, description, scope, module) VALUES
  ('view_ninebox_self',          'Ver a propria avaliacao 9-Box',                    'tenant', 'ninebox'),
  ('view_ninebox_team',          'Ver matriz 9-Box do time (liderados)',             'tenant', 'ninebox'),
  ('view_ninebox_all',           'Ver todas as avaliacoes 9-Box do tenant',          'tenant', 'ninebox'),
  ('manage_ninebox_settings',    'Editar configuracao do 9-Box (grid, criterios)',   'tenant', 'ninebox'),
  ('manage_ninebox_cycles',      'Criar e gerenciar ciclos formais de avaliacao',    'tenant', 'ninebox'),
  ('evaluate_ninebox_subject',   'Avaliar liderado no 9-Box (gestor)',               'tenant', 'ninebox'),
  ('finalize_ninebox',           'Finalizar avaliacao gerando snapshot imutavel',    'tenant', 'ninebox'),
  ('view_ninebox_history',       'Ver historico de snapshots de avaliados',          'tenant', 'ninebox')
ON CONFLICT (code) DO UPDATE
  SET description = EXCLUDED.description,
      scope = EXCLUDED.scope,
      module = EXCLUDED.module;

-- ============================================================================
-- MATRIZ · concede permissoes a cada role
-- ============================================================================

-- colaborador · ve apenas a propria
INSERT INTO role_permissions (role, permission_code) VALUES
  ('colaborador', 'view_ninebox_self'),

-- lider · ve a propria, do time, avalia liderados, finaliza
  ('lider', 'view_ninebox_self'),
  ('lider', 'view_ninebox_team'),
  ('lider', 'evaluate_ninebox_subject'),
  ('lider', 'finalize_ninebox'),
  ('lider', 'view_ninebox_history'),

-- rh · ve tudo, avalia, finaliza, gerencia ciclos e config
  ('rh', 'view_ninebox_self'),
  ('rh', 'view_ninebox_team'),
  ('rh', 'view_ninebox_all'),
  ('rh', 'manage_ninebox_settings'),
  ('rh', 'manage_ninebox_cycles'),
  ('rh', 'evaluate_ninebox_subject'),
  ('rh', 'finalize_ninebox'),
  ('rh', 'view_ninebox_history'),

-- diretoria · superset de RH (tambem pode editar ciclos fechados)
  ('diretoria', 'view_ninebox_self'),
  ('diretoria', 'view_ninebox_team'),
  ('diretoria', 'view_ninebox_all'),
  ('diretoria', 'manage_ninebox_settings'),
  ('diretoria', 'manage_ninebox_cycles'),
  ('diretoria', 'evaluate_ninebox_subject'),
  ('diretoria', 'finalize_ninebox'),
  ('diretoria', 'view_ninebox_history')
ON CONFLICT (role, permission_code) DO NOTHING;

-- ============================================================================
-- DEFAULTS · funcao que popula ninebox_settings com 3x3 e rotulos GE-McKinsey
-- em PT-BR para um tenant novo.
--
-- Chamada na ativacao do modulo no tenant (idempotente · so insere se nao
-- existe). Caso o tenant ja tenha customizado, nao sobrescreve.
-- ============================================================================

CREATE OR REPLACE FUNCTION ninebox_seed_defaults_for_tenant(p_tenant_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  INSERT INTO ninebox_settings (
    tenant_id,
    grid_size,
    potential_criteria,
    performance_criteria,
    box_labels,
    force_justification_extremes,
    min_justification_length,
    require_self_assessment
  ) VALUES (
    p_tenant_id,
    '3x3',

    -- Potencial · 3 criterios padrao (totalizando 100)
    jsonb_build_array(
      jsonb_build_object('name', 'Capacidade de aprendizado',  'weight', 35),
      jsonb_build_object('name', 'Visao estrategica',          'weight', 35),
      jsonb_build_object('name', 'Lideranca e influencia',     'weight', 30)
    ),

    -- Performance · 3 criterios padrao
    jsonb_build_array(
      jsonb_build_object('name', 'Entrega de resultados',      'weight', 50),
      jsonb_build_object('name', 'Qualidade do trabalho',      'weight', 30),
      jsonb_build_object('name', 'Colaboracao e atitude',      'weight', 20)
    ),

    -- Rotulos GE-McKinsey adaptados em PT-BR · 3x3
    -- Linha (potencial) 1=baixo, 2=medio, 3=alto · Coluna (performance) idem
    jsonb_build_object(
      '1_1', 'Risco de saida',
      '1_2', 'Performer eficaz',
      '1_3', 'Performer solido',
      '2_1', 'Enigma',
      '2_2', 'Mantenedor',
      '2_3', 'Profissional de impacto',
      '3_1', 'Diamante bruto',
      '3_2', 'Forte potencial',
      '3_3', 'Estrela'
    ),

    TRUE,   -- force_justification_extremes
    50,     -- min_justification_length
    FALSE   -- require_self_assessment
  )
  ON CONFLICT (tenant_id) DO NOTHING;
END;
$$;

GRANT EXECUTE ON FUNCTION ninebox_seed_defaults_for_tenant TO authenticated;

COMMENT ON FUNCTION ninebox_seed_defaults_for_tenant IS
  'Sessao A2 · Popula ninebox_settings com defaults 3x3 GE-McKinsey PT-BR · idempotente';

-- ============================================================================
-- TRIGGER · ao ativar o modulo ninebox em um tenant, popular defaults
-- ============================================================================
-- Quando uma nova module_activation com module_code = 'ninebox' e
-- scope_kind = 'tenant' e criada, dispara o seed_defaults_for_tenant.
-- Para escopos employer_unit/working_unit, resolve o tenant_id e tambem
-- garante o default.

CREATE OR REPLACE FUNCTION ninebox_on_activation()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
  v_tenant UUID;
BEGIN
  IF NEW.module_code <> 'ninebox' THEN
    RETURN NEW;
  END IF;

  v_tenant := COALESCE(
    NEW.tenant_id,
    (SELECT tenant_id FROM employer_units WHERE id = NEW.employer_unit_id),
    (SELECT tenant_id FROM working_units WHERE id = NEW.working_unit_id)
  );

  IF v_tenant IS NOT NULL THEN
    PERFORM ninebox_seed_defaults_for_tenant(v_tenant);
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_ninebox_on_activation ON module_activations;
CREATE TRIGGER trg_ninebox_on_activation
  AFTER INSERT ON module_activations
  FOR EACH ROW EXECUTE FUNCTION ninebox_on_activation();

-- ============================================================================
-- VALIDACAO POS-SEED
-- ============================================================================
-- SELECT count(*) FROM modules WHERE code = 'ninebox';                       -- 1
-- SELECT count(*) FROM permissions WHERE module = 'ninebox' AND active;      -- 8
-- SELECT role, count(*) FROM role_permissions
--   WHERE permission_code IN (SELECT code FROM permissions WHERE module = 'ninebox')
--   GROUP BY role ORDER BY role;
--   colaborador  1
--   diretoria    8
--   lider        5
--   rh           8
-- ============================================================================

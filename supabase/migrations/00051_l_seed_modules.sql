-- ============================================================================
-- R2 People · Seed Modules v1
-- ============================================================================
-- Popula catalogo inicial de modulos.
--
-- Pre-requisito: r2_people_schema_modules_v1.sql aplicado
-- ============================================================================

-- ============================================================================
-- CATALOGO DE MODULOS
-- ============================================================================

INSERT INTO modules (code, display_name, description, icon_name, is_core, display_order) VALUES
  ('base',
   'Base',
   'Cadastros essenciais (usuarios, unidades, organograma, autenticacao)',
   'Building2',
   TRUE,
   0),

  ('climate',
   'Clima Organizacional',
   'Pesquisas anonimas de clima com perguntas customizaveis e relatorios agregados',
   'Activity',
   FALSE,
   10),

  ('recognition',
   'Reconhecimentos',
   'Mural de reconhecimentos entre colaboradores com reacoes e moderacao',
   'Award',
   FALSE,
   20),

  ('pdi',
   'PDI · Plano de Desenvolvimento Individual',
   'Ciclos de desenvolvimento com acoes, prazos, evidencias e avaliacao',
   'TrendingUp',
   FALSE,
   30),

  ('onboarding',
   'Onboarding',
   'Jornada de integracao apos admissao com templates, stages e checklist',
   'UserPlus',
   FALSE,
   40)
ON CONFLICT (code) DO UPDATE SET
  display_name = EXCLUDED.display_name,
  description = EXCLUDED.description,
  icon_name = EXCLUDED.icon_name,
  is_core = EXCLUDED.is_core,
  display_order = EXCLUDED.display_order;

-- ============================================================================
-- VALIDACAO POS-SEED
-- ============================================================================
-- SELECT count(*) FROM modules;          -- 5
-- SELECT count(*) FROM modules WHERE is_core;   -- 1 (base)
-- SELECT code, display_name FROM modules ORDER BY display_order;
-- ============================================================================

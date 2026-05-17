-- ============================================================================
-- R2 People · Seed Recognition v1
-- ============================================================================
-- Adiciona permissoes do modulo Recognition ao catalogo base.
--
-- Pre-requisitos:
--   - r2_people_schema_base_v1.sql aplicado
--   - r2_people_seed_base_v1.sql aplicado
--   - r2_people_schema_recognition_v1.sql aplicado
--
-- Idempotente.
-- ============================================================================

-- ============================================================================
-- CATALOGO · adiciona 5 permissoes do modulo recognition
-- ============================================================================

INSERT INTO permissions (code, description, scope, module) VALUES
  ('view_recognitions_public', 'Ver feed de reconhecimentos publicos do tenant',     'tenant', 'recognition'),
  ('create_recognition',       'Criar reconhecimento para outro colaborador',         'tenant', 'recognition'),
  ('react_recognition',        'Reagir a reconhecimentos (emoji)',                    'tenant', 'recognition'),
  ('report_recognition',       'Denunciar reconhecimento por conteudo inapropriado',  'tenant', 'recognition'),
  ('manage_recognition_reports', 'Resolver denuncias e ocultar posts (moderacao)',    'tenant', 'recognition')
ON CONFLICT (code) DO UPDATE
  SET description = EXCLUDED.description,
      scope = EXCLUDED.scope,
      module = EXCLUDED.module;

-- ============================================================================
-- MATRIZ · concede permissoes a cada role
-- ============================================================================

-- Todos os 4 roles podem ver, criar, reagir, denunciar
INSERT INTO role_permissions (role, permission_code) VALUES
  ('colaborador', 'view_recognitions_public'),
  ('colaborador', 'create_recognition'),
  ('colaborador', 'react_recognition'),
  ('colaborador', 'report_recognition'),

  ('lider', 'view_recognitions_public'),
  ('lider', 'create_recognition'),
  ('lider', 'react_recognition'),
  ('lider', 'report_recognition'),

  ('rh', 'view_recognitions_public'),
  ('rh', 'create_recognition'),
  ('rh', 'react_recognition'),
  ('rh', 'report_recognition'),
  ('rh', 'manage_recognition_reports'),

  ('diretoria', 'view_recognitions_public'),
  ('diretoria', 'create_recognition'),
  ('diretoria', 'react_recognition'),
  ('diretoria', 'report_recognition'),
  ('diretoria', 'manage_recognition_reports')
ON CONFLICT (role, permission_code) DO NOTHING;

-- ============================================================================
-- VALIDACAO POS-SEED
-- ============================================================================
-- Apos rodar:
--
-- SELECT count(*) FROM permissions WHERE module = 'recognition' AND active;
--   Esperado: 5
--
-- SELECT role, count(*) FROM role_permissions
-- WHERE permission_code IN (
--   SELECT code FROM permissions WHERE module = 'recognition'
-- ) GROUP BY role ORDER BY role;
--   Esperado:
--     colaborador  4
--     diretoria    5
--     lider        4
--     rh           5
--
-- Total da matriz apos esta sessao:
-- SELECT role, count(*) FROM role_permissions GROUP BY role ORDER BY role;
--   colaborador  13   (era 9 + 4)
--   diretoria    30   (era 25 + 5)
--   lider        16   (era 12 + 4)
--   rh           27   (era 22 + 5)
-- ============================================================================

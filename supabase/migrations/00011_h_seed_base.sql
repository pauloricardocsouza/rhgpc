-- ============================================================================
-- R2 People · Seed base v1
-- ============================================================================
-- Popula o catalogo global de permissoes (tabela permissions) e a matriz
-- role x permission (tabela role_permissions).
--
-- Pre-requisito: r2_people_schema_base_v1.sql ja aplicado.
--
-- Nao popula tenants, app_users ou outros dados de empresa · isso fica em
-- arquivo separado por deploy (ex.: r2_people_seed_gpc_v1.sql).
--
-- Idempotente · pode ser rodado varias vezes sem duplicar (usa ON CONFLICT).
-- ============================================================================

-- ============================================================================
-- CATALOGO DE PERMISSOES
-- ============================================================================

INSERT INTO permissions (code, description, scope, module) VALUES

  -- ===== Modulo CORE (tenants, units, depts, users) =====
  ('view_tenant',          'Ver dados do tenant atual',                            'tenant', 'core'),
  ('manage_tenant',        'Editar configuracao do tenant (branding, locale)',     'tenant', 'core'),

  ('view_employer_units',  'Ver unidades empregadoras (CNPJs)',                    'tenant', 'core'),
  ('manage_employer_units','Criar/editar/desativar unidades empregadoras',         'tenant', 'core'),

  ('view_working_units',   'Ver unidades de trabalho (lojas, CDs, escritorios)',   'tenant', 'core'),
  ('manage_working_units', 'Criar/editar/desativar unidades de trabalho',          'tenant', 'core'),

  ('view_departments',     'Ver departamentos',                                    'tenant', 'core'),
  ('manage_departments',   'Criar/editar/desativar departamentos',                 'tenant', 'core'),

  ('view_audit_log',       'Ver trilha de auditoria',                              'tenant', 'core'),

  -- ===== Modulo PEOPLE (app_users) =====
  ('view_self_profile',    'Ver o proprio perfil',                                 'self',   'people'),
  ('edit_self_profile',    'Editar campos limitados do proprio perfil',            'self',   'people'),

  ('view_team_profiles',   'Ver perfis dos liderados (direto e indireto)',         'team',   'people'),

  ('view_all_users',       'Ver todos os usuarios do tenant',                      'tenant', 'people'),
  ('manage_users',         'Criar/editar/desativar usuarios do tenant',            'tenant', 'people'),
  ('manage_user_roles',    'Alterar role de outros usuarios',                      'tenant', 'people'),
  ('manage_user_external_ids', 'Vincular/desvincular IDs em sistemas externos',    'tenant', 'people'),

  -- ===== Modulo PDI =====
  ('view_self_pdi',        'Ver os proprios PDIs',                                 'self',   'pdi'),
  ('manage_self_pdi',      'Criar/editar os proprios PDIs (acoes, comentarios)',   'self',   'pdi'),

  ('view_team_pdi',        'Ver PDIs dos liderados',                               'team',   'pdi'),
  ('manage_team_pdi',      'Aprovar/comentar PDIs dos liderados',                  'team',   'pdi'),

  ('view_all_pdi',         'Ver todos os PDIs do tenant',                          'tenant', 'pdi'),
  ('manage_all_pdi',       'CRUD completo em PDIs (apenas RH/Diretoria)',          'tenant', 'pdi'),

  -- ===== Modulo CLIMATE =====
  ('respond_climate',      'Responder pulsos de clima a que foi convidado',        'self',   'climate'),

  ('manage_climate',       'Criar/editar/ativar/encerrar pulsos de clima',         'tenant', 'climate'),
  ('view_climate_results', 'Ver resultados consolidados (anonimos)',               'tenant', 'climate')

ON CONFLICT (code) DO UPDATE
  SET description = EXCLUDED.description,
      scope = EXCLUDED.scope,
      module = EXCLUDED.module;

-- ============================================================================
-- MATRIZ ROLE x PERMISSION
-- ============================================================================

-- Limpa entradas atuais para reaplicar matriz limpa
TRUNCATE TABLE role_permissions;

-- ===== COLABORADOR =====
INSERT INTO role_permissions (role, permission_code) VALUES
  ('colaborador', 'view_tenant'),
  ('colaborador', 'view_employer_units'),
  ('colaborador', 'view_working_units'),
  ('colaborador', 'view_departments'),
  ('colaborador', 'view_self_profile'),
  ('colaborador', 'edit_self_profile'),
  ('colaborador', 'view_self_pdi'),
  ('colaborador', 'manage_self_pdi'),
  ('colaborador', 'respond_climate');

-- ===== LIDER (tudo do colaborador + visao do time) =====
INSERT INTO role_permissions (role, permission_code) VALUES
  ('lider', 'view_tenant'),
  ('lider', 'view_employer_units'),
  ('lider', 'view_working_units'),
  ('lider', 'view_departments'),
  ('lider', 'view_self_profile'),
  ('lider', 'edit_self_profile'),
  ('lider', 'view_team_profiles'),
  ('lider', 'view_self_pdi'),
  ('lider', 'manage_self_pdi'),
  ('lider', 'view_team_pdi'),
  ('lider', 'manage_team_pdi'),
  ('lider', 'respond_climate');

-- ===== RH (operacao completa de gestao de pessoas, sem decisoes estrategicas) =====
INSERT INTO role_permissions (role, permission_code) VALUES
  ('rh', 'view_tenant'),
  ('rh', 'view_employer_units'),
  ('rh', 'manage_employer_units'),
  ('rh', 'view_working_units'),
  ('rh', 'manage_working_units'),
  ('rh', 'view_departments'),
  ('rh', 'manage_departments'),
  ('rh', 'view_audit_log'),
  ('rh', 'view_self_profile'),
  ('rh', 'edit_self_profile'),
  ('rh', 'view_team_profiles'),
  ('rh', 'view_all_users'),
  ('rh', 'manage_users'),
  ('rh', 'manage_user_external_ids'),
  ('rh', 'view_self_pdi'),
  ('rh', 'manage_self_pdi'),
  ('rh', 'view_team_pdi'),
  ('rh', 'manage_team_pdi'),
  ('rh', 'view_all_pdi'),
  ('rh', 'manage_all_pdi'),
  ('rh', 'respond_climate'),
  ('rh', 'manage_climate');

-- ===== DIRETORIA (tudo + decisoes estrategicas + ver resultados de clima) =====
INSERT INTO role_permissions (role, permission_code) VALUES
  ('diretoria', 'view_tenant'),
  ('diretoria', 'manage_tenant'),
  ('diretoria', 'view_employer_units'),
  ('diretoria', 'manage_employer_units'),
  ('diretoria', 'view_working_units'),
  ('diretoria', 'manage_working_units'),
  ('diretoria', 'view_departments'),
  ('diretoria', 'manage_departments'),
  ('diretoria', 'view_audit_log'),
  ('diretoria', 'view_self_profile'),
  ('diretoria', 'edit_self_profile'),
  ('diretoria', 'view_team_profiles'),
  ('diretoria', 'view_all_users'),
  ('diretoria', 'manage_users'),
  ('diretoria', 'manage_user_roles'),
  ('diretoria', 'manage_user_external_ids'),
  ('diretoria', 'view_self_pdi'),
  ('diretoria', 'manage_self_pdi'),
  ('diretoria', 'view_team_pdi'),
  ('diretoria', 'manage_team_pdi'),
  ('diretoria', 'view_all_pdi'),
  ('diretoria', 'manage_all_pdi'),
  ('diretoria', 'respond_climate'),
  ('diretoria', 'manage_climate'),
  ('diretoria', 'view_climate_results');

-- ============================================================================
-- VALIDACAO POS-SEED
-- ============================================================================
-- Para conferir manualmente apos rodar:
--
-- SELECT count(*) FROM permissions WHERE active;
--   Esperado: 25
--
-- SELECT role, count(*) FROM role_permissions GROUP BY role ORDER BY role;
--   Esperado:
--     colaborador  9
--     diretoria   25
--     lider       12
--     rh          22
--
-- SELECT module, count(*) FROM permissions GROUP BY module ORDER BY module;
--   Esperado:
--     climate    3
--     core       9
--     people     7
--     pdi        6
--
-- SELECT p.module, p.code, rp.role
-- FROM permissions p LEFT JOIN role_permissions rp ON rp.permission_code = p.code
-- WHERE rp.role IS NULL;
--   Esperado: 0 linhas (toda permissao tem ao menos 1 role)
-- ============================================================================

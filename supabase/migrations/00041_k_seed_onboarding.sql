-- ============================================================================
-- R2 People · Seed Onboarding v1
-- ============================================================================
-- Adiciona permissoes do modulo Onboarding ao catalogo + template exemplo
-- opcional para o primeiro tenant.
--
-- Pre-requisito: r2_people_schema_onboarding_v1.sql aplicado
-- ============================================================================

-- ============================================================================
-- PERMISSOES
-- ============================================================================

INSERT INTO permissions (code, module, description) VALUES
  ('view_onboarding',   'onboarding', 'Visualizar onboardings (proprio/time/todos)'),
  ('manage_onboarding', 'onboarding', 'Criar e gerenciar onboardings + templates')
ON CONFLICT (code) DO NOTHING;

-- ============================================================================
-- ATRIBUICAO POR ROLE
-- ============================================================================
-- - colaborador: nao precisa (so ve o seu via RLS owner)
-- - lider: view_onboarding (ve do time)
-- - rh: view + manage
-- - diretoria: view + manage

INSERT INTO role_permissions (role, permission_code) VALUES
  ('lider',     'view_onboarding'),
  ('rh',        'view_onboarding'),
  ('rh',        'manage_onboarding'),
  ('diretoria', 'view_onboarding'),
  ('diretoria', 'manage_onboarding')
ON CONFLICT (role, permission_code) DO NOTHING;

-- ============================================================================
-- TEMPLATE EXEMPLO · "Operador de Loja" (opcional)
-- ============================================================================
-- Usa o primeiro tenant disponivel. Pula se ja existir.

DO $$
DECLARE
  v_tenant UUID;
  v_creator UUID;
  v_template_id UUID;
  v_stage_doc UUID;
  v_stage_train UUID;
  v_stage_culture UUID;
BEGIN
  SELECT id INTO v_tenant FROM tenants ORDER BY created_at LIMIT 1;
  IF v_tenant IS NULL THEN
    RAISE NOTICE 'Sem tenant · pulando template exemplo';
    RETURN;
  END IF;

  -- Pega um RH ou Diretoria do tenant para ser o creator (FK NOT NULL)
  SELECT id INTO v_creator FROM app_users
   WHERE tenant_id = v_tenant AND role IN ('rh', 'diretoria') AND active = TRUE
   ORDER BY created_at LIMIT 1;

  IF v_creator IS NULL THEN
    RAISE NOTICE 'Sem RH/Diretoria · pulando template exemplo';
    RETURN;
  END IF;

  -- Idempotencia: pula se ja existe
  IF EXISTS (SELECT 1 FROM onb_templates WHERE tenant_id = v_tenant AND code = 'OPERADOR-LOJA') THEN
    RAISE NOTICE 'Template OPERADOR-LOJA ja existe · pulando';
    RETURN;
  END IF;

  -- Template
  INSERT INTO onb_templates (
    tenant_id, code, display_name, description,
    suggested_duration_days, status, created_by
  ) VALUES (
    v_tenant, 'OPERADOR-LOJA', 'Onboarding Operador de Loja',
    'Jornada padrao de integracao para operadores de loja (caixa, frente de loja, repositor)',
    30, 'published', v_creator
  ) RETURNING id INTO v_template_id;

  -- STAGE 1 · Documentacao (dia 1-3)
  INSERT INTO onb_template_stages (
    tenant_id, template_id, display_name, description,
    display_order, offset_days_start, duration_days
  ) VALUES (
    v_tenant, v_template_id, 'Documentacao',
    'Entrega de documentos e cadastros iniciais',
    1, 0, 3
  ) RETURNING id INTO v_stage_doc;

  INSERT INTO onb_template_tasks (tenant_id, template_id, stage_id, title, description, kind, offset_days, is_required, display_order) VALUES
    (v_tenant, v_template_id, v_stage_doc, 'Entregar documentos pessoais (RG, CPF, CTPS, comprovante de residencia)', 'Conferir lista completa com RH antes da assinatura do contrato', 'documentation', 0, TRUE, 1),
    (v_tenant, v_template_id, v_stage_doc, 'Assinar contrato de trabalho', 'Pelo RH com 2 vias', 'documentation', 1, TRUE, 2),
    (v_tenant, v_template_id, v_stage_doc, 'Assinar termo de codigo de conduta e politicas internas', NULL, 'compliance', 1, TRUE, 3),
    (v_tenant, v_template_id, v_stage_doc, 'Cadastro biometrico para ponto eletronico', NULL, 'system_access', 2, TRUE, 4),
    (v_tenant, v_template_id, v_stage_doc, 'Receber cracha e uniforme', NULL, 'documentation', 2, TRUE, 5);

  -- STAGE 2 · Treinamentos (dia 3-15)
  INSERT INTO onb_template_stages (
    tenant_id, template_id, display_name, description,
    display_order, offset_days_start, duration_days
  ) VALUES (
    v_tenant, v_template_id, 'Treinamentos',
    'Capacitacao tecnica e normas operacionais',
    2, 3, 12
  ) RETURNING id INTO v_stage_train;

  INSERT INTO onb_template_tasks (tenant_id, template_id, stage_id, title, description, kind, offset_days, is_required, display_order) VALUES
    (v_tenant, v_template_id, v_stage_train, 'NR-5 (CIPA) e NR-12 quando aplicavel', NULL, 'training', 0, TRUE, 1),
    (v_tenant, v_template_id, v_stage_train, 'Treinamento de seguranca alimentar (boas praticas)', NULL, 'training', 1, TRUE, 2),
    (v_tenant, v_template_id, v_stage_train, 'Treinamento operacional do PDV (Winthor) ou frente de loja', 'Conduzido pelo coordenador da area', 'training', 3, TRUE, 3),
    (v_tenant, v_template_id, v_stage_train, 'Treinamento de atendimento ao cliente', NULL, 'training', 5, TRUE, 4),
    (v_tenant, v_template_id, v_stage_train, 'Treinamento de prevencao de perdas', NULL, 'training', 7, FALSE, 5),
    (v_tenant, v_template_id, v_stage_train, 'Acompanhamento operacional (shadowing)', 'Acompanhar veterano do setor por 2 dias', 'training', 9, TRUE, 6);

  -- STAGE 3 · Integracao Cultural (dia 1-30)
  INSERT INTO onb_template_stages (
    tenant_id, template_id, display_name, description,
    display_order, offset_days_start, duration_days
  ) VALUES (
    v_tenant, v_template_id, 'Integracao Cultural',
    'Conhecer pessoas, valores e historia da empresa',
    3, 0, 30
  ) RETURNING id INTO v_stage_culture;

  INSERT INTO onb_template_tasks (tenant_id, template_id, stage_id, title, description, kind, offset_days, is_required, display_order) VALUES
    (v_tenant, v_template_id, v_stage_culture, 'Reuniao de boas-vindas com RH', 'Apresentacao da empresa, valores, beneficios', 'meeting', 0, TRUE, 1),
    (v_tenant, v_template_id, v_stage_culture, 'Reuniao com gestor direto', 'Combinados de equipe, expectativas', 'meeting', 1, TRUE, 2),
    (v_tenant, v_template_id, v_stage_culture, 'Tour pela loja e apresentacao da equipe', NULL, 'cultural', 2, TRUE, 3),
    (v_tenant, v_template_id, v_stage_culture, 'Almoco de integracao com o time', NULL, 'cultural', 7, FALSE, 4),
    (v_tenant, v_template_id, v_stage_culture, 'Feedback dos primeiros 30 dias com gestor', NULL, 'meeting', 28, TRUE, 5);

  RAISE NOTICE 'Template OPERADOR-LOJA criado com 3 stages e 16 tasks';
END $$;

-- ============================================================================
-- VALIDACAO POS-SEED
-- ============================================================================
-- SELECT count(*) FROM permissions WHERE module = 'onboarding';   -- 2
-- SELECT code FROM onb_templates;                                  -- OPERADOR-LOJA
-- SELECT count(*) FROM onb_template_stages
--   WHERE template_id = (SELECT id FROM onb_templates WHERE code='OPERADOR-LOJA'); -- 3
-- SELECT count(*) FROM onb_template_tasks
--   WHERE template_id = (SELECT id FROM onb_templates WHERE code='OPERADOR-LOJA'); -- 16
-- ============================================================================

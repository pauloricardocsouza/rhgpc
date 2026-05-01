-- ============================================================================
-- R2 PEOPLE - SEED INICIAL (PostgreSQL / Supabase)
-- ============================================================================
-- Popula o ambiente com o caso real do Grupo Pinto Cerqueira:
--   - 4 empresas (GPC + 3 prestadoras: Labuta, Limpactiva, Segure)
--   - 14 unidades organizacionais (lojas, CDs, escritórios, prestadoras)
--   - 15 departamentos
--   - 28 cargos com faixas salariais
--   - 9 perfis de acesso (3 system + 6 específicos do GPC)
--   - 30 colaboradores demo com vínculos empregador↔tomador
--   - 8 competências
--   - 1 ciclo de avaliação aberto (2026.1)
--
-- Idempotente: pode ser rodado múltiplas vezes sem duplicar dados.
-- Todos os UPSERTs usam ON CONFLICT para atualizar registros existentes.
--
-- Uso:
--   1. Execute primeiro o schema_v3.sql no SQL Editor do Supabase
--   2. Em seguida execute este seed
--   3. Para ambiente limpo: rode TRUNCATE no final do arquivo
-- ============================================================================

BEGIN;

-- ============================================================================
-- 1. COMPANY (TENANT) - Grupo Pinto Cerqueira
-- ============================================================================

INSERT INTO companies (id, slug, name, legal_name, cnpj_root, primary_color, settings, active)
VALUES (
  '00000000-0000-0000-0001-000000000001',
  'gpc',
  'Grupo Pinto Cerqueira',
  'Grupo Pinto Cerqueira Comércio LTDA',
  '12.345.678',
  '#2B4A7A',
  jsonb_build_object(
    'timezone', 'America/Bahia',
    'locale', 'pt-BR',
    'date_format', 'DD/MM/YYYY',
    'currency', 'BRL',
    'evaluation_scale', 5,
    'self_eval_window_days', 7,
    'allow_anonymous_peer', 'optional',
    'allow_eval_reopen', true,
    'nine_box_enabled', true,
    'nine_box_visible_to_employee', false,
    'anonymize_after_termination_days', 365,
    'retain_evaluation_history', true,
    'channels', jsonb_build_object('in_app', true, 'email', false, 'whatsapp', false),
    'password_policy', jsonb_build_object(
      'min_length', 8,
      'require_special', true,
      'require_number', true,
      'expiration_days', null,
      'lockout_attempts', 5
    ),
    'require_2fa_admins', true,
    'require_2fa_all', false,
    'session_idle_timeout_minutes', 60,
    'email_branding', true,
    'pdf_watermark', true
  ),
  true
)
ON CONFLICT (id) DO UPDATE SET
  name = EXCLUDED.name,
  legal_name = EXCLUDED.legal_name,
  settings = EXCLUDED.settings,
  updated_at = now();


-- ============================================================================
-- 2. USERS · alguns usuários-chave (gestores, RH, líderes operacionais)
-- ============================================================================
-- IDs seguem padrão 'usr_NN' para legibilidade (UUIDs reais em produção)
-- auth_email é sintético no formato {username}@gpc.r2.local
-- ============================================================================

INSERT INTO users (id, username, auth_email, full_name, cpf, gender, birth_date, active, must_change_pwd) VALUES
-- GPC próprios (administrativo / liderança)
('00000000-0000-0000-0002-000000000001','ricardo.silva',     'ricardo.silva@gpc.r2.local',     'Ricardo Silva',                '04281539267','M','1991-04-12', true, false),
('00000000-0000-0000-0002-000000000002','maria.santos',      'maria.santos@gpc.r2.local',      'Maria Santos',                 '02345678901','F','1977-08-23', true, false),
('00000000-0000-0000-0002-000000000003','patricia.mello',    'patricia.mello@gpc.r2.local',    'Patrícia Mello',               '03456789012','F','1986-11-05', true, false),
('00000000-0000-0000-0002-000000000004','joao.carvalho',     'joao.carvalho@gpc.r2.local',     'João Carvalho',                '04567890123','M','1984-02-14', true, false),
('00000000-0000-0000-0002-000000000005','beatriz.lopes',     'beatriz.lopes@gpc.r2.local',     'Beatriz Lopes Almeida',        '05678901234','F','1993-06-30', true, false),
('00000000-0000-0000-0002-000000000006','helena.cardoso',    'helena.cardoso@gpc.r2.local',    'Helena Cardoso',               '06789012345','F','1989-09-17', true, false),
('00000000-0000-0000-0002-000000000007','sandra.gomes',      'sandra.gomes@gpc.r2.local',      'Sandra Gomes',                 '07890123456','F','1980-12-08', true, false),
('00000000-0000-0000-0002-000000000008','roberto.almeida',   'roberto.almeida@gpc.r2.local',   'Roberto Almeida',              '08901234567','M','1978-03-22', true, false),
('00000000-0000-0000-0002-000000000009','talita.comercial',  'talita.comercial@gpc.r2.local',  'Talita Comercial',             '09012345678','F','1983-07-11', true, false),
('00000000-0000-0000-0002-000000000010','carlos.augusto',    'carlos.augusto@gpc.r2.local',    'Carlos Augusto',               '10123456789','M','1981-10-25', true, false),
('00000000-0000-0000-0002-000000000029','pedro.lima',        'pedro.lima@gpc.r2.local',        'Pedro Lima',                   '29234567890','M','1991-05-19', true, false),
('00000000-0000-0000-0002-000000000030','carla.reis',        'carla.reis@gpc.r2.local',        'Carla Reis',                   '30345678901','F','1984-01-28', true, false),

-- Labuta (terceirizados)
('00000000-0000-0000-0002-000000000011','fernanda.lima',     'fernanda.lima@gpc.r2.local',     'Fernanda Lima dos Santos',     '11456789012','F','1992-04-15', true, false),
('00000000-0000-0000-0002-000000000012','carlos.eduardo',    'carlos.eduardo@gpc.r2.local',    'Carlos Eduardo Lopes',         '12567890123','M','1995-08-03', true, false),
('00000000-0000-0000-0002-000000000013','daniela.vieira',    'daniela.vieira@gpc.r2.local',    'Daniela Vieira Matos',         '13678901234','F','1998-11-22', true, false),
('00000000-0000-0000-0002-000000000014','gabriel.pinto',     'gabriel.pinto@gpc.r2.local',     'Gabriel Pinto Souza',          '14789012345','M','2004-02-09', true, true),
('00000000-0000-0000-0002-000000000015','otavio.pereira',    'otavio.pereira@gpc.r2.local',    'Otávio Pereira',               '15890123456','M','2001-06-17', true, false),
('00000000-0000-0000-0002-000000000016','julia.machado',     'julia.machado@gpc.r2.local',     'Júlia Machado',                '16901234567','F','1997-12-30', true, false),
('00000000-0000-0000-0002-000000000017','pedro.felipe',      'pedro.felipe@gpc.r2.local',      'Pedro Felipe',                 '17012345678','M','2003-09-14', true, false),
('00000000-0000-0000-0002-000000000018','ana.beatriz',       'ana.beatriz@gpc.r2.local',       'Ana Beatriz Souza',            '18123456789','F','1996-03-26', true, false),
('00000000-0000-0000-0002-000000000019','eduardo.mendes',    'eduardo.mendes@gpc.r2.local',    'Eduardo Mendes',               '19234567890','M','1989-07-04', true, false),
('00000000-0000-0000-0002-000000000020','larissa.rocha',     'larissa.rocha@gpc.r2.local',     'Larissa Rocha',                '20345678901','F','2000-10-12', true, false),
('00000000-0000-0000-0002-000000000021','igor.vasconcelos',  'igor.vasconcelos@gpc.r2.local',  'Igor Vasconcelos',             '21456789012','M','1987-04-20', true, false),
('00000000-0000-0000-0002-000000000022','natalia.ferreira',  'natalia.ferreira@gpc.r2.local',  'Natália Ferreira',             '22567890123','F','2002-01-08', true, false),

-- Larissa Pereira: persona de RH da Labuta (tem acesso restrito ao empregador Labuta)
('00000000-0000-0000-0002-000000000040','larissa.pereira',   'larissa.pereira@gpc.r2.local',   'Larissa Pereira',              '40789012345','F','1985-05-27', true, false),

-- Limpactiva
('00000000-0000-0000-0002-000000000023','jose.silva',        'jose.silva@gpc.r2.local',        'José da Silva',                '23678901234','M','1974-11-19', true, false),
('00000000-0000-0000-0002-000000000024','maria.aparecida',   'maria.aparecida@gpc.r2.local',   'Maria Aparecida',              '24789012345','F','1979-08-15', true, false),
('00000000-0000-0000-0002-000000000025','antonio.lopes',     'antonio.lopes@gpc.r2.local',     'Antônio Lopes',                '25890123456','M','1986-02-23', true, false),

-- Segure
('00000000-0000-0000-0002-000000000026','sergio.rodrigues',  'sergio.rodrigues@gpc.r2.local',  'Sérgio Rodrigues',             '26901234567','M','1977-06-08', true, false),
('00000000-0000-0000-0002-000000000027','marcos.goncalves',  'marcos.goncalves@gpc.r2.local',  'Marcos Gonçalves',             '27012345678','M','1983-09-30', true, false),
('00000000-0000-0000-0002-000000000028','wagner.pereira',    'wagner.pereira@gpc.r2.local',    'Wagner Pereira',               '28123456789','M','1988-12-04', true, false),

-- Carla Moreira: DPO/Auditoria
('00000000-0000-0000-0002-000000000041','carla.moreira',     'carla.moreira@gpc.r2.local',     'Carla Moreira',                '41890123456','F','1981-04-15', true, false)
ON CONFLICT (id) DO UPDATE SET
  full_name = EXCLUDED.full_name,
  active = EXCLUDED.active,
  updated_at = now();


-- ============================================================================
-- 3. UNITS · 14 unidades organizacionais polimórficas
-- ============================================================================
-- Estrutura:
--   - 1 administrative: GPC Matriz (escritório corporativo)
--   - 7 operational: ATP-Varejo, ATP-Atacado, Cestão L1, Cestão Inh., ATP S.Bonfim, CD Logística, ATP Conceição
--   - 3 service_provider: Labuta, Limpactiva, Segure
--   - 3 administrative subordinadas à matriz: GPC Financeiro, GPC RH, GPC TI
-- ============================================================================

INSERT INTO units (id, company_id, parent_id, code, name, role, type, cnpj, active) VALUES
-- Matriz administrativa (raiz da hierarquia)
('00000000-0000-0000-0003-000000000001','00000000-0000-0000-0001-000000000001', NULL,
 'GPC-MAT','GPC Matriz','administrative','matriz','12.345.678/0001-00', true),

-- Áreas administrativas dentro da matriz
('00000000-0000-0000-0003-000000000002','00000000-0000-0000-0001-000000000001','00000000-0000-0000-0003-000000000001',
 'GPC-FIN','GPC Financeiro','administrative','escritorio','12.345.678/0001-00', true),
('00000000-0000-0000-0003-000000000003','00000000-0000-0000-0001-000000000001','00000000-0000-0000-0003-000000000001',
 'GPC-RH','GPC RH','administrative','escritorio','12.345.678/0001-00', true),
('00000000-0000-0000-0003-000000000004','00000000-0000-0000-0001-000000000001','00000000-0000-0000-0003-000000000001',
 'GPC-TI','GPC TI','administrative','escritorio','12.345.678/0001-00', true),

-- Lojas operacionais
('00000000-0000-0000-0003-000000000005','00000000-0000-0000-0001-000000000001','00000000-0000-0000-0003-000000000001',
 'ATP-VAR','ATP-Varejo','operational','loja','12.345.678/0002-91', true),
('00000000-0000-0000-0003-000000000006','00000000-0000-0000-0001-000000000001','00000000-0000-0000-0003-000000000001',
 'ATP-ATA','ATP-Atacado','operational','loja','12.345.678/0003-72', true),
('00000000-0000-0000-0003-000000000007','00000000-0000-0000-0001-000000000001','00000000-0000-0000-0003-000000000001',
 'CES-L1','Cestão L1','operational','loja','12.345.678/0004-53', true),
('00000000-0000-0000-0003-000000000008','00000000-0000-0000-0001-000000000001','00000000-0000-0000-0003-000000000001',
 'CES-INH','Cestão Inhambupe','operational','loja','12.345.678/0005-34', true),
('00000000-0000-0000-0003-000000000009','00000000-0000-0000-0001-000000000001','00000000-0000-0000-0003-000000000001',
 'ATP-SBO','ATP Senhor do Bonfim','operational','loja','12.345.678/0006-15', true),
('00000000-0000-0000-0003-000000000010','00000000-0000-0000-0001-000000000001','00000000-0000-0000-0003-000000000001',
 'ATP-CON','ATP Conceição','operational','loja','12.345.678/0007-96', true),

-- CD
('00000000-0000-0000-0003-000000000011','00000000-0000-0000-0001-000000000001','00000000-0000-0000-0003-000000000001',
 'CD-LOG','CD Logística','operational','cd','12.345.678/0008-77', true),

-- Prestadoras (NÃO são subordinadas à matriz na hierarquia, são CNPJs externos)
('00000000-0000-0000-0003-000000000012','00000000-0000-0000-0001-000000000001', NULL,
 'LABUTA','Labuta Serviços Empresariais','service_provider','prestadora','45.678.901/0001-25', true),
('00000000-0000-0000-0003-000000000013','00000000-0000-0000-0001-000000000001', NULL,
 'LIMPAC','Limpactiva Serviços de Limpeza','service_provider','prestadora','56.789.012/0001-34', true),
('00000000-0000-0000-0003-000000000014','00000000-0000-0000-0001-000000000001', NULL,
 'SEGURE','Segure Vigilância Patrimonial','service_provider','prestadora','67.890.123/0001-43', true)
ON CONFLICT (id) DO UPDATE SET
  name = EXCLUDED.name,
  parent_id = EXCLUDED.parent_id,
  cnpj = EXCLUDED.cnpj,
  active = EXCLUDED.active,
  updated_at = now();


-- ============================================================================
-- 4. DEPARTMENTS · 15 áreas funcionais
-- ============================================================================

INSERT INTO departments (id, company_id, parent_id, unit_id, code, name, description, active) VALUES
-- Administrativos (corporativo - sem unit_id pois são transversais)
('00000000-0000-0000-0004-000000000001','00000000-0000-0000-0001-000000000001', NULL, NULL, 'FIN',     'Financeiro',         'Tesouraria, contas a pagar/receber, contabilidade', true),
('00000000-0000-0000-0004-000000000002','00000000-0000-0000-0001-000000000001', NULL, NULL, 'RH',      'Recursos Humanos',   'Gestão de pessoas, recrutamento, DP', true),
('00000000-0000-0000-0004-000000000003','00000000-0000-0000-0001-000000000001', NULL, NULL, 'TI',      'Tecnologia',         'Infraestrutura, BI, sistemas', true),
('00000000-0000-0000-0004-000000000004','00000000-0000-0000-0001-000000000001', NULL, NULL, 'COM',     'Comercial',          'Compras, gestão de fornecedores, marketing', true),
('00000000-0000-0000-0004-000000000005','00000000-0000-0000-0001-000000000001','00000000-0000-0000-0004-000000000004', NULL, 'COM-COMP','Compras',            'Negociação com fornecedores', true),
('00000000-0000-0000-0004-000000000006','00000000-0000-0000-0001-000000000001','00000000-0000-0000-0004-000000000004', NULL, 'COM-MKT', 'Marketing',          'Comunicação, branding, encartes', true),
('00000000-0000-0000-0004-000000000007','00000000-0000-0000-0001-000000000001', NULL, NULL, 'AUD',     'Auditoria',          'Controle interno e auditoria', true),
('00000000-0000-0000-0004-000000000008','00000000-0000-0000-0001-000000000001', NULL, NULL, 'JUR',     'Jurídico',           'Contratos, contencioso', true),
-- Operacionais (associados a unidades)
('00000000-0000-0000-0004-000000000009','00000000-0000-0000-0001-000000000001', NULL, NULL, 'OP',      'Operações',          'Operação de loja, frente de caixa, açougue, padaria', true),
('00000000-0000-0000-0004-000000000010','00000000-0000-0000-0001-000000000001','00000000-0000-0000-0004-000000000009', NULL, 'OP-CX',   'Frente de caixa',    'Operação de caixas e atendimento', true),
('00000000-0000-0000-0004-000000000011','00000000-0000-0000-0001-000000000001','00000000-0000-0000-0004-000000000009', NULL, 'OP-AC',   'Açougue',            'Setor de carnes', true),
('00000000-0000-0000-0004-000000000012','00000000-0000-0000-0001-000000000001','00000000-0000-0000-0004-000000000009', NULL, 'OP-PAD',  'Padaria',            'Setor de panificação', true),
('00000000-0000-0000-0004-000000000013','00000000-0000-0000-0001-000000000001','00000000-0000-0000-0004-000000000009', NULL, 'OP-REP',  'Reposição',          'Reposição de mercadorias em gôndolas', true),
('00000000-0000-0000-0004-000000000014','00000000-0000-0000-0001-000000000001', NULL, NULL, 'LOG',     'Logística',          'Recebimento, expedição, movimentação', true),
('00000000-0000-0000-0004-000000000015','00000000-0000-0000-0001-000000000001', NULL, NULL, 'LIMP',    'Limpeza',            'Higienização e limpeza', true)
ON CONFLICT (id) DO UPDATE SET
  name = EXCLUDED.name,
  parent_id = EXCLUDED.parent_id,
  description = EXCLUDED.description,
  updated_at = now();


-- ============================================================================
-- 5. POSITIONS · 28 cargos com faixa salarial
-- ============================================================================

INSERT INTO positions (id, company_id, department_id, code, name, level, cbo_code, min_salary, mid_salary, max_salary, active) VALUES
-- Operacional (loja)
('00000000-0000-0000-0005-000000000001','00000000-0000-0000-0001-000000000001','00000000-0000-0000-0004-000000000010','OP-CX-JR',    'Operador de Caixa',           'Operacional', '4211-25',1518.00,1620.00,1850.00, true),
('00000000-0000-0000-0005-000000000002','00000000-0000-0000-0001-000000000001','00000000-0000-0000-0004-000000000013','REP-JR',      'Repositor',                   'Operacional', '4143-30',1518.00,1620.00,1800.00, true),
('00000000-0000-0000-0005-000000000003','00000000-0000-0000-0001-000000000001','00000000-0000-0000-0004-000000000011','AC-JR',       'Açougueiro',                  'Operacional', '8485-05',2000.00,2400.00,2900.00, true),
('00000000-0000-0000-0005-000000000004','00000000-0000-0000-0001-000000000001','00000000-0000-0000-0004-000000000012','PAD-JR',      'Padeiro',                     'Operacional', '8483-15',2000.00,2400.00,2900.00, true),
('00000000-0000-0000-0005-000000000005','00000000-0000-0000-0001-000000000001','00000000-0000-0000-0004-000000000010','SUB-LOJA',    'Subgerente de Loja',          'Coordenação', '4101-05',3500.00,4800.00,6200.00, true),
('00000000-0000-0000-0005-000000000006','00000000-0000-0000-0001-000000000001','00000000-0000-0000-0004-000000000010','GER-LOJA',    'Gerente de Loja',             'Gerência',    '1414-10',7500.00,10500.00,14000.00, true),

-- Logística
('00000000-0000-0000-0005-000000000007','00000000-0000-0000-0001-000000000001','00000000-0000-0000-0004-000000000014','CONF-LOG',    'Conferente',                  'Operacional', '4141-30',1800.00,2200.00,2700.00, true),
('00000000-0000-0000-0005-000000000008','00000000-0000-0000-0001-000000000001','00000000-0000-0000-0004-000000000014','COORD-LOG',   'Coord. de Logística',         'Coordenação', '1413-30',6500.00,8500.00,11000.00, true),

-- Limpeza e vigilância
('00000000-0000-0000-0005-000000000009','00000000-0000-0000-0001-000000000001','00000000-0000-0000-0004-000000000015','AUX-LIMP',    'Aux. de Limpeza',             'Operacional', '5121-15',1518.00,1518.00,1700.00, true),
('00000000-0000-0000-0005-000000000010','00000000-0000-0000-0001-000000000001','00000000-0000-0000-0004-000000000009','VIG-PAT',     'Vigilante',                   'Operacional', '5173-30',1900.00,2100.00,2400.00, true),

-- Financeiro
('00000000-0000-0000-0005-000000000011','00000000-0000-0000-0001-000000000001','00000000-0000-0000-0004-000000000001','AUX-FIN',     'Auxiliar Financeiro',         'Operacional', '4131-20',2000.00,2400.00,2900.00, true),
('00000000-0000-0000-0005-000000000012','00000000-0000-0000-0001-000000000001','00000000-0000-0000-0004-000000000001','ANL-FIN-JR',  'Analista Financeiro Júnior',  'Júnior',      '2522-10',2800.00,3500.00,4500.00, true),
('00000000-0000-0000-0005-000000000013','00000000-0000-0000-0001-000000000001','00000000-0000-0000-0004-000000000001','ANL-FIN-PL',  'Analista Financeiro Pleno',   'Pleno',       '2522-10',3800.00,4500.00,5800.00, true),
('00000000-0000-0000-0005-000000000014','00000000-0000-0000-0001-000000000001','00000000-0000-0000-0004-000000000001','ANL-FIN-SR',  'Analista Financeiro Sênior',  'Sênior',      '2522-10',4800.00,5500.00,7200.00, true),
('00000000-0000-0000-0005-000000000015','00000000-0000-0000-0001-000000000001','00000000-0000-0000-0004-000000000001','LID-FIN',     'Líder Financeiro',            'Coordenação', '1414-30',7500.00,9500.00,12000.00, true),
('00000000-0000-0000-0005-000000000016','00000000-0000-0000-0001-000000000001','00000000-0000-0000-0004-000000000001','DIR-FIN',     'Diretor(a) Financeiro(a)',    'Diretoria',   '1231-05',18000.00,25000.00,35000.00, true),

-- Comercial
('00000000-0000-0000-0005-000000000017','00000000-0000-0000-0001-000000000001','00000000-0000-0000-0004-000000000004','ANL-COM-PL',  'Analista Comercial Pleno',    'Pleno',       '2521-05',3800.00,4500.00,5800.00, true),
('00000000-0000-0000-0005-000000000018','00000000-0000-0000-0001-000000000001','00000000-0000-0000-0004-000000000006','ANL-MKT-PL',  'Analista de Marketing Pleno', 'Pleno',       '2531-05',3800.00,4500.00,5800.00, true),
('00000000-0000-0000-0005-000000000019','00000000-0000-0000-0001-000000000001','00000000-0000-0000-0004-000000000004','DIR-COM',     'Diretor(a) Comercial',        'Diretoria',   '1231-15',15000.00,18000.00,28000.00, true),

-- TI / BI
('00000000-0000-0000-0005-000000000020','00000000-0000-0000-0001-000000000001','00000000-0000-0000-0004-000000000003','COORD-BI',    'Coord. de BI',                'Coordenação', '2123-05',6500.00,7500.00,9500.00, true),
('00000000-0000-0000-0005-000000000021','00000000-0000-0000-0001-000000000001','00000000-0000-0000-0004-000000000003','ANL-BI-PL',   'Analista de BI Pleno',        'Pleno',       '2123-10',4500.00,5500.00,7500.00, true),

-- RH
('00000000-0000-0000-0005-000000000022','00000000-0000-0000-0001-000000000001','00000000-0000-0000-0004-000000000002','COORD-RH',    'Coord. de RH',                'Coordenação', '1422-05',6500.00,8200.00,10500.00, true),
('00000000-0000-0000-0005-000000000023','00000000-0000-0000-0001-000000000001','00000000-0000-0000-0004-000000000002','ANL-RH-PL',   'Analista de RH Pleno',        'Pleno',       '2524-05',3800.00,4500.00,5800.00, true),

-- Auditoria
('00000000-0000-0000-0005-000000000024','00000000-0000-0000-0001-000000000001','00000000-0000-0000-0004-000000000007','AUD-SR',      'Auditor Sênior',              'Sênior',      '2522-15',7000.00,8800.00,11500.00, true),
('00000000-0000-0000-0005-000000000025','00000000-0000-0000-0001-000000000001','00000000-0000-0000-0004-000000000007','DPO',         'Encarregado de Dados (DPO)',  'Coordenação', '1422-30',7500.00,9000.00,12000.00, true),

-- Estagiário (genérico)
('00000000-0000-0000-0005-000000000026','00000000-0000-0000-0001-000000000001', NULL,                                    'EST',         'Estagiário(a)',               'Estagiário',  null,    1100.00,1400.00,1800.00, true),

-- Aprendiz
('00000000-0000-0000-0005-000000000027','00000000-0000-0000-0001-000000000001', NULL,                                    'APR',         'Jovem Aprendiz',              'Aprendiz',    null,     760.00,950.00,1100.00, true),

-- Genérico para terceirizados sem mapeamento exato
('00000000-0000-0000-0005-000000000028','00000000-0000-0000-0001-000000000001', NULL,                                    'TER-GEN',     'Terceirizado Genérico',       'Operacional', null,    1518.00,2000.00,3500.00, true)
ON CONFLICT (id) DO UPDATE SET
  name = EXCLUDED.name,
  level = EXCLUDED.level,
  min_salary = EXCLUDED.min_salary,
  mid_salary = EXCLUDED.mid_salary,
  max_salary = EXCLUDED.max_salary,
  updated_at = now();


-- ============================================================================
-- 6. SYSTEM PAGES · catálogo das páginas do sistema
-- ============================================================================

INSERT INTO system_pages (code, name, category, is_sensitive, available_perms) VALUES
('home',                  'Home',                          'geral',     false, ARRAY['view']),
('dashboard_rh',          'Dashboard RH',                  'admin',     true,  ARRAY['view','export']),
('colaboradores_lista',   'Lista de Colaboradores',        'rh',        true,  ARRAY['view','create','edit','export']),
('colaborador_perfil',    'Perfil do Colaborador',         'rh',        true,  ARRAY['view','edit']),
('movimentacoes',         'Movimentações',                 'gestor',    true,  ARRAY['view','create','edit','approve','reject']),
('aprovacoes_rh',         'Aprovações RH',                 'admin',     true,  ARRAY['view','approve','reject','export']),
('estrutura',             'Filiais, Cargos e Departamentos','admin',    false, ARRAY['view','create','edit','delete']),
('acessos',               'Acessos e Perfis',              'admin',    true,  ARRAY['view','create','edit','delete']),
('importacao',            'Importação',                    'admin',    true,  ARRAY['view','create','export']),
('relatorios',            'Relatórios Analíticos',         'admin',    true,  ARRAY['view','export']),
('configuracoes',         'Configurações da Empresa',      'admin',    true,  ARRAY['view','edit']),
('auditoria',             'Auditoria e Logs',              'admin',    true,  ARRAY['view','export']),
('ciclos',                'Ciclos de Avaliação',           'aval',     false, ARRAY['view','create','edit']),
('avaliacao',             'Formulário de Avaliação',       'aval',     false, ARRAY['view','create','edit']),
('feedback',              'Feedback Contínuo',             'feedback', false, ARRAY['view','create']),
('praises',               'Mural de Elogios',              'feedback', false, ARRAY['view','create'])
ON CONFLICT (code) DO UPDATE SET
  name = EXCLUDED.name,
  category = EXCLUDED.category,
  is_sensitive = EXCLUDED.is_sensitive,
  available_perms = EXCLUDED.available_perms;


-- ============================================================================
-- 7. PERMISSION PROFILES · 9 perfis (3 system + 6 GPC-específicos)
-- ============================================================================

INSERT INTO permission_profiles (id, company_id, code, name, description, color, icon, is_system,
  employer_scope, unit_scope, department_scope, hierarchy_scope, special_permissions, active) VALUES

-- Perfis system (vêm em todos os tenants)
('00000000-0000-0000-0006-000000000001','00000000-0000-0000-0001-000000000001',
 'super_admin', 'Super Administrador',
 'Acesso total ao sistema. Reservado para 1-2 pessoas (geralmente o admin do tenant).',
 '#1A2D4F', '⚛', true,
 'all','all','all','all',
 ARRAY['approve_movements','import_csv','export_sensitive','reset_passwords','manage_profiles','view_audit','override_scope','manage_cycles'],
 true),

('00000000-0000-0000-0006-000000000002','00000000-0000-0000-0001-000000000001',
 'colaborador', 'Colaborador',
 'Perfil padrão de qualquer colaborador. Vê apenas o próprio perfil, feedbacks recebidos e avalia a si mesmo.',
 '#5A7090', '👤', true,
 'self','self','self','self',
 ARRAY[]::TEXT[],
 true),

('00000000-0000-0000-0006-000000000003','00000000-0000-0000-0001-000000000001',
 'lider', 'Líder de Equipe',
 'Vê os subordinados diretos e indiretos. Avalia liderados e aprova movimentações em primeira instância.',
 '#6D28D9', '◆', true,
 'all','all','all','recursive',
 ARRAY['approve_movements'],
 true),

-- Perfis específicos do GPC

('00000000-0000-0000-0006-000000000004','00000000-0000-0000-0001-000000000001',
 'admin_rh_gpc', 'Administrador RH (GPC)',
 'RH corporativo do GPC. Vê todos os colaboradores de todas as unidades. Aprova movimentações em segunda instância.',
 '#2B4A7A', '⚙', false,
 'all','all','all','all',
 ARRAY['approve_movements','import_csv','export_sensitive','reset_passwords','view_audit','manage_cycles'],
 true),

('00000000-0000-0000-0006-000000000005','00000000-0000-0000-0001-000000000001',
 'rh_prestadora_labuta', 'RH Prestadora · Labuta',
 'RH da prestadora Labuta. Vê apenas os 247 colaboradores cujo empregador é a Labuta, em qualquer filial onde estejam alocados.',
 '#6D28D9', 'L', false,
 'specific','all','all','all',
 ARRAY['approve_movements','export_sensitive'],
 true),

('00000000-0000-0000-0006-000000000006','00000000-0000-0000-0001-000000000001',
 'gerente_filial_cestao_l1', 'Gerente de Filial · Cestão L1',
 'Gerente da filial Cestão L1. Vê todos que trabalham nessa filial (próprios + terceirizados). Aprova movimentações de subordinados.',
 '#1E7B4B', '⌂', false,
 'all','specific','all','recursive',
 ARRAY['approve_movements'],
 true),

('00000000-0000-0000-0006-000000000007','00000000-0000-0000-0001-000000000001',
 'coordenador_dept', 'Coordenador de Departamento',
 'Coordena um departamento específico. Vê colaboradores do próprio depto em qualquer filial.',
 '#F5831F', '▣', false,
 'all','all','specific','all',
 ARRAY['approve_movements'],
 true),

('00000000-0000-0000-0006-000000000008','00000000-0000-0000-0001-000000000001',
 'auditor_dpo', 'Auditor / DPO',
 'Encarregado de Proteção de Dados (LGPD). Acesso somente leitura ao log de auditoria, respondendo DSAR.',
 '#1A2D4F', '🛡', false,
 'all','all','all','all',
 ARRAY['view_audit','export_sensitive'],
 true),

('00000000-0000-0000-0006-000000000009','00000000-0000-0000-0001-000000000001',
 'readonly_diretoria', 'Diretoria · Somente leitura',
 'Para diretores que precisam de visibilidade ampla mas não devem alterar dados.',
 '#854F0B', '◉', false,
 'all','all','all','all',
 ARRAY[]::TEXT[],
 true)
ON CONFLICT (id) DO UPDATE SET
  name = EXCLUDED.name,
  description = EXCLUDED.description,
  employer_scope = EXCLUDED.employer_scope,
  unit_scope = EXCLUDED.unit_scope,
  department_scope = EXCLUDED.department_scope,
  hierarchy_scope = EXCLUDED.hierarchy_scope,
  special_permissions = EXCLUDED.special_permissions,
  updated_at = now();


-- ============================================================================
-- 7.1 PROFILE → PAGE PERMISSIONS
-- ============================================================================
-- Define o que cada perfil pode fazer em cada página
-- ============================================================================

DELETE FROM profile_page_permissions WHERE profile_id IN (
  SELECT id FROM permission_profiles WHERE company_id = '00000000-0000-0000-0001-000000000001'
);

-- Super Admin: tudo em tudo
INSERT INTO profile_page_permissions (profile_id, page_code, permissions)
SELECT '00000000-0000-0000-0006-000000000001', code, available_perms FROM system_pages;

-- Colaborador: home + perfil próprio + avaliação + feedback + mural
INSERT INTO profile_page_permissions (profile_id, page_code, permissions) VALUES
('00000000-0000-0000-0006-000000000002', 'home',                ARRAY['view']),
('00000000-0000-0000-0006-000000000002', 'colaborador_perfil',  ARRAY['view']),
('00000000-0000-0000-0006-000000000002', 'avaliacao',           ARRAY['view','create','edit']),
('00000000-0000-0000-0006-000000000002', 'feedback',            ARRAY['view','create']),
('00000000-0000-0000-0006-000000000002', 'praises',             ARRAY['view','create']);

-- Líder: tudo do colaborador + avaliar liderados + criar movimentações + aprovar 1ª instância
INSERT INTO profile_page_permissions (profile_id, page_code, permissions) VALUES
('00000000-0000-0000-0006-000000000003', 'home',                ARRAY['view']),
('00000000-0000-0000-0006-000000000003', 'colaborador_perfil',  ARRAY['view','edit']),
('00000000-0000-0000-0006-000000000003', 'colaboradores_lista', ARRAY['view']),
('00000000-0000-0000-0006-000000000003', 'movimentacoes',       ARRAY['view','create','edit','approve','reject']),
('00000000-0000-0000-0006-000000000003', 'avaliacao',           ARRAY['view','create','edit']),
('00000000-0000-0000-0006-000000000003', 'feedback',            ARRAY['view','create']),
('00000000-0000-0000-0006-000000000003', 'praises',             ARRAY['view','create']);

-- Admin RH GPC: tudo exceto auditoria avançada
INSERT INTO profile_page_permissions (profile_id, page_code, permissions)
SELECT '00000000-0000-0000-0006-000000000004', code, available_perms
  FROM system_pages WHERE code NOT IN ('auditoria');
INSERT INTO profile_page_permissions (profile_id, page_code, permissions) VALUES
('00000000-0000-0000-0006-000000000004', 'auditoria', ARRAY['view']);

-- RH Labuta: páginas de RH mas com escopo restrito a empregador Labuta
INSERT INTO profile_page_permissions (profile_id, page_code, permissions) VALUES
('00000000-0000-0000-0006-000000000005', 'home',                ARRAY['view']),
('00000000-0000-0000-0006-000000000005', 'colaboradores_lista', ARRAY['view','create','edit','export']),
('00000000-0000-0000-0006-000000000005', 'colaborador_perfil',  ARRAY['view','edit']),
('00000000-0000-0000-0006-000000000005', 'movimentacoes',       ARRAY['view','create','approve','reject']),
('00000000-0000-0000-0006-000000000005', 'aprovacoes_rh',       ARRAY['view','approve','reject']),
('00000000-0000-0000-0006-000000000005', 'importacao',          ARRAY['view','create']),
('00000000-0000-0000-0006-000000000005', 'relatorios',          ARRAY['view','export']);

-- Gerente Cestão L1: páginas de gestão de equipe mas restrito à filial
INSERT INTO profile_page_permissions (profile_id, page_code, permissions) VALUES
('00000000-0000-0000-0006-000000000006', 'home',                ARRAY['view']),
('00000000-0000-0000-0006-000000000006', 'colaboradores_lista', ARRAY['view']),
('00000000-0000-0000-0006-000000000006', 'colaborador_perfil',  ARRAY['view']),
('00000000-0000-0000-0006-000000000006', 'movimentacoes',       ARRAY['view','create','approve','reject']),
('00000000-0000-0000-0006-000000000006', 'avaliacao',           ARRAY['view','create','edit']),
('00000000-0000-0000-0006-000000000006', 'feedback',            ARRAY['view','create']),
('00000000-0000-0000-0006-000000000006', 'relatorios',          ARRAY['view']);

-- Coordenador de Departamento
INSERT INTO profile_page_permissions (profile_id, page_code, permissions) VALUES
('00000000-0000-0000-0006-000000000007', 'home',                ARRAY['view']),
('00000000-0000-0000-0006-000000000007', 'colaboradores_lista', ARRAY['view']),
('00000000-0000-0000-0006-000000000007', 'colaborador_perfil',  ARRAY['view','edit']),
('00000000-0000-0000-0006-000000000007', 'movimentacoes',       ARRAY['view','create','approve']),
('00000000-0000-0000-0006-000000000007', 'avaliacao',           ARRAY['view','create','edit']);

-- Auditor / DPO
INSERT INTO profile_page_permissions (profile_id, page_code, permissions) VALUES
('00000000-0000-0000-0006-000000000008', 'home',                ARRAY['view']),
('00000000-0000-0000-0006-000000000008', 'auditoria',           ARRAY['view','export']),
('00000000-0000-0000-0006-000000000008', 'configuracoes',       ARRAY['view']),
('00000000-0000-0000-0006-000000000008', 'colaborador_perfil',  ARRAY['view']);

-- Diretoria readonly
INSERT INTO profile_page_permissions (profile_id, page_code, permissions) VALUES
('00000000-0000-0000-0006-000000000009', 'home',                ARRAY['view']),
('00000000-0000-0000-0006-000000000009', 'dashboard_rh',        ARRAY['view']),
('00000000-0000-0000-0006-000000000009', 'colaboradores_lista', ARRAY['view']),
('00000000-0000-0000-0006-000000000009', 'colaborador_perfil',  ARRAY['view']),
('00000000-0000-0000-0006-000000000009', 'relatorios',          ARRAY['view','export']);


-- ============================================================================
-- 7.2 PROFILE EMPLOYER SCOPE · RH Labuta vê só Labuta
-- ============================================================================

DELETE FROM profile_employer_scope WHERE profile_id = '00000000-0000-0000-0006-000000000005';
INSERT INTO profile_employer_scope (profile_id, unit_id) VALUES
('00000000-0000-0000-0006-000000000005', '00000000-0000-0000-0003-000000000012');  -- LABUTA


-- ============================================================================
-- 7.3 PROFILE UNIT SCOPE · Gerente Cestão L1 vê só Cestão L1
-- ============================================================================

DELETE FROM profile_unit_scope WHERE profile_id = '00000000-0000-0000-0006-000000000006';
INSERT INTO profile_unit_scope (profile_id, unit_id) VALUES
('00000000-0000-0000-0006-000000000006', '00000000-0000-0000-0003-000000000007');  -- CES-L1



-- ============================================================================
-- 8. UPDATE units.manager_user_id agora que temos os usuários cadastrados
-- ============================================================================

UPDATE units SET manager_user_id = '00000000-0000-0000-0002-000000000007' WHERE id = '00000000-0000-0000-0003-000000000007';  -- Sandra Gomes → Cestão L1
UPDATE units SET manager_user_id = '00000000-0000-0000-0002-000000000008' WHERE id = '00000000-0000-0000-0003-000000000005';  -- Roberto Almeida → ATP-Varejo
UPDATE units SET manager_user_id = '00000000-0000-0000-0002-000000000030' WHERE id = '00000000-0000-0000-0003-000000000011';  -- Carla Reis → CD Logística
UPDATE units SET manager_user_id = '00000000-0000-0000-0002-000000000002' WHERE id = '00000000-0000-0000-0003-000000000001';  -- Maria Santos → Matriz

-- Líderes de departamento
UPDATE departments SET leader_user_id = '00000000-0000-0000-0002-000000000004' WHERE id = '00000000-0000-0000-0004-000000000001'; -- João Carvalho → Financeiro
UPDATE departments SET leader_user_id = '00000000-0000-0000-0002-000000000003' WHERE id = '00000000-0000-0000-0004-000000000002'; -- Patrícia Mello → RH
UPDATE departments SET leader_user_id = '00000000-0000-0000-0002-000000000001' WHERE id = '00000000-0000-0000-0004-000000000003'; -- Ricardo Silva → TI
UPDATE departments SET leader_user_id = '00000000-0000-0000-0002-000000000009' WHERE id = '00000000-0000-0000-0004-000000000004'; -- Talita → Comercial
UPDATE departments SET leader_user_id = '00000000-0000-0000-0002-000000000010' WHERE id = '00000000-0000-0000-0004-000000000007'; -- Carlos Augusto → Auditoria
UPDATE departments SET leader_user_id = '00000000-0000-0000-0002-000000000030' WHERE id = '00000000-0000-0000-0004-000000000014'; -- Carla Reis → Logística


-- ============================================================================
-- 9. USER_COMPANIES · vínculos triplos (empregador + tomador + departamento)
-- ============================================================================
-- Estrutura de cada linha:
-- (user, company, EMPREGADOR, TOMADOR, depto, cargo, manager, contrato, hire_date, salário, perfil_acesso)
-- ============================================================================

INSERT INTO user_companies (id, user_id, company_id,
  employer_unit_id, working_unit_id, department_id, position_id,
  manager_user_id, employee_code, contract_type, hire_date, allocation_start_date,
  base_salary, status, access_level, permission_profile_id, is_active)
VALUES

-- ============ GPC PRÓPRIOS (employer = GPC-MAT) ============

-- Ricardo Silva (Coord. BI - TI)
('00000000-0000-0000-0007-000000000001','00000000-0000-0000-0002-000000000001','00000000-0000-0000-0001-000000000001',
 '00000000-0000-0000-0003-000000000001','00000000-0000-0000-0003-000000000004','00000000-0000-0000-0004-000000000003','00000000-0000-0000-0005-000000000020',
 '00000000-0000-0000-0002-000000000002','GPC-0001','clt','2023-03-15','2023-03-15',7500.00,'active','admin','00000000-0000-0000-0006-000000000001', true),

-- Maria Santos (Diretora Financeira) - sem manager
('00000000-0000-0000-0007-000000000002','00000000-0000-0000-0002-000000000002','00000000-0000-0000-0001-000000000001',
 '00000000-0000-0000-0003-000000000001','00000000-0000-0000-0003-000000000001','00000000-0000-0000-0004-000000000001','00000000-0000-0000-0005-000000000016',
 NULL,'GPC-0002','clt','2018-01-10','2018-01-10',25000.00,'active','admin','00000000-0000-0000-0006-000000000004', true),

-- Patrícia Mello (Coord RH)
('00000000-0000-0000-0007-000000000003','00000000-0000-0000-0002-000000000003','00000000-0000-0000-0001-000000000001',
 '00000000-0000-0000-0003-000000000001','00000000-0000-0000-0003-000000000003','00000000-0000-0000-0004-000000000002','00000000-0000-0000-0005-000000000022',
 '00000000-0000-0000-0002-000000000002','GPC-0003','clt','2022-02-20','2022-02-20',8200.00,'active','hr','00000000-0000-0000-0006-000000000004', true),

-- João Carvalho (Líder Financeiro)
('00000000-0000-0000-0007-000000000004','00000000-0000-0000-0002-000000000004','00000000-0000-0000-0001-000000000001',
 '00000000-0000-0000-0003-000000000001','00000000-0000-0000-0003-000000000002','00000000-0000-0000-0004-000000000001','00000000-0000-0000-0005-000000000015',
 '00000000-0000-0000-0002-000000000002','GPC-0004','clt','2020-08-10','2020-08-10',9500.00,'active','manager','00000000-0000-0000-0006-000000000003', true),

-- Beatriz Lopes (Analista Sr. Financeiro)
('00000000-0000-0000-0007-000000000005','00000000-0000-0000-0002-000000000005','00000000-0000-0000-0001-000000000001',
 '00000000-0000-0000-0003-000000000001','00000000-0000-0000-0003-000000000002','00000000-0000-0000-0004-000000000001','00000000-0000-0000-0005-000000000014',
 '00000000-0000-0000-0002-000000000004','GPC-0005','clt','2023-06-15','2023-06-15',5500.00,'active','employee','00000000-0000-0000-0006-000000000002', true),

-- Helena Cardoso (Analista Sr. Financeiro - férias)
('00000000-0000-0000-0007-000000000006','00000000-0000-0000-0002-000000000006','00000000-0000-0000-0001-000000000001',
 '00000000-0000-0000-0003-000000000001','00000000-0000-0000-0003-000000000002','00000000-0000-0000-0004-000000000001','00000000-0000-0000-0005-000000000014',
 '00000000-0000-0000-0002-000000000004','GPC-0006','clt','2022-12-01','2022-12-01',5400.00,'vacation','employee','00000000-0000-0000-0006-000000000002', true),

-- Sandra Gomes (Gerente Cestão L1)
('00000000-0000-0000-0007-000000000007','00000000-0000-0000-0002-000000000007','00000000-0000-0000-0001-000000000001',
 '00000000-0000-0000-0003-000000000001','00000000-0000-0000-0003-000000000007','00000000-0000-0000-0004-000000000009','00000000-0000-0000-0005-000000000006',
 '00000000-0000-0000-0002-000000000002','GPC-0007','clt','2019-07-12','2019-07-12',11000.00,'active','manager','00000000-0000-0000-0006-000000000006', true),

-- Roberto Almeida (Gerente ATP-Varejo)
('00000000-0000-0000-0007-000000000008','00000000-0000-0000-0002-000000000008','00000000-0000-0000-0001-000000000001',
 '00000000-0000-0000-0003-000000000001','00000000-0000-0000-0003-000000000005','00000000-0000-0000-0004-000000000009','00000000-0000-0000-0005-000000000006',
 '00000000-0000-0000-0002-000000000002','GPC-0008','clt','2019-02-08','2019-02-08',10500.00,'active','manager','00000000-0000-0000-0006-000000000003', true),

-- Talita Comercial (Diretora Comercial)
('00000000-0000-0000-0007-000000000009','00000000-0000-0000-0002-000000000009','00000000-0000-0000-0001-000000000001',
 '00000000-0000-0000-0003-000000000001','00000000-0000-0000-0003-000000000001','00000000-0000-0000-0004-000000000004','00000000-0000-0000-0005-000000000019',
 '00000000-0000-0000-0002-000000000002','GPC-0009','clt','2021-03-05','2021-03-05',18000.00,'active','admin','00000000-0000-0000-0006-000000000003', true),

-- Carlos Augusto (Auditor Sênior)
('00000000-0000-0000-0007-000000000010','00000000-0000-0000-0002-000000000010','00000000-0000-0000-0001-000000000001',
 '00000000-0000-0000-0003-000000000001','00000000-0000-0000-0003-000000000001','00000000-0000-0000-0004-000000000007','00000000-0000-0000-0005-000000000024',
 '00000000-0000-0000-0002-000000000002','GPC-0010','clt','2021-10-15','2021-10-15',8800.00,'active','manager','00000000-0000-0000-0006-000000000003', true),

-- Pedro Lima (Subgerente ATP-Varejo)
('00000000-0000-0000-0007-000000000029','00000000-0000-0000-0002-000000000029','00000000-0000-0000-0001-000000000001',
 '00000000-0000-0000-0003-000000000001','00000000-0000-0000-0003-000000000005','00000000-0000-0000-0004-000000000009','00000000-0000-0000-0005-000000000005',
 '00000000-0000-0000-0002-000000000008','GPC-0029','clt','2021-06-12','2021-06-12',4800.00,'active','manager','00000000-0000-0000-0006-000000000003', true),

-- Carla Reis (Coord. Logística)
('00000000-0000-0000-0007-000000000030','00000000-0000-0000-0002-000000000030','00000000-0000-0000-0001-000000000001',
 '00000000-0000-0000-0003-000000000001','00000000-0000-0000-0003-000000000011','00000000-0000-0000-0004-000000000014','00000000-0000-0000-0005-000000000008',
 '00000000-0000-0000-0002-000000000002','GPC-0030','clt','2020-10-25','2020-10-25',8500.00,'active','manager','00000000-0000-0000-0006-000000000003', true),

-- ============ LABUTA TERCEIRIZADOS (employer = LABUTA) ============

-- Fernanda Lima (Analista Pleno - alocada Cestão L1)
('00000000-0000-0000-0007-000000000011','00000000-0000-0000-0002-000000000011','00000000-0000-0000-0001-000000000001',
 '00000000-0000-0000-0003-000000000012','00000000-0000-0000-0003-000000000007','00000000-0000-0000-0004-000000000001','00000000-0000-0000-0005-000000000013',
 '00000000-0000-0000-0002-000000000004','LAB-0001','terceirizado','2024-01-15','2024-01-15',3900.00,'active','employee','00000000-0000-0000-0006-000000000002', true),

-- Carlos Eduardo (Analista Pleno - alocado ATP-Atacado)
('00000000-0000-0000-0007-000000000012','00000000-0000-0000-0002-000000000012','00000000-0000-0000-0001-000000000001',
 '00000000-0000-0000-0003-000000000012','00000000-0000-0000-0003-000000000006','00000000-0000-0000-0004-000000000004','00000000-0000-0000-0005-000000000017',
 '00000000-0000-0000-0002-000000000009','LAB-0002','terceirizado','2024-08-22','2024-08-22',4100.00,'active','employee','00000000-0000-0000-0006-000000000002', true),

-- Daniela Vieira (Analista Júnior - alocada Cestão L1)
('00000000-0000-0000-0007-000000000013','00000000-0000-0000-0002-000000000013','00000000-0000-0000-0001-000000000001',
 '00000000-0000-0000-0003-000000000012','00000000-0000-0000-0003-000000000007','00000000-0000-0000-0004-000000000001','00000000-0000-0000-0005-000000000012',
 '00000000-0000-0000-0002-000000000004','LAB-0003','terceirizado','2025-02-10','2025-02-10',2800.00,'active','employee','00000000-0000-0000-0006-000000000002', true),

-- Gabriel Pinto (Estagiário - alocado Cestão L1)
('00000000-0000-0000-0007-000000000014','00000000-0000-0000-0002-000000000014','00000000-0000-0000-0001-000000000001',
 '00000000-0000-0000-0003-000000000012','00000000-0000-0000-0003-000000000007','00000000-0000-0000-0004-000000000001','00000000-0000-0000-0005-000000000026',
 '00000000-0000-0000-0002-000000000004','LAB-0004','estagio','2025-08-05','2025-08-05',1400.00,'active','employee','00000000-0000-0000-0006-000000000002', true),

-- Otávio Pereira (Operador de Caixa - Cestão L1)
('00000000-0000-0000-0007-000000000015','00000000-0000-0000-0002-000000000015','00000000-0000-0000-0001-000000000001',
 '00000000-0000-0000-0003-000000000012','00000000-0000-0000-0003-000000000007','00000000-0000-0000-0004-000000000010','00000000-0000-0000-0005-000000000001',
 '00000000-0000-0000-0002-000000000007','LAB-0005','terceirizado','2024-03-12','2024-03-12',1620.00,'active','employee','00000000-0000-0000-0006-000000000002', true),

-- Júlia Machado (Operadora Caixa - ATP-Varejo, em licença maternidade)
('00000000-0000-0000-0007-000000000016','00000000-0000-0000-0002-000000000016','00000000-0000-0000-0001-000000000001',
 '00000000-0000-0000-0003-000000000012','00000000-0000-0000-0003-000000000005','00000000-0000-0000-0004-000000000010','00000000-0000-0000-0005-000000000001',
 '00000000-0000-0000-0002-000000000008','LAB-0006','terceirizado','2024-10-30','2024-10-30',1620.00,'maternity_leave','employee','00000000-0000-0000-0006-000000000002', true),

-- Pedro Felipe (Repositor - ATP-Varejo)
('00000000-0000-0000-0007-000000000017','00000000-0000-0000-0002-000000000017','00000000-0000-0000-0001-000000000001',
 '00000000-0000-0000-0003-000000000012','00000000-0000-0000-0003-000000000005','00000000-0000-0000-0004-000000000013','00000000-0000-0000-0005-000000000002',
 '00000000-0000-0000-0002-000000000008','LAB-0007','terceirizado','2025-06-18','2025-06-18',1620.00,'active','employee','00000000-0000-0000-0006-000000000002', true),

-- Ana Beatriz (Analista Marketing - alocada GPC Matriz)
('00000000-0000-0000-0007-000000000018','00000000-0000-0000-0002-000000000018','00000000-0000-0000-0001-000000000001',
 '00000000-0000-0000-0003-000000000012','00000000-0000-0000-0003-000000000001','00000000-0000-0000-0004-000000000006','00000000-0000-0000-0005-000000000018',
 '00000000-0000-0000-0002-000000000009','LAB-0008','terceirizado','2023-10-22','2023-10-22',4500.00,'active','employee','00000000-0000-0000-0006-000000000002', true),

-- Eduardo Mendes (Conferente - CD Logística)
('00000000-0000-0000-0007-000000000019','00000000-0000-0000-0002-000000000019','00000000-0000-0000-0001-000000000001',
 '00000000-0000-0000-0003-000000000012','00000000-0000-0000-0003-000000000011','00000000-0000-0000-0004-000000000014','00000000-0000-0000-0005-000000000007',
 '00000000-0000-0000-0002-000000000030','LAB-0009','terceirizado','2023-02-28','2023-02-28',2200.00,'active','employee','00000000-0000-0000-0006-000000000002', true),

-- Larissa Rocha (Operadora - Cestão Inhambupe, férias)
('00000000-0000-0000-0007-000000000020','00000000-0000-0000-0002-000000000020','00000000-0000-0000-0001-000000000001',
 '00000000-0000-0000-0003-000000000012','00000000-0000-0000-0003-000000000008','00000000-0000-0000-0004-000000000010','00000000-0000-0000-0005-000000000001',
 NULL,'LAB-0010','terceirizado','2025-03-15','2025-03-15',1620.00,'vacation','employee','00000000-0000-0000-0006-000000000002', true),

-- Igor Vasconcelos (Açougueiro - Cestão L1)
('00000000-0000-0000-0007-000000000021','00000000-0000-0000-0002-000000000021','00000000-0000-0000-0001-000000000001',
 '00000000-0000-0000-0003-000000000012','00000000-0000-0000-0003-000000000007','00000000-0000-0000-0004-000000000011','00000000-0000-0000-0005-000000000003',
 '00000000-0000-0000-0002-000000000007','LAB-0011','terceirizado','2022-04-08','2022-04-08',2400.00,'active','employee','00000000-0000-0000-0006-000000000002', true),

-- Natália Ferreira (Aux Financeiro - GPC Financeiro)
('00000000-0000-0000-0007-000000000022','00000000-0000-0000-0002-000000000022','00000000-0000-0000-0001-000000000001',
 '00000000-0000-0000-0003-000000000012','00000000-0000-0000-0003-000000000002','00000000-0000-0000-0004-000000000001','00000000-0000-0000-0005-000000000011',
 '00000000-0000-0000-0002-000000000004','LAB-0012','terceirizado','2025-10-20','2025-10-20',2200.00,'active','employee','00000000-0000-0000-0006-000000000002', true),

-- Larissa Pereira (RH da Labuta - usa o perfil rh_prestadora_labuta)
-- Ela é empregada DIRETAMENTE pela Labuta e trabalha NA própria Labuta administrando
('00000000-0000-0000-0007-000000000040','00000000-0000-0000-0002-000000000040','00000000-0000-0000-0001-000000000001',
 '00000000-0000-0000-0003-000000000012','00000000-0000-0000-0003-000000000012','00000000-0000-0000-0004-000000000002','00000000-0000-0000-0005-000000000022',
 NULL,'LAB-RH-01','terceirizado','2022-11-15','2022-11-15',7800.00,'active','hr','00000000-0000-0000-0006-000000000005', true),

-- ============ LIMPACTIVA (employer = LIMPAC) ============

-- José da Silva (Aux. Limpeza - ATP-Varejo)
('00000000-0000-0000-0007-000000000023','00000000-0000-0000-0002-000000000023','00000000-0000-0000-0001-000000000001',
 '00000000-0000-0000-0003-000000000013','00000000-0000-0000-0003-000000000005','00000000-0000-0000-0004-000000000015','00000000-0000-0000-0005-000000000009',
 NULL,'LIM-0001','terceirizado','2020-12-01','2020-12-01',1518.00,'active','employee','00000000-0000-0000-0006-000000000002', true),

-- Maria Aparecida (Aux. Limpeza - Cestão L1)
('00000000-0000-0000-0007-000000000024','00000000-0000-0000-0002-000000000024','00000000-0000-0000-0001-000000000001',
 '00000000-0000-0000-0003-000000000013','00000000-0000-0000-0003-000000000007','00000000-0000-0000-0004-000000000015','00000000-0000-0000-0005-000000000009',
 NULL,'LIM-0002','terceirizado','2023-06-10','2023-06-10',1518.00,'active','employee','00000000-0000-0000-0006-000000000002', true),

-- Antônio Lopes (Aux. Limpeza - CD Logística)
('00000000-0000-0000-0007-000000000025','00000000-0000-0000-0002-000000000025','00000000-0000-0000-0001-000000000001',
 '00000000-0000-0000-0003-000000000013','00000000-0000-0000-0003-000000000011','00000000-0000-0000-0004-000000000015','00000000-0000-0000-0005-000000000009',
 NULL,'LIM-0003','terceirizado','2024-12-15','2024-12-15',1518.00,'active','employee','00000000-0000-0000-0006-000000000002', true),

-- ============ SEGURE (employer = SEGURE) ============

-- Sérgio Rodrigues (Vigilante - Cestão L1)
('00000000-0000-0000-0007-000000000026','00000000-0000-0000-0002-000000000026','00000000-0000-0000-0001-000000000001',
 '00000000-0000-0000-0003-000000000014','00000000-0000-0000-0003-000000000007','00000000-0000-0000-0004-000000000009','00000000-0000-0000-0005-000000000010',
 NULL,'SEG-0001','terceirizado','2020-02-15','2020-02-15',2100.00,'active','employee','00000000-0000-0000-0006-000000000002', true),

-- Marcos Gonçalves (Vigilante - ATP-Varejo)
('00000000-0000-0000-0007-000000000027','00000000-0000-0000-0002-000000000027','00000000-0000-0000-0001-000000000001',
 '00000000-0000-0000-0003-000000000014','00000000-0000-0000-0003-000000000005','00000000-0000-0000-0004-000000000009','00000000-0000-0000-0005-000000000010',
 NULL,'SEG-0002','terceirizado','2022-09-20','2022-09-20',2100.00,'active','employee','00000000-0000-0000-0006-000000000002', true),

-- Wagner Pereira (Vigilante - CD Logística)
('00000000-0000-0000-0007-000000000028','00000000-0000-0000-0002-000000000028','00000000-0000-0000-0001-000000000001',
 '00000000-0000-0000-0003-000000000014','00000000-0000-0000-0003-000000000011','00000000-0000-0000-0004-000000000009','00000000-0000-0000-0005-000000000010',
 NULL,'SEG-0003','terceirizado','2024-02-28','2024-02-28',2100.00,'active','employee','00000000-0000-0000-0006-000000000002', true),

-- ============ DPO (Carla Moreira - vinculada à GPC mas com perfil de auditor) ============

('00000000-0000-0000-0007-000000000041','00000000-0000-0000-0002-000000000041','00000000-0000-0000-0001-000000000001',
 '00000000-0000-0000-0003-000000000001','00000000-0000-0000-0003-000000000001','00000000-0000-0000-0004-000000000007','00000000-0000-0000-0005-000000000025',
 '00000000-0000-0000-0002-000000000002','GPC-DPO-01','clt','2023-08-01','2023-08-01',9000.00,'active','admin','00000000-0000-0000-0006-000000000008', true)

ON CONFLICT (id) DO UPDATE SET
  employer_unit_id = EXCLUDED.employer_unit_id,
  working_unit_id = EXCLUDED.working_unit_id,
  department_id = EXCLUDED.department_id,
  position_id = EXCLUDED.position_id,
  manager_user_id = EXCLUDED.manager_user_id,
  contract_type = EXCLUDED.contract_type,
  hire_date = EXCLUDED.hire_date,
  base_salary = EXCLUDED.base_salary,
  status = EXCLUDED.status,
  permission_profile_id = EXCLUDED.permission_profile_id,
  updated_at = now();


-- ============================================================================
-- 10. COMPETENCIES · 8 competências do framework do GPC
-- ============================================================================

INSERT INTO competencies (id, company_id, name, description, category, weight, active) VALUES
('00000000-0000-0000-0008-000000000001','00000000-0000-0000-0001-000000000001','Foco no cliente',     'Capacidade de entender e atender necessidades do cliente',           'comportamental',1.5, true),
('00000000-0000-0000-0008-000000000002','00000000-0000-0000-0001-000000000001','Comunicação',         'Clareza ao se expressar e escutar ativamente',                       'comportamental',1.0, true),
('00000000-0000-0000-0008-000000000003','00000000-0000-0000-0001-000000000001','Trabalho em equipe',  'Colabora ativamente e contribui com o grupo',                        'comportamental',1.0, true),
('00000000-0000-0000-0008-000000000004','00000000-0000-0000-0001-000000000001','Proatividade',        'Antecipa-se a problemas e propõe melhorias',                         'comportamental',1.2, true),
('00000000-0000-0000-0008-000000000005','00000000-0000-0000-0001-000000000001','Domínio técnico',     'Conhecimento e aplicação das ferramentas e processos da função',     'tecnica',       1.5, true),
('00000000-0000-0000-0008-000000000006','00000000-0000-0000-0001-000000000001','Qualidade da entrega','Atenção a detalhes e cumprimento de padrões',                        'tecnica',       1.3, true),
('00000000-0000-0000-0008-000000000007','00000000-0000-0000-0001-000000000001','Liderança',           'Inspira e desenvolve liderados (apenas para cargos de gestão)',      'lideranca',     1.5, true),
('00000000-0000-0000-0008-000000000008','00000000-0000-0000-0001-000000000001','Visão estratégica',   'Pensa no longo prazo e em impacto sistêmico',                        'lideranca',     1.0, true)
ON CONFLICT (id) DO UPDATE SET
  name = EXCLUDED.name,
  description = EXCLUDED.description,
  weight = EXCLUDED.weight;


-- ============================================================================
-- 11. REVIEW CYCLE · Ciclo 2026.1 em andamento (fase manager_eval)
-- ============================================================================

INSERT INTO review_cycles (id, company_id, name, start_date, end_date,
  self_eval_deadline, manager_eval_deadline, status, scale_max, allow_anonymous_peer, config) VALUES
('00000000-0000-0000-0009-000000000001','00000000-0000-0000-0001-000000000001',
 '2026.1 - 1º Semestre 2026',
 '2026-03-02','2026-06-30',
 '2026-03-31','2026-04-30',
 'manager_eval', 5, false,
 jsonb_build_object(
   'eval_types', ARRAY['self','manager'],
   'self_window_days', 7,
   'nine_box_phase_start', '2026-05-01',
   'feedback_phase_start', '2026-05-16'
 ))
ON CONFLICT (id) DO UPDATE SET
  status = EXCLUDED.status,
  config = EXCLUDED.config,
  updated_at = now();

-- Vincular as 8 competências ao ciclo
DELETE FROM cycle_competencies WHERE cycle_id = '00000000-0000-0000-0009-000000000001';
INSERT INTO cycle_competencies (cycle_id, competency_id, weight)
SELECT '00000000-0000-0000-0009-000000000001', id, weight FROM competencies WHERE company_id = '00000000-0000-0000-0001-000000000001';


-- ============================================================================
-- 12. RESUMO E VERIFICAÇÃO
-- ============================================================================

DO $$
DECLARE
  c_companies   INTEGER;
  c_users       INTEGER;
  c_units       INTEGER;
  c_units_op    INTEGER;
  c_units_sp    INTEGER;
  c_units_ad    INTEGER;
  c_depts       INTEGER;
  c_positions   INTEGER;
  c_profiles    INTEGER;
  c_uc          INTEGER;
  c_uc_gpc      INTEGER;
  c_uc_lab      INTEGER;
  c_uc_lim      INTEGER;
  c_uc_seg      INTEGER;
  c_comps       INTEGER;
  c_cycles      INTEGER;
BEGIN
  SELECT COUNT(*) INTO c_companies FROM companies WHERE id = '00000000-0000-0000-0001-000000000001';
  SELECT COUNT(*) INTO c_users     FROM users     WHERE deleted_at IS NULL;
  SELECT COUNT(*) INTO c_units     FROM units     WHERE company_id = '00000000-0000-0000-0001-000000000001';
  SELECT COUNT(*) INTO c_units_op  FROM units     WHERE company_id = '00000000-0000-0000-0001-000000000001' AND role = 'operational';
  SELECT COUNT(*) INTO c_units_sp  FROM units     WHERE company_id = '00000000-0000-0000-0001-000000000001' AND role = 'service_provider';
  SELECT COUNT(*) INTO c_units_ad  FROM units     WHERE company_id = '00000000-0000-0000-0001-000000000001' AND role = 'administrative';
  SELECT COUNT(*) INTO c_depts     FROM departments WHERE company_id = '00000000-0000-0000-0001-000000000001';
  SELECT COUNT(*) INTO c_positions FROM positions WHERE company_id = '00000000-0000-0000-0001-000000000001';
  SELECT COUNT(*) INTO c_profiles  FROM permission_profiles WHERE company_id = '00000000-0000-0000-0001-000000000001';
  SELECT COUNT(*) INTO c_uc        FROM user_companies WHERE company_id = '00000000-0000-0000-0001-000000000001';
  SELECT COUNT(*) INTO c_uc_gpc    FROM user_companies WHERE company_id = '00000000-0000-0000-0001-000000000001' AND employer_unit_id = '00000000-0000-0000-0003-000000000001';
  SELECT COUNT(*) INTO c_uc_lab    FROM user_companies WHERE company_id = '00000000-0000-0000-0001-000000000001' AND employer_unit_id = '00000000-0000-0000-0003-000000000012';
  SELECT COUNT(*) INTO c_uc_lim    FROM user_companies WHERE company_id = '00000000-0000-0000-0001-000000000001' AND employer_unit_id = '00000000-0000-0000-0003-000000000013';
  SELECT COUNT(*) INTO c_uc_seg    FROM user_companies WHERE company_id = '00000000-0000-0000-0001-000000000001' AND employer_unit_id = '00000000-0000-0000-0003-000000000014';
  SELECT COUNT(*) INTO c_comps     FROM competencies WHERE company_id = '00000000-0000-0000-0001-000000000001';
  SELECT COUNT(*) INTO c_cycles    FROM review_cycles WHERE company_id = '00000000-0000-0000-0001-000000000001';

  RAISE NOTICE '';
  RAISE NOTICE '════════════════════════════════════════════════════════════════';
  RAISE NOTICE '  R2 PEOPLE - SEED INICIAL CONCLUÍDO';
  RAISE NOTICE '════════════════════════════════════════════════════════════════';
  RAISE NOTICE '  Tenant (companies):       %', c_companies;
  RAISE NOTICE '  Usuários (users):         %', c_users;
  RAISE NOTICE '  Unidades totais:          %', c_units;
  RAISE NOTICE '    operational:            %', c_units_op;
  RAISE NOTICE '    service_provider:       %', c_units_sp;
  RAISE NOTICE '    administrative:         %', c_units_ad;
  RAISE NOTICE '  Departamentos:            %', c_depts;
  RAISE NOTICE '  Cargos:                   %', c_positions;
  RAISE NOTICE '  Perfis de acesso:         %', c_profiles;
  RAISE NOTICE '  Vínculos (user_companies):%', c_uc;
  RAISE NOTICE '    GPC próprios:           %', c_uc_gpc;
  RAISE NOTICE '    Labuta:                 %', c_uc_lab;
  RAISE NOTICE '    Limpactiva:             %', c_uc_lim;
  RAISE NOTICE '    Segure:                 %', c_uc_seg;
  RAISE NOTICE '  Competências:             %', c_comps;
  RAISE NOTICE '  Ciclos de avaliação:      %', c_cycles;
  RAISE NOTICE '════════════════════════════════════════════════════════════════';
END $$;

COMMIT;


-- ============================================================================
-- LIMPEZA (descomentar APENAS para zerar o ambiente do GPC)
-- ============================================================================
/*
BEGIN;
DELETE FROM cycle_competencies      WHERE cycle_id IN (SELECT id FROM review_cycles WHERE company_id = '00000000-0000-0000-0001-000000000001');
DELETE FROM review_cycles           WHERE company_id = '00000000-0000-0000-0001-000000000001';
DELETE FROM competencies            WHERE company_id = '00000000-0000-0000-0001-000000000001';
DELETE FROM user_companies          WHERE company_id = '00000000-0000-0000-0001-000000000001';
DELETE FROM profile_employer_scope  WHERE profile_id IN (SELECT id FROM permission_profiles WHERE company_id = '00000000-0000-0000-0001-000000000001');
DELETE FROM profile_unit_scope      WHERE profile_id IN (SELECT id FROM permission_profiles WHERE company_id = '00000000-0000-0000-0001-000000000001');
DELETE FROM profile_page_permissions WHERE profile_id IN (SELECT id FROM permission_profiles WHERE company_id = '00000000-0000-0000-0001-000000000001');
DELETE FROM permission_profiles     WHERE company_id = '00000000-0000-0000-0001-000000000001';
DELETE FROM positions               WHERE company_id = '00000000-0000-0000-0001-000000000001';
DELETE FROM departments             WHERE company_id = '00000000-0000-0000-0001-000000000001';
DELETE FROM units                   WHERE company_id = '00000000-0000-0000-0001-000000000001';
DELETE FROM users                   WHERE id IN (
  SELECT id FROM users WHERE id::text LIKE '00000000-0000-0000-0002-%'
);
DELETE FROM companies               WHERE id = '00000000-0000-0000-0001-000000000001';
COMMIT;
*/

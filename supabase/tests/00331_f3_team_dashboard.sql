-- ============================================================================
-- R2 People · Testes Sessao F3 · Dashboard da equipe
-- ============================================================================
-- 12 testes:
--   T01-T02 · estrutura basica (sem subordinados / com subordinados)
--   T03-T05 · pdis_overdue (cobertura, ordenacao, dias)
--   T06-T08 · recognitions rankings (publicos, privados, escopo)
--   T09     · include_indirect engloba neto
--   T10-T12 · isolamento por gestor + permissoes
-- ============================================================================

BEGIN;

-- ----------------------------------------------------------------------------
-- SETUP
-- ----------------------------------------------------------------------------

INSERT INTO tenants (id, slug, legal_name, display_name) VALUES
  ('f3aaaaaa-0000-0000-0000-000000000001', 'tx-f3', 'Tenant X F3', 'X');

-- Hierarquia:
--   SA (super_admin)
--   GERENTE
--     SUB1 / SUB2
--       NETO (sob SUB2)
--   OUTRO_GERENTE
--     SUB_OUTRO

INSERT INTO app_users (id, tenant_id, auth_user_id, email, full_name, role, manager_id, employment_link, hired_at) VALUES
  ('f3aaaaaa-0001-0000-0000-000000000001', 'f3aaaaaa-0000-0000-0000-000000000001',
   'f3aaaaaa-1001-0000-0000-000000000001', 'sa@f3.test', 'SA-F3', 'super_admin', NULL, 'clt', '2020-01-01'),
  ('f3aaaaaa-0001-0000-0000-000000000010', 'f3aaaaaa-0000-0000-0000-000000000001',
   'f3aaaaaa-1001-0000-0000-000000000010', 'gerente@f3.test', 'GERENTE-F3', 'lider', NULL, 'clt', '2020-01-01'),
  ('f3aaaaaa-0001-0000-0000-000000000011', 'f3aaaaaa-0000-0000-0000-000000000001',
   'f3aaaaaa-1001-0000-0000-000000000011', 'sub1@f3.test', 'SUB1-F3', 'colaborador',
   'f3aaaaaa-0001-0000-0000-000000000010', 'clt', '2021-01-01'),
  ('f3aaaaaa-0001-0000-0000-000000000012', 'f3aaaaaa-0000-0000-0000-000000000001',
   'f3aaaaaa-1001-0000-0000-000000000012', 'sub2@f3.test', 'SUB2-F3', 'lider',
   'f3aaaaaa-0001-0000-0000-000000000010', 'clt', '2021-01-01'),
  ('f3aaaaaa-0001-0000-0000-000000000013', 'f3aaaaaa-0000-0000-0000-000000000001',
   'f3aaaaaa-1001-0000-0000-000000000013', 'neto@f3.test', 'NETO-F3', 'colaborador',
   'f3aaaaaa-0001-0000-0000-000000000012', 'clt', '2022-01-01'),
  ('f3aaaaaa-0001-0000-0000-000000000020', 'f3aaaaaa-0000-0000-0000-000000000001',
   'f3aaaaaa-1001-0000-0000-000000000020', 'outro@f3.test', 'OUTRO-GER-F3', 'lider', NULL, 'clt', '2020-01-01'),
  ('f3aaaaaa-0001-0000-0000-000000000021', 'f3aaaaaa-0000-0000-0000-000000000001',
   'f3aaaaaa-1001-0000-0000-000000000021', 'subo@f3.test', 'SUB-OUTRO-F3', 'colaborador',
   'f3aaaaaa-0001-0000-0000-000000000020', 'clt', '2021-01-01');

-- Fichas (employees) para nomes detalhados
INSERT INTO employees (id, tenant_id, full_name, job_title, hire_date, cpf, created_by) VALUES
  ('f3aaaaaa-0002-0000-0000-000000000011', 'f3aaaaaa-0000-0000-0000-000000000001',
   'SUB1 F3 FICHA', 'Op', '2021-01-01', '31111111111',
   'f3aaaaaa-0001-0000-0000-000000000001'),
  ('f3aaaaaa-0002-0000-0000-000000000012', 'f3aaaaaa-0000-0000-0000-000000000001',
   'SUB2 F3 FICHA', 'Lider', '2021-01-01', '32222222222',
   'f3aaaaaa-0001-0000-0000-000000000001'),
  ('f3aaaaaa-0002-0000-0000-000000000013', 'f3aaaaaa-0000-0000-0000-000000000001',
   'NETO F3 FICHA', 'Op', '2022-01-01', '33333333333',
   'f3aaaaaa-0001-0000-0000-000000000001');

UPDATE app_users SET employee_id = 'f3aaaaaa-0002-0000-0000-000000000011'
  WHERE id = 'f3aaaaaa-0001-0000-0000-000000000011';
UPDATE app_users SET employee_id = 'f3aaaaaa-0002-0000-0000-000000000012'
  WHERE id = 'f3aaaaaa-0001-0000-0000-000000000012';
UPDATE app_users SET employee_id = 'f3aaaaaa-0002-0000-0000-000000000013'
  WHERE id = 'f3aaaaaa-0001-0000-0000-000000000013';

-- PDI cycle
INSERT INTO pdi_cycles (id, tenant_id, code, display_name, start_date, end_date, active) VALUES
  ('f3aaaaaa-0003-0000-0000-000000000001', 'f3aaaaaa-0000-0000-0000-000000000001',
   'PDI2024F3', 'PDI 2024', '2024-01-01', '2024-12-31', TRUE),
  ('f3aaaaaa-0003-0000-0000-000000000002', 'f3aaaaaa-0000-0000-0000-000000000001',
   'PDI2023F3', 'PDI 2023', '2023-01-01', '2023-12-31', FALSE);

-- 2 PDIs em atraso de SUB1 em ciclos diferentes: 1 muito atrasado, 1 pouco atrasado
INSERT INTO pdis (id, tenant_id, user_id, cycle_id, manager_id_snapshot,
                  objective, status, start_date, end_date, actions_total, actions_completed, created_by)
VALUES
  ('f3aaaaaa-0004-0000-0000-000000000001', 'f3aaaaaa-0000-0000-0000-000000000001',
   'f3aaaaaa-0001-0000-0000-000000000011',
   'f3aaaaaa-0003-0000-0000-000000000002',
   'f3aaaaaa-0001-0000-0000-000000000010',
   'PDI antigo', 'active', '2023-01-01', CURRENT_DATE - 60, 4, 1,
   'f3aaaaaa-0001-0000-0000-000000000010'),
  ('f3aaaaaa-0004-0000-0000-000000000002', 'f3aaaaaa-0000-0000-0000-000000000001',
   'f3aaaaaa-0001-0000-0000-000000000011',
   'f3aaaaaa-0003-0000-0000-000000000001',
   'f3aaaaaa-0001-0000-0000-000000000010',
   'PDI recem-vencido', 'active', '2024-01-01', CURRENT_DATE - 5, 5, 4,
   'f3aaaaaa-0001-0000-0000-000000000010');

-- 1 PDI no prazo de SUB2 (nao deve aparecer)
INSERT INTO pdis (id, tenant_id, user_id, cycle_id, manager_id_snapshot,
                  objective, status, start_date, end_date, created_by)
VALUES (
  'f3aaaaaa-0004-0000-0000-000000000003', 'f3aaaaaa-0000-0000-0000-000000000001',
  'f3aaaaaa-0001-0000-0000-000000000012',
  'f3aaaaaa-0003-0000-0000-000000000001',
  'f3aaaaaa-0001-0000-0000-000000000010',
  'PDI no prazo', 'active', '2024-01-01', CURRENT_DATE + 30,
  'f3aaaaaa-0001-0000-0000-000000000010'
);

-- 1 PDI completed de SUB2 (status nao bate, nao deve aparecer mesmo se end vencida)
INSERT INTO pdis (id, tenant_id, user_id, cycle_id, manager_id_snapshot,
                  objective, status, start_date, end_date, completed_at, created_by)
VALUES (
  'f3aaaaaa-0004-0000-0000-000000000004', 'f3aaaaaa-0000-0000-0000-000000000001',
  'f3aaaaaa-0001-0000-0000-000000000012',
  'f3aaaaaa-0003-0000-0000-000000000002',
  'f3aaaaaa-0001-0000-0000-000000000010',
  'PDI ja concluido', 'completed', '2023-01-01', CURRENT_DATE - 100, now(),
  'f3aaaaaa-0001-0000-0000-000000000010'
);

-- 1 PDI atrasado de NETO (so aparece se include_indirect=true)
INSERT INTO pdis (id, tenant_id, user_id, cycle_id, manager_id_snapshot,
                  objective, status, start_date, end_date, created_by)
VALUES (
  'f3aaaaaa-0004-0000-0000-000000000005', 'f3aaaaaa-0000-0000-0000-000000000001',
  'f3aaaaaa-0001-0000-0000-000000000013',
  'f3aaaaaa-0003-0000-0000-000000000001',
  'f3aaaaaa-0001-0000-0000-000000000012',
  'PDI do neto atrasado', 'active', '2024-01-01', CURRENT_DATE - 10,
  'f3aaaaaa-0001-0000-0000-000000000012'
);

-- Reconhecimentos · varios padroes
INSERT INTO recognitions (id, tenant_id, sender_id, recipient_id, message, is_private, created_at)
VALUES
  -- SUB1 recebe 3 publicos do GERENTE
  ('f3aaaaaa-0005-0000-0000-000000000001', 'f3aaaaaa-0000-0000-0000-000000000001',
   'f3aaaaaa-0001-0000-0000-000000000010', 'f3aaaaaa-0001-0000-0000-000000000011',
   'Otimo projeto X', FALSE, now() - INTERVAL '10 days'),
  ('f3aaaaaa-0005-0000-0000-000000000002', 'f3aaaaaa-0000-0000-0000-000000000001',
   'f3aaaaaa-0001-0000-0000-000000000010', 'f3aaaaaa-0001-0000-0000-000000000011',
   'Ajuda no Y', FALSE, now() - INTERVAL '5 days'),
  ('f3aaaaaa-0005-0000-0000-000000000003', 'f3aaaaaa-0000-0000-0000-000000000001',
   'f3aaaaaa-0001-0000-0000-000000000010', 'f3aaaaaa-0001-0000-0000-000000000011',
   'Iniciativa Z', FALSE, now() - INTERVAL '2 days'),

  -- SUB1 recebe 1 privado de OUTRO_GERENTE (gerente da equipe nao deve ver)
  ('f3aaaaaa-0005-0000-0000-000000000004', 'f3aaaaaa-0000-0000-0000-000000000001',
   'f3aaaaaa-0001-0000-0000-000000000020', 'f3aaaaaa-0001-0000-0000-000000000011',
   'Mentoria informal', TRUE, now() - INTERVAL '15 days'),

  -- SUB2 recebe 1 publico
  ('f3aaaaaa-0005-0000-0000-000000000005', 'f3aaaaaa-0000-0000-0000-000000000001',
   'f3aaaaaa-0001-0000-0000-000000000010', 'f3aaaaaa-0001-0000-0000-000000000012',
   'Bom trabalho', FALSE, now() - INTERVAL '8 days'),

  -- SUB2 envia 2 publicos (vira sender)
  ('f3aaaaaa-0005-0000-0000-000000000006', 'f3aaaaaa-0000-0000-0000-000000000001',
   'f3aaaaaa-0001-0000-0000-000000000012', 'f3aaaaaa-0001-0000-0000-000000000013',
   'NETO ajudou muito', FALSE, now() - INTERVAL '3 days'),
  ('f3aaaaaa-0005-0000-0000-000000000007', 'f3aaaaaa-0000-0000-0000-000000000001',
   'f3aaaaaa-0001-0000-0000-000000000012', 'f3aaaaaa-0001-0000-0000-000000000011',
   'SUB1 obrigado', FALSE, now() - INTERVAL '4 days'),

  -- NETO recebe 1 publico (so visivel com include_indirect)
  ('f3aaaaaa-0005-0000-0000-000000000008', 'f3aaaaaa-0000-0000-0000-000000000001',
   'f3aaaaaa-0001-0000-0000-000000000012', 'f3aaaaaa-0001-0000-0000-000000000013',
   'NETO 2', FALSE, now() - INTERVAL '6 days'),

  -- Reconhecimento muito antigo (>90d) · nao deve entrar
  ('f3aaaaaa-0005-0000-0000-000000000009', 'f3aaaaaa-0000-0000-0000-000000000001',
   'f3aaaaaa-0001-0000-0000-000000000010', 'f3aaaaaa-0001-0000-0000-000000000011',
   'Velho', FALSE, now() - INTERVAL '120 days');

-- ============================================================================
-- T01 · Usuario sem subordinados
-- ============================================================================

SELECT test_login('f3aaaaaa-1001-0000-0000-000000000011');  -- SUB1 (colaborador)

DO $$
DECLARE r JSONB;
BEGIN
  r := rpc_my_team_dashboard(FALSE);
  IF (r ->> 'ok')::BOOLEAN <> TRUE THEN
    RAISE EXCEPTION 'T01 FAIL · r=%', r;
  END IF;
  IF jsonb_array_length(r -> 'pdis_overdue') <> 0 THEN
    RAISE EXCEPTION 'T01 FAIL · esperava pdis_overdue vazio';
  END IF;
  RAISE NOTICE 'PASS · T01 · usuario sem subordinados retorna arrays vazios';
END $$;

-- ============================================================================
-- T02 · GERENTE com 2 diretos · estrutura completa
-- ============================================================================

SELECT test_login('f3aaaaaa-1001-0000-0000-000000000010');  -- GERENTE

DO $$
DECLARE r JSONB;
BEGIN
  r := rpc_my_team_dashboard(FALSE);
  IF (r ->> 'ok')::BOOLEAN <> TRUE THEN
    RAISE EXCEPTION 'T02 FAIL · r=%', r;
  END IF;
  IF NOT (r ? 'pdis_overdue' AND r ? 'recognitions_top_recipients' AND r ? 'recognitions_top_senders') THEN
    RAISE EXCEPTION 'T02 FAIL · faltam campos · r=%', r;
  END IF;
  IF (r ->> 'team_size')::INT <> 2 THEN
    RAISE EXCEPTION 'T02 FAIL · team_size esperava 2 · veio %', r ->> 'team_size';
  END IF;
  RAISE NOTICE 'PASS · T02 · payload completo com team_size=2 (diretos)';
END $$;

-- ============================================================================
-- T03 · pdis_overdue · so PDIs ativos com end_date passada
-- ============================================================================

DO $$
DECLARE r JSONB;
DECLARE c INT;
BEGIN
  r := rpc_my_team_dashboard(FALSE);
  c := jsonb_array_length(r -> 'pdis_overdue');
  -- Esperado: 2 PDIs (ambos de SUB1)
  IF c <> 2 THEN
    RAISE EXCEPTION 'T03 FAIL · esperava 2 pdis_overdue (diretos) · veio %', c;
  END IF;
  RAISE NOTICE 'PASS · T03 · pdis_overdue cobre so PDIs ativos vencidos (2 de SUB1)';
END $$;

-- ============================================================================
-- T04 · Ordenacao · PDI mais antigo primeiro
-- ============================================================================

DO $$
DECLARE r JSONB;
DECLARE first_obj TEXT;
BEGIN
  r := rpc_my_team_dashboard(FALSE);
  first_obj := ((r -> 'pdis_overdue') -> 0) ->> 'objective';
  IF first_obj <> 'PDI antigo' THEN
    RAISE EXCEPTION 'T04 FAIL · esperava PDI antigo primeiro · veio %', first_obj;
  END IF;
  RAISE NOTICE 'PASS · T04 · ordenacao end_date ASC (mais antigo primeiro)';
END $$;

-- ============================================================================
-- T05 · Campos days_overdue e progress_pct
-- ============================================================================

DO $$
DECLARE r JSONB;
DECLARE first JSONB;
BEGIN
  r := rpc_my_team_dashboard(FALSE);
  first := (r -> 'pdis_overdue') -> 0;
  IF (first ->> 'days_overdue')::INT < 50 THEN
    RAISE EXCEPTION 'T05 FAIL · days_overdue esperava ~60 · veio %', first ->> 'days_overdue';
  END IF;
  IF (first ->> 'progress_pct')::INT <> 25 THEN
    RAISE EXCEPTION 'T05 FAIL · progress_pct esperava 25 (1/4) · veio %', first ->> 'progress_pct';
  END IF;
  RAISE NOTICE 'PASS · T05 · days_overdue + progress_pct calculados';
END $$;

-- ============================================================================
-- T06 · Top recipients · SUB1 tem mais (3 publicos visiveis)
-- ============================================================================

DO $$
DECLARE r JSONB;
DECLARE top1 JSONB;
BEGIN
  r := rpc_my_team_dashboard(FALSE);
  top1 := (r -> 'recognitions_top_recipients') -> 0;
  IF top1 ->> 'user_name' NOT LIKE '%SUB1%' THEN
    RAISE EXCEPTION 'T06 FAIL · primeiro recipient deveria ser SUB1 · veio %', top1;
  END IF;
  -- SUB1 recebe 4 publicos (3 GERENTE + 1 SUB2) · gerente NAO ve o privado
  IF (top1 ->> 'total')::INT <> 4 THEN
    RAISE EXCEPTION 'T06 FAIL · esperava 4 total (publicos) · veio %', top1 ->> 'total';
  END IF;
  IF (top1 ->> 'private_count')::INT <> 0 THEN
    RAISE EXCEPTION 'T06 FAIL · private_count deveria ser 0 para gerente · veio %', top1 ->> 'private_count';
  END IF;
  RAISE NOTICE 'PASS · T06 · SUB1 lidera recipients (4 publicos), privado filtrado';
END $$;

-- ============================================================================
-- T07 · Top senders · SUB2 enviou 2 publicos visiveis ao gerente
-- ============================================================================

DO $$
DECLARE r JSONB;
DECLARE found_sub2 BOOLEAN := FALSE;
DECLARE item JSONB;
BEGIN
  r := rpc_my_team_dashboard(FALSE);
  -- Reconhecimentos enviados pelo NETO sao 0 (so SUB2 enviou)
  -- mas o segundo dos 2 enviados por SUB2 foi para NETO (nao subordinado direto)
  -- Ambos sao senders subordinados (SUB2 e direto) então aparecem nos top_senders
  FOR item IN SELECT * FROM jsonb_array_elements(r -> 'recognitions_top_senders') LOOP
    IF item ->> 'user_name' LIKE '%SUB2%' THEN
      found_sub2 := TRUE;
      IF (item ->> 'total')::INT <> 3 THEN
        RAISE EXCEPTION 'T07 FAIL · SUB2 esperava 3 enviados · veio %', item ->> 'total';
      END IF;
    END IF;
  END LOOP;
  IF NOT found_sub2 THEN
    RAISE EXCEPTION 'T07 FAIL · SUB2 nao encontrado em senders · veio %', r -> 'recognitions_top_senders';
  END IF;
  RAISE NOTICE 'PASS · T07 · SUB2 aparece com 3 enviados';
END $$;

-- ============================================================================
-- T08 · RH ve o reconhecimento privado
-- ============================================================================

SELECT test_login('f3aaaaaa-1001-0000-0000-000000000001');  -- SA (que tem acesso de admin)

-- Cria um RH no tenant
INSERT INTO app_users (id, tenant_id, auth_user_id, email, full_name, role, manager_id, employment_link, hired_at) VALUES
  ('f3aaaaaa-0001-0000-0000-000000000099', 'f3aaaaaa-0000-0000-0000-000000000001',
   'f3aaaaaa-1001-0000-0000-000000000099', 'rh@f3.test', 'RH-F3', 'rh', NULL, 'clt', '2020-01-01');

-- RH precisa ser gerente de alguem ou ter relacao. Aqui o RH nao tem subordinados,
-- entao o dashboard dele vem vazio. Vamos testar do GERENTE indo embora e
-- voltando com RH como manager:
UPDATE app_users SET manager_id = 'f3aaaaaa-0001-0000-0000-000000000099'
  WHERE id IN ('f3aaaaaa-0001-0000-0000-000000000011', 'f3aaaaaa-0001-0000-0000-000000000012');

SELECT test_login('f3aaaaaa-1001-0000-0000-000000000099');  -- RH

DO $$
DECLARE r JSONB;
DECLARE top1 JSONB;
BEGIN
  r := rpc_my_team_dashboard(FALSE);
  top1 := (r -> 'recognitions_top_recipients') -> 0;
  IF top1 ->> 'user_name' NOT LIKE '%SUB1%' THEN
    RAISE EXCEPTION 'T08 FAIL · SUB1 deveria liderar';
  END IF;
  -- RH ve TODOS · 4 publicos + 1 privado = 5
  IF (top1 ->> 'total')::INT <> 5 THEN
    RAISE EXCEPTION 'T08 FAIL · RH esperava 5 (com privado) · veio %', top1 ->> 'total';
  END IF;
  IF (top1 ->> 'private_count')::INT <> 1 THEN
    RAISE EXCEPTION 'T08 FAIL · private_count para RH esperava 1 · veio %', top1 ->> 'private_count';
  END IF;
  RAISE NOTICE 'PASS · T08 · RH ve total=5 com private_count=1';
END $$;

-- Restaura hierarquia original
UPDATE app_users SET manager_id = 'f3aaaaaa-0001-0000-0000-000000000010'
  WHERE id IN ('f3aaaaaa-0001-0000-0000-000000000011', 'f3aaaaaa-0001-0000-0000-000000000012');

-- ============================================================================
-- T09 · include_indirect engloba NETO
-- ============================================================================

SELECT test_login('f3aaaaaa-1001-0000-0000-000000000010');  -- GERENTE

DO $$
DECLARE r JSONB;
BEGIN
  r := rpc_my_team_dashboard(TRUE);
  IF (r ->> 'team_size')::INT <> 3 THEN
    RAISE EXCEPTION 'T09 FAIL · team_size com indirect esperava 3 · veio %', r ->> 'team_size';
  END IF;
  -- Com NETO entra mais 1 PDI atrasado
  IF jsonb_array_length(r -> 'pdis_overdue') <> 3 THEN
    RAISE EXCEPTION 'T09 FAIL · pdis_overdue com indirect esperava 3 · veio %',
      jsonb_array_length(r -> 'pdis_overdue');
  END IF;
  RAISE NOTICE 'PASS · T09 · include_indirect amplia universo (NETO + PDI dele)';
END $$;

-- ============================================================================
-- T10 · Isolamento entre gestores · OUTRO_GERENTE ve so seu sub
-- ============================================================================

SELECT test_login('f3aaaaaa-1001-0000-0000-000000000020');  -- OUTRO_GERENTE

DO $$
DECLARE r JSONB;
BEGIN
  r := rpc_my_team_dashboard(FALSE);
  IF (r ->> 'team_size')::INT <> 1 THEN
    RAISE EXCEPTION 'T10 FAIL · OUTRO_GERENTE esperava 1 · veio %', r ->> 'team_size';
  END IF;
  -- Nenhum PDI vencido na sua equipe (SUB_OUTRO nao tem)
  IF jsonb_array_length(r -> 'pdis_overdue') <> 0 THEN
    RAISE EXCEPTION 'T10 FAIL · esperava 0 pdis · veio %', jsonb_array_length(r -> 'pdis_overdue');
  END IF;
  RAISE NOTICE 'PASS · T10 · isolamento entre gestores';
END $$;

-- ============================================================================
-- T11 · Reconhecimentos antigos (>90d) filtrados
-- ============================================================================

SELECT test_login('f3aaaaaa-1001-0000-0000-000000000010');  -- GERENTE

DO $$
DECLARE r JSONB;
DECLARE top1 JSONB;
BEGIN
  r := rpc_my_team_dashboard(FALSE);
  top1 := (r -> 'recognitions_top_recipients') -> 0;
  -- SUB1 tem 4 publicos visiveis no periodo (o de 120d foi filtrado)
  IF (top1 ->> 'total')::INT <> 4 THEN
    RAISE EXCEPTION 'T11 FAIL · esperava 4 (publicos 90d) · veio %', top1 ->> 'total';
  END IF;
  RAISE NOTICE 'PASS · T11 · reconhecimentos >90d filtrados';
END $$;

-- ============================================================================
-- T12 · Permissao not_authenticated
-- ============================================================================

DO $$
DECLARE r JSONB;
BEGIN
  -- Loga com auth_user_id que nao existe
  PERFORM set_config('request.jwt.claim.sub', 'ffffffff-9999-0000-0000-000000000000', TRUE);
  r := rpc_my_team_dashboard(FALSE);
  IF r ->> 'error' <> 'not_authenticated' THEN
    RAISE EXCEPTION 'T12 FAIL · esperava not_authenticated · veio %', r;
  END IF;
  RAISE NOTICE 'PASS · T12 · usuario nao autenticado bloqueado';
END $$;

-- ============================================================================
-- FECHAMENTO
-- ============================================================================

DO $$
BEGIN
  RAISE NOTICE '========================================';
  RAISE NOTICE '=== F3 · 12 testes executados · OK   ===';
  RAISE NOTICE '========================================';
END $$;

ROLLBACK;

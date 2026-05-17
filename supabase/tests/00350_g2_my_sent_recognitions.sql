-- ============================================================================
-- R2 People · Testes Sessao G2 · my_sent_recognitions
-- ============================================================================
-- 7 testes:
--   T01 · not_authenticated
--   T02 · sem reconhecimentos enviados retorna lista vazia
--   T03 · enriquecimento com recipient_name + recipient_employee_id
--   T04 · ordenacao DESC por created_at
--   T05 · limit padrao = 10 (cap entre 1-50)
--   T06 · oculta hidden_at
--   T07 · isolamento: nao retorna enviados de outros usuarios
-- ============================================================================

BEGIN;

INSERT INTO tenants (id, slug, legal_name, display_name) VALUES
  ('92aaaaaa-0000-0000-0000-000000000001', 'tx-g2', 'Tenant X G2', 'X');

INSERT INTO app_users (id, tenant_id, auth_user_id, email, full_name, role, manager_id,
                       employment_link, hired_at) VALUES
  ('92aaaaaa-0003-0000-0000-000000000010', '92aaaaaa-0000-0000-0000-000000000001',
   '92aaaaaa-aaa1-0000-0000-000000000010', 'eu@g2.test', 'EU G2', 'colaborador', NULL,
   'clt', '2022-01-01'),
  ('92aaaaaa-0003-0000-0000-000000000011', '92aaaaaa-0000-0000-0000-000000000001',
   '92aaaaaa-aaa1-0000-0000-000000000011', 'a@g2.test', 'COLAB A G2', 'colaborador', NULL,
   'clt', '2022-01-01'),
  ('92aaaaaa-0003-0000-0000-000000000012', '92aaaaaa-0000-0000-0000-000000000001',
   '92aaaaaa-aaa1-0000-0000-000000000012', 'b@g2.test', 'COLAB B G2', 'colaborador', NULL,
   'clt', '2022-01-01'),
  ('92aaaaaa-0003-0000-0000-000000000099', '92aaaaaa-0000-0000-0000-000000000001',
   '92aaaaaa-aaa1-0000-0000-000000000099', 'outro@g2.test', 'OUTRO G2', 'colaborador', NULL,
   'clt', '2022-01-01');

INSERT INTO employees (id, tenant_id, full_name, job_title, hire_date, cpf, created_by) VALUES
  ('92aaaaaa-0004-0000-0000-000000000011', '92aaaaaa-0000-0000-0000-000000000001',
   'COLAB A G2 FICHA', 'Analista', '2022-01-01', '80111111111',
   '92aaaaaa-0003-0000-0000-000000000010');
UPDATE app_users SET employee_id='92aaaaaa-0004-0000-0000-000000000011' WHERE id='92aaaaaa-0003-0000-0000-000000000011';

-- ============================================================================
-- T01 · not_authenticated
-- ============================================================================
DO $$ DECLARE r JSONB;
BEGIN
  PERFORM set_config('request.jwt.claim.sub', 'ffffffff-0000-0000-0000-000000000000', TRUE);
  r := rpc_my_sent_recognitions(10);
  IF r ->> 'error' <> 'not_authenticated' THEN
    RAISE EXCEPTION 'T01 FAIL · %', r;
  END IF;
  RAISE NOTICE 'PASS · T01 · not_authenticated';
END $$;

-- ============================================================================
-- T02 · Lista vazia
-- ============================================================================
SELECT test_login('92aaaaaa-aaa1-0000-0000-000000000010');
DO $$ DECLARE r JSONB;
BEGIN
  r := rpc_my_sent_recognitions();
  IF (r ->> 'ok')::BOOLEAN <> TRUE THEN
    RAISE EXCEPTION 'T02 FAIL · ok=false · %', r;
  END IF;
  IF jsonb_array_length(r -> 'items') <> 0 THEN
    RAISE EXCEPTION 'T02 FAIL · esperava 0 · veio %', jsonb_array_length(r -> 'items');
  END IF;
  RAISE NOTICE 'PASS · T02 · sem reconhecimentos retorna []';
END $$;

-- Insere 3 reconhecimentos enviados pelo EU (created_at distintos)
INSERT INTO recognitions (id, tenant_id, sender_id, recipient_id, message, is_private, created_at) VALUES
  ('92aaaaaa-0009-0000-0000-000000000001', '92aaaaaa-0000-0000-0000-000000000001',
   '92aaaaaa-0003-0000-0000-000000000010', '92aaaaaa-0003-0000-0000-000000000011',
   'Para A · mais recente', FALSE, now() - INTERVAL '1 day'),
  ('92aaaaaa-0009-0000-0000-000000000002', '92aaaaaa-0000-0000-0000-000000000001',
   '92aaaaaa-0003-0000-0000-000000000010', '92aaaaaa-0003-0000-0000-000000000012',
   'Para B · meio', FALSE, now() - INTERVAL '5 days'),
  ('92aaaaaa-0009-0000-0000-000000000003', '92aaaaaa-0000-0000-0000-000000000001',
   '92aaaaaa-0003-0000-0000-000000000010', '92aaaaaa-0003-0000-0000-000000000011',
   'Para A · antigo', TRUE, now() - INTERVAL '10 days'),
  -- Outro user enviando para A (nao deve aparecer no feed do EU)
  ('92aaaaaa-0009-0000-0000-000000000004', '92aaaaaa-0000-0000-0000-000000000001',
   '92aaaaaa-0003-0000-0000-000000000099', '92aaaaaa-0003-0000-0000-000000000011',
   'Do OUTRO', FALSE, now() - INTERVAL '2 days'),
  -- Hidden (nao deve aparecer)
  ('92aaaaaa-0009-0000-0000-000000000005', '92aaaaaa-0000-0000-0000-000000000001',
   '92aaaaaa-0003-0000-0000-000000000010', '92aaaaaa-0003-0000-0000-000000000012',
   'Hidden', FALSE, now() - INTERVAL '3 days');
UPDATE recognitions SET hidden_at = now(), hidden_by='92aaaaaa-0003-0000-0000-000000000010'
WHERE id = '92aaaaaa-0009-0000-0000-000000000005';

-- ============================================================================
-- T03 · Enriquecimento com nome e employee_id
-- ============================================================================
DO $$ DECLARE r JSONB; DECLARE first JSONB;
BEGIN
  r := rpc_my_sent_recognitions();
  first := (r -> 'items') -> 0;
  -- O mais recente foi para A
  IF first ->> 'recipient_name' <> 'COLAB A G2 FICHA' THEN
    RAISE EXCEPTION 'T03 FAIL · esperava nome da ficha A · veio %', first ->> 'recipient_name';
  END IF;
  IF first ->> 'recipient_employee_id' IS NULL THEN
    RAISE EXCEPTION 'T03 FAIL · esperava employee_id preenchido';
  END IF;
  RAISE NOTICE 'PASS · T03 · enriquece com nome da ficha + employee_id';
END $$;

-- ============================================================================
-- T04 · Ordenacao DESC por created_at
-- ============================================================================
DO $$ DECLARE r JSONB;
BEGIN
  r := rpc_my_sent_recognitions();
  IF jsonb_array_length(r -> 'items') <> 3 THEN
    RAISE EXCEPTION 'T04 FAIL · esperava 3 · veio %', jsonb_array_length(r -> 'items');
  END IF;
  IF ((r -> 'items') -> 0) ->> 'message' <> 'Para A · mais recente' THEN
    RAISE EXCEPTION 'T04 FAIL · primeiro deveria ser mais recente · veio %', ((r -> 'items') -> 0) ->> 'message';
  END IF;
  IF ((r -> 'items') -> 2) ->> 'message' <> 'Para A · antigo' THEN
    RAISE EXCEPTION 'T04 FAIL · ultimo deveria ser antigo';
  END IF;
  RAISE NOTICE 'PASS · T04 · ordenacao DESC por created_at';
END $$;

-- ============================================================================
-- T05 · Cap de limit
-- ============================================================================
DO $$ DECLARE r JSONB;
BEGIN
  -- Limit acima do cap (50) vira 50
  r := rpc_my_sent_recognitions(999);
  IF (r ->> 'limit')::INT <> 50 THEN
    RAISE EXCEPTION 'T05 FAIL · cap esperava 50 · veio %', r ->> 'limit';
  END IF;
  -- Limit abaixo de 1 vira 1
  r := rpc_my_sent_recognitions(0);
  IF (r ->> 'limit')::INT <> 1 THEN
    RAISE EXCEPTION 'T05 FAIL · piso esperava 1 · veio %', r ->> 'limit';
  END IF;
  RAISE NOTICE 'PASS · T05 · cap entre 1 e 50';
END $$;

-- ============================================================================
-- T06 · Hidden nao aparece
-- ============================================================================
DO $$ DECLARE r JSONB; DECLARE item JSONB;
BEGIN
  r := rpc_my_sent_recognitions();
  FOR item IN SELECT * FROM jsonb_array_elements(r -> 'items') LOOP
    IF item ->> 'message' = 'Hidden' THEN
      RAISE EXCEPTION 'T06 FAIL · hidden retornou';
    END IF;
  END LOOP;
  RAISE NOTICE 'PASS · T06 · hidden_at filtrado';
END $$;

-- ============================================================================
-- T07 · Isolamento · OUTRO nao ve enviados do EU
-- ============================================================================
SELECT test_login('92aaaaaa-aaa1-0000-0000-000000000099');
DO $$ DECLARE r JSONB;
BEGIN
  r := rpc_my_sent_recognitions();
  -- OUTRO so enviou 1 (para A)
  IF jsonb_array_length(r -> 'items') <> 1 THEN
    RAISE EXCEPTION 'T07 FAIL · OUTRO esperava 1 enviado · veio %', jsonb_array_length(r -> 'items');
  END IF;
  RAISE NOTICE 'PASS · T07 · isolamento por sender_id';
END $$;

DO $$ BEGIN
  RAISE NOTICE '========================================';
  RAISE NOTICE '=== G2 · 7 testes executados · OK    ===';
  RAISE NOTICE '========================================';
END $$;

ROLLBACK;

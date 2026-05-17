-- ============================================================================
-- R2 People · Testes Recognition v1
-- ============================================================================
-- Testes do modulo Recognition · cobrem RPCs, constraints, triggers, RLS,
-- privacidade e moderacao.
--
-- Pre-requisitos: schema base + seed base + schema recognition + seed recognition
-- aplicados.
--
-- Roda em transacao com ROLLBACK no fim · nao deixa lixo.
-- ============================================================================

BEGIN;

-- ============================================================================
-- SETUP · Reaproveita helpers de teste do schema base + cria dados Recognition
-- ============================================================================

-- 1 tenant + 4 usuarios em hierarquia:
-- DIR (diretoria) -> LID (lider) -> COL1 (colaborador), COL2 (colaborador)
-- + RH (rh) standalone

INSERT INTO tenants (id, slug, legal_name, display_name) VALUES
  ('00000000-0000-0000-D000-000000000001', 'recog-test', 'Recognition Test', 'Recog')
ON CONFLICT (id) DO NOTHING;

INSERT INTO employer_units (id, tenant_id, code, legal_name) VALUES
  ('00000000-0000-0000-D001-000000000001', '00000000-0000-0000-D000-000000000001', 'EMP', 'Emp Recog')
ON CONFLICT (id) DO NOTHING;

INSERT INTO working_units (id, tenant_id, employer_unit_id, code, display_name) VALUES
  ('00000000-0000-0000-D002-000000000001', '00000000-0000-0000-D000-000000000001', '00000000-0000-0000-D001-000000000001', 'WU', 'WU Recog')
ON CONFLICT (id) DO NOTHING;

INSERT INTO app_users (
  id, tenant_id, auth_user_id, email, full_name, role,
  employer_unit_id, working_unit_id, manager_id, employment_link, hired_at
) VALUES
  ('00000000-0000-0000-D004-000000000001',
   '00000000-0000-0000-D000-000000000001', '33333333-3333-3333-3333-000000000001',
   'dir@recog-test.com', 'Diretor Recog', 'diretoria',
   '00000000-0000-0000-D001-000000000001', '00000000-0000-0000-D002-000000000001',
   NULL, 'clt', '2020-01-01'),

  ('00000000-0000-0000-D004-000000000002',
   '00000000-0000-0000-D000-000000000001', '33333333-3333-3333-3333-000000000002',
   'rh@recog-test.com', 'RH Recog', 'rh',
   '00000000-0000-0000-D001-000000000001', '00000000-0000-0000-D002-000000000001',
   '00000000-0000-0000-D004-000000000001', 'clt', '2020-01-01'),

  ('00000000-0000-0000-D004-000000000003',
   '00000000-0000-0000-D000-000000000001', '33333333-3333-3333-3333-000000000003',
   'lid@recog-test.com', 'Lider Recog', 'lider',
   '00000000-0000-0000-D001-000000000001', '00000000-0000-0000-D002-000000000001',
   '00000000-0000-0000-D004-000000000001', 'clt', '2020-01-01'),

  ('00000000-0000-0000-D004-000000000004',
   '00000000-0000-0000-D000-000000000001', '33333333-3333-3333-3333-000000000004',
   'col1@recog-test.com', 'Colaborador 1', 'colaborador',
   '00000000-0000-0000-D001-000000000001', '00000000-0000-0000-D002-000000000001',
   '00000000-0000-0000-D004-000000000003', 'clt', '2021-01-01'),

  ('00000000-0000-0000-D004-000000000005',
   '00000000-0000-0000-D000-000000000001', '33333333-3333-3333-3333-000000000005',
   'col2@recog-test.com', 'Colaborador 2', 'colaborador',
   '00000000-0000-0000-D001-000000000001', '00000000-0000-0000-D002-000000000001',
   '00000000-0000-0000-D004-000000000003', 'clt', '2021-06-01')
ON CONFLICT (id) DO NOTHING;

CREATE OR REPLACE FUNCTION test_log(msg TEXT)
RETURNS TEXT AS $$
BEGIN RAISE NOTICE '%', msg; RETURN msg; END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- TESTE 1 · Constraint sender != recipient
-- ============================================================================

SELECT test_log('--- TESTE 1 · Constraint sender != recipient ---');

DO $$ BEGIN
  BEGIN
    INSERT INTO recognitions (tenant_id, sender_id, recipient_id, message)
    VALUES (
      '00000000-0000-0000-D000-000000000001',
      '00000000-0000-0000-D004-000000000004',
      '00000000-0000-0000-D004-000000000004',
      'Reconheco a mim mesmo'
    );
    ASSERT FALSE, 'Self-recognize deveria falhar';
  EXCEPTION WHEN check_violation THEN NULL;
  END;
END $$;

SELECT test_log('OK · sender = recipient bloqueado');

-- ============================================================================
-- TESTE 2 · Mensagem com tamanho minimo e maximo
-- ============================================================================

SELECT test_log('--- TESTE 2 · Mensagem 3-1000 chars ---');

DO $$ BEGIN
  BEGIN
    INSERT INTO recognitions (tenant_id, sender_id, recipient_id, message)
    VALUES (
      '00000000-0000-0000-D000-000000000001',
      '00000000-0000-0000-D004-000000000004',
      '00000000-0000-0000-D004-000000000005',
      'oi'
    );
    ASSERT FALSE, 'Mensagem com 2 chars deveria falhar';
  EXCEPTION WHEN check_violation THEN NULL;
  END;

  BEGIN
    INSERT INTO recognitions (tenant_id, sender_id, recipient_id, message)
    VALUES (
      '00000000-0000-0000-D000-000000000001',
      '00000000-0000-0000-D004-000000000004',
      '00000000-0000-0000-D004-000000000005',
      repeat('a', 1001)
    );
    ASSERT FALSE, 'Mensagem com 1001 chars deveria falhar';
  EXCEPTION WHEN check_violation THEN NULL;
  END;

  -- 3 chars passa
  INSERT INTO recognitions (tenant_id, sender_id, recipient_id, message)
  VALUES (
    '00000000-0000-0000-D000-000000000001',
    '00000000-0000-0000-D004-000000000004',
    '00000000-0000-0000-D004-000000000005',
    'top'
  );
END $$;

SELECT test_log('OK · constraint de tamanho de mensagem');

-- ============================================================================
-- TESTE 3 · UPSERT de reacao (1 reacao por usuario por post)
-- ============================================================================

SELECT test_log('--- TESTE 3 · 1 reacao por usuario por post ---');

DO $$
DECLARE
  v_post UUID;
  v_count INT;
  v_kind recognition_reaction_kind;
BEGIN
  INSERT INTO recognitions (tenant_id, sender_id, recipient_id, message)
  VALUES (
    '00000000-0000-0000-D000-000000000001',
    '00000000-0000-0000-D004-000000000003',
    '00000000-0000-0000-D004-000000000004',
    'Excelente apresentacao no comite'
  )
  RETURNING id INTO v_post;

  -- DIR reage com clap
  INSERT INTO recognition_reactions (tenant_id, recognition_id, user_id, kind)
  VALUES ('00000000-0000-0000-D000-000000000001', v_post, '00000000-0000-0000-D004-000000000001', 'clap');

  -- DIR tenta reagir com heart -> deve dar conflict
  BEGIN
    INSERT INTO recognition_reactions (tenant_id, recognition_id, user_id, kind)
    VALUES ('00000000-0000-0000-D000-000000000001', v_post, '00000000-0000-0000-D004-000000000001', 'heart');
    ASSERT FALSE, '2 reacoes do mesmo user no mesmo post deveria falhar';
  EXCEPTION WHEN unique_violation THEN NULL;
  END;

  -- UPSERT troca o emoji
  INSERT INTO recognition_reactions (tenant_id, recognition_id, user_id, kind)
  VALUES ('00000000-0000-0000-D000-000000000001', v_post, '00000000-0000-0000-D004-000000000001', 'heart')
  ON CONFLICT (recognition_id, user_id) DO UPDATE SET kind = EXCLUDED.kind;

  SELECT count(*) INTO v_count FROM recognition_reactions WHERE recognition_id = v_post;
  ASSERT v_count = 1, format('Esperado 1 reacao apos UPSERT, obtido %s', v_count);

  SELECT kind INTO v_kind FROM recognition_reactions WHERE recognition_id = v_post;
  ASSERT v_kind = 'heart', 'Reacao deveria ter sido trocada para heart';
END $$;

SELECT test_log('OK · UNIQUE (post, user) + UPSERT funcionam');

-- ============================================================================
-- TESTE 4 · Trigger denormaliza reactions_count
-- ============================================================================

SELECT test_log('--- TESTE 4 · reactions_count denormalizado ---');

DO $$
DECLARE
  v_post UUID;
  v_count_in_post INT;
BEGIN
  INSERT INTO recognitions (tenant_id, sender_id, recipient_id, message)
  VALUES (
    '00000000-0000-0000-D000-000000000001',
    '00000000-0000-0000-D004-000000000003',
    '00000000-0000-0000-D004-000000000005',
    'Agilidade no atendimento'
  )
  RETURNING id INTO v_post;

  -- Iniciar count = 0
  SELECT reactions_count INTO v_count_in_post FROM recognitions WHERE id = v_post;
  ASSERT v_count_in_post = 0, 'Inicial deveria ser 0';

  -- 3 usuarios reagem
  INSERT INTO recognition_reactions (tenant_id, recognition_id, user_id, kind) VALUES
    ('00000000-0000-0000-D000-000000000001', v_post, '00000000-0000-0000-D004-000000000001', 'clap'),
    ('00000000-0000-0000-D000-000000000001', v_post, '00000000-0000-0000-D004-000000000002', 'heart'),
    ('00000000-0000-0000-D000-000000000001', v_post, '00000000-0000-0000-D004-000000000004', 'celebrate');

  SELECT reactions_count INTO v_count_in_post FROM recognitions WHERE id = v_post;
  ASSERT v_count_in_post = 3, format('Esperado 3 apos 3 inserts, obtido %s', v_count_in_post);

  -- Remove 1
  DELETE FROM recognition_reactions
  WHERE recognition_id = v_post AND user_id = '00000000-0000-0000-D004-000000000001';

  SELECT reactions_count INTO v_count_in_post FROM recognitions WHERE id = v_post;
  ASSERT v_count_in_post = 2, format('Esperado 2 apos remover 1, obtido %s', v_count_in_post);
END $$;

SELECT test_log('OK · trigger atualiza reactions_count em INSERT/DELETE');

-- ============================================================================
-- TESTE 5 · Trigger denormaliza reports_count
-- ============================================================================

SELECT test_log('--- TESTE 5 · reports_count denormalizado ---');

DO $$
DECLARE
  v_post UUID;
  v_reports INT;
BEGIN
  INSERT INTO recognitions (tenant_id, sender_id, recipient_id, message)
  VALUES (
    '00000000-0000-0000-D000-000000000001',
    '00000000-0000-0000-D004-000000000004',
    '00000000-0000-0000-D004-000000000005',
    'Mensagem que sera denunciada'
  )
  RETURNING id INTO v_post;

  INSERT INTO recognition_reports (tenant_id, recognition_id, reporter_id, reason) VALUES
    ('00000000-0000-0000-D000-000000000001', v_post, '00000000-0000-0000-D004-000000000003', 'Conteudo inapropriado'),
    ('00000000-0000-0000-D000-000000000001', v_post, '00000000-0000-0000-D004-000000000001', 'Linguagem ofensiva');

  SELECT reports_count INTO v_reports FROM recognitions WHERE id = v_post;
  ASSERT v_reports = 2, format('Esperado 2 reports, obtido %s', v_reports);
END $$;

SELECT test_log('OK · trigger atualiza reports_count');

-- ============================================================================
-- TESTE 6 · 1 denuncia por reporter por post (UNIQUE)
-- ============================================================================

SELECT test_log('--- TESTE 6 · UNIQUE (post, reporter) ---');

DO $$
DECLARE
  v_post UUID;
BEGIN
  INSERT INTO recognitions (tenant_id, sender_id, recipient_id, message)
  VALUES (
    '00000000-0000-0000-D000-000000000001',
    '00000000-0000-0000-D004-000000000004',
    '00000000-0000-0000-D004-000000000005',
    'Outra mensagem qualquer'
  )
  RETURNING id INTO v_post;

  INSERT INTO recognition_reports (tenant_id, recognition_id, reporter_id, reason)
  VALUES ('00000000-0000-0000-D000-000000000001', v_post, '00000000-0000-0000-D004-000000000003', 'Razao A');

  BEGIN
    INSERT INTO recognition_reports (tenant_id, recognition_id, reporter_id, reason)
    VALUES ('00000000-0000-0000-D000-000000000001', v_post, '00000000-0000-0000-D004-000000000003', 'Razao B');
    ASSERT FALSE, 'Mesma pessoa denunciar 2x deveria falhar';
  EXCEPTION WHEN unique_violation THEN NULL;
  END;
END $$;

SELECT test_log('OK · 1 denuncia por reporter por post');

-- ============================================================================
-- TESTE 7 · RPC create · sender = recipient retorna erro
-- ============================================================================

SELECT test_log('--- TESTE 7 · RPC create · self-recognize ---');

-- Nota: como nao temos auth real configurada no teste local,
-- as RPCs que dependem de current_user_id() retornam not_authenticated.
-- Para testar a logica das RPCs em si, simulamos via SET LOCAL JWT.

DO $$
DECLARE
  v_result JSONB;
BEGIN
  PERFORM set_config('request.jwt.claim.sub', '33333333-3333-3333-3333-000000000004', TRUE);

  v_result := rpc_recognition_create(
    '00000000-0000-0000-D004-000000000004',  -- mesmo user (sender)
    'Mensagem qualquer'
  );

  ASSERT v_result->>'error' = 'cannot_self_recognize',
    format('Esperado cannot_self_recognize, obtido %s', v_result::TEXT);
END $$;

SELECT test_log('OK · RPC create bloqueia self-recognize');

-- ============================================================================
-- TESTE 8 · RPC create · cross-tenant block
-- ============================================================================

SELECT test_log('--- TESTE 8 · RPC create · cross-tenant block ---');

DO $$
DECLARE
  v_result JSONB;
BEGIN
  -- Cria user em OUTRO tenant
  INSERT INTO tenants (id, slug, legal_name, display_name)
  VALUES ('00000000-0000-0000-E000-000000000001', 'other-test', 'Other', 'Other')
  ON CONFLICT (id) DO NOTHING;

  INSERT INTO app_users (id, tenant_id, auth_user_id, email, full_name, hired_at)
  VALUES (
    '00000000-0000-0000-E004-000000000001',
    '00000000-0000-0000-E000-000000000001',
    '44444444-4444-4444-4444-000000000001',
    'externo@other-test.com', 'Externo Other', '2024-01-01'
  ) ON CONFLICT (id) DO NOTHING;

  -- COL1 (tenant D) tenta reconhecer Externo (tenant E)
  PERFORM set_config('request.jwt.claim.sub', '33333333-3333-3333-3333-000000000004', TRUE);

  v_result := rpc_recognition_create(
    '00000000-0000-0000-E004-000000000001',
    'Mensagem cross-tenant'
  );

  ASSERT v_result->>'error' = 'cross_tenant_blocked',
    format('Esperado cross_tenant_blocked, obtido %s', v_result::TEXT);
END $$;

SELECT test_log('OK · RPC create bloqueia cross-tenant');

-- ============================================================================
-- TESTE 9 · RPC create · happy path
-- ============================================================================

SELECT test_log('--- TESTE 9 · RPC create · happy path ---');

DO $$
DECLARE
  v_result JSONB;
  v_id UUID;
  v_msg TEXT;
BEGIN
  PERFORM set_config('request.jwt.claim.sub', '33333333-3333-3333-3333-000000000004', TRUE);

  v_result := rpc_recognition_create(
    '00000000-0000-0000-D004-000000000005',
    'Excelente trabalho na inauguracao da loja',
    FALSE
  );

  ASSERT v_result->>'ok' = 'true', format('Esperado ok=true, obtido %s', v_result::TEXT);
  v_id := (v_result->>'recognition_id')::UUID;

  SELECT message INTO v_msg FROM recognitions WHERE id = v_id;
  ASSERT v_msg = 'Excelente trabalho na inauguracao da loja', 'Mensagem salva incorreta';
END $$;

SELECT test_log('OK · RPC create cria reconhecimento');

-- ============================================================================
-- TESTE 10 · RPC react · adicionar/trocar/remover
-- ============================================================================

SELECT test_log('--- TESTE 10 · RPC react · CRUD de reacao ---');

DO $$
DECLARE
  v_post UUID;
  v_result JSONB;
  v_count INT;
BEGIN
  INSERT INTO recognitions (tenant_id, sender_id, recipient_id, message)
  VALUES (
    '00000000-0000-0000-D000-000000000001',
    '00000000-0000-0000-D004-000000000003',
    '00000000-0000-0000-D004-000000000004',
    'Lideranca exemplar no projeto'
  )
  RETURNING id INTO v_post;

  -- DIR reage com clap
  PERFORM set_config('request.jwt.claim.sub', '33333333-3333-3333-3333-000000000001', TRUE);

  v_result := rpc_recognition_react(v_post, 'clap');
  ASSERT v_result->>'ok' = 'true', format('Reagir falhou: %s', v_result::TEXT);

  -- Troca para heart
  v_result := rpc_recognition_react(v_post, 'heart');
  ASSERT v_result->>'kind' = 'heart', 'Trocar reacao falhou';

  SELECT count(*) INTO v_count FROM recognition_reactions WHERE recognition_id = v_post;
  ASSERT v_count = 1, format('Apos troca deveria ter 1 reacao, obtido %s', v_count);

  -- Remove
  v_result := rpc_recognition_react(v_post, NULL);
  ASSERT v_result->>'action' = 'removed', 'Remover reacao falhou';

  SELECT count(*) INTO v_count FROM recognition_reactions WHERE recognition_id = v_post;
  ASSERT v_count = 0, format('Apos remover deveria ter 0 reacoes, obtido %s', v_count);
END $$;

SELECT test_log('OK · RPC react · adicionar/trocar/remover');

-- ============================================================================
-- TESTE 11 · RPC report · 1 denuncia por reporter
-- ============================================================================

SELECT test_log('--- TESTE 11 · RPC report ---');

DO $$
DECLARE
  v_post UUID;
  v_result JSONB;
BEGIN
  INSERT INTO recognitions (tenant_id, sender_id, recipient_id, message)
  VALUES (
    '00000000-0000-0000-D000-000000000001',
    '00000000-0000-0000-D004-000000000004',
    '00000000-0000-0000-D004-000000000005',
    'Post a ser denunciado'
  )
  RETURNING id INTO v_post;

  PERFORM set_config('request.jwt.claim.sub', '33333333-3333-3333-3333-000000000003', TRUE);

  v_result := rpc_recognition_report(v_post, 'Conteudo inapropriado');
  ASSERT v_result->>'ok' = 'true', format('Report falhou: %s', v_result::TEXT);

  -- Tentar denunciar de novo
  v_result := rpc_recognition_report(v_post, 'Outra razao');
  ASSERT v_result->>'error' = 'already_reported', 'Deveria bloquear duplicata';

  -- Razao muito curta
  PERFORM set_config('request.jwt.claim.sub', '33333333-3333-3333-3333-000000000005', TRUE);
  v_result := rpc_recognition_report(v_post, 'a');
  ASSERT v_result->>'error' = 'reason_too_short', 'Razao curta deveria falhar';
END $$;

SELECT test_log('OK · RPC report');

-- ============================================================================
-- TESTE 12 · RPC resolve_report · so RH/Diretoria · acao hide oculta o post
-- ============================================================================

SELECT test_log('--- TESTE 12 · RPC resolve_report ---');

DO $$
DECLARE
  v_post UUID;
  v_report UUID;
  v_result JSONB;
  v_hidden TIMESTAMPTZ;
  v_status recognition_report_status;
BEGIN
  INSERT INTO recognitions (tenant_id, sender_id, recipient_id, message)
  VALUES (
    '00000000-0000-0000-D000-000000000001',
    '00000000-0000-0000-D004-000000000004',
    '00000000-0000-0000-D004-000000000005',
    'Post problematico para moderar'
  )
  RETURNING id INTO v_post;

  INSERT INTO recognition_reports (tenant_id, recognition_id, reporter_id, reason)
  VALUES ('00000000-0000-0000-D000-000000000001', v_post, '00000000-0000-0000-D004-000000000003', 'Inapropriado')
  RETURNING id INTO v_report;

  -- COL1 (colaborador) tenta resolver -> deve dar permission_denied
  PERFORM set_config('request.jwt.claim.sub', '33333333-3333-3333-3333-000000000004', TRUE);
  v_result := rpc_recognition_resolve_report(v_report, 'hide');
  ASSERT v_result->>'error' = 'permission_denied', format('Colaborador deveria ser bloqueado, obtido %s', v_result::TEXT);

  -- RH resolve com hide
  PERFORM set_config('request.jwt.claim.sub', '33333333-3333-3333-3333-000000000002', TRUE);
  v_result := rpc_recognition_resolve_report(v_report, 'hide', 'Linguagem inadequada confirmada');
  ASSERT v_result->>'ok' = 'true', format('RH deveria poder resolver, obtido %s', v_result::TEXT);

  -- Post foi marcado como hidden
  SELECT hidden_at INTO v_hidden FROM recognitions WHERE id = v_post;
  ASSERT v_hidden IS NOT NULL, 'Post deveria ter hidden_at preenchido';

  -- Status do report
  SELECT status INTO v_status FROM recognition_reports WHERE id = v_report;
  ASSERT v_status = 'resolved_hidden', format('Status deveria ser resolved_hidden, obtido %s', v_status);
END $$;

SELECT test_log('OK · RPC resolve_report respeita permissao + oculta post');

-- ============================================================================
-- TESTE 13 · RPC get_feed · respeita privacidade
-- ============================================================================

SELECT test_log('--- TESTE 13 · RPC get_feed · privacidade ---');

DO $$
DECLARE
  v_post UUID;
  v_result JSONB;
  v_items JSONB;
  v_count INT;
BEGIN
  -- LID cria post privado para COL1
  INSERT INTO recognitions (tenant_id, sender_id, recipient_id, message, is_private)
  VALUES (
    '00000000-0000-0000-D000-000000000001',
    '00000000-0000-0000-D004-000000000003',
    '00000000-0000-0000-D004-000000000004',
    'Feedback particular sobre desempenho',
    TRUE
  )
  RETURNING id INTO v_post;

  -- COL2 tenta ver feed · post privado nao deve aparecer
  PERFORM set_config('request.jwt.claim.sub', '33333333-3333-3333-3333-000000000005', TRUE);
  v_result := rpc_recognition_get_feed(50);
  v_items := v_result->'items';

  SELECT count(*) INTO v_count
  FROM jsonb_array_elements(v_items) item
  WHERE (item->>'id')::UUID = v_post;

  ASSERT v_count = 0, format('COL2 nao deveria ver post privado, mas viu %s vezes', v_count);

  -- COL1 (recipient) ve seu proprio post privado
  PERFORM set_config('request.jwt.claim.sub', '33333333-3333-3333-3333-000000000004', TRUE);
  v_result := rpc_recognition_get_feed(50);
  v_items := v_result->'items';

  SELECT count(*) INTO v_count
  FROM jsonb_array_elements(v_items) item
  WHERE (item->>'id')::UUID = v_post;

  ASSERT v_count = 1, format('COL1 (recipient) deveria ver seu post privado, viu %s', v_count);

  -- LID (manager do recipient) tambem ve
  PERFORM set_config('request.jwt.claim.sub', '33333333-3333-3333-3333-000000000003', TRUE);
  v_result := rpc_recognition_get_feed(50);
  v_items := v_result->'items';

  SELECT count(*) INTO v_count
  FROM jsonb_array_elements(v_items) item
  WHERE (item->>'id')::UUID = v_post;

  ASSERT v_count = 1, format('LID (manager) deveria ver post privado, viu %s', v_count);

  -- DIR (manager indireto) tambem ve
  PERFORM set_config('request.jwt.claim.sub', '33333333-3333-3333-3333-000000000001', TRUE);
  v_result := rpc_recognition_get_feed(50);
  v_items := v_result->'items';

  SELECT count(*) INTO v_count
  FROM jsonb_array_elements(v_items) item
  WHERE (item->>'id')::UUID = v_post;

  ASSERT v_count = 1, format('DIR (diretoria) deveria ver, viu %s', v_count);

  -- RH tambem ve
  PERFORM set_config('request.jwt.claim.sub', '33333333-3333-3333-3333-000000000002', TRUE);
  v_result := rpc_recognition_get_feed(50);
  v_items := v_result->'items';

  SELECT count(*) INTO v_count
  FROM jsonb_array_elements(v_items) item
  WHERE (item->>'id')::UUID = v_post;

  ASSERT v_count = 1, format('RH deveria ver, viu %s', v_count);
END $$;

SELECT test_log('OK · feed filtra privados corretamente por papel');

-- ============================================================================
-- TESTE 14 · RPC get_feed · hidden posts nao aparecem (exceto para RH/Dir)
-- ============================================================================

SELECT test_log('--- TESTE 14 · feed nao mostra hidden ---');

DO $$
DECLARE
  v_post UUID;
  v_result JSONB;
  v_items JSONB;
  v_count INT;
BEGIN
  INSERT INTO recognitions (tenant_id, sender_id, recipient_id, message, hidden_at, hidden_by, hidden_reason)
  VALUES (
    '00000000-0000-0000-D000-000000000001',
    '00000000-0000-0000-D004-000000000004',
    '00000000-0000-0000-D004-000000000005',
    'Post oculto pela moderacao',
    now(),
    '00000000-0000-0000-D004-000000000002',
    'moderado'
  )
  RETURNING id INTO v_post;

  -- COL1 nao ve hidden
  PERFORM set_config('request.jwt.claim.sub', '33333333-3333-3333-3333-000000000004', TRUE);
  v_result := rpc_recognition_get_feed(50);
  v_items := v_result->'items';

  SELECT count(*) INTO v_count
  FROM jsonb_array_elements(v_items) item
  WHERE (item->>'id')::UUID = v_post;

  ASSERT v_count = 0, format('Hidden nao deveria aparecer no feed, viu %s', v_count);
END $$;

SELECT test_log('OK · hidden posts ocultos no feed');

-- ============================================================================
-- TESTE 15 · RPC get_stats · KPIs corretos
-- ============================================================================

SELECT test_log('--- TESTE 15 · RPC get_stats ---');

DO $$
DECLARE
  v_result JSONB;
  v_my_received INT;
BEGIN
  -- COL1 ja recebeu varios posts nos testes anteriores
  PERFORM set_config('request.jwt.claim.sub', '33333333-3333-3333-3333-000000000004', TRUE);

  v_result := rpc_recognition_get_stats(30);
  ASSERT v_result->>'ok' = 'true', format('Stats falhou: %s', v_result::TEXT);

  -- Conferir presenca de campos esperados
  ASSERT v_result ? 'my_sent', 'Faltou my_sent';
  ASSERT v_result ? 'my_received', 'Faltou my_received';
  ASSERT v_result ? 'total_period', 'Faltou total_period';
  ASSERT v_result ? 'active_users', 'Faltou active_users';
  ASSERT v_result ? 'top_recipients', 'Faltou top_recipients';
  ASSERT v_result ? 'participation_rate', 'Faltou participation_rate';

  -- COL1 recebeu pelo menos 1 (do TESTE 9)
  v_my_received := (v_result->>'my_received')::INT;
  ASSERT v_my_received >= 1, format('COL1 deveria ter recebido pelo menos 1, obtido %s', v_my_received);
END $$;

SELECT test_log('OK · stats retorna KPIs com estrutura esperada');

-- ============================================================================
-- TESTE 16 · Permissoes do seed Recognition aplicadas
-- ============================================================================

SELECT test_log('--- TESTE 16 · Permissoes Recognition no catalogo ---');

DO $$
DECLARE
  v INT;
BEGIN
  SELECT count(*) INTO v FROM permissions WHERE module = 'recognition' AND active;
  ASSERT v = 5, format('Esperado 5 perms recognition, obtido %s', v);

  -- Colaborador tem 4 perms
  SELECT count(*) INTO v FROM role_permissions rp
  JOIN permissions p ON p.code = rp.permission_code
  WHERE rp.role = 'colaborador' AND p.module = 'recognition';
  ASSERT v = 4, format('Colaborador deveria ter 4 perms recognition, obtido %s', v);

  -- Diretoria tem 5
  SELECT count(*) INTO v FROM role_permissions rp
  JOIN permissions p ON p.code = rp.permission_code
  WHERE rp.role = 'diretoria' AND p.module = 'recognition';
  ASSERT v = 5, format('Diretoria deveria ter 5 perms recognition, obtido %s', v);

  -- Lider NAO tem manage_recognition_reports
  SELECT count(*) INTO v FROM role_permissions
  WHERE role = 'lider' AND permission_code = 'manage_recognition_reports';
  ASSERT v = 0, 'Lider NAO deveria ter manage_recognition_reports';
END $$;

SELECT test_log('OK · permissoes Recognition no catalogo bate');

-- ============================================================================
-- TESTE 17 · CASCADE quando user e deletado · reactions cascateiam
-- ============================================================================

SELECT test_log('--- TESTE 17 · CASCADE de user para reactions ---');

DO $$
DECLARE
  v_post UUID;
  v_user UUID;
  v_count INT;
BEGIN
  -- Cria user temporario
  INSERT INTO app_users (id, tenant_id, email, full_name, hired_at)
  VALUES ('00000000-0000-0000-D004-000000000099',
          '00000000-0000-0000-D000-000000000001',
          'temp-cascade@recog-test.com', 'Temp Cascade', '2024-01-01')
  RETURNING id INTO v_user;

  INSERT INTO recognitions (tenant_id, sender_id, recipient_id, message)
  VALUES (
    '00000000-0000-0000-D000-000000000001',
    '00000000-0000-0000-D004-000000000004',
    '00000000-0000-0000-D004-000000000005',
    'Post para cascade test'
  )
  RETURNING id INTO v_post;

  -- User reage
  INSERT INTO recognition_reactions (tenant_id, recognition_id, user_id, kind)
  VALUES ('00000000-0000-0000-D000-000000000001', v_post, v_user, 'star');

  -- Delete user
  DELETE FROM app_users WHERE id = v_user;

  -- Reacao deve ter cascateado
  SELECT count(*) INTO v_count FROM recognition_reactions
  WHERE user_id = v_user;
  ASSERT v_count = 0, 'Reacoes deveriam ter cascateado';
END $$;

SELECT test_log('OK · CASCADE de user remove reactions');

-- ============================================================================
-- TESTE 18 · Idempotencia do seed
-- ============================================================================

SELECT test_log('--- TESTE 18 · Idempotencia do seed Recognition ---');

DO $$
DECLARE
  v_before INT;
  v_after INT;
BEGIN
  SELECT count(*) INTO v_before FROM permissions;

  -- Re-aplicar seed (simulado · so re-INSERT com ON CONFLICT)
  INSERT INTO permissions (code, description, scope, module) VALUES
    ('view_recognitions_public', 'X', 'tenant', 'recognition'),
    ('create_recognition', 'X', 'tenant', 'recognition')
  ON CONFLICT (code) DO UPDATE SET description = EXCLUDED.description;

  SELECT count(*) INTO v_after FROM permissions;
  ASSERT v_before = v_after, format('Re-aplicar seed nao deveria duplicar (antes %s, depois %s)', v_before, v_after);
END $$;

SELECT test_log('OK · seed e idempotente');

-- ============================================================================
-- FINAL
-- ============================================================================

SELECT test_log('=== TODOS OS TESTES PASSARAM ===');

ROLLBACK;

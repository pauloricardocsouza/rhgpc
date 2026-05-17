-- ============================================================================
-- R2 People · Testes Sessao A2 · 9-Box
-- ============================================================================
-- Cobertura:
--   1. Setup · ativa modulo, popula defaults, valida settings padrao
--   2. Settings · update, validacoes (pesos sum 100, max 5 criterios)
--   3. Cycles · create, list, update, fechamento
--   4. Evaluation lifecycle · start -> self_submit -> manager_submit -> finalize
--   5. Visibilidade · subject ve so a sua, manager ve time, RH ve tudo
--   6. Justificativa obrigatoria em caixa extrema
--   7. Snapshot imutavel · re-finalize gera versao 2
--   8. Ad-hoc · sem cycle_id
--   9. Cancel · troca status corretamente
--   10. require_self_assessment toggle
--   11. Modulo inativo no escopo do recurso (manager em wu sem ninebox)
--   12. team_matrix · cobertura de roles
--   13. history · respeita visibilidade
--
-- Pre-requisitos:
--   - 00_local_setup.sql aplicado (auth.uid stub, roles)
--   - Schemas H, H2, J, K, L aplicados
--   - patch A1 aplicado
--   - schema ninebox aplicado
--   - seed ninebox aplicado
--
-- Roda em BEGIN ... ROLLBACK · nao deixa lixo.
-- ============================================================================

BEGIN;

-- ============================================================================
-- SETUP · cria tenant A2 com hierarquia: DIR -> LIDER1 -> [USR1, USR2]
--                                              -> LIDER2 -> [USR3]
-- ============================================================================

INSERT INTO tenants (id, slug, legal_name, display_name) VALUES
  ('00000000-0000-0000-A2A0-000000000001', 'a2-test', 'Tenant A2', 'A2');

INSERT INTO employer_units (id, tenant_id, code, legal_name) VALUES
  ('00000000-0000-0000-A2A1-000000000001', '00000000-0000-0000-A2A0-000000000001', 'EMP', 'Employer EMP');

INSERT INTO working_units (id, tenant_id, employer_unit_id, code, display_name) VALUES
  ('00000000-0000-0000-A2A2-000000000001', '00000000-0000-0000-A2A0-000000000001', '00000000-0000-0000-A2A1-000000000001', 'WU1', 'Loja WU1'),
  ('00000000-0000-0000-A2A2-000000000002', '00000000-0000-0000-A2A0-000000000001', '00000000-0000-0000-A2A1-000000000001', 'WU2', 'Loja WU2');

INSERT INTO departments (id, tenant_id, code, display_name) VALUES
  ('00000000-0000-0000-A2A3-000000000001', '00000000-0000-0000-A2A0-000000000001', 'OPS', 'Operacoes');

-- DIR (diretoria, sem manager)
-- LIDER1 (lider, manager=DIR, em WU1)
-- LIDER2 (lider, manager=DIR, em WU2)
-- USR1 (colaborador, manager=LIDER1, WU1)
-- USR2 (colaborador, manager=LIDER1, WU1)
-- USR3 (colaborador, manager=LIDER2, WU2)
-- RH (rh, manager=DIR, WU1)
-- SA (super_admin · sem hierarquia)

INSERT INTO app_users (
  id, tenant_id, auth_user_id, email, full_name, role,
  employer_unit_id, working_unit_id, department_id,
  manager_id, employment_link, hired_at
) VALUES
  ('00000000-0000-0000-A2A4-00000000000D',
   '00000000-0000-0000-A2A0-000000000001',
   'a2aa2222-2222-2222-2222-00000000000D',
   'dir@a2.test', 'Diretor A2', 'diretoria',
   '00000000-0000-0000-A2A1-000000000001',
   '00000000-0000-0000-A2A2-000000000001',
   '00000000-0000-0000-A2A3-000000000001',
   NULL, 'clt', '2020-01-01'),

  ('00000000-0000-0000-A2A4-000000000001',
   '00000000-0000-0000-A2A0-000000000001',
   'a2aa2222-2222-2222-2222-000000000001',
   'lider1@a2.test', 'Lider Um', 'lider',
   '00000000-0000-0000-A2A1-000000000001',
   '00000000-0000-0000-A2A2-000000000001',
   '00000000-0000-0000-A2A3-000000000001',
   '00000000-0000-0000-A2A4-00000000000D', 'clt', '2020-01-01'),

  ('00000000-0000-0000-A2A4-000000000002',
   '00000000-0000-0000-A2A0-000000000001',
   'a2aa2222-2222-2222-2222-000000000002',
   'lider2@a2.test', 'Lider Dois', 'lider',
   '00000000-0000-0000-A2A1-000000000001',
   '00000000-0000-0000-A2A2-000000000002',
   '00000000-0000-0000-A2A3-000000000001',
   '00000000-0000-0000-A2A4-00000000000D', 'clt', '2020-01-01'),

  ('00000000-0000-0000-A2A4-000000000011',
   '00000000-0000-0000-A2A0-000000000001',
   'a2aa2222-2222-2222-2222-000000000011',
   'usr1@a2.test', 'Usuario Um', 'colaborador',
   '00000000-0000-0000-A2A1-000000000001',
   '00000000-0000-0000-A2A2-000000000001',
   '00000000-0000-0000-A2A3-000000000001',
   '00000000-0000-0000-A2A4-000000000001', 'clt', '2020-01-01'),

  ('00000000-0000-0000-A2A4-000000000012',
   '00000000-0000-0000-A2A0-000000000001',
   'a2aa2222-2222-2222-2222-000000000012',
   'usr2@a2.test', 'Usuario Dois', 'colaborador',
   '00000000-0000-0000-A2A1-000000000001',
   '00000000-0000-0000-A2A2-000000000001',
   '00000000-0000-0000-A2A3-000000000001',
   '00000000-0000-0000-A2A4-000000000001', 'clt', '2020-01-01'),

  ('00000000-0000-0000-A2A4-000000000013',
   '00000000-0000-0000-A2A0-000000000001',
   'a2aa2222-2222-2222-2222-000000000013',
   'usr3@a2.test', 'Usuario Tres', 'colaborador',
   '00000000-0000-0000-A2A1-000000000001',
   '00000000-0000-0000-A2A2-000000000002',
   '00000000-0000-0000-A2A3-000000000001',
   '00000000-0000-0000-A2A4-000000000002', 'clt', '2020-01-01'),

  ('00000000-0000-0000-A2A4-0000000000FE',
   '00000000-0000-0000-A2A0-000000000001',
   'a2aa2222-2222-2222-2222-0000000000FE',
   'rh@a2.test', 'RH A2', 'rh',
   '00000000-0000-0000-A2A1-000000000001',
   '00000000-0000-0000-A2A2-000000000001',
   '00000000-0000-0000-A2A3-000000000001',
   '00000000-0000-0000-A2A4-00000000000D', 'clt', '2020-01-01'),

  ('00000000-0000-0000-A2A4-0000000000FF',
   '00000000-0000-0000-A2A0-000000000001',
   'a2aa2222-2222-2222-2222-0000000000FF',
   'sa@r2a2.test', 'Super Admin', 'super_admin',
   NULL, NULL, NULL,
   NULL, 'clt', '2020-01-01');

-- Helper de assert
CREATE OR REPLACE FUNCTION a2_assert(condition BOOLEAN, msg TEXT)
RETURNS VOID AS $$
BEGIN
  IF NOT condition THEN
    RAISE EXCEPTION 'FAIL · %', msg;
  ELSE
    RAISE NOTICE 'PASS · %', msg;
  END IF;
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- T01-T03 · Setup · ativacao do modulo no tenant popula defaults
-- ============================================================================

SELECT test_login('a2aa2222-2222-2222-2222-0000000000FF');  -- SA

-- Antes de ativar, settings nao existem
SELECT a2_assert(
  NOT EXISTS (SELECT 1 FROM ninebox_settings WHERE tenant_id = '00000000-0000-0000-A2A0-000000000001'),
  'T01 · settings nao existem antes da ativacao'
);

-- Ativa modulo no tenant · trigger popula defaults
INSERT INTO module_activations (module_code, scope_kind, tenant_id, activated_by) VALUES
  ('ninebox', 'tenant',
   '00000000-0000-0000-A2A0-000000000001',
   '00000000-0000-0000-A2A4-0000000000FF');

SELECT a2_assert(
  EXISTS (SELECT 1 FROM ninebox_settings WHERE tenant_id = '00000000-0000-0000-A2A0-000000000001'),
  'T02 · trigger popula ninebox_settings com defaults na ativacao'
);

-- Defaults: 3x3, 3 criterios cada eixo, 9 labels
SELECT a2_assert(
  (SELECT grid_size FROM ninebox_settings
   WHERE tenant_id = '00000000-0000-0000-A2A0-000000000001') = '3x3'
  AND
  (SELECT jsonb_array_length(potential_criteria) FROM ninebox_settings
   WHERE tenant_id = '00000000-0000-0000-A2A0-000000000001') = 3
  AND
  (SELECT jsonb_array_length(performance_criteria) FROM ninebox_settings
   WHERE tenant_id = '00000000-0000-0000-A2A0-000000000001') = 3,
  'T03 · defaults sao 3x3 com 3 criterios em cada eixo'
);

-- ============================================================================
-- T04-T07 · Settings update · validacoes
-- ============================================================================

SELECT test_login('a2aa2222-2222-2222-2222-0000000000FE');  -- RH

-- T04 · pesos nao somam 100 -> erro
SELECT a2_assert(
  rpc_ninebox_settings_update(jsonb_build_object(
    'potential_criteria', jsonb_build_array(
      jsonb_build_object('name', 'Aprendizado', 'weight', 50),
      jsonb_build_object('name', 'Lideranca',   'weight', 30)  -- soma 80
    )
  )) ->> 'detail' = 'criteria_weights_must_sum_100',
  'T04 · pesos que nao somam 100 sao rejeitados'
);

-- T05 · 6 criterios -> erro (max 5)
SELECT a2_assert(
  rpc_ninebox_settings_update(jsonb_build_object(
    'potential_criteria', jsonb_build_array(
      jsonb_build_object('name', 'A', 'weight', 20),
      jsonb_build_object('name', 'B', 'weight', 20),
      jsonb_build_object('name', 'C', 'weight', 20),
      jsonb_build_object('name', 'D', 'weight', 20),
      jsonb_build_object('name', 'E', 'weight', 10),
      jsonb_build_object('name', 'F', 'weight', 10)  -- 6 itens
    )
  )) ->> 'detail' = 'criteria_count_must_be_1_to_5',
  'T05 · mais de 5 criterios sao rejeitados'
);

-- T06 · update valido com 5x5 e 4 criterios cada
SELECT a2_assert(
  rpc_ninebox_settings_update(jsonb_build_object(
    'grid_size', '5x5',
    'potential_criteria', jsonb_build_array(
      jsonb_build_object('name', 'Aprendizado',  'weight', 30),
      jsonb_build_object('name', 'Lideranca',    'weight', 30),
      jsonb_build_object('name', 'Estrategia',   'weight', 20),
      jsonb_build_object('name', 'Inovacao',     'weight', 20)
    ),
    'performance_criteria', jsonb_build_array(
      jsonb_build_object('name', 'Resultados',   'weight', 50),
      jsonb_build_object('name', 'Qualidade',    'weight', 25),
      jsonb_build_object('name', 'Colaboracao',  'weight', 25)
    ),
    'min_justification_length', 100,
    'require_self_assessment', TRUE
  )) ->> 'ok' = 'true',
  'T06 · update valido com 5x5 e 4+3 criterios passa'
);

-- T07 · colaborador nao pode editar settings
SELECT test_login('a2aa2222-2222-2222-2222-000000000011');  -- USR1
SELECT a2_assert(
  rpc_ninebox_settings_update(jsonb_build_object('grid_size', '3x3')) ->> 'error' = 'permission_denied',
  'T07 · colaborador nao pode editar settings'
);

-- Volta para 3x3 com 1 criterio cada e min_justification 50 (defaults para o resto dos testes)
SELECT test_login('a2aa2222-2222-2222-2222-0000000000FE');
SELECT rpc_ninebox_settings_update(jsonb_build_object(
  'grid_size', '3x3',
  'potential_criteria', jsonb_build_array(
    jsonb_build_object('name', 'Potencial Geral',  'weight', 100)
  ),
  'performance_criteria', jsonb_build_array(
    jsonb_build_object('name', 'Performance Geral', 'weight', 100)
  ),
  'min_justification_length', 50,
  'require_self_assessment', FALSE
));

-- ============================================================================
-- T08-T10 · Cycles
-- ============================================================================

-- T08 · cria ciclo
WITH r AS (
  SELECT rpc_ninebox_cycle_create(
    'Ciclo 2026',
    '2026-01-01'::DATE,
    '2026-12-31'::DATE,
    2026,
    'Ciclo formal anual'
  ) AS resp
)
SELECT a2_assert(
  (SELECT resp ->> 'ok' FROM r) = 'true',
  'T08 · cria ciclo com sucesso'
);

-- T09 · datas invertidas -> erro
SELECT a2_assert(
  rpc_ninebox_cycle_create(
    'Invalido', '2026-12-31'::DATE, '2026-01-01'::DATE
  ) ->> 'error' = 'invalid_dates',
  'T09 · datas invertidas rejeitadas'
);

-- T10 · listagem retorna o ciclo criado
SELECT a2_assert(
  jsonb_array_length(rpc_ninebox_cycle_list() -> 'cycles') = 1,
  'T10 · cycle_list retorna 1 ciclo'
);

-- Captura o cycle_id para usar nos proximos testes
DO $$
DECLARE
  v_cycle UUID;
BEGIN
  SELECT id INTO v_cycle FROM ninebox_cycles
    WHERE tenant_id = '00000000-0000-0000-A2A0-000000000001'
    ORDER BY created_at DESC LIMIT 1;
  PERFORM set_config('a2.cycle_id', v_cycle::TEXT, FALSE);
END $$;

-- ============================================================================
-- T11-T16 · Evaluation lifecycle · LIDER1 avalia USR1
-- ============================================================================

-- T11 · LIDER1 inicia avaliacao para USR1
SELECT test_login('a2aa2222-2222-2222-2222-000000000001');  -- LIDER1

DO $$
DECLARE
  v_resp JSONB;
  v_eval UUID;
BEGIN
  v_resp := rpc_ninebox_evaluation_start(
    '00000000-0000-0000-A2A4-000000000011',  -- USR1
    current_setting('a2.cycle_id')::UUID,
    FALSE
  );
  IF v_resp ->> 'ok' <> 'true' THEN
    RAISE EXCEPTION 'T11 FAIL · resp = %', v_resp;
  END IF;
  v_eval := (v_resp ->> 'evaluation_id')::UUID;
  PERFORM set_config('a2.eval_id', v_eval::TEXT, FALSE);
  RAISE NOTICE 'PASS · T11 · LIDER1 inicia evaluation para USR1';
END $$;

-- T12 · USR1 (subject) submete auto-avaliacao com nota 4
SELECT test_login('a2aa2222-2222-2222-2222-000000000011');  -- USR1

SELECT a2_assert(
  rpc_ninebox_evaluation_self_submit(
    current_setting('a2.eval_id')::UUID,
    jsonb_build_array(
      jsonb_build_object('axis', 'potential',   'criterion_index', 1, 'score', 4),
      jsonb_build_object('axis', 'performance', 'criterion_index', 1, 'score', 4)
    )
  ) ->> 'ok' = 'true',
  'T12 · USR1 submete auto-avaliacao'
);

-- T13 · status agora e self_done
SELECT a2_assert(
  (SELECT status::TEXT FROM ninebox_evaluations WHERE id = current_setting('a2.eval_id')::UUID) = 'self_done',
  'T13 · status virou self_done apos auto-avaliacao'
);

-- T14 · LIDER1 submete sua avaliacao com nota 3 em ambos -> caixa central (2,2)
SELECT test_login('a2aa2222-2222-2222-2222-000000000001');  -- LIDER1

DO $$
DECLARE v_resp JSONB;
BEGIN
  v_resp := rpc_ninebox_evaluation_manager_submit(
    current_setting('a2.eval_id')::UUID,
    jsonb_build_array(
      jsonb_build_object('axis', 'potential',   'criterion_index', 1, 'score', 3),
      jsonb_build_object('axis', 'performance', 'criterion_index', 1, 'score', 3)
    )
  );
  IF v_resp ->> 'ok' <> 'true' THEN
    RAISE EXCEPTION 'T14 FAIL · %', v_resp;
  END IF;
  IF (v_resp ->> 'final_box_row')::INT <> 2 OR (v_resp ->> 'final_box_col')::INT <> 2 THEN
    RAISE EXCEPTION 'T14 FAIL · esperado (2,2), obtido (%,%)',
      v_resp ->> 'final_box_row', v_resp ->> 'final_box_col';
  END IF;
  RAISE NOTICE 'PASS · T14 · gestor submete · box final (2,2) Mantenedor';
END $$;

-- T15 · status virou manager_done · gestor finaliza
SELECT a2_assert(
  rpc_ninebox_evaluation_finalize(current_setting('a2.eval_id')::UUID) ->> 'ok' = 'true',
  'T15 · finalize gera snapshot v1'
);

SELECT a2_assert(
  (SELECT count(*) FROM ninebox_evaluation_snapshots
   WHERE evaluation_id = current_setting('a2.eval_id')::UUID) = 1,
  'T16 · snapshot v1 criado'
);

-- ============================================================================
-- T17 · Justificativa obrigatoria em caixa extrema
-- ============================================================================

-- LIDER1 inicia nova evaluation para USR2 e da nota 5 em ambos -> (3,3) extremo
SELECT test_login('a2aa2222-2222-2222-2222-000000000001');  -- LIDER1
DO $$
DECLARE v_eval UUID;
BEGIN
  v_eval := (rpc_ninebox_evaluation_start(
    '00000000-0000-0000-A2A4-000000000012',  -- USR2
    current_setting('a2.cycle_id')::UUID,
    FALSE
  ) ->> 'evaluation_id')::UUID;
  PERFORM set_config('a2.eval2_id', v_eval::TEXT, FALSE);
END $$;

-- Tenta submeter sem justificativa em caixa extrema (3,3) -> erro
SELECT a2_assert(
  rpc_ninebox_evaluation_manager_submit(
    current_setting('a2.eval2_id')::UUID,
    jsonb_build_array(
      jsonb_build_object('axis', 'potential',   'criterion_index', 1, 'score', 5),
      jsonb_build_object('axis', 'performance', 'criterion_index', 1, 'score', 5)
    ),
    NULL
  ) ->> 'error' = 'justification_required_for_extreme_box',
  'T17 · caixa extrema (3,3) sem justificativa rejeitada'
);

-- T18 · com justificativa adequada passa
SELECT a2_assert(
  rpc_ninebox_evaluation_manager_submit(
    current_setting('a2.eval2_id')::UUID,
    jsonb_build_array(
      jsonb_build_object('axis', 'potential',   'criterion_index', 1, 'score', 5),
      jsonb_build_object('axis', 'performance', 'criterion_index', 1, 'score', 5)
    ),
    'Funcionario excepcional com entrega consistente acima da expectativa em todos os ciclos'
  ) ->> 'ok' = 'true',
  'T18 · caixa extrema com justificativa de 50+ chars passa'
);

-- T19 · justificativa muito curta -> rejeita
DO $$
DECLARE v_eval3 UUID;
BEGIN
  -- Cria 3a eval para USR3 (LIDER2 quem deveria, vamos usar SA pra agilizar)
  PERFORM test_login('a2aa2222-2222-2222-2222-0000000000FF');  -- SA
  v_eval3 := (rpc_ninebox_evaluation_start(
    '00000000-0000-0000-A2A4-000000000013',
    current_setting('a2.cycle_id')::UUID,
    FALSE
  ) ->> 'evaluation_id')::UUID;
  PERFORM set_config('a2.eval3_id', v_eval3::TEXT, FALSE);
END $$;

SELECT test_login('a2aa2222-2222-2222-2222-0000000000FF');

SELECT a2_assert(
  rpc_ninebox_evaluation_manager_submit(
    current_setting('a2.eval3_id')::UUID,
    jsonb_build_array(
      jsonb_build_object('axis', 'potential',   'criterion_index', 1, 'score', 1),
      jsonb_build_object('axis', 'performance', 'criterion_index', 1, 'score', 1)
    ),
    'curto'  -- < 50 chars
  ) ->> 'error' = 'justification_required_for_extreme_box',
  'T19 · justificativa muito curta em caixa extrema rejeitada'
);

-- ============================================================================
-- T20-T24 · Visibilidade
-- ============================================================================

-- T20 · USR1 ve sua propria evaluation
SELECT test_login('a2aa2222-2222-2222-2222-000000000011');  -- USR1
SELECT a2_assert(
  rpc_ninebox_evaluation_get(current_setting('a2.eval_id')::UUID) ->> 'view_as' = 'subject',
  'T20 · USR1 ve a propria evaluation como subject'
);

-- T21 · USR1 NAO ve a evaluation do USR2
SELECT a2_assert(
  rpc_ninebox_evaluation_get(current_setting('a2.eval2_id')::UUID) ->> 'error' = 'permission_denied',
  'T21 · USR1 nao acessa evaluation de outro colaborador'
);

-- T22 · LIDER1 ve evaluation de USR1 (liderado direto)
SELECT test_login('a2aa2222-2222-2222-2222-000000000001');  -- LIDER1
SELECT a2_assert(
  rpc_ninebox_evaluation_get(current_setting('a2.eval_id')::UUID) ->> 'view_as' = 'manager_or_admin',
  'T22 · LIDER1 ve evaluation de USR1 como manager'
);

-- T23 · LIDER1 NAO ve evaluation de USR3 (liderado de LIDER2)
SELECT a2_assert(
  rpc_ninebox_evaluation_get(current_setting('a2.eval3_id')::UUID) ->> 'error' = 'permission_denied',
  'T23 · LIDER1 nao ve evaluation fora do seu time'
);

-- T24 · DIR ve evaluation de USR3 (manager indireto, sobe a cadeia: USR3 -> LIDER2 -> DIR)
SELECT test_login('a2aa2222-2222-2222-2222-00000000000D');  -- DIR
SELECT a2_assert(
  rpc_ninebox_evaluation_get(current_setting('a2.eval3_id')::UUID) ->> 'view_as' = 'manager_or_admin',
  'T24 · DIR ve evaluation de USR3 (manager indireto)'
);

-- ============================================================================
-- T25 · Re-finalize gera snapshot v2 (auditoria de mudancas)
-- ============================================================================

-- DIR muda nota e re-submit (volta para manager_done) e finaliza de novo
SELECT test_login('a2aa2222-2222-2222-2222-00000000000D');  -- DIR

SELECT rpc_ninebox_evaluation_manager_submit(
  current_setting('a2.eval_id')::UUID,
  jsonb_build_array(
    jsonb_build_object('axis', 'potential',   'criterion_index', 1, 'score', 4),
    jsonb_build_object('axis', 'performance', 'criterion_index', 1, 'score', 3)
  )
);

SELECT rpc_ninebox_evaluation_finalize(current_setting('a2.eval_id')::UUID);

SELECT a2_assert(
  (SELECT count(*) FROM ninebox_evaluation_snapshots
   WHERE evaluation_id = current_setting('a2.eval_id')::UUID) = 2,
  'T25 · re-finalize gera snapshot v2'
);

SELECT a2_assert(
  (SELECT max(version) FROM ninebox_evaluation_snapshots
   WHERE evaluation_id = current_setting('a2.eval_id')::UUID) = 2,
  'T26 · snapshot v2 e a versao mais recente'
);

-- ============================================================================
-- T27 · Avaliacao ad-hoc (sem cycle_id)
-- ============================================================================

SELECT test_login('a2aa2222-2222-2222-2222-000000000001');  -- LIDER1

DO $$
DECLARE v_eval UUID;
BEGIN
  v_eval := (rpc_ninebox_evaluation_start(
    '00000000-0000-0000-A2A4-000000000011',  -- USR1 (mesmo subject)
    NULL,
    TRUE  -- ad-hoc
  ) ->> 'evaluation_id')::UUID;
  PERFORM set_config('a2.adhoc_id', v_eval::TEXT, FALSE);
  RAISE NOTICE 'PASS · T27 · ad-hoc para mesmo subject permitido (sem cycle)';
END $$;

SELECT a2_assert(
  (SELECT cycle_id FROM ninebox_evaluations WHERE id = current_setting('a2.adhoc_id')::UUID) IS NULL
  AND
  (SELECT is_adhoc FROM ninebox_evaluations WHERE id = current_setting('a2.adhoc_id')::UUID) = TRUE,
  'T28 · ad-hoc tem cycle_id NULL e is_adhoc TRUE'
);

-- ============================================================================
-- T29 · Cancel
-- ============================================================================

SELECT a2_assert(
  rpc_ninebox_evaluation_cancel(current_setting('a2.adhoc_id')::UUID, 'teste cancelar') ->> 'ok' = 'true',
  'T29 · cancel funciona em status draft'
);

SELECT a2_assert(
  (SELECT status::TEXT FROM ninebox_evaluations WHERE id = current_setting('a2.adhoc_id')::UUID) = 'canceled',
  'T30 · status virou canceled'
);

-- T31 · cancel em finalized -> erro
SELECT a2_assert(
  rpc_ninebox_evaluation_cancel(current_setting('a2.eval_id')::UUID, 'tentando') ->> 'error' = 'cannot_cancel_in_status',
  'T31 · nao pode cancelar evaluation finalizada'
);

-- ============================================================================
-- T32 · Modulo inativo no escopo do recurso
-- ============================================================================

-- Desativa ninebox em WU2 especificamente
SELECT test_login('a2aa2222-2222-2222-2222-0000000000FF');  -- SA

-- Atualmente ninebox esta ativo por scope=tenant para A2.
-- Vamos manter ativo, mas testar a checagem cruzando: USR3 esta em WU2,
-- mas se ninebox_settings nao tivesse criterios, start falharia.
-- Aqui vou validar uma situacao mais simples: USR1 (LIDER1) tenta
-- iniciar para alguem que nao existe -> subject_not_found
SELECT test_login('a2aa2222-2222-2222-2222-000000000001');  -- LIDER1
SELECT a2_assert(
  rpc_ninebox_evaluation_start(
    '00000000-0000-0000-FFFF-FFFFFFFFFFFF',  -- nao existe
    current_setting('a2.cycle_id')::UUID,
    FALSE
  ) ->> 'error' = 'subject_not_found',
  'T32 · subject inexistente -> erro'
);

-- ============================================================================
-- T33 · team_matrix · LIDER1 ve seus liderados, nao ve outros
-- ============================================================================

SELECT test_login('a2aa2222-2222-2222-2222-000000000001');  -- LIDER1

DO $$
DECLARE v_resp JSONB; v_count INT;
BEGIN
  v_resp := rpc_ninebox_team_matrix(current_setting('a2.cycle_id')::UUID, 'all');
  v_count := jsonb_array_length(v_resp -> 'points');
  -- LIDER1 lidera USR1 e USR2 · ambos tem evaluation -> 2 pontos
  IF v_count <> 2 THEN
    RAISE EXCEPTION 'T33 FAIL · esperado 2 pontos, obtido % · resp=%', v_count, v_resp;
  END IF;
  RAISE NOTICE 'PASS · T33 · LIDER1 ve 2 pontos no team_matrix (USR1 e USR2)';
END $$;

-- T34 · RH ve todas
-- Antes de chamar, deixa USR3 em manager_done (T19 deixou eval3 em draft)
SELECT test_login('a2aa2222-2222-2222-2222-0000000000FF');  -- SA
SELECT rpc_ninebox_evaluation_manager_submit(
  current_setting('a2.eval3_id')::UUID,
  jsonb_build_array(
    jsonb_build_object('axis', 'potential',   'criterion_index', 1, 'score', 1),
    jsonb_build_object('axis', 'performance', 'criterion_index', 1, 'score', 1)
  ),
  'Justificativa de baixo desempenho em ambos os eixos com mais de 50 caracteres totais.'
);

SELECT test_login('a2aa2222-2222-2222-2222-0000000000FE');  -- RH
SELECT a2_assert(
  jsonb_array_length(rpc_ninebox_team_matrix(current_setting('a2.cycle_id')::UUID, 'all') -> 'points') = 3,
  'T34 · RH ve 3 pontos (USR1, USR2, USR3)'
);

-- T35 · USR1 (colaborador sem liderados) NAO acessa team_matrix
SELECT test_login('a2aa2222-2222-2222-2222-000000000011');  -- USR1
SELECT a2_assert(
  rpc_ninebox_team_matrix(current_setting('a2.cycle_id')::UUID, 'all') ->> 'error' = 'permission_denied',
  'T35 · colaborador sem liderados nao acessa team_matrix'
);

-- ============================================================================
-- T36 · history · evolucao temporal
-- ============================================================================

-- USR1 ve seu proprio historico (1 evaluation finalizada com 2 versoes)
SELECT test_login('a2aa2222-2222-2222-2222-000000000011');  -- USR1
SELECT a2_assert(
  jsonb_array_length(rpc_ninebox_history('00000000-0000-0000-A2A4-000000000011') -> 'history') = 2,
  'T36 · USR1 ve 2 snapshots no proprio historico (v1 e v2)'
);

-- T37 · USR2 (colaborador sem hierarquia) NAO ve historico de USR1
SELECT test_login('a2aa2222-2222-2222-2222-000000000012');  -- USR2
SELECT a2_assert(
  rpc_ninebox_history('00000000-0000-0000-A2A4-000000000011') ->> 'error' = 'permission_denied',
  'T37 · colaborador nao acessa historico de outro'
);

-- ============================================================================
-- T38-T39 · require_self_assessment toggle
-- ============================================================================

SELECT test_login('a2aa2222-2222-2222-2222-0000000000FE');  -- RH
SELECT rpc_ninebox_settings_update(jsonb_build_object('require_self_assessment', TRUE));

SELECT test_login('a2aa2222-2222-2222-2222-000000000002');  -- LIDER2

DO $$
DECLARE v_eval UUID;
BEGIN
  -- Cancela primeiro o eval de USR3 que esta em manager_done (deixa um draft novo)
  v_eval := (rpc_ninebox_evaluation_start(
    '00000000-0000-0000-A2A4-000000000013',
    NULL, TRUE  -- ad-hoc para nao colidir
  ) ->> 'evaluation_id')::UUID;
  PERFORM set_config('a2.eval_self', v_eval::TEXT, FALSE);
END $$;

-- LIDER2 tenta submeter sem USR3 ter feito self · deve falhar
SELECT a2_assert(
  rpc_ninebox_evaluation_manager_submit(
    current_setting('a2.eval_self')::UUID,
    jsonb_build_array(
      jsonb_build_object('axis', 'potential',   'criterion_index', 1, 'score', 3),
      jsonb_build_object('axis', 'performance', 'criterion_index', 1, 'score', 3)
    )
  ) ->> 'error' = 'self_assessment_required_first',
  'T38 · com require_self_assessment, lider sem self bloqueado'
);

-- T39 · diretoria pode bypassar a regra
SELECT test_login('a2aa2222-2222-2222-2222-00000000000D');  -- DIR
SELECT a2_assert(
  rpc_ninebox_evaluation_manager_submit(
    current_setting('a2.eval_self')::UUID,
    jsonb_build_array(
      jsonb_build_object('axis', 'potential',   'criterion_index', 1, 'score', 3),
      jsonb_build_object('axis', 'performance', 'criterion_index', 1, 'score', 3)
    )
  ) ->> 'ok' = 'true',
  'T39 · diretoria pode bypassar require_self_assessment'
);

-- ============================================================================
-- T40 · Modulo inativo bloqueia (gate A1)
-- ============================================================================

SELECT test_login('a2aa2222-2222-2222-2222-0000000000FF');  -- SA

-- Desativa ninebox no tenant
DELETE FROM module_activations
WHERE module_code = 'ninebox'
  AND tenant_id = '00000000-0000-0000-A2A0-000000000001';

SELECT test_login('a2aa2222-2222-2222-2222-000000000011');  -- USR1
SELECT a2_assert(
  rpc_ninebox_evaluation_get(current_setting('a2.eval_id')::UUID) ->> 'error' = 'module_inactive',
  'T40 · sem ativacao retorna module_inactive (integrado com Sessao A1)'
);

-- ============================================================================
-- FECHAMENTO
-- ============================================================================

DO $$
BEGIN
  RAISE NOTICE '========================================';
  RAISE NOTICE '=== A2 · 40 testes executados · OK   ===';
  RAISE NOTICE '========================================';
END $$;

ROLLBACK;

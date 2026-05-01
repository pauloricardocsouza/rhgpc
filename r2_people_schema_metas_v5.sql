-- ============================================================================
-- R2 People · Schema do Módulo de Metas e Indicadores · v5
-- ============================================================================
-- Adiciona ao schema existente (v4) as 4 tabelas + RPCs para o módulo de metas:
--   1. goals                      · meta-mãe com período, escopo (filial/depto)
--   2. goal_indicators            · indicadores avaliados separadamente
--   3. goal_payout_rules          · regras de pagamento (cargo/depto/usuário)
--   4. goal_payout_calculations   · snapshot do cálculo final por colaborador
--
-- Inclui:
--   · Multi-tenancy via tenant_id (consistente com v4)
--   · RLS policies por papel (admin RH, gestor, líder, colaborador)
--   · Triggers para updated_at e validação de transições de status
--   · RPC `goals_calculate_payouts(goal_id)` que calcula prévia
--   · RPC `goals_finalize_validation(goal_id)` que congela payouts em snapshot
--   · Constraints e índices para queries comuns
--
-- Versão: 1.0 · 29 de abril de 2026
-- Dependências: tabelas users, units, departments, roles do schema v4
-- ============================================================================


-- ============================================================================
-- 1. TIPOS ENUMERADOS
-- ============================================================================

-- Status do ciclo de uma meta
CREATE TYPE goal_status AS ENUM (
  'draft',                -- rascunho · ainda sem ativação
  'active',               -- ativa · período em curso
  'result_pending',       -- período encerrou · aguarda lançamento
  'validation_pending',   -- resultado lançado · aguarda gestor validar
  'validated',            -- validada · aguarda processar folha
  'paid',                 -- paga · creditada na folha
  'cancelled'             -- cancelada · não gera pagamento
);

-- Periodicidade da meta
CREATE TYPE goal_periodicity AS ENUM (
  'monthly',
  'quarterly',
  'semestral',
  'annual',
  'custom'
);

-- Direção do indicador (maior é melhor / menor é melhor / valor exato)
CREATE TYPE indicator_direction AS ENUM (
  'higher_better',
  'lower_better',
  'exact_target'
);

-- Unidade do indicador (apresentação · não afeta cálculo)
CREATE TYPE indicator_unit AS ENUM (
  'currency_brl',  -- R$
  'percentage',    -- %
  'units',         -- un
  'kilograms',     -- kg
  'points',        -- pontos
  'count'          -- contagem genérica
);

-- Tipo de regra de pagamento
CREATE TYPE payout_rule_type AS ENUM (
  'role',          -- por cargo · multiplica pelo nº de pessoas no cargo
  'department',    -- por departamento · multiplica pelo nº no depto
  'user'           -- colaborador específico · valor único
);

-- Status de validação de cada indicador (independente do status da meta-mãe)
CREATE TYPE indicator_validation_status AS ENUM (
  'pending',       -- aguarda decisão do gestor
  'approved',      -- gestor aprovou
  'contested'      -- gestor contestou · líder precisa relançar
);

-- Status de cada linha de pagamento calculado
CREATE TYPE payout_calc_status AS ENUM (
  'preview',       -- prévia em tempo real · ainda não fechada
  'locked',        -- fechada após validação · aguarda folha
  'paid',          -- creditada na folha
  'cancelled'      -- cancelada · não vai pagar
);


-- ============================================================================
-- 2. TABELA: goals
-- ============================================================================
-- A meta-mãe. Cadastrada pelo RH ou gestor. Define escopo, período e responsáveis.
-- Pode ter 1+ indicadores e 1+ regras de pagamento.

CREATE TABLE goals (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,

  -- Identificação
  name VARCHAR(200) NOT NULL,
  description TEXT,

  -- Escopo (onde a meta se aplica)
  unit_id UUID REFERENCES units(id) ON DELETE RESTRICT,        -- filial · null = todas
  department_id UUID REFERENCES departments(id) ON DELETE RESTRICT,  -- depto · opcional

  -- Período
  period_start DATE NOT NULL,
  period_end DATE NOT NULL,
  periodicity goal_periodicity NOT NULL DEFAULT 'quarterly',

  -- Responsáveis
  owner_user_id UUID NOT NULL REFERENCES users(id) ON DELETE RESTRICT,    -- gestor que valida
  reporter_user_id UUID REFERENCES users(id) ON DELETE SET NULL,          -- quem aponta resultado

  -- Status do ciclo
  status goal_status NOT NULL DEFAULT 'draft',
  status_changed_at TIMESTAMPTZ DEFAULT now(),

  -- Rastreamento de clone (para metas recorrentes)
  cloned_from_goal_id UUID REFERENCES goals(id) ON DELETE SET NULL,

  -- Auditoria
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  created_by UUID REFERENCES users(id),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_by UUID REFERENCES users(id),

  -- Constraints
  CONSTRAINT goals_period_valid CHECK (period_end >= period_start),
  CONSTRAINT goals_name_not_empty CHECK (length(trim(name)) > 0)
);

CREATE INDEX idx_goals_tenant_status ON goals(tenant_id, status) WHERE status NOT IN ('cancelled', 'paid');
CREATE INDEX idx_goals_tenant_period ON goals(tenant_id, period_start, period_end);
CREATE INDEX idx_goals_owner ON goals(owner_user_id, status);
CREATE INDEX idx_goals_reporter ON goals(reporter_user_id, status);
CREATE INDEX idx_goals_unit_dept ON goals(unit_id, department_id);
CREATE INDEX idx_goals_cloned_from ON goals(cloned_from_goal_id) WHERE cloned_from_goal_id IS NOT NULL;

COMMENT ON TABLE goals IS 'Meta-mãe · cadastra período, escopo (filial/depto) e responsáveis. Tem 1+ indicadores e 1+ regras de pagamento.';
COMMENT ON COLUMN goals.cloned_from_goal_id IS 'Se a meta foi criada a partir de clone, aponta para a original. Útil para análise de evolução período a período.';


-- ============================================================================
-- 3. TABELA: goal_indicators
-- ============================================================================
-- Cada meta tem 1+ indicadores. Cada indicador é avaliado e validado independentemente.
-- O resultado é apontado pelo reporter e validado pelo owner.

CREATE TABLE goal_indicators (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  goal_id UUID NOT NULL REFERENCES goals(id) ON DELETE CASCADE,
  tenant_id UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,  -- desnormalizado para RLS

  -- Definição
  position INT NOT NULL DEFAULT 0,                  -- ordem de exibição
  name VARCHAR(150) NOT NULL,
  unit indicator_unit NOT NULL DEFAULT 'currency_brl',
  direction indicator_direction NOT NULL DEFAULT 'higher_better',

  -- Valores
  target_value NUMERIC(18, 4) NOT NULL,             -- valor alvo
  gate_percentage NUMERIC(5, 2) NOT NULL DEFAULT 80, -- % mín para liberar pagamento
  is_proportional BOOLEAN NOT NULL DEFAULT TRUE,    -- TRUE: paga proporcional · FALSE: binário

  -- Resultado lançado (preenchido na fase result_pending)
  result_value NUMERIC(18, 4),
  result_reported_at TIMESTAMPTZ,
  result_reported_by UUID REFERENCES users(id) ON DELETE SET NULL,
  result_comment TEXT,
  result_source TEXT,                                -- ex: "DRE TOTVS · fechamento 02/06"

  -- Validação (preenchida na fase validation_pending)
  validation_status indicator_validation_status NOT NULL DEFAULT 'pending',
  validated_at TIMESTAMPTZ,
  validated_by UUID REFERENCES users(id) ON DELETE SET NULL,
  validation_comment TEXT,

  -- % atingimento calculado (denormalizado para queries rápidas; recalculado por trigger)
  achievement_pct NUMERIC(7, 2),

  -- Auditoria
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),

  -- Constraints
  CONSTRAINT indicators_target_positive CHECK (target_value <> 0),  -- alvo zero não faz sentido
  CONSTRAINT indicators_gate_pct_range CHECK (gate_percentage >= 0 AND gate_percentage <= 200),
  CONSTRAINT indicators_name_not_empty CHECK (length(trim(name)) > 0)
);

CREATE INDEX idx_indicators_goal ON goal_indicators(goal_id, position);
CREATE INDEX idx_indicators_validation ON goal_indicators(tenant_id, validation_status) WHERE validation_status = 'pending';
CREATE INDEX idx_indicators_reporter ON goal_indicators(result_reported_by) WHERE result_reported_at IS NOT NULL;

COMMENT ON COLUMN goal_indicators.gate_percentage IS 'Porcentagem mínima de atingimento para liberar pagamento. Ex: 80 = só paga se atingiu 80%+ do alvo.';
COMMENT ON COLUMN goal_indicators.is_proportional IS 'TRUE: paga proporcional ao atingimento (capped em 100%). FALSE: binário · acima do gate paga 100%, abaixo paga 0%.';
COMMENT ON COLUMN goal_indicators.achievement_pct IS 'Cache do % atingimento. Recalculado por trigger quando result_value muda. Pode passar de 100% (ex: 117% supera alvo).';


-- ============================================================================
-- 4. TABELA: goal_payout_rules
-- ============================================================================
-- Regras de pagamento. 1 meta pode ter N regras combinando tipos diferentes.
-- Ex: meta "Rentabilidade Cestão L1" tem:
--   · regra 1: por cargo "Comprador Pleno" → R$ 500 cada
--   · regra 2: por cargo "Assistente"      → R$ 200 cada
--   · regra 3: usuário "João Carvalho"     → R$ 2.000

CREATE TABLE goal_payout_rules (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  goal_id UUID NOT NULL REFERENCES goals(id) ON DELETE CASCADE,
  tenant_id UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,  -- desnormalizado para RLS

  -- Tipo da regra
  rule_type payout_rule_type NOT NULL,

  -- Beneficiário (apenas UM dos 3 deve estar preenchido conforme rule_type)
  role_id UUID REFERENCES roles(id) ON DELETE RESTRICT,
  department_id UUID REFERENCES departments(id) ON DELETE RESTRICT,
  user_id UUID REFERENCES users(id) ON DELETE RESTRICT,

  -- Valor por pessoa elegível
  amount_per_person NUMERIC(12, 2) NOT NULL,

  -- Filtros adicionais (opcionais)
  unit_id UUID REFERENCES units(id) ON DELETE RESTRICT,  -- restringe a uma filial específica

  -- Auditoria
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),

  -- Constraints
  CONSTRAINT payout_rules_amount_positive CHECK (amount_per_person > 0),
  CONSTRAINT payout_rules_one_beneficiary CHECK (
    (rule_type = 'role'       AND role_id IS NOT NULL       AND department_id IS NULL AND user_id IS NULL) OR
    (rule_type = 'department' AND department_id IS NOT NULL AND role_id IS NULL       AND user_id IS NULL) OR
    (rule_type = 'user'       AND user_id IS NOT NULL       AND role_id IS NULL       AND department_id IS NULL)
  )
);

CREATE INDEX idx_payout_rules_goal ON goal_payout_rules(goal_id);
CREATE INDEX idx_payout_rules_role ON goal_payout_rules(role_id) WHERE role_id IS NOT NULL;
CREATE INDEX idx_payout_rules_dept ON goal_payout_rules(department_id) WHERE department_id IS NOT NULL;
CREATE INDEX idx_payout_rules_user ON goal_payout_rules(user_id) WHERE user_id IS NOT NULL;

COMMENT ON TABLE goal_payout_rules IS 'Regras de pagamento. Cada regra define quem recebe (cargo/depto/colaborador) e quanto. Uma meta pode misturar regras de tipos diferentes.';
COMMENT ON COLUMN goal_payout_rules.amount_per_person IS 'Valor por pessoa elegível. Para regras de cargo/depto, multiplica pelo headcount. Para user específico, é valor único.';
COMMENT ON COLUMN goal_payout_rules.unit_id IS 'Restringe a regra a uma filial específica (útil quando a meta cobre múltiplas filiais mas o pagamento é localizado).';


-- ============================================================================
-- 5. TABELA: goal_payout_calculations
-- ============================================================================
-- Snapshot do cálculo final por colaborador, congelado no momento da validação.
-- Antes de validar: linhas com status='preview' e podem ser regeneradas.
-- Após validar:    linhas com status='locked' e não mudam mais (audit trail).

CREATE TABLE goal_payout_calculations (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  goal_id UUID NOT NULL REFERENCES goals(id) ON DELETE CASCADE,
  tenant_id UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,  -- desnormalizado para RLS

  -- Beneficiário final
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE RESTRICT,

  -- Origem do cálculo
  applied_rule_id UUID REFERENCES goal_payout_rules(id) ON DELETE SET NULL,
  applied_rule_type payout_rule_type NOT NULL,
  applied_role_id UUID REFERENCES roles(id),
  applied_department_id UUID REFERENCES departments(id),

  -- Valores
  base_amount NUMERIC(12, 2) NOT NULL,           -- valor cheio se atingisse 100%
  achievement_pct NUMERIC(7, 2) NOT NULL,        -- % médio dos indicadores aprovados
  final_amount NUMERIC(12, 2) NOT NULL,          -- base × pct/100 (ou 0 se abaixo do gate)

  -- Status do pagamento
  status payout_calc_status NOT NULL DEFAULT 'preview',
  locked_at TIMESTAMPTZ,
  paid_at TIMESTAMPTZ,
  payroll_reference VARCHAR(50),                  -- ex: "FOLHA-2026-06"

  -- Snapshot (preserva contexto após mudança de cargo/depto)
  user_role_at_lock VARCHAR(100),
  user_department_at_lock VARCHAR(100),
  user_unit_at_lock VARCHAR(100),

  -- Auditoria
  calculated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  calculated_by UUID REFERENCES users(id),

  -- Constraints
  CONSTRAINT payout_calc_amounts_non_negative CHECK (base_amount >= 0 AND final_amount >= 0),
  CONSTRAINT payout_calc_achievement_range CHECK (achievement_pct >= 0 AND achievement_pct <= 200),
  CONSTRAINT payout_calc_one_beneficiary_per_goal_user UNIQUE (goal_id, user_id, applied_rule_id)
);

CREATE INDEX idx_payout_calc_goal_status ON goal_payout_calculations(goal_id, status);
CREATE INDEX idx_payout_calc_user ON goal_payout_calculations(user_id, status);
CREATE INDEX idx_payout_calc_payroll ON goal_payout_calculations(payroll_reference) WHERE payroll_reference IS NOT NULL;
CREATE INDEX idx_payout_calc_locked ON goal_payout_calculations(tenant_id, status, locked_at) WHERE status IN ('locked', 'paid');

COMMENT ON TABLE goal_payout_calculations IS 'Snapshot do cálculo de pagamento por colaborador. Antes da validação: status=preview e regenerável. Após: status=locked e imutável (audit trail).';
COMMENT ON COLUMN goal_payout_calculations.user_role_at_lock IS 'Snapshot do cargo do colaborador no momento do lock. Preserva contexto se ele for promovido depois.';


-- ============================================================================
-- 6. TRIGGERS · auto-cálculo de achievement_pct e updated_at
-- ============================================================================

-- Recalcular achievement_pct sempre que result_value muda
CREATE OR REPLACE FUNCTION fn_calc_indicator_achievement()
RETURNS TRIGGER AS $$
BEGIN
  IF NEW.result_value IS NOT NULL AND NEW.target_value <> 0 THEN
    -- Direção: higher_better usa result/target · lower_better usa target/result
    IF NEW.direction = 'higher_better' THEN
      NEW.achievement_pct := ROUND((NEW.result_value / NEW.target_value * 100)::NUMERIC, 2);
    ELSIF NEW.direction = 'lower_better' THEN
      IF NEW.result_value > 0 THEN
        NEW.achievement_pct := ROUND((NEW.target_value / NEW.result_value * 100)::NUMERIC, 2);
      ELSE
        NEW.achievement_pct := 200;  -- caso especial: zero é "infinitamente bom"
      END IF;
    ELSE  -- exact_target: quanto mais próximo, melhor
      NEW.achievement_pct := ROUND(
        GREATEST(0, 100 - ABS((NEW.result_value - NEW.target_value) / NEW.target_value * 100))::NUMERIC,
        2
      );
    END IF;
  ELSE
    NEW.achievement_pct := NULL;
  END IF;

  NEW.updated_at := now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_calc_indicator_achievement
  BEFORE INSERT OR UPDATE OF result_value, target_value, direction
  ON goal_indicators
  FOR EACH ROW
  EXECUTE FUNCTION fn_calc_indicator_achievement();


-- updated_at automático em todas as tabelas
CREATE OR REPLACE FUNCTION fn_set_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at := now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_goals_updated_at BEFORE UPDATE ON goals
  FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at();

CREATE TRIGGER trg_payout_rules_updated_at BEFORE UPDATE ON goal_payout_rules
  FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at();


-- Validação de transição de status (state machine)
CREATE OR REPLACE FUNCTION fn_validate_goal_status_transition()
RETURNS TRIGGER AS $$
BEGIN
  IF OLD.status = NEW.status THEN
    RETURN NEW;
  END IF;

  -- Transições permitidas
  IF NOT (
    (OLD.status = 'draft'              AND NEW.status IN ('active', 'cancelled')) OR
    (OLD.status = 'active'             AND NEW.status IN ('result_pending', 'cancelled')) OR
    (OLD.status = 'result_pending'     AND NEW.status IN ('validation_pending', 'cancelled')) OR
    (OLD.status = 'validation_pending' AND NEW.status IN ('result_pending', 'validated', 'cancelled')) OR
    (OLD.status = 'validated'          AND NEW.status IN ('paid', 'cancelled')) OR
    (OLD.status = 'paid'               AND NEW.status = 'paid')  -- terminal
  ) THEN
    RAISE EXCEPTION 'Transição inválida de status: % → %', OLD.status, NEW.status;
  END IF;

  NEW.status_changed_at := now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_goal_status_transition
  BEFORE UPDATE OF status ON goals
  FOR EACH ROW
  EXECUTE FUNCTION fn_validate_goal_status_transition();


-- ============================================================================
-- 7. RPC · goals_calculate_payouts
-- ============================================================================
-- Calcula a prévia de pagamentos para uma meta (sem persistir como locked).
-- Usado pela UI em tempo real e pela validação para mostrar valores finais.
-- Retorna linhas que devem ser exibidas/persistidas em goal_payout_calculations.

CREATE OR REPLACE FUNCTION goals_calculate_payouts(p_goal_id UUID)
RETURNS TABLE (
  user_id UUID,
  user_name TEXT,
  applied_rule_id UUID,
  applied_rule_type payout_rule_type,
  base_amount NUMERIC(12, 2),
  achievement_pct NUMERIC(7, 2),
  final_amount NUMERIC(12, 2)
) AS $$
DECLARE
  v_avg_achievement NUMERIC(7, 2);
  v_goal_unit_id UUID;
BEGIN
  -- 1. Achievement médio dos indicadores APROVADOS
  --    Indicadores com gate não atingido contribuem 0%
  --    Indicadores não-proporcionais ficam 0% se abaixo do gate, 100% se acima
  SELECT AVG(
    CASE
      WHEN gi.validation_status <> 'approved' THEN NULL  -- ignora não aprovados
      WHEN gi.achievement_pct IS NULL THEN NULL          -- sem resultado
      WHEN gi.achievement_pct < gi.gate_percentage THEN 0
      WHEN NOT gi.is_proportional THEN 100               -- binário acima do gate
      ELSE LEAST(gi.achievement_pct, 100)                -- proporcional capped em 100
    END
  )::NUMERIC(7, 2)
  INTO v_avg_achievement
  FROM goal_indicators gi
  WHERE gi.goal_id = p_goal_id
    AND gi.validation_status = 'approved';

  -- Se nenhum indicador aprovado, atingimento é 0
  v_avg_achievement := COALESCE(v_avg_achievement, 0);

  -- 2. Pega unit_id da meta para filtros opcionais
  SELECT g.unit_id INTO v_goal_unit_id FROM goals g WHERE g.id = p_goal_id;

  -- 3. Expande as regras em linhas por colaborador
  RETURN QUERY
  WITH expanded AS (
    -- Regra por cargo: 1 linha por usuário no cargo (na unit da meta, se especificada)
    SELECT
      u.id AS user_id,
      u.full_name AS user_name,
      pr.id AS applied_rule_id,
      pr.rule_type AS applied_rule_type,
      pr.amount_per_person AS base_amount
    FROM goal_payout_rules pr
    JOIN users u ON u.role_id = pr.role_id
    WHERE pr.goal_id = p_goal_id
      AND pr.rule_type = 'role'
      AND u.is_active
      AND (pr.unit_id IS NULL OR u.unit_id = pr.unit_id)
      AND (v_goal_unit_id IS NULL OR u.unit_id = v_goal_unit_id)

    UNION ALL

    -- Regra por departamento
    SELECT
      u.id, u.full_name, pr.id, pr.rule_type, pr.amount_per_person
    FROM goal_payout_rules pr
    JOIN users u ON u.department_id = pr.department_id
    WHERE pr.goal_id = p_goal_id
      AND pr.rule_type = 'department'
      AND u.is_active
      AND (pr.unit_id IS NULL OR u.unit_id = pr.unit_id)
      AND (v_goal_unit_id IS NULL OR u.unit_id = v_goal_unit_id)

    UNION ALL

    -- Regra por usuário específico
    SELECT
      u.id, u.full_name, pr.id, pr.rule_type, pr.amount_per_person
    FROM goal_payout_rules pr
    JOIN users u ON u.id = pr.user_id
    WHERE pr.goal_id = p_goal_id
      AND pr.rule_type = 'user'
      AND u.is_active
  )
  SELECT
    e.user_id,
    e.user_name,
    e.applied_rule_id,
    e.applied_rule_type,
    e.base_amount,
    v_avg_achievement,
    ROUND((e.base_amount * v_avg_achievement / 100)::NUMERIC, 2) AS final_amount
  FROM expanded e
  ORDER BY e.user_name;
END;
$$ LANGUAGE plpgsql STABLE;

COMMENT ON FUNCTION goals_calculate_payouts IS 'Calcula prévia de pagamentos. Soma indicadores aprovados, aplica gate e proporcionalidade, expande regras em linhas por colaborador. Não persiste · uso em tempo real e na validação.';


-- ============================================================================
-- 8. RPC · goals_finalize_validation
-- ============================================================================
-- Chamado quando o gestor aprova todos os indicadores e clica "Aprovar e fechar".
-- Persiste o snapshot calculado em goal_payout_calculations com status='locked'.

CREATE OR REPLACE FUNCTION goals_finalize_validation(p_goal_id UUID, p_validator_id UUID)
RETURNS TABLE (
  beneficiaries_count INT,
  total_amount NUMERIC(12, 2)
) AS $$
DECLARE
  v_count INT;
  v_total NUMERIC(12, 2);
  v_tenant_id UUID;
BEGIN
  -- Garantir que todos os indicadores foram decididos
  IF EXISTS (
    SELECT 1 FROM goal_indicators
    WHERE goal_id = p_goal_id AND validation_status = 'pending'
  ) THEN
    RAISE EXCEPTION 'Existem indicadores aguardando decisão. Aprove ou conteste todos antes de fechar.';
  END IF;

  -- Pegar tenant_id da meta
  SELECT tenant_id INTO v_tenant_id FROM goals WHERE id = p_goal_id;

  -- Limpar previews antigos (se houver)
  DELETE FROM goal_payout_calculations
  WHERE goal_id = p_goal_id AND status = 'preview';

  -- Inserir snapshot atual com status='locked'
  INSERT INTO goal_payout_calculations (
    goal_id, tenant_id, user_id, applied_rule_id, applied_rule_type,
    applied_role_id, applied_department_id,
    base_amount, achievement_pct, final_amount,
    status, locked_at,
    user_role_at_lock, user_department_at_lock, user_unit_at_lock,
    calculated_by
  )
  SELECT
    p_goal_id,
    v_tenant_id,
    calc.user_id,
    calc.applied_rule_id,
    calc.applied_rule_type,
    u.role_id,
    u.department_id,
    calc.base_amount,
    calc.achievement_pct,
    calc.final_amount,
    'locked',
    now(),
    r.name,        -- snapshot do cargo
    d.name,        -- snapshot do depto
    un.name,       -- snapshot da unidade
    p_validator_id
  FROM goals_calculate_payouts(p_goal_id) calc
  JOIN users u ON u.id = calc.user_id
  LEFT JOIN roles r ON r.id = u.role_id
  LEFT JOIN departments d ON d.id = u.department_id
  LEFT JOIN units un ON un.id = u.unit_id;

  -- Atualizar status da meta para validated
  UPDATE goals
  SET status = 'validated',
      updated_by = p_validator_id
  WHERE id = p_goal_id;

  -- Retornar resumo
  SELECT COUNT(*)::INT, COALESCE(SUM(final_amount), 0)::NUMERIC(12, 2)
  INTO v_count, v_total
  FROM goal_payout_calculations
  WHERE goal_id = p_goal_id AND status = 'locked';

  RETURN QUERY SELECT v_count, v_total;
END;
$$ LANGUAGE plpgsql VOLATILE SECURITY DEFINER;

COMMENT ON FUNCTION goals_finalize_validation IS 'Fecha validação e persiste snapshot final. Marca payouts como locked e move meta para status validated. Falha se algum indicador estiver pending.';


-- ============================================================================
-- 9. RPC · goals_clone_from_previous
-- ============================================================================
-- Cria nova meta clonando indicadores e regras de uma meta anterior.
-- Não copia: período, status, resultados, validações.

CREATE OR REPLACE FUNCTION goals_clone_from_previous(
  p_source_goal_id UUID,
  p_new_period_start DATE,
  p_new_period_end DATE,
  p_creator_id UUID
)
RETURNS UUID AS $$
DECLARE
  v_new_goal_id UUID;
  v_source goals%ROWTYPE;
BEGIN
  -- Carregar meta de origem
  SELECT * INTO v_source FROM goals WHERE id = p_source_goal_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Meta de origem não encontrada: %', p_source_goal_id;
  END IF;

  -- Criar nova meta como rascunho
  INSERT INTO goals (
    tenant_id, name, description, unit_id, department_id,
    period_start, period_end, periodicity,
    owner_user_id, reporter_user_id,
    status, cloned_from_goal_id,
    created_by, updated_by
  ) VALUES (
    v_source.tenant_id,
    v_source.name || ' (cópia)',
    v_source.description,
    v_source.unit_id,
    v_source.department_id,
    p_new_period_start,
    p_new_period_end,
    v_source.periodicity,
    v_source.owner_user_id,
    v_source.reporter_user_id,
    'draft',
    p_source_goal_id,
    p_creator_id,
    p_creator_id
  ) RETURNING id INTO v_new_goal_id;

  -- Clonar indicadores (sem resultado/validação)
  INSERT INTO goal_indicators (
    goal_id, tenant_id, position, name, unit, direction,
    target_value, gate_percentage, is_proportional
  )
  SELECT
    v_new_goal_id, tenant_id, position, name, unit, direction,
    target_value, gate_percentage, is_proportional
  FROM goal_indicators
  WHERE goal_id = p_source_goal_id;

  -- Clonar regras de pagamento
  INSERT INTO goal_payout_rules (
    goal_id, tenant_id, rule_type,
    role_id, department_id, user_id,
    amount_per_person, unit_id
  )
  SELECT
    v_new_goal_id, tenant_id, rule_type,
    role_id, department_id, user_id,
    amount_per_person, unit_id
  FROM goal_payout_rules
  WHERE goal_id = p_source_goal_id;

  RETURN v_new_goal_id;
END;
$$ LANGUAGE plpgsql VOLATILE SECURITY DEFINER;

COMMENT ON FUNCTION goals_clone_from_previous IS 'Cria nova meta a partir de outra como template. Copia indicadores e regras, gera novo ciclo em rascunho. Períodos e validações são novos.';


-- ============================================================================
-- 10. RLS POLICIES · multi-tenant + papel
-- ============================================================================

ALTER TABLE goals ENABLE ROW LEVEL SECURITY;
ALTER TABLE goal_indicators ENABLE ROW LEVEL SECURITY;
ALTER TABLE goal_payout_rules ENABLE ROW LEVEL SECURITY;
ALTER TABLE goal_payout_calculations ENABLE ROW LEVEL SECURITY;

-- Helper · pega tenant atual da sessão (mesma função do schema v4)
-- assume current_tenant_id() já existe

-- GOALS · leitura
CREATE POLICY goals_select_admin_rh ON goals
  FOR SELECT TO authenticated
  USING (
    tenant_id = current_tenant_id()
    AND has_permission('goals.view_all')
  );

CREATE POLICY goals_select_owner ON goals
  FOR SELECT TO authenticated
  USING (
    tenant_id = current_tenant_id()
    AND owner_user_id = current_user_id()
  );

CREATE POLICY goals_select_reporter ON goals
  FOR SELECT TO authenticated
  USING (
    tenant_id = current_tenant_id()
    AND reporter_user_id = current_user_id()
  );

CREATE POLICY goals_select_beneficiary ON goals
  FOR SELECT TO authenticated
  USING (
    tenant_id = current_tenant_id()
    AND id IN (
      SELECT goal_id FROM goal_payout_calculations
      WHERE user_id = current_user_id()
    )
  );

-- GOALS · INSERT/UPDATE só admin RH e owner
CREATE POLICY goals_modify ON goals
  FOR ALL TO authenticated
  USING (
    tenant_id = current_tenant_id()
    AND (has_permission('goals.manage') OR owner_user_id = current_user_id())
  )
  WITH CHECK (
    tenant_id = current_tenant_id()
    AND (has_permission('goals.manage') OR owner_user_id = current_user_id())
  );

-- INDICATORS · herda do goal
CREATE POLICY indicators_select ON goal_indicators
  FOR SELECT TO authenticated
  USING (
    tenant_id = current_tenant_id()
    AND goal_id IN (SELECT id FROM goals)  -- aplica RLS de goals em cascata
  );

CREATE POLICY indicators_modify ON goal_indicators
  FOR ALL TO authenticated
  USING (
    tenant_id = current_tenant_id()
    AND goal_id IN (
      SELECT id FROM goals
      WHERE has_permission('goals.manage') OR owner_user_id = current_user_id() OR reporter_user_id = current_user_id()
    )
  )
  WITH CHECK (
    tenant_id = current_tenant_id()
    AND goal_id IN (
      SELECT id FROM goals
      WHERE has_permission('goals.manage') OR owner_user_id = current_user_id() OR reporter_user_id = current_user_id()
    )
  );

-- PAYOUT_RULES · só admin RH e owner podem definir; beneficiários podem ler
CREATE POLICY payout_rules_select ON goal_payout_rules
  FOR SELECT TO authenticated
  USING (
    tenant_id = current_tenant_id()
    AND goal_id IN (SELECT id FROM goals)
  );

CREATE POLICY payout_rules_modify ON goal_payout_rules
  FOR ALL TO authenticated
  USING (
    tenant_id = current_tenant_id()
    AND goal_id IN (
      SELECT id FROM goals
      WHERE has_permission('goals.manage') OR owner_user_id = current_user_id()
    )
  )
  WITH CHECK (
    tenant_id = current_tenant_id()
    AND goal_id IN (
      SELECT id FROM goals
      WHERE has_permission('goals.manage') OR owner_user_id = current_user_id()
    )
  );

-- PAYOUT_CALCULATIONS · cada beneficiário lê o seu; admin RH lê tudo
CREATE POLICY payout_calc_select_self ON goal_payout_calculations
  FOR SELECT TO authenticated
  USING (
    tenant_id = current_tenant_id()
    AND user_id = current_user_id()
  );

CREATE POLICY payout_calc_select_admin ON goal_payout_calculations
  FOR SELECT TO authenticated
  USING (
    tenant_id = current_tenant_id()
    AND has_permission('goals.view_all')
  );

CREATE POLICY payout_calc_select_owner ON goal_payout_calculations
  FOR SELECT TO authenticated
  USING (
    tenant_id = current_tenant_id()
    AND goal_id IN (SELECT id FROM goals WHERE owner_user_id = current_user_id())
  );

-- INSERT/UPDATE em payout_calculations só via RPCs (SECURITY DEFINER)
-- não há policy de INSERT/UPDATE direto; clientes não conseguem mexer manualmente


-- ============================================================================
-- 11. VIEWS DE CONVENIÊNCIA
-- ============================================================================

-- Resumo de meta para cards na lista (Patrícia)
CREATE OR REPLACE VIEW vw_goal_summary AS
SELECT
  g.id,
  g.tenant_id,
  g.name,
  g.status,
  g.period_start,
  g.period_end,
  g.periodicity,
  un.name AS unit_name,
  d.name AS department_name,
  owner.full_name AS owner_name,
  reporter.full_name AS reporter_name,
  (SELECT COUNT(*) FROM goal_indicators WHERE goal_id = g.id) AS indicators_count,
  (SELECT COUNT(*) FROM goal_payout_rules WHERE goal_id = g.id) AS rules_count,
  (
    SELECT COUNT(DISTINCT calc.user_id)
    FROM goals_calculate_payouts(g.id) calc
  ) AS beneficiaries_count,
  (
    SELECT COALESCE(SUM(calc.base_amount), 0)
    FROM goals_calculate_payouts(g.id) calc
  ) AS payout_full_amount,
  (
    SELECT COALESCE(SUM(calc.final_amount), 0)
    FROM goals_calculate_payouts(g.id) calc
  ) AS payout_calculated_amount,
  CASE
    WHEN g.status = 'paid' THEN 0
    WHEN g.period_end < CURRENT_DATE THEN 0
    ELSE (g.period_end - CURRENT_DATE)::INT
  END AS days_remaining
FROM goals g
LEFT JOIN units un ON un.id = g.unit_id
LEFT JOIN departments d ON d.id = g.department_id
LEFT JOIN users owner ON owner.id = g.owner_user_id
LEFT JOIN users reporter ON reporter.id = g.reporter_user_id;

COMMENT ON VIEW vw_goal_summary IS 'Visão consolidada de meta para listagens. Calcula contagens e totais via RPC. Use em cards e relatórios.';


-- View "Minhas metas" (visão do colaborador)
CREATE OR REPLACE VIEW vw_my_goals AS
SELECT
  g.id AS goal_id,
  g.name,
  g.status,
  g.period_start,
  g.period_end,
  un.name AS unit_name,
  d.name AS department_name,
  pr.rule_type AS my_rule_type,
  pr.amount_per_person AS my_potential_amount,
  pc.final_amount AS my_calculated_amount,
  pc.status AS my_payout_status,
  pc.payroll_reference AS my_payroll_ref,
  (
    SELECT AVG(achievement_pct)
    FROM goal_indicators
    WHERE goal_id = g.id AND validation_status = 'approved'
  ) AS avg_achievement_pct
FROM goals g
LEFT JOIN units un ON un.id = g.unit_id
LEFT JOIN departments d ON d.id = g.department_id
JOIN goal_payout_rules pr ON pr.goal_id = g.id
LEFT JOIN goal_payout_calculations pc ON pc.goal_id = g.id AND pc.user_id = current_user_id()
WHERE
  -- Linhas onde o usuário atual é beneficiário
  (pr.rule_type = 'user' AND pr.user_id = current_user_id())
  OR (pr.rule_type = 'role' AND pr.role_id = (SELECT role_id FROM users WHERE id = current_user_id()))
  OR (pr.rule_type = 'department' AND pr.department_id = (SELECT department_id FROM users WHERE id = current_user_id()));

COMMENT ON VIEW vw_my_goals IS 'Metas das quais o usuário atual é beneficiário. Filtra por regras de cargo/depto/individual + RLS de payout_calculations.';


-- ============================================================================
-- 12. PERMISSÕES (granular)
-- ============================================================================
-- Adicionar à tabela permissions (do schema v4):

INSERT INTO permissions (key, label, description, module) VALUES
  ('goals.view_all',     'Ver todas as metas',        'Acessa metas de todas as filiais e departamentos',     'goals'),
  ('goals.manage',       'Gerenciar metas',           'Criar, editar, ativar e cancelar metas',                'goals'),
  ('goals.report_result','Lançar resultado',          'Apontar valor realizado dos indicadores',               'goals'),
  ('goals.validate',     'Validar resultado',         'Aprovar ou contestar indicadores e fechar pagamento',  'goals'),
  ('goals.view_payouts', 'Ver cálculo de pagamentos', 'Visualizar valores calculados por colaborador',         'goals'),
  ('goals.export',       'Exportar para folha',       'Gerar arquivo de remessa para sistema de folha',       'goals')
ON CONFLICT (key) DO NOTHING;


-- ============================================================================
-- 13. EXEMPLOS DE QUERIES COMUNS
-- ============================================================================

-- Exemplo 1: Lista de metas que aguardam validação do gestor logado
-- SELECT * FROM vw_goal_summary WHERE status = 'validation_pending' AND owner_user_id = '<user-id>';

-- Exemplo 2: Prévia de payouts antes da validação
-- SELECT * FROM goals_calculate_payouts('<goal-id>') ORDER BY final_amount DESC;

-- Exemplo 3: Histórico anual do colaborador (timeline pessoal)
-- SELECT
--   DATE_TRUNC('month', g.period_end) AS month,
--   SUM(pc.final_amount) AS total_received,
--   COUNT(DISTINCT g.id) AS goals_count
-- FROM goal_payout_calculations pc
-- JOIN goals g ON g.id = pc.goal_id
-- WHERE pc.user_id = current_user_id()
--   AND pc.status IN ('locked', 'paid')
--   AND g.period_end BETWEEN '2026-01-01' AND '2026-12-31'
-- GROUP BY DATE_TRUNC('month', g.period_end)
-- ORDER BY month;

-- Exemplo 4: Comparação · seu desempenho vs equipe (compradores no mesmo trimestre)
-- WITH team_avg AS (
--   SELECT AVG(pc.achievement_pct) AS team_pct
--   FROM goal_payout_calculations pc
--   JOIN goals g ON g.id = pc.goal_id
--   JOIN users u ON u.id = pc.user_id
--   WHERE u.role_id = (SELECT role_id FROM users WHERE id = current_user_id())
--     AND g.period_end BETWEEN '2026-04-01' AND '2026-06-30'
-- )
-- SELECT
--   pc.user_id,
--   pc.achievement_pct AS my_pct,
--   t.team_pct
-- FROM goal_payout_calculations pc, team_avg t
-- WHERE pc.user_id = current_user_id();


-- ============================================================================
-- FIM · v5 do módulo de metas
-- ============================================================================
-- Próximas iterações sugeridas (v6):
--   · Tabela goal_history para log de alterações (auditoria detalhada)
--   · Suporte a metas em cascata (1 meta-mãe da empresa → metas-filhas das filiais)
--   · Notificações automáticas (gatilhos para emails/push em transições de status)
--   · Webhook para integrar com sistema de folha externo
--   · Suporte a indicadores compostos (fórmulas combinando múltiplos KPIs)

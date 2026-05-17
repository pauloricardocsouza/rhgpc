# Spec · M4 · Férias (módulo completo)

**Status:** pronto para execução em ambiente com Postgres 16
**Pré-requisitos:** M1 (Estrutura) aplicado · helper `user_is_manager_of()` disponível
**Estimativa:** 2 sessões (~6-8h)

---

## 1. Objetivo

Portar para Next.js o **módulo de Férias** desenhado no rhgpc. Substitui planilhas de programação e gera schema formal para vacation_acquisition_periods + vacation_periods com regras CLT enforced no banco.

| Tela origem | Página Next.js | Persona |
|---|---|---|
| [r2_people_ferias.html](../r2_people_ferias.html) | `/ferias` | RH (Patrícia) |
| [r2_people_ferias_programacao_anual.html](../r2_people_ferias_programacao_anual.html) | `/ferias/programacao-anual` | RH + Líder + Diretoria |
| [r2_people_ferias_programar.html](../r2_people_ferias_programar.html) | modal embarcado em ambas | Colaborador (autoatendimento) ou Líder |
| [r2_people_afastamentos.html](../r2_people_afastamentos.html) | `/afastamentos` | RH (relacionado, gera dos atestados) |

---

## 2. Regras CLT enforced no banco

| Regra | Artigo CLT | Onde validar |
|---|---|---|
| Período aquisitivo 12 meses contínuos | Art. 130 | trigger ao criar `vacation_acquisition_periods` |
| Período concessivo 12 meses após aquisitivo | Art. 134 | CHECK constraint |
| Vencimento gera multa em dobro | Art. 137 | flag `paid_double` ao processar pós-concessivo |
| Fracionamento até 3 partes, uma ≥ 14 dias contínuos | Art. 134 §1º | RPC `rpc_create_vacation_plan` valida fracionamento |
| Aviso prévio ≥ 30 dias da data de início | Art. 135 | CHECK em `vacation_periods.starts_at` vs `notified_at` |
| Abono pecuniário ≤ 1/3 dos dias | Art. 143 | CHECK `bonus_days <= round(total_days/3)` |
| Faltas reduzem dias de férias (>5 = 24d, >14 = 18d, >23 = 12d) | Art. 130 | função `calc_vacation_days_after_absences()` |

---

## 3. Schema · migration 00430_m4_schema_vacations.sql

```sql
-- ENUMS
DO $$ BEGIN CREATE TYPE vacation_status AS ENUM (
  'planned',       -- programado, aguarda aprovação
  'approved',      -- aprovado, aguarda início
  'in_progress',   -- em curso
  'completed',     -- concluído
  'canceled'
); EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN CREATE TYPE acquisition_status AS ENUM (
  'open',          -- período aquisitivo em curso
  'completed',     -- 12 meses completados, saldo disponível
  'expired',       -- venceu sem programar, paga em dobro
  'paid'           -- pago, encerrado
); EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- TABELAS

CREATE TABLE vacation_acquisition_periods (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id       UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  employee_id     UUID NOT NULL REFERENCES app_users(id) ON DELETE CASCADE,
  starts_at       DATE NOT NULL,                       -- início do aquisitivo
  ends_at         DATE NOT NULL,                       -- starts_at + 1 year - 1 day
  concessivo_ends_at DATE NOT NULL,                    -- ends_at + 1 year
  status          acquisition_status NOT NULL DEFAULT 'open',

  -- Faltas no período (reduzem dias)
  absences_count  INT NOT NULL DEFAULT 0,
  base_days       INT NOT NULL DEFAULT 30,             -- 30, 24, 18 ou 12 conforme faltas
  consumed_days   INT NOT NULL DEFAULT 0,
  remaining_days  INT GENERATED ALWAYS AS (base_days - consumed_days) STORED,

  paid_double     BOOLEAN NOT NULL DEFAULT FALSE,      -- vencido sem programar
  paid_at         TIMESTAMPTZ,

  created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT now(),

  CONSTRAINT acq_dates_ordered CHECK (ends_at = starts_at + INTERVAL '1 year' - INTERVAL '1 day'),
  CONSTRAINT acq_concessivo_ordered CHECK (concessivo_ends_at = ends_at + INTERVAL '1 year'),
  CONSTRAINT acq_base_days_valid CHECK (base_days IN (12, 18, 24, 30)),
  CONSTRAINT acq_consumed_le_base CHECK (consumed_days <= base_days),
  UNIQUE (employee_id, starts_at)
);

CREATE INDEX idx_acq_tenant_employee ON vacation_acquisition_periods(tenant_id, employee_id);
CREATE INDEX idx_acq_status ON vacation_acquisition_periods(tenant_id, status) WHERE status IN ('completed', 'expired');
CREATE INDEX idx_acq_concessivo ON vacation_acquisition_periods(concessivo_ends_at) WHERE status = 'completed';

CREATE TABLE vacation_periods (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id       UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  acquisition_id  UUID NOT NULL REFERENCES vacation_acquisition_periods(id),
  employee_id     UUID NOT NULL REFERENCES app_users(id),

  starts_at       DATE NOT NULL,
  ends_at         DATE NOT NULL,
  days            INT GENERATED ALWAYS AS (ends_at - starts_at + 1) STORED,
  fraction_number INT NOT NULL DEFAULT 1,              -- 1, 2 ou 3 (fracionamento)

  bonus_days      INT NOT NULL DEFAULT 0,              -- abono pecuniário
  advance_13th    BOOLEAN NOT NULL DEFAULT FALSE,      -- adiantamento 1ª parcela 13º

  status          vacation_status NOT NULL DEFAULT 'planned',
  notified_at     TIMESTAMPTZ,                         -- aviso prévio formal
  approved_at     TIMESTAMPTZ,
  approved_by     UUID REFERENCES app_users(id),
  rejected_reason TEXT,

  created_by      UUID NOT NULL REFERENCES app_users(id),

  created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT now(),

  CONSTRAINT vp_dates_ordered CHECK (ends_at >= starts_at),
  CONSTRAINT vp_fraction_valid CHECK (fraction_number BETWEEN 1 AND 3),
  CONSTRAINT vp_bonus_valid CHECK (bonus_days BETWEEN 0 AND 10),
  CONSTRAINT vp_notice_30d CHECK (
    notified_at IS NULL OR starts_at >= (notified_at::DATE + INTERVAL '30 days')
  )
);

CREATE INDEX idx_vp_tenant_employee ON vacation_periods(tenant_id, employee_id, starts_at);
CREATE INDEX idx_vp_status ON vacation_periods(tenant_id, status);
CREATE INDEX idx_vp_acquisition ON vacation_periods(acquisition_id);
CREATE INDEX idx_vp_year_month ON vacation_periods(tenant_id, EXTRACT(YEAR FROM starts_at), EXTRACT(MONTH FROM starts_at));

-- Triggers
CREATE OR REPLACE FUNCTION vp_validate_total_days() RETURNS TRIGGER LANGUAGE plpgsql AS $$
DECLARE
  v_acq vacation_acquisition_periods;
  v_total_planned INT;
BEGIN
  SELECT * INTO v_acq FROM vacation_acquisition_periods WHERE id = NEW.acquisition_id;

  -- Soma dias planejados + dias deste novo período + bonus_days
  SELECT COALESCE(SUM(days), 0) + COALESCE(SUM(bonus_days), 0) INTO v_total_planned
    FROM vacation_periods
    WHERE acquisition_id = NEW.acquisition_id
      AND status IN ('planned', 'approved', 'in_progress', 'completed')
      AND id <> NEW.id;

  IF (v_total_planned + NEW.days + NEW.bonus_days) > v_acq.base_days THEN
    RAISE EXCEPTION 'vacation_exceeds_acquisition_balance'
      USING ERRCODE = '22023';
  END IF;

  -- Pelo menos 1 fração deve ter ≥ 14 dias
  IF NEW.fraction_number > 1 THEN
    IF NOT EXISTS (
      SELECT 1 FROM vacation_periods
      WHERE acquisition_id = NEW.acquisition_id
        AND days >= 14
        AND id <> NEW.id
    ) AND NEW.days < 14 THEN
      RAISE EXCEPTION 'fraction_requires_one_period_min_14d'
        USING ERRCODE = '22023';
    END IF;
  END IF;

  RETURN NEW;
END; $$;

CREATE TRIGGER trg_vp_validate
  BEFORE INSERT OR UPDATE ON vacation_periods
  FOR EACH ROW EXECUTE FUNCTION vp_validate_total_days();

-- Função: calcular base_days conforme faltas
CREATE OR REPLACE FUNCTION calc_vacation_days_after_absences(p_absences INT) RETURNS INT
LANGUAGE plpgsql IMMUTABLE AS $$
BEGIN
  -- CLT Art. 130
  IF p_absences <= 5 THEN RETURN 30;
  ELSIF p_absences <= 14 THEN RETURN 24;
  ELSIF p_absences <= 23 THEN RETURN 18;
  ELSIF p_absences <= 32 THEN RETURN 12;
  ELSE RETURN 0;  -- > 32 faltas: perde direito
  END IF;
END; $$;

-- View materializada para programação anual (refresh diário)
CREATE MATERIALIZED VIEW mv_vacation_planning_overview AS
SELECT
  vp.tenant_id,
  vp.employee_id,
  au.full_name,
  au.employer_unit_id,
  eu.legal_name AS employer_name,
  au.working_unit_id,
  wu.display_name AS working_name,
  au.department_id,
  d.display_name AS department_name,
  au.job_title,
  vp.id AS period_id,
  vp.acquisition_id,
  vp.starts_at,
  vp.ends_at,
  vp.days,
  vp.bonus_days,
  vp.fraction_number,
  vp.status,
  acq.base_days,
  acq.remaining_days,
  acq.concessivo_ends_at,
  CASE
    WHEN acq.concessivo_ends_at < CURRENT_DATE THEN 'expired_double'
    WHEN acq.concessivo_ends_at < CURRENT_DATE + INTERVAL '90 days' THEN 'expiring_soon'
    WHEN acq.remaining_days = acq.base_days THEN 'not_scheduled'
    ELSE 'on_track'
  END AS health
FROM vacation_periods vp
JOIN vacation_acquisition_periods acq ON acq.id = vp.acquisition_id
JOIN app_users au ON au.id = vp.employee_id
LEFT JOIN employer_units eu ON eu.id = au.employer_unit_id
LEFT JOIN working_units wu ON wu.id = au.working_unit_id
LEFT JOIN departments d ON d.id = au.department_id
WHERE au.active = TRUE;

CREATE INDEX idx_mv_vp_tenant ON mv_vacation_planning_overview(tenant_id);
CREATE INDEX idx_mv_vp_employer ON mv_vacation_planning_overview(employer_unit_id);
CREATE INDEX idx_mv_vp_year ON mv_vacation_planning_overview(EXTRACT(YEAR FROM starts_at));
```

---

## 4. RPCs principais

```sql
-- 1. Criar período aquisitivo (geralmente trigger automático no momento da admissão)
rpc_acquisition_create(p_employee_id, p_starts_at)
  -- valida: ainda não existe aquisitivo aberto para esse employee
  -- preenche ends_at = starts_at + 1y - 1d
  -- preenche concessivo_ends_at = ends_at + 1y

-- 2. Programar férias (com fracionamento)
rpc_vacation_plan_create(
  p_employee_id, p_acquisition_id,
  p_periods JSONB  -- [{starts_at, ends_at, bonus_days, advance_13th, fraction_number}]
)
  -- valida: caller é líder do employee OU é RH OU é o próprio (autoatendimento)
  -- valida: soma de days + bonus_days ≤ acq.base_days
  -- valida: pelo menos 1 fração ≥ 14d se fracionamento > 1
  -- valida: bonus_days total ≤ floor(base_days / 3)
  -- valida: aviso prévio ≥ 30d (starts_at >= now() + 30d)
  -- cria registros em vacation_periods com status='planned'
  -- notifica RH para aprovação

-- 3. Aprovar férias programadas
rpc_vacation_approve(p_period_id)
  -- exige: caller é RH OU é líder direto do employee
  -- atualiza status='approved'
  -- registra approved_at + approved_by

-- 4. Rejeitar
rpc_vacation_reject(p_period_id, p_reason)
  -- exige: caller é RH ou líder
  -- atualiza status='canceled'
  -- preserva rejected_reason

-- 5. Marcar em curso (job pg_cron diário)
rpc_vacation_mark_in_progress()
  -- UPDATE vacation_periods SET status='in_progress' WHERE status='approved' AND starts_at <= today

-- 6. Marcar concluído (job pg_cron diário)
rpc_vacation_mark_completed()
  -- UPDATE vacation_periods SET status='completed' WHERE status='in_progress' AND ends_at < today

-- 7. Detectar aquisitivos vencendo (job pg_cron diário)
rpc_acquisition_check_expiring()
  -- UPDATE vacation_acquisition_periods SET status='expired'
  --   WHERE concessivo_ends_at < today AND remaining_days > 0 AND status='completed'
  -- também marca paid_double=TRUE
  -- notifica RH

-- 8. Programação anual (alimentando a tela /ferias/programacao-anual)
rpc_vacation_annual_plan(p_year INT, p_employer_unit_id UUID DEFAULT NULL)
  -- retorna matriz colaborador × mês com cobertura visual
  -- respeita escopo do caller (RH vê tudo, líder vê só time, etc.)

-- 9. Buscar próximas férias do colaborador (alimentando /minha-jornada)
rpc_my_vacations(p_limit INT DEFAULT 10)

-- 10. Cancelar férias aprovadas
rpc_vacation_cancel(p_period_id, p_reason)
  -- exige aviso ≥ 7 dias antes de starts_at
  -- restaura consumed_days no aquisitivo
```

---

## 5. Páginas Next.js

### 5.1 `/ferias` (RH operacional)

Referência: [r2_people_ferias.html](../r2_people_ferias.html)

- 4 KPIs: aquisitivos vencendo 60d, em dobro, em curso, programados próximos 30d
- Toggle **Calendário Gantt** (8 meses) ↔ **Lista**
- Gantt: linha "HOJE" laranja, barras coloridas por status, scroll horizontal
- Lista: filtros por filial, status, mês
- Painel lateral sticky com abas: Aquisitivos abertos / Programações / Histórico
- Footer com botões Programar (abre wizard) / Exportar CSV

### 5.2 `/ferias/programacao-anual` (planejamento estratégico)

Referência: [r2_people_ferias_programacao_anual.html](../r2_people_ferias_programacao_anual.html)

- Toggle 3 personas: Líder / DP / Diretoria (escopo diferente cada uma)
- Scope banner contextual: "Você está vendo 23 colaboradores da sua equipe direta"
- 5 KPIs dinâmicos
- Filtros multi-select: Filial, Setor, Mês
- View 1 · **Tabela agrupada** por filial → setor com alertas (EM DOBRO, VENCE, Sem programação)
- View 2 · **Matriz anual** mês × colaborador (12 colunas)
- Botão "+ Programar férias" em cada linha (abre wizard contextualizado)

### 5.3 Modal · Wizard de programação

Já desenhada em [r2_people_ferias_programar.html](../r2_people_ferias_programar.html). Portar como `src/components/ferias/VacationWizardModal.tsx`:

- 3 passos: Datas + fracionamento / Abono + 13º / Confirmar
- Validações CLT inline (com mensagens explícitas)
- Calcula impacto financeiro em tempo real
- Submit chama `rpc_vacation_plan_create`

---

## 6. Testes · `supabase/tests/00430_m4_vacations.sql`

Meta: 35+ testes cobrindo:

1. Aquisitivo criado automaticamente na admissão
2. Aquisitivo vence sem programação → marca expired + paid_double
3. Fracionamento em 2 partes, uma com 14d → OK
4. Fracionamento em 2 partes, nenhuma ≥14d → falha
5. Fracionamento em 4 partes → falha
6. Soma de dias excede saldo → falha
7. Abono > 1/3 → falha
8. Aviso prévio < 30d → falha
9. Cálculo de base_days conforme faltas (testar 4 ranges)
10. Cross-tenant blocked
11. Colaborador autoprograma → OK
12. Líder programa para subordinado → OK
13. Outro líder programa para não-subordinado → falha
14. Aprovação por RH OK
15. Aprovação por outro líder (não direto) → falha
16. Cancel após started → falha (já em curso)
17. Cancel com < 7d aviso → falha
18. Job in_progress muda status
19. Job completed muda status
20. Job expiring marca em dobro + notifica
21. View materializada agrega corretamente
22. `rpc_my_vacations` respeita RLS (só vê próprias)
23. `rpc_vacation_annual_plan` líder vê só time
24. `rpc_vacation_annual_plan` RH vê tudo do tenant
25. Bonus_days correto após múltiplos períodos
26. Adiantamento 13º registrado mas não calculado nesta sessão (M6 calcula)
27. Audit log para create/approve/cancel
28-35: edge cases (estagiário < 12m, função terminada, etc.)

---

## 7. Critérios de aceitação

- [ ] Migration 00430 aplica idempotentemente
- [ ] 35+ testes passando
- [ ] View materializada refresca em < 2s para 1000 colaboradores
- [ ] Pelos 2 cenários reais GPC (Helena com aquisitivo vencendo 18/05/26, Juliana em dobro)
- [ ] 2 páginas Next.js + 1 componente modal
- [ ] Adapter em `src/lib/r2/vacations.ts`
- [ ] Sidebar nav-item "Férias"
- [ ] Doc da sessão em `docs/sessao_m4.md`

---

## 8. Pontos de atenção

- **Trigger automático de aquisitivo na admissão**: idealmente em hook do M1 ou no signup
- **Job pg_cron diário** essencial · sem ele status fica desatualizado
- **Adiantamento de 13º** registrado como flag · cálculo financeiro real fica na M6
- **Materialized view** refresh manual via `REFRESH MATERIALIZED VIEW CONCURRENTLY mv_vacation_planning_overview` · job às 6h
- **Importação de saldos** legados (do ERP) via `rpc_acquisition_import_legacy` com `consumed_days` preset · necessário pra migrar clientes que já têm histórico
- **Estagiários (< 12m)** não têm aquisitivo · validar no `rpc_acquisition_create`
- **Demissão antes do aquisitivo completar** gera férias proporcionais · cálculo em M2 (Movimentações)

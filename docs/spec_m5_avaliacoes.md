# Spec · M5 · Avaliações & Feedback (UI completa)

**Status:** pronto para execução em ambiente com Postgres 16
**Pré-requisitos:** schema A2 (9-Box) e schema H2 (recognition) já aplicados na codebase Next.js · M1 (Estrutura) aplicada
**Estimativa:** 1-2 sessões (~5-6h)

---

## 1. Objetivo

O backend de **avaliações** já está parcialmente implementado (9-Box · sessão A2 com 40/40 testes). Falta:
- **UI completa de ciclos** (CRUD de cycles, gestão de evaluations dentro do cycle)
- **Workflow de avaliação dual** (auto-avaliação + avaliação do gestor, com sincronização)
- **Validação cruzada** (RH valida se conjunto de avaliações está consistente antes de fechar cycle)
- **Tela de "Minhas avaliações"** (colaborador vê histórico próprio e ações pendentes)
- **Tela de "Avaliações a fazer"** (líder vê dashboard de quem ainda não avaliou)
- **Feedback contínuo** (solicitação e envio fora de ciclo formal)

| Tela origem | Página Next.js | Persona |
|---|---|---|
| `r2_people_ciclos.html` | `/admin/ciclos` | RH |
| `r2_people_avaliacao.html` | `/avaliacao/[evaluationId]` | Colaborador + Líder (mesma tela) |
| `r2_people_admin_dashboard.html` aba Avaliações | `/admin/avaliacoes` | RH |
| `r2_people_feedback_mural.html` | `/feedback` (componente, já existe parcial) | Todos |

---

## 2. Schema adicional · migration 00460_m5_schema_evaluations.sql

```sql
-- ENUMS
DO $$ BEGIN CREATE TYPE eval_phase AS ENUM (
  'self',         -- colaborador faz auto-avaliacao
  'manager',      -- lider avalia
  'calibration',  -- RH calibra (opcional)
  'closed'        -- fechada · imutavel
); EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN CREATE TYPE eval_status AS ENUM (
  'pending', 'in_progress', 'submitted', 'reviewed', 'finalized'
); EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- Ciclos (ja existem parcialmente em A2 · este estende)
ALTER TABLE evaluation_cycles
  ADD COLUMN IF NOT EXISTS current_phase eval_phase NOT NULL DEFAULT 'self',
  ADD COLUMN IF NOT EXISTS phase_self_starts DATE,
  ADD COLUMN IF NOT EXISTS phase_self_ends DATE,
  ADD COLUMN IF NOT EXISTS phase_manager_ends DATE,
  ADD COLUMN IF NOT EXISTS phase_calibration_ends DATE,
  ADD COLUMN IF NOT EXISTS require_calibration BOOLEAN NOT NULL DEFAULT FALSE;

-- Tabela principal · uma row por (cycle, employee)
CREATE TABLE IF NOT EXISTS evaluations (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id       UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  cycle_id        UUID NOT NULL REFERENCES evaluation_cycles(id) ON DELETE CASCADE,

  employee_id     UUID NOT NULL REFERENCES app_users(id),
  manager_id      UUID NOT NULL REFERENCES app_users(id),    -- snapshot · pode mudar durante ciclo

  -- Status separado por fase
  self_status     eval_status NOT NULL DEFAULT 'pending',
  manager_status  eval_status NOT NULL DEFAULT 'pending',
  calibration_status eval_status,                            -- opcional

  -- Submissoes
  self_submitted_at TIMESTAMPTZ,
  manager_submitted_at TIMESTAMPTZ,
  calibration_done_at TIMESTAMPTZ,

  -- Sentimento geral (1-5)
  self_overall    INT,
  manager_overall INT,
  final_overall   INT,                                       -- definido na calibracao ou = manager

  -- 9-Box final (vinculado ao snapshot do A2)
  final_box_row   INT,
  final_box_col   INT,
  final_box_label VARCHAR(60),

  -- Comentarios livres
  self_strengths  TEXT,
  self_to_develop TEXT,
  self_comment    TEXT,
  manager_strengths TEXT,
  manager_to_develop TEXT,
  manager_comment TEXT,
  calibration_notes TEXT,

  created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT now(),

  UNIQUE (cycle_id, employee_id),
  CONSTRAINT eval_overall_range CHECK (
    (self_overall IS NULL OR self_overall BETWEEN 1 AND 5) AND
    (manager_overall IS NULL OR manager_overall BETWEEN 1 AND 5) AND
    (final_overall IS NULL OR final_overall BETWEEN 1 AND 5)
  )
);

CREATE INDEX IF NOT EXISTS idx_evals_cycle_employee
  ON evaluations(cycle_id, employee_id);
CREATE INDEX IF NOT EXISTS idx_evals_manager_pending
  ON evaluations(manager_id, manager_status)
  WHERE manager_status IN ('pending', 'in_progress');

-- Itens da avaliacao (competencias) · 1:N com evaluations
CREATE TABLE IF NOT EXISTS evaluation_items (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  evaluation_id   UUID NOT NULL REFERENCES evaluations(id) ON DELETE CASCADE,

  competency_code VARCHAR(80) NOT NULL,                    -- 'tecnica', 'colaboracao', etc.
  competency_name VARCHAR(160) NOT NULL,

  self_score      INT,                                     -- 1-5
  manager_score   INT,
  final_score     INT,

  self_comment    TEXT,
  manager_comment TEXT,

  display_order   INT NOT NULL DEFAULT 0,

  CONSTRAINT item_scores_range CHECK (
    (self_score IS NULL OR self_score BETWEEN 1 AND 5) AND
    (manager_score IS NULL OR manager_score BETWEEN 1 AND 5)
  )
);

-- Catalogo de competencias (configurado por tenant)
CREATE TABLE IF NOT EXISTS competencies (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id       UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  code            VARCHAR(80) NOT NULL,
  display_name    VARCHAR(160) NOT NULL,
  description     TEXT,
  category        VARCHAR(60),                             -- 'tecnica', 'comportamental', 'lideranca'
  applies_to_levels TEXT[],                                -- ex: ['lideranca'] · NULL = todos
  display_order   INT NOT NULL DEFAULT 0,
  active          BOOLEAN NOT NULL DEFAULT TRUE,
  UNIQUE (tenant_id, code)
);
```

---

## 3. RPCs

```sql
-- 1. Criar ciclo
rpc_eval_cycle_create(p_name, p_starts_at, p_ends_at, p_target_role_filter, p_require_calibration)

-- 2. Iniciar ciclo · cria evaluations pra todos os colaboradores elegiveis
rpc_eval_cycle_start(p_cycle_id)
  -- gera evaluations + evaluation_items (a partir de competencies catalogo)
  -- notifica colaboradores ('voce tem auto-avaliacao pendente')
  -- notifica lideres ('voce tem N avaliacoes pra fazer')

-- 3. Salvar auto-avaliacao (parcial · draft)
rpc_eval_self_save(p_eval_id, p_items JSONB, p_strengths, p_to_develop, p_comment, p_overall)
  -- valida: caller = employee_id
  -- status = 'in_progress' enquanto salva, 'submitted' quando self_submitted_at preenchido

-- 4. Submeter auto-avaliacao (final)
rpc_eval_self_submit(p_eval_id)
  -- valida: todos os items tem self_score, comentarios obrigatorios preenchidos
  -- status = 'submitted', preenche self_submitted_at
  -- notifica lider

-- 5. Salvar/submeter avaliacao do lider (analogo · ja pode ver self)
rpc_eval_manager_save(...)
rpc_eval_manager_submit(p_eval_id, p_final_box_row, p_final_box_col)
  -- valida: caller = manager_id da row
  -- valida: self ja foi submetido (manager ve auto-avaliacao primeiro)
  -- atualiza 9-Box snapshot

-- 6. Calibracao (RH revisa em lote, ajusta 9-Box se necessario)
rpc_eval_calibration_save(p_eval_id, p_final_overall, p_final_box_row, p_final_box_col, p_notes)
  -- exige permission 'calibrate_evaluations'
  -- log auditavel obrigatorio

-- 7. Finalizar (fecha ciclo)
rpc_eval_cycle_close(p_cycle_id)
  -- valida: todas evaluations foram pelo menos manager_submitted
  -- congela tudo (status='finalized', UPDATE bloqueado via RLS)
  -- gera 9-Box snapshot final no schema A2
  -- notifica colaboradores ('sua avaliacao foi finalizada')

-- 8. Dashboard: avaliacoes do lider (pendentes pra ele)
rpc_eval_my_pending_evaluations()
  -- retorna {pending_self, pending_manager} pro caller

-- 9. Historico do colaborador
rpc_eval_my_history(p_limit)
  -- retorna evaluations onde employee_id = caller · ordenado por cycle.ends_at DESC
```

---

## 4. Páginas Next.js

### 4.1 `/admin/ciclos` (RH)
Referência: [r2_people_ciclos.html](../r2_people_ciclos.html)

- Timeline 4 fases (Setup → Auto → Gestor → Calibração → Fechado)
- Lista de ciclos com status pill
- Modal "Novo ciclo" com config de fases, target roles, escala (3x3 ou 5x5)
- Bulk actions: "Iniciar ciclo", "Reabrir fase", "Forçar fechamento"

### 4.2 `/avaliacao/[id]` (dual)
Referência: [r2_people_avaliacao.html](../r2_people_avaliacao.html)

- Detecta automaticamente se caller é employee ou manager
- Modo SELF: cards de competências com slider 1-5 + comentário inline
- Modo MANAGER: vê auto-avaliação ao lado, faz a sua
- Autosave 700ms
- Botão "Submeter" valida completude
- 9-Box final (só modo MANAGER) · grade visual pra arrastar/clicar

### 4.3 `/admin/avaliacoes` (RH)
- Dashboard agregado por cycle ativo
- KPIs: % completude self, % completude manager, distribuição 9-Box
- Drill: lista de evaluations com status
- Calibration mode: tabela com final_box editável + nota da decisão
- Export CSV completo

### 4.4 `/minhas-avaliacoes`
- Histórico pessoal
- Card destacado: ação pendente atual ("Termine sua auto-avaliação até 20/jun")
- Lista de ciclos anteriores com link pra ver detalhe

---

## 5. Testes · `supabase/tests/00460_m5_evaluations.sql`

Meta: 35+ testes:

1. Criar ciclo + iniciar gera evaluations corretas
2. Self submit OK
3. Self submit incompleto bloqueado
4. Manager não pode submit antes de self
5. Manager submit OK gera 9-Box snapshot
6. Calibração ajusta final_box (não toca self/manager scores)
7. Close cycle bloqueia UPDATE em evaluations
8. Cross-tenant blocked
9. Eval_item scores validos (1-5)
10. RPC eval_my_pending retorna contagens corretas
11. Trocar manager_id mid-cycle preserva manager_id da row evaluation
12. Notificações disparadas em cada transição
13. Audit log de calibration_save obrigatório
14-35: edge cases (colab demitido durante ciclo, lider mudou de tenant, etc.)

---

## 6. Critérios de aceitação

- [ ] Migration 00460 aplica idempotentemente
- [ ] 35+ testes passando
- [ ] 4 páginas Next.js funcionais
- [ ] Adapter em `src/lib/r2/evaluations.ts`
- [ ] Sidebar nav-items: "Ciclos" (RH), "Minhas avaliações" (todos), "Avaliações a fazer" (líder)
- [ ] Notificações disparam em cada transição (start cycle, self submit, manager assign, finalize)
- [ ] Doc da sessão em `docs/sessao_m5.md`

---

## 7. Pontos de atenção

- **Snapshot manager_id**: ao criar evaluation, capturar manager_id de app_users naquele momento · não muda mesmo se trocar gestor durante ciclo
- **Calibração opcional**: se `require_calibration=FALSE`, manager_submit já finaliza
- **Reabrir fase**: cuidado · permite só se ciclo não fechado, log obrigatório
- **Escala 3x3 vs 5x5**: definida no cycle, evaluations herdam · final_box_row/col validados pela CHECK
- **Trocar competências catalogo mid-cycle**: bloqueado (evaluation_items já criadas continuam com snapshot)
- **Colaborador demitido durante ciclo**: marcar evaluation como `closed` automaticamente sem requerer manager_submit

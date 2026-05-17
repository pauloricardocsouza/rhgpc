# Spec · M2 · Movimentações

**Status:** pronto para execução em ambiente com Postgres 16
**Pré-requisitos:** M1 (Estrutura) aplicado · M3 (Atestados) opcional para FK `auto_movement_id`
**Estimativa:** 1 sessão (~4-5h)

---

## 1. Objetivo

Portar para Next.js o módulo de Movimentações de RH. Substitui formulários em Word/papel por workflow estruturado com aprovação RH e notificação ao colaborador.

| Tela origem | Página Next.js | Persona |
|---|---|---|
| [r2_people_movimentacoes.html](../r2_people_movimentacoes.html) | `/movimentacoes` | Líder (João) |
| [r2_people_aprovacoes_rh.html](../r2_people_aprovacoes_rh.html) | `/admin/movimentacoes` | RH (Patrícia) |
| [r2_people_colaborador_movimentacoes.html](../r2_people_colaborador_movimentacoes.html) | `/minha-jornada/movimentacoes` | Colaborador (Fernanda) |

---

## 2. Tipos de movimentação

```sql
CREATE TYPE movement_kind AS ENUM (
  'promotion',                -- promoção (mudança de cargo + salário)
  'salary_adjustment',        -- aumento sem mudar cargo
  'salary_adjustment_collective_bargain', -- reajuste dissídio (massa)
  'transfer_unit',            -- mudança de filial/working_unit
  'transfer_department',      -- mudança de departamento
  'transfer_manager',         -- mudança de gestor direto
  'role_change',              -- mudança de cargo sem mudar salário (raro)
  'admission',                -- admissão (criada na importação)
  'termination',              -- desligamento
  'leave_medical',            -- afastamento por enfermidade (gerado de atestado ≥3d)
  'leave_maternity',          -- licença maternidade
  'leave_paternity',          -- licença paternidade
  'leave_other'               -- outros afastamentos
);

CREATE TYPE movement_status AS ENUM (
  'draft',                    -- líder ainda preenchendo
  'pending_rh',               -- aguardando aprovação RH
  'approved',                 -- aprovado, aguarda data efetiva
  'effective',                -- aplicado (data efetiva chegou)
  'rejected',                 -- rejeitado por RH
  'canceled'                  -- cancelado antes de aprovar
);
```

---

## 3. Schema · migration 00450_m2_schema_movements.sql

```sql
CREATE TABLE movements (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id       UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  protocol        VARCHAR(40) NOT NULL,                -- 'MOV-2026-0517-AB12C'

  employee_id     UUID NOT NULL REFERENCES app_users(id),
  kind            movement_kind NOT NULL,
  status          movement_status NOT NULL DEFAULT 'draft',

  -- Snapshot do estado anterior (preenchido ao criar)
  before_data     JSONB NOT NULL,
  -- Estado proposto
  after_data      JSONB NOT NULL,

  -- Datas
  effective_date  DATE,                                -- quando entra em vigor
  notice_days     INT,                                 -- dias de aviso prévio (Art. 135 férias, etc.)

  -- Workflow
  requested_by    UUID NOT NULL REFERENCES app_users(id),
  requested_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
  approved_by     UUID REFERENCES app_users(id),
  approved_at     TIMESTAMPTZ,
  rejected_reason TEXT,

  -- Justificativa do líder
  justification   TEXT NOT NULL,
  rh_notes        TEXT,                                -- comentário do RH no momento da aprovação

  -- Vinculação com origem automática (atestado, dissídio, etc.)
  source_kind     VARCHAR(40),                        -- 'medical_certificate', 'collective_bargain_import', 'manual'
  source_id       UUID,                                -- FK lógica (atestado, etc.)

  created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT now(),

  UNIQUE (tenant_id, protocol)
);

CREATE INDEX idx_mov_tenant_employee ON movements(tenant_id, employee_id, requested_at DESC);
CREATE INDEX idx_mov_status ON movements(tenant_id, status) WHERE status IN ('draft', 'pending_rh');
CREATE INDEX idx_mov_requester ON movements(requested_by);

-- Trigger de protocolo (mesmo padrão de M3)
CREATE OR REPLACE FUNCTION mov_generate_protocol() RETURNS TRIGGER LANGUAGE plpgsql AS $$
DECLARE v_suffix TEXT;
BEGIN
  IF NEW.protocol IS NULL OR NEW.protocol = '' THEN
    v_suffix := upper(substr(encode(gen_random_bytes(3), 'hex'), 1, 5));
    NEW.protocol := 'MOV-' || to_char(now(), 'YYYY-MM-DD') || '-' || v_suffix;
  END IF;
  RETURN NEW;
END; $$;

CREATE TRIGGER trg_mov_protocol BEFORE INSERT ON movements
  FOR EACH ROW EXECUTE FUNCTION mov_generate_protocol();

-- FK atrasada em medical_certificates (M3)
ALTER TABLE medical_certificates
  ADD CONSTRAINT fk_mc_movement
  FOREIGN KEY (auto_movement_id) REFERENCES movements(id) DEFERRABLE;
```

---

## 4. RPCs principais

```sql
-- 1. Criar movimento (líder solicita)
rpc_movement_create(
  p_employee_id UUID,
  p_kind movement_kind,
  p_after_data JSONB,       -- {new_salary, new_role_id, new_unit_id, new_manager_id, etc.}
  p_effective_date DATE,
  p_justification TEXT,
  p_notice_days INT DEFAULT NULL
)
  -- valida: caller é líder direto OU RH
  -- valida: after_data tem os campos necessários para o kind
  -- valida: effective_date >= today + notice_days
  -- snapshot before_data automaticamente do estado atual de app_users
  -- status = 'pending_rh' (líder) ou 'approved' (RH) ou 'draft' (se p_finalize=false)

-- 2. Aprovar movimento (RH)
rpc_movement_approve(p_movement_id UUID, p_rh_notes TEXT DEFAULT NULL)
  -- exige: caller é RH OU diretoria
  -- valida: status='pending_rh'
  -- valida orçamento se kind in ('promotion', 'salary_adjustment')
  -- atualiza status='approved'
  -- agenda aplicação para effective_date (via cron ou imediato se data passada)

-- 3. Rejeitar
rpc_movement_reject(p_movement_id UUID, p_reason TEXT)

-- 4. Aplicar (cron diário ou imediato)
rpc_movement_apply(p_movement_id UUID)
  -- atualiza app_users com after_data
  -- registra histórico em audit_log
  -- status='effective'
  -- notifica colaborador

-- 5. Listar pendentes (RH)
rpc_movements_pending_queue()

-- 6. Histórico do colaborador (alimenta /minha-jornada)
rpc_my_movements(p_limit INT DEFAULT 20)
  -- retorna movimentos onde employee_id = caller
  -- inclui draft? NÃO (líder ainda preenchendo, colaborador não deve ver)
  -- inclui pending_rh? SIM (transparência: "promoção em análise")

-- 7. Importação em massa (dissídio coletivo)
rpc_movement_bulk_import(p_csv TEXT, p_kind movement_kind, p_justification TEXT)
  -- parse CSV (matricula, novo_salario ou outros campos)
  -- cria movements em batch com status='approved' (já validado por contador externo)
  -- agenda apply em massa para effective_date

-- 8. Estatísticas para dashboard
rpc_movements_stats(p_year INT, p_month INT)
  -- agregação: count por kind, valor total de aumentos, headcount delta
```

---

## 5. Páginas Next.js

### 5.1 `/movimentacoes` (líder)

Referência: [r2_people_movimentacoes.html](../r2_people_movimentacoes.html)

- Lista de movimentações do time (criadas pelo próprio líder)
- Filtros: status, kind, mês
- Botão "+ Solicitar movimentação" abre wizard 4 passos:
  1. Selecionar colaborador (autocomplete do próprio time)
  2. Tipo de movimentação (radio cards)
  3. Detalhes específicos (form dinâmico conforme kind)
  4. Justificativa + revisar + enviar

### 5.2 `/admin/movimentacoes` (RH)

Referência: [r2_people_aprovacoes_rh.html](../r2_people_aprovacoes_rh.html)

- 4 abas: Pendentes / Aprovadas / Rejeitadas / Auditoria
- Tabela com filtros (kind, líder solicitante, unidade)
- Cada linha tem drill: ver before/after diff, justificativa do líder
- Modal de aprovação com:
  - Resumo do impacto
  - Validação de orçamento (se promoção)
  - Campo de comentário RH
  - Botões Aprovar / Rejeitar (rejeitar pede motivo)

### 5.3 `/minha-jornada/movimentacoes` (colaborador)

Referência: [r2_people_colaborador_movimentacoes.html](../r2_people_colaborador_movimentacoes.html)

- Banner LGPD Art. 18 (direito de transparência)
- Cards de movimentações ordenados por data
- Status visual: pendente (cinza), aprovada (verde), rejeitada (vermelho), efetivada (azul)
- Para cada: kind, antes → depois, data efetiva, quem solicitou, justificativa (se rejeitada, motivo)
- Workflow 5 passos visualizado: solicitada → análise RH → aprovada → aguarda data → efetivada

---

## 6. Testes · `supabase/tests/00450_m2_movements.sql`

Meta: 30+ testes:

1. Líder cria movimento de promoção para subordinado → OK
2. Líder cria para não-subordinado → falha (permission_denied)
3. Colaborador cria movimento → falha (não pode auto-promover)
4. RH cria movimento direto → OK e já vai pra approved
5. Aviso prévio < notice_days → falha
6. RH aprova movimento → status='approved'
7. RH rejeita sem motivo → falha
8. RH rejeita com motivo → status='rejected'
9. Cron apply efetiva movimento na data → app_users atualizado
10. Promoção com salário fora da faixa job_role → warning (não bloqueia)
11. Atestado ≥3d gera movement automático
12. Bulk import dissídio cria N movements
13. Cross-tenant blocked
14. Histórico do colaborador inclui pending_rh
15. Histórico do colaborador NÃO inclui draft
16. Audit log registra cada transição de status
17-30: edge cases

---

## 7. Critérios de aceitação

- [ ] Migration 00450 aplica idempotentemente
- [ ] 30+ testes passando
- [ ] FK `medical_certificates.auto_movement_id` populada
- [ ] 3 páginas Next.js + componentes
- [ ] Adapter em `src/lib/r2/movements.ts`
- [ ] Wizard 4 passos funcional com validação inline
- [ ] Notificação automática ao colaborador em cada transição
- [ ] Sidebar nav-items (RH, líder, colaborador)
- [ ] Doc da sessão em `docs/sessao_m2.md`

---

## 8. Pontos de atenção

- **`before_data` deve ser snapshot literal**: copia dos campos relevantes de `app_users` no momento da criação, não FK · permite ver o estado anterior mesmo se app_users mudar depois
- **Aplicação na data efetiva**: cron diário OU aplicação imediata se `effective_date <= today` no momento da aprovação
- **Bulk import dissídio**: gerar UM audit log com `before_data` e `after_data` agregados, mais N audit_logs individuais (pesado mas auditável)
- **Validação de orçamento** (promoção): integrar com M6 (Folha & Custo) para mostrar impacto na folha · alerta se ultrapassa salary_max do job_role
- **Cancelamento**: só permite antes de `status='effective'` · depois de efetivado, criar **novo movimento reverso** (transparência)
- **Demissão (`termination`)**: trigger pode marcar `app_users.terminated_at` e `active=FALSE` no apply
- **Promoção com mudança de manager**: gera `movement.kind='transfer_manager'` adicional ou inclui no after_data?
  - Decisão: incluir no after_data se for parte da mesma movimentação (atomicidade)
- **Notice_days** padrão: 0 (imediato) para `salary_adjustment`, 30 para férias (M4 usa schema próprio), 1 (próximo dia) para mudanças administrativas

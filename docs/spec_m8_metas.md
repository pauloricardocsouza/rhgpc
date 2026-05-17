# Spec · M8 · Metas (backend completo)

**Status:** schema v5 já desenhado em `r2_people_schema_metas_v5.sql` · falta portar pra migration + RPCs + UI completas
**Pré-requisitos:** M1 aplicado, integração com OKRs (M7 já tem)
**Estimativa:** 1-2 sessões (~5-6h)

---

## 1. Objetivo

Diferente de **OKRs** (já implementado · qualitativo, aspiracional), **Metas** são **quantitativas e remuneradoras**:
- Cada meta tem indicadores numéricos com peso
- Realização gera **payout em R$** segundo regras configuráveis
- Workflow: RH cadastra → Líder lança realizado → Gestor valida → RH calcula payout
- Vinculação opcional com **PLR / bônus variável**

| Tela origem | Página Next.js | Persona |
|---|---|---|
| `r2_people_metas.html` | `/admin/metas` | RH |
| `r2_people_minhas_metas.html` | `/minhas-metas` | Colaborador |
| `r2_people_lancamento_resultado.html` | `/metas/lancar/[id]` | Líder |
| `r2_people_validacao_resultado.html` | `/metas/validar/[id]` | Gestor sênior + RH |

---

## 2. Schema · portar do `r2_people_schema_metas_v5.sql`

Schema já existe (36 KB · 4 tabelas + 7 enums + 12 RLS + 3 RPCs + 2 views).

Migration a criar: `00470_m8_schema_metas.sql` portando v5 + ajustes:

```sql
-- Já no schema v5 (validar e portar):
-- goals · cabeçalho da meta
-- goal_indicators · indicadores numéricos com peso
-- goal_payout_rules · regras de payout (degrau, linear, etc.)
-- goal_payout_calculations · cálculos resolvidos por período

-- Enums já definidos:
-- goal_kind: 'individual', 'time', 'corporate', 'cascade'
-- goal_period: 'monthly', 'quarterly', 'yearly', 'campaign'
-- payout_kind: 'linear', 'degrau', 'multiplicador'
-- payout_status: 'pending', 'calculated', 'approved', 'paid', 'cancelled'
-- result_status: 'awaiting', 'submitted', 'validated', 'rejected'

-- RPCs já no schema v5:
-- rpc_calculate_payouts(p_goal_id, p_period)
-- rpc_finalize_validation(p_goal_id, p_validator_id)
-- rpc_clone_from_previous(p_goal_id, p_target_period)
```

Ajustes adicionais:

```sql
-- Conectar com OKRs (M7) opcionalmente
ALTER TABLE goals
  ADD COLUMN IF NOT EXISTS okr_objective_id UUID REFERENCES okr_objectives(id);

-- Conectar com cargo/job_role (M1) opcionalmente
ALTER TABLE goals
  ADD COLUMN IF NOT EXISTS applies_to_job_role_id UUID REFERENCES job_roles(id);

-- Trigger pra detectar metas vencidas sem lançamento
-- (preenche result_status='awaiting' -> 'late' automaticamente)
```

---

## 3. Fluxo ponta a ponta · campanha de vendas

### Configuração (RH)

1. Patrícia cria meta "Campanha Natal 2026 · Cestão L1"
2. Tipo: campaign · período: 01/dez/26 a 25/dez/26
3. Aplica a todos colaboradores do working_unit 'Cestão L1' com cargo 'Operador de Caixa'
4. Indicadores:
   - Vendas individuais: peso 60% · meta R$ 50k · payout até R$ 1.500
   - NPS atendimento: peso 40% · meta 9.0 · payout até R$ 1.000
5. Regra de payout: degrau · 0-50% = 0, 50-80% = 50% do payout, 80-100% = 80%, 100%+ = 100%, 110%+ = 110% (acelerador)

### Execução

Diariamente:
- Sistema importa dados de venda via integração (ou manual via líder)
- Indicador "Vendas" se atualiza automaticamente

No fim do período (26/dez):
- Líder de cada caixa abre `/metas/lancar/[campanha-natal]`
- Vê os indicadores pré-preenchidos
- Lança valores finais (caso queira ajustar com base em ocorrências)
- Submete pra validação

### Validação

Gerente regional abre `/metas/validar/[campanha-natal]`:
- Lista cards de cada colaborador com:
  - Valor lançado vs meta
  - % atingimento
  - Payout calculado preview
- Aprova individualmente ou em lote
- Pode rejeitar (volta pra líder corrigir)

### Cálculo e pagamento

Patrícia abre `/admin/metas/[campanha-natal]/payouts`:
- Vê tabela com todos colaboradores e payouts
- Aprova lote · status = `approved`
- Export CSV pra folha integrar
- Após pagamento, marca como `paid`

---

## 4. RPCs adicionais

```sql
-- Workflow específico (além das já no schema v5)

-- 1. Lançar resultado (líder)
rpc_goal_result_submit(p_goal_id, p_employee_id, p_indicators JSONB)
  -- indicators: [{indicator_code, value}, ...]
  -- valida: caller é líder direto do employee
  -- valida: período aberto
  -- atualiza result_status = 'submitted'

-- 2. Aprovar lote (gestor)
rpc_goal_result_approve_batch(p_goal_id, p_employee_ids UUID[])
  -- exige permission 'approve_goal_results' (geralmente gerente regional)
  -- transição submitted -> validated

-- 3. Rejeitar com motivo
rpc_goal_result_reject(p_goal_id, p_employee_id, p_reason)
  -- volta pra submitted=false, líder pode editar

-- 4. Forçar recálculo (RH · se ajustou regra)
rpc_goal_recalculate_all(p_goal_id)
  -- exige permission 'manage_goals'
  -- audit log obrigatório

-- 5. Export CSV pra folha
rpc_goal_export_payouts(p_goal_id, p_status='approved')
  -- retorna JSON estruturado pronto pra serializar CSV
  -- inclui matricula externa (app_user_external_ids)

-- 6. Histórico do colaborador
rpc_my_goals(p_limit, p_period=NULL)
  -- retorna goals onde caller esteve elegível + payouts recebidos
```

---

## 5. Páginas Next.js

### 5.1 `/admin/metas` (RH)
- KPIs: metas ativas, R$ provisionado, R$ pago, % atingimento médio
- Tabs: Ativas / Encerradas / Rascunhos
- Tabela com filtros (período, tipo, escopo)
- Botão "+ Nova meta" abre wizard 5 passos:
  1. Tipo (individual/time/corporativa/cascateada)
  2. Período + escopo (quem está elegível)
  3. Indicadores (até 5) com pesos
  4. Regra de payout (degrau, linear, multiplicador)
  5. Revisar e ativar

### 5.2 `/minhas-metas` (Colaborador)
- Cards de metas vigentes com progress
- Indicadores em barra com valor atual vs meta
- Payout estimado em tempo real
- Histórico de campanhas anteriores com payouts recebidos

### 5.3 `/metas/lancar/[id]` (Líder)
- Lista de colaboradores elegíveis da equipe
- Por linha: inputs pra cada indicador
- Submissão em lote
- Aviso se passou do prazo

### 5.4 `/metas/validar/[id]` (Gestor sênior)
- Lista de pendências de validação
- Botões "Aprovar / Rejeitar / Solicitar revisão"
- Vista comparativa: valor histórico vs lançado

---

## 6. Testes · `supabase/tests/00470_m8_metas.sql`

Meta: 30+ testes:

1. Criar goal individual + indicators
2. Calcular payout linear · cenário 50%, 100%, 150%
3. Calcular payout degrau · 4 degraus
4. Validar (gestor) move status pra 'validated'
5. Rejeitar volta status pra 'submitted=false'
6. Recálculo pós-mudança de regra mantém histórico
7. Audit log de aprovação obrigatório
8. RH calcula payouts em massa OK
9. Cross-tenant blocked
10. Colab fora do escopo do goal não aparece
11. Líder fora do escopo bloqueado em rpc_goal_result_submit
12. Goal vencida sem lançamento marca como 'late' automaticamente
13. Goal vinculada a OKR sincroniza progresso (opcional)
14-30: edge cases

---

## 7. Critérios de aceitação

- [ ] Migration 00470 aplica idempotentemente
- [ ] 30+ testes passando
- [ ] 4 páginas Next.js funcionais
- [ ] Wizard de criação completo
- [ ] Export CSV/XLSX pra folha
- [ ] Adapter `src/lib/r2/goals.ts`
- [ ] Doc da sessão em `docs/sessao_m8.md`

---

## 8. Pontos de atenção

- **Payout cap**: definir teto absoluto por colaborador (ex: máx R$ 5k por campanha) pra evitar erro de configuração
- **Reabertura de período**: bloqueado se já foi `paid`. Senão, possível com audit log
- **Migração de dados legados**: muitas empresas tem histórico em planilha · spec separada de import
- **Integração com folha**: por enquanto export CSV manual · roadmap futuro webhook
- **PLR vs bônus individual**: usar campo `kind` pra distinguir e aplicar regras fiscais diferentes
- **Goals em cascata**: trigger atualiza progresso do parent quando children mudam

# Spec C2 · Customer Success Playbook · Kick-off → Health → Expansão

**Status**: especificação · pré-implementação
**Versão**: 1.0 · 17 de maio de 2026
**Escopo**: jornada pós-contrato, health score, intervenções, expansão de receita, churn prevention, renovação
**Depende de**: spec C1 (sales playbook), spec M13 (onboarding wizard), schema v12 (billing/quotas)

---

## 1. Por que CS existe (1 frase)

> Vender é metade do trabalho. R2 People só atinge a meta de NRR > 105 % se cada tenant **enxergar valor mensurável em 30 dias, virar advocate em 90, e expandir em 12 meses**. Sem CS proativo, churn de PME brasileira é histórico 20 % a.a — com CS, meta é 8 %.

---

## 2. Estrutura do time de CS

### 2.1 Funções e contratação progressiva

| Função | Quando | Carteira | Foco |
|---|---|---|---|
| **CS founder-led** | mês 1-9 | 1-15 tenants | Tudo: kick-off, suporte, expansão, renovação |
| **CS Manager pleno** | mês 9 | 30-40 tenants ativos | Pro tier (R$ 599-2.499 MRR) |
| **Onboarding Specialist** | mês 12 | 100% dos novos kick-offs | Setup técnico + ramp-up semana 1 |
| **CS Enterprise** | mês 15 | 5-10 contas Enterprise | QBR formal, expansão, advocacy |
| **Suporte L1** | mês 18 | tickets entrantes | Triagem, FAQ, escalation |

### 2.2 Ratio target

- **Pro tier**: 1 CSM para cada 30-40 tenants
- **Enterprise**: 1 CSM para cada 5-10 tenants
- **Starter**: tech-touch (e-mail automatizado + self-service KB)

---

## 3. Jornada do cliente (timeline visual)

```
D-7  ┐ CONTRATO assinado
     │ ↓ welcome email automático
D+0  ├─ KICK-OFF call 60min · plano 30/60/90 apresentado
D+1  │ ↓ wizard M13 começa (assistido)
D+7  ├─ SETUP TÉCNICO completo · primeiros eventos
     │ ↓ training 1h líderes
D+30 ├─ ADOÇÃO INICIAL · health score primeiro
     │ ↓ ajustes finos, módulos extras habilitados
D+60 ├─ HEALTH CHECK formal · 1:1 c/ champion
     │ ↓ rollout módulos avançados (OKRs, PDI)
D+90 ├─ QBR · primeira revisão executiva · upsell sondado
     │ ↓
D+180├─ EXPANSÃO ou RENOVAÇÃO · upgrade plan, +seats, add-ons
     │ ↓
D+365├─ RENOVAÇÃO ANUAL · advocate ou churn?
```

---

## 4. Health Score (0-100)

Cada tenant tem um **health score** recalculado semanalmente. Workflow CS prioriza por score.

### 4.1 Componentes (peso)

| Sinal | Peso | Como medir | Verde / Amarelo / Vermelho |
|---|---|---|---|
| **Uso ativo** | 25 | DAU/MAU últimos 30d | > 30% / 15-30% / < 15% |
| **Adoção de módulos** | 20 | módulos ativados / módulos do plano | > 75% / 40-75% / < 40% |
| **Adoção de líderes** | 15 | % de líderes que abriram 1:1 ou avaliação último mês | > 70% / 40-70% / < 40% |
| **Stickiness** | 10 | DAU/MAU ratio | > 0.3 / 0.15-0.3 / < 0.15 |
| **Crescimento de seats** | 10 | Δ seats últimos 90d | > +5% / 0 a +5% / negativo |
| **Tickets de suporte** | 10 | volume últimos 30d (inverso) | < 3 / 3-8 / > 8 |
| **NPS último** | 5 | promotor (9-10) / passivo (7-8) / detrator (0-6) | promotor / passivo / detrator |
| **Pagamento em dia** | 5 | dias em atraso na última fatura | 0 / 1-7 / > 7 |

### 4.2 Cálculo

```
score = (uso × 0.25 + adoção × 0.20 + líderes × 0.15 + sticky × 0.10
       + seats × 0.10 + tickets × 0.10 + nps × 0.05 + payment × 0.05) × 100
```

Cada componente normaliza para 0-1 (verde=1, amarelo=0.5, vermelho=0).

### 4.3 Categorização

| Faixa | Categoria | Ação CS |
|---|---|---|
| 80-100 | **Champion** | Pedir referral, sondar upsell, convidar pra case |
| 60-79 | **Saudável** | Check-in trimestral, monitoring |
| 40-59 | **Atenção** | 1:1 mensal, plano de adoção customizado |
| 20-39 | **Risco** | War room semanal, escalation para CS Manager |
| 0-19 | **Crítico** | Save plan emergencial · executivo R2 entra na conversa |

### 4.4 Tabela `tenant_health`

```sql
CREATE TABLE IF NOT EXISTS tenant_health (
  tenant_id          uuid PRIMARY KEY REFERENCES tenants(id) ON DELETE CASCADE,
  score              numeric NOT NULL CHECK (score BETWEEN 0 AND 100),
  category           text NOT NULL CHECK (category IN ('champion','healthy','attention','risk','critical')),
  components         jsonb NOT NULL,           -- { uso: 0.8, adocao: 0.7, ... }
  trend              text CHECK (trend IN ('up','flat','down')),
  last_calculated_at timestamptz NOT NULL DEFAULT now(),
  csm_assigned_id    uuid REFERENCES auth.users(id),
  next_intervention_at timestamptz,
  notes              text
);

CREATE INDEX idx_health_risk
  ON tenant_health (score)
  WHERE category IN ('risk','critical');
```

Job semanal `rpc_calculate_tenant_health()` roda toda madrugada de segunda.

---

## 5. Plano 30/60/90 detalhado

### 5.1 Dias 1-7 · Setup técnico (Onboarding Specialist lead)

| Dia | Ação | Responsável | Output |
|---|---|---|---|
| D+0 | Kick-off call 60min | CSM + Champion + 1-2 admins | Plano 30/60/90 enviado por e-mail |
| D+1 | Wizard M13 acompanhado (Zoom) | OS + Champion | Tenant ativo, 1 admin MFA setado |
| D+2-3 | Importação CSV de colaboradores | OS + RH cliente | 80%+ dos employees no sistema |
| D+4 | Treinamento ao admin (1h gravada) | OS | Vídeo disponível na KB do cliente |
| D+5 | Configuração primeira política | OS + Champion | RLS papel×permissão definida |
| D+7 | Health check inicial | CSM | Health score primeiro · banner cliente |

**Meta D+7**: 100% setup, 60%+ colaboradores cadastrados, 1 admin treinado, primeira movement.created.

### 5.2 Dias 8-30 · Rollout interno (CSM lead)

- **Semana 2**: webinar de 30min para líderes do cliente (CSM facilita, gravado, disponibilizado interno)
- **Semana 3**: 1:1 CSM ↔ champion (15min) — quais líderes estão usando, quais resistem
- **Semana 4**: ajuste fino — habilitar/desabilitar módulos baseado em adoção real

**KPIs vivos (dashboard cliente)**:
- % de colaboradores ativados (login ≥ 1x)
- Primeira movimentação criada
- Primeira avaliação ou 1:1 registrada
- % de líderes ativos

**Meta D+30**: health score ≥ 60.

### 5.3 Dias 31-60 · Adoção profunda

- Habilitar módulos avançados (avaliação ciclo, OKRs, 1:1s estruturadas)
- Configurar webhook ERP folha se aplicável (suporte CS + DevOps R2)
- Rodar primeira pesquisa de clima ou eNPS
- Verificar adoção de **líderes**: meta > 60% dos líderes têm 1:1 registrada

**Meta D+60**: health ≥ 70, todos os módulos do plano ativos.

### 5.4 Dias 61-90 · QBR (Quarterly Business Review)

- **QBR formal 60min** com diretoria do cliente
- **Pauta padrão**:
  1. Recap de uso (números absolutos: pessoas/movs/atestados/avaliações processadas)
  2. ROI estimado (horas RH economizadas × custo médio)
  3. Benchmark com setor (sem identificar outros clientes)
  4. Pontos de atenção (adoção, treinamento, configuração)
  5. Roadmap próximos 90 dias
  6. Sondagem de upsell (módulos extras, plano superior, +seats)
- **Output**: PDF assinado de QBR · próximas ações pactuadas

**Meta D+90**: health ≥ 75, sinalização de upsell para 30%+ dos QBRs.

### 5.5 Steady state pós D+90

- **1:1 mensal CSM ↔ champion** (30min)
- **QBR trimestral** com diretoria
- **Alerta automático** se uso cai > 30% MoM → intervenção
- **Programa de advocacy**: cliente que recomenda outro → R$ 1.500 cashback

---

## 6. Playbooks de intervenção

### 6.1 Cliente em **atenção** (health 40-59)

1. **Diagnóstico** (CSM): rodar relatório de uso por módulo, por líder, por mês
2. **1:1 com champion** (30min): qual o bloqueador? Treinamento? Resistência cultural? Bug?
3. **Plano customizado de 30 dias**: 3 metas concretas + responsáveis + KPIs
4. **Check-in semanal** durante esses 30 dias
5. **Re-medir health** ao fim do prazo

### 6.2 Cliente em **risco** (health 20-39)

1. **War room interno R2** (CSM + CS Manager + AE original)
2. **Reunião executiva com cliente** (CTO/CEO R2 + Diretor cliente)
3. **Carta de compromisso** (de ambos os lados): "vamos resolver até X, ou conversamos sobre saída amigável"
4. **CSM dedicado full-time por 30 dias** (não atende outros tickets)
5. **Health re-medido semanalmente**

### 6.3 Cliente em **crítico** (health 0-19)

1. **Executivo R2 (CEO ou CTO) entra na conversa direto**
2. **Save plan ou churn graceful**: oferta de manter em Starter por 3 meses, ou exit limpo
3. **Postmortem interno R2**: o que falhou no ICP/onboarding/produto que levou até aqui
4. **Sem ressentimento**: ofertar referência amigável para concorrente se for o melhor pro cliente

### 6.4 Cliente **champion** (health 80+)

1. **Pedido de case** (estudo para landing/blog/LinkedIn)
2. **Convite para webinar** como cliente convidado (advocacy)
3. **Beta de features novas** (acesso antecipado)
4. **Programa de indicação ativado** (R$ 1.500 cashback por novo cliente)
5. **Co-marketing**: logo no site, vídeo case, post LinkedIn coproduzido

---

## 7. Expansão de receita

### 7.1 Hooks de upsell automáticos

Quando estes sinais aparecem, CRM cria task para CSM abordar:

| Sinal | Oferta | Mensagem |
|---|---|---|
| Quota seats > 90% utilizada | +seats extras OU upgrade plano | "Você está perto do limite. Adicionar seats sai R$ X, ou upgrade pra Pro libera 4× mais." |
| API calls > 80% / mês recorrente | upgrade plano OU add-on API | idem |
| Storage > 80% | upgrade plano OU add-on storage | idem |
| Webhooks no limite | upgrade plano | "Já tem 8/10 webhooks. Vamos pra Pro?" |
| Pediu funcionalidade do plano superior (OKR no Starter, SSO no Pro) | upgrade plano | "Essa feature existe no Pro/Enterprise. Quer testar 14 dias?" |
| Crescimento de seats > 20% em 90d | upgrade plano | "Seu time cresceu 25%. Talvez seja hora de subir pro próximo tier." |

### 7.2 Hooks de cross-sell (add-ons)

| Sinal | Add-on | Quando ofertar |
|---|---|---|
| Empresa contrata muito PJ | Calculadora custo PJ R$ 99 | QBR ou indicador interno |
| Folha terceirizada cara | Folha white-label R$ 299 | QBR (após confiança estabelecida) |
| Alto volume de uploads atestado | Worker OCR dedicado R$ 199 | quando fila atrasa > 10min |
| Cliente sensível a security | Webhook signing por ambiente R$ 49 | depois de CSP violations |
| Cliente Enterprise | Suporte 24×7 R$ 1.500 | após primeiro incidente fora horário |

### 7.3 Renovação anual

- **D-60 antes da renovação**: CSM contata para conversar sobre próximo ano
- **D-45**: proposta de renovação com:
  - Plano vigente OU upgrade sugerido
  - Anual com 10% off (default)
  - 2 anos com 18% off (opcional)
  - Add-ons recomendados baseado em uso
- **D-30**: e-mail formal com link de pagamento
- **D-15**: lembrete + alerta de mudança automática para mensal se não renovar
- **D-0**: ativa renovação OU congela conta para mensal pro-rateado

---

## 8. KPIs do CS

| Métrica | Meta 12 meses | Como medir |
|---|---|---|
| **NRR** (Net Revenue Retention) | > 105% | (MRR mês X / MRR mês X-1) inc. upgrades e churn |
| **GRR** (Gross Revenue Retention) | > 92% | NRR sem upgrades (só churn + downgrade) |
| **Churn anual logo** | < 8% | tenants cancelados / total ano-base |
| **Churn anual MRR** | < 10% | R$ perdido / MRR ano-base |
| **% accounts em "saudável" ou melhor** | > 75% | health ≥ 60 |
| **Time-to-value** (kick-off → primeira mov.) | < 14 dias | data primeiro movement.created |
| **Adoção de líderes 60d** | > 60% | líderes com ao menos 1 ação |
| **NPS** | > 50 | survey trimestral |
| **CSAT do CSM** | > 4.5 / 5 | survey pós-interação |
| **Expansão MRR % do MRR base** | > 15% ano | upsells + cross-sells fechados |

---

## 9. Tooling CSM

| Ferramenta | Custo | Função |
|---|---|---|
| HubSpot Service Hub | R$ 500/mês até 5 seats | Tickets + tasks + pipeline expansão |
| Vitally / Pocus (futuro) | TBD | Health score automation + alerts |
| Loom Pro | R$ 80/mês | Vídeos de treinamento personalizado |
| Calendly | free | Agenda 1:1 + QBR |
| Slack Connect | incluso | Canal compartilhado c/ cliente Pro+ |
| Notion (KB cliente) | R$ 200/mês | Knowledge base interna do cliente |
| Survicate / Refiner | R$ 300/mês | NPS automático trimestral |

---

## 10. RPCs e schema CS

```sql
-- Cálculo de health score
CREATE OR REPLACE FUNCTION rpc_calculate_tenant_health(p_tenant_id uuid)
RETURNS tenant_health
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uso numeric;
  v_adocao numeric;
  v_lideres numeric;
  v_sticky numeric;
  v_seats numeric;
  v_tickets numeric;
  v_nps numeric;
  v_payment numeric;
  v_score numeric;
  v_category text;
  v_components jsonb;
  v_result tenant_health;
BEGIN
  -- Cada cálculo individual (simplificado)
  SELECT LEAST(1, dau_30d::numeric / NULLIF(mau_30d, 0)) INTO v_sticky
  FROM (SELECT count(DISTINCT user_id) FILTER (WHERE last_active > now() - interval '1 day') AS dau_30d,
               count(DISTINCT user_id) FILTER (WHERE last_active > now() - interval '30 days') AS mau_30d
        FROM user_activity_log WHERE tenant_id = p_tenant_id) s;
  -- (... outros componentes elididos por brevidade)

  v_score := (
    COALESCE(v_uso, 0) * 0.25 +
    COALESCE(v_adocao, 0) * 0.20 +
    COALESCE(v_lideres, 0) * 0.15 +
    COALESCE(v_sticky, 0) * 0.10 +
    COALESCE(v_seats, 0.5) * 0.10 +
    COALESCE(v_tickets, 0.5) * 0.10 +
    COALESCE(v_nps, 0.5) * 0.05 +
    COALESCE(v_payment, 1) * 0.05
  ) * 100;

  v_category := CASE
    WHEN v_score >= 80 THEN 'champion'
    WHEN v_score >= 60 THEN 'healthy'
    WHEN v_score >= 40 THEN 'attention'
    WHEN v_score >= 20 THEN 'risk'
    ELSE 'critical'
  END;

  v_components := jsonb_build_object(
    'uso', v_uso, 'adocao', v_adocao, 'lideres', v_lideres,
    'sticky', v_sticky, 'seats', v_seats, 'tickets', v_tickets,
    'nps', v_nps, 'payment', v_payment
  );

  INSERT INTO tenant_health (tenant_id, score, category, components, last_calculated_at)
  VALUES (p_tenant_id, v_score, v_category, v_components, now())
  ON CONFLICT (tenant_id) DO UPDATE SET
    score = EXCLUDED.score,
    category = EXCLUDED.category,
    components = EXCLUDED.components,
    last_calculated_at = EXCLUDED.last_calculated_at
  RETURNING * INTO v_result;

  RETURN v_result;
END;
$$;

-- Tabela de intervenções (audit do que CSM fez por tenant)
CREATE TABLE IF NOT EXISTS cs_interventions (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id   uuid NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  csm_id      uuid REFERENCES auth.users(id),
  type        text NOT NULL,  -- 'kickoff','health_check','qbr','war_room','renewal_call','save_call'
  category    text,           -- 'champion','healthy','attention','risk','critical'
  outcome     text,
  next_step   text,
  scheduled_at timestamptz,
  completed_at timestamptz,
  notes       text,
  created_at  timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX idx_cs_interv_tenant ON cs_interventions (tenant_id, created_at DESC);
```

---

## 11. Testes meta (mínimo 22)

- ✓ `rpc_calculate_tenant_health` inserts/updates linha em `tenant_health`
- ✓ Score 80+ marca categoria 'champion'
- ✓ Score < 20 marca categoria 'critical'
- ✓ Job semanal roda para todos tenants ativos
- ✓ Drop de uso > 30% MoM dispara alerta CSM
- ✓ Quota seats > 90% cria task de upsell no CRM
- ✓ Renovação anual D-60 dispara workflow CSM
- ✓ Cliente novo recebe welcome email D+0
- ✓ Kick-off agendado em D+0 a D+3 (não acumula > 3d)
- ✓ Health calculado no D+30 fica gravado em tenant_health
- ✓ Cliente em 'risk' gera reunião executiva R2 (notification)
- ✓ Cliente em 'critical' bloqueia novos upsells (foco em save)
- ✓ Cliente 'champion' aparece no programa de advocacy
- ✓ Cross-sell de OCR dedicado só aparece se fila > 10min recorrente
- ✓ Survey NPS dispara trimestralmente
- ✓ NPS detrator (0-6) cria intervenção automática
- ✓ QBR registrado em `cs_interventions` com outcome
- ✓ War room cria thread interna R2 (notification multi-user)
- ✓ Pagamento em atraso > 7d derruba componente 'payment' para 0
- ✓ Renovação fechada antes do prazo dá badge ao CSM (gamification)
- ✓ Slack Connect criado automaticamente em kick-off para Pro+
- ✓ KB do cliente acessível só ao tenant em Notion privado

---

## 12. Anti-padrões (o que CS NUNCA faz)

- **Vender em vez de servir**: CSM não fecha contrato — esse é AE. CSM expande, não converte.
- **Esconder problema do cliente**: bug, downtime, atraso — sempre comunicar primeiro, antes do cliente perceber.
- **Discount como muleta de retenção**: se cliente quer sair, conversar valor, não preço. Só descontar como último recurso, com aprovação do CEO.
- **Promessas que produto não cumpre**: nunca prometer feature do roadmap como se fosse pronta.
- **Trato VIP só pra Enterprise**: Starter também merece resposta digna (mesmo que assíncrona).
- **Burocratizar**: cliente PME quer agilidade, não 4 e-mails de aprovação.

---

## 13. Roadmap CS pós-MVP (12 meses)

| Mês | Iniciativa |
|---|---|
| M+1 | Dashboard de health score interno (página `r2_people_cs_dashboard.html`) |
| M+2 | Automação de welcome e-mail + agendamento kick-off |
| M+3 | Templates de QBR em PDF dinâmico |
| M+4 | Survey NPS automático trimestral |
| M+6 | Programa de advocacy formal (referrals + cases) |
| M+9 | KB do cliente em Notion auto-provisionado por tenant |
| M+12 | CS playbook em Notion público (transparência radical) |

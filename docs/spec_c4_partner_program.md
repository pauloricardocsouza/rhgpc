# Spec C4 · Partner Program · Escritórios Contábeis & Consultorias

**Status**: especificação · pré-implementação
**Versão**: 1.0 · 18 de maio de 2026
**Escopo**: programa de parceiros que revendem R2 People c/ comissão recorrente · canal alternativo de aquisição
**Depende de**: spec C1 (Sales), spec C2 (CS), spec C3 (Marketing), spec M10 (settings tenant), schema v12 (billing)

---

## 1. Por que partner program faz sentido em ano 1

PME brasileira **confia mais no contador do que em SaaS HR**. Escritório contábil é quem orienta sobre folha, eSocial, CCT — e quando aponta uma ferramenta de RH, o cliente compra mais rápido que via mkt direto.

**Hipótese**: 30-40% do MRR em ano 2 vem de partners se programa for bem desenhado.

**Quem é partner típico**:
1. **Escritório contábil pequeno-médio** (5-50 clientes ativos, todos PMEs)
2. **Consultoria RH boutique** (faz processo seletivo + 1x consultoria, quer ferramenta pra recomendar)
3. **Consultoria de gestão** (foco em PMEs, recomenda pacote tecnológico)
4. **Revenda de softwares** (vende Domínio, Senior, Conta Azul; complementa portfolio)

---

## 2. Modelo de comissionamento

### 2.1 Estrutura

| Tier | Requisito | Comissão MRR | Suporte | Marca |
|---|---|---|---|---|
| **Indicação** | qualquer um · 1+ cliente fechado | R$ 1.500 one-shot | n/a | n/a |
| **Bronze** | 3+ clientes ativos · NPS partner ≥ 7 | 15% MRR recorrente | e-mail dedicado | "Parceiro R2" |
| **Silver** | 10+ clientes ativos · 90%+ retenção 12m | 20% MRR recorrente | gerente parceiro + webinar trimestral | "Parceiro Silver R2" + selo |
| **Gold** | 25+ clientes ativos · contribui c/ MRR ≥ R$ 15k | 25% MRR recorrente + 5% bônus expansão | gerente dedicado + co-marketing | "Parceiro Gold R2" + selo + landing co-brand |
| **Platinum** | 50+ clientes ativos · MRR ≥ R$ 50k | 30% MRR recorrente · convite eventos | acesso roadmap + relacionamento C-level R2 | white-label opcional |

Comissão **dura enquanto cliente fica** (recorrente, não one-shot).
Se cliente sair em < 6 meses por fault no partner (oversold, sem treinamento), comissão é zerada (clawback).

### 2.2 Pagamento

- **Mensal** via PIX no dia 10 do mês seguinte
- **Comprovante** PDF detalhado por cliente
- **NF de comissão** emitida pelo partner contra R2 (CNPJ)
- **Mínimo de saque**: R$ 100 (acumula se menor)

### 2.3 Cliente trazido por partner

- Recebe **20% off no primeiro ano** (incentivo)
- Partner aparece como "implementador oficial" no setup do tenant
- Configurações iniciais podem ser feitas pelo partner com permissão delegada

---

## 3. Workflow de partnership

```
1. Interesse
   contador@escritorio.com.br → solucoesr2.com.br/partner
   ↓
2. Aplicação
   Formulário c/ CNPJ + segmento + carteira aproximada + cases
   ↓
3. Qualificação (R2 valida)
   - CNPJ ativo? Receita compatível?
   - Carteira clientes alinhada c/ ICP R2?
   - Não compete c/ produto (não vende outro SaaS HR)?
   ↓
4. Onboarding partner (60min Zoom)
   - Treinamento produto
   - Material comercial entregue
   - Acesso ao Partner Portal
   - Assinatura contrato partner (eletrônico)
   - Tier Bronze atribuído inicial
   ↓
5. Primeiro cliente
   - Partner usa link de indicação único
   - Cliente vê "Implementado por X" no setup
   - Sales R2 acompanha pra fechar
   ↓
6. Recorrência
   - Partner ganha comissão mensal
   - Sobe de tier conforme metas
   - Acesso a webinars exclusivos
```

---

## 4. Partner Portal · `r2_people_partner_portal.html`

Tela dedicada para partners (não usa shell admin · login separado).

**5 abas**:

| Aba | Conteúdo |
|---|---|
| **Dashboard** | MRR gerado · clientes ativos · próximo pagamento · NPS partner |
| **Meus Clientes** | Lista c/ status (trial/active/churned) · MRR de cada · health score · ação |
| **Materiais** | Pitch deck · vídeos · 1-pager por segmento · landing co-brand |
| **Treinamentos** | Vídeos onboarding + atualizações produto + webinars gravados |
| **Pagamentos** | Histórico comissões · próximo pagamento · NFs emitidas |

---

## 5. Schema (extensões)

```sql
CREATE TABLE IF NOT EXISTS partners (
  id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_name        text NOT NULL,
  cnpj                text UNIQUE NOT NULL,
  segment             text NOT NULL,                -- 'contador','consultoria_rh','consultoria_gestao','revenda_software'
  tier                text NOT NULL CHECK (tier IN ('indicacao','bronze','silver','gold','platinum')) DEFAULT 'indicacao',
  status              text NOT NULL CHECK (status IN ('applied','qualifying','active','suspended','terminated')) DEFAULT 'applied',
  applied_at          timestamptz DEFAULT now(),
  qualified_at        timestamptz,
  activated_at        timestamptz,
  contract_pdf_key    text,
  contract_signed_at  timestamptz,
  primary_contact_name text NOT NULL,
  primary_contact_email text NOT NULL,
  primary_contact_phone text,
  bank_pix_key        text,                          -- para pagamento comissão
  metadata            jsonb DEFAULT '{}'::jsonb
);

CREATE TABLE IF NOT EXISTS partner_referrals (
  id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  partner_id          uuid NOT NULL REFERENCES partners(id) ON DELETE CASCADE,
  tenant_id           uuid REFERENCES tenants(id) ON DELETE SET NULL,
  referral_code       text UNIQUE NOT NULL,         -- código único do partner
  client_company_name text,
  client_contact_email text,
  status              text NOT NULL CHECK (status IN ('lead','demo_scheduled','trial','converted','churned')) DEFAULT 'lead',
  referred_at         timestamptz DEFAULT now(),
  converted_at        timestamptz,
  churned_at          timestamptz,
  initial_plan        text,
  first_year_discount_applied boolean DEFAULT false
);

CREATE TABLE IF NOT EXISTS partner_commissions (
  id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  partner_id          uuid NOT NULL REFERENCES partners(id) ON DELETE CASCADE,
  referral_id         uuid REFERENCES partner_referrals(id),
  tenant_id           uuid NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  period              text NOT NULL,                 -- '2026-05'
  mrr_brl_cents       int NOT NULL,
  commission_pct      numeric NOT NULL,
  commission_brl_cents int NOT NULL,
  bonus_brl_cents     int DEFAULT 0,
  status              text NOT NULL CHECK (status IN ('pending','approved','paid','clawback')) DEFAULT 'pending',
  paid_at             timestamptz,
  payment_ref         text,
  nf_pdf_key          text,
  UNIQUE (partner_id, tenant_id, period)
);

CREATE INDEX IF NOT EXISTS idx_partner_commissions_pending
  ON partner_commissions (status, period) WHERE status IN ('pending','approved');

CREATE TABLE IF NOT EXISTS partner_materials (
  id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  title               text NOT NULL,
  category            text NOT NULL CHECK (category IN ('pitch_deck','video','one_pager','case_study','webinar')),
  format              text NOT NULL,                 -- 'pdf','mp4','pptx'
  url                 text NOT NULL,
  target_segment      text[],                        -- ['varejo','industria','servicos']
  required_tier       text DEFAULT 'bronze',
  uploaded_at         timestamptz DEFAULT now()
);

CREATE TABLE IF NOT EXISTS partner_nps (
  id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  partner_id          uuid NOT NULL REFERENCES partners(id) ON DELETE CASCADE,
  contact_user_id     uuid REFERENCES auth.users(id),
  score               int NOT NULL CHECK (score BETWEEN 0 AND 10),
  comment             text,
  period              text NOT NULL,
  created_at          timestamptz DEFAULT now()
);
```

---

## 6. RPCs principais

```sql
rpc_partner_register(p_data jsonb) RETURNS uuid
rpc_partner_qualify(p_partner_id uuid, p_decision text, p_notes text)
rpc_partner_calculate_monthly_commissions(p_period text) -- cron mensal
rpc_partner_dashboard(p_partner_id uuid)
  RETURNS TABLE (mrr_total, mrr_growth_mom, clients_active, clients_churned_90d, next_payment_brl, next_payment_at, tier, next_tier_progress)
rpc_partner_referral_link(p_partner_id uuid) RETURNS text -- URL c/ ?ref=CODE
rpc_partner_clawback(p_partner_id uuid, p_tenant_id uuid, p_reason text)
```

---

## 7. Contrato partner (template)

Cláusulas-chave (a redigir c/ jurídico):

1. **Comissão recorrente** enquanto cliente ativo, sem garantia de retenção
2. **Clawback 6 meses** se cliente sair por fault do partner (oversold, sem onboarding)
3. **Exclusividade** zero (partner pode vender outros produtos não-concorrentes)
4. **Não-concorrência** parcial (não vender outro SaaS HR explicitamente concorrente)
5. **Confidencialidade** sobre roadmap e dados de clientes
6. **Rescisão** com 30 dias notice qualquer parte
7. **Suspensão imediata** em caso de violação contratual ou conduta antiética
8. **Indenização** se prejuízo causado por má conduta do partner

---

## 8. Material comercial entregue

| Material | Conteúdo |
|---|---|
| **Pitch deck partner** (PDF/PPTX) | 12 slides · sobre R2 + por que partner + tiers + suporte |
| **1-pagers por segmento** | Varejo · Indústria · Serviços (formatos pra mandar ao cliente final) |
| **Vídeo de pitch 90s** | Pra partner mandar pra cliente potencial |
| **Calculadora ROI** (link compartilhável) | Cliente preenche tamanho da empresa, ferramenta mostra economia esperada |
| **Templates de e-mail** | Cold outreach + follow-up · 3 versões |
| **Roteiro de demo 30min** | Padronizado · partner roda com cliente |
| **Comparativo competitivo** (PDF) | R2 vs Sólides/Qulture/Senior por dimensão |
| **Landing co-brand** (Gold+) | URL `solucoesr2.com.br/parceiros/{slug}` c/ logo do partner |

Materiais hospedados em CDN · acessíveis via Partner Portal · versionados.

---

## 9. Onboarding partner (60min Zoom)

**Pauta**:
1. **Sobre R2** (10min): posicionamento "camada humana sobre Domínio" + ICP + diferenciação
2. **Tour do produto** (15min): demo das 10 telas principais que o cliente verá
3. **Tour Partner Portal** (10min): dashboard, materiais, comissões
4. **Processo de venda** (10min): identifica oportunidade → usa link ref → R2 assume demo → fechamento
5. **Comissionamento** (5min): tiers, pagamento, clawback
6. **Q&A** (10min)

Pós-Zoom:
- Acesso liberado em 24h
- Material entregue via Drive compartilhado
- Slack/WhatsApp dedicado pro partner com gerente parceiro

---

## 10. KPIs do programa

| Métrica | Meta 12 meses |
|---|---|
| **Partners ativos** | 30 |
| **% MRR via partners** | 30% |
| **Conversion lead partner → cliente** | > 25% (vs 12% via mkt direto) |
| **CAC partner** | < R$ 800 (vs R$ 1.500 mkt direto) |
| **Retenção 12m clientes partner** | > 92% (espera-se cliente partner ser mais aderente) |
| **NPS partner médio** | > 8 |
| **Tempo médio aplicação → ativo** | < 7 dias |

---

## 11. Riscos e mitigações

| Risco | Mitigação |
|---|---|
| Partner que só "joga lead pra cima do muro" sem qualificar | Tier exige NPS partner + retenção; conversion baixa baixa tier |
| Cliente trazido por partner sai rápido (oversold) | Clawback 6 meses · partner perde comissão |
| Partner começa a vender concorrente | Cláusula de não-concorrência partial · monitoramento ativo |
| Partner usa logo R2 indevidamente (marketing falso) | Brand guidelines no contrato · denúncia → suspensão |
| Comissão paga errada (cálculo bug) | Audit trimestral · cliente pode contestar até 90d |
| Partner abandona após 6 meses | Tier indicação é low-touch · libera energia pra Silver+ |

---

## 12. Roadmap pós-MVP

1. **M+3 · Programa formal lançado** com 5 partners piloto handpicked
2. **M+6 · Partner Portal v1** + materiais completos
3. **M+9 · Webinar mensal partners** + newsletter dedicada
4. **M+12 · Convenção anual partners** (presencial · networking + roadmap)
5. **M+18 · Marketplace de serviços** (partners oferecem implementação extra, R2 fica c/ 15% take rate)
6. **M+24 · Programa de certificação** (partners certificados aparecem em diretório público)

---

## 13. Posicionamento

Atualizar C3 (Marketing) adicionando bullet:
> "**Programa de parceiros**: contadores e consultores ganham 15-30% MRR recorrente trazendo clientes pra R2 People. 30+ partners ativos no primeiro ano de programa."

E adicionar pilar 7 ao C3 (conteúdo):
- "Webinar mensal para contadores: como adicionar gestão de pessoas ao portfólio do seu escritório"

# Spec C1 · Comercial & Sales Playbook · Lead → Contrato → Go-live

**Status**: especificação · em validação com fundadores R2
**Versão**: 1.0 · 17 de maio de 2026
**Escopo**: funil comercial, materiais, pricing, qualificação, processo de venda, contratação, kick-off
**Depende de**: spec M10 (settings tenant), spec M13 (onboarding wizard), schema v12 (planos/billing)

---

## 1. Posicionamento (uma frase)

> **R2 People** é a plataforma de gestão de pessoas pensada para PMEs brasileiras que precisam digitalizar RH respeitando CLT, LGPD e a complexidade real do mercado (estrutura tripartite, multi-filial, dado de saúde sensível) — sem custo de implementação Enterprise e sem a infantilidade dos SaaS HR genéricos.

### 1.1 Diferenciação contra os 3 competidores principais

| | **Qulture.Rocks** | **Sólides** | **Senior** | **R2 People** |
|---|---|---|---|---|
| Tripartite CTPS ≠ tomador | ❌ | ❌ | ⚠ via custom | ✅ nativo |
| LGPD-first (CID nunca exposto à liderança) | ⚠ depende config | ⚠ depende | ❌ legado | ✅ arquitetural |
| Onboarding < 25min (TTFE) | ❌ 2-4 semanas | ❌ 1-2 semanas | ❌ 3-6 meses | ✅ M13 wizard |
| Preço transparente (sem "fale com vendas") | ⚠ desconto opaco | ⚠ idem | ❌ orçamento | ✅ tabela pública |
| Atestados c/ OCR client-side | ❌ | ❌ | ❌ | ✅ Tesseract WASM |
| DPO compartilhado pra cliente PME | ❌ | ❌ | ⚠ pago | ✅ incluso Pro+ |
| Webhooks HMAC nativos | ⚠ Zapier only | ⚠ idem | ⚠ EDI legado | ✅ schema v10 |
| Postura segurança auditável pelo cliente | ❌ | ❌ | ⚠ NDA | ✅ DevSec console |

---

## 2. ICP · Ideal Customer Profile

### 2.1 Quem compra (3 segmentos primários)

| Segmento | Tamanho | Pain principal | Time-to-pain | Disposição a pagar |
|---|---|---|---|---|
| **Varejo regional** | 30-500 pessoas, 3-15 lojas | Estrutura tripartite (rede ≠ loja) quebra ERPs genéricos | imediato | R$ 800-3k/mês |
| **Indústria média** | 50-300 pessoas, 1-3 unidades | Atestados em pilha + folha terceirizada gerando atrito | trimestral (cota de absenteísmo) | R$ 700-2k/mês |
| **Serviços B2B** | 30-200 pessoas | Avaliações ad-hoc + 1:1s sem registro + churn de talento | mensal (1:1 perdido) | R$ 500-2k/mês |

### 2.2 Quem decide

- **Comprador econômico**: Diretor/CFO (assina contrato, libera orçamento)
- **Comprador técnico**: Coord/Ger RH (define se a plataforma resolve)
- **Influenciador**: TI (avalia LGPD, integrações, SLA)
- **Usuário final**: líderes diretos + colaboradores (vivem o dia-a-dia)

### 2.3 Quem NÃO é cliente (anti-ICP)

- < 20 pessoas (planilha + WhatsApp ainda funciona)
- > 1.000 pessoas (Enterprise quer Senior/Totvs por integração ERP profunda)
- Setores ultra-regulados (banco, seguro) que exigem ISO 27001 antes do pen-test
- Empresas que querem "sistema de ponto" — não é nosso escopo (somos gestão de pessoas, não controle de jornada)

---

## 3. Funil comercial · 6 estágios

```
                ┌─────────────┐
LEAD            │ Conhece R2  │  → fonte (referência GPC, LinkedIn, indicação)
                └─────┬───────┘
                      ▼
                ┌─────────────┐
SQL             │Qualificado  │  → preenche formulário c/ CNPJ + headcount
                └─────┬───────┘
                      ▼
                ┌─────────────┐
DEMO            │ Reunião 30m │  → vê produto + entende preço
                └─────┬───────┘
                      ▼
                ┌─────────────┐
PROPOSTA        │ Tabela + ROI│  → recebe PDF c/ pricing + caso real GPC
                └─────┬───────┘
                      ▼
                ┌─────────────┐
TRIAL           │ 14 dias livre│ → wizard M13 + dados reais imp. CSV
                └─────┬───────┘
                      ▼
                ┌─────────────┐
CONTRATO        │ Pagto + DPA │  → cartão recorrente OU PIX trimestral
                └─────┬───────┘
                      ▼
                ┌─────────────┐
KICK-OFF        │ Reunião 60m │  → CS apresenta plano 30/60/90d
                └─────────────┘
```

### 3.1 Métricas por estágio (meta primeiros 90d pós-GA)

| Estágio | Quantidade meta | Conversion para próxima | Tempo médio |
|---|---|---|---|
| LEAD | 200/mês | 25% | n/a |
| SQL | 50/mês | 60% | 2-5 dias |
| DEMO | 30/mês | 70% | 7-14 dias |
| PROPOSTA | 20/mês | 50% | 7-14 dias |
| TRIAL | 10/mês | 50% | 14 dias |
| CONTRATO | 5/mês | 100% (já fecharam) | 1-3 dias |
| KICK-OFF | 5/mês | 100% | 7 dias pós-contrato |

**MRR esperado mês 1 pós-GA**: 5 contratos × R$ 600 ticket médio inicial = **R$ 3k MRR**.
**MRR meta 12 meses**: 80 contratos pagantes × R$ 850 ticket médio = **R$ 68k MRR** = **R$ 816k ARR**.

---

## 4. Materiais comerciais (por estágio)

### 4.1 LEAD → SQL

- **Landing pages segmentadas** (`/varejo`, `/industria`, `/servicos`) com 1 caso de uso primário e CTA "Quero ver"
- **Calculadora "Quanto sua empresa perde com RH analógico"** — input: nº de colaboradores, output: horas/mês perdidas em atestados + folha + avaliações × custo médio
- **Showcase navegável** (`r2_people_showcase.html` já criado) acessível sem login

### 4.2 SQL → DEMO

- **Cold e-mail templates** (3 versões: técnico/comercial/diretoria) — máx 80 palavras
- **Vídeo Loom de 90s** mostrando: tripartite + OCR atestado + 9-Box em 3 cliques
- **Calendar.com** com agenda livre + perguntas de pré-qualificação (CNPJ, headcount, ERP atual)

### 4.3 DEMO → PROPOSTA

- **Roteiro de demo de 30min** padrão (cobre):
  - 5min · contexto + perguntas
  - 8min · cadastro pessoa + estrutura tripartite (caso GPC)
  - 5min · atestado c/ OCR + RLS CID escondendo do líder
  - 5min · 9-Box + 1:1 + OKR rápido
  - 4min · billing + LGPD (tranquiliza diretoria)
  - 3min · perguntas + próximos passos
- **Q&A canned** com 30 perguntas frequentes + respostas (em `docs/sales_qa.md`)

### 4.4 PROPOSTA → TRIAL

- **PDF de proposta** (template em `templates/proposta_comercial.pdf` — já existe v1):
  - Capa com nome do cliente + logo (auto-preenchido)
  - Diagnóstico (3 pains identificados na demo)
  - Solução proposta (módulos selecionados)
  - Pricing tabular (Pro recomendado, opção Starter, Enterprise se > 200 pessoas)
  - ROI estimado (cálculo personalizado)
  - Plano de implantação 30/60/90
  - Validade 14 dias
- **DPA** (Data Processing Agreement) padrão ABNT + LGPD anexo

### 4.5 TRIAL → CONTRATO

- **E-mail diário 1-14** (cadência automatizada):
  - D+1 · "Bem-vindo, eis seu link"
  - D+3 · "Você já importou seus colaboradores? Posso ajudar."
  - D+7 · "Como está a primeira semana? Posso agendar 1:1 30min"
  - D+10 · "ROI parcial — você já economizou X horas"
  - D+13 · "Trial vence amanhã — vamos fechar?"
- **Slack/WhatsApp dedicado** com CS durante trial
- **CSV de import assistido** — CS dedica 30min pra ajudar a primeira importação

### 4.6 CONTRATO → KICK-OFF

- **Contrato eletrônico** (Clicksign/DocuSign) com 1 click
- **Boleto/PIX trimestral** (10% off) OU cartão recorrente mensal
- **CS atribuído** notificado automaticamente via webhook `subscription.activated`
- **Kick-off 60min agendado** (CS apresenta plano)

---

## 5. Pricing public (em `solucoesr2.com.br/precos`)

| | **Starter** | **Pro** | **Enterprise** |
|---|---|---|---|
| Mensal | R$ 299 | R$ 799 | R$ 2.499 |
| Anual (10% off) | R$ 269 | R$ 719 | R$ 2.249 |
| Seats inclusos | 25 | 100 | 300 |
| Seat extra | R$ 19 | R$ 15 | R$ 12 |
| Max seats | 50 | 500 | ilimitado |
| Módulos | 5 básicos | 11 completos | Tudo + add-ons |
| Storage | 5 GB | 50 GB | 500 GB |
| API calls/mês | 10k | 100k | 1M |
| Webhooks | 2 | 10 | 50 |
| SSO | ❌ | ❌ | ✅ |
| MFA obrigatório | opcional | ✅ | ✅ |
| Suporte | e-mail H. comercial | priority + chat | CS dedicado + SLA 99.9 |
| DPO compartilhado | ❌ | ✅ | ✅ |
| Pen-test compartilhado | ❌ | ❌ | ✅ anual |
| Audit log estendido | 90d | 1 ano | 5 anos |

### 5.1 Add-ons (qualquer plano)

- **Calculadora de custo PJ** R$ 99/mês
- **Folha de pagamento white-label** R$ 299/mês
- **Worker FastAPI OCR dedicado** (offload da fila) R$ 199/mês
- **Webhook signing dedicado por ambiente** (separa prod/staging) R$ 49/mês
- **Suporte 24×7 (Enterprise apenas)** R$ 1.500/mês

### 5.2 Descontos negociáveis

- Anual: 10% off (default público)
- 2 anos: 18% off
- ONGs: 30% off comprovação MROSC
- Indicação que vira contrato: R$ 1.500 cashback (programa M-Indicações)

### 5.3 Sem-negociação policy

Nunca descontar abaixo de:
- Pro mensal: R$ 599 (25% off teto)
- Enterprise mensal: R$ 1.999 (20% off teto)
- Justificar SEMPRE (caso âncora, RFP, deal especial) no CRM.

---

## 6. Qualificação (BANT-C + 1)

| Critério | Pergunta | Quem responde | Como pesar |
|---|---|---|---|
| **B**udget | Já tem orçamento mensal para SaaS RH? | CFO/Diretor | < R$ 500 → Starter; 500-2k → Pro; > 2k → Enterprise |
| **A**uthority | Quem assina contrato? | Comprador | Se for "preciso falar com chefe" → não SQL ainda |
| **N**eed | Qual o pain hoje? Por que agora? | RH | Top 3 pains R2 atende? Se 0/3 → no fit |
| **T**iming | Quando precisa funcionando? | RH | < 30d → trial expressa; > 90d → nurturing |
| **C**ompliance | Tem alguma fiscalização ou processo trabalhista recente? | Jurídico | Sim → LGPD vira diferencial decisivo |
| **+ Champion** | Há alguém interno empurrando a mudança? | qualquer | Sem champion → 80% chance de stall |

Score 5-6/6 = fast track demo. Score 3-4/6 = nurturing 30d. Score 0-2/6 = arquivar polidamente.

---

## 7. Equipe comercial inicial (mês 1-12)

| Função | Quando contratar | Responsabilidade | Comissão |
|---|---|---|---|
| **CEO sales** (fundador) | mês 1 | Todas as demos, fecha deals Enterprise | n/a (equity) |
| **SDR júnior** | mês 4 (após PMF) | Qualifica leads, agenda demos | R$ 3.5k + R$ 100/SQL |
| **AE pleno** | mês 7 | Conduz demo + proposta + fechamento Pro | R$ 6k + 8% MRR primeiros 6m |
| **CS sênior** | mês 9 | Onboarding, retenção, expansão | R$ 7k + 1.5% expansão |
| **AE Enterprise** | mês 12 | Deals > R$ 5k MRR | R$ 9k + 5% MRR + bônus anual |

Stack tooling:
- **HubSpot CRM** (free tier até R$ 500/mês)
- **Calendly** (free tier)
- **Loom** (Pro R$ 80/mês para gravações ilimitadas)
- **Clicksign** assinatura eletrônica (R$ 290/mês até 100 docs)
- **Plausible Analytics** (R$ 50/mês, privacy-friendly)

---

## 8. Onboarding pós-contrato · plano 30/60/90

### 8.1 Dias 1-7 · Setup técnico

- CS acompanha wizard M13 com cliente (Zoom de 60min)
- Importa CSV de colaboradores (CS prepara o arquivo a partir do que o cliente manda)
- Configura primeira política de acesso + branding
- Treinamento ao admin (1h gravada para depois)

### 8.2 Dias 8-30 · Rollout interno

- Webinar de 30min para líderes do cliente (CS facilita)
- 1:1 semanal CS↔champion (15min)
- KPIs vivos: % de colaboradores ativados, primeira movimentação, primeira avaliação

### 8.3 Dias 31-60 · Adoção profunda

- Habilitar módulos avançados (avaliação, OKRs, 1:1s)
- Configurar webhook ERP folha se aplicável (suporte CS + DevOps R2)
- Primeira pesquisa de clima/eNPS rodada
- Health score: meta 70+ (escala 0-100)

### 8.4 Dias 61-90 · QBR

- **Quarterly Business Review** (60min) com diretoria do cliente
- Apresenta uso da plataforma + ROI realizado + benchmark do setor
- Sondagem de upsell (módulos extras, plano superior)
- Renovação se mensal vira anual com desconto

### 8.5 Pós 90 · Steady state

- 1:1 mensal CS (30min)
- QBR trimestral
- Alerta automático se uso cai > 30% MoM (intervenção)
- Programa de advocacy: cliente que recomenda ganha bônus

---

## 9. Métricas norte (north-stars comerciais)

| Métrica | Meta 12m | Como medir |
|---|---|---|
| **MRR** | R$ 68k | sum(plan_price + seat_extras) ativos |
| **NRR** (Net Revenue Retention) | > 105% | (MRR mês X / MRR mês X-1) considerando upgrades + churn |
| **CAC payback** | < 10 meses | (custo aquisição / MRR ganho) |
| **LTV/CAC** | > 4× | LTV considerando churn anual 8% |
| **Churn anual** | < 8% | logos perdidos / 12m |
| **NPS** | > 50 | survey trimestral |
| **Trial → Paid** | > 50% | trials iniciados / contratos fechados |
| **Time-to-value** (kick-off → primeira movimentação) | < 14 dias | dados do banco |

---

## 10. Risk & objection handling

### 10.1 As 10 objeções mais comuns + respostas

1. **"Já temos planilha, funciona"**
   → "Vamos calcular o custo escondido? Em média um RH de 50 pessoas perde 35h/mês em planilha. A R$ 60/h custo total, são R$ 25k/ano só do RH. Pro custa R$ 9.6k/ano."

2. **"E se vazar dado de saúde?"**
   → "Por arquitetura, atestado com CID nunca aparece para o líder. Só DPO + RH validador veem. Mostro a tela agora?"

3. **"Não posso trocar meu ERP folha agora"**
   → "Não pedimos. R2 People conversa via webhook com o que você já tem. Mostro um exemplo de fluxo com Senior/Totvs/Sankhya?"

4. **"Sólides já faz isso e é barato"**
   → "Para empresa com tripartite, Sólides não modela isso nativo. E nosso pricing por seat acaba sendo equivalente em volume médio."

5. **"E LGPD?"**
   → "DPO compartilhado incluso no Pro. ROPA pré-preenchida. DSAR automatizado. Spec D7 detalha tudo, te mando."

6. **"Demora pra implementar?"**
   → "Em vídeo de 25min você está com plataforma funcional. Mais 1 semana com CS para rollout. Mostro o wizard?"

7. **"E se sair do ar?"**
   → "SLO 99.5%, dump diário cifrado, smoke test noturno, drill trimestral. DR Console é público para o cliente, te mostro."

8. **"Posso usar minha cor/logo?"**
   → "Sim, branding por tenant no wizard inicial. Sub-domínio próprio só Enterprise."

9. **"E API?"**
   → "REST + webhook outbound HMAC nativo. Catálogo de 10 eventos. Sem custo extra no Pro."

10. **"Quanto custa sair?"**
    → "Nada. Export ZIP completo via DSAR portability. Sem lock-in, sem multa, sem 'phase out fee'."

### 10.2 Red flags que indicam NÃO fechar

- Cliente insiste em SLA > 99.99% (só Enterprise + custo dedicado)
- Cliente exige código-fonte ou self-hosting (não vendemos)
- Cliente pede integração com sistema legado proprietário sem API documentada
- Cliente compra "para o ano que vem" sem urgência real
- Champion sai da empresa durante o trial — pause e re-qualifique

---

## 11. Roadmap comercial pós-MVP (6 meses)

| Mês | Iniciativa |
|---|---|
| M+1 | Lançar landing pages segmentadas + calculadora |
| M+2 | Programa formal de indicação (referral) com tracking automático |
| M+3 | Webinar mensal aberto "RH Digital sem Drama" |
| M+4 | Conteúdo: blog SEO + LinkedIn newsletter "Dossier RH PME" |
| M+5 | Parceria com 3 escritórios contábeis (revenue share) |
| M+6 | Programa de partners (consultorias RH revendem c/ 20% recorrente) |

---

## 12. Tracking comercial (CRM mínimo)

Pipeline visual no HubSpot por estágio. Cada deal carrega:
- empresa, headcount, segmento ICP
- BANT-C score (0-6)
- canal de origem
- plan_target sugerido
- valor estimado MRR
- data próxima etapa
- objeções abertas
- champion identificado

Dashboard semanal: novos leads, conversion rate por estágio, deals stuck > 30d (intervenção SDR).

---

## 13. Anexos referenciados

- `templates/proposta_comercial.pdf` — já existe v1
- `templates/dpa_lgpd.pdf` — criar pós-validação jurídica
- `r2_people_showcase.html` — já existe
- `r2_people_billing.html` — já existe (mostrar em demo)
- `r2_people_lgpd_cockpit.html` — já existe (mostrar em demo)
- `docs/sales_qa.md` — TODO criar com 30 Q&A
- `docs/roi_calculator_formula.md` — TODO criar

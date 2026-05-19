# Spec M19 · Benefícios & Dependentes · Catálogo, Adesão, Convênios, Reembolso

**Status**: especificação · pré-implementação
**Versão**: 1.0 · 18 de maio de 2026
**Escopo**: catálogo de benefícios da empresa, adesão self-service, dependentes c/ comprovantes, convênios parceiros c/ desconto, workflow de reembolso (R2 aprova, Domínio paga)
**Depende de**: spec M16 (Integração Domínio), spec D7 (LGPD), spec D8 (RLS), spec M12 (notif)

---

## 1. Por que isso existe (e não está só no Domínio)

Domínio sabe **descontar VR/VA/plano de saúde** na folha. Mas:
- Colaborador **não sabe quais benefícios** a empresa oferece
- Para aderir a um benefício opcional precisa **mandar e-mail pro RH**
- Cadastro de **dependentes** (plano de saúde, IR) vive em pasta Word
- **Reembolso** (telemedicina, óculos, curso) vira fila de WhatsApp
- **Convênios parceiros** (academia, lojas) são folder esquecido

R2 People = **portal de benefícios self-service** + **fluxo aprovativo unificado** + **catálogo descoberta**. Tudo financeiro continua passando pelo Domínio.

---

## 2. Áreas cobertas

### 2.1 Catálogo de benefícios

Por tenant:

| Benefício | Tipo | Adesão | Custo p/ colab |
|---|---|---|---|
| **Vale-refeição** (VR) | obrigatório (CCT) | automática | desconto folha |
| **Vale-alimentação** (VA) | obrigatório (CCT) | automática | desconto folha |
| **Vale-transporte** | obrigatório (Lei 7.418) | opt-out | 6% salário |
| **Plano de saúde** | opcional | self-service | varia (coparticipação) |
| **Plano odontológico** | opcional | self-service | varia |
| **Seguro de vida** | opcional | self-service ou grupo | varia |
| **Previdência privada** | opcional | self-service | varia (matching empresa) |
| **Telemedicina** | empresa paga 100% | automático | R$ 0 |
| **Auxílio creche** | conforme CCT | self-service + comprovante | empresa paga |
| **Auxílio educação** | discricionário | aprovação líder + RH | empresa paga |
| **Gympass / Wellhub** | opcional | self-service | empresa subsidia X% |
| **Cesta básica** | benefício específico | automático | empresa paga |
| **Day off aniversário** | benefício | automático (folga aniversário) | empresa concede |

**Cada benefício tem ficha**:
- Nome + descrição rica (markdown)
- Categoria (saúde/educação/lazer/financeiro/alimentação/transporte)
- Tipo de adesão (automática / opt-out / opt-in / aprovação)
- Custo para colaborador (% salário · valor fixo · gratuito)
- Custo para empresa
- Quais cargos/filiais têm direito (regras)
- Documentos exigidos (comprovante de matrícula, atestado de saúde, etc)
- FAQ
- Logo do parceiro
- Quem operacionaliza (RH interno · parceiro X · Domínio)

### 2.2 Adesão self-service

Workflow padrão:

1. Colaborador entra em "Meus Benefícios" e vê catálogo
2. Filtros: "disponíveis pra mim" / "já adiro" / "categoria"
3. Click em "Aderir" abre wizard de 3 passos:
   - **Confirmação**: explica regras, custo, prazo de carência
   - **Comprovantes**: upload se necessário (matrícula, etc)
   - **Aceite**: termo específico do benefício (LGPD-ready)
4. Se requer aprovação líder/RH: vai pra fila (notif M12 disparada)
5. Se aprovado: dispara webhook (M12) pro Domínio fazer setup folha
6. Status reflete em tempo real: pending / approved / active / cancelled

### 2.3 Dependentes

Cadastro consolidado (usado por plano de saúde + IR + dependentes em geral):

| Campo | Tipo | Obrigatório |
|---|---|---|
| Nome completo | text | sim |
| CPF | text | sim (para IR) |
| Data nascimento | date | sim |
| Grau de parentesco | enum (cônjuge, filho_a, enteado_a, pais, outros) | sim |
| Sexo / Gênero | text | sim (plano saúde) |
| Documento (certidão nasc / casamento / comprovante guarda) | PDF | sim |
| Validade dependência (filho até 21 ou 24 se universitário) | date | calculado |
| Inclui em IR? | bool | sim |
| Inclui em plano saúde? | bool | sim |
| Inclui em vale-alimentação? | bool | varia |
| Dependente PCD? | bool | varia |

R2 mantém cadastro mestre. Quando colaborador adiciona/remove dependente, dispara evento pro Domínio atualizar folha (IR, desconto plano saúde).

**Alertas automáticos**:
- Filho completando 21 anos (perde dependência IR) → notif RH + colaborador
- Filho universitário completando 24 anos → idem
- Comprovante de matrícula vencendo → renovar

### 2.4 Convênios parceiros (desconto por ser do GPC)

Catálogo de parceiros locais/nacionais com **código de desconto exclusivo**:

| Parceiro | Desconto | Como usar |
|---|---|---|
| Academia Smart Fit (Salvador) | 30% | mostrar crachá GPC + código no app |
| Drogasil | 15% medicamentos | número CPF cadastrado |
| Cinemark | 50% ingressos | código mensal renovado |
| Faculdade UNIME | 20% mensalidade | matrícula c/ comprovante CTPS |
| Restaurante chinês X | 10% almoço | falar nome GPC |

**Página de convênios** = vitrine + filtros (categoria, cidade, online/presencial) + click "Como usar" mostra detalhes + código + telefone.

Tenant_admin gerencia: adiciona/edita/remove parceiros + define códigos.

**Métricas**:
- Top 5 convênios mais clicados
- NPS dos convênios (colaborador pode avaliar)
- Convênios com baixa adoção → revisar / desativar

### 2.5 Reembolso (R2 aprova, Domínio paga)

Para benefícios que não passam pré-aprovados:
- Telemedicina extra
- Óculos / lentes (com PT médica)
- Curso de inglês (com nota fiscal)
- Material escolar de filho
- Vale-cultura (livro, cinema)
- Plano de saúde de dependente não-coberto

**Workflow**:
1. Colaborador abre solicitação:
   - Categoria
   - Valor
   - Data do gasto
   - Comprovante (NF/recibo PDF)
   - Justificativa
2. R2 valida automaticamente:
   - Valor dentro do teto da política?
   - Categoria permitida pro cargo?
   - Tem comprovante?
   - Dentro do prazo (30d do gasto)?
3. Líder aprova/rejeita (workflow ou auto-aprova se regra)
4. RH valida (opcional, depende política)
5. R2 dispara webhook (M12) pro Domínio:
   - Cria pagamento extra na próxima folha
   - Ou pagamento avulso PIX (se categoria permite)
6. Status reflete: pending_leader → pending_rh → approved → paid

---

## 3. Schema

```sql
-- 3.1 Catálogo
CREATE TABLE IF NOT EXISTS benefit_catalog (
  id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id           uuid NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  code                text NOT NULL,            -- 'vr','va','vt','saude','odonto','gympass',...
  name                text NOT NULL,
  category            text NOT NULL CHECK (category IN ('saude','educacao','lazer','financeiro','alimentacao','transporte','familia','outros')),
  description_md      text,
  adhesion_type       text NOT NULL CHECK (adhesion_type IN ('automatic','opt_out','opt_in','requires_approval')),
  cost_employee_type  text CHECK (cost_employee_type IN ('free','fixed','percent_salary','coparticipation')),
  cost_employee_value numeric,
  cost_company_value  numeric,
  operator            text,                      -- 'rh_internal','parceiro_x','dominio'
  partner_logo_url    text,
  rules_md            text,                      -- regras de elegibilidade
  required_docs       text[],                    -- ['matricula','atestado_saude']
  faq_md              text,
  active              boolean DEFAULT true,
  display_order       int DEFAULT 0,
  UNIQUE (tenant_id, code)
);

-- 3.2 Regras de elegibilidade (quais cargos/filiais têm direito)
CREATE TABLE IF NOT EXISTS benefit_eligibility (
  benefit_id          uuid NOT NULL REFERENCES benefit_catalog(id) ON DELETE CASCADE,
  position_id         uuid REFERENCES positions(id),
  branch_id           uuid REFERENCES branches(id),
  department_id       uuid REFERENCES departments(id),
  min_months_company  int DEFAULT 0,             -- tempo mínimo de casa
  PRIMARY KEY (benefit_id, position_id, branch_id, department_id)
);

-- 3.3 Adesões
CREATE TABLE IF NOT EXISTS benefit_subscriptions (
  id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id           uuid NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  employee_id         uuid NOT NULL REFERENCES employees(id) ON DELETE CASCADE,
  benefit_id          uuid NOT NULL REFERENCES benefit_catalog(id),
  status              text NOT NULL CHECK (status IN ('pending_approval','active','suspended','cancelled')) DEFAULT 'pending_approval',
  adhered_at          timestamptz NOT NULL DEFAULT now(),
  active_from         date,
  cancelled_at        timestamptz,
  cancellation_reason text,
  approved_by         uuid REFERENCES auth.users(id),
  approved_at         timestamptz,
  metadata            jsonb DEFAULT '{}'::jsonb, -- valores específicos, planos escolhidos
  UNIQUE (employee_id, benefit_id, adhered_at)
);

CREATE INDEX idx_benefit_subs_active
  ON benefit_subscriptions (employee_id) WHERE status = 'active';

-- 3.4 Dependentes
CREATE TABLE IF NOT EXISTS dependents (
  id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id           uuid NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  employee_id         uuid NOT NULL REFERENCES employees(id) ON DELETE CASCADE,
  full_name           text NOT NULL,
  cpf                 text,
  birth_date          date NOT NULL,
  relationship        text NOT NULL CHECK (relationship IN ('conjuge','filho','filha','enteado','enteada','pai','mae','outro')),
  gender              text,
  pcd                 boolean DEFAULT false,
  pcd_type            text,
  document_pdf_key    text,
  includes_in_ir      boolean DEFAULT true,
  includes_in_health  boolean DEFAULT false,
  includes_in_va      boolean DEFAULT false,
  dependency_valid_until date,                  -- calculado: filho 21/24 anos
  status              text CHECK (status IN ('active','removed')) DEFAULT 'active',
  added_at            timestamptz DEFAULT now(),
  removed_at          timestamptz,
  removed_reason      text
);

CREATE INDEX idx_dependents_employee
  ON dependents (employee_id) WHERE status = 'active';

-- 3.5 Convênios parceiros
CREATE TABLE IF NOT EXISTS partner_perks (
  id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id           uuid NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  partner_name        text NOT NULL,
  partner_logo_url    text,
  category            text,                      -- 'academia','restaurante','farmacia','educacao','lazer','etc'
  discount_pct        numeric,
  discount_description text,                     -- "30% mensalidade · primeiros 6 meses"
  how_to_use_md       text,
  promo_code          text,
  url                 text,
  phone               text,
  address             text,
  city                text,
  state               text,
  active              boolean DEFAULT true,
  valid_until         date,
  display_order       int DEFAULT 0
);

CREATE TABLE IF NOT EXISTS partner_perk_clicks (
  id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id           uuid NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  perk_id             uuid NOT NULL REFERENCES partner_perks(id) ON DELETE CASCADE,
  user_id             uuid REFERENCES auth.users(id),
  clicked_at          timestamptz DEFAULT now()
);

CREATE TABLE IF NOT EXISTS partner_perk_ratings (
  id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  perk_id             uuid NOT NULL REFERENCES partner_perks(id) ON DELETE CASCADE,
  user_id             uuid NOT NULL REFERENCES auth.users(id),
  rating              int NOT NULL CHECK (rating BETWEEN 1 AND 5),
  comment             text,
  created_at          timestamptz DEFAULT now(),
  UNIQUE (perk_id, user_id)
);

-- 3.6 Reembolsos
CREATE TABLE IF NOT EXISTS reimbursement_requests (
  id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id           uuid NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  employee_id         uuid NOT NULL REFERENCES employees(id) ON DELETE CASCADE,
  category            text NOT NULL,            -- 'telemedicina','oculos','curso','material_escolar','cultura'
  amount_brl_cents    int NOT NULL,
  expense_date        date NOT NULL,
  receipt_pdf_key     text NOT NULL,
  justification       text,
  status              text NOT NULL CHECK (status IN ('pending_leader','pending_rh','approved','rejected','paid')) DEFAULT 'pending_leader',
  leader_id           uuid REFERENCES auth.users(id),
  leader_decision_at  timestamptz,
  leader_notes        text,
  rh_id               uuid REFERENCES auth.users(id),
  rh_decision_at      timestamptz,
  rh_notes            text,
  payment_method      text,                      -- 'folha_proxima','pix_avulso'
  paid_at             timestamptz,
  dominio_event_id    text,                      -- ref do webhook pro Domínio
  created_at          timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX idx_reimb_employee ON reimbursement_requests (employee_id, created_at DESC);
CREATE INDEX idx_reimb_pending ON reimbursement_requests (status, created_at)
  WHERE status IN ('pending_leader','pending_rh');

-- 3.7 Políticas de reembolso por tenant (tetos)
CREATE TABLE IF NOT EXISTS reimbursement_policies (
  id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id           uuid NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  category            text NOT NULL,
  max_brl_cents_month int,                       -- teto mensal
  max_brl_cents_year  int,                       -- teto anual
  requires_leader     boolean DEFAULT true,
  requires_rh         boolean DEFAULT true,
  eligible_positions  uuid[],                    -- NULL = todos
  deadline_days       int DEFAULT 30,            -- prazo para solicitar após gasto
  description_md      text,
  active              boolean DEFAULT true,
  UNIQUE (tenant_id, category)
);
```

---

## 4. RPCs principais

```sql
-- 4.1 Benefícios disponíveis pra mim
rpc_my_available_benefits(p_user_id uuid)
  RETURNS TABLE (benefit_id, name, category, cost_employee_value, already_adhered boolean)

-- 4.2 Aderir benefício (workflow)
rpc_benefit_adhere(p_employee_id, p_benefit_id, p_metadata jsonb DEFAULT '{}')
  RETURNS TABLE (subscription_id uuid, status text, requires_approval boolean)

-- 4.3 Adicionar dependente
rpc_dependent_add(p_employee_id, p_full_name, p_cpf, p_birth_date, p_relationship, ...)
  RETURNS uuid

-- 4.4 Solicitar reembolso
rpc_reimbursement_request(p_employee_id, p_category, p_amount, p_expense_date, p_receipt_key, p_justification)
  RETURNS TABLE (request_id uuid, status text, requires_leader_approval boolean)

-- 4.5 Aprovar/rejeitar reembolso (líder ou RH)
rpc_reimbursement_decide(p_request_id, p_decision text, p_notes)
  RETURNS void

-- 4.6 Cockpit RH · todos pendentes
rpc_rh_pending_approvals(p_tenant_id)
  RETURNS TABLE (request_id, employee_name, category, amount, days_pending)

-- 4.7 Stats convênios (UI gerencial)
rpc_perks_stats(p_tenant_id, p_days int DEFAULT 30)
  RETURNS TABLE (perk_id, name, click_count, avg_rating numeric)
```

---

## 5. UI · 3 telas novas + 2 extensões

### 5.1 `r2_people_beneficios.html` (colaborador)

**Hero**: "Olá Fernanda, você tem 4 benefícios ativos · 3 disponíveis pra aderir"

**3 abas**:
- **Meus benefícios** (ativos): cards com nome, valor, status
- **Disponíveis pra mim** (catálogo elegível): cards com "Aderir" button
- **Convênios parceiros**: grid de cards com logo + desconto + "Como usar"

### 5.2 `r2_people_dependentes.html` (colaborador)

- Lista dependentes ativos c/ avatar circular
- Botão "+ Adicionar dependente" abre wizard 4 passos
- Cada dependente: card com nome, parentesco, idade, badges (IR/Saúde/VA)
- Alerta proativo: "João completa 21 anos em 90 dias · perde dependência IR"

### 5.3 `r2_people_reembolso.html` (colaborador)

- "+ Nova solicitação" abre wizard
- Lista de solicitações com status timeline
- Filtros: status, categoria, período

### 5.4 Extensão `r2_people_admin_dashboard.html` (líder)

Card novo "**Aprovações pendentes**":
- N solicitações de reembolso aguardando você
- N pedidos de benefício aguardando
- Link "Aprovar tudo"

### 5.5 Extensão `r2_people_configuracoes.html` (tenant_admin)

Nova aba "**Benefícios**":
- Gerenciar catálogo (CRUD)
- Gerenciar políticas de reembolso (tetos)
- Gerenciar convênios parceiros
- Métricas de adoção

---

## 6. Integração com Domínio (via M16)

| Evento R2 | Reflete no Domínio |
|---|---|
| Colaborador adere VR/VA opcional | adiciona desconto folha |
| Adere plano saúde | adiciona desconto coparticipação |
| Cancela benefício | remove desconto folha próxima |
| Adiciona dependente IR | atualiza desconto IR folha |
| Remove dependente | atualiza desconto IR folha |
| Reembolso aprovado | cria pagamento avulso na próxima folha |
| Day off aniversário acionado | abate dia do banco horas (se configurado) |

R2 emite eventos via M12. Domínio recebe via M14 inbound (handlers a definir conforme API real do Domínio).

---

## 7. Notificações via M12

- `benefit.adhered_pending` → líder/RH
- `benefit.approved` → colaborador
- `dependent.dependency_expiring` (21/24 anos) → colaborador + RH
- `dependent.school_proof_expiring` → colaborador
- `reimbursement.requested` → líder
- `reimbursement.approved_by_leader` → RH
- `reimbursement.paid` → colaborador
- `perk.new_partner` → todos (opt-in)

---

## 8. RLS

- Cada colaborador vê **só seus** benefícios/dependentes/reembolsos
- Líder vê **subordinados diretos** apenas (sem benefício/dependente, só pendência aprovativa)
- RH com `view_benefits_all` vê tudo do tenant
- DPO vê tudo (auditoria)
- Convênios parceiros: visíveis para todos do tenant (não tem PII)

```sql
ALTER TABLE benefit_subscriptions ENABLE ROW LEVEL SECURITY;
CREATE POLICY benefit_subs_self_or_admin ON benefit_subscriptions FOR ALL USING (
  tenant_id = (current_setting('app.tenant_id', true))::uuid
  AND (
    employee_id IN (SELECT id FROM employees WHERE user_id = auth.uid())
    OR EXISTS (SELECT 1 FROM user_permissions WHERE user_id = auth.uid()
      AND permission IN ('view_benefits_all','dpo_full_access'))
  )
);
```

---

## 9. LGPD

- Dependente CPF + comprovante = dado pessoal de terceiro → exige consent específico (colaborador atesta "tenho autorização do dependente")
- Dependente PCD = dado sensível → criptografia em repouso + permission `view_dependent_pcd`
- Reembolso médico (psicólogo, terapeuta) categoria especial → líder vê só valor + categoria, não detalhe da NF
- Documentos (comprovantes) com retenção definida (5 anos pós-término)

---

## 10. Testes meta (mínimo 22)

- ✓ Catálogo respeita elegibilidade por cargo/filial
- ✓ Adesão de benefício opcional dispara webhook Domínio
- ✓ Cancelamento dispara webhook
- ✓ Dependente filho 21 anos dispara alerta IR
- ✓ Dependente PCD não aparece para líder sem permissão
- ✓ Reembolso > teto rejeita automaticamente
- ✓ Reembolso fora do prazo (> 30d) rejeita
- ✓ Aprovação líder dispara notif RH
- ✓ Aprovação RH dispara webhook Domínio
- ✓ Webhook pagamento confirma marca paid
- ✓ Convênio click registra em log + atualiza top 5
- ✓ Rating do parceiro afeta display order
- ✓ Convênio expirado some do catálogo
- ✓ RLS: tenant A não vê benefícios tenant B
- ✓ RLS: colaborador não vê outros colaboradores
- ✓ Líder vê só subordinados em pendências aprovativas
- ✓ Comprovante (PDF) só baixa via signed URL temporária
- ✓ Reembolso psicólogo: categoria visível, NF detalhe oculto pro líder
- ✓ Bulk add dependentes via CSV não duplica
- ✓ Integração Domínio offline: enfileira eventos + retry
- ✓ Dependente removido vira soft delete + audit
- ✓ Métrica de adoção por benefício calcula corretamente

---

## 11. Posicionamento comercial

Adicionar bullet na landing pillars:

> "**Portal de benefícios self-service**: seu colaborador descobre, adere e gerencia plano de saúde, VR, convênios parceiros e reembolsos sem mandar e-mail pro RH. Tudo conecta no seu Domínio sem dupla digitação."

E na lista de motivos pra escolher R2:
> "Sólides faz avaliação. Qulture faz 1:1. Senior faz folha. R2 People faz tudo isso + **portal de benefícios + dependentes + convênios + reembolso** que ninguém mais oferece nesse preço."

---

## 12. Roadmap pós-MVP

1. **M+3 · marketplace de benefícios** (R2 negocia conjunto · cliente adere com 1 click)
2. **M+6 · cartão flexível** (Caju/Flash · R2 integra saldo + extrato + bloqueios)
3. **M+9 · benefícios localizados** (Brasil + estados c/ regras CCT específicas)
4. **M+12 · IA recomenda convênios** ("colaboradores como você usaram Smart Fit, top 3")
5. **M+18 · Total Rewards Statement** anual (PDF mostrando salário + benefícios + bônus = pacote total) — alta retenção
6. **M+24 · simulador "se eu aderisse a tudo"** quanto desconta x quanto recebe

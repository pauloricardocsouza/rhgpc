# Spec D7 · Compliance & LGPD · Playbook do DPO

**Status**: especificação · pré-implementação
**Versão**: 1.0 · 17 de maio de 2026
**Escopo**: rotinas do DPO, ROPA (registro de atividades), DSAR runbook, retenção, treinamento, comunicação ANPD
**Depende de**: schema v4+ (action_log, dsar_requests), spec D4 (retention), spec D6 (incident response)

---

## 1. Papéis e governança

| Papel | Pessoa exemplo | Responsabilidades |
|---|---|---|
| **Controlador** | cada tenant (GPC, Filadélfia, etc.) | Decide finalidades e meios do tratamento |
| **Operador** | R2 Soluções Empresariais | Trata dados em nome do controlador |
| **Encarregado / DPO R2** | Carla Moreira (referência) | Canal com ANPD e titulares, supervisão interna |
| **Encarregado tenant** | Patrícia Mello (GPC) | Ponto focal LGPD no cliente |
| **Comitê de Privacidade** | DPO + CTO + Jurídico | Decisões de risco alto, aprovação de novos tratamentos |

**Reuniões**:
- Comitê mensal (1h) revisando ROPA, incidentes, DSARs pendentes
- DPO + CTO quinzenal (30min) acompanhando KPIs de compliance
- Tudo registrado em ata privada (tabela `compliance_minutes`)

---

## 2. ROPA · Registro de Atividades de Tratamento (Art. 37 LGPD)

### 2.1 Template por tratamento

Cada operação que envolve dado pessoal preenche este registro. Mantido em tabela versionada.

| Campo | Conteúdo exemplo |
|---|---|
| Atividade | "Gestão de atestados médicos" |
| Finalidade | Validar afastamentos para fins trabalhistas (CLT art 6, §1º Lei 8.213) |
| Base legal | Art 7º II + Art 11 II.f LGPD (cumprimento de obrigação legal · dado sensível para saúde ocupacional) |
| Categorias de titulares | Empregados, dependentes (vacinação) |
| Categorias de dados | Identificação, dados de saúde (CID, médico, CRM), atestado em PDF |
| Compartilhamento | Tomador operacional (acesso restrito), sistema folha (apenas dias), DPO (auditoria) |
| Transferência internacional | Não |
| Retenção | 5 anos pós-término (CLT) |
| Medidas de segurança | RLS por tenant, criptografia em repouso, OCR client-side, signed URLs |
| Responsável | Patrícia Mello (RH GPC) |
| Última revisão | 2026-04-15 |

### 2.2 Tratamentos catalogados (R2 People em GPC)

1. Cadastro de empregados (CTPS, endereço, dependentes)
2. Gestão de atestados médicos
3. Folha de pagamento e benefícios
4. Avaliações de desempenho (9-Box, PDI)
5. 1:1s e feedbacks
6. OKRs e metas
7. Movimentações (promoção, transferência, desligamento)
8. Treinamentos e certificações
9. Pesquisas (clima, eNPS) — modo anonimizado
10. Histórico de consulta (auditoria interna LGPD)
11. Autenticação e MFA (dado de login, IP, device fingerprint)
12. Comunicações internas (comunicados, notificações)
13. Onboarding (documentos da admissão)
14. Vagas internas e indicações

Tabela `processing_activities` é a fonte de verdade. UI em `/admin/lgpd/ropa`.

### 2.3 Schema

```sql
CREATE TABLE processing_activities (
  id                 uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id          uuid REFERENCES tenants(id),  -- NULL = atividade da R2 operador
  name               text NOT NULL,
  purpose            text NOT NULL,
  legal_basis        text NOT NULL,
  legal_basis_article text,                         -- "Art 7º II" ou "Art 11 II.f"
  data_subjects      text[] NOT NULL,
  data_categories    text[] NOT NULL,
  sensitive_data     boolean NOT NULL DEFAULT false,
  recipients         text[],
  international_transfer boolean DEFAULT false,
  international_country text,
  retention_policy   text NOT NULL,
  security_measures  text[],
  responsible_role   text,
  responsible_user_id uuid REFERENCES auth.users(id),
  risk_assessment    text CHECK (risk_assessment IN ('low','medium','high','critical')),
  dpia_required      boolean DEFAULT false,
  dpia_doc_url       text,
  status             text CHECK (status IN ('draft','active','suspended','retired')),
  created_at         timestamptz DEFAULT now(),
  last_reviewed_at   timestamptz,
  next_review_at     timestamptz
);
```

Revisão obrigatória anual. Trigger gera alerta P3 60 dias antes de `next_review_at`.

---

## 3. DSAR · Direito do Titular (Art. 18 LGPD)

### 3.1 Direitos cobertos

| Direito | Endpoint | Prazo legal | Prazo R2 |
|---|---|---|---|
| Confirmação de existência | RPC `dsar_confirm_existence` | 15 dias | 5 dias |
| Acesso aos dados | RPC `dsar_export` (gera ZIP em 1h) | 15 dias | 7 dias |
| Correção | UI auto-serviço + ticket | "imediato" | 5 dias |
| Anonimização/bloqueio/eliminação | RPC `dsar_anonymize` ou `dsar_erase` | 15 dias | 10 dias |
| Portabilidade | RPC `dsar_export` (formato JSON/CSV) | 15 dias | 7 dias |
| Informações sobre compartilhamento | RPC `dsar_recipients` | 15 dias | 7 dias |
| Revogação de consentimento | UI auto-serviço | imediato | imediato |
| Oposição a tratamento | Ticket revisado por DPO | 15 dias | 10 dias |

### 3.2 Fluxo

```
1. Titular abre solicitação
   - via UI auto-serviço (auth) OU
   - via formulário público dpo@solucoesr2.com.br (sem auth) OU
   - via Encarregado tenant que registra em nome do titular

2. Verificação de identidade
   - se autenticado: já validado
   - se não: prova de identidade (selfie + doc) revisada pelo DPO

3. Triagem (DPO ou auto-roteador)
   - Tipo do pedido + escopo (qual tenant)
   - Cria ticket em dsar_requests com prazo

4. Execução
   - Acesso/portabilidade: RPC export → ZIP em /storage com signed URL 7d
   - Erasure: marca soft delete + scheduling hard delete 30d (grace period)
   - Correção: dispara workflow de update (admin tenant aprova)

5. Resposta ao titular
   - E-mail com link/explicação
   - SLA respeitado, sempre comunicado quando atrasar

6. Auditoria
   - Toda ação registrada em dsar_audit_trail
   - Ticket fica no histórico permanentemente (mesmo após resolução)
```

### 3.3 Schema (consolidado)

```sql
CREATE TYPE dsar_type AS ENUM (
  'confirm','access','correct','anonymize','erase','portability',
  'recipients_info','consent_revoke','opposition'
);

CREATE TYPE dsar_status AS ENUM (
  'submitted','identity_pending','triage','in_progress',
  'completed','rejected','partial','expired'
);

CREATE TABLE dsar_requests (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id       uuid REFERENCES tenants(id),
  subject_user_id uuid REFERENCES auth.users(id),  -- NULL se titular não-autenticado
  subject_email   text NOT NULL,
  subject_cpf_hash text,                            -- hash SHA-256 pra identificação cruzada
  type            dsar_type NOT NULL,
  status          dsar_status NOT NULL DEFAULT 'submitted',
  description     text,
  scope_details   jsonb,                            -- ex: { "categories": ["medical","payroll"] }
  identity_proof_url text,
  triaged_by      uuid REFERENCES auth.users(id),
  triaged_at      timestamptz,
  assigned_to     uuid REFERENCES auth.users(id),  -- DPO ou delegado
  legal_deadline_at timestamptz NOT NULL,           -- prazo legal absoluto (15d)
  target_deadline_at timestamptz NOT NULL,          -- prazo interno (5-10d)
  response_url    text,                             -- signed URL do ZIP/relatório
  response_summary text,
  rejection_reason text,
  hard_delete_at  timestamptz,                      -- para erasures, agenda 30d
  created_at      timestamptz DEFAULT now(),
  completed_at    timestamptz,
  expires_at      timestamptz                       -- ticket arquivado após N anos
);

CREATE INDEX idx_dsar_open ON dsar_requests (legal_deadline_at)
  WHERE status NOT IN ('completed','rejected','expired');

CREATE TABLE dsar_audit_trail (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  dsar_id     uuid NOT NULL REFERENCES dsar_requests(id) ON DELETE CASCADE,
  actor_id    uuid REFERENCES auth.users(id),
  action      text NOT NULL,        -- "submitted","triaged","data_exported","erasure_scheduled"...
  details     jsonb,
  occurred_at timestamptz DEFAULT now()
);
```

### 3.4 Função `dsar_export()` (resumo)

Retorna ZIP com:
- `01_personal_data.json` (employees, users, contacts)
- `02_employment_history.json` (movements, positions, salaries)
- `03_performance.json` (avaliações, PDI, OKRs, 1:1s)
- `04_health.json` (atestados — só se titular autorizar, senão omitido com nota)
- `05_communications.json` (notificações enviadas a você)
- `06_audit.json` (logins seus, ações suas registradas)
- `07_recipients.md` (com quem compartilhamos)
- `README.md` (legenda das colunas, como ler)

Gerado em job assíncrono (worker), notificado por e-mail quando pronto. TTL signed URL = 7 dias.

---

## 4. Retenção e descarte (consolidado)

(Visão de DPO; detalhamento operacional em spec D4 §3)

```sql
CREATE TABLE retention_policies (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  data_category   text NOT NULL,
  retention_hot   interval NOT NULL,    -- janela quente (online)
  retention_cold  interval NOT NULL,    -- janela frio (arquivo)
  hard_delete_after interval,           -- NULL = nunca apagar
  legal_basis     text NOT NULL,
  applies_to_tables text[] NOT NULL,
  reviewed_at     timestamptz,
  active          boolean DEFAULT true
);
```

Job mensal `apply_retention_policies()`:
1. Move registros de quente → arquivo (UPDATE flag + reduz índices)
2. Para categoria sem regra fiscal, dispara DSAR-erase automático após `hard_delete_after`
3. Gera relatório em `retention_runs` (rows movidas, rows apagadas)
4. Notifica DPO + Encarregado tenant

---

## 5. Consentimentos

| Tratamento | Base legal | Requer consentimento? |
|---|---|---|
| Cadastro CLT | Art 7º II (obrigação legal) | Não |
| Folha | Art 7º II + V (contrato + obrigação legal) | Não |
| Atestados | Art 11 II.f (saúde ocupacional) | Não, mas auditoria reforçada |
| Avaliações | Art 7º V (execução do contrato) | Não |
| Pesquisas anônimas | Art 7º IX (legítimo interesse) | Não, opt-out disponível |
| Pesquisas identificadas | Art 7º I (consentimento) | **Sim** |
| Foto perfil (uso interno) | Art 7º V | Não |
| Foto perfil (uso comunicação externa) | Art 7º I | **Sim** |
| Comunicação marketing R2 | Art 7º I | **Sim** opt-in |
| Cookies analytics | Art 7º IX + IX considerando AdTech | Opt-in via banner |

Tabela `consents`:

```sql
CREATE TABLE consents (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id       uuid NOT NULL REFERENCES auth.users(id),
  purpose_code  text NOT NULL,        -- "marketing","analytics","identified_survey"
  granted       boolean NOT NULL,
  granted_at    timestamptz NOT NULL DEFAULT now(),
  revoked_at    timestamptz,
  expires_at    timestamptz,          -- consentimento por tempo determinado
  evidence_ip   inet,
  evidence_ua   text,
  evidence_method text,               -- "checkbox","banner","email_confirm"
  policy_version text NOT NULL,        -- versão da política aceita
  notes         text
);
```

Banner UI guarda toggle individual por propósito. Revogação aplica em 24h.

---

## 6. KPIs de compliance (dashboard DPO)

| KPI | Threshold | Frequência |
|---|---|---|
| DSAR média de resposta | < 5 dias | semanal |
| DSARs em atraso (> prazo legal) | 0 | diário |
| DSARs pendentes triagem > 48h | 0 | diário |
| Incidentes P1/P2 últimos 90d | trending down | mensal |
| Atividades ROPA sem revisão em 13m | 0 | mensal |
| Consentimentos revogados últimos 30d | trending | mensal |
| Treinamentos atrasados (equipe R2) | 0 | mensal |
| Honeytokens acionados | 0 | tempo real |
| Storage de dados sensíveis ainda online após retenção | 0 | mensal |
| Tenants sem Encarregado designado | 0 | mensal |

UI `/admin/lgpd/dashboard`.

---

## 7. Treinamento

| Audiência | Conteúdo | Frequência |
|---|---|---|
| Equipe R2 (toda) | LGPD básico + práticas de código seguro | onboarding + anual |
| Engenharia | OWASP, RLS, secrets handling | onboarding + semestral |
| Suporte | Como tratar DSAR e dúvida de titular | onboarding + anual |
| Liderança | Cenários de incidente, comunicação ANPD | anual |
| Tenants (Encarregados) | Como operar o produto em compliance | a cada contratação + anual |

Tracking em tabela `compliance_trainings`. Atraso > 30d gera alerta para gestor.

---

## 8. Comunicação com ANPD

### 8.1 Quando

- **Vazamento confirmado** de dados pessoais (Art 48): em até 48h
- **Resposta a consulta** da ANPD: prazo definido pelo ofício
- **Submissão proativa de DPIA** (avaliação de impacto) para tratamento de alto risco

### 8.2 Quem

Encarregado/DPO R2 é o único ponto de contato. Equipe redireciona qualquer contato externo para `dpo@solucoesr2.com.br`.

### 8.3 Modelos

- `templates/anpd_breach_notification.md` · formulário Art 48
- `templates/anpd_ropa_summary.pdf` · síntese ROPA para consulta
- `templates/anpd_dpia.md` · avaliação de impacto

---

## 9. Sub-operadores (sub-processors)

R2 People depende de:

| Sub-operador | Função | Dados expostos | Localização | Contrato |
|---|---|---|---|---|
| Supabase | Banco + Auth + Storage | Todos | US-East/EU | DPA assinado |
| Vercel | Hospedagem app | Logs HTTP + nomes | Global edge | DPA padrão |
| Logflare | Logs centralizados | Logs estruturados (sem PII) | US | DPA padrão |
| SendGrid | E-mail transacional | Endereço + nome | US | DPA + EU SCC |
| ClamAV (auto-hospedado) | Antivírus uploads | Arquivos temporários | mesma região | n/a (self) |
| Backblaze B2 | Backups encriptados | Dumps cifrados | EU | DPA padrão |

Lista publicada em `solucoesr2.com.br/lgpd/sub-operadores` com obrigação de avisar tenants com 30d de antecedência sobre mudanças.

---

## 10. Tabelas de governança

```sql
CREATE TABLE compliance_minutes (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  meeting_type text CHECK (meeting_type IN ('committee_monthly','dpo_cto_biweekly','tenant_review','adhoc')),
  meeting_date date NOT NULL,
  attendees    text[],
  agenda       text,
  decisions    text,
  action_items jsonb,           -- [{ owner, action, due }]
  next_meeting date,
  doc_url      text,
  created_by   uuid REFERENCES auth.users(id),
  created_at   timestamptz DEFAULT now()
);

CREATE TABLE compliance_trainings (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id     uuid NOT NULL REFERENCES auth.users(id),
  audience    text NOT NULL,
  course_code text NOT NULL,
  course_version text NOT NULL,
  completed_at timestamptz,
  score       numeric,
  expires_at  timestamptz NOT NULL,
  evidence_url text
);

CREATE TABLE retention_runs (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  ran_at      timestamptz DEFAULT now(),
  policy_id   uuid REFERENCES retention_policies(id),
  rows_moved_to_cold int,
  rows_hard_deleted int,
  errors_count int,
  notes       text
);
```

---

## 11. Testes meta (mínimo 25)

- ✓ DSAR submitted gera linha em `dsar_requests` + audit trail
- ✓ DSAR sem identidade verificada não exporta dado
- ✓ DSAR `access` gera ZIP completo em < 1h
- ✓ DSAR `erase` agenda hard delete em 30d
- ✓ DSAR `erase` revertível em <30d (soft delete pattern)
- ✓ DSAR após 15d sem completar dispara alerta P2 ao DPO
- ✓ ROPA sem revisão há 13 meses dispara alerta P3
- ✓ Consentimento revogado bloqueia próximo envio em < 24h
- ✓ Consentimento expirado não permite tratamento associado
- ✓ Foto marketing externa sem consentimento → bloqueado no export
- ✓ Pesquisa identificada sem consentimento → bloqueada
- ✓ Retention job remove dados expirados (não-fiscais)
- ✓ Retention job preserva folha (regra fiscal, nunca apaga)
- ✓ Sub-operador novo dispara comunicação aos tenants
- ✓ Treinamento expirado bloqueia acesso a área restrita (engenheiro sem OWASP atualizado)
- ✓ DSAR-export omite atestado se titular não autorizou na request
- ✓ Encarregado tenant não-designado mostra warning no painel tenant
- ✓ ANPD notification gera evidência arquivada em incidents.postmortem_url
- ✓ Honeytoken accionado registra em honeytoken_hits + alerta P1
- ✓ Tabela `dsar_audit_trail` recebe registro de cada transição de status
- ✓ Consent banner respeita opt-out (não carrega analytics se revogado)
- ✓ DPIA marcado como required força bloqueio de ativação do tratamento
- ✓ ROPA com risk_assessment='critical' exige aprovação do Comitê
- ✓ retention_runs sempre é registrado mesmo se 0 rows afetadas
- ✓ Tabela `consents` mantém histórico completo (não UPDATE, sempre INSERT)

---

## 12. Direitos não automatizados (Q&A frequente)

- **Posso ver tudo que coletam sobre mim?** Sim, via DSAR `access`. Em até 7 dias úteis você recebe um ZIP com tudo. Para dado de saúde, pedimos confirmação adicional.
- **Posso pedir para apagarem tudo?** Sim, exceto dados que somos obrigados a guardar por lei (folha, 5 anos pós-término CLT). Damos 30 dias de janela para você reverter.
- **Posso saber com quem compartilham?** Sim, via DSAR `recipients_info` ou na nossa página pública de sub-operadores.
- **Posso revogar consentimentos?** Sim, na sua área "Privacidade". Aplicamos em 24h.
- **Posso reclamar à ANPD?** Sim, sempre. Mas tente nosso DPO primeiro: `dpo@solucoesr2.com.br`, respondemos em até 5 dias.

UI pública `/lgpd/seus-direitos` traduz isto em linguagem simples.

---

## 13. Roadmap pós-MVP

1. **DPIA automatizado** com checklist guiado.
2. **Banner de cookies por região** (Brasil + LGPD, UE + GDPR se expandir).
3. **Auto-tagging de PII** em logs via DLP ML (alerta se PII detectado).
4. **Selo / certificação** (ISO 27701 ou similar de privacidade).
5. **Audit-as-a-Service**: tenant compra horas extras do DPO R2.

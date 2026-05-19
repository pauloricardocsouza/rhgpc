# Spec M18 · Compliance & Treinamentos · NR-7 / NR-6 / NR-1 / Termos / Documentos

**Status**: especificação · pré-implementação
**Versão**: 1.0 · 18 de maio de 2026
**Escopo**: gestão de obrigações trabalhistas não-fiscais (ASO, EPI, treinamentos NR, antiassédio, LGPD), termos versionados c/ aceite, documentos pessoais com alerta de vencimento
**Depende de**: spec D7 (LGPD), schema v9+ (employees, evaluations), spec M12 (notif), spec D8 (RLS)

---

## 1. Por que isso existe (e não está no Domínio)

Domínio cuida de **folha + obrigações fiscais** (INSS, FGTS, eSocial). Mas existe uma camada de **compliance trabalhista não-fiscal** que:
- O Domínio não cobre (ASO médico, EPI assinado, treinamento de brigada)
- Hoje vive em pasta de Word + planilha + e-mail
- Vira multa pesada em fiscalização do MTE
- O líder não sabe quem da equipe está em dia

R2 People = **fonte única de verdade** para essas obrigações. Cada item tem:
- Documento digital (PDF anexo)
- Data de validade
- Responsável por renovar
- Alerta automático antes de vencer
- Histórico auditável (NR-1: registro perene)

---

## 2. Áreas cobertas

### 2.1 ASO · Atestado de Saúde Ocupacional (NR-7 / PCMSO)

**Tipos exigidos pela NR-7**:
- Admissional (antes de iniciar atividade)
- Periódico (anual / bianual conforme risco)
- Retorno ao trabalho (após afastamento > 30 dias)
- Mudança de função
- Demissional (até 10 dias da rescisão)

**Campos**:
- Tipo
- Data realização
- Data validade (calculada pelo tipo + risco)
- Médico responsável (CRM + UF)
- Conclusão (apto / inapto / apto com restrição)
- Restrições (texto livre)
- PDF assinado anexo (criptografado)
- Empresa de medicina ocupacional (cadastro)

**Alertas**:
- 60 dias antes vencer · líder + RH
- 30 dias · RH
- 7 dias · RH + colaborador (lembrete agendar)
- Vencido · alerta P2 (multa imediata em fiscalização)

### 2.2 EPI · Equipamento de Proteção Individual (NR-6)

**Workflow**:
1. Cargo tem **matriz de EPIs obrigatórios** (capacete, bota, luva, óculos, abafador, etc)
2. Quando colaborador admitido, R2 gera ficha de entrega
3. RH/almoxarifado registra entrega: data, CA (Certificado de Aprovação), validade
4. Colaborador **assina digitalmente** (touch + senha + timestamp + IP)
5. Renovação automática quando validade vence
6. Registro perene (NR-1: 20 anos pós-término)

**Campos por entrega**:
- EPI (capacete tipo II, bota PVC cano longo, etc)
- CA + validade
- Quantidade entregue
- Data entrega
- Assinatura digital do colaborador (hash + timestamp)
- Responsável pela entrega
- Próxima renovação prevista

### 2.3 Treinamentos obrigatórios

| Treinamento | Frequência | Carga horária mínima | Quem se aplica |
|---|---|---|---|
| **NR-1 · Disposições gerais** | admissional | 4h | todos |
| **NR-6 · EPI** | admissional + bienal | 4h | quem usa EPI |
| **NR-10 · Eletricidade** | bienal | 40h (básico) ou 80h (complementar) | eletricistas, manutenção |
| **NR-11 · Transporte/Empilhadeira** | bienal | 16-24h | operadores |
| **NR-12 · Máquinas** | inicial + reciclagem | varia | operadores |
| **NR-17 · Ergonomia** | conforme AET | 4h | escritório repetitivo |
| **NR-20 · Inflamáveis** | inicial + bienal | 16h | quem manuseia |
| **NR-23 · Brigada incêndio** | anual | 16h | brigadistas |
| **NR-35 · Trabalho em altura** | inicial + bienal | 8h | quem trabalha > 2m |
| **Antiassédio** (Lei 14.457) | anual | 2h | todos |
| **LGPD** (interno) | onboarding + anual | 1h | todos |
| **Compliance** (anticorrupção, código de ética) | anual | 1-2h | todos |
| **Brigada de emergência** | bienal | 8h | brigadistas |

**Cada treinamento tem**:
- Curso (vídeo/PDF/presencial)
- Avaliação obrigatória (passar = ≥ 70%)
- Certificado gerado em PDF c/ hash (validação pública por QR code)
- Validade
- Próxima reciclagem agendada
- Histórico perene em `compliance_trainings` (já existe no v11, expandir)

### 2.4 Termos e políticas versionadas

Toda política que o colaborador precisa aceitar:

| Termo | Quando aceitar | Versionamento |
|---|---|---|
| Termo de uso do sistema R2 | primeiro login | a cada mudança v |
| Política de privacidade R2 (LGPD) | primeiro login | a cada mudança v |
| Código de ética da empresa | admissional + anual | a cada release |
| Política antiassédio | admissional + anual | a cada release |
| Termo de uso de equipamento (notebook empresa) | entrega | a cada renovação |
| Acordo de confidencialidade (NDA) | admissional para áreas sensíveis | uma vez |
| Política de mídia social | admissional + anual | a cada release |
| Termo de imagem (foto interna OK, marketing externo opt-in) | admissional | uma vez + revogável |

**Cada aceite registra**:
- Versão do documento
- Hash SHA-256 do PDF
- Timestamp
- IP
- User agent
- Geolocation aproximada (cidade · LGPD opt-in)

Mudança de versão → R2 força novo aceite na próxima sessão.

### 2.5 Documentos pessoais com vencimento

| Documento | Quem responsabiliza | Alerta |
|---|---|---|
| CTPS · número e série | RH (admissão) | n/a |
| RG / CIN | colaborador | quando muda |
| CPF | nunca expira | n/a |
| **CNH** (motoristas) | colaborador | 90/30/7d antes vencer |
| Carteira nacional saúde / vacinação | depende função | varia |
| **Cartão CNH-AT** (NR-11 operador empilhadeira) | empresa | 90/30/7d |
| Comprovante endereço | colaborador | atualizar 1x/ano |
| Reservista | masculino até 45 | uma vez |
| Título de eleitor | colaborador | quando muda |
| Diploma / certificado profissão regulamentada (CRM, CREA, OAB, etc) | colaborador | anual de comprovação |

Cada doc pode ter upload PDF/foto criptografado.

### 2.6 Exames médicos periódicos adicionais (além ASO)

Para funções de risco:
- Audiometria (a cada 6m exposição > 85dB)
- Espirometria (anual exposição agentes químicos)
- Hemograma (semestral químicos)
- Acuidade visual (anual digitadores)
- ECG (anual altas tensões)

Calendário integrado com NR-7 do médico ocupacional.

### 2.7 Periculosidade / Insalubridade

R2 só **lista** (não calcula adicional · isso é Domínio):
- Quais cargos da empresa são periculosos/insalubres
- Quais EPIs neutralizam (importante: NR-15 + 16 permitem reduzir adicional se EPI eficaz comprovado)
- Laudo LTCAT vigente (PDF + validade)
- PPP (Perfil Profissiográfico Previdenciário) por colaborador

---

## 3. Schema (estende v11 compliance_trainings)

```sql
-- 3.1 ASO
CREATE TABLE IF NOT EXISTS medical_exams_aso (
  id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id           uuid NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  employee_id         uuid NOT NULL REFERENCES employees(id) ON DELETE CASCADE,
  exam_type           text NOT NULL CHECK (exam_type IN ('admissional','periodico','retorno','mudanca_funcao','demissional')),
  exam_date           date NOT NULL,
  valid_until         date NOT NULL,
  physician_name      text NOT NULL,
  physician_crm       text NOT NULL,
  physician_uf        text NOT NULL,
  clinic_name         text,
  conclusion          text NOT NULL CHECK (conclusion IN ('apto','inapto','apto_com_restricao')),
  restrictions        text,
  pdf_storage_key     text,
  pdf_sha256          text,
  created_by          uuid REFERENCES auth.users(id),
  created_at          timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX idx_aso_employee ON medical_exams_aso (employee_id, exam_date DESC);
CREATE INDEX idx_aso_expiring_soon ON medical_exams_aso (valid_until)
  WHERE conclusion IN ('apto','apto_com_restricao');

-- 3.2 EPI · matriz por cargo + entregas
CREATE TABLE IF NOT EXISTS epi_catalog (
  id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id           uuid NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  name                text NOT NULL,           -- "Bota PVC cano longo branca"
  ca_number           text NOT NULL,           -- "CA 12345"
  ca_valid_until      date,
  description         text,
  active              boolean DEFAULT true,
  UNIQUE (tenant_id, name, ca_number)
);

CREATE TABLE IF NOT EXISTS epi_required_by_position (
  position_id         uuid NOT NULL REFERENCES positions(id) ON DELETE CASCADE,
  epi_id              uuid NOT NULL REFERENCES epi_catalog(id) ON DELETE CASCADE,
  qty_per_period      int NOT NULL DEFAULT 1,
  replacement_months  int NOT NULL DEFAULT 12,
  PRIMARY KEY (position_id, epi_id)
);

CREATE TABLE IF NOT EXISTS epi_deliveries (
  id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id           uuid NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  employee_id         uuid NOT NULL REFERENCES employees(id) ON DELETE CASCADE,
  epi_id              uuid NOT NULL REFERENCES epi_catalog(id),
  delivered_qty       int NOT NULL,
  delivered_at        timestamptz NOT NULL DEFAULT now(),
  delivered_by        uuid REFERENCES auth.users(id),
  next_replacement_at date,
  signature_hash      text,                    -- hash da assinatura digital
  signature_timestamp timestamptz,
  signature_ip        inet,
  signature_pdf_key   text,                    -- PDF da ficha assinada
  notes               text
);

CREATE INDEX idx_epi_employee ON epi_deliveries (employee_id, delivered_at DESC);

-- 3.3 Treinamentos (extensão de compliance_trainings v11)
ALTER TABLE compliance_trainings
  ADD COLUMN IF NOT EXISTS norm text,                      -- 'NR-10', 'NR-35', 'LGPD', etc
  ADD COLUMN IF NOT EXISTS modality text CHECK (modality IN ('online','presencial','blended')),
  ADD COLUMN IF NOT EXISTS workload_hours numeric,
  ADD COLUMN IF NOT EXISTS instructor_name text,
  ADD COLUMN IF NOT EXISTS instructor_credential text,     -- engenheiro segurança, médico, etc
  ADD COLUMN IF NOT EXISTS certificate_pdf_key text,
  ADD COLUMN IF NOT EXISTS certificate_qr_code text,       -- URL pública de verificação
  ADD COLUMN IF NOT EXISTS pass_score numeric;             -- nota mínima (default 70)

-- 3.4 Termos e políticas versionados
CREATE TABLE IF NOT EXISTS policy_documents (
  id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id           uuid NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  policy_code         text NOT NULL,             -- 'tos_r2','privacy_r2','codigo_etica','antiassedio','nda','imagem'
  version             text NOT NULL,              -- 'v3.2', 'v2026.05'
  title               text NOT NULL,
  body_markdown       text,                       -- texto integral
  pdf_storage_key     text,
  pdf_sha256          text NOT NULL,
  required_for        text[] NOT NULL,            -- ['all','admin','field_only',etc]
  renewal_period      interval,                   -- NULL = uma vez; '1 year' = anual
  effective_from      date NOT NULL,
  superseded_by       uuid REFERENCES policy_documents(id),
  created_at          timestamptz NOT NULL DEFAULT now(),
  UNIQUE (tenant_id, policy_code, version)
);

CREATE TABLE IF NOT EXISTS policy_acceptances (
  id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id           uuid NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  user_id             uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  policy_id           uuid NOT NULL REFERENCES policy_documents(id) ON DELETE RESTRICT,
  accepted_at         timestamptz NOT NULL DEFAULT now(),
  ip                  inet,
  user_agent          text,
  geo_city            text,                      -- LGPD opt-in
  UNIQUE (user_id, policy_id)
);

CREATE INDEX idx_acceptances_user ON policy_acceptances (user_id, accepted_at DESC);

-- 3.5 Documentos pessoais
CREATE TABLE IF NOT EXISTS personal_documents (
  id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id           uuid NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  employee_id         uuid NOT NULL REFERENCES employees(id) ON DELETE CASCADE,
  doc_type            text NOT NULL,             -- 'cnh','rg','cpf','reservista','diploma_crm','etc'
  number              text,                       -- número/série/registro
  issuer              text,                       -- 'Detran-BA','Polícia Civil', etc
  issued_at           date,
  valid_until         date,
  pdf_storage_key     text,
  notes               text,
  uploaded_at         timestamptz NOT NULL DEFAULT now(),
  uploaded_by         uuid REFERENCES auth.users(id)
);

CREATE INDEX idx_personal_docs_employee ON personal_documents (employee_id, doc_type);
CREATE INDEX idx_personal_docs_expiring
  ON personal_documents (valid_until)
  WHERE valid_until IS NOT NULL;

-- 3.6 LTCAT / Periculosidade / PPP
CREATE TABLE IF NOT EXISTS ltcat_documents (
  id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id           uuid NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  branch_id           uuid REFERENCES branches(id),
  effective_from      date NOT NULL,
  valid_until         date NOT NULL,
  responsible_engineer text NOT NULL,
  engineer_crea       text NOT NULL,
  pdf_storage_key     text,
  notes               text
);

CREATE TABLE IF NOT EXISTS position_hazard_classification (
  position_id         uuid PRIMARY KEY REFERENCES positions(id) ON DELETE CASCADE,
  is_periculosa       boolean DEFAULT false,
  periculosidade_basis text,                    -- 'inflamaveis','explosivos','energia_eletrica','seguranca','radioativos'
  is_insalubre        boolean DEFAULT false,
  insalubridade_grade text,                    -- 'minimo','medio','maximo'
  insalubridade_basis text,                    -- 'ruido','calor','agentes_quimicos','biologicos'
  epi_neutralizes     boolean DEFAULT false,
  neutralization_evidence_pdf text,
  reviewed_at         timestamptz,
  reviewed_by         uuid REFERENCES auth.users(id)
);
```

---

## 4. RPCs principais

```sql
-- 4.1 Próximos ASOs a vencer (alerta RH)
rpc_aso_expiring(p_tenant_id uuid, p_days int DEFAULT 60)
  RETURNS TABLE (employee_id, full_name, exam_date, valid_until, days_remaining)

-- 4.2 Compliance score do colaborador (% de obrigações em dia)
rpc_employee_compliance_score(p_tenant_id, p_employee_id)
  RETURNS TABLE (
    score numeric,                              -- 0-100
    aso_status text,                           -- 'ok','expiring','expired','missing'
    epi_status text,
    trainings_status jsonb,                    -- {nr_35:'ok',antiassedio:'expired',...}
    pending_policies int,
    pending_documents int
  )

-- 4.3 Painel de compliance do tenant (cockpit RH)
rpc_tenant_compliance_dashboard(p_tenant_id uuid)
  RETURNS TABLE (
    total_employees int,
    asos_ok int, asos_expiring int, asos_expired int,
    epi_pending_signatures int,
    trainings_expired int,
    policies_pending_acceptance int,
    documents_expiring_30d int,
    ltcat_status text
  )

-- 4.4 Forçar aceite de política nova (após release de versão)
rpc_policy_force_acceptance(p_tenant_id, p_policy_id)
  RETURNS int  -- número de usuários afetados

-- 4.5 Gerar certificado PDF c/ QR code
rpc_training_issue_certificate(p_training_id)
  RETURNS TABLE (pdf_url text, qr_verify_url text)

-- 4.6 Verificação pública de certificado (QR code)
rpc_certificate_verify(p_qr_code text)
  RETURNS TABLE (valid boolean, employee_name text, training_name text, issued_at date, expires_at date)
```

---

## 5. UI · página `r2_people_compliance.html` (cockpit RH)

### 5.1 Estrutura

**Hero**: compliance score agregado do tenant (média dos colaboradores)

**5 abas**:

| Aba | Conteúdo |
|---|---|
| **ASOs** | tabela colaborador × tipo × vencimento c/ filtro "vencendo em 30/60/90d" |
| **EPIs** | matriz cargo × EPI + lista pendentes de assinatura + estoque (futuro) |
| **Treinamentos** | grade obrigatórios × colaborador (heatmap verde/amber/red) |
| **Termos & Políticas** | gerenciar versões + ver % de aceite por documento |
| **Documentos pessoais** | lista vencimentos próximos (CNH, etc) + upload em batch |

### 5.2 Drill-down por colaborador

Em `r2_people_colaborador.html` adicionar aba **Compliance**:
- Mini-score (0-100)
- Lista de cada obrigação com status badge
- Botão "Cobrar pendência" (envia notif via M12)
- Histórico completo (audit)

### 5.3 Drill-down por líder

Em `r2_people_admin_dashboard.html` adicionar card **"Compliance da equipe"**:
- N colaboradores fora de conformidade
- Top 3 pendências
- Link "Cobrar todos"

---

## 6. Notificações via M12

Eventos disparados:
- `aso.expiring` (60/30/7d) → colaborador + líder + RH
- `aso.expired` → RH (P2)
- `epi.delivery_required` → almoxarifado
- `training.expiring` → colaborador + RH
- `policy.new_version_published` → todos os afetados (force aceite)
- `document.expiring` → colaborador (CNH em 30d, etc)
- `ltcat.expiring` → eng segurança + RH (180d)

---

## 7. Integração com Domínio (via M16)

| Evento Domínio | Reflete em M18 |
|---|---|
| Admissão | dispara wizard "agendar ASO admissional + entregar EPIs + força aceite políticas" |
| Demissão | gera ASO demissional (10d) + devolução EPIs + revoga aceites |
| Mudança função | dispara ASO de mudança de função |
| Afastamento > 30d | ao retornar, agenda ASO de retorno |

Tudo configurável.

---

## 8. RLS

```sql
ALTER TABLE medical_exams_aso ENABLE ROW LEVEL SECURITY;
CREATE POLICY aso_view ON medical_exams_aso FOR SELECT USING (
  tenant_id = (current_setting('app.tenant_id', true))::uuid
  AND (
    -- Próprio colaborador vê seu ASO
    employee_id IN (SELECT id FROM employees WHERE user_id = auth.uid())
    -- RH + DPO + médico ocupacional
    OR EXISTS (SELECT 1 FROM user_permissions WHERE user_id = auth.uid()
      AND permission IN ('view_medical_aso','dpo_full_access'))
  )
);

-- Conclusão "inapto" tem visibilidade ainda mais restrita
-- (líder vê só "apto/restrição", não "inapto" sem permissão)
```

Documentos pessoais (CNH, RG) só o próprio colaborador + RH com `view_personal_documents`.

LTCAT visível por todos (informativo).

---

## 9. Testes meta (mínimo 20)

- ✓ ASO admissional sem registro bloqueia início de atividade (alerta P2)
- ✓ ASO próximo de vencer dispara notif em 60d/30d/7d
- ✓ Líder vê "apto/restrição" mas não "inapto" sem permissão
- ✓ EPI entregue cria ficha PDF + signature_hash imutável
- ✓ Cargo sem matriz de EPI permite cadastrar matriz default
- ✓ Treinamento NR-10 expirado bloqueia colaborador de função elétrica (regra opcional)
- ✓ Certificado PDF tem QR code que valida publicamente
- ✓ Política nova versão força aceite na próxima sessão
- ✓ Aceite registra IP + UA + timestamp + hash do PDF
- ✓ CNH vencida de motorista dispara alerta P2 (não pode dirigir)
- ✓ Compliance score 0-100 calcula corretamente
- ✓ Painel de compliance do tenant agrega tudo
- ✓ Integração Domínio: admissão dispara wizard
- ✓ Integração Domínio: demissão dispara ASO demissional 10d
- ✓ RLS: tenant A não vê ASO do tenant B
- ✓ RLS: líder não vê inapto sem perm
- ✓ Audit log: cada ação grava em action_log
- ✓ LTCAT vencido alerta engenheiro + RH 180d antes
- ✓ Documentos pessoais sem perm: próprio colaborador OK, outros não
- ✓ Bulk import: CSV de 1000 employees + matriz EPI sem timeout

---

## 10. Posicionamento comercial

Atualizar landing/pricing com mais um diferencial:

> "Sólides faz avaliação. Qulture faz 1:1. Senior faz folha. **R2 People faz tudo isso + a única plataforma que te mantém em dia com NR-7, NR-6, LGPD e termos versionados — sem você precisar lembrar.**"

Bullet adicional na landing pillars:
- "Compliance trabalhista por arquitetura: ASO, EPI, treinamentos NR, termos · com alertas automáticos antes da multa do MTE"

---

## 11. Roadmap pós-MVP

1. **M+3 · integração com SESMT externo** (empresa terceirizada que faz ASO) via API
2. **M+6 · biometria para assinatura EPI** (impressão digital mobile)
3. **M+9 · IA recomenda renovações** (com base em padrão de absenteísmo, sugere antecipar exame)
4. **M+12 · marketplace de cursos NR** (parceria com SENAI/SESI/etc, R2 vira hub de aquisição + tracking)
5. **M+18 · auditoria automatizada** (relatório PDF mensal pra cumprir auditoria MTE)

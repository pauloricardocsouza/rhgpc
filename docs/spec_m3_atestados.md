# Spec · M3 · Atestados Médicos

**Status:** pronto para execução em ambiente com Postgres 16 + worker Python
**Pré-requisitos:** M1 aplicado (job_roles, permission_profiles), worker FastAPI rodando
**Estimativa:** 2 sessões (~6-8h em ambiente preparado)

---

## 1. Objetivo

Portar para Next.js o **módulo completo de Atestados** desenhado no rhgpc · 4 telas + schema v4 §5 já blueprintado:

| Tela origem | Página Next.js destino | Persona |
|---|---|---|
| [r2_people_atestados.html](../r2_people_atestados.html) | `/atestados` | RH (Patrícia) |
| [r2_people_atestado_envio_lider.html](../r2_people_atestado_envio_lider.html) | `/atestados/enviar` | Líder (João, Sandra) |
| [r2_people_atestado_validacao_dp.html](../r2_people_atestado_validacao_dp.html) | `/atestados/validar` | DP (Patrícia) |
| [r2_people_atestado_colaborador.html](../r2_people_atestado_colaborador.html) | `/minha-jornada/atestados` | Colaborador (Fernanda) |

---

## 2. Regra-chave de produto · LGPD Art. 11

Categoria especial de dados sensíveis. Três princípios duros:

1. **Líder envia mas não vê depois.** Após upload, o líder perde acesso ao conteúdo. Tem direito apenas a `protocol`, `status`, `certificate_type`, iniciais do colaborador (ex: "F. Lima") e `days_off`. Não vê CID, não vê PDF, não vê nome do médico.
2. **CID-10 só pro DP** com permission `view_medical_cid`. Nem o próprio colaborador vê em listas (só ao baixar o documento original).
3. **OCR roda client-side** (Tesseract WASM). Imagem nunca sai do navegador para serviço externo de OCR.

A garantia é **arquitetural** (RLS + RPC limitada), não cosmética.

---

## 3. Schema novo

Portar diretamente de [r2_people_schema_v4.sql](../r2_people_schema_v4.sql) §5 e [r2_people_medical_certificates_schema.sql](../r2_people_medical_certificates_schema.sql) (versão standalone).

### 3.1 Migration `00410_m3_schema_medical_certificates.sql`

```sql
-- Enums
DO $$ BEGIN CREATE TYPE certificate_type AS ENUM (
  'consulta', 'doenca_propria', 'doenca_familiar', 'acidente_trabalho',
  'doacao_sangue', 'gestacao', 'paternidade', 'casamento', 'falecimento',
  'cirurgia', 'fisioterapia', 'outros'
); EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN CREATE TYPE certificate_status AS ENUM (
  'pending_validation',  -- aguardando DP
  'validated',           -- DP aprovou
  'rejected',            -- DP rejeitou
  'expired_review'       -- não validado em 7 dias
); EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN CREATE TYPE ocr_quality AS ENUM (
  'excellent',  -- 95%+ confiança
  'good',       -- 80-95%
  'fair',       -- 60-80%
  'poor'        -- <60%, exige revisão manual
); EXCEPTION WHEN duplicate_object THEN NULL; END $$;

CREATE TABLE IF NOT EXISTS medical_certificates (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id       UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,

  -- Identificação humana
  protocol        VARCHAR(40) NOT NULL,                  -- 'ATD-2026-04-28-3D72A'

  -- Quem é o atestado
  employee_id     UUID NOT NULL REFERENCES app_users(id),

  -- Quem submeteu (líder, RH ou o próprio colaborador)
  submitter_id    UUID NOT NULL REFERENCES app_users(id),
  submitted_via   VARCHAR(20) NOT NULL,                  -- 'leader', 'self', 'hr_paper'

  -- Conteúdo (categoria especial · acesso restrito)
  certificate_type certificate_type NOT NULL DEFAULT 'doenca_propria',
  cid_code        VARCHAR(10),                           -- M54.5, J11.1
  cid_description VARCHAR(240),                          -- 'Dor lombar baixa'
  doctor_name     VARCHAR(160),
  doctor_crm      VARCHAR(20),
  hospital_clinic VARCHAR(200),

  -- Período
  issued_at       DATE NOT NULL,                         -- data do atestado
  starts_at       DATE NOT NULL,                         -- início do afastamento
  ends_at         DATE NOT NULL,                         -- fim do afastamento
  days_off        INT GENERATED ALWAYS AS (ends_at - starts_at + 1) STORED,

  -- Storage do documento original (bucket privado)
  file_storage_path TEXT,                                -- 'medical/<tenant>/<year>/<id>.pdf'
  file_size_bytes BIGINT,
  file_mime       VARCHAR(60),

  -- OCR
  ocr_extracted   JSONB,                                 -- output bruto do Tesseract
  ocr_quality     ocr_quality,
  ocr_confidence  NUMERIC(4,3),                          -- 0.000 a 1.000

  -- Workflow
  status          certificate_status NOT NULL DEFAULT 'pending_validation',
  validated_at    TIMESTAMPTZ,
  validated_by    UUID REFERENCES app_users(id),
  rejection_reason TEXT,

  -- Movimentação automática gerada (se days_off >= 3)
  auto_movement_id UUID,                                 -- FK p/ movements quando M2 estiver pronto

  created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT now(),

  UNIQUE (tenant_id, protocol),
  CONSTRAINT mc_dates_ordered CHECK (ends_at >= starts_at),
  CONSTRAINT mc_cid_format CHECK (cid_code IS NULL OR cid_code ~ '^[A-Z][0-9]{2}(\.[0-9]+)?$')
);

CREATE INDEX IF NOT EXISTS idx_mc_tenant ON medical_certificates(tenant_id);
CREATE INDEX IF NOT EXISTS idx_mc_employee ON medical_certificates(employee_id, starts_at DESC);
CREATE INDEX IF NOT EXISTS idx_mc_submitter ON medical_certificates(submitter_id);
CREATE INDEX IF NOT EXISTS idx_mc_pending ON medical_certificates(tenant_id, status, created_at) WHERE status = 'pending_validation';

-- Trigger de protocolo
CREATE OR REPLACE FUNCTION mc_generate_protocol() RETURNS TRIGGER LANGUAGE plpgsql AS $$
DECLARE v_suffix TEXT;
BEGIN
  IF NEW.protocol IS NULL OR NEW.protocol = '' THEN
    v_suffix := upper(substr(encode(gen_random_bytes(3), 'hex'), 1, 5));
    NEW.protocol := 'ATD-' || to_char(now(), 'YYYY-MM-DD') || '-' || v_suffix;
  END IF;
  RETURN NEW;
END; $$;

CREATE TRIGGER trg_mc_protocol BEFORE INSERT ON medical_certificates
  FOR EACH ROW EXECUTE FUNCTION mc_generate_protocol();

-- RLS (catalogo de policies separadas para deixar evidente)
ALTER TABLE medical_certificates ENABLE ROW LEVEL SECURITY;

-- Policy: DP vê todos do próprio tenant
CREATE POLICY mc_dp_select ON medical_certificates FOR SELECT
  USING (tenant_id = current_tenant_id() AND user_has_permission('view_medical_cid'));

-- Policy: próprio colaborador vê os seus (sem cid)
CREATE POLICY mc_self_select ON medical_certificates FOR SELECT
  USING (employee_id = current_user_id());

-- IMPORTANTE: NÃO há policy de SELECT para submitter_id (líder)
-- Líder usa RPC limitada que retorna campos abreviados
```

### 3.2 Storage bucket

```sql
-- Bucket privado (criar via supabase JS ou painel)
-- INSERT INTO storage.buckets (id, name, public) VALUES ('medical-certificates', 'medical-certificates', false);

-- Policy: upload apenas para usuários autenticados do tenant
-- Policy: read apenas para DP com permission ou próprio colaborador
-- Policy: delete apenas para DPO com permission view_audit_log
```

---

## 4. RPCs

### 4.1 RPC de submissão (líder envia)

```sql
CREATE OR REPLACE FUNCTION rpc_submit_certificate(
  p_employee_id UUID,
  p_certificate_type certificate_type,
  p_starts_at DATE, p_ends_at DATE, p_issued_at DATE,
  p_file_storage_path TEXT,
  p_file_size_bytes BIGINT,
  p_cid_code VARCHAR DEFAULT NULL,        -- OCR pode sugerir, líder não vê
  p_cid_description VARCHAR DEFAULT NULL,
  p_doctor_name VARCHAR DEFAULT NULL,
  p_doctor_crm VARCHAR DEFAULT NULL,
  p_hospital_clinic VARCHAR DEFAULT NULL,
  p_ocr_extracted JSONB DEFAULT NULL,
  p_ocr_quality ocr_quality DEFAULT NULL,
  p_ocr_confidence NUMERIC DEFAULT NULL
) RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_user app_users; v_target app_users; v_id UUID;
BEGIN
  SELECT * INTO v_user FROM app_users WHERE id = current_user_id();
  IF v_user.id IS NULL THEN RETURN jsonb_build_object('error', 'not_authenticated'); END IF;
  IF NOT module_is_active_for_me('medical_certificates') THEN
    RETURN jsonb_build_object('error', 'module_inactive');
  END IF;

  SELECT * INTO v_target FROM app_users
    WHERE id = p_employee_id AND tenant_id = v_user.tenant_id;
  IF v_target.id IS NULL THEN RETURN jsonb_build_object('error', 'employee_not_found'); END IF;

  -- Permissão: pode submeter para si OU é líder do alvo OU é RH
  IF NOT (
    v_user.id = p_employee_id
    OR user_is_manager_of(p_employee_id)
    OR v_user.role IN ('rh', 'diretoria')
  ) THEN
    RETURN jsonb_build_object('error', 'permission_denied');
  END IF;

  -- Validações
  IF p_ends_at < p_starts_at THEN RETURN jsonb_build_object('error', 'invalid_date_range'); END IF;
  IF p_starts_at > current_date + INTERVAL '7 days' THEN
    RETURN jsonb_build_object('error', 'starts_at_too_future');
  END IF;
  IF p_issued_at > current_date THEN RETURN jsonb_build_object('error', 'issued_at_future'); END IF;

  INSERT INTO medical_certificates (
    tenant_id, employee_id, submitter_id,
    submitted_via, certificate_type,
    cid_code, cid_description, doctor_name, doctor_crm, hospital_clinic,
    issued_at, starts_at, ends_at,
    file_storage_path, file_size_bytes,
    ocr_extracted, ocr_quality, ocr_confidence
  ) VALUES (
    v_user.tenant_id, p_employee_id, v_user.id,
    CASE WHEN v_user.id = p_employee_id THEN 'self'
         WHEN v_user.role IN ('rh','diretoria') THEN 'hr_paper'
         ELSE 'leader' END,
    p_certificate_type,
    p_cid_code, p_cid_description, p_doctor_name, p_doctor_crm, p_hospital_clinic,
    p_issued_at, p_starts_at, p_ends_at,
    p_file_storage_path, p_file_size_bytes,
    p_ocr_extracted, p_ocr_quality, p_ocr_confidence
  ) RETURNING id INTO v_id;

  -- Notificar DP + RH prestadora (se houver) + colaborador
  -- INSERT INTO notifications ...

  -- Audit log
  INSERT INTO audit_log (tenant_id, actor_user_id, action, entity_table, entity_id, after_data)
    VALUES (v_user.tenant_id, v_user.id, 'insert', 'medical_certificates', v_id,
            jsonb_build_object('protocol', (SELECT protocol FROM medical_certificates WHERE id = v_id)));

  RETURN jsonb_build_object('ok', TRUE, 'id', v_id,
    'protocol', (SELECT protocol FROM medical_certificates WHERE id = v_id));
END; $$;
```

### 4.2 RPC limitada para o líder ver os que ele enviou

```sql
CREATE OR REPLACE FUNCTION rpc_get_my_submitted_certificates(p_limit INT DEFAULT 50)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_user app_users; v_items JSONB;
BEGIN
  SELECT * INTO v_user FROM app_users WHERE id = current_user_id();
  IF v_user.id IS NULL THEN RETURN jsonb_build_object('error', 'not_authenticated'); END IF;

  -- RETORNA APENAS CAMPOS LIMITADOS
  -- NÃO retorna cid_code, cid_description, file_storage_path, doctor_name
  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'id', mc.id,
    'protocol', mc.protocol,
    'employee_initials',
      substr(split_part(au.full_name, ' ', 1), 1, 1) || '. ' ||
      split_part(au.full_name, ' ', array_length(string_to_array(au.full_name, ' '), 1)),
    'certificate_type', mc.certificate_type,
    'starts_at', mc.starts_at,
    'ends_at', mc.ends_at,
    'days_off', mc.days_off,
    'status', mc.status,
    'created_at', mc.created_at
  ) ORDER BY mc.created_at DESC), '[]'::jsonb) INTO v_items
    FROM medical_certificates mc
    JOIN app_users au ON au.id = mc.employee_id
    WHERE mc.submitter_id = v_user.id
      AND mc.tenant_id = v_user.tenant_id
    LIMIT p_limit;

  RETURN jsonb_build_object('ok', TRUE, 'items', v_items);
END; $$;
```

### 4.3 Outras RPCs

- `rpc_get_certificate_detail(p_id)` · versão completa para DP (exige `view_medical_cid`)
- `rpc_validate_certificate(p_id, p_cid_code, p_cid_description, p_create_movement BOOLEAN)` · valida + gera movimento auto se days_off ≥ 3
- `rpc_reject_certificate(p_id, p_reason)` · rejeita com motivo obrigatório
- `rpc_get_pending_certificates_queue()` · fila do DP, ordenada por urgência (dias parado + qualidade OCR)
- `rpc_search_cid_codes(p_query)` · autocomplete dos 20 CIDs mais comuns + busca em catálogo expandido futuro
- `rpc_my_certificates(p_limit)` · visão do próprio colaborador (sem CID em listagem)

---

## 5. Worker · OCR client-side

O `worker/` atual roda OCR **server-side** com pdftoppm + tesseract. Para atestados precisa ser **client-side** (LGPD).

### 5.1 Estratégia

- Frontend usa `tesseract.js` (WASM puro, executa no navegador)
- PDF rasterizado via `pdfjs-dist` (também client-side)
- Resultado JSON enviado ao backend junto com o upload do arquivo
- Backend **não roda OCR** · apenas armazena o arquivo original e os campos extraídos

### 5.2 Pacotes
```json
{
  "tesseract.js": "^5.x",
  "pdfjs-dist": "^4.x"
}
```

### 5.3 Componente `ClientSideOCR.tsx`

```tsx
'use client'
import { createWorker, type Worker } from 'tesseract.js'
import * as pdfjsLib from 'pdfjs-dist'

export async function ocrPdfClientSide(file: File): Promise<OcrResult> {
  // 1. Carrega PDF
  const buf = await file.arrayBuffer()
  const pdf = await pdfjsLib.getDocument(buf).promise

  // 2. Renderiza página 1 em canvas 300dpi
  const page = await pdf.getPage(1)
  const viewport = page.getViewport({ scale: 4.17 }) // ~300dpi
  const canvas = document.createElement('canvas')
  canvas.width = viewport.width; canvas.height = viewport.height
  await page.render({ canvasContext: canvas.getContext('2d')!, viewport }).promise

  // 3. OCR com tesseract.js
  const worker: Worker = await createWorker('por')
  const { data } = await worker.recognize(canvas)
  await worker.terminate()

  // 4. Parser regex (mesmo que o worker server-side)
  return parseAtestadoText(data.text, data.confidence)
}

function parseAtestadoText(text: string, confidence: number): OcrResult {
  // Regex para CID-10, datas, dias de afastamento, nome do médico, CRM
  // ...
  return {
    cid_code: extractCid(text),
    cid_description: lookupCid(extractCid(text)),
    days_off: extractDays(text),
    issued_at: extractIssuedDate(text),
    starts_at: extractStartDate(text),
    doctor_name: extractDoctor(text),
    doctor_crm: extractCRM(text),
    quality: confidence >= 0.95 ? 'excellent'
           : confidence >= 0.80 ? 'good'
           : confidence >= 0.60 ? 'fair' : 'poor',
    confidence,
    raw_text: text,
  }
}
```

---

## 6. Páginas Next.js

### 6.1 `/atestados/enviar` (líder)

Referência: [r2_people_atestado_envio_lider.html](../r2_people_atestado_envio_lider.html)

- Wizard 4 passos:
  1. Selecionar colaborador (autocomplete `rpc_search_employees`)
  2. Upload do PDF (input camera nativo `<input type="file" capture="environment" accept="image/*,application/pdf">`)
  3. OCR client-side roda + pré-preenche formulário (CID **oculto pro líder**)
  4. Confirmar e enviar (chama `rpc_submit_certificate`)
- Banner LGPD Art. 11 visível em todos os passos
- Sidebar com histórico **abreviado** (`rpc_get_my_submitted_certificates`): só protocol + status + iniciais

### 6.2 `/atestados/validar` (DP)

Referência: [r2_people_atestado_validacao_dp.html](../r2_people_atestado_validacao_dp.html)

Layout inbox-style 3 colunas:
- **Filtros** (esquerda): qualidade OCR, tipo, prioridade (dias parado), status
- **Fila** (centro): cards com qualidade OCR, alertas, foto thumb
- **Detalhe** (direita): PDF viewer (react-pdf) + form de validação com CID autocomplete

Banner azul condicional: "Movimentação será gerada automaticamente" se days_off ≥ 3.

### 6.3 `/atestados` (hub RH)

Referência: [r2_people_atestados.html](../r2_people_atestados.html)

- Lista geral com filtros
- KPIs no topo (em validação, validados mês, rejeitados, em atraso)
- Drill-down por colaborador (link para `/minha-jornada/atestados?id=...`)

### 6.4 `/minha-jornada/atestados` (colaborador)

Referência: [r2_people_atestado_colaborador.html](../r2_people_atestado_colaborador.html)

- Atalho dentro de `/minha-jornada` (já implementada G1)
- Lista própria + botão "Enviar atestado pra mim" (autoenvio)
- Ações: baixar PDF (revela CID), abrir ticket de dúvida

---

## 7. Testes

`supabase/tests/00410_m3_medical_certificates.sql` · meta 35+ testes:

```sql
BEGIN;

-- Setup
INSERT INTO tenants ... ;
INSERT INTO app_users ... (criar: diretor, dp, lider, colab1, colab2)
-- Marcar dp com permission_profile que tem 'view_medical_cid' OU role rh

-- 1. Líder envia atestado para subordinado
SELECT test_login('lider-uid');
SELECT _assert_eq((rpc_submit_certificate(
  'colab1-id'::UUID, 'doenca_propria', '2026-05-10', '2026-05-12', '2026-05-10',
  'medical/test/2026/abc.pdf', 102400,
  'M54.5', 'Dor lombar', 'Dr. House', '12345-BA', 'Hospital Teste',
  '{"raw": "..."}'::jsonb, 'good', 0.87
)->>'ok')::TEXT, 'true', 'líder envia OK');

-- 2. Líder TENTA ler o que enviou e recebe versão limitada
SELECT _assert_eq(
  jsonb_typeof((rpc_get_my_submitted_certificates(10)->'items')->0->'cid_code'),
  'null', 'líder NÃO vê cid_code'
);
SELECT _assert_eq(
  jsonb_typeof((rpc_get_my_submitted_certificates(10)->'items')->0->'doctor_name'),
  'null', 'líder NÃO vê doctor_name'
);

-- 3. Líder NÃO consegue SELECT direto na tabela (RLS bloqueia)
-- (rodar via auth.uid spoofado)
SELECT _assert_count(0, 'SELECT * FROM medical_certificates WHERE submitter_id = ''lider-uid''',
  'líder sem policy de SELECT direto');

-- 4. DP vê tudo
SELECT test_login('dp-uid');
SELECT _assert_eq(
  (rpc_get_certificate_detail('cert-id')->>'ok')::TEXT, 'true',
  'DP acessa detalhe completo'
);

-- 5. DP valida + gera movimento auto (days_off >= 3)
SELECT _assert_eq(
  (rpc_validate_certificate('cert-id', 'M54.5', 'Dor lombar', TRUE)->>'ok')::TEXT, 'true',
  'DP valida + gera movement'
);

-- 6. Datas inválidas rejeitadas
SELECT _assert_eq(
  rpc_submit_certificate('colab1-id'::UUID, 'doenca_propria',
    '2026-05-15', '2026-05-10', '2026-05-10',  -- ends < starts
    'medical/test/2026/xyz.pdf', 100, NULL, NULL, NULL, NULL, NULL,
    NULL, NULL, NULL)->>'error',
  'invalid_date_range', 'rejeita range invertido'
);

-- 7. Colaborador autoenvio
SELECT test_login('colab1-uid');
SELECT _assert_eq(
  (rpc_submit_certificate('colab1-id'::UUID, 'consulta',
    '2026-05-20', '2026-05-20', '2026-05-19',
    'medical/test/2026/self.pdf', 80000, NULL, NULL, NULL, NULL, NULL,
    NULL, NULL, NULL)->>'ok')::TEXT,
  'true', 'self submission'
);

-- 8. Cross-tenant blocked
-- 9. Rejeição com motivo obrigatório
-- 10. Movimentação auto cria movement vinculado
-- 11. RH prestadora (Larissa) com profile escopo Labuta vê só da Labuta
-- 12. CID malformado rejeitado pelo CHECK constraint
-- ... (totalizar 35+)

ROLLBACK;
```

---

## 8. Critérios de aceitação

- [ ] Migration 00410 aplica idempotentemente
- [ ] Testes 35+ passando
- [ ] Bucket `medical-certificates` privado criado
- [ ] OCR client-side funciona (Tesseract WASM + pdfjs)
- [ ] Líder NÃO vê CID nem PDF (validado via RPC + RLS)
- [ ] DP valida e gera movement auto quando days_off ≥ 3
- [ ] Banner LGPD presente em todas as 4 telas
- [ ] Audit log para toda visualização de CID
- [ ] Adapter em `src/lib/r2/medical.ts`
- [ ] Sidebar nav-item "Atestados" condicional (visível pra líder, dp, colaborador)
- [ ] Doc da sessão em `docs/sessao_m3.md`

---

## 9. Pontos de atenção

- **`auto_movement_id`** fica NULL enquanto M2 (Movimentações) não estiver pronto · adicionar FK depois
- **Tesseract.js bundle é pesado** (~3MB gzipped) · lazy-load só na página `/atestados/enviar`
- **iOS Safari** tem limites de canvas size · testar com PDF de várias páginas
- **CID-10 catálogo expandido** (10mil+ códigos) fica em `cid_codes` table futura · por ora 20 mais comuns embarcados no client
- **Storage retention**: 5 anos (CLT Art. 168) · job pg_cron de limpeza futuro
- **OCR poor quality**: forçar revisão manual no DP, marcar prioridade alta na fila
- **Conflito de upload**: se OCR falha mid-upload, manter PDF no storage e marcar `pending_validation` com `ocr_quality = poor`

---

## 10. Próximas sessões desbloqueadas após M3

- **M2 · Movimentações** · pode finalizar a FK `medical_certificates.auto_movement_id`
- **Dashboard de saúde ocupacional** · agregação de afastamentos por unidade/departamento
- **Relatórios LGPD** · exportação DSAR Art. 18 inclui histórico de atestados próprios

---

**Comando de execução:**

```bash
psql $DATABASE_URL -v ON_ERROR_STOP=1 -f supabase/migrations/00410_m3_schema_medical_certificates.sql
psql $DATABASE_URL -v ON_ERROR_STOP=1 -f supabase/migrations/00411_m3_rpcs_medical_certificates.sql
psql $DATABASE_URL -v ON_ERROR_STOP=1 -f supabase/tests/00410_m3_medical_certificates.sql | grep -E "PASS|FAIL"
npm install tesseract.js pdfjs-dist
cd src && tsc --noEmit --strict
```

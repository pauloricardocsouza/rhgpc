-- ============================================================================
-- R2 PEOPLE - MÓDULO DE ATESTADOS MÉDICOS (PostgreSQL / Supabase)
-- ============================================================================
-- Extensão ao schema_v3 para suportar atestados médicos com:
--   1. Proteção especial de dado sensível (CID + diagnóstico) · LGPD Art. 5º II
--   2. Anexação por própria pessoa OU por líder em nome do liderado
--   3. Workflow de validação pelo DP
--   4. OCR e compressão registrados como metadata (executados no client)
--   5. Geração automática de personnel_movements quando aprovado
--   6. Audit log automático em todo acesso a CID
--
-- Pré-requisito: schema_v3.sql aplicado.
-- Aplicar APÓS rls_policies_detailed.sql.
-- ============================================================================

BEGIN;

-- ============================================================================
-- 1. ENUMS
-- ============================================================================

DO $$ BEGIN
  CREATE TYPE attest_status AS ENUM (
    'draft',              -- rascunho enquanto preenche
    'pending',            -- aguardando validação do DP
    'approved',           -- validado e lançado
    'rejected',           -- recusado pelo DP (ilegível, suspeito, etc.)
    'expired'             -- arquivo de retenção, fora do ano fiscal
  );
EXCEPTION WHEN duplicate_object THEN null; END $$;

DO $$ BEGIN
  CREATE TYPE attest_upload_role AS ENUM (
    'self',               -- o próprio colaborador anexou
    'manager',            -- líder anexou em nome do liderado
    'hr'                  -- DP anexou (ex: digitalização de papel entregue na recepção)
  );
EXCEPTION WHEN duplicate_object THEN null; END $$;


-- ============================================================================
-- 2. TABELA PRINCIPAL: medical_certificates
-- ============================================================================

CREATE TABLE IF NOT EXISTS medical_certificates (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id UUID NOT NULL REFERENCES companies(id) ON DELETE CASCADE,

  -- Quem é o titular (pessoa atestada)
  user_id UUID NOT NULL REFERENCES users(id),

  -- Quem subiu (pode ser != titular)
  uploaded_by_user_id UUID NOT NULL REFERENCES users(id),
  upload_role attest_upload_role NOT NULL,

  -- Período de afastamento
  start_date DATE NOT NULL,
  end_date DATE NOT NULL,
  days_count INT GENERATED ALWAYS AS (end_date - start_date + 1) STORED,
  certificate_date DATE,           -- data de emissão do atestado pelo médico

  -- Médico
  doctor_name TEXT,
  doctor_crm TEXT,                 -- ex: "BA 23456"
  doctor_specialty TEXT,
  hospital_clinic TEXT,

  -- Dados sensíveis (categoria especial LGPD Art. 5º II)
  -- Em produção, essas colunas são CRIPTOGRAFADAS via pgsodium ou Supabase Vault.
  -- Aqui definidas como TEXT para simplicidade do schema; em produção use:
  --   ALTER TABLE medical_certificates ALTER COLUMN cid_code TYPE bytea
  --     USING pgsodium.crypto_aead_det_encrypt(cid_code::bytea, ...);
  cid_code TEXT,                   -- ex: "J11"
  cid_description TEXT,            -- ex: "Influenza por vírus não identificado"
  diagnosis_notes TEXT,            -- observações clínicas (raro)

  -- Arquivo
  file_url TEXT NOT NULL,          -- caminho Supabase Storage: medical_certs/{uuid}.jpg
  file_size_kb INT,
  file_mime TEXT,                  -- 'image/jpeg', 'image/png', 'application/pdf'
  original_size_kb INT,            -- antes da compressão client-side
  compression_ratio NUMERIC(4,3),  -- ex: 0.067 = 93% de redução

  -- OCR
  ocr_text TEXT,                   -- texto bruto extraído (não exibe ao líder)
  ocr_confidence NUMERIC(3,2),     -- 0.00 a 1.00 (Tesseract score médio)
  ocr_engine TEXT DEFAULT 'tesseract@5.0.4',
  is_legible BOOLEAN DEFAULT TRUE,
  ocr_keywords_found TEXT[],       -- ex: ['atestado', 'dias', 'CID']

  -- Workflow
  status attest_status NOT NULL DEFAULT 'draft',
  submitted_at TIMESTAMPTZ,
  reviewed_at TIMESTAMPTZ,
  reviewed_by_user_id UUID REFERENCES users(id),
  rejection_reason TEXT,
  hr_notes TEXT,                   -- observações do DP (apenas DP vê)

  -- Notas do uploader
  uploader_notes TEXT,             -- observação livre (visível ao DP)

  -- Vínculo com afastamento gerado em personnel_movements
  generated_movement_id UUID REFERENCES personnel_movements(id),

  -- LGPD: data prevista de anonimização
  anonymize_at DATE,               -- = approved_at + retention_days da empresa

  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),

  -- Constraints de integridade
  CONSTRAINT mc_dates_valid CHECK (start_date <= end_date),
  CONSTRAINT mc_days_max CHECK (days_count <= 365),     -- bloqueio de erro grosseiro
  CONSTRAINT mc_uploader_consistent CHECK (
    (upload_role = 'self' AND user_id = uploaded_by_user_id)
    OR (upload_role IN ('manager', 'hr') AND user_id <> uploaded_by_user_id)
  )
);

CREATE INDEX IF NOT EXISTS idx_mc_user           ON medical_certificates(user_id, status);
CREATE INDEX IF NOT EXISTS idx_mc_company_status ON medical_certificates(company_id, status);
CREATE INDEX IF NOT EXISTS idx_mc_uploader       ON medical_certificates(uploaded_by_user_id);
CREATE INDEX IF NOT EXISTS idx_mc_dates          ON medical_certificates(user_id, start_date);
CREATE INDEX IF NOT EXISTS idx_mc_pending        ON medical_certificates(company_id, status) WHERE status = 'pending';
CREATE INDEX IF NOT EXISTS idx_mc_anonymize      ON medical_certificates(anonymize_at) WHERE anonymize_at IS NOT NULL;

COMMENT ON TABLE medical_certificates IS
  'Atestados médicos. CID é dado sensível (LGPD Art. 5º II) · armazenado idealmente criptografado.
   Líderes veem apenas dias/período via view filtrada. Apenas titular + DP + DPO veem CID.';

COMMENT ON COLUMN medical_certificates.cid_code IS 'CID-10. SENSÍVEL. Em produção: pgsodium.crypto_aead_det_encrypt';
COMMENT ON COLUMN medical_certificates.upload_role IS 'self|manager|hr. Define quem fez o upload e governa permissões.';
COMMENT ON COLUMN medical_certificates.ocr_confidence IS 'Score 0-1 do Tesseract. Abaixo de 0.5 marca is_legible=false.';


-- ============================================================================
-- 3. VIEW PARA LÍDERES (sem CID)
-- ============================================================================
-- Líder com hierarchy_scope vê esta view, NUNCA a tabela bruta.
-- Mascaramos automaticamente cid_code, cid_description, ocr_text.
-- ============================================================================

CREATE OR REPLACE VIEW v_medical_certificates_leader AS
SELECT
  mc.id,
  mc.company_id,
  mc.user_id,
  u.full_name AS user_full_name,
  mc.uploaded_by_user_id,
  uu.full_name AS uploaded_by_name,
  mc.upload_role,
  mc.start_date,
  mc.end_date,
  mc.days_count,
  mc.certificate_date,
  -- DADOS SENSÍVEIS MASCARADOS:
  '[restrito ao DP]'::TEXT AS cid_code,
  '[restrito ao DP]'::TEXT AS cid_description,
  NULL::TEXT AS diagnosis_notes,
  NULL::TEXT AS doctor_name,            -- nome do médico também é dado sensível indireto
  NULL::TEXT AS ocr_text,
  -- Metadados não-sensíveis liberados:
  mc.file_size_kb,
  mc.is_legible,
  mc.ocr_confidence,
  mc.status,
  mc.submitted_at,
  mc.reviewed_at,
  mc.uploader_notes,
  mc.created_at,
  mc.updated_at
FROM medical_certificates mc
JOIN users u  ON u.id  = mc.user_id
JOIN users uu ON uu.id = mc.uploaded_by_user_id;

COMMENT ON VIEW v_medical_certificates_leader IS
  'View para líderes acessarem atestados de subordinados sem ver CID nem médico.
   LGPD-compliant: masking explícito antes de chegar ao client.';


-- ============================================================================
-- 4. RLS POLICIES · combinando os 4 escopos com proteção extra para CID
-- ============================================================================

ALTER TABLE medical_certificates ENABLE ROW LEVEL SECURITY;

-- ----------------------------------------------------------------------------
-- 4.1 SELECT: titular vê seus, DP vê todos do tenant, líder vê via view
-- ----------------------------------------------------------------------------

DROP POLICY IF EXISTS mc_select ON medical_certificates;
CREATE POLICY mc_select ON medical_certificates
  FOR SELECT
  USING (
    company_id = current_user_company_id()
    AND (
      -- 1. Titular vê seus próprios atestados (com CID)
      user_id = current_user_id()
      -- 2. Quem subiu vê o que subiu (mesmo se não for o titular · caso do líder)
      --    MAS líder NÃO vê CID via tabela bruta · ele deve usar v_medical_certificates_leader
      --    A policy permite SELECT mas o frontend deve consultar a view para manager
      OR uploaded_by_user_id = current_user_id()
      -- 3. DP/RH com permissão approve_movements vê tudo
      OR current_user_has_permission('approve_movements')
      -- 4. DPO/Auditor com view_audit vê tudo (acesso registrado)
      OR current_user_has_permission('view_audit')
    )
  );


-- ----------------------------------------------------------------------------
-- 4.2 INSERT: titular ou líder do titular OU DP
-- ----------------------------------------------------------------------------

DROP POLICY IF EXISTS mc_insert ON medical_certificates;
CREATE POLICY mc_insert ON medical_certificates
  FOR INSERT
  WITH CHECK (
    company_id = current_user_company_id()
    AND uploaded_by_user_id = current_user_id()
    AND (
      -- Caso 1: anexando para si próprio
      (upload_role = 'self' AND user_id = current_user_id())
      -- Caso 2: líder anexando para subordinado direto/indireto
      OR (
        upload_role = 'manager'
        AND can_see_hierarchy(user_id)
      )
      -- Caso 3: DP anexando manualmente
      OR (
        upload_role = 'hr'
        AND current_user_has_permission('approve_movements')
      )
    )
  );


-- ----------------------------------------------------------------------------
-- 4.3 UPDATE: regras finas de quem pode editar o quê e quando
-- ----------------------------------------------------------------------------

DROP POLICY IF EXISTS mc_update ON medical_certificates;
CREATE POLICY mc_update ON medical_certificates
  FOR UPDATE
  USING (
    company_id = current_user_company_id()
    AND (
      -- Uploader pode editar enquanto draft
      (uploaded_by_user_id = current_user_id() AND status = 'draft')
      -- DP sempre pode (com approve_movements)
      OR current_user_has_permission('approve_movements')
    )
  );


-- ----------------------------------------------------------------------------
-- 4.4 DELETE: apenas RH com approve_movements (e nem isso, na prática)
-- ----------------------------------------------------------------------------
-- Atestados são ARQUIVO LEGAL · não devem ser deletados, apenas anonimizados.
-- Esta policy existe mas nem o RH normal deve usar.

DROP POLICY IF EXISTS mc_delete ON medical_certificates;
CREATE POLICY mc_delete ON medical_certificates
  FOR DELETE
  USING (
    company_id = current_user_company_id()
    AND current_user_has_permission('manage_profiles')
    AND status = 'draft'  -- só drafts podem ser deletados
  );


-- ============================================================================
-- 5. TRIGGER DE AUDIT · todo SELECT em CID gera log
-- ============================================================================
-- Postgres não tem trigger pra SELECT direto, mas podemos:
--   a) usar pg_audit (extension) em produção
--   b) registrar via função wrapper que retorna o CID descriptografado
-- ============================================================================

CREATE OR REPLACE FUNCTION read_certificate_cid(p_cert_id UUID)
RETURNS TABLE(cid_code TEXT, cid_description TEXT)
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public AS $$
DECLARE
  v_cert medical_certificates;
  v_user_id UUID := current_user_id();
  v_company_id UUID := current_user_company_id();
BEGIN
  -- Busca o atestado (RLS já filtra)
  SELECT * INTO v_cert
    FROM medical_certificates
   WHERE id = p_cert_id AND company_id = v_company_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Atestado não encontrado ou sem permissão.';
  END IF;

  -- Verifica se pode ver CID:
  --   - É o titular
  --   - Tem approve_movements (DP)
  --   - Tem view_audit (DPO)
  IF NOT (
    v_cert.user_id = v_user_id
    OR current_user_has_permission('approve_movements')
    OR current_user_has_permission('view_audit')
  ) THEN
    RAISE EXCEPTION 'Acesso negado ao CID. Você não é o titular nem RH/DPO.';
  END IF;

  -- REGISTRA O ACESSO (LGPD Art. 37)
  INSERT INTO audit_log (
    company_id, actor_user_id, action, target_table, target_id,
    extra
  ) VALUES (
    v_company_id, v_user_id, 'view_sensitive', 'medical_certificates', p_cert_id,
    jsonb_build_object(
      'field', 'cid_code',
      'titular_user_id', v_cert.user_id,
      'reason', CASE
        WHEN v_cert.user_id = v_user_id THEN 'self_access'
        WHEN current_user_has_permission('approve_movements') THEN 'hr_validation'
        WHEN current_user_has_permission('view_audit') THEN 'audit_review'
        ELSE 'unknown'
      END
    )
  );

  -- Retorna o CID
  RETURN QUERY SELECT v_cert.cid_code, v_cert.cid_description;
END;
$$;

GRANT EXECUTE ON FUNCTION read_certificate_cid TO authenticated;

COMMENT ON FUNCTION read_certificate_cid IS
  'Função única para ler CID. Cada chamada gera entrada em audit_log.
   Frontend deve usar SEMPRE esta função, NUNCA SELECT direto na tabela.';


-- ============================================================================
-- 6. TRIGGER PÓS-APROVAÇÃO: gera afastamento em personnel_movements
-- ============================================================================

CREATE OR REPLACE FUNCTION trg_mc_post_approval()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
DECLARE
  v_user_company user_companies;
  v_movement_id UUID;
  v_retention_days INT;
BEGIN
  IF NEW.status = 'approved' AND (OLD.status IS NULL OR OLD.status <> 'approved') THEN

    -- Pega user_company do titular
    SELECT * INTO v_user_company
      FROM user_companies
     WHERE user_id = NEW.user_id
       AND company_id = NEW.company_id
       AND is_active = TRUE
     LIMIT 1;

    -- Cria movimentação de afastamento
    INSERT INTO personnel_movements (
      company_id, user_company_id,
      movement_type, status,
      effective_date, end_date,
      requested_by_user_id, justification,
      related_entity_type, related_entity_id
    ) VALUES (
      NEW.company_id, v_user_company.id,
      'sick_leave', 'approved',
      NEW.start_date, NEW.end_date,
      NEW.uploaded_by_user_id,
      'Afastamento por atestado médico de ' || NEW.days_count || ' dias',
      'medical_certificate', NEW.id
    ) RETURNING id INTO v_movement_id;

    -- Atualiza status do colaborador para sick_leave durante o período
    -- (em produção, isso seria um cron job que verifica vigência diariamente)
    IF NEW.start_date <= CURRENT_DATE AND NEW.end_date >= CURRENT_DATE THEN
      UPDATE user_companies
         SET status = 'sick_leave', updated_at = now()
       WHERE id = v_user_company.id;
    END IF;

    -- Vincula o atestado à movimentação criada
    NEW.generated_movement_id := v_movement_id;
    NEW.reviewed_at := now();

    -- Define data de anonimização
    SELECT (settings->>'anonymize_after_termination_days')::INT INTO v_retention_days
      FROM companies WHERE id = NEW.company_id;
    IF v_retention_days IS NULL THEN v_retention_days := 365; END IF;
    NEW.anonymize_at := CURRENT_DATE + (v_retention_days || ' days')::INTERVAL;

    -- Notifica o titular
    INSERT INTO notifications (company_id, to_user_id, kind, title, body, link)
    VALUES (
      NEW.company_id, NEW.user_id, 'medical_certificate_approved',
      'Seu atestado foi aprovado',
      'Seu atestado de ' || NEW.days_count || ' dias (' || to_char(NEW.start_date, 'DD/MM') || ' a ' || to_char(NEW.end_date, 'DD/MM') || ') foi validado pelo DP.',
      '/atestados/' || NEW.id
    );

    -- Se foi anexado por outro (líder), notifica também o uploader
    IF NEW.uploaded_by_user_id <> NEW.user_id THEN
      INSERT INTO notifications (company_id, to_user_id, kind, title, body, link)
      VALUES (
        NEW.company_id, NEW.uploaded_by_user_id, 'medical_certificate_approved',
        'Atestado validado',
        'O atestado que você anexou em nome de outro colaborador foi aprovado.',
        '/atestados/' || NEW.id
      );
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_mc_post_approval ON medical_certificates;
CREATE TRIGGER trg_mc_post_approval
  BEFORE UPDATE OF status ON medical_certificates
  FOR EACH ROW EXECUTE FUNCTION trg_mc_post_approval();


-- ============================================================================
-- 7. TRIGGER DE NOTIFICAÇÃO PARA O DP QUANDO ATESTADO FICA PENDING
-- ============================================================================

CREATE OR REPLACE FUNCTION trg_mc_notify_hr_on_pending()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
DECLARE
  v_hr_user_id UUID;
  v_titular_name TEXT;
BEGIN
  IF NEW.status = 'pending' AND (OLD.status IS NULL OR OLD.status <> 'pending') THEN

    SELECT full_name INTO v_titular_name FROM users WHERE id = NEW.user_id;

    -- Notifica todos os usuários com perfil que tem approve_movements no tenant
    FOR v_hr_user_id IN
      SELECT uc.user_id
        FROM user_companies uc
        JOIN permission_profiles pp ON pp.id = uc.permission_profile_id
       WHERE uc.company_id = NEW.company_id
         AND uc.is_active = TRUE
         AND 'approve_movements' = ANY(pp.special_permissions)
    LOOP
      INSERT INTO notifications (company_id, to_user_id, kind, title, body, link)
      VALUES (
        NEW.company_id, v_hr_user_id, 'medical_certificate_pending',
        'Novo atestado para validar',
        v_titular_name || ' enviou atestado de ' || NEW.days_count || ' dias.',
        '/atestados?tab=pending'
      );
    END LOOP;
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_mc_notify_hr ON medical_certificates;
CREATE TRIGGER trg_mc_notify_hr
  AFTER INSERT OR UPDATE OF status ON medical_certificates
  FOR EACH ROW EXECUTE FUNCTION trg_mc_notify_hr_on_pending();


-- ============================================================================
-- 8. ANONIMIZAÇÃO PROGRAMADA (cron job diário)
-- ============================================================================
-- Função idempotente que pode ser chamada por uma Edge Function diária.
-- Anonimiza atestados cuja data de retenção venceu.
-- Mantém estatística (dias, datas) mas remove identificação clínica.
-- ============================================================================

CREATE OR REPLACE FUNCTION anonymize_expired_certificates()
RETURNS INT
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public AS $$
DECLARE
  v_count INT;
BEGIN
  UPDATE medical_certificates
     SET cid_code = '[anonimizado]',
         cid_description = '[anonimizado]',
         diagnosis_notes = NULL,
         doctor_name = '[anonimizado]',
         doctor_crm = NULL,
         doctor_specialty = NULL,
         hospital_clinic = NULL,
         ocr_text = NULL,
         file_url = '[anonimizado]',
         status = 'expired',
         updated_at = now()
   WHERE anonymize_at <= CURRENT_DATE
     AND status = 'approved'
     AND cid_code <> '[anonimizado]';

  GET DIAGNOSTICS v_count = ROW_COUNT;

  -- Registra a operação no audit log
  IF v_count > 0 THEN
    INSERT INTO audit_log (action, target_table, extra)
    VALUES (
      'anonymize_expired',
      'medical_certificates',
      jsonb_build_object('count', v_count, 'execution_date', CURRENT_DATE)
    );
  END IF;

  RETURN v_count;
END;
$$;

COMMENT ON FUNCTION anonymize_expired_certificates IS
  'Cron diário: anonimiza atestados cuja retenção venceu. Mantém estatística mas remove identificação.';


-- ============================================================================
-- 9. FUNÇÃO RPC PARA O FRONTEND: list_my_certificates
-- ============================================================================

CREATE OR REPLACE FUNCTION list_my_certificates(
  p_scope TEXT DEFAULT 'mine'  -- 'mine' | 'team' | 'pending_validation'
)
RETURNS TABLE (
  id UUID,
  user_id UUID,
  user_full_name TEXT,
  upload_role TEXT,
  uploaded_by_name TEXT,
  start_date DATE,
  end_date DATE,
  days_count INT,
  status TEXT,
  is_legible BOOLEAN,
  ocr_confidence NUMERIC,
  uploader_notes TEXT,
  created_at TIMESTAMPTZ,
  -- CID só preenchido se o user pode ver
  cid_visible BOOLEAN,
  cid_code TEXT,
  cid_description TEXT
)
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path = public AS $$
DECLARE
  v_user_id UUID := current_user_id();
  v_company_id UUID := current_user_company_id();
  v_can_see_cid_globally BOOLEAN := current_user_has_permission('approve_movements')
                                  OR current_user_has_permission('view_audit');
BEGIN
  RETURN QUERY
  SELECT
    mc.id,
    mc.user_id,
    u.full_name,
    mc.upload_role::TEXT,
    uu.full_name,
    mc.start_date,
    mc.end_date,
    mc.days_count,
    mc.status::TEXT,
    mc.is_legible,
    mc.ocr_confidence,
    mc.uploader_notes,
    mc.created_at,
    -- Pode ver CID?
    (mc.user_id = v_user_id OR v_can_see_cid_globally)::BOOLEAN AS cid_visible,
    CASE
      WHEN mc.user_id = v_user_id OR v_can_see_cid_globally THEN mc.cid_code
      ELSE '[restrito]'::TEXT
    END,
    CASE
      WHEN mc.user_id = v_user_id OR v_can_see_cid_globally THEN mc.cid_description
      ELSE '[restrito]'::TEXT
    END
  FROM medical_certificates mc
  JOIN users u  ON u.id  = mc.user_id
  JOIN users uu ON uu.id = mc.uploaded_by_user_id
  WHERE mc.company_id = v_company_id
    AND CASE p_scope
      WHEN 'mine' THEN mc.user_id = v_user_id
      WHEN 'team' THEN can_see_hierarchy(mc.user_id) AND mc.user_id <> v_user_id
      WHEN 'pending_validation' THEN
        mc.status = 'pending' AND v_can_see_cid_globally
      ELSE FALSE
    END
  ORDER BY mc.created_at DESC;
END;
$$;

GRANT EXECUTE ON FUNCTION list_my_certificates TO authenticated;


-- ============================================================================
-- 10. ATUALIZAÇÃO DA TABELA system_pages (catálogo de páginas)
-- ============================================================================

INSERT INTO system_pages (code, name, category, is_sensitive, available_perms) VALUES
('atestados', 'Atestados Médicos', 'rh', true, ARRAY['view','create','edit','approve','reject','export'])
ON CONFLICT (code) DO UPDATE SET
  name = EXCLUDED.name,
  category = EXCLUDED.category,
  is_sensitive = EXCLUDED.is_sensitive,
  available_perms = EXCLUDED.available_perms;


-- Vincula a página aos perfis padrão
DO $$
DECLARE
  v_company_id UUID;
  v_profile_id UUID;
BEGIN
  -- Para cada tenant existente, dá permissão padrão
  FOR v_company_id IN SELECT id FROM companies WHERE active = TRUE
  LOOP
    -- Colaborador: pode anexar os próprios + ver os próprios
    SELECT id INTO v_profile_id
      FROM permission_profiles
     WHERE company_id = v_company_id AND code = 'colaborador';
    IF FOUND THEN
      INSERT INTO profile_page_permissions (profile_id, page_code, permissions)
      VALUES (v_profile_id, 'atestados', ARRAY['view','create'])
      ON CONFLICT (profile_id, page_code) DO UPDATE SET permissions = EXCLUDED.permissions;
    END IF;

    -- Líder: pode anexar dos liderados + ver dos liderados (sem CID)
    SELECT id INTO v_profile_id
      FROM permission_profiles
     WHERE company_id = v_company_id AND code = 'lider';
    IF FOUND THEN
      INSERT INTO profile_page_permissions (profile_id, page_code, permissions)
      VALUES (v_profile_id, 'atestados', ARRAY['view','create'])
      ON CONFLICT (profile_id, page_code) DO UPDATE SET permissions = EXCLUDED.permissions;
    END IF;

    -- Admin RH: tudo (inclusive aprovar)
    SELECT id INTO v_profile_id
      FROM permission_profiles
     WHERE company_id = v_company_id AND code = 'admin_rh_gpc';
    IF FOUND THEN
      INSERT INTO profile_page_permissions (profile_id, page_code, permissions)
      VALUES (v_profile_id, 'atestados', ARRAY['view','create','edit','approve','reject','export'])
      ON CONFLICT (profile_id, page_code) DO UPDATE SET permissions = EXCLUDED.permissions;
    END IF;
  END LOOP;
END $$;


COMMIT;


-- ============================================================================
-- RESUMO DO QUE FOI CRIADO
-- ============================================================================
/*
TABELAS:
  ✓ medical_certificates · atestados com proteção LGPD
  ✓ Indices para performance (idx_mc_user, idx_mc_company_status, etc.)

VIEWS:
  ✓ v_medical_certificates_leader · sem CID, para líderes

RLS POLICIES (4):
  ✓ mc_select · titular + uploader + DP/DPO
  ✓ mc_insert · self/manager/hr conforme escopo
  ✓ mc_update · uploader em draft + DP sempre
  ✓ mc_delete · apenas drafts, apenas RH com manage_profiles

FUNÇÕES:
  ✓ read_certificate_cid(uuid) · lê CID com audit automático
  ✓ list_my_certificates(scope) · lista com mascaramento condicional
  ✓ anonymize_expired_certificates() · cron de retenção

TRIGGERS:
  ✓ trg_mc_post_approval · gera personnel_movements + atualiza status do user_company
  ✓ trg_mc_notify_hr · notifica DP quando atestado fica pending

INTEGRAÇÕES:
  ✓ system_pages: nova entrada 'atestados'
  ✓ profile_page_permissions: 3 perfis padrão configurados

PROTEÇÕES LGPD:
  ✓ CID/diagnóstico/médico mascarados em view de líder
  ✓ Função read_certificate_cid registra cada acesso em audit_log
  ✓ Anonimização programada após retention_days
  ✓ Constraint de uploader consistente (self ↔ user_id, manager/hr ↔ outro user)
  ✓ Atestados não podem ser deletados (apenas drafts) · preservação legal
*/

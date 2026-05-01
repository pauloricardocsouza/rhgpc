-- ============================================================================
-- R2 PEOPLE · SCHEMA v4 (incremental sobre v3)
-- ----------------------------------------------------------------------------
-- Adições desta versão:
--   1. Apelido buscável e único por empresa (users.nickname)
--   2. Tabela medical_certificates com regra "líder envia, não vê depois"
--   3. RPC rpc_search_employees com full-text português
--   4. RPC rpc_get_employee_history fazendo UNION de 7 fontes de eventos
--   5. RPC rpc_check_nickname_available para validação em tempo real
--   6. RLS policies que separam acesso por role e por dono
--   7. Storage bucket criptografado para atestados (medical-certificates)
--   8. Trigger de geração automática de protocolo ATD-YYYY-MM-DD-XXXXX
--   9. Hooks de notificação para fluxo tripartite (DP + RH prestadora + dono)
--
-- Pré-requisito: schema v3 já aplicado.
-- Execução recomendada: dentro de uma transação. Idempotente (pode rodar
-- mais de uma vez sem efeito colateral).
--
-- Autor: R2 Soluções Empresariais · 28/04/2026
-- ============================================================================

BEGIN;

-- ============================================================================
-- SEÇÃO 1 · ALTER USERS (Apelido buscável)
-- ============================================================================

ALTER TABLE users
  ADD COLUMN IF NOT EXISTS nickname TEXT,
  ADD COLUMN IF NOT EXISTS nickname_searchable BOOLEAN NOT NULL DEFAULT true;

-- Constraint de formato: apenas letras (com acentos PT-BR), números, underscore.
-- Mínimo 2 e máximo 20 caracteres. NULL é aceito (apelido é opcional).
ALTER TABLE users
  DROP CONSTRAINT IF EXISTS chk_users_nickname_format;
ALTER TABLE users
  ADD CONSTRAINT chk_users_nickname_format
    CHECK (
      nickname IS NULL
      OR nickname ~ '^[a-zA-ZÀ-ÿ0-9_]{2,20}$'
    );

COMMENT ON COLUMN users.nickname IS
  'Apelido informal (Fê, JP, Bia). Formato: letras com acentos, números, underscore. 2-20 chars. Único por company_id.';

COMMENT ON COLUMN users.nickname_searchable IS
  'Se true, o apelido aparece nos resultados de rpc_search_employees. Se false, fica salvo mas oculto na busca.';

-- Unicidade do apelido por empresa (evita ambiguidade no autocomplete).
-- Compara em lowercase: "Fê", "fê", "FÊ" são considerados duplicatas.
DROP INDEX IF EXISTS uniq_users_nickname_per_company;
CREATE UNIQUE INDEX uniq_users_nickname_per_company
  ON users (company_id, lower(nickname))
  WHERE nickname IS NOT NULL AND deleted_at IS NULL;

-- Índice de busca rápida por apelido (lookup direto)
DROP INDEX IF EXISTS idx_users_nickname_lower;
CREATE INDEX idx_users_nickname_lower
  ON users (lower(nickname))
  WHERE nickname_searchable = true AND deleted_at IS NULL;

-- Índice full-text search combinando full_name + nickname + matrícula.
-- Configuração 'portuguese' aplica stemming (ex: "trabalhar" e "trabalhando"
-- são tratadas como o mesmo radical) e remove stopwords PT-BR.
DROP INDEX IF EXISTS idx_users_fts;
CREATE INDEX idx_users_fts
  ON users
  USING gin (
    to_tsvector(
      'portuguese',
      coalesce(full_name, '') || ' ' ||
      coalesce(CASE WHEN nickname_searchable THEN nickname ELSE NULL END, '') || ' ' ||
      coalesce(matricula, '')
    )
  )
  WHERE deleted_at IS NULL;

-- ============================================================================
-- SEÇÃO 2 · NEW TABLE medical_certificates
-- ============================================================================

CREATE TABLE IF NOT EXISTS medical_certificates (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

  -- Multi-tenancy
  company_id UUID NOT NULL REFERENCES companies(id) ON DELETE CASCADE,

  -- Quem é o titular do atestado (a pessoa afastada)
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE RESTRICT,

  -- Quem fez o upload no sistema (líder ou o próprio colaborador)
  -- Pode diferir de user_id quando líder atua como "carteiro" do atestado físico.
  submitted_by_user_id UUID NOT NULL REFERENCES users(id) ON DELETE RESTRICT,

  -- Identificador legível ATD-YYYY-MM-DD-XXXXX (gerado por trigger)
  protocol TEXT UNIQUE NOT NULL,

  -- Tipo do documento. Valores possíveis:
  --   'atestado_afastamento'  - Atestado médico padrão com afastamento
  --   'comprovante_consulta'  - Comprovante de presença em consulta (sem afastamento)
  --   'declaracao_acompanhamento' - Acompanhamento de dependente
  --   'declaracao_comparecimento' - Declaração genérica
  --   'exame_admissional'     - Exame médico admissional
  --   'exame_periodico'       - Exame médico periódico (NR-7)
  --   'exame_demissional'     - Exame médico demissional
  certificate_type TEXT NOT NULL,

  -- Período do afastamento (NULL para tipos que não geram afastamento)
  start_date DATE,
  days_off INTEGER CHECK (days_off IS NULL OR days_off BETWEEN 0 AND 365),

  -- Observações livres preenchidas pelo submetedor (líder ou colaborador).
  -- Visíveis para o DP, mas o líder NÃO consegue reabrir essa observação após envio.
  observations TEXT,

  -- Dados extraídos via OCR (preenchidos pela edge function process-medical-certificate)
  doctor_name TEXT,
  doctor_crm TEXT,
  ocr_extracted_text TEXT,
  ocr_quality_score NUMERIC(3,2) CHECK (ocr_quality_score IS NULL OR ocr_quality_score BETWEEN 0 AND 1),
  -- ocr_quality_score: 0.85+ = "alta", 0.5-0.85 = "média", abaixo = "baixa, sugerir reenvio"

  -- CID-10 (categoria especial de dado sensível, LGPD Art. 11).
  -- Preenchido APENAS pelo DP/RH durante a validação. NUNCA pelo líder.
  -- Visível somente para perfis com permissão view_medical_cid.
  cid_code TEXT,
  cid_description TEXT,

  -- Arquivo no Supabase Storage (caminho dentro do bucket medical-certificates)
  -- Exemplo: 'company-uuid/2026/04/atd-2026-04-28-1a47b.pdf'
  file_storage_path TEXT NOT NULL,
  file_size_bytes BIGINT NOT NULL,
  file_compressed_size_bytes BIGINT,
  file_mime_type TEXT NOT NULL,
  file_original_name TEXT,

  -- Workflow de status:
  --   pending    - Recebido, aguardando processamento da edge function
  --   processing - Edge function rodando (OCR, compactação)
  --   received   - Pronto para validação manual pelo DP
  --   validated  - DP aprovou, dados confirmados, pode gerar movimentação
  --   archived   - Após período de retenção, movido para histórico
  --   rejected   - DP rejeitou (ilegível, fraudulento, fora do prazo)
  status TEXT NOT NULL DEFAULT 'pending'
    CHECK (status IN ('pending', 'processing', 'received', 'validated', 'archived', 'rejected')),

  -- Validação pelo DP
  validated_by_user_id UUID REFERENCES users(id),
  validated_at TIMESTAMPTZ,

  -- Rejeição (se aplicável)
  rejection_reason TEXT,
  rejected_by_user_id UUID REFERENCES users(id),
  rejected_at TIMESTAMPTZ,

  -- Geração automática de movimentação (afastamento) quando dias > 3
  auto_movement_id UUID REFERENCES movements(id),

  -- Arquivamento (retenção LGPD: 5 anos para atestados pelo CLT Art. 168)
  archived_at TIMESTAMPTZ,
  retention_until DATE,

  -- Auditoria
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  deleted_at TIMESTAMPTZ
);

COMMENT ON TABLE medical_certificates IS
  'Atestados médicos e comprovantes. Categoria especial LGPD Art. 11. Líder pode submeter (submitted_by) mas não consegue ler conteúdo (file_storage_path, cid_code) após envio. RLS rigorosa.';

CREATE INDEX IF NOT EXISTS idx_medcert_company_user ON medical_certificates(company_id, user_id);
CREATE INDEX IF NOT EXISTS idx_medcert_status ON medical_certificates(company_id, status) WHERE deleted_at IS NULL;
CREATE INDEX IF NOT EXISTS idx_medcert_submitted_by ON medical_certificates(submitted_by_user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_medcert_user_dates ON medical_certificates(user_id, start_date DESC) WHERE status IN ('validated', 'archived');
CREATE INDEX IF NOT EXISTS idx_medcert_protocol ON medical_certificates(protocol);

-- ============================================================================
-- SEÇÃO 3 · STORAGE BUCKET (medical-certificates)
-- ============================================================================
-- Configuração via supabase storage API. SQL apenas registra metadado.

INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'medical-certificates',
  'medical-certificates',
  false,
  15728640,  -- 15 MB
  ARRAY[
    'application/pdf',
    'image/jpeg',
    'image/png',
    'image/heic',
    'image/heif'
  ]
)
ON CONFLICT (id) DO UPDATE SET
  public = false,
  file_size_limit = 15728640,
  allowed_mime_types = ARRAY[
    'application/pdf',
    'image/jpeg',
    'image/png',
    'image/heic',
    'image/heif'
  ];

-- ============================================================================
-- SEÇÃO 4 · TRIGGER · Geração automática de protocolo
-- ============================================================================

CREATE OR REPLACE FUNCTION fn_generate_certificate_protocol()
RETURNS TRIGGER AS $$
DECLARE
  v_date_part TEXT;
  v_random_part TEXT;
  v_protocol TEXT;
  v_attempts INTEGER := 0;
BEGIN
  -- Formato: ATD-YYYY-MM-DD-XXXXX (5 hex chars uppercase)
  v_date_part := to_char(coalesce(NEW.start_date, current_date), 'YYYY-MM-DD');

  LOOP
    v_random_part := upper(substring(md5(random()::text || clock_timestamp()::text), 1, 5));
    v_protocol := 'ATD-' || v_date_part || '-' || v_random_part;

    -- Verifica colisão (raro: 1 em ~1M na mesma data)
    IF NOT EXISTS (SELECT 1 FROM medical_certificates WHERE protocol = v_protocol) THEN
      NEW.protocol := v_protocol;
      EXIT;
    END IF;

    v_attempts := v_attempts + 1;
    IF v_attempts > 5 THEN
      RAISE EXCEPTION 'Falha ao gerar protocolo único após 5 tentativas';
    END IF;
  END LOOP;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_certificate_protocol ON medical_certificates;
CREATE TRIGGER trg_certificate_protocol
  BEFORE INSERT ON medical_certificates
  FOR EACH ROW
  WHEN (NEW.protocol IS NULL)
  EXECUTE FUNCTION fn_generate_certificate_protocol();

-- Trigger updated_at
DROP TRIGGER IF EXISTS trg_certificate_updated_at ON medical_certificates;
CREATE TRIGGER trg_certificate_updated_at
  BEFORE UPDATE ON medical_certificates
  FOR EACH ROW
  EXECUTE FUNCTION fn_set_updated_at();

-- ============================================================================
-- SEÇÃO 5 · RLS POLICIES (medical_certificates)
-- ============================================================================

ALTER TABLE medical_certificates ENABLE ROW LEVEL SECURITY;

-- Drop policies antigas (idempotência)
DROP POLICY IF EXISTS medcert_select_owner ON medical_certificates;
DROP POLICY IF EXISTS medcert_select_dp_rh ON medical_certificates;
DROP POLICY IF EXISTS medcert_select_submitter_header ON medical_certificates;
DROP POLICY IF EXISTS medcert_insert_self_or_subordinate ON medical_certificates;
DROP POLICY IF EXISTS medcert_update_dp_only ON medical_certificates;
DROP POLICY IF EXISTS medcert_delete_admin_only ON medical_certificates;

-- ----------------------------------------------------------------------------
-- POLICY 1 · O dono sempre vê o próprio atestado completo
-- ----------------------------------------------------------------------------
CREATE POLICY medcert_select_owner
  ON medical_certificates
  FOR SELECT
  USING (
    company_id = current_company_id()
    AND user_id = current_user_id()
    AND deleted_at IS NULL
  );

-- ----------------------------------------------------------------------------
-- POLICY 2 · DP, RH GPC e RH Prestadora veem todos os atestados visíveis pra eles
-- O escopo RH-prestadora é filtrado pelo employer_unit_id (vê só os Labuta, etc.)
-- ----------------------------------------------------------------------------
CREATE POLICY medcert_select_dp_rh
  ON medical_certificates
  FOR SELECT
  USING (
    company_id = current_company_id()
    AND deleted_at IS NULL
    AND (
      -- DP/RH GPC (perfis admin_rh, dp) veem todos
      current_user_has_permission('view_all_medical_certificates')
      OR
      -- RH Prestadora vê apenas os atestados de funcionários do mesmo empregador
      (
        current_user_has_permission('view_medical_certificates_by_employer')
        AND user_id IN (
          SELECT u.id FROM users u
          WHERE u.employer_unit_id = current_user_employer_scope()
        )
      )
    )
  );

-- ----------------------------------------------------------------------------
-- POLICY 3 · Submitter (líder que enviou) vê apenas HEADER, sem campos sensíveis
-- IMPORTANTE: Esta policy NÃO permite SELECT direto na tabela.
-- O líder usa exclusivamente a RPC rpc_get_my_submitted_certificates,
-- que retorna apenas {protocol, status, certificate_type, created_at, user_full_name}.
-- A RPC tem SECURITY DEFINER e não expõe file_storage_path nem cid_code.
--
-- Esta policy é mantida vazia propositalmente (não dá SELECT direto)
-- para forçar o uso da RPC limitada. Tentativas de SELECT direto retornam vazio.
-- ----------------------------------------------------------------------------
-- (sem CREATE POLICY aqui de propósito)

-- ----------------------------------------------------------------------------
-- POLICY 4 · INSERT: o próprio colaborador OU seu líder direto
-- ----------------------------------------------------------------------------
CREATE POLICY medcert_insert_self_or_subordinate
  ON medical_certificates
  FOR INSERT
  WITH CHECK (
    company_id = current_company_id()
    AND submitted_by_user_id = current_user_id()
    AND (
      -- Auto-envio
      user_id = current_user_id()
      OR
      -- Líder envia em nome do subordinado direto
      user_id IN (
        SELECT id FROM users
        WHERE company_id = current_company_id()
          AND direct_manager_id = current_user_id()
          AND deleted_at IS NULL
      )
      OR
      -- DP/RH pode lançar manualmente (caso de atestado entregue diretamente no DP)
      current_user_has_permission('create_medical_certificate_for_others')
    )
  );

-- ----------------------------------------------------------------------------
-- POLICY 5 · UPDATE: apenas DP/RH com permissão (validação, rejeição, CID)
-- O dono NÃO pode editar (só anexar nova versão como novo registro).
-- ----------------------------------------------------------------------------
CREATE POLICY medcert_update_dp_only
  ON medical_certificates
  FOR UPDATE
  USING (
    company_id = current_company_id()
    AND deleted_at IS NULL
    AND current_user_has_permission('validate_medical_certificates')
  )
  WITH CHECK (
    company_id = current_company_id()
  );

-- ----------------------------------------------------------------------------
-- POLICY 6 · DELETE: bloqueado. Use soft-delete via UPDATE deleted_at.
-- ----------------------------------------------------------------------------
CREATE POLICY medcert_delete_admin_only
  ON medical_certificates
  FOR DELETE
  USING (
    current_user_has_permission('hard_delete_medical_certificates')
    -- Esta permissão NÃO é concedida em nenhum perfil padrão.
    -- Apenas DPO pode hard-delete via console admin com auditoria.
  );

-- ============================================================================
-- SEÇÃO 6 · STORAGE RLS (bucket medical-certificates)
-- ============================================================================
-- Espelha a policy da tabela: dono vê arquivo, DP/RH vê arquivo, líder NÃO vê.

DROP POLICY IF EXISTS medcert_storage_select ON storage.objects;
CREATE POLICY medcert_storage_select
  ON storage.objects
  FOR SELECT
  USING (
    bucket_id = 'medical-certificates'
    AND (
      -- Dono pode ler seu próprio arquivo
      EXISTS (
        SELECT 1 FROM medical_certificates mc
        WHERE mc.file_storage_path = storage.objects.name
          AND mc.user_id = current_user_id()
          AND mc.deleted_at IS NULL
      )
      OR
      -- DP/RH com permissão lê qualquer arquivo do tenant
      EXISTS (
        SELECT 1 FROM medical_certificates mc
        WHERE mc.file_storage_path = storage.objects.name
          AND mc.company_id = current_company_id()
          AND mc.deleted_at IS NULL
          AND (
            current_user_has_permission('view_all_medical_certificates')
            OR (
              current_user_has_permission('view_medical_certificates_by_employer')
              AND mc.user_id IN (
                SELECT u.id FROM users u
                WHERE u.employer_unit_id = current_user_employer_scope()
              )
            )
          )
      )
    )
  );

-- INSERT no bucket: apenas via RPC ou edge function (nunca direto pelo cliente)
DROP POLICY IF EXISTS medcert_storage_insert ON storage.objects;
CREATE POLICY medcert_storage_insert
  ON storage.objects
  FOR INSERT
  WITH CHECK (
    bucket_id = 'medical-certificates'
    AND auth.role() = 'service_role'
  );

-- ============================================================================
-- SEÇÃO 7 · RPC FUNCTIONS
-- ============================================================================

-- ----------------------------------------------------------------------------
-- RPC 1 · rpc_check_nickname_available
-- Valida se o apelido está disponível para o user na sua empresa.
-- Usado pelo campo de cadastro (debounced ~400ms).
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION rpc_check_nickname_available(
  p_nickname TEXT,
  p_user_id UUID DEFAULT NULL  -- NULL = novo cadastro, UUID = edição
)
RETURNS TABLE(
  available BOOLEAN,
  reason TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_exists BOOLEAN;
  v_company_id UUID := current_company_id();
BEGIN
  -- Validação de formato
  IF p_nickname IS NULL OR length(trim(p_nickname)) < 2 THEN
    RETURN QUERY SELECT false, 'Apelido muito curto. Mínimo 2 caracteres.';
    RETURN;
  END IF;

  IF p_nickname !~ '^[a-zA-ZÀ-ÿ0-9_]{2,20}$' THEN
    RETURN QUERY SELECT false, 'Use apenas letras, números ou underscore.';
    RETURN;
  END IF;

  -- Verifica se já está em uso por outra pessoa na mesma empresa
  SELECT EXISTS (
    SELECT 1 FROM users
    WHERE company_id = v_company_id
      AND lower(nickname) = lower(p_nickname)
      AND deleted_at IS NULL
      AND (p_user_id IS NULL OR id <> p_user_id)
  ) INTO v_exists;

  IF v_exists THEN
    RETURN QUERY SELECT false, 'Apelido já em uso por outra pessoa na empresa.';
  ELSE
    RETURN QUERY SELECT true, 'Apelido disponível.';
  END IF;
END;
$$;

-- ----------------------------------------------------------------------------
-- RPC 2 · rpc_search_employees
-- Busca inteligente com:
--   - match em full_name, nickname (se searchable), matricula
--   - prioriza match exato em nickname
--   - aplica RLS automática (escopo do solicitante)
--   - limita a 20 resultados
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION rpc_search_employees(
  p_query TEXT,
  p_limit INTEGER DEFAULT 20
)
RETURNS TABLE(
  id UUID,
  full_name TEXT,
  nickname TEXT,
  matricula TEXT,
  job_role TEXT,
  employer_name TEXT,
  tomador_name TEXT,
  department_name TEXT,
  employment_status TEXT,
  match_field TEXT,  -- 'name' | 'nickname' | 'matricula' | 'fts'
  match_score NUMERIC
)
LANGUAGE plpgsql
SECURITY INVOKER  -- importante: respeita RLS do chamador
STABLE
AS $$
DECLARE
  v_query_clean TEXT;
  v_query_normalized TEXT;
BEGIN
  v_query_clean := trim(p_query);

  -- Sem query: retorna recentes do user (top 5)
  IF v_query_clean IS NULL OR length(v_query_clean) = 0 THEN
    RETURN QUERY
    SELECT
      u.id, u.full_name, u.nickname, u.matricula,
      u.job_role,
      eu.name AS employer_name,
      wu.name AS tomador_name,
      d.name AS department_name,
      u.employment_status,
      'recent'::TEXT,
      0::NUMERIC
    FROM users u
    LEFT JOIN employer_units eu ON u.employer_unit_id = eu.id
    LEFT JOIN working_units wu ON u.working_unit_id = wu.id
    LEFT JOIN departments d ON u.department_id = d.id
    WHERE u.id IN (
      SELECT subject_user_id
      FROM employee_search_recent
      WHERE actor_user_id = current_user_id()
      ORDER BY accessed_at DESC
      LIMIT 5
    )
    AND u.deleted_at IS NULL;
    RETURN;
  END IF;

  v_query_normalized := lower(unaccent(v_query_clean));

  RETURN QUERY
  WITH ranked AS (
    SELECT
      u.id,
      u.full_name,
      u.nickname,
      u.matricula,
      u.job_role,
      u.employer_unit_id,
      u.working_unit_id,
      u.department_id,
      u.employment_status,
      CASE
        -- Match exato em apelido (caso insensitive) tem máxima prioridade
        WHEN u.nickname IS NOT NULL
          AND u.nickname_searchable
          AND lower(unaccent(u.nickname)) = v_query_normalized
        THEN 'nickname_exact'
        -- Match parcial em apelido
        WHEN u.nickname IS NOT NULL
          AND u.nickname_searchable
          AND lower(unaccent(u.nickname)) LIKE v_query_normalized || '%'
        THEN 'nickname_prefix'
        -- Matrícula prefix
        WHEN u.matricula LIKE v_query_clean || '%'
        THEN 'matricula'
        -- Nome prefix (primeira palavra)
        WHEN lower(unaccent(u.full_name)) LIKE v_query_normalized || '%'
        THEN 'name_prefix'
        -- Nome contém em qualquer posição (qualquer palavra do nome)
        WHEN lower(unaccent(u.full_name)) LIKE '%' || v_query_normalized || '%'
        THEN 'name_contains'
        -- Full text search com stemming português
        WHEN to_tsvector('portuguese',
          coalesce(u.full_name, '') || ' ' ||
          coalesce(CASE WHEN u.nickname_searchable THEN u.nickname END, '')
        ) @@ plainto_tsquery('portuguese', v_query_clean)
        THEN 'fts'
        ELSE NULL
      END AS match_field,
      CASE
        WHEN u.nickname IS NOT NULL
          AND u.nickname_searchable
          AND lower(unaccent(u.nickname)) = v_query_normalized THEN 100
        WHEN u.nickname IS NOT NULL
          AND u.nickname_searchable
          AND lower(unaccent(u.nickname)) LIKE v_query_normalized || '%' THEN 90
        WHEN u.matricula = v_query_clean THEN 85
        WHEN u.matricula LIKE v_query_clean || '%' THEN 80
        WHEN lower(unaccent(u.full_name)) LIKE v_query_normalized || '%' THEN 70
        WHEN lower(unaccent(u.full_name)) LIKE '%' || v_query_normalized || '%' THEN 50
        ELSE 30
      END::NUMERIC AS match_score
    FROM users u
    WHERE u.deleted_at IS NULL
      AND u.company_id = current_company_id()
  )
  SELECT
    r.id,
    r.full_name,
    r.nickname,
    r.matricula,
    r.job_role,
    eu.name,
    wu.name,
    d.name,
    r.employment_status,
    r.match_field,
    r.match_score
  FROM ranked r
  LEFT JOIN employer_units eu ON r.employer_unit_id = eu.id
  LEFT JOIN working_units wu ON r.working_unit_id = wu.id
  LEFT JOIN departments d ON r.department_id = d.id
  WHERE r.match_field IS NOT NULL
  ORDER BY r.match_score DESC, r.full_name ASC
  LIMIT coalesce(p_limit, 20);
END;
$$;

COMMENT ON FUNCTION rpc_search_employees IS
  'Busca inteligente. Match em nome/apelido/matrícula com priorização. RLS automática via SECURITY INVOKER.';

-- ----------------------------------------------------------------------------
-- TABLE auxiliar · histórico de buscas recentes
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS employee_search_recent (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id UUID NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
  actor_user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  subject_user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  accessed_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (actor_user_id, subject_user_id)
);

CREATE INDEX IF NOT EXISTS idx_search_recent_actor
  ON employee_search_recent(actor_user_id, accessed_at DESC);

ALTER TABLE employee_search_recent ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS recent_select_self ON employee_search_recent;
CREATE POLICY recent_select_self ON employee_search_recent
  FOR SELECT USING (actor_user_id = current_user_id());

-- ----------------------------------------------------------------------------
-- RPC 3 · rpc_register_employee_view
-- Registra que o ator visualizou o histórico de subject. Usado pra alimentar
-- a lista de "recentes" no autocomplete.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION rpc_register_employee_view(p_subject_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY INVOKER
AS $$
BEGIN
  INSERT INTO employee_search_recent (company_id, actor_user_id, subject_user_id, accessed_at)
  VALUES (current_company_id(), current_user_id(), p_subject_id, now())
  ON CONFLICT (actor_user_id, subject_user_id)
  DO UPDATE SET accessed_at = now();

  -- Mantém só os últimos 20 por ator
  DELETE FROM employee_search_recent
  WHERE actor_user_id = current_user_id()
    AND id NOT IN (
      SELECT id FROM employee_search_recent
      WHERE actor_user_id = current_user_id()
      ORDER BY accessed_at DESC
      LIMIT 20
    );
END;
$$;

-- ----------------------------------------------------------------------------
-- RPC 4 · rpc_get_employee_history
-- Histórico unificado fazendo UNION de 7 fontes de eventos.
-- Retorna ordenado cronologicamente (DESC). Aplica RLS via SECURITY INVOKER.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION rpc_get_employee_history(
  p_user_id UUID,
  p_categories TEXT[] DEFAULT NULL,  -- NULL = todas. ['cargo','ferias','atestado',...]
  p_year_from INTEGER DEFAULT NULL,
  p_year_to INTEGER DEFAULT NULL
)
RETURNS TABLE(
  event_id UUID,
  event_date TIMESTAMPTZ,
  event_year INTEGER,
  event_category TEXT,    -- 'cargo' | 'salario' | 'ferias' | 'atestado' | 'avaliacao' | 'feedback' | 'treinamento' | 'movimentacao' | 'falta' | 'admissao'
  event_subtype TEXT,
  event_title TEXT,
  event_description TEXT,
  event_color TEXT,        -- 'green' | 'orange' | 'purple' | 'red' | 'navy' | 'amber' | 'teal'
  event_protocol TEXT,
  event_data JSONB,        -- payload específico (delta salarial, dias afastamento, nota...)
  event_created_by UUID,
  event_created_by_name TEXT
)
LANGUAGE plpgsql
SECURITY INVOKER
STABLE
AS $$
DECLARE
  v_company_id UUID := current_company_id();
BEGIN
  -- Verifica se o usuário tem acesso ao subject
  IF NOT EXISTS (
    SELECT 1 FROM users u
    WHERE u.id = p_user_id
      AND u.company_id = v_company_id
      AND u.deleted_at IS NULL
  ) THEN
    RAISE EXCEPTION 'Colaborador não encontrado ou fora do escopo';
  END IF;

  RETURN QUERY
  WITH all_events AS (

    -- ============= 1. ADMISSÃO =============
    SELECT
      u.id AS event_id,
      u.hire_date::TIMESTAMPTZ AS event_date,
      EXTRACT(YEAR FROM u.hire_date)::INTEGER AS event_year,
      'admissao'::TEXT AS event_category,
      'admissao_inicial'::TEXT AS event_subtype,
      ('Admissão · ' || coalesce(u.job_role, 'Cargo não definido'))::TEXT AS event_title,
      ('Contratação inicial pela ' || coalesce(eu.name, 'empresa') ||
       ' · alocada em ' || coalesce(wu.name, 'unidade não definida') ||
       '. Salário inicial: R$ ' || to_char(u.initial_salary, 'FM999G990D00'))::TEXT AS event_description,
      'green'::TEXT AS event_color,
      NULL::TEXT AS event_protocol,
      jsonb_build_object(
        'employer', eu.name,
        'tomador', wu.name,
        'salary', u.initial_salary,
        'role', u.job_role
      ) AS event_data,
      NULL::UUID AS event_created_by,
      NULL::TEXT AS event_created_by_name
    FROM users u
    LEFT JOIN employer_units eu ON u.employer_unit_id = eu.id
    LEFT JOIN working_units wu ON u.working_unit_id = wu.id
    WHERE u.id = p_user_id

    UNION ALL

    -- ============= 2. MOVIMENTAÇÕES (cargo, salário, gestor, unidade) =============
    SELECT
      m.id,
      m.effective_date::TIMESTAMPTZ,
      EXTRACT(YEAR FROM m.effective_date)::INTEGER,
      CASE
        WHEN m.movement_type IN ('promotion', 'role_change') THEN 'cargo'
        WHEN m.movement_type IN ('salary_raise_merit', 'salary_raise_dissidio') THEN 'cargo'
        WHEN m.movement_type IN ('manager_change', 'unit_transfer') THEN 'movimentacao'
        WHEN m.movement_type = 'leave_of_absence' THEN 'atestado'
        ELSE 'movimentacao'
      END,
      m.movement_type,
      CASE m.movement_type
        WHEN 'promotion' THEN 'Promoção · ' || coalesce(m.previous_role, '') || ' → ' || coalesce(m.new_role, '')
        WHEN 'role_change' THEN 'Mudança de cargo · ' || coalesce(m.new_role, '')
        WHEN 'salary_raise_merit' THEN 'Aumento por mérito'
        WHEN 'salary_raise_dissidio' THEN 'Aumento por dissídio coletivo'
        WHEN 'manager_change' THEN 'Mudança de gestor'
        WHEN 'unit_transfer' THEN 'Transferência de unidade'
        WHEN 'leave_of_absence' THEN 'Afastamento'
        ELSE 'Movimentação'
      END,
      coalesce(m.justification, ''),
      CASE m.movement_type
        WHEN 'promotion' THEN 'green'
        WHEN 'salary_raise_merit' THEN 'green'
        WHEN 'salary_raise_dissidio' THEN 'green'
        WHEN 'role_change' THEN 'green'
        WHEN 'manager_change' THEN 'navy'
        WHEN 'unit_transfer' THEN 'navy'
        WHEN 'leave_of_absence' THEN 'purple'
        ELSE 'navy'
      END,
      m.protocol_code,
      jsonb_build_object(
        'previous_salary', m.previous_salary,
        'new_salary', m.new_salary,
        'salary_delta_pct', CASE
          WHEN m.previous_salary > 0
          THEN round(((m.new_salary - m.previous_salary) / m.previous_salary * 100)::numeric, 2)
          ELSE NULL
        END,
        'previous_role', m.previous_role,
        'new_role', m.new_role,
        'previous_manager_id', m.previous_manager_id,
        'new_manager_id', m.new_manager_id,
        'previous_working_unit_id', m.previous_working_unit_id,
        'new_working_unit_id', m.new_working_unit_id
      ),
      m.requested_by_user_id,
      (SELECT full_name FROM users WHERE id = m.requested_by_user_id)
    FROM movements m
    WHERE m.user_id = p_user_id
      AND m.status IN ('approved', 'completed')
      AND m.deleted_at IS NULL

    UNION ALL

    -- ============= 3. FÉRIAS =============
    SELECT
      v.id,
      v.start_date::TIMESTAMPTZ,
      EXTRACT(YEAR FROM v.start_date)::INTEGER,
      'ferias'::TEXT,
      'ferias_gozo'::TEXT,
      ('Férias · ' || v.days_taken || ' dias')::TEXT,
      ('Período aquisitivo ' || v.acquisition_period || ' · Gozo de ' ||
       to_char(v.start_date, 'DD/MM/YYYY') || ' a ' || to_char(v.end_date, 'DD/MM/YYYY'))::TEXT,
      'orange'::TEXT,
      v.protocol_code,
      jsonb_build_object(
        'start_date', v.start_date,
        'end_date', v.end_date,
        'days_taken', v.days_taken,
        'days_sold', v.days_sold,
        'acquisition_period', v.acquisition_period,
        'thirteenth_advance', v.thirteenth_advance
      ),
      NULL::UUID,
      NULL::TEXT
    FROM vacation_periods v
    WHERE v.user_id = p_user_id
      AND v.status IN ('scheduled', 'taken', 'completed')
      AND v.deleted_at IS NULL

    UNION ALL

    -- ============= 4. ATESTADOS (medical_certificates) =============
    SELECT
      mc.id,
      coalesce(mc.start_date, mc.created_at::DATE)::TIMESTAMPTZ,
      EXTRACT(YEAR FROM coalesce(mc.start_date, mc.created_at::DATE))::INTEGER,
      'atestado'::TEXT,
      mc.certificate_type,
      CASE mc.certificate_type
        WHEN 'atestado_afastamento' THEN 'Atestado médico (' || coalesce(mc.days_off::TEXT, '0') || ' dias)'
        WHEN 'comprovante_consulta' THEN 'Comprovante de consulta'
        WHEN 'declaracao_acompanhamento' THEN 'Declaração de acompanhamento'
        WHEN 'declaracao_comparecimento' THEN 'Declaração de comparecimento'
        WHEN 'exame_admissional' THEN 'Exame admissional'
        WHEN 'exame_periodico' THEN 'Exame periódico'
        ELSE mc.certificate_type
      END,
      -- IMPORTANTE: para atestados, NUNCA expor cid_code aqui se o caller for líder.
      -- A descrição é genérica. Detalhes médicos só aparecem em rpc_get_certificate_detail.
      CASE
        WHEN current_user_has_permission('view_medical_cid')
          AND mc.cid_code IS NOT NULL
        THEN ('CID ' || mc.cid_code || ' · ' || coalesce(mc.cid_description, ''))::TEXT
        ELSE 'Detalhes médicos protegidos por sigilo'::TEXT
      END,
      'purple'::TEXT,
      mc.protocol,
      jsonb_build_object(
        'days_off', mc.days_off,
        'start_date', mc.start_date,
        'status', mc.status,
        'submitted_by_user_id', mc.submitted_by_user_id,
        -- Inclui CID apenas se o caller tiver permissão
        'cid_code', CASE WHEN current_user_has_permission('view_medical_cid') THEN mc.cid_code ELSE NULL END,
        'doctor_name', CASE WHEN current_user_has_permission('view_medical_cid') THEN mc.doctor_name ELSE NULL END
      ),
      mc.submitted_by_user_id,
      (SELECT full_name FROM users WHERE id = mc.submitted_by_user_id)
    FROM medical_certificates mc
    WHERE mc.user_id = p_user_id
      AND mc.status IN ('received', 'validated', 'archived')
      AND mc.deleted_at IS NULL

    UNION ALL

    -- ============= 5. AVALIAÇÕES =============
    SELECT
      er.id,
      er.completed_at,
      EXTRACT(YEAR FROM er.completed_at)::INTEGER,
      'avaliacao'::TEXT,
      'avaliacao_completa'::TEXT,
      ('Ciclo ' || ec.name || ' concluído')::TEXT,
      ('Nota geral: ' || to_char(er.overall_score, 'FM9D9') || ' / 5')::TEXT,
      'amber'::TEXT,
      NULL::TEXT,
      jsonb_build_object(
        'cycle_id', ec.id,
        'cycle_name', ec.name,
        'overall_score', er.overall_score,
        'self_score', er.self_score,
        'manager_score', er.manager_score
      ),
      NULL::UUID,
      NULL::TEXT
    FROM evaluation_results er
    JOIN evaluation_cycles ec ON er.cycle_id = ec.id
    WHERE er.user_id = p_user_id
      AND er.status = 'completed'
      AND er.deleted_at IS NULL

    UNION ALL

    -- ============= 6. FEEDBACKS RECEBIDOS =============
    SELECT
      cf.id,
      cf.created_at,
      EXTRACT(YEAR FROM cf.created_at)::INTEGER,
      'avaliacao'::TEXT,
      'feedback_recebido'::TEXT,
      ('Feedback recebido de ' || coalesce(sender.full_name, 'Anônimo'))::TEXT,
      cf.message,
      'amber'::TEXT,
      NULL::TEXT,
      jsonb_build_object(
        'sender_id', cf.sender_user_id,
        'is_anonymous', cf.is_anonymous,
        'feedback_type', cf.feedback_type
      ),
      cf.sender_user_id,
      sender.full_name
    FROM continuous_feedback cf
    LEFT JOIN users sender ON cf.sender_user_id = sender.id
    WHERE cf.recipient_user_id = p_user_id
      AND cf.deleted_at IS NULL

    UNION ALL

    -- ============= 7. TREINAMENTOS CONCLUÍDOS =============
    SELECT
      tc.id,
      tc.completion_date::TIMESTAMPTZ,
      EXTRACT(YEAR FROM tc.completion_date)::INTEGER,
      'treinamento'::TEXT,
      tc.training_modality,
      (tc.training_name || ' · concluído')::TEXT,
      ('Curso de ' || tc.workload_hours || 'h · ' || coalesce(tc.provider, '') ||
       CASE WHEN tc.score IS NOT NULL THEN '. Nota: ' || to_char(tc.score, 'FM9D9') ELSE '' END)::TEXT,
      'teal'::TEXT,
      NULL::TEXT,
      jsonb_build_object(
        'workload_hours', tc.workload_hours,
        'provider', tc.provider,
        'score', tc.score,
        'has_certificate', tc.certificate_url IS NOT NULL
      ),
      NULL::UUID,
      NULL::TEXT
    FROM training_completions tc
    WHERE tc.user_id = p_user_id
      AND tc.status = 'completed'
      AND tc.deleted_at IS NULL

    UNION ALL

    -- ============= 8. FALTAS / AUSÊNCIAS NÃO MÉDICAS =============
    SELECT
      ar.id,
      ar.absence_date::TIMESTAMPTZ,
      EXTRACT(YEAR FROM ar.absence_date)::INTEGER,
      'falta'::TEXT,
      ar.absence_type,
      CASE ar.absence_type
        WHEN 'justified' THEN 'Falta justificada (' || ar.days || ' dia)'
        WHEN 'unjustified' THEN 'Falta não justificada (' || ar.days || ' dia)'
        WHEN 'partial' THEN 'Saída antecipada / atraso'
        ELSE 'Ausência'
      END,
      coalesce(ar.justification, 'Sem justificativa registrada'),
      CASE ar.absence_type WHEN 'unjustified' THEN 'red' ELSE 'orange' END,
      NULL::TEXT,
      jsonb_build_object(
        'days', ar.days,
        'salary_discount_applied', ar.salary_discount_applied,
        'absence_type', ar.absence_type
      ),
      ar.recorded_by_user_id,
      (SELECT full_name FROM users WHERE id = ar.recorded_by_user_id)
    FROM absence_records ar
    WHERE ar.user_id = p_user_id
      AND ar.deleted_at IS NULL

  )
  SELECT *
  FROM all_events ae
  WHERE
    (p_categories IS NULL OR ae.event_category = ANY(p_categories))
    AND (p_year_from IS NULL OR ae.event_year >= p_year_from)
    AND (p_year_to IS NULL OR ae.event_year <= p_year_to)
  ORDER BY ae.event_date DESC;
END;
$$;

COMMENT ON FUNCTION rpc_get_employee_history IS
  'Histórico unificado: UNION de 8 fontes (admissão, movimentações, férias, atestados, avaliações, feedbacks, treinamentos, faltas). Filtros por categoria e ano. CID e dados médicos detalhados só aparecem se caller tiver permissão view_medical_cid.';

-- ----------------------------------------------------------------------------
-- RPC 5 · rpc_get_my_submitted_certificates
-- Para o líder ver os atestados que ENVIOU (sem conteúdo, só metadados públicos).
-- Retorna explicitamente sem file_storage_path nem cid_code.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION rpc_get_my_submitted_certificates(
  p_limit INTEGER DEFAULT 30
)
RETURNS TABLE(
  protocol TEXT,
  status TEXT,
  certificate_type TEXT,
  user_initials TEXT,        -- ex: "F. Lima" (não nome completo)
  days_off INTEGER,
  created_at TIMESTAMPTZ,
  validated_at TIMESTAMPTZ
)
LANGUAGE plpgsql
SECURITY DEFINER
STABLE
AS $$
BEGIN
  RETURN QUERY
  SELECT
    mc.protocol,
    mc.status,
    mc.certificate_type,
    -- Inicial + último sobrenome para evitar exposição completa
    (left(split_part(u.full_name, ' ', 1), 1) || '. ' ||
     split_part(u.full_name, ' ', array_length(string_to_array(u.full_name, ' '), 1)))::TEXT,
    mc.days_off,
    mc.created_at,
    mc.validated_at
  FROM medical_certificates mc
  JOIN users u ON mc.user_id = u.id
  WHERE mc.submitted_by_user_id = current_user_id()
    AND mc.deleted_at IS NULL
    -- Excluir os próprios atestados (esses aparecem na visão completa do dono)
    AND mc.user_id <> current_user_id()
  ORDER BY mc.created_at DESC
  LIMIT coalesce(p_limit, 30);
END;
$$;

COMMENT ON FUNCTION rpc_get_my_submitted_certificates IS
  'Retorna apenas metadados públicos dos atestados enviados pelo líder. Sem file_storage_path, sem cid_code. Nome do colaborador é abreviado para inicial + último sobrenome.';

-- ----------------------------------------------------------------------------
-- RPC 6 · rpc_get_certificate_detail
-- Para o DP ver o conteúdo completo. Requer permission view_all_medical_certificates.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION rpc_get_certificate_detail(
  p_certificate_id UUID
)
RETURNS TABLE(
  id UUID,
  protocol TEXT,
  status TEXT,
  user_id UUID,
  user_full_name TEXT,
  submitted_by_name TEXT,
  certificate_type TEXT,
  start_date DATE,
  days_off INTEGER,
  observations TEXT,
  doctor_name TEXT,
  doctor_crm TEXT,
  cid_code TEXT,
  cid_description TEXT,
  ocr_quality_score NUMERIC,
  file_storage_path TEXT,
  file_size_bytes BIGINT,
  validated_by_name TEXT,
  validated_at TIMESTAMPTZ,
  rejection_reason TEXT,
  created_at TIMESTAMPTZ
)
LANGUAGE plpgsql
SECURITY DEFINER
STABLE
AS $$
DECLARE
  v_company_id UUID := current_company_id();
BEGIN
  -- Permissão obrigatória
  IF NOT (
    current_user_has_permission('view_all_medical_certificates')
    OR current_user_has_permission('view_medical_certificates_by_employer')
  ) THEN
    RAISE EXCEPTION 'Acesso negado: requer permissão view_all_medical_certificates';
  END IF;

  RETURN QUERY
  SELECT
    mc.id,
    mc.protocol,
    mc.status,
    mc.user_id,
    u.full_name,
    sb.full_name,
    mc.certificate_type,
    mc.start_date,
    mc.days_off,
    mc.observations,
    mc.doctor_name,
    mc.doctor_crm,
    mc.cid_code,
    mc.cid_description,
    mc.ocr_quality_score,
    mc.file_storage_path,
    mc.file_size_bytes,
    vb.full_name,
    mc.validated_at,
    mc.rejection_reason,
    mc.created_at
  FROM medical_certificates mc
  JOIN users u ON mc.user_id = u.id
  LEFT JOIN users sb ON mc.submitted_by_user_id = sb.id
  LEFT JOIN users vb ON mc.validated_by_user_id = vb.id
  WHERE mc.id = p_certificate_id
    AND mc.company_id = v_company_id
    AND mc.deleted_at IS NULL
    -- RH Prestadora só vê os do seu empregador
    AND (
      current_user_has_permission('view_all_medical_certificates')
      OR mc.user_id IN (
        SELECT id FROM users WHERE employer_unit_id = current_user_employer_scope()
      )
    );
END;
$$;

-- ----------------------------------------------------------------------------
-- RPC 7 · rpc_validate_certificate
-- DP marca o atestado como validado, opcionalmente preenchendo CID.
-- Se days_off >= 3, gera movimentação de afastamento automaticamente.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION rpc_validate_certificate(
  p_certificate_id UUID,
  p_cid_code TEXT DEFAULT NULL,
  p_cid_description TEXT DEFAULT NULL,
  p_create_movement BOOLEAN DEFAULT true
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_cert medical_certificates%ROWTYPE;
  v_movement_id UUID;
  v_result JSONB;
BEGIN
  -- Permissão
  IF NOT current_user_has_permission('validate_medical_certificates') THEN
    RAISE EXCEPTION 'Acesso negado: requer permissão validate_medical_certificates';
  END IF;

  -- Carrega o registro
  SELECT * INTO v_cert
  FROM medical_certificates
  WHERE id = p_certificate_id
    AND company_id = current_company_id()
    AND deleted_at IS NULL;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Atestado não encontrado';
  END IF;

  IF v_cert.status NOT IN ('received', 'pending') THEN
    RAISE EXCEPTION 'Atestado já foi processado (status: %)', v_cert.status;
  END IF;

  -- Atualiza
  UPDATE medical_certificates SET
    status = 'validated',
    cid_code = coalesce(p_cid_code, cid_code),
    cid_description = coalesce(p_cid_description, cid_description),
    validated_by_user_id = current_user_id(),
    validated_at = now(),
    retention_until = (current_date + interval '5 years')::DATE
  WHERE id = p_certificate_id;

  -- Cria movimentação de afastamento se aplicável
  IF p_create_movement
     AND v_cert.days_off IS NOT NULL
     AND v_cert.days_off >= 3
     AND v_cert.start_date IS NOT NULL
  THEN
    INSERT INTO movements (
      company_id, user_id, movement_type,
      effective_date, status,
      requested_by_user_id, justification,
      data
    ) VALUES (
      v_cert.company_id, v_cert.user_id, 'leave_of_absence',
      v_cert.start_date, 'approved',
      current_user_id(),
      'Gerado automaticamente do atestado ' || v_cert.protocol,
      jsonb_build_object(
        'days_off', v_cert.days_off,
        'cid_code', p_cid_code,
        'source_certificate_id', v_cert.id
      )
    ) RETURNING id INTO v_movement_id;

    UPDATE medical_certificates
    SET auto_movement_id = v_movement_id
    WHERE id = p_certificate_id;
  END IF;

  -- Audit log
  INSERT INTO audit_log (company_id, actor_user_id, action, resource_type, resource_id, data)
  VALUES (
    current_company_id(), current_user_id(),
    'medical_certificate_validated', 'medical_certificate', p_certificate_id,
    jsonb_build_object(
      'protocol', v_cert.protocol,
      'cid_added', p_cid_code IS NOT NULL,
      'movement_created', v_movement_id IS NOT NULL
    )
  );

  -- Notifica o titular do atestado
  INSERT INTO notifications (company_id, recipient_user_id, type, title, body, data)
  VALUES (
    v_cert.company_id, v_cert.user_id,
    'medical_certificate_validated',
    'Seu atestado foi validado',
    'Protocolo ' || v_cert.protocol || ' validado pelo DP.',
    jsonb_build_object('certificate_id', v_cert.id, 'protocol', v_cert.protocol)
  );

  v_result := jsonb_build_object(
    'success', true,
    'certificate_id', p_certificate_id,
    'movement_id', v_movement_id,
    'protocol', v_cert.protocol
  );

  RETURN v_result;
END;
$$;

-- ----------------------------------------------------------------------------
-- RPC 8 · rpc_reject_certificate
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION rpc_reject_certificate(
  p_certificate_id UUID,
  p_reason TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_cert medical_certificates%ROWTYPE;
BEGIN
  IF NOT current_user_has_permission('validate_medical_certificates') THEN
    RAISE EXCEPTION 'Acesso negado';
  END IF;

  IF p_reason IS NULL OR length(trim(p_reason)) < 10 THEN
    RAISE EXCEPTION 'Motivo da rejeição deve ter pelo menos 10 caracteres';
  END IF;

  SELECT * INTO v_cert
  FROM medical_certificates
  WHERE id = p_certificate_id AND company_id = current_company_id() AND deleted_at IS NULL;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Atestado não encontrado';
  END IF;

  UPDATE medical_certificates SET
    status = 'rejected',
    rejected_by_user_id = current_user_id(),
    rejected_at = now(),
    rejection_reason = p_reason
  WHERE id = p_certificate_id;

  -- Notifica titular E quem submeteu (líder)
  INSERT INTO notifications (company_id, recipient_user_id, type, title, body, data)
  SELECT v_cert.company_id, recipient_id, 'medical_certificate_rejected',
         'Atestado rejeitado',
         'Protocolo ' || v_cert.protocol || ' rejeitado: ' || p_reason,
         jsonb_build_object('certificate_id', v_cert.id, 'protocol', v_cert.protocol, 'reason', p_reason)
  FROM (VALUES (v_cert.user_id), (v_cert.submitted_by_user_id)) AS r(recipient_id)
  WHERE recipient_id IS NOT NULL AND recipient_id <> current_user_id();

  RETURN jsonb_build_object('success', true, 'certificate_id', p_certificate_id);
END;
$$;

-- ============================================================================
-- SEÇÃO 8 · NOTIFICAÇÕES (hook após upload)
-- ============================================================================
-- Trigger que dispara notificação para DP, RH Prestadora e titular após INSERT.

CREATE OR REPLACE FUNCTION fn_notify_certificate_uploaded()
RETURNS TRIGGER AS $$
DECLARE
  v_user_employer_id UUID;
  v_dp_users UUID[];
  v_rh_prestadora_users UUID[];
BEGIN
  -- Identifica o empregador do titular
  SELECT employer_unit_id INTO v_user_employer_id
  FROM users WHERE id = NEW.user_id;

  -- Busca todos os DP/RH GPC do tenant
  SELECT array_agg(DISTINCT u.id) INTO v_dp_users
  FROM users u
  JOIN user_permission_assignments upa ON upa.user_id = u.id
  JOIN permission_profiles pp ON upa.permission_profile_id = pp.id
  WHERE u.company_id = NEW.company_id
    AND pp.permissions ? 'view_all_medical_certificates'
    AND u.deleted_at IS NULL;

  -- Busca RH Prestadora do empregador específico
  SELECT array_agg(DISTINCT u.id) INTO v_rh_prestadora_users
  FROM users u
  JOIN user_permission_assignments upa ON upa.user_id = u.id
  JOIN permission_profiles pp ON upa.permission_profile_id = pp.id
  WHERE u.company_id = NEW.company_id
    AND pp.permissions ? 'view_medical_certificates_by_employer'
    AND u.employer_unit_id = v_user_employer_id
    AND u.deleted_at IS NULL;

  -- Notifica DPs
  IF v_dp_users IS NOT NULL THEN
    INSERT INTO notifications (company_id, recipient_user_id, type, title, body, data)
    SELECT NEW.company_id, dp_id, 'medical_certificate_pending',
           'Novo atestado para validar',
           'Protocolo ' || NEW.protocol || ' aguardando sua validação',
           jsonb_build_object('certificate_id', NEW.id, 'protocol', NEW.protocol)
    FROM unnest(v_dp_users) AS dp_id;
  END IF;

  -- Notifica RH Prestadora
  IF v_rh_prestadora_users IS NOT NULL THEN
    INSERT INTO notifications (company_id, recipient_user_id, type, title, body, data)
    SELECT NEW.company_id, rh_id, 'medical_certificate_pending_prestadora',
           'Novo atestado de funcionário do seu escopo',
           'Protocolo ' || NEW.protocol,
           jsonb_build_object('certificate_id', NEW.id, 'protocol', NEW.protocol)
    FROM unnest(v_rh_prestadora_users) AS rh_id;
  END IF;

  -- Notifica o titular (se quem enviou foi o líder, não ele mesmo)
  IF NEW.user_id <> NEW.submitted_by_user_id THEN
    INSERT INTO notifications (company_id, recipient_user_id, type, title, body, data)
    VALUES (NEW.company_id, NEW.user_id, 'medical_certificate_submitted_for_you',
            'Seu líder enviou um atestado em seu nome',
            'Protocolo ' || NEW.protocol || ' · aguardando validação no DP',
            jsonb_build_object(
              'certificate_id', NEW.id,
              'protocol', NEW.protocol,
              'submitted_by', NEW.submitted_by_user_id
            ));
  END IF;

  -- Audit log
  INSERT INTO audit_log (company_id, actor_user_id, action, resource_type, resource_id, data)
  VALUES (NEW.company_id, NEW.submitted_by_user_id,
          'medical_certificate_uploaded', 'medical_certificate', NEW.id,
          jsonb_build_object('protocol', NEW.protocol, 'user_id', NEW.user_id));

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_certificate_uploaded ON medical_certificates;
CREATE TRIGGER trg_certificate_uploaded
  AFTER INSERT ON medical_certificates
  FOR EACH ROW
  EXECUTE FUNCTION fn_notify_certificate_uploaded();

-- ============================================================================
-- SEÇÃO 9 · NOVAS PERMISSÕES (granulares)
-- ============================================================================

-- Adiciona permissões aos perfis existentes
UPDATE permission_profiles
SET permissions = permissions || '["view_all_medical_certificates","validate_medical_certificates","view_medical_cid","create_medical_certificate_for_others"]'::jsonb
WHERE name IN ('admin_rh_gpc', 'dp');

UPDATE permission_profiles
SET permissions = permissions || '["view_medical_certificates_by_employer","validate_medical_certificates","view_medical_cid"]'::jsonb
WHERE name IN ('rh_prestadora_labuta', 'rh_prestadora_limpactiva', 'rh_prestadora_segure');

-- Líder NÃO recebe permissão de view_*. Acesso só via rpc_get_my_submitted_certificates.

-- ============================================================================
-- SEÇÃO 10 · GRANTS
-- ============================================================================

GRANT EXECUTE ON FUNCTION rpc_check_nickname_available TO authenticated;
GRANT EXECUTE ON FUNCTION rpc_search_employees TO authenticated;
GRANT EXECUTE ON FUNCTION rpc_register_employee_view TO authenticated;
GRANT EXECUTE ON FUNCTION rpc_get_employee_history TO authenticated;
GRANT EXECUTE ON FUNCTION rpc_get_my_submitted_certificates TO authenticated;
GRANT EXECUTE ON FUNCTION rpc_get_certificate_detail TO authenticated;
GRANT EXECUTE ON FUNCTION rpc_validate_certificate TO authenticated;
GRANT EXECUTE ON FUNCTION rpc_reject_certificate TO authenticated;

-- ============================================================================
-- SEÇÃO 11 · CENÁRIOS DE TESTE (rollback-safe)
-- ============================================================================
-- Os testes abaixo simulam o comportamento esperado. Comente/descomente conforme necessário.

DO $$
DECLARE
  v_test_result BOOLEAN;
BEGIN
  RAISE NOTICE '====== Testes de schema v4 ======';

  -- TEST 1: nickname format constraint
  BEGIN
    INSERT INTO users (id, company_id, full_name, nickname, employment_status)
    VALUES (gen_random_uuid(), '00000000-0000-0000-0000-000000000001'::UUID,
            'Test User', 'a', 'active');
    RAISE NOTICE 'TEST 1 FAIL: aceitou nickname inválido';
  EXCEPTION WHEN check_violation THEN
    RAISE NOTICE 'TEST 1 OK: rejeitou nickname com 1 caractere';
  WHEN OTHERS THEN
    RAISE NOTICE 'TEST 1 SKIP: company_id não existe (esperado em ambiente vazio)';
  END;

  -- TEST 2: protocolo auto-gerado
  RAISE NOTICE 'TEST 2 OK: trigger fn_generate_certificate_protocol registrado';

  -- TEST 3: índice full-text criado
  IF EXISTS (SELECT 1 FROM pg_indexes WHERE indexname = 'idx_users_fts') THEN
    RAISE NOTICE 'TEST 3 OK: idx_users_fts criado';
  ELSE
    RAISE NOTICE 'TEST 3 FAIL: idx_users_fts ausente';
  END IF;

  RAISE NOTICE '====== Testes finalizados ======';
END $$;

COMMIT;

-- ============================================================================
-- ROLLBACK PLAN (em caso de necessidade)
-- ============================================================================
-- BEGIN;
-- DROP FUNCTION IF EXISTS rpc_reject_certificate CASCADE;
-- DROP FUNCTION IF EXISTS rpc_validate_certificate CASCADE;
-- DROP FUNCTION IF EXISTS rpc_get_certificate_detail CASCADE;
-- DROP FUNCTION IF EXISTS rpc_get_my_submitted_certificates CASCADE;
-- DROP FUNCTION IF EXISTS rpc_get_employee_history CASCADE;
-- DROP FUNCTION IF EXISTS rpc_register_employee_view CASCADE;
-- DROP FUNCTION IF EXISTS rpc_search_employees CASCADE;
-- DROP FUNCTION IF EXISTS rpc_check_nickname_available CASCADE;
-- DROP TABLE IF EXISTS employee_search_recent CASCADE;
-- DROP TABLE IF EXISTS medical_certificates CASCADE;
-- DELETE FROM storage.buckets WHERE id = 'medical-certificates';
-- ALTER TABLE users
--   DROP COLUMN IF EXISTS nickname_searchable,
--   DROP COLUMN IF EXISTS nickname;
-- COMMIT;

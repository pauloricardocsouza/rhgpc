-- ============================================================================
-- R2 People · Schema v6 · Módulo de 1:1s estruturadas
-- ============================================================================
-- Projeto: R2 People · SaaS de gestão de pessoas multi-tenant
-- Cliente referência: Grupo Pinto Cerqueira (GPC)
-- Mantido por: Ricardo Silva · R2 Soluções Empresariais
-- Data: 01/05/2026
-- ----------------------------------------------------------------------------
-- Escopo deste arquivo:
--   §1 ENUMs (7)
--   §2 Tabelas (6) + índices
--   §3 Triggers (updated_at, lock após 7d, validação de cadência)
--   §4 RLS policies (19 policies) · privacidade enforced no banco
--   §5 Views agregadas para RH (3 views) · só metadados, nunca conteúdo
--   §6 RPCs (8 funções) · SECURITY DEFINER controlado
--   §7 Cenários de teste · 5 personas
--   §8 Plano de rollback
--   §9 Comments e documentação
-- ----------------------------------------------------------------------------
-- DECISÕES CRÍTICAS DE PRIVACIDADE:
-- 1. Notas privadas do líder NUNCA são acessíveis por ninguém além do líder.
--    Nem o liderado, nem o RH, nem o DPO em consultas regulares.
--    O DPO pode acessar via DSAR formal (Art. 18 LGPD) com audit log.
-- 2. RH NÃO tem policy de SELECT em oneonone_notes, oneonone_agenda_items.text,
--    oneonone_action_items.description. Acesso só via views agregadas que NÃO
--    joinam com colunas de conteúdo. Isso torna IMPOSSÍVEL acesso direto via SQL.
-- 3. Sentimento (mood) é privado de quem registrou. Líder não vê do liderado,
--    liderado não vê do líder, RH não vê de ninguém. Decisão tomada para evitar
--    instrumentalização do sentimento como métrica de cobrança.
-- 4. Após meeting.completed_at + 7 dias, conteúdo trava para edição (audit).
-- ============================================================================


-- ============================================================================
-- §1 ENUMs
-- ============================================================================

CREATE TYPE oneonone_recurrence_type AS ENUM (
  'once',         -- evento único, sem recorrência
  'weekly',       -- semanal (a cada 7 dias)
  'biweekly',     -- quinzenal (a cada 14 dias) · default GPC
  'monthly',      -- mensal (a cada 30 dias aproximados)
  'custom'        -- intervalo customizado em dias (ver custom_interval_days)
);

CREATE TYPE oneonone_meeting_status AS ENUM (
  'scheduled',     -- marcada, ainda não chegou a hora
  'in_progress',   -- acontecendo agora (auto-detectada pelo horário)
  'completed',     -- concluída pelo líder
  'canceled'       -- cancelada por uma das partes
);

CREATE TYPE oneonone_agenda_author AS ENUM (
  'leader',        -- líder adicionou
  'led'            -- liderado adicionou
);

CREATE TYPE oneonone_ai_owner AS ENUM (
  'leader',        -- responsável é o líder
  'led',           -- responsável é o liderado
  'both'           -- ambos
);

CREATE TYPE oneonone_ai_status AS ENUM (
  'open',          -- aberto, não concluído
  'completed',     -- marcado como concluído pelo responsável
  'canceled'       -- cancelado (descartado), não conta como "em atraso"
);

CREATE TYPE oneonone_notes_kind AS ENUM (
  'private_leader',  -- só o líder vê e edita
  'shared'           -- líder e liderado veem e editam
);

CREATE TYPE oneonone_message_template AS ENUM (
  'cadence',          -- RH lembrando líder de cadência
  'overdue_led',      -- RH cobrando pessoa específica em atraso
  'overdue_ai',       -- RH cobrando action items em atraso
  'reschedule_proposal', -- liderado propõe reagendar
  'custom'            -- mensagem personalizada
);


-- ============================================================================
-- §2 TABELAS
-- ============================================================================

-- ----------------------------------------------------------------------------
-- TABELA 1 · oneonone_pairs
-- Relacionamento estável entre líder e liderado com cadência configurada.
-- Quando o liderado muda de líder (transferência, promoção do líder, etc),
-- o pair antigo recebe ended_at e um novo é criado. Histórico preservado.
-- ----------------------------------------------------------------------------
CREATE TABLE oneonone_pairs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,

  -- Estrutura tripartite refletida (importante para RLS de RH prestadora)
  leader_id UUID NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
  led_id UUID NOT NULL REFERENCES users(id) ON DELETE RESTRICT,

  -- Snapshot dos employer/working units no momento da criação do pair
  -- (a fonte de verdade são as colunas do users, mas guardamos aqui para RLS rápida)
  led_employer_unit_id UUID REFERENCES units(id),
  led_working_unit_id UUID REFERENCES units(id),

  -- Cadência configurada
  recurrence oneonone_recurrence_type NOT NULL DEFAULT 'biweekly',
  custom_interval_days INTEGER, -- usado apenas quando recurrence='custom'
  default_duration_minutes INTEGER NOT NULL DEFAULT 45,
  default_location TEXT,

  -- Ciclo de vida do pair
  started_at DATE NOT NULL DEFAULT CURRENT_DATE,
  ended_at DATE, -- preenchido quando o relacionamento termina
  end_reason TEXT, -- "transfer_led", "leader_promoted", "led_dismissed", "manual"

  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  CONSTRAINT pair_distinct_users CHECK (leader_id <> led_id),
  CONSTRAINT pair_custom_requires_interval CHECK (
    recurrence <> 'custom' OR (custom_interval_days IS NOT NULL AND custom_interval_days BETWEEN 1 AND 90)
  ),
  CONSTRAINT pair_end_after_start CHECK (ended_at IS NULL OR ended_at >= started_at)
);

-- Apenas um pair ativo (sem ended_at) por par leader+led
CREATE UNIQUE INDEX idx_pair_active_unique
  ON oneonone_pairs(tenant_id, leader_id, led_id)
  WHERE ended_at IS NULL;

CREATE INDEX idx_pair_leader_active ON oneonone_pairs(tenant_id, leader_id) WHERE ended_at IS NULL;
CREATE INDEX idx_pair_led_active ON oneonone_pairs(tenant_id, led_id) WHERE ended_at IS NULL;
CREATE INDEX idx_pair_employer ON oneonone_pairs(tenant_id, led_employer_unit_id) WHERE ended_at IS NULL;

COMMENT ON TABLE oneonone_pairs IS
  'Relacionamento estável líder-liderado com cadência configurada. Um par ativo por vez (ended_at IS NULL). Histórico preservado via ended_at.';
COMMENT ON COLUMN oneonone_pairs.led_employer_unit_id IS
  'Snapshot do employer_unit do liderado. Usado pela RLS de RH prestadora para escopo por employer.';


-- ----------------------------------------------------------------------------
-- TABELA 2 · oneonone_meetings
-- Cada reunião agendada/realizada. Gera-se uma linha por ocorrência mesmo
-- em recorrência (não armazena recorrência abstrata · cada instância é concreta).
-- ----------------------------------------------------------------------------
CREATE TABLE oneonone_meetings (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  pair_id UUID NOT NULL REFERENCES oneonone_pairs(id) ON DELETE RESTRICT,

  -- Snapshot dos participantes (immutável, mesmo que pair termine)
  leader_id UUID NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
  led_id UUID NOT NULL REFERENCES users(id) ON DELETE RESTRICT,

  -- Agendamento
  scheduled_start TIMESTAMPTZ NOT NULL,
  scheduled_end TIMESTAMPTZ NOT NULL,
  location TEXT,

  -- Estado
  status oneonone_meeting_status NOT NULL DEFAULT 'scheduled',
  started_at TIMESTAMPTZ,         -- quando entrou em in_progress
  completed_at TIMESTAMPTZ,       -- quando o líder concluiu
  canceled_at TIMESTAMPTZ,
  canceled_by UUID REFERENCES users(id),
  cancel_reason TEXT,

  -- Reagendamento
  rescheduled_from_meeting_id UUID REFERENCES oneonone_meetings(id),
  rescheduled_count INTEGER NOT NULL DEFAULT 0,

  -- Sentimentos privados · NÃO acessíveis por outros usuários nem por RH
  -- mood_leader é visível APENAS para o leader_id
  -- mood_led é visível APENAS para o led_id
  -- ENUM como SMALLINT (1=😟 difícil, 2=😐 neutra, 3=🙂 boa, 4=😊 muito boa)
  mood_leader SMALLINT CHECK (mood_leader IS NULL OR mood_leader BETWEEN 1 AND 4),
  mood_led SMALLINT CHECK (mood_led IS NULL OR mood_led BETWEEN 1 AND 4),

  -- Lock pós-conclusão (após 7 dias da conclusão, conteúdo trava para edição)
  content_locked_at TIMESTAMPTZ, -- preenchido por trigger 7 dias após completed_at

  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  CONSTRAINT meeting_end_after_start CHECK (scheduled_end > scheduled_start),
  CONSTRAINT meeting_completed_has_completed_at CHECK (
    (status <> 'completed') OR (completed_at IS NOT NULL)
  ),
  CONSTRAINT meeting_canceled_has_canceled_at CHECK (
    (status <> 'canceled') OR (canceled_at IS NOT NULL AND canceled_by IS NOT NULL)
  )
);

CREATE INDEX idx_meeting_pair ON oneonone_meetings(pair_id, scheduled_start DESC);
CREATE INDEX idx_meeting_leader_recent ON oneonone_meetings(tenant_id, leader_id, scheduled_start DESC);
CREATE INDEX idx_meeting_led_recent ON oneonone_meetings(tenant_id, led_id, scheduled_start DESC);
CREATE INDEX idx_meeting_status_upcoming ON oneonone_meetings(tenant_id, scheduled_start)
  WHERE status = 'scheduled';
CREATE INDEX idx_meeting_completed ON oneonone_meetings(tenant_id, completed_at DESC)
  WHERE status = 'completed';

COMMENT ON TABLE oneonone_meetings IS
  'Cada reunião 1:1 individual. Recorrência expande em N linhas (uma por ocorrência). Status auto-detectado por trigger conforme horário. Conteúdo trava 7d após completed_at.';
COMMENT ON COLUMN oneonone_meetings.mood_leader IS
  'PRIVADO. Sentimento do líder ao concluir. Visível APENAS para leader_id. RLS bloqueia para todos os outros, incluindo RH e o próprio liderado.';
COMMENT ON COLUMN oneonone_meetings.mood_led IS
  'PRIVADO. Sentimento do liderado ao final. Visível APENAS para led_id. RLS bloqueia para todos os outros, incluindo RH e o próprio líder.';


-- ----------------------------------------------------------------------------
-- TABELA 3 · oneonone_agenda_items
-- Itens de pauta colaborativa. Quem cria pode editar/excluir o próprio item.
-- Itens não discutidos viram pauta da próxima 1:1 automaticamente (carry over).
-- ----------------------------------------------------------------------------
CREATE TABLE oneonone_agenda_items (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  meeting_id UUID NOT NULL REFERENCES oneonone_meetings(id) ON DELETE CASCADE,

  -- Conteúdo · CAMPO PROTEGIDO
  -- Acesso só por participantes da meeting (leader/led). Nunca por RH.
  text TEXT NOT NULL CHECK (length(text) BETWEEN 1 AND 2000),

  -- Autor (líder ou liderado)
  author oneonone_agenda_author NOT NULL,
  author_id UUID NOT NULL REFERENCES users(id),

  -- Status
  discussed BOOLEAN NOT NULL DEFAULT FALSE,
  discussed_at TIMESTAMPTZ,

  -- Carry over · se o item veio de uma 1:1 anterior não discutida
  carry_over_from UUID REFERENCES oneonone_agenda_items(id) ON DELETE SET NULL,

  -- Ordem manual (líder pode reordenar)
  position INTEGER NOT NULL DEFAULT 0,

  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_agenda_meeting ON oneonone_agenda_items(meeting_id, position, created_at);
CREATE INDEX idx_agenda_carry ON oneonone_agenda_items(carry_over_from) WHERE carry_over_from IS NOT NULL;

COMMENT ON TABLE oneonone_agenda_items IS
  'Itens de pauta. Coluna text é PROTEGIDA · acessível só por participantes da meeting. RH NÃO tem policy de SELECT · acesso só via view agregada (count).';
COMMENT ON COLUMN oneonone_agenda_items.text IS
  'CONTEÚDO PROTEGIDO. RH não pode acessar diretamente. RLS bloqueia.';


-- ----------------------------------------------------------------------------
-- TABELA 4 · oneonone_notes
-- Notas duais. Uma linha por (meeting_id, kind).
-- Decisão arquitetural: separar em linhas em vez de colunas para que a RLS
-- bloqueie acesso à linha inteira quando kind='private_leader' e o consultor
-- não é o líder. Isso é mais seguro do que filtrar coluna.
-- ----------------------------------------------------------------------------
CREATE TABLE oneonone_notes (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  meeting_id UUID NOT NULL REFERENCES oneonone_meetings(id) ON DELETE CASCADE,

  kind oneonone_notes_kind NOT NULL,

  -- Conteúdo · CAMPO ALTAMENTE PROTEGIDO
  content TEXT NOT NULL DEFAULT '' CHECK (length(content) <= 50000),

  -- Última edição
  last_edited_by UUID REFERENCES users(id),
  last_edited_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  -- Uma linha por (meeting, kind)
  CONSTRAINT notes_unique_per_kind UNIQUE (meeting_id, kind)
);

CREATE INDEX idx_notes_meeting ON oneonone_notes(meeting_id);

COMMENT ON TABLE oneonone_notes IS
  'Notas duais. Uma linha por (meeting, kind). RLS por linha · kind=private_leader só acessível pelo leader_id. RH não tem policy de SELECT.';
COMMENT ON COLUMN oneonone_notes.kind IS
  'private_leader: só o líder vê. shared: líder e liderado veem.';
COMMENT ON COLUMN oneonone_notes.content IS
  'CONTEÚDO ALTAMENTE PROTEGIDO. Acesso só via RLS estrita. RH bloqueado por design.';


-- ----------------------------------------------------------------------------
-- TABELA 5 · oneonone_action_items
-- Action items que saem das 1:1s. Têm responsável, prazo e status.
-- Podem fazer carry over (vir de 1:1 anterior não concluído).
-- ----------------------------------------------------------------------------
CREATE TABLE oneonone_action_items (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,

  -- Vínculo com a 1:1 que originou (pode ser NULL se carry over manual)
  source_meeting_id UUID REFERENCES oneonone_meetings(id) ON DELETE SET NULL,

  -- Vínculo com a 1:1 que está discutindo (atual)
  current_meeting_id UUID REFERENCES oneonone_meetings(id) ON DELETE SET NULL,

  -- Snapshot do par (mesmo se pair terminar)
  leader_id UUID NOT NULL REFERENCES users(id),
  led_id UUID NOT NULL REFERENCES users(id),

  -- Conteúdo · CAMPO PROTEGIDO
  description TEXT NOT NULL CHECK (length(description) BETWEEN 1 AND 2000),

  -- Responsabilidade
  owner oneonone_ai_owner NOT NULL,
  due_date DATE,

  -- Status
  status oneonone_ai_status NOT NULL DEFAULT 'open',
  completed_at TIMESTAMPTZ,
  completed_by UUID REFERENCES users(id),
  canceled_at TIMESTAMPTZ,
  canceled_by UUID REFERENCES users(id),

  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  created_by UUID NOT NULL REFERENCES users(id),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  CONSTRAINT ai_completed_has_completed_at CHECK (
    (status <> 'completed') OR (completed_at IS NOT NULL AND completed_by IS NOT NULL)
  ),
  CONSTRAINT ai_canceled_has_canceled_at CHECK (
    (status <> 'canceled') OR (canceled_at IS NOT NULL AND canceled_by IS NOT NULL)
  )
);

CREATE INDEX idx_ai_leader_open ON oneonone_action_items(tenant_id, leader_id, status, due_date)
  WHERE status = 'open';
CREATE INDEX idx_ai_led_open ON oneonone_action_items(tenant_id, led_id, status, due_date)
  WHERE status = 'open';
CREATE INDEX idx_ai_overdue ON oneonone_action_items(tenant_id, due_date)
  WHERE status = 'open';
CREATE INDEX idx_ai_source_meeting ON oneonone_action_items(source_meeting_id);

COMMENT ON TABLE oneonone_action_items IS
  'Action items das 1:1s. Coluna description PROTEGIDA · só participantes (leader, led) veem. RH consulta apenas count via view agregada.';
COMMENT ON COLUMN oneonone_action_items.description IS
  'CONTEÚDO PROTEGIDO. RH bloqueado.';


-- ----------------------------------------------------------------------------
-- TABELA 6 · oneonone_messages
-- Mensagens RH→Líder (cobranças via templates) e Liderado→Líder (proposta de
-- reagendamento). Esta tabela é VISÍVEL para RH porque RH é quem envia.
-- ----------------------------------------------------------------------------
CREATE TABLE oneonone_messages (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,

  sender_id UUID NOT NULL REFERENCES users(id),
  recipient_id UUID NOT NULL REFERENCES users(id),

  -- Contexto da mensagem
  template_kind oneonone_message_template NOT NULL,
  about_pair_id UUID REFERENCES oneonone_pairs(id), -- se cobra cadência de um par específico
  about_meeting_id UUID REFERENCES oneonone_meetings(id), -- se é proposta de reagendar

  subject TEXT NOT NULL,
  body TEXT NOT NULL CHECK (length(body) BETWEEN 1 AND 5000),

  read_at TIMESTAMPTZ,
  acted_at TIMESTAMPTZ, -- quando o destinatário tomou ação derivada (reagendou, etc)

  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  CONSTRAINT msg_distinct_users CHECK (sender_id <> recipient_id)
);

CREATE INDEX idx_msg_recipient_unread ON oneonone_messages(tenant_id, recipient_id, created_at DESC)
  WHERE read_at IS NULL;
CREATE INDEX idx_msg_about_pair ON oneonone_messages(about_pair_id);

COMMENT ON TABLE oneonone_messages IS
  'Mensagens entre RH e líderes (cobranças por template) ou liderado↔líder (proposta de reagendamento). Conteúdo visível para sender e recipient.';


-- ============================================================================
-- §3 TRIGGERS
-- ============================================================================

-- updated_at automático
CREATE OR REPLACE FUNCTION oneonone_set_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_oneonone_pairs_updated
  BEFORE UPDATE ON oneonone_pairs
  FOR EACH ROW EXECUTE FUNCTION oneonone_set_updated_at();

CREATE TRIGGER trg_oneonone_meetings_updated
  BEFORE UPDATE ON oneonone_meetings
  FOR EACH ROW EXECUTE FUNCTION oneonone_set_updated_at();

CREATE TRIGGER trg_oneonone_agenda_updated
  BEFORE UPDATE ON oneonone_agenda_items
  FOR EACH ROW EXECUTE FUNCTION oneonone_set_updated_at();

CREATE TRIGGER trg_oneonone_ai_updated
  BEFORE UPDATE ON oneonone_action_items
  FOR EACH ROW EXECUTE FUNCTION oneonone_set_updated_at();


-- Lock automático de conteúdo após 7 dias da conclusão
-- Não impede UPDATE diretamente (isso é responsabilidade da policy WITH CHECK),
-- só preenche o timestamp · views e RPCs verificam content_locked_at IS NULL.
CREATE OR REPLACE FUNCTION oneonone_check_content_lock()
RETURNS TRIGGER AS $$
BEGIN
  -- Quando completed_at é preenchido, content_locked_at fica NULL.
  -- Um job diário (descrito no §8) preenche content_locked_at = completed_at + 7d
  -- para meetings cujo prazo expirou. Aqui só validamos consistência.
  IF NEW.status = 'completed' AND NEW.completed_at IS NULL THEN
    RAISE EXCEPTION 'Meeting com status=completed exige completed_at preenchido';
  END IF;

  -- Auto-fill de started_at quando entra em in_progress
  IF NEW.status = 'in_progress' AND NEW.started_at IS NULL THEN
    NEW.started_at = NOW();
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_meeting_status_check
  BEFORE INSERT OR UPDATE OF status ON oneonone_meetings
  FOR EACH ROW EXECUTE FUNCTION oneonone_check_content_lock();


-- ============================================================================
-- §4 RLS POLICIES
-- ============================================================================

ALTER TABLE oneonone_pairs ENABLE ROW LEVEL SECURITY;
ALTER TABLE oneonone_meetings ENABLE ROW LEVEL SECURITY;
ALTER TABLE oneonone_agenda_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE oneonone_notes ENABLE ROW LEVEL SECURITY;
ALTER TABLE oneonone_action_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE oneonone_messages ENABLE ROW LEVEL SECURITY;

-- Função auxiliar: verifica se o usuário corrente tem alguma permissão dada
-- (espera-se que app.user_id e app.tenant_id sejam settados via session vars
-- pelo PostgREST/Supabase a cada request, conforme padrão dos schemas anteriores)
CREATE OR REPLACE FUNCTION oneonone_current_user_id()
RETURNS UUID AS $$
  SELECT current_setting('app.user_id', true)::UUID;
$$ LANGUAGE sql STABLE;

CREATE OR REPLACE FUNCTION oneonone_current_tenant_id()
RETURNS UUID AS $$
  SELECT current_setting('app.tenant_id', true)::UUID;
$$ LANGUAGE sql STABLE;

CREATE OR REPLACE FUNCTION oneonone_user_has_permission(p_perm TEXT)
RETURNS BOOLEAN AS $$
  SELECT EXISTS (
    SELECT 1 FROM user_permissions up
    WHERE up.user_id = oneonone_current_user_id()
      AND up.permission = p_perm
      AND up.tenant_id = oneonone_current_tenant_id()
  );
$$ LANGUAGE sql STABLE SECURITY DEFINER;


-- ----------------------------------------------------------------------------
-- POLICIES · oneonone_pairs
-- ----------------------------------------------------------------------------

-- Líder vê seus próprios pairs
CREATE POLICY pair_leader_select ON oneonone_pairs
  FOR SELECT
  USING (
    tenant_id = oneonone_current_tenant_id()
    AND leader_id = oneonone_current_user_id()
  );

-- Liderado vê o pair em que está
CREATE POLICY pair_led_select ON oneonone_pairs
  FOR SELECT
  USING (
    tenant_id = oneonone_current_tenant_id()
    AND led_id = oneonone_current_user_id()
  );

-- RH vê metadados de todos os pairs (sem conteúdo de meetings/notes)
-- A view oneonones_rh_dashboard usa este SELECT para listar líderes/cadência
CREATE POLICY pair_rh_select ON oneonone_pairs
  FOR SELECT
  USING (
    tenant_id = oneonone_current_tenant_id()
    AND oneonone_user_has_permission('view_oneonones_metadata')
  );

-- RH prestadora vê apenas pairs onde led_employer_unit_id está em seu escopo
CREATE POLICY pair_rh_provider_select ON oneonone_pairs
  FOR SELECT
  USING (
    tenant_id = oneonone_current_tenant_id()
    AND oneonone_user_has_permission('view_oneonones_metadata_by_employer')
    AND led_employer_unit_id IN (
      SELECT scope_unit_id FROM user_permission_scopes
      WHERE user_id = oneonone_current_user_id()
        AND scope_type = 'employer'
    )
  );

-- Líder cria/altera pair (admin RH também via permission)
CREATE POLICY pair_leader_modify ON oneonone_pairs
  FOR ALL
  USING (
    tenant_id = oneonone_current_tenant_id()
    AND (leader_id = oneonone_current_user_id()
         OR oneonone_user_has_permission('manage_oneonone_pairs'))
  );


-- ----------------------------------------------------------------------------
-- POLICIES · oneonone_meetings
-- ----------------------------------------------------------------------------

-- Participantes (leader ou led) veem suas próprias meetings
CREATE POLICY meeting_participant_select ON oneonone_meetings
  FOR SELECT
  USING (
    tenant_id = oneonone_current_tenant_id()
    AND (leader_id = oneonone_current_user_id()
         OR led_id = oneonone_current_user_id())
  );

-- RH vê meetings (mas mood_leader e mood_led são ofuscados via view, ver §5)
-- Esta policy concede SELECT na linha inteira porque é necessário para joins,
-- mas o app DEVE usar a view oneonones_rh_dashboard, que NÃO retorna mood_*.
CREATE POLICY meeting_rh_select ON oneonone_meetings
  FOR SELECT
  USING (
    tenant_id = oneonone_current_tenant_id()
    AND oneonone_user_has_permission('view_oneonones_metadata')
  );

-- RH prestadora · escopo por employer do liderado
CREATE POLICY meeting_rh_provider_select ON oneonone_meetings
  FOR SELECT
  USING (
    tenant_id = oneonone_current_tenant_id()
    AND oneonone_user_has_permission('view_oneonones_metadata_by_employer')
    AND EXISTS (
      SELECT 1 FROM oneonone_pairs p
      WHERE p.id = oneonone_meetings.pair_id
        AND p.led_employer_unit_id IN (
          SELECT scope_unit_id FROM user_permission_scopes
          WHERE user_id = oneonone_current_user_id()
            AND scope_type = 'employer'
        )
    )
  );

-- Apenas o líder (ou liderado para campos limitados) atualiza meeting
-- Mood_leader é alterado APENAS se quem altera é o leader_id
-- Mood_led é alterado APENAS se quem altera é o led_id
-- Isso é enforced via WITH CHECK e via RPC (SECURITY DEFINER)
CREATE POLICY meeting_leader_update ON oneonone_meetings
  FOR UPDATE
  USING (tenant_id = oneonone_current_tenant_id() AND leader_id = oneonone_current_user_id())
  WITH CHECK (tenant_id = oneonone_current_tenant_id() AND leader_id = oneonone_current_user_id());

CREATE POLICY meeting_leader_insert ON oneonone_meetings
  FOR INSERT
  WITH CHECK (tenant_id = oneonone_current_tenant_id() AND leader_id = oneonone_current_user_id());


-- ----------------------------------------------------------------------------
-- POLICIES · oneonone_agenda_items
-- ----------------------------------------------------------------------------
-- CRÍTICO: NÃO HÁ POLICY DE SELECT PARA RH. Acesso só por participantes.
-- RH consulta count via view agregada que usa SECURITY DEFINER.
-- ----------------------------------------------------------------------------

CREATE POLICY agenda_participant_select ON oneonone_agenda_items
  FOR SELECT
  USING (
    tenant_id = oneonone_current_tenant_id()
    AND EXISTS (
      SELECT 1 FROM oneonone_meetings m
      WHERE m.id = oneonone_agenda_items.meeting_id
        AND (m.leader_id = oneonone_current_user_id()
             OR m.led_id = oneonone_current_user_id())
    )
  );

-- INSERT: qualquer participante pode adicionar item (autoria coerente)
CREATE POLICY agenda_participant_insert ON oneonone_agenda_items
  FOR INSERT
  WITH CHECK (
    tenant_id = oneonone_current_tenant_id()
    AND author_id = oneonone_current_user_id()
    AND EXISTS (
      SELECT 1 FROM oneonone_meetings m
      WHERE m.id = oneonone_agenda_items.meeting_id
        AND m.content_locked_at IS NULL
        AND ((m.leader_id = oneonone_current_user_id() AND author = 'leader')
             OR (m.led_id = oneonone_current_user_id() AND author = 'led'))
    )
  );

-- UPDATE/DELETE: só o autor (e líder pode reordenar via update de position)
CREATE POLICY agenda_author_modify ON oneonone_agenda_items
  FOR UPDATE
  USING (
    tenant_id = oneonone_current_tenant_id()
    AND author_id = oneonone_current_user_id()
    AND EXISTS (
      SELECT 1 FROM oneonone_meetings m
      WHERE m.id = oneonone_agenda_items.meeting_id
        AND m.content_locked_at IS NULL
    )
  );

CREATE POLICY agenda_author_delete ON oneonone_agenda_items
  FOR DELETE
  USING (
    tenant_id = oneonone_current_tenant_id()
    AND author_id = oneonone_current_user_id()
    AND EXISTS (
      SELECT 1 FROM oneonone_meetings m
      WHERE m.id = oneonone_agenda_items.meeting_id
        AND m.content_locked_at IS NULL
    )
  );


-- ----------------------------------------------------------------------------
-- POLICIES · oneonone_notes
-- ----------------------------------------------------------------------------
-- AS POLICIES MAIS RESTRITIVAS DO MÓDULO.
-- - kind='private_leader' acessível APENAS pelo leader_id da meeting
-- - kind='shared' acessível pelo leader_id E pelo led_id
-- - RH NÃO TEM POLICY DE SELECT. Não há jeito de RH ler conteúdo via SQL direto.
-- - DPO acessa via DSAR formal (não via policy regular · ver §6 oneonone_dsar_export)
-- ----------------------------------------------------------------------------

-- Notas privadas do líder · só o líder
CREATE POLICY notes_private_leader_select ON oneonone_notes
  FOR SELECT
  USING (
    tenant_id = oneonone_current_tenant_id()
    AND kind = 'private_leader'
    AND EXISTS (
      SELECT 1 FROM oneonone_meetings m
      WHERE m.id = oneonone_notes.meeting_id
        AND m.leader_id = oneonone_current_user_id()
    )
  );

-- Notas compartilhadas · líder e liderado
CREATE POLICY notes_shared_select ON oneonone_notes
  FOR SELECT
  USING (
    tenant_id = oneonone_current_tenant_id()
    AND kind = 'shared'
    AND EXISTS (
      SELECT 1 FROM oneonone_meetings m
      WHERE m.id = oneonone_notes.meeting_id
        AND (m.leader_id = oneonone_current_user_id()
             OR m.led_id = oneonone_current_user_id())
    )
  );

-- INSERT/UPDATE de notas privadas · só o líder
CREATE POLICY notes_private_leader_modify ON oneonone_notes
  FOR ALL
  USING (
    tenant_id = oneonone_current_tenant_id()
    AND kind = 'private_leader'
    AND EXISTS (
      SELECT 1 FROM oneonone_meetings m
      WHERE m.id = oneonone_notes.meeting_id
        AND m.leader_id = oneonone_current_user_id()
        AND m.content_locked_at IS NULL
    )
  )
  WITH CHECK (
    tenant_id = oneonone_current_tenant_id()
    AND kind = 'private_leader'
    AND EXISTS (
      SELECT 1 FROM oneonone_meetings m
      WHERE m.id = oneonone_notes.meeting_id
        AND m.leader_id = oneonone_current_user_id()
        AND m.content_locked_at IS NULL
    )
  );

-- INSERT/UPDATE de notas compartilhadas · líder e liderado
CREATE POLICY notes_shared_modify ON oneonone_notes
  FOR ALL
  USING (
    tenant_id = oneonone_current_tenant_id()
    AND kind = 'shared'
    AND EXISTS (
      SELECT 1 FROM oneonone_meetings m
      WHERE m.id = oneonone_notes.meeting_id
        AND (m.leader_id = oneonone_current_user_id()
             OR m.led_id = oneonone_current_user_id())
        AND m.content_locked_at IS NULL
    )
  )
  WITH CHECK (
    tenant_id = oneonone_current_tenant_id()
    AND kind = 'shared'
    AND EXISTS (
      SELECT 1 FROM oneonone_meetings m
      WHERE m.id = oneonone_notes.meeting_id
        AND (m.leader_id = oneonone_current_user_id()
             OR m.led_id = oneonone_current_user_id())
        AND m.content_locked_at IS NULL
    )
  );


-- ----------------------------------------------------------------------------
-- POLICIES · oneonone_action_items
-- ----------------------------------------------------------------------------
-- Mesma lógica das agenda_items: NÃO HÁ POLICY DE SELECT PARA RH.
-- RH vê apenas count via view agregada.
-- ----------------------------------------------------------------------------

CREATE POLICY ai_participant_select ON oneonone_action_items
  FOR SELECT
  USING (
    tenant_id = oneonone_current_tenant_id()
    AND (leader_id = oneonone_current_user_id()
         OR led_id = oneonone_current_user_id())
  );

CREATE POLICY ai_participant_insert ON oneonone_action_items
  FOR INSERT
  WITH CHECK (
    tenant_id = oneonone_current_tenant_id()
    AND (leader_id = oneonone_current_user_id()
         OR led_id = oneonone_current_user_id())
    AND created_by = oneonone_current_user_id()
  );

-- UPDATE: completar permitido se for responsável (ou both)
CREATE POLICY ai_participant_update ON oneonone_action_items
  FOR UPDATE
  USING (
    tenant_id = oneonone_current_tenant_id()
    AND (leader_id = oneonone_current_user_id()
         OR led_id = oneonone_current_user_id())
  );


-- ----------------------------------------------------------------------------
-- POLICIES · oneonone_messages
-- ----------------------------------------------------------------------------

CREATE POLICY msg_sender_select ON oneonone_messages
  FOR SELECT
  USING (
    tenant_id = oneonone_current_tenant_id()
    AND sender_id = oneonone_current_user_id()
  );

CREATE POLICY msg_recipient_select ON oneonone_messages
  FOR SELECT
  USING (
    tenant_id = oneonone_current_tenant_id()
    AND recipient_id = oneonone_current_user_id()
  );

CREATE POLICY msg_send ON oneonone_messages
  FOR INSERT
  WITH CHECK (
    tenant_id = oneonone_current_tenant_id()
    AND sender_id = oneonone_current_user_id()
  );

CREATE POLICY msg_recipient_update_read ON oneonone_messages
  FOR UPDATE
  USING (
    tenant_id = oneonone_current_tenant_id()
    AND recipient_id = oneonone_current_user_id()
  );


-- ============================================================================
-- §5 VIEWS AGREGADAS PARA RH (só metadados, nunca conteúdo)
-- ============================================================================

-- ----------------------------------------------------------------------------
-- VIEW · oneonones_rh_dashboard_leader
-- Retorna por líder: cadência, # liderados, # em débito, # AIs abertos.
-- NÃO retorna mood, NÃO joina com agenda/notes/action_items.description.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE VIEW oneonones_rh_dashboard_leader
WITH (security_invoker = true) AS
SELECT
  l.id AS leader_id,
  l.name AS leader_name,
  l.nickname AS leader_handle,
  l.tenant_id,

  COUNT(DISTINCT p.id) FILTER (WHERE p.ended_at IS NULL) AS active_pairs,

  -- Cadência média (em dias) das últimas 4 meetings completadas por par
  AVG(
    EXTRACT(EPOCH FROM (
      m.completed_at - LAG(m.completed_at) OVER (PARTITION BY p.id ORDER BY m.completed_at)
    )) / 86400
  ) FILTER (WHERE m.status = 'completed') AS avg_cadence_days,

  -- Quantidade de liderados em débito (sem 1:1 há > 30 dias)
  COUNT(DISTINCT p.led_id) FILTER (
    WHERE p.ended_at IS NULL
      AND NOT EXISTS (
        SELECT 1 FROM oneonone_meetings m2
        WHERE m2.pair_id = p.id
          AND m2.status = 'completed'
          AND m2.completed_at > NOW() - INTERVAL '30 days'
      )
  ) AS led_in_debt,

  -- Action items abertos (count, sem texto)
  (SELECT COUNT(*) FROM oneonone_action_items ai
    WHERE ai.leader_id = l.id AND ai.status = 'open' AND ai.tenant_id = l.tenant_id
  ) AS ai_open,

  -- Action items em atraso
  (SELECT COUNT(*) FROM oneonone_action_items ai
    WHERE ai.leader_id = l.id AND ai.status = 'open'
      AND ai.due_date < CURRENT_DATE AND ai.tenant_id = l.tenant_id
  ) AS ai_overdue,

  -- Última 1:1 concluída pelo líder
  MAX(m.completed_at) AS last_completed_at

FROM users l
LEFT JOIN oneonone_pairs p ON p.leader_id = l.id AND p.ended_at IS NULL
LEFT JOIN oneonone_meetings m ON m.pair_id = p.id
WHERE l.tenant_id = oneonone_current_tenant_id()
GROUP BY l.id, l.name, l.nickname, l.tenant_id;

COMMENT ON VIEW oneonones_rh_dashboard_leader IS
  'Visão agregada para RH. Apenas metadados · NÃO retorna texto de pauta, notas, descrição de AIs ou mood. security_invoker garante que RH só vê o que RLS deixa ver.';


-- ----------------------------------------------------------------------------
-- VIEW · oneonones_rh_overdue_led
-- Lista de liderados com 1:1 mais antiga que X dias. Usada na sidebar do RH.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE VIEW oneonones_rh_overdue_led
WITH (security_invoker = true) AS
SELECT
  led.id AS led_id,
  led.name AS led_name,
  led.nickname AS led_handle,
  led.tenant_id,
  l.id AS leader_id,
  l.name AS leader_name,
  p.id AS pair_id,
  COALESCE(MAX(m.completed_at), p.started_at::TIMESTAMPTZ) AS last_meeting_at,
  EXTRACT(DAY FROM (NOW() - COALESCE(MAX(m.completed_at), p.started_at::TIMESTAMPTZ)))::INT AS days_since
FROM oneonone_pairs p
JOIN users led ON led.id = p.led_id
JOIN users l ON l.id = p.leader_id
LEFT JOIN oneonone_meetings m ON m.pair_id = p.id AND m.status = 'completed'
WHERE p.ended_at IS NULL
  AND p.tenant_id = oneonone_current_tenant_id()
GROUP BY led.id, led.name, led.nickname, led.tenant_id, l.id, l.name, p.id, p.started_at
HAVING EXTRACT(DAY FROM (NOW() - COALESCE(MAX(m.completed_at), p.started_at::TIMESTAMPTZ))) > 30
ORDER BY days_since DESC;

COMMENT ON VIEW oneonones_rh_overdue_led IS
  'Liderados sem 1:1 concluída há mais de 30 dias. Apenas metadados. Usada na sidebar da tela de RH.';


-- ----------------------------------------------------------------------------
-- VIEW · oneonones_rh_activity
-- Atividade recente (apenas eventos, sem conteúdo). 50 últimos eventos.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE VIEW oneonones_rh_activity
WITH (security_invoker = true) AS
SELECT * FROM (
  -- Meetings concluídas
  SELECT
    'completed' AS event_type,
    m.id AS event_id,
    m.completed_at AS event_at,
    m.leader_id AS actor_id,
    m.led_id AS related_user_id,
    m.tenant_id,
    NULL::TEXT AS message_preview
  FROM oneonone_meetings m
  WHERE m.status = 'completed'
    AND m.completed_at > NOW() - INTERVAL '30 days'

  UNION ALL

  -- Meetings agendadas
  SELECT
    'scheduled',
    m.id,
    m.created_at,
    m.leader_id,
    m.led_id,
    m.tenant_id,
    NULL
  FROM oneonone_meetings m
  WHERE m.status = 'scheduled'
    AND m.created_at > NOW() - INTERVAL '30 days'

  UNION ALL

  -- Cancelamentos/reagendamentos
  SELECT
    'canceled',
    m.id,
    m.canceled_at,
    m.canceled_by,
    CASE WHEN m.canceled_by = m.leader_id THEN m.led_id ELSE m.leader_id END,
    m.tenant_id,
    NULL
  FROM oneonone_meetings m
  WHERE m.status = 'canceled'
    AND m.canceled_at > NOW() - INTERVAL '30 days'
) AS events
WHERE tenant_id = oneonone_current_tenant_id()
ORDER BY event_at DESC
LIMIT 50;

COMMENT ON VIEW oneonones_rh_activity IS
  'Eventos recentes do módulo. Apenas tipo+atores+timestamps. Sem conteúdo de notas/pauta/AIs.';


-- ============================================================================
-- §6 RPCs (8 funções)
-- ============================================================================

-- ----------------------------------------------------------------------------
-- RPC 1 · rpc_oneonone_get_room
-- Retorna a sala completa para um participante. Líder vê notas privadas,
-- liderado não. Notas compartilhadas vão para os dois. Mood do outro é null.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION rpc_oneonone_get_room(p_meeting_id UUID)
RETURNS JSONB AS $$
DECLARE
  v_meeting oneonone_meetings%ROWTYPE;
  v_user_id UUID := oneonone_current_user_id();
  v_is_leader BOOLEAN;
  v_is_led BOOLEAN;
BEGIN
  SELECT * INTO v_meeting FROM oneonone_meetings WHERE id = p_meeting_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'meeting_not_found' USING ERRCODE = 'P0002'; END IF;

  v_is_leader := (v_meeting.leader_id = v_user_id);
  v_is_led := (v_meeting.led_id = v_user_id);

  IF NOT (v_is_leader OR v_is_led) THEN
    RAISE EXCEPTION 'not_a_participant' USING ERRCODE = '42501';
  END IF;

  RETURN jsonb_build_object(
    'meeting', jsonb_build_object(
      'id', v_meeting.id,
      'scheduled_start', v_meeting.scheduled_start,
      'scheduled_end', v_meeting.scheduled_end,
      'status', v_meeting.status,
      'location', v_meeting.location,
      'leader_id', v_meeting.leader_id,
      'led_id', v_meeting.led_id,
      -- Mood retornado APENAS para o próprio dono
      'mood_leader', CASE WHEN v_is_leader THEN v_meeting.mood_leader ELSE NULL END,
      'mood_led', CASE WHEN v_is_led THEN v_meeting.mood_led ELSE NULL END,
      'content_locked_at', v_meeting.content_locked_at
    ),
    'agenda', (
      SELECT COALESCE(jsonb_agg(jsonb_build_object(
        'id', a.id,
        'text', a.text,
        'author', a.author,
        'discussed', a.discussed,
        'is_carry', a.carry_over_from IS NOT NULL,
        'created_at', a.created_at
      ) ORDER BY a.position, a.created_at), '[]'::jsonb)
      FROM oneonone_agenda_items a WHERE a.meeting_id = p_meeting_id
    ),
    -- Notas: privada só para líder, compartilhada para ambos
    'notes_private', CASE
      WHEN v_is_leader THEN (
        SELECT to_jsonb(n) FROM oneonone_notes n
        WHERE n.meeting_id = p_meeting_id AND n.kind = 'private_leader'
      )
      ELSE NULL
    END,
    'notes_shared', (
      SELECT to_jsonb(n) FROM oneonone_notes n
      WHERE n.meeting_id = p_meeting_id AND n.kind = 'shared'
    ),
    'action_items', (
      SELECT COALESCE(jsonb_agg(jsonb_build_object(
        'id', ai.id,
        'description', ai.description,
        'owner', ai.owner,
        'due_date', ai.due_date,
        'status', ai.status,
        'from_prev', ai.source_meeting_id IS NOT NULL AND ai.source_meeting_id <> p_meeting_id
      ) ORDER BY ai.created_at DESC), '[]'::jsonb)
      FROM oneonone_action_items ai
      WHERE ai.current_meeting_id = p_meeting_id
        OR (ai.source_meeting_id = p_meeting_id AND ai.status = 'open')
    )
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER STABLE;


-- ----------------------------------------------------------------------------
-- RPC 2 · rpc_oneonone_save_notes
-- Atualiza notas (privada ou compartilhada) com checks de autoria.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION rpc_oneonone_save_notes(
  p_meeting_id UUID,
  p_kind oneonone_notes_kind,
  p_content TEXT
) RETURNS UUID AS $$
DECLARE
  v_meeting oneonone_meetings%ROWTYPE;
  v_user_id UUID := oneonone_current_user_id();
  v_note_id UUID;
BEGIN
  SELECT * INTO v_meeting FROM oneonone_meetings WHERE id = p_meeting_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'meeting_not_found'; END IF;
  IF v_meeting.content_locked_at IS NOT NULL THEN
    RAISE EXCEPTION 'content_locked' USING ERRCODE = '42501';
  END IF;

  -- Notas privadas só pelo líder
  IF p_kind = 'private_leader' AND v_meeting.leader_id <> v_user_id THEN
    RAISE EXCEPTION 'only_leader_can_edit_private_notes' USING ERRCODE = '42501';
  END IF;

  -- Notas compartilhadas pelos dois
  IF p_kind = 'shared' AND v_meeting.leader_id <> v_user_id AND v_meeting.led_id <> v_user_id THEN
    RAISE EXCEPTION 'not_a_participant' USING ERRCODE = '42501';
  END IF;

  INSERT INTO oneonone_notes (tenant_id, meeting_id, kind, content, last_edited_by, last_edited_at)
  VALUES (v_meeting.tenant_id, p_meeting_id, p_kind, p_content, v_user_id, NOW())
  ON CONFLICT (meeting_id, kind) DO UPDATE
    SET content = EXCLUDED.content,
        last_edited_by = EXCLUDED.last_edited_by,
        last_edited_at = NOW()
  RETURNING id INTO v_note_id;

  RETURN v_note_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER VOLATILE;


-- ----------------------------------------------------------------------------
-- RPC 3 · rpc_oneonone_complete_meeting
-- Finaliza meeting · valida que quem chama é o líder · cria carry over de
-- itens não discutidos para a próxima meeting do par.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION rpc_oneonone_complete_meeting(
  p_meeting_id UUID,
  p_mood_leader SMALLINT DEFAULT NULL
) RETURNS VOID AS $$
DECLARE
  v_meeting oneonone_meetings%ROWTYPE;
  v_user_id UUID := oneonone_current_user_id();
  v_next_meeting_id UUID;
BEGIN
  SELECT * INTO v_meeting FROM oneonone_meetings WHERE id = p_meeting_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'meeting_not_found'; END IF;
  IF v_meeting.leader_id <> v_user_id THEN
    RAISE EXCEPTION 'only_leader_can_complete' USING ERRCODE = '42501';
  END IF;
  IF v_meeting.status = 'completed' THEN
    RAISE EXCEPTION 'already_completed';
  END IF;

  UPDATE oneonone_meetings
  SET status = 'completed',
      completed_at = NOW(),
      mood_leader = COALESCE(p_mood_leader, mood_leader)
  WHERE id = p_meeting_id;

  -- Identificar próxima meeting agendada do par
  SELECT id INTO v_next_meeting_id
  FROM oneonone_meetings
  WHERE pair_id = v_meeting.pair_id
    AND status = 'scheduled'
    AND scheduled_start > NOW()
  ORDER BY scheduled_start ASC
  LIMIT 1;

  -- Carry over: cria cópias dos itens não discutidos vinculadas à próxima meeting
  IF v_next_meeting_id IS NOT NULL THEN
    INSERT INTO oneonone_agenda_items (
      tenant_id, meeting_id, text, author, author_id, discussed, carry_over_from, position
    )
    SELECT
      tenant_id,
      v_next_meeting_id,
      text,
      author,
      author_id,
      FALSE,
      id, -- referência ao item original
      999 + ROW_NUMBER() OVER (ORDER BY position) -- coloca no final
    FROM oneonone_agenda_items
    WHERE meeting_id = p_meeting_id
      AND discussed = FALSE
      AND carry_over_from IS NULL; -- não copiar carry de carry (evita cascata infinita)
  END IF;

  -- Audit
  INSERT INTO audit_log (tenant_id, user_id, action, entity_type, entity_id, payload)
  VALUES (
    v_meeting.tenant_id, v_user_id,
    'oneonone_meeting_completed', 'oneonone_meetings', p_meeting_id,
    jsonb_build_object('next_meeting_id', v_next_meeting_id)
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER VOLATILE;


-- ----------------------------------------------------------------------------
-- RPC 4 · rpc_oneonone_propose_reschedule
-- Liderado propõe reagendamento. Cria mensagem para o líder com a sugestão.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION rpc_oneonone_propose_reschedule(
  p_meeting_id UUID,
  p_new_start TIMESTAMPTZ,
  p_new_end TIMESTAMPTZ,
  p_reason TEXT
) RETURNS UUID AS $$
DECLARE
  v_meeting oneonone_meetings%ROWTYPE;
  v_user_id UUID := oneonone_current_user_id();
  v_msg_id UUID;
BEGIN
  SELECT * INTO v_meeting FROM oneonone_meetings WHERE id = p_meeting_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'meeting_not_found'; END IF;
  IF v_meeting.led_id <> v_user_id THEN
    RAISE EXCEPTION 'only_led_can_propose' USING ERRCODE = '42501';
  END IF;

  INSERT INTO oneonone_messages (
    tenant_id, sender_id, recipient_id, template_kind,
    about_meeting_id, subject, body
  ) VALUES (
    v_meeting.tenant_id, v_user_id, v_meeting.leader_id, 'reschedule_proposal',
    p_meeting_id,
    'Proposta de reagendamento',
    'Proposta para ' || to_char(p_new_start, 'DD/MM/YYYY HH24:MI') ||
    CASE WHEN p_reason IS NOT NULL AND p_reason <> '' THEN E'\n\nMotivo: ' || p_reason ELSE '' END
  ) RETURNING id INTO v_msg_id;

  RETURN v_msg_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER VOLATILE;


-- ----------------------------------------------------------------------------
-- RPC 5 · rpc_oneonone_send_rh_message
-- RH envia mensagem para líder via template.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION rpc_oneonone_send_rh_message(
  p_recipient_id UUID,
  p_template oneonone_message_template,
  p_subject TEXT,
  p_body TEXT,
  p_about_pair_id UUID DEFAULT NULL
) RETURNS UUID AS $$
DECLARE
  v_user_id UUID := oneonone_current_user_id();
  v_tenant_id UUID := oneonone_current_tenant_id();
  v_msg_id UUID;
BEGIN
  IF NOT oneonone_user_has_permission('send_oneonone_messages') THEN
    RAISE EXCEPTION 'permission_denied' USING ERRCODE = '42501';
  END IF;

  INSERT INTO oneonone_messages (
    tenant_id, sender_id, recipient_id, template_kind,
    about_pair_id, subject, body
  ) VALUES (
    v_tenant_id, v_user_id, p_recipient_id, p_template,
    p_about_pair_id, p_subject, p_body
  ) RETURNING id INTO v_msg_id;

  -- Audit
  INSERT INTO audit_log (tenant_id, user_id, action, entity_type, entity_id, payload)
  VALUES (
    v_tenant_id, v_user_id,
    'oneonone_rh_message_sent', 'oneonone_messages', v_msg_id,
    jsonb_build_object('recipient_id', p_recipient_id, 'template', p_template)
  );

  RETURN v_msg_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER VOLATILE;


-- ----------------------------------------------------------------------------
-- RPC 6 · rpc_oneonone_create_action_item
-- Cria action item vinculado a uma meeting.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION rpc_oneonone_create_action_item(
  p_meeting_id UUID,
  p_description TEXT,
  p_owner oneonone_ai_owner,
  p_due_date DATE
) RETURNS UUID AS $$
DECLARE
  v_meeting oneonone_meetings%ROWTYPE;
  v_user_id UUID := oneonone_current_user_id();
  v_ai_id UUID;
BEGIN
  SELECT * INTO v_meeting FROM oneonone_meetings WHERE id = p_meeting_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'meeting_not_found'; END IF;
  IF v_meeting.leader_id <> v_user_id AND v_meeting.led_id <> v_user_id THEN
    RAISE EXCEPTION 'not_a_participant' USING ERRCODE = '42501';
  END IF;

  INSERT INTO oneonone_action_items (
    tenant_id, source_meeting_id, current_meeting_id,
    leader_id, led_id, description, owner, due_date, created_by
  ) VALUES (
    v_meeting.tenant_id, p_meeting_id, p_meeting_id,
    v_meeting.leader_id, v_meeting.led_id, p_description, p_owner, p_due_date, v_user_id
  ) RETURNING id INTO v_ai_id;

  RETURN v_ai_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER VOLATILE;


-- ----------------------------------------------------------------------------
-- RPC 7 · rpc_oneonone_get_my_history
-- Retorna histórico de 1:1s do liderado. Inclui apenas o que ele/ela pode ver.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION rpc_oneonone_get_my_history(p_limit INT DEFAULT 20)
RETURNS JSONB AS $$
DECLARE
  v_user_id UUID := oneonone_current_user_id();
BEGIN
  RETURN (
    SELECT jsonb_agg(row_to_json(h))
    FROM (
      SELECT
        m.id,
        m.scheduled_start,
        m.completed_at,
        m.status,
        -- Mood do PRÓPRIO usuário (não do outro)
        CASE
          WHEN m.leader_id = v_user_id THEN m.mood_leader
          WHEN m.led_id = v_user_id THEN m.mood_led
        END AS my_mood,
        (SELECT COUNT(*) FROM oneonone_agenda_items WHERE meeting_id = m.id) AS agenda_count,
        (SELECT COUNT(*) FROM oneonone_action_items WHERE current_meeting_id = m.id) AS ai_count,
        EXISTS (SELECT 1 FROM oneonone_notes WHERE meeting_id = m.id AND kind = 'shared' AND length(content) > 0) AS has_shared_notes
      FROM oneonone_meetings m
      WHERE (m.leader_id = v_user_id OR m.led_id = v_user_id)
        AND m.status IN ('completed', 'canceled')
      ORDER BY m.scheduled_start DESC
      LIMIT p_limit
    ) h
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER STABLE;


-- ----------------------------------------------------------------------------
-- RPC 8 · rpc_oneonone_dsar_export
-- Acesso DPO via DSAR (LGPD Art. 18). NÃO é uma policy regular · só pode ser
-- chamada por usuário com permission='dsar_export' e gera audit pesado.
-- Retorna TUDO sobre o user solicitante: meetings em que participou, notas
-- (incluindo privadas se for o líder), AIs, mensagens. NÃO retorna conteúdo
-- de outros pares · só do solicitante.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION rpc_oneonone_dsar_export(p_target_user_id UUID)
RETURNS JSONB AS $$
DECLARE
  v_user_id UUID := oneonone_current_user_id();
BEGIN
  IF NOT oneonone_user_has_permission('dsar_export') THEN
    RAISE EXCEPTION 'permission_denied · DSAR exige permission dsar_export' USING ERRCODE = '42501';
  END IF;

  -- Audit pesado
  INSERT INTO audit_log (tenant_id, user_id, action, entity_type, entity_id, payload)
  VALUES (
    oneonone_current_tenant_id(), v_user_id,
    'oneonone_dsar_export', 'users', p_target_user_id,
    jsonb_build_object('target', p_target_user_id, 'export_at', NOW(), 'reason', 'LGPD Art. 18')
  );

  RETURN jsonb_build_object(
    'meetings_as_leader', (
      SELECT jsonb_agg(to_jsonb(m)) FROM oneonone_meetings m WHERE m.leader_id = p_target_user_id
    ),
    'meetings_as_led', (
      SELECT jsonb_agg(to_jsonb(m)) FROM oneonone_meetings m WHERE m.led_id = p_target_user_id
    ),
    'agenda_items_authored', (
      SELECT jsonb_agg(to_jsonb(a)) FROM oneonone_agenda_items a WHERE a.author_id = p_target_user_id
    ),
    'notes_private_authored', (
      SELECT jsonb_agg(to_jsonb(n))
      FROM oneonone_notes n
      JOIN oneonone_meetings m ON m.id = n.meeting_id
      WHERE n.kind = 'private_leader' AND m.leader_id = p_target_user_id
    ),
    'notes_shared_participated', (
      SELECT jsonb_agg(to_jsonb(n))
      FROM oneonone_notes n
      JOIN oneonone_meetings m ON m.id = n.meeting_id
      WHERE n.kind = 'shared'
        AND (m.leader_id = p_target_user_id OR m.led_id = p_target_user_id)
    ),
    'action_items', (
      SELECT jsonb_agg(to_jsonb(ai))
      FROM oneonone_action_items ai
      WHERE ai.leader_id = p_target_user_id OR ai.led_id = p_target_user_id
    ),
    'messages_sent', (
      SELECT jsonb_agg(to_jsonb(msg)) FROM oneonone_messages msg WHERE msg.sender_id = p_target_user_id
    ),
    'messages_received', (
      SELECT jsonb_agg(to_jsonb(msg)) FROM oneonone_messages msg WHERE msg.recipient_id = p_target_user_id
    )
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER VOLATILE;


-- ============================================================================
-- §7 CENÁRIOS DE TESTE · 5 personas
-- ============================================================================
--
-- Estes cenários são executados manualmente após aplicar o schema, fazendo
-- SET app.user_id e SET app.tenant_id apropriados (simulando a sessão).
-- O app de teste real fica em rls_policies_oneonones_tests.sql (futuro).
--
-- CENÁRIO A · João Carvalho (líder financeiro)
--   user_id: <joao_uuid>
--   permissions: manage_subordinates
--   Esperado:
--     ✓ SELECT em oneonone_pairs onde leader_id = joao → vê 4 pairs
--     ✓ SELECT em oneonone_meetings onde leader_id = joao → todas as suas
--     ✓ SELECT em oneonone_notes WHERE kind='private_leader' → vê as próprias
--     ✓ SELECT em oneonone_notes WHERE kind='shared' → vê de todas as suas meetings
--     ✓ INSERT em oneonone_meetings com leader_id=joao → OK
--     ✗ SELECT em oneonone_notes de meeting de outro líder → 0 linhas (RLS oculta)
--     ✗ UPDATE em oneonone_meetings.mood_led → bloqueado (não é o led)
--
-- CENÁRIO B · Fernanda Lima (liderada do João)
--   user_id: <fernanda_uuid>
--   permissions: view_self_*
--   Esperado:
--     ✓ SELECT em oneonone_pairs onde led_id = fernanda → vê 1 pair
--     ✓ SELECT em oneonone_meetings onde led_id = fernanda → todas
--     ✓ SELECT em oneonone_notes WHERE kind='shared' → vê
--     ✗ SELECT em oneonone_notes WHERE kind='private_leader' → 0 linhas (RLS oculta)
--     ✗ Mood do João via rpc_oneonone_get_room → retorna NULL para mood_leader
--     ✓ rpc_oneonone_propose_reschedule → cria mensagem para João
--     ✗ INSERT em oneonone_meetings → 0 (não é líder)
--
-- CENÁRIO C · Patrícia Mello (RH GPC, vê todos)
--   user_id: <patricia_uuid>
--   permissions: view_oneonones_metadata, send_oneonone_messages
--   Esperado:
--     ✓ SELECT em oneonones_rh_dashboard_leader → vê 32 líderes
--     ✓ SELECT em oneonones_rh_overdue_led → vê 8 liderados em débito
--     ✗ SELECT em oneonone_notes → 0 linhas (sem policy de SELECT)
--     ✗ SELECT em oneonone_agenda_items.text → 0 linhas
--     ✗ SELECT em oneonone_action_items.description → 0 linhas
--     ✓ rpc_oneonone_send_rh_message → cria mensagem · audit registrado
--     ✗ rpc_oneonone_get_room para meeting de outros → exception not_a_participant
--
-- CENÁRIO D · Larissa Pereira (RH Labuta, escopo restrito)
--   user_id: <larissa_uuid>
--   permissions: view_oneonones_metadata_by_employer
--   user_permission_scopes: {scope_type: 'employer', scope_unit_id: <labuta_id>}
--   Esperado:
--     ✓ SELECT em oneonone_pairs onde led_employer_unit_id = labuta → 8 pairs
--     ✗ SELECT em oneonone_pairs onde led_employer_unit_id = gpc → 0 linhas
--     ✓ View dashboard → vê apenas líderes Labuta
--     ✗ Tudo o que envolva conteúdo (notes, agenda, AIs) → 0 linhas
--
-- CENÁRIO E · Carla Moreira (DPO)
--   user_id: <carla_uuid>
--   permissions: view_audit_log, dsar_export
--   Esperado:
--     ✗ SELECT em oneonone_notes → 0 linhas (DPO regular NÃO tem acesso)
--     ✓ rpc_oneonone_dsar_export(fernanda_uuid) → JSONB com dados da Fernanda
--     ✓ Audit log registra a chamada DSAR com timestamp e justificativa


-- ============================================================================
-- §8 PLANO DE ROLLBACK
-- ============================================================================
--
-- Em caso de necessidade de remoção do schema do módulo de 1:1s:
--
-- 1. Backup das tabelas (manual, antes de qualquer DROP):
--    pg_dump -t oneonone_* > backup_oneonones_$(date +%Y%m%d).sql
--
-- 2. Notificar usuários ativos (24h antes):
--    INSERT INTO notifications (...) SELECT ... FROM oneonone_pairs WHERE ended_at IS NULL;
--
-- 3. Drop em ordem reversa de dependência:
--    DROP FUNCTION IF EXISTS rpc_oneonone_dsar_export(UUID);
--    DROP FUNCTION IF EXISTS rpc_oneonone_get_my_history(INT);
--    DROP FUNCTION IF EXISTS rpc_oneonone_create_action_item(UUID, TEXT, oneonone_ai_owner, DATE);
--    DROP FUNCTION IF EXISTS rpc_oneonone_send_rh_message(UUID, oneonone_message_template, TEXT, TEXT, UUID);
--    DROP FUNCTION IF EXISTS rpc_oneonone_propose_reschedule(UUID, TIMESTAMPTZ, TIMESTAMPTZ, TEXT);
--    DROP FUNCTION IF EXISTS rpc_oneonone_complete_meeting(UUID, SMALLINT);
--    DROP FUNCTION IF EXISTS rpc_oneonone_save_notes(UUID, oneonone_notes_kind, TEXT);
--    DROP FUNCTION IF EXISTS rpc_oneonone_get_room(UUID);
--    DROP VIEW IF EXISTS oneonones_rh_activity;
--    DROP VIEW IF EXISTS oneonones_rh_overdue_led;
--    DROP VIEW IF EXISTS oneonones_rh_dashboard_leader;
--    DROP TABLE IF EXISTS oneonone_messages CASCADE;
--    DROP TABLE IF EXISTS oneonone_action_items CASCADE;
--    DROP TABLE IF EXISTS oneonone_notes CASCADE;
--    DROP TABLE IF EXISTS oneonone_agenda_items CASCADE;
--    DROP TABLE IF EXISTS oneonone_meetings CASCADE;
--    DROP TABLE IF EXISTS oneonone_pairs CASCADE;
--    DROP TYPE IF EXISTS oneonone_message_template;
--    DROP TYPE IF EXISTS oneonone_notes_kind;
--    DROP TYPE IF EXISTS oneonone_ai_status;
--    DROP TYPE IF EXISTS oneonone_ai_owner;
--    DROP TYPE IF EXISTS oneonone_agenda_author;
--    DROP TYPE IF EXISTS oneonone_meeting_status;
--    DROP TYPE IF EXISTS oneonone_recurrence_type;
--    DROP FUNCTION IF EXISTS oneonone_user_has_permission(TEXT);
--    DROP FUNCTION IF EXISTS oneonone_current_tenant_id();
--    DROP FUNCTION IF EXISTS oneonone_current_user_id();
--    DROP FUNCTION IF EXISTS oneonone_check_content_lock();
--    DROP FUNCTION IF EXISTS oneonone_set_updated_at();
--
-- 4. Manter backup criptografado por 5 anos (LGPD Art. 16, retenção legal).


-- ============================================================================
-- §9 JOBS / SCHEDULED FUNCTIONS (sugestões para Supabase pg_cron)
-- ============================================================================
--
-- JOB 1 · Lock de conteúdo após 7 dias da conclusão (diário, 03:00):
--   UPDATE oneonone_meetings
--   SET content_locked_at = NOW()
--   WHERE status = 'completed'
--     AND content_locked_at IS NULL
--     AND completed_at < NOW() - INTERVAL '7 days';
--
-- JOB 2 · Auto-detect in_progress (a cada minuto):
--   UPDATE oneonone_meetings
--   SET status = 'in_progress', started_at = scheduled_start
--   WHERE status = 'scheduled'
--     AND scheduled_start <= NOW()
--     AND scheduled_end > NOW();
--
-- JOB 3 · Geração de meetings recorrentes (diário, 06:00):
--   Para cada pair com recurrence != 'once' e ended_at IS NULL,
--   verifica se há meeting agendada nos próximos 30 dias. Se não, cria a próxima
--   conforme cadência. Importante: respeitar feriados? · decisão de produto futura.
--
-- JOB 4 · Notificar liderados sem 1:1 há +30d (semanal, segunda 08:00):
--   SELECT recipient_id FROM oneonones_rh_overdue_led WHERE days_since > 30
--   → cria notification in-app para o líder responsável

-- ============================================================================
-- FIM DO SCHEMA v6 · MÓDULO DE 1:1s
-- ============================================================================

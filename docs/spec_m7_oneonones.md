# Spec · M7 · 1:1s Estruturadas

**Status:** pronto para execução em ambiente com Postgres 16 + pg_cron
**Pré-requisitos:** migrations base aplicadas
**Estimativa:** 2 sessões (~8h em ambiente preparado)

---

## 1. Objetivo

Portar para Next.js o **módulo completo de 1:1s** desenhado no rhgpc · 4 telas + schema v6 pronto.

| Tela origem | Página Next.js destino | Persona |
|---|---|---|
| [r2_people_oneonones.html](../r2_people_oneonones.html) | `/1on1s` | Líder (João) |
| [r2_people_oneonone_room.html](../r2_people_oneonone_room.html) | `/1on1s/[meetingId]/sala` | Líder + Liderado |
| [r2_people_minhas_1on1s.html](../r2_people_minhas_1on1s.html) | `/minhas-1on1s` | Liderado (Fernanda) |
| [r2_people_oneonones_rh.html](../r2_people_oneonones_rh.html) | `/admin/1on1s` | RH (Patrícia, Larissa) |

---

## 2. Regra-chave de produto · Privacidade arquitetural

**Privacidade é propriedade do schema, não da tela.** RH consultando o banco direto NÃO consegue ler conteúdo. Quatro princípios duros:

1. **Notas privadas do líder** · só o `leader_id` lê. Sem policy de SELECT para RH/admin/DPO regulares. Apenas DSAR formal via RPC dedicada.
2. **Notas compartilhadas** · só os dois participantes (`leader_id`, `led_id`).
3. **Pauta e descrição de action items** · bloqueados para RH. RH só vê metadados (count, dates, status) via views agregadas.
4. **Sentimento (mood)** · privado de quem registrou. `mood_leader` só pelo líder, `mood_led` só pelo liderado. RH não vê de ninguém. Decisão dura para evitar instrumentalização.

---

## 3. Schema novo

Portar diretamente de [r2_people_schema_oneonones_v6.sql](../r2_people_schema_oneonones_v6.sql) (60KB · já completo).

### 3.1 Estrutura · 6 tabelas + 7 enums

```sql
-- migration: 00420_m7_schema_oneonones.sql

-- ENUMS
CREATE TYPE meeting_status AS ENUM ('scheduled', 'in_progress', 'completed', 'canceled');
CREATE TYPE meeting_cadence AS ENUM ('weekly', 'biweekly', 'monthly', 'custom');
CREATE TYPE agenda_item_status AS ENUM ('pending', 'discussed', 'skipped', 'carried_over');
CREATE TYPE note_kind AS ENUM ('private_leader', 'shared');
CREATE TYPE action_item_owner AS ENUM ('lead', 'led', 'both');
CREATE TYPE action_item_status AS ENUM ('open', 'in_progress', 'completed', 'canceled');
CREATE TYPE mood AS ENUM ('great', 'good', 'neutral', 'difficult');
CREATE TYPE message_template AS ENUM ('cadence', 'overdue_led', 'overdue_ai', 'custom');

-- TABELAS

CREATE TABLE oneonone_pairs (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id       UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  leader_id       UUID NOT NULL REFERENCES app_users(id),
  led_id          UUID NOT NULL REFERENCES app_users(id),
  cadence         meeting_cadence NOT NULL DEFAULT 'biweekly',
  custom_days     INT,                                   -- se cadence='custom', 1-90
  default_duration_min INT NOT NULL DEFAULT 30,
  default_location TEXT,                                 -- 'Online · Meet', 'Sala 3', etc.
  active          BOOLEAN NOT NULL DEFAULT TRUE,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (tenant_id, leader_id, led_id),
  CONSTRAINT pair_not_self CHECK (leader_id <> led_id),
  CONSTRAINT custom_days_range CHECK (
    cadence <> 'custom' OR (custom_days BETWEEN 1 AND 90)
  )
);

CREATE TABLE oneonone_meetings (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  pair_id         UUID NOT NULL REFERENCES oneonone_pairs(id) ON DELETE CASCADE,
  tenant_id       UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  leader_id       UUID NOT NULL REFERENCES app_users(id),  -- desnormalizado p/ RLS perf
  led_id          UUID NOT NULL REFERENCES app_users(id),
  scheduled_start TIMESTAMPTZ NOT NULL,
  scheduled_end   TIMESTAMPTZ NOT NULL,
  actual_start    TIMESTAMPTZ,
  actual_end      TIMESTAMPTZ,
  location        TEXT,
  status          meeting_status NOT NULL DEFAULT 'scheduled',
  mood_leader     mood,                                  -- privado do líder
  mood_led        mood,                                  -- privado do liderado
  content_locked_at TIMESTAMPTZ,                         -- preenchido 7d após completed
  canceled_reason TEXT,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT meeting_time_ordered CHECK (scheduled_end > scheduled_start),
  CONSTRAINT meeting_actual_ordered CHECK (
    actual_end IS NULL OR actual_start IS NULL OR actual_end >= actual_start
  )
);

CREATE TABLE oneonone_agenda_items (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  meeting_id      UUID NOT NULL REFERENCES oneonone_meetings(id) ON DELETE CASCADE,
  tenant_id       UUID NOT NULL,
  author_id       UUID NOT NULL REFERENCES app_users(id),
  text            TEXT NOT NULL,
  status          agenda_item_status NOT NULL DEFAULT 'pending',
  carried_from_meeting_id UUID REFERENCES oneonone_meetings(id),  -- anti-cascata
  display_order   INT NOT NULL DEFAULT 0,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE oneonone_notes (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  meeting_id      UUID NOT NULL REFERENCES oneonone_meetings(id) ON DELETE CASCADE,
  tenant_id       UUID NOT NULL,
  kind            note_kind NOT NULL,
  author_id       UUID NOT NULL REFERENCES app_users(id),
  content         TEXT NOT NULL DEFAULT '',
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (meeting_id, kind, author_id)  -- 1 nota por kind por autor por meeting
);

CREATE TABLE oneonone_action_items (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  meeting_id      UUID NOT NULL REFERENCES oneonone_meetings(id) ON DELETE CASCADE,
  tenant_id       UUID NOT NULL,
  description     TEXT NOT NULL,                         -- bloqueado para RH
  owner           action_item_owner NOT NULL,
  due_date        DATE,
  status          action_item_status NOT NULL DEFAULT 'open',
  completed_at    TIMESTAMPTZ,
  completed_by    UUID REFERENCES app_users(id),
  carried_from_meeting_id UUID REFERENCES oneonone_meetings(id),
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE oneonone_messages (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id       UUID NOT NULL,
  sender_id       UUID NOT NULL REFERENCES app_users(id),
  recipient_id    UUID NOT NULL REFERENCES app_users(id),
  about_pair_id   UUID REFERENCES oneonone_pairs(id),    -- contexto (opcional)
  template        message_template NOT NULL,
  subject         VARCHAR(200),
  body            TEXT NOT NULL,
  read_at         TIMESTAMPTZ,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- INDEXES
CREATE INDEX idx_pairs_leader ON oneonone_pairs(leader_id) WHERE active = TRUE;
CREATE INDEX idx_pairs_led ON oneonone_pairs(led_id) WHERE active = TRUE;
CREATE INDEX idx_meetings_pair_time ON oneonone_meetings(pair_id, scheduled_start DESC);
CREATE INDEX idx_meetings_status ON oneonone_meetings(tenant_id, status, scheduled_start);
CREATE INDEX idx_agenda_meeting ON oneonone_agenda_items(meeting_id, display_order);
CREATE INDEX idx_notes_meeting ON oneonone_notes(meeting_id);
CREATE INDEX idx_ai_meeting ON oneonone_action_items(meeting_id);
CREATE INDEX idx_ai_open ON oneonone_action_items(tenant_id, status, due_date) WHERE status IN ('open', 'in_progress');
CREATE INDEX idx_messages_recipient ON oneonone_messages(recipient_id, created_at DESC);
```

### 3.2 RLS · 25 policies privacy-enforced

```sql
-- migration: 00421_m7_rls_oneonones.sql

ALTER TABLE oneonone_pairs ENABLE ROW LEVEL SECURITY;
ALTER TABLE oneonone_meetings ENABLE ROW LEVEL SECURITY;
ALTER TABLE oneonone_agenda_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE oneonone_notes ENABLE ROW LEVEL SECURITY;
ALTER TABLE oneonone_action_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE oneonone_messages ENABLE ROW LEVEL SECURITY;

-- PAIRS · participantes veem, RH com permission vê metadados
CREATE POLICY pairs_participants ON oneonone_pairs FOR SELECT
  USING (leader_id = current_user_id() OR led_id = current_user_id());

CREATE POLICY pairs_rh_metadata ON oneonone_pairs FOR SELECT
  USING (
    tenant_id = current_tenant_id()
    AND user_has_permission('view_oneonones_metadata')
  );

CREATE POLICY pairs_leader_manage ON oneonone_pairs FOR ALL
  USING (leader_id = current_user_id() AND user_has_permission('manage_oneonone_pairs'));

-- MEETINGS · idem
CREATE POLICY meetings_participants ON oneonone_meetings FOR SELECT
  USING (leader_id = current_user_id() OR led_id = current_user_id());

CREATE POLICY meetings_rh_metadata ON oneonone_meetings FOR SELECT
  USING (tenant_id = current_tenant_id() AND user_has_permission('view_oneonones_metadata'));

-- AGENDA · APENAS participantes (RH NÃO vê texto)
CREATE POLICY agenda_participants_only ON oneonone_agenda_items FOR ALL
  USING (EXISTS (
    SELECT 1 FROM oneonone_meetings m
    WHERE m.id = meeting_id
      AND (m.leader_id = current_user_id() OR m.led_id = current_user_id())
  ));
-- NÃO criar policy de SELECT para RH em agenda

-- NOTES · 2 policies
CREATE POLICY notes_shared_participants ON oneonone_notes FOR SELECT
  USING (
    kind = 'shared'
    AND EXISTS (
      SELECT 1 FROM oneonone_meetings m
      WHERE m.id = meeting_id
        AND (m.leader_id = current_user_id() OR m.led_id = current_user_id())
    )
  );

CREATE POLICY notes_private_leader_only ON oneonone_notes FOR SELECT
  USING (
    kind = 'private_leader'
    AND EXISTS (
      SELECT 1 FROM oneonone_meetings m
      WHERE m.id = meeting_id AND m.leader_id = current_user_id()
    )
  );

-- INSERT/UPDATE de notes: igual mas adicionar validação de kind=author
CREATE POLICY notes_insert_validate ON oneonone_notes FOR INSERT
  WITH CHECK (
    author_id = current_user_id()
    AND CASE
      WHEN kind = 'private_leader' THEN EXISTS (
        SELECT 1 FROM oneonone_meetings m
        WHERE m.id = meeting_id AND m.leader_id = current_user_id()
      )
      WHEN kind = 'shared' THEN EXISTS (
        SELECT 1 FROM oneonone_meetings m
        WHERE m.id = meeting_id
          AND (m.leader_id = current_user_id() OR m.led_id = current_user_id())
      )
    END
  );

CREATE POLICY notes_update_locked ON oneonone_notes FOR UPDATE
  USING (
    author_id = current_user_id()
    AND NOT EXISTS (
      SELECT 1 FROM oneonone_meetings m
      WHERE m.id = meeting_id AND m.content_locked_at IS NOT NULL
    )
  );

-- ACTION_ITEMS · igual a agenda (apenas participantes)
CREATE POLICY ai_participants_only ON oneonone_action_items FOR ALL
  USING (EXISTS (
    SELECT 1 FROM oneonone_meetings m
    WHERE m.id = meeting_id
      AND (m.leader_id = current_user_id() OR m.led_id = current_user_id())
  ));

-- MESSAGES · destinatário ou remetente
CREATE POLICY messages_party ON oneonone_messages FOR SELECT
  USING (sender_id = current_user_id() OR recipient_id = current_user_id());

CREATE POLICY messages_send ON oneonone_messages FOR INSERT
  WITH CHECK (
    sender_id = current_user_id()
    AND user_has_permission('send_oneonone_messages')
  );

-- ... mais policies para UPDATE/DELETE, totalizando 25
```

### 3.3 Views agregadas para RH (só metadados)

```sql
-- migration: 00422_m7_views_rh.sql

CREATE OR REPLACE VIEW oneonones_rh_dashboard_leader AS
SELECT
  p.tenant_id,
  p.leader_id,
  u_leader.full_name AS leader_name,
  p.led_id,
  u_led.full_name AS led_name,
  p.cadence,
  COUNT(m.id) FILTER (WHERE m.status = 'completed' AND m.scheduled_start > now() - INTERVAL '90 days') AS meetings_last_90d,
  MAX(m.scheduled_start) FILTER (WHERE m.status = 'completed') AS last_completed_at,
  -- COUNT abertos (NÃO retorna descrição)
  (SELECT COUNT(*) FROM oneonone_action_items ai
   JOIN oneonone_meetings m2 ON m2.id = ai.meeting_id
   WHERE m2.leader_id = p.leader_id AND m2.led_id = p.led_id
     AND ai.status IN ('open', 'in_progress')) AS open_action_items,
  -- Health score: 14d = verde, 21d = âmbar, >35d = vermelho
  CASE
    WHEN MAX(m.scheduled_start) FILTER (WHERE m.status = 'completed') > now() - INTERVAL '14 days' THEN 'fresh'
    WHEN MAX(m.scheduled_start) FILTER (WHERE m.status = 'completed') > now() - INTERVAL '35 days' THEN 'aging'
    ELSE 'stale'
  END AS health
FROM oneonone_pairs p
JOIN app_users u_leader ON u_leader.id = p.leader_id
JOIN app_users u_led ON u_led.id = p.led_id
LEFT JOIN oneonone_meetings m ON m.pair_id = p.id
WHERE p.active = TRUE
GROUP BY p.tenant_id, p.leader_id, u_leader.full_name, p.led_id, u_led.full_name, p.cadence;

-- View 2 · overdue_led (sem 1:1 há mais de 30 dias)
CREATE OR REPLACE VIEW oneonones_rh_overdue_led AS
SELECT
  p.tenant_id, p.leader_id, u_leader.full_name AS leader_name,
  p.led_id, u_led.full_name AS led_name,
  MAX(m.scheduled_start) FILTER (WHERE m.status = 'completed') AS last_meeting,
  EXTRACT(DAY FROM now() - MAX(m.scheduled_start) FILTER (WHERE m.status = 'completed'))::INT AS days_since
FROM oneonone_pairs p
JOIN app_users u_leader ON u_leader.id = p.leader_id
JOIN app_users u_led ON u_led.id = p.led_id
LEFT JOIN oneonone_meetings m ON m.pair_id = p.id
WHERE p.active = TRUE
GROUP BY p.tenant_id, p.leader_id, u_leader.full_name, p.led_id, u_led.full_name
HAVING (
  MAX(m.scheduled_start) FILTER (WHERE m.status = 'completed') IS NULL
  OR MAX(m.scheduled_start) FILTER (WHERE m.status = 'completed') < now() - INTERVAL '30 days'
);

-- View 3 · activity (eventos recentes, só metadados)
CREATE OR REPLACE VIEW oneonones_rh_activity AS
SELECT
  m.tenant_id,
  m.leader_id, u_leader.full_name AS leader_name,
  m.led_id, u_led.full_name AS led_name,
  m.status, m.scheduled_start, m.actual_end,
  CASE m.status
    WHEN 'completed' THEN m.actual_end
    WHEN 'canceled' THEN m.updated_at
    ELSE m.scheduled_start
  END AS event_at
FROM oneonone_meetings m
JOIN app_users u_leader ON u_leader.id = m.leader_id
JOIN app_users u_led ON u_led.id = m.led_id
WHERE m.scheduled_start > now() - INTERVAL '90 days'
ORDER BY event_at DESC;
```

### 3.4 RPCs SECURITY DEFINER (8 totais)

```sql
-- migration: 00423_m7_rpcs_oneonones.sql

-- 1. rpc_oneonone_get_room(meeting_id) · retorna sala completa para participante
-- 2. rpc_oneonone_save_notes(meeting_id, kind, content) · valida ownership
-- 3. rpc_oneonone_complete_meeting(meeting_id, mood_leader) · carry over auto
-- 4. rpc_oneonone_propose_reschedule(meeting_id, new_start, new_end, reason)
-- 5. rpc_oneonone_send_rh_message(recipient_id, template, subject, body, about_pair_id)
-- 6. rpc_oneonone_create_action_item(meeting_id, description, owner, due_date)
-- 7. rpc_oneonone_get_my_history(p_limit)
-- 8. rpc_oneonone_dsar_export(target_user_id) · LGPD Art. 18, permission própria

-- Exemplo: complete_meeting com carry over
CREATE OR REPLACE FUNCTION rpc_oneonone_complete_meeting(
  p_meeting_id UUID, p_mood_leader mood DEFAULT NULL
) RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_user app_users; v_meeting oneonone_meetings;
  v_next_meeting_id UUID; v_carried INT := 0;
BEGIN
  SELECT * INTO v_user FROM app_users WHERE id = current_user_id();
  IF v_user.id IS NULL THEN RETURN jsonb_build_object('error', 'not_authenticated'); END IF;

  SELECT * INTO v_meeting FROM oneonone_meetings WHERE id = p_meeting_id;
  IF v_meeting.id IS NULL THEN RETURN jsonb_build_object('error', 'meeting_not_found'); END IF;
  IF v_meeting.leader_id <> v_user.id THEN
    RETURN jsonb_build_object('error', 'permission_denied', 'reason', 'only_leader_completes');
  END IF;
  IF v_meeting.status = 'completed' THEN
    RETURN jsonb_build_object('error', 'already_completed');
  END IF;

  UPDATE oneonone_meetings
    SET status = 'completed', actual_end = now(), mood_leader = p_mood_leader, updated_at = now()
    WHERE id = p_meeting_id;

  -- Encontra próxima meeting do pair para fazer carry over
  SELECT id INTO v_next_meeting_id FROM oneonone_meetings
    WHERE pair_id = v_meeting.pair_id
      AND scheduled_start > v_meeting.scheduled_start
      AND status = 'scheduled'
    ORDER BY scheduled_start ASC LIMIT 1;

  IF v_next_meeting_id IS NOT NULL THEN
    -- Anti-cascata: não copia items que já foram carry over (carried_from_meeting_id IS NULL)
    INSERT INTO oneonone_agenda_items
      (meeting_id, tenant_id, author_id, text, status, carried_from_meeting_id, display_order)
    SELECT
      v_next_meeting_id, ai.tenant_id, ai.author_id, ai.text, 'carried_over',
      p_meeting_id,
      COALESCE((SELECT MAX(display_order) FROM oneonone_agenda_items WHERE meeting_id = v_next_meeting_id), 0) + ROW_NUMBER() OVER ()
    FROM oneonone_agenda_items ai
    WHERE ai.meeting_id = p_meeting_id
      AND ai.status = 'pending'
      AND ai.carried_from_meeting_id IS NULL;
    GET DIAGNOSTICS v_carried = ROW_COUNT;
  END IF;

  -- Audit
  INSERT INTO audit_log (tenant_id, actor_user_id, action, entity_table, entity_id, after_data)
    VALUES (v_user.tenant_id, v_user.id, 'update', 'oneonone_meetings', p_meeting_id,
            jsonb_build_object('event', 'completed', 'carried_over', v_carried));

  RETURN jsonb_build_object('ok', TRUE, 'meeting_id', p_meeting_id,
    'next_meeting_id', v_next_meeting_id, 'carried_over', v_carried);
END; $$;
```

### 3.5 Jobs pg_cron sugeridos (4)

```sql
-- migration: 00424_m7_cron_jobs.sql (opcional, depende de pg_cron disponível)

-- Job 1: auto-detect in_progress a cada 1min
SELECT cron.schedule('oneonone-auto-in-progress', '* * * * *', $$
  UPDATE oneonone_meetings
  SET status = 'in_progress', actual_start = scheduled_start
  WHERE status = 'scheduled'
    AND scheduled_start <= now()
    AND scheduled_end > now();
$$);

-- Job 2: lock content após 7 dias
SELECT cron.schedule('oneonone-lock-content', '0 3 * * *', $$
  UPDATE oneonone_meetings
  SET content_locked_at = now()
  WHERE status = 'completed'
    AND actual_end < now() - INTERVAL '7 days'
    AND content_locked_at IS NULL;
$$);

-- Job 3: gerar próximas meetings nos próximos 30 dias para pairs ativos
SELECT cron.schedule('oneonone-generate-next', '0 4 * * *', $$
  -- Lógica que olha cadence e cria registros scheduled
$$);

-- Job 4: marcar canceladas as scheduled que passaram do prazo sem start
SELECT cron.schedule('oneonone-auto-cancel', '0 5 * * *', $$
  UPDATE oneonone_meetings
  SET status = 'canceled', canceled_reason = 'auto: scheduled_end exceeded without start'
  WHERE status = 'scheduled'
    AND scheduled_end < now() - INTERVAL '24 hours';
$$);
```

---

## 4. Páginas Next.js

### 4.1 `/1on1s` (hub líder)

Referência: [r2_people_oneonones.html](../r2_people_oneonones.html)

- 4 KPIs: cadência média, próxima 1:1, AIs em atraso, sem 1:1 há +30d
- Banner contextual amarelo se há liderado em débito
- Grid de cards por liderado (border colorida por health: fresh/aging/stale)
- Modal de agendamento com select de pessoa, data/hora, duração, recorrência

### 4.2 `/1on1s/[meetingId]/sala` (sala individual)

Referência: [r2_people_oneonone_room.html](../r2_people_oneonone_room.html)

- Header sticky com avatar, chips EMP/TOM, status pill, timer regressivo
- 4 tabs: Notas, Pauta, Action items, Histórico
- **Notas duais lado a lado**:
  - Privadas (fundo amarelo, cadeado, "só você vê") · `kind='private_leader'`
  - Compartilhadas (fundo branco, ícone pessoas, "você e Fernanda veem") · `kind='shared'`
- Auto-save com debounce 700ms
- Modal "Concluir" com sentimento + checkbox de lock após 7d

### 4.3 `/minhas-1on1s` (liderada)

Referência: [r2_people_minhas_1on1s.html](../r2_people_minhas_1on1s.html)

- Hero gradient navy→roxo com pill verde pulsante se "em andamento agora"
- Botões "Entrar na sala" + "Propor reagendar"
- Pauta inline editável (bullet roxo "você", laranja "líder", âmbar "vindo da anterior")
- Meus action items com checkbox **só nos próprios** (owner IN 'led' OR 'both')
- Histórico **SEM mostrar sentimento do líder**
- Sidebar com card verde "Sua privacidade"

### 4.4 `/admin/1on1s` (RH agregado)

Referência: [r2_people_oneonones_rh.html](../r2_people_oneonones_rh.html)

- Banner verde de privacidade no topo: "Você vê apenas metadados, nunca conteúdo"
- 6 KPIs clicáveis
- Tabela de líderes com pill colorida + visual de 6 semanas (verde/âmbar/vermelho)
- Modal "Notificar líder" com 4 templates
- Sidebar com lista de liderados sem 1:1 +45d

---

## 5. Testes

`supabase/tests/00420_m7_oneonones.sql` · meta 45+ testes:

Cenários críticos:
1. Notas privadas: líder cria → vê; RH SQL direto retorna 0; outro líder retorna 0
2. Notas compartilhadas: ambos participantes leem; RH retorna 0
3. Pauta: RH SQL direto na tabela retorna 0 rows
4. Action item: descrição não vaza para RH em nenhuma view
5. mood_leader: salvo, mas SELECT pelo led retorna NULL via RPC
6. Complete meeting: cria carry over automático, anti-cascata
7. Content lock após 7d: UPDATE falha
8. Cadence custom: aceita 1-90, rejeita 0 e 91
9. DSAR export: requer permission `dsar_export`, audit pesado
10. RH Larissa (profile escopo Labuta) vê pairs onde led_employer = Labuta
11. Reschedule só pelo led
12. Send_rh_message exige `send_oneonone_messages`
13. Job auto-in-progress muda status quando horário chega
14. Carry over não duplica itens já carregados
15. Pair self-reference rejeitada (CHECK)

---

## 6. Critérios de aceitação

- [ ] Migrations 00420-00424 aplicam idempotentemente
- [ ] 45+ testes passando
- [ ] **Privacidade enforced**: testes confirmam que RH NÃO consegue ler conteúdo via SQL direto
- [ ] 4 páginas Next.js renderizam
- [ ] Carry over de pauta funciona ao completar meeting
- [ ] Content lock após 7d (testar manualmente atualizando timestamp)
- [ ] Adapter em `src/lib/r2/oneonones.ts`
- [ ] Permissions adicionadas: `view_oneonones_metadata`, `send_oneonone_messages`, `manage_oneonone_pairs`, `view_oneonones_metadata_by_employer`, `dsar_export`
- [ ] Sidebar nav-items "1:1s" (líder/RH) e "Minhas 1:1s" (liderado)
- [ ] Banner verde de privacidade visível na `/admin/1on1s`
- [ ] Doc da sessão em `docs/sessao_m7.md`

---

## 7. Pontos de atenção

- **mood é o item mais sensível**: nunca aparecer em listas, dashboards ou views
- **Anti-cascata é silencioso mas crítico**: sem ele, um item carry-over de carry-over propaga infinito
- **Content lock**: precisa de UPDATE policy específica que cheque `content_locked_at IS NULL`
- **DSAR export deve audit log pesado**: cada acesso a notas privadas de terceiro gera entrada
- **Job pg_cron**: se ambiente não tem pg_cron, marcar 00424 como opcional e implementar com Edge Function ou job externo
- **Privacy banner não substitui RLS**: a barra verde é cosmética, a garantia é a 25 policies
- **RH prestadora (Larissa)** precisa de `permission_profile` (M1) com `scope_employer_unit_id` para filtro funcionar
- **`oneonone_notes UNIQUE (meeting_id, kind, author_id)`**: garante 1 nota por kind por autor (líder pode ter 1 privada + 1 compartilhada por meeting; liderado só 1 compartilhada)

---

**Comando de execução:**

```bash
for f in supabase/migrations/00420*.sql supabase/migrations/00421*.sql \
         supabase/migrations/00422*.sql supabase/migrations/00423*.sql; do
  psql $DATABASE_URL -v ON_ERROR_STOP=1 -f $f
done
psql $DATABASE_URL -v ON_ERROR_STOP=1 -f supabase/tests/00420_m7_oneonones.sql | grep -E "PASS|FAIL"
cd src && tsc --noEmit --strict
```

# Spec M20 · Inbox Unificado do Líder · Aprovações + Calendar + Alertas

**Status**: especificação · pré-implementação
**Versão**: 1.0 · 18 de maio de 2026
**Escopo**: tela única do líder consolidando tudo que precisa da decisão dele · férias, atestados, movimentações, reembolsos, PDIs, 1:1s, treinamentos pendentes da equipe
**Depende de**: spec M12 (notif), spec M18 (compliance), spec M19 (benefícios/reembolso), spec M17 (analytics)

---

## 1. Por que isso existe

Hoje o líder tem que abrir **5+ telas diferentes** para gerenciar o time:
- Atestados (`r2_people_atestados.html`)
- Férias (`r2_people_ferias.html`)
- Movimentações (`r2_people_movimentacoes.html`)
- Avaliações (`r2_people_avaliacao.html`)
- 1:1s (`r2_people_oneonones.html`)
- Aprovações (`r2_people_aprovacoes_rh.html`)
- Reembolsos (novo · M19)
- Treinamentos pendentes (novo · M18)

Resultado: **líder vira o gargalo**, esquece pendência, equipe fica esperando, eNPS cai.

**M20 = uma tela só** com:
- Inbox de aprovações ordenadas por urgência
- Calendar view consolidado (1:1, férias, ausências, aniversários, prazos)
- Painel da minha equipe c/ alertas proativos
- Ações rápidas inline (aprovar/rejeitar sem navegar)

---

## 2. Estrutura da página `r2_people_inbox_lider.html`

### 2.1 Hero · resumo do dia

| Card | Conteúdo |
|---|---|
| **Aprovações pendentes** | 3 críticas · 5 hoje · 12 esta semana |
| **1:1s desta semana** | 4 agendadas · 1 sem pauta |
| **Equipe em férias hoje** | 2 pessoas |
| **Alertas de risco** | João C 4 atestados em 60d · Maria S sem 1:1 há 90d |

### 2.2 Inbox de aprovações (principal)

Lista ordenada por:
1. Bloqueador legal (ASO vencido, MFA não habilitado)
2. SLA estourado
3. Aprovação > 24h pendente
4. Novos

Cada item:
- Ícone tipo (📄 atestado, 🏖️ férias, ↗ movement, 💰 reembolso, 🎓 treinamento)
- Nome do colaborador + avatar
- Resumo em 1 linha
- Tempo aguardando ("aguarda 2d")
- Botões inline: ✓ Aprovar / ✗ Rejeitar / 👁 Ver detalhe / 💬 Pedir mais info

Bulk actions:
- "Aprovar todos" (com confirmação)
- "Aprovar todos do tipo X"

### 2.3 Calendar consolidado

Vista mensal com sobreposição de:
- 📞 1:1s agendadas (recurring)
- 🏖️ Férias da equipe (range colorido)
- 🩺 Ausências por atestado (range)
- 🎂 Aniversários (natalício + empresa)
- ⏰ Prazos (avaliação ciclo, OKR check-in, ASO vencimento)
- 📚 Treinamentos agendados (sala/online)

Filtros: por pessoa, por tipo de evento.

Click no evento abre quick view com ação (reagendar 1:1, ver atestado, etc).

### 2.4 Painel "Minha equipe" (resumido)

Cards de cada subordinado direto com:
- Avatar + nome
- Status hoje (ativo / férias / atestado / homeoffice / treinamento)
- Próximo 1:1 (ou "agendar")
- Última avaliação (badge 9-Box: champion/contributor/risk)
- Sinais de alerta:
  - 🔴 ASO vencendo em < 30d
  - 🟡 4+ atestados em 90d
  - 🟡 0 1:1 em 60d
  - 🟡 PDI sem update há > 60d
  - 🟢 Champion subindo no 9-Box
- Compliance score (0-100, do M18)

### 2.5 Atividade recente da equipe

Feed cronológico (últimas 30 ações):
- "Fernanda submeteu atestado de 2 dias"
- "João atualizou OKR Q2.1 para 80%"
- "Pedro completou treinamento NR-35"
- "Maria pediu férias 15-20/junho"

Cada item é click→ação ou drill-down.

---

## 3. Schema (extensões mínimas)

Aproveita tabelas existentes. Nova tabela só para preferências:

```sql
CREATE TABLE IF NOT EXISTS leader_inbox_prefs (
  user_id              uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  default_view         text CHECK (default_view IN ('inbox','calendar','team')) DEFAULT 'inbox',
  auto_approve_rules   jsonb DEFAULT '{}'::jsonb,
  -- Ex: {"reimbursement_under_100": true, "vacation_in_planned_period": true}
  digest_frequency     text CHECK (digest_frequency IN ('realtime','hourly','daily','weekly')) DEFAULT 'daily',
  digest_time          time DEFAULT '08:00',
  notify_via           text[] DEFAULT ARRAY['in_app','email'],
  -- Sinais de alerta personalizados
  alert_atestado_count int DEFAULT 4,                    -- alerta se N atestados em 90d
  alert_no_oneonone_days int DEFAULT 60,
  alert_no_pdi_days    int DEFAULT 60,
  silenced_employees   uuid[],                            -- não receber alerta de X
  updated_at           timestamptz DEFAULT now()
);
```

---

## 4. RPCs principais

```sql
-- Inbox · todas as pendências priorizadas
rpc_leader_inbox(p_leader_id uuid)
  RETURNS TABLE (
    item_id uuid,
    item_type text,                                       -- 'vacation','aso','movement','reimbursement','training'
    employee_id uuid,
    employee_name text,
    summary text,
    urgency text,                                         -- 'blocker','urgent','normal'
    waiting_hours int,
    sla_at timestamptz,
    actions text[]                                        -- ['approve','reject','more_info']
  )

-- Calendar consolidado
rpc_leader_calendar(p_leader_id uuid, p_start date, p_end date)
  RETURNS TABLE (
    event_id uuid,
    event_type text,
    title text,
    start_at timestamptz,
    end_at timestamptz,
    employee_id uuid,
    metadata jsonb
  )

-- Painel da equipe
rpc_leader_team_panel(p_leader_id uuid)
  RETURNS TABLE (
    employee_id uuid,
    full_name text,
    current_status text,                                  -- 'active','vacation','medical','homeoffice','training'
    next_oneonone_at timestamptz,
    last_evaluation_box text,
    compliance_score numeric,
    alerts text[]                                         -- ['aso_expiring','too_many_certificates','no_oneonone_60d']
  )

-- Bulk approve
rpc_leader_bulk_approve(p_leader_id uuid, p_item_ids uuid[])
  RETURNS TABLE (approved int, failed int, errors jsonb)
```

---

## 5. UI · página `r2_people_inbox_lider.html`

### 5.1 Layout 3 painéis

```
+------------+----------------------+----------+
| Sidebar    | Inbox principal       | Painel    |
| (240px)    | (60%)                 | equipe    |
|            |                       | (340px)   |
|            | Hero (4 cards)        |           |
|            | -------------------- | Filtros   |
|            | Tabs: Inbox/Cal/Team  | Lista 8   |
|            | -------------------- | sub-      |
|            | Lista de aprovações   | ordinados |
|            | inline actions        | + sinais  |
+------------+----------------------+----------+
```

### 5.2 Aprovação inline

```html
<div class="inbox-item urgent">
  <div class="item-icon">🏖️</div>
  <div class="item-info">
    <strong>Fernanda Lima pediu férias</strong>
    <span class="meta">15-20 junho · 6 dias · aguarda 2d</span>
  </div>
  <div class="item-actions">
    <button class="btn-sm approve">✓ Aprovar</button>
    <button class="btn-sm reject">✗ Rejeitar</button>
    <button class="btn-sm-icon">👁</button>
    <button class="btn-sm-icon">💬</button>
  </div>
</div>
```

Aprovar dispara mutation otimista (item some) + retry se falhar.

### 5.3 Quick view

Click em "👁 Ver detalhe" abre side-drawer com:
- Contexto completo do item
- Histórico relacionado (ex: últimas férias do colaborador)
- Comentários
- Botão "Aprovar com observação"

### 5.4 Calendar view

Grid mensal estilo Google Calendar simplificado:
- Eventos coloridos por tipo
- Hover mostra detalhe
- Click abre quick action

### 5.5 Painel equipe

Card por subordinado com:
- Foto/avatar grande
- Status badge
- 3 mini-stats (1:1s últimos 90d, atestados últimos 90d, último update PDI)
- Pílulas de alerta (vermelho/amarelo)
- Click expande para perfil completo

---

## 6. Notificações via M12

Push/in-app/e-mail para o líder em:
- Nova aprovação pendente
- SLA estourado (item > 48h sem decisão)
- Sinal de alerta novo (ex: 4º atestado da pessoa em 90d)
- 1:1 hoje em N horas
- Aniversário hoje na equipe
- Avaliação ciclo abrindo

Respeita `digest_frequency` do `leader_inbox_prefs` (realtime/hourly/daily/weekly).

---

## 7. Permissões

- Líder vê **só seus subordinados diretos** (manager_id = self)
- Coord_rh vê **toda a equipe do tenant** (override de filtro)
- DPO vê tudo (auditoria)
- Colaborador NÃO acessa esta tela

---

## 8. Performance

- Inbox carrega em < 500ms para líder com 50 subordinados (índices em `manager_id` + `status`)
- Calendar carrega em < 1s para 30 dias
- Refresh em background a cada 30s (não bloqueia UI)
- Bulk approve até 50 itens em < 3s

---

## 9. Auto-aprovação por regra (avançado)

Líder pode configurar regras tipo:
- "Reembolso de telemedicina < R$ 100 auto-aprova"
- "Férias em período pré-planejado auto-aprova"
- "Atestado < 3 dias auto-aprova"

Cada auto-aprovação gera registro em `action_log` com `actor_id = leader + auto = true`.

Regras armazenadas em `leader_inbox_prefs.auto_approve_rules`.

---

## 10. Testes meta (mínimo 18)

- ✓ Inbox lista apenas subordinados diretos do líder
- ✓ Coord_rh vê todos
- ✓ Bulk approve aprova N itens em transação
- ✓ Item bloqueador (ASO vencido) aparece no topo
- ✓ Aprovação inline atualiza estado sem refresh
- ✓ Calendar consolidado mostra 6 tipos de evento
- ✓ Painel equipe mostra alertas calculados em tempo real
- ✓ Auto-aprovação dispara conforme regra
- ✓ Notificação respeita digest_frequency
- ✓ Bulk approve > 50 itens dá erro 422
- ✓ Mutação otimista reverte se backend falha
- ✓ Performance: inbox < 500ms, calendar < 1s
- ✓ RLS bloqueia ver subordinado de outro líder
- ✓ Action_log registra cada decisão c/ actor
- ✓ Aniversário no calendar lista correta
- ✓ Sinal "atestado recorrente" calcula > 4 em 90d
- ✓ Silenced_employees não dispara alerta
- ✓ Preferência default_view respeitada

---

## 11. Integração com outras specs

- **M17 People Analytics**: alertas do painel equipe alimentam métricas (turnover risk, eNPS individual queda)
- **M18 Compliance**: ASO/EPI/treinamento pendente aparece no inbox
- **M19 Benefícios**: reembolso pendente entra no inbox c/ valor + categoria
- **M12 Notif**: cada item gera notificação respeitando preferências
- **M16 Domínio**: férias aprovadas geram evento pro Domínio executar

---

## 12. Roadmap pós-MVP

1. **M+3 · IA prioriza inbox** (ML sugere top 3 a decidir agora)
2. **M+6 · ações por voz** (mobile: "aprovar férias da Fernanda")
3. **M+9 · resumo por slack/teams** (líder não precisa abrir R2 pra aprovar simples)
4. **M+12 · delegação** (líder ausente delega aprovações temporárias)
5. **M+18 · sugestão de pauta 1:1** (ML cruza dados da semana e sugere o que falar com cada subordinado)

# Spec M22 · Sucessão & Carreira · Skill Matrix, Sucessão Planejada, Mentoring

**Status**: especificação · pré-implementação
**Versão**: 1.0 · 18 de maio de 2026
**Escopo**: skill matrix por equipe + plano de sucessão por cargo crítico + mentoring matching opt-in + carreira self-request
**Depende de**: schema v9+ (employees, positions), spec M17 (Analytics), spec M18 (compliance/trilhas), spec M21 (trilhas operacionais)

---

## 1. Por que isso existe

Diretoria de PME brasileira acorda com dúvidas que **não consegue responder**:
- Se o gerente da loja X sair amanhã, **quem assume**?
- Quais skills temos no time e **quais faltam**?
- Quem é **champion potencial** mas não está sendo desenvolvido?
- Quem é **bom mentor** e quem precisa ser mentorado?
- Estou perdendo **5 Analistas Plenos** por ano · isso é normal pro mercado?

R2 People hoje tem PDI + 9-Box + OKRs, mas não **conecta isso em uma visão de carreira**. M22 fecha esse loop.

---

## 2. Áreas cobertas

### 2.1 Skill Matrix por equipe

Cada cargo tem **competências esperadas** (hard skills + soft skills). Cada colaborador é autoavaliado + avaliado pelo líder em cada competência (escala 1-5).

| Cargo | Competências esperadas (exemplos) |
|---|---|
| Analista Pleno BI | SQL avançado · Python pandas · storytelling · stakeholder mgmt · LGPD básico |
| Líder Financeiro | DRE · DFC · gestão de risco · liderança · gestão de conflito |
| Gerente de Loja | Operação varejo · gestão pessoas · KPIs · prevenção perdas · liderança remota |
| Coord Logística | Logística reversa · WMS · gestão equipe · indicadores · CCT |
| Atendente Caixa | Atendimento · velocidade PDV · proatividade · trabalho em equipe |

**UI**: heatmap colaborador × competência colorido (verde = atinge, amarelo = parcial, vermelho = abaixo).

**Insights agregados** (do M17 Analytics):
- "Time TI tem gap de competência em Python (4 de 9 abaixo do esperado) · planejar treinamento"
- "Coord Logística tem 3 pessoas com perfil para virar Gerente Operações"

### 2.2 Plano de sucessão

Para **cada cargo de liderança/crítico**, define-se:
- **Titular atual** (pessoa que ocupa)
- **Sucessor primário** (quem assumiria em caso de saída em 0-30 dias)
- **Sucessores secundários** (2-3 pessoas em desenvolvimento, 6-12 meses)
- **Skills gap** de cada sucessor (o que precisa desenvolver pra estar pronto)
- **Tempo estimado de preparação** (com PDI específico apontando para o cargo)

**UI**: árvore visual (organograma com sucessores) + tabela de cargos críticos.

**Alertas**:
- Cargo crítico sem sucessor primário identificado → P2 ao DPO/CEO
- Sucessor primário saiu da empresa → recalcular
- Titular > 5 anos no cargo sem plano = risco de retenção (oferecer challenge)

### 2.3 Mentoring matching

Programa opt-in onde colaborador pode se inscrever como:
- **Mentor** (oferece seu tempo · pelo menos 5 anos de casa ou skill notável)
- **Mentee** (busca apoio · qualquer nível)
- **Ambos** (sênior que quer mentorar júnior + ainda quer aprender com diretor)

**Matching automático** baseado em:
- Skill desejada pelo mentee × skill ofertada pelo mentor
- Compatibilidade horário (escala/turno disponibilidade)
- Não-conflito de hierarquia (mentor não pode ser líder direto do mentee · viés)
- Diferença de tempo de empresa mínima (mentor 2+ anos a mais)

**Workflow**:
1. Mentee solicita matching ("quero aprender SQL avançado")
2. R2 sugere 3 mentores compatíveis
3. Mentee escolhe + envia convite
4. Mentor aceita ou rejeita (sem prejuízo)
5. Pareados acordam frequência (semanal/quinzenal)
6. R2 agenda 1:1s recorrentes (cruzando spec M20)
7. Termina por consenso ou após N sessões

Status registrado · feedback bidirecional ao fim.

### 2.4 Carreira self-request

Hoje, colaborador interessa em movimentação só fala em 1:1 (e o líder pode esquecer). M22 dá **canal formal**:

1. Colaborador abre "Plano de Carreira" no perfil
2. Lista cargos da empresa filtrados pela aderência
3. Click "Tenho interesse" em um cargo → notifica RH + líder atual + líder do cargo destino
4. Gera **PDI direcionado** para o cargo destino (skills gap calculado automaticamente)
5. Quando vaga abrir, prioriza candidatos internos interessados
6. Histórico fica · "interessei-me em Coord BI 2x · não fui priorizado por X"

**Resultados esperados**:
- Aumenta promoções internas vs contratação externa (M17 mede)
- Reduz turnover por insatisfação de carreira
- Líder enxerga ambições do time (puxa conversa em 1:1)

### 2.5 Trilha de carreira sugerida

Por cargo, mapa visual: "Operadora Caixa → Frente de Caixa Sr → Sub-Gerente → Gerente de Loja → Gerente Regional → Diretoria Operações"

Para cada degrau:
- Tempo médio no cargo anterior antes de subir
- Skills necessárias
- Treinamentos sugeridos
- Casos de sucesso (anonimizado: "12 pessoas fizeram esse caminho em < 5 anos")

Inspira sem prometer.

---

## 3. Schema

```sql
-- 3.1 Skills · catálogo do tenant
CREATE TABLE IF NOT EXISTS skills_catalog (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id       uuid NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  name            text NOT NULL,
  category        text NOT NULL CHECK (category IN ('hard','soft','language','tool','certification')),
  description     text,
  active          boolean DEFAULT true,
  UNIQUE (tenant_id, name)
);

-- 3.2 Competências esperadas por cargo
CREATE TABLE IF NOT EXISTS position_skills_required (
  position_id     uuid NOT NULL,
  skill_id        uuid NOT NULL REFERENCES skills_catalog(id) ON DELETE CASCADE,
  expected_level  int NOT NULL CHECK (expected_level BETWEEN 1 AND 5),
  weight          numeric DEFAULT 1,             -- peso na avaliação
  PRIMARY KEY (position_id, skill_id)
);

-- 3.3 Skill self-assessment + leader assessment
CREATE TABLE IF NOT EXISTS employee_skills (
  id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id           uuid NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  employee_id         uuid NOT NULL,
  skill_id            uuid NOT NULL REFERENCES skills_catalog(id),
  self_level          int CHECK (self_level BETWEEN 1 AND 5),
  leader_level        int CHECK (leader_level BETWEEN 1 AND 5),
  leader_id           uuid,
  last_assessed_at    timestamptz DEFAULT now(),
  evidence            text,
  UNIQUE (employee_id, skill_id)
);

CREATE INDEX IF NOT EXISTS idx_emp_skills_employee
  ON employee_skills (employee_id);

-- 3.4 Plano de sucessão
CREATE TABLE IF NOT EXISTS succession_plans (
  id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id           uuid NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  position_id         uuid NOT NULL,
  current_holder_id   uuid,                       -- titular atual
  criticality         text CHECK (criticality IN ('low','medium','high','critical')) DEFAULT 'medium',
  reviewed_at         timestamptz,
  reviewed_by         uuid REFERENCES auth.users(id),
  next_review_at      timestamptz,
  notes               text
);

CREATE INDEX IF NOT EXISTS idx_succession_position
  ON succession_plans (tenant_id, position_id);

CREATE TABLE IF NOT EXISTS succession_candidates (
  id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  plan_id             uuid NOT NULL REFERENCES succession_plans(id) ON DELETE CASCADE,
  employee_id         uuid NOT NULL,
  priority            text NOT NULL CHECK (priority IN ('primary','secondary','tertiary')),
  readiness           text NOT NULL CHECK (readiness IN ('ready_now','ready_6m','ready_12m','ready_24m','exploratory')),
  skills_gap_summary  text,
  pdi_id              uuid,                       -- ref ao PDI específico do sucessor
  added_at            timestamptz DEFAULT now(),
  notes               text,
  UNIQUE (plan_id, employee_id)
);

-- 3.5 Mentoring program
CREATE TABLE IF NOT EXISTS mentoring_profiles (
  id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id           uuid NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  user_id             uuid NOT NULL REFERENCES auth.users(id),
  role                text NOT NULL CHECK (role IN ('mentor','mentee','both')),
  skills_offered      uuid[] DEFAULT ARRAY[]::uuid[],
  skills_seeking      uuid[] DEFAULT ARRAY[]::uuid[],
  availability        text,                       -- "quartas 14-15h, alternados"
  bio                 text,
  active              boolean DEFAULT true,
  joined_at           timestamptz DEFAULT now(),
  UNIQUE (tenant_id, user_id)
);

CREATE TABLE IF NOT EXISTS mentoring_pairs (
  id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id           uuid NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  mentor_id           uuid NOT NULL REFERENCES auth.users(id),
  mentee_id           uuid NOT NULL REFERENCES auth.users(id),
  initiated_by        uuid NOT NULL,
  status              text NOT NULL CHECK (status IN ('proposed','active','completed','cancelled')) DEFAULT 'proposed',
  topic               text,                       -- "aprender SQL avançado"
  frequency           text,                       -- 'weekly','biweekly','monthly'
  started_at          timestamptz,
  completed_at        timestamptz,
  mentor_feedback     text,
  mentee_feedback     text,
  mentor_rating       int CHECK (mentor_rating BETWEEN 1 AND 5),
  mentee_rating       int CHECK (mentee_rating BETWEEN 1 AND 5),
  notes               text
);

CREATE INDEX IF NOT EXISTS idx_mentoring_active
  ON mentoring_pairs (tenant_id, status) WHERE status = 'active';

-- 3.6 Carreira · self-request
CREATE TABLE IF NOT EXISTS career_interests (
  id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id           uuid NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  employee_id         uuid NOT NULL,
  target_position_id  uuid NOT NULL,
  motivation          text,
  expected_timeframe  text CHECK (expected_timeframe IN ('6m','12m','24m','3y_plus')),
  status              text CHECK (status IN ('declared','in_pdi','considered','approved','not_selected','withdrawn')) DEFAULT 'declared',
  pdi_id              uuid,
  declared_at         timestamptz DEFAULT now(),
  resolved_at         timestamptz,
  resolution_notes    text,
  UNIQUE (employee_id, target_position_id, declared_at)
);

CREATE INDEX IF NOT EXISTS idx_career_interest_active
  ON career_interests (target_position_id) WHERE status IN ('declared','in_pdi','considered');

-- 3.7 Trilha de carreira sugerida
CREATE TABLE IF NOT EXISTS career_paths (
  id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id           uuid NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  name                text NOT NULL,              -- "Loja · Operação"
  description         text,
  active              boolean DEFAULT true
);

CREATE TABLE IF NOT EXISTS career_path_steps (
  id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  path_id             uuid NOT NULL REFERENCES career_paths(id) ON DELETE CASCADE,
  position_id         uuid NOT NULL,
  step_order          int NOT NULL,
  avg_time_months     int,                        -- tempo médio observado nesse degrau antes de subir
  required_skills     uuid[] DEFAULT ARRAY[]::uuid[],
  suggested_tracks    uuid[] DEFAULT ARRAY[]::uuid[],
  UNIQUE (path_id, step_order)
);
```

---

## 4. RPCs principais

```sql
-- Skill matrix por equipe (heatmap)
rpc_team_skills_heatmap(p_leader_id uuid)
  RETURNS TABLE (employee_id, employee_name, skill_id, skill_name, expected, actual, gap)

-- Gap de competência por cargo (planejar treinamento)
rpc_position_skills_gap(p_tenant_id uuid, p_position_id uuid)
  RETURNS TABLE (skill_id, skill_name, expected_level, avg_actual_level, gap_count, employees_below)

-- Sucessores prontos por cargo crítico
rpc_succession_readiness(p_tenant_id uuid, p_position_id uuid DEFAULT NULL)
  RETURNS TABLE (position_id, position_name, holder_id, primary_id, primary_readiness, secondary_count, criticality)

-- Cargos críticos sem sucessor identificado (alerta)
rpc_succession_gaps(p_tenant_id uuid)
  RETURNS TABLE (position_id, position_name, criticality, holder_id, missing_priority text[])

-- Matching mentor → mentee
rpc_mentoring_match_suggest(p_mentee_user_id uuid, p_topic text, p_limit int DEFAULT 3)
  RETURNS TABLE (mentor_user_id uuid, mentor_name text, skills_overlap int, availability text, fit_score numeric)

-- Solicitar matching mentor
rpc_mentoring_request(p_mentor_user_id uuid, p_topic text, p_frequency text)
  RETURNS uuid

-- Declarar interesse em cargo (career self-request)
rpc_career_interest_declare(p_target_position_id uuid, p_motivation text, p_timeframe text)
  RETURNS uuid

-- Próximo degrau sugerido para o colaborador
rpc_career_next_step(p_employee_id uuid)
  RETURNS TABLE (next_position_id, position_name, gap_skills jsonb, suggested_tracks uuid[], realistic_timeframe text)
```

---

## 5. UI · 3 telas novas + extensões

### 5.1 `r2_people_skill_matrix.html` (RH + líder)

Modo gestor RH:
- Heatmap colaborador × competência (verde/amber/red)
- Filtros: departamento, cargo, nível
- Drill-down colaborador → ficha completa de skills

Modo líder:
- Sua equipe na coluna · skills na linha
- Identifica gaps · sugere treinamento ou contratação

### 5.2 `r2_people_sucessao.html` (CEO + diretoria + RH sênior)

- Lista de **cargos críticos** (filtrável)
- Para cada um:
  - Foto + nome do titular
  - Sucessor primário (com badge "pronto agora" / "6m" / "12m")
  - 2-3 secundários
  - Skills gap visual
  - PDI direcionado (link)
- **Alerta vermelho** para cargos críticos sem sucessor
- Vista organograma (árvore) opcional

### 5.3 `r2_people_mentoring.html` (todos)

Modo colaborador:
- Toggle "Sou mentor / Sou mentee / Ambos"
- Lista de matches sugeridos
- Pares ativos (suas mentorias)
- Histórico

Modo admin RH:
- Visão geral programa (X mentores ativos, Y matches em andamento)
- Pares com baixo NPS pós-encerramento (rever matching)

### 5.4 Extensão em `r2_people_minha_trajetoria.html`

Adicionar seção **"Plano de carreira"**:
- "Próximo degrau possível: Frente de Caixa Sênior"
- Skills que faltam (3 de 8 esperadas)
- "Declarar interesse" CTA
- Histórico de interesses declarados

### 5.5 Extensão em `r2_people_inbox_lider.html`

Adicionar alerta:
- "Fernanda Lima declarou interesse em Coord BI · você quer conversar?"
- "3 sucessores do seu cargo estão em andamento · revisar PDI"

---

## 6. Integração cruzada

| Spec | Como M22 conecta |
|---|---|
| **M17 Analytics** | % de promoção interna (M22) entra como métrica · skill gap agregado entra no dashboard diretoria |
| **M18 Compliance** | Trilhas NR são pré-requisito para alguns cargos · sucessor só "pronto" se NR-X ok |
| **M21 Trilhas operacionais** | Sucessor de gerente loja deve ter trilha Gerente de Loja concluída |
| **M20 Inbox líder** | Declaração de interesse + alertas de sucessão entram no inbox |
| **PDI** (já existe) | PDI gerado automático quando declara interesse em cargo |
| **9-Box** | Champions do 9-Box são candidatos naturais a sucessores · vínculo automático |

---

## 7. Notificações via M12

- `succession.gap_detected` → CEO + RH (cargo crítico sem sucessor)
- `succession.holder_left` → RH (titular saiu · ativar plano)
- `mentoring.match_suggested` → mentee (3 sugestões)
- `mentoring.request_received` → mentor
- `mentoring.session_today` → mentor + mentee (lembrete 1h antes)
- `career.interest_declared` → líder atual + RH
- `career.pdi_assigned` → colaborador (PDI direcionado criado)
- `skill.gap_team` → líder (3+ pessoas abaixo do esperado na mesma skill)

---

## 8. Permissões

| Dado | Quem vê |
|---|---|
| Próprio skill assessment | colaborador · sempre |
| Skill do subordinado | líder direto |
| Skill agregado por departamento | RH coord |
| Plano de sucessão · todos | apenas `view_succession_plans` (CEO + Diretoria + RH sênior) |
| Mentoring · próprias relações | sempre |
| Mentoring · stats agregados | RH coord |
| Carreira · próprios interesses | sempre |
| Carreira · interesses do time | líder + RH |

Plano de sucessão é **sensível** — saber "você é o backup do Marcos mas ainda precisa de 12 meses" pode gerar conversa difícil. Por isso visibilidade controlada.

---

## 9. Testes meta (mínimo 22)

- ✓ Skill assessment self + leader gera gap correto
- ✓ Sucessor primário sem skill obrigatória NÃO é "pronto agora"
- ✓ Cargo crítico sem sucessor dispara alerta P2
- ✓ Sucessor que sai recalcula plano automaticamente
- ✓ Mentor não pode ser líder direto do mentee (RLS)
- ✓ Matching considera disponibilidade horária
- ✓ Matching diferença tempo empresa > 2 anos
- ✓ Mentee feedback bidirecional após encerramento
- ✓ Career interest cria PDI direcionado automaticamente
- ✓ Vaga aberta prioriza candidatos internos interessados
- ✓ Trilha de carreira mostra próximo degrau realista
- ✓ Tempo médio no degrau anterior calculado com dados históricos
- ✓ Heatmap skill matrix carrega < 1s para time de 50
- ✓ Plano de sucessão respeita visibilidade restrita
- ✓ Notificação `succession.holder_left` dispara em < 1h após terminate
- ✓ Mentoring NPS < 6 dispara revisão do matching
- ✓ Carreira self-request não aparece para outros colaboradores
- ✓ Skill agregado por departamento omite indivíduos
- ✓ % promoção interna alimenta People Analytics (M17)
- ✓ Trilha NR-X obrigatória bloqueia status "pronto agora"
- ✓ Mentoring pair encerrada não bloqueia novo matching
- ✓ Bulk import de skills via CSV não duplica

---

## 10. Roadmap pós-MVP

1. **M+3 · IA sugere desenvolvimento** (cruza skill gap + interesse + cargos abertos no mercado)
2. **M+6 · 360° feedback estruturado** (pares + subordinados + líder · cruza com skills)
3. **M+9 · benchmark de skills do setor** (anonimizado · "TI varejo BR média X" vs sua média)
4. **M+12 · marketplace interno de projetos** (skill ofertada × projeto curto · gig economy interno)
5. **M+18 · sucessão por simulação Monte Carlo** (E se 3 pessoas saírem? Quem assume?)
6. **M+24 · skills inferidas por análise de atividade** (NLP em PDIs/feedbacks · sugere skill não declarada)

---

## 11. Posicionamento comercial

Atualizar C1/C3 com bullet:
> "**Sucessão e carreira sob controle**: skill matrix por equipe, plano de sucessão por cargo crítico, mentoring matching automático, carreira self-request. Diretoria sabe quem assume se gerente sair amanhã. Colaborador sabe o próximo degrau realista."

Diferenciação adicional vs Qulture/Sólides:
- Qulture: 9-Box sim, sucessão não · matrix de skills básica
- Sólides: assessment de DISC, mas sem skill matrix por cargo
- Senior HCM: tem sucessão (Enterprise pago caro · implantação 6m)
- **R2 People**: tudo isso incluso no Pro · ativável no wizard

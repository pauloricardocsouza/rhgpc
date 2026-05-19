# Spec M21 · Específicos Varejo Multi-Loja · GPC e similares

**Status**: especificação · pré-implementação
**Versão**: 1.0 · 18 de maio de 2026
**Escopo**: funcionalidades dedicadas a operações de varejo multi-loja (anchor client GPC: 14 unidades, 367 colaboradores)
**Depende de**: spec M17 (Analytics), spec M18 (Compliance), spec M20 (Inbox líder), spec M16 (Domínio · banco horas), schema v9+

---

## 1. Por que isso existe (e merece spec própria)

Varejo não é "qualquer empresa" — tem dores específicas que SaaS HR genéricos ignoram:

| Dor varejo | SaaS HR genérico | R2 People · M21 |
|---|---|---|
| **Absenteísmo destrói operação de loja** (sem caixa = fila → fuga de cliente) | mostra % total | painel loja × horário × cargo c/ alerta tempo real |
| **Gerente regional cuida de 5-10 lojas** | uma tela só pra "minha equipe" | quadro multi-loja consolidado + drill-down |
| **Quadro de honra** (vendedor do mês, melhor frente caixa) é cultural no varejo | inexiste ou genérico | módulo dedicado c/ ranking automático + reconhecimento público |
| **Treinamento por função** (caixa, repositor, ASG, segurança) é frequente | trilha genérica | trilhas por função c/ matriz e progresso |
| **Comissão de vendas** muda comportamento | só folha mostra | consulta em tempo real do colaborador + projeção |
| **Escala/turno** complica férias e folgas | só calendar simples | visualização escala oficial (externa) + impacto de pedidos |
| **Tripartite** (rede ≠ loja CTPS) quebra ERPs | não modela | nativo R2 desde dia 1 (já existe) |

---

## 2. Áreas cobertas

### 2.1 Quadro multi-loja para gerente regional

Cenário GPC: **Carla Reis** é Coordenadora de Logística do Atacadão Pinto · ela "cuida" de 5 lojas (ATP-Varejo, ATP-Atacado, CD Logística, Cestão L1, Cestão Inhambupe). Hoje precisa abrir 5 dashboards diferentes.

**Tela única "Minhas lojas"**:

| Loja | Headcount | Ativos hoje | Absent. mês | Turnover 90d | Ações pendentes | Health |
|---|---|---|---|---|---|---|
| Cestão L1 | 91 | 88 (97%) | 4.2% | 12% | 3 | 🟢 |
| ATP-Varejo | 78 | 72 (92%) | 6.1% | 18% | 7 | 🟡 |
| Cestão Inhambupe | 46 | 41 (89%) | 8.4% | 22% | 12 | 🔴 |
| ATP-Atacado | 42 | 41 (98%) | 2.8% | 8% | 1 | 🟢 |
| CD Logística | 37 | 35 (95%) | 5.1% | 14% | 4 | 🟡 |

Sort/filtro por: health, turnover, absenteísmo, ações pendentes.

Drill-down click linha → painel da loja específica.

### 2.2 Absenteísmo por loja (granularidade que importa)

Métricas vivas:
- **% de absenteísmo dia/semana/mês** por loja
- **Horário crítico** (loja c/ pico 11-14h precisa de caixa)
- **Cobertura por função** (quantos caixas, quantos repositores ativos agora vs escala planejada)
- **Mapa de calor** dias da semana × loja (segunda 30% absent recorrente?)
- **Recorrência** (5+ atestados em 90d de mesma pessoa → ação)
- **Tipo de ausência** (atestado · falta sem justificativa · falta justificada · férias · folga compensada)

Alertas em tempo real:
- "Cestão L1: 3 caixas ausentes às 11h (escala previa 6) — abrir extras?"
- "ATP-Varejo: ASGs caíram pra 1 (mínimo 2) — chamar cobertura"

### 2.3 Quadro de honra

Reconhecimento público + gamificação leve · varejo precisa de cultura visível.

**Categorias automáticas mensais**:
- **Funcionário do mês** (mais elogios + nota 9-Box + 0 atestado)
- **Vendedor do mês** (maior venda · vem do ERP via M16)
- **Frente de caixa de excelência** (maior NPS cliente · maior velocidade)
- **Repositor do mês** (menor ruptura · pontualidade)
- **Time da loja do mês** (loja c/ menor absent + maior eNPS + meta batida)

**UI**:
- Card grande na home pro tenant todo (ja existe parcial — refinar)
- Histórico "Hall of Fame" navegável
- Página pública (opt-in) tipo "vitrine" para a empresa mostrar
- E-mail mensal automático ao tenant_admin com vencedores

**Cálculo**:
```sql
-- Funcionário do mês por loja
CREATE OR REPLACE FUNCTION rpc_employee_of_month_by_branch(
  p_tenant_id uuid,
  p_branch_id uuid,
  p_month text  -- '2026-05'
) RETURNS TABLE (
  employee_id uuid,
  full_name text,
  score numeric,
  reasoning jsonb
)
-- Lógica · combina:
-- * count(praises_received WHERE month = X) * 3
-- * eval_box (champion=10, contributor=5, average=2)
-- * (1 - absent_rate) * 5
-- * tenure_bonus (anos de casa, max 3)
```

### 2.4 Treinamento por função

Diferente do M18 (treinamentos NR obrigatórios legais), aqui são **trilhas operacionais** por função:

| Função | Trilha · módulos sequenciais | Duração total | Quando |
|---|---|---|---|
| **Operador de caixa** | Sistema PDV · atendimento · estorno · sangria · fechamento | 12h | admissão |
| **Repositor** | Layout planograma · validade · etiqueta · GLP/EPI · técnica empilhamento | 8h | admissão |
| **ASG (limpeza)** | Produtos químicos · NR-6 EPI · áreas restritas · descarte | 6h | admissão |
| **Vigilante** | Vigilância · primeiros socorros · evacuação · NR-21 | 16h | admissão + bienal |
| **Frente de caixa sênior** | Liderança · gestão de conflito · KPIs · supervisão | 20h | promoção |
| **Gerente de loja** | Gestão operação · pessoas · vendas · prevenção perdas · DRE básico | 40h | promoção/contratação |

Cada trilha tem:
- Vídeos curtos (5-15min cada)
- Quiz de fixação por módulo
- Avaliação final (mín 70%)
- Certificado interno (não NR oficial)
- Validade (rever a cada N meses)

Mobile-first (colaborador faz no celular entre atendimentos).

### 2.5 Comissão de vendas (consulta · vem do Domínio)

R2 **não calcula**. Reflete o que vem do ERP de venda + folha Domínio:
- Meta do mês × realizado × % atingido
- Comissão acumulada no mês
- Projeção para fim de mês (ritmo atual)
- Ranking comparativo na loja (sem expor valor individual de outros — só sua posição)
- Histórico 12 meses

Colaborador consulta no app. Líder vê ranking da loja agregado.

### 2.6 Escala/turno (visualização)

Escala é feita externamente (sistema dedicado tipo Tangerino, Ahgora ou planilha). R2 **importa via M14 inbound** + **mostra impacto**.

**Tela**:
- Calendar semanal × pessoa × turno
- Sobreposição: férias programadas, atestados, folgas compensadas, treinamentos
- Alerta: "Você está marcando férias em 18-22/jun mas você é o único caixa do turno noturno"

### 2.7 Métricas operacionais específicas varejo

- **Headcount líquido por loja** (não só total · sazonalidade comum: dezembro picos)
- **Custo médio por loja vs receita da loja** (precisa cruzar dado ERP venda)
- **Turnover de caixa** (alta no varejo — geralmente > 80% a.a.)
- **Tempo médio de promoção repositor → frente de caixa → sênior → gerente**
- **% de promoções internas (vs contratação externa)** — saúde de carreira

---

## 3. UI · 3 telas novas

### 3.1 `r2_people_quadro_multiloja.html` (gerente regional)

Persona: Carla Reis · Coord Logística · 5 lojas.

- Hero: 4 KPIs agregados (headcount total, ativos hoje, absent médio, turnover 90d)
- Tabela 5 lojas c/ semáforo health + ações
- Drill-down: click linha abre painel da loja
- Filtros: período, função, status

### 3.2 `r2_people_quadro_honra.html` (mural público interno)

Persona: todos do tenant.

- Hero com **vencedores do mês atual** em destaque (5 categorias, cards grandes c/ avatares)
- Hall of Fame · arquivo navegável por mês/ano
- Filtros: loja, categoria
- Botão "Parabenizar" (dispara reconhecimento público via mural)

### 3.3 `r2_people_trilhas_funcao.html` (RH + colaborador)

Persona: dual (gestor RH gerencia · colaborador faz)

Modo gestor:
- Lista trilhas configuradas
- % conclusão por função/loja
- Bottlenecks (módulo X tem queda)
- + Nova trilha

Modo colaborador:
- "Sua trilha · 60% concluída"
- Próximo módulo destacado
- Progresso visual
- Certificados conquistados

---

## 4. Schema (extensões)

```sql
-- Trilhas operacionais (diferente de compliance_trainings que é NR)
CREATE TABLE IF NOT EXISTS operational_tracks (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id       uuid NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  code            text NOT NULL,
  name            text NOT NULL,
  description     text,
  target_function text NOT NULL,                  -- 'caixa','repositor','asg','vigilante',etc
  total_hours     numeric,
  validity_months int,
  active          boolean DEFAULT true,
  UNIQUE (tenant_id, code)
);

CREATE TABLE IF NOT EXISTS operational_track_modules (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  track_id        uuid NOT NULL REFERENCES operational_tracks(id) ON DELETE CASCADE,
  name            text NOT NULL,
  description     text,
  display_order   int NOT NULL,
  video_url       text,
  pdf_url         text,
  quiz_questions  jsonb,                          -- [{q, options[], correct_idx, explain}]
  pass_score      numeric DEFAULT 70,
  estimated_minutes int
);

CREATE TABLE IF NOT EXISTS employee_track_progress (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id       uuid NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  employee_id     uuid NOT NULL,
  track_id        uuid NOT NULL REFERENCES operational_tracks(id),
  module_id       uuid NOT NULL REFERENCES operational_track_modules(id),
  started_at      timestamptz,
  completed_at    timestamptz,
  quiz_score      numeric,
  attempts        int DEFAULT 0,
  UNIQUE (employee_id, module_id)
);

-- Hall of fame · vencedores mensais
CREATE TABLE IF NOT EXISTS hall_of_fame (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id       uuid NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  category        text NOT NULL CHECK (category IN ('funcionario_mes','vendedor_mes','caixa_excelencia','repositor_mes','time_loja_mes')),
  period          text NOT NULL,                  -- '2026-05'
  branch_id       uuid,
  employee_id     uuid,                            -- NULL se category='time_loja_mes'
  score           numeric,
  reasoning       jsonb,
  awarded_at      timestamptz NOT NULL DEFAULT now(),
  UNIQUE (tenant_id, category, period, branch_id, employee_id)
);

-- Absenteísmo agregado diário por loja (refresh noturno)
CREATE TABLE IF NOT EXISTS branch_absenteeism_daily (
  tenant_id           uuid NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  branch_id           uuid NOT NULL,
  day                 date NOT NULL,
  headcount_expected  int NOT NULL,
  headcount_present   int NOT NULL,
  absent_certificate  int DEFAULT 0,
  absent_unjustified  int DEFAULT 0,
  absent_vacation     int DEFAULT 0,
  absent_dayoff       int DEFAULT 0,
  calculated_at       timestamptz DEFAULT now(),
  PRIMARY KEY (tenant_id, branch_id, day)
);

CREATE INDEX IF NOT EXISTS idx_absent_recent
  ON branch_absenteeism_daily (tenant_id, day DESC);

-- Comissões de vendas (refletido do ERP via M14)
CREATE TABLE IF NOT EXISTS sales_commissions_summary (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id       uuid NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  employee_id     uuid NOT NULL,
  period          text NOT NULL,                  -- '2026-05'
  meta_brl_cents  bigint,
  realizado_brl_cents bigint,
  comissao_brl_cents bigint,
  pct_atingimento numeric,
  rank_in_branch  int,
  rank_total_in_branch int,
  source          text DEFAULT 'erp_dominio',
  synced_at       timestamptz DEFAULT now(),
  UNIQUE (employee_id, period)
);
```

---

## 5. RPCs principais

```sql
rpc_branch_panel(p_tenant_id uuid, p_branch_id uuid)
  RETURNS TABLE (headcount, ativos_hoje, absent_pct_mes, turnover_90d, pending_actions, health)

rpc_multibranch_panel(p_user_id uuid)
  -- Lojas das quais o usuário é gerente regional
  RETURNS TABLE (branch_id, name, headcount, ativos_hoje, absent_pct, turnover, pending, health)

rpc_calculate_hall_of_fame(p_tenant_id uuid, p_period text)
  -- Roda mensalmente (cron · primeiro dia do mês)
  RETURNS int -- nº de prêmios calculados

rpc_employee_track_progress(p_employee_id uuid)
  RETURNS TABLE (track_name, total_modules, completed, pct, next_module_id, last_activity_at)

rpc_branch_absent_realtime(p_tenant_id uuid, p_branch_id uuid)
  -- Snapshot tempo real (usado por alertas)
  RETURNS TABLE (expected, present, absent_now, by_function jsonb)
```

---

## 6. Integrações cruzadas

| Spec | Como M21 usa |
|---|---|
| **M16 Domínio** | Reflete comissões + folha + banco horas |
| **M17 Analytics** | Turnover por loja, absent, headcount entram nos dashboards diretoria |
| **M18 Compliance** | Treinamentos NR obrigatórios + trilhas operacionais coexistem |
| **M19 Benefícios** | Comissão influencia mediana salarial agregada |
| **M20 Inbox Líder** | Alertas absenteísmo loja entram no inbox do gerente regional |
| **M14 Webhooks inbound** | Sistema vendas → comissões; sistema ponto → absenteísmo |

---

## 7. Notificações via M12

- `branch_absent_critical` → gerente regional (cobertura abaixo do mínimo)
- `branch_health_dropped` → diretoria (loja vermelha 2 dias seguidos)
- `hall_of_fame_calculated` → todo tenant (vencedores do mês)
- `track_module_completed` → colaborador (parabéns + próximo)
- `track_completed` → líder + colaborador
- `commission_milestone_50_75_100_pct` → colaborador

---

## 8. Mobile-first (operacional varejo)

Trilhas + comissão + escala precisam **funcionar bem no celular** porque chão de loja não tem desktop. Considerações:

- Vídeos curtos (< 15min · permitir entre atendimentos)
- Quiz com toque (botões grandes, sem scroll horizontal)
- Comissão consulta rápida (3 toques: app → comissão → resultado)
- Notificação push de absent crítica (gerente regional precisa ver em 30s)

---

## 9. Testes meta (mínimo 20)

- ✓ Quadro multi-loja só mostra lojas do gerente regional
- ✓ Drill-down loja abre painel correto
- ✓ Absent realtime atualiza < 1min após mudança
- ✓ Hall of fame calculado mensal automaticamente
- ✓ Categoria sem dados (vendedor sem ERP) mostra "n/a"
- ✓ Trilha operacional permite resumo (resume from last module)
- ✓ Quiz < 70% bloqueia próximo módulo
- ✓ Certificado interno gerado em PDF
- ✓ Comissão consulta só do próprio colaborador (RLS)
- ✓ Ranking só mostra posição, não valor de outros
- ✓ Escala importada via M14 não duplica
- ✓ Alerta cobertura crítica dispara push em < 30s
- ✓ Health da loja calculado em batch noturno
- ✓ Carla Reis (Coord ATP) vê 5 lojas, não 14
- ✓ Patrícia Mello (Coord RH GPC) vê todas (override)
- ✓ Funcionário do mês cálculo respeita absent < 5%
- ✓ Histórico Hall of Fame navega por ano/mês
- ✓ Trilha por função vincula automático no admission_date
- ✓ Mudança de função (movement) dispara nova trilha sugerida
- ✓ Mobile: trilha completa em < 30min total mostra OK em 4G

---

## 10. Roadmap pós-MVP

1. **M+3 · gamificação leve** (badges, levels, XP) — opcional · alguns clientes adoram, outros odeiam
2. **M+6 · benchmark intra-loja** (anônimo · "sua loja vs média da rede")
3. **M+9 · predição absenteísmo** (ML por loja + sazonalidade)
4. **M+12 · sugestão de escala** (otimização considerando férias + cobertura)
5. **M+18 · vitrine pública opt-in** ("conheça nosso time" externa)
6. **M+24 · trilhas em parceria SENAI/SENAC** (cliente compra cursos via R2 marketplace)

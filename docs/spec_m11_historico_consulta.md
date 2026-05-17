# Spec · M11 · Histórico de consulta (search-driven UI)

**Status:** RPCs principais já existem no schema v4 (`rpc_search_employees`, `rpc_get_employee_history`) · falta UI completa
**Pré-requisitos:** M1 (Estrutura), M3 (Atestados) idealmente aplicados · todos os módulos backend pra ter histórico real
**Estimativa:** 1 sessão (~4-5h)

---

## 1. Objetivo

Implementar a tela de **Histórico de Consulta** · interface search-driven estilo Linear/Raycast/Cmd-K que permite a um líder/RH:
1. Buscar qualquer colaborador por nome, apelido, matrícula, CPF
2. Ver timeline unificada com TODOS os eventos do colaborador (admissão, movimentações, férias, atestados, avaliações, feedbacks, treinamentos, faltas)
3. Filtrar por categoria
4. Respeitar RLS (vê só o que o caller tem permissão)

| Tela origem | Página Next.js |
|---|---|
| `r2_people_historico_consulta.html` | `/historico` |

---

## 2. Por que essa tela é importante

O histórico unificado responde uma pergunta crítica em qualquer empresa: **"o que aconteceu com a Fulana nos últimos N meses?"**

Hoje no GPC essa pergunta é respondida abrindo:
- Excel A (cadastro)
- Excel B (folha)
- Pasta digital de atestados
- Email histórico
- Memória da Karla

Levando em média 20+ minutos por consulta. Com essa tela: 5 segundos.

Casos de uso reais:
- **Líder** preparando 1:1 quer ver eventos recentes do liderado
- **RH** analisando demissão precisa ver histórico de movimentações
- **DP** investigando absenteísmo precisa ver atestados + faltas
- **Diretoria** olhando colaborador pra eventual promoção

---

## 3. Schema · sem mudanças necessárias

A RPC `rpc_get_employee_history(p_user_id, p_categories[], p_year_from, p_year_to)` já existe no schema v4 (`r2_people_schema_v4.sql`).

Faz `UNION ALL` de 8 fontes:
- `app_users.hired_at` (admissão)
- `movements` (kind in promotion/transfer/salary_adjustment/etc.)
- `vacation_periods` (status='completed' ou 'in_progress')
- `medical_certificates` (status='validated' · sem CID na listagem)
- `evaluations` (status='finalized' · com score final)
- `recognitions` (recebidos · respeitando is_private)
- `training_enrollments` (status='completed')
- `pdis` (status='closed' · com resultado)

E retorna lista de eventos unificados:

```json
[
  {
    "event_id": "uuid",
    "category": "movement",
    "kind": "promotion",
    "date": "2025-10-15",
    "title": "Promoção · Analista Pleno",
    "description": "De Analista Jr para Analista Pleno · salário R$ 3.500 → R$ 5.500",
    "actor_name": "João Carvalho",
    "actor_role": "Líder Financeiro",
    "color": "green",
    "icon": "TrendingUp",
    "payload": { "from_role": "...", "to_role": "...", "salary_delta": 2000 }
  },
  ...
]
```

CID e dados médicos só retornam se caller tem `view_medical_cid`.

### Ajustes opcionais

Adicionar:

```sql
-- migration: 00490_m11_consulta_audit.sql

-- Registro de quem viu o histórico de quem (LGPD)
CREATE TABLE history_views (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id       UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,

  viewer_id       UUID NOT NULL REFERENCES app_users(id),
  target_id       UUID NOT NULL REFERENCES app_users(id),

  categories      TEXT[],                              -- categorias filtradas na visualizacao
  year_from       INT,
  year_to         INT,

  -- IP e user agent pra audit pesado
  ip_address      INET,
  user_agent      TEXT,

  viewed_at       TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_history_views_viewer ON history_views(viewer_id, viewed_at DESC);
CREATE INDEX idx_history_views_target ON history_views(target_id, viewed_at DESC);
```

Cada chamada de `rpc_get_employee_history` registra automaticamente em `history_views`.

---

## 4. RPCs (já existentes · ajustes mínimos)

```sql
-- Já existe no schema v4 · ajustar pra registrar audit:

CREATE OR REPLACE FUNCTION rpc_get_employee_history(
  p_user_id UUID,
  p_categories TEXT[] DEFAULT NULL,
  p_year_from INT DEFAULT NULL,
  p_year_to INT DEFAULT NULL
) RETURNS JSONB AS $$
DECLARE
  v_caller app_users;
  v_target app_users;
BEGIN
  -- ... (logica existente) ...

  -- NOVO: registrar visualizacao
  INSERT INTO history_views (tenant_id, viewer_id, target_id, categories, year_from, year_to)
    VALUES (v_caller.tenant_id, v_caller.id, p_user_id, p_categories, p_year_from, p_year_to);

  -- ... (retorno) ...
END; $$;

-- Busca inteligente (ja existe):
CREATE OR REPLACE FUNCTION rpc_search_employees(p_query TEXT, p_limit INT DEFAULT 10)
RETURNS JSONB ...;
-- Priorizacao por relevancia:
-- 100 pts: match exato em apelido
-- 90 pts:  prefix match em apelido
-- 85 pts:  match exato em matricula
-- 80 pts:  match exato em CPF
-- 70 pts:  prefix match em nome completo
-- 50 pts:  contains em nome
-- 30 pts:  FTS portugues com unaccent

-- Registrar view recente (alimenta "Vistos recentemente")
CREATE TABLE IF NOT EXISTS recent_employee_views (
  user_id         UUID NOT NULL,
  subject_id      UUID NOT NULL,
  viewed_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, subject_id)
);

CREATE OR REPLACE FUNCTION rpc_register_employee_view(p_subject_id UUID)
RETURNS JSONB AS $$
  -- UPSERT em recent_employee_views
  -- Mantém max 20 por usuário (delete os antigos)
$$;

CREATE OR REPLACE FUNCTION rpc_my_recent_views(p_limit INT DEFAULT 8)
RETURNS JSONB AS $$
  -- Retorna os últimos N consultados pelo caller
$$;
```

---

## 5. Página Next.js · `/historico`

Referência: [r2_people_historico_consulta.html](../r2_people_historico_consulta.html)

### Layout

```
+----------------------------------------------------------+
| Topbar com search autocomplete (grande, centralizado)    |
|  [🔍 Buscar Fernanda, @Fê, matrícula 0024...]            |
+----------------------------------------------------------+

Quando vazio:
+----------------------------------------------------------+
| ✨ Vistos recentemente (8 últimos · cards)              |
|  [Fernanda Lima] [João Carvalho] [Daniela Pereira] ...   |
+----------------------------------------------------------+

Quando busca tem resultados:
+----------------------------------------------------------+
| Resultados (4 matches, ordenados por relevância)         |
| → [João Pedro Silva @JP] · Analista Sênior · Cestão L1   |
| → [João Carvalho]        · Líder Financeiro · GPC        |
| → [João Vitor Mendes]    · Estagiário · CD Inhambupe     |
| → [Maria João Costa @Maju] · Operadora · Cestão Loja 1   |
+----------------------------------------------------------+

Quando clica em alguém:
+----------------------------------------------------------+
| Header do colaborador                                    |
|  [Avatar] Fernanda Lima · @Fê                            |
|  Analista Pleno · Cestão L1 · 4 anos de casa             |
|  EMP: Labuta · TOM: Cestão L1                            |
+----------------------------------------------------------+
| KPIs rápidos (6 cards)                                   |
|  [Atestados] [Férias] [Avaliações] [PDIs] [1:1s] [Recog.]|
+----------------------------------------------------------+
| Filtros: [Todas] [Admissão] [Movimentações] [Férias]     |
|          [Atestados] [Avaliações] [Treinos] [PDIs]       |
+----------------------------------------------------------+
| Timeline agrupada por ano                                |
|                                                          |
| 📅 2026                                                   |
|  ├─ Mai/2026 · Avaliação 9-Box · Box 5 (Core)           |
|  ├─ Abr/2026 · PDI iniciado · "Pleno → Sênior"          |
|  ├─ Mar/2026 · Promoção · Jr → Pleno · +R$ 2.000        |
|  └─ Jan/2026 · Treinamento · Power BI · concluído       |
|                                                          |
| 📅 2025                                                   |
|  ├─ Out/2025 · Avaliação 9-Box · Box 5                  |
|  ├─ Jul/2025 · Férias · 15 dias                         |
|  ├─ Mai/2025 · Reconhecimento de Patrícia               |
|  └─ Fev/2025 · Atestado · 3 dias afastado               |
|                                                          |
| 📅 2024 (admissão)                                       |
|  └─ Mar/2024 · Admissão · Analista Jr · Cestão L1       |
+----------------------------------------------------------+
```

### Comportamentos

- **Autocomplete debounced** (300ms) chama `rpc_search_employees`
- **Toggle de persona** no topo demonstra RLS ao vivo (Patrícia/João/Larissa)
- **Cards de "Vistos recentemente"** alimentados por `rpc_my_recent_views`
- **Highlight** das letras da query nos nomes dos resultados
- **Filtros por categoria** chama RPC com `p_categories` filtrado
- **Tooltip** em cada evento mostra payload detalhado
- **Export** PDF do histórico (button discreto canto direito)

---

## 6. Privacy enforcement

A tela já respeita RLS por design (RPC `SECURITY INVOKER`). Mas atenção a 3 pontos:

### 6.1 CID nunca aparece em listagem

Mesmo na timeline do próprio colaborador, eventos de tipo `medical_certificate` mostram:
- Título: "Atestado · 3 dias"
- **NÃO** mostram: CID, médico, descrição

Pra ver CID, precisa baixar o PDF (que tem audit log separado).

### 6.2 Reconhecimentos privados respeitados

Filtro de `is_private`:
- Se reconhecimento é privado: só aparece se caller é sender OU recipient OU rh/diretoria/dpo
- Outros leem o evento como "Reconhecimento (privado)" sem detalhes

### 6.3 1:1s não aparecem nesta tela

Por design · 1:1s tem privacy enforcement próprio (ver `r2_people_privacy_oneonones.md`). Não fazem parte do histórico unificado.

---

## 7. Audit log

A tabela `history_views` registra cada consulta. Útil para:

- **DPO** monitorar quem está consultando histórico de quem (LGPD Art. 18)
- **Detectar comportamento anômalo** (líder consultando colaboradores fora do seu escopo)
- **Compliance trail** em caso de auditoria externa

Query exemplo:

```sql
-- Quem consultou meu histórico nos últimos 30 dias?
SELECT
  viewer_id,
  au.full_name AS viewer_name,
  COUNT(*) AS views,
  MAX(viewed_at) AS last_view
FROM history_views hv
JOIN app_users au ON au.id = hv.viewer_id
WHERE hv.target_id = '<me>'
  AND hv.viewed_at > now() - INTERVAL '30 days'
GROUP BY 1, 2
ORDER BY last_view DESC;
```

Esse query pode ser exposto pro próprio colaborador via DSAR.

---

## 8. Testes · `supabase/tests/00490_m11_historico.sql`

Meta: 20+ testes:

1. Search por apelido prioriza exato > prefix > contém
2. Search por matrícula match exato pontua alto
3. Histórico unificado retorna eventos de todas as fontes
4. CID NÃO aparece em listagem mesmo pro próprio colaborador
5. Reconhecimento privado escondido pra terceiros não autorizados
6. RLS: líder vê só sua subárvore
7. RLS: RH vê todos do tenant
8. RLS: colaborador vê só si mesmo
9. Cross-tenant blocked
10. history_views é populado a cada consulta
11. Filtro por categoria funciona
12. Filtro por ano funciona
13. recent_employee_views mantém max 20
14. rpc_my_recent_views ordena por viewed_at DESC
15-20: edge cases (colab demitido, sem eventos, etc.)

---

## 9. Critérios de aceitação

- [ ] Migration 00490 aplica (apenas tabelas auxiliares de audit)
- [ ] 20+ testes passando
- [ ] Página `/historico` funcional com autocomplete
- [ ] Toggle de persona demonstra RLS visualmente
- [ ] Vistos recentemente (cards de até 8)
- [ ] Timeline agrupada por ano
- [ ] Filtros por categoria
- [ ] Export PDF do histórico
- [ ] Audit log de consultas registrado
- [ ] Adapter `src/lib/r2/history.ts`
- [ ] Doc da sessão em `docs/sessao_m11.md`

---

## 10. Pontos de atenção

- **Performance**: `rpc_get_employee_history` faz UNION ALL de 8 tabelas · cuidar de índices (`idx_*_employee_date` em cada tabela)
- **CID em produção**: triplo check · listagem NUNCA mostra CID, mesmo pra DP (só ao baixar PDF)
- **Audit log pode pesar**: limitar retenção a 1 ano (histórico antigo agregado em estatística)
- **DSAR**: implementar RPC `rpc_my_view_history` pro próprio colaborador ver quem o consultou (LGPD Art. 18)
- **Cache no client**: cachear `rpc_my_recent_views` em sessionStorage (TTL 5min)
- **Highlight da query**: usar `<mark>` em vez de `<strong>` (semântica correta + estilizável)
- **Autocomplete dropdown**: capturar Esc, ArrowUp/Down, Enter (igual ao search global do shell)

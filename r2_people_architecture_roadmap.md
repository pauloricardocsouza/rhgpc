# R2 People · Documento de Arquitetura e Roadmap de Implementação

> **Versão:** 1.0
> **Data:** 27 de abril de 2026
> **Autor:** Ricardo Silva (R2 Soluções Empresariais)
> **Status:** Aprovado para execução
> **Audiência:** time técnico interno + co-desenvolvedores futuros + parceiros estratégicos

---

## Sumário executivo

O **R2 People** é uma plataforma SaaS de gestão de pessoas focada em **avaliação de desempenho, feedback contínuo e reconhecimento público**, projetada desde a fundação para suportar empresas com **estruturas reais brasileiras**, em particular grupos com forte uso de terceirização e múltiplos empregadores operando em filiais comuns.

O diferencial técnico é o modelo de **vínculo triplo** (empregador × tomador × departamento) materializado em todas as camadas · schema, RLS, RPC, UI · permitindo análises e operações que sistemas convencionais não conseguem expressar.

Este documento descreve a arquitetura escolhida, o roadmap de implementação em 4 fases ao longo de 14 a 16 semanas, dependências críticas, riscos identificados, estimativa de custo de operação e métricas de sucesso.

A estratégia comercial é **híbrida e gradual**: começar como produto interno do GPC e HEC (clientes existentes da R2), validar e refinar em produção real, e a partir do quarto trimestre iniciar oferta comercial para PMEs varejistas brasileiras.

---

## 1. Contexto e motivação

### 1.1 Cenário de mercado

Os principais produtos brasileiros de gestão de pessoas (Sólides, Qulture.Rocks, Feedz, TeamCulture) são excelentes em avaliação clássica e feedback, mas todos partem do pressuposto de que **um colaborador trabalha em uma empresa** com uma única hierarquia, um único CNPJ pagador, e uma única filial. Essa premissa cobre 70 a 80 por cento dos casos urbanos formais, mas **falha completamente em três contextos brasileiros muito comuns**:

1. **Varejo de médio porte com terceirização** · supermercados, atacadistas, redes de moda e materiais de construção tipicamente terceirizam até 80 por cento da operação de loja (caixas, repositores, açougueiros, padeiros, vigilantes, limpeza). O colaborador trabalha no espaço físico da loja, segue regras da loja, mas é empregado formal de uma prestadora de serviços externa.
2. **Hospitais e instituições de saúde** · o staff médico, de enfermagem e administrativo é frequentemente vinculado a OS (Organizações Sociais), cooperativas ou prestadoras especializadas, ainda que opere fisicamente dentro do hospital público.
3. **Construção civil e indústria** · operários terceirizados, contratos por obra, estruturas de empreiteiras dentro de canteiros.

Nesses cenários, o RH operacional do tomador (loja, hospital, canteiro) precisa **avaliar pessoas que não são empregados dele**, enquanto o RH do empregador (prestadora) precisa de visibilidade dos seus 200, 500 ou 1000 funcionários distribuídos em 5 a 15 tomadores diferentes. Os sistemas existentes resolvem isso com gambiarras: planilhas paralelas, múltiplas instâncias do mesmo software, ou simplesmente ignorando a complexidade.

### 1.2 Validação inicial

A R2 Soluções já entrega serviços de business intelligence e automação para o **Grupo Pinto Cerqueira (GPC)**, conglomerado regional de supermercados na Bahia (367 colaboradores, 14 unidades, brands ATP-Varejo, ATP-Atacado, Cestão L1, Cestão Inhambupe), e para o **Hospital Estadual da Criança (HEC/LABCMI)** em Feira de Santana. Ambos enfrentam diariamente a dor descrita acima e são os clientes-piloto naturais do produto.

O GPC opera com **3 prestadoras principais**: Labuta (247 colaboradores), Limpactiva (38) e Segure (22), distribuídos em 7 lojas. Hoje, gerentes de loja avaliam terceirizados em planilhas Excel separadas que ninguém consolida, RH da Labuta não vê o histórico de avaliações dos próprios funcionários porque tudo fica fragmentado entre as lojas tomadoras, e os colaboradores terceirizados sentem-se invisíveis no processo.

### 1.3 Hipótese de produto

Construir um sistema onde:

- O modelo de dados **separa fundamentalmente** empregador (CNPJ que paga) de tomador (filial onde trabalha) de departamento (área funcional), e essa separação é mantida em **todas as camadas** (schema, segurança, relatórios, UI).
- Cada relatório oferece um **toggle dinâmico EMP ↔ TOM** que faz a mesma análise pelos dois eixos: "tudo da Labuta em qualquer filial" vs "tudo da Cestão L1 com qualquer empregador".
- Perfis de acesso são **multidimensionais**: o RH da Labuta vê 247 pessoas de qualquer filial; o gerente de Cestão L1 vê 91 pessoas de qualquer empregador; o coordenador GPC corporativo vê tudo. As regras se compõem por interseção, não por exceções.
- A LGPD é **arquitetural, não documental**: trilha de auditoria imutável, direito de acesso pelo próprio colaborador (DSAR Art. 18), retenção por base legal, anonimização programada após desligamento.

Validar essas hipóteses internamente em 2 clientes durante 4 a 6 meses antes de oferecer comercialmente.

---

## 2. Decisões arquiteturais

### 2.1 Multitenancy

**Decisão**: tenant compartilhado com isolamento por `company_id` em todas as tabelas, garantido por RLS.

**Alternativas consideradas e rejeitadas**:

- *Database por tenant* · over-engineering para o porte alvo (PMEs). Custo operacional de migração e manutenção desproporcional ao ganho marginal de isolamento.
- *Schema por tenant* (Postgres `schema`) · viável mas cria complexidade em queries cross-tenant para o time R2 (analytics, suporte) e dificulta upgrade de schema síncrono.

**Tenant compartilhado** com `company_id` em cada tabela e RLS bloqueando vazamento entre tenants é o equilíbrio certo: isolamento forte (RLS é defesa em profundidade), simplicidade operacional (uma única migração serve todos), custo proporcional ao uso.

### 2.2 Modelo de dados de unidades

**Decisão**: tabela única `units` polimórfica com `role` enum (`administrative` | `operational` | `service_provider`) e `parent_id` self-referencial.

A separação entre lojas operacionais (Cestão L1, ATP-Varejo) e prestadoras (Labuta, Limpactiva) acontece **pelo `role`**, não por tabelas separadas. Isso permite que `user_companies.employer_unit_id` aponte tanto para uma prestadora quanto para a matriz GPC (no caso de empregados próprios), sem precisar de FKs alternativas ou union types.

### 2.3 Segurança em 4 dimensões

**Decisão**: implementar `permission_profiles` com 4 escopos independentes:

| Dimensão | Modos | Origem do escopo |
|---|---|---|
| `employer_scope` | all, specific, self, none | tabela `profile_employer_scope` |
| `unit_scope` | all, specific, self, none | tabela `profile_unit_scope` |
| `department_scope` | all, specific, self, none | tabela `profile_department_scope` (com flag `recursive` para sub-deptos) |
| `hierarchy_scope` | all, recursive, direct, self, none | calculado em runtime via CTE recursiva sobre `manager_user_id` |

A função-master `can_see_user_company(target_user, target_emp, target_tom, target_dept)` aplica AND lógico entre as 4 dimensões, com 3 atalhos para curto-circuito (self, override, hierarchy). Documentada em `r2_people_rls_policies_detailed.sql`.

A escolha foi entre **dimensões fixas** (4 colunas como acima) e **dimensões abertas** (tabela `profile_scopes` com `dimension` enum livre). Optei pelo modelo fixo porque as 4 dimensões mapeiam perguntas reais de produto, e adicionar uma 5ª dimensão (ex: linha de produto) seria mudança consciente, não emergência.

### 2.4 Avaliação como entidade flexível

**Decisão**: `reviews` modela qualquer tipo de avaliação (auto, gestor, par, 360, líder por liderado) via coluna `kind`, com `evaluator_id` e `evaluatee_id` separados. `review_answers` armazena as notas por competência, e `nine_box_positions` é desacoplada para permitir 9-Box sem ter que ser a mesma tabela.

Essa separação permite que no MVP suportemos apenas `kind IN ('self', 'manager')` e na fase 2 ativemos `peer` e `360` apenas adicionando tipos enum, sem migração de schema.

### 2.5 Workflow de movimentações

**Decisão**: `personnel_movements` com máquina de estados explícita (`draft → pending_manager → pending_hr → approved | rejected | canceled`), tabela `personnel_movements_approvals` para registrar cada decisão (quem, quando, comentário), e trigger pós-aprovação que atualiza `user_companies` automaticamente.

A separação entre **solicitar** (escrever em `personnel_movements`) e **efetivar** (atualizar `user_companies`) é deliberada · permite auditoria precisa de "quem decidiu o quê" e suporta workflows multi-etapa (ex: Labuta + GPC) sem ter que rodar update direto na tabela final.

### 2.6 RPC sobre views diretas

**Decisão**: relatórios complexos via funções RPC (`rpt_*`) em vez de queries diretas a views.

Justificativa em três pontos:

1. **Parametrização rica** · toggle EMP↔TOM, filtros multidimensionais, ranges de data são naturais como argumentos de função.
2. **Curto-circuito de RLS** · funções com `SECURITY DEFINER` aplicam validação no início (uma vez), ao invés de o planner executar o predicado RLS em cada linha de uma view.
3. **Versionabilidade** · alterar a fórmula de turnover ou de salary distribution é alterar uma função; não obriga o frontend a refazer queries.

### 2.7 Stack: Supabase, Next.js, Vercel

**Decisão**: backend em Supabase (Postgres + RLS + Auth + Realtime + Storage), frontend em Next.js 14 com App Router, deploy na Vercel.

A escolha do Supabase é fortemente influenciada pelo perfil técnico da R2 (forte em SQL, forte em modelagem relacional, forte em BI). Substituir por Firebase ou similar exigiria reaprender padrões e perder superpoderes do Postgres (CTEs recursivas, RLS expressivo, triggers, índices funcionais). A escolha do Next.js é por familiaridade do desenvolvedor e ecossistema maduro de componentes (shadcn, lucide, recharts) que casam com o design system já desenhado nos protótipos HTML.

A escolha da Vercel é praticidade: deploy zero-config, edge functions para regras leves de redirect e healthcheck, observabilidade integrada. Para o porte alvo (até alguns milhares de usuários por tenant), o custo é desprezível e a operação é praticamente automática.

---

## 3. Stack tecnológico detalhado

```
┌─────────────────────────────────────────────────────────┐
│                       Frontend                           │
│                                                          │
│  Next.js 14 (App Router)  +  React 18  +  TypeScript    │
│  Tailwind CSS 3 (no JIT)  +  shadcn/ui                  │
│  Chart.js 4 (charts)  +  lucide-react (ícones)          │
│  React Query (server state)  +  Zustand (UI state)      │
│  @supabase/supabase-js + @supabase/auth-helpers-nextjs  │
│                                                          │
│  Deploy: Vercel (Edge Network global)                    │
└─────────────────────────────────────────────────────────┘
                          ↕ HTTPS
┌─────────────────────────────────────────────────────────┐
│                 Supabase (BaaS Postgres)                 │
│                                                          │
│  PostgreSQL 15  (~5GB inicial, escalável)                │
│  ├── 28 tabelas (schema v3)                              │
│  ├── 11 funções RPC (report builder)                     │
│  ├── 35+ policies RLS multidimensionais                  │
│  ├── Triggers de auditoria + timestamps                  │
│  └── 2 views materializadas (matrizes pesadas)           │
│                                                          │
│  Auth   (JWT + email/password + Microsoft SSO)           │
│  Realtime (broadcast praises + notifications)            │
│  Storage (avatares, anexos PDI, exports)                 │
│  Edge Functions (cron de notificações, healthcheck)      │
└─────────────────────────────────────────────────────────┘
                          ↕
┌─────────────────────────────────────────────────────────┐
│                 Integrações futuras                      │
│                                                          │
│  TOTVS WinThor (ERP do GPC)  →  REST API                 │
│  eSocial (futuro, fase 4)   →  XML SOAP                 │
│  Microsoft Entra (SSO)      →  OAuth 2.0                │
│  WhatsApp Business API       →  Notificações (fase 3)    │
└─────────────────────────────────────────────────────────┘
```

### 3.1 Justificativa das bibliotecas-chave

| Biblioteca | Versão | Justificativa |
|---|---|---|
| `@supabase/auth-helpers-nextjs` | latest | Integra Supabase Auth com Next.js Middleware para session check em routes |
| `@tanstack/react-query` | 5.x | Cache de server state, refetch on focus, background sync |
| `zustand` | 4.x | UI state leve sem boilerplate Redux (menus abertos, temas, modais) |
| `tailwindcss` | 3.x JIT | Design system já implementado nos protótipos HTML, fácil de portar |
| `chart.js` | 4.x | Já validado nos protótipos do GPC (dashboards de faturamento) |
| `papaparse` | 5.x | Parser de CSV robusto com encoding detection (importação) |
| `dayjs` | 1.x | Datas em PT-BR, timezone Bahia, lighweight (vs moment) |
| `zod` | 3.x | Validação runtime + tipos inferidos (forms, RPC inputs) |
| `react-hook-form` | 7.x | Formulários performáticos (avaliação tem 8 competências × 2 sliders) |

### 3.2 Convenções de projeto

- **Estrutura de pastas**: `app/` (rotas Next), `components/` (UI reutilizável), `lib/` (helpers, supabase client), `hooks/` (custom hooks), `types/` (Database type from Supabase CLI), `tests/` (Playwright E2E + Vitest unitário).
- **Tipos**: `database.types.ts` gerado automaticamente via `supabase gen types typescript` em CI. Frontend nunca cria tipos manualmente para entidades de DB.
- **Nomenclatura**: snake_case no DB, camelCase no TypeScript, conversão automática na borda (ex: `user_companies` → `userCompanies` na props de componente).
- **Mensagens em PT-BR**: arquivo único `lib/messages.ts` com chaves padronizadas. I18n estruturado fica para fase 4 quando houver demanda.
- **Commits**: convenção Conventional Commits (`feat:`, `fix:`, `chore:`, `refactor:`) para gerar changelog automático.

---

## 4. Roadmap em 4 fases

O MVP é dividido em 4 fases sequenciais, cada uma encerrada com **gate de validação** antes de avançar. Cada fase tem entregáveis claros, critérios de aceite e dependências mapeadas. As fases somam **14 a 16 semanas** de trabalho focado.

### Fase 1: Fundação técnica (semanas 1 a 4)

**Objetivo**: estabelecer a infraestrutura, schema, autenticação, multi-tenant e estrutura organizacional. Ao final desta fase, deve ser possível um administrador logar, criar a estrutura da empresa e cadastrar colaboradores.

**Entregáveis**:

- Provisão Supabase + projeto Vercel + repositório GitHub com CI básico (lint + typecheck)
- Aplicação completa do `r2_people_schema_v3.sql` em ambiente de produção
- Aplicação do `r2_people_seed_initial.sql` populando o tenant GPC
- Aplicação das `r2_people_rls_policies_detailed.sql` com testes manuais via `my_visibility_summary()`
- Implementação do fluxo de **login + onboarding** (telas já prototipadas em HTML)
- Implementação de **CRUD da estrutura organizacional** (filiais, departamentos, cargos)
- Implementação da **listagem de colaboradores** com filtros multidimensionais
- Implementação do **cadastro/edição de colaborador** (5 abas)
- Pipeline de tipo automático: `supabase gen types` rodando em CI

**Critérios de aceite**:

1. Patrícia Mello (RH GPC) consegue logar, criar uma nova filial, criar um novo cargo, e cadastrar um colaborador novo sem ajuda técnica
2. RLS efetiva: Fernanda Lima (colaboradora) só vê o próprio perfil; tentativas de acesso a `/colaboradores` retornam 403
3. Larissa Pereira (RH Labuta) só vê os 247 colaboradores da Labuta na listagem, em qualquer filial
4. Função `my_visibility_summary()` retorna valores coerentes para os 6 cenários documentados em `rls_policies_detailed.sql`
5. Carga de tipos < 200ms (TTI inicial), Lighthouse score > 85 em mobile

**Dependências críticas**:

- Acesso ao projeto Supabase em região São Paulo (sa-east-1) ativo
- Domínio `dash.solucoesr2.com.br` apontando corretamente para Vercel
- SSL/TLS configurado em todos os subdomínios

**Estimativa de esforço**: 160h (4 semanas × 40h)

**Risco principal**: complexidade das policies RLS pode exigir iterações de tuning. Mitigação: começar com policies mais permissivas e ir restringindo, sempre com testes automatizados de visibilidade.

---

### Fase 2: Avaliação e ciclos (semanas 5 a 9)

**Objetivo**: implementar o módulo de avaliação completo · ciclos, formulários, 9-Box, PDI e tela do RH para acompanhar adesão. Esta é a fase que define o valor central do produto.

**Entregáveis**:

- Implementação da tela de **Ciclos** (CRUD, wizard de criação, gerenciamento de competências por ciclo)
- Implementação do **formulário de avaliação** (auto + gestor com auto visível)
- Implementação do **9-Box matrix** com posicionamento manual + sugestão automática
- Implementação do **PDI co-construído** (objetivos com 3 origens: colaborador, gestor, RH)
- Implementação do **Dashboard RH** com 5 abas (visão geral, adesão por filial, distribuição de notas, 9-Box, líderes pendentes)
- Implementação da **home pessoal do colaborador** (cards de progresso do ciclo)
- Sistema de **notificações in-app** (sem email/whatsapp ainda) para deadlines de avaliação
- Cron job (Edge Function) que gera notificações automáticas de prazos
- Edge Function que processa **submissão de avaliação** (atualiza status, agrega scores, dispara próximo passo)

**Critérios de aceite**:

1. Patrícia Mello consegue criar o ciclo 2026.2 com 8 competências, prazos definidos, e lançar para todos os 367 colaboradores em uma única ação
2. Fernanda Lima consegue fazer auto-avaliação completa pelo celular (mobile-first) em até 15 minutos
3. João Carvalho consegue avaliar 6 liderados (incluindo terceirizados Labuta) com a auto-avaliação visível como referência
4. Após submissão, scores agregados aparecem corretamente em `reviews.overall_score` (média ponderada das competências)
5. Dashboard RH mostra adesão real-time (ex: "88% dos auto-avaliações concluídas, 12% pendentes")
6. 9-Box automatic suggestion baseado em score do gestor + componente de potencial (analista preenche manualmente nessa versão)
7. Performance: tela de avaliação carrega em <1.5s mesmo com 8 competências e 2 perspectivas

**Dependências críticas**:

- Schema das tabelas `reviews`, `review_answers`, `nine_box_positions`, `cycle_competencies` aplicado e testado
- Funções RPC `rpt_review_score_distribution` e `rpt_ninebox_distribution` já validadas
- Frontend de avaliação testado em 3 dispositivos diferentes (Desktop, iPhone, Android low-end)

**Estimativa de esforço**: 200h (5 semanas × 40h)

**Risco principal**: a tela de avaliação é a mais complexa do produto (15+ campos por competência × 8 competências + comentários). Risco de UX confusa que reduz adesão. Mitigação: protótipo HTML já validado, testes de usabilidade com 3 colaboradores reais antes de release final.

**Gate de validação Fase 2**: após release, conduzir um ciclo de avaliação real com 30 colaboradores do GPC durante 2 semanas. Coletar NPS interno. Se NPS < 40, parar antes de fase 3 e iterar UX.

---

### Fase 3: Feedback contínuo, mural e movimentações (semanas 10 a 13)

**Objetivo**: ativar a camada "social" do produto que mantém engajamento entre ciclos, mais o módulo de movimentações pessoais (que conecta avaliação a decisões executivas como promoções).

**Entregáveis**:

- Implementação da tela de **Feedback Contínuo** (recebidos, enviados, solicitados, com modo anônimo)
- Implementação do **Mural de Elogios** público com reactions, valores institucionais, ranking 30d
- Implementação do **fluxo de Movimentações** (3 telas: criação pelo líder, aprovação RH, vista do colaborador)
- Trigger pós-aprovação que atualiza `user_companies` automaticamente
- Realtime subscriptions: novos praises aparecem ao vivo no mural sem refresh
- Sistema de **menções @** em comentários de feedback e justificativas
- Implementação do **Hub de relatórios** (categorizado: favoritos, headcount, custos, performance, movimentações)
- Implementação do **Report Builder** com toggle EMP↔TOM, filtros multidimensionais e exportação CSV
- Conectar todas as RPC `rpt_*` da biblioteca já construída
- Funcionalidade de exportação de relatórios em CSV e PDF (cliente-side com `pdf-lib`)

**Critérios de aceite**:

1. Sandra Gomes (Gerente Cestão L1) consegue elogiar José da Silva (Limpactiva) no mural; o elogio aparece em tempo real para todos os 367 colaboradores
2. Fernanda Lima recebe notificação in-app quando um feedback novo chega; consegue ler, reagir e responder em até 30 segundos
3. João Carvalho cria movimentação de promoção para Fernanda; ela aparece em "pending_hr" para Patrícia; após aprovação, `user_companies` é atualizada automaticamente e Fernanda vê a confirmação na tela "Minhas Movimentações"
4. Patrícia gera relatório "Headcount por filial" e troca para "Headcount por empregador" com 1 clique; ambos retornam corretamente em <2s
5. Exportação de CSV preserva acentos PT-BR, formatação de moeda BRL e datas DD/MM/AAAA
6. Mural de elogios suporta 1000+ reactions por elogio sem degradação de performance (testado com `pg_bench` localmente)

**Dependências críticas**:

- Supabase Realtime habilitado para tabelas `praises`, `praise_reactions`, `notifications`, `feedbacks`
- Implementação correta dos triggers pós-aprovação em `personnel_movements`
- Cliente do navegador suporta WebSockets (todos os browsers modernos suportam)

**Estimativa de esforço**: 160h (4 semanas × 40h)

**Risco principal**: o mural de elogios pode virar "dead letter" se não for adotado nas primeiras semanas. Cultura > tecnologia. Mitigação: campanha de seeding com Patrícia + R2 publicando 15-20 elogios reais nos primeiros 7 dias para criar massa crítica e exemplos.

**Gate de validação Fase 3**: ao fim das 4 semanas, contar quantos elogios públicos e feedbacks privados foram trocados nas últimas 2 semanas. Meta: > 60 elogios e > 80 feedbacks no GPC. Se não bater, antes de fase 4 dedicar 1 semana a iterações de UX (notificações push web, melhor onboarding social).

---

### Fase 4: Polimento, importação e launch (semanas 14 a 16)

**Objetivo**: lapidar arestas, suportar importação em massa, finalizar conformidade LGPD, treinar usuários-chave e fazer o lançamento oficial.

**Entregáveis**:

- Implementação da tela de **Importação CSV** com wizard 5 passos e dry-run
- Implementação do **Dashboard de Auditoria** (DPO Carla Moreira)
- Implementação das telas de **erro/404/403/500/offline/sessão**
- Implementação da **tela de Configurações da empresa** (6 abas, com identidade visual customizável)
- **Função de DSAR (LGPD Art. 18)** automática: colaborador clica "Exportar meus dados" e recebe ZIP com tudo
- **Anonimização programada**: Edge Function que roda diariamente e anonimiza desligados após 365 dias
- Documentação de usuário (manuais por persona: colaborador, líder, RH)
- Material de treinamento (vídeos curtos de 2-3 min cada, hosted no YouTube unlisted)
- Treinamento presencial com 5 super-usuários do GPC (key persons)
- Versionamento `v0.1.0` (RC) e `v1.0.0` (oficial)
- Página institucional `r2people.com.br` com cases (GPC e HEC após autorização)

**Critérios de aceite**:

1. Patrícia Mello consegue importar 50 novos colaboradores via CSV em <10 minutos, com dry-run mostrando 0 erros antes do commit final
2. Carla Moreira consegue gerar relatório de auditoria de 6 meses com 1 clique e exportar como PDF assinado
3. Fernanda Lima consegue fazer pedido de exportação dos próprios dados; recebe ZIP em até 24h (na prática, instantâneo)
4. Status de saúde de compliance: 100% das verificações verdes (auditoria, retenção, pseudonymização, base legal)
5. Tela de Auditoria carrega 1000+ eventos sem lag perceptível (paginação eficiente)
6. Lighthouse a11y score > 90 em todas as telas principais
7. Suporte a tradução PT-BR completo, sem strings hardcoded em inglês

**Estimativa de esforço**: 120h (3 semanas × 40h)

**Risco principal**: subestimar treinamento. Tecnologia perfeita não vale nada se o RH do cliente não consegue usar. Mitigação: treinamento começa na semana 14 (paralelo aos últimos polishings), não na semana 16.

**Gate final de release**: 95% de adesão dos 367 colaboradores do GPC ao primeiro ciclo de avaliação completo no R2 People. Sem isso, atrasar oferta comercial e investigar causa raiz da não-adesão.

---

## 5. Cronograma visual

```
                  Sem 1   Sem 5   Sem 10   Sem 14   Sem 16
                    │       │       │        │        │
Fase 1: Fundação   ████████████
Fase 2: Avaliação           ████████████████████
Fase 3: Feedback                    ████████████████
Fase 4: Polimento                            ████████████
                                              │
                                  Pilot live com GPC ↗
                                              │
                                       Launch v1.0 ↗
```

Marcos críticos:

- **Semana 4**: schema completo em produção, primeiro login funcional
- **Semana 9**: primeiro ciclo de avaliação real do GPC rodando (cobre 2026.2)
- **Semana 13**: primeiro elogio público no mural do GPC
- **Semana 16**: launch oficial v1.0, R2 People disponível para venda
- **Semana 20** (pós-MVP): primeira nova licença vendida fora do círculo R2

---

## 6. Riscos e mitigações

### 6.1 Riscos técnicos

| Risco | Probabilidade | Impacto | Mitigação |
|---|---|---|---|
| RLS policies geram performance ruim em listagem grande | Média | Alto | Materialized view diária com flags pré-computados; closure table para hierarchy se necessário |
| Realtime do Supabase fica sobrecarregado com muitos elogios simultâneos | Baixa | Médio | Throttle no client (max 1 update/s por usuário); fallback a polling 30s se WS falhar |
| Importação de CSV com encoding errado (UTF-8 vs Latin1) | Alta | Baixo | Detection automática + dry-run obrigatório + preview ANTES do commit |
| Migration de schema quebra dados existentes em produção | Baixa | Crítico | Migrations versionadas em SQL puro; ambiente de staging idêntico; backup pré-deploy automático |
| Custo Supabase explode além do planejado | Baixa | Médio | Pricing tier Pro (25 USD/mês) suporta até 100k MAU; monitoramento mensal |

### 6.2 Riscos de produto

| Risco | Probabilidade | Impacto | Mitigação |
|---|---|---|---|
| Adesão ao mural baixa (<20 elogios/mês no GPC) | Média | Alto | Campanha de seeding 7 dias; gamificação leve (rankings); reconhecimentos acumulam pontos no perfil |
| Líderes resistem a fazer avaliações no mobile | Baixa | Médio | UI desktop-first para avaliação completa, mobile para review pontual |
| Modelo de duplo eixo confunde RH operacional | Média | Médio | Onboarding focado, glossário inline, vídeos de 2 min explicando "empregador vs tomador" |
| Interface intimida estagiários e operacionais | Baixa | Alto | Onboarding gradual, persona "colaborador" testada com Gabriel Pinto real |

### 6.3 Riscos comerciais

| Risco | Probabilidade | Impacto | Mitigação |
|---|---|---|---|
| GPC e HEC esperam customizações específicas que viram débito técnico | Alta | Médio | Contrato firmou que customizações vão para roadmap geral, não branch específico |
| Concorrentes (Sólides) reagem com cópia do modelo de duplo eixo | Baixa | Alto | Ganhar tração rápida em 2-3 PMEs antes; diferencial não é o modelo isolado, é a integração com BI já oferecida pela R2 |
| Vendas para PMEs leva mais tempo que esperado (ciclo médio 90 dias) | Alta | Médio | Não depender de receita de venda no Q4 2026; financiar fase 5 com base nos 2 clientes pilotos |

---

## 7. Estimativa de custo operacional

### 7.1 Custo de infraestrutura mensal (em produção, pós-launch)

| Item | Custo USD | Custo BRL (aproximado) | Notas |
|---|---|---|---|
| Supabase Pro (1 projeto) | 25.00 | 130.00 | Suporta até 8GB DB, 500GB egress, 100k MAU |
| Vercel Pro (1 time, sem add-ons) | 20.00 | 105.00 | Bandwidth 1TB, edge functions, analytics |
| Domínio + DNS (anual rateado) | 1.50 | 8.00 | `r2people.com.br` + subdomínios |
| Sentry (error tracking) · Free Tier | 0.00 | 0.00 | Free até 5k erros/mês |
| GitHub Pro (privado) | 4.00 | 21.00 | CI Actions com 3000 min/mês |
| Total | **50.50 USD/mês** | **~264 BRL/mês** | |

### 7.2 Custo proporcional ao crescimento

A 5 tenants (5x GPC), o Supabase Pro ainda atende. Para escalar até 50 tenants, migrar para Team Tier (599 USD/mês) com possibilidade de read-replicas e Point-in-Time Recovery. A 200+ tenants, considerar Supabase self-hosted em cloud própria (AWS sa-east-1) com economia de 60-70%.

### 7.3 Pricing alvo para clientes

Baseado em pesquisa rápida do mercado brasileiro de gestão de pessoas:

- **Sólides:** R$ 12 a 25 por colaborador/mês (depende de módulos)
- **Qulture.Rocks:** R$ 18 a 30 por colaborador/mês
- **Feedz:** R$ 15 a 22 por colaborador/mês

Posicionamento R2 People: **R$ 12 a 18 por colaborador/mês**, com desconto progressivo a partir de 100 colaboradores. Para o GPC (367 colab × 15) seriam ~5500 BRL/mês de receita potencial. Para o HEC (~250 colab × 12 com desconto) seriam ~3000 BRL/mês.

Margem operacional: 264 BRL custo / ~8500 BRL receita potencial = **~97% margem bruta** com 2 clientes piloto, viabilizando reinvestimento em features.

---

## 8. Métricas de sucesso

### 8.1 Métricas técnicas

| Métrica | Meta semana 4 | Meta semana 16 |
|---|---|---|
| Lighthouse Performance (mobile) | ≥ 75 | ≥ 88 |
| Lighthouse Acessibilidade | ≥ 80 | ≥ 92 |
| Time to Interactive (TTI) | ≤ 3.0s | ≤ 1.8s |
| First Contentful Paint (FCP) | ≤ 2.0s | ≤ 1.0s |
| Tempo médio de query RPC | ≤ 800ms | ≤ 200ms |
| Coverage de testes E2E | ≥ 30% | ≥ 65% |
| Error rate em produção (Sentry) | ≤ 1% | ≤ 0.2% |

### 8.2 Métricas de produto (após release)

| Métrica | Meta após 30d | Meta após 90d |
|---|---|---|
| Adesão a auto-avaliação no ciclo ativo | ≥ 70% | ≥ 90% |
| Adesão a avaliação do gestor | ≥ 50% | ≥ 85% |
| Elogios públicos por mês (GPC) | ≥ 30 | ≥ 80 |
| Feedbacks privados por mês | ≥ 50 | ≥ 150 |
| % de colaboradores com PDI ativo | ≥ 30% | ≥ 60% |
| NPS interno (R2 People) | ≥ 40 | ≥ 60 |
| MAU (monthly active users) GPC | ≥ 200 | ≥ 320 |

### 8.3 Métricas de negócio (12 meses pós-launch)

- Pelo menos **3 clientes pagantes** fora do círculo R2 (clientes existentes)
- Receita recorrente mensal (MRR) ≥ R$ 25.000
- Churn voluntário ≤ 5% ao trimestre
- NPS clientes ≥ 50

---

## 9. Decisões deferidas (parking lot)

Funcionalidades discutidas e conscientemente postergadas para versões pós-MVP:

| Item | Razão da postergação | Versão alvo |
|---|---|---|
| Avaliação 360° (par + liderado) | MVP foca em auto + gestor (suficiente para 80% dos casos) | v1.5 (Q3 2026) |
| Calibração de notas em comitê | Processo complexo que demanda UX dedicada | v2.0 (Q1 2027) |
| Integração com TOTVS WinThor (escrita) | MVP só lê do TOTVS via ETL existente | v2.0 (Q1 2027) |
| OKRs e metas SMART | Modulo separado, escopo amplo | v2.0 (Q1 2027) |
| Pesquisa de clima organizacional | Fora do core de avaliação/feedback | v2.5 |
| Notificações por email/WhatsApp | MVP usa só in-app | v1.2 (Q2 2026) |
| Múltiplas línguas (EN, ES) | Mercado-alvo é Brasil | quando 5+ clientes pedirem |
| App nativo iOS/Android | PWA é suficiente para MVP | quando MAU > 5000 |
| Marketplace de templates de PDI | Diferenciação futura, não MVP | v2.5 |
| Integração com Gupy/Kenoby (recrutamento) | Out of scope, é outro produto | nunca (parceria, não build) |

---

## 10. Critérios de saída do MVP

O MVP é considerado **completo e em produção** quando os seguintes critérios são simultaneamente satisfeitos:

1. ✅ Todas as 4 fases entregues com critérios de aceite cumpridos
2. ✅ GPC operando com R2 People em substituição às planilhas Excel atuais
3. ✅ HEC operando o módulo de avaliação para staff de UTI Pediátrica e Obstétrica
4. ✅ NPS interno R2 People ≥ 40 medido com 30+ usuários
5. ✅ Documentação de usuário completa e validada (3 personas)
6. ✅ Plano de continuidade operacional documentado (backup, restore, DR)
7. ✅ Compliance LGPD validado por consultor jurídico externo (custo previsto: ~R$ 5.000)
8. ✅ Pacote comercial (proposta + apresentação + cases) pronto para vendas

A partir de então, o foco shift para **aquisição de clientes** e desenvolvimento iterativo (vs. build inicial).

---

## 11. Conclusão e próximos passos

O R2 People é um produto tecnicamente viável dentro do horizonte de 14 a 16 semanas, baseado em ferramentas maduras (Supabase, Next.js, Vercel) e construído sobre fundamentos arquiteturais sólidos já validados nos protótipos HTML. O diferencial competitivo principal · modelo multi-eixo empregador × tomador · é defensável, real, e endereça uma dor de mercado mensurável no varejo brasileiro de médio porte e em instituições públicas com terceirização.

A estratégia de entrar pelo "produto interno" (GPC + HEC) antes de oferecer comercialmente é prudente: valida em produção real com clientes que já confiam na R2, gera cases reais antes do esforço comercial, e reduz risco de produto-mercado.

### Próximos passos imediatos:

1. Aprovar este documento internamente (R2 + GPC) · semana 0
2. Provisionar Supabase + Vercel + GitHub repo · semana 1, dia 1
3. Reunião de kickoff técnico com Ricardo Silva como tech lead · semana 1, dia 2
4. Iniciar Fase 1 com aplicação do schema v3 · semana 1, dia 3
5. Daily standup assíncrono via Slack durante todo o desenvolvimento
6. Demo semanal com Patrícia Mello (RH GPC) sobre progresso

> *Este documento é versionado em Git e revisado a cada conclusão de fase. A próxima revisão prevista é ao final da Fase 1, quando a Fase 2 será refinada com aprendizados da fundação.*

---

**Apêndice A** · Lista de artefatos já produzidos (versão atual do projeto):

- `r2_people_schema_v3.sql` (schema completo, 1124 linhas)
- `r2_people_seed_initial.sql` (dados de demo do GPC, 849 linhas)
- `r2_people_rls_policies_detailed.sql` (políticas multidimensionais, 1148 linhas)
- `r2_people_rpc_report_builder.sql` (biblioteca de RPC para relatórios, 1036 linhas)
- 22 protótipos HTML funcionais cobrindo as principais telas
- Documento de wireframes com 11 seções de sitemap

**Apêndice B** · Glossário de termos do produto:

- **Empregador (EMP)**: pessoa jurídica que assina a CTPS, paga a folha e responde formalmente pelo vínculo trabalhista (ex: Labuta).
- **Tomador (TOM)**: filial física ou unidade onde o colaborador trabalha de fato (ex: Cestão L1).
- **Próprio**: empregado direto da empresa-tenant (employer = matriz GPC).
- **Terceirizado**: empregado de prestadora alocado em filial GPC (employer = Labuta, working = filial GPC).
- **9-Box**: matriz 3×3 que cruza desempenho × potencial para classificar colaboradores.
- **PDI**: Plano de Desenvolvimento Individual com objetivos para 6-12 meses.
- **DSAR**: Data Subject Access Request · direito de acesso aos dados pessoais (LGPD Art. 18).
- **DPO**: Data Protection Officer · encarregado de proteção de dados pessoais (LGPD Art. 41).
- **RLS**: Row Level Security · mecanismo do PostgreSQL que filtra linhas por usuário no nível de tabela.
- **Tenant**: cliente do produto SaaS com seus próprios dados isolados (ex: GPC, HEC).

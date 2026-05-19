# R2 People · Índice Consolidado de Artefatos

**Versão**: 2.49 · 18 de maio de 2026
**Mantido por**: Ricardo Silva · R2 Soluções Empresariais
**Cliente referência**: Grupo Pinto Cerqueira (GPC) · 367 colaboradores · 14 unidades · Bahia
**Status**: protótipo iterativo + backend Next.js parcial · pré-MVP

**Mudança em v2.10** · adicionado **spec M10 (Configurações do tenant)** — último spec funcional faltando, cobrindo `tenants.settings` JSONB + 3 tabelas (`tenant_webhooks`, `tenant_api_keys`, `settings_history`), 6 abas (Geral/Branding/Notif/Integrações/Billing/Workspace), 9 RPCs e 25+ testes meta. Mais **schema SQL v10 consolidado** unindo 4 áreas em um único arquivo: movimentações (snapshot before/after JSONB c/ trigger de protocol), auth enterprise (SSO providers, MFA TOTP + recovery codes, tenant invitations, login audit, session revocations, rate-limit 3-camadas), settings runtime (webhooks c/ HMAC, api_keys), e history_views (LGPD audit + recent_employee_views c/ trigger de trim). 12+ tabelas, GRANTs e RLS habilitado em loop.

**Mudança em v2.9** · adicionado **r2_people_showcase.html** (página entry-point comercial com 50+ cards navegáveis) + **3 specs novos** (`spec_m5_avaliacoes`, `spec_m8_metas`, `spec_m9_relatorios`) totalizando 10 specs prontos para Postgres + **schema v9** com 8 módulos novos (Notifications, Comunicados, Vagas, Treinamentos, Climate, eNPS, OKRs, Cargos&Salários) com 20 tabelas e 12 ENUMs + **política de Atestados** (3ª política LGPD do produto).

**Mudança em v2.8** · expansão massiva da Camada 1: agora 57 HTMLs (era 42), com **identidade visual Cofre completa** (logo GPC oficial, fontes Archivo + JetBrains Mono, paleta navy #2E476F / orange #F58634 alinhada ao comercial). Adicionado **shell compartilhado** (`assets/r2-shell.css` + `r2-shell.js`) que dá a todos os HTMLs: dark mode, density compacta, sidebar collapse, search global Cmd+K, bell de notificações, user dropdown, atalhos de teclado. Ver §15 abaixo para inventário completo.

**Mudança em v2.5**: o repositório agora hospeda **duas camadas no mesmo lugar** · (1) os HTMLs single-file que rodam em `rh.solucoesr2.com.br` (deploy atual via GitHub Pages) e (2) a codebase Next.js 14 + Supabase em `src/`, `supabase/`, `worker/` com 170 testes backend passando e 12 páginas implementadas. Ver §14 abaixo para a relação entre as duas camadas.

---

## 1. Visão geral

O **R2 People** é uma plataforma multi-tenant de gestão de pessoas inspirada em Qulture.Rocks e Sólides, mas pensada para o contexto brasileiro e adaptada à realidade dos clientes do R2: redes regionais com **estrutura tripartite** (empregador legal CTPS distinto da unidade tomadora operacional). O design system é o mesmo do GPC: Sora + JetBrains Mono, paleta navy/laranja/verde, sidebar 240px, mobile-first.

A construção é feita em **imersões iterativas**: a cada turno, uma nova tela ou peça de schema é entregue, sempre integrada ao que já existe. Este documento é a fonte de verdade pra navegar entre os artefatos.

**Stack-alvo**: Next.js + Supabase (Postgres com RLS, Auth, Realtime, Storage) + Vercel. Frontend single-file HTML + Tailwind utility classes para os protótipos. Backend Postgres já com schema v4 modelado.

---

## 2. Sumário executivo dos artefatos

### Camada 1 · Protótipos HTML (deploy atual)

| Categoria | Quantidade | Tamanho total |
|---|---|---|
| Telas de produto (HTML interativo) | 42 | ~2,33 MB |
| Documentação técnica e de produto (MD) | 5 | ~138 KB |
| Schema e SQL de design (`r2_people_schema_v*.sql`) | 10 | ~408 KB |
| **Subtotal** | **57** | **~2,87 MB** |

### Camada 2 · Codebase Next.js + Supabase (em desenvolvimento)

| Categoria | Quantidade | Localização |
|---|---|---|
| Páginas Next.js (App Router) | 12 | `src/app/**/page.tsx` |
| Componentes React (TS strict) | ~20 | `src/components/{employees,team,profile,navbar,imports}/` |
| Módulos do adapter TS | 10 | `src/lib/r2/` |
| Migrations Supabase (incrementais, idempotentes) | 32 | `supabase/migrations/` |
| Testes SQL (170 testes passando) | 20 | `supabase/tests/` |
| Worker FastAPI (OCR Tesseract) | 1 | `worker/` |
| Docs de sessão (sessao_a1, a2, b2, b3, c4, e1-e6, f1-f6, g1-g3, h, h2, j, k, l) | 22 | `docs/` |
| **Total** | **~13k linhas TS/TSX + ~25k linhas SQL** | - |

**Combinado**: 57 artefatos de design + codebase Next.js parcial = duas representações sincronizadas do mesmo produto.

57 artefatos de design catalogados, 11 categorias funcionais, 9 personas distintas, 4 escopos hierárquicos de RLS demonstrados.

---

## 3. Mapa de personas

Cada persona aparece em múltiplas telas e tem RLS específica:

| Persona | Iniciais | Papel | Aparece em | Permissões principais |
|---|---|---|---|---|
| **Patrícia Mello** | PM | Coordenadora RH GPC | 11 telas | `view_all_*`, `validate_medical_certificates`, `view_medical_cid`, `manage_tax_regime`, `view_oneonones_metadata`, `send_oneonone_messages` |
| **João Carvalho** | JC | Líder Financeiro GPC | 8 telas | `manage_subordinates`, `submit_medical_for_subordinate`, `manage_oneonone_pairs` |
| **Fernanda Lima** ("Fê") | FL | Analista Pleno · Labuta · Cestão L1 | 9 telas | `view_self_*`, `submit_medical_self` |
| **Larissa Pereira** | LP | RH Labuta (prestadora) | 4 telas | `view_*_by_employer`, `validate_medical_for_employer`, `view_oneonones_metadata_by_employer` |
| **Carla Moreira** | CM | DPO · auditoria LGPD | 1 tela | `view_audit_log`, `dsar_*`, `hard_delete_authorized` |
| **Renato Pinto** | RP | Diretor Operações | 2 telas | `view_all_*` (read-only consolidado), `simulate_payroll` |
| **Carlos Eduardo** ("Cadu") | CR | Coordenador Operações | mocks | `manage_team` |
| **Sandra Lima** | SL | Gerente Cestão L1 | mocks | `manage_team_branch` |
| **Gabriel Pinto** ("Gabi") | GP | Estagiário (onboarding `must_change_pwd`) | 2 telas | `view_self_basic` |

A **estrutura tripartite** é mostrada nos chips EMP / TOM presentes em todas as telas:
- **EMP** (empregador legal CTPS) · Labuta, GPC, Limpactiva, Segure
- **TOM** (tomador operacional) · Cestão Loja 1, Cestão Inhambupe, ATP Varejo, ATP Atacado, Sede ATP

Reports e queries suportam ambos os eixos via switch (ver `r2_people_relatorios.html` e `r2_people_rpc_report_builder.sql`).

---

## 4. Catálogo por módulo funcional

### Módulo 1 · Autenticação e onboarding

| # | Artefato | Persona | Descrição resumida |
|---|---|---|---|
| 01 | `r2_people_login.html` | qualquer | Split-screen desktop + fullscreen mobile · tabs Username/CPF · Microsoft SSO · tenant chip |
| 02 | `r2_people_onboarding.html` | Gabriel (estagiário) | Wizard 5 passos · `must_change_pwd=true` · password strength meter · foto opcional · tour features |
| 03 | `r2_people_error_pages.html` | qualquer | 5 estados togláveis: 404, 403 com explicação RLS, 500 com error ID, offline com network ping, sessão expirada com countdown |

**Fluxo coberto**: usuário recebe link → login → primeiro acesso força troca de senha → tour → home. Erros tratados em qualquer ponto com páginas dedicadas.

### Módulo 2 · Home e visão pessoal

| # | Artefato | Persona | Descrição resumida |
|---|---|---|---|
| 04 | `r2_people_home.html` | múltiplas | Hub de homes · 3 versões togláveis (RH/líder/colaborador) com cards de KPI e atalhos |
| 05 | `r2_people_colaborador_home.html` | Fernanda | Home pessoal · próximas tarefas · feedback recebido · ciclos abertos · banner LGPD Art.18 |
| 06 | `r2_people_minha_trajetoria.html` ⭐ | Fernanda | **Autoconsulta de histórico** · hero gradient navy→roxo→rosa · 4 hstats glassmorphism · 7 conquistas (4 desbloqueadas + 3 locked com progress) · timeline 14 eventos em 4 anos · ações self-service (baixar atestado, recibo, certificado) · privacy notes em itens médicos |

**Decisão de produto importante**: a "Minha trajetória" tem **tom de progressão pessoal**, não fiscalização. Linguagem 2ª pessoa ("Você foi promovida 🎉"), badges de conquista, ações self-service. Reusa `rpc_get_employee_history` mas a RLS oculta `cid_code` e `doctor_name` mesmo do próprio usuário (visível só na tela do DP).

### Módulo 3 · Cadastros e estrutura

| # | Artefato | Persona | Descrição resumida |
|---|---|---|---|
| 07 | `r2_people_colaborador.html` ⭐ | Patrícia/Fernanda | Cadastro/edição · 5 abas · **campo Apelido enriquecido** com badge buscável, prefix `@`, contador 0/20, sugestões automáticas, preview "Como aparece nas buscas", toggle searchable, validação inline |
| 08 | `r2_people_colaboradores_lista.html` | Patrícia | Listagem · 30 colaboradores mock · filtros · paginação |
| 09 | `r2_people_estrutura.html` | Patrícia | CRUD Filiais (14), Departamentos (15), Cargos (28) |
| 10 | `r2_people_acessos.html` | Patrícia | 9 perfis de permissão incluindo "RH Prestadora · Labuta" com escopo por employer |
| 11 | `r2_people_importacao.html` | Patrícia | Hub central + wizard 5 passos com dry-run · CSV upload · mapping inteligente |
| 12 | `r2_people_historico_consulta.html` ⭐ | múltiplas | **Search-driven UI** estilo Linear/Raycast · autocomplete inteligente (nome/apelido/matrícula) com highlight · toggle 3 personas demonstrando RLS ao vivo · 6 KPI cards · timeline agrupada por ano com 22 eventos da Fernanda · filtros por categoria |

**Decisão de produto importante**: o **Apelido** virou cidadão de primeira classe · campo único por empresa (constraint), buscável via FTS português com `unaccent()`, exibido como pill `@Fê` em listas e perfis. Resolve o problema real do GPC ter 4 "João" e 3 "Bia". Definido em schema_v4 §1.

### Módulo 4 · Movimentações

| # | Artefato | Persona | Descrição resumida |
|---|---|---|---|
| 13 | `r2_people_movimentacoes.html` | João (líder) | Tela do líder · wizard 4 passos para solicitar promoção/aumento/transferência |
| 14 | `r2_people_aprovacoes_rh.html` | Patrícia | Tela RH · 4 abas (pendentes/aprovadas/rejeitadas/auditoria) · validação de movimentações |
| 15 | `r2_people_colaborador_movimentacoes.html` | Fernanda | Minhas movimentações · banner LGPD Art.18 · 8 cards (promoção pendente, férias, dissídio, troca gestor, troca filial, transferência rejeitada, admissão) · workflow 5 passos |

**Fluxo coberto**: líder solicita → RH aprova/rejeita → colaborador acompanha via tela própria. Status sincronizados via `movements.status` ENUM.

### Módulo 5 · Atestados (módulo completo, 5 telas)

| # | Artefato | Persona | Descrição resumida |
|---|---|---|---|
| 16 | `r2_people_atestados.html` | Patrícia | Hub geral de atestados (lista + filtros + ações) |
| 17 | `r2_people_atestado_envio_lider.html` ⭐ | João (líder) | Envio pelo líder · wizard 4 passos · banner LGPD Art.11 · OCR mock + compactação 3,42MB→487KB (-86%) · CID **não** mostrado pro líder · sidebar com histórico mostrando só protocol+status (sem thumbnail nem botão "ver") |
| 18 | `r2_people_atestado_validacao_dp.html` ⭐ | Patrícia (DP) | **Validação pelo DP** · layout 3 colunas inbox-style · filtros laterais com contadores · fila central com 8 cards (qualidade OCR, prioridade, alertas) · viewer com PDF mock realista do Rafael Costa Lima + form de validação · **CID-10 com autocomplete inteligente** (20 códigos comuns embarcados) · banner azul "Movimentação será gerada automaticamente" se ≥3 dias |
| 19 | `r2_people_atestado_colaborador.html` | Fernanda | Visão própria + autoenvio + histórico pessoal |

**Regra-chave do módulo (definida no schema v4 §5)**:
- **Líder envia mas não vê depois.** Submitter NÃO tem policy de SELECT direto na tabela; é forçado a usar a RPC limitada `rpc_get_my_submitted_certificates` que retorna apenas `protocol`, `status`, `certificate_type`, `user_initials` (abreviados como "F. Lima"), `days_off`, sem `file_storage_path` nem `cid_code`.
- **CID só aparece pro DP**, nunca pro líder, nem pra própria pessoa em telas listativas (só ao baixar o documento original).
- **Movimentação automática** gerada se `days_off >= 3` via `rpc_validate_certificate(create_movement=true)`, vinculando `medical_certificates.auto_movement_id` ao `movements.id`.

**Fluxo ponta-a-ponta (atestado de 7 dias do Rafael)**:
1. Sandra Lima (gerente ATP Varejo) recebe atestado físico do Rafael
2. Abre `atestado_envio_lider.html`, seleciona Rafael, tira foto, sistema processa via OCR (Tesseract WASM client-side, preserva LGPD) e compacta
3. Submete → trigger gera protocol `ATD-2026-04-28-3D72A`, audit log, notifica Patrícia (DP) + Larissa (RH Labuta) + Rafael
4. Sandra perde acesso ao conteúdo. Vê só protocol + status no histórico.
5. Patrícia abre `atestado_validacao_dp.html`, seleciona o card do Rafael, viewer mostra PDF + form com OCR pré-preenchido + sugestão de CID M54.5 (Dor lombar)
6. Patrícia confirma CID, clica "Validar e gerar movimentação" → RPC cria `MOV-AUTO-2026-04-28-3D72A` de afastamento por enfermidade
7. Rafael recebe notificação "Seu atestado foi validado" e vê o evento em `minha_trajetoria.html` (sem CID exposto)

### Módulo 6 · Férias (módulo completo, 2 telas)

| # | Artefato | Persona | Descrição resumida |
|---|---|---|---|
| 20 | `r2_people_ferias.html` ⭐ | Patrícia | **Gestão operacional** · 4 KPIs · toggle Calendário Gantt 8 meses ↔ Lista · linha "HOJE" laranja · barras coloridas por status (programada/em curso/histórica/vencendo) · painel lateral sticky com 3 abas (Períodos aquisitivos com progresso, Programações, Histórico) · footer com Programar/Exportar |
| 21 | `r2_people_ferias_programacao_anual.html` ⭐ | múltiplas | **Programação anual** · toggle 3 personas (Líder/DP/Diretoria) com escopo demonstrado · scope banner com contagem · 5 KPIs dinâmicos · filtros multi-select de Filial e Setor · tabela agrupada por filial→setor · alertas pulsantes (EM DOBRO, VENCE, Sem programação) · view alternativa Matriz Anual mês×colaborador |

**Regras CLT refletidas no design**:
- Período aquisitivo (12 meses) → liberação → concessivo (12 meses) → vence em dobro
- Aviso prévio 60 dias (CLT Art. 135) registrado em campo `notice_days`
- Fracionamento permite até 3 partes desde que uma tenha ≥14 dias contínuos
- Abono pecuniário até 1/3 dos dias
- Adiantamento de 13º a pedido do empregado
- 16 colaboradores mock cobrem cenários reais: Helena com aquisitivo crítico vencendo 18/05/26, Juliana com aquisitivo já vencido (paga em dobro!), Beatriz sem programação, Gabriel estagiário, etc.

### Módulo 7 · Avaliações e Feedback

| # | Artefato | Persona | Descrição resumida |
|---|---|---|---|
| 22 | `r2_people_ciclos.html` | Patrícia | Tela de Ciclos · 5-phase timeline · CRUD de ciclos de avaliação |
| 23 | `r2_people_avaliacao.html` | Fernanda/João | Formulário de avaliação dual auto+gestor · escala 1-5 · comentários por competência |
| 24 | `r2_people_feedback_mural.html` | múltiplas | Big tabs Feedback (navy) / Mural (laranja) · feedback contínuo + reconhecimentos públicos |

### Módulo 8 · Relatórios e auditoria

| # | Artefato | Persona | Descrição resumida |
|---|---|---|---|
| 25 | `r2_people_admin_dashboard.html` | Patrícia | Dashboard RH · 5 abas · 9-Box · KPIs gerais |
| 26 | `r2_people_relatorios.html` ⭐ | Patrícia | Hub categorizado + Report builder · **switch EMPREGADOR ↔ TOMADOR** (peça-chave da arquitetura) |
| 27 | `r2_people_auditoria.html` | Carla Moreira (DPO) | Persona DPO · 4 abas LGPD · audit log filtrado · DSAR · ferramentas de retenção |

### Módulo 9 · Configurações

| # | Artefato | Persona | Descrição resumida |
|---|---|---|---|
| 28 | `r2_people_configuracoes.html` | Patrícia | Tenant settings · 6 abas (geral, branding, notificações, integrações, billing, workspace) |

### Módulo 10 · Folha & Custo (módulo completo, 3 telas)

| # | Artefato | Persona | Descrição resumida |
|---|---|---|---|
| 29 | `r2_people_calculadora_custo.html` ⭐ | Patrícia (RH) | **Calculadora individual de custo** · toggle SIMPLES NACIONAL ↔ LUCRO REAL com banner contextual GPC mostrando quais empresas operam em cada regime · slider de salário com gradient · 5 toggles de benefícios (VR, VA, plano saúde, odonto, seguro) · variáveis (comissão, HE, adicionais) · PLR rateado por mês · result panel gradient com líquido + anual · donut chart SVG inline · breakdown detalhado por seção · comparativo SIMPLES vs LUCRO REAL lado a lado com cálculo de diferença anual escalada (×10 colab) |
| 30 | `r2_people_folha_por_filial.html` ⭐ | Renato (Diretoria) | **Simulador de folha por filial** · 4 KPIs consolidados (367 colab, R$ 1,8M/mês, R$ 22M/ano, R$ 5k médio) · filtros por empregador · **4 cenários componíveis**: dissídio %, mérito %, redução headcount %, contratações novas · impact banner consolidado em tempo real · bar chart horizontal das top 8 filiais por custo · **heatmap mensal de sazonalidade** com picos em julho e dezembro (1ª parc 13º + 13º completo) · tabela detalhada com drill-down por departamento · 14 unidades reais (GPC + Labuta + Limpactiva + Segure) com hierarquia de departamentos |
| 31 | `r2_people_regime_tributario.html` ⭐ | Patrícia (RH) | **CRUD de regime tributário por unidade** · 4 KPIs (14 unidades · 5 Lucro Real · 9 Simples · 3 alteradas em 2026) · banner warn alertando 2 unidades próximas do teto Simples (R$ 4,8 mi) · tabela com regime clicável (badges coloridos por tipo) · CNPJ, Anexo Simples, FAP, RAT, Headcount e Faturamento por unidade · **modal de confirmação dupla** com cálculo de impacto em tempo real (colaboradores afetados, encargos antes/depois, economia mensal estimada) · 2 checkboxes obrigatórios (aprovação contábil + ciência do recálculo) · audit log com 6 eventos cronológicos (regime, FAP, RAT, criação) com chips "from → to" coloridos |

**Decisão de produto importante**: a separação em três telas é intencional. **Calculadora individual** é operacional (RH simulando custo de uma contratação ou aumento), **folha por filial** é estratégica (diretoria respondendo perguntas de negócio sobre dissídio, headcount, contratações), e **regime tributário** é administrativa (Patrícia + contador atualizando configurações fiscais base). As três usam **a mesma legislação 2026** (constantes compartilhadas) e **mesmo modelo de cálculo de encargos** · quando a Receita atualizar a tabela em janeiro/2027, a alteração é num único arquivo SQL `legal_tax_tables`. A tela de regime tributário é a **fonte de verdade do `units.tax_regime`** · sem ela, calc e folha eram puros mocks.

**Tom de cada tela** (importante para coerência):
- **Calculadora**: exploratória, leve, slider de salário interativo
- **Folha por filial**: estratégica, executiva, cenários componíveis
- **Regime tributário**: administrativa, conservadora, confirmação dupla, audit log explícito

**Constantes legais 2026 versionadas** (Portaria Interministerial MPS/MF nº 13/2026 + Lei 15.270/2025):
- INSS empregado progressivo: 7,5% / 9% / 12% / 14% com deduções R$ 0 / 24,32 / 111,40 / 198,49
- Teto INSS: R$ 8.475,55 · Desconto máx: R$ 988,09
- IRRF: isenção integral até R$ 5.000 · faixa de redução até R$ 7.350 · tabela tradicional acima
- Salário mínimo: R$ 1.621,00
- Encargos Lucro Real: INSS Patronal 20% + RAT 1-3% (× FAP 0,5-2,0) + Sistema S 5,8% + FGTS 8% = ~35,8% direto, ~67% com provisões e cascata
- Encargos Simples (Anexos I-III): apenas FGTS 8%, ~30% com provisões · INSS, RAT, Sistema S inclusos no DAS
- Provisões mensais: Férias 11,11% (1/12 + 1/3) · 13º 8,33% (1/12) · Multa rescisória 4%

**Validações fiscais reais** (na tela de regime tributário):
- Faturamento >R$ 4 mi destacado em laranja como aviso · regime Simples requer faturamento ≤ R$ 4,8 mi anuais
- FAP entre 0,5 e 2,0 (multiplicador da Previdência Social, atualizado anualmente)
- RAT entre 1% (baixo) e 3% (alto) conforme grau de risco da atividade
- Anexos Simples I (comércio), II (indústria), III (serviços com folha alta), IV (serviços com folha baixa), V (intelectual)
- Mudança de regime exige aprovação contábil + ciência do recálculo retroativo

**Fluxo coberto**: Patrícia simula custo de promoção da Fernanda → Renato simula impacto agregado de dissídio coletivo no GPC → comparativo entre regimes mostra que mover terceirização da Labuta (Simples) para CLT direto (Lucro Real) custaria 1,3× a mais por colaborador. Quando uma unidade Simples cresce e ultrapassa R$ 4,8 mi, Patrícia recebe o alerta na tela de regime tributário e executa a mudança com confirmação dupla · todas as simulações futuras passam a usar o novo regime automaticamente.

### Módulo 11 · 1:1s estruturadas (módulo completo, 4 telas + schema dedicado)

| # | Artefato | Persona | Descrição resumida |
|---|---|---|---|
| 32 | `r2_people_oneonones.html` ⭐ | João (líder) | **Hub do líder** · 4 KPIs (cadência média, próxima 1:1, AIs em atraso, sem 1:1 há +30d) · banner contextual amarelo alertando liderado em débito · grid de cards por liderado com borda colorida (fresh/aging/stale), próxima 1:1, idade da última, AIs abertos · lista próximas 7 dias · lista 6 recentes com indicador "pauta ✓" / "sem pauta" · modal de agendamento com seleção visual de pessoa, data, hora, duração, local, recorrência (única/quinzenal/semanal/mensal) e pauta inicial opcional |
| 33 | `r2_people_oneonone_room.html` ⭐ | João (líder) / dual | **Sala da 1:1 individual** · header sticky com avatar + chips EMP/TOM + status pill pulsante "Em andamento" + timer regressivo (verde→laranja→vermelho) + botões Reagendar/Concluir · 4 tabs (Notas, Pauta, Action items, Histórico) · **notas duais lado a lado**: privadas (fundo amarelo, ícone cadeado, "só você vê · ninguém mais (nem RH)") + compartilhadas (fundo branco, ícone pessoas, "você e Fernanda veem") com auto-save 700ms · pauta com bullet colorido por autor, tag "vindo da anterior", excluir só do próprio · action items com responsável (lead/led/both), prazo, status, carry over · modal de concluir com sentimento (😊🙂😐😟) explicado como privado + checkbox de lock após 7d |
| 34 | `r2_people_minhas_1on1s.html` ⭐ | Fernanda (liderada) | **Visão da liderada** · hero gradient navy→roxo com pill verde pulsante "Em andamento agora" + avatar do líder + bloco de horário + botões "Entrar na sala" e "Propor reagendar" · 4 KPIs pessoais · pauta inline editável (bullet roxo "você adicionou" / laranja "João adicionou" / âmbar "vindo da anterior") · Meus action items com checkbox habilitado só nos próprios (owner=led ou both) · histórico SEM mostrar sentimento do líder · sidebar com card verde "Sua privacidade" explicitando "as notas privadas do João não aparecem para você" · modal de propor reagendamento que NÃO impõe ("João recebe a sugestão e decide se aceita") |
| 35 | `r2_people_oneonones_rh.html` ⭐ | Patrícia (RH GPC) / Larissa (RH Labuta) | **Visão RH agregada** · banner verde de privacidade no topo enforced ("Você vê apenas metadados, nunca conteúdo · garantido pelo banco, não só pela tela") · persona switcher GPC ↔ Labuta com banner roxo de escopo restrito quando Labuta · 6 KPIs clicáveis · tabela de líderes com pill colorida de cadência + visual de 6 semanas (verde/âmbar/vermelho) + clique expande drill com lista de liderados em débito reforçando "RLS bloqueia conteúdo" · modal "Notificar líder" com 4 templates (Cadência / Liderado em atraso / AIs em atraso / Personalizada) e sugestão automática baseada no maior problema · sidebar com lista de liderados sem 1:1 +45d e atividade recente (só metadados) |

**Decisão de produto crítica**: este módulo foi construído com **privacidade como propriedade arquitetural, não cosmética**. As 4 telas refletem o que cada persona pode ver, mas a garantia real está no schema (`r2_people_schema_oneonones_v6.sql`):

- **Notas privadas do líder**: NUNCA acessíveis por ninguém além do leader_id da meeting. RH não tem policy de SELECT em `oneonone_notes`. Mesmo com SQL direto não é possível ler.
- **Notas compartilhadas**: visíveis apenas para os 2 participantes (leader_id, led_id).
- **Texto de pauta e descrição de action items**: bloqueado para RH. RH consulta apenas count via views agregadas.
- **Sentimento (mood)**: privado de quem registrou. Líder não vê do liderado, liderado não vê do líder, RH não vê de ninguém. Decisão dura: zero exibição cruzada para evitar instrumentalização do sentimento como métrica de cobrança.
- **DSAR (LGPD Art. 18)**: existe apenas como RPC dedicada `rpc_oneonone_dsar_export(target_user_id)` com permission própria e audit pesado. DPO regular não tem acesso direto.

**Estados das meetings**: `scheduled` → `in_progress` (auto-detectado pelo horário via job pg_cron a cada 1min) → `completed` (líder marca) → `canceled`. Após `completed_at + 7 dias`, conteúdo trava para edição (`content_locked_at`).

**Carry over de pauta**: itens não discutidos viram pauta da próxima 1:1 do par automaticamente, com tag visual "vindo da anterior". Anti-cascata: não copia carry de carry (evita propagação infinita).

**Cadências configuráveis por par**: `weekly` / `biweekly` (default GPC) / `monthly` / `custom` (1-90 dias). Job pg_cron diário gera próximas meetings nos próximos 30 dias para pares ativos.

**Templates de mensagem RH→Líder** (em `oneonone_messages`): Cadência (lembrar regularidade), Overdue Led (cobrar pessoa específica), Overdue AI (cobrar action items), Custom (livre). Sugestão automática baseada no maior problema do líder na tabela.

**Fluxo coberto** (Fluxo H, ver §8): RH detecta líder com cadência ruim → notifica via template → líder vê notificação in-app → agenda 1:1 → conduz na sala → conclui com sentimento privado · liderado recebe AIs e marca como concluído quando feito · ciclo refeito quinzenal.

**Sidebars atualizadas em 27 telas existentes** com link "1:1s" (líder/RH) ou "Minhas 1:1s" (liderado), inseridos contextualmente após o módulo de mesma natureza (Avaliações para líder, Movimentações para RH, Minhas avaliações para liderado). Marker `data-r2-1on1-injected="v1"` torna a operação idempotente.

---

## 5. Backend (10 artefatos SQL)

### Schemas (incremental)

| # | Arquivo | Tamanho | Conteúdo |
|---|---|---|---|
| S1 | `r2_people_schema.sql` | 18 KB | v1: estrutura básica multi-tenant, users, companies |
| S2 | `r2_people_schema_v2.sql` | 24 KB | v2: tripartite (employer_unit_id + working_unit_id), permission_profiles |
| S3 | `r2_people_schema_v3.sql` | 52 KB | v3: 14 seções consolidadas, evaluations, feedback, ciclos, audit_log, notifications |
| S4 | `r2_people_schema_v4.sql` ⭐ | 54 KB | **v4**: nickname searchable + medical_certificates (24 colunas) + 8 RPCs (busca, histórico, validação) + RLS específicas + storage bucket criptografado + triggers de protocolo e notificação tripartite + cenários de teste + plano de rollback |
| S5 | `r2_people_schema_metas_v5.sql` ⭐ | 36 KB | **v5**: módulo de Metas · 4 tabelas (goals, goal_indicators, goal_payout_rules, goal_payout_calculations), 7 enums, 12 RLS policies, 3 RPCs (calculate_payouts, finalize_validation, clone_from_previous), 2 views agregadas |
| S6 | `r2_people_schema_oneonones_v6.sql` ⭐ | 60 KB | **v6 atual**: módulo de 1:1s · 6 tabelas (pairs, meetings, agenda_items, notes, action_items, messages), 7 enums, **25 RLS policies** (sem policy de SELECT para RH em conteúdo · privacidade enforced), 3 views agregadas para RH (só metadados), 8 RPCs com SECURITY DEFINER, 5 cenários de teste, 4 jobs pg_cron sugeridos |

### Outros artefatos SQL

| # | Arquivo | Tamanho | Conteúdo |
|---|---|---|---|
| S7 | `r2_people_seed_initial.sql` | 64 KB | Seed idempotente (849 linhas): GPC + Labuta + Limpactiva + Segure, 14 unidades, 28 cargos, 30 colaboradores mock, 9 perfis de permissão, ciclo Q1/2026, exemplos de movimentações |
| S8 | `r2_people_rls_policies_detailed.sql` | 43 KB | RLS detalhada para todas as tabelas + 6 cenários de teste passando (Patrícia, João, Fernanda, Larissa, Gabriel, Carla) |
| S9 | `r2_people_rpc_report_builder.sql` | 40 KB | 11 funções RPC do report builder com switch EMP/TOM |
| S10 | `r2_people_medical_certificates_schema.sql` | 26 KB | Versão standalone do módulo de atestados (subset do v4 para revisão isolada) |

### RPCs principais consolidadas

Do schema v4 (chamadas pelas telas via Supabase JS SDK):

```typescript
// Busca inteligente (alimenta autocomplete em historico_consulta.html)
rpc_search_employees(p_query, p_limit)
  → priorização: nickname_exact(100) > nickname_prefix(90) > matricula(85)
    > name_prefix(70) > name_contains(50) > FTS português(30)
  → SECURITY INVOKER (respeita RLS do chamador)

// Histórico unificado (alimenta historico_consulta.html e minha_trajetoria.html)
rpc_get_employee_history(p_user_id, p_categories[], p_year_from, p_year_to)
  → UNION ALL de 8 fontes: admissão, movimentações, férias, atestados,
    avaliações, feedbacks, treinamentos, faltas
  → CID e dados médicos só retornam se caller tem 'view_medical_cid'

// Atestados (módulo completo)
rpc_check_nickname_available(p_nickname, p_user_id)
rpc_get_my_submitted_certificates(p_limit)  -- visão LIMITADA do líder
rpc_get_certificate_detail(p_certificate_id)  -- visão completa do DP
rpc_validate_certificate(p_certificate_id, p_cid_code, p_cid_description, p_create_movement)
rpc_reject_certificate(p_certificate_id, p_reason)

// Buscas recentes
rpc_register_employee_view(p_subject_id)

// 1:1s (schema v6, privacidade enforced)
rpc_oneonone_get_room(p_meeting_id)
  → retorna sala completa para participante: meeting + agenda + notes_shared
  → notes_private retornadas APENAS se caller é o leader_id
  → mood retornado APENAS para o próprio dono (mood_leader p/ líder, mood_led p/ liderado)
rpc_oneonone_save_notes(p_meeting_id, p_kind, p_content)
  → valida que privadas só pelo líder, compartilhadas pelos dois
  → bloqueia edição após content_locked_at
rpc_oneonone_complete_meeting(p_meeting_id, p_mood_leader)
  → exige caller = leader_id
  → cria carry over automático dos itens não discutidos para próxima meeting
  → audit_log obrigatório
rpc_oneonone_propose_reschedule(p_meeting_id, p_new_start, p_new_end, p_reason)
  → exige caller = led_id (apenas liderado propõe)
  → cria mensagem para o líder
rpc_oneonone_send_rh_message(p_recipient_id, p_template, p_subject, p_body, p_about_pair_id)
  → exige permission send_oneonone_messages
  → audit_log obrigatório
rpc_oneonone_create_action_item(p_meeting_id, p_description, p_owner, p_due_date)
rpc_oneonone_get_my_history(p_limit)
  → retorna histórico do próprio user com seu próprio mood (nunca o do outro)
rpc_oneonone_dsar_export(p_target_user_id)
  → exige permission dsar_export (LGPD Art. 18)
  → audit pesado · não joina com pares de terceiros
```

---

## 6. Documentação (5 arquivos MD)

| # | Arquivo | Tamanho | Conteúdo |
|---|---|---|---|
| D1 | `r2_people_wireframes_mvp.md` | 36 KB | 11 seções · sitemap completo · fluxos de telas · diagramas ASCII |
| D2 | `r2_people_architecture_roadmap.md` | 37 KB | 4 fases (14-16 semanas) · riscos · custo estimado ~R$ 264/mês · métricas · parking lot |
| D3 | `r2_people_privacy_policy.md` | 23 KB | Política LGPD completa (419 linhas) · 13 seções + 2 apêndices · distinção controlador (cliente) vs operador (R2) · DSAR Art. 18 |
| D4 | `r2_people_analise_correcoes.md` | 4 KB | Relatório de 2 ondas de correções sistêmicas: 211 substituições de em-dash, XSS no CID, IRRF Lei 15.270/2025, divisões por zero, contraste, debounce, headcount canônico 367 |
| D5 | `r2_people_INDEX.md` ⭐ | este | Índice consolidado v2.4 |

---

## 7. Matriz de dependências entre artefatos

Setas indicam "depende de" no sentido de que mudanças em A potencialmente quebram B:

```
schema_v3.sql
    ↓
schema_v4.sql ──────┬──→ historico_consulta.html (rpc_search_employees, rpc_get_employee_history)
                    ├──→ minha_trajetoria.html (mesma RPC, escopo self)
                    ├──→ colaborador.html (campo nickname + rpc_check_nickname_available)
                    ├──→ atestado_envio_lider.html (medical_certificates INSERT + RLS)
                    ├──→ atestado_validacao_dp.html (rpc_validate + rpc_reject + rpc_get_certificate_detail)
                    └──→ atestado_colaborador.html (auto-envio + listagem própria)
    ↓
schema_metas_v5.sql ──┬──→ metas.html (RH cadastro · rpc_calculate_payouts)
                      ├──→ minhas_metas.html (timeline pessoal)
                      ├──→ lancamento_resultado.html (líder lança realizado)
                      └──→ validacao_resultado.html (gestor valida + rpc_finalize_validation)
    ↓
schema_oneonones_v6.sql ──┬──→ oneonones.html (hub do líder · view oneonones_rh_dashboard_leader filtrada)
                          ├──→ oneonone_room.html (rpc_get_room, rpc_save_notes, rpc_complete_meeting)
                          ├──→ minhas_1on1s.html (rpc_get_my_history, rpc_propose_reschedule)
                          └──→ oneonones_rh.html (3 views agregadas · rpc_send_rh_message)
                              ↓ privacidade enforced
                              · 25 RLS policies, 0 SELECT para RH em conteúdo
                              · DSAR Art. 18 via rpc_dsar_export dedicada

rls_policies_detailed.sql ──→ todas as telas (transversal)

seed_initial.sql ──→ todas as telas (mocks consistentes)

design system GPC ──→ todas as 42 telas (Sora + JetBrains Mono · paleta navy/orange/green)

rpc_report_builder.sql ──→ relatorios.html (11 RPCs do switch EMP/TOM)

regime_tributario.html ──┬──→ units.tax_regime (fonte de verdade)
                         └──→ units.simples_anexo, units.fap, units.rat_pct
                              ↓ alimentam
constantes_legislacao_2026 ──┬──→ calculadora_custo.html (cálculo individual)
                             └──→ folha_por_filial.html (cálculo agregado)
                             ↑ futuro: legal_tax_tables (Postgres) versionada por ano

sidebar nav-item "1:1s" / "Minhas 1:1s" ──→ injetado em 27 telas existentes
                                            (idempotente via data-r2-1on1-injected="v1")
```

**Regra de manutenção**: ao alterar schema, sempre atualizar mocks no seed e revisar telas que consomem as RPCs afetadas. O INDEX deve ser atualizado a cada novo artefato (manualmente ou via job CI futuro).

---

## 8. Fluxos ponta-a-ponta consolidados

### Fluxo A · Promoção da Fernanda

1. **João Carvalho** (`movimentacoes.html`) preenche wizard de promoção · justificativa · novo salário 8.500
2. Sistema gera `MOV-2026-0427` com status `pending_rh`
3. Notifica Patrícia (Patrícia recebe in-app)
4. **Patrícia** (`aprovacoes_rh.html`) vê na fila, valida budget, aprova
5. Status muda para `approved`, trigger atualiza `users.salary`, `users.job_role`
6. **Fernanda** (`colaborador_movimentacoes.html` ou `minha_trajetoria.html`) recebe notificação "Sua promoção foi aprovada 🎉"
7. Evento aparece na timeline pessoal da Fernanda como evento `green` da categoria `cargo`

### Fluxo B · Atestado de 7 dias do Rafael (descrito em detalhe na seção do Módulo 5)

### Fluxo C · Programação anual de férias 2026

1. **Patrícia** convoca reunião de planejamento em janeiro
2. Abre `ferias_programacao_anual.html` com persona DP (vê todos os 367)
3. Filtra por filial Cestão Loja 1 → vê 4 KPIs (3 com aquisitivo vencendo, 1 em dobro!)
4. Tabela mostra Helena com aquisitivo crítico (vence 18/05/26), Juliana já em dobro
5. Patrícia agenda reuniões com líderes para acertar programações
6. **João Carvalho** abre a mesma tela (persona Líder, vê só 4 da equipe direta)
7. Programa Fernanda (15/12 a 13/01), Daniela (jun), Natália fracionada (mai+ago), Gabriel (ainda em formação)
8. Cada programação cria `vacation_periods.status='approved'`
9. Job diário às 7h envia notificação 60 dias antes do início
10. **Renato** (diretoria) abre a mesma tela em vista de macro: vê matriz anual e valida que não há concentração crítica em nenhum mês

### Fluxo D · Busca inteligente "joão"

1. **Patrícia** digita "joão" em `historico_consulta.html`
2. Frontend chama `rpc_search_employees('joão', 20)`
3. RPC normaliza com `unaccent()`, aplica RLS (Patrícia vê todos)
4. Retorna 4 matches priorizados:
   - João Pedro Silva (`@JP`, score 90 · match prefix em apelido)
   - João Carvalho (score 70 · name_prefix)
   - João Vitor Mendes (score 70)
   - Maria João Costa (`@Maju`, score 50 · name_contains)
5. Patrícia clica em João Pedro → frontend chama `rpc_register_employee_view` (alimenta recentes) e `rpc_get_employee_history(joao_pedro_id)`
6. Histórico volta com 8 eventos: admissão, dissídios, primeira promoção pendente, primeiras férias planejadas, etc.

### Fluxo E · Onboarding do estagiário Gabriel

1. Patrícia cria o cadastro em `colaborador.html` com `must_change_pwd=true`
2. Sistema envia e-mail de boas-vindas com link único
3. Gabriel clica → `login.html` (faz login com senha temporária)
4. Sistema redireciona para `onboarding.html` (5 passos: senha nova, foto, dados pessoais, ler políticas, tour)
5. Após concluir, vai pra `colaborador_home.html`
6. Gabriel recebe primeiro feedback do João em D+30
7. Em D+11 meses (regra do estágio), aparece em `ferias_programacao_anual.html` com tag "Estagiário · primeiras férias após 12m"

### Fluxo F · Simulação de impacto do dissídio coletivo

1. **Patrícia** recebe email do sindicato dos comerciários BA confirmando dissídio de 4,5% para março
2. Abre `calculadora_custo.html` com salário típico de repositor (R$ 2.100, Labuta, Simples) → vê custo individual de R$ 2.730/mês
3. Aplica reajuste e vê novo custo: R$ 2.853/mês (+R$ 123 por colaborador)
4. Abre `folha_por_filial.html` (persona Renato, ou ela mesma se tiver `simulate_payroll`) e aplica cenário "Dissídio coletivo: 4,5%"
5. **Impact banner laranja** mostra agregado: *"+R$ 83.125 / mês · +R$ 1.080.625 / ano"*
6. Drill-down na Labuta @ Cestão Loja 1 (78 colab) revela impacto específico: ~R$ 9.500/mês adicionais
7. Renato exporta a simulação como PDF e leva para reunião de orçamento
8. Decisão: aplicar dissídio em março, mas suspender contratações pelos próximos 2 meses para compensar o impacto no fluxo de caixa
9. Patrícia executa o reajuste em massa via `importacao.html` (CSV com novos salários) · todas as alterações geram movimentações `salary_adjustment_collective_bargain` no histórico

### Fluxo G · Mudança de regime tributário por crescimento

1. Em fevereiro, **Labuta @ Cestão Inhambupe** tem o faturamento anual projetado batendo R$ 4,64 mi · sistema acompanha receita mensal via job de sincronização contábil
2. Quando o projetado ultrapassa R$ 4 mi, sistema dispara alerta visível em `regime_tributario.html` · banner warn laranja: *"2 unidades próximas do teto Simples (R$ 4,8 mi anuais)"*
3. **Patrícia** consulta o contador externo, que confirma que a unidade efetivamente passará do teto se mantiver crescimento
4. Patrícia abre a tela e clica no badge "Simples Nacional · Anexo III" da Labuta @ Cestão Inhambupe
5. **Modal de confirmação dupla** aparece com:
   - Change summary: Simples Anexo III → Lucro Real, vigência 01/05/2026
   - Impact box laranja: 65 colaboradores afetados, encargos atuais ~30%, novos ~67%, **custo mensal estimado +R$ 56.880**
   - 2 checkboxes obrigatórios (aprovação contábil + ciência do recálculo)
6. Patrícia marca os 2 checkboxes (botão destrava) e clica "Aplicar alteração"
7. Sistema executa `rpc_change_tax_regime` que: (a) valida permission `manage_tax_regime`, (b) atualiza `units.tax_regime` e `tax_regime_effective_from`, (c) registra audit log com `from`, `to`, `justification` e timestamps
8. A mudança é refletida automaticamente em:
   - `calculadora_custo.html`: novas simulações pra essa unidade usam Lucro Real
   - `folha_por_filial.html`: KPIs e tabela atualizam o regime; Renato vê próximo cenário de dissídio com encargos corretos
   - `relatorios.html`: relatórios de custo passam a mostrar essa unidade no eixo Lucro Real
9. Próximo refresh da `mv_payroll_by_unit` (job 1h da manhã) consolida os números agregados nos dashboards

### Fluxo H · 1:1 quinzenal do João com a Fernanda

1. **João** entra em `oneonones.html` na manhã da sexta · vê 4 KPIs (cadência média 14d, próxima 1:1 hoje 16h com Fernanda, 7 AIs abertos com 2 em atraso, 1 liderado em débito) · banner âmbar alerta sobre Daniela há 38d sem 1:1 (mas tem nota explicativa "voltou de férias 27/04")
2. Card da Fernanda mostra "Próxima: hoje 16h" · "Última: 14d atrás" pill verde · 2 AIs abertos
3. **Fernanda** entra em `minhas_1on1s.html` antes da reunião · hero com pill verde pulsante "Em andamento agora" · adiciona pauta "PDI · próximos passos para promoção" (com tag "vindo da anterior" porque ficou pendente da última 1:1)
4. 16:00 chega · job pg_cron auto-detect muda meeting para `in_progress` · ambos clicam "Entrar na sala" e abrem `oneonone_room.html`
5. Status pill pulsante verde "Em andamento" · timer regressivo "23:14 restantes" · 4 tabs (Notas/Pauta/AIs/Histórico)
6. João escreve em **notas privadas** (fundo amarelo, só ele vê): "Notei que a Fê veio mais quieta hoje, talvez algo aconteceu antes da reunião" · auto-save após 700ms · `rpc_oneonone_save_notes(meeting, 'private_leader', content)` valida que caller=leader_id
7. Conversam · marcam itens da pauta como discutidos via checkbox · adicionam **notas compartilhadas** (fundo branco, ambos veem): "Combinamos curso interno + mentoria com Patrícia"
8. João cria 2 action items via `rpc_oneonone_create_action_item`: 1 para ele (compartilhar material do curso, prazo 08/05) e 1 para Fernanda (preparar 2 cases de modelagem dimensional, prazo 15/05)
9. 16:43 · João clica "Concluir 1:1" · modal mostra resumo (4 itens discutidos + 1 não discutido + 2 AIs criados) · picker de sentimento (Muito boa/Boa/Neutra/Difícil) explicado como **privado dele** · checkbox "bloquear edição após 7 dias"
10. `rpc_oneonone_complete_meeting(meeting_id, mood_leader=3)` · atualiza status, persiste mood do líder, **gera carry over automático** do item não discutido para a próxima meeting (15/05) · audit log
11. Fernanda recebe notificação in-app · vê novos AIs em `minhas_1on1s.html` · histórico atualiza com a 1:1 de hoje (sem mostrar mood do João)
12. Em paralelo, **Patrícia** abre `oneonones_rh.html` · view `oneonones_rh_dashboard_leader` mostra João como líder saudável (verde, cadência 14d) · card de atividade recente mostra "João Carvalho concluiu 1:1 com Fernanda Lima · há 18min" · sem nenhum conteúdo, só o evento
13. Sete dias depois, job pg_cron preenche `content_locked_at` na meeting concluída · novas tentativas de UPDATE retornam erro `content_locked` via RLS

---

## 9. Regras de negócio chave (transversais)

### Estrutura tripartite

Toda pessoa tem:
- `employer_unit_id` → empregador legal CTPS (quem assina folha, paga INSS, FGTS)
- `working_unit_id` → tomador operacional (onde trabalha de fato)
- `department_id` → área funcional

Reports e queries devem suportar **ambos os eixos**: "tudo da Labuta" (empregador) vs "tudo do Cestão L1" (tomador). O switch está em `relatorios.html` e nas RPCs do `rpc_report_builder.sql`.

### Apelido

- Único por empresa (`UNIQUE INDEX (company_id, lower(nickname))`)
- 2-20 caracteres, regex `^[a-zA-ZÀ-ÿ0-9_]{2,20}$`
- Toggle `nickname_searchable` permite ocultar dos resultados de busca (útil em casos de privacidade)
- Aparece como pill `@Fê` em todas as visualizações

### LGPD · Atestados (Art. 11 categoria especial)

- **Líder envia, não vê depois.** Acesso forçado via RPC limitada
- **CID-10 só pro DP** com permission `view_medical_cid`
- OCR roda **client-side** (Tesseract WASM) · imagem nunca sai do navegador para serviço externo
- Storage bucket privado com RLS espelhando policy da tabela
- Retenção mínima 5 anos (CLT Art. 168)
- Audit log de toda visualização

### Privacidade · 1:1s estruturadas

Privacidade aqui é **propriedade arquitetural, não cosmética**. Garantida pela RLS do schema (`r2_people_schema_oneonones_v6.sql`), não pela tela. RH consultando o banco direto não consegue ler conteúdo.

- **Notas privadas do líder**: NUNCA acessíveis por ninguém além do `leader_id` da meeting. Sem policy de SELECT para RH/admin/DPO regulares. Apenas DSAR formal via `rpc_oneonone_dsar_export` (LGPD Art. 18) com permission própria e audit pesado.
- **Notas compartilhadas**: visíveis apenas para os 2 participantes (`leader_id`, `led_id`).
- **Texto de pauta** (`oneonone_agenda_items.text`) e **descrição de action items** (`oneonone_action_items.description`): bloqueado para RH. Acesso só via views agregadas (`oneonones_rh_dashboard_leader`, `oneonones_rh_overdue_led`, `oneonones_rh_activity`) que retornam apenas count/dates/status, nunca texto.
- **Sentimento (mood)**: privado de quem registrou. `mood_leader` visível apenas pelo líder; `mood_led` visível apenas pelo liderado; RH não vê de ninguém. Decisão dura tomada para evitar instrumentalização do sentimento como métrica de cobrança.
- **Lock de conteúdo após 7 dias** da conclusão (`content_locked_at` preenchido por job pg_cron). UPDATE retorna erro após esse prazo.
- **Estados auto-detectados**: `scheduled` → `in_progress` (job a cada 1min compara horário) → `completed` (manual pelo líder) → `canceled`.
- **Carry over de pauta**: itens não discutidos viram pauta da próxima 1:1 do par via `rpc_oneonone_complete_meeting`. Anti-cascata: não copia carry de carry.
- **RH prestadora** (Larissa Labuta) vê apenas pairs onde `led_employer_unit_id` está no escopo dela via `user_permission_scopes`. Multi-tenant tripartite preservado.

### Hierarquia de visibilidade

| Persona | Vê dados de... |
|---|---|
| Colaborador | Si mesmo |
| Líder | Si mesmo + subordinados diretos (recursivo opcional via flag `hierarchy_scope='recursive'`) |
| RH Prestadora | Funcionários com `employer_unit_id = scope_employer` |
| RH GPC | Todos do tenant |
| Diretoria | Todos do tenant (read-only) |
| DPO | Todos do tenant + audit log + ferramentas de retenção |

### Folha & Custo · Legislação versionada

Todos os cálculos de custo do colaborador (calculadora individual e folha por filial) usam **constantes legais versionadas por ano**, evitando recalcular simulações antigas com tabelas atuais.

- **Tabela INSS empregado** segue Portaria Interministerial MPS/MF (atualizada anualmente em janeiro)
- **IRRF** segue tabela vigente da Receita Federal · 2026 incorpora isenção até R$ 5k da Lei 15.270/2025
- **Encargos patronais** dependem do regime tributário (`tax_regime` na tabela `units`):
  - Lucro Real / Lucro Presumido: ~67% sobre folha (com provisões e cascata)
  - Simples Nacional Anexos I-III: ~30% (encargos no DAS)
- **Provisões mensais** independem do regime: férias 11,11% · 13º 8,33% · multa rescisória 4%
- Na futura `legal_tax_tables`, toda simulação salva referencia o `legal_year` para auditabilidade

**Regra prática para o GPC**: ATP Varejo, ATP Atacado, Cestão Loja 1, Cestão Inhambupe e Sede operam em Lucro Real · Labuta, Limpactiva e Segure (prestadoras) operam em Simples Nacional. Por isso o custo de um repositor da Labuta alocado no Cestão é ~30% maior que o salário, enquanto o de um operador GPC direto seria ~67% maior · diferença que justifica economicamente a estrutura de terceirização.

### Notificações

Sempre **in-app only** no MVP (não envia e-mail/SMS por escolha de produto, reduz custo e risco LGPD). Tabela `notifications` com 5 tipos principais.

### Idioma

PT-BR exclusivo. Todas as strings hardcoded em português, sem framework de i18n no MVP.

### Sem em-dashes

Regra de estilo do Ricardo: **nunca** usar `--` (em-dash) em textos. Usar `:` ou `·` (middot) ou `-` (hífen simples).

### Contraste

**Nunca texto branco em fundo cinza** (baixo contraste). Em backgrounds claros ou cinza, sempre texto escuro.

---

## 10. Parking lot (próximas imersões candidatas)

Itens já discutidos, mas ainda não construídos. Atualizado em v2.4 após entrega do Módulo 11 (1:1s).

### Telas
- **PDI com plano de ação** (alta prioridade · gap importante vs Sólides/Qulture)
- **Pesquisa de clima por pulsos curtos** (1 pergunta semanal · base para módulo de Engajamento)
- **9-Box / Matriz de talentos** (visual atrativo para demos)
- **OKRs com check-ins semanais**
- **eNPS + termômetro emocional**
- **Cargos & Salários estruturado** com matriz
- **Trilhas de treinamento e certificações**
- **Onboarding por papel** (extensão do que já existe)
- **Modal de programação de férias** (wizard com fracionamento + abono + 13º) · fecha CRUD do módulo Férias
- **Tela de movimentações de afastamento** gerada automaticamente do atestado validado
- **Calculadora de férias** no autoatendimento do colaborador (saldo, projeção, abono)
- **Banco de talentos / vagas internas**
- **Programa de indicação** (caso GPC)
- **Comunicados internos**

### Backend
- **Schema v7 (Férias formal)** consolidando: `vacation_acquisition_periods`, `vacation_periods` com fracionamento, `achievement_definitions` + `user_achievements`, `mv_vacation_planning_overview` materialized view
- Job `cron.schedule` diário para alertar férias vencendo 90/60/30 dias
- Edge function `process-medical-certificate` (real, não mock) com Tesseract WASM real
- Job de refresh da view materializada às 6h
- Tabela `cid_codes` populada (10mil+ códigos CID-10 oficiais)
- **Schema futuro · PDI**: tabelas `pdi_plans`, `pdi_actions`, `pdi_milestones` com vinculação a `oneonone_action_items` (PDI vira fonte de AIs específicas)
- **Schema futuro · Engajamento**: `pulse_questions`, `pulse_responses`, eNPS por filial

### Documentação
- **Pitch deck comercial** para vender o R2 People para PMEs
- **Modelo de proposta comercial** (template Word com cláusulas, escopo, prazos)
- **Termos de uso** (complemento jurídico da política de privacidade já existente)
- **Manual do administrador** (white-label do tenant)
- **Política específica de 1:1s** complementando `privacy_policy.md` · explicar visualmente o modelo de 3 camadas (privado/compartilhado/agregado RH)

### Decisões de produto pendentes
- Política de retenção de fotos de perfil (LGPD)
- Política de exclusão de conta (DSAR Art. 18 detalhado)
- Modelo de billing (per-seat? per-tenant? freemium?)
- Estratégia de versionamento do schema (zero-downtime migrations?)
- **Folha externa**: qual ERP, periodicidade, granularidade, mapeamento de campos
- **Banco de horas externo**: API ou CSV, granularidade, qual sistema de ponto
- **Cartão Flash**: mapeamento de categorias para buckets de custo (salarial, PAT, indenizatório, adiantamento)
- **Tipos de vínculo** (`tipo_vinculo` ENUM): clt | estagio | jovem_aprendiz | pj | socio | diarista | intermitente · cada um com ciclo de vida e fontes de dados próprios

### Itens entregues nesta versão (v2.4)
- ✓ 1:1s estruturadas com PDI sendo gap reconhecido (mas não implementado nesta rodada)
- ✓ Schema metas v5 (anteriormente listado como "Schema v5" no parking lot)
- ✓ Sidebars atualizadas em 27 telas

### Itens entregues parcialmente na camada Next.js (catalogados em v2.5)

A codebase Next.js já implementou backend e UI parciais para os seguintes módulos (ver §14 para mapa de paridade completo):
- ✓ Ficha de empregado (`/pessoas`, `/pessoas/[id]`, `/pessoas/novo`)
- ✓ Importação OCR (`/pessoas/importar` + worker FastAPI)
- ✓ Avaliações 9-Box (schema + RPCs prontos · UI parcial)
- ✓ PDI (schema + RPCs + edição inline)
- ✓ Reconhecimentos (público/privado · UI de enviados)
- ✓ Onboarding (templates · UI inline edit pendente)
- ✓ Dashboards (equipe + tenant + drilldown)
- ✓ Minha jornada (G1)
- ✓ Solicitações de mudança de perfil (G3)
- ✓ Admin de módulos por tenant
- ✓ Storage de PDFs com retenção 30d

---

## 11. Decisões deliberadas de fora-de-escopo

Estas funcionalidades **não serão construídas** no R2 People. Não são esquecimentos nem dívida técnica: são escolhas de produto conscientes, registradas aqui para evitar discussão recorrente.

### Sem integração com ERP (TOTVS WinThor, etc.)

**Decisão**: o R2 People permanece como sistema paralelo. Sem sincronização automática de cadastros, folha, ou outros dados do ERP.

**Por quê**:
- Mantém o produto independente de ERPs específicos · facilita revender para outras PMEs sem amarração técnica
- Elimina complexidade de OAuth, webhook, mapeamento bidirecional de schemas
- Reduz risco operacional (sincronização inconsistente é fonte clássica de bugs em RH-tech)
- Importação via CSV manual já cobre 90% do caso de uso (vide `r2_people_importacao.html` com wizard de 5 passos e dry-run)

**Implicações**:
- Cadastros de colaboradores precisam ser mantidos manualmente quando há mudanças no ERP (admissão, demissão, promoção)
- A tela `importacao.html` é o ponto único de entrada em massa
- Customers que precisem de sincronização ERP↔R2 People precisam de projeto dedicado, fora do escopo do produto base

### Sem perfil público do colaborador

**Decisão**: não há "página de perfil" visível para colegas. O R2 People não é uma rede social interna.

**Por quê**:
- Reforça posicionamento de **ferramenta de RH operacional**, não plataforma de engajamento
- Reduz superfície de exposição LGPD (menos dados visíveis = menos risco)
- Simplifica modelo de permissões (não precisa pensar em "o que aparece no perfil para colegas vs gestores vs RH")
- Elimina categoria inteira de moderação (foto inapropriada, bio ofensiva, etc.)
- Elimina debate sobre engajamento social (likes, comentários, badges públicos)

**Implicações**:
- Apelido (`@Fê`, `@Bia`) **continua existindo** porque tem função operacional clara: chave de busca + identificação em listas e atribuições
- Apelido **não** vira link clicável que abre página dedicada · só aparece em contexto operacional
- Mural (`feedback_mural.html`) **continua** existindo porque tem função explícita de reconhecimento profissional, não rede social
- Avatar e nome aparecem em listas, mas sem clique-para-perfil
- Conquistas (em `minha_trajetoria.html`) são **só para o próprio usuário ver**, não exibidas para colegas

### Sem notificações por e-mail/SMS no MVP

**Decisão**: notificações são apenas in-app.

**Por quê**:
- Reduz custo (sem provedor de e-mail transacional, SMS gateway)
- Reduz risco LGPD (e-mail e SMS são canais menos seguros para dados de RH)
- Simplifica configuração (não precisa de SPF/DKIM/DMARC, opt-in/opt-out, anti-spam)
- App-first significa que usuário aprende a abrir o sistema regularmente

**Implicações**:
- Notificações urgentes dependem do usuário entrar no sistema · alertas críticos (ex: aprovação pendente de movimentação) precisam ser visíveis em badges no menu
- Roadmap pós-MVP pode reavaliar e-mail para casos específicos (recuperação de senha, convite, ausência prolongada)

### Sem app nativo iOS/Android no MVP

**Decisão**: web responsivo (PWA) é o suficiente.

**Por quê**:
- Custo de manter 3 codebases (web + iOS + Android) é proibitivo no MVP
- App stores adicionam fricção (review, atualizações, contas de developer)
- 100% das funcionalidades-chave funcionam em mobile web
- A tela de envio de atestado (`atestado_envio_lider.html`) já demonstra o uso de câmera nativa via `<input type="file" capture="environment">`

**Implicações**:
- Sem push notification nativa · usuário recebe apenas in-app
- Sem geolocalização precisa (ponto eletrônico não está no escopo)
- Sem leitura biométrica · login via senha + magic link (futuro)
- Roadmap pós-MVP: avaliar Capacitor ou wrapper Median.co se houver demanda real

### Sem multi-idioma no MVP

**Decisão**: PT-BR exclusivo. Sem framework de i18n.

**Por quê**:
- Mercado-alvo (PMEs brasileiras) usa exclusivamente português
- i18n adiciona complexidade no código (chaves de tradução, fallbacks, plurais, formatação de datas/moedas)
- CLT, eSocial, CAGED, INSS são todas regulações brasileiras · adaptar para outros países exigiria reformular o domínio inteiro

**Implicações**:
- Strings hardcoded em PT-BR no código
- Internacionalização futura (se houver) seria projeto dedicado, não retrofit

---

## 12. Histórico de versões do INDEX

| Versão | Data | Mudanças |
|---|---|---|
| 1.0 | abril 2026 | Versão inicial · 30 artefatos · 9 categorias |
| 2.0 | 28 abr 2026 | 39 artefatos · módulos funcionais · matriz de dependências · fluxos detalhados |
| 2.1 | 28 abr 2026 | Adicionada §11 "Decisões deliberadas de fora-de-escopo" registrando que TOTVS WinThor, perfil público, notificações por e-mail, app nativo e multi-idioma estão fora do escopo conscientemente |
| 2.2 | 29 abr 2026 | 41 artefatos · novo Módulo 10 Folha & Custo (calculadora individual + folha por filial) · Renato aparece em 2 telas · Fluxo F dissídio coletivo · regra-chave de legislação versionada 2026 |
| 2.3 | 29 abr 2026 | 42 artefatos · adicionada tela de regime tributário por unidade ao Módulo 10 (CRUD com modal de confirmação dupla + audit log + validações fiscais) · Patrícia ganha permission `manage_tax_regime` (10 telas) · Fluxo G mudança de regime por crescimento · matriz de dependências mostra regime_tributario como fonte de verdade do `units.tax_regime` |
| 2.4 | 1 mai 2026 | 57 artefatos · novo Módulo 11 1:1s estruturadas (4 telas: hub do líder, sala dual, visão do liderado, visão RH agregada) · novo schema_oneonones_v6.sql com 6 tabelas, 7 enums, 25 RLS policies privacidade-enforced, 3 views agregadas, 8 RPCs SECURITY DEFINER · sidebars atualizadas em 27 telas (idempotente via marker) · Patrícia +2 permissions (view_oneonones_metadata, send_oneonone_messages, 11 telas), João +1 (manage_oneonone_pairs, 8 telas), Larissa +1 (view_oneonones_metadata_by_employer, 4 telas), Fernanda 9 telas · Fluxo H 1:1 quinzenal · nova regra de privacidade transversal "1:1s estruturadas" no §9 · novo doc analise_correcoes.md catalogado · schema_metas_v5 também listado (já entregue antes mas faltava no índice) |
| 2.5 | 17 mai 2026 | **Fusão de repositórios** · codebase Next.js + Supabase + worker OCR (anteriormente em `r2_people_repo.zip` separado) movida pra este mesmo repositório · adicionadas pastas `src/` (12 páginas + componentes + adapter TS), `supabase/migrations/` (32 arquivos), `supabase/tests/` (20 arquivos · 170 testes passando), `worker/` (FastAPI OCR), `docs/` (22 sessões a1-l) · `README.md` substituído pelo da codebase Next.js (era stub de 31 bytes) · `MIGRATION_PROMPT.md` adicionado na raiz · `package.json.example`, `tsconfig.json`, `tailwind.config.ts`, `.env.example`, `.gitignore` adicionados · §2 reformulado em duas camadas · nova §14 com mapa de paridade HTMLs ↔ Next.js · §10 atualizado com itens já implementados na camada Next.js · sem mudança nos 42 HTMLs ou nos schemas de design |
| 2.6 | 17 mai 2026 | **Sessão de specs + parking lot** · 4 specs detalhadas para próximas sessões em ambiente com Postgres: `docs/spec_d1_auth.md` (Supabase Auth real), `docs/spec_m1_estrutura_acessos.md`, `docs/spec_m3_atestados.md`, `docs/spec_m7_oneonones.md` · cada spec inclui migrations, RPCs, testes, adapter TS, páginas Next.js, critérios de aceitação e pontos de atenção · 2 HTMLs novos do parking lot: `r2_people_pdi.html` (módulo completo PDI com 3 personas togláveis, hero, KPIs, lista de ações, histórico) e `r2_people_ferias_programar.html` (wizard CLT de programação de férias com 3 passos: datas/fracionamento, abono+13º, confirmar · validações Art. 134/135) · 2 docs MD novos: `r2_people_privacy_oneonones.md` (modelo de 3 camadas de privacidade complementando a privacy_policy geral) e `r2_people_pitch_deck.md` (15 slides + FAQ pra material comercial) · auditoria leve: 28 em-dashes substituídos em arquivos novos e atualizados (specs + README + INDEX) · pasta vazia `r2_people_export/` removida |
| **2.7** | **17 mai 2026** | **Continuação specs + parking lot + docs jurídicos/admin** · 3 specs novas: `docs/spec_m2_movimentacoes.md` (workflow promoção/transferência/aumento com aprovação RH), `docs/spec_m4_ferias.md` (schema v7 com vacation_acquisition_periods + vacation_periods + view materializada + regras CLT enforced no banco), `docs/spec_m6_folha_custo.md` (legislação 2026 versionada em `legal_tax_tables`, funções SQL `calc_inss`/`calc_irrf`, 4 telas Folha & Custo + Regime tributário) · 1 HTML novo: `r2_people_9box.html` (matriz 3×3 colorida com 9 caixas, bubbles dos colaboradores, modal de drill por caixa com lista detalhada, histórico de ciclos, toggle 3x3↔5x5) · 2 docs MD comerciais/jurídicos: `r2_people_terms_of_service.md` (17 seções: aceite, RBAC, conta, uso aceitável, SLA, IP, LGPD, encerramento, retenções legais, foro Salvador BA) e `r2_people_admin_manual.md` (12 seções + glossário: conceitos, setup primeiro acesso, estrutura organizacional, RBAC, módulos, tarefas frequentes, importação CSV/OCR, LGPD/DSAR, troubleshooting comum, quando chamar suporte R2) · em-dashes auditados em todos os novos artefatos |

---

## 13. Como navegar este conjunto

**Para entender a arquitetura**: leia `architecture_roadmap.md` → `schema_v4.sql` → `rls_policies_detailed.sql`

**Para ver o produto em ação**: abra `home.html` e navegue pelas personas. Os links internos (sidebar) referenciam as outras telas.

**Para entender LGPD**: `privacy_policy.md` → `auditoria.html` → seção §5 deste INDEX (Atestados)

**Para vender ou apresentar**: parking lot tem o pitch deck pendente. Por ora, use `home.html` (RH view) + `historico_consulta.html` + `ferias_programacao_anual.html` como demos de alto impacto.

**Para construir backend**: ordem dos arquivos SQL: schema_v3 → schema_v4 → rls_policies_detailed → seed_initial. Aplicar em transação. Testar com os 6 cenários do `rls_policies_detailed.sql`.

**Para entender personas e RLS**: a tela `historico_consulta.html` tem o **toggle de personas mais didático** do conjunto, demonstrando RLS ao vivo. A `ferias_programacao_anual.html` tem o segundo melhor demo (3 personas).

---

*Este INDEX é mantido manualmente conforme novos artefatos são adicionados. Sempre atualizar a contagem total no §2, adicionar entrada no §4 (módulo apropriado), atualizar matriz §7 se houver dependência nova, e mover item do parking lot §10 para a categoria correspondente.*

---

## 14. Relação entre Camada 1 (HTMLs) e Camada 2 (Next.js)

A partir de v2.5 o repositório hospeda as duas representações do produto no mesmo lugar. Elas têm papéis diferentes:

### Camada 1 · HTMLs (`r2_people_*.html`)

- **Papel**: fonte de verdade visual e funcional para validação com Karla/Ricardo/clientes
- **Deploy**: GitHub Pages em `rh.solucoesr2.com.br` (via `CNAME`)
- **Tech**: single-file HTML + Tailwind inline + Sora/JetBrains Mono · sem build, sem backend
- **Quando alterar**: ao desenhar nova tela, ao validar UX com cliente, ao iterar layout
- **Vantagem**: deploy instantâneo, zero infra, qualquer pessoa abre e navega

### Camada 2 · Next.js (`src/`, `supabase/`, `worker/`)

- **Papel**: implementação produtiva real, multi-tenant, com RLS e testes
- **Deploy**: Vercel (frontend) + Supabase (Postgres + Auth + Storage) + container Docker (worker OCR) · ainda não em prod
- **Tech**: Next.js 14 App Router + TS strict + Tailwind + Supabase JS SDK + FastAPI
- **Quando alterar**: ao implementar feature real após validação visual na Camada 1
- **Vantagem**: integridade de dados, segurança LGPD, testes automatizados

### Mapa de paridade · 12 páginas Next.js vs 42 HTMLs

**Já implementado nas duas camadas:**

| HTML rhgpc | Página Next.js |
|---|---|
| `colaborador.html` | `src/app/pessoas/[id]/page.tsx` |
| `colaboradores_lista.html` | `src/app/pessoas/page.tsx` |
| `colaborador_home.html` + `minha_trajetoria.html` | `src/app/minha-jornada/page.tsx` |
| `importacao.html` | `src/app/pessoas/importar/page.tsx` + worker |
| `admin_dashboard.html` | `src/app/dashboard/page.tsx` + drill |
| `feedback_mural.html` (parcial · só enviados) | `src/app/meus-reconhecimentos/page.tsx` |
| (team view) | `src/app/minha-equipe/page.tsx` |
| (G3 profile change) | `src/app/admin/aprovacoes/page.tsx` |

**Só na Camada 1 (HTMLs) · 30 telas aguardando portabilidade pra Next.js:**

| Grupo | HTMLs | Sessão sugerida |
|---|---|---|
| Auth & Onboarding | `login`, `onboarding`, `error_pages` | D1 (crítica para deploy) |
| Estrutura & Acessos | `estrutura`, `acessos` | M1 |
| Movimentações | `movimentacoes`, `aprovacoes_rh`, `colaborador_movimentacoes` | M2 |
| Atestados | `atestados`, `atestado_envio_lider`, `atestado_validacao_dp`, `atestado_colaborador` | M3 |
| Férias | `ferias`, `ferias_programacao_anual`, `afastamentos` | M4 |
| Avaliações & Feedback (UI) | `ciclos`, `avaliacao`, `feedback_mural` (recebidos) | M5 |
| Folha & Custo | `calculadora_custo`, `folha_por_filial`, `regime_tributario`, `comparar_cenarios` | M6 |
| 1:1s | `oneonones`, `oneonone_room`, `minhas_1on1s`, `oneonones_rh` | M7 |
| Metas (OKR) | `metas`, `minhas_metas`, `lancamento_resultado`, `validacao_resultado` | M8 |
| Relatórios & Auditoria | `relatorios`, `auditoria` | M9 |
| Configurações | `configuracoes` | M10 |
| Histórico de consulta | `historico_consulta` | M11 |
| Utilitárias/showcase | `home`, `demo`, `empty_states` | opcional |

### Schemas SQL · design vs aplicado

| Camada | Arquivos | Estado |
|---|---|---|
| Design (raiz) | `r2_people_schema.sql` (v1) → `_v2.sql` → `_v3.sql` → `_v4.sql` → `_metas_v5.sql` → `_oneonones_v6.sql` + `_rls_policies_detailed.sql` + `_rpc_report_builder.sql` + `_seed_initial.sql` + `_medical_certificates_schema.sql` | Blueprint completo · não aplicado |
| Aplicado (`supabase/migrations/`) | 32 migrations incrementais (00010_h → 00361_g3) | Aplicáveis · 170 testes passando |

Os schemas de design da raiz cobrem **mais módulos** (atestados v4, metas v5, 1:1s v6, regime tributário) do que as migrations aplicadas (que cobrem o core até G3). Os primeiros servem de blueprint para portar os módulos restantes em sessões M1-M11.

### Fluxo recomendado para próximas sessões

```
1. Desenhar/iterar na Camada 1 (HTML)        ── validar com cliente
2. Aprovar visualmente
3. Portar pra Camada 2 (Next.js + Supabase)  ── implementar com testes
4. Documentar em docs/sessao_mX.md
5. Atualizar este INDEX (§4 e §10)
```

A Camada 1 não morre quando a feature é portada · ela continua servindo como spec visual viva e como ambiente de demo rápida para vendas.

---

## 15. Inventário Camada 1 v2.8 (atualizado)

### Shell compartilhado (NOVO em v2.8)

| Arquivo | Conteúdo |
|---|---|
| `assets/r2-shell.css` | ~380 linhas · dark mode (`[data-theme="dark"]`), density compacta (`[data-density="compact"]`), sidebar collapse (`[data-sidebar="collapsed"]`), topbar actions, bell badge, notif dropdown, search overlay, user dropdown, page-header padrão Cofre |
| `assets/r2-shell.js` | ~360 linhas · boot (aplica prefs antes do render), mobile drawer, atalhos teclado, search com índice de 39 páginas, bell com 5 notificações mock, user dropdown |
| `assets/gpc-color.png` / `.svg` | Logo GPC oficial (PNG 137 KB · SVG aproximação) |
| `assets/gpc-white.png` | Variante branca pra fundos escuros |
| `assets/r2-color.png` / `r2-white.png` | Logo R2 Soluções |
| `assets/favicon.svg` | Favicon GPC navy/orange compacto |

### Atalhos de teclado (cross-page · via shell)

| Atalho | Ação |
|---|---|
| `Cmd/Ctrl + K` ou `/` | Abrir search global |
| `Cmd/Ctrl + J` | Toggle dark mode |
| `Cmd/Ctrl + Shift + K` | Toggle density compacta |
| `Cmd/Ctrl + B` | Toggle sidebar collapse (desktop) |
| `Esc` | Fechar overlays (search, drawer, dropdown) |
| `↑ ↓ ↵` | Navegar no search |

### Páginas (57 HTMLs · catalogadas por área)

#### Você (5)
- `r2_people_login.html` · login + SSO Microsoft
- `r2_people_onboarding.html` · wizard 5 passos primeiro acesso
- `r2_people_minha_trajetoria.html` ⭐ · trajetória pessoal gamificada
- `r2_people_colaborador_home.html` · home pessoal
- `r2_people_notificacoes.html` 🆕 · caixa de notificações com filtros

#### Comunicação (3)
- `r2_people_comunicados.html` 🆕 · feed editorial estilo intranet
- `r2_people_feedback_mural.html` · mural + feedback contínuo
- `r2_people_minhas_1on1s.html` · 1:1s visão liderado

#### Pessoas / Estrutura (5)
- `r2_people_colaborador.html` ⭐ · cadastro/edição com Apelido
- `r2_people_colaboradores_lista.html` · listagem com filtros
- `r2_people_estrutura.html` · Filiais + Departamentos + Cargos
- `r2_people_cargos_salarios.html` 🆕 · matriz salarial estruturada
- `r2_people_historico_consulta.html` ⭐ · search-driven UI (Linear/Raycast)

#### Desempenho (8)
- `r2_people_ciclos.html` · ciclos de avaliação
- `r2_people_avaliacao.html` · avaliação dual auto+gestor
- `r2_people_pdi.html` 🆕 · PDI com 3 personas togláveis
- `r2_people_9box.html` 🆕 · matriz de talentos 3×3 interativa
- `r2_people_okrs.html` 🆕 · objetivos + key results + check-ins
- `r2_people_metas.html` · Metas v5
- `r2_people_oneonones.html` ⭐ · hub líder
- `r2_people_oneonone_room.html` ⭐ · sala 1:1 dual

#### Movimentações (3)
- `r2_people_movimentacoes.html` · líder solicita
- `r2_people_aprovacoes_rh.html` · RH aprova
- `r2_people_colaborador_movimentacoes.html` · colaborador acompanha

#### Vida & Saúde (8)
- `r2_people_atestados.html` · hub atestados
- `r2_people_atestado_envio_lider.html` ⭐ · envio com OCR client-side
- `r2_people_atestado_validacao_dp.html` ⭐ · validação DP
- `r2_people_atestado_colaborador.html` · autoenvio
- `r2_people_afastamentos.html` · gestão de afastamentos
- `r2_people_ferias.html` ⭐ · Gantt + lista
- `r2_people_ferias_programacao_anual.html` ⭐ · programação anual
- `r2_people_ferias_programar.html` 🆕 · wizard CLT 3 passos

#### Pesquisas (2)
- `r2_people_clima.html` 🆕 · pulso semanal com 5 moods + heatmap
- `r2_people_enps.html` 🆕 · Employee NPS quinzenal

#### Carreira (3)
- `r2_people_vagas.html` 🆕 · banco de talentos + indicações
- `r2_people_indicacoes.html` 🆕 · suas indicações + ganhos
- `r2_people_treinamentos.html` 🆕 · trilhas LMS-style

#### Folha & Custo (5)
- `r2_people_calculadora_custo.html` ⭐ · individual com slider
- `r2_people_folha_por_filial.html` ⭐ · agregada por unidade
- `r2_people_comparar_cenarios.html` · A/B de cenários
- `r2_people_regime_tributario.html` ⭐ · CRUD tax_regime
- `r2_people_lancamento_resultado.html` · líder lança realizado de meta

#### Análise (3)
- `r2_people_admin_dashboard.html` · dashboard RH agregado
- `r2_people_relatorios.html` ⭐ · report builder EMP/TOM
- `r2_people_oneonones_rh.html` ⭐ · 1:1s visão RH agregada

#### Administração (7)
- `index.html` · admin de módulos (entry point Pages)
- `r2_people_tenants.html` 🆕 · cadastro de clientes (super_admin)
- `r2_people_acessos.html` · perfis de permissão
- `r2_people_auditoria.html` · audit log + DSAR
- `r2_people_configuracoes.html` · tenant settings
- `r2_people_importacao.html` · CSV + OCR Domínio
- `r2_people_minhas_metas.html` · metas pessoais

#### Utilitárias / Validação (5)
- `r2_people_minhas_metas.html` · metas pessoais
- `r2_people_validacao_resultado.html` · gestor valida
- `r2_people_home.html` · hub togglável 3 personas
- `r2_people_demo.html` · demo único
- `r2_people_empty_states.html` · 5 estados togláveis
- `r2_people_error_pages.html` · 5 estados togláveis (404/403/500/offline/expired)

🆕 = adicionado em v2.6, v2.7 ou v2.8
⭐ = página complexa com features destacadas

### Docs MD (10)
- `r2_people_INDEX.md` ⭐ · este
- `r2_people_architecture_roadmap.md`
- `r2_people_privacy_policy.md` · LGPD geral
- `r2_people_privacy_oneonones.md` 🆕 · LGPD específica de 1:1s (3 camadas)
- `r2_people_terms_of_service.md` 🆕 · 17 seções
- `r2_people_admin_manual.md` 🆕 · 12 seções + glossário
- `r2_people_pitch_deck.md` 🆕 · 15 slides comercial
- `r2_people_modelo_proposta.md` 🆕 · template editável
- `r2_people_wireframes_mvp.md`
- `r2_people_analise_correcoes.md`

### Specs técnicos pra próximas sessões com Postgres (em `docs/`)
- `spec_d1_auth.md` 🆕 · Supabase Auth real
- `spec_m1_estrutura_acessos.md` 🆕 · CRUD organizacional
- `spec_m2_movimentacoes.md` 🆕 · workflow aprovação
- `spec_m3_atestados.md` 🆕 · schema v4 LGPD Art. 11
- `spec_m4_ferias.md` 🆕 · schema v7 CLT
- `spec_m6_folha_custo.md` 🆕 · legislação 2026 versionada
- `spec_m7_oneonones.md` 🆕 · 25 RLS privacy-enforced

---

## 16. Histórico de versões resumido (mais detalhes em §12)

| Versão | Principais entregas |
|---|---|
| 2.4 | Módulo 1:1s estruturadas (4 telas + schema v6) |
| 2.5 | Fusão de repositórios (Camada 1 HTMLs + Camada 2 Next.js) |
| 2.6 | 4 specs técnicas + 2 HTMLs parking lot + docs comerciais |
| 2.7 | 3 specs adicionais + 9-Box visual + termos/manual |
| 2.8 | Identidade visual Cofre + 12 páginas novas + shell compartilhado |
| 2.9 | Showcase entry-point + 3 specs (M5/M8/M9) + schema v9 + privacy atestados |
| 2.10 | Spec M10 Configurações + schema v10 consolidado (movs+auth+settings+history) |
| 2.11 | Spec D4 Backups/DR + Spec M12 Notif/Webhooks runtime (filas pgmq + HMAC + DLQ) |
| 2.12 | Spec D5 Observabilidade (Logflare + Prom + Tempo + 7 SLOs + 10 alertas + runbooks) |
| 2.13 | Spec D6 Segurança aplicacional (CSP A+, OWASP Top 10, secrets, pen-test, 25+ testes meta) |
| 2.14 | Spec D7 Compliance LGPD playbook (DPO routines, ROPA, DSAR runbook, retenção, ANPD) |
| 2.15 | Schema SQL v11 (Observability + Security + Compliance · materializa D5+D6+D7 em SQL executável) |
| 2.16 | Página HTML cockpit LGPD do DPO (6 abas: DSAR + ROPA + Retenção + Consents + Sub-ops + Treinamentos) |
| 2.17 | Página HTML admin Notif & Webhooks (6 abas: Webhooks + Filas + E-mails + DLQ + Stats + Catálogo) |
| 2.18 | Página HTML Observability admin (7 SLOs c/ budget bars + incidentes + alertas + métricas + logs stream + drill-down) |
| 2.19 | Página HTML Security DevSec Console (score 92/100 + hardening 16/18 + CVEs + CSP + honeytokens + OWASP Top10 + secrets rotação) |
| 2.20 | Página HTML Hub Admin (entry-point dos 4 cockpits operacionais + status banner + quick actions + atividade recente cross-cockpit) |
| 2.21 | Spec M13 Onboarding Wizard do tenant (7 passos obrig + 4 opcionais + tenant_onboarding state + microcopy PT-BR + 22 testes meta) |
| 2.22 | Página HTML Tenant Setup wizard (timeline 7 passos + step card passo 4 + pré-views MFA/branding/política · materializa M13) |
| 2.23 | Schema SQL v12 (Onboarding + Billing + Quotas · materializa M13 + adiciona plans/subscriptions/invoices/seats c/ enforcement) |
| 2.24 | Página HTML Billing & Plano (hero plano vigente + 5 quotas vivas + faturas + métodos pagto + seats + 3 planos compare + usage log) |
| 2.25 | Página HTML DR Console (postura hero + 4 RPO/RTO tiers + 6 abas: backups multi-camada + retenção + 4 cenários + drills + smoke + dr_events) |
| 2.26 | Hub Admin atualizado para 6 cockpits (grid 3x2 + Billing + DR cards + status banner 6 pills + 2 quick actions novos) |
| 2.27 | Spec C1 · Comercial & Sales Playbook (1ª da série C · funil 6 estágios + BANT-C + 10 objeções + pricing público + plano 30/60/90 + meta R$ 68k MRR ano 1) |
| 2.28 | Página HTML Preços públicos · landing comercial (toggle mensal/anual + 3 planos compare + 5 add-ons + tabela detalhada 22 linhas + 8 FAQs + CTA bottom) |
| 2.29 | Página HTML Landing principal comercial (hero + mockup app + 6 pain points + 3 pilares + stats faixa + case GPC + 12 módulos + final CTA · fecha funil de aquisição) |
| 2.30 | Spec C2 Customer Success Playbook (health score 8 sinais + 5 categorias champion→critical + plano 30/60/90 + 4 intervenções + expansão MRR + 22 testes meta · fecha série C) |
| 2.31 | PADRONIZAÇÃO COFRE batch · 4 commits · ~50 páginas refatoradas para padrão visual único (sidebar centralizada + mono sections + ::before bar active + footer "Desenvolvido por R2" + topbar mono + page-eyebrow utility) · 4 scripts PowerShell idempotentes em scripts/ |
| 2.32 | Página CS Dashboard · materializa spec C2 já no padrão Cofre desde o início (carteira 5 tenants + distribuição + 3 intervenções priorizadas + 5 hooks expansão + 4 renovações + 10 KPIs) · persona Marina Carvalho CSM Sênior |
| 2.33 | Hub Admin atualizado para 7 cockpits (adiciona CS Dashboard · status banner 7 pills · quick actions 9 botões) |
| 2.34 | Spec D8 Multi-tenant Isolation Patterns (5 padrões policy + framework pgtap + attack matrix 20 ataques + rls_denial_log + auditoria checklist + storage/realtime/edge isolation + 25+ testes meta · fecha D-series com D2-D8) |
| 2.35 | Spec M14 Webhooks Inbound (par com M12 outbound) · endpoint HMAC + 9 sistemas suportados (Senior/Totvs/Sankhya/AD/Dimep/etc) + 4 handlers padrão (payroll/AD/attendance) + dedupe via inbound_event_dedupe + rate-limit 3 camadas + RLS signing_secret protegido + 25+ testes meta |
| 2.36 | Schema SQL v13 (Isolation + Inbound) materializa D8+M14 em SQL executável · rls_denial_log c/ auto-classify + 4 tabelas inbound + 4 handlers RPC + HMAC validator + create_endpoint c/ secret gen + rotate_secret + cleanup TTL · seeds 11 handlers mapeados · RLS c/ signing_secret REVOKE authenticated |
| 2.37 | Spec D9 API Pública (REST v1 + GraphQL + SDKs TS/Python/PHP/Go) · 22 resources REST + 3 métodos auth (JWT/ApiKey/OAuth) + idempotency-key + rate-limit 3 camadas por plano + RFC 7807 errors + cursor pagination + versioning policy 24m + 3 tabelas (api_keys/idempotency/usage_log) + 30+ testes meta |
| 2.38 | Página HTML API Console · materializa spec D9 (5 KPIs uso + 6 abas: API Keys table + Usage chart 14d + Endpoints catalog + SDKs quickstart TS/Python/PHP/Go + GraphQL Explorer link Apollo Sandbox + Webhooks shortcut) · persona Diego Ito Dev Integrações · already no padrão Cofre |
| 2.39 | Hub Admin atualizado para 8 cockpits (adiciona API Console gradient blue-purple) · status banner 8 pills + quick actions 10 botões · agora cobre todo o ecossistema operacional R2 People |
| 2.40 | Schema SQL v14 (API Pública) materializa D9 em SQL executável · api_keys c/ bcrypt cost 12 + key_prefix lookup indexado + idempotency_keys TTL 24h + api_usage_log particionado · 8 RPCs (create/validate/revoke/idempotency check+save/log_request/cleanup/stats) + view v_api_keys_safe + RLS c/ key_hash REVOKE FROM authenticated + GRANTs por coluna |
| 2.41 | Spec M15 Mobile-first PWA · decisão PWA-first vs nativo + Next.js Service Worker + manifest c/ shortcuts e Share Target + offline-first c/ outbox pattern e conflict resolution + Web Push c/ quiet hours + WebAuthn biometria + câmera+OCR client-side + 25+ testes meta + roadmap nativo M+3 |
| 2.42 | Spec C3 Marketing & Content (fecha série C trio Marketing/Sales/CS) · 5 pilares conteúdo (CLT/Gestão/LGPD/Calculadoras/Cases) + SEO long-tail PME + webinar mensal c/ 12 pautas + partner program 4 tiers (Referral/Affiliate/Reseller/Strategic) + meta 25k tráfego + R$ 68k MRR · CAC R$ 250 vs R$ 800 outbound · 18+ testes meta |
| 2.43 | Relatório consolidado da sessão autônoma 17-18/05 · `docs/sessao_autonoma_2026_05_18_relatorio.md` documenta 43 commits + 20 specs + 6 schemas SQL + 8 cockpits + padronização Cofre 50 páginas + 3 dimensões completas (produto/operação/comercial) + roadmap próximas sessões |
| 2.44 | Reposicionamento estratégico (R2 = gestão de pessoas, NÃO DP · Domínio é fonte fiscal) + Spec M17 People Analytics + Spec M16 Integração Domínio ESPECULATIVA |
| 2.45 | Aniversariantes destacados na home + C1/C3 v1.1 reposicionado + landing hero refeito |
| 2.46 | Spec M18 Compliance & Treinamentos + Spec M19 Benefícios & Dependentes + Schema SQL v15 |
| 2.47 | Página HTML Analytics M17 + Spec M20 Inbox Líder + Hub 9 cockpits |
| 2.48 | Página HTML Inbox do Líder (M20) · persona João Carvalho 11 subordinados |
| **2.49** | **Página HTML `r2_people_compliance.html` materializa M18 (persona Patrícia Mello Coord RH · score 78/100 hero c/ ring SVG · 5 KPIs ASOs/EPIs/treinamentos/termos · 6 abas: ASOs 60d c/ Pedro Souza bloqueador + EPIs 2 assinaturas pendentes + matriz cargo + Heatmap treinamentos NR por filial 6 filiais × 8 normas c/ CD Logística NR-10 75% red + Termos 5 políticas c/ % aceite + Documentos vencendo CNH + LTCAT 3 filiais c/ 1 VENCIDO + Hazard 4 cargos c/ EPI neutraliza) · banner alerta vermelho ASO admissional vencido 12d) + Página HTML `r2_people_beneficios.html` materializa M19 (persona Fernanda Lima Analista Pleno · hero pacote total navy→purple gradient c/ R$ 7.930 total empresa · 5 abas: Meus 6 benefícios ativos + Disponíveis 7 c/ "Aderir" CTA orange + Dependentes 3 cards c/ alerta IR Clara 21 anos + Reembolsos 5 c/ status badges + Convênios parceiros 6 cards c/ rating estrelas + clicks)** |

---

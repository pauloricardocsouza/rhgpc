# R2 People Platform · Wireframe Textual do MVP

**Versão:** 1.0
**Escopo:** MVP (Avaliação de Desempenho + Feedback Contínuo)
**Perfis:** Colaborador, Gestor, Admin RH, Super Admin (R2)

---

## 1. Sitemap

```
/
├── /login                         (público)
├── /select-company                (autenticado, multi-empresa)
│
├── /home                          (todos)
├── /perfil                        (todos)
│
├── /avaliacoes
│   ├── /ativas                    (todos: avaliações pendentes minhas)
│   ├── /historico                 (todos: meus resultados anteriores)
│   ├── /:cycleId/responder        (preenche autoavaliação ou avalia liderado)
│   └── /:cycleId/resultado/:userId (vê resultado consolidado)
│
├── /feedbacks
│   ├── /recebidos                 (timeline)
│   ├── /enviados
│   ├── /enviar                    (compor)
│   └── /solicitar                 (pedir feedback de alguém)
│
├── /elogios
│   ├── /mural                     (feed da empresa)
│   └── /enviar                    (postar elogio)
│
├── /equipe                        (gestor)
│   ├── /                          (lista de liderados)
│   └── /:userId                   (perfil do liderado)
│
└── /admin                         (admin RH)
    ├── /dashboard
    ├── /colaboradores
    │   ├── /                      (lista)
    │   ├── /importar              (CSV)
    │   └── /:userId               (editar)
    ├── /departamentos
    ├── /competencias
    ├── /ciclos
    │   ├── /                      (lista)
    │   ├── /novo                  (wizard 4 passos)
    │   └── /:cycleId/acompanhar   (status do ciclo)
    ├── /configuracoes
    └── /auditoria

/super-admin                       (R2 apenas)
└── /empresas                      (gestão de tenants)
```

---

## 2. Telas comuns (todos os perfis)

### 2.1 Login `/login`

```
┌────────────────────────────────────┐
│         [LOGO R2]                  │
│                                    │
│    Bem-vindo de volta              │
│                                    │
│    Usuário                         │
│    [_______________________]       │
│                                    │
│    Senha                           │
│    [_______________________]  👁   │
│                                    │
│    [   ENTRAR                  ]   │
│                                    │
│    Esqueceu a senha?               │
└────────────────────────────────────┘
```

**Comportamento:**
- Frontend converte `username` em `auth_email` (`{username}@r2-internal.local`) antes de chamar `supabase.auth.signInWithPassword`.
- "Esqueceu a senha" abre modal: usuário informa username, sistema envia notificação ao admin RH da empresa default (já que o colaborador pode não ter e-mail).
- Após login, se usuário tem mais de uma empresa ativa: redireciona para `/select-company`. Se só uma: vai direto para `/home`.

### 2.2 Seletor de empresa `/select-company`

```
┌────────────────────────────────────┐
│  Olá, Ricardo                      │
│  Você tem acesso a 2 empresas      │
│                                    │
│  ┌──────────────────────────────┐ │
│  │ [logo] GPC                   │ │
│  │ Admin RH • 367 colaboradores │ │
│  └──────────────────────────────┘ │
│                                    │
│  ┌──────────────────────────────┐ │
│  │ [logo] HEC                   │ │
│  │ Admin RH • 412 colaboradores │ │
│  └──────────────────────────────┘ │
│                                    │
│  [ ] Definir como empresa padrão   │
└────────────────────────────────────┘
```

**Comportamento:**
- Ao clicar em uma empresa, chama RPC `set_active_company(company_id)` que atualiza o claim `active_company_id` no JWT.
- Token é refeito, app recarrega contexto.
- Trocador também fica acessível no header de qualquer tela.

### 2.3 Home `/home`

```
┌─────────────────────────────────────────────┐
│ ☰  R2 People    [GPC ▾]    🔔 3   👤 Ricardo│
├─────────────────────────────────────────────┤
│                                             │
│  Olá, Ricardo                               │
│  Quarta, 30 de Abril                        │
│                                             │
│  ┌─── PENDÊNCIAS ────────────────────────┐ │
│  │ ⚠  Autoavaliação · Ciclo 2026.1       │ │
│  │     Prazo: 15/05  •  [ Responder → ]  │ │
│  │                                        │ │
│  │ 💬  3 pedidos de feedback aguardando   │ │
│  │     [ Ver pedidos → ]                 │ │
│  └────────────────────────────────────────┘ │
│                                             │
│  ┌─── ÚLTIMOS FEEDBACKS RECEBIDOS ───────┐ │
│  │ Ana Silva • há 2 dias                  │ │
│  │ "Excelente entrega no projeto X..."    │ │
│  │                                        │ │
│  │ João • há 5 dias  • Anônimo            │ │
│  │ "Sugiro melhorar a comunicação..."     │ │
│  │                                        │ │
│  │ [ Ver todos →]                        │ │
│  └────────────────────────────────────────┘ │
│                                             │
│  ┌─── ELOGIOS RECENTES NA EMPRESA ───────┐ │
│  │ 🎉 Carla → Pedro: "Salvou o cliente!"  │ │
│  │ 🎉 Time de TI → Ricardo: "MVP do mês"  │ │
│  └────────────────────────────────────────┘ │
└─────────────────────────────────────────────┘
```

**Comportamento:**
- Cards de pendência são clicáveis e levam direto à ação.
- Bloco "Últimos feedbacks": se `is_anonymous = TRUE`, esconde nome do remetente.
- O trocador de empresa no header fica visível em todas as telas.

### 2.4 Meu perfil `/perfil`

```
┌─────────────────────────────────────────────┐
│  [foto]                                     │
│  Ricardo Silva                              │
│  Coordenador de BI • TI                     │
│  GPC • desde Mar/2023                       │
│                                             │
│  [ Alterar senha ]  [ Editar foto ]         │
│                                             │
│  ── Informações pessoais ──                 │
│  Nome completo: Ricardo Silva               │
│  Usuário: ricardo.silva                     │
│  CPF: ***.***.***-**                        │
│  E-mail de contato: ricardo@solucoesr2.com  │
│  Telefone: (75) 9****-****                  │
│                                             │
│  ── Hierarquia ──                           │
│  Gestor: Maria Santos                       │
│  Liderados (4): Ana, João, Carla, Pedro     │
└─────────────────────────────────────────────┘
```

---

## 3. Módulo de Avaliações

### 3.1 Avaliações ativas `/avaliacoes/ativas`

```
┌─────────────────────────────────────────────┐
│  Avaliações                                 │
│  [ Ativas ] [ Histórico ]                   │
│                                             │
│  CICLO ATUAL: 2026.1 · Avaliação Anual      │
│  Período: 01/04 a 15/05                     │
│                                             │
│  ┌──────────────────────────────────────┐  │
│  │ AUTOAVALIAÇÃO                         │  │
│  │ Status: Pendente                      │  │
│  │ Prazo: 15/05/2026 (15 dias restantes) │  │
│  │ [ Responder agora →]                  │  │
│  └───────────────────────────────────────┘  │
│                                             │
│  ── Como gestor, avaliar (4) ──             │
│                                             │
│  ┌──────────────────────────────────────┐  │
│  │ Ana Silva   • Em andamento (60%)      │  │
│  │ João Costa  • Pendente                │  │
│  │ Carla Reis  • Concluída ✓             │  │
│  │ Pedro Lima  • Pendente                │  │
│  └───────────────────────────────────────┘  │
└─────────────────────────────────────────────┘
```

### 3.2 Responder avaliação `/avaliacoes/:cycleId/responder`

```
┌─────────────────────────────────────────────┐
│  ← Voltar                                   │
│                                             │
│  Autoavaliação · Ciclo 2026.1               │
│  Progresso: ████████░░  4 de 5 competências │
│  [ Salvar rascunho ]                        │
│                                             │
│  ── 1. Comunicação ──                       │
│  Capacidade de transmitir ideias com clareza│
│                                             │
│  Sua nota:                                  │
│  ○ 1  ○ 2  ○ 3  ● 4  ○ 5                   │
│  1=Abaixo do esperado    5=Supera muito     │
│                                             │
│  Comentário (opcional):                     │
│  ┌──────────────────────────────────────┐  │
│  │ Tenho buscado clareza nas reuniões... │  │
│  │                                       │  │
│  └───────────────────────────────────────┘  │
│                                             │
│  ── 2. Trabalho em equipe ──                │
│  ...                                        │
│                                             │
│         [ Anterior ]  [ Próxima  → ]        │
│                                             │
│  ── Tela final ──                           │
│  Comentário geral (opcional)                │
│  Nota geral: calculada automaticamente: 4.2 │
│                                             │
│         [ Submeter avaliação ]              │
└─────────────────────────────────────────────┘
```

**Comportamento:**
- Auto-save a cada 30s (status `in_progress`).
- Submeter exige confirmação modal: "Após submeter, não é possível alterar."
- Nota geral pode ser sobrescrita manualmente.
- Ao submeter, vira `status = 'submitted'` e `submitted_at = NOW()`.

### 3.3 Resultado consolidado `/avaliacoes/:cycleId/resultado/:userId`

```
┌─────────────────────────────────────────────┐
│  Resultado · Ciclo 2026.1                   │
│  Ricardo Silva • Coord. de BI               │
│                                             │
│  ┌─── NOTA GERAL ────────────────────────┐ │
│  │  Autoavaliação:    4.2                 │ │
│  │  Avaliação gestor: 4.5                 │ │
│  │  ────────────────────                  │ │
│  │  Média:            4.35                │ │
│  └────────────────────────────────────────┘ │
│                                             │
│  ── COMPETÊNCIAS (gráfico radar) ──         │
│       Comunicação                           │
│            5                                │
│           /│\                               │
│          / │ \   Trabalho em equipe         │
│   Inov. ┤  │  ├─5                           │
│         5\ │ /                              │
│           \│/                               │
│            5                                │
│         Resultado                           │
│                                             │
│  Legenda: ─── Auto   ─── Gestor             │
│                                             │
│  ── COMENTÁRIOS ──                          │
│  Você (autoavaliação):                      │
│  "Acho que evoluí em comunicação..."        │
│                                             │
│  Maria Santos (gestor):                     │
│  "Excelente progresso este ciclo..."        │
└─────────────────────────────────────────────┘
```

**Comportamento:**
- Visível ao reviewee somente quando o ciclo for fechado (`status = 'closed'`).
- Visível ao gestor sempre que o gestor já tiver submetido.
- Visível ao admin RH sempre.

---

## 4. Módulo de Feedbacks

### 4.1 Feedbacks recebidos `/feedbacks/recebidos`

```
┌─────────────────────────────────────────────┐
│  Feedbacks                                  │
│  [ Recebidos ] [ Enviados ] [+ Novo ]       │
│                                             │
│  Filtros: [Tipo ▾] [Período ▾] [Pessoa ▾]   │
│                                             │
│  ┌──────────────────────────────────────┐  │
│  │ 👍 POSITIVO • há 2 dias                │  │
│  │ De: Ana Silva                          │  │
│  │ Competência: Comunicação               │  │
│  │ "Sua apresentação ontem foi muito..."  │  │
│  │                                        │  │
│  │ [Responder]  [Marcar como lido]        │  │
│  └────────────────────────────────────────┘  │
│                                             │
│  ┌──────────────────────────────────────┐  │
│  │ 💡 CONSTRUTIVO • há 5 dias  • ANÔNIMO  │  │
│  │ Competência: Liderança                 │  │
│  │ "Sugiro que nas reuniões 1:1 você..."  │  │
│  └────────────────────────────────────────┘  │
└─────────────────────────────────────────────┘
```

### 4.2 Enviar feedback `/feedbacks/enviar`

```
┌─────────────────────────────────────────────┐
│  Enviar feedback                            │
│                                             │
│  Para quem? *                               │
│  [ Buscar colaborador...           🔍 ]     │
│                                             │
│  Tipo de feedback *                         │
│  ◉ 👍 Positivo                              │
│  ○ 💡 Construtivo                           │
│                                             │
│  Competência relacionada (opcional)         │
│  [ Selecionar...                       ▾]   │
│                                             │
│  Mensagem *                                 │
│  ┌──────────────────────────────────────┐  │
│  │                                       │  │
│  │                                       │  │
│  └───────────────────────────────────────┘  │
│  Mín. 20 caracteres                         │
│                                             │
│  Visibilidade                               │
│  ◉ Privado (só destinatário)                │
│  ○ Compartilhar com gestor do destinatário  │
│  ○ Público (mural)                          │
│                                             │
│  [ ] Enviar como anônimo                    │
│      (configurável por sua empresa)         │
│                                             │
│         [ Cancelar ]  [ Enviar ]            │
└─────────────────────────────────────────────┘
```

**Comportamento:**
- Checkbox "Enviar como anônimo" só aparece se `companies.settings.allow_anonymous_feedback = TRUE`.
- Auto-save de rascunho enquanto digita.

### 4.3 Solicitar feedback `/feedbacks/solicitar`

Variação do "Enviar": no lugar de mensagem, escolhe pessoas (até 5) e escreve um pedido. Cria N registros em `feedback_requests`.

---

## 5. Módulo de Elogios

### 5.1 Mural de elogios `/elogios/mural`

```
┌─────────────────────────────────────────────┐
│  Mural de Elogios       [+ Novo elogio]     │
│                                             │
│  ┌──────────────────────────────────────┐  │
│  │ 🎉 Carla Reis  →  Pedro Lima           │  │
│  │ há 3 horas                             │  │
│  │ Competência: Foco no cliente           │  │
│  │                                        │  │
│  │ "Pedro virou a noite ajudando o ATP   │  │
│  │  Atacado a fechar o relatório..."     │  │
│  │                                        │  │
│  │ 👏 12   ❤️ 5   🚀 3                    │  │
│  └────────────────────────────────────────┘  │
│                                             │
│  ┌──────────────────────────────────────┐  │
│  │ 🎉 Ricardo  →  Time de BI              │  │
│  │ ontem                                  │  │
│  │ ...                                   │  │
│  └───────────────────────────────────────┘  │
└─────────────────────────────────────────────┘
```

### 5.2 Postar elogio `/elogios/enviar`

Similar ao "Enviar feedback", mas mais leve: campo "Para quem", competência opcional, mensagem. Sem opção de anônimo, sem visibilidade configurável (sempre público).

---

## 6. Telas de Gestor (perfil `gestor`)

### 6.1 Minha equipe `/equipe`

```
┌─────────────────────────────────────────────┐
│  Minha equipe                               │
│  4 liderados diretos                        │
│                                             │
│  ┌──────────────────────────────────────┐  │
│  │ Ana Silva                              │  │
│  │ Analista de BI                         │  │
│  │ ─────────────────────                  │  │
│  │ Última avaliação: 4.3                  │  │
│  │ Feedbacks no ciclo: 7                  │  │
│  │ Status atual: ✓ Em dia                 │  │
│  │ [ Ver perfil ]  [ Avaliar ]            │  │
│  └────────────────────────────────────────┘  │
│  ...                                         │
└─────────────────────────────────────────────┘
```

### 6.2 Perfil do liderado `/equipe/:userId`

Visão consolidada do liderado: dados básicos, histórico de avaliações (gráfico de evolução), feedbacks recebidos (que o gestor pode ver pelas regras de RLS), elogios recebidos. Botão para iniciar 1:1 (módulo Fase 2).

---

## 7. Telas de Admin RH (perfil `admin_rh`)

### 7.1 Dashboard administrativo `/admin/dashboard`

```
┌─────────────────────────────────────────────┐
│  Dashboard RH · GPC                         │
│                                             │
│  ┌──────────┬──────────┬──────────────┐    │
│  │ 367      │ 14       │ 92%          │    │
│  │ Colab.   │ Departos │ Adesão ciclo │    │
│  └──────────┴──────────┴──────────────┘    │
│                                             │
│  ── CICLO 2026.1 ──                         │
│  ████████████░░  78% concluído              │
│  286 de 367 avaliações submetidas           │
│  [ Ver detalhes →]                          │
│                                             │
│  ── ATIVIDADE RECENTE ──                    │
│  ▪ Hoje: 23 feedbacks, 8 elogios            │
│  ▪ Esta semana: 142 feedbacks, 51 elogios   │
│                                             │
│  ── DEPARTAMENTOS COM BAIXA ADESÃO ──       │
│  Atacadão Pinto Senhor do Bonfim    45%     │
│  Cestão Inhambupe                   62%     │
│                                             │
│  [ Exportar relatório CSV ]                 │
└─────────────────────────────────────────────┘
```

### 7.2 Importar colaboradores `/admin/colaboradores/importar`

```
┌─────────────────────────────────────────────┐
│  Importar colaboradores                     │
│                                             │
│  Passo 1 de 3 · Baixar modelo               │
│  [ Baixar template CSV ]                    │
│                                             │
│  Colunas esperadas:                         │
│  username, full_name, cpf, contact_email,   │
│  job_title, department_code, manager_user,  │
│  role, hire_date, password                  │
│                                             │
│  Passo 2 de 3 · Upload                      │
│  ┌──────────────────────────────────────┐  │
│  │  📁  Arrastar arquivo aqui            │  │
│  │      ou clicar para selecionar        │  │
│  └───────────────────────────────────────┘  │
│                                             │
│  Passo 3 de 3 · Validação prévia            │
│  ✓ 367 linhas detectadas                    │
│  ✓ 365 válidas                              │
│  ⚠  2 com problemas:                        │
│     Linha 14: department_code "ATP-99"      │
│                não existe                   │
│     Linha 88: username duplicado            │
│                                             │
│  [ Ver detalhes ]  [ Importar 365 válidas ] │
└─────────────────────────────────────────────┘
```

**Comportamento:**
- Upload nunca executa direto: sempre passa por dry-run de validação.
- Senha pode vir no CSV ou ser gerada (4 últimos dígitos do CPF + sufixo aleatório, exibido no relatório final).
- No final, baixa CSV com colaboradores criados + senhas iniciais.

### 7.3 Gestão de competências `/admin/competencias`

```
┌─────────────────────────────────────────────┐
│  Competências           [+ Nova competência]│
│                                             │
│  Categoria: [ Todas ▾]                      │
│                                             │
│  ┌──────────────────────────────────────┐  │
│  │ Comunicação              Comportamental│  │
│  │ Capacidade de transmitir ideias...     │  │
│  │ Peso: 1.0 • Ativa                      │  │
│  │ [Editar] [Desativar]                   │  │
│  └────────────────────────────────────────┘  │
│  ┌──────────────────────────────────────┐  │
│  │ Foco no cliente          Comportamental│  │
│  │ ...                                    │  │
│  └───────────────────────────────────────┘  │
└─────────────────────────────────────────────┘
```

### 7.4 Criar ciclo (wizard) `/admin/ciclos/novo`

Wizard em 4 passos:

```
Passo 1: Informações básicas
  Nome, descrição, tipo (anual/semestral/trimestral/custom),
  datas de início e fim.

Passo 2: Configuração
  ☑ Autoavaliação habilitada
  ☑ Avaliação do gestor habilitada
  ☐ Avaliação por pares (Fase 2)
  ☐ Avaliação dos liderados (Fase 2)
  Escala: 1 a 5

Passo 3: Competências
  Lista checkboxes de competências ativas da empresa.
  Drag-drop para ordenar. Mínimo 3.

Passo 4: Participantes
  ◉ Toda a empresa
  ○ Por departamento (multi-select)
  ○ Lista personalizada (CSV)
  Pré-visualização: 367 colaboradores serão incluídos.

  [ Salvar como rascunho ]  [ Iniciar ciclo ]
```

**Comportamento:**
- "Iniciar ciclo" cria registros em `reviews` para cada par reviewee/reviewer/type.
- Notificações in-app são geradas para todos os participantes.

### 7.5 Acompanhamento de ciclo `/admin/ciclos/:cycleId/acompanhar`

```
┌─────────────────────────────────────────────┐
│  Ciclo 2026.1 · Avaliação Anual             │
│  Status: Em revisão                         │
│  ───────────────────────                    │
│  Progresso geral: 78% (286/367)             │
│                                             │
│  ── POR TIPO DE AVALIAÇÃO ──                │
│  Autoavaliação:    82% ████████████░       │
│  Gestor:           74% ██████████░░░       │
│                                             │
│  ── POR DEPARTAMENTO ──                     │
│  ATP Atacado            95%                 │
│  Cestão Loja 1          88%                 │
│  ATP Senhor do Bonfim   45% ⚠               │
│                                             │
│  [ Enviar lembrete a pendentes (81) ]       │
│  [ Estender prazo ] [ Encerrar ciclo ]      │
└─────────────────────────────────────────────┘
```

### 7.6 Configurações da empresa `/admin/configuracoes`

```
┌─────────────────────────────────────────────┐
│  Configurações · GPC                        │
│                                             │
│  ── IDENTIDADE ──                           │
│  Nome: Grupo Pinto Cerqueira                │
│  Slug: gpc                                  │
│  Logo: [imagem]  [Trocar]                   │
│                                             │
│  ── HIERARQUIA ──                           │
│  Visibilidade do gestor:                    │
│  ○ Só liderados diretos                     │
│  ◉ Liderados diretos + indiretos (recursivo)│
│  ○ Profundidade customizada: [   ]          │
│                                             │
│  ── FEEDBACKS ──                            │
│  ☑ Permitir feedback anônimo                │
│  ☑ Permitir feedback público (mural)        │
│  Visibilidade padrão: [Privado ▾]           │
│                                             │
│  ── AVALIAÇÕES ──                           │
│  Escala padrão: [1 a 5 ▾]                   │
│                                             │
│  [ Salvar alterações ]                      │
└─────────────────────────────────────────────┘
```

### 7.7 Auditoria `/admin/auditoria`

Tabela paginada do `audit_log`, filtrável por usuário, ação, período, entidade. Exportável em CSV. Para LGPD.

---

## 8. Fluxos críticos

### Fluxo A · Primeiro acesso de colaborador novo

1. Admin RH importa CSV → colaborador é criado em `users` + `user_companies`.
2. Sistema gera senha temporária e a entrega em PDF para o admin.
3. Admin imprime ou comunica internamente (sem e-mail).
4. Colaborador acessa `/login`, digita username + senha temporária.
5. Sistema detecta `must_change_password = true` (campo em `users.profile_data`) e força tela de troca de senha.
6. Após troca, vai para `/home`.

### Fluxo B · Ciclo completo de avaliação

1. Admin cria ciclo em wizard, define participantes, inicia.
2. Sistema cria N registros em `reviews` (N = colaboradores × tipos habilitados) e gera notificações in-app.
3. Colaborador entra em `/avaliacoes/ativas`, vê pendência, clica "Responder".
4. Preenche autoavaliação (auto-save), submete.
5. Em paralelo, gestor entra na mesma tela, vê lista de liderados, avalia cada um.
6. Admin acompanha em `/admin/ciclos/:id/acompanhar`, envia lembretes aos atrasados.
7. Admin clica "Encerrar ciclo" → status muda para `closed`.
8. Colaboradores ganham acesso ao consolidado em `/avaliacoes/:cycleId/resultado/:userId`.

### Fluxo C · Trocar de empresa (multi-tenant)

1. Usuário clica no nome da empresa no header.
2. Dropdown lista empresas vinculadas.
3. Ao selecionar, frontend chama RPC `set_active_company(uuid)`.
4. RPC valida vínculo em `user_companies`, atualiza claim `active_company_id` no JWT (via `auth.update_user`).
5. Frontend recarrega contexto e redireciona para `/home`.
6. Toda navegação subsequente é filtrada pelo RLS na nova empresa.

### Fluxo D · Enviar feedback anônimo

1. Colaborador acessa `/feedbacks/enviar`.
2. Frontend lê `companies.settings.allow_anonymous_feedback`. Se true, mostra checkbox "Anônimo".
3. Usuário marca anônimo, escolhe destinatário, escreve mensagem, envia.
4. Backend grava `feedbacks` com `is_anonymous = TRUE` e `from_user_id = auth.uid()` (sempre real, para auditoria).
5. Destinatário recebe notificação. Ao abrir feedback, frontend esconde nome do remetente.
6. Admin RH, ao consultar auditoria, vê o `from_user_id` real (regra de compliance).

---

## 9. Componentes reutilizáveis

| Componente            | Onde aparece                                  |
|-----------------------|-----------------------------------------------|
| `<Header>`            | Todas (logo, trocador empresa, sino, avatar)  |
| `<UserPicker>`        | Enviar feedback, solicitar, postar elogio     |
| `<CompetencyPicker>`  | Feedback, elogio, criar ciclo                 |
| `<RatingStars>` (1-5) | Responder avaliação                           |
| `<RadarChart>`        | Resultado de avaliação                        |
| `<ProgressBar>`       | Wizard de avaliação, dashboard admin          |
| `<EmptyState>`        | Listas vazias                                 |
| `<ConfirmModal>`      | Submeter avaliação, encerrar ciclo            |

---

## 10. Estados de erro e vazio (cobertura mínima do MVP)

- Sem internet (offline)
- Token expirado (redireciona pra login)
- Sem permissão (mostra "Você não tem acesso a esta página")
- Lista vazia em todas as telas-tabela
- Falha de auto-save (toast com retry)
- Importação CSV com erros (relatório linha-a-linha)

---

## 11. Telas que NÃO entram no MVP (Fase 2+)

- 1:1 (reuniões individuais)
- PDI (Plano de Desenvolvimento Individual)
- OKRs e metas
- People Analytics avançado
- Sucessão e plano de carreira
- Pesquisa de clima e eNPS
- Avaliação por pares e liderados (estrutura já existe, só ativar)
- Calibração
- Integrações (Slack, e-mail externo, TOTVS)
- App mobile nativo

---

**Próximos passos sugeridos**

1. Validar este wireframe com 1 a 2 stakeholders da GPC (gestor e admin RH).
2. Priorizar 2 telas-chave para protótipo visual em HTML.
3. Decidir stack final e abrir repositório.
4. Aplicar schema v2 em ambiente de dev (Supabase).

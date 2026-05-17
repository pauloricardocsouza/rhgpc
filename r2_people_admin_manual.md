# Manual do Administrador · R2 People

**Versão:** 1.0 · 17 de maio de 2026
**Público:** RH/TI responsável pela operação do tenant
**Pré-requisitos:** acesso com papel `diretoria` ou perfil de permissão com `manage_tenant`

---

## Índice

1. [Conceitos fundamentais](#1-conceitos-fundamentais)
2. [Primeiro acesso e setup](#2-primeiro-acesso-e-setup)
3. [Estrutura organizacional](#3-estrutura-organizacional)
4. [Cadastro de colaboradores](#4-cadastro-de-colaboradores)
5. [Gestão de acessos e permissões](#5-gestão-de-acessos-e-permissões)
6. [Módulos](#6-módulos)
7. [Tarefas operacionais frequentes](#7-tarefas-operacionais-frequentes)
8. [Importação em massa](#8-importação-em-massa)
9. [Auditoria e LGPD](#9-auditoria-e-lgpd)
10. [Configurações do tenant](#10-configurações-do-tenant)
11. [Troubleshooting comum](#11-troubleshooting-comum)
12. [Quando chamar o suporte R2](#12-quando-chamar-o-suporte-r2)

---

## 1. Conceitos fundamentais

### 1.1 Tenant

Sua empresa é um **tenant** isolado no R2 People. Todos os dados são segregados por `tenant_id` no banco · você não vê dados de outros clientes da R2.

### 1.2 Estrutura tripartite

Cada colaborador pertence a três dimensões:

- **Empregador (EMP)**: a entidade legal (CNPJ) que assina a CTPS · ex: ATP Varejo Ltda
- **Tomador (TOM)**: a unidade onde o colaborador efetivamente trabalha · ex: Cestão Loja 1
- **Departamento**: área funcional · ex: Padaria, Frente de Caixa, TI

Reports e relatórios suportam os dois eixos (EMP e TOM). Para terceirizações, isso é crítico.

### 1.3 RBAC · 5 papéis

| Papel | Quem é | O que vê |
|---|---|---|
| `super_admin` | Staff R2 (suporte) | Tudo, cross-tenant |
| `diretoria` | Diretores, sócios | Tudo do tenant, ativa/desativa módulos |
| `rh` | RH, DP | Operação dia-a-dia, todos os colaboradores |
| `lider` | Gerentes, supervisores | Próprio time (recursivo) |
| `colaborador` | Demais | Próprio perfil |

Perfis customizados (ex: "RH Prestadora · Labuta") são possíveis via [Permission Profiles](#5-gestão-de-acessos-e-permissões).

### 1.4 Módulos

Cada tenant ativa/desativa módulos independentemente. Módulo desativado **não aparece** na sidebar e **bloqueia chamadas RPC** correspondentes (erro `module_inactive`).

Módulos disponíveis:
- `employees` (sempre ativo · ficha base)
- `9box` · matriz de talentos
- `pdi` · plano de desenvolvimento
- `recognition` · reconhecimentos
- `onboarding` · jornadas de integração
- `medical_certificates` · atestados
- `vacations` · férias
- `movements` · movimentações
- `oneonones` · 1:1s estruturadas
- `payroll` · folha e custo
- `metas` · metas/OKRs

---

## 2. Primeiro acesso e setup

### 2.1 Configurações iniciais (1ª hora)

Ao receber a Plataforma, faça nesta ordem:

1. **Login do admin** · receba magic link no email cadastrado pela R2
2. **Cadastre dados básicos do tenant** em `/admin/configuracoes`:
   - Nome legal e fantasia
   - CNPJ principal
   - Logo (PNG, máx 500KB)
   - Cores primárias (se quiser personalizar)
3. **Cadastre empregadores** em `/admin/estrutura` aba *Empregadores*:
   - Razão social, CNPJ, IE, cidade/UF
   - Regime tributário (Simples ou Lucro Real)
4. **Cadastre unidades (lojas/filiais)** em `/admin/estrutura` aba *Filiais*:
   - Vincular cada uma ao empregador correto
   - Tipo (matriz, filial, CD, escritório, rural)
5. **Cadastre departamentos** em `/admin/estrutura` aba *Departamentos*:
   - Hierarquia simples (cada um pode ter parent)
6. **Cadastre cargos** em `/admin/estrutura` aba *Cargos*:
   - Nome, nível (estágio/jr/pleno/sr/líder/gerência/diretoria)
   - Código CBO oficial (opcional mas recomendado)
   - Faixa salarial sugerida (opcional, alimenta calculadora de custo)
7. **Ative módulos** em `/admin/modulos`:
   - Cada módulo tem 3 estados: ativo, somente leitura, desativado
   - Recomendação inicial: ativar `employees`, `9box`, `pdi`, `recognition` · adicionar outros gradualmente

### 2.2 Importação inicial de colaboradores

Veja [§8 Importação em massa](#8-importação-em-massa).

### 2.3 Convite de líderes

Após colaboradores importados:

1. Em `/pessoas`, filtre por `role = 'lider'` (ou ajuste papéis individualmente)
2. Cada líder recebe email automaticamente com magic link
3. Acompanhe taxa de primeiro acesso em `/admin/onboarding`

---

## 3. Estrutura organizacional

### 3.1 Criar/editar empregador

**Caminho:** `/admin/estrutura` → aba Empregadores → botão *+ Novo*

Campos:
- **Código** (interno, único · ex: `GPC-MATRIZ`)
- **Razão social** (oficial)
- **Nome fantasia** (opcional)
- **CNPJ** (14 dígitos, validado)
- **Inscrição estadual** (opcional)
- **Tipo** (matriz/filial/CD/escritório/rural)
- **Cidade e UF**

### 3.2 Vincular unidade a empregador

Cada `working_unit` (loja, CD, etc.) tem **um** `employer_unit_id`. Defina ao criar.

⚠️ **Cuidado**: mudar o empregador de uma unidade com colaboradores ativos pode confundir a folha. Faça via `/admin/movimentacoes` (cria movement `transfer_unit` em massa) para preservar histórico.

### 3.3 Departamentos com hierarquia

Departamentos podem ter parent (ex: TI > Infra, TI > Desenvolvimento). A árvore aparece com indentação visual.

⚠️ **Cuidado**: limite de 5 níveis recomendado · árvores muito profundas dificultam reports.

### 3.4 Cargos

**Faixa salarial sugerida** (opcional) é usada em:
- Validação na calculadora de custo
- Warning ao criar promoção com salário fora da faixa

---

## 4. Cadastro de colaboradores

### 4.1 Criação manual

**Caminho:** `/pessoas/novo`

5 seções:
1. **Dados pessoais**: nome completo, apelido (para busca rápida), CPF, email
2. **Vínculo**: empregador, unidade, departamento, cargo, gestor direto, data admissão
3. **Tipo de vínculo**: CLT, estágio, PJ, aprendiz, eventual, pró-labore
4. **Acessos**: papel RBAC, perfil de permissão (se houver)
5. **Foto** (opcional, upload)

CPF é validado por mod 11. Email é único por tenant.

### 4.2 Edição inline

Na ficha do colaborador (`/pessoas/[id]`), cada seção tem botão *Editar*. Salva via RPC e gera audit log.

### 4.3 Desligamento

Não exclui o registro. Use *Editar > Tipo de vínculo > Desligar*:
- Preencher `terminated_at`
- `active = FALSE`
- Triggers automáticos:
  - Cancela férias futuras programadas
  - Marca PDIs como `closed_termination`
  - Notifica gestor direto
  - Cria movement `termination` automático

Dados permanecem por **2 anos pós-desligamento** para defesa em ações trabalhistas.

### 4.4 Reativação

Caso de retorno (raro): editar e marcar `active = TRUE`. Pode ser necessário reatribuir papel se foi rebaixado.

---

## 5. Gestão de acessos e permissões

### 5.1 Papéis base

Cada colaborador tem **um** papel RBAC. Atribuído em `/pessoas/[id]` seção *Acessos*.

### 5.2 Perfis customizados

Quando os 5 papéis padrão não são suficientes (ex: RH terceirizada com escopo limitado), crie um **Permission Profile** em `/admin/acessos`:

1. **Código** (interno) e **nome de exibição**
2. **Papel base** (papel do qual herda permissões)
3. **Escopo** (opcional): limitar a um empregador específico
4. **Permissões extras** (checklist do catálogo)

Exemplo prático GPC:
- **Nome**: "RH Prestadora · Labuta"
- **Base role**: `rh`
- **Escopo**: empregador "Labuta"
- **Permissões extras**: `validate_medical_for_employer`, `view_oneonones_metadata_by_employer`

A pessoa com esse perfil:
- Tem todas as permissões padrão de `rh`
- Mas só vê colaboradores cujo `employer_unit_id = labuta`
- Pode validar atestados desses colaboradores (não dos outros)

### 5.3 Atribuir perfil

Em `/pessoas/[id]` seção *Acessos*, escolha o perfil no dropdown. Substitui o papel base para fins de permissões.

### 5.4 Revogar acessos

Para tirar temporariamente um líder do escopo de visão sem desligar:
- Mude `role` para `colaborador`
- Acessos via perfil custom: desative o perfil (`active = FALSE`)

---

## 6. Módulos

### 6.1 Ativar/desativar

**Caminho:** `/admin/modulos`

3 estados:
- **Ativo (✓)**: aparece na sidebar, RPCs funcionam
- **Somente leitura (🔒)**: aparece na sidebar com cadeado, dados visíveis mas edições bloqueadas (RPC retorna `module_readonly`)
- **Desativado (-)**: oculto na sidebar, RPCs retornam `module_inactive`

Mudanças têm **modal de confirmação consciente** com lista de impactos.

### 6.2 Quando desativar

- **Em testes**: módulo recém-aberto que ainda não foi treinado · evita uso errado
- **Em transição**: ao migrar de outro sistema, deixar `medical_certificates` em readonly enquanto migra histórico
- **Decisão estratégica**: cliente decide não usar (ex: prefere fazer atestados fora do sistema)

### 6.3 Implicações em cadeia

Alguns módulos dependem de outros. Sistema avisa, mas observe:
- `payroll` depende de `employees` (sempre ativo)
- `movements` integra com `vacations` e `medical_certificates` (FK)
- `oneonones` é independente

---

## 7. Tarefas operacionais frequentes

### 7.1 Aprovação de mudanças de cadastro

Quando colaborador solicita via *Minha Jornada*, a solicitação aparece em `/admin/aprovacoes`:

1. Cards com diff (antes → depois)
2. Botões Aprovar / Rejeitar
3. Rejeitar pede motivo (visível ao colaborador)
4. Aprovação atualiza `app_users` e gera audit log

### 7.2 Aprovação de movimentações

`/admin/movimentacoes` · aba Pendentes:

1. Linha tem before/after, justificativa do líder, impacto na folha
2. Modal de aprovação mostra **validação de orçamento** se promoção
3. Aprovação agenda aplicação para `effective_date`

### 7.3 Validação de atestados

`/admin/atestados` ou `/atestados/validar` (DP):

1. Fila ordenada por urgência (dias parado + qualidade OCR)
2. Viewer com PDF + form de validação
3. CID com autocomplete (20 mais comuns embarcados)
4. Botão *Validar* gera movimento automático se `days_off ≥ 3`

⚠️ **CID nunca aparece pro líder que enviou** · garantia arquitetural via RLS.

### 7.4 Programação anual de férias

Em janeiro, agendar reunião com líderes:

1. Abrir `/ferias/programacao-anual` com persona DP (vê todos)
2. Filtrar por filial · ver alertas (EM DOBRO, VENCE em 60d, Sem programação)
3. Marcar reuniões com líderes para acertar
4. Líderes preenchem para o time direto via mesma tela (escopo restrito)

### 7.5 Fechamento de ciclo 9-Box

Ciclos são trimestrais (config no `/admin/configuracoes` aba *Ciclos*):

1. Notificações automáticas D-30, D-15, D-7 para líderes
2. Acompanhar progresso em `/admin/dashboard` aba 9-Box (cobertura %)
3. Ao fechar, snapshot imutável é criado (`box_labels_snapshot` JSONB)
4. Após fechado, novas avaliações só com novo ciclo aberto

---

## 8. Importação em massa

### 8.1 Cenário típico

Migrar do sistema atual (planilha, TOTVS, etc.) na ativação.

### 8.2 Via CSV

**Caminho:** `/pessoas/importar`

1. Upload CSV (template em [docs/template_import.csv](docs/))
2. **Mapping inteligente**: sistema sugere colunas (Nome, CPF, Email, etc.)
3. **Dry-run**: pré-visualiza primeiras 10 linhas e detecta erros antes
4. Confirmar · processa em background
5. Acompanhar progresso em `/pessoas/importar/[jobId]`

Colunas obrigatórias:
- `nome_completo`, `cpf`, `email`, `data_admissao`, `cargo`, `salario`, `unidade_trabalho`, `empregador`

Colunas opcionais:
- `apelido`, `gestor_email` (vincula por email, resolvido no fim), `tipo_vinculo`, `cbo`, `foto_url`

### 8.3 Via OCR de fichas Domínio

**Caminho:** `/pessoas/importar` aba *PDF Domínio*

1. Upload de PDF de ficha do Domínio (cada PDF é uma ficha)
2. OCR server-side: pdftoppm 300dpi → tesseract → parser regex
3. Resultado em fila para revisão · campos extraídos pré-preenchidos
4. Revisar campo a campo · ajustar se necessário · aprovar

Velocidade típica: 10-15 fichas/min em máquina padrão.

### 8.4 Importação de saldos legados de férias

Necessário quando migra cliente que já tinha histórico em outro sistema:

1. Em `/admin/importacoes` aba *Férias legadas*
2. CSV com colunas: `cpf`, `periodo_aquisitivo_inicio`, `dias_consumidos`, `dias_disponiveis`
3. Sistema cria `vacation_acquisition_periods` com `consumed_days` preset
4. ⚠️ Não cria as férias passadas como `vacation_periods` (ficaria histórico errado)

---

## 9. Auditoria e LGPD

### 9.1 Audit log

Toda ação relevante gera entrada em `audit_log`:
- Quem fez (`actor_user_id` + snapshot do email)
- Quando (`created_at`)
- O quê (`action` + `entity_table` + `entity_id`)
- Diff (`before_data` + `after_data`)

**Caminho:** `/admin/auditoria` (requer permission `view_audit_log`)

Filtros:
- Por ator, por entidade, por janela de tempo
- Export CSV para auditoria externa

### 9.2 Solicitações DSAR (LGPD Art. 18)

Quando colaborador (ou ex-colaborador) solicita acesso aos próprios dados:

1. DPO recebe a solicitação por canal externo (email, WhatsApp)
2. DPO abre `/admin/dsar/exportar/[cpf]`
3. Sistema gera ZIP com todos os dados pessoais em JSON
4. Inclui histórico de atestados, PDIs, avaliações, 1:1s (notas próprias)
5. **NÃO inclui** notas privadas de líder sobre essa pessoa (privacidade arquitetural)
6. Audit log pesado registra a operação

⚠️ Para exportar notas privadas de 1:1s (caso judicial), usar `rpc_oneonone_dsar_export` com permission `dsar_export`. Audit duplo.

### 9.3 Retenções legais

Ver [Termos de Uso §14.3](r2_people_terms_of_service.md#143-retenções-legais).

### 9.4 Notificação de incidente

Em caso de suspeita de vazamento de dados:

1. **Comunique imediatamente** ao DPO do tenant
2. **Contate suporte R2** em emergencia@solucoesr2.com.br
3. R2 inicia investigação e responde em até 24h
4. Se confirmado, notificação à ANPD em até 72h (LGPD Art. 48)

---

## 10. Configurações do tenant

**Caminho:** `/admin/configuracoes`

6 abas:

1. **Geral**: nome, fuso horário, idioma (PT-BR fixo no MVP)
2. **Branding**: logo, cores primárias, slogan
3. **Notificações**: quais eventos disparam notificação in-app
4. **Integrações**: webhooks (futuro)
5. **Billing**: plano contratado, próxima fatura, método de pagamento (admin)
6. **Workspace**: configurações de cada módulo ativo

---

## 11. Troubleshooting comum

### 11.1 "Colaborador não consegue fazer login"

Verifique:
- Email correto cadastrado em `/pessoas/[id]`?
- Email não está bloqueado pelo provedor de email da empresa? (Magic link cai em spam?)
- Conta está `active = TRUE`?
- Magic link expira em 60min · pedir para tentar novamente

### 11.2 "Líder não vê subordinados em /minha-equipe"

Verifique:
- Subordinados têm `manager_id` apontando para o líder?
- Líder tem `role = 'lider'` ou superior?
- Módulo `employees` está ativo (sempre deve estar)?

### 11.3 "Erro 'module_inactive' ao tentar ação"

Verifique em `/admin/modulos` se o módulo está ativo. Se estiver em readonly, ações de escrita falham.

### 11.4 "Importação CSV trava em X%"

- Verificar logs em `/pessoas/importar/[jobId]`
- Erros comuns: CPF inválido, email duplicado, cargo inexistente
- Corrigir CSV e relançar (importação é idempotente por CPF)

### 11.5 "Dashboard mostra dados desatualizados"

Algumas views são materializadas e refreshed por cron:
- `mv_payroll_by_unit`: refresh diário às 1h
- `mv_vacation_planning_overview`: refresh diário às 6h

Forçar refresh manual (admin): `/admin/configuracoes` aba *Workspace* → botão *Refresh views*.

### 11.6 "Colaborador vê dados que não deveria"

⚠️ **Crítico.** Reporte imediatamente:
- `emergencia@solucoesr2.com.br` se for vazamento de PII
- Captura de tela + URL + usuário logado
- R2 investiga em até 1h útil

---

## 12. Quando chamar o suporte R2

### Por canal regular (suporte@solucoesr2.com.br · resposta 1 dia útil)
- Dúvidas de uso
- Solicitações de novas funcionalidades
- Ajuste de configurações que não estão na UI

### Por canal prioritário (WhatsApp business · resposta em horas)
- Plano Business+
- Bugs com workaround impossível
- Dúvidas em horário comercial

### Por emergência (emergencia@solucoesr2.com.br · resposta em 1h útil)
- Vazamento de dados suspeito
- Plataforma fora do ar (não confundir com lentidão)
- Erro crítico de cálculo (folha errada que vai ser usada hoje)

### Por canal LGPD (dpo@solucoesr2.com.br)
- Solicitações de exercício de direitos do titular
- Dúvidas sobre tratamento de dados
- Notificação de incidente

---

## Anexo · Glossário

| Termo | Significado |
|---|---|
| Aquisitivo | Período de 12 meses que dá direito a 30 dias de férias (CLT Art. 130) |
| Concessivo | Período de 12 meses após aquisitivo para gozar as férias |
| CBO | Classificação Brasileira de Ocupações |
| CID | Classificação Internacional de Doenças (usado em atestados) |
| CTPS | Carteira de Trabalho e Previdência Social |
| DSAR | Data Subject Access Request (LGPD Art. 18) |
| FAP | Fator Acidentário de Prevenção (multiplica RAT) |
| FGTS | Fundo de Garantia por Tempo de Serviço |
| Magic link | Link único por email para login sem senha |
| OCR | Optical Character Recognition |
| PDI | Plano de Desenvolvimento Individual |
| Permission Profile | Perfil customizado que estende um papel RBAC |
| RAT | Risco Ambiental do Trabalho (1%, 2% ou 3% conforme atividade) |
| RBAC | Role-Based Access Control |
| RLS | Row-Level Security (Postgres) |
| RPC | Remote Procedure Call (função SQL chamada do frontend) |
| Tenant | Instância isolada de um cliente |

---

*Manual atualizado conforme novos módulos. Cópia mais recente sempre em [rh.solucoesr2.com.br/manual](https://rh.solucoesr2.com.br) e neste repositório.*

**Sugestões de melhoria?** suporte@solucoesr2.com.br

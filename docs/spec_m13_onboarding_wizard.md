# Spec M13 · Onboarding Wizard do Tenant (Primeira Execução)

**Status**: especificação · pré-implementação
**Versão**: 1.0 · 17 de maio de 2026
**Escopo**: fluxo guiado de setup quando um tenant entra pela primeira vez no R2 People
**Depende de**: schema v9+ (tenants, users, roles), spec M10 (settings), spec D7 (consent/policy)

---

## 1. Objetivos

1. **Levar o tenant da home vazia ao "primeiro evento útil"** em < 25 minutos.
2. **Coletar o mínimo** para a plataforma operar (branding, primeira pessoa, primeiro perfil de acesso, primeira política).
3. **Educar enquanto configura** — cada passo explica o "porquê" e o impacto LGPD.
4. **Permitir pular** passos não-críticos e retomar depois.
5. **Marcar conclusão** para destravar features avançadas.

### 1.1 North star metrics

- **Time-to-first-event** (signup → primeiro `movement.created` ou `employee.admitted`): meta P50 < 25min, P95 < 2h.
- **Wizard completion rate**: meta > 70 % completam todos os passos obrigatórios em < 7 dias.
- **Activation 7d**: tenants com ≥ 3 usuários ativos e ≥ 10 employees cadastrados em 7 dias.

---

## 2. Estrutura do wizard

7 passos obrigatórios + 4 opcionais. Linha do tempo visual no topo, progresso salvo a cada passo.

### 2.1 Passo 1 · Boas-vindas + ToS

- Apresenta R2 People em 3 frases
- Aceite de Termos + Política de Privacidade + DPA (Data Processing Agreement)
- Versão da política aceita gravada em `consents` (purpose_code = `tos_dpa_v3.2`)
- **Bloqueador**: sem aceite, login não destrava

### 2.2 Passo 2 · Identificação do tenant

Campos:
- Razão social
- Nome fantasia (default = primeiro nome)
- CNPJ (validação + lookup ReceitaWS para auto-preencher)
- Endereço fiscal
- Setor / segmento (lista: Varejo / Indústria / Serviços / Saúde / Logística / Educação / Outro)
- Tamanho (1-10, 11-50, 51-200, 201-500, 500+)
- Encarregado LGPD (e-mail + nome) — obrigatório

**Validações**:
- CNPJ não pode duplicar (1 CNPJ = 1 tenant ativo)
- Encarregado precisa ser e-mail válido (envia confirmação ao final)

### 2.3 Passo 3 · Branding

- Upload logo (PNG/SVG, 256x256 mín., 2MB máx., EXIF strip)
- Cor primária (color picker · default navy R2)
- Cor secundária (default laranja R2)
- Preview ao vivo da home com branding aplicado
- Opção "Use o template R2 padrão" para pular

**Settings persistidos** em `tenants.settings.branding`:
```json
{
  "logo_url": "https://...",
  "primary": "#2E476F",
  "secondary": "#F58634",
  "favicon_url": "..."
}
```

### 2.4 Passo 4 · Primeira pessoa admin

- Auto-cria 1 user para o cadastrante do tenant (o que está no wizard) como **tenant_admin**.
- Pede para adicionar segunda pessoa: ou um colaborador ou outro admin.
- Pergunta: "Seu RH é interno ou terceirizado?" → afeta a sugestão de papéis subsequentes.
- Mostra dica: "Você pode importar todos os colaboradores depois via CSV ou planilha — recomendamos esse passo para depois."

### 2.5 Passo 5 · Estrutura mínima

Pede pelo menos:
- 1 unidade/filial (default "Sede")
- 1 departamento (default "Geral")
- 1 cargo (default "Colaborador" + escolha de banda salarial padrão)

Para tenants já com tripartite (CTPS empregador ≠ tomador operacional):
- Pergunta: "Você gerencia mais de uma razão social ou unidade?" → habilita campo `emp_legal_id` + `tom_operacional_id` no cadastro

### 2.6 Passo 6 · Primeira política de acesso

- Mostra os **5 papéis padrão** (colaborador, lider, rh, diretoria, tenant_admin) com permissões resumidas
- Pergunta: "Quem pode ver salários?" → cria política `view_salary` com checkboxes por papel
- Pergunta: "Quem pode ver atestados médicos (CID)?" → cria política `view_medical_cid`
- Pergunta: "Quem aprova movimentações?" → cria workflow approval default

Tudo pode ser refinado depois em `r2_people_acessos.html`. O wizard apenas garante um baseline funcional.

### 2.7 Passo 7 · MFA do admin

- Obrigatório para tenant_admin (spec D6 hardening)
- Mostra QR code TOTP + códigos de recovery (download obrigatório antes de continuar)
- Confirma com 1 código TOTP válido
- Persiste em `user_mfa_factors`

### 2.8 Passos opcionais (oferecidos depois)

| Passo | Quando oferecer | Impacto se pular |
|---|---|---|
| Importar colaboradores | sugerir logo após Passo 7 | banner "0 colaboradores" persiste |
| Configurar webhook ERP folha | só se tamanho > 50 | usa só notif in-app |
| Convidar primeiro RH externo | só se "RH terceirizado" no Passo 4 | n/a |
| Configurar SSO (SAML/OIDC) | só plano Enterprise | usa só senha + MFA |

---

## 3. UI · padrão visual

- Tela cheia com header minimalista (logo R2 People + persona "Setup de [tenant]")
- Timeline horizontal com 7 dots (atual destacado em laranja, completos em verde, futuros em cinza)
- Card central de até 540px com conteúdo do passo
- Botões "Voltar" (esquerda) e "Continuar" (direita, primary)
- "Pular este passo" como link discreto no rodapé (apenas para opcionais)
- Side-panel "Por que pedimos isso?" expansível em cada passo (educação LGPD/UX)

---

## 4. Estado e persistência

```sql
CREATE TABLE tenant_onboarding (
  tenant_id        uuid PRIMARY KEY REFERENCES tenants(id) ON DELETE CASCADE,
  current_step     int NOT NULL DEFAULT 1,
  steps_completed  int[] DEFAULT '{}',
  steps_skipped    int[] DEFAULT '{}',
  steps_optional_done int[] DEFAULT '{}',
  started_at       timestamptz NOT NULL DEFAULT now(),
  completed_at     timestamptz,
  abandoned_at     timestamptz,                -- 14d sem progresso
  last_step_at     timestamptz,
  metadata         jsonb DEFAULT '{}'::jsonb   -- responses por passo
);

CREATE INDEX idx_onboarding_open ON tenant_onboarding (last_step_at)
  WHERE completed_at IS NULL AND abandoned_at IS NULL;
```

A cada Continue/Skip → `UPDATE tenant_onboarding SET current_step=current_step+1, last_step_at=now(), steps_completed=array_append(...)`. Trigger marca `completed_at` quando passos 1-7 (obrigatórios) estão em `steps_completed`.

---

## 5. Estados do wizard

| Estado | Disparo | UI |
|---|---|---|
| **Não iniciado** | tenant criado mas wizard nunca aberto | Modal cobre dashboard ao primeiro login |
| **Em progresso** | wizard aberto, pelo menos 1 passo feito | Banner no topo "Setup pendente (4/7)" com link |
| **Pausado** | usuário fechou no meio | Pode retomar do último passo |
| **Concluído** | todos os 7 obrigatórios feitos | Banner "Wizard completo · ver itens opcionais" some em 7d |
| **Abandonado** | 14d sem progresso | E-mail nudge ao admin + DPO interno avisa CS |

---

## 6. Eventos emitidos

| Evento | Quando | Audiência |
|---|---|---|
| `onboarding.started` | tenant abre wizard pela 1ª vez | analytics, CS |
| `onboarding.step_completed` | a cada Continue | analytics |
| `onboarding.step_skipped` | a cada Pular | analytics |
| `onboarding.completed` | passos 1-7 feitos | CS recebe alerta para outreach |
| `onboarding.abandoned` | 14d sem progresso | CS faz contato manual |
| `onboarding.optional_done` | passo opcional concluído | analytics |

Integrados via spec M12 (notif runtime).

---

## 7. RPCs

```sql
-- Iniciar (chamado no primeiro login do tenant_admin)
rpc_onboarding_start(p_tenant_id uuid) RETURNS tenant_onboarding

-- Avançar (registra resposta + sobe step)
rpc_onboarding_advance(
  p_tenant_id uuid,
  p_step int,
  p_response jsonb
) RETURNS tenant_onboarding

-- Pular opcional
rpc_onboarding_skip(p_tenant_id uuid, p_step int) RETURNS tenant_onboarding

-- Status (usado pelo banner global)
rpc_onboarding_status(p_tenant_id uuid)
  RETURNS TABLE (
    current_step int,
    total_required int,
    completed int,
    completion_pct numeric,
    next_action_label text,
    is_blocked boolean
  )
```

---

## 8. Hooks de "auto-conclusão"

Alguns passos completam automaticamente se condição já existe (ex: tenant que já fez signup com CNPJ pelo formulário comercial não precisa repreencher Passo 2).

```sql
-- No INSERT de tenants
INSERT INTO tenant_onboarding (tenant_id, steps_completed)
SELECT id,
  CASE WHEN cnpj IS NOT NULL AND legal_name IS NOT NULL
       THEN ARRAY[1, 2]
       ELSE ARRAY[]::int[]
  END
FROM tenants WHERE id = NEW.id;
```

---

## 9. Microcopy (PT-BR)

| Passo | Título | Subtítulo |
|---|---|---|
| 1 | Bem-vindo ao R2 People | Antes de começar, leia e aceite nossos termos. |
| 2 | Conte sobre sua empresa | Esses dados são necessários para emitir relatórios e cumprir obrigações legais. |
| 3 | Personalize a aparência | Sua identidade visual aparece para todos os colaboradores. |
| 4 | Adicione a primeira pessoa | Comece com você. Depois você importa o time todo. |
| 5 | Crie a estrutura mínima | Uma unidade, um departamento, um cargo. Basta isso. |
| 6 | Defina quem vê o quê | Vamos configurar uma política inicial. Você refina depois. |
| 7 | Proteja sua conta com MFA | Como admin, você tem acesso a dados sensíveis. MFA é obrigatório. |

Cada passo tem um "**Por que pedimos isso?**" expansível que explica em 2-3 frases o motivo.

---

## 10. Acessibilidade

- Navegação por teclado completa (Tab + Enter + Esc)
- ARIA live region para anúncios de progresso
- Focus trap no modal
- Mínimo 4.5:1 contraste em todos os textos
- Atalho Ctrl+Enter avança para próximo passo
- Em mobile, timeline vira hamburguer

---

## 11. A/B candidatos pós-MVP

- **Ordem de passos**: testar Passo 7 (MFA) antes do Passo 4 (admin) — força hardening
- **Texto de boas-vindas**: comparar tom mais formal vs mais leve
- **Passo opcional "Importar agora"**: oferecer dentro do wizard vs depois
- **Vídeo intro**: 60s vs sem vídeo no Passo 1

---

## 12. Testes meta (mínimo 22)

### 12.1 Avanço
- ✓ Iniciar wizard cria linha em `tenant_onboarding`
- ✓ Advance no Passo N persiste resposta em metadata
- ✓ Advance no Passo N+1 sem completar N retorna erro
- ✓ Skip em passo obrigatório retorna erro
- ✓ Skip em passo opcional avança normalmente

### 12.2 Bloqueio
- ✓ Sem aceite ToS (passo 1), login fica em loop pro wizard
- ✓ Sem MFA (passo 7), tenant_admin não acessa páginas privilegiadas
- ✓ Cnpj duplicado no Passo 2 → erro 409

### 12.3 Estado
- ✓ Concluir 7 passos obrigatórios → `completed_at` setado
- ✓ 14d sem progresso → `abandoned_at` + alerta CS
- ✓ Reabrir wizard preserva último passo
- ✓ Re-abrir wizard após `completed_at` mostra só opcionais

### 12.4 Branding
- ✓ Upload logo > 2MB → rejeitado
- ✓ Logo aplicada gera CSP-compatible URL
- ✓ Cor primária inválida (hex inválido) → erro

### 12.5 Eventos
- ✓ `onboarding.started` emite 1x
- ✓ `onboarding.step_completed` emite por passo
- ✓ `onboarding.completed` aciona webhook + alerta CS
- ✓ Eventos pegam idempotência (re-fire não duplica)

### 12.6 Acessibilidade
- ✓ Tab atravessa todos os campos sem armadilhas
- ✓ Esc fecha apenas se em passo opcional
- ✓ Screen reader anuncia "Passo 3 de 7" ao avançar
- ✓ Mobile drawer abre/fecha timeline corretamente

---

## 13. UI · página `r2_people_onboarding.html` (a criar como complemento)

A página atual `r2_people_onboarding.html` é de **onboarding de colaborador novo** (admissão). A nova proposta seria uma página **`r2_people_tenant_setup.html`** específica do wizard de primeira execução do tenant.

Componentes principais:
- `<TimelineSteps current={4} total={7} />`
- `<StepCard title subtitle whyLink children />`
- `<NavFooter onBack onContinue onSkip />`
- `<SidePanelWhy />`
- `<MfaQRDisplay secret={...} backupCodes={[...]} />`
- `<BrandPreview logo primary secondary />`

---

## 14. Métricas de sucesso

Após 90 dias do lançamento, esperamos:
- TTFE (time-to-first-event) P50 < 25min ✓
- Completion rate > 70 % em 7d ✓
- Drop-off por passo < 15 % em cada um
- Suporte às dúvidas de setup < 5 % dos tenants

Painel em Looker/Grafana sob a tag `onboarding_funnel`.

---

## 15. Roadmap pós-MVP

1. **Templates de tenant** (Varejo, Indústria, Serviços) que pré-preenchem estrutura, políticas e papéis típicos do setor.
2. **Onboarding por chat** (em vez de wizard linear) — modo conversacional opcional.
3. **Co-pilot CS** — agent IA que ajuda o admin a entender cada passo via tooltip ativo.
4. **Onboarding gamificado** — barra de "tenant health" que cresce conforme passos completados.
5. **Multi-tenant orchestration** — para o R2 onboarding em massa de novos clientes (CSV de tenants).

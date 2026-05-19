# Spec D10 · Mobile-First · PWA, Push, Offline, Geolocation

**Status**: especificação · pré-implementação
**Versão**: 1.0 · 18 de maio de 2026
**Escopo**: tornar R2 People nativo no celular do colaborador via PWA, push notifications, modo offline básico, geolocation opcional p/ check-in
**Depende de**: spec M12 (notif runtime), spec D6 (security headers), spec D8 (multi-tenant isolation), spec M21 (mobile-first chão de loja)

---

## 1. Por que mobile-first é estratégico

**80% dos colaboradores brasileiros não tem desktop no trabalho**. Chão de loja, almoxarifado, vigilância, ASG, motorista, repositor — todos usam celular. Se R2 People não funciona bem no celular, **fica restrito a RH e administrativo** (20% da empresa) e perde adoção.

### 1.1 Realidade de campo

| Cenário | Frequência |
|---|---|
| Operadora de caixa quer pedir férias entre clientes | semanal |
| Repositor quer ver holerite na hora do almoço | mensal |
| Motorista quer enviar atestado do PA | mensal |
| Vigilante quer assinar EPI recebido sem ir ao RH | mensal |
| Gerente regional vê alerta cobertura crítica em movimento | diário |
| Colaborador celebra aniversário do colega no mural | semanal |

Cada um desses casos precisa **abrir em < 3s no 4G** e funcionar sem fricção.

---

## 2. Estratégia: PWA (Progressive Web App)

**Por que PWA, não app nativo**:
- 1 codebase serve web + mobile
- Sem fila Apple Store / Play Store
- Atualização instantânea (sem aguardar review)
- Reduz CAC (cliente não precisa "instalar app")
- Push notification funciona em iOS (desde iOS 16.4) e Android
- Geolocation, câmera, biometria funcionam
- Offline cache via Service Worker

**Quando vale considerar nativo (pós-MVP)**:
- Se push do iOS começar a falhar muito
- Se cliente Enterprise exige "app na loja"
- Se feature avançada bloquear (NFC ponto, etc)

---

## 3. Camadas técnicas

### 3.1 Web App Manifest

```json
{
  "name": "R2 People",
  "short_name": "R2 People",
  "description": "Sua gestão de pessoas no celular",
  "start_url": "/home?source=pwa",
  "display": "standalone",
  "orientation": "portrait",
  "background_color": "#F4F7FC",
  "theme_color": "#2E476F",
  "icons": [
    {"src": "/assets/icon-192.png", "sizes": "192x192", "type": "image/png"},
    {"src": "/assets/icon-512.png", "sizes": "512x512", "type": "image/png"},
    {"src": "/assets/icon-maskable-512.png", "sizes": "512x512", "type": "image/png", "purpose": "maskable"}
  ],
  "screenshots": [
    {"src": "/assets/screen-home.png", "sizes": "750x1334", "type": "image/png", "form_factor": "narrow"}
  ],
  "shortcuts": [
    {"name": "Pedir férias", "url": "/ferias/programar"},
    {"name": "Enviar atestado", "url": "/atestado/enviar"},
    {"name": "Meu holerite", "url": "/trajetoria#holerite"},
    {"name": "Inbox líder", "url": "/lider/inbox"}
  ]
}
```

Tenant_admin pode customizar `theme_color`, `icons` e `name` no wizard de branding (M10/M13).

### 3.2 Service Worker

**Estratégias de cache**:

| Tipo de recurso | Estratégia |
|---|---|
| App shell (HTML/CSS/JS) | Cache-first com revalidação background |
| Imagens estáticas | Cache-first com TTL 30 dias |
| Avatars de pessoas | Stale-while-revalidate |
| API de dados pessoais | Network-first com fallback cache (1h) |
| Dado sensível (CID, salário) | Network-only (nunca cachear) |
| Push manifest | Cache-first |

Service worker registrado em `/sw.js`. Atualização forçada quando muda versão do app (notify user "Nova versão disponível → atualizar").

### 3.3 Push Notifications (Web Push)

**Casos de uso**:

| Quem | Notificação | Trigger |
|---|---|---|
| Colaborador | "Seu atestado foi validado ✓" | RH valida |
| Colaborador | "Suas férias 15-20/jun foram aprovadas" | líder aprova |
| Colaborador | "Reembolso pago · R$ 482 na próxima folha" | RH aprova |
| Colaborador | "Hoje é aniversário do Carlos! Mande um abraço 🎉" | data |
| Líder | "Fernanda pediu férias · aguardando você" | nova solicitação |
| Líder | "🚨 Cestão L1: 3 caixas faltam agora (escala previa 6)" | absent crítico |
| Líder | "Hoje sua 1:1 com João às 14h" | 1h antes |
| Gerente regional | "🔴 Inhambupe: cobertura crítica · 1/3 caixas" | tempo real |
| Diretoria | "Turnover do mês: 12% (era 8% mês anterior)" | mensal |

**Tecnologia**: Web Push Protocol c/ VAPID keys + Firebase Cloud Messaging fallback (Android sem Push API).

**Permissão**:
- Pedida SÓ no segundo uso (não no primeiro login, anti-pattern)
- Pré-pedido contextual ("Quer ser avisado quando seu pedido for aprovado?") antes do browser prompt
- Reduz negação de ~70% para ~15% (UX literature)

### 3.4 Modo offline

**O que funciona offline**:
- Ver dados em cache (holerite recente, dependentes, próximas férias)
- Visualizar comunicados já carregados
- Rascunhar novo atestado (envia quando volta online)
- Ver perfil próprio + histórico
- Ver calendar de 1:1s e ausências

**O que NÃO funciona offline (por design)**:
- Aprovar/rejeitar (decisão precisa estar sincronizada)
- Login (auth requer rede)
- Dado sensível em tempo real
- Compras de plano (billing)

**Indicador visual**: badge fixo "📴 Modo offline" quando sem rede + sync pendente count.

### 3.5 Geolocation (opcional)

**Usos**:

| Caso | Permissão |
|---|---|
| Check-in de visita técnica (raro em varejo, comum em serviços) | opt-in explícito |
| Sugestão de filial no setup (lat/long ↔ loja mais próxima) | opt-in |
| Confirmar entrega de EPI (foto + geo do recebimento) | opt-in |
| LGPD: geo cidade no aceite de termo (D7) | opt-in granular |

**Nunca usar para**: rastreamento contínuo, "vigilância", controle de jornada (existem sistemas dedicados). R2 People **não é controle de ponto**.

Tenant_admin define no setup quais features de geo são habilitadas no tenant.

---

## 4. Otimizações de performance mobile

| Métrica | Meta 4G | Meta 3G |
|---|---|---|
| FCP (First Contentful Paint) | < 1.5s | < 3s |
| LCP (Largest Contentful Paint) | < 2.5s | < 5s |
| TTI (Time to Interactive) | < 3s | < 6s |
| TBT (Total Blocking Time) | < 200ms | < 600ms |
| Bundle JS inicial | < 80KB gzip | idem |
| Bundle CSS inicial | < 25KB gzip | idem |

**Técnicas**:
- Code splitting por rota (Next.js já faz)
- Lazy load imagens (loading="lazy")
- Skeleton screens em vez de spinner
- Preload de fonts críticas
- Font subset (só caracteres pt-BR)
- Worker thread para parsers pesados (OCR Tesseract)
- HTTP/3 + Brotli compression no servidor

---

## 5. UI mobile-specific

### 5.1 Adaptações por tela

| Tela | Mobile-specific |
|---|---|
| Home | Cards em coluna única · KPIs swipeable · pull-to-refresh |
| Inbox líder | Side-panel equipe vira drawer hamburguer · aprovar com swipe |
| Calendar | Vista semanal padrão (não mensal · mobile espaço limitado) |
| Atestado upload | Câmera direta · OCR client-side · sem precisar de PC |
| Holerite | PDF nativo no celular · share button (WhatsApp família) |
| 1:1s | Notas em voz (transcrição automática · pós-MVP) |
| Benefícios | Cards swipeable · "Aderir" full-screen modal |
| Reembolso | Câmera para NF · OCR extrai valor · 1 click submeter |

### 5.2 Padrões touch

- Botões mínimo 44×44px (Apple HIG)
- Espaçamento entre toques 8px mín.
- Swipe right = back (consistente c/ iOS)
- Long press = menu contextual
- Pull-to-refresh em listas
- Bottom sheet para ações ("Aderir benefício" abre por baixo)

### 5.3 Bottom navigation (futuro pós-MVP)

Em vez de hamburger menu, considerar **bottom nav fixa** com 5 ícones (Home · Equipe · Inbox · Mural · Perfil) — padrão Instagram/WhatsApp.

---

## 6. Schema (extensões mínimas)

```sql
-- Tokens de push notification
CREATE TABLE IF NOT EXISTS push_subscriptions (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id       uuid NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  user_id         uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  endpoint        text NOT NULL,
  p256dh_key      text NOT NULL,
  auth_key        text NOT NULL,
  user_agent      text,
  device_type     text,                            -- 'ios','android','desktop'
  app_version     text,
  enabled         boolean NOT NULL DEFAULT true,
  silenced_categories text[] DEFAULT ARRAY[]::text[],
  created_at      timestamptz DEFAULT now(),
  last_used_at    timestamptz DEFAULT now(),
  UNIQUE (user_id, endpoint)
);

CREATE INDEX IF NOT EXISTS idx_push_active
  ON push_subscriptions (user_id) WHERE enabled = true;

-- Log de pushes enviados (debug + analytics)
CREATE TABLE IF NOT EXISTS push_delivery_log (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id       uuid NOT NULL,
  user_id         uuid NOT NULL,
  subscription_id uuid REFERENCES push_subscriptions(id) ON DELETE SET NULL,
  category        text NOT NULL,
  title           text NOT NULL,
  body            text,
  payload         jsonb,
  status          text NOT NULL CHECK (status IN ('queued','sent','delivered','clicked','failed','expired')),
  sent_at         timestamptz,
  clicked_at      timestamptz,
  error_msg       text
);

CREATE INDEX IF NOT EXISTS idx_push_log_recent
  ON push_delivery_log (sent_at DESC);

-- Geolocation events (opt-in)
CREATE TABLE IF NOT EXISTS geo_events (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id       uuid NOT NULL,
  user_id         uuid NOT NULL,
  event_type      text NOT NULL,                  -- 'epi_delivery','visit_checkin','terms_acceptance'
  lat             numeric(10,7),
  lng             numeric(10,7),
  accuracy_m      int,
  city            text,
  state           text,
  occurred_at     timestamptz DEFAULT now()
);

-- Service Worker cache version (controla refresh forçado)
CREATE TABLE IF NOT EXISTS pwa_versions (
  version         text PRIMARY KEY,
  released_at     timestamptz DEFAULT now(),
  breaking        boolean DEFAULT false,           -- força reload imediato
  release_notes   text
);
```

---

## 7. RPCs principais

```sql
-- Registrar subscription de push
rpc_push_register(p_endpoint text, p_p256dh text, p_auth text, p_device_type text)
  RETURNS uuid

-- Desabilitar push de uma categoria
rpc_push_silence_category(p_user_id uuid, p_category text)
  RETURNS void

-- Enviar push (chamado pelo worker)
rpc_push_send(p_user_id uuid, p_category text, p_title text, p_body text, p_payload jsonb)
  RETURNS int  -- nº de devices entregues

-- Registrar evento de geolocalização
rpc_geo_record(p_event_type text, p_lat numeric, p_lng numeric, p_accuracy int)
  RETURNS uuid

-- Versão atual do PWA (Service Worker consulta)
rpc_pwa_current_version() RETURNS TABLE (version text, breaking boolean, notes text)
```

---

## 8. Permissões e preferências (UX)

### 8.1 Tela "Preferências mobile"

Em `r2_people_perfil_mobile.html` (a criar):
- Toggle por categoria de notif (atestado/férias/reembolso/aniversário/1:1/etc)
- Quiet hours (não notificar entre X e Y · respeita timezone do user)
- Geolocation: ativado/desativado por feature
- Limpar cache (debug)
- Versão app + data última atualização
- "Desinstalar" (limpa subscription + cache)

### 8.2 Onboarding mobile

Primeira vez no PWA:
1. Tela boas-vindas explicando o que é
2. "Instalar na tela inicial" CTA (com tutorial visual)
3. Solicitação de notificações **contextual** (após primeiro evento útil)
4. Solicitação de geolocation **só se feature ativa**

---

## 9. Testes meta (mínimo 18)

- ✓ App instala como PWA em Chrome Android
- ✓ App instala como PWA em Safari iOS
- ✓ Manifest validado pelo Lighthouse (PWA score 100)
- ✓ FCP < 1.5s em 4G simulado
- ✓ Service Worker cacheia app shell
- ✓ Offline: home carrega de cache
- ✓ Offline: pode rascunhar atestado e enviar quando volta online
- ✓ Push notification chega em < 5s em Android
- ✓ Push notification chega em iOS 16.4+
- ✓ Push respeita silenced_categories
- ✓ Push respeita quiet hours
- ✓ Click em push abre tela correta
- ✓ Atualização forçada quando breaking=true
- ✓ Geolocation pede permissão só se feature ativa
- ✓ Geolocation falha silenciosamente se user nega
- ✓ Dado sensível (CID) nunca aparece em cache offline
- ✓ Logout limpa todos os caches + revoga subscription
- ✓ Versão antiga do SW atualiza para nova em background

---

## 10. Métricas norte

| Métrica | Meta 12m |
|---|---|
| **% de usuários ativos mobile** | > 60% (vs 40% desktop) |
| **Push opt-in rate** | > 50% (vs 15% padrão de mercado) |
| **Push click-through rate** | > 8% (média mercado 2%) |
| **PWA install rate** | > 25% dos usuários mobile |
| **Sessão média mobile** | > 3min |
| **FCP p75 mobile** | < 1.8s |
| **Crash rate** | < 0.1% |
| **Net Promoter Score mobile** | > 60 (avaliação app) |

---

## 11. Acessibilidade mobile

- WCAG 2.1 AA mínimo
- Suporte screen reader (TalkBack Android · VoiceOver iOS)
- Texto escalonável até 200% sem quebra
- Contraste 4.5:1 obrigatório
- Áreas de toque 44×44px mínimo
- Skip links para conteúdo principal
- Estados focus visíveis em todas as ações

---

## 12. Roadmap pós-MVP

1. **M+3 · App store opcional** (wrapper Capacitor pra Apple Store)
2. **M+6 · Notas de 1:1 por voz** (transcrição automática via Web Speech API)
3. **M+9 · Reconhecimento facial pra confirmar identidade** (high security ops)
4. **M+12 · Bottom navigation** (após validação UX c/ piloto)
5. **M+18 · Modo dark verdadeiro** (não só tema · ajuste por sensor luz)
6. **M+24 · Apple Watch / Wear OS** (notif crítica c/ approve no relógio · só Enterprise)

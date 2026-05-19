# Spec M15 · Mobile-first · PWA + Push + Offline-first

**Status**: especificação · pré-implementação
**Versão**: 1.0 · 18 de maio de 2026
**Escopo**: PWA instalável, push notifications, offline-first com sync, mobile-specific features (camera, biometria, geofence opcional)
**Depende de**: spec M12 (notifications), spec D6 (security), spec D9 (API), spec D8 (RLS)

---

## 1. Por que mobile importa para PMEs brasileiras

A persona alvo do R2 People — colaborador de PME brasileira (rede de varejo, indústria média, serviços) — **vive no celular Android**, não no desktop:
- Líder de loja faz 1:1 sentado no estoque, pelo celular
- Operador de chão de fábrica reporta atestado no celular do RH
- Colaborador acessa benefícios e demonstrativo de folha **só do celular**
- Diretor regional vê dashboards consolidados no celular antes da reunião

**Sem mobile bom = adoção fraca = churn alto**.

### 1.1 Métricas alvo

| Métrica | Meta 12 meses |
|---|---|
| % de DAU vindo de mobile | > 65% |
| App install rate (PWA add to home screen) | > 40% dos usuários ativos |
| Push notification open rate | > 30% (vs ~5% e-mail) |
| Time-to-action (notif → ação) | mediana < 30s |
| Crash rate | < 0.1% |
| Cold start | < 2.5s |

---

## 2. Por que PWA, não app nativo (no MVP)

**Decisão**: PWA primeiro. Apps nativos (React Native ou Flutter) só após PMF mobile validado.

### 2.1 Trade-offs avaliados

| Critério | PWA | React Native | Flutter |
|---|---|---|---|
| Time-to-market | semanas | meses | meses |
| Custo manutenção | 1 codebase (web) | 1.5 codebases | 1.5 codebases |
| App Store presence | ❌ (precisa TWA pra Google Play) | ✅ | ✅ |
| Push notifications | ✅ (Web Push) | ✅ FCM | ✅ FCM |
| Câmera para atestado | ✅ getUserMedia | ✅ | ✅ |
| Biometria (digital/face) | ⚠ WebAuthn | ✅ | ✅ |
| Offline | ✅ Service Worker | ✅ | ✅ |
| Geofence (opcional) | ⚠ limitado | ✅ | ✅ |
| Performance | boa o suficiente | melhor | melhor |

PWA cobre 90% das necessidades + reusa codebase web + lança em semanas. **Decisão pragmática**.

### 2.2 Plano pós-MVP

- M+6: avaliar adoção PWA
- M+9: se mobile > 70% DAU, considerar app nativo via React Native (mantém ~80% lógica compartilhada com web)
- Não plano para Flutter (stack TypeScript + React já dominado pela equipe)

---

## 3. Arquitetura PWA

### 3.1 Stack

- **Next.js 14 App Router** (mesma codebase web)
- **next-pwa** ou implementação manual de Service Worker
- **Workbox** para estratégias de cache
- **Web Push API** + VAPID keys
- **IndexedDB** para storage local (via Dexie.js)

### 3.2 Manifest

```json
{
  "name": "R2 People · Gestão de Pessoas",
  "short_name": "R2 People",
  "description": "RH digital com LGPD de verdade",
  "start_url": "/?source=pwa",
  "display": "standalone",
  "orientation": "portrait-primary",
  "theme_color": "#2E476F",
  "background_color": "#F4F7FC",
  "icons": [
    {"src":"/icons/icon-192.png","sizes":"192x192","type":"image/png","purpose":"any"},
    {"src":"/icons/icon-512.png","sizes":"512x512","type":"image/png","purpose":"any maskable"}
  ],
  "shortcuts": [
    {"name":"Enviar atestado","url":"/atestados/novo","icons":[...]},
    {"name":"1:1 hoje","url":"/oneonones/hoje","icons":[...]},
    {"name":"Minha folha","url":"/folha/atual","icons":[...]}
  ],
  "share_target": {
    "action": "/atestados/upload",
    "method": "POST",
    "enctype": "multipart/form-data",
    "params": {"files": [{"name": "file", "accept": ["image/*", "application/pdf"]}]}
  }
}
```

### 3.3 Service Worker strategies

| Recurso | Estratégia | Justificativa |
|---|---|---|
| HTML pages | NetworkFirst (timeout 3s, fallback cache) | Conteúdo dinâmico |
| API GET (employees, etc) | StaleWhileRevalidate (TTL 5min) | Mostra cache enquanto busca update |
| API POST/PUT/DELETE | NetworkOnly + offline queue | Mutações precisam de network |
| Assets estáticos (CSS, JS, fonts) | CacheFirst (1 ano) | Versionados via hash no nome |
| Imagens (atestados, fotos) | CacheFirst (30 dias) | Não muda após upload |
| Manifest, icons | StaleWhileRevalidate | Atualiza sem bloquear |

---

## 4. Offline-first sync

### 4.1 Cenários offline críticos

| Ação | Comportamento offline |
|---|---|
| Ver lista de funcionários | Cache local (últimas 50 acessadas) |
| Ver detalhe próprio (perfil, holerites) | Cache completo (sync nightly) |
| Submeter atestado | Queue local + upload quando online |
| Responder 1:1 | Queue local |
| Aprovar movement | Queue local (idempotency-key gerada client) |
| Pesquisa de clima | Funciona 100% offline, sync depois |

### 4.2 Outbox pattern

```typescript
// Pseudo-código simplificado
class Outbox {
  async enqueue(operation: PendingOp) {
    await db.outbox.add({
      ...operation,
      idempotencyKey: crypto.randomUUID(),
      enqueuedAt: Date.now(),
      attempts: 0
    });
    this.trySync();
  }

  async trySync() {
    if (!navigator.onLine) return;
    const pending = await db.outbox.where('attempts').below(5).toArray();
    for (const op of pending) {
      try {
        await api.execute(op);
        await db.outbox.delete(op.id);
      } catch (e) {
        await db.outbox.update(op.id, { attempts: op.attempts + 1, lastError: e.message });
      }
    }
  }
}

// Hook em window
window.addEventListener('online', () => outbox.trySync());
setInterval(() => outbox.trySync(), 30_000); // best effort
```

### 4.3 Conflict resolution

- **Last-write-wins** com timestamp client (default)
- **Server validation** rejeita se conflict crítico (movement já aprovado por outro)
- **UI mostra** ⚠ "Sua mudança offline conflitou com outra" + opção de reaplicar

### 4.4 UI offline

- Banner amarelo "Você está offline" no topo
- Badge `⏳ pendente` em items que ainda não sincronizaram
- Tela `/sync-status` com fila atual visível
- "Sincronizar agora" button

---

## 5. Push notifications

### 5.1 Subscription

```typescript
// Pede permissão + registra subscription
async function enablePush() {
  const reg = await navigator.serviceWorker.ready;
  const sub = await reg.pushManager.subscribe({
    userVisibleOnly: true,
    applicationServerKey: urlBase64ToUint8Array(VAPID_PUBLIC_KEY)
  });
  await api.post('/v1/push-subscriptions', sub.toJSON());
}
```

### 5.2 Eventos com push (categorias)

| Categoria | Default | Quem pode silenciar |
|---|---|---|
| **Crítico** (segurança, MFA) | Sempre push | Nunca |
| **Aprovação requerida** (movement, atestado) | Push | Sim, mas avisa |
| **Mencionado** (1:1, comentário) | Push | Sim |
| **Lembrete** (check-in OKR, 1:1 agendada) | Push | Sim |
| **Informativo** (comunicado, novo módulo) | Sem push (só in-app) | n/a |

### 5.3 Quiet hours

- Default: silencia push entre 22h-7h timezone do user
- Crítico bypassa quiet hours (e.g. login suspeito)
- Configurável no perfil

### 5.4 Notification actions (rich push)

```javascript
self.registration.showNotification('Movement aguardando aprovação', {
  body: 'Fernanda Lima · promoção · +R$ 700',
  icon: '/icons/icon-192.png',
  badge: '/icons/badge-72.png',
  data: { movementId: 'abc-...', deepLink: '/movements/abc-.../approve' },
  actions: [
    { action: 'approve', title: '✓ Aprovar' },
    { action: 'view', title: 'Ver detalhes' }
  ]
});

// Quando user clica numa action
self.addEventListener('notificationclick', e => {
  e.notification.close();
  if (e.action === 'approve') {
    e.waitUntil(approveMovement(e.notification.data.movementId));
  } else {
    e.waitUntil(clients.openWindow(e.notification.data.deepLink));
  }
});
```

### 5.5 Schema

```sql
CREATE TABLE IF NOT EXISTS push_subscriptions (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id   uuid NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  user_id     uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  endpoint    text NOT NULL UNIQUE,
  p256dh_key  text NOT NULL,
  auth_key    text NOT NULL,
  user_agent  text,
  platform    text,                  -- 'ios','android','desktop'
  created_at  timestamptz DEFAULT now(),
  last_used_at timestamptz,
  active      boolean DEFAULT true
);

CREATE INDEX idx_push_user_active
  ON push_subscriptions (user_id) WHERE active = true;
```

---

## 6. Mobile-specific features

### 6.1 Câmera para upload de atestado

```html
<input type="file"
       accept="image/*,application/pdf"
       capture="environment">
```

iOS/Android abre câmera nativa direta. Combinado com OCR client-side (Tesseract WASM), atestado é processado em-device sem subir imagem (privacy by design — apenas o texto extraído é enviado se autorizado).

### 6.2 Biometria (WebAuthn)

Para login com Face ID / digital após primeiro login com senha + MFA:

```typescript
const cred = await navigator.credentials.create({
  publicKey: {
    challenge: serverChallenge,
    rp: { name: 'R2 People' },
    user: { id, name: email, displayName: fullName },
    pubKeyCredParams: [{ type: 'public-key', alg: -7 }],
    authenticatorSelection: { authenticatorAttachment: 'platform', userVerification: 'required' }
  }
});
```

Substitui MFA TOTP em devices confiáveis. Spec D3 (auth avançada) integra.

### 6.3 Compartilhar arquivo recebido (Share Target API)

Usuário recebe atestado por WhatsApp → menu compartilhar mostra "R2 People" → atestado entra direto na fila de upload.

### 6.4 Foto de perfil via câmera

`<input type="file" capture="user">` para selfie de perfil.

### 6.5 Geofence (opcional, futuro)

Para clientes de varejo: ponto eletrônico geofenced (só pode marcar dentro do polígono da loja). **Out of MVP** — só roadmap.

---

## 7. Performance mobile

### 7.1 Budget

| Métrica | Budget | Como medir |
|---|---|---|
| First Contentful Paint | < 1.8s 4G | Lighthouse mobile |
| Largest Contentful Paint | < 2.5s | Lighthouse mobile |
| Time to Interactive | < 3.5s | Lighthouse mobile |
| Cumulative Layout Shift | < 0.1 | Lighthouse mobile |
| Bundle JS inicial | < 200KB gzip | Webpack analyzer |
| Total weight (1ª visita) | < 500KB | Lighthouse |
| Total weight (cache hit) | < 50KB | Service Worker |

### 7.2 Otimizações específicas mobile

- Imagens: WebP + responsive srcset + lazy loading
- Fontes: preload + font-display: swap
- Code splitting agressivo por rota
- Skeleton screens em vez de spinners
- Touch targets ≥ 44×44px (Apple HIG)
- Inputs com `inputmode` correto (`tel`, `numeric`, `email`)
- Sem hover-only interactions

---

## 8. Acessibilidade mobile

- Contraste WCAG AAA onde possível (mín AA)
- Modo escuro respeita `prefers-color-scheme`
- Aumento de fonte respeita `font-size` do usuário (não usar px fixo, usar rem)
- TalkBack/VoiceOver testado em fluxos críticos
- Captions em vídeos
- Vibration API para feedback tátil em ações críticas (aprovar movement vibra 50ms)

---

## 9. Compatibilidade

| Plataforma | Suporte |
|---|---|
| iOS Safari 16.4+ | Full PWA (push em iOS 16.4+) |
| iOS Safari < 16.4 | Sem push, resto OK |
| Android Chrome | Full PWA + WebAPK install |
| Android Samsung Internet | Full PWA |
| Desktop Chrome/Edge | Full PWA + install card |
| Desktop Safari | Parcial (sem push web) |
| Desktop Firefox | Full PWA + push |

---

## 10. Testes meta (mínimo 25)

### 10.1 PWA install
- ✓ Manifest válido (Lighthouse PWA score 100)
- ✓ Service Worker registra sem erros
- ✓ "Add to Home Screen" prompt aparece após 2 visitas
- ✓ App instalado abre standalone (sem barra de URL)
- ✓ Shortcuts funcionam (atestado / 1:1 / folha)

### 10.2 Offline
- ✓ App abre offline (cached shell)
- ✓ Listas vistas online aparecem offline
- ✓ Atestado submetido offline aparece com badge ⏳
- ✓ Sincroniza quando volta online (event 'online')
- ✓ Idempotência impede duplicação se sync 2x
- ✓ Conflict 422 mostra UI de reapply

### 10.3 Push
- ✓ Subscription registrada no banco
- ✓ Push chega em < 5s do disparo
- ✓ Quiet hours respeitada (push de não-crítico delayed)
- ✓ Crítico bypassa quiet hours
- ✓ Notification action 'approve' funciona sem abrir app
- ✓ Deep link abre página correta

### 10.4 Mobile features
- ✓ Câmera abre direto em mobile com `capture="environment"`
- ✓ OCR client-side processa imagem em < 5s
- ✓ Share Target recebe arquivo do WhatsApp
- ✓ WebAuthn registra Face ID em iOS
- ✓ WebAuthn registra digital em Android

### 10.5 Performance
- ✓ Lighthouse mobile score > 90 em LCP/FCP/TTI
- ✓ Bundle inicial < 200KB gzip
- ✓ Cold start < 2.5s em 4G simulado
- ✓ Touch targets ≥ 44×44px (axe check)

### 10.6 Compatibilidade
- ✓ iOS Safari 16.4+ install + push
- ✓ Android Chrome instala como WebAPK
- ✓ Desktop Chrome instala
- ✓ Fallback graceful em browsers sem suporte

---

## 11. UI · adaptações específicas mobile

### 11.1 Navigation

Desktop tem sidebar 240px. Mobile precisa de:
- **Bottom tab bar** com 5 ações principais (Home, Pessoas, +, Notif, Eu)
- **Hamburger menu** para tudo mais (drawer slide-in)
- **Floating action button (FAB)** para ação primária da página

### 11.2 Forms

- Inputs full-width em mobile
- Keyboards específicos via `inputmode` (date, tel, numeric)
- Auto-zoom desabilitado em inputs (`<meta viewport>` + `font-size ≥ 16px`)
- Submit em sticky footer (sempre acessível)

### 11.3 Tables

Tables responsivas viram cards stacked:

```css
@media (max-width: 768px) {
  table.responsive thead { display: none; }
  table.responsive tr {
    display: block;
    background: #fff;
    border-radius: 10px;
    padding: 12px;
    margin-bottom: 8px;
  }
  table.responsive td {
    display: flex;
    justify-content: space-between;
    padding: 6px 0;
  }
  table.responsive td::before {
    content: attr(data-label);
    font-weight: 600;
    color: var(--txt2);
  }
}
```

---

## 12. Roadmap pós-MVP

1. **M+3**: app nativo iOS+Android via React Native (se PWA adoption > 60%)
2. **M+6**: Ponto eletrônico geofenced (clientes varejo)
3. **M+9**: Apple Watch / Wear OS companion (recebe push de aprovação)
4. **M+12**: Modo offline-first ainda mais profundo (rodar OCR + assinar movements 100% local)
5. **M+18**: app standalone Android instalável via APK direto (sem Play Store, para empresas com restrição)

---

## 13. Considerações LGPD mobile-specific

- **Permissões claras**: ao pedir push/câmera/biometria, explicar o porquê em PT-BR
- **Notification body** não vaza dado sensível: "Você tem uma aprovação pendente" (não "Promoção R$ 700 da Fernanda")
- **Biometria** processada localmente, R2 só recebe assertion (não a digital em si)
- **OCR client-side** mantém arquivo nunca em servidor R2 se usuário não autorizar
- **Push subscription** revogada automaticamente em logout + permission denied

# Spec · D1 · Supabase Auth Real

**Status:** crítica para deploy em produção · pronto para execução em ambiente com projeto Supabase
**Pré-requisitos:** projeto Supabase criado, migrations base aplicadas, conta de email para magic link
**Estimativa:** 1 sessão (~4-5h em ambiente preparado)

---

## 1. Objetivo

Substituir o stub atual em [src/lib/supabase.ts](../src/lib/supabase.ts) (que devolve `null` e mocka calls) pela integração real com Supabase Auth. Sem isso o produto **não vai pra produção**.

---

## 2. O que existe hoje

```typescript
// src/lib/supabase.ts (819 bytes · stub)
export function createClient() {
  return {
    auth: { getSession: async () => ({ data: { session: null } }) },
    rpc: async () => { throw new Error('Supabase not configured') }
  }
}
```

Todas as RPCs no banco (`current_user_id()`, `current_tenant_id()`) esperam `auth.uid()` retornar UUID válido do `auth.users.id`. Sem auth real, qualquer chamada falha.

---

## 3. O que entregar

### 3.1 Cliente Supabase real

`src/lib/supabase.ts` (browser) + `src/lib/supabase-server.ts` (server components/route handlers):

```typescript
// src/lib/supabase.ts (browser)
import { createBrowserClient } from '@supabase/ssr'

export function createClient() {
  return createBrowserClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!
  )
}

// src/lib/supabase-server.ts
import { createServerClient } from '@supabase/ssr'
import { cookies } from 'next/headers'

export function createServerClient() {
  const cookieStore = cookies()
  return createServerClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
    {
      cookies: {
        get: (name) => cookieStore.get(name)?.value,
        set: (name, value, options) => cookieStore.set({ name, value, ...options }),
        remove: (name, options) => cookieStore.delete({ name, ...options })
      }
    }
  )
}
```

### 3.2 Middleware de proteção de rotas

`src/middleware.ts`:

```typescript
import { createServerClient } from '@supabase/ssr'
import { NextResponse, type NextRequest } from 'next/server'

const PUBLIC_PATHS = ['/login', '/onboarding-callback', '/auth/callback']

export async function middleware(req: NextRequest) {
  const res = NextResponse.next()

  // Permitir rotas públicas
  if (PUBLIC_PATHS.some(p => req.nextUrl.pathname.startsWith(p))) {
    return res
  }

  const supabase = createServerClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
    {
      cookies: {
        get: (name) => req.cookies.get(name)?.value,
        set: (name, value, options) => res.cookies.set({ name, value, ...options }),
        remove: (name, options) => res.cookies.delete({ name, ...options })
      }
    }
  )

  const { data: { session } } = await supabase.auth.getSession()

  if (!session) {
    const url = req.nextUrl.clone()
    url.pathname = '/login'
    url.searchParams.set('next', req.nextUrl.pathname)
    return NextResponse.redirect(url)
  }

  // Validar que app_users existe para esse auth_user_id
  const { data: appUser } = await supabase
    .from('app_users')
    .select('id, tenant_id, role, active')
    .eq('auth_user_id', session.user.id)
    .single()

  if (!appUser || !appUser.active) {
    // Auth sessão existe mas não há app_users · força onboarding
    const url = req.nextUrl.clone()
    url.pathname = '/onboarding-callback'
    return NextResponse.redirect(url)
  }

  return res
}

export const config = {
  matcher: ['/((?!_next/static|_next/image|favicon.ico|public).*)']
}
```

### 3.3 Página de login (`src/app/login/page.tsx`)

Referência visual: [r2_people_login.html](../r2_people_login.html)

- Split-screen desktop + fullscreen mobile
- Tabs Email/CPF
- Botão "Entrar com Google" (OAuth)
- Magic link como fallback
- Tenant chip no canto

```tsx
'use client'
import { useState } from 'react'
import { createClient } from '@/lib/supabase'

export default function LoginPage() {
  const [email, setEmail] = useState('')
  const [sent, setSent] = useState(false)
  const supabase = createClient()

  async function sendMagicLink() {
    const { error } = await supabase.auth.signInWithOtp({
      email,
      options: {
        emailRedirectTo: `${window.location.origin}/auth/callback`
      }
    })
    if (!error) setSent(true)
  }

  async function signInWithGoogle() {
    await supabase.auth.signInWithOAuth({
      provider: 'google',
      options: { redirectTo: `${window.location.origin}/auth/callback` }
    })
  }

  // ... layout
}
```

### 3.4 Callback handler (`src/app/auth/callback/route.ts`)

```typescript
import { createServerClient } from '@/lib/supabase-server'
import { NextResponse } from 'next/server'

export async function GET(req: Request) {
  const url = new URL(req.url)
  const code = url.searchParams.get('code')
  const next = url.searchParams.get('next') ?? '/'

  if (code) {
    const supabase = createServerClient()
    await supabase.auth.exchangeCodeForSession(code)
  }

  return NextResponse.redirect(new URL(next, url.origin))
}
```

### 3.5 Trigger de criação de `app_users` no signup

```sql
-- migration: 00500_d1_trigger_app_users_from_auth.sql

CREATE OR REPLACE FUNCTION create_app_user_from_auth()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_tenant_slug TEXT;
  v_tenant_id UUID;
BEGIN
  -- Extrai tenant_slug do email (gpc@empresa.com.br → 'empresa') ou de raw_user_meta_data
  v_tenant_slug := COALESCE(
    NEW.raw_user_meta_data->>'tenant_slug',
    -- Fallback: derivar do domínio do email
    split_part(split_part(NEW.email, '@', 2), '.', 1)
  );

  SELECT id INTO v_tenant_id FROM tenants WHERE slug = v_tenant_slug;

  IF v_tenant_id IS NULL THEN
    -- Sem tenant correspondente, criar app_user "orphan" que será resolvido no onboarding
    -- Alternativa: rejeitar via RAISE EXCEPTION (escolha de produto)
    INSERT INTO app_users (
      tenant_id, auth_user_id, email, full_name, role, active
    ) VALUES (
      (SELECT id FROM tenants WHERE slug = 'orphan' LIMIT 1),  -- tenant especial
      NEW.id, lower(NEW.email),
      COALESCE(NEW.raw_user_meta_data->>'full_name', split_part(NEW.email, '@', 1)),
      'colaborador', FALSE  -- inativo até onboarding manual
    );
  ELSE
    INSERT INTO app_users (
      tenant_id, auth_user_id, email, full_name, role
    ) VALUES (
      v_tenant_id, NEW.id, lower(NEW.email),
      COALESCE(NEW.raw_user_meta_data->>'full_name', split_part(NEW.email, '@', 1)),
      'colaborador'
    );
  END IF;

  RETURN NEW;
END; $$;

CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION create_app_user_from_auth();
```

### 3.6 Wizard de onboarding (`src/app/onboarding-callback/page.tsx`)

Referência visual: [r2_people_onboarding.html](../r2_people_onboarding.html)

Tela mostrada quando usuário autentica mas não tem `app_users` vinculado:
- Pede: tenant slug (ou convite), nome completo, CPF
- RPC `rpc_complete_onboarding(p_tenant_slug, p_full_name, p_cpf)` vincula ao tenant

### 3.7 Hook `useUser`

```tsx
// src/hooks/useUser.ts
'use client'
import { useEffect, useState } from 'react'
import { createClient } from '@/lib/supabase'
import type { User } from '@supabase/supabase-js'

export interface AppUser {
  id: string; tenant_id: string; full_name: string;
  email: string; role: 'super_admin' | 'diretoria' | 'rh' | 'lider' | 'colaborador';
  avatar_url: string | null;
}

export function useUser() {
  const [user, setUser] = useState<AppUser | null>(null)
  const [loading, setLoading] = useState(true)

  useEffect(() => {
    const supabase = createClient()

    async function load() {
      const { data: { session } } = await supabase.auth.getSession()
      if (!session) { setLoading(false); return }

      const { data } = await supabase
        .from('app_users')
        .select('id, tenant_id, full_name, email, role, avatar_url')
        .eq('auth_user_id', session.user.id)
        .single()

      setUser(data)
      setLoading(false)
    }

    load()

    const { data: subscription } = supabase.auth.onAuthStateChange(() => load())
    return () => subscription.subscription.unsubscribe()
  }, [])

  return { user, loading }
}
```

---

## 4. Configuração no painel Supabase

### 4.1 Auth providers

- **Email** (magic link): habilitar
- **Google OAuth**: configurar (precisa de Google Cloud Console com OAuth client)
- **Email confirmações**: desabilitar para magic link sem fricção (ou manter se quiser email verification)

### 4.2 URL configuration

- Site URL: `https://r2people.vercel.app` (ou domínio próprio)
- Redirect URLs:
  - `http://localhost:3000/auth/callback` (dev)
  - `https://r2people.vercel.app/auth/callback` (prod)

### 4.3 Email templates customizados (PT-BR)

Editar em Authentication > Email Templates:
- Confirm signup
- Magic Link
- Reset password

Templates devem usar branding R2 People (logo, cores navy/orange).

---

## 5. Variáveis de ambiente

`.env.local` (ver `.env.example`):

```bash
NEXT_PUBLIC_SUPABASE_URL=https://xxx.supabase.co
NEXT_PUBLIC_SUPABASE_ANON_KEY=eyJ...
SUPABASE_SERVICE_ROLE_KEY=eyJ...           # apenas server-side
DATABASE_URL=postgres://...                 # para migrations
```

---

## 6. Testes

`supabase/tests/00500_d1_auth_trigger.sql`:

```sql
BEGIN;

-- Mock auth.users insert
INSERT INTO tenants (id, slug, legal_name, display_name) VALUES
  ('d1tenant-0000-0000-0000-000000000001', 'gpc', 'Grupo Pinto Cerqueira', 'GPC');

INSERT INTO auth.users (id, email, raw_user_meta_data) VALUES
  ('d1auth01-0000-0000-0000-000000000001', 'novo@gpc.com.br',
   '{"tenant_slug": "gpc", "full_name": "João Novo"}'::jsonb);

-- Verifica que trigger criou app_users
SELECT _assert_eq(
  (SELECT full_name FROM app_users WHERE auth_user_id = 'd1auth01-0000-0000-0000-000000000001'),
  'João Novo',
  'trigger cria app_users via raw_user_meta_data'
);

-- Email sem tenant_slug, sem domínio matchando, vai pra orphan
INSERT INTO tenants (id, slug, legal_name, display_name) VALUES
  ('d1tenant-9999-0000-0000-000000000099', 'orphan', 'Orphan Tenant', 'Orphan');

INSERT INTO auth.users (id, email) VALUES
  ('d1auth01-9999-0000-0000-000000000099', 'estranho@desconhecido.com');

SELECT _assert_eq(
  (SELECT active FROM app_users WHERE auth_user_id = 'd1auth01-9999-0000-0000-000000000099'),
  FALSE,
  'app_user orphan criado como inativo'
);

ROLLBACK;
```

---

## 7. Critérios de aceitação

- [ ] `src/lib/supabase.ts` substituído (não é mais stub)
- [ ] `src/lib/supabase-server.ts` criado
- [ ] `src/middleware.ts` protege todas as rotas exceto `/login`, `/onboarding-callback`, `/auth/callback`
- [ ] Página `/login` funcional com magic link + Google
- [ ] Callback handler troca code por session corretamente
- [ ] Wizard `/onboarding-callback` resolve usuários sem `app_users`
- [ ] Trigger `on_auth_user_created` cria `app_users` no signup
- [ ] Hook `useUser` retorna user tipado
- [ ] `tsc --noEmit --strict` zero erros
- [ ] Smoke test: login com magic link → recebe email → clica → redirect → ver dashboard
- [ ] Smoke test: logout → tentar acessar `/dashboard` → redirect para `/login`
- [ ] RPCs existentes funcionam com `auth.uid()` real (testar `rpc_navbar()`)

---

## 8. Pontos de atenção

- **Email transacional**: Supabase tem limite de 30 emails/hora no plano free. Para produção, configurar provedor SMTP próprio (Resend, SendGrid)
- **Magic link expiration**: padrão 60min, configurável em Auth > Settings
- **Trigger SECURITY DEFINER**: executa como postgres role, então pode INSERT em `app_users` mesmo com RLS ligado
- **Tenant onboarding**: o trigger atual é otimista (deriva do domínio). Para enterprise, melhor exigir convite (`tenant_invitations` table) e validar token
- **Google OAuth precisa de domínio verificado** no Google Cloud Console para sair de "test" mode
- **Cookie SameSite**: padrão `lax` funciona. Se hospedar frontend em domínio diferente do Supabase, precisa `none` + `secure`
- **CSP**: se adicionar Content Security Policy, permitir `frame-src` do Supabase para magic link
- **Logout completo**: chamar `supabase.auth.signOut({ scope: 'global' })` para invalidar sessão em todos os devices
- **Erro `JWT expired`**: middleware deve detectar e forçar re-login

---

## 9. Itens fora desta sessão (próximas)

- **SSO SAML/OIDC** (para enterprise)
- **MFA TOTP** (autenticação 2 fatores)
- **Convites por email** (`tenant_invitations`)
- **Password reset flow** (se for usar senhas além de magic link)
- **Auditoria de login** (registrar IP, user agent no `audit_log`)
- **Rate limiting** (proteção contra abuso de magic link)

---

**Comando de execução:**

```bash
# 1. Criar projeto Supabase em app.supabase.com
# 2. Aplicar migrations existentes + trigger novo
psql $DATABASE_URL -v ON_ERROR_STOP=1 -f supabase/migrations/00500_d1_trigger_app_users_from_auth.sql

# 3. Configurar OAuth e templates de email no painel

# 4. Instalar deps frontend
npm install @supabase/ssr @supabase/supabase-js

# 5. Preencher .env.local
cp .env.example .env.local
# editar URL e keys

# 6. Subir dev server
npm run dev

# 7. Testar fluxo de login manualmente
# 8. Validar TS
tsc --noEmit --strict
```

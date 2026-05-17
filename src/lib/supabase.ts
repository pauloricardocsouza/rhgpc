/**
 * R2 People · Supabase client
 * ============================================================================
 * Browser client para uso em Server/Client Components do Next.js App Router.
 *
 * Configuracao:
 *   - Defina NEXT_PUBLIC_SUPABASE_URL e NEXT_PUBLIC_SUPABASE_ANON_KEY no .env.local
 *   - Esta versao usa @supabase/ssr (recomendado pelo Supabase para Next.js 14+)
 *
 * Para Server Components, crie um arquivo separado src/lib/supabase-server.ts
 * usando createServerClient com cookies do next/headers.
 * ============================================================================
 */

import { createBrowserClient } from '@supabase/ssr'

export function createClient() {
  return createBrowserClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
  )
}

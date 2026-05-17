'use client'

/**
 * R2 People · Sessao B3 · AppShell
 * ============================================================================
 * Wrapper de layout: sidebar + main content area.
 * Use em app/(authenticated)/layout.tsx ou similar.
 *
 * Exemplo de uso:
 *
 *   // app/(authenticated)/layout.tsx
 *   import { AppShell } from '@/components/AppShell'
 *
 *   export default function Layout({ children }: { children: React.ReactNode }) {
 *     return <AppShell>{children}</AppShell>
 *   }
 * ============================================================================
 */

import { Sidebar } from './Sidebar'

export function AppShell({ children }: { children: React.ReactNode }) {
  return (
    <div className="flex min-h-screen bg-zinc-50">
      <Sidebar />
      <main className="flex-1 min-w-0 overflow-x-auto">
        {children}
      </main>
    </div>
  )
}

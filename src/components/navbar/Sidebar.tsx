'use client'

/**
 * R2 People · Sessao B3 · Sidebar
 * ============================================================================
 * Sidebar vertical colapsavel.
 *
 * Estados:
 *   - Expandida (240px) · icone + label
 *   - Colapsada (64px)  · so icone, tooltip ao hover
 *
 * Decisoes:
 *   - Estado collapsed persistido em localStorage (key: r2p:sidebar:collapsed)
 *   - Modulo readonly (soft_disabled): mostra cadeado ao lado do nome
 *   - Modulo inativo: nao aparece (filtragem feita no backend)
 *   - Sections agrupadas com header (apenas no estado expandido)
 *
 * Stack:
 *   - Next.js App Router (use o hook usePathname para active state)
 *   - lucide-react (icones dinamicos por nome)
 *   - Tailwind CSS
 * ============================================================================
 */

import { useState, useEffect } from 'react'
import Link from 'next/link'
import { usePathname } from 'next/navigation'
import {
  Home, Users, Network, Award, TrendingUp, UserPlus, Grid3x3, Activity,
  BarChart3, Layers, Building2, UserCog, FileSearch, User, Lock,
  ChevronLeft, ChevronRight, Loader2, AlertTriangle,
} from 'lucide-react'
import { useNavbar, type NavbarItem } from './useNavbar'

const ICON_MAP: Record<string, React.ComponentType<{ className?: string }>> = {
  Home, Users, Network, Award, TrendingUp, UserPlus, Grid3x3, Activity,
  BarChart3, Layers, Building2, UserCog, FileSearch, User,
}

const STORAGE_KEY = 'r2p:sidebar:collapsed'

const SECTION_LABELS: Record<string, string> = {
  main: 'Principal',
  modules: 'Modulos',
  admin: 'Administracao',
}

// ============================================================================

export function Sidebar() {
  const { loading, error, role, items } = useNavbar()
  const pathname = usePathname()
  const [collapsed, setCollapsed] = useState(false)
  const [mounted, setMounted] = useState(false)

  // Hidrata estado collapsed do localStorage apos mount (evita SSR mismatch)
  useEffect(() => {
    setMounted(true)
    try {
      const v = localStorage.getItem(STORAGE_KEY)
      if (v === '1') setCollapsed(true)
    } catch {}
  }, [])

  const toggle = () => {
    const next = !collapsed
    setCollapsed(next)
    try { localStorage.setItem(STORAGE_KEY, next ? '1' : '0') } catch {}
  }

  // Agrupa items por section preservando ordem
  const sections: { name: string; items: NavbarItem[] }[] = []
  const seen: Record<string, number> = {}
  items.forEach(it => {
    if (!(it.section in seen)) {
      seen[it.section] = sections.length
      sections.push({ name: it.section, items: [] })
    }
    sections[seen[it.section]].items.push(it)
  })

  return (
    <aside
      className={[
        'sticky top-0 h-screen flex flex-col bg-zinc-950 text-zinc-100',
        'border-r border-zinc-800 transition-all duration-200 ease-out',
        collapsed ? 'w-16' : 'w-60',
      ].join(' ')}
    >
      {/* Header */}
      <div className={['flex items-center px-3 h-14 border-b border-zinc-800', collapsed ? 'justify-center' : 'justify-between'].join(' ')}>
        {!collapsed && (
          <span className="text-sm font-semibold tracking-wide">
            R2 <span className="text-zinc-400">People</span>
          </span>
        )}
        <button
          onClick={toggle}
          className="p-1.5 rounded hover:bg-zinc-800 text-zinc-400 hover:text-zinc-100 transition"
          aria-label={collapsed ? 'Expandir sidebar' : 'Colapsar sidebar'}
        >
          {collapsed ? <ChevronRight className="h-4 w-4" /> : <ChevronLeft className="h-4 w-4" />}
        </button>
      </div>

      {/* Estados */}
      {loading && (
        <div className="flex-1 flex items-center justify-center">
          <Loader2 className="h-4 w-4 animate-spin text-zinc-500" />
        </div>
      )}

      {error && (
        <div className="m-3 p-2 rounded bg-red-950/50 border border-red-900 text-xs text-red-300 flex gap-2 items-start">
          <AlertTriangle className="h-3.5 w-3.5 flex-shrink-0 mt-0.5" />
          {!collapsed && <span>{error}</span>}
        </div>
      )}

      {/* Items */}
      {!loading && !error && (
        <nav className="flex-1 overflow-y-auto py-2">
          {sections.map((sec, idx) => (
            <div key={sec.name} className={idx > 0 ? 'mt-3' : ''}>
              {!collapsed && (
                <div className="px-3 py-1 text-[10px] font-semibold uppercase tracking-wider text-zinc-500">
                  {SECTION_LABELS[sec.name] ?? sec.name}
                </div>
              )}
              {collapsed && idx > 0 && (
                <div className="mx-3 my-2 border-t border-zinc-800" />
              )}
              <ul>
                {sec.items.map(item => (
                  <SidebarItem
                    key={item.key}
                    item={item}
                    collapsed={collapsed}
                    isActive={mounted && (pathname === item.path || pathname.startsWith(item.path + '/'))}
                  />
                ))}
              </ul>
            </div>
          ))}
        </nav>
      )}

      {/* Footer · papel atual */}
      {!loading && !error && role && (
        <div className={['border-t border-zinc-800 px-3 py-2', collapsed ? 'text-center' : ''].join(' ')}>
          {collapsed ? (
            <div title={role} className="h-7 w-7 mx-auto rounded-full bg-zinc-800 flex items-center justify-center text-[10px] font-mono uppercase">
              {role.slice(0, 2)}
            </div>
          ) : (
            <div className="text-[10px] text-zinc-500 uppercase tracking-wider">
              Logado como <span className="text-zinc-300 font-mono">{role}</span>
            </div>
          )}
        </div>
      )}
    </aside>
  )
}

// ============================================================================
// SidebarItem · linha individual com tooltip quando colapsado
// ============================================================================

function SidebarItem({
  item, collapsed, isActive,
}: { item: NavbarItem; collapsed: boolean; isActive: boolean }) {
  const Icon = ICON_MAP[item.icon] ?? Layers

  return (
    <li>
      <Link
        href={item.path}
        title={collapsed ? `${item.label}${item.readonly ? ' (somente leitura)' : ''}` : undefined}
        className={[
          'flex items-center gap-3 mx-2 my-0.5 px-2 py-2 rounded text-sm transition',
          isActive
            ? 'bg-zinc-800 text-white'
            : 'text-zinc-300 hover:bg-zinc-800/50 hover:text-white',
          collapsed ? 'justify-center' : '',
        ].join(' ')}
      >
        <Icon className="h-4 w-4 flex-shrink-0" />
        {!collapsed && (
          <>
            <span className="flex-1 truncate">{item.label}</span>
            {item.readonly && (
              <Lock
                className="h-3.5 w-3.5 text-amber-400 flex-shrink-0"
                aria-label="Modulo em somente leitura"
              />
            )}
          </>
        )}
        {collapsed && item.readonly && (
          <span className="absolute ml-6 -mt-3 h-2 w-2 rounded-full bg-amber-400" aria-label="Somente leitura" />
        )}
      </Link>
    </li>
  )
}

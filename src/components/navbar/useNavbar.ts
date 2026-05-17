'use client'

/**
 * R2 People · Sessao B3 · useNavbar hook
 * ============================================================================
 * Faz fetch via adapter R2 (Sessao C4) e mantem cache em sessionStorage.
 * Cache invalidado em: refresh manual, mudanca de role, logout.
 *
 * Exporta tambem `clearNavbarCache()` para usar apos logout.
 * ============================================================================
 */

import { useEffect, useState, useCallback } from 'react'
import { Navbar, RpcError, type NavbarItem, type UserRole } from '@/lib/r2'

export type { NavbarItem, NavbarSection } from '@/lib/r2'

export interface NavbarState {
  loading: boolean
  error: string | null
  role: UserRole | null
  items: NavbarItem[]
  refresh: () => Promise<void>
}

const CACHE_KEY = 'r2p:navbar:v1'
const CACHE_TTL_MS = 5 * 60 * 1000  // 5 minutos

interface CacheEntry {
  ts: number
  role: UserRole
  items: NavbarItem[]
}

function readCache(): CacheEntry | null {
  if (typeof window === 'undefined') return null
  try {
    const raw = sessionStorage.getItem(CACHE_KEY)
    if (!raw) return null
    const entry = JSON.parse(raw) as CacheEntry
    if (Date.now() - entry.ts > CACHE_TTL_MS) return null
    return entry
  } catch {
    return null
  }
}

function writeCache(role: UserRole, items: NavbarItem[]) {
  if (typeof window === 'undefined') return
  try {
    sessionStorage.setItem(CACHE_KEY, JSON.stringify({ ts: Date.now(), role, items }))
  } catch {
    // Storage cheio ou indisponivel · ignora silenciosamente
  }
}

export function clearNavbarCache() {
  if (typeof window === 'undefined') return
  try { sessionStorage.removeItem(CACHE_KEY) } catch {}
}

export function useNavbar(): NavbarState {
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)
  const [role, setRole] = useState<UserRole | null>(null)
  const [items, setItems] = useState<NavbarItem[]>([])

  const fetchNavbar = useCallback(async (skipCache = false) => {
    setError(null)

    if (!skipCache) {
      const cached = readCache()
      if (cached) {
        setRole(cached.role)
        setItems(cached.items)
        setLoading(false)
        return
      }
    }

    setLoading(true)
    try {
      const r = await Navbar.get()
      setRole(r.role)
      setItems(r.items)
      writeCache(r.role, r.items)
    } catch (err) {
      setError(err instanceof RpcError ? err.code : 'unknown_error')
    } finally {
      setLoading(false)
    }
  }, [])

  const refresh = useCallback(async () => {
    clearNavbarCache()
    await fetchNavbar(true)
  }, [fetchNavbar])

  useEffect(() => {
    fetchNavbar()
  }, [fetchNavbar])

  return { loading, error, role, items, refresh }
}

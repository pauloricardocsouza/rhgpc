'use client'

/**
 * R2 People · /pessoas
 * ============================================================================
 * Dashboard de pessoas (ficha de empregado).
 *
 * Funcionalidades:
 *   - Busca livre (nome, CPF, matricula)
 *   - Filtros: status (ativo/desligado/todos), employer_unit, working_unit, cargo
 *   - Grid de cards com avatar, nome, cargo, matricula, badge "Desligado"
 *   - Paginacao (carregar mais)
 *   - Botoes: Importar (XLSX/PDF) e Nova ficha
 *
 * Permissoes: visivel para todos no tenant. Botoes de escrita
 * apenas para diretoria e rh.
 * ============================================================================
 */

import { useEffect, useState, useCallback, useMemo } from 'react'
import Link from 'next/link'
import {
  Search, Filter, Users, Plus, Upload, Loader2,
  AlertTriangle, BadgeCheck, BadgeX,
} from 'lucide-react'

import {
  Employees,
  RpcError,
  type EmployeeListItem,
  type EmployeeStatus,
} from '@/lib/r2'

import { ImportDialog } from '@/components/employees/ImportDialog'

const PAGE_SIZE = 30

export default function PessoasPage() {
  const [items, setItems] = useState<EmployeeListItem[]>([])
  const [total, setTotal] = useState(0)
  const [loading, setLoading] = useState(true)
  const [errorCode, setErrorCode] = useState<string | null>(null)

  // Filtros
  const [search, setSearch] = useState('')
  const [status, setStatus] = useState<EmployeeStatus>('all')
  const [jobTitle, setJobTitle] = useState('')

  // Paginacao
  const [offset, setOffset] = useState(0)

  // Dialogs
  const [showImport, setShowImport] = useState(false)

  const fetchPage = useCallback(async (reset = false) => {
    setLoading(true)
    setErrorCode(null)
    try {
      const r = await Employees.list({
        search: search || undefined,
        status,
        jobTitle: jobTitle || undefined,
        limit: PAGE_SIZE,
        offset: reset ? 0 : offset,
      })
      if (reset) {
        setItems(r.employees)
        setOffset(PAGE_SIZE)
      } else {
        setItems((prev) => [...prev, ...r.employees])
        setOffset((prev) => prev + PAGE_SIZE)
      }
      setTotal(r.total)
    } catch (err) {
      setErrorCode(err instanceof RpcError ? err.code : 'unknown_error')
    } finally {
      setLoading(false)
    }
  }, [search, status, jobTitle, offset])

  // Reset ao mudar filtros
  useEffect(() => {
    const handle = setTimeout(() => {
      setOffset(0)
      fetchPage(true)
    }, search ? 300 : 0)  // debounce 300ms na busca livre
    return () => clearTimeout(handle)
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [search, status, jobTitle])

  const stats = useMemo(() => {
    const active = items.filter(e => e.is_active).length
    const terminated = items.filter(e => !e.is_active).length
    return { active, terminated, total }
  }, [items, total])

  const hasMore = items.length < total

  return (
    <div className="max-w-7xl mx-auto p-6 space-y-6">
      <header className="flex items-start justify-between gap-4 border-b border-zinc-200 pb-4">
        <div>
          <h1 className="text-2xl font-semibold text-zinc-900 flex items-center gap-2">
            <Users className="h-6 w-6 text-zinc-700" />
            Pessoas
          </h1>
          <p className="text-sm text-zinc-500 mt-1">
            {total > 0 ? (
              <>
                {stats.active} ativos · {stats.terminated} desligados · {total} total
              </>
            ) : (
              'Carregando...'
            )}
          </p>
        </div>

        <div className="flex gap-2">
          <button
            onClick={() => setShowImport(true)}
            className="px-3 py-2 text-sm font-medium text-zinc-700 hover:bg-zinc-100 border border-zinc-200 rounded inline-flex items-center gap-1.5"
          >
            <Upload className="h-4 w-4" />
            Importar
          </button>
          <Link
            href="/pessoas/novo"
            className="px-3 py-2 text-sm font-medium text-white bg-zinc-900 hover:bg-zinc-800 rounded inline-flex items-center gap-1.5"
          >
            <Plus className="h-4 w-4" />
            Nova ficha
          </Link>
        </div>
      </header>

      {/* Filtros */}
      <div className="flex flex-wrap gap-3 items-center">
        <div className="relative flex-1 min-w-[260px]">
          <Search className="h-4 w-4 absolute left-3 top-1/2 -translate-y-1/2 text-zinc-400 pointer-events-none" />
          <input
            type="text"
            value={search}
            onChange={(e) => setSearch(e.target.value)}
            placeholder="Buscar por nome, CPF ou matricula..."
            className="w-full pl-9 pr-3 py-2 text-sm border border-zinc-200 rounded focus:outline-none focus:ring-2 focus:ring-zinc-300"
          />
        </div>

        <div className="flex gap-1 items-center bg-zinc-100 rounded p-1">
          {(['all', 'active', 'terminated'] as const).map(s => (
            <button
              key={s}
              onClick={() => setStatus(s)}
              className={[
                'px-3 py-1.5 text-xs font-medium rounded transition',
                status === s
                  ? 'bg-white text-zinc-900 shadow-sm'
                  : 'text-zinc-600 hover:text-zinc-900',
              ].join(' ')}
            >
              {s === 'all' ? 'Todos' : s === 'active' ? 'Ativos' : 'Desligados'}
            </button>
          ))}
        </div>

        <input
          type="text"
          value={jobTitle}
          onChange={(e) => setJobTitle(e.target.value)}
          placeholder="Filtrar por cargo..."
          className="w-44 px-3 py-2 text-sm border border-zinc-200 rounded focus:outline-none focus:ring-2 focus:ring-zinc-300"
        />
      </div>

      {/* Lista */}
      {errorCode && (
        <div className="border border-red-200 bg-red-50 rounded-md p-4 text-red-900">
          <div className="flex gap-2 items-start">
            <AlertTriangle className="h-5 w-5 mt-0.5" />
            <div>
              <h3 className="font-semibold">Erro ao carregar pessoas</h3>
              <p className="text-sm mt-1 font-mono">{errorCode}</p>
            </div>
          </div>
        </div>
      )}

      {loading && items.length === 0 ? (
        <div className="flex items-center justify-center py-16">
          <Loader2 className="h-6 w-6 animate-spin text-zinc-400" />
        </div>
      ) : items.length === 0 ? (
        <div className="text-center py-16 text-zinc-500">
          <Users className="h-12 w-12 mx-auto mb-3 text-zinc-300" />
          <p className="text-sm">
            {search || status !== 'all' || jobTitle
              ? 'Nenhuma pessoa encontrada com esses filtros'
              : 'Nenhuma ficha cadastrada ainda. Importe um XLSX ou crie uma nova.'}
          </p>
        </div>
      ) : (
        <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4 gap-3">
          {items.map((p) => (
            <PersonCard key={p.id} person={p} />
          ))}
        </div>
      )}

      {hasMore && !loading && (
        <div className="flex justify-center pt-4">
          <button
            onClick={() => fetchPage(false)}
            className="px-4 py-2 text-sm font-medium text-zinc-700 hover:bg-zinc-100 border border-zinc-200 rounded"
          >
            Carregar mais ({total - items.length} restantes)
          </button>
        </div>
      )}

      {loading && items.length > 0 && (
        <div className="flex justify-center py-2">
          <Loader2 className="h-4 w-4 animate-spin text-zinc-400" />
        </div>
      )}

      {showImport && (
        <ImportDialog
          onClose={() => setShowImport(false)}
          onImported={() => {
            setShowImport(false)
            setOffset(0)
            fetchPage(true)
          }}
        />
      )}
    </div>
  )
}

// ============================================================================
// PersonCard
// ============================================================================

function PersonCard({ person }: { person: EmployeeListItem }) {
  const initials = useMemo(() => {
    return person.full_name
      .split(/\s+/)
      .filter(Boolean)
      .slice(0, 2)
      .map(w => w[0])
      .join('')
      .toUpperCase()
  }, [person.full_name])

  // Cor do avatar deterministica pelo id
  const avatarColor = useMemo(() => {
    const colors = ['#818cf8', '#f472b6', '#34d399', '#fb923c', '#60a5fa', '#a78bfa', '#fbbf24', '#22d3ee', '#f87171', '#4ade80']
    const hash = person.id.split('').reduce((s, c) => s + c.charCodeAt(0), 0)
    return colors[hash % colors.length]
  }, [person.id])

  return (
    <Link
      href={`/pessoas/${person.id}`}
      className="block bg-white border border-zinc-200 rounded-lg p-4 hover:border-zinc-300 hover:shadow-sm transition"
    >
      <div className="flex items-start gap-3">
        <div
          className="w-12 h-12 rounded-full flex items-center justify-center font-semibold text-white text-sm flex-shrink-0"
          style={{ background: avatarColor }}
        >
          {initials || '?'}
        </div>
        <div className="flex-1 min-w-0">
          <div className="flex items-start gap-2">
            <h3 className="font-medium text-zinc-900 text-sm leading-tight truncate flex-1">
              {person.full_name}
            </h3>
            {!person.is_active && (
              <span className="text-[10px] font-semibold uppercase tracking-wide px-1.5 py-0.5 rounded bg-red-100 text-red-700 flex-shrink-0">
                Desligado
              </span>
            )}
          </div>
          <p className="text-xs text-zinc-500 mt-1 truncate">{person.job_title}</p>
          <div className="flex items-center gap-2 mt-2 text-[11px] text-zinc-500">
            {person.matricula_esocial && (
              <span className="font-mono">#{person.matricula_esocial}</span>
            )}
            {person.employer_unit_name && (
              <>
                <span className="text-zinc-300">·</span>
                <span className="truncate">{person.employer_unit_name}</span>
              </>
            )}
          </div>
          {person.is_active ? (
            <div className="text-[10px] text-emerald-700 mt-1.5 flex items-center gap-1">
              <BadgeCheck className="h-3 w-3" />
              Ativo desde {formatDate(person.hire_date)}
            </div>
          ) : (
            <div className="text-[10px] text-red-700 mt-1.5 flex items-center gap-1">
              <BadgeX className="h-3 w-3" />
              Desligado em {formatDate(person.termination_date)}
            </div>
          )}
        </div>
      </div>
    </Link>
  )
}

function formatDate(iso: string | null): string {
  if (!iso) return ''
  const [y, m, d] = iso.split('-')
  return `${d}/${m}/${y}`
}

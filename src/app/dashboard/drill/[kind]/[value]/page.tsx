'use client'

/**
 * R2 People · /dashboard/drill/[kind]/[value] (Sessao F6)
 * ============================================================================
 * Pagina de drilldown · lista pessoas (ou PDIs) por trás de um agregado.
 *
 * Convencoes de URL:
 *   - ninebox · /dashboard/drill/ninebox/3-3       (row=3, col=3)
 *   - employer_unit · /dashboard/drill/employer_unit/<uuid>
 *   - department · /dashboard/drill/department/<uuid>
 *   - headcount_metric · /dashboard/drill/headcount_metric/total_active
 *   - pdis_by_manager · /dashboard/drill/pdis_by_manager/<uuid>
 *
 * Permissao: a RPC valida. Colaborador comum recebe permission_denied
 * e o componente mostra a tela 403 (mesmo padrao da F4).
 *
 * Layout: header com titulo + descricao do filtro, banner amber se
 * scope=hierarchy, tabela de resultados com link para cada ficha.
 * ============================================================================
 */

import { useEffect, useState, useCallback } from 'react'
import Link from 'next/link'
import { useParams, useSearchParams } from 'next/navigation'
import {
  TrendingUp, ChevronLeft, Loader2, AlertCircle, ExternalLink,
  Target, Calendar, Building2, Users, Filter,
} from 'lucide-react'

import {
  dashboardDrill, RpcError,
  type DrillKind, type DrillItem, type DrillResult,
} from '@/lib/r2'
import { isoDateToBr } from '@/lib/validation'

const VALID_KINDS: DrillKind[] = [
  'ninebox', 'employer_unit', 'department', 'headcount_metric', 'pdis_by_manager',
]

const KIND_LABELS: Record<DrillKind, string> = {
  ninebox: 'Caixa 9-Box',
  employer_unit: 'Unidade empregadora',
  department: 'Departamento',
  headcount_metric: 'Métrica de headcount',
  pdis_by_manager: 'PDIs em atraso por gestor',
}

const HEADCOUNT_LABELS: Record<string, string> = {
  total_active: 'Pessoas ativas',
  total_terminated: 'Pessoas desligadas',
  hired_30d: 'Contratadas nos últimos 30 dias',
  hired_90d: 'Contratadas nos últimos 90 dias',
  terminated_30d: 'Desligadas nos últimos 30 dias',
  terminated_90d: 'Desligadas nos últimos 90 dias',
}

const STANDARD_BOXES_3x3: ReadonlyArray<readonly string[]> = [
  ['Questionavel',       'Bom Profissional',     'Forte Desempenho'],
  ['Mantenedor',         'Mantenedor+',          'Alto Potencial'],
  ['Insuficiente',       'Eficaz',               'Future Star'],
]

// ============================================================================
// Page
// ============================================================================

export default function DrillPage() {
  const params = useParams<{ kind: string; value: string }>()
  const searchParams = useSearchParams()

  const kind = params.kind as DrillKind
  // value para ninebox vem como "row-col"; para demais e literal
  const rawValue = decodeURIComponent(params.value)

  const [data, setData] = useState<DrillResult | null>(null)
  const [loading, setLoading] = useState(true)
  const [forbidden, setForbidden] = useState(false)
  const [error, setError] = useState<string | null>(null)

  const fetchData = useCallback(async () => {
    if (!VALID_KINDS.includes(kind)) {
      setError(`unknown_kind: ${kind}`)
      setLoading(false)
      return
    }
    setLoading(true)
    setError(null)
    try {
      let result: DrillResult
      if (kind === 'ninebox') {
        const m = rawValue.match(/^(\d+)-(\d+)$/)
        if (!m) {
          setError('invalid_value: esperado formato "row-col"')
          setLoading(false)
          return
        }
        result = await dashboardDrill({
          kind: 'ninebox',
          valueInt1: parseInt(m[1], 10),
          valueInt2: parseInt(m[2], 10),
        })
      } else {
        result = await dashboardDrill({ kind, value: rawValue })
      }
      setData(result)
    } catch (err) {
      if (err instanceof RpcError && err.code === 'permission_denied') {
        setForbidden(true)
      } else {
        setError(err instanceof RpcError ? err.code : 'unknown_error')
      }
    } finally {
      setLoading(false)
    }
  }, [kind, rawValue])

  useEffect(() => { fetchData() }, [fetchData])

  // ==========================================================================
  // Render
  // ==========================================================================

  if (forbidden) return <Forbidden />

  if (loading) {
    return (
      <div className="flex items-center justify-center min-h-[60vh]">
        <Loader2 className="h-6 w-6 animate-spin text-zinc-400" />
      </div>
    )
  }

  if (error) {
    return (
      <div className="max-w-2xl mx-auto p-8">
        <Link href="/dashboard" className="text-sm text-zinc-600 hover:text-zinc-900 inline-flex items-center gap-1 mb-4">
          <ChevronLeft className="h-4 w-4" /> Dashboard
        </Link>
        <div className="border border-red-200 bg-red-50 rounded p-4 text-red-900">
          <strong>Erro:</strong> <code className="font-mono">{error}</code>
        </div>
      </div>
    )
  }

  if (!data) return null

  // Titulo descritivo conforme kind
  const description = describeFilter(kind, rawValue, data)
  const titleIcon = pickIcon(kind)

  // O nome do parametro do searchParams nao e usado aqui, mas mantemos
  // o objeto para nao deslogar futuras leituras (e silenciar lint sobre var nao usada)
  void searchParams

  return (
    <div className="max-w-5xl mx-auto p-6 space-y-4">
      <Link href="/dashboard" className="text-sm text-zinc-600 hover:text-zinc-900 inline-flex items-center gap-1">
        <ChevronLeft className="h-4 w-4" /> Dashboard
      </Link>

      <header className="border-b border-zinc-200 pb-4">
        <div className="flex items-start gap-3">
          {titleIcon}
          <div className="flex-1 min-w-0">
            <h1 className="text-xl font-semibold text-zinc-900">
              {KIND_LABELS[kind]}
            </h1>
            <p className="text-sm text-zinc-600 mt-0.5">{description}</p>
            <p className="text-xs text-zinc-500 mt-2">
              {data.count} resultado{data.count === 1 ? '' : 's'} · universo de {data.universe_size}
            </p>
          </div>
        </div>
      </header>

      {data.scope === 'hierarchy' && (
        <div className="border border-amber-200 bg-amber-50 rounded p-3 text-sm text-amber-900 flex items-start gap-2">
          <AlertCircle className="h-4 w-4 mt-0.5 flex-shrink-0" />
          <div>
            <strong>Escopo reduzido:</strong> resultados limitados à sua subárvore de liderança.
          </div>
        </div>
      )}

      {data.items.length === 0 ? (
        <div className="text-center py-12 border border-zinc-200 rounded">
          <Filter className="h-10 w-10 mx-auto mb-3 text-zinc-300" />
          <p className="text-sm text-zinc-500">Nenhum resultado para este filtro.</p>
        </div>
      ) : (
        <ResultsList kind={kind} items={data.items} />
      )}
    </div>
  )
}

// ============================================================================
// Helpers
// ============================================================================

function pickIcon(kind: DrillKind): React.ReactNode {
  const cls = 'h-8 w-8 text-zinc-600 flex-shrink-0'
  if (kind === 'pdis_by_manager') return <Target className={cls} />
  if (kind === 'employer_unit') return <Building2 className={cls} />
  if (kind === 'department') return <Building2 className={cls} />
  if (kind === 'headcount_metric') return <Users className={cls} />
  return <TrendingUp className={cls} />
}

function describeFilter(kind: DrillKind, rawValue: string, data: DrillResult): string {
  if (kind === 'ninebox') {
    const m = rawValue.match(/^(\d+)-(\d+)$/)
    if (m) {
      const r = parseInt(m[1], 10), c = parseInt(m[2], 10)
      if (r >= 1 && r <= 3 && c >= 1 && c <= 3) {
        return `Pessoas na caixa "${STANDARD_BOXES_3x3[r - 1][c - 1]}" (linha ${r}, coluna ${c}) da última avaliação 9-Box`
      }
    }
    return `Pessoas na caixa ${rawValue}`
  }
  if (kind === 'headcount_metric') {
    return HEADCOUNT_LABELS[rawValue] || rawValue
  }
  if (kind === 'employer_unit') {
    const first = data.items[0]
    return first?.unit_name ? `Pessoas em "${first.unit_name}"` : 'Pessoas na unidade selecionada'
  }
  if (kind === 'department') {
    const first = data.items[0]
    return first?.department_name ? `Pessoas em "${first.department_name}"` : 'Pessoas no departamento selecionado'
  }
  if (kind === 'pdis_by_manager') {
    return 'PDIs ativos com data de fim já vencida, sob este gestor'
  }
  return ''
}

// ============================================================================
// Lista de resultados
// ============================================================================

function ResultsList({ kind, items }: { kind: DrillKind; items: DrillItem[] }) {
  if (kind === 'pdis_by_manager') {
    return (
      <div className="space-y-2">
        {items.map(it => <PdiRow key={it.pdi_id} item={it} />)}
      </div>
    )
  }
  return (
    <div className="space-y-1">
      {items.map((it, idx) => <PersonRow key={(it.app_user_id ?? '') + idx} item={it} />)}
    </div>
  )
}

function PersonRow({ item }: { item: DrillItem }) {
  const content = (
    <div className="border border-zinc-200 rounded p-3 hover:bg-zinc-50 transition group">
      <div className="flex items-center gap-3 flex-wrap">
        <div className="flex-1 min-w-0">
          <div className="font-medium text-sm text-zinc-900 truncate">
            {item.full_name}
          </div>
          <div className="text-xs text-zinc-500 mt-0.5 flex gap-2 flex-wrap">
            {item.job_title && <span>{item.job_title}</span>}
            {item.unit_name && <span>· {item.unit_name}</span>}
            {item.department_name && <span>· {item.department_name}</span>}
          </div>
          {(item.hire_date || item.termination_date) && (
            <div className="text-[10px] text-zinc-500 mt-1 flex gap-2 flex-wrap">
              {item.hire_date && (
                <span className="inline-flex items-center gap-0.5">
                  <Calendar className="h-2.5 w-2.5" />
                  Contratado em {isoDateToBr(item.hire_date)}
                </span>
              )}
              {item.termination_date && (
                <span className="inline-flex items-center gap-0.5">
                  <Calendar className="h-2.5 w-2.5" />
                  Desligado em {isoDateToBr(item.termination_date)}
                </span>
              )}
            </div>
          )}
        </div>
        <span className="text-[10px] font-semibold uppercase tracking-wide px-2 py-0.5 rounded bg-zinc-100 text-zinc-700 flex-shrink-0">
          {item.chip_label}
        </span>
        {item.employee_id && (
          <ExternalLink className="h-3.5 w-3.5 text-zinc-300 group-hover:text-zinc-700 flex-shrink-0" />
        )}
      </div>
    </div>
  )
  if (item.employee_id) {
    return <Link href={`/pessoas/${item.employee_id}`} className="block">{content}</Link>
  }
  return content
}

function PdiRow({ item }: { item: DrillItem }) {
  const overdue = item.days_overdue ?? 0
  const overdueClass =
    overdue > 30 ? 'bg-red-100 text-red-700' :
    overdue > 7  ? 'bg-amber-100 text-amber-700' :
                   'bg-zinc-100 text-zinc-700'
  const content = (
    <div className="border border-zinc-200 rounded p-3 hover:bg-zinc-50 group">
      <div className="flex items-start gap-3 flex-wrap">
        <div className="flex-1 min-w-0">
          <div className="font-medium text-sm text-zinc-900 truncate">
            {item.full_name}
          </div>
          <div className="text-xs text-zinc-600 mt-0.5">
            {item.objective}
          </div>
          <div className="text-[10px] text-zinc-500 mt-1 flex gap-2 flex-wrap">
            {item.job_title && <span>{item.job_title}</span>}
            {item.unit_name && <span>· {item.unit_name}</span>}
            {item.end_date && (
              <span>· Fim previsto: {isoDateToBr(item.end_date)}</span>
            )}
            {item.actions_total != null && item.actions_total > 0 && (
              <span>· {item.actions_completed}/{item.actions_total} ações</span>
            )}
          </div>
        </div>
        <span className={`text-[10px] font-semibold px-2 py-0.5 rounded flex-shrink-0 ${overdueClass}`}>
          {item.chip_label}
        </span>
        {item.employee_id && (
          <ExternalLink className="h-3.5 w-3.5 text-zinc-300 group-hover:text-zinc-700 flex-shrink-0" />
        )}
      </div>
    </div>
  )
  if (item.employee_id) {
    return <Link href={`/pessoas/${item.employee_id}`} className="block">{content}</Link>
  }
  return content
}

// ============================================================================
// 403
// ============================================================================

function Forbidden() {
  return (
    <div className="max-w-md mx-auto p-12 text-center">
      <AlertCircle className="h-12 w-12 mx-auto mb-4 text-zinc-300" />
      <h1 className="text-xl font-semibold text-zinc-900 mb-2">Acesso restrito</h1>
      <p className="text-sm text-zinc-600 mb-4">
        Drilldowns do dashboard são visíveis apenas para RH, diretoria e líderes.
      </p>
      <Link href="/" className="text-sm text-zinc-700 hover:text-zinc-900 underline">
        Voltar para o início
      </Link>
    </div>
  )
}

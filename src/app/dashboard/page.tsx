'use client'

/**
 * R2 People · /dashboard (Sessao F4)
 * ============================================================================
 * Dashboard tenant-wide.
 *
 * Acesso:
 *   - super_admin / diretoria / rh  · scope=full
 *   - lider                          · scope=hierarchy (subarvore propria)
 *   - colaborador                    · permission_denied · UI mostra 403
 *
 * Layout: header + 4 secoes:
 *   1. Headcount (KPIs grandes + cards por unidade/depto)
 *   2. Distribuicao 9-Box (grade)
 *   3. PDIs atrasados por gestor (tabela)
 *   4. Ranking de reconhecimentos (2 colunas)
 *
 * Banner amber se scope=hierarchy para indicar escopo reduzido.
 * ============================================================================
 */

import { useEffect, useState, useCallback } from 'react'
import Link from 'next/link'
import {
  TrendingUp, Target, Award, Users, Building2, Briefcase,
  Loader2, AlertCircle, ChevronLeft, ChevronRight, UserPlus, UserMinus,
  ArrowDownRight, ArrowUpRight, Clock, Lock,
} from 'lucide-react'

import {
  tenantDashboard, RpcError,
  type TenantDashboardResult, type TenantHeadcount,
  type NineboxBucket, type PdiOverdueByManager, type RecognitionRanking,
} from '@/lib/r2'

// ============================================================================
// 3x3 padrao GE-McKinsey (mesma logica usada na F3)
// row/col 1-3 ja vem como inteiros do backend
// ============================================================================

const STANDARD_BOXES_3x3: ReadonlyArray<readonly string[]> = [
  ['Questionavel',       'Bom Profissional',     'Forte Desempenho'],
  ['Mantenedor',         'Mantenedor+',          'Alto Potencial'],
  ['Insuficiente',       'Eficaz',               'Future Star'],
]

const BOX_COLOR_3x3: ReadonlyArray<readonly string[]> = [
  ['bg-red-100 text-red-900',     'bg-amber-100 text-amber-900', 'bg-emerald-100 text-emerald-900'],
  ['bg-amber-100 text-amber-900', 'bg-amber-100 text-amber-900', 'bg-emerald-100 text-emerald-900'],
  ['bg-red-100 text-red-900',     'bg-amber-100 text-amber-900', 'bg-emerald-200 text-emerald-900'],
]

// ============================================================================
// Page
// ============================================================================

export default function DashboardPage() {
  const [data, setData] = useState<TenantDashboardResult | null>(null)
  const [loading, setLoading] = useState(true)
  const [forbidden, setForbidden] = useState(false)
  const [error, setError] = useState<string | null>(null)

  const fetchData = useCallback(async () => {
    setLoading(true)
    setError(null)
    try {
      const r = await tenantDashboard()
      setData(r)
    } catch (err) {
      if (err instanceof RpcError && err.code === 'permission_denied') {
        setForbidden(true)
      } else {
        setError(err instanceof RpcError ? err.code : 'unknown_error')
      }
    } finally {
      setLoading(false)
    }
  }, [])

  useEffect(() => { fetchData() }, [fetchData])

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
        <div className="border border-red-200 bg-red-50 rounded p-4 text-red-900">
          <strong>Erro:</strong> <code className="font-mono">{error}</code>
        </div>
      </div>
    )
  }

  if (!data) return null

  return (
    <div className="max-w-7xl mx-auto p-6 space-y-5">
      <Link href="/" className="text-sm text-zinc-600 hover:text-zinc-900 inline-flex items-center gap-1">
        <ChevronLeft className="h-4 w-4" /> Início
      </Link>

      <header className="border-b border-zinc-200 pb-4">
        <h1 className="text-2xl font-semibold text-zinc-900 inline-flex items-center gap-2">
          <TrendingUp className="h-6 w-6 text-zinc-600" />
          Dashboard
        </h1>
        <p className="text-sm text-zinc-500 mt-1">
          {data.scope === 'full'
            ? `Visão de toda a empresa · ${data.universe_size} pessoas`
            : `Visão da sua cadeia de liderança · ${data.universe_size} pessoa${data.universe_size === 1 ? '' : 's'}`}
        </p>
      </header>

      {data.scope === 'hierarchy' && (
        <div className="border border-amber-200 bg-amber-50 rounded p-3 text-sm text-amber-900 flex items-start gap-2">
          <AlertCircle className="h-4 w-4 mt-0.5 flex-shrink-0" />
          <div>
            <strong>Escopo reduzido:</strong> você está vendo apenas a sua subárvore de liderança.
            RH e diretoria têm visão completa do tenant.
          </div>
        </div>
      )}

      {/* Headcount */}
      <HeadcountSection h={data.headcount} />

      {/* Resto · 3 cards lado a lado */}
      <div className="grid grid-cols-1 lg:grid-cols-3 gap-3">
        <DashboardCard title="Distribuição 9-Box" icon={TrendingUp}>
          <NineboxGrid buckets={data.ninebox_distribution} />
        </DashboardCard>

        <DashboardCard
          title={`PDIs atrasados por gestor (${data.pdis_overdue_by_manager.length})`}
          icon={Target}
          highlight={data.pdis_overdue_by_manager.length > 0 ? 'red' : null}
        >
          <PdisOverdueByManager items={data.pdis_overdue_by_manager} />
        </DashboardCard>

        <DashboardCard title="Reconhecimentos (90d)" icon={Award}>
          <RecognitionsRanking
            recipients={data.recognition_top_recipients}
            senders={data.recognition_top_senders}
          />
        </DashboardCard>
      </div>
    </div>
  )
}

// ============================================================================
// Headcount
// ============================================================================

function HeadcountSection({ h }: { h: TenantHeadcount }) {
  return (
    <section>
      <h2 className="text-xs font-semibold uppercase tracking-wider text-zinc-500 mb-2 flex items-center gap-1.5">
        <Users className="h-3.5 w-3.5" /> Headcount
      </h2>

      {/* KPIs grandes */}
      <div className="grid grid-cols-2 md:grid-cols-4 gap-3 mb-3">
        <BigKpi
          icon={Users}
          label="Ativos"
          value={h.total_active}
          color="emerald"
          metric="total_active"
        />
        <BigKpi
          icon={UserPlus}
          label="Contratados 30d"
          value={h.hired_30d}
          subtitle={`${h.hired_90d} em 90d`}
          color="blue"
          metric="hired_30d"
        />
        <BigKpi
          icon={UserMinus}
          label="Desligados 30d"
          value={h.terminated_30d}
          subtitle={`${h.terminated_90d} em 90d`}
          color={h.terminated_30d > 0 ? 'red' : 'zinc'}
          metric="terminated_30d"
        />
        <BigKpi
          icon={Briefcase}
          label="Total desligados"
          value={h.total_terminated}
          color="zinc"
          metric="total_terminated"
        />
      </div>

      {/* Distribuicao por unidade/depto · clicaveis */}
      {(h.by_employer_unit.length > 0 || h.by_department.length > 0) && (
        <div className="grid grid-cols-1 md:grid-cols-2 gap-3">
          {h.by_employer_unit.length > 0 && (
            <DashboardCard title="Por unidade empregadora" icon={Building2}>
              <UnitBars
                items={h.by_employer_unit.map(u => ({
                  id: u.unit_id, name: u.unit_name, count: u.count,
                }))}
                total={h.total_active}
                drillKind="employer_unit"
              />
            </DashboardCard>
          )}
          {h.by_department.length > 0 && (
            <DashboardCard title="Por departamento" icon={Briefcase}>
              <UnitBars
                items={h.by_department.map(d => ({
                  id: d.department_id, name: d.department_name, count: d.count,
                }))}
                total={h.total_active}
                drillKind="department"
              />
            </DashboardCard>
          )}
        </div>
      )}
    </section>
  )
}

function BigKpi({
  icon: Icon, label, value, subtitle, color, metric,
}: {
  icon: React.ComponentType<{ className?: string }>
  label: string
  value: number
  subtitle?: string
  color: 'emerald' | 'blue' | 'red' | 'zinc'
  metric?: string  // se presente e value > 0, vira link de drilldown
}) {
  const cls = {
    emerald: 'bg-emerald-50 border-emerald-200 text-emerald-900',
    blue:    'bg-blue-50 border-blue-200 text-blue-900',
    red:     'bg-red-50 border-red-200 text-red-900',
    zinc:    'bg-white border-zinc-200 text-zinc-900',
  }[color]

  const inner = (
    <div className={`border rounded-lg p-4 ${cls} ${metric && value > 0 ? 'cursor-pointer hover:shadow-sm transition' : ''}`}>
      <div className="flex items-center gap-2 mb-1">
        <Icon className="h-4 w-4 opacity-70" />
        <span className="text-xs font-semibold uppercase tracking-wider opacity-70">
          {label}
        </span>
      </div>
      <div className="text-3xl font-semibold">{value}</div>
      {subtitle && <div className="text-xs opacity-70 mt-0.5">{subtitle}</div>}
    </div>
  )
  if (metric && value > 0) {
    return <Link href={`/dashboard/drill/headcount_metric/${metric}`}>{inner}</Link>
  }
  return inner
}

function UnitBars({
  items, total, drillKind,
}: {
  items: Array<{ id: string; name: string | null; count: number }>
  total: number
  drillKind: 'employer_unit' | 'department'
}) {
  const max = items.reduce((m, i) => Math.max(m, i.count), 0)

  return (
    <div className="space-y-1.5">
      {items.map(it => {
        const pct = max > 0 ? (it.count / max) * 100 : 0
        const totalPct = total > 0 ? Math.round((it.count / total) * 100) : 0
        const row = (
          <div className="flex items-center gap-2 hover:bg-zinc-50 px-1 -mx-1 rounded transition cursor-pointer">
            <span className="text-xs text-zinc-700 truncate flex-shrink-0 w-32">
              {it.name || '-'}
            </span>
            <div className="flex-1 h-4 bg-zinc-100 rounded overflow-hidden relative">
              <div
                className="h-full bg-zinc-600 transition-all"
                style={{ width: `${pct}%` }}
              />
            </div>
            <span className="text-xs font-medium text-zinc-900 w-16 text-right flex-shrink-0">
              {it.count} ({totalPct}%)
            </span>
          </div>
        )
        return (
          <Link key={it.id} href={`/dashboard/drill/${drillKind}/${it.id}`}>
            {row}
          </Link>
        )
      })}
    </div>
  )
}

// ============================================================================
// 9-Box (versao tenant)
// ============================================================================

function NineboxGrid({ buckets }: { buckets: NineboxBucket[] }) {
  // Builda grid 3x3 com count = 0 default
  const grid: number[][] = [[0, 0, 0], [0, 0, 0], [0, 0, 0]]
  let total = 0
  for (const b of buckets) {
    if (b.box_row && b.box_col && b.box_row >= 1 && b.box_row <= 3 && b.box_col >= 1 && b.box_col <= 3) {
      grid[b.box_row - 1][b.box_col - 1] += b.count
      total += b.count
    }
  }

  if (total === 0) {
    return (
      <div className="text-center py-6">
        <AlertCircle className="h-8 w-8 mx-auto mb-2 text-zinc-300" />
        <p className="text-xs text-zinc-500">
          Nenhuma avaliação 9-Box finalizada.
        </p>
      </div>
    )
  }

  return (
    <>
      <div className="grid grid-cols-3 gap-1 text-center text-xs">
        {[2, 1, 0].map(r =>
          [0, 1, 2].map(c => {
            const count = grid[r][c]
            const label = STANDARD_BOXES_3x3[r][c]
            // row/col 1-indexed para a RPC
            const rowCol = `${r + 1}-${c + 1}`
            const cellContent = (
              <div
                className={`px-1 py-2 rounded ${count > 0 ? BOX_COLOR_3x3[r][c] : 'bg-zinc-50 text-zinc-400'} ${count > 0 ? 'cursor-pointer hover:opacity-80 transition' : ''}`}
                title={label}
              >
                <div className="font-bold text-base">{count}</div>
                <div className="text-[9px] uppercase tracking-tight truncate" title={label}>
                  {label}
                </div>
              </div>
            )
            if (count > 0) {
              return (
                <Link key={`${r}-${c}`} href={`/dashboard/drill/ninebox/${rowCol}`}>
                  {cellContent}
                </Link>
              )
            }
            return <div key={`${r}-${c}`}>{cellContent}</div>
          }),
        )}
      </div>
      <div className="mt-3 pt-3 border-t border-zinc-100 text-[10px] text-zinc-500 flex justify-between">
        <span>{total} pessoa{total === 1 ? '' : 's'} avaliada{total === 1 ? '' : 's'}</span>
        <span>Vert: Potencial · Horiz: Desempenho</span>
      </div>
    </>
  )
}

// ============================================================================
// PDIs por gestor
// ============================================================================

function PdisOverdueByManager({ items }: { items: PdiOverdueByManager[] }) {
  if (items.length === 0) {
    return (
      <div className="text-center py-6">
        <Target className="h-8 w-8 mx-auto mb-2 text-emerald-300" />
        <p className="text-xs text-zinc-500">
          Nenhum gestor com PDIs em atraso.
        </p>
      </div>
    )
  }

  return (
    <div className="space-y-2 max-h-72 overflow-y-auto">
      {items.map(m => {
        const content = (
          <div className="border border-zinc-100 rounded p-2 hover:bg-zinc-50 transition cursor-pointer">
            <div className="flex items-center gap-2 flex-wrap">
              <span className="text-sm font-medium text-zinc-900 truncate flex-1">
                {m.manager_name || '(sem gestor definido)'}
              </span>
              <span className={`text-[10px] font-semibold px-1.5 py-0.5 rounded inline-flex items-center gap-0.5 ${
                m.overdue_count >= 5 ? 'bg-red-100 text-red-700'
                : m.overdue_count >= 2 ? 'bg-amber-100 text-amber-700'
                : 'bg-zinc-100 text-zinc-700'
              }`}>
                {m.overdue_count} {m.overdue_count === 1 ? 'PDI' : 'PDIs'}
              </span>
            </div>
            <div className="text-[10px] text-zinc-500 mt-0.5 flex items-center gap-1">
              <Clock className="h-2.5 w-2.5" />
              Pior: {m.worst_overdue_days} dias de atraso
              {m.manager_email && <span className="ml-auto truncate">{m.manager_email}</span>}
            </div>
          </div>
        )
        if (m.manager_id) {
          return (
            <Link key={m.manager_id} href={`/dashboard/drill/pdis_by_manager/${m.manager_id}`}>
              {content}
            </Link>
          )
        }
        return <div key="no-mgr">{content}</div>
      })}
    </div>
  )
}

// ============================================================================
// Reconhecimentos (mesmo padrao da F3)
// ============================================================================

function RecognitionsRanking({
  recipients, senders,
}: {
  recipients: RecognitionRanking[]
  senders: RecognitionRanking[]
}) {
  if (recipients.length === 0 && senders.length === 0) {
    return (
      <div className="text-center py-6">
        <Award className="h-8 w-8 mx-auto mb-2 text-zinc-300" />
        <p className="text-xs text-zinc-500">
          Nenhum reconhecimento nos últimos 90 dias.
        </p>
      </div>
    )
  }

  return (
    <div className="space-y-3">
      <RankingColumn
        title="Mais reconhecidos"
        icon={ArrowDownRight}
        items={recipients}
        showPrivate
      />
      {senders.length > 0 && (
        <RankingColumn
          title="Mais reconheceram"
          icon={ArrowUpRight}
          items={senders}
        />
      )}
    </div>
  )
}

function RankingColumn({
  title, icon: Icon, items, showPrivate,
}: {
  title: string
  icon: React.ComponentType<{ className?: string }>
  items: RecognitionRanking[]
  showPrivate?: boolean
}) {
  if (items.length === 0) return null
  return (
    <div>
      <h4 className="text-[10px] font-semibold uppercase tracking-wider text-zinc-500 flex items-center gap-1 mb-1.5">
        <Icon className="h-3 w-3" /> {title}
      </h4>
      <div className="space-y-1">
        {items.slice(0, 5).map((it, idx) => (
          <RankingRow key={it.user_id} item={it} rank={idx + 1} showPrivate={showPrivate} />
        ))}
      </div>
    </div>
  )
}

function RankingRow({
  item, rank, showPrivate,
}: {
  item: RecognitionRanking
  rank: number
  showPrivate?: boolean
}) {
  const content = (
    <div className="flex items-center gap-2 px-2 py-1.5 rounded hover:bg-zinc-50 group">
      <span className="text-[10px] font-semibold text-zinc-400 w-3 text-center">{rank}</span>
      <span className="text-sm text-zinc-900 truncate flex-1">{item.user_name}</span>
      {showPrivate && item.private_count != null && item.private_count > 0 && (
        <span className="text-[9px] text-zinc-500 inline-flex items-center gap-0.5" title={`${item.private_count} privados`}>
          <Lock className="h-2.5 w-2.5" />
          {item.private_count}
        </span>
      )}
      <span className="text-sm font-medium text-zinc-900">{item.total}</span>
      {item.employee_id && (
        <ChevronRight className="h-3 w-3 text-zinc-300 group-hover:text-zinc-700 flex-shrink-0" />
      )}
    </div>
  )

  if (item.employee_id) {
    return <Link href={`/pessoas/${item.employee_id}`} className="block">{content}</Link>
  }
  return <div>{content}</div>
}

// ============================================================================
// Card wrapper
// ============================================================================

function DashboardCard({
  title, icon: Icon, highlight, children,
}: {
  title: string
  icon: React.ComponentType<{ className?: string }>
  highlight?: 'red' | null
  children: React.ReactNode
}) {
  return (
    <div className={`bg-white border rounded-lg p-4 ${
      highlight === 'red' ? 'border-red-200' : 'border-zinc-200'
    }`}>
      <h3 className="text-xs font-semibold uppercase tracking-wider text-zinc-500 flex items-center gap-1.5 mb-3 pb-2 border-b border-zinc-100">
        <Icon className="h-3.5 w-3.5" />
        {title}
      </h3>
      {children}
    </div>
  )
}

// ============================================================================
// Forbidden
// ============================================================================

function Forbidden() {
  return (
    <div className="max-w-md mx-auto p-12 text-center">
      <AlertCircle className="h-12 w-12 mx-auto mb-4 text-zinc-300" />
      <h1 className="text-xl font-semibold text-zinc-900 mb-2">Acesso restrito</h1>
      <p className="text-sm text-zinc-600 mb-4">
        O dashboard corporativo é visível apenas para RH, diretoria e líderes.
      </p>
      <Link href="/" className="text-sm text-zinc-700 hover:text-zinc-900 underline">
        Voltar para o início
      </Link>
    </div>
  )
}

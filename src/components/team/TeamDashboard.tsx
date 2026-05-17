'use client'

/**
 * R2 People · TeamDashboard (Sessao F3)
 * ============================================================================
 * Painel agregado para /minha-equipe com 3 widgets:
 *
 *   1. Distribuicao 9-Box · grade 3x3 contando subordinados por caixa
 *      (calculada a partir do array team retornado por myTeam())
 *
 *   2. PDIs em atraso · lista ordenada pelo mais antigo, com chip de dias
 *      vencidos e progresso de acoes
 *
 *   3. Ranking de reconhecimentos · 2 colunas (top recipients + top senders)
 *
 * Props:
 *   team: TeamMember[]   (vem de rpc_my_team)
 *   dashboard: MyTeamDashboardResult | null  (vem de rpc_my_team_dashboard)
 *   loading: boolean
 *
 * Layout: 3 cards lado a lado em desktop, empilhados em mobile.
 * ============================================================================
 */

import { useMemo } from 'react'
import Link from 'next/link'
import {
  TrendingUp, Target, Award, Loader2, AlertCircle,
  ChevronRight, Clock, ArrowUpRight, ArrowDownRight,
} from 'lucide-react'

import type {
  TeamMember, MyTeamDashboardResult, PdiOverdueItem, RecognitionRanking,
} from '@/lib/r2'

interface TeamDashboardProps {
  team: TeamMember[]
  dashboard: MyTeamDashboardResult | null
  loading: boolean
}

// ============================================================================
// Mapeamento 3x3 dos labels GE-McKinsey (padrao Ninebox)
// ============================================================================

// Os labels reais vem dos snapshots por avaliacao; aqui usamos um mapa
// padrao para quando final_box_label estiver presente como uma das 9 caixas.
const STANDARD_BOXES_3x3 = [
  ['Questionavel',       'Bom Profissional',     'Forte Desempenho'],
  ['Mantenedor',         'Mantenedor+',          'Alto Potencial'],
  ['Insuficiente',       'Eficaz',               'Future Star'],
]

const BOX_COLOR_3x3 = [
  ['bg-red-100 text-red-900',     'bg-amber-100 text-amber-900', 'bg-emerald-100 text-emerald-900'],
  ['bg-amber-100 text-amber-900', 'bg-amber-100 text-amber-900', 'bg-emerald-100 text-emerald-900'],
  ['bg-red-100 text-red-900',     'bg-amber-100 text-amber-900', 'bg-emerald-200 text-emerald-900'],
]

// ============================================================================
// Component
// ============================================================================

export function TeamDashboard({ team, dashboard, loading }: TeamDashboardProps) {
  // Conta distribuicao 9-Box a partir do team
  const ninebox = useMemo(() => buildNineboxGrid(team), [team])
  const totalEvaluated = useMemo(
    () => team.filter(m => m.last_evaluation_box).length,
    [team],
  )

  if (loading && !dashboard) {
    return (
      <div className="bg-white border border-zinc-200 rounded-lg p-8 text-center">
        <Loader2 className="h-5 w-5 animate-spin text-zinc-400 mx-auto" />
      </div>
    )
  }

  if (!dashboard) return null

  return (
    <div className="grid grid-cols-1 lg:grid-cols-3 gap-3">
      {/* 1. Distribuicao 9-Box */}
      <DashboardCard title="Distribuição 9-Box" icon={TrendingUp}>
        <NineboxGrid grid={ninebox} totalEvaluated={totalEvaluated} teamSize={team.length} />
      </DashboardCard>

      {/* 2. PDIs em atraso */}
      <DashboardCard
        title={`PDIs em atraso (${dashboard.pdis_overdue.length})`}
        icon={Target}
        highlight={dashboard.pdis_overdue.length > 0 ? 'red' : null}
      >
        <PdisOverdueList items={dashboard.pdis_overdue} />
      </DashboardCard>

      {/* 3. Ranking de reconhecimentos */}
      <DashboardCard title="Reconhecimentos (90d)" icon={Award}>
        <RecognitionsRanking
          recipients={dashboard.recognitions_top_recipients}
          senders={dashboard.recognitions_top_senders}
        />
      </DashboardCard>
    </div>
  )
}

// ============================================================================
// 9-Box helpers
// ============================================================================

interface NineboxCell {
  label: string
  count: number
  members: TeamMember[]
}

function buildNineboxGrid(team: TeamMember[]): NineboxCell[][] {
  // Inicializa grade 3x3 com labels padrao
  const grid: NineboxCell[][] = STANDARD_BOXES_3x3.map(row =>
    row.map(label => ({ label, count: 0, members: [] as TeamMember[] })),
  )

  // Distribui membros pelas caixas conforme last_evaluation_box (match por label string)
  // Como nao temos row/col na resposta de myTeam, usamos o label diretamente.
  for (const m of team) {
    if (!m.last_evaluation_box) continue
    let placed = false
    for (let r = 0; r < grid.length; r++) {
      for (let c = 0; c < grid[r].length; c++) {
        if (grid[r][c].label === m.last_evaluation_box) {
          grid[r][c].count++
          grid[r][c].members.push(m)
          placed = true
          break
        }
      }
      if (placed) break
    }
    // Se label nao corresponde a uma caixa padrao, cai na grade central (Mantenedor+)
    if (!placed) {
      grid[1][1].count++
      grid[1][1].members.push(m)
    }
  }

  return grid
}

function NineboxGrid({
  grid, totalEvaluated, teamSize,
}: {
  grid: NineboxCell[][]
  totalEvaluated: number
  teamSize: number
}) {
  if (totalEvaluated === 0) {
    return (
      <div className="text-center py-6">
        <AlertCircle className="h-8 w-8 mx-auto mb-2 text-zinc-300" />
        <p className="text-xs text-zinc-500">
          Nenhuma pessoa com avaliação 9-Box ainda.<br />
          {teamSize} {teamSize === 1 ? 'pessoa' : 'pessoas'} sem avaliação.
        </p>
      </div>
    )
  }

  return (
    <>
      {/* Grade · ordem visual: linha 2 (top), 1, 0 para potencial crescer pra cima */}
      <div className="grid grid-cols-3 gap-1 text-center text-xs">
        {[2, 1, 0].map(r =>
          grid[r].map((cell, c) => (
            <div
              key={`${r}-${c}`}
              className={`px-1 py-2 rounded ${cell.count > 0 ? BOX_COLOR_3x3[r][c] : 'bg-zinc-50 text-zinc-400'}`}
              title={cell.label}
            >
              <div className="font-bold text-base">{cell.count}</div>
              <div className="text-[9px] uppercase tracking-tight truncate" title={cell.label}>
                {cell.label}
              </div>
            </div>
          )),
        )}
      </div>

      {/* Rodape · contadores */}
      <div className="mt-3 pt-3 border-t border-zinc-100 text-[10px] text-zinc-500 flex justify-between">
        <span>{totalEvaluated}/{teamSize} avaliadas</span>
        <span>Eixo vertical: Potencial · horizontal: Desempenho</span>
      </div>
    </>
  )
}

// ============================================================================
// PDIs em atraso
// ============================================================================

function PdisOverdueList({ items }: { items: PdiOverdueItem[] }) {
  if (items.length === 0) {
    return (
      <div className="text-center py-6">
        <Target className="h-8 w-8 mx-auto mb-2 text-emerald-300" />
        <p className="text-xs text-zinc-500">
          Nenhum PDI em atraso. Bom trabalho!
        </p>
      </div>
    )
  }

  return (
    <div className="space-y-2 max-h-72 overflow-y-auto">
      {items.slice(0, 10).map(p => (
        <PdiRow key={p.pdi_id} pdi={p} />
      ))}
      {items.length > 10 && (
        <p className="text-[10px] text-zinc-500 text-center pt-2">
          ... mais {items.length - 10}
        </p>
      )}
    </div>
  )
}

function PdiRow({ pdi }: { pdi: PdiOverdueItem }) {
  const overdueClass =
    pdi.days_overdue > 30 ? 'text-red-700 bg-red-100' :
    pdi.days_overdue > 7  ? 'text-amber-700 bg-amber-100' :
                            'text-zinc-700 bg-zinc-100'

  const content = (
    <div className="border border-zinc-100 rounded p-2 hover:bg-zinc-50 transition group">
      <div className="flex items-center gap-2 flex-wrap">
        <span className="text-sm font-medium text-zinc-900 truncate flex-1">
          {pdi.user_name}
        </span>
        <span className={`text-[10px] font-semibold px-1.5 py-0.5 rounded inline-flex items-center gap-0.5 ${overdueClass}`}>
          <Clock className="h-2.5 w-2.5" />
          {pdi.days_overdue}d
        </span>
      </div>
      <p className="text-xs text-zinc-500 truncate mt-0.5" title={pdi.objective}>
        {pdi.objective}
      </p>
      {pdi.actions_total > 0 && (
        <div className="mt-1.5 flex items-center gap-2">
          <div className="flex-1 h-1 bg-zinc-100 rounded-full overflow-hidden">
            <div
              className="h-full bg-zinc-600"
              style={{ width: `${pdi.progress_pct}%` }}
            />
          </div>
          <span className="text-[10px] text-zinc-500 flex-shrink-0">
            {pdi.actions_completed}/{pdi.actions_total}
          </span>
        </div>
      )}
    </div>
  )

  if (pdi.employee_id) {
    return <Link href={`/pessoas/${pdi.employee_id}`} className="block">{content}</Link>
  }
  return <div>{content}</div>
}

// ============================================================================
// Ranking de reconhecimentos
// ============================================================================

function RecognitionsRanking({
  recipients, senders,
}: {
  recipients: RecognitionRanking[]
  senders: RecognitionRanking[]
}) {
  const hasData = recipients.length > 0 || senders.length > 0

  if (!hasData) {
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
        <Icon className="h-3 w-3" />
        {title}
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
      <span className="text-[10px] font-semibold text-zinc-400 w-3 text-center">
        {rank}
      </span>
      <span className="text-sm text-zinc-900 truncate flex-1">
        {item.user_name}
      </span>
      {showPrivate && item.private_count != null && item.private_count > 0 && (
        <span className="text-[9px] text-zinc-500" title={`${item.private_count} privados`}>
          🔒{item.private_count}
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

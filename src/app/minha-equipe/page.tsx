'use client'

/**
 * R2 People · /minha-equipe (Sessao F1)
 * ============================================================================
 * Lista de pessoas que reportam ao usuario logado.
 *
 * Inclui:
 *   - Toggle "incluir indiretos" (subordinados de subordinados, ate 10 niveis)
 *   - Card por pessoa com avatar, nome, cargo, KPIs:
 *       - PDIs ativos
 *       - Caixa da ultima avaliacao 9-Box
 *       - Reconhecimentos nos ultimos 30d
 *       - Onboarding em andamento
 *   - Click no card abre /pessoas/[id] (ja com GestaoSections visiveis)
 *
 * Empty state: gestor sem subordinados ve mensagem explicativa.
 * ============================================================================
 */

import { useEffect, useState, useCallback } from 'react'
import Link from 'next/link'
import {
  Users, Loader2, AlertCircle, ChevronLeft, ChevronRight,
  Target, TrendingUp, Award, Compass, Layers,
} from 'lucide-react'

import { myTeam, myTeamDashboard, RpcError, type TeamMember, type MyTeamDashboardResult } from '@/lib/r2'
import { TeamDashboard } from '@/components/team/TeamDashboard'

// ============================================================================
// Page
// ============================================================================

export default function MinhaEquipePage() {
  const [team, setTeam] = useState<TeamMember[]>([])
  const [dashboard, setDashboard] = useState<MyTeamDashboardResult | null>(null)
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)
  const [includeIndirect, setIncludeIndirect] = useState(false)

  const fetchTeam = useCallback(async () => {
    setLoading(true)
    setError(null)
    try {
      // Carrega em paralelo: lista de pessoas + dashboard agregado
      const [teamR, dashR] = await Promise.all([
        myTeam(includeIndirect),
        myTeamDashboard(includeIndirect),
      ])
      setTeam(teamR.team)
      setDashboard(dashR)
    } catch (err) {
      setError(err instanceof RpcError ? err.code : 'unknown_error')
    } finally {
      setLoading(false)
    }
  }, [includeIndirect])

  useEffect(() => { fetchTeam() }, [fetchTeam])

  const directCount = team.filter(m => m.is_direct_report).length
  const indirectCount = team.length - directCount

  return (
    <div className="max-w-6xl mx-auto p-6 space-y-4">
      <Link href="/" className="text-sm text-zinc-600 hover:text-zinc-900 inline-flex items-center gap-1">
        <ChevronLeft className="h-4 w-4" /> Início
      </Link>

      <header className="border-b border-zinc-200 pb-4">
        <h1 className="text-2xl font-semibold text-zinc-900 inline-flex items-center gap-2">
          <Users className="h-6 w-6 text-zinc-600" />
          Minha equipe
        </h1>
        <p className="text-sm text-zinc-500 mt-1">
          Pessoas que reportam diretamente a você
          {includeIndirect && ' (incluindo subordinados indiretos)'}.
        </p>
      </header>

      {/* Toggle indiretos */}
      <div className="flex items-center justify-between flex-wrap gap-2">
        <div className="text-sm text-zinc-600">
          {loading ? '...' : (
            <span>
              {directCount} direto{directCount === 1 ? '' : 's'}
              {includeIndirect && indirectCount > 0 && (
                <span className="text-zinc-500"> · {indirectCount} indireto{indirectCount === 1 ? '' : 's'}</span>
              )}
            </span>
          )}
        </div>
        <label className="inline-flex items-center gap-2 text-sm text-zinc-700 cursor-pointer">
          <input
            type="checkbox"
            checked={includeIndirect}
            onChange={(e) => setIncludeIndirect(e.target.checked)}
            className="rounded border-zinc-300"
          />
          Incluir subordinados indiretos
        </label>
      </div>

      {error && (
        <div className="border border-red-200 bg-red-50 rounded p-3 text-sm text-red-900 flex items-center gap-2">
          <AlertCircle className="h-4 w-4" />
          Erro: <code className="font-mono">{error}</code>
        </div>
      )}

      {loading ? (
        <div className="flex justify-center py-12">
          <Loader2 className="h-6 w-6 animate-spin text-zinc-400" />
        </div>
      ) : team.length === 0 ? (
        <EmptyState />
      ) : (
        <>
          {/* F3 · Dashboard agregado da equipe */}
          <TeamDashboard team={team} dashboard={dashboard} loading={loading} />

          {/* Lista de cards · cada pessoa */}
          <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-3 mt-4">
            {team.map(m => <MemberCard key={m.id} member={m} />)}
          </div>
        </>
      )}
    </div>
  )
}

// ============================================================================
// MemberCard
// ============================================================================

function MemberCard({ member }: { member: TeamMember }) {
  const displayName = member.full_name || member.app_user_name
  const initials = getInitials(displayName)
  const colorClass = getColorClass(displayName)

  const card = (
    <div className="bg-white border border-zinc-200 rounded-lg p-4 hover:shadow-md hover:border-zinc-300 transition group h-full">
      <div className="flex items-start gap-3">
        <div className={`w-10 h-10 rounded-full flex items-center justify-center text-white font-semibold text-sm flex-shrink-0 ${colorClass}`}>
          {initials}
        </div>
        <div className="flex-1 min-w-0">
          <div className="flex items-center gap-1.5 flex-wrap">
            <h3 className="font-medium text-sm text-zinc-900 truncate">{displayName}</h3>
            {!member.is_direct_report && (
              <span className="text-[10px] font-semibold uppercase tracking-wide px-1 py-0.5 rounded bg-zinc-100 text-zinc-600 inline-flex items-center gap-0.5">
                <Layers className="h-2.5 w-2.5" />
                nível {member.depth}
              </span>
            )}
            {!member.is_active && (
              <span className="text-[10px] font-semibold uppercase tracking-wide px-1 py-0.5 rounded bg-red-100 text-red-700">
                Inativo
              </span>
            )}
          </div>
          <p className="text-xs text-zinc-500 truncate mt-0.5">
            {member.job_title || '-'}
          </p>
          {member.working_unit_name && (
            <p className="text-xs text-zinc-400 truncate">{member.working_unit_name}</p>
          )}
        </div>
        <ChevronRight className="h-4 w-4 text-zinc-300 group-hover:text-zinc-700 flex-shrink-0" />
      </div>

      {/* KPIs */}
      <div className="mt-3 pt-3 border-t border-zinc-100 grid grid-cols-2 gap-2 text-xs">
        <Kpi
          icon={Target}
          label="PDIs ativos"
          value={member.pdis_active}
          highlight={member.pdis_active > 0 ? 'blue' : null}
        />
        <Kpi
          icon={TrendingUp}
          label="Última caixa"
          value={member.last_evaluation_box || '-'}
          highlight={member.last_evaluation_box ? 'emerald' : null}
        />
        <Kpi
          icon={Award}
          label="Reconhec. 30d"
          value={member.recognitions_30d}
          highlight={member.recognitions_30d > 0 ? 'amber' : null}
        />
        <Kpi
          icon={Compass}
          label="Onboarding"
          value={member.onboarding_active ? 'Em curso' : '-'}
          highlight={member.onboarding_active ? 'blue' : null}
        />
      </div>
    </div>
  )

  if (member.employee_id) {
    return <Link href={`/pessoas/${member.employee_id}`} className="block">{card}</Link>
  }
  // Sem ficha vinculada · card nao clicavel
  return <div className="opacity-70 cursor-not-allowed">{card}</div>
}

function Kpi({
  icon: Icon, label, value, highlight,
}: {
  icon: React.ComponentType<{ className?: string }>
  label: string
  value: string | number
  highlight: 'blue' | 'emerald' | 'amber' | null
}) {
  const valCls = highlight
    ? { blue: 'text-blue-700', emerald: 'text-emerald-700', amber: 'text-amber-700' }[highlight]
    : 'text-zinc-400'

  return (
    <div className="flex items-center gap-1.5 min-w-0">
      <Icon className="h-3 w-3 text-zinc-400 flex-shrink-0" />
      <div className="min-w-0 flex-1">
        <div className="text-[10px] uppercase tracking-wider text-zinc-500 truncate">{label}</div>
        <div className={`text-xs font-medium truncate ${valCls}`}>{value}</div>
      </div>
    </div>
  )
}

// ============================================================================
// Empty state
// ============================================================================

function EmptyState() {
  return (
    <div className="text-center py-16 text-zinc-500 max-w-md mx-auto">
      <Users className="h-12 w-12 mx-auto mb-3 text-zinc-300" />
      <h2 className="text-sm font-semibold text-zinc-700 mb-1">Nenhum subordinado direto</h2>
      <p className="text-sm">
        Você não tem pessoas que reportam diretamente a você no sistema.
        Se você é gestor mas não está vendo sua equipe, peça ao RH para conferir os vínculos
        de <code className="font-mono bg-zinc-100 px-1 rounded">manager_id</code> dos colaboradores.
      </p>
    </div>
  )
}

// ============================================================================
// Helpers
// ============================================================================

function getInitials(name: string): string {
  return name.split(/\s+/).filter(Boolean).slice(0, 2).map(w => w[0] || '').join('').toUpperCase()
}

function getColorClass(name: string): string {
  const colors = [
    'bg-emerald-600', 'bg-blue-600', 'bg-amber-600', 'bg-rose-600',
    'bg-violet-600', 'bg-cyan-600', 'bg-orange-600', 'bg-teal-600',
  ]
  let hash = 0
  for (let i = 0; i < name.length; i++) hash = (hash * 31 + name.charCodeAt(i)) | 0
  return colors[Math.abs(hash) % colors.length]
}

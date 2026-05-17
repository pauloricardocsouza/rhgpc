'use client'

/**
 * R2 People · GestaoSections (Sessao F1)
 * ============================================================================
 * 4 secoes colapsaveis adicionais para /pessoas/[id]:
 *   1. Historico de avaliacoes 9-Box
 *   2. PDIs
 *   3. Reconhecimentos
 *   4. Onboardings
 *
 * Carrega o resumo de gestao via Employees.gestaoSummary.
 * Se receber `permission_denied`, esconde completamente as secoes (silencioso).
 * Se receber `has_app_user=false`, mostra uma faixa explicativa.
 *
 * Cada secao tem o mesmo padrao de Section/DataItem ja usado na pagina.
 * ============================================================================
 */

import { useEffect, useState } from 'react'
import {
  ChevronDown, ChevronRight, Loader2,
  TrendingUp, Target, Award, Compass, AlertCircle, Calendar,
} from 'lucide-react'

import {
  Employees, RpcError,
  type GestaoSummary, type GestaoEvaluation, type GestaoPdi,
  type GestaoRecognition, type GestaoOnboarding,
} from '@/lib/r2'

import { PdiCardEditable } from './PdiCardEditable'

// ============================================================================
// Helpers
// ============================================================================

function formatDate(iso: string | null | undefined): string {
  if (!iso) return '-'
  const m = iso.match(/^(\d{4})-(\d{2})-(\d{2})/)
  if (!m) return iso
  return `${m[3]}/${m[2]}/${m[1]}`
}

function formatDateTime(iso: string | null | undefined): string {
  if (!iso) return '-'
  const d = new Date(iso)
  return `${formatDate(iso)} ${d.toLocaleTimeString('pt-BR', { hour: '2-digit', minute: '2-digit' })}`
}

const STATUS_LABELS: Record<string, { label: string; cls: string }> = {
  draft:        { label: 'Rascunho', cls: 'bg-zinc-100 text-zinc-700' },
  active:       { label: 'Ativo', cls: 'bg-blue-100 text-blue-800' },
  completed:    { label: 'Concluído', cls: 'bg-emerald-100 text-emerald-800' },
  canceled:     { label: 'Cancelado', cls: 'bg-red-100 text-red-800' },
  not_started:  { label: 'Não iniciado', cls: 'bg-zinc-100 text-zinc-700' },
  in_progress:  { label: 'Em andamento', cls: 'bg-blue-100 text-blue-800' },
  finalized:    { label: 'Finalizada', cls: 'bg-emerald-100 text-emerald-800' },
  pending:      { label: 'Pendente', cls: 'bg-amber-100 text-amber-800' },
  self_pending: { label: 'Autoavaliação pendente', cls: 'bg-amber-100 text-amber-800' },
  manager_pending: { label: 'Avaliação do gestor pendente', cls: 'bg-amber-100 text-amber-800' },
}

function StatusBadge({ status }: { status: string }) {
  const def = STATUS_LABELS[status] || { label: status, cls: 'bg-zinc-100 text-zinc-700' }
  return (
    <span className={`text-[10px] font-semibold uppercase tracking-wide px-1.5 py-0.5 rounded ${def.cls}`}>
      {def.label}
    </span>
  )
}

// ============================================================================
// Public component
// ============================================================================

export function GestaoSections({
  employeeId, openByDefault = true, onAppUserResolved, refreshKey,
}: {
  employeeId: string
  openByDefault?: boolean
  /** F2 · chamado quando o backend resolve o app_user_id da ficha (ou null se nao tem) */
  onAppUserResolved?: (appUserId: string | null) => void
  /** F2 · incrementa para forcar refetch · usado apos acoes F2 */
  refreshKey?: number
}) {
  const [data, setData] = useState<GestaoSummary | null>(null)
  const [loading, setLoading] = useState(true)
  const [hidden, setHidden] = useState(false)  // true se permission_denied
  const [errorCode, setErrorCode] = useState<string | null>(null)
  // F5 · refresh local disparado por edicoes inline (sem alterar refreshKey externa)
  const [localRefresh, setLocalRefresh] = useState(0)

  const [openSections, setOpenSections] = useState<Set<string>>(
    openByDefault
      ? new Set(['evaluations', 'pdis', 'recognitions', 'onboardings'])
      : new Set(),
  )

  useEffect(() => {
    let cancelled = false
    const fetch = async () => {
      setLoading(true)
      try {
        const r = await Employees.gestaoSummary(employeeId)
        if (!cancelled) {
          setData(r)
          onAppUserResolved?.(r.has_app_user && r.app_user_id ? r.app_user_id : null)
        }
      } catch (err) {
        if (cancelled) return
        if (err instanceof RpcError) {
          if (err.code === 'permission_denied') {
            // Esconde completamente as secoes - usuario nao tem direito
            setHidden(true)
            onAppUserResolved?.(null)
          } else {
            setErrorCode(err.code)
          }
        } else {
          setErrorCode('unknown_error')
        }
      } finally {
        if (!cancelled) setLoading(false)
      }
    }
    fetch()
    return () => { cancelled = true }
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [employeeId, refreshKey, localRefresh])

  const toggle = (key: string) => {
    setOpenSections(prev => {
      const next = new Set(prev)
      if (next.has(key)) next.delete(key)
      else next.add(key)
      return next
    })
  }

  if (hidden) return null  // silencioso para nao-gestores

  if (loading) {
    return (
      <div className="bg-white border border-zinc-200 rounded-lg p-6 text-center text-zinc-500">
        <Loader2 className="h-5 w-5 animate-spin mx-auto" />
      </div>
    )
  }

  if (errorCode) {
    return (
      <div className="bg-white border border-zinc-200 rounded-lg p-4 text-sm text-red-700 flex items-center gap-2">
        <AlertCircle className="h-4 w-4" />
        Não foi possível carregar dados de gestão: <code className="font-mono">{errorCode}</code>
      </div>
    )
  }

  if (!data) return null

  // Ficha sem app_user vinculado · banner explicativo
  if (!data.has_app_user) {
    return (
      <div className="bg-amber-50 border border-amber-200 rounded-lg p-4 text-sm text-amber-900 flex items-start gap-2">
        <AlertCircle className="h-4 w-4 mt-0.5 flex-shrink-0" />
        <div>
          <strong>Esta ficha ainda não tem usuário do sistema vinculado.</strong>
          <p className="mt-1">
            Sem vínculo a <code className="font-mono bg-amber-100 px-1 rounded">app_users</code>, não há histórico de avaliações,
            PDIs, reconhecimentos ou onboardings para mostrar.
          </p>
        </div>
      </div>
    )
  }

  return (
    <>
      {/* Avaliacoes 9-Box */}
      <Section
        title={`Histórico de avaliações 9-Box (${data.evaluations.length})`}
        icon={TrendingUp}
        open={openSections.has('evaluations')}
        onToggle={() => toggle('evaluations')}
      >
        <EvaluationsList evaluations={data.evaluations} />
      </Section>

      {/* PDIs */}
      <Section
        title={`PDIs (${data.pdis.length})`}
        icon={Target}
        open={openSections.has('pdis')}
        onToggle={() => toggle('pdis')}
      >
        <PdisList pdis={data.pdis} onChanged={() => setLocalRefresh(k => k + 1)} />
      </Section>

      {/* Reconhecimentos */}
      <Section
        title={`Reconhecimentos recebidos (${data.recognitions.length})`}
        icon={Award}
        open={openSections.has('recognitions')}
        onToggle={() => toggle('recognitions')}
      >
        <RecognitionsList recognitions={data.recognitions} />
      </Section>

      {/* Onboardings */}
      <Section
        title={`Onboardings (${data.onboardings.length})`}
        icon={Compass}
        open={openSections.has('onboardings')}
        onToggle={() => toggle('onboardings')}
      >
        <OnboardingsList onboardings={data.onboardings} />
      </Section>
    </>
  )
}

// ============================================================================
// Sub-components
// ============================================================================

function Section({
  title, icon: Icon, open, onToggle, children,
}: {
  title: string
  icon: React.ComponentType<{ className?: string }>
  open: boolean
  onToggle: () => void
  children: React.ReactNode
}) {
  return (
    <div className="bg-white border border-zinc-200 rounded-lg overflow-hidden">
      <button
        onClick={onToggle}
        className="w-full px-4 py-3 flex items-center gap-3 hover:bg-zinc-50 transition"
      >
        {open ? (
          <ChevronDown className="h-4 w-4 text-zinc-400 flex-shrink-0" />
        ) : (
          <ChevronRight className="h-4 w-4 text-zinc-400 flex-shrink-0" />
        )}
        <Icon className="h-4 w-4 text-zinc-600 flex-shrink-0" />
        <span className="font-medium text-sm text-zinc-900 flex-1 text-left">{title}</span>
      </button>
      {open && (
        <div className="px-4 pb-4 pt-1 border-t border-zinc-200">
          {children}
        </div>
      )}
    </div>
  )
}

function Empty({ msg }: { msg: string }) {
  return <p className="text-sm text-zinc-500 italic mt-3">{msg}</p>
}

// ----- Avaliacoes -----

function EvaluationsList({ evaluations }: { evaluations: GestaoEvaluation[] }) {
  if (evaluations.length === 0) {
    return <Empty msg="Nenhuma avaliação 9-Box registrada" />
  }
  return (
    <table className="w-full text-sm mt-3">
      <thead>
        <tr className="text-left text-[10px] uppercase tracking-wider text-zinc-500 border-b border-zinc-200">
          <th className="py-2 font-semibold">Ciclo</th>
          <th className="py-2 font-semibold">Caixa</th>
          <th className="py-2 font-semibold">Status</th>
          <th className="py-2 font-semibold">Avaliador</th>
          <th className="py-2 font-semibold">Finalizada em</th>
        </tr>
      </thead>
      <tbody>
        {evaluations.map(e => (
          <tr key={e.id} className="border-b border-zinc-100 last:border-0">
            <td className="py-2">
              {e.cycle_name || '-'}
              {e.is_adhoc && <span className="ml-1 text-[10px] text-zinc-500">(ad-hoc)</span>}
            </td>
            <td className="py-2">
              {e.final_box_label ? (
                <span className="font-medium text-zinc-900">{e.final_box_label}</span>
              ) : <span className="text-zinc-400">-</span>}
              {e.final_box_row != null && e.final_box_col != null && (
                <span className="text-[10px] text-zinc-500 ml-1">
                  ({e.final_box_row + 1},{e.final_box_col + 1})
                </span>
              )}
            </td>
            <td className="py-2"><StatusBadge status={e.status} /></td>
            <td className="py-2 text-zinc-600">{e.manager_name || '-'}</td>
            <td className="py-2 text-xs font-mono">{formatDate(e.finalized_at)}</td>
          </tr>
        ))}
      </tbody>
    </table>
  )
}

// ----- PDIs -----

function PdisList({ pdis, onChanged }: { pdis: GestaoPdi[]; onChanged: () => void }) {
  if (pdis.length === 0) {
    return <Empty msg="Nenhum PDI registrado" />
  }
  return (
    <div className="space-y-3 mt-3">
      {pdis.map(p => (
        <PdiCardEditable key={p.id} pdi={p} onChanged={onChanged} />
      ))}
    </div>
  )
}

// ----- Reconhecimentos -----

function RecognitionsList({ recognitions }: { recognitions: GestaoRecognition[] }) {
  if (recognitions.length === 0) {
    return <Empty msg="Nenhum reconhecimento recebido" />
  }
  return (
    <div className="space-y-2 mt-3">
      {recognitions.map(r => (
        <div key={r.id} className="border border-zinc-200 rounded p-3 flex gap-3">
          <Award className="h-4 w-4 text-amber-600 flex-shrink-0 mt-0.5" />
          <div className="flex-1 min-w-0">
            <div className="flex items-center gap-2 flex-wrap">
              <span className="text-sm font-medium text-zinc-900">
                {r.sender_name || 'Anônimo'}
              </span>
              {r.is_private && (
                <span className="text-[10px] font-semibold uppercase tracking-wide px-1.5 py-0.5 rounded bg-zinc-100 text-zinc-700">
                  Privado
                </span>
              )}
              {r.reactions_count > 0 && (
                <span className="text-xs text-zinc-500">
                  {r.reactions_count} reaçõe{r.reactions_count === 1 ? '' : 's'}
                </span>
              )}
              <span className="text-xs text-zinc-400 ml-auto">{formatDateTime(r.created_at)}</span>
            </div>
            <p className="text-sm text-zinc-700 mt-1">{r.message}</p>
          </div>
        </div>
      ))}
    </div>
  )
}

// ----- Onboardings -----

function OnboardingsList({ onboardings }: { onboardings: GestaoOnboarding[] }) {
  if (onboardings.length === 0) {
    return <Empty msg="Nenhum onboarding registrado" />
  }
  return (
    <div className="space-y-3 mt-3">
      {onboardings.map(o => (
        <div key={o.id} className="border border-zinc-200 rounded p-3">
          <div className="flex items-center gap-2 flex-wrap">
            <h4 className="font-medium text-sm text-zinc-900">{o.display_name}</h4>
            <StatusBadge status={o.status} />
          </div>
          <div className="text-xs text-zinc-500 mt-1 flex gap-3 flex-wrap items-center">
            {o.start_date && (
              <span className="inline-flex items-center gap-1">
                <Calendar className="h-3 w-3" /> {formatDate(o.start_date)}
              </span>
            )}
            {o.target_end_date && (
              <span>até {formatDate(o.target_end_date)}</span>
            )}
            {o.completed_at && (
              <span className="text-emerald-700">concluído em {formatDate(o.completed_at)}</span>
            )}
          </div>
          {o.tasks_total > 0 && (
            <div className="mt-2 flex items-center gap-2">
              <div className="flex-1 max-w-xs h-1.5 bg-zinc-100 rounded-full overflow-hidden">
                <div
                  className="h-full bg-emerald-600"
                  style={{ width: `${(o.tasks_completed / o.tasks_total) * 100}%` }}
                />
              </div>
              <span className="text-xs text-zinc-500">
                {o.tasks_completed}/{o.tasks_total} tarefas
              </span>
              {o.tasks_required > 0 && (
                <span className="text-xs text-amber-700">
                  ({o.tasks_required_done}/{o.tasks_required} obrigatórias)
                </span>
              )}
            </div>
          )}
        </div>
      ))}
    </div>
  )
}

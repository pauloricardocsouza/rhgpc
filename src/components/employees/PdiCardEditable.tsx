'use client'

/**
 * R2 People · PdiCardEditable (Sessao F5)
 * ============================================================================
 * Card de PDI com modo edicao inline expansivel.
 *
 * Modos:
 *   - view: visualizacao compacta (igual ao card original do GestaoSections)
 *   - edit: campos editaveis (objetivo, contexto, datas, status) + gestao
 *           de acoes (add/marcar concluido/remover)
 *
 * Permissao: o componente assume que o backend ja valida. Em caso de
 * permission_denied/permission_required, mostra erro inline.
 *
 * Props:
 *   - pdi:       resumo retornado por rpc_employees_gestao_summary
 *   - onChanged: callback para o pai re-fetchar (incrementa refreshKey)
 * ============================================================================
 */

import { useState, useCallback, useEffect } from 'react'
import {
  ChevronDown, ChevronRight, Loader2, Pencil, Check, X as XIcon,
  Plus, Trash2, CircleCheck, Circle, AlertCircle, Calendar,
} from 'lucide-react'

import {
  Pdi, RpcError,
  type GestaoPdi, type PdiAction, type PdiActionKind, type PdiActionStatus, type PdiStatus,
} from '@/lib/r2'

import { isoDateToBr } from '@/lib/validation'

// ============================================================================
// Tipos auxiliares
// ============================================================================

const STATUS_OPTIONS: Array<{ value: PdiStatus; label: string; cls: string }> = [
  { value: 'draft',     label: 'Rascunho',  cls: 'bg-zinc-100 text-zinc-700' },
  { value: 'active',    label: 'Ativo',     cls: 'bg-blue-100 text-blue-800' },
  { value: 'completed', label: 'Concluído', cls: 'bg-emerald-100 text-emerald-800' },
  { value: 'canceled',  label: 'Cancelado', cls: 'bg-red-100 text-red-800' },
]

const ACTION_KIND_LABEL: Record<PdiActionKind, string> = {
  curso: 'Curso',
  leitura: 'Leitura',
  mentoria: 'Mentoria',
  projeto: 'Projeto',
  certificacao: 'Certificação',
  evento: 'Evento',
  outro: 'Outro',
}

const ACTION_KIND_OPTIONS: PdiActionKind[] = [
  'curso', 'leitura', 'mentoria', 'projeto', 'certificacao', 'evento', 'outro',
]

// ============================================================================
// Component
// ============================================================================

interface PdiCardEditableProps {
  pdi: GestaoPdi
  onChanged: () => void
  /**
   * G1 · quando true, o card e mostrado em "modo dono":
   *  - sem botao de editar objetivo/datas
   *  - sem botoes de mudanca de status
   *  - sem add/remove de acoes
   *  - mantem apenas toggle de status de cada acao (o dono pode marcar
   *    suas acoes como concluidas, conforme regra do backend)
   */
  viewerIsOwner?: boolean
}

export function PdiCardEditable({ pdi, onChanged, viewerIsOwner = false }: PdiCardEditableProps) {
  const [editing, setEditing] = useState(false)
  const [expanded, setExpanded] = useState(false)

  // Estados do form (objetivo, contexto, datas, status)
  const [objective, setObjective] = useState(pdi.objective)
  const [startDate, setStartDate] = useState(pdi.start_date ?? '')
  const [endDate, setEndDate] = useState(pdi.end_date ?? '')

  // Estado de acoes (carregadas sob demanda)
  const [actions, setActions] = useState<PdiAction[]>([])
  const [actionsLoading, setActionsLoading] = useState(false)
  const [actionsError, setActionsError] = useState<string | null>(null)

  const [busy, setBusy] = useState(false)
  const [error, setError] = useState<string | null>(null)

  // Carrega acoes ao expandir (lazy)
  const loadActions = useCallback(async () => {
    setActionsLoading(true)
    setActionsError(null)
    try {
      const r = await Pdi.getById(pdi.id)
      setActions(r.plan.actions || [])
    } catch (err) {
      setActionsError(err instanceof RpcError ? err.code : 'unknown_error')
    } finally {
      setActionsLoading(false)
    }
  }, [pdi.id])

  useEffect(() => {
    if (expanded && actions.length === 0 && !actionsLoading && !actionsError) {
      loadActions()
    }
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [expanded])

  const startEdit = () => {
    setObjective(pdi.objective)
    setStartDate(pdi.start_date ?? '')
    setEndDate(pdi.end_date ?? '')
    setEditing(true)
    setExpanded(true)
  }

  const cancelEdit = () => {
    setEditing(false)
    setError(null)
  }

  const saveEdit = async () => {
    if (objective.trim().length < 5) {
      setError('Objetivo precisa ter ao menos 5 caracteres')
      return
    }
    setBusy(true)
    setError(null)
    try {
      // So envia o que mudou (a RPC trata NULL como "preserva")
      const payload: Parameters<typeof Pdi.update>[1] = {}
      if (objective.trim() !== pdi.objective) payload.objective = objective.trim()
      if (startDate !== (pdi.start_date ?? '')) payload.startDate = startDate || undefined
      if (endDate !== (pdi.end_date ?? ''))   payload.endDate   = endDate   || undefined

      if (Object.keys(payload).length > 0) {
        await Pdi.update(pdi.id, payload)
      }
      setEditing(false)
      onChanged()
    } catch (err) {
      setError(err instanceof RpcError ? friendlyError(err.code) : 'Erro inesperado')
    } finally {
      setBusy(false)
    }
  }

  const changeStatus = async (newStatus: PdiStatus) => {
    setBusy(true)
    setError(null)
    try {
      let reason: string | undefined
      if (newStatus === 'canceled') {
        const r = window.prompt('Motivo do cancelamento (obrigatório):')
        if (!r || !r.trim()) { setBusy(false); return }
        reason = r.trim()
      }
      await Pdi.changeStatus(pdi.id, newStatus, reason)
      onChanged()
    } catch (err) {
      setError(err instanceof RpcError ? friendlyError(err.code) : 'Erro inesperado')
    } finally {
      setBusy(false)
    }
  }

  const addAction = async (input: {
    title: string; description?: string; kind: PdiActionKind; dueDate?: string
  }) => {
    setBusy(true)
    setError(null)
    try {
      await Pdi.addAction({ pdiId: pdi.id, ...input })
      await loadActions()
      onChanged()
    } catch (err) {
      setError(err instanceof RpcError ? friendlyError(err.code) : 'Erro inesperado')
    } finally {
      setBusy(false)
    }
  }

  const toggleActionStatus = async (action: PdiAction) => {
    setBusy(true)
    setError(null)
    try {
      const next: PdiActionStatus =
        action.status === 'completed' ? 'in_progress' : 'completed'
      await Pdi.updateAction(action.id, { status: next })
      await loadActions()
      onChanged()
    } catch (err) {
      setError(err instanceof RpcError ? friendlyError(err.code) : 'Erro inesperado')
    } finally {
      setBusy(false)
    }
  }

  const removeAction = async (action: PdiAction) => {
    if (!window.confirm(`Remover ação "${action.title}"?`)) return
    setBusy(true)
    setError(null)
    try {
      await Pdi.removeAction(action.id)
      await loadActions()
      onChanged()
    } catch (err) {
      setError(err instanceof RpcError ? friendlyError(err.code) : 'Erro inesperado')
    } finally {
      setBusy(false)
    }
  }

  // ==========================================================================
  // Render
  // ==========================================================================

  return (
    <div className="border border-zinc-200 rounded">
      {/* Header */}
      <div className="p-3 flex items-start gap-2">
        <button
          onClick={() => setExpanded(!expanded)}
          className="text-zinc-400 hover:text-zinc-700 mt-0.5"
          aria-label="Expandir"
        >
          {expanded ? <ChevronDown className="h-4 w-4" /> : <ChevronRight className="h-4 w-4" />}
        </button>

        <div className="flex-1 min-w-0">
          {editing ? (
            <input
              type="text"
              value={objective}
              onChange={(e) => setObjective(e.target.value)}
              maxLength={500}
              className="w-full px-2 py-1 text-sm font-medium border border-zinc-300 rounded focus:outline-none focus:ring-2 focus:ring-zinc-300"
            />
          ) : (
            <h4 className="font-medium text-sm text-zinc-900">{pdi.objective}</h4>
          )}

          <div className="text-xs text-zinc-500 mt-1 flex gap-3 flex-wrap items-center">
            <StatusBadge status={pdi.status} />
            {pdi.cycle_name && <span>{pdi.cycle_name}</span>}
            {pdi.start_date && <span>de {isoDateToBr(pdi.start_date)}</span>}
            {pdi.end_date && <span>até {isoDateToBr(pdi.end_date)}</span>}
            {pdi.manager_name && <span>· gestor: {pdi.manager_name}</span>}
          </div>

          {/* Progress */}
          {pdi.actions_total > 0 && (
            <div className="mt-2 flex items-center gap-2">
              <div className="flex-1 max-w-xs h-1.5 bg-zinc-100 rounded-full overflow-hidden">
                <div
                  className="h-full bg-emerald-600"
                  style={{ width: `${(pdi.actions_completed / pdi.actions_total) * 100}%` }}
                />
              </div>
              <span className="text-xs text-zinc-500">
                {pdi.actions_completed}/{pdi.actions_total} ações
              </span>
            </div>
          )}
        </div>

        {/* Botoes do header */}
        {!editing && !viewerIsOwner && (
          <button
            onClick={startEdit}
            disabled={busy}
            className="p-1.5 hover:bg-zinc-100 rounded text-zinc-600 disabled:opacity-50"
            title="Editar PDI"
          >
            <Pencil className="h-3.5 w-3.5" />
          </button>
        )}
      </div>

      {/* Expandido · campos editaveis + acoes */}
      {expanded && (
        <div className="border-t border-zinc-100 px-3 py-3 bg-zinc-50/50 space-y-3">
          {error && (
            <div className="border border-red-200 bg-red-50 rounded p-2 text-xs text-red-900 flex items-start gap-1.5">
              <AlertCircle className="h-3.5 w-3.5 mt-0.5 flex-shrink-0" />
              {error}
            </div>
          )}

          {/* Modo edicao · datas + acoes de status */}
          {editing && (
            <>
              <div className="grid grid-cols-1 sm:grid-cols-2 gap-2">
                <FieldSmall label="Início">
                  <input
                    type="date"
                    value={startDate}
                    onChange={(e) => setStartDate(e.target.value)}
                    className="w-full px-2 py-1 text-xs border border-zinc-200 rounded focus:outline-none focus:ring-2 focus:ring-zinc-300"
                  />
                </FieldSmall>
                <FieldSmall label="Fim">
                  <input
                    type="date"
                    value={endDate}
                    onChange={(e) => setEndDate(e.target.value)}
                    className="w-full px-2 py-1 text-xs border border-zinc-200 rounded focus:outline-none focus:ring-2 focus:ring-zinc-300"
                  />
                </FieldSmall>
              </div>
              <div className="flex justify-end gap-2 pt-2 border-t border-zinc-200">
                <button
                  onClick={cancelEdit}
                  disabled={busy}
                  className="px-3 py-1.5 text-xs font-medium text-zinc-700 hover:bg-zinc-100 border border-zinc-200 disabled:opacity-50 rounded inline-flex items-center gap-1"
                >
                  <XIcon className="h-3 w-3" /> Cancelar
                </button>
                <button
                  onClick={saveEdit}
                  disabled={busy}
                  className="px-3 py-1.5 text-xs font-medium text-white bg-zinc-900 hover:bg-zinc-800 disabled:opacity-50 rounded inline-flex items-center gap-1"
                >
                  {busy ? <Loader2 className="h-3 w-3 animate-spin" /> : <Check className="h-3 w-3" />}
                  Salvar
                </button>
              </div>
            </>
          )}

          {/* Mudanca de status (independente de editing) · so para gestor */}
          {!editing && !viewerIsOwner && (
            <div className="flex items-center gap-1 flex-wrap">
              <span className="text-[10px] uppercase tracking-wider text-zinc-500 font-semibold mr-1">
                Mudar status:
              </span>
              {STATUS_OPTIONS.filter(s => s.value !== pdi.status).map(s => (
                <button
                  key={s.value}
                  onClick={() => changeStatus(s.value)}
                  disabled={busy}
                  className={`text-[10px] font-semibold uppercase tracking-wide px-1.5 py-0.5 rounded ${s.cls} hover:opacity-80 disabled:opacity-30`}
                >
                  {s.label}
                </button>
              ))}
            </div>
          )}

          {/* Acoes do PDI */}
          <div>
            <div className="flex items-center justify-between mb-1.5">
              <h5 className="text-[10px] font-semibold uppercase tracking-wider text-zinc-500">
                Ações ({actions.length})
              </h5>
            </div>

            {actionsLoading ? (
              <div className="text-xs text-zinc-500 flex items-center gap-1.5">
                <Loader2 className="h-3 w-3 animate-spin" /> Carregando ações...
              </div>
            ) : actionsError ? (
              <div className="text-xs text-red-700">{actionsError}</div>
            ) : (
              <>
                {actions.length === 0 ? (
                  <p className="text-xs text-zinc-500 italic">Nenhuma ação cadastrada</p>
                ) : (
                  <div className="space-y-1">
                    {actions
                      .slice()
                      .sort((a, b) => a.display_order - b.display_order)
                      .map(a => (
                        <ActionRow
                          key={a.id}
                          action={a}
                          busy={busy}
                          allowRemove={!viewerIsOwner}
                          onToggleStatus={() => toggleActionStatus(a)}
                          onRemove={() => removeAction(a)}
                        />
                      ))}
                  </div>
                )}

                {!viewerIsOwner && <AddActionForm onSubmit={addAction} busy={busy} />}
              </>
            )}
          </div>
        </div>
      )}
    </div>
  )
}

// ============================================================================
// Sub-componentes
// ============================================================================

function StatusBadge({ status }: { status: string }) {
  const def = STATUS_OPTIONS.find(s => s.value === status)
  if (!def) {
    return (
      <span className="text-[10px] font-semibold uppercase tracking-wide px-1.5 py-0.5 rounded bg-zinc-100 text-zinc-700">
        {status}
      </span>
    )
  }
  return (
    <span className={`text-[10px] font-semibold uppercase tracking-wide px-1.5 py-0.5 rounded ${def.cls}`}>
      {def.label}
    </span>
  )
}

function FieldSmall({ label, children }: { label: string; children: React.ReactNode }) {
  return (
    <div>
      <label className="block text-[10px] uppercase tracking-wider text-zinc-500 font-semibold mb-0.5">
        {label}
      </label>
      {children}
    </div>
  )
}

function ActionRow({
  action, busy, allowRemove, onToggleStatus, onRemove,
}: {
  action: PdiAction
  busy: boolean
  allowRemove: boolean
  onToggleStatus: () => void
  onRemove: () => void
}) {
  const isDone = action.status === 'completed'
  return (
    <div className="bg-white border border-zinc-100 rounded px-2 py-1.5 flex items-center gap-2 group">
      <button
        onClick={onToggleStatus}
        disabled={busy}
        className="text-zinc-400 hover:text-emerald-700 disabled:opacity-50"
        title={isDone ? 'Marcar como em andamento' : 'Marcar como concluída'}
      >
        {isDone
          ? <CircleCheck className="h-4 w-4 text-emerald-600" />
          : <Circle className="h-4 w-4" />}
      </button>
      <div className="flex-1 min-w-0">
        <div className={`text-xs ${isDone ? 'line-through text-zinc-500' : 'text-zinc-900'}`}>
          {action.title}
        </div>
        <div className="text-[10px] text-zinc-500 flex gap-2 mt-0.5">
          <span>{ACTION_KIND_LABEL[action.kind]}</span>
          {action.due_date && (
            <span className="inline-flex items-center gap-0.5">
              <Calendar className="h-2.5 w-2.5" />
              {isoDateToBr(action.due_date)}
            </span>
          )}
        </div>
      </div>
      {allowRemove && (
        <button
          onClick={onRemove}
          disabled={busy}
          className="text-zinc-300 hover:text-red-600 disabled:opacity-50 opacity-0 group-hover:opacity-100 transition"
          title="Remover ação"
        >
          <Trash2 className="h-3.5 w-3.5" />
        </button>
      )}
    </div>
  )
}

function AddActionForm({
  onSubmit, busy,
}: {
  onSubmit: (input: {
    title: string; description?: string; kind: PdiActionKind; dueDate?: string
  }) => Promise<void>
  busy: boolean
}) {
  const [showForm, setShowForm] = useState(false)
  const [title, setTitle] = useState('')
  const [kind, setKind] = useState<PdiActionKind>('outro')
  const [dueDate, setDueDate] = useState('')

  const canSubmit = title.trim().length >= 3 && !busy

  const handleSubmit = async () => {
    if (!canSubmit) return
    await onSubmit({
      title: title.trim(),
      kind,
      dueDate: dueDate || undefined,
    })
    // Reset
    setTitle('')
    setKind('outro')
    setDueDate('')
    setShowForm(false)
  }

  if (!showForm) {
    return (
      <button
        onClick={() => setShowForm(true)}
        disabled={busy}
        className="mt-2 px-2 py-1 text-xs text-zinc-700 hover:bg-zinc-100 border border-dashed border-zinc-300 rounded inline-flex items-center gap-1 disabled:opacity-50"
      >
        <Plus className="h-3 w-3" /> Adicionar ação
      </button>
    )
  }

  return (
    <div className="mt-2 border border-zinc-200 rounded p-2 space-y-2 bg-white">
      <input
        type="text"
        value={title}
        onChange={(e) => setTitle(e.target.value)}
        placeholder="Título da ação (mín. 3 caracteres)"
        maxLength={200}
        className="w-full px-2 py-1 text-xs border border-zinc-200 rounded focus:outline-none focus:ring-2 focus:ring-zinc-300"
      />
      <div className="grid grid-cols-1 sm:grid-cols-2 gap-2">
        <select
          value={kind}
          onChange={(e) => setKind(e.target.value as PdiActionKind)}
          className="w-full px-2 py-1 text-xs border border-zinc-200 rounded focus:outline-none focus:ring-2 focus:ring-zinc-300 bg-white"
        >
          {ACTION_KIND_OPTIONS.map(k => (
            <option key={k} value={k}>{ACTION_KIND_LABEL[k]}</option>
          ))}
        </select>
        <input
          type="date"
          value={dueDate}
          onChange={(e) => setDueDate(e.target.value)}
          className="w-full px-2 py-1 text-xs border border-zinc-200 rounded focus:outline-none focus:ring-2 focus:ring-zinc-300"
        />
      </div>
      <div className="flex justify-end gap-1">
        <button
          onClick={() => { setShowForm(false); setTitle('') }}
          disabled={busy}
          className="px-2 py-1 text-xs text-zinc-700 hover:bg-zinc-100 disabled:opacity-50 rounded inline-flex items-center gap-1"
        >
          <XIcon className="h-3 w-3" /> Cancelar
        </button>
        <button
          onClick={handleSubmit}
          disabled={!canSubmit}
          className="px-2 py-1 text-xs text-white bg-zinc-900 hover:bg-zinc-800 disabled:opacity-50 rounded inline-flex items-center gap-1"
        >
          {busy ? <Loader2 className="h-3 w-3 animate-spin" /> : <Plus className="h-3 w-3" />}
          Adicionar
        </button>
      </div>
    </div>
  )
}

// ============================================================================
// Mensagens de erro friendly
// ============================================================================

function friendlyError(code: string): string {
  const map: Record<string, string> = {
    not_authenticated: 'Sessão expirada. Faça login novamente.',
    module_inactive: 'Módulo PDI não está ativo.',
    permission_denied: 'Você não tem permissão para editar este PDI.',
    pdi_not_found: 'PDI não encontrado.',
    action_not_found: 'Ação não encontrada.',
    invalid_transition: 'Transição de status inválida para esse estado.',
    cancel_reason_required: 'Para cancelar, é necessário informar o motivo.',
    objective_required: 'Objetivo é obrigatório.',
    end_before_start: 'Data fim deve ser depois da data início.',
    title_required: 'Título da ação é obrigatório.',
    title_too_short: 'Título precisa de pelo menos 3 caracteres.',
  }
  return map[code] || `Erro: ${code}`
}

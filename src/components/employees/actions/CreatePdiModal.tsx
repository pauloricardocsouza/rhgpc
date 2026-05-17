'use client'

/**
 * R2 People · CreatePdiModal (Sessao F2)
 * ============================================================================
 * Modal full-screen para criar um PDI.
 *
 * Fluxo:
 *   1. Ao montar, carrega ciclos PDI ativos via Pdi.listCycles()
 *   2. Se nenhum ciclo aberto · mostra mensagem + link para configurar
 *   3. RH/gestor escolhe ciclo, preenche objetivo + datas opcionais
 *   4. Submit chama Pdi.create
 *   5. Em erro 'permission_denied' / 'cycle_not_open' / etc · mensagem amigavel
 *
 * Permissoes (backend valida):
 *   - manage_self_pdi (criar pra si)
 *   - user_is_manager_of(target) (gestor direto)
 *   - manage_all_pdi (RH / diretoria)
 * ============================================================================
 */

import { useState, useEffect } from 'react'
import { X, Target, Loader2, AlertCircle, Calendar } from 'lucide-react'
import Link from 'next/link'

import { Pdi, RpcError } from '@/lib/r2'

interface CreatePdiModalProps {
  appUserId: string
  employeeName: string
  onClose: () => void
  onCreated: () => void
}

interface Cycle {
  id: string
  code: string
  display_name: string
  start_date: string
  end_date: string
  open_for_planning: boolean
}

export function CreatePdiModal({
  appUserId, employeeName, onClose, onCreated,
}: CreatePdiModalProps) {
  const [cycles, setCycles] = useState<Cycle[]>([])
  const [loadingCycles, setLoadingCycles] = useState(true)
  const [cycleError, setCycleError] = useState<string | null>(null)

  const [cycleId, setCycleId] = useState('')
  const [objective, setObjective] = useState('')
  const [context, setContext] = useState('')
  const [startDate, setStartDate] = useState('')
  const [endDate, setEndDate] = useState('')

  const [submitting, setSubmitting] = useState(false)
  const [submitError, setSubmitError] = useState<string | null>(null)

  // Carrega ciclos disponiveis ao montar
  useEffect(() => {
    let cancelled = false
    const fetch = async () => {
      try {
        const r = await Pdi.listCycles()
        const open = r.items.filter(c => c.open_for_planning)
        if (!cancelled) {
          setCycles(open)
          // Auto-seleciona se houver apenas 1
          if (open.length === 1) setCycleId(open[0].id)
        }
      } catch (err) {
        if (cancelled) return
        setCycleError(err instanceof RpcError ? err.code : 'unknown_error')
      } finally {
        if (!cancelled) setLoadingCycles(false)
      }
    }
    fetch()
    return () => { cancelled = true }
  }, [])

  // Esc fecha
  useEffect(() => {
    const handler = (e: KeyboardEvent) => { if (e.key === 'Escape') onClose() }
    window.addEventListener('keydown', handler)
    return () => window.removeEventListener('keydown', handler)
  }, [onClose])

  const canSubmit = cycleId && objective.trim().length >= 5 && !submitting

  const handleSubmit = async () => {
    if (!canSubmit) return
    setSubmitError(null)
    setSubmitting(true)
    try {
      await Pdi.create({
        userId: appUserId,
        cycleId,
        objective: objective.trim(),
        context: context.trim() || undefined,
        startDate: startDate || undefined,
        endDate: endDate || undefined,
      })
      onCreated()
    } catch (err) {
      setSubmitError(err instanceof RpcError ? friendlyError(err.code) : 'Erro inesperado')
    } finally {
      setSubmitting(false)
    }
  }

  return (
    <ModalShell title="Criar PDI" icon={Target} onClose={onClose}>
      <div className="max-w-2xl mx-auto space-y-5">
        <div className="text-sm text-zinc-600">
          PDI para <strong className="text-zinc-900">{employeeName}</strong>.
        </div>

        {/* Ciclo */}
        {loadingCycles ? (
          <div className="text-sm text-zinc-500 flex items-center gap-2">
            <Loader2 className="h-4 w-4 animate-spin" />
            Carregando ciclos disponíveis...
          </div>
        ) : cycleError ? (
          <ErrorBox msg={`Erro ao carregar ciclos: ${cycleError}`} />
        ) : cycles.length === 0 ? (
          <div className="border border-amber-200 bg-amber-50 rounded p-4 text-sm text-amber-900">
            <div className="flex items-start gap-2">
              <AlertCircle className="h-5 w-5 mt-0.5 flex-shrink-0" />
              <div>
                <strong>Nenhum ciclo PDI aberto para planejamento.</strong>
                <p className="mt-1">
                  Peça ao RH ou administrador para abrir um ciclo via{' '}
                  <Link href="/admin/pdi/ciclos" className="underline hover:no-underline">
                    Configurações &gt; PDI &gt; Ciclos
                  </Link>.
                </p>
              </div>
            </div>
          </div>
        ) : (
          <Field label="Ciclo" required>
            <select
              value={cycleId}
              onChange={(e) => setCycleId(e.target.value)}
              className="w-full px-3 py-2 text-sm border border-zinc-200 rounded focus:outline-none focus:ring-2 focus:ring-zinc-300 bg-white"
            >
              <option value="">— Selecione um ciclo —</option>
              {cycles.map(c => (
                <option key={c.id} value={c.id}>
                  {c.display_name} ({formatDate(c.start_date)} → {formatDate(c.end_date)})
                </option>
              ))}
            </select>
          </Field>
        )}

        <Field
          label="Objetivo"
          required
          hint="Mínimo 5 caracteres. O que essa pessoa pretende desenvolver?"
        >
          <textarea
            value={objective}
            onChange={(e) => setObjective(e.target.value)}
            rows={3}
            maxLength={500}
            placeholder="Ex: Aprimorar habilidades de comunicação em apresentações"
            className="w-full px-3 py-2 text-sm border border-zinc-200 rounded focus:outline-none focus:ring-2 focus:ring-zinc-300"
          />
        </Field>

        <Field
          label="Contexto (opcional)"
          hint="Por que esse objetivo agora? Que ações esperadas?"
        >
          <textarea
            value={context}
            onChange={(e) => setContext(e.target.value)}
            rows={2}
            maxLength={1000}
            placeholder="Ex: Após a avaliação 9-Box, identificamos oportunidade..."
            className="w-full px-3 py-2 text-sm border border-zinc-200 rounded focus:outline-none focus:ring-2 focus:ring-zinc-300"
          />
        </Field>

        <div className="grid grid-cols-1 sm:grid-cols-2 gap-3">
          <Field label="Início (opcional)" hint="Default: data atual">
            <input
              type="date"
              value={startDate}
              onChange={(e) => setStartDate(e.target.value)}
              className="w-full px-3 py-2 text-sm border border-zinc-200 rounded focus:outline-none focus:ring-2 focus:ring-zinc-300"
            />
          </Field>
          <Field label="Fim (opcional)" hint="Default: fim do ciclo">
            <input
              type="date"
              value={endDate}
              onChange={(e) => setEndDate(e.target.value)}
              className="w-full px-3 py-2 text-sm border border-zinc-200 rounded focus:outline-none focus:ring-2 focus:ring-zinc-300"
            />
          </Field>
        </div>

        {submitError && <ErrorBox msg={submitError} />}

        <div className="flex items-center justify-end gap-2 pt-2 border-t border-zinc-100">
          <button
            onClick={onClose}
            disabled={submitting}
            className="px-4 py-2 text-sm font-medium text-zinc-700 hover:bg-zinc-100 border border-zinc-200 disabled:opacity-50 rounded"
          >
            Cancelar
          </button>
          <button
            onClick={handleSubmit}
            disabled={!canSubmit}
            className="px-4 py-2 text-sm font-medium text-white bg-zinc-900 hover:bg-zinc-800 disabled:opacity-50 rounded inline-flex items-center gap-1.5"
          >
            {submitting && <Loader2 className="h-3.5 w-3.5 animate-spin" />}
            <Calendar className="h-3.5 w-3.5" />
            Criar PDI
          </button>
        </div>
      </div>
    </ModalShell>
  )
}

// ============================================================================
// Helpers compartilhados pelos modais F2
// ============================================================================

export function ModalShell({
  title, icon: Icon, onClose, children,
}: {
  title: string
  icon: React.ComponentType<{ className?: string }>
  onClose: () => void
  children: React.ReactNode
}) {
  return (
    <div className="fixed inset-0 z-50 bg-black/50 flex" onClick={onClose}>
      <div
        className="bg-white w-full h-full overflow-y-auto"
        onClick={(e) => e.stopPropagation()}
      >
        <div className="sticky top-0 bg-white border-b border-zinc-200 px-6 py-3 flex items-center gap-3 z-10">
          <button
            onClick={onClose}
            className="p-1.5 hover:bg-zinc-100 rounded text-zinc-600"
            title="Fechar (Esc)"
          >
            <X className="h-4 w-4" />
          </button>
          <Icon className="h-5 w-5 text-zinc-600" />
          <h1 className="text-lg font-semibold text-zinc-900">{title}</h1>
        </div>
        <div className="px-6 py-6">{children}</div>
      </div>
    </div>
  )
}

export function Field({
  label, required, hint, children,
}: {
  label: string
  required?: boolean
  hint?: string
  children: React.ReactNode
}) {
  return (
    <div>
      <label className="block text-xs font-semibold uppercase tracking-wider text-zinc-500 mb-1">
        {label}
        {required && <span className="text-red-600 ml-0.5">*</span>}
      </label>
      {children}
      {hint && <p className="text-xs text-zinc-500 mt-1">{hint}</p>}
    </div>
  )
}

export function ErrorBox({ msg }: { msg: string }) {
  return (
    <div className="border border-red-200 bg-red-50 rounded p-3 text-sm text-red-900 flex items-start gap-2">
      <AlertCircle className="h-4 w-4 mt-0.5 flex-shrink-0" />
      <span>{msg}</span>
    </div>
  )
}

function formatDate(iso: string): string {
  const m = iso.match(/^(\d{4})-(\d{2})-(\d{2})/)
  if (!m) return iso
  return `${m[3]}/${m[2]}/${m[1]}`
}

function friendlyError(code: string): string {
  const map: Record<string, string> = {
    not_authenticated: 'Sessão expirada. Faça login novamente.',
    module_inactive: 'Módulo PDI não está ativo para o tenant.',
    user_not_found: 'Pessoa não encontrada.',
    cross_tenant_blocked: 'Operação cross-tenant bloqueada.',
    permission_denied: 'Você não tem permissão para criar PDI para esta pessoa.',
    cycle_not_found: 'Ciclo PDI não encontrado.',
    cycle_not_open: 'Ciclo PDI não está aberto para planejamento.',
    cycle_cross_tenant: 'Ciclo de outro tenant.',
    objective_required: 'Objetivo é obrigatório.',
    end_before_start: 'Data fim deve ser depois da data início.',
  }
  return map[code] || `Erro: ${code}`
}

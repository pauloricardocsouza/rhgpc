'use client'

/**
 * R2 People · RecognizeModal (Sessao F2)
 * ============================================================================
 * Modal full-screen para criar um reconhecimento.
 *
 * Campos:
 *   - Mensagem (obrigatoria, min 10 caracteres)
 *   - Toggle "privado" · so visivel para super_admin/RH/diretoria/sender/recipient
 *
 * Backend valida modulo ativo e cross-tenant.
 * ============================================================================
 */

import { useState, useEffect } from 'react'
import { Award, Loader2, Lock, Globe } from 'lucide-react'

import { Recognition, RpcError } from '@/lib/r2'
import { ModalShell, Field, ErrorBox } from './CreatePdiModal'

interface RecognizeModalProps {
  appUserId: string
  employeeName: string
  onClose: () => void
  onCreated: () => void
}

export function RecognizeModal({
  appUserId, employeeName, onClose, onCreated,
}: RecognizeModalProps) {
  const [message, setMessage] = useState('')
  const [isPrivate, setIsPrivate] = useState(false)
  const [submitting, setSubmitting] = useState(false)
  const [submitError, setSubmitError] = useState<string | null>(null)

  useEffect(() => {
    const handler = (e: KeyboardEvent) => { if (e.key === 'Escape') onClose() }
    window.addEventListener('keydown', handler)
    return () => window.removeEventListener('keydown', handler)
  }, [onClose])

  const canSubmit = message.trim().length >= 10 && !submitting

  const handleSubmit = async () => {
    if (!canSubmit) return
    setSubmitError(null)
    setSubmitting(true)
    try {
      await Recognition.create({
        recipientId: appUserId,
        message: message.trim(),
        isPrivate,
      })
      onCreated()
    } catch (err) {
      setSubmitError(err instanceof RpcError ? friendlyError(err.code) : 'Erro inesperado')
    } finally {
      setSubmitting(false)
    }
  }

  return (
    <ModalShell title="Reconhecer" icon={Award} onClose={onClose}>
      <div className="max-w-2xl mx-auto space-y-5">
        <div className="text-sm text-zinc-600">
          Reconhecimento para <strong className="text-zinc-900">{employeeName}</strong>.
        </div>

        <Field
          label="Mensagem"
          required
          hint="Mínimo 10 caracteres. Descreva especificamente o que está sendo reconhecido."
        >
          <textarea
            value={message}
            onChange={(e) => setMessage(e.target.value)}
            rows={5}
            maxLength={1000}
            placeholder="Ex: Ótimo trabalho conduzindo a reunião com o cliente X. Sua preparação ficou evidente quando..."
            className="w-full px-3 py-2 text-sm border border-zinc-200 rounded focus:outline-none focus:ring-2 focus:ring-zinc-300"
          />
          <div className="text-xs text-zinc-400 mt-1 text-right">
            {message.length} / 1000
          </div>
        </Field>

        {/* Toggle privado/publico */}
        <Field label="Visibilidade">
          <div className="grid grid-cols-2 gap-2">
            <VisibilityOption
              icon={Globe}
              title="Público"
              hint="Visível para qualquer pessoa do tenant"
              selected={!isPrivate}
              onClick={() => setIsPrivate(false)}
            />
            <VisibilityOption
              icon={Lock}
              title="Privado"
              hint="Só RH, diretoria, você e o destinatário"
              selected={isPrivate}
              onClick={() => setIsPrivate(true)}
            />
          </div>
        </Field>

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
            className="px-4 py-2 text-sm font-medium text-white bg-amber-700 hover:bg-amber-800 disabled:opacity-50 rounded inline-flex items-center gap-1.5"
          >
            {submitting && <Loader2 className="h-3.5 w-3.5 animate-spin" />}
            <Award className="h-3.5 w-3.5" />
            Reconhecer
          </button>
        </div>
      </div>
    </ModalShell>
  )
}

function VisibilityOption({
  icon: Icon, title, hint, selected, onClick,
}: {
  icon: React.ComponentType<{ className?: string }>
  title: string
  hint: string
  selected: boolean
  onClick: () => void
}) {
  return (
    <button
      onClick={onClick}
      type="button"
      className={[
        'border rounded p-3 text-left transition',
        selected
          ? 'border-amber-500 bg-amber-50 ring-2 ring-amber-200'
          : 'border-zinc-200 hover:border-zinc-300',
      ].join(' ')}
    >
      <div className="flex items-center gap-2 mb-1">
        <Icon className={`h-4 w-4 ${selected ? 'text-amber-700' : 'text-zinc-500'}`} />
        <span className={`text-sm font-medium ${selected ? 'text-amber-900' : 'text-zinc-900'}`}>
          {title}
        </span>
      </div>
      <p className="text-xs text-zinc-600">{hint}</p>
    </button>
  )
}

function friendlyError(code: string): string {
  const map: Record<string, string> = {
    not_authenticated: 'Sessão expirada. Faça login novamente.',
    module_inactive: 'Módulo de reconhecimentos não está ativo.',
    user_not_found: 'Pessoa não encontrada.',
    cross_tenant_blocked: 'Operação cross-tenant bloqueada.',
    permission_denied: 'Você não tem permissão para reconhecer esta pessoa.',
    self_recognition_blocked: 'Você não pode reconhecer a si mesmo.',
    message_too_short: 'A mensagem precisa ter pelo menos 10 caracteres.',
  }
  return map[code] || `Erro: ${code}`
}

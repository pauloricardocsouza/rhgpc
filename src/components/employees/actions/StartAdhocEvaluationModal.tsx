'use client'

/**
 * R2 People · StartAdhocEvaluationModal (Sessao F2)
 * ============================================================================
 * Modal para iniciar uma avaliacao 9-Box ad-hoc (fora de ciclo formal).
 *
 * Diferencas de uma avaliacao normal:
 *   - cycle_id e NULL no backend
 *   - is_adhoc=TRUE
 *   - Nao conta no fechamento de ciclo (mas entra no historico)
 *
 * Fluxo:
 *   1. Confirma com o gestor que quer iniciar
 *   2. Chama Ninebox.startEvaluation({ subjectId, isAdhoc: true })
 *   3. Redireciona para a tela de avaliacao (rota /ninebox/avaliacoes/[id])
 *      onde o gestor preenche os scores
 *
 * Backend valida que o caller eh manager direto ou tem permissao.
 * ============================================================================
 */

import { useState, useEffect } from 'react'
import { useRouter } from 'next/navigation'
import { TrendingUp, Loader2, Zap } from 'lucide-react'

import { Ninebox, RpcError } from '@/lib/r2'
import { ModalShell, ErrorBox } from './CreatePdiModal'

interface StartAdhocEvaluationModalProps {
  appUserId: string
  employeeName: string
  onClose: () => void
  onCreated: () => void
}

export function StartAdhocEvaluationModal({
  appUserId, employeeName, onClose, onCreated,
}: StartAdhocEvaluationModalProps) {
  const router = useRouter()
  const [submitting, setSubmitting] = useState(false)
  const [submitError, setSubmitError] = useState<string | null>(null)

  useEffect(() => {
    const handler = (e: KeyboardEvent) => { if (e.key === 'Escape' && !submitting) onClose() }
    window.addEventListener('keydown', handler)
    return () => window.removeEventListener('keydown', handler)
  }, [onClose, submitting])

  const handleSubmit = async () => {
    setSubmitError(null)
    setSubmitting(true)
    try {
      const r = await Ninebox.startEvaluation({
        subjectId: appUserId,
        isAdhoc: true,
      })
      // Notifica o pai para refresh + navega para a avaliacao recem criada
      onCreated()
      router.push(`/ninebox/avaliacoes/${r.evaluation_id}`)
    } catch (err) {
      setSubmitError(err instanceof RpcError ? friendlyError(err.code) : 'Erro inesperado')
    } finally {
      setSubmitting(false)
    }
  }

  return (
    <ModalShell title="Iniciar avaliação 9-Box ad-hoc" icon={TrendingUp} onClose={onClose}>
      <div className="max-w-2xl mx-auto space-y-5">
        <div className="text-sm text-zinc-600">
          Iniciar avaliação 9-Box ad-hoc para <strong className="text-zinc-900">{employeeName}</strong>.
        </div>

        {/* Card explicativo */}
        <div className="border border-blue-200 bg-blue-50 rounded p-4 text-sm text-blue-900">
          <div className="flex items-start gap-2">
            <Zap className="h-5 w-5 mt-0.5 flex-shrink-0" />
            <div className="space-y-2">
              <p>
                <strong>Avaliação ad-hoc</strong> é feita fora de um ciclo formal.
                Use quando você quer registrar uma percepção de desempenho/potencial
                independentemente do cronograma normal de avaliações.
              </p>
              <p>
                Após confirmar, você será levado para a tela de avaliação onde poderá
                preencher os scores de potencial e desempenho.
              </p>
            </div>
          </div>
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
            disabled={submitting}
            className="px-4 py-2 text-sm font-medium text-white bg-emerald-700 hover:bg-emerald-800 disabled:opacity-50 rounded inline-flex items-center gap-1.5"
          >
            {submitting && <Loader2 className="h-3.5 w-3.5 animate-spin" />}
            <TrendingUp className="h-3.5 w-3.5" />
            Iniciar avaliação
          </button>
        </div>
      </div>
    </ModalShell>
  )
}

function friendlyError(code: string): string {
  const map: Record<string, string> = {
    not_authenticated: 'Sessão expirada. Faça login novamente.',
    module_inactive: 'Módulo 9-Box não está ativo.',
    module_inactive_at_resource_scope: 'Módulo 9-Box não está ativo para este escopo.',
    subject_not_found: 'Pessoa não encontrada.',
    permission_denied: 'Você não tem permissão para avaliar esta pessoa.',
    subject_has_no_manager: 'Pessoa não tem gestor definido. Defina um gestor antes de avaliar.',
    evaluation_already_exists_for_cycle: 'Já existe avaliação para essa pessoa neste contexto.',
  }
  return map[code] || `Erro: ${code}`
}

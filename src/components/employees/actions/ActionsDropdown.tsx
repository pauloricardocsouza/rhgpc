'use client'

/**
 * R2 People · ActionsDropdown (Sessao F2)
 * ============================================================================
 * Botao "+ Acao" no header de /pessoas/[id] que abre dropdown com:
 *   - Criar PDI
 *   - Reconhecer
 *   - Iniciar avaliacao 9-Box ad-hoc
 *
 * Renderiza condicionalmente os modais full-screen quando uma opcao e clicada.
 *
 * Permissoes:
 *   - Botao so aparece se a ficha tem app_user vinculado
 *   - Cada acao faz seu proprio check no backend; em caso de erro mostra mensagem
 *
 * Props:
 *   - employeeId: id da ficha (para refresh apos acao)
 *   - appUserId: id do usuario destinatario das acoes
 *   - employeeName: para exibicao no modal
 *   - onActionCompleted?: callback para o pai recarregar dados
 * ============================================================================
 */

import { useState, useRef, useEffect } from 'react'
import { Plus, Target, Award, TrendingUp, ChevronDown } from 'lucide-react'

import { CreatePdiModal } from './CreatePdiModal'
import { RecognizeModal } from './RecognizeModal'
import { StartAdhocEvaluationModal } from './StartAdhocEvaluationModal'

interface ActionsDropdownProps {
  employeeId: string
  appUserId: string
  employeeName: string
  onActionCompleted?: () => void
}

type ModalKind = 'pdi' | 'recognize' | 'adhoc' | null

export function ActionsDropdown({
  employeeId, appUserId, employeeName, onActionCompleted,
}: ActionsDropdownProps) {
  const [open, setOpen] = useState(false)
  const [modal, setModal] = useState<ModalKind>(null)
  const ref = useRef<HTMLDivElement>(null)

  // Fechar dropdown ao clicar fora
  useEffect(() => {
    if (!open) return
    const handler = (e: MouseEvent) => {
      if (ref.current && !ref.current.contains(e.target as Node)) setOpen(false)
    }
    window.addEventListener('mousedown', handler)
    return () => window.removeEventListener('mousedown', handler)
  }, [open])

  const handleAction = (kind: 'pdi' | 'recognize' | 'adhoc') => {
    setOpen(false)
    setModal(kind)
  }

  const handleCompleted = () => {
    setModal(null)
    onActionCompleted?.()
  }

  return (
    <>
      <div ref={ref} className="relative">
        <button
          onClick={() => setOpen(!open)}
          className="px-3 py-1.5 text-sm font-medium text-white bg-zinc-900 hover:bg-zinc-800 rounded inline-flex items-center gap-1.5"
        >
          <Plus className="h-3.5 w-3.5" />
          Ação
          <ChevronDown className="h-3.5 w-3.5" />
        </button>

        {open && (
          <div className="absolute right-0 top-full mt-1 bg-white border border-zinc-200 rounded-md shadow-lg w-56 py-1 z-20">
            <DropdownItem
              icon={Target}
              label="Criar PDI"
              hint="Plano de desenvolvimento"
              onClick={() => handleAction('pdi')}
            />
            <DropdownItem
              icon={Award}
              label="Reconhecer"
              hint="Reconhecimento público ou privado"
              onClick={() => handleAction('recognize')}
            />
            <DropdownItem
              icon={TrendingUp}
              label="Iniciar 9-Box ad-hoc"
              hint="Avaliação fora de ciclo"
              onClick={() => handleAction('adhoc')}
            />
          </div>
        )}
      </div>

      {/* Modais full-screen renderizados condicionalmente */}
      {modal === 'pdi' && (
        <CreatePdiModal
          appUserId={appUserId}
          employeeName={employeeName}
          onClose={() => setModal(null)}
          onCreated={handleCompleted}
        />
      )}
      {modal === 'recognize' && (
        <RecognizeModal
          appUserId={appUserId}
          employeeName={employeeName}
          onClose={() => setModal(null)}
          onCreated={handleCompleted}
        />
      )}
      {modal === 'adhoc' && (
        <StartAdhocEvaluationModal
          appUserId={appUserId}
          employeeName={employeeName}
          onClose={() => setModal(null)}
          onCreated={handleCompleted}
        />
      )}
    </>
  )
}

function DropdownItem({
  icon: Icon, label, hint, onClick,
}: {
  icon: React.ComponentType<{ className?: string }>
  label: string
  hint: string
  onClick: () => void
}) {
  return (
    <button
      onClick={onClick}
      className="w-full px-3 py-2 text-left hover:bg-zinc-50 flex items-start gap-2 group"
    >
      <Icon className="h-4 w-4 text-zinc-600 mt-0.5 flex-shrink-0" />
      <div className="min-w-0">
        <div className="text-sm font-medium text-zinc-900">{label}</div>
        <div className="text-xs text-zinc-500">{hint}</div>
      </div>
    </button>
  )
}

'use client'

/**
 * R2 People · MyProfileRequests (Sessao G3)
 * ============================================================================
 * Painel na /minha-jornada listando solicitacoes de alteracao do proprio
 * perfil. Permite cancelar pendentes e mostra historico (approved/rejected).
 *
 * Tambem expoe um botao para abrir o modal por field (proxima sessao
 * podera integrar isso diretamente nos campos de dados pessoais).
 * ============================================================================
 */

import { useCallback, useEffect, useState } from 'react'
import {
  Loader2, AlertCircle, X, Check, Clock, CheckCircle2, XCircle, MinusCircle,
} from 'lucide-react'

import {
  myProfileRequestsList, myProfileRequestCancel, RpcError,
  type ProfileChangeRequest, type ProfileChangeField, type ProfileChangeStatus,
} from '@/lib/r2'
import { isoDateToBr } from '@/lib/validation'

const FIELD_LABELS: Record<ProfileChangeField, string> = {
  phone_mobile: 'Telefone celular',
  phone_home: 'Telefone fixo',
  personal_email: 'Email pessoal',
  residence_address: 'Endereço residencial',
  emergency_contact: 'Contato de emergência',
  photo: 'Foto de perfil',
}

const STATUS_META: Record<ProfileChangeStatus, {
  label: string; cls: string; icon: React.ComponentType<{ className?: string }>;
}> = {
  pending:  { label: 'Pendente',  cls: 'bg-amber-100 text-amber-800',     icon: Clock },
  approved: { label: 'Aprovada',  cls: 'bg-emerald-100 text-emerald-800', icon: CheckCircle2 },
  rejected: { label: 'Rejeitada', cls: 'bg-red-100 text-red-800',         icon: XCircle },
  canceled: { label: 'Cancelada', cls: 'bg-zinc-100 text-zinc-700',       icon: MinusCircle },
}

// ============================================================================
// Component
// ============================================================================

interface MyProfileRequestsProps {
  /** Incrementar pra forcar re-fetch (ex: apos uma nova solicitacao) */
  refreshKey?: number
  onChanged?: () => void
}

export function MyProfileRequests({ refreshKey, onChanged }: MyProfileRequestsProps) {
  const [items, setItems] = useState<ProfileChangeRequest[]>([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)
  const [busyId, setBusyId] = useState<string | null>(null)

  const fetchItems = useCallback(async () => {
    setLoading(true)
    setError(null)
    try {
      const r = await myProfileRequestsList(20)
      setItems(r.items)
    } catch (err) {
      setError(err instanceof RpcError ? err.code : 'unknown_error')
    } finally {
      setLoading(false)
    }
  }, [])

  useEffect(() => { fetchItems() }, [fetchItems, refreshKey])

  const cancel = async (id: string) => {
    if (!window.confirm('Cancelar esta solicitação?')) return
    setBusyId(id)
    try {
      await myProfileRequestCancel(id)
      await fetchItems()
      onChanged?.()
    } catch (err) {
      alert(err instanceof RpcError ? `Erro: ${err.code}` : 'Erro inesperado')
    } finally {
      setBusyId(null)
    }
  }

  if (loading) {
    return (
      <div className="flex items-center gap-2 text-xs text-zinc-500">
        <Loader2 className="h-3 w-3 animate-spin" /> Carregando solicitações...
      </div>
    )
  }

  if (error) {
    return (
      <div className="text-xs text-red-700">{error}</div>
    )
  }

  if (items.length === 0) {
    return (
      <p className="text-xs text-zinc-500 italic">
        Você não tem solicitações de alteração ainda.
      </p>
    )
  }

  return (
    <div className="space-y-2">
      {items.map(r => (
        <RequestRow
          key={r.id}
          r={r}
          busy={busyId === r.id}
          onCancel={() => cancel(r.id)}
        />
      ))}
    </div>
  )
}

function RequestRow({
  r, busy, onCancel,
}: {
  r: ProfileChangeRequest
  busy: boolean
  onCancel: () => void
}) {
  const meta = STATUS_META[r.status]
  const Icon = meta.icon

  return (
    <div className="border border-zinc-100 rounded p-2.5 hover:bg-zinc-50/50">
      <div className="flex items-center gap-2 flex-wrap">
        <span className="text-sm font-medium text-zinc-900">{FIELD_LABELS[r.field]}</span>
        <span className={`text-[10px] font-semibold uppercase tracking-wide px-1.5 py-0.5 rounded inline-flex items-center gap-1 ${meta.cls}`}>
          <Icon className="h-2.5 w-2.5" />
          {meta.label}
        </span>
        <span className="text-[10px] text-zinc-500 ml-auto">
          {isoDateToBr(r.created_at.slice(0, 10))}
        </span>
        {r.status === 'pending' && (
          <button
            onClick={onCancel}
            disabled={busy}
            className="text-zinc-400 hover:text-red-600 disabled:opacity-50 ml-1"
            title="Cancelar solicitação"
          >
            {busy ? <Loader2 className="h-3.5 w-3.5 animate-spin" /> : <X className="h-3.5 w-3.5" />}
          </button>
        )}
      </div>

      {/* Resumo do valor */}
      <div className="text-xs text-zinc-600 mt-1">
        <ChangeSummary field={r.field} newValue={r.new_value} oldValue={r.old_value} />
      </div>

      {/* Motivo da rejeicao */}
      {r.status === 'rejected' && r.rejection_reason && (
        <div className="mt-1.5 text-xs text-red-700 flex items-start gap-1">
          <AlertCircle className="h-3 w-3 mt-0.5 flex-shrink-0" />
          <span><strong>Motivo:</strong> {r.rejection_reason}</span>
        </div>
      )}

      {/* Revisor (approved/rejected) */}
      {r.reviewer_name && (
        <div className="mt-1 text-[10px] text-zinc-500 flex items-center gap-1">
          <Check className="h-2.5 w-2.5" />
          Revisada por {r.reviewer_name}
          {r.reviewed_at && ' em ' + isoDateToBr(r.reviewed_at.slice(0, 10))}
        </div>
      )}
    </div>
  )
}

/** Exibe diff resumido de "de X para Y". */
function ChangeSummary({
  field, newValue, oldValue,
}: {
  field: ProfileChangeField
  newValue: Record<string, unknown>
  oldValue: Record<string, unknown> | null
}) {
  if (field === 'photo') {
    return <span className="italic">Nova foto anexada</span>
  }
  if (field === 'emergency_contact') {
    const newName = String(newValue?.name ?? '-')
    const newPhone = String(newValue?.phone ?? '-')
    return (
      <span>
        Novo contato: <strong>{newName}</strong> · {newPhone}
        {newValue?.relation ? <span className="text-zinc-500"> · {String(newValue.relation)}</span> : null}
      </span>
    )
  }
  const newVal = String(newValue?.value ?? '-')
  const oldVal = String(oldValue?.value ?? '')
  return (
    <span>
      {oldVal && <span className="line-through text-zinc-400 mr-1">{oldVal}</span>}
      <strong>{newVal}</strong>
    </span>
  )
}

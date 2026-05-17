'use client'

/**
 * R2 People · /admin/aprovacoes (Sessao G3)
 * ============================================================================
 * Fila de aprovacao de solicitacoes de alteracao de dados pessoais.
 * Permite ao RH/diretoria/super_admin aprovar ou rejeitar (com motivo).
 *
 * Acesso bloqueado para colaboradores comuns · backend retorna
 * permission_denied → frontend mostra tela 403.
 * ============================================================================
 */

import { useEffect, useState, useCallback } from 'react'
import Link from 'next/link'
import {
  Send, ChevronLeft, Loader2, AlertCircle, CheckCircle2, XCircle,
  User, Image as ImageIcon, ArrowRight,
} from 'lucide-react'

import {
  profileRequestsPendingList, profileRequestApprove, profileRequestReject,
  RpcError,
  type PendingProfileChangeRequest, type ProfileChangeField,
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

export default function AprovacoesPage() {
  const [items, setItems] = useState<PendingProfileChangeRequest[]>([])
  const [loading, setLoading] = useState(true)
  const [forbidden, setForbidden] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [busyId, setBusyId] = useState<string | null>(null)

  const fetchItems = useCallback(async () => {
    setLoading(true)
    setError(null)
    try {
      const r = await profileRequestsPendingList()
      setItems(r.items)
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

  useEffect(() => { fetchItems() }, [fetchItems])

  const approve = async (id: string) => {
    if (!window.confirm('Aprovar esta solicitação e aplicar à ficha?')) return
    setBusyId(id)
    try {
      await profileRequestApprove(id)
      await fetchItems()
    } catch (err) {
      alert(err instanceof RpcError ? `Erro: ${err.code}` : 'Erro inesperado')
    } finally {
      setBusyId(null)
    }
  }

  const reject = async (id: string) => {
    const reason = window.prompt('Motivo da rejeição (obrigatório, mín. 3 caracteres):')
    if (!reason || reason.trim().length < 3) {
      if (reason !== null) alert('Motivo precisa ter ao menos 3 caracteres.')
      return
    }
    setBusyId(id)
    try {
      await profileRequestReject(id, reason.trim())
      await fetchItems()
    } catch (err) {
      alert(err instanceof RpcError ? `Erro: ${err.code}` : 'Erro inesperado')
    } finally {
      setBusyId(null)
    }
  }

  if (forbidden) {
    return (
      <div className="max-w-md mx-auto p-12 text-center">
        <AlertCircle className="h-12 w-12 mx-auto mb-4 text-zinc-300" />
        <h1 className="text-xl font-semibold text-zinc-900 mb-2">Acesso restrito</h1>
        <p className="text-sm text-zinc-600 mb-4">
          Apenas RH, diretoria e super_admin podem revisar solicitações.
        </p>
        <Link href="/" className="text-sm text-zinc-700 hover:text-zinc-900 underline">
          Voltar para o início
        </Link>
      </div>
    )
  }

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

  return (
    <div className="max-w-4xl mx-auto p-6 space-y-4">
      <Link href="/" className="text-sm text-zinc-600 hover:text-zinc-900 inline-flex items-center gap-1">
        <ChevronLeft className="h-4 w-4" /> Início
      </Link>

      <header className="border-b border-zinc-200 pb-4">
        <h1 className="text-2xl font-semibold text-zinc-900 inline-flex items-center gap-2">
          <Send className="h-6 w-6 text-zinc-600" />
          Aprovações pendentes
        </h1>
        <p className="text-sm text-zinc-500 mt-1">
          {items.length} solicitaç{items.length === 1 ? 'ão' : 'ões'} aguardando revisão
        </p>
      </header>

      {items.length === 0 ? (
        <div className="text-center py-12 border border-zinc-200 rounded">
          <CheckCircle2 className="h-10 w-10 mx-auto mb-3 text-emerald-300" />
          <p className="text-sm text-zinc-500">Nenhuma solicitação pendente.</p>
        </div>
      ) : (
        <div className="space-y-3">
          {items.map(it => (
            <RequestCard
              key={it.id}
              item={it}
              busy={busyId === it.id}
              onApprove={() => approve(it.id)}
              onReject={() => reject(it.id)}
            />
          ))}
        </div>
      )}
    </div>
  )
}

function RequestCard({
  item, busy, onApprove, onReject,
}: {
  item: PendingProfileChangeRequest
  busy: boolean
  onApprove: () => void
  onReject: () => void
}) {
  return (
    <div className="border border-zinc-200 rounded-lg p-4">
      <div className="flex items-start gap-3">
        <div className="w-10 h-10 rounded-full bg-zinc-100 flex items-center justify-center flex-shrink-0">
          <User className="h-5 w-5 text-zinc-600" />
        </div>
        <div className="flex-1 min-w-0">
          <div className="flex items-center gap-2 flex-wrap">
            <span className="text-sm font-medium text-zinc-900">{item.employee_name}</span>
            {item.employee_job_title && (
              <span className="text-xs text-zinc-500">· {item.employee_job_title}</span>
            )}
            <span className="text-[10px] text-zinc-400 ml-auto">
              {isoDateToBr(item.created_at.slice(0, 10))}
            </span>
          </div>
          <div className="mt-1.5">
            <span className="text-[10px] font-semibold uppercase tracking-wider text-zinc-500">
              Campo:
            </span>{' '}
            <span className="text-sm font-medium text-zinc-900">{FIELD_LABELS[item.field]}</span>
          </div>

          {/* Diff */}
          <div className="mt-2 border border-zinc-100 rounded p-2.5 bg-zinc-50/50">
            <Diff item={item} />
          </div>

          {/* Acoes */}
          <div className="mt-3 flex gap-2">
            <button
              onClick={onApprove}
              disabled={busy}
              className="px-3 py-1.5 text-xs font-medium text-white bg-emerald-700 hover:bg-emerald-800 disabled:opacity-50 rounded inline-flex items-center gap-1"
            >
              {busy ? <Loader2 className="h-3 w-3 animate-spin" /> : <CheckCircle2 className="h-3 w-3" />}
              Aprovar
            </button>
            <button
              onClick={onReject}
              disabled={busy}
              className="px-3 py-1.5 text-xs font-medium text-white bg-red-700 hover:bg-red-800 disabled:opacity-50 rounded inline-flex items-center gap-1"
            >
              <XCircle className="h-3 w-3" />
              Rejeitar
            </button>
          </div>
        </div>
      </div>
    </div>
  )
}

function Diff({ item }: { item: PendingProfileChangeRequest }) {
  if (item.field === 'photo') {
    return (
      <div className="flex items-center gap-2 text-xs">
        <ImageIcon className="h-3.5 w-3.5 text-zinc-500" />
        <span className="text-zinc-600">
          Nova foto anexada:
        </span>
        <code className="text-[10px] bg-white px-1.5 py-0.5 rounded border border-zinc-200">
          {item.pending_photo_path}
        </code>
      </div>
    )
  }

  if (item.field === 'emergency_contact') {
    const newName  = String(item.new_value?.name ?? '-')
    const newPhone = String(item.new_value?.phone ?? '-')
    const newRel   = String(item.new_value?.relation ?? '')
    const oldName  = String(item.old_value?.name ?? '')
    const oldPhone = String(item.old_value?.phone ?? '')
    return (
      <div className="text-xs space-y-1">
        <div>
          {oldName && <span className="text-zinc-400 line-through mr-2">{oldName}</span>}
          <strong className="text-zinc-900">{newName}</strong>
        </div>
        <div>
          {oldPhone && <span className="text-zinc-400 line-through mr-2">{oldPhone}</span>}
          <strong className="text-zinc-900">{newPhone}</strong>
        </div>
        {newRel && <div className="text-zinc-600">Parentesco: {newRel}</div>}
      </div>
    )
  }

  const newVal = String(item.new_value?.value ?? '-')
  const oldVal = String(item.old_value?.value ?? '')

  return (
    <div className="text-xs flex items-center gap-2 flex-wrap">
      {oldVal && (
        <>
          <span className="text-zinc-400 line-through">{oldVal}</span>
          <ArrowRight className="h-3 w-3 text-zinc-400 flex-shrink-0" />
        </>
      )}
      <strong className="text-zinc-900">{newVal}</strong>
    </div>
  )
}

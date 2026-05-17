'use client'

/**
 * R2 People · /meus-reconhecimentos (Sessao G2)
 * ============================================================================
 * Pagina pessoal de reconhecimentos com 2 abas:
 *   - Recebidos: usa Employees.gestaoSummary do proprio employee_id
 *   - Enviados:  usa mySentRecognitions (RPC G2)
 *
 * Permissao: qualquer authenticated ve apenas o que e seu (RPCs filtram).
 * ============================================================================
 */

import { useEffect, useState, useCallback } from 'react'
import Link from 'next/link'
import {
  Award, ArrowDownRight, ArrowUpRight, Loader2, AlertCircle,
  Lock, ChevronLeft,
} from 'lucide-react'

import {
  myJourney, mySentRecognitions, Employees, RpcError,
  type SentRecognition, type GestaoRecognition, type GestaoSummary,
} from '@/lib/r2'
import { isoDateToBr } from '@/lib/validation'

type Tab = 'received' | 'sent'

export default function MeusReconhecimentosPage() {
  const [tab, setTab] = useState<Tab>('received')
  const [received, setReceived] = useState<GestaoRecognition[] | null>(null)
  const [sent, setSent] = useState<SentRecognition[] | null>(null)
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)

  const fetchAll = useCallback(async () => {
    setLoading(true)
    setError(null)
    try {
      // myJourney + gestaoSummary (se tem ficha) + mySentRecognitions
      const j = await myJourney()
      const sentP = mySentRecognitions(10)
      let gestao: GestaoSummary | null = null
      if (j.identity.employee_id) {
        try {
          gestao = await Employees.gestaoSummary(j.identity.employee_id)
        } catch {
          gestao = null
        }
      }
      const sentR = await sentP
      setReceived(gestao?.recognitions ?? [])
      setSent(sentR.items)
    } catch (err) {
      setError(err instanceof RpcError ? err.code : 'unknown_error')
    } finally {
      setLoading(false)
    }
  }, [])

  useEffect(() => { fetchAll() }, [fetchAll])

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
      <Link href="/minha-jornada" className="text-sm text-zinc-600 hover:text-zinc-900 inline-flex items-center gap-1">
        <ChevronLeft className="h-4 w-4" /> Minha jornada
      </Link>

      <header className="border-b border-zinc-200 pb-4">
        <h1 className="text-2xl font-semibold text-zinc-900 inline-flex items-center gap-2">
          <Award className="h-6 w-6 text-amber-600" />
          Meus reconhecimentos
        </h1>
        <p className="text-sm text-zinc-500 mt-1">
          {tab === 'received'
            ? `${received?.length ?? 0} recebido${(received?.length ?? 0) === 1 ? '' : 's'}`
            : `${sent?.length ?? 0} enviado${(sent?.length ?? 0) === 1 ? '' : 's'} (10 mais recentes)`}
        </p>
      </header>

      {/* Tabs */}
      <div className="flex gap-1 border-b border-zinc-200">
        <TabButton
          icon={ArrowDownRight}
          label="Recebidos"
          count={received?.length ?? 0}
          active={tab === 'received'}
          onClick={() => setTab('received')}
        />
        <TabButton
          icon={ArrowUpRight}
          label="Enviados"
          count={sent?.length ?? 0}
          active={tab === 'sent'}
          onClick={() => setTab('sent')}
        />
      </div>

      {/* Content */}
      <div>
        {tab === 'received' ? (
          <ReceivedList items={received ?? []} />
        ) : (
          <SentList items={sent ?? []} />
        )}
      </div>
    </div>
  )
}

function TabButton({
  icon: Icon, label, count, active, onClick,
}: {
  icon: React.ComponentType<{ className?: string }>
  label: string
  count: number
  active: boolean
  onClick: () => void
}) {
  return (
    <button
      onClick={onClick}
      className={`px-3 py-2 text-sm font-medium inline-flex items-center gap-1.5 border-b-2 transition ${
        active
          ? 'text-zinc-900 border-zinc-900'
          : 'text-zinc-500 border-transparent hover:text-zinc-700'
      }`}
    >
      <Icon className="h-3.5 w-3.5" />
      {label}
      <span className={`ml-1 text-[10px] px-1.5 py-0.5 rounded ${
        active ? 'bg-zinc-900 text-white' : 'bg-zinc-100 text-zinc-600'
      }`}>
        {count}
      </span>
    </button>
  )
}

function ReceivedList({ items }: { items: GestaoRecognition[] }) {
  if (items.length === 0) {
    return <EmptyState msg="Você ainda não recebeu reconhecimentos." />
  }
  return (
    <div className="space-y-2">
      {items.map(r => (
        <div key={r.id} className="border border-zinc-100 rounded p-3 bg-zinc-50/30">
          <div className="flex items-start gap-2">
            <Award className="h-4 w-4 text-amber-600 mt-0.5 flex-shrink-0" />
            <div className="flex-1 min-w-0">
              <p className="text-sm text-zinc-900">{r.message}</p>
              <div className="text-[10px] text-zinc-500 mt-1 flex gap-2 flex-wrap items-center">
                {r.sender_name && <span>de {r.sender_name}</span>}
                <span>· {isoDateToBr(r.created_at.slice(0, 10))}</span>
                {r.is_private && (
                  <span className="inline-flex items-center gap-0.5 text-amber-700">
                    <Lock className="h-2.5 w-2.5" /> privado
                  </span>
                )}
              </div>
            </div>
          </div>
        </div>
      ))}
    </div>
  )
}

function SentList({ items }: { items: SentRecognition[] }) {
  if (items.length === 0) {
    return <EmptyState msg="Você ainda não enviou reconhecimentos." />
  }
  return (
    <div className="space-y-2">
      {items.map(r => {
        const row = (
          <div className="border border-zinc-100 rounded p-3 hover:bg-zinc-50/50 transition group">
            <div className="flex items-start gap-2">
              <Award className="h-4 w-4 text-amber-600 mt-0.5 flex-shrink-0" />
              <div className="flex-1 min-w-0">
                <div className="flex items-center gap-1 mb-0.5 flex-wrap">
                  <span className="text-xs text-zinc-500">para</span>
                  <span className="text-sm font-medium text-zinc-900 truncate">
                    {r.recipient_name ?? '-'}
                  </span>
                  {r.recipient_job_title && (
                    <span className="text-[10px] text-zinc-500">· {r.recipient_job_title}</span>
                  )}
                </div>
                <p className="text-sm text-zinc-900">{r.message}</p>
                <div className="text-[10px] text-zinc-500 mt-1 flex gap-2 flex-wrap items-center">
                  <span>{isoDateToBr(r.created_at.slice(0, 10))}</span>
                  {r.is_private && (
                    <span className="inline-flex items-center gap-0.5 text-amber-700">
                      <Lock className="h-2.5 w-2.5" /> privado
                    </span>
                  )}
                  {r.reactions_count > 0 && (
                    <span>· {r.reactions_count} reação{r.reactions_count === 1 ? '' : 'es'}</span>
                  )}
                </div>
              </div>
            </div>
          </div>
        )
        if (r.recipient_employee_id) {
          return (
            <Link key={r.id} href={`/pessoas/${r.recipient_employee_id}`} className="block">
              {row}
            </Link>
          )
        }
        return <div key={r.id}>{row}</div>
      })}
    </div>
  )
}

function EmptyState({ msg }: { msg: string }) {
  return (
    <div className="text-center py-12 border border-zinc-200 rounded">
      <AlertCircle className="h-10 w-10 mx-auto mb-3 text-zinc-300" />
      <p className="text-sm text-zinc-500">{msg}</p>
    </div>
  )
}

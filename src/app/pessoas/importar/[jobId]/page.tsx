'use client'

/**
 * R2 People · /pessoas/importar/[jobId]
 * ============================================================================
 * Tela de revisao lote a lote de um job de OCR.
 *
 * Comportamento:
 *   - Polling de 3s enquanto o job esta em running/pending
 *   - Quando completed/reviewing, mostra os items extraidos para revisao
 *   - Cada item exibe: pagina origem, nome, CPF, cargo, score de confianca,
 *     alertas do parser
 *   - RH pode:
 *       · Editar campos do item (Pencil) · marca como `edited`
 *       · Aprovar individual (CheckCircle) · cria registro em employees
 *       · Rejeitar individual (XCircle) · com motivo opcional
 *       · Aprovar todos pendentes (botao do topo)
 *       · Arquivar o job (apos revisao concluida)
 *
 * Filtros: status (todos / pendentes / aprovados / rejeitados / duplicatas).
 *
 * Indicador de confianca:
 *   verde   >= 80%
 *   amarelo >= 50%
 *   vermelho < 50%
 * ============================================================================
 */

import { useEffect, useState, useCallback, useMemo } from 'react'
import { useParams } from 'next/navigation'
import Link from 'next/link'
import {
  ChevronLeft, Loader2, AlertTriangle, CheckCircle2, XCircle,
  Pencil, Save, X as XIcon, ChevronDown, ChevronRight,
  Archive, RotateCcw, FileText, Eye, Users as UsersIcon, Search,
} from 'lucide-react'

import {
  Imports, RpcError,
  type ImportJob, type ImportItem, type ImportItemStatus,
  type EmployeePayload,
} from '@/lib/r2'

import { isoDateToBr } from '@/lib/validation'
import { DownloadPdfButton } from '@/components/imports/DownloadPdfButton'
import { PdfPreviewModal } from '@/components/imports/PdfPreviewModal'

const POLL_INTERVAL_MS = 3000

export default function ImportarReviewPage() {
  const params = useParams<{ jobId: string }>()
  const jobId = params.jobId

  const [job, setJob] = useState<ImportJob | null>(null)
  const [items, setItems] = useState<ImportItem[]>([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)
  const [statusFilter, setStatusFilter] = useState<ImportItemStatus | 'all'>('all')
  const [busyAction, setBusyAction] = useState<string | null>(null)
  // E6 · pagina do PDF a previewar · null = modal fechado
  const [previewPage, setPreviewPage] = useState<number | null>(null)

  const fetchJobAndItems = useCallback(async () => {
    try {
      const [jobR, itemsR] = await Promise.all([
        Imports.get(jobId),
        Imports.items.list(jobId, {
          status: statusFilter === 'all' ? undefined : statusFilter,
          limit: 200,
        }),
      ])
      setJob(jobR.job)
      setItems(itemsR.items)
      setError(null)
    } catch (err) {
      setError(err instanceof RpcError ? err.code : 'unknown_error')
    } finally {
      setLoading(false)
    }
  }, [jobId, statusFilter])

  useEffect(() => { fetchJobAndItems() }, [fetchJobAndItems])

  // Polling enquanto o job esta processando
  useEffect(() => {
    if (!job) return
    if (job.status !== 'pending' && job.status !== 'running') return
    const handle = setInterval(fetchJobAndItems, POLL_INTERVAL_MS)
    return () => clearInterval(handle)
  }, [job, fetchJobAndItems])

  const handleApprove = async (item: ImportItem) => {
    setBusyAction(item.id)
    try {
      await Imports.items.approve(item.id)
      await fetchJobAndItems()
    } catch (err) {
      alert(`Erro ao aprovar: ${err instanceof RpcError ? err.code : 'unknown_error'}`)
    } finally {
      setBusyAction(null)
    }
  }

  const handleReject = async (item: ImportItem) => {
    const reason = prompt('Motivo da rejeição (opcional):')
    if (reason === null) return  // usuario cancelou
    setBusyAction(item.id)
    try {
      await Imports.items.reject(item.id, reason || undefined)
      await fetchJobAndItems()
    } catch (err) {
      alert(`Erro ao rejeitar: ${err instanceof RpcError ? err.code : 'unknown_error'}`)
    } finally {
      setBusyAction(null)
    }
  }

  const handleSaveEdit = async (item: ImportItem, patch: Partial<EmployeePayload>) => {
    setBusyAction(item.id)
    try {
      await Imports.items.update(item.id, patch)
      await fetchJobAndItems()
    } catch (err) {
      alert(`Erro ao salvar edição: ${err instanceof RpcError ? err.code : 'unknown_error'}`)
    } finally {
      setBusyAction(null)
    }
  }

  const handleApproveAll = async () => {
    if (!confirm(`Aprovar todos os ${counts.pending} itens pendentes? Os que ja existem no sistema serão marcados como duplicatas.`)) return
    setBusyAction('all')
    try {
      const r = await Imports.approveAll(jobId)
      alert(`Aprovação em lote: ${r.approved} criadas, ${r.duplicates} duplicatas, ${r.errors} erros.`)
      await fetchJobAndItems()
    } catch (err) {
      alert(`Erro: ${err instanceof RpcError ? err.code : 'unknown_error'}`)
    } finally {
      setBusyAction(null)
    }
  }

  const handleArchive = async () => {
    if (!confirm('Arquivar este job? Os itens aprovados continuam visíveis em /pessoas, mas o job sai da lista padrão.')) return
    setBusyAction('archive')
    try {
      await Imports.archive(jobId)
      await fetchJobAndItems()
    } catch (err) {
      alert(`Erro: ${err instanceof RpcError ? err.code : 'unknown_error'}`)
    } finally {
      setBusyAction(null)
    }
  }

  const counts = useMemo(() => {
    return {
      total: items.length,
      pending: items.filter(i => i.status === 'pending' || i.status === 'edited').length,
      approved: items.filter(i => i.status === 'approved').length,
      rejected: items.filter(i => i.status === 'rejected').length,
      duplicate: items.filter(i => i.status === 'duplicate').length,
    }
  }, [items])

  if (loading) {
    return (
      <div className="flex items-center justify-center min-h-[60vh]">
        <Loader2 className="h-6 w-6 animate-spin text-zinc-400" />
      </div>
    )
  }

  if (error || !job) {
    return (
      <div className="max-w-2xl mx-auto p-8">
        <Link href="/pessoas/importar" className="text-sm text-zinc-600 hover:text-zinc-900 inline-flex items-center gap-1 mb-4">
          <ChevronLeft className="h-4 w-4" /> Importações
        </Link>
        <div className="border border-red-200 bg-red-50 rounded-md p-4 text-red-900">
          <strong>Erro:</strong> {error || 'Job não encontrado'}
        </div>
      </div>
    )
  }

  const isProcessing = job.status === 'pending' || job.status === 'running'
  const canReview = job.status === 'completed' || job.status === 'reviewing'

  return (
    <div className="max-w-6xl mx-auto p-6 space-y-4">
      <Link href="/pessoas/importar" className="text-sm text-zinc-600 hover:text-zinc-900 inline-flex items-center gap-1">
        <ChevronLeft className="h-4 w-4" /> Importações
      </Link>

      {/* Header */}
      <div className="bg-white border border-zinc-200 rounded-lg p-5">
        <div className="flex items-start justify-between gap-4 flex-wrap">
          <div className="flex-1 min-w-0">
            <h1 className="text-xl font-semibold text-zinc-900 truncate flex items-center gap-2">
              <FileText className="h-5 w-5 text-zinc-600" />
              {job.source_file_name}
            </h1>
            <div className="text-sm text-zinc-500 mt-1 flex items-center gap-3 flex-wrap">
              {job.source_pages_total != null && <span>{job.source_pages_total} páginas</span>}
              <span>·</span>
              <span>{job.items_total} fichas extraídas</span>
              <span>·</span>
              <span>Status: <strong className="text-zinc-700">{job.status}</strong></span>
            </div>
          </div>

          {/* Actions */}
          <div className="flex gap-2">
            {canReview && counts.pending > 0 && (
              <button
                onClick={handleApproveAll}
                disabled={busyAction === 'all'}
                className="px-3 py-1.5 text-sm font-medium text-white bg-emerald-700 hover:bg-emerald-800 disabled:opacity-50 rounded inline-flex items-center gap-1.5"
              >
                {busyAction === 'all' && <Loader2 className="h-3.5 w-3.5 animate-spin" />}
                <CheckCircle2 className="h-3.5 w-3.5" />
                Aprovar todos ({counts.pending})
              </button>
            )}
            <DownloadPdfButton jobId={job.id} />
            {(job.status === 'completed' || job.status === 'reviewing') && (
              <button
                onClick={handleArchive}
                disabled={busyAction === 'archive'}
                className="px-3 py-1.5 text-sm font-medium text-zinc-700 hover:bg-zinc-100 border border-zinc-200 rounded inline-flex items-center gap-1.5"
              >
                {busyAction === 'archive' && <Loader2 className="h-3.5 w-3.5 animate-spin" />}
                <Archive className="h-3.5 w-3.5" />
                Arquivar
              </button>
            )}
          </div>
        </div>

        {/* Progress bar */}
        {isProcessing && job.source_pages_total != null && (
          <div className="mt-4">
            <div className="text-xs text-zinc-500 mb-1 flex justify-between">
              <span>Processando OCR...</span>
              <span>{job.pages_processed} / {job.source_pages_total} páginas</span>
            </div>
            <div className="h-2 bg-zinc-100 rounded-full overflow-hidden">
              <div
                className="h-full bg-zinc-700 transition-all duration-500"
                style={{ width: `${(job.pages_processed / Math.max(job.source_pages_total, 1)) * 100}%` }}
              />
            </div>
            <div className="text-xs text-zinc-400 mt-1 italic">
              Atualização automática a cada 3 segundos. Você pode fechar e voltar quando quiser.
            </div>
          </div>
        )}

        {/* Errors do worker */}
        {job.error_log.length > 0 && (
          <div className="mt-3 border border-amber-200 bg-amber-50 rounded p-2 text-xs text-amber-900">
            <strong>{job.error_log.length}</strong> aviso(s) durante o OCR:
            <ul className="mt-1 space-y-0.5 max-h-24 overflow-y-auto">
              {job.error_log.slice(0, 5).map((e, i) => (
                <li key={i} className="font-mono">
                  {e.page ? `pág ${e.page}: ` : ''}{e.message}
                </li>
              ))}
              {job.error_log.length > 5 && (
                <li className="text-amber-700 italic">e mais {job.error_log.length - 5}...</li>
              )}
            </ul>
          </div>
        )}
      </div>

      {/* Filtros */}
      {canReview && (
        <div className="flex gap-1 items-center bg-zinc-100 rounded p-1 w-fit">
          {([
            ['all',      `Todos (${counts.total})`],
            ['pending',  `Pendentes (${counts.pending})`],
            ['approved', `Aprovadas (${counts.approved})`],
            ['rejected', `Rejeitadas (${counts.rejected})`],
            ['duplicate', `Duplicatas (${counts.duplicate})`],
          ] as const).map(([val, lbl]) => (
            <button
              key={val}
              onClick={() => setStatusFilter(val as ImportItemStatus | 'all')}
              className={[
                'px-3 py-1.5 text-xs font-medium rounded transition',
                statusFilter === val
                  ? 'bg-white text-zinc-900 shadow-sm'
                  : 'text-zinc-600 hover:text-zinc-900',
              ].join(' ')}
            >
              {lbl}
            </button>
          ))}
        </div>
      )}

      {/* Lista de items */}
      {canReview ? (
        items.length === 0 ? (
          <div className="text-center py-12 text-zinc-500">
            <UsersIcon className="h-12 w-12 mx-auto mb-3 text-zinc-300" />
            <p className="text-sm">Nenhum item com este filtro</p>
          </div>
        ) : (
          <div className="space-y-2">
            {items.map(item => (
              <ItemCard
                key={item.id}
                item={item}
                busy={busyAction === item.id}
                onApprove={() => handleApprove(item)}
                onReject={() => handleReject(item)}
                onSave={(patch) => handleSaveEdit(item, patch)}
                onPreview={() => setPreviewPage(item.page_number)}
              />
            ))}
          </div>
        )
      ) : isProcessing ? (
        <div className="text-center py-12 text-zinc-500">
          <Loader2 className="h-8 w-8 mx-auto mb-3 animate-spin" />
          <p className="text-sm">Aguardando o worker terminar o OCR...</p>
        </div>
      ) : (
        <div className="text-center py-12 text-zinc-500">
          <Archive className="h-8 w-8 mx-auto mb-3 text-zinc-300" />
          <p className="text-sm">Job {job.status}.</p>
        </div>
      )}

      {/* E6 · Preview do PDF original */}
      {previewPage != null && (
        <PdfPreviewModal
          jobId={jobId}
          initialPage={previewPage}
          onClose={() => setPreviewPage(null)}
        />
      )}
    </div>
  )
}

// ============================================================================
// ItemCard
// ============================================================================

function ItemCard({
  item, busy, onApprove, onReject, onSave, onPreview,
}: {
  item: ImportItem
  busy: boolean
  onApprove: () => void
  onReject: () => void
  onSave: (patch: Partial<EmployeePayload>) => Promise<void>
  onPreview: () => void
}) {
  const [expanded, setExpanded] = useState(false)
  const [editing, setEditing] = useState(false)
  const [editValues, setEditValues] = useState<Partial<EmployeePayload>>({})

  const startEdit = () => {
    setEditValues({
      full_name: item.parsed_payload.full_name,
      cpf: item.parsed_payload.cpf,
      job_title: item.parsed_payload.job_title,
      hire_date: item.parsed_payload.hire_date,
      phone_mobile: item.parsed_payload.phone_mobile,
      birth_date: item.parsed_payload.birth_date,
    })
    setEditing(true)
    setExpanded(true)
  }

  const saveEdit = async () => {
    // So envia o que mudou
    const patch: Partial<EmployeePayload> = {}
    for (const [k, v] of Object.entries(editValues)) {
      const orig = (item.parsed_payload as Record<string, unknown>)[k]
      if (v !== orig) (patch as Record<string, unknown>)[k] = v
    }
    if (Object.keys(patch).length === 0) {
      setEditing(false)
      return
    }
    await onSave(patch)
    setEditing(false)
  }

  const canAct = item.status === 'pending' || item.status === 'edited'
  const isApproved = item.status === 'approved'
  const isRejected = item.status === 'rejected'
  const isDuplicate = item.status === 'duplicate'

  return (
    <div className={[
      'bg-white border rounded-lg overflow-hidden',
      isApproved ? 'border-emerald-200' : isRejected ? 'border-red-200 opacity-70'
        : isDuplicate ? 'border-amber-200' : 'border-zinc-200',
    ].join(' ')}>
      <div className="px-4 py-3 flex items-center gap-3">
        <button
          onClick={() => setExpanded(!expanded)}
          className="text-zinc-400 hover:text-zinc-700"
          aria-label="Expandir"
        >
          {expanded ? <ChevronDown className="h-4 w-4" /> : <ChevronRight className="h-4 w-4" />}
        </button>

        {/* Confidence dot */}
        <ConfidenceDot score={item.confidence_score} />

        <div className="flex-1 min-w-0">
          <div className="flex items-center gap-2 flex-wrap">
            <span className="font-medium text-sm text-zinc-900 truncate">
              {item.full_name || '(sem nome)'}
            </span>
            <ItemStatusBadge status={item.status} />
            {item.parser_alerts.length > 0 && (
              <span
                className="text-[10px] font-semibold uppercase tracking-wide px-1.5 py-0.5 rounded bg-amber-100 text-amber-800"
                title={item.parser_alerts.join(', ')}
              >
                {item.parser_alerts.length} alerta{item.parser_alerts.length === 1 ? '' : 's'}
              </span>
            )}
          </div>
          <div className="text-xs text-zinc-500 mt-0.5 flex gap-3 flex-wrap">
            {item.cpf && <span className="font-mono">{item.cpf}</span>}
            {item.job_title && <span>· {item.job_title}</span>}
            {item.hire_date && <span>· admissão {isoDateToBr(item.hire_date)}</span>}
            {item.termination_date && <span className="text-red-700">· saída {isoDateToBr(item.termination_date)}</span>}
            <span>· pág {item.page_number}</span>
          </div>
        </div>

        {/* Lupa · sempre disponivel (mesmo apos aprovar/rejeitar, para reconferir) */}
        <button
          onClick={onPreview}
          className="p-1.5 hover:bg-zinc-100 rounded text-zinc-600 flex-shrink-0"
          title={`Ver página ${item.page_number} do PDF original`}
        >
          <Search className="h-4 w-4" />
        </button>

        {/* Acoes */}
        {canAct && !editing && (
          <div className="flex gap-1">
            <button
              onClick={startEdit}
              disabled={busy}
              className="p-1.5 hover:bg-zinc-100 rounded text-zinc-600"
              title="Editar campos antes de aprovar"
            >
              <Pencil className="h-4 w-4" />
            </button>
            <button
              onClick={onApprove}
              disabled={busy}
              className="px-2 py-1.5 text-xs font-medium text-white bg-emerald-700 hover:bg-emerald-800 disabled:opacity-50 rounded inline-flex items-center gap-1"
              title="Aprovar e criar ficha"
            >
              {busy ? <Loader2 className="h-3 w-3 animate-spin" /> : <CheckCircle2 className="h-3 w-3" />}
              Aprovar
            </button>
            <button
              onClick={onReject}
              disabled={busy}
              className="px-2 py-1.5 text-xs font-medium text-red-700 hover:bg-red-50 border border-red-200 disabled:opacity-50 rounded inline-flex items-center gap-1"
              title="Rejeitar"
            >
              <XCircle className="h-3 w-3" />
              Rejeitar
            </button>
          </div>
        )}

        {/* Aprovado · link para a ficha criada */}
        {isApproved && item.employee_id && (
          <Link
            href={`/pessoas/${item.employee_id}`}
            className="px-2 py-1.5 text-xs font-medium text-emerald-700 hover:bg-emerald-50 border border-emerald-200 rounded inline-flex items-center gap-1"
          >
            <Eye className="h-3 w-3" />
            Ver ficha
          </Link>
        )}

        {/* Duplicata · link para a ficha existente */}
        {isDuplicate && item.duplicate_of && (
          <Link
            href={`/pessoas/${item.duplicate_of}`}
            className="px-2 py-1.5 text-xs font-medium text-amber-800 hover:bg-amber-50 border border-amber-200 rounded inline-flex items-center gap-1"
          >
            <Eye className="h-3 w-3" />
            Ver existente
          </Link>
        )}
      </div>

      {/* Expandido · payload completo + edit form */}
      {expanded && (
        <div className="border-t border-zinc-100 px-4 py-3 bg-zinc-50/50">
          {editing ? (
            <EditForm
              values={editValues}
              onChange={setEditValues}
              onCancel={() => setEditing(false)}
              onSave={saveEdit}
              busy={busy}
            />
          ) : (
            <>
              {item.parser_alerts.length > 0 && (
                <div className="mb-3 text-xs text-amber-800 flex flex-wrap gap-1">
                  <strong>Alertas:</strong>
                  {item.parser_alerts.map((a, i) => (
                    <code key={i} className="font-mono bg-amber-100 px-1 rounded">{a}</code>
                  ))}
                </div>
              )}
              <PayloadGrid payload={item.parsed_payload} />
              {item.rejection_reason && (
                <div className="mt-3 text-xs text-red-700">
                  <strong>Motivo da rejeição:</strong> {item.rejection_reason}
                </div>
              )}
            </>
          )}
        </div>
      )}
    </div>
  )
}

// ============================================================================
// Helpers de UI
// ============================================================================

function ConfidenceDot({ score }: { score: number | null }) {
  let color = 'bg-zinc-300', label = 'sem score'
  if (score != null) {
    if (score >= 80) { color = 'bg-emerald-500'; label = `confiança ${score}%` }
    else if (score >= 50) { color = 'bg-amber-500'; label = `confiança ${score}%` }
    else { color = 'bg-red-500'; label = `confiança baixa ${score}%` }
  }
  return (
    <div className={`w-2.5 h-2.5 rounded-full ${color} flex-shrink-0`} title={label} />
  )
}

function ItemStatusBadge({ status }: { status: ImportItemStatus }) {
  const label = {
    pending: 'Pendente',
    approved: 'Aprovada',
    rejected: 'Rejeitada',
    duplicate: 'Duplicata',
    edited: 'Editada',
  }[status]
  const cls = {
    pending:   'bg-zinc-100 text-zinc-700',
    approved:  'bg-emerald-100 text-emerald-800',
    rejected:  'bg-red-100 text-red-800',
    duplicate: 'bg-amber-100 text-amber-800',
    edited:    'bg-blue-100 text-blue-800',
  }[status]
  return (
    <span className={`text-[10px] font-semibold uppercase tracking-wide px-1.5 py-0.5 rounded ${cls}`}>
      {label}
    </span>
  )
}

function PayloadGrid({ payload }: { payload: EmployeePayload }) {
  const entries = useMemo(() => Object.entries(payload as Record<string, unknown>)
    .filter(([, v]) => v !== null && v !== undefined && v !== '')
    .sort(([a], [b]) => a.localeCompare(b)), [payload])

  return (
    <div className="grid grid-cols-2 sm:grid-cols-3 lg:grid-cols-4 gap-x-4 gap-y-1.5 text-xs">
      {entries.map(([k, v]) => (
        <div key={k}>
          <div className="text-[10px] uppercase tracking-wider text-zinc-500 font-semibold">
            {k}
          </div>
          <div className="text-zinc-900 truncate" title={String(v)}>
            {String(v)}
          </div>
        </div>
      ))}
    </div>
  )
}

function EditForm({
  values, onChange, onCancel, onSave, busy,
}: {
  values: Partial<EmployeePayload>
  onChange: (v: Partial<EmployeePayload>) => void
  onCancel: () => void
  onSave: () => void
  busy: boolean
}) {
  const set = (k: keyof EmployeePayload, v: string) => onChange({ ...values, [k]: v })

  return (
    <div className="space-y-2">
      <div className="grid grid-cols-1 sm:grid-cols-2 gap-2">
        <InputRow label="Nome completo" value={values.full_name ?? ''} onChange={v => set('full_name', v)} />
        <InputRow label="CPF" value={values.cpf ?? ''} onChange={v => set('cpf', v)} />
        <InputRow label="Cargo" value={values.job_title ?? ''} onChange={v => set('job_title', v)} />
        <InputRow label="Data admissão (AAAA-MM-DD)" value={values.hire_date ?? ''} onChange={v => set('hire_date', v)} />
        <InputRow label="Telefone celular" value={values.phone_mobile ?? ''} onChange={v => set('phone_mobile', v)} />
        <InputRow label="Data nascimento (AAAA-MM-DD)" value={values.birth_date ?? ''} onChange={v => set('birth_date', v)} />
      </div>
      <div className="flex gap-2 justify-end pt-2">
        <button
          onClick={onCancel}
          disabled={busy}
          className="px-3 py-1.5 text-xs font-medium text-zinc-700 hover:bg-zinc-100 border border-zinc-200 rounded inline-flex items-center gap-1"
        >
          <XIcon className="h-3 w-3" /> Cancelar
        </button>
        <button
          onClick={onSave}
          disabled={busy}
          className="px-3 py-1.5 text-xs font-medium text-white bg-zinc-900 hover:bg-zinc-800 disabled:opacity-50 rounded inline-flex items-center gap-1"
        >
          {busy ? <Loader2 className="h-3 w-3 animate-spin" /> : <Save className="h-3 w-3" />}
          Salvar edição
        </button>
      </div>
    </div>
  )
}

function InputRow({ label, value, onChange }: { label: string; value: string; onChange: (v: string) => void }) {
  return (
    <div>
      <label className="block text-[10px] uppercase tracking-wider text-zinc-500 font-semibold mb-0.5">{label}</label>
      <input
        type="text"
        value={value}
        onChange={(e) => onChange(e.target.value)}
        className="w-full px-2 py-1 text-xs border border-zinc-200 rounded focus:outline-none focus:ring-2 focus:ring-zinc-300"
      />
    </div>
  )
}

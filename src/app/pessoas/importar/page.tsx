'use client'

/**
 * R2 People · /pessoas/importar
 * ============================================================================
 * Tela inicial de importacao. Mostra:
 *   - Bloco de upload para iniciar um novo job
 *   - Lista de jobs anteriores com status + contadores
 *   - Botao para revisar um job em andamento (pending review)
 *
 * Fluxo de upload:
 *   1. Usuario seleciona PDF
 *   2. Frontend chama Imports.create(file_name, file_size, pages_total)
 *      e recebe { id, worker_token }
 *   3. Frontend faz POST multipart para o worker FastAPI em /upload com
 *      o arquivo + id + token
 *   4. Worker comeca a processar em background
 *   5. Frontend redireciona para /pessoas/importar/[jobId] que faz polling
 *      do progresso e mostra a tela de revisao quando terminar
 * ============================================================================
 */

import { useEffect, useState, useCallback } from 'react'
import { useRouter } from 'next/navigation'
import Link from 'next/link'
import {
  ChevronLeft, Upload, FileText, Loader2, AlertTriangle,
  CheckCircle2, XCircle, Clock, Archive, ChevronRight, RefreshCw,
} from 'lucide-react'

import {
  Imports, RpcError,
  type ImportJob, type ImportJobStatus,
} from '@/lib/r2'

// Em Next.js, `NEXT_PUBLIC_*` é injetado em build-time; declarado via next-env.d.ts.
// Aqui usamos `globalThis` para evitar dependência de @types/node neste arquivo.
const WORKER_URL =
  (typeof globalThis !== 'undefined'
    && (globalThis as { process?: { env?: Record<string, string | undefined> } }).process
    ?.env?.NEXT_PUBLIC_OCR_WORKER_URL)
  || 'http://localhost:8787'

export default function ImportarPage() {
  const router = useRouter()
  const [jobs, setJobs] = useState<ImportJob[]>([])
  const [loading, setLoading] = useState(true)
  const [uploading, setUploading] = useState(false)
  const [error, setError] = useState<string | null>(null)

  const fetchJobs = useCallback(async () => {
    try {
      const r = await Imports.list({ limit: 30 })
      setJobs(r.jobs)
    } catch (err) {
      setError(err instanceof RpcError ? err.code : 'unknown_error')
    } finally {
      setLoading(false)
    }
  }, [])

  useEffect(() => { fetchJobs() }, [fetchJobs])

  // Refresh automatico a cada 5s se algum job estiver em andamento
  useEffect(() => {
    const hasRunning = jobs.some(j => j.status === 'pending' || j.status === 'running')
    if (!hasRunning) return
    const handle = setInterval(fetchJobs, 5000)
    return () => clearInterval(handle)
  }, [jobs, fetchJobs])

  const handleUpload = async (file: File) => {
    setError(null)
    setUploading(true)
    try {
      // 1. Cria o job no backend
      const { id, worker_token } = await Imports.create({
        fileName: file.name,
        fileSize: file.size,
      })

      // 2. Envia o PDF para o worker
      const formData = new FormData()
      formData.append('file', file)
      formData.append('job_id', id)
      formData.append('worker_token', worker_token)

      const resp = await fetch(`${WORKER_URL}/upload`, {
        method: 'POST',
        body: formData,
      })

      if (!resp.ok) {
        const text = await resp.text().catch(() => resp.statusText)
        throw new Error(`Worker recusou o upload (${resp.status}): ${text.slice(0, 200)}`)
      }

      // 3. Redireciona para a tela de acompanhamento
      router.push(`/pessoas/importar/${id}`)
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Erro desconhecido no upload')
      setUploading(false)
    }
  }

  const runningJobs = jobs.filter(j => j.status === 'running' || j.status === 'pending')
  const completedJobs = jobs.filter(j => j.status === 'completed' || j.status === 'reviewing')
  const archivedJobs = jobs.filter(j => j.status === 'archived' || j.status === 'failed')

  return (
    <div className="max-w-5xl mx-auto p-6 space-y-6">
      <Link href="/pessoas" className="text-sm text-zinc-600 hover:text-zinc-900 inline-flex items-center gap-1">
        <ChevronLeft className="h-4 w-4" /> Pessoas
      </Link>

      <header className="border-b border-zinc-200 pb-4">
        <h1 className="text-2xl font-semibold text-zinc-900">Importar fichas</h1>
        <p className="text-sm text-zinc-500 mt-1">
          Faça upload do PDF "Registro de Empregado" do sistema Domínio.
          O processamento OCR roda em background e você revisa o resultado antes de gravar.
        </p>
      </header>

      {error && (
        <div className="border border-red-200 bg-red-50 rounded-md p-4 text-sm text-red-900">
          <div className="flex gap-2 items-start">
            <AlertTriangle className="h-5 w-5 mt-0.5 flex-shrink-0" />
            <div>
              <strong>Erro:</strong> {error}
            </div>
          </div>
        </div>
      )}

      {/* Uploader */}
      <UploadBox uploading={uploading} onUpload={handleUpload} />

      {/* Lista de jobs */}
      {loading ? (
        <div className="flex justify-center py-12">
          <Loader2 className="h-6 w-6 animate-spin text-zinc-400" />
        </div>
      ) : jobs.length === 0 ? (
        <div className="text-center py-12 text-zinc-500">
          <FileText className="h-12 w-12 mx-auto mb-3 text-zinc-300" />
          <p className="text-sm">Nenhum job de importação ainda. Faça upload de um PDF acima para começar.</p>
        </div>
      ) : (
        <div className="space-y-6">
          {runningJobs.length > 0 && (
            <JobSection title="Em processamento" jobs={runningJobs} highlight />
          )}
          {completedJobs.length > 0 && (
            <JobSection title="Pendentes de revisão" jobs={completedJobs} />
          )}
          {archivedJobs.length > 0 && (
            <JobSection title="Concluídos e arquivados" jobs={archivedJobs} muted />
          )}
        </div>
      )}
    </div>
  )
}

// ============================================================================
// UploadBox
// ============================================================================

function UploadBox({
  uploading, onUpload,
}: {
  uploading: boolean
  onUpload: (file: File) => void
}) {
  const [dragging, setDragging] = useState(false)

  const handleFiles = (files: FileList | null) => {
    if (!files || files.length === 0) return
    const f = files[0]
    if (!f.name.toLowerCase().endsWith('.pdf')) {
      alert('Apenas arquivos PDF são aceitos')
      return
    }
    onUpload(f)
  }

  return (
    <label
      className={[
        'block border-2 border-dashed rounded-lg p-10 text-center cursor-pointer transition',
        dragging
          ? 'border-zinc-500 bg-zinc-50'
          : 'border-zinc-300 hover:border-zinc-400 hover:bg-zinc-50',
        uploading ? 'pointer-events-none opacity-60' : '',
      ].join(' ')}
      onDragOver={(e) => { e.preventDefault(); setDragging(true) }}
      onDragLeave={() => setDragging(false)}
      onDrop={(e) => {
        e.preventDefault()
        setDragging(false)
        handleFiles(e.dataTransfer.files)
      }}
    >
      {uploading ? (
        <>
          <Loader2 className="h-10 w-10 mx-auto text-zinc-400 mb-3 animate-spin" />
          <div className="text-sm font-medium text-zinc-700">Enviando para o worker...</div>
          <div className="text-xs text-zinc-500 mt-1">
            Não feche a aba. Você será redirecionado para acompanhar o progresso.
          </div>
        </>
      ) : (
        <>
          <Upload className="h-10 w-10 mx-auto text-zinc-400 mb-3" />
          <div className="text-sm font-medium text-zinc-700">
            Arraste o PDF aqui ou clique para selecionar
          </div>
          <div className="text-xs text-zinc-500 mt-1">
            Apenas arquivos PDF · pode conter centenas ou milhares de fichas
          </div>
          <input
            type="file"
            accept="application/pdf"
            className="hidden"
            onChange={(e) => handleFiles(e.target.files)}
          />
        </>
      )}
    </label>
  )
}

// ============================================================================
// JobSection
// ============================================================================

function JobSection({
  title, jobs, highlight, muted,
}: {
  title: string
  jobs: ImportJob[]
  highlight?: boolean
  muted?: boolean
}) {
  return (
    <section>
      <h2 className="text-xs font-semibold uppercase tracking-wider text-zinc-500 mb-2">{title}</h2>
      <div className={[
        'border border-zinc-200 rounded-lg bg-white divide-y divide-zinc-100',
        muted ? 'opacity-70' : '',
      ].join(' ')}>
        {jobs.map(j => <JobRow key={j.id} job={j} highlight={highlight} />)}
      </div>
    </section>
  )
}

function JobRow({ job, highlight }: { job: ImportJob; highlight?: boolean }) {
  const isInteractive = job.status === 'completed' || job.status === 'reviewing'
                       || job.status === 'running' || job.status === 'pending'

  const content = (
    <div className="px-4 py-3 flex items-center gap-3 group">
      <JobStatusIcon status={job.status} />
      <div className="flex-1 min-w-0">
        <div className="flex items-center gap-2 flex-wrap">
          <span className="font-medium text-zinc-900 text-sm truncate">{job.source_file_name}</span>
          <JobStatusBadge status={job.status} />
        </div>
        <div className="text-xs text-zinc-500 mt-0.5 flex items-center gap-3 flex-wrap">
          {job.source_pages_total != null && (
            <span>
              {job.pages_processed}/{job.source_pages_total} páginas
            </span>
          )}
          {job.items_total > 0 && (
            <span>{job.items_total} fichas extraídas</span>
          )}
          {job.items_approved > 0 && (
            <span className="text-emerald-700">{job.items_approved} aprovadas</span>
          )}
          {job.items_rejected > 0 && (
            <span className="text-red-700">{job.items_rejected} rejeitadas</span>
          )}
          {job.items_duplicates > 0 && (
            <span className="text-amber-700">{job.items_duplicates} duplicatas</span>
          )}
          {job.pages_failed > 0 && (
            <span className="text-amber-700">{job.pages_failed} páginas falhadas</span>
          )}
          <span className="text-zinc-400">·</span>
          <span>{formatRelative(job.created_at)}</span>
        </div>

        {/* Progress bar quando em andamento */}
        {(job.status === 'running' || job.status === 'pending') && job.source_pages_total != null && (
          <div className="mt-2 h-1 bg-zinc-100 rounded-full overflow-hidden max-w-md">
            <div
              className="h-full bg-zinc-700 transition-all"
              style={{ width: `${(job.pages_processed / Math.max(job.source_pages_total, 1)) * 100}%` }}
            />
          </div>
        )}
      </div>
      {isInteractive && <ChevronRight className="h-4 w-4 text-zinc-400 group-hover:text-zinc-700" />}
    </div>
  )

  if (isInteractive) {
    return (
      <Link
        href={`/pessoas/importar/${job.id}`}
        className={['block hover:bg-zinc-50 transition', highlight ? 'bg-amber-50/30' : ''].join(' ')}
      >
        {content}
      </Link>
    )
  }
  return <div>{content}</div>
}

function JobStatusIcon({ status }: { status: ImportJobStatus }) {
  const props = { className: 'h-5 w-5 flex-shrink-0' as string }
  switch (status) {
    case 'pending':   return <Clock {...props} />
    case 'running':   return <Loader2 className="h-5 w-5 flex-shrink-0 animate-spin text-zinc-700" />
    case 'completed': return <CheckCircle2 className="h-5 w-5 flex-shrink-0 text-amber-600" />
    case 'reviewing': return <RefreshCw className="h-5 w-5 flex-shrink-0 text-amber-600" />
    case 'archived':  return <Archive className="h-5 w-5 flex-shrink-0 text-zinc-400" />
    case 'failed':    return <XCircle className="h-5 w-5 flex-shrink-0 text-red-600" />
  }
}

function JobStatusBadge({ status }: { status: ImportJobStatus }) {
  const label = {
    pending: 'Aguardando',
    running: 'Processando',
    completed: 'Pendente revisão',
    reviewing: 'Em revisão',
    archived: 'Arquivado',
    failed: 'Falhou',
  }[status]

  const cls = {
    pending:   'bg-zinc-100 text-zinc-700',
    running:   'bg-blue-100 text-blue-800',
    completed: 'bg-amber-100 text-amber-800',
    reviewing: 'bg-amber-100 text-amber-800',
    archived:  'bg-zinc-100 text-zinc-500',
    failed:    'bg-red-100 text-red-800',
  }[status]

  return (
    <span className={`text-[10px] font-semibold uppercase tracking-wide px-1.5 py-0.5 rounded ${cls}`}>
      {label}
    </span>
  )
}

function formatRelative(iso: string): string {
  const date = new Date(iso)
  const diffMs = Date.now() - date.getTime()
  const diffMin = Math.floor(diffMs / 60000)
  if (diffMin < 1) return 'agora'
  if (diffMin < 60) return `há ${diffMin}min`
  const diffH = Math.floor(diffMin / 60)
  if (diffH < 24) return `há ${diffH}h`
  const diffD = Math.floor(diffH / 24)
  if (diffD < 7) return `há ${diffD}d`
  return date.toLocaleDateString('pt-BR')
}

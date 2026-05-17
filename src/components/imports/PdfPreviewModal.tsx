'use client'

/**
 * R2 People · PdfPreviewModal (Sessao E6)
 * ============================================================================
 * Modal full-screen para visualizar o PDF original de um job de OCR.
 *
 * Usa react-pdf (wrapper de pdf.js).
 *
 * Comportamento:
 *   - initialPage: pula direto para a pagina do item revisado
 *   - Zoom in/out (botoes + atalhos)
 *   - Navegacao por pagina (anterior/proxima/ir-para)
 *   - Loading granular: enquanto baixa o PDF e enquanto renderiza cada pagina
 *   - Erros: pdf_not_stored, pdf_purged (mensagem amigavel)
 *
 * Permissao: usa Imports.getPdfUrl que aplica RLS por tenant.
 *
 * Dependencias:
 *   npm install react-pdf pdfjs-dist
 *
 * Carregamento do worker do pdf.js:
 *   import { pdfjs } from 'react-pdf'
 *   pdfjs.GlobalWorkerOptions.workerSrc = ...
 *   Em produção, configurar via next.config.js para servir o worker.
 *   Aqui usamos CDN de fallback que sempre funciona.
 * ============================================================================
 */

import { useState, useEffect, useCallback } from 'react'
import {
  X, ZoomIn, ZoomOut, ChevronLeft, ChevronRight,
  Loader2, AlertCircle, Download, Maximize2,
} from 'lucide-react'

import { Imports, RpcError } from '@/lib/r2'
import { createClient } from '@/lib/supabase'

// react-pdf · imports dinamicos (so client-side, evita SSR break)
// Em runtime real do Next.js, importe diretamente.
// Aqui mantemos tipagem forte e checamos disponibilidade.

interface PdfPreviewModalProps {
  jobId: string
  /** Pagina inicial (1-indexada) · default 1 */
  initialPage?: number
  onClose: () => void
}

interface PdfMeta {
  url: string
  fileName: string
}

export function PdfPreviewModal({ jobId, initialPage = 1, onClose }: PdfPreviewModalProps) {
  const [meta, setMeta] = useState<PdfMeta | null>(null)
  const [error, setError] = useState<string | null>(null)
  const [loadingMeta, setLoadingMeta] = useState(true)

  const [page, setPage] = useState(initialPage)
  const [totalPages, setTotalPages] = useState(0)
  const [zoom, setZoom] = useState(1.0)
  const [pageInput, setPageInput] = useState(String(initialPage))

  // 1. Busca a signed URL ao montar
  useEffect(() => {
    let cancelled = false

    const fetchUrl = async () => {
      setLoadingMeta(true)
      setError(null)
      try {
        const data = await Imports.getPdfUrl(jobId)

        const supabase = createClient() as unknown as {
          storage?: {
            from: (bucket: string) => {
              createSignedUrl: (path: string, expires: number) => Promise<{
                data: { signedUrl: string } | null
                error: { message: string } | null
              }>
            }
          }
        }
        if (typeof supabase.storage?.from !== 'function') {
          if (!cancelled) setError('Cliente Supabase Storage indisponível')
          return
        }

        const signed = await supabase.storage.from(data.bucket)
          .createSignedUrl(data.path, data.expires_in)

        if (signed.error || !signed.data) {
          if (!cancelled) setError(`Falha ao gerar URL: ${signed.error?.message || 'sem dados'}`)
          return
        }

        if (!cancelled) {
          setMeta({ url: signed.data.signedUrl, fileName: data.file_name })
        }
      } catch (err) {
        if (cancelled) return
        if (err instanceof RpcError) {
          if (err.code === 'pdf_not_stored') {
            setError('PDF não foi salvo no servidor. Jobs anteriores à E5 ou com falha de upload.')
          } else if (err.code === 'pdf_purged') {
            setError('PDF apagado pelo housekeeping (mais de 30 dias após arquivamento).')
          } else {
            setError(err.code)
          }
        } else {
          setError('Erro inesperado ao obter URL do PDF')
        }
      } finally {
        if (!cancelled) setLoadingMeta(false)
      }
    }

    fetchUrl()
    return () => { cancelled = true }
  }, [jobId])

  // Sincroniza pageInput com page
  useEffect(() => { setPageInput(String(page)) }, [page])

  // Atalhos de teclado
  useEffect(() => {
    const handler = (e: KeyboardEvent) => {
      if (e.key === 'Escape') onClose()
      else if (e.key === 'ArrowRight' && page < totalPages) setPage(page + 1)
      else if (e.key === 'ArrowLeft' && page > 1) setPage(page - 1)
      else if (e.key === '+' || e.key === '=') setZoom(z => Math.min(z + 0.25, 3))
      else if (e.key === '-' || e.key === '_') setZoom(z => Math.max(z - 0.25, 0.5))
    }
    window.addEventListener('keydown', handler)
    return () => window.removeEventListener('keydown', handler)
  }, [page, totalPages, onClose])

  const goToPage = useCallback((value: string) => {
    const n = parseInt(value, 10)
    if (Number.isFinite(n) && n >= 1 && n <= totalPages) {
      setPage(n)
    } else {
      setPageInput(String(page))
    }
  }, [page, totalPages])

  return (
    <div
      className="fixed inset-0 z-50 bg-black/80 flex flex-col"
      onClick={onClose}
    >
      <div
        className="flex-1 flex flex-col"
        onClick={(e) => e.stopPropagation()}
      >
        {/* Toolbar */}
        <div className="bg-zinc-900 text-zinc-100 px-4 py-2 flex items-center gap-3 flex-shrink-0">
          <button
            onClick={onClose}
            className="p-1.5 hover:bg-zinc-800 rounded"
            title="Fechar (Esc)"
          >
            <X className="h-4 w-4" />
          </button>

          <span className="font-medium text-sm truncate max-w-md">
            {meta?.fileName || 'PDF Original'}
          </span>

          <span className="flex-1" />

          {/* Navegação por página */}
          {totalPages > 0 && (
            <div className="flex items-center gap-1 text-sm">
              <button
                onClick={() => setPage(Math.max(1, page - 1))}
                disabled={page <= 1}
                className="p-1.5 hover:bg-zinc-800 disabled:opacity-30 rounded"
                title="Página anterior (←)"
              >
                <ChevronLeft className="h-4 w-4" />
              </button>
              <input
                type="text"
                value={pageInput}
                onChange={(e) => setPageInput(e.target.value)}
                onBlur={(e) => goToPage(e.target.value)}
                onKeyDown={(e) => {
                  if (e.key === 'Enter') goToPage(e.currentTarget.value)
                }}
                className="w-12 px-1.5 py-1 text-center text-zinc-900 rounded text-xs"
              />
              <span className="text-xs text-zinc-400">/ {totalPages}</span>
              <button
                onClick={() => setPage(Math.min(totalPages, page + 1))}
                disabled={page >= totalPages}
                className="p-1.5 hover:bg-zinc-800 disabled:opacity-30 rounded"
                title="Próxima página (→)"
              >
                <ChevronRight className="h-4 w-4" />
              </button>
            </div>
          )}

          {/* Zoom */}
          <div className="flex items-center gap-1 text-sm border-l border-zinc-700 pl-3">
            <button
              onClick={() => setZoom(z => Math.max(z - 0.25, 0.5))}
              className="p-1.5 hover:bg-zinc-800 rounded"
              title="Diminuir zoom (-)"
            >
              <ZoomOut className="h-4 w-4" />
            </button>
            <span className="text-xs text-zinc-400 w-12 text-center">{Math.round(zoom * 100)}%</span>
            <button
              onClick={() => setZoom(z => Math.min(z + 0.25, 3))}
              className="p-1.5 hover:bg-zinc-800 rounded"
              title="Aumentar zoom (+)"
            >
              <ZoomIn className="h-4 w-4" />
            </button>
            <button
              onClick={() => setZoom(1.0)}
              className="p-1.5 hover:bg-zinc-800 rounded text-xs"
              title="100%"
            >
              <Maximize2 className="h-4 w-4" />
            </button>
          </div>

          {/* Download */}
          {meta && (
            <a
              href={meta.url}
              target="_blank"
              rel="noopener noreferrer"
              download={meta.fileName}
              className="p-1.5 hover:bg-zinc-800 rounded border-l border-zinc-700 pl-3 ml-1"
              title="Abrir em nova aba"
            >
              <Download className="h-4 w-4" />
            </a>
          )}
        </div>

        {/* Viewer */}
        <div className="flex-1 overflow-auto bg-zinc-800 flex justify-center py-6 px-2">
          {loadingMeta ? (
            <div className="text-zinc-300 flex items-center gap-2 mt-12">
              <Loader2 className="h-5 w-5 animate-spin" />
              Carregando URL do PDF...
            </div>
          ) : error ? (
            <div className="text-zinc-300 max-w-md mt-12 text-center">
              <AlertCircle className="h-8 w-8 mx-auto mb-3 text-amber-500" />
              <p className="text-sm">{error}</p>
            </div>
          ) : meta ? (
            <PdfDocument
              url={meta.url}
              page={page}
              zoom={zoom}
              onLoadSuccess={(numPages) => {
                setTotalPages(numPages)
                // Se initialPage > totalPages, recua
                if (page > numPages) setPage(Math.max(1, numPages))
              }}
              onLoadError={(msg) => setError(msg)}
            />
          ) : null}
        </div>
      </div>
    </div>
  )
}

// ============================================================================
// PdfDocument · wrapper do react-pdf com loading e error inline
// ============================================================================

interface PdfDocumentProps {
  url: string
  page: number
  zoom: number
  onLoadSuccess: (numPages: number) => void
  onLoadError: (msg: string) => void
}

function PdfDocument({ url, page, zoom, onLoadSuccess, onLoadError }: PdfDocumentProps) {
  // Carga dinâmica de react-pdf para não quebrar SSR
  // Em projetos Next.js, considere `dynamic(() => import(...), { ssr: false })`
  const [Doc, setDoc] = useState<DynamicPdfComponents | null>(null)
  const [docError, setDocError] = useState<string | null>(null)

  useEffect(() => {
    let cancelled = false
    const load = async () => {
      try {
        // @ts-expect-error · react-pdf é resolvido em runtime; em dev sem o pacote instalado o catch trata
        const mod = await import('react-pdf') as unknown as ReactPdfModule
        // Configura o worker do pdf.js · usa CDN de fallback
        // (em produção, hospede o worker estático no /public)
        if (mod.pdfjs?.GlobalWorkerOptions) {
          const version = mod.pdfjs.version || '4.0.379'
          mod.pdfjs.GlobalWorkerOptions.workerSrc =
            `https://unpkg.com/pdfjs-dist@${version}/build/pdf.worker.min.mjs`
        }
        if (!cancelled) {
          setDoc({ Document: mod.Document, Page: mod.Page })
        }
      } catch (err) {
        if (!cancelled) {
          setDocError(err instanceof Error ? err.message : 'Falha ao carregar react-pdf')
        }
      }
    }
    load()
    return () => { cancelled = true }
  }, [])

  if (docError) {
    return (
      <div className="text-zinc-300 max-w-md text-center mt-12">
        <AlertCircle className="h-8 w-8 mx-auto mb-3 text-red-500" />
        <p className="text-sm">{docError}</p>
        <p className="text-xs text-zinc-500 mt-2">
          Verifique se o pacote react-pdf está instalado: <code>npm install react-pdf pdfjs-dist</code>
        </p>
      </div>
    )
  }

  if (!Doc) {
    return (
      <div className="text-zinc-300 flex items-center gap-2 mt-12">
        <Loader2 className="h-5 w-5 animate-spin" />
        Inicializando viewer...
      </div>
    )
  }

  const { Document, Page } = Doc

  return (
    <Document
      file={url}
      onLoadSuccess={(info: { numPages: number }) => onLoadSuccess(info.numPages)}
      onLoadError={(err: Error) => onLoadError(err.message)}
      loading={
        <div className="text-zinc-300 flex items-center gap-2 mt-12">
          <Loader2 className="h-5 w-5 animate-spin" />
          Carregando documento...
        </div>
      }
      error={
        <div className="text-zinc-300 max-w-md text-center mt-12">
          <AlertCircle className="h-8 w-8 mx-auto mb-3 text-red-500" />
          <p className="text-sm">Erro ao renderizar o PDF</p>
        </div>
      }
    >
      <Page
        pageNumber={page}
        scale={zoom}
        renderAnnotationLayer={false}
        renderTextLayer={false}
        loading={
          <div className="bg-white border border-zinc-300 rounded p-12">
            <Loader2 className="h-5 w-5 animate-spin text-zinc-400" />
          </div>
        }
        className="shadow-2xl"
      />
    </Document>
  )
}

// ============================================================================
// Tipos minimos do react-pdf para nao depender de types em build-time
// ============================================================================

interface DynamicPdfComponents {
  Document: React.ComponentType<{
    file: string
    onLoadSuccess?: (info: { numPages: number }) => void
    onLoadError?: (err: Error) => void
    loading?: React.ReactNode
    error?: React.ReactNode
    children: React.ReactNode
  }>
  Page: React.ComponentType<{
    pageNumber: number
    scale?: number
    renderAnnotationLayer?: boolean
    renderTextLayer?: boolean
    loading?: React.ReactNode
    className?: string
  }>
}

interface ReactPdfModule {
  Document: DynamicPdfComponents['Document']
  Page: DynamicPdfComponents['Page']
  pdfjs?: {
    version?: string
    GlobalWorkerOptions: { workerSrc: string }
  }
}

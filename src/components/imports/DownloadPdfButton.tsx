'use client'

/**
 * R2 People · DownloadPdfButton (Sessao E5)
 * ============================================================================
 * Botao para baixar o PDF original de um job de OCR.
 *
 * Fluxo:
 *   1. Chama Imports.getPdfUrl(jobId) → { bucket, path, expires_in, file_name }
 *   2. Usa o supabase client para createSignedUrl(bucket, path, expires_in)
 *   3. Abre a URL em uma nova aba (download)
 *
 * Estados:
 *   - Loading enquanto gera a URL
 *   - Desabilitado se pdf_not_stored ou pdf_purged
 *   - Tooltip explicando se nao disponivel
 * ============================================================================
 */

import { useState } from 'react'
import { Download, Loader2, AlertCircle } from 'lucide-react'
import { Imports, RpcError } from '@/lib/r2'
import { createClient } from '@/lib/supabase'

interface DownloadPdfButtonProps {
  jobId: string
  /** Se sabido a priori (ex.: storage_path ja conhecido do listing), permite estilizar */
  available?: boolean
  /** Texto auxiliar exibido em caso de erro */
  unavailableReason?: string
  className?: string
}

export function DownloadPdfButton({
  jobId, available = true, unavailableReason, className,
}: DownloadPdfButtonProps) {
  const [loading, setLoading] = useState(false)
  const [error, setError] = useState<string | null>(null)

  const handleDownload = async () => {
    setLoading(true)
    setError(null)
    try {
      const meta = await Imports.getPdfUrl(jobId)

      // Em Supabase real, esse client retornaria a signed URL.
      // Em ambiente sem Supabase, o stub retorna data: null, e tratamos abaixo.
      const supabase = createClient() as unknown as {
        storage: {
          from: (bucket: string) => {
            createSignedUrl: (path: string, expires: number, opts?: { download?: string }) => Promise<{
              data: { signedUrl: string } | null
              error: { message: string } | null
            }>
          }
        }
      }

      if (typeof supabase.storage?.from !== 'function') {
        setError('Cliente Supabase Storage indisponível neste ambiente')
        return
      }

      const { data, error: signedErr } = await supabase.storage
        .from(meta.bucket)
        .createSignedUrl(meta.path, meta.expires_in, { download: meta.file_name })

      if (signedErr || !data) {
        setError(`Falha ao gerar URL: ${signedErr?.message || 'sem dados'}`)
        return
      }

      // Abre em nova aba (download começa automaticamente quando o backend retorna
      // Content-Disposition attachment, que o ?download= dispara)
      window.open(data.signedUrl, '_blank', 'noopener,noreferrer')
    } catch (err) {
      if (err instanceof RpcError) {
        if (err.code === 'pdf_not_stored') {
          setError('PDF não foi salvo (job antigo ou upload falhou)')
        } else if (err.code === 'pdf_purged') {
          setError('PDF foi apagado (job arquivado há mais de 30 dias)')
        } else {
          setError(err.code)
        }
      } else {
        setError('Erro inesperado')
      }
    } finally {
      setLoading(false)
    }
  }

  if (!available) {
    return (
      <div className={['flex items-center gap-1.5 text-xs text-zinc-500', className].filter(Boolean).join(' ')}>
        <AlertCircle className="h-3.5 w-3.5" />
        <span>PDF indisponível{unavailableReason ? ` · ${unavailableReason}` : ''}</span>
      </div>
    )
  }

  return (
    <div className={['inline-flex items-center gap-2', className].filter(Boolean).join(' ')}>
      <button
        onClick={handleDownload}
        disabled={loading}
        className="px-3 py-1.5 text-xs font-medium text-zinc-700 hover:bg-zinc-100 border border-zinc-200 disabled:opacity-50 rounded inline-flex items-center gap-1.5"
      >
        {loading ? <Loader2 className="h-3.5 w-3.5 animate-spin" /> : <Download className="h-3.5 w-3.5" />}
        Baixar PDF original
      </button>
      {error && (
        <span className="text-xs text-red-700 flex items-center gap-1">
          <AlertCircle className="h-3 w-3" />
          {error}
        </span>
      )}
    </div>
  )
}

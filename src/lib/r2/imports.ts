/**
 * R2 People · Adapter · Import Jobs (Sessao E4)
 * ============================================================================
 * Cobre o fluxo de importacao OCR de fichas via worker Python:
 *
 *   1. Frontend chama Imports.create(file_name, file_size, pages_total)
 *      e recebe { id, worker_token }
 *   2. Frontend faz upload do PDF para o worker FastAPI, passando id + token
 *   3. Worker processa em background e atualiza o job via RPCs internas
 *      (rpc_import_worker_*). Frontend acompanha por SSE do worker, ou
 *      polling de Imports.get(id) que retorna o status agregado.
 *   4. Quando todos os items chegam, frontend abre tela de revisao e
 *      usa items.list/update/approve/reject.
 *   5. RH pode aprovar em lote (approveAll) ou arquivar o job.
 *
 * ============================================================================
 */

import { callRpc } from './base'
import type { EmployeePayload } from './employees'

// ============================================================================
// Tipos
// ============================================================================

export type ImportJobStatus =
  | 'pending' | 'running' | 'completed' | 'failed' | 'reviewing' | 'archived'

export type ImportItemStatus =
  | 'pending' | 'approved' | 'rejected' | 'duplicate' | 'edited'

export interface ImportJob {
  id: string
  tenant_id: string
  uploaded_by: string | null
  uploaded_by_name?: string
  source_file_name: string
  source_file_size: number | null
  source_pages_total: number | null
  status: ImportJobStatus

  pages_processed: number
  pages_failed: number
  items_total: number
  items_approved: number
  items_rejected: number
  items_duplicates: number

  error_log: Array<{ page?: number; message: string }>

  created_at: string
  started_at: string | null
  completed_at: string | null
  archived_at: string | null
}

export interface ImportJobCreateResult {
  id: string
  worker_token: string
}

export interface ImportItem {
  id: string
  job_id: string
  tenant_id: string
  page_number: number
  status: ImportItemStatus

  parsed_payload: EmployeePayload
  full_name: string | null
  cpf: string | null
  matricula_esocial: string | null
  job_title: string | null
  hire_date: string | null
  termination_date: string | null

  parser_alerts: string[]
  confidence_score: number | null

  approved_at: string | null
  approved_by: string | null
  approved_payload: EmployeePayload | null
  employee_id: string | null
  duplicate_of: string | null

  rejected_at: string | null
  rejected_by: string | null
  rejection_reason: string | null

  created_at: string
  updated_at: string
}

export interface ImportJobListResult {
  jobs: ImportJob[]
  total: number
  limit: number
  offset: number
}

export interface ImportItemListResult {
  items: ImportItem[]
  total: number
  limit: number
  offset: number
}

export interface ApproveResult {
  id: string
  status: 'approved' | 'duplicate'
  employee_id: string | null
  duplicate_of: string | null
}

// ============================================================================
// API publica
// ============================================================================

export const Imports = {
  /**
   * Cria um novo job de importacao. O `worker_token` retornado deve ser
   * passado ao worker no upload do PDF para autorizar updates de progresso.
   */
  async create(input: {
    fileName: string
    fileSize?: number
    pagesTotal?: number
  }): Promise<ImportJobCreateResult> {
    return callRpc<ImportJobCreateResult>('rpc_import_job_create', {
      p_payload: {
        file_name: input.fileName,
        file_size: input.fileSize,
        pages_total: input.pagesTotal,
      },
    })
  },

  /**
   * Lista os jobs do tenant. Permite filtrar por status.
   */
  async list(filters: {
    status?: ImportJobStatus
    limit?: number
    offset?: number
  } = {}): Promise<ImportJobListResult> {
    return callRpc<ImportJobListResult>('rpc_import_jobs_list', {
      p_status: filters.status ?? null,
      p_limit: filters.limit ?? 20,
      p_offset: filters.offset ?? 0,
    })
  },

  /**
   * Retorna o detalhe de um job com contadores agregados.
   */
  async get(id: string): Promise<{ job: ImportJob }> {
    return callRpc<{ job: ImportJob }>('rpc_import_jobs_get', { p_id: id })
  },

  /**
   * Arquiva o job (visualmente sai da lista padrao).
   */
  async archive(id: string) {
    return callRpc<{ id: string; archived: boolean }>('rpc_import_job_archive', { p_id: id })
  },

  /**
   * Aprovar todos os items pendentes do job de uma vez.
   * Retorna contadores de approved / duplicate / errors.
   */
  async approveAll(jobId: string): Promise<{
    approved: number
    duplicates: number
    errors: number
  }> {
    return callRpc('rpc_import_job_approve_all', { p_job_id: jobId })
  },

  /**
   * Sessao E5 · obtem dados para baixar o PDF original do job.
   * Retorna bucket + path para o cliente Supabase chamar createSignedUrl.
   * Erros:
   *   - 'pdf_not_stored'  · worker nao salvou ainda (ou job antigo)
   *   - 'pdf_purged'      · PDF foi apagado pelo housekeeping (>30d archived)
   *   - 'job_not_found'   · job inexistente ou de outro tenant
   */
  async getPdfUrl(jobId: string): Promise<{
    bucket: string
    path: string
    expires_in: number
    file_name: string
    file_size: number | null
    uploaded_at: string | null
  }> {
    return callRpc('rpc_import_jobs_get_pdf_url', { p_job_id: jobId })
  },

  /**
   * Sessao E5 · super_admin apenas · roda housekeeping manual.
   * Apaga do Storage os PDFs de jobs archived ha mais de 30 dias.
   */
  async cleanupExpired(): Promise<{
    purged_count: number
    paths: string[]
  }> {
    return callRpc('rpc_import_jobs_cleanup_expired', {})
  },

  items: {
    /**
     * Lista os items extraidos de um job, filtravel por status.
     */
    async list(jobId: string, filters: {
      status?: ImportItemStatus
      limit?: number
      offset?: number
    } = {}): Promise<ImportItemListResult> {
      return callRpc<ImportItemListResult>('rpc_import_items_list', {
        p_job_id: jobId,
        p_status: filters.status ?? null,
        p_limit: filters.limit ?? 50,
        p_offset: filters.offset ?? 0,
      })
    },

    /**
     * Atualiza o payload de um item antes da aprovacao.
     * Apenas campos pendentes (status='pending') podem ser editados.
     */
    async update(id: string, patch: Partial<EmployeePayload>) {
      return callRpc<{ id: string; status: ImportItemStatus }>('rpc_import_item_update', {
        p_id: id,
        p_patch: patch,
      })
    },

    /**
     * Aprova um item · promove para `employees`. Se CPF ja existe,
     * marca como `duplicate` e linka via `duplicate_of`.
     */
    async approve(id: string): Promise<ApproveResult> {
      return callRpc<ApproveResult>('rpc_import_item_approve', { p_id: id })
    },

    /**
     * Rejeita o item · nao gera nenhum registro em `employees`.
     */
    async reject(id: string, reason?: string) {
      return callRpc<{ id: string; status: 'rejected' }>('rpc_import_item_reject', {
        p_id: id,
        p_reason: reason ?? null,
      })
    },
  },
}

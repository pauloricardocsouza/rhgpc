/**
 * R2 People · Adapter · PDI (Sessao J)
 * ============================================================================
 * Planos de Desenvolvimento Individual.
 *
 * Atualmente exposto: create, get_by_id, list, list_cycles, update, change_status,
 * action_add, action_update, action_remove, comment_add.
 *
 * Sera expandido em C2 com tipos detalhados de Action, Comment e Evidence.
 * ============================================================================
 */

import { callRpc } from './base'

export type PdiStatus = 'draft' | 'active' | 'completed' | 'canceled'

export type PdiActionKind =
  | 'curso' | 'leitura' | 'mentoria' | 'projeto'
  | 'certificacao' | 'evento' | 'outro'

export type PdiActionStatus =
  | 'not_started' | 'in_progress' | 'completed' | 'canceled'

export interface PdiAction {
  id: string
  tenant_id: string
  pdi_id: string
  title: string
  description: string | null
  kind: PdiActionKind
  due_date: string | null
  status: PdiActionStatus
  display_order: number
  evidence_path: string | null
  evidence_url: string | null
  evidence_note: string | null
  completed_at: string | null
  created_at: string
  updated_at: string
}

export interface PdiPlan {
  id: string
  tenant_id: string
  user_id: string                         // dono do PDI (era subject_id)
  user_name?: string
  manager_id_snapshot: string | null
  manager_name?: string
  cycle_id: string | null
  cycle_name?: string
  objective: string                       // era "title"
  context: string | null                  // era "description"
  status: PdiStatus
  start_date: string | null
  end_date: string | null
  activated_at: string | null
  completed_at: string | null
  actions: PdiAction[]
  actions_total: number
  actions_completed: number
  created_at: string
}

export const Pdi = {
  /**
   * Cria um PDI. Vinculado a um ciclo aberto.
   * Retorna pdi_id.
   */
  async create(input: {
    userId: string
    cycleId: string
    objective: string
    context?: string
    startDate?: string  // 'AAAA-MM-DD'
    endDate?: string
  }): Promise<{ pdi_id: string }> {
    return callRpc<{ pdi_id: string }>('rpc_pdi_create', {
      p_user_id: input.userId,
      p_cycle_id: input.cycleId,
      p_objective: input.objective,
      p_context: input.context ?? null,
      p_start_date: input.startDate ?? null,
      p_end_date: input.endDate ?? null,
    })
  },

  async getById(pdiId: string): Promise<{ plan: PdiPlan }> {
    return callRpc<{ plan: PdiPlan }>('rpc_pdi_get_by_id', { p_pdi_id: pdiId })
      .then(r => ({ plan: r.plan }))
  },

  async list(filters: { status?: PdiStatus; cycleId?: string; subjectId?: string } = {}) {
    return callRpc<{ plans: PdiPlan[] }>('rpc_pdi_list', {
      p_status: filters.status ?? null,
      p_cycle_id: filters.cycleId ?? null,
      p_subject_id: filters.subjectId ?? null,
    })
  },

  /**
   * Lista ciclos PDI ativos do tenant.
   * Retorna items[{ id, code, display_name, start_date, end_date, open_for_planning }].
   */
  async listCycles() {
    return callRpc<{
      items: Array<{
        id: string
        code: string
        display_name: string
        start_date: string
        end_date: string
        open_for_planning: boolean
      }>
    }>('rpc_pdi_list_cycles', {})
  },

  /**
   * Atualiza campos editaveis do PDI. Todos os parametros sao opcionais;
   * NULL/undefined preserva o valor atual.
   */
  async update(pdiId: string, payload: {
    objective?: string
    context?: string
    startDate?: string  // 'AAAA-MM-DD'
    endDate?: string
  }) {
    return callRpc<{ pdi_id: string }>('rpc_pdi_update', {
      p_pdi_id: pdiId,
      p_objective: payload.objective ?? null,
      p_context: payload.context ?? null,
      p_start_date: payload.startDate ?? null,
      p_end_date: payload.endDate ?? null,
    })
  },

  /**
   * Muda status do PDI (draft -> active -> completed | canceled).
   * cancelReason e obrigatorio quando newStatus='canceled' segundo o backend.
   */
  async changeStatus(pdiId: string, newStatus: PdiStatus, cancelReason?: string) {
    return callRpc<{ pdi_id: string; status: PdiStatus }>('rpc_pdi_change_status', {
      p_pdi_id: pdiId,
      p_new_status: newStatus,
      p_cancel_reason: cancelReason ?? null,
    })
  },

  async addAction(input: {
    pdiId: string
    title: string
    description?: string
    kind?: PdiActionKind
    dueDate?: string
  }) {
    return callRpc<{ action_id: string }>('rpc_pdi_action_add', {
      p_pdi_id: input.pdiId,
      p_title: input.title,
      p_description: input.description ?? null,
      p_kind: input.kind ?? 'outro',
      p_due_date: input.dueDate ?? null,
    })
  },

  /**
   * Atualiza uma acao. Todos opcionais; NULL/undefined preserva.
   */
  async updateAction(actionId: string, payload: {
    title?: string
    description?: string
    kind?: PdiActionKind
    dueDate?: string
    status?: PdiActionStatus
    evidenceUrl?: string
    evidenceNote?: string
  }) {
    return callRpc<{ action_id: string }>('rpc_pdi_action_update', {
      p_action_id: actionId,
      p_title: payload.title ?? null,
      p_description: payload.description ?? null,
      p_kind: payload.kind ?? null,
      p_due_date: payload.dueDate ?? null,
      p_status: payload.status ?? null,
      p_evidence_path: null,
      p_evidence_url: payload.evidenceUrl ?? null,
      p_evidence_note: payload.evidenceNote ?? null,
    })
  },

  async removeAction(actionId: string) {
    return callRpc<{ action_id: string }>('rpc_pdi_action_remove', {
      p_action_id: actionId,
    })
  },

  async addComment(planId: string, message: string) {
    return callRpc<{ comment_id: string }>('rpc_pdi_comment_add', {
      p_plan_id: planId,
      p_message: message,
    })
  },
}

/**
 * R2 People · Adapter · 9-Box (Sessao A2)
 * ============================================================================
 * Avaliacao matricial de potencial vs desempenho.
 *
 * Conceitos:
 *   - Settings · configuracao do 9-Box no tenant (grid 3x3 ou 5x5, criterios, etc.)
 *   - Cycle    · ciclo formal de avaliacao com janela de datas
 *   - Evaluation · avaliacao individual (manager + auto-avaliacao opcional)
 *   - Snapshot · captura imutavel do estado finalizado (preserva criterios da epoca)
 *
 * Fluxo tipico:
 *   1. RH/diretoria configura settings (rpc_ninebox_settings_update)
 *   2. RH cria ciclo (rpc_ninebox_cycle_create)
 *   3. Gestor inicia avaliacao do liderado (rpc_ninebox_evaluation_start)
 *   4. Colaborador faz auto-avaliacao se required (rpc_ninebox_evaluation_self_submit)
 *   5. Gestor submete scores (rpc_ninebox_evaluation_manager_submit)
 *   6. Gestor finaliza · snapshot imutavel criado (rpc_ninebox_evaluation_finalize)
 *
 * Justificativa e obrigatoria em "caixas extremas" se force_justification_extremes = TRUE.
 * ============================================================================
 */

import { callRpc, type NineboxCycleStatus, type NineboxEvaluationStatus } from './base'

// ============================================================================
// Settings
// ============================================================================

export type NineboxGridSize = '3x3' | '5x5'

export interface NineboxCriterion {
  name: string
  weight: number     // 0-100 · soma dos criterios deve dar 100
  description?: string
}

export interface NineboxSettings {
  tenant_id: string
  grid_size: NineboxGridSize
  potential_criteria: NineboxCriterion[]
  performance_criteria: NineboxCriterion[]
  box_labels: Record<string, string>  // ex: "1,1" -> "Insuficiente"
  force_justification_extremes: boolean
  min_justification_length: number
  require_self_assessment: boolean
  updated_at: string
  updated_by: string | null
}

// ============================================================================
// Cycle
// ============================================================================

export interface NineboxCycle {
  id: string
  tenant_id: string
  name: string
  description: string | null
  reference_year: number | null
  start_date: string  // ISO date
  end_date: string
  status: NineboxCycleStatus
  created_at: string
  created_by: string | null
}

// ============================================================================
// Evaluation
// ============================================================================

export interface NineboxScoreEntry {
  criterion_name: string
  score: number   // 1-5 (3x3) ou 1-9 (5x5) tipicamente
}

export interface NineboxScores {
  potential: NineboxScoreEntry[]
  performance: NineboxScoreEntry[]
}

export interface NineboxEvaluation {
  id: string
  tenant_id: string
  subject_id: string         // colaborador avaliado
  subject_name?: string
  manager_id: string         // gestor avaliador
  manager_name?: string
  cycle_id: string | null    // null para ad-hoc
  is_adhoc: boolean
  status: NineboxEvaluationStatus
  grid_size_snapshot: NineboxGridSize
  potential_criteria_snapshot: NineboxCriterion[]
  performance_criteria_snapshot: NineboxCriterion[]
  box_labels_snapshot: Record<string, string>
  final_potential_score: number | null
  final_performance_score: number | null
  final_box_row: number | null
  final_box_col: number | null
  final_box_label: string | null
  justification: string | null
  self_scores: NineboxScores | null
  manager_scores: NineboxScores | null
  created_at: string
  self_submitted_at: string | null
  manager_submitted_at: string | null
  finalized_at: string | null
  canceled_at: string | null
  cancel_reason: string | null
}

// ============================================================================
// Team matrix (visao agregada)
// ============================================================================

export interface NineboxMatrixCell {
  row: number  // 1-N
  col: number  // 1-N
  label: string
  count: number
  subjects: { id: string; name: string; final_potential_score: number; final_performance_score: number }[]
}

export interface NineboxTeamMatrix {
  cycle_id: string | null
  grid_size: NineboxGridSize
  cells: NineboxMatrixCell[]
  total_evaluations: number
}

// ============================================================================
// API publica
// ============================================================================

export const Ninebox = {
  // ----- Settings --------------------------------------------------------
  async getSettings(): Promise<{ settings: NineboxSettings }> {
    return callRpc<{ settings: NineboxSettings }>('rpc_ninebox_settings_get')
      .then(r => ({ settings: r.settings }))
  },

  async updateSettings(
    payload: Partial<Omit<NineboxSettings, 'tenant_id' | 'updated_at' | 'updated_by'>>,
  ): Promise<{ settings: NineboxSettings }> {
    return callRpc<{ settings: NineboxSettings }>('rpc_ninebox_settings_update', {
      p_payload: payload,
    }).then(r => ({ settings: r.settings }))
  },

  // ----- Cycles ----------------------------------------------------------
  async createCycle(input: {
    name: string
    startDate: string
    endDate: string
    referenceYear?: number
    description?: string
  }): Promise<{ cycle_id: string }> {
    return callRpc<{ cycle_id: string }>('rpc_ninebox_cycle_create', {
      p_name: input.name,
      p_start_date: input.startDate,
      p_end_date: input.endDate,
      p_reference_year: input.referenceYear ?? null,
      p_description: input.description ?? null,
    }).then(r => ({ cycle_id: r.cycle_id }))
  },

  async listCycles(status?: NineboxCycleStatus): Promise<{ cycles: NineboxCycle[] }> {
    return callRpc<{ cycles: NineboxCycle[] }>('rpc_ninebox_cycle_list', {
      p_status: status ?? null,
    }).then(r => ({ cycles: r.cycles }))
  },

  async updateCycle(
    cycleId: string,
    payload: Partial<Pick<NineboxCycle, 'name' | 'description' | 'start_date' | 'end_date' | 'status'>>,
  ): Promise<{ cycle: NineboxCycle }> {
    return callRpc<{ cycle: NineboxCycle }>('rpc_ninebox_cycle_update', {
      p_cycle_id: cycleId,
      p_payload: payload,
    }).then(r => ({ cycle: r.cycle }))
  },

  // ----- Evaluations -----------------------------------------------------
  async startEvaluation(input: {
    subjectId: string
    cycleId?: string
    isAdhoc?: boolean
  }): Promise<{ evaluation_id: string }> {
    return callRpc<{ evaluation_id: string }>('rpc_ninebox_evaluation_start', {
      p_subject_id: input.subjectId,
      p_cycle_id: input.cycleId ?? null,
      p_is_adhoc: input.isAdhoc ?? false,
    }).then(r => ({ evaluation_id: r.evaluation_id }))
  },

  async selfSubmit(evaluationId: string, scores: NineboxScores) {
    return callRpc<{ evaluation_id: string }>('rpc_ninebox_evaluation_self_submit', {
      p_evaluation_id: evaluationId,
      p_scores: scores,
    }).then(r => ({ evaluation_id: r.evaluation_id }))
  },

  async managerSubmit(input: {
    evaluationId: string
    scores: NineboxScores
    justification?: string
  }) {
    return callRpc<{ evaluation_id: string }>('rpc_ninebox_evaluation_manager_submit', {
      p_evaluation_id: input.evaluationId,
      p_scores: input.scores,
      p_justification: input.justification ?? null,
    }).then(r => ({ evaluation_id: r.evaluation_id }))
  },

  async finalize(evaluationId: string) {
    return callRpc<{ evaluation_id: string; snapshot_id: string }>('rpc_ninebox_evaluation_finalize', {
      p_evaluation_id: evaluationId,
    })
  },

  async cancel(evaluationId: string, reason?: string) {
    return callRpc<{ evaluation_id: string }>('rpc_ninebox_evaluation_cancel', {
      p_evaluation_id: evaluationId,
      p_reason: reason ?? null,
    }).then(r => ({ evaluation_id: r.evaluation_id }))
  },

  async getEvaluation(evaluationId: string): Promise<{ evaluation: NineboxEvaluation }> {
    return callRpc<{ evaluation: NineboxEvaluation }>('rpc_ninebox_evaluation_get', {
      p_evaluation_id: evaluationId,
    }).then(r => ({ evaluation: r.evaluation }))
  },

  async listEvaluations(filters: {
    cycleId?: string
    status?: NineboxEvaluationStatus
  } = {}): Promise<{ evaluations: NineboxEvaluation[] }> {
    return callRpc<{ evaluations: NineboxEvaluation[] }>('rpc_ninebox_evaluation_list', {
      p_cycle_id: filters.cycleId ?? null,
      p_status: filters.status ?? null,
    }).then(r => ({ evaluations: r.evaluations }))
  },

  // ----- Views agregadas -------------------------------------------------
  async getTeamMatrix(input: {
    cycleId?: string
    scope?: 'all' | 'my_team' | 'my_employer_unit' | 'my_working_unit'
  } = {}): Promise<NineboxTeamMatrix> {
    return callRpc<Omit<NineboxTeamMatrix, 'ok'>>('rpc_ninebox_team_matrix', {
      p_cycle_id: input.cycleId ?? null,
      p_scope: input.scope ?? 'all',
    })
  },

  async getHistory(subjectId: string): Promise<{ history: NineboxEvaluation[] }> {
    return callRpc<{ history: NineboxEvaluation[] }>('rpc_ninebox_history', {
      p_subject_id: subjectId,
    }).then(r => ({ history: r.history }))
  },
}

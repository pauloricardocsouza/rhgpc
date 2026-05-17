/**
 * R2 People · Adapter · Recognition (Sessao H2)
 * ============================================================================
 * Feed de reconhecimentos entre colaboradores.
 *
 * Atualmente exposto: create, get_feed, get_stats, react, report, resolve_report.
 * Sera expandido em C1 com tipos completos de Reaction e Report.
 * ============================================================================
 */

import { callRpc } from './base'

export interface Recognition {
  id: string
  tenant_id: string
  author_id: string
  author_name?: string
  recipient_id: string
  recipient_name?: string
  category: string
  message: string
  hidden_at: string | null
  created_at: string
  reactions_count: number
}

export interface RecognitionFeedResult {
  recognitions: Recognition[]
  has_more: boolean
}

export interface RecognitionStats {
  total_given: number
  total_received: number
  top_categories: { category: string; count: number }[]
}

export const Recognition = {
  async create(input: {
    recipientId: string
    message: string
    isPrivate?: boolean
  }): Promise<{ recognition_id: string }> {
    return callRpc<{ recognition_id: string }>('rpc_recognition_create', {
      p_recipient_id: input.recipientId,
      p_message: input.message,
      p_is_private: input.isPrivate ?? false,
    }).then(r => ({ recognition_id: r.recognition_id }))
  },

  async getFeed(input: { limit?: number; before?: string } = {}): Promise<RecognitionFeedResult> {
    return callRpc<Omit<RecognitionFeedResult, 'ok'>>('rpc_recognition_get_feed', {
      p_limit: input.limit ?? 20,
      p_before: input.before ?? null,
    })
  },

  async getStats(userId?: string): Promise<RecognitionStats> {
    return callRpc<Omit<RecognitionStats, 'ok'>>('rpc_recognition_get_stats', {
      p_user_id: userId ?? null,
    })
  },

  async react(recognitionId: string, reactionType: string) {
    return callRpc<{ recognition_id: string }>('rpc_recognition_react', {
      p_recognition_id: recognitionId,
      p_reaction_type: reactionType,
    })
  },

  async report(recognitionId: string, reason: string) {
    return callRpc<{ report_id: string }>('rpc_recognition_report', {
      p_recognition_id: recognitionId,
      p_reason: reason,
    })
  },

  async resolveReport(reportId: string, action: 'dismiss' | 'hide_recognition') {
    return callRpc<{ report_id: string }>('rpc_recognition_resolve_report', {
      p_report_id: reportId,
      p_action: action,
    })
  },
}

/**
 * R2 People · Adapter · Onboarding (Sessao K)
 * ============================================================================
 * Jornadas de onboarding com templates, etapas e tarefas (checklists).
 *
 * Atualmente exposto: templates (create/update/list/get + stage_add, task_add),
 * jornadas (create_blank, create_from_template, list, get_by_id, change_status,
 * stage_add, task_add, task_complete/uncomplete).
 *
 * Sera expandido em C3.
 * ============================================================================
 */

import { callRpc } from './base'

export type OnboardingStatus = 'draft' | 'active' | 'completed' | 'canceled'
export type OnboardingTaskStatus = 'pending' | 'completed'

export interface OnboardingTask {
  id: string
  stage_id: string
  title: string
  description: string | null
  order_index: number
  status: OnboardingTaskStatus
  completed_at: string | null
  due_date: string | null
}

export interface OnboardingStage {
  id: string
  journey_id?: string
  template_id?: string
  title: string
  description: string | null
  order_index: number
  tasks: OnboardingTask[]
}

export interface OnboardingJourney {
  id: string
  tenant_id: string
  subject_id: string
  subject_name?: string
  template_id: string | null
  status: OnboardingStatus
  started_at: string | null
  completed_at: string | null
  stages: OnboardingStage[]
}

export interface OnboardingTemplate {
  id: string
  tenant_id: string
  name: string
  description: string | null
  stages: OnboardingStage[]
  active: boolean
}

export const Onboarding = {
  // ----- Templates -------------------------------------------------------
  template: {
    async create(input: { name: string; description?: string }) {
      return callRpc<{ template_id: string }>('rpc_onb_template_create', {
        p_name: input.name,
        p_description: input.description ?? null,
      })
    },
    async getById(templateId: string): Promise<{ template: OnboardingTemplate }> {
      return callRpc<{ template: OnboardingTemplate }>('rpc_onb_template_get', {
        p_template_id: templateId,
      }).then(r => ({ template: r.template }))
    },
    async list() {
      return callRpc<{ templates: OnboardingTemplate[] }>('rpc_onb_template_list')
    },
    async update(templateId: string, payload: Partial<Pick<OnboardingTemplate, 'name' | 'description' | 'active'>>) {
      return callRpc<{ template_id: string }>('rpc_onb_template_update', {
        p_template_id: templateId,
        p_payload: payload,
      })
    },
    async addStage(input: { templateId: string; title: string; description?: string; orderIndex?: number }) {
      return callRpc<{ stage_id: string }>('rpc_onb_template_stage_add', {
        p_template_id: input.templateId,
        p_title: input.title,
        p_description: input.description ?? null,
        p_order_index: input.orderIndex ?? null,
      })
    },
    async addTask(input: {
      stageId: string
      title: string
      description?: string
      orderIndex?: number
    }) {
      return callRpc<{ task_id: string }>('rpc_onb_template_task_add', {
        p_stage_id: input.stageId,
        p_title: input.title,
        p_description: input.description ?? null,
        p_order_index: input.orderIndex ?? null,
      })
    },
  },

  // ----- Journeys --------------------------------------------------------
  async createBlank(input: { subjectId: string }) {
    return callRpc<{ journey_id: string }>('rpc_onboarding_create_blank', {
      p_subject_id: input.subjectId,
    })
  },

  async createFromTemplate(input: { subjectId: string; templateId: string }) {
    return callRpc<{ journey_id: string }>('rpc_onboarding_create_from_template', {
      p_subject_id: input.subjectId,
      p_template_id: input.templateId,
    })
  },

  async list(filters: { status?: OnboardingStatus; subjectId?: string } = {}) {
    return callRpc<{ journeys: OnboardingJourney[] }>('rpc_onboarding_list', {
      p_status: filters.status ?? null,
      p_subject_id: filters.subjectId ?? null,
    })
  },

  async getById(journeyId: string): Promise<{ journey: OnboardingJourney }> {
    return callRpc<{ journey: OnboardingJourney }>('rpc_onboarding_get_by_id', {
      p_journey_id: journeyId,
    }).then(r => ({ journey: r.journey }))
  },

  async changeStatus(journeyId: string, newStatus: OnboardingStatus) {
    return callRpc<{ journey_id: string }>('rpc_onboarding_change_status', {
      p_journey_id: journeyId,
      p_new_status: newStatus,
    })
  },

  async addStage(input: { journeyId: string; title: string; description?: string }) {
    return callRpc<{ stage_id: string }>('rpc_onboarding_stage_add', {
      p_journey_id: input.journeyId,
      p_title: input.title,
      p_description: input.description ?? null,
    })
  },

  async addTask(input: { stageId: string; title: string; description?: string }) {
    return callRpc<{ task_id: string }>('rpc_onboarding_task_add', {
      p_stage_id: input.stageId,
      p_title: input.title,
      p_description: input.description ?? null,
    })
  },

  async completeTask(taskId: string) {
    return callRpc<{ task_id: string }>('rpc_onboarding_task_complete', {
      p_task_id: taskId,
    })
  },

  async uncompleteTask(taskId: string) {
    return callRpc<{ task_id: string }>('rpc_onboarding_task_uncomplete', {
      p_task_id: taskId,
    })
  },
}

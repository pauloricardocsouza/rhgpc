/**
 * R2 People · Adapter · Employees (Sessao E1)
 * ============================================================================
 * Ficha de empregado: gestao completa do registro de funcionario.
 *
 * Modelo:
 *   - employee (principal)
 *   - salary_history (lista de reajustes)
 *   - vacations (periodos aquisitivo/gozo/abono)
 *   - leaves (afastamentos por doenca/acidente)
 *
 * Importar via XLSX:
 *   - Frontend parseia o XLSX com SheetJS
 *   - Envia para Employees.importXlsx que cria com idempotencia por CPF
 *
 * Importar via PDF:
 *   - Stub presente · OCR roda fora do banco (edge function ou processo local)
 *   - Endpoint a definir em sessao futura
 * ============================================================================
 */

import { callRpc } from './base'

// ============================================================================
// Enums espelhados
// ============================================================================

export type MaritalStatus =
  | 'solteiro' | 'casado' | 'divorciado' | 'viuvo' | 'separado'
  | 'uniao_estavel' | 'nao_informado'

export type RaceColor =
  | 'branca' | 'preta' | 'parda' | 'amarela' | 'indigena' | 'nao_informada'

export type EducationLevel =
  | 'analfabeto'
  | 'fundamental_1_5_incompleto' | 'fundamental_1_5_completo'
  | 'fundamental_6_9_incompleto' | 'fundamental_6_9_completo'
  | 'medio_incompleto' | 'medio_completo'
  | 'superior_incompleto' | 'superior_completo'
  | 'pos_graduacao' | 'mestrado' | 'doutorado'
  | 'nao_informado'

export type SalaryUnit = 'mes' | 'hora' | 'dia' | 'semana' | 'quinzena'

export type DismissalType =
  | 'demitido_sem_justa_causa' | 'demitido_com_justa_causa'
  | 'pedido_demissao' | 'rescisao_indireta'
  | 'termino_contrato_experiencia' | 'termino_contrato_determinado'
  | 'aposentadoria' | 'falecimento'
  | 'rescisao_acordo' | 'rescisao_antecipada_contrato'
  | 'outro'

export type LeaveReason =
  | 'acidente_trabalho' | 'doenca_comum' | 'doenca_ocupacional'
  | 'auxilio_maternidade' | 'auxilio_paternidade'
  | 'servico_militar' | 'outro'

export type VacationKind = 'aquisitivo' | 'gozo' | 'abono_pecuniario'

export type EmployeeSex = 'masculino' | 'feminino' | 'nao_informado'

export type EmployeeStatus = 'active' | 'terminated' | 'all'

// ============================================================================
// Tipos
// ============================================================================

export interface EmployeeListItem {
  id: string
  matricula_esocial: string | null
  full_name: string
  cpf: string | null
  job_title: string
  cbo: string | null
  hire_date: string
  termination_date: string | null
  termination_type: DismissalType | null
  employer_unit_id: string | null
  employer_unit_name: string | null
  working_unit_id: string | null
  working_unit_name: string | null
  phone_mobile: string | null
  is_active: boolean
  source: 'manual' | 'xlsx_import' | 'pdf_ocr'
}

export interface Employee {
  id: string
  tenant_id: string
  employer_unit_id: string | null
  employer_unit_name?: string | null
  working_unit_id: string | null
  working_unit_name?: string | null
  department_id: string | null
  department_name?: string | null

  // Identificacao
  matricula_esocial: string | null
  ficha_numero: string | null
  full_name: string
  beneficiaries: string | null

  // Documentos
  cpf: string | null
  rg: string | null
  rg_issue_date: string | null
  rg_issuer: string | null
  voter_id: string | null
  voter_zone: string | null
  voter_section: string | null
  ctps_number: string | null
  ctps_serie: string | null
  ctps_issue_date: string | null
  ctps_uf: string | null
  pis: string | null
  military_doc: string | null
  cnh: string | null
  cnh_category: string | null

  // Pessoal
  birth_date: string | null
  birth_city: string | null
  birth_state: string | null
  nationality: string | null
  marital_status: MaritalStatus
  sex: EmployeeSex
  race_color: RaceColor
  education: EducationLevel
  has_disability: boolean
  disability_description: string | null
  father_name: string | null
  mother_name: string | null

  // Contato
  residence_address: string | null
  residence_cep: string | null
  phone_home: string | null
  phone_mobile: string | null
  email: string | null

  // Vinculo
  job_title: string
  job_function: string | null
  cbo: string | null
  hire_date: string
  initial_salary: number | null
  salary_unit: SalaryUnit
  work_schedule_start: string | null
  work_schedule_end: string | null
  break_start: string | null
  break_end: string | null
  fgts_opt_in_date: string | null
  bank_account: string | null

  // Rescisao
  termination_date: string | null
  termination_type: DismissalType | null
  termination_reason: string | null

  // Meta
  created_at: string
  updated_at: string
  archived_at: string | null
  source: 'manual' | 'xlsx_import' | 'pdf_ocr'
  is_active: boolean
}

export interface SalaryHistoryEntry {
  id: string
  employee_id: string
  tenant_id: string
  effective_date: string
  amount: number
  unit: SalaryUnit
  job_title: string | null
  job_function: string | null
  cbo: string | null
  change_type: 'adjustment' | 'promotion' | 'dissidio' | 'initial' | string
  observations: string | null
  created_at: string
}

export interface Vacation {
  id: string
  employee_id: string
  tenant_id: string
  kind: VacationKind
  start_date: string
  end_date: string
  paid_on_termination: boolean
  observations: string | null
  created_at: string
}

export interface Leave {
  id: string
  employee_id: string
  tenant_id: string
  start_date: string
  end_date: string | null
  reason: LeaveReason
  description: string | null
  cid: string | null
  inss_benefit: string | null
  created_at: string
}

export interface EmployeeDetailResult {
  employee: Employee
  salary_history: SalaryHistoryEntry[]
  vacations: Vacation[]
  leaves: Leave[]
}

export interface EmployeeListFilters {
  search?: string
  status?: EmployeeStatus
  employerUnitId?: string
  workingUnitId?: string
  jobTitle?: string
  limit?: number
  offset?: number
}

export interface EmployeeListResult {
  employees: EmployeeListItem[]
  total: number
  limit: number
  offset: number
}

export interface ImportResultError {
  index: number
  error: string
  full_name?: string
}

export interface ImportResult {
  total: number
  created: number
  skipped: number
  errors: ImportResultError[]
}

// ============================================================================
// Payload de create/update (todos os campos opcionais para PATCH)
// ============================================================================

export interface EmployeePayload {
  // Identificacao
  matricula_esocial?: string
  ficha_numero?: string
  full_name?: string
  beneficiaries?: string
  // Documentos
  cpf?: string
  rg?: string
  rg_issue_date?: string
  rg_issuer?: string
  voter_id?: string
  voter_zone?: string
  voter_section?: string
  ctps_number?: string
  ctps_serie?: string
  ctps_issue_date?: string
  ctps_uf?: string
  pis?: string
  military_doc?: string
  cnh?: string
  cnh_category?: string
  // Pessoal
  birth_date?: string
  birth_city?: string
  birth_state?: string
  nationality?: string
  marital_status?: MaritalStatus
  sex?: EmployeeSex
  race_color?: RaceColor
  education?: EducationLevel
  has_disability?: boolean
  disability_description?: string
  father_name?: string
  mother_name?: string
  // Contato
  residence_address?: string
  residence_cep?: string
  phone_home?: string
  phone_mobile?: string
  email?: string
  // Vinculo
  employer_unit_id?: string
  working_unit_id?: string
  department_id?: string
  job_title?: string
  job_function?: string
  cbo?: string
  hire_date?: string
  initial_salary?: number | string
  salary_unit?: SalaryUnit
  work_schedule_start?: string
  work_schedule_end?: string
  break_start?: string
  break_end?: string
  fgts_opt_in_date?: string
  bank_account?: string
  // Rescisao
  termination_date?: string | null
  termination_type?: DismissalType | null
  termination_reason?: string | null
  // Meta
  tenant_id?: string
  source?: 'manual' | 'xlsx_import' | 'pdf_ocr'
}

// ============================================================================
// API publica
// ============================================================================

export const Employees = {
  /**
   * Lista funcionarios com filtros + paginacao.
   * search: busca por nome, CPF ou matricula
   */
  async list(filters: EmployeeListFilters = {}): Promise<EmployeeListResult> {
    return callRpc<EmployeeListResult>('rpc_employees_list', {
      p_search: filters.search ?? null,
      p_status: filters.status ?? 'all',
      p_employer_unit_id: filters.employerUnitId ?? null,
      p_working_unit_id: filters.workingUnitId ?? null,
      p_job_title: filters.jobTitle ?? null,
      p_limit: filters.limit ?? 50,
      p_offset: filters.offset ?? 0,
    })
  },

  /**
   * Retorna ficha completa + historico salarial + ferias + afastamentos.
   * Erro: `employee_not_found`
   */
  async getById(id: string): Promise<EmployeeDetailResult> {
    return callRpc<EmployeeDetailResult>('rpc_employees_get_by_id', { p_id: id })
  },

  /**
   * Cria nova ficha. Idempotente por CPF · se ja existe, retorna o id existente.
   * Erros: `full_name_required`, `hire_date_required`, `job_title_required`,
   *        `permission_denied`, `scope_outside_tenant`
   */
  async create(payload: EmployeePayload): Promise<{ id: string; created?: boolean; already_exists?: boolean }> {
    return callRpc<{ id: string; created?: boolean; already_exists?: boolean }>(
      'rpc_employees_create',
      { p_payload: payload },
    )
  },

  /**
   * Atualiza campos da ficha. Preserva campos nao passados.
   * Para limpar termination_date/type/reason, passe null explicito.
   * Audit automatico via trigger.
   */
  async update(id: string, payload: EmployeePayload): Promise<{ id: string; updated: boolean }> {
    return callRpc<{ id: string; updated: boolean }>('rpc_employees_update', {
      p_id: id,
      p_payload: payload,
    })
  },

  /**
   * Adiciona uma linha de historico salarial.
   */
  async salaryAdd(employeeId: string, payload: {
    effectiveDate: string
    amount: number | string
    unit?: SalaryUnit
    jobTitle?: string
    jobFunction?: string
    cbo?: string
    changeType?: 'adjustment' | 'promotion' | 'dissidio' | 'initial'
    observations?: string
  }): Promise<{ id: string }> {
    return callRpc<{ id: string }>('rpc_employees_salary_add', {
      p_employee_id: employeeId,
      p_payload: {
        effective_date: payload.effectiveDate,
        amount: payload.amount,
        unit: payload.unit ?? 'mes',
        job_title: payload.jobTitle ?? null,
        job_function: payload.jobFunction ?? null,
        cbo: payload.cbo ?? null,
        change_type: payload.changeType ?? 'adjustment',
        observations: payload.observations ?? null,
      },
    })
  },

  /**
   * Adiciona um periodo de ferias (aquisitivo, gozo ou abono).
   */
  async vacationAdd(employeeId: string, payload: {
    kind: VacationKind
    startDate: string
    endDate: string
    paidOnTermination?: boolean
    observations?: string
  }): Promise<{ id: string }> {
    return callRpc<{ id: string }>('rpc_employees_vacation_add', {
      p_employee_id: employeeId,
      p_payload: {
        kind: payload.kind,
        start_date: payload.startDate,
        end_date: payload.endDate,
        paid_on_termination: payload.paidOnTermination ?? false,
        observations: payload.observations ?? null,
      },
    })
  },

  /**
   * Adiciona um afastamento (doenca, acidente, etc).
   * endDate null = ainda afastado.
   */
  async leaveAdd(employeeId: string, payload: {
    startDate: string
    endDate?: string
    reason?: LeaveReason
    description?: string
    cid?: string
    inssBenefit?: string
  }): Promise<{ id: string }> {
    return callRpc<{ id: string }>('rpc_employees_leave_add', {
      p_employee_id: employeeId,
      p_payload: {
        start_date: payload.startDate,
        end_date: payload.endDate ?? null,
        reason: payload.reason ?? 'doenca_comum',
        description: payload.description ?? null,
        cid: payload.cid ?? null,
        inss_benefit: payload.inssBenefit ?? null,
      },
    })
  },

  /**
   * Soft-delete · marca como arquivado.
   */
  async archive(id: string): Promise<{ id: string; archived: boolean }> {
    return callRpc<{ id: string; archived: boolean }>('rpc_employees_archive', { p_id: id })
  },

  /**
   * Importacao em batch via JSON parseado de XLSX.
   * Cada registro segue o EmployeePayload. Idempotente por CPF.
   * Retorna { total, created, skipped, errors[] }.
   */
  async importXlsx(records: EmployeePayload[]): Promise<ImportResult> {
    return callRpc<ImportResult>('rpc_employees_import_xlsx', {
      p_records: records,
    })
  },

  /**
   * Verifica se um CPF já está cadastrado no tenant atual.
   * Retorna { exists: false } ou { exists: true, id, full_name, matricula_esocial, is_active }.
   * Use antes do submit para mostrar aviso de duplicação com link para a ficha existente.
   */
  async checkCpf(cpf: string): Promise<{
    exists: boolean
    id?: string
    full_name?: string
    matricula_esocial?: string | null
    is_active?: boolean
    reason?: 'invalid_format'
  }> {
    return callRpc('rpc_employees_check_cpf', { p_cpf: cpf })
  },

  /**
   * Sessao F1 · resumo de gestao da pessoa (avaliacoes 9-Box, PDIs,
   * reconhecimentos, onboardings).
   *
   * Permissao: super_admin, diretoria, rh ou gestor direto da pessoa.
   * Erros:
   *   - 'permission_denied' · usuario nao tem direito de ver
   *   - 'employee_not_found' · ficha inexistente ou em outro tenant
   *
   * Quando a ficha nao tem app_user vinculado, retorna has_app_user=false
   * com arrays vazios (UI mostra mensagem explicativa).
   */
  async gestaoSummary(employeeId: string): Promise<GestaoSummary> {
    return callRpc<GestaoSummary>('rpc_employees_gestao_summary', { p_employee_id: employeeId })
  },

  /**
   * Sessao F1 · stub para importacao via PDF.
   * Por enquanto, o usuario roda o script `extrair_fichas_dominio.py`
   * localmente, gera o XLSX e usa importXlsx. Pode ser substituido por
   * edge function futura.
   */
  async importPdf(_pdfBlob: Blob): Promise<never> {
    throw new Error(
      'PDF OCR ainda nao implementado server-side. ' +
      'Use o script extrair_fichas_dominio.py para gerar XLSX, depois Employees.importXlsx.',
    )
  },
}

// ============================================================================
// Sessao F1 · "Minha equipe"
// ============================================================================

export interface TeamMember {
  id: string                       // app_user_id
  employee_id: string | null
  full_name: string | null         // do employees (preferencial)
  app_user_name: string            // fallback do app_users
  email: string
  role: string
  job_title: string | null
  employer_unit_name: string | null
  working_unit_name: string | null
  depth: number                    // 1 = direto, 2+ = indireto
  is_direct_report: boolean
  is_active: boolean
  pdis_active: number
  last_evaluation_box: string | null
  recognitions_30d: number
  onboarding_active: boolean
}

export interface MyTeamResult {
  team: TeamMember[]
  include_indirect: boolean
}

export interface GestaoEvaluation {
  id: string
  cycle_id: string | null
  cycle_name: string | null
  status: string
  is_adhoc: boolean
  final_box_label: string | null
  final_box_row: number | null
  final_box_col: number | null
  final_potential_score: number | null
  final_performance_score: number | null
  manager_name: string | null
  finalized_at: string | null
  created_at: string
}

export interface GestaoPdi {
  id: string
  cycle_id: string | null
  cycle_name: string | null
  objective: string
  status: 'draft' | 'active' | 'completed' | 'canceled' | string
  start_date: string | null
  end_date: string | null
  actions_total: number
  actions_completed: number
  manager_name: string | null
  activated_at: string | null
  completed_at: string | null
  created_at: string
}

export interface GestaoRecognition {
  id: string
  message: string
  is_private: boolean
  sender_id: string
  sender_name: string | null
  reactions_count: number
  created_at: string
}

export interface GestaoOnboarding {
  id: string
  display_name: string
  status: 'not_started' | 'in_progress' | 'completed' | 'canceled' | string
  start_date: string | null
  target_end_date: string | null
  tasks_total: number
  tasks_completed: number
  tasks_required: number
  tasks_required_done: number
  started_at: string | null
  completed_at: string | null
  created_at: string
}

export interface GestaoSummary {
  has_app_user: boolean
  app_user_id?: string
  app_user_role?: string
  evaluations: GestaoEvaluation[]
  pdis: GestaoPdi[]
  recognitions: GestaoRecognition[]
  onboardings: GestaoOnboarding[]
}

/**
 * Sessao F1 · lista subordinados do usuario logado.
 * include_indirect=true puxa toda a subarvore (subordinados dos subordinados),
 * limitada em 10 niveis para evitar loops.
 */
export async function myTeam(includeIndirect = false): Promise<MyTeamResult> {
  return callRpc<MyTeamResult>('rpc_my_team', { p_include_indirect: includeIndirect })
}

// ============================================================================
// Sessao F3 · Dashboard da equipe
// ============================================================================

export interface PdiOverdueItem {
  pdi_id: string
  objective: string
  user_id: string
  employee_id: string | null
  user_name: string
  job_title: string | null
  cycle_name: string | null
  end_date: string
  days_overdue: number
  actions_total: number
  actions_completed: number
  progress_pct: number
}

export interface RecognitionRanking {
  user_id: string
  employee_id: string | null
  user_name: string
  job_title: string | null
  total: number
  public_count?: number
  private_count?: number
}

export interface MyTeamDashboardResult {
  include_indirect: boolean
  team_size: number
  pdis_overdue: PdiOverdueItem[]
  recognitions_top_recipients: RecognitionRanking[]
  recognitions_top_senders: RecognitionRanking[]
}

/**
 * Sessao F3 · agregados pre-calculados para a tela /minha-equipe:
 *   - PDIs em atraso (status='active' com end_date passada)
 *   - Top 10 recipients e senders de reconhecimentos (90d)
 *
 * A grade 9-Box e calculada no frontend a partir de myTeam().
 */
export async function myTeamDashboard(includeIndirect = false): Promise<MyTeamDashboardResult> {
  return callRpc<MyTeamDashboardResult>('rpc_my_team_dashboard', {
    p_include_indirect: includeIndirect,
  })
}

// ============================================================================
// Sessao F4 · Tenant Dashboard
// ============================================================================

export type DashboardScope = 'full' | 'hierarchy'

export interface TenantHeadcount {
  total_active: number
  total_terminated: number
  hired_30d: number
  hired_90d: number
  terminated_30d: number
  terminated_90d: number
  by_employer_unit: Array<{
    unit_id: string
    unit_name: string | null
    count: number
  }>
  by_department: Array<{
    department_id: string
    department_name: string | null
    count: number
  }>
}

export interface NineboxBucket {
  box_label: string
  box_row: number | null
  box_col: number | null
  count: number
}

export interface PdiOverdueByManager {
  manager_id: string | null
  manager_name: string | null
  manager_email: string | null
  overdue_count: number
  worst_overdue_days: number
}

export interface TenantDashboardResult {
  scope: DashboardScope
  universe_size: number
  headcount: TenantHeadcount
  ninebox_distribution: NineboxBucket[]
  pdis_overdue_by_manager: PdiOverdueByManager[]
  recognition_top_recipients: RecognitionRanking[]
  recognition_top_senders: RecognitionRanking[]
}

/**
 * Sessao F4 · Dashboard tenant-wide para RH/diretoria.
 * Lideres veem com escopo 'hierarchy' (apenas sua subarvore).
 * Colaboradores comuns recebem 'permission_denied'.
 */
export async function tenantDashboard(): Promise<TenantDashboardResult> {
  return callRpc<TenantDashboardResult>('rpc_tenant_dashboard', {})
}

// ============================================================================
// Sessao F6 · Dashboard Drilldown
// ============================================================================

export type DrillKind =
  | 'ninebox'
  | 'employer_unit'
  | 'department'
  | 'headcount_metric'
  | 'pdis_by_manager'

export type HeadcountMetric =
  | 'total_active'
  | 'total_terminated'
  | 'hired_30d'
  | 'hired_90d'
  | 'terminated_30d'
  | 'terminated_90d'

export interface DrillItem {
  // Sempre presentes
  full_name: string
  chip_label: string
  job_title: string | null
  unit_name: string | null
  department_name?: string | null

  // Variam por kind
  app_user_id?: string
  employee_id?: string | null
  pdi_id?: string

  // ninebox
  box_row?: number
  box_col?: number

  // headcount_metric
  hire_date?: string
  termination_date?: string | null

  // pdis_by_manager
  objective?: string
  end_date?: string
  days_overdue?: number
  actions_total?: number
  actions_completed?: number
}

export interface DrillResult {
  scope: DashboardScope
  kind: DrillKind
  universe_size: number
  count: number
  items: DrillItem[]
}

/**
 * Sessao F6 · drilldown a partir do dashboard.
 *
 * Por kind:
 *   - ninebox            valueInt1=row, valueInt2=col
 *   - employer_unit      value=unit_id
 *   - department         value=department_id
 *   - headcount_metric   value=metric (total_active/hired_30d/...)
 *   - pdis_by_manager    value=manager_id
 */
export async function dashboardDrill(input: {
  kind: DrillKind
  value?: string
  valueInt1?: number
  valueInt2?: number
}): Promise<DrillResult> {
  return callRpc<DrillResult>('rpc_dashboard_drill', {
    p_kind: input.kind,
    p_value_text: input.value ?? null,
    p_value_int1: input.valueInt1 ?? null,
    p_value_int2: input.valueInt2 ?? null,
  })
}

// ============================================================================
// Sessao G1 · Minha Jornada
// ============================================================================

export interface MyJourneyIdentity {
  app_user_id: string
  employee_id: string | null
  email: string
  full_name: string
  role: string
  job_title: string | null
  employment_link: string | null
  hired_at: string | null
  hire_date: string | null
  birth_date: string | null
  employer_unit: {
    id: string
    trade_name: string
    legal_name: string
    city: string | null
    state_uf: string | null
  } | null
  working_unit: {
    id: string
    trade_name: string
    city: string | null
    state_uf: string | null
  } | null
  department: {
    id: string
    display_name: string
  } | null
  manager: {
    id: string
    email: string
    full_name: string
  } | null
}

export interface MyJourneyPdiKpis {
  active: number
  completed: number
  draft: number
  canceled: number
  overdue: number
  actions_total: number
  actions_completed: number
}

export interface MyJourneyRecogKpis {
  received_total: number
  received_90d: number
  sent_total: number
  sent_90d: number
}

export interface MyJourneyLastNinebox {
  evaluation_id: string
  box_label: string
  box_row: number
  box_col: number
  finalized_at: string
  cycle_name: string | null
  is_adhoc: boolean
}

export interface MyJourneyOnboardingKpis {
  active: number
  completed: number
  tasks_total: number
  tasks_completed: number
}

export interface MyJourneyResult {
  identity: MyJourneyIdentity
  pdi_kpis: MyJourneyPdiKpis
  recog_kpis: MyJourneyRecogKpis
  last_ninebox: MyJourneyLastNinebox | null
  onboarding_kpis: MyJourneyOnboardingKpis
}

/**
 * Sessao G1 · snapshot agregado da propria jornada (identidade + KPIs).
 * Listas detalhadas (PDIs, reconhecimentos) sao buscadas por RPCs separadas.
 */
export async function myJourney(): Promise<MyJourneyResult> {
  return callRpc<MyJourneyResult>('rpc_my_journey', {})
}

// ============================================================================
// Sessao G2 · Feed de reconhecimentos enviados
// ============================================================================

export interface SentRecognition {
  id: string
  message: string
  is_private: boolean
  recipient_id: string
  recipient_name: string | null
  recipient_employee_id: string | null
  recipient_job_title: string | null
  reactions_count: number
  created_at: string
}

export interface SentRecognitionsResult {
  items: SentRecognition[]
  limit: number
}

export async function mySentRecognitions(limit = 10): Promise<SentRecognitionsResult> {
  return callRpc<SentRecognitionsResult>('rpc_my_sent_recognitions', { p_limit: limit })
}

// ============================================================================
// Sessao G3 · Solicitacoes de alteracao de dados pessoais
// ============================================================================

export type ProfileChangeField =
  | 'phone_mobile'
  | 'phone_home'
  | 'personal_email'
  | 'residence_address'
  | 'emergency_contact'
  | 'photo'

export type ProfileChangeStatus = 'pending' | 'approved' | 'rejected' | 'canceled'

export interface ProfileChangeRequest {
  id: string
  field: ProfileChangeField
  old_value: Record<string, unknown> | null
  new_value: Record<string, unknown>
  pending_photo_path: string | null
  status: ProfileChangeStatus
  rejection_reason: string | null
  reviewed_at: string | null
  reviewer_name: string | null
  created_at: string
}

export interface PendingProfileChangeRequest {
  id: string
  employee_id: string
  employee_name: string
  employee_job_title: string | null
  field: ProfileChangeField
  old_value: Record<string, unknown> | null
  new_value: Record<string, unknown>
  pending_photo_path: string | null
  requested_by_name: string | null
  created_at: string
}

/** Cria uma nova solicitacao de alteracao do proprio perfil */
export async function myProfileRequestCreate(input: {
  field: ProfileChangeField
  newValue: Record<string, unknown>
  pendingPhotoPath?: string
}): Promise<{ request_id: string }> {
  return callRpc<{ request_id: string }>('rpc_my_profile_request_create', {
    p_field: input.field,
    p_new_value: input.newValue,
    p_pending_photo_path: input.pendingPhotoPath ?? null,
  })
}

/** Lista as proprias solicitacoes (qualquer status) */
export async function myProfileRequestsList(limit = 20): Promise<{ items: ProfileChangeRequest[] }> {
  return callRpc<{ items: ProfileChangeRequest[] }>('rpc_my_profile_requests_list', { p_limit: limit })
}

/** Cancela uma solicitacao propria ainda pendente */
export async function myProfileRequestCancel(requestId: string): Promise<{ ok: true }> {
  return callRpc<{ ok: true }>('rpc_my_profile_request_cancel', { p_request_id: requestId })
}

/** RH/diretoria/SA · lista fila de solicitacoes pendentes do tenant */
export async function profileRequestsPendingList(): Promise<{ items: PendingProfileChangeRequest[] }> {
  return callRpc<{ items: PendingProfileChangeRequest[] }>('rpc_profile_requests_pending_list', {})
}

/** RH/diretoria/SA · aprova e aplica em employees */
export async function profileRequestApprove(requestId: string): Promise<{ request_id: string }> {
  return callRpc<{ request_id: string }>('rpc_profile_request_approve', { p_request_id: requestId })
}

/** RH/diretoria/SA · rejeita com motivo (>= 3 chars) */
export async function profileRequestReject(requestId: string, reason: string): Promise<{ ok: true }> {
  return callRpc<{ ok: true }>('rpc_profile_request_reject', {
    p_request_id: requestId,
    p_reason: reason,
  })
}

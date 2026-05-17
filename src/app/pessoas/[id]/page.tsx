'use client'

/**
 * R2 People · /pessoas/[id]
 * ============================================================================
 * Ficha completa estilo LinkedIn:
 *   - Header com avatar grande, nome, cargo, empresa, badge de status
 *   - Sidebar fixa esquerda · identidade resumida (CPF, RG, nascimento, contatos)
 *   - Main coluna · secoes colapsaveis
 *     1. Dados pessoais (filiacao, naturalidade, cor, escolaridade, etc)
 *     2. Documentos (RG, CTPS, titulo eleitor, PIS, CNH)
 *     3. Vinculo (admissao, jornada, cargo, CBO, salario inicial)
 *     4. Historico salarial (tabela cronologica)
 *     5. Ferias (aquisitivo, gozo, abono)
 *     6. Afastamentos (acidentes, doencas)
 *     7. Auditoria (eventos do registro)
 *
 * Edicao: botao "Editar" abre modal por secao · grava com audit per-field.
 * ============================================================================
 */

import { useState, useEffect, useCallback } from 'react'
import { useParams, useRouter } from 'next/navigation'
import Link from 'next/link'
import {
  ChevronLeft, ChevronDown, ChevronRight, Pencil, Loader2,
  AlertTriangle, BadgeCheck, BadgeX, Mail, Phone, MapPin,
  Calendar, Briefcase, GraduationCap, Users as UsersIcon,
  TrendingUp, Plane, HeartPulse, FileText, CreditCard,
} from 'lucide-react'

import {
  Employees,
  RpcError,
  type EmployeeDetailResult,
  type EmployeePayload,
  type SalaryHistoryEntry,
  type Vacation,
  type Leave,
} from '@/lib/r2'

import { EditSectionDialog, type EditField } from '@/components/employees/EditSectionDialog'
import { GestaoSections } from '@/components/employees/GestaoSections'
import { ActionsDropdown } from '@/components/employees/actions/ActionsDropdown'

// ============================================================================
// Helpers
// ============================================================================

function formatDate(iso: string | null | undefined): string {
  if (!iso) return '-'
  const [y, m, d] = iso.split('-')
  return `${d}/${m}/${y}`
}

function formatMoney(amount: number | null | undefined, unit?: string): string {
  if (amount == null) return '-'
  const value = `R$ ${Number(amount).toLocaleString('pt-BR', { minimumFractionDigits: 2, maximumFractionDigits: 2 })}`
  return unit ? `${value} / ${unit}` : value
}

function getInitials(name: string): string {
  return name.split(/\s+/).filter(Boolean).slice(0, 2).map(w => w[0]).join('').toUpperCase()
}

function avatarColorFor(id: string): string {
  const colors = ['#818cf8', '#f472b6', '#34d399', '#fb923c', '#60a5fa', '#a78bfa', '#fbbf24', '#22d3ee', '#f87171', '#4ade80']
  const hash = id.split('').reduce((s, c) => s + c.charCodeAt(0), 0)
  return colors[hash % colors.length]
}

// Maps de label para os enums
const MARITAL_LABELS: Record<string, string> = {
  solteiro: 'Solteiro(a)',
  casado: 'Casado(a)',
  divorciado: 'Divorciado(a)',
  viuvo: 'Viúvo(a)',
  separado: 'Separado(a)',
  uniao_estavel: 'União estável',
  nao_informado: 'Não informado',
}

const RACE_LABELS: Record<string, string> = {
  branca: 'Branca',
  preta: 'Preta',
  parda: 'Parda',
  amarela: 'Amarela',
  indigena: 'Indígena',
  nao_informada: 'Não informada',
}

const EDUCATION_LABELS: Record<string, string> = {
  analfabeto: 'Analfabeto',
  fundamental_1_5_incompleto: 'Fundamental 1º-5º incompleto',
  fundamental_1_5_completo: 'Fundamental 1º-5º completo',
  fundamental_6_9_incompleto: 'Fundamental 6º-9º incompleto',
  fundamental_6_9_completo: 'Fundamental 6º-9º completo',
  medio_incompleto: 'Médio incompleto',
  medio_completo: 'Médio completo',
  superior_incompleto: 'Superior incompleto',
  superior_completo: 'Superior completo',
  pos_graduacao: 'Pós-graduação',
  mestrado: 'Mestrado',
  doutorado: 'Doutorado',
  nao_informado: 'Não informado',
}

const DISMISSAL_LABELS: Record<string, string> = {
  demitido_sem_justa_causa: 'Demitido sem justa causa',
  demitido_com_justa_causa: 'Demitido com justa causa',
  pedido_demissao: 'Pedido de demissão',
  rescisao_indireta: 'Rescisão indireta',
  termino_contrato_experiencia: 'Término do contrato de experiência',
  termino_contrato_determinado: 'Término do contrato por prazo determinado',
  aposentadoria: 'Aposentadoria',
  falecimento: 'Falecimento',
  rescisao_acordo: 'Rescisão por acordo',
  rescisao_antecipada_contrato: 'Rescisão antecipada do contrato',
  outro: 'Outro',
}

// ============================================================================
// Page component
// ============================================================================

export default function PessoaDetalhePage() {
  const params = useParams<{ id: string }>()
  const router = useRouter()
  const id = params.id

  const [data, setData] = useState<EmployeeDetailResult | null>(null)
  const [loading, setLoading] = useState(true)
  const [errorCode, setErrorCode] = useState<string | null>(null)
  // F2 · app_user_id descoberto pelo GestaoSections (necessario para acoes)
  const [appUserId, setAppUserId] = useState<string | null>(null)
  // F2 · contador que dispara refresh do GestaoSections apos uma acao
  const [actionsRefreshKey, setActionsRefreshKey] = useState(0)

  // Estado de seções colapsáveis · todas abertas por padrão
  const [openSections, setOpenSections] = useState<Set<string>>(
    new Set(['pessoal', 'documentos', 'vinculo', 'salarios', 'ferias', 'afastamentos']),
  )

  // Edit dialog
  const [editing, setEditing] = useState<{ section: string; title: string; fields: EditField[] } | null>(null)

  const fetchDetail = useCallback(async () => {
    setLoading(true)
    setErrorCode(null)
    try {
      const r = await Employees.getById(id)
      setData(r)
    } catch (err) {
      setErrorCode(err instanceof RpcError ? err.code : 'unknown_error')
    } finally {
      setLoading(false)
    }
  }, [id])

  useEffect(() => { fetchDetail() }, [fetchDetail])

  const toggleSection = (key: string) => {
    setOpenSections(prev => {
      const next = new Set(prev)
      if (next.has(key)) next.delete(key)
      else next.add(key)
      return next
    })
  }

  const saveEdit = async (payload: EmployeePayload) => {
    try {
      await Employees.update(id, payload)
      setEditing(null)
      await fetchDetail()
    } catch (err) {
      alert(`Erro ao salvar: ${err instanceof RpcError ? err.code : 'unknown_error'}`)
    }
  }

  if (loading) {
    return (
      <div className="flex items-center justify-center min-h-[60vh]">
        <Loader2 className="h-6 w-6 animate-spin text-zinc-400" />
      </div>
    )
  }

  if (errorCode || !data) {
    return (
      <div className="max-w-2xl mx-auto p-8">
        <Link href="/pessoas" className="text-sm text-zinc-600 hover:text-zinc-900 inline-flex items-center gap-1 mb-4">
          <ChevronLeft className="h-4 w-4" /> Voltar para pessoas
        </Link>
        <div className="border border-red-200 bg-red-50 rounded-md p-4 text-red-900">
          <div className="flex gap-2 items-start">
            <AlertTriangle className="h-5 w-5 mt-0.5" />
            <div>
              <h3 className="font-semibold">Erro ao carregar ficha</h3>
              <p className="text-sm mt-1 font-mono">{errorCode || 'unknown_error'}</p>
            </div>
          </div>
        </div>
      </div>
    )
  }

  const { employee: e, salary_history, vacations, leaves } = data

  return (
    <div className="max-w-6xl mx-auto p-6 space-y-4">
      <Link href="/pessoas" className="text-sm text-zinc-600 hover:text-zinc-900 inline-flex items-center gap-1">
        <ChevronLeft className="h-4 w-4" /> Pessoas
      </Link>

      {/* Header estilo LinkedIn */}
      <div className="bg-white border border-zinc-200 rounded-lg overflow-hidden">
        <div className="h-24 bg-gradient-to-r from-zinc-700 to-zinc-900" />
        <div className="px-6 pb-5 -mt-12">
          <div className="flex items-end justify-between gap-4">
            <div
              className="w-24 h-24 rounded-full ring-4 ring-white flex items-center justify-center text-white text-2xl font-semibold flex-shrink-0"
              style={{ background: avatarColorFor(e.id) }}
            >
              {getInitials(e.full_name) || '?'}
            </div>
            <div className="flex gap-2 pb-2 items-center">
              {!e.is_active && (
                <span className="text-xs font-semibold uppercase tracking-wide px-3 py-1 rounded-full bg-red-100 text-red-700 inline-flex items-center gap-1">
                  <BadgeX className="h-3 w-3" /> Desligado
                </span>
              )}
              {e.is_active && (
                <span className="text-xs font-semibold uppercase tracking-wide px-3 py-1 rounded-full bg-emerald-100 text-emerald-700 inline-flex items-center gap-1">
                  <BadgeCheck className="h-3 w-3" /> Ativo
                </span>
              )}
              {/* F2 · botão + Ação · só aparece se a ficha tem app_user vinculado */}
              {appUserId && (
                <ActionsDropdown
                  employeeId={e.id}
                  appUserId={appUserId}
                  employeeName={e.full_name}
                  onActionCompleted={() => setActionsRefreshKey(k => k + 1)}
                />
              )}
            </div>
          </div>

          <div className="mt-3">
            <h1 className="text-2xl font-semibold text-zinc-900">{e.full_name}</h1>
            <p className="text-zinc-600 mt-0.5">
              {e.job_title}{e.cbo && <span className="text-zinc-400"> · CBO {e.cbo}</span>}
            </p>
            {e.employer_unit_name && (
              <p className="text-sm text-zinc-500 mt-1 flex items-center gap-1.5">
                <Briefcase className="h-3.5 w-3.5" />
                {e.employer_unit_name}
                {e.working_unit_name && <span className="text-zinc-400">· {e.working_unit_name}</span>}
              </p>
            )}
            <div className="flex flex-wrap gap-3 mt-3 text-xs text-zinc-500">
              {e.matricula_esocial && (
                <span className="font-mono">Matrícula {e.matricula_esocial}</span>
              )}
              <span>Admissão: {formatDate(e.hire_date)}</span>
              {e.termination_date && (
                <span className="text-red-700">Saída: {formatDate(e.termination_date)}</span>
              )}
            </div>
          </div>
        </div>
      </div>

      {/* Grid sidebar + main */}
      <div className="grid grid-cols-1 lg:grid-cols-[280px_1fr] gap-4">
        {/* Sidebar identidade */}
        <aside className="bg-white border border-zinc-200 rounded-lg p-4 space-y-4 h-fit lg:sticky lg:top-4">
          <h3 className="text-xs font-semibold uppercase tracking-wider text-zinc-500">Identidade</h3>
          <IdentityField icon={CreditCard} label="CPF" value={e.cpf} mono />
          <IdentityField icon={CreditCard} label="RG" value={e.rg} mono extra={e.rg_issuer} />
          <IdentityField icon={Calendar} label="Nascimento" value={formatDate(e.birth_date)}
                         extra={e.birth_city ? `${e.birth_city} - ${e.birth_state || ''}` : null} />
          <IdentityField icon={Mail} label="Email" value={e.email} />
          <IdentityField icon={Phone} label="Celular" value={e.phone_mobile} />
          <IdentityField icon={Phone} label="Residencial" value={e.phone_home} />
          <IdentityField icon={MapPin} label="Endereço"
                         value={e.residence_address}
                         extra={e.residence_cep ? `CEP ${e.residence_cep}` : null} />
        </aside>

        {/* Main · seções colapsáveis */}
        <div className="space-y-4">
          {/* === Dados pessoais === */}
          <Section
            id="pessoal"
            title="Dados pessoais"
            icon={UsersIcon}
            open={openSections.has('pessoal')}
            onToggle={() => toggleSection('pessoal')}
            onEdit={() => setEditing({
              section: 'pessoal',
              title: 'Editar dados pessoais',
              fields: [
                { key: 'father_name', label: 'Nome do pai', value: e.father_name ?? '' },
                { key: 'mother_name', label: 'Nome da mãe', value: e.mother_name ?? '' },
                { key: 'birth_city', label: 'Cidade de nascimento', value: e.birth_city ?? '' },
                { key: 'birth_state', label: 'UF de nascimento', value: e.birth_state ?? '', maxLength: 2 },
                { key: 'nationality', label: 'Nacionalidade', value: e.nationality ?? '' },
                { key: 'marital_status', label: 'Estado civil', value: e.marital_status,
                  options: Object.entries(MARITAL_LABELS) },
                { key: 'sex', label: 'Sexo', value: e.sex,
                  options: [['masculino', 'Masculino'], ['feminino', 'Feminino'], ['nao_informado', 'Não informado']] },
                { key: 'race_color', label: 'Cor/raça', value: e.race_color,
                  options: Object.entries(RACE_LABELS) },
                { key: 'education', label: 'Escolaridade', value: e.education,
                  options: Object.entries(EDUCATION_LABELS) },
                { key: 'has_disability', label: 'Possui deficiência?', value: e.has_disability ? 'true' : 'false',
                  options: [['false', 'Não'], ['true', 'Sim']] },
              ],
            })}
          >
            <DataGrid>
              <DataItem label="Nome do pai" value={e.father_name} />
              <DataItem label="Nome da mãe" value={e.mother_name} />
              <DataItem label="Naturalidade" value={e.birth_city ? `${e.birth_city} - ${e.birth_state ?? ''}` : null} />
              <DataItem label="Nacionalidade" value={e.nationality} />
              <DataItem label="Estado civil" value={MARITAL_LABELS[e.marital_status]} />
              <DataItem label="Sexo" value={e.sex === 'nao_informado' ? null : e.sex} />
              <DataItem label="Cor/raça" value={RACE_LABELS[e.race_color]} />
              <DataItem label="Escolaridade" value={EDUCATION_LABELS[e.education]} icon={GraduationCap} />
              <DataItem label="Possui deficiência" value={e.has_disability ? 'Sim' : 'Não'} />
              {e.beneficiaries && <DataItem label="Beneficiários" value={e.beneficiaries} fullWidth />}
            </DataGrid>
          </Section>

          {/* === Documentos === */}
          <Section
            id="documentos"
            title="Documentos"
            icon={FileText}
            open={openSections.has('documentos')}
            onToggle={() => toggleSection('documentos')}
            onEdit={() => setEditing({
              section: 'documentos',
              title: 'Editar documentos',
              fields: [
                { key: 'cpf', label: 'CPF', value: e.cpf ?? '' },
                { key: 'rg', label: 'RG', value: e.rg ?? '' },
                { key: 'rg_issuer', label: 'Órgão emissor RG', value: e.rg_issuer ?? '' },
                { key: 'rg_issue_date', label: 'Data emissão RG (AAAA-MM-DD)', value: e.rg_issue_date ?? '' },
                { key: 'ctps_number', label: 'CTPS número', value: e.ctps_number ?? '' },
                { key: 'ctps_serie', label: 'CTPS série', value: e.ctps_serie ?? '' },
                { key: 'pis', label: 'PIS', value: e.pis ?? '' },
                { key: 'voter_id', label: 'Título eleitoral', value: e.voter_id ?? '' },
                { key: 'cnh', label: 'CNH', value: e.cnh ?? '' },
              ],
            })}
          >
            <DataGrid>
              <DataItem label="CPF" value={e.cpf} mono />
              <DataItem label="RG" value={e.rg} mono extra={e.rg_issuer} />
              <DataItem label="Data emissão RG" value={formatDate(e.rg_issue_date)} />
              <DataItem label="CTPS" value={e.ctps_number ? `${e.ctps_number} série ${e.ctps_serie}` : null} mono />
              <DataItem label="CTPS UF / expedição" value={e.ctps_uf ? `${e.ctps_uf} · ${formatDate(e.ctps_issue_date)}` : null} />
              <DataItem label="PIS" value={e.pis} mono />
              <DataItem label="Título eleitoral" value={e.voter_id}
                        extra={e.voter_zone ? `Zona ${e.voter_zone}, seção ${e.voter_section}` : null} mono />
              <DataItem label="CNH" value={e.cnh} mono extra={e.cnh_category ? `Categoria ${e.cnh_category}` : null} />
              <DataItem label="Doc. militar" value={e.military_doc} mono />
            </DataGrid>
          </Section>

          {/* === Vínculo === */}
          <Section
            id="vinculo"
            title="Vínculo"
            icon={Briefcase}
            open={openSections.has('vinculo')}
            onToggle={() => toggleSection('vinculo')}
            onEdit={() => setEditing({
              section: 'vinculo',
              title: 'Editar vínculo',
              fields: [
                { key: 'job_title', label: 'Cargo', value: e.job_title, required: true },
                { key: 'job_function', label: 'Função', value: e.job_function ?? '' },
                { key: 'cbo', label: 'CBO', value: e.cbo ?? '' },
                { key: 'hire_date', label: 'Data de admissão (AAAA-MM-DD)', value: e.hire_date, required: true },
                { key: 'initial_salary', label: 'Salário inicial (somente número)', value: String(e.initial_salary ?? '') },
                { key: 'salary_unit', label: 'Periodicidade', value: e.salary_unit,
                  options: [['mes', 'Mês'], ['hora', 'Hora'], ['dia', 'Dia'], ['semana', 'Semana'], ['quinzena', 'Quinzena']] },
                { key: 'work_schedule_start', label: 'Início da jornada (HH:MM)', value: e.work_schedule_start ?? '' },
                { key: 'work_schedule_end', label: 'Fim da jornada (HH:MM)', value: e.work_schedule_end ?? '' },
                { key: 'break_start', label: 'Início do intervalo (HH:MM)', value: e.break_start ?? '' },
                { key: 'break_end', label: 'Fim do intervalo (HH:MM)', value: e.break_end ?? '' },
                { key: 'termination_date', label: 'Data de saída (AAAA-MM-DD ou vazio)', value: e.termination_date ?? '' },
                { key: 'termination_type', label: 'Tipo de desligamento', value: e.termination_type ?? '',
                  options: [['', '— Ativo —'], ...Object.entries(DISMISSAL_LABELS)] },
                { key: 'termination_reason', label: 'Motivo do desligamento', value: e.termination_reason ?? '', textarea: true },
              ],
            })}
          >
            <DataGrid>
              <DataItem label="Cargo" value={e.job_title} />
              <DataItem label="Função" value={e.job_function} />
              <DataItem label="CBO" value={e.cbo} mono />
              <DataItem label="Data de admissão" value={formatDate(e.hire_date)} icon={Calendar} />
              <DataItem label="Salário inicial" value={formatMoney(e.initial_salary, e.salary_unit)} />
              <DataItem label="Jornada"
                        value={e.work_schedule_start && e.work_schedule_end
                          ? `${e.work_schedule_start} às ${e.work_schedule_end}` : null} />
              <DataItem label="Intervalo"
                        value={e.break_start && e.break_end
                          ? `${e.break_start} às ${e.break_end}` : null} />
              <DataItem label="FGTS opção" value={formatDate(e.fgts_opt_in_date)} />
              {e.termination_date && (
                <>
                  <DataItem label="Data de saída" value={formatDate(e.termination_date)} />
                  <DataItem label="Tipo de desligamento" value={e.termination_type ? DISMISSAL_LABELS[e.termination_type] : null} />
                  {e.termination_reason && <DataItem label="Motivo" value={e.termination_reason} fullWidth />}
                </>
              )}
            </DataGrid>
          </Section>

          {/* === Histórico salarial === */}
          <Section
            id="salarios"
            title={`Histórico salarial (${salary_history.length})`}
            icon={TrendingUp}
            open={openSections.has('salarios')}
            onToggle={() => toggleSection('salarios')}
          >
            <SalaryTable entries={salary_history} />
          </Section>

          {/* === Férias === */}
          <Section
            id="ferias"
            title={`Férias (${vacations.length})`}
            icon={Plane}
            open={openSections.has('ferias')}
            onToggle={() => toggleSection('ferias')}
          >
            <VacationsTable entries={vacations} />
          </Section>

          {/* === Afastamentos === */}
          <Section
            id="afastamentos"
            title={`Afastamentos (${leaves.length})`}
            icon={HeartPulse}
            open={openSections.has('afastamentos')}
            onToggle={() => toggleSection('afastamentos')}
          >
            <LeavesTable entries={leaves} />
          </Section>

          {/* F1 · gestão (4 seções extras, condicionadas a permissão no backend) */}
          <GestaoSections
            employeeId={e.id}
            onAppUserResolved={setAppUserId}
            refreshKey={actionsRefreshKey}
          />
        </div>
      </div>

      {editing && (
        <EditSectionDialog
          title={editing.title}
          fields={editing.fields}
          onCancel={() => setEditing(null)}
          onSave={saveEdit}
        />
      )}
    </div>
  )
}

// ============================================================================
// Helper components
// ============================================================================

function IdentityField({
  icon: Icon, label, value, mono, extra,
}: {
  icon: React.ComponentType<{ className?: string }>
  label: string
  value: string | null | undefined
  mono?: boolean
  extra?: string | null
}) {
  return (
    <div className="text-sm">
      <div className="text-[10px] uppercase tracking-wider text-zinc-500 font-semibold flex items-center gap-1">
        <Icon className="h-3 w-3" />
        {label}
      </div>
      <div className={mono ? 'font-mono text-xs mt-0.5 text-zinc-900' : 'mt-0.5 text-zinc-900'}>
        {value || <span className="text-zinc-400 italic font-sans text-xs">não informado</span>}
      </div>
      {extra && <div className="text-xs text-zinc-500 mt-0.5">{extra}</div>}
    </div>
  )
}

function Section({
  id: _id, title, icon: Icon, open, onToggle, onEdit, children,
}: {
  id: string
  title: string
  icon: React.ComponentType<{ className?: string }>
  open: boolean
  onToggle: () => void
  onEdit?: () => void
  children: React.ReactNode
}) {
  return (
    <div className="bg-white border border-zinc-200 rounded-lg overflow-hidden">
      <button
        onClick={onToggle}
        className="w-full px-4 py-3 flex items-center gap-3 hover:bg-zinc-50 transition"
      >
        {open ? (
          <ChevronDown className="h-4 w-4 text-zinc-400 flex-shrink-0" />
        ) : (
          <ChevronRight className="h-4 w-4 text-zinc-400 flex-shrink-0" />
        )}
        <Icon className="h-4 w-4 text-zinc-600 flex-shrink-0" />
        <span className="font-medium text-sm text-zinc-900 flex-1 text-left">{title}</span>
        {onEdit && open && (
          <span
            onClick={(ev) => { ev.stopPropagation(); onEdit() }}
            className="text-xs font-medium text-zinc-700 hover:bg-zinc-100 border border-zinc-200 rounded px-2 py-1 inline-flex items-center gap-1 cursor-pointer"
          >
            <Pencil className="h-3 w-3" /> Editar
          </span>
        )}
      </button>
      {open && (
        <div className="px-4 pb-4 pt-1 border-t border-zinc-200">
          {children}
        </div>
      )}
    </div>
  )
}

function DataGrid({ children }: { children: React.ReactNode }) {
  return (
    <div className="grid grid-cols-1 sm:grid-cols-2 gap-x-6 gap-y-3 mt-3">
      {children}
    </div>
  )
}

function DataItem({
  label, value, mono, extra, icon: Icon, fullWidth,
}: {
  label: string
  value: string | null | undefined
  mono?: boolean
  extra?: string | null
  icon?: React.ComponentType<{ className?: string }>
  fullWidth?: boolean
}) {
  return (
    <div className={fullWidth ? 'sm:col-span-2' : ''}>
      <div className="text-[10px] uppercase tracking-wider text-zinc-500 font-semibold flex items-center gap-1">
        {Icon && <Icon className="h-3 w-3" />}
        {label}
      </div>
      <div className={mono ? 'font-mono text-xs mt-0.5 text-zinc-900' : 'text-sm mt-0.5 text-zinc-900'}>
        {value || <span className="text-zinc-400 italic font-sans text-xs">não informado</span>}
      </div>
      {extra && <div className="text-xs text-zinc-500 mt-0.5">{extra}</div>}
    </div>
  )
}

// ============================================================================
// Sub-tables
// ============================================================================

function SalaryTable({ entries }: { entries: SalaryHistoryEntry[] }) {
  if (entries.length === 0) {
    return <p className="text-sm text-zinc-500 italic mt-3">Nenhum reajuste registrado</p>
  }
  return (
    <table className="w-full text-sm mt-3">
      <thead>
        <tr className="text-left text-[10px] uppercase tracking-wider text-zinc-500 border-b border-zinc-200">
          <th className="py-2 font-semibold">Data</th>
          <th className="py-2 font-semibold">Valor</th>
          <th className="py-2 font-semibold">Cargo</th>
          <th className="py-2 font-semibold">Tipo</th>
        </tr>
      </thead>
      <tbody>
        {entries.map(s => (
          <tr key={s.id} className="border-b border-zinc-100 last:border-0">
            <td className="py-2 font-mono text-xs">{formatDate(s.effective_date)}</td>
            <td className="py-2">{formatMoney(s.amount, s.unit)}</td>
            <td className="py-2 text-zinc-600">{s.job_title || '-'}</td>
            <td className="py-2">
              <span className="text-[10px] font-semibold uppercase tracking-wide px-1.5 py-0.5 rounded bg-zinc-100 text-zinc-700">
                {s.change_type}
              </span>
            </td>
          </tr>
        ))}
      </tbody>
    </table>
  )
}

function VacationsTable({ entries }: { entries: Vacation[] }) {
  if (entries.length === 0) {
    return <p className="text-sm text-zinc-500 italic mt-3">Nenhum período de férias registrado</p>
  }
  return (
    <table className="w-full text-sm mt-3">
      <thead>
        <tr className="text-left text-[10px] uppercase tracking-wider text-zinc-500 border-b border-zinc-200">
          <th className="py-2 font-semibold">Tipo</th>
          <th className="py-2 font-semibold">Início</th>
          <th className="py-2 font-semibold">Fim</th>
          <th className="py-2 font-semibold">Obs.</th>
        </tr>
      </thead>
      <tbody>
        {entries.map(v => (
          <tr key={v.id} className="border-b border-zinc-100 last:border-0">
            <td className="py-2 capitalize">{v.kind.replace('_', ' ')}</td>
            <td className="py-2 font-mono text-xs">{formatDate(v.start_date)}</td>
            <td className="py-2 font-mono text-xs">{formatDate(v.end_date)}</td>
            <td className="py-2 text-zinc-600 text-xs">
              {v.paid_on_termination ? <span className="text-amber-700">Paga na rescisão</span> : (v.observations || '-')}
            </td>
          </tr>
        ))}
      </tbody>
    </table>
  )
}

function LeavesTable({ entries }: { entries: Leave[] }) {
  if (entries.length === 0) {
    return <p className="text-sm text-zinc-500 italic mt-3">Nenhum afastamento registrado</p>
  }
  return (
    <table className="w-full text-sm mt-3">
      <thead>
        <tr className="text-left text-[10px] uppercase tracking-wider text-zinc-500 border-b border-zinc-200">
          <th className="py-2 font-semibold">Saída</th>
          <th className="py-2 font-semibold">Retorno</th>
          <th className="py-2 font-semibold">Motivo</th>
          <th className="py-2 font-semibold">CID</th>
        </tr>
      </thead>
      <tbody>
        {entries.map(l => (
          <tr key={l.id} className="border-b border-zinc-100 last:border-0">
            <td className="py-2 font-mono text-xs">{formatDate(l.start_date)}</td>
            <td className="py-2 font-mono text-xs">
              {l.end_date ? formatDate(l.end_date) : <span className="text-amber-700 font-sans">Em curso</span>}
            </td>
            <td className="py-2 capitalize">{l.reason.replace(/_/g, ' ')}</td>
            <td className="py-2 font-mono text-xs">{l.cid || '-'}</td>
          </tr>
        ))}
      </tbody>
    </table>
  )
}

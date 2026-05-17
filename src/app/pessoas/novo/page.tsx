'use client'

/**
 * R2 People · /pessoas/novo
 * ============================================================================
 * Formulário de criação manual de ficha de empregado.
 *
 * Layout: página única longa com 5 seções (sticky header com seções como índice):
 *   1. Identificação    · nome, matrícula, beneficiários, sexo, nascimento
 *   2. Documentos       · CPF, RG, CTPS, PIS (CPF com check de duplicação)
 *   3. Dados pessoais   · filiação, naturalidade, raça, escolaridade, deficiência
 *   4. Contato          · endereço, CEP, telefones, email
 *   5. Vínculo          · cargo, CBO, admissão, salário, jornada
 *
 * Obrigatórios (validados no submit):
 *   full_name, hire_date, job_title, cpf (válido), rg, birth_date, sex
 *   E pelo menos um telefone (mobile ou home).
 *
 * CPF duplicado: aviso inline com link para ficha existente, sem bloquear,
 * mas o submit envia mesmo assim · o backend retorna `already_exists` e a UI
 * redireciona para a ficha.
 * ============================================================================
 */

import { useState, useCallback, useMemo } from 'react'
import { useRouter } from 'next/navigation'
import Link from 'next/link'
import {
  ChevronLeft, Loader2, User, FileText, Users as UsersIcon,
  MapPin, Briefcase, AlertTriangle, ExternalLink, CheckCircle2,
} from 'lucide-react'

import {
  Employees, RpcError,
  type EmployeePayload, type MaritalStatus, type RaceColor,
  type EducationLevel, type EmployeeSex,
} from '@/lib/r2'

import {
  TextField, CpfField, CepField, PhoneField, DateField, TimeField, EmailField,
  SelectField, TextareaField,
  useCpfDuplicateCheck,
} from '@/components/employees/FormFields'

import {
  cleanCpf, cleanCep, cleanPhone, brDateToIso,
  validateCpf, validateDateBr, validatePhone,
  UF_LIST,
} from '@/lib/validation'

// ============================================================================
// Estado inicial
// ============================================================================

interface FormState {
  // Identificacao
  full_name: string
  matricula_esocial: string
  ficha_numero: string
  beneficiaries: string
  sex: '' | EmployeeSex
  birth_date: string  // DD/MM/AAAA na UI

  // Documentos
  cpf: string
  rg: string
  rg_issuer: string
  rg_issue_date: string
  ctps_number: string
  ctps_serie: string
  ctps_uf: string
  ctps_issue_date: string
  pis: string
  voter_id: string
  voter_zone: string
  voter_section: string

  // Pessoal
  father_name: string
  mother_name: string
  birth_city: string
  birth_state: string
  nationality: string
  marital_status: MaritalStatus
  race_color: RaceColor
  education: EducationLevel
  has_disability: 'true' | 'false'
  disability_description: string

  // Contato
  residence_address: string
  residence_cep: string
  phone_home: string
  phone_mobile: string
  email: string

  // Vinculo
  job_title: string
  job_function: string
  cbo: string
  hire_date: string
  initial_salary: string
  salary_unit: 'mes' | 'hora' | 'dia' | 'semana' | 'quinzena'
  work_schedule_start: string
  work_schedule_end: string
  break_start: string
  break_end: string
  fgts_opt_in_date: string
}

const INITIAL_STATE: FormState = {
  full_name: '', matricula_esocial: '', ficha_numero: '', beneficiaries: '',
  sex: '', birth_date: '',
  cpf: '', rg: '', rg_issuer: '', rg_issue_date: '',
  ctps_number: '', ctps_serie: '', ctps_uf: '', ctps_issue_date: '',
  pis: '', voter_id: '', voter_zone: '', voter_section: '',
  father_name: '', mother_name: '', birth_city: '', birth_state: '',
  nationality: 'BRASIL', marital_status: 'nao_informado',
  race_color: 'nao_informada', education: 'nao_informado',
  has_disability: 'false', disability_description: '',
  residence_address: '', residence_cep: '', phone_home: '', phone_mobile: '', email: '',
  job_title: '', job_function: '', cbo: '', hire_date: '',
  initial_salary: '', salary_unit: 'mes',
  work_schedule_start: '', work_schedule_end: '',
  break_start: '', break_end: '', fgts_opt_in_date: '',
}

const SECTIONS = [
  { id: 'identificacao', label: 'Identificação', icon: User },
  { id: 'documentos',    label: 'Documentos',    icon: FileText },
  { id: 'pessoal',       label: 'Dados pessoais', icon: UsersIcon },
  { id: 'contato',       label: 'Contato',       icon: MapPin },
  { id: 'vinculo',       label: 'Vínculo',       icon: Briefcase },
] as const

const MARITAL_OPTIONS = [
  ['nao_informado', 'Não informado'],
  ['solteiro', 'Solteiro(a)'],
  ['casado', 'Casado(a)'],
  ['divorciado', 'Divorciado(a)'],
  ['viuvo', 'Viúvo(a)'],
  ['separado', 'Separado(a)'],
  ['uniao_estavel', 'União estável'],
] as const

const RACE_OPTIONS = [
  ['nao_informada', 'Não informada'],
  ['branca', 'Branca'],
  ['preta', 'Preta'],
  ['parda', 'Parda'],
  ['amarela', 'Amarela'],
  ['indigena', 'Indígena'],
] as const

const EDUCATION_OPTIONS = [
  ['nao_informado', 'Não informado'],
  ['analfabeto', 'Analfabeto'],
  ['fundamental_1_5_incompleto', 'Fundamental 1º-5º incompleto'],
  ['fundamental_1_5_completo', 'Fundamental 1º-5º completo'],
  ['fundamental_6_9_incompleto', 'Fundamental 6º-9º incompleto'],
  ['fundamental_6_9_completo', 'Fundamental 6º-9º completo'],
  ['medio_incompleto', 'Médio incompleto'],
  ['medio_completo', 'Médio completo'],
  ['superior_incompleto', 'Superior incompleto'],
  ['superior_completo', 'Superior completo'],
  ['pos_graduacao', 'Pós-graduação'],
  ['mestrado', 'Mestrado'],
  ['doutorado', 'Doutorado'],
] as const

const SEX_OPTIONS = [
  ['', '— Selecione —'],
  ['masculino', 'Masculino'],
  ['feminino', 'Feminino'],
  ['nao_informado', 'Prefere não informar'],
] as const

const SALARY_UNIT_OPTIONS = [
  ['mes', 'Mês'],
  ['hora', 'Hora'],
  ['dia', 'Dia'],
  ['semana', 'Semana'],
  ['quinzena', 'Quinzena'],
] as const

const UF_OPTIONS: ReadonlyArray<readonly [string, string]> = [
  ['', '—'],
  ...UF_LIST.map(uf => [uf, uf] as const),
]

// ============================================================================
// Page
// ============================================================================

export default function PessoaNovaPage() {
  const router = useRouter()
  const [form, setForm] = useState<FormState>(INITIAL_STATE)
  const [submitting, setSubmitting] = useState(false)
  const [showAllErrors, setShowAllErrors] = useState(false)
  const [submitError, setSubmitError] = useState<string | null>(null)

  const update = useCallback(<K extends keyof FormState>(key: K, value: FormState[K]) => {
    setForm(prev => ({ ...prev, [key]: value }))
  }, [])

  // Check de CPF duplicado em tempo real
  const cpfDup = useCpfDuplicateCheck(form.cpf)

  // Validação global ao submeter
  const errors = useMemo(() => {
    const e: string[] = []
    if (!form.full_name.trim()) e.push('Nome completo é obrigatório')
    if (!form.hire_date) e.push('Data de admissão é obrigatória')
    else if (validateDateBr(form.hire_date)) e.push('Data de admissão inválida')
    if (!form.job_title.trim()) e.push('Cargo é obrigatório')
    if (!form.cpf.trim()) e.push('CPF é obrigatório')
    else if (validateCpf(form.cpf)) e.push('CPF inválido')
    if (!form.rg.trim()) e.push('RG é obrigatório')
    if (!form.birth_date) e.push('Data de nascimento é obrigatória')
    else if (validateDateBr(form.birth_date, { notFuture: true })) e.push('Data de nascimento inválida')
    if (!form.sex) e.push('Sexo é obrigatório')
    if (!form.phone_mobile && !form.phone_home) {
      e.push('Informe ao menos um telefone (celular ou residencial)')
    } else {
      if (form.phone_mobile && validatePhone(form.phone_mobile)) e.push('Telefone celular inválido')
      if (form.phone_home && validatePhone(form.phone_home)) e.push('Telefone residencial inválido')
    }
    return e
  }, [form])

  const canSubmit = errors.length === 0 && !submitting

  // Builder do payload final · só dispara no submit
  const buildPayload = (): EmployeePayload => ({
    full_name: form.full_name.trim(),
    matricula_esocial: form.matricula_esocial.trim() || undefined,
    ficha_numero: form.ficha_numero.trim() || undefined,
    beneficiaries: form.beneficiaries.trim() || undefined,
    cpf: cleanCpf(form.cpf) || undefined,
    rg: form.rg.trim() || undefined,
    rg_issuer: form.rg_issuer.trim() || undefined,
    rg_issue_date: brDateToIso(form.rg_issue_date) || undefined,
    ctps_number: form.ctps_number.trim() || undefined,
    ctps_serie: form.ctps_serie.trim() || undefined,
    ctps_uf: form.ctps_uf || undefined,
    ctps_issue_date: brDateToIso(form.ctps_issue_date) || undefined,
    pis: form.pis.trim() || undefined,
    voter_id: form.voter_id.trim() || undefined,
    voter_zone: form.voter_zone.trim() || undefined,
    voter_section: form.voter_section.trim() || undefined,
    father_name: form.father_name.trim() || undefined,
    mother_name: form.mother_name.trim() || undefined,
    birth_date: brDateToIso(form.birth_date) || undefined,
    birth_city: form.birth_city.trim() || undefined,
    birth_state: form.birth_state || undefined,
    nationality: form.nationality.trim() || 'BRASIL',
    marital_status: form.marital_status,
    sex: form.sex || 'nao_informado',
    race_color: form.race_color,
    education: form.education,
    has_disability: form.has_disability === 'true',
    disability_description: form.disability_description.trim() || undefined,
    residence_address: form.residence_address.trim() || undefined,
    residence_cep: cleanCep(form.residence_cep) || undefined,
    phone_home: cleanPhone(form.phone_home) || undefined,
    phone_mobile: cleanPhone(form.phone_mobile) || undefined,
    email: form.email.trim() || undefined,
    job_title: form.job_title.trim(),
    job_function: form.job_function.trim() || undefined,
    cbo: form.cbo.trim() || undefined,
    hire_date: brDateToIso(form.hire_date),
    initial_salary: form.initial_salary
      ? Number(form.initial_salary.replace(/\./g, '').replace(',', '.'))
      : undefined,
    salary_unit: form.salary_unit,
    work_schedule_start: form.work_schedule_start || undefined,
    work_schedule_end: form.work_schedule_end || undefined,
    break_start: form.break_start || undefined,
    break_end: form.break_end || undefined,
    fgts_opt_in_date: brDateToIso(form.fgts_opt_in_date) || undefined,
    source: 'manual',
  })

  const handleSubmit = async () => {
    setSubmitError(null)
    setShowAllErrors(true)

    if (errors.length > 0) {
      // Scroll para o primeiro erro
      window.scrollTo({ top: 0, behavior: 'smooth' })
      return
    }

    setSubmitting(true)
    try {
      const r = await Employees.create(buildPayload())
      router.push(`/pessoas/${r.id}`)
    } catch (err) {
      if (err instanceof RpcError) {
        setSubmitError(err.code)
      } else {
        setSubmitError('unknown_error')
      }
    } finally {
      setSubmitting(false)
    }
  }

  return (
    <div className="max-w-5xl mx-auto p-6">
      {/* Breadcrumb */}
      <Link href="/pessoas" className="text-sm text-zinc-600 hover:text-zinc-900 inline-flex items-center gap-1 mb-3">
        <ChevronLeft className="h-4 w-4" /> Pessoas
      </Link>

      <div className="grid grid-cols-1 lg:grid-cols-[200px_1fr] gap-6">
        {/* Sidebar · índice de seções */}
        <aside className="lg:sticky lg:top-4 h-fit space-y-1">
          {SECTIONS.map(s => (
            <a
              key={s.id}
              href={`#${s.id}`}
              className="flex items-center gap-2 px-3 py-2 text-sm text-zinc-600 hover:bg-zinc-100 rounded transition"
            >
              <s.icon className="h-4 w-4" />
              {s.label}
            </a>
          ))}
        </aside>

        {/* Main · formulário */}
        <div className="space-y-6">
          <header className="border-b border-zinc-200 pb-4">
            <h1 className="text-2xl font-semibold text-zinc-900">Nova ficha de empregado</h1>
            <p className="text-sm text-zinc-500 mt-1">
              Preencha pelo menos os campos obrigatórios (marcados com <span className="text-red-600">*</span>).
            </p>
          </header>

          {/* Banner de erros de validação após tentar submeter */}
          {showAllErrors && errors.length > 0 && (
            <div className="border border-red-200 bg-red-50 rounded-md p-4">
              <div className="flex items-start gap-2">
                <AlertTriangle className="h-5 w-5 text-red-700 mt-0.5 flex-shrink-0" />
                <div>
                  <h3 className="font-semibold text-red-900 text-sm">
                    {errors.length} {errors.length === 1 ? 'campo precisa' : 'campos precisam'} de atenção
                  </h3>
                  <ul className="text-sm text-red-800 mt-1 list-disc list-inside space-y-0.5">
                    {errors.map((e, i) => <li key={i}>{e}</li>)}
                  </ul>
                </div>
              </div>
            </div>
          )}

          {submitError && (
            <div className="border border-red-200 bg-red-50 rounded-md p-4 text-sm text-red-900">
              <strong>Erro ao salvar:</strong> <code className="font-mono">{submitError}</code>
            </div>
          )}

          {/* === Identificação === */}
          <Section id="identificacao" title="Identificação" icon={User}>
            <Row cols={2}>
              <TextField
                label="Nome completo" required
                value={form.full_name}
                onChange={(v) => update('full_name', v)}
                showError={showAllErrors}
                placeholder="Ex: CARLOS ALBERTO IDALAN FERREIRA"
                maxLength={200}
              />
              <SelectField
                label="Sexo" required
                value={form.sex}
                onChange={(v) => update('sex', v as EmployeeSex)}
                options={SEX_OPTIONS}
                showError={showAllErrors}
              />
            </Row>
            <Row cols={3}>
              <TextField
                label="Matrícula eSocial"
                value={form.matricula_esocial}
                onChange={(v) => update('matricula_esocial', v)}
                placeholder="Ex: 195"
                maxLength={40}
              />
              <TextField
                label="Nº ficha"
                value={form.ficha_numero}
                onChange={(v) => update('ficha_numero', v)}
                placeholder="Ex: 000120"
                maxLength={20}
              />
              <DateField
                label="Data de nascimento" required
                value={form.birth_date}
                onChange={(v) => update('birth_date', v)}
                showError={showAllErrors}
                notFuture
              />
            </Row>
            <Row cols={1}>
              <TextField
                label="Beneficiários"
                value={form.beneficiaries}
                onChange={(v) => update('beneficiaries', v)}
                hint="Filhos, cônjuge ou outros dependentes (separar por vírgula)"
                maxLength={300}
              />
            </Row>
          </Section>

          {/* === Documentos === */}
          <Section id="documentos" title="Documentos" icon={FileText}>
            <Row cols={2}>
              <div className="space-y-1">
                <CpfField
                  label="CPF" required
                  value={form.cpf}
                  onChange={(v) => update('cpf', v)}
                  showError={showAllErrors}
                />
                {cpfDup.checking && (
                  <div className="text-xs text-zinc-500 flex items-center gap-1">
                    <Loader2 className="h-3 w-3 animate-spin" />
                    Verificando se já está cadastrado...
                  </div>
                )}
                {cpfDup.duplicate && (
                  <div className="border border-amber-300 bg-amber-50 rounded p-2 text-xs text-amber-900 flex items-start gap-2">
                    <AlertTriangle className="h-3.5 w-3.5 flex-shrink-0 mt-0.5" />
                    <div className="flex-1">
                      <div className="font-semibold">CPF já cadastrado</div>
                      <div className="mt-0.5">
                        {cpfDup.duplicate.full_name}
                        {cpfDup.duplicate.matricula_esocial && ` · matrícula ${cpfDup.duplicate.matricula_esocial}`}
                        {!cpfDup.duplicate.is_active && ' · desligado'}
                      </div>
                      <Link
                        href={`/pessoas/${cpfDup.duplicate.id}`}
                        className="inline-flex items-center gap-1 mt-1 text-amber-900 underline hover:no-underline"
                      >
                        Ver ficha existente <ExternalLink className="h-3 w-3" />
                      </Link>
                    </div>
                  </div>
                )}
              </div>
              <TextField
                label="RG" required
                value={form.rg}
                onChange={(v) => update('rg', v)}
                showError={showAllErrors}
                placeholder="Somente números"
                maxLength={30}
              />
            </Row>
            <Row cols={3}>
              <TextField
                label="Órgão emissor RG"
                value={form.rg_issuer}
                onChange={(v) => update('rg_issuer', v)}
                placeholder="Ex: SSP/BA"
                maxLength={20}
              />
              <DateField
                label="Data emissão RG"
                value={form.rg_issue_date}
                onChange={(v) => update('rg_issue_date', v)}
                notFuture
              />
              <TextField
                label="PIS"
                value={form.pis}
                onChange={(v) => update('pis', v)}
                maxLength={20}
              />
            </Row>
            <Row cols={4}>
              <TextField
                label="CTPS número"
                value={form.ctps_number}
                onChange={(v) => update('ctps_number', v)}
                maxLength={30}
              />
              <TextField
                label="CTPS série"
                value={form.ctps_serie}
                onChange={(v) => update('ctps_serie', v)}
                maxLength={15}
              />
              <SelectField
                label="CTPS UF"
                value={form.ctps_uf}
                onChange={(v) => update('ctps_uf', v)}
                options={UF_OPTIONS}
              />
              <DateField
                label="CTPS expedição"
                value={form.ctps_issue_date}
                onChange={(v) => update('ctps_issue_date', v)}
                notFuture
              />
            </Row>
            <Row cols={3}>
              <TextField
                label="Título eleitoral"
                value={form.voter_id}
                onChange={(v) => update('voter_id', v)}
                maxLength={20}
              />
              <TextField
                label="Zona"
                value={form.voter_zone}
                onChange={(v) => update('voter_zone', v)}
                maxLength={10}
              />
              <TextField
                label="Seção"
                value={form.voter_section}
                onChange={(v) => update('voter_section', v)}
                maxLength={10}
              />
            </Row>
          </Section>

          {/* === Dados pessoais === */}
          <Section id="pessoal" title="Dados pessoais" icon={UsersIcon}>
            <Row cols={2}>
              <TextField
                label="Nome do pai"
                value={form.father_name}
                onChange={(v) => update('father_name', v)}
                maxLength={200}
              />
              <TextField
                label="Nome da mãe"
                value={form.mother_name}
                onChange={(v) => update('mother_name', v)}
                maxLength={200}
              />
            </Row>
            <Row cols={3}>
              <TextField
                label="Cidade de nascimento"
                value={form.birth_city}
                onChange={(v) => update('birth_city', v)}
                placeholder="Ex: SALVADOR"
                maxLength={80}
              />
              <SelectField
                label="UF de nascimento"
                value={form.birth_state}
                onChange={(v) => update('birth_state', v)}
                options={UF_OPTIONS}
              />
              <TextField
                label="Nacionalidade"
                value={form.nationality}
                onChange={(v) => update('nationality', v)}
                maxLength={40}
              />
            </Row>
            <Row cols={2}>
              <SelectField
                label="Estado civil"
                value={form.marital_status}
                onChange={(v) => update('marital_status', v as MaritalStatus)}
                options={MARITAL_OPTIONS}
              />
              <SelectField
                label="Cor/raça"
                value={form.race_color}
                onChange={(v) => update('race_color', v as RaceColor)}
                options={RACE_OPTIONS}
              />
            </Row>
            <Row cols={2}>
              <SelectField
                label="Grau de instrução"
                value={form.education}
                onChange={(v) => update('education', v as EducationLevel)}
                options={EDUCATION_OPTIONS}
              />
              <SelectField
                label="Possui deficiência?"
                value={form.has_disability}
                onChange={(v) => update('has_disability', v as 'true' | 'false')}
                options={[['false', 'Não'], ['true', 'Sim']] as const}
              />
            </Row>
            {form.has_disability === 'true' && (
              <Row cols={1}>
                <TextareaField
                  label="Descrição da deficiência"
                  value={form.disability_description}
                  onChange={(v) => update('disability_description', v)}
                  placeholder="Tipo, CID e outras informações relevantes"
                  rows={2}
                />
              </Row>
            )}
          </Section>

          {/* === Contato === */}
          <Section id="contato" title="Contato" icon={MapPin}>
            <Row cols={2}>
              <PhoneField
                label="Telefone celular"
                value={form.phone_mobile}
                onChange={(v) => update('phone_mobile', v)}
                showError={showAllErrors}
                hint={!form.phone_home ? 'Pelo menos um telefone é obrigatório' : undefined}
              />
              <PhoneField
                label="Telefone residencial"
                value={form.phone_home}
                onChange={(v) => update('phone_home', v)}
                showError={showAllErrors}
              />
            </Row>
            <Row cols={1}>
              <EmailField
                label="Email"
                value={form.email}
                onChange={(v) => update('email', v)}
                maxLength={255}
              />
            </Row>
            <Row cols={[2, 1]}>
              <TextField
                label="Endereço residencial"
                value={form.residence_address}
                onChange={(v) => update('residence_address', v)}
                placeholder="Rua, número, complemento, bairro, cidade, UF"
                maxLength={300}
              />
              <CepField
                label="CEP"
                value={form.residence_cep}
                onChange={(v) => update('residence_cep', v)}
              />
            </Row>
          </Section>

          {/* === Vínculo === */}
          <Section id="vinculo" title="Vínculo" icon={Briefcase}>
            <Row cols={[2, 1, 1]}>
              <TextField
                label="Cargo" required
                value={form.job_title}
                onChange={(v) => update('job_title', v)}
                showError={showAllErrors}
                placeholder="Ex: REPOSITOR (A)"
                maxLength={120}
              />
              <TextField
                label="Função"
                value={form.job_function}
                onChange={(v) => update('job_function', v)}
                maxLength={120}
              />
              <TextField
                label="CBO"
                value={form.cbo}
                onChange={(v) => update('cbo', v)}
                hint="6 dígitos"
                maxLength={10}
              />
            </Row>
            <Row cols={3}>
              <DateField
                label="Data de admissão" required
                value={form.hire_date}
                onChange={(v) => update('hire_date', v)}
                showError={showAllErrors}
                notFuture
              />
              <TextField
                label="Salário inicial"
                value={form.initial_salary}
                onChange={(v) => update('initial_salary', v)}
                placeholder="1.500,00"
                hint="Use vírgula como separador decimal"
                inputMode="decimal"
              />
              <SelectField
                label="Periodicidade"
                value={form.salary_unit}
                onChange={(v) => update('salary_unit', v as FormState['salary_unit'])}
                options={SALARY_UNIT_OPTIONS}
              />
            </Row>
            <Row cols={4}>
              <TimeField
                label="Início da jornada"
                value={form.work_schedule_start}
                onChange={(v) => update('work_schedule_start', v)}
              />
              <TimeField
                label="Fim da jornada"
                value={form.work_schedule_end}
                onChange={(v) => update('work_schedule_end', v)}
              />
              <TimeField
                label="Início do intervalo"
                value={form.break_start}
                onChange={(v) => update('break_start', v)}
              />
              <TimeField
                label="Fim do intervalo"
                value={form.break_end}
                onChange={(v) => update('break_end', v)}
              />
            </Row>
            <Row cols={1}>
              <DateField
                label="Data de opção pelo FGTS"
                value={form.fgts_opt_in_date}
                onChange={(v) => update('fgts_opt_in_date', v)}
                notFuture
                className="max-w-xs"
              />
            </Row>
          </Section>

          {/* Footer · ações */}
          <div className="sticky bottom-0 bg-white border-t border-zinc-200 -mx-6 px-6 py-3 flex items-center justify-between">
            <Link
              href="/pessoas"
              className="px-4 py-2 text-sm font-medium text-zinc-700 hover:bg-zinc-100 border border-zinc-200 rounded"
            >
              Cancelar
            </Link>
            <div className="flex items-center gap-3">
              {errors.length === 0 && (
                <span className="text-xs text-emerald-700 flex items-center gap-1">
                  <CheckCircle2 className="h-3.5 w-3.5" />
                  Pronto para salvar
                </span>
              )}
              <button
                onClick={handleSubmit}
                disabled={!canSubmit}
                className="px-4 py-2 text-sm font-medium text-white bg-zinc-900 hover:bg-zinc-800 disabled:opacity-50 disabled:cursor-not-allowed rounded inline-flex items-center gap-1.5"
              >
                {submitting && <Loader2 className="h-3.5 w-3.5 animate-spin" />}
                Salvar ficha
              </button>
            </div>
          </div>
        </div>
      </div>
    </div>
  )
}

// ============================================================================
// Helpers visuais
// ============================================================================

function Section({
  id, title, icon: Icon, children,
}: {
  id: string
  title: string
  icon: React.ComponentType<{ className?: string }>
  children: React.ReactNode
}) {
  return (
    <section
      id={id}
      className="bg-white border border-zinc-200 rounded-lg p-5 scroll-mt-4"
    >
      <h2 className="text-sm font-semibold text-zinc-900 flex items-center gap-2 mb-4 pb-3 border-b border-zinc-100">
        <Icon className="h-4 w-4 text-zinc-600" />
        {title}
      </h2>
      <div className="space-y-3">
        {children}
      </div>
    </section>
  )
}

function Row({ cols, children }: { cols: number | number[]; children: React.ReactNode }) {
  // Suporta cols como número (n colunas iguais) ou array (proporções tipo [2,1,1])
  const gridClass = useMemo(() => {
    if (typeof cols === 'number') {
      const map: Record<number, string> = {
        1: 'grid-cols-1',
        2: 'grid-cols-1 sm:grid-cols-2',
        3: 'grid-cols-1 sm:grid-cols-2 lg:grid-cols-3',
        4: 'grid-cols-1 sm:grid-cols-2 lg:grid-cols-4',
      }
      return map[cols] || 'grid-cols-1'
    }
    // Array: cria template-columns customizado
    const tmpl = cols.map(n => `${n}fr`).join(' ')
    return `grid-cols-1 sm:[grid-template-columns:${tmpl}]`
  }, [cols])

  return <div className={`grid ${gridClass} gap-3`}>{children}</div>
}

'use client'

/**
 * R2 People · /minha-jornada (Sessao G1)
 * ============================================================================
 * Tela pessoal do colaborador. Conteudo:
 *
 *   1. Header com nome, cargo, unidade, departamento, gestor
 *   2. KPIs: PDIs ativos/atrasados, reconhecimentos 90d, ultima caixa 9-Box
 *   3. Dados pessoais basicos (read-only)
 *   4. Meus PDIs · usa PdiCardEditable com viewerIsOwner=true
 *      (so o toggle de status das acoes; sem editar objetivo/datas/status)
 *   5. Reconhecimentos recebidos · feed
 *   6. Reconhecimentos que enviei · feed
 *   7. Onboarding em curso · cards
 *
 * Permissao: qualquer authenticated. O backend filtra por escopo proprio.
 * ============================================================================
 */

import { useEffect, useState, useCallback } from 'react'
import Link from 'next/link'
import {
  User, Briefcase, Building2, MapPin, Cake, Calendar,
  Target, Award, TrendingUp, BookOpen, Loader2, AlertCircle,
  ArrowDownRight, ArrowUpRight, Lock, ChevronLeft, Send, Pencil,
} from 'lucide-react'

import {
  myJourney, Employees, RpcError,
  type MyJourneyResult, type GestaoSummary, type GestaoRecognition, type GestaoOnboarding,
  type ProfileChangeField,
} from '@/lib/r2'
import { PdiCardEditable } from '@/components/employees/PdiCardEditable'
import { ProfileChangeRequestModal } from '@/components/profile/ProfileChangeRequestModal'
import { MyProfileRequests } from '@/components/profile/MyProfileRequests'
import { isoDateToBr } from '@/lib/validation'

// ============================================================================
// 9-Box mapping (3x3 padrao)
// ============================================================================

const BOX_COLOR_3x3: ReadonlyArray<readonly string[]> = [
  ['bg-red-100 text-red-900',     'bg-amber-100 text-amber-900', 'bg-emerald-100 text-emerald-900'],
  ['bg-amber-100 text-amber-900', 'bg-amber-100 text-amber-900', 'bg-emerald-100 text-emerald-900'],
  ['bg-red-100 text-red-900',     'bg-amber-100 text-amber-900', 'bg-emerald-200 text-emerald-900'],
]

// ============================================================================
// Page
// ============================================================================

export default function MinhaJornadaPage() {
  const [journey, setJourney] = useState<MyJourneyResult | null>(null)
  const [gestao, setGestao] = useState<GestaoSummary | null>(null)
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)
  const [refreshKey, setRefreshKey] = useState(0)
  // G3 · modal de solicitar alteracao
  const [changeModal, setChangeModal] = useState<{
    field: ProfileChangeField
    initialValue?: Record<string, unknown>
  } | null>(null)
  const [requestsRefreshKey, setRequestsRefreshKey] = useState(0)

  const fetchAll = useCallback(async () => {
    setLoading(true)
    setError(null)
    try {
      // 1. Snapshot agregado · sempre carregado
      const j = await myJourney()
      setJourney(j)

      // 2. Listas detalhadas via gestaoSummary (apenas se a pessoa tem ficha)
      if (j.identity.employee_id) {
        try {
          const g = await Employees.gestaoSummary(j.identity.employee_id)
          setGestao(g)
        } catch (err) {
          // Sem fatalidade: tela ainda mostra journey, e secao de listas mostra empty
          if (!(err instanceof RpcError) || err.code !== 'permission_denied') {
            console.warn('Falha ao buscar gestaoSummary:', err)
          }
          setGestao(null)
        }
      } else {
        setGestao(null)
      }
    } catch (err) {
      setError(err instanceof RpcError ? err.code : 'unknown_error')
    } finally {
      setLoading(false)
    }
  }, [])

  useEffect(() => { fetchAll() }, [fetchAll, refreshKey])

  if (loading) {
    return (
      <div className="flex items-center justify-center min-h-[60vh]">
        <Loader2 className="h-6 w-6 animate-spin text-zinc-400" />
      </div>
    )
  }

  if (error) {
    return (
      <div className="max-w-2xl mx-auto p-8">
        <div className="border border-red-200 bg-red-50 rounded p-4 text-red-900">
          <strong>Erro:</strong> <code className="font-mono">{error}</code>
        </div>
      </div>
    )
  }

  if (!journey) return null

  const id = journey.identity

  return (
    <div className="max-w-5xl mx-auto p-6 space-y-5">
      <Link href="/" className="text-sm text-zinc-600 hover:text-zinc-900 inline-flex items-center gap-1">
        <ChevronLeft className="h-4 w-4" /> Início
      </Link>

      {/* Header pessoal */}
      <HeaderPessoal identity={id} />

      {/* KPIs */}
      <KpisRow journey={journey} />

      {/* Dados pessoais basicos */}
      <DadosPessoais
        identity={id}
        onRequestChange={(field, initialValue) =>
          setChangeModal({ field, initialValue })}
      />

      {/* Minhas solicitacoes de alteracao (G3) */}
      {id.employee_id && (
        <SectionCard title="Solicitações de alteração" icon={Send}>
          <MyProfileRequests
            refreshKey={requestsRefreshKey}
            onChanged={() => setRequestsRefreshKey(k => k + 1)}
          />
        </SectionCard>
      )}

      {/* Meus PDIs */}
      <MeusPdis
        gestao={gestao}
        hasFicha={!!id.employee_id}
        onChanged={() => setRefreshKey(k => k + 1)}
      />

      {/* Reconhecimentos recebidos */}
      <RecogRecebidos gestao={gestao} hasFicha={!!id.employee_id} />

      {/* Reconhecimentos enviados (do journey via recog_kpis · contagem; lista detalhada nao temos RPC dedicada) */}
      <RecogEnviados journey={journey} />

      {/* Onboarding em curso */}
      <Onboardings gestao={gestao} hasFicha={!!id.employee_id} />

      {/* G3 · modal de solicitar alteracao */}
      {changeModal && (
        <ProfileChangeRequestModal
          field={changeModal.field}
          initialValue={changeModal.initialValue}
          onClose={() => setChangeModal(null)}
          onCreated={() => {
            setChangeModal(null)
            setRequestsRefreshKey(k => k + 1)
          }}
        />
      )}
    </div>
  )
}

// ============================================================================
// Header pessoal
// ============================================================================

function HeaderPessoal({ identity: id }: { identity: MyJourneyResult['identity'] }) {
  const initials = id.full_name
    .split(/\s+/)
    .filter(Boolean)
    .slice(0, 2)
    .map(s => s[0]?.toUpperCase() ?? '')
    .join('')

  return (
    <header className="bg-white border border-zinc-200 rounded-lg p-5">
      <div className="flex items-start gap-4 flex-wrap">
        <div className="w-16 h-16 rounded-full bg-zinc-900 text-white flex items-center justify-center text-2xl font-semibold flex-shrink-0">
          {initials || '?'}
        </div>
        <div className="flex-1 min-w-0">
          <h1 className="text-2xl font-semibold text-zinc-900">{id.full_name}</h1>
          {id.job_title && (
            <p className="text-sm text-zinc-600 mt-0.5 flex items-center gap-1.5">
              <Briefcase className="h-3.5 w-3.5" /> {id.job_title}
            </p>
          )}
          <div className="text-xs text-zinc-500 mt-2 flex flex-wrap gap-x-4 gap-y-1">
            {id.employer_unit && (
              <span className="inline-flex items-center gap-1">
                <Building2 className="h-3 w-3" /> {id.employer_unit.trade_name}
              </span>
            )}
            {id.department && (
              <span className="inline-flex items-center gap-1">
                <BookOpen className="h-3 w-3" /> {id.department.display_name}
              </span>
            )}
            {id.manager && (
              <span className="inline-flex items-center gap-1">
                <User className="h-3 w-3" /> Gestor: {id.manager.full_name}
              </span>
            )}
          </div>
        </div>
      </div>

      {!id.employee_id && (
        <div className="mt-3 border border-amber-200 bg-amber-50 rounded p-2.5 text-xs text-amber-900 flex items-start gap-2">
          <AlertCircle className="h-3.5 w-3.5 mt-0.5 flex-shrink-0" />
          Sua ficha de empregado ainda não está vinculada. Peça ao RH para concluir o cadastro.
          Alguns dados pessoais podem aparecer incompletos.
        </div>
      )}
    </header>
  )
}

// ============================================================================
// KPIs
// ============================================================================

function KpisRow({ journey }: { journey: MyJourneyResult }) {
  const { pdi_kpis, recog_kpis, last_ninebox } = journey

  return (
    <section className="grid grid-cols-2 md:grid-cols-4 gap-3">
      <Kpi
        icon={Target}
        label="PDIs ativos"
        value={pdi_kpis.active}
        subtitle={pdi_kpis.overdue > 0 ? `${pdi_kpis.overdue} vencido${pdi_kpis.overdue === 1 ? '' : 's'}` : 'em dia'}
        color={pdi_kpis.overdue > 0 ? 'amber' : 'emerald'}
      />
      <Kpi
        icon={Target}
        label="Ações"
        value={pdi_kpis.actions_total > 0
          ? `${pdi_kpis.actions_completed}/${pdi_kpis.actions_total}`
          : '0/0'}
        subtitle={pdi_kpis.actions_total === 0 ? 'nenhuma ação cadastrada' : 'concluídas/total'}
        color="zinc"
      />
      <Kpi
        icon={Award}
        label="Reconhecimentos 90d"
        value={recog_kpis.received_90d}
        subtitle={`${recog_kpis.received_total} no total`}
        color="emerald"
      />
      <Kpi
        icon={TrendingUp}
        label="Última 9-Box"
        value={last_ninebox?.box_label ?? '—'}
        subtitle={last_ninebox ? isoDateToBr(last_ninebox.finalized_at.slice(0, 10)) : 'sem avaliação ainda'}
        color={last_ninebox ? nineboxColor(last_ninebox.box_row, last_ninebox.box_col) : 'zinc'}
        big={!!last_ninebox}
      />
    </section>
  )
}

function nineboxColor(row: number, col: number): 'emerald' | 'amber' | 'red' {
  if (row < 1 || row > 3 || col < 1 || col > 3) return 'amber'
  // BOX_COLOR_3x3[row-1][col-1] tem o tom; aqui simplificamos
  const r = row - 1
  const c = col - 1
  if (BOX_COLOR_3x3[r][c].includes('emerald')) return 'emerald'
  if (BOX_COLOR_3x3[r][c].includes('red')) return 'red'
  return 'amber'
}

function Kpi({
  icon: Icon, label, value, subtitle, color, big,
}: {
  icon: React.ComponentType<{ className?: string }>
  label: string
  value: number | string
  subtitle: string
  color: 'emerald' | 'amber' | 'red' | 'zinc'
  big?: boolean
}) {
  const cls = {
    emerald: 'bg-emerald-50 border-emerald-200 text-emerald-900',
    amber:   'bg-amber-50 border-amber-200 text-amber-900',
    red:     'bg-red-50 border-red-200 text-red-900',
    zinc:    'bg-white border-zinc-200 text-zinc-900',
  }[color]
  return (
    <div className={`border rounded-lg p-3 ${cls}`}>
      <div className="flex items-center gap-1.5 mb-1">
        <Icon className="h-3.5 w-3.5 opacity-70" />
        <span className="text-[10px] font-semibold uppercase tracking-wider opacity-70">
          {label}
        </span>
      </div>
      <div className={big ? 'text-lg font-semibold leading-tight' : 'text-2xl font-semibold'}>
        {value}
      </div>
      <div className="text-[10px] opacity-70 mt-0.5">{subtitle}</div>
    </div>
  )
}

// ============================================================================
// Dados pessoais (read-only)
// ============================================================================

function DadosPessoais({
  identity: id, onRequestChange,
}: {
  identity: MyJourneyResult['identity']
  onRequestChange: (field: ProfileChangeField, initialValue?: Record<string, unknown>) => void
}) {
  return (
    <section className="bg-white border border-zinc-200 rounded-lg p-4">
      <h2 className="text-xs font-semibold uppercase tracking-wider text-zinc-500 mb-3 flex items-center gap-1.5">
        <User className="h-3.5 w-3.5" /> Dados pessoais
      </h2>
      <div className="grid grid-cols-1 md:grid-cols-2 gap-x-6 gap-y-3 text-sm">
        <Field label="Email corporativo" value={id.email} icon={null} />
        <Field
          label="Admissão"
          value={id.hire_date ? isoDateToBr(id.hire_date) : (id.hired_at ? isoDateToBr(id.hired_at.slice(0, 10)) : '-')}
          icon={Calendar}
        />
        <Field
          label="Nascimento"
          value={id.birth_date ? isoDateToBr(id.birth_date) : '-'}
          icon={Cake}
        />
        <Field
          label="Vínculo"
          value={(id.employment_link || '-').toUpperCase()}
          icon={Briefcase}
        />
        <Field
          label="Unidade de trabalho"
          value={id.working_unit
            ? `${id.working_unit.trade_name}${id.working_unit.city ? ` · ${id.working_unit.city}/${id.working_unit.state_uf}` : ''}`
            : (id.employer_unit ? id.employer_unit.trade_name : '-')}
          icon={MapPin}
        />
        <Field label="Função" value={id.job_title ?? '-'} icon={Briefcase} />
      </div>

      {/* G3 · botoes para campos solicitaveis */}
      <div className="mt-4 pt-3 border-t border-zinc-100">
        <div className="text-[10px] uppercase tracking-wider text-zinc-500 font-semibold mb-2">
          Solicitar alteração
        </div>
        <div className="flex flex-wrap gap-1.5">
          <RequestButton onClick={() => onRequestChange('phone_mobile')} label="Telefone celular" />
          <RequestButton onClick={() => onRequestChange('phone_home')} label="Telefone fixo" />
          <RequestButton onClick={() => onRequestChange('personal_email')} label="Email pessoal" />
          <RequestButton onClick={() => onRequestChange('residence_address')} label="Endereço" />
          <RequestButton onClick={() => onRequestChange('emergency_contact')} label="Contato de emergência" />
          <RequestButton onClick={() => onRequestChange('photo')} label="Foto de perfil" />
        </div>
      </div>
    </section>
  )
}

function RequestButton({ onClick, label }: { onClick: () => void; label: string }) {
  return (
    <button
      onClick={onClick}
      className="text-xs px-2.5 py-1.5 border border-zinc-200 rounded hover:bg-zinc-50 hover:border-zinc-300 text-zinc-700 inline-flex items-center gap-1 transition"
    >
      <Pencil className="h-3 w-3" />
      {label}
    </button>
  )
}

function Field({
  label, value, icon: Icon,
}: {
  label: string
  value: string
  icon: React.ComponentType<{ className?: string }> | null
}) {
  return (
    <div>
      <div className="text-[10px] uppercase tracking-wider text-zinc-500 font-semibold mb-0.5">
        {label}
      </div>
      <div className="text-sm text-zinc-900 flex items-center gap-1.5">
        {Icon && <Icon className="h-3.5 w-3.5 text-zinc-400 flex-shrink-0" />}
        <span className="truncate">{value}</span>
      </div>
    </div>
  )
}

// ============================================================================
// Meus PDIs (com PdiCardEditable em modo dono)
// ============================================================================

function MeusPdis({
  gestao, hasFicha, onChanged,
}: {
  gestao: GestaoSummary | null
  hasFicha: boolean
  onChanged: () => void
}) {
  return (
    <SectionCard title="Meus PDIs" icon={Target}>
      {!hasFicha ? (
        <EmptyText msg="Vincule sua ficha de empregado para ver seus PDIs." />
      ) : !gestao || gestao.pdis.length === 0 ? (
        <EmptyText msg="Você não tem PDIs registrados ainda." />
      ) : (
        <div className="space-y-3">
          {gestao.pdis.map(p => (
            <PdiCardEditable
              key={p.id}
              pdi={p}
              onChanged={onChanged}
              viewerIsOwner
            />
          ))}
          <p className="text-[10px] text-zinc-500 italic">
            Você pode marcar suas ações como concluídas. Edições no objetivo, datas ou
            status do PDI ficam com seu gestor ou com o RH.
          </p>
        </div>
      )}
    </SectionCard>
  )
}

// ============================================================================
// Reconhecimentos recebidos (feed simples)
// ============================================================================

function RecogRecebidos({
  gestao, hasFicha,
}: {
  gestao: GestaoSummary | null
  hasFicha: boolean
}) {
  return (
    <SectionCard
      title="Reconhecimentos recebidos"
      icon={ArrowDownRight}
      headerLink={hasFicha && gestao && gestao.recognitions.length > 0
        ? { href: '/meus-reconhecimentos', label: 'Ver feed completo' }
        : null}
    >
      {!hasFicha ? (
        <EmptyText msg="Vincule sua ficha para ver reconhecimentos." />
      ) : !gestao || gestao.recognitions.length === 0 ? (
        <EmptyText msg="Nenhum reconhecimento recebido ainda." />
      ) : (
        <div className="space-y-2">
          {gestao.recognitions.slice(0, 5).map(r => <RecognitionItem key={r.id} r={r} />)}
        </div>
      )}
    </SectionCard>
  )
}

function RecognitionItem({ r }: { r: GestaoRecognition }) {
  return (
    <div className="border border-zinc-100 rounded p-3 bg-zinc-50/30">
      <div className="flex items-start gap-2">
        <Award className="h-4 w-4 text-amber-600 mt-0.5 flex-shrink-0" />
        <div className="flex-1 min-w-0">
          <p className="text-sm text-zinc-900">{r.message}</p>
          <div className="text-[10px] text-zinc-500 mt-1 flex gap-2 flex-wrap items-center">
            {r.sender_name && <span>de {r.sender_name}</span>}
            <span>· {isoDateToBr(r.created_at.slice(0, 10))}</span>
            {r.is_private && (
              <span className="inline-flex items-center gap-0.5 text-amber-700">
                <Lock className="h-2.5 w-2.5" /> privado
              </span>
            )}
          </div>
        </div>
      </div>
    </div>
  )
}

// ============================================================================
// Reconhecimentos enviados (so contagens · feed detalhado seria outra RPC)
// ============================================================================

function RecogEnviados({ journey }: { journey: MyJourneyResult }) {
  const { sent_total, sent_90d } = journey.recog_kpis

  return (
    <SectionCard
      title="Reconhecimentos que eu enviei"
      icon={ArrowUpRight}
      headerLink={sent_total > 0
        ? { href: '/meus-reconhecimentos?tab=sent', label: 'Ver feed completo' }
        : null}
    >
      {sent_total === 0 ? (
        <EmptyText msg="Você ainda não enviou reconhecimentos." />
      ) : (
        <div className="grid grid-cols-2 gap-3 text-sm">
          <div className="border border-zinc-100 rounded p-3 text-center">
            <div className="text-2xl font-semibold text-zinc-900">{sent_total}</div>
            <div className="text-[10px] uppercase tracking-wider text-zinc-500 mt-1">
              Total enviados
            </div>
          </div>
          <div className="border border-zinc-100 rounded p-3 text-center">
            <div className="text-2xl font-semibold text-zinc-900">{sent_90d}</div>
            <div className="text-[10px] uppercase tracking-wider text-zinc-500 mt-1">
              Nos últimos 90 dias
            </div>
          </div>
        </div>
      )}
    </SectionCard>
  )
}

// ============================================================================
// Onboardings
// ============================================================================

function Onboardings({
  gestao, hasFicha,
}: {
  gestao: GestaoSummary | null
  hasFicha: boolean
}) {
  return (
    <SectionCard title="Onboardings" icon={BookOpen}>
      {!hasFicha ? (
        <EmptyText msg="Vincule sua ficha para ver onboardings." />
      ) : !gestao || gestao.onboardings.length === 0 ? (
        <EmptyText msg="Nenhum onboarding em curso." />
      ) : (
        <div className="space-y-2">
          {gestao.onboardings.map(o => <OnboardingItem key={o.id} o={o} />)}
        </div>
      )}
    </SectionCard>
  )
}

function OnboardingItem({ o }: { o: GestaoOnboarding }) {
  const pct = o.tasks_total > 0 ? Math.round((o.tasks_completed / o.tasks_total) * 100) : 0
  return (
    <div className="border border-zinc-100 rounded p-3">
      <div className="flex items-center gap-2 mb-1">
        <span className="text-sm font-medium text-zinc-900 flex-1 truncate">{o.display_name}</span>
        <span className="text-[10px] uppercase tracking-wider text-zinc-500">
          {o.status}
        </span>
      </div>
      {o.tasks_total > 0 && (
        <div className="flex items-center gap-2">
          <div className="flex-1 h-1.5 bg-zinc-100 rounded-full overflow-hidden">
            <div className="h-full bg-emerald-600" style={{ width: `${pct}%` }} />
          </div>
          <span className="text-xs text-zinc-500">
            {o.tasks_completed}/{o.tasks_total} tarefas
          </span>
        </div>
      )}
    </div>
  )
}

// ============================================================================
// Helpers visuais
// ============================================================================

function SectionCard({
  title, icon: Icon, children, headerLink,
}: {
  title: string
  icon: React.ComponentType<{ className?: string }>
  children: React.ReactNode
  headerLink?: { href: string; label: string } | null
}) {
  return (
    <section className="bg-white border border-zinc-200 rounded-lg p-4">
      <h2 className="text-xs font-semibold uppercase tracking-wider text-zinc-500 mb-3 pb-2 border-b border-zinc-100 flex items-center gap-1.5">
        <Icon className="h-3.5 w-3.5" /> {title}
        {headerLink && (
          <Link
            href={headerLink.href}
            className="ml-auto text-[10px] font-medium text-zinc-700 hover:text-zinc-900 normal-case tracking-normal"
          >
            {headerLink.label} →
          </Link>
        )}
      </h2>
      {children}
    </section>
  )
}

function EmptyText({ msg }: { msg: string }) {
  return <p className="text-xs text-zinc-500 italic py-2">{msg}</p>
}

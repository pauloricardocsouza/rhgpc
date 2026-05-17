'use client'

/**
 * R2 People · Sessao B2 · /admin/modulos
 * ============================================================================
 * Pagina admin de modulos · usa o adapter R2 (Sessao C4) para todas as RPCs.
 *
 * Stack:
 *   - Next.js 14+ App Router
 *   - lucide-react (icones)
 *   - Tailwind CSS
 *
 * Tipos e RPCs consumidos via @/lib/r2:
 *   - Modules.getOverview, .activate, .deactivate, .reactivate, .getImpactSummary
 *   - ModuleSummary, ImpactItem, ModuleScopeKind, UserRole, RpcError
 * ============================================================================
 */

import { useEffect, useState, useMemo, useCallback } from 'react'
import { createClient } from '@/lib/supabase'
import {
  Building2, ChevronDown, ChevronRight, AlertTriangle, Loader2,
  Activity, Award, TrendingUp, UserPlus, Grid3x3, Layers,
  CheckCircle2, XCircle, Lock,
} from 'lucide-react'

import {
  Modules,
  RpcError,
  type ModuleSummary,
  type ModuleScopeKind,
  type UnitState,
  type ImpactItem,
  type UserRole,
} from '@/lib/r2'

// ----------------------------------------------------------------------------
// Icone por nome (espelha o icon_name vindo do banco)
// ----------------------------------------------------------------------------

const ICON_MAP: Record<string, React.ComponentType<{ className?: string }>> = {
  Building2, Activity, Award, TrendingUp, UserPlus, Grid3x3, Layers,
}

const iconFor = (name: string) => ICON_MAP[name] ?? Layers

// ============================================================================
// AdminModulesPage · componente raiz
// ============================================================================

export default function AdminModulesPage() {
  const supabase = createClient()

  const [loading, setLoading] = useState(true)
  const [errorCode, setErrorCode] = useState<string | null>(null)
  const [role, setRole] = useState<UserRole | null>(null)
  const [modules, setModules] = useState<ModuleSummary[]>([])
  const [tenantId, setTenantId] = useState<string | null>(null)
  const [expanded, setExpanded] = useState<Set<string>>(new Set())

  const [deactivateModal, setDeactivateModal] = useState<{
    moduleCode: string
    moduleName: string
    scopeKind: ModuleScopeKind
    scopeId: string
    scopeLabel: string
  } | null>(null)

  const fetchOverview = useCallback(async () => {
    setLoading(true)
    setErrorCode(null)

    try {
      const { data: { user } } = await supabase.auth.getUser()
      if (user) {
        const { data: appUser } = await supabase
          .from('app_users')
          .select('tenant_id')
          .eq('auth_user_id', user.id)
          .single()
        if (appUser) setTenantId((appUser as { tenant_id: string }).tenant_id)
      }
    } catch {
      // super_admin nao tem tenant_id · seguimos
    }

    try {
      const r = await Modules.getOverview()
      setRole(r.role)
      setModules(r.modules)
    } catch (err) {
      setErrorCode(err instanceof RpcError ? err.code : 'unknown_error')
    } finally {
      setLoading(false)
    }
  }, [supabase])

  useEffect(() => { fetchOverview() }, [fetchOverview])

  const toggleExpanded = (code: string) => {
    setExpanded(prev => {
      const next = new Set(prev)
      if (next.has(code)) next.delete(code)
      else next.add(code)
      return next
    })
  }

  const activate = async (code: string, scopeKind: ModuleScopeKind, scopeId: string) => {
    try {
      await Modules.activate(code, scopeKind, scopeId)
      await fetchOverview()
    } catch (err) {
      alert(`Erro: ${err instanceof RpcError ? err.code : 'unknown_error'}`)
    }
  }

  const reactivate = async (code: string, scopeKind: ModuleScopeKind, scopeId: string) => {
    try {
      await Modules.reactivate(code, scopeKind, scopeId)
      await fetchOverview()
    } catch (err) {
      alert(`Erro: ${err instanceof RpcError ? err.code : 'unknown_error'}`)
    }
  }

  const requestDeactivate = (
    moduleCode: string,
    moduleName: string,
    scopeKind: ModuleScopeKind,
    scopeId: string,
    scopeLabel: string,
  ) => {
    setDeactivateModal({ moduleCode, moduleName, scopeKind, scopeId, scopeLabel })
  }

  const onDeactivateConfirmed = async (reason: string) => {
    if (!deactivateModal) return
    try {
      await Modules.deactivate(
        deactivateModal.moduleCode,
        deactivateModal.scopeKind,
        deactivateModal.scopeId,
        reason || undefined,
      )
      setDeactivateModal(null)
      await fetchOverview()
    } catch (err) {
      alert(`Erro: ${err instanceof RpcError ? err.code : 'unknown_error'}`)
    }
  }

  if (loading) {
    return (
      <div className="flex items-center justify-center min-h-[60vh]">
        <Loader2 className="h-6 w-6 animate-spin text-zinc-400" />
      </div>
    )
  }

  if (errorCode) {
    return (
      <div className="max-w-2xl mx-auto p-8">
        <div className="border border-red-200 bg-red-50 rounded-md p-4 text-red-900">
          <div className="flex gap-2 items-start">
            <AlertTriangle className="h-5 w-5 mt-0.5" />
            <div>
              <h3 className="font-semibold">Nao foi possivel carregar os modulos</h3>
              <p className="text-sm mt-1 font-mono">{errorCode}</p>
              {errorCode === 'permission_denied' && (
                <p className="text-sm mt-2">
                  Esta pagina e acessivel apenas a super_admin e diretoria.
                </p>
              )}
            </div>
          </div>
        </div>
      </div>
    )
  }

  return (
    <div className="max-w-6xl mx-auto p-6 space-y-6">
      <header className="border-b border-zinc-200 pb-4">
        <h1 className="text-2xl font-semibold text-zinc-900">Gestao de Modulos</h1>
        <p className="text-sm text-zinc-500 mt-1">
          {role === 'super_admin'
            ? 'Visao global · todos os tenants'
            : 'Modulos disponiveis no seu tenant'}
        </p>
      </header>

      <div className="space-y-3">
        {modules.map((m) => (
          <ModuleCard
            key={m.code}
            module={m}
            role={role}
            tenantId={tenantId}
            expanded={expanded.has(m.code)}
            onToggle={() => toggleExpanded(m.code)}
            onActivate={activate}
            onReactivate={reactivate}
            onRequestDeactivate={requestDeactivate}
          />
        ))}
      </div>

      {deactivateModal && (
        <DeactivateConfirmModal
          {...deactivateModal}
          onClose={() => setDeactivateModal(null)}
          onConfirm={onDeactivateConfirmed}
        />
      )}
    </div>
  )
}

// ============================================================================
// ModuleCard
// ============================================================================

interface ModuleCardProps {
  module: ModuleSummary
  role: UserRole | null
  tenantId: string | null
  expanded: boolean
  onToggle: () => void
  onActivate: (code: string, scopeKind: ModuleScopeKind, scopeId: string) => void
  onReactivate: (code: string, scopeKind: ModuleScopeKind, scopeId: string) => void
  onRequestDeactivate: (
    code: string, name: string, scopeKind: ModuleScopeKind, scopeId: string, scopeLabel: string,
  ) => void
}

function ModuleCard({
  module: m, role, tenantId, expanded, onToggle,
  onActivate, onReactivate, onRequestDeactivate,
}: ModuleCardProps) {
  const Icon = iconFor(m.icon_name)
  const isCore = m.is_core

  const summary = useMemo(() => {
    if (role === 'super_admin' && m.global_view) {
      const v = m.global_view
      return `${v.tenants_active}/${v.tenants_total} tenants · ${v.activations_total} ativacoes`
    }
    if (role === 'diretoria' && m.tenant_view) {
      const v = m.tenant_view
      const eAct = v.employer_units.filter(u => u.active).length
      const wAct = v.working_units.filter(u => u.active).length
      const tag = v.tenant_active ? 'Ativo no tenant' : v.tenant_disabled ? 'Desativado' : 'Nao ativado'
      return `${tag} · ${eAct} employer · ${wAct} working`
    }
    return ''
  }, [m, role])

  return (
    <div className="border border-zinc-200 rounded-lg bg-white overflow-hidden">
      <button
        onClick={onToggle}
        className="w-full px-4 py-3 flex items-center gap-3 hover:bg-zinc-50 transition"
      >
        {expanded ? (
          <ChevronDown className="h-4 w-4 text-zinc-400 flex-shrink-0" />
        ) : (
          <ChevronRight className="h-4 w-4 text-zinc-400 flex-shrink-0" />
        )}
        <div className="h-10 w-10 rounded-md bg-zinc-100 flex items-center justify-center flex-shrink-0">
          <Icon className="h-5 w-5 text-zinc-700" />
        </div>
        <div className="flex-1 text-left">
          <div className="flex items-center gap-2">
            <span className="font-medium text-zinc-900">{m.display_name}</span>
            {isCore && (
              <span className="px-2 py-0.5 text-[10px] font-semibold uppercase rounded bg-zinc-900 text-white tracking-wide">
                Core
              </span>
            )}
            <span className="text-[10px] font-mono text-zinc-400">{m.code}</span>
          </div>
          <p className="text-sm text-zinc-500 line-clamp-1 mt-0.5">{m.description}</p>
        </div>
        <div className="text-xs text-zinc-500 hidden sm:block">{summary}</div>
      </button>

      {expanded && (
        <div className="border-t border-zinc-200 p-4 bg-zinc-50/30">
          {role === 'super_admin' && m.global_view && <SuperAdminPanel module={m} />}
          {role === 'diretoria' && m.tenant_view && (
            <DiretoriaPanel
              module={m}
              tenantId={tenantId}
              onActivate={onActivate}
              onReactivate={onReactivate}
              onRequestDeactivate={onRequestDeactivate}
            />
          )}
        </div>
      )}
    </div>
  )
}

// ============================================================================
// SuperAdminPanel
// ============================================================================

function SuperAdminPanel({ module: m }: { module: ModuleSummary }) {
  const v = m.global_view!
  const stats = [
    { label: 'Tenants total', value: v.tenants_total },
    { label: 'Tenants ativos', value: v.tenants_active },
    { label: 'Tenants desativados', value: v.tenants_disabled },
    { label: 'Employer units ativos', value: v.employer_units_active },
    { label: 'Working units ativos', value: v.working_units_active },
    { label: 'Total de ativacoes', value: v.activations_total },
  ]
  return (
    <div className="grid grid-cols-2 sm:grid-cols-3 gap-3">
      {stats.map(s => (
        <div key={s.label} className="bg-white border border-zinc-200 rounded p-3">
          <div className="text-2xl font-semibold text-zinc-900">{s.value}</div>
          <div className="text-xs text-zinc-500 mt-1">{s.label}</div>
        </div>
      ))}
      <div className="col-span-full text-xs text-zinc-500 mt-2">
        Para gerenciar ativacoes, acesse via diretoria do tenant ou use o painel de
        administracao especifico do tenant.
      </div>
    </div>
  )
}

// ============================================================================
// DiretoriaPanel
// ============================================================================

function DiretoriaPanel({
  module: m, tenantId, onActivate, onReactivate, onRequestDeactivate,
}: {
  module: ModuleSummary
  tenantId: string | null
  onActivate: (code: string, scopeKind: ModuleScopeKind, scopeId: string) => void
  onReactivate: (code: string, scopeKind: ModuleScopeKind, scopeId: string) => void
  onRequestDeactivate: (
    code: string, name: string, scopeKind: ModuleScopeKind, scopeId: string, scopeLabel: string,
  ) => void
}) {
  const v = m.tenant_view!
  const isCore = m.is_core

  if (!tenantId) {
    return <div className="text-sm text-zinc-500">Carregando contexto do tenant...</div>
  }

  return (
    <div className="space-y-4">
      <ScopeBlock
        title="Tenant (toda a organizacao)"
        items={[{
          id: tenantId,
          name: 'Ativacao no nivel do tenant',
          code: '',
          active: v.tenant_active,
          disabled: v.tenant_disabled,
        }]}
        onActivate={(id) => onActivate(m.code, 'tenant', id)}
        onReactivate={(id) => onReactivate(m.code, 'tenant', id)}
        onDeactivate={(id) => onRequestDeactivate(
          m.code, m.display_name, 'tenant', id, 'Tenant inteiro',
        )}
        isCore={isCore}
      />

      {v.employer_units.length > 0 && (
        <ScopeBlock
          title="Employer Units"
          items={v.employer_units}
          onActivate={(id) => onActivate(m.code, 'employer_unit', id)}
          onReactivate={(id) => onReactivate(m.code, 'employer_unit', id)}
          onDeactivate={(id, name) => onRequestDeactivate(
            m.code, m.display_name, 'employer_unit', id, name,
          )}
          isCore={isCore}
        />
      )}

      {v.working_units.length > 0 && (
        <ScopeBlock
          title="Working Units"
          items={v.working_units}
          onActivate={(id) => onActivate(m.code, 'working_unit', id)}
          onReactivate={(id) => onReactivate(m.code, 'working_unit', id)}
          onDeactivate={(id, name) => onRequestDeactivate(
            m.code, m.display_name, 'working_unit', id, name,
          )}
          isCore={isCore}
        />
      )}
    </div>
  )
}

// ============================================================================
// ScopeBlock
// ============================================================================

function ScopeBlock({
  title, items, onActivate, onReactivate, onDeactivate, isCore,
}: {
  title: string
  items: UnitState[]
  onActivate: (id: string, name: string) => void
  onReactivate: (id: string, name: string) => void
  onDeactivate: (id: string, name: string) => void
  isCore: boolean
}) {
  return (
    <div>
      <div className="text-xs font-semibold uppercase tracking-wider text-zinc-500 mb-2">{title}</div>
      <div className="bg-white border border-zinc-200 rounded divide-y divide-zinc-100">
        {items.map(item => (
          <div key={item.id} className="px-3 py-2 flex items-center gap-3">
            <StatusBadge active={item.active} disabled={item.disabled} isCore={isCore} />
            <div className="flex-1 min-w-0">
              <div className="text-sm font-medium text-zinc-900 truncate">{item.name}</div>
              {item.code && <div className="text-xs text-zinc-500 font-mono">{item.code}</div>}
            </div>
            <div className="flex gap-1">
              {isCore ? (
                <span className="text-xs text-zinc-400 px-2 italic">core · sempre ativo</span>
              ) : item.active ? (
                <button
                  onClick={() => onDeactivate(item.id, item.name)}
                  className="px-3 py-1 text-xs font-medium text-zinc-700 hover:bg-zinc-100 border border-zinc-200 rounded"
                >
                  Desativar
                </button>
              ) : item.disabled ? (
                <button
                  onClick={() => onReactivate(item.id, item.name)}
                  className="px-3 py-1 text-xs font-medium text-blue-700 hover:bg-blue-50 border border-blue-200 rounded"
                >
                  Reativar
                </button>
              ) : (
                <button
                  onClick={() => onActivate(item.id, item.name)}
                  className="px-3 py-1 text-xs font-medium text-emerald-700 hover:bg-emerald-50 border border-emerald-200 rounded"
                >
                  Ativar
                </button>
              )}
            </div>
          </div>
        ))}
      </div>
    </div>
  )
}

function StatusBadge({ active, disabled, isCore }: { active: boolean; disabled: boolean; isCore: boolean }) {
  if (isCore) return <Lock className="h-4 w-4 text-zinc-400" />
  if (active) return <CheckCircle2 className="h-4 w-4 text-emerald-600" />
  if (disabled) return <AlertTriangle className="h-4 w-4 text-amber-500" />
  return <XCircle className="h-4 w-4 text-zinc-300" />
}

// ============================================================================
// DeactivateConfirmModal · usa Modules.getImpactSummary
// ============================================================================

function DeactivateConfirmModal({
  moduleCode, moduleName, scopeKind, scopeId, scopeLabel,
  onClose, onConfirm,
}: {
  moduleCode: string
  moduleName: string
  scopeKind: ModuleScopeKind
  scopeId: string
  scopeLabel: string
  onClose: () => void
  onConfirm: (reason: string) => void
}) {
  const [loading, setLoading] = useState(true)
  const [impact, setImpact] = useState<ImpactItem[]>([])
  const [reason, setReason] = useState('')
  const [consented, setConsented] = useState(false)

  useEffect(() => {
    (async () => {
      try {
        const r = await Modules.getImpactSummary(moduleCode, scopeKind, scopeId)
        setImpact(r.impact)
      } catch {
        setImpact([])
      } finally {
        setLoading(false)
      }
    })()
  }, [moduleCode, scopeKind, scopeId])

  return (
    <div
      className="fixed inset-0 z-50 bg-black/50 flex items-center justify-center p-4"
      onClick={onClose}
    >
      <div
        className="bg-white rounded-lg max-w-lg w-full p-5 max-h-[90vh] overflow-y-auto"
        onClick={(e) => e.stopPropagation()}
      >
        <div className="flex items-start gap-3 mb-4">
          <div className="h-10 w-10 rounded-full bg-amber-100 flex items-center justify-center flex-shrink-0">
            <AlertTriangle className="h-5 w-5 text-amber-600" />
          </div>
          <div className="flex-1">
            <h2 className="text-lg font-semibold text-zinc-900">Desativar {moduleName}?</h2>
            <p className="text-sm text-zinc-500 mt-0.5">Escopo: {scopeLabel}</p>
          </div>
        </div>

        <div className="bg-amber-50 border border-amber-200 rounded p-3 mb-4 text-sm text-amber-900">
          <strong>Atencao:</strong> ao desativar, todos os dados ficam em modo somente leitura.
          Avaliacoes em andamento sao bloqueadas para edicao, novos registros nao podem ser criados.
          Voce pode reativar a qualquer momento sem perda de dados.
        </div>

        <div className="mb-4">
          <h3 className="text-xs font-semibold uppercase tracking-wider text-zinc-500 mb-2">
            Dados afetados no escopo
          </h3>
          {loading ? (
            <div className="flex items-center justify-center py-4">
              <Loader2 className="h-4 w-4 animate-spin text-zinc-400" />
            </div>
          ) : (
            <ul className="space-y-1 text-sm">
              {impact.map((item) => (
                <li key={item.kind} className="flex justify-between py-1 px-2 rounded bg-zinc-50">
                  <span className="text-zinc-700">{item.label}</span>
                  <span className={`font-mono font-semibold ${item.count > 0 ? 'text-amber-700' : 'text-zinc-400'}`}>
                    {item.count}
                  </span>
                </li>
              ))}
            </ul>
          )}
        </div>

        <div className="mb-4">
          <label className="block text-xs font-semibold uppercase tracking-wider text-zinc-500 mb-2">
            Motivo (opcional)
          </label>
          <textarea
            value={reason}
            onChange={(e) => setReason(e.target.value)}
            rows={2}
            placeholder="Ex: reorganizacao, fim do periodo de avaliacao..."
            className="w-full border border-zinc-200 rounded px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-zinc-300"
          />
        </div>

        <label className="flex gap-3 items-start mb-5 cursor-pointer">
          <input
            type="checkbox"
            checked={consented}
            onChange={(e) => setConsented(e.target.checked)}
            className="mt-0.5 h-4 w-4 rounded border-zinc-300"
          />
          <span className="text-sm text-zinc-700">
            Entendo que apos a desativacao os dados ficarao em modo somente leitura
            ate a reativacao do modulo.
          </span>
        </label>

        <div className="flex gap-2 justify-end">
          <button
            onClick={onClose}
            className="px-4 py-2 text-sm font-medium text-zinc-700 hover:bg-zinc-100 border border-zinc-200 rounded"
          >
            Cancelar
          </button>
          <button
            disabled={!consented}
            onClick={() => onConfirm(reason)}
            className="px-4 py-2 text-sm font-medium text-white bg-red-600 hover:bg-red-700 disabled:opacity-50 disabled:cursor-not-allowed rounded"
          >
            Desativar modulo
          </button>
        </div>
      </div>
    </div>
  )
}

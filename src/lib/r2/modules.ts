/**
 * R2 People · Adapter · Modules (Sessao B2)
 * ============================================================================
 * Envelopa as RPCs de admin de modulos:
 *   - getOverview        · rpc_admin_modules_overview
 *   - activate           · rpc_admin_module_activate
 *   - deactivate         · rpc_admin_module_deactivate
 *   - reactivate         · rpc_admin_module_reactivate
 *   - getImpactSummary   · rpc_admin_module_impact_summary
 *   - getCatalog         · rpc_modules_catalog_list
 *   - listMyActive       · rpc_my_active_modules
 *   - checkActive        · rpc_module_check
 * ============================================================================
 */

import { callRpc, type ModuleScopeKind, type UserRole } from './base'

// ============================================================================
// Tipos · Overview
// ============================================================================

export interface UnitState {
  id: string
  name: string
  code: string
  active: boolean
  disabled: boolean
  employer_unit_id?: string
}

export interface ModuleTenantView {
  tenant_active: boolean
  tenant_disabled: boolean
  employer_units: UnitState[]
  working_units: UnitState[]
}

export interface ModuleGlobalView {
  tenants_total: number
  tenants_active: number
  tenants_disabled: number
  employer_units_active: number
  working_units_active: number
  activations_total: number
}

export interface ModuleSummary {
  code: string
  display_name: string
  description: string
  icon_name: string
  is_core: boolean
  display_order: number
  tenant_view?: ModuleTenantView   // presente quando role = diretoria
  global_view?: ModuleGlobalView   // presente quando role = super_admin
}

export interface ModulesOverview {
  role: UserRole
  modules: ModuleSummary[]
}

// ============================================================================
// Tipos · Impact summary
// ============================================================================

export interface ImpactItem {
  kind: string
  label: string
  count: number
  note?: string
}

export interface ImpactSummary {
  module: string
  scope_kind: ModuleScopeKind
  scope_id: string
  tenant_id: string
  impact: ImpactItem[]
}

// ============================================================================
// Tipos · Catalog (modulos disponiveis no sistema)
// ============================================================================

export interface ModuleCatalogEntry {
  code: string
  display_name: string
  description: string
  icon_name: string
  is_core: boolean
  display_order: number
  active: boolean
}

// ============================================================================
// Tipos · Activate/Deactivate results
// ============================================================================

export interface ActivationResult {
  activation_id?: string
  created?: boolean
  reactivated?: boolean
  already_active?: boolean
  already_disabled?: boolean
  disabled?: boolean
}

// ============================================================================
// API publica
// ============================================================================

export const Modules = {
  /**
   * Lista todos os modulos com estado por escopo.
   * super_admin recebe `global_view`, diretoria recebe `tenant_view`.
   */
  async getOverview(): Promise<ModulesOverview> {
    return callRpc<{ role: UserRole; modules: ModuleSummary[] }>('rpc_admin_modules_overview')
      .then(r => ({ role: r.role, modules: r.modules }))
  },

  /**
   * Ativa um modulo em um escopo. Idempotente · se ja ativo, retorna `already_active: true`.
   * Se existia uma ativacao em soft_disabled, reativa (retorna `reactivated: true`).
   *
   * Erros possiveis:
   *   - `not_authenticated`
   *   - `permission_denied`
   *   - `scope_outside_tenant`
   *   - `scope_not_found`
   *   - `module_not_found_or_inactive`
   */
  async activate(
    code: string,
    scopeKind: ModuleScopeKind,
    scopeId: string,
  ): Promise<ActivationResult> {
    return callRpc<Omit<ActivationResult, 'ok'>>('rpc_admin_module_activate', {
      p_module_code: code,
      p_scope_kind: scopeKind,
      p_scope_id: scopeId,
    })
  },

  /**
   * Soft-disable de um modulo. Dados ficam acessiveis em readonly.
   *
   * Erros possiveis:
   *   - `cannot_disable_core_module`
   *   - `activation_not_found`
   *   - `scope_outside_tenant`
   */
  async deactivate(
    code: string,
    scopeKind: ModuleScopeKind,
    scopeId: string,
    reason?: string,
  ): Promise<ActivationResult> {
    return callRpc<Omit<ActivationResult, 'ok'>>('rpc_admin_module_deactivate', {
      p_module_code: code,
      p_scope_kind: scopeKind,
      p_scope_id: scopeId,
      p_reason: reason ?? null,
    })
  },

  /**
   * Alias semantico de activate em activation soft_disabled.
   */
  async reactivate(
    code: string,
    scopeKind: ModuleScopeKind,
    scopeId: string,
  ): Promise<ActivationResult> {
    return callRpc<Omit<ActivationResult, 'ok'>>('rpc_admin_module_reactivate', {
      p_module_code: code,
      p_scope_kind: scopeKind,
      p_scope_id: scopeId,
    })
  },

  /**
   * Retorna preview dos dados afetados antes de desativar (counts por modulo).
   */
  async getImpactSummary(
    code: string,
    scopeKind: ModuleScopeKind,
    scopeId: string,
  ): Promise<ImpactSummary> {
    return callRpc<Omit<ImpactSummary, 'ok'>>('rpc_admin_module_impact_summary', {
      p_module_code: code,
      p_scope_kind: scopeKind,
      p_scope_id: scopeId,
    })
  },

  /**
   * Lista o catalogo de todos os modulos disponiveis no sistema.
   */
  async getCatalog(): Promise<{ modules: ModuleCatalogEntry[] }> {
    return callRpc<{ modules: ModuleCatalogEntry[] }>('rpc_modules_catalog_list')
      .then(r => ({ modules: r.modules }))
  },

  /**
   * Lista os modulos ativos para o user logado.
   */
  async listMyActive(): Promise<{ modules: string[] }> {
    return callRpc<{ modules: string[] }>('rpc_my_active_modules')
      .then(r => ({ modules: r.modules }))
  },

  /**
   * Verifica se um modulo especifico esta ativo para o user logado.
   * Util para gates de rota / componentes.
   */
  async checkActive(code: string): Promise<{ active: boolean; readonly: boolean }> {
    return callRpc<{ active: boolean; readonly: boolean }>('rpc_module_check', {
      p_module_code: code,
    }).then(r => ({ active: r.active, readonly: r.readonly }))
  },
}

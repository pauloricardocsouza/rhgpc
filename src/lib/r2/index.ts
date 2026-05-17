/**
 * R2 People · Adapter (C4)
 * ============================================================================
 * Cliente TypeScript tipado para todas as RPCs do banco.
 *
 * Uso:
 *
 *   import { Modules, Navbar, Ninebox } from '@/lib/r2'
 *
 *   const overview = await Modules.getOverview()
 *   if (overview.role === 'super_admin') {
 *     // overview.modules[0].global_view e tipado
 *   }
 *
 * Tratamento de erro:
 *
 *   try {
 *     await Modules.deactivate('ninebox', 'tenant', tenantId, 'reorg')
 *   } catch (err) {
 *     if (err instanceof RpcError) {
 *       if (err.code === 'cannot_disable_core_module') { ... }
 *     }
 *   }
 *
 * Versao "safe" (sem throw):
 *
 *   import { callRpcSafe } from '@/lib/r2'
 *   const r = await callRpcSafe('rpc_my_navbar')
 *   if ('error' in r) { ... } else { ... }
 * ============================================================================
 */

// Re-exports dos modulos
export * from './base'
export * from './modules'
export * from './navbar'
export * from './ninebox'
export * from './recognition'
export * from './pdi'
export * from './onboarding'
export * from './employees'
export * from './imports'

// Atalho · namespace agregador (opcional)
import { Modules } from './modules'
import { Navbar } from './navbar'
import { Ninebox } from './ninebox'
import { Recognition } from './recognition'
import { Pdi } from './pdi'
import { Onboarding } from './onboarding'
import {
  Employees, myTeam, myTeamDashboard, tenantDashboard, dashboardDrill, myJourney,
  mySentRecognitions,
  myProfileRequestCreate, myProfileRequestsList, myProfileRequestCancel,
  profileRequestsPendingList, profileRequestApprove, profileRequestReject,
} from './employees'
import { Imports } from './imports'

export const R2 = {
  Modules,
  Navbar,
  Ninebox,
  Recognition,
  Pdi,
  Onboarding,
  Employees,
  Imports,
  myTeam,
  myTeamDashboard,
  tenantDashboard,
  dashboardDrill,
  myJourney,
  mySentRecognitions,
  myProfileRequestCreate,
  myProfileRequestsList,
  myProfileRequestCancel,
  profileRequestsPendingList,
  profileRequestApprove,
  profileRequestReject,
}

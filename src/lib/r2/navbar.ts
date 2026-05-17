/**
 * R2 People · Adapter · Navbar (Sessao B3)
 * ============================================================================
 * Envelopa a RPC `rpc_my_navbar` que retorna a lista de itens da navbar do user
 * logado, ja filtrada por papel e estado dos modulos (inativo some, soft_disabled
 * aparece com readonly=true).
 * ============================================================================
 */

import { callRpc, type UserRole } from './base'

export type NavbarSection = 'main' | 'modules' | 'admin'

export interface NavbarItem {
  key: string
  label: string
  icon: string
  path: string
  module_code: string | null
  section: NavbarSection
  readonly: boolean
}

export interface NavbarResult {
  role: UserRole
  items: NavbarItem[]
}

export const Navbar = {
  /**
   * Retorna a navbar do user logado.
   *
   * Comportamento:
   *   - Items "core" (sem module_code) sempre aparecem se o papel tem acesso
   *   - Modulo ativo: aparece com readonly=false
   *   - Modulo soft_disabled: aparece com readonly=true (UI mostra cadeado)
   *   - Modulo nao ativo: omitido
   *   - super_admin: ve todos os itens do catalogo, sempre com readonly=false
   *
   * Erros: `not_authenticated`
   */
  async get(): Promise<NavbarResult> {
    return callRpc<{ role: UserRole; items: NavbarItem[] }>('rpc_my_navbar')
      .then(r => ({ role: r.role, items: r.items }))
  },
}

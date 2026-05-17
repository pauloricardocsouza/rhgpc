/**
 * R2 People · Adapter · Tipos base e helper de chamada de RPC
 * ============================================================================
 * Todas as RPCs do banco retornam um JSONB com forma:
 *   - Sucesso:  { ok: true, ...payload }
 *   - Erro:     { error: 'snake_case_code', ...extras }
 *
 * Este modulo:
 *   - Define o tipo discriminante `RpcResult<T>`
 *   - Encapsula o handling com `callRpc` que joga `RpcError` em caso de falha
 *   - Exporta enums espelhados do banco (module_scope_kind, ninebox_cycle_status, etc.)
 * ============================================================================
 */

import { createClient } from '@/lib/supabase'

// ============================================================================
// Enums espelhados do banco
// ============================================================================

export type ModuleScopeKind = 'tenant' | 'employer_unit' | 'working_unit'

export type NineboxCycleStatus = 'planning' | 'active' | 'closed'

export type NineboxEvaluationStatus =
  | 'draft'
  | 'self_done'
  | 'manager_done'
  | 'finalized'
  | 'canceled'

export type UserRole =
  | 'super_admin'
  | 'diretoria'
  | 'rh'
  | 'lider'
  | 'colaborador'

// ============================================================================
// Tipos genericos
// ============================================================================

export type RpcSuccess<T = Record<string, unknown>> = { ok: true } & T
export type RpcFailure = { error: string; [key: string]: unknown }
export type RpcResult<T = Record<string, unknown>> = RpcSuccess<T> | RpcFailure

export function isRpcError<T>(result: RpcResult<T>): result is RpcFailure {
  return (result as RpcFailure).error !== undefined
}

// ============================================================================
// Erro tipado
// ============================================================================

export class RpcError extends Error {
  code: string
  rpcName: string
  details: Record<string, unknown>

  constructor(rpcName: string, code: string, details: Record<string, unknown> = {}) {
    super(`[${rpcName}] ${code}`)
    this.name = 'RpcError'
    this.code = code
    this.rpcName = rpcName
    this.details = details
  }
}

// ============================================================================
// callRpc · helper que chama supabase.rpc e ja desempacota o resultado
// ============================================================================

/**
 * Chama uma RPC do Supabase e desempacota o resultado.
 *
 * Se a chamada falhar no nivel de rede / SQL, joga RpcError com code='supabase_error'.
 * Se a RPC retornar { error: ... }, joga RpcError com code = error code.
 * Caso contrario, retorna o payload do sucesso (sem o campo `ok`).
 *
 * As funcoes do adapter (Modules, Ninebox, etc.) ja desempacotam o payload e retornam
 * tipos limpos · nao precisa checar `r.ok` no chamador. Em caso de erro, capture
 * RpcError com try/catch.
 *
 * Use `callRpcSafe` se preferir tratar o erro como valor de retorno.
 */
export async function callRpc<T = Record<string, unknown>>(
  rpcName: string,
  params: Record<string, unknown> = {},
): Promise<T> {
  const supabase = createClient()
  const { data, error } = await supabase.rpc(rpcName, params)

  if (error) {
    throw new RpcError(rpcName, 'supabase_error', { message: error.message })
  }

  const result = data as RpcResult<T>

  if (isRpcError(result)) {
    throw new RpcError(rpcName, result.error, result)
  }

  // Tira o `ok: true` do retorno · o chamador recebe o payload limpo
  const { ok: _ok, ...payload } = result as RpcSuccess<T>
  return payload as T
}

/**
 * Versao "safe" · retorna o resultado tipado sem jogar excecao.
 * Util quando voce quer fazer pattern matching no chamador.
 */
export async function callRpcSafe<T = Record<string, unknown>>(
  rpcName: string,
  params: Record<string, unknown> = {},
): Promise<RpcResult<T>> {
  try {
    const payload = await callRpc<T>(rpcName, params)
    return { ok: true, ...payload } as RpcSuccess<T>
  } catch (err) {
    if (err instanceof RpcError) {
      return { error: err.code, ...err.details } as RpcFailure
    }
    return { error: 'unknown_error', message: String(err) } as RpcFailure
  }
}

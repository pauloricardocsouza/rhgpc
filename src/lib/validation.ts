/**
 * R2 People · Helpers de validação e máscaras
 * ============================================================================
 * Funções puras para validar e formatar campos brasileiros típicos:
 *   - CPF (com dígitos verificadores)
 *   - CEP
 *   - Telefone (10 ou 11 dígitos)
 *   - Data (DD/MM/AAAA ou AAAA-MM-DD)
 *
 * Convenção:
 *   - validateXxx(value): retorna `null` se válido ou string com mensagem de erro
 *   - formatXxx(value):   recebe dígitos crus, devolve string formatada
 *   - cleanXxx(value):    remove tudo que não é dígito
 * ============================================================================
 */

// ============================================================================
// CPF
// ============================================================================

export function cleanCpf(value: string): string {
  return (value || '').replace(/\D/g, '')
}

export function formatCpf(value: string): string {
  const digits = cleanCpf(value).slice(0, 11)
  if (digits.length <= 3) return digits
  if (digits.length <= 6) return `${digits.slice(0, 3)}.${digits.slice(3)}`
  if (digits.length <= 9) return `${digits.slice(0, 3)}.${digits.slice(3, 6)}.${digits.slice(6)}`
  return `${digits.slice(0, 3)}.${digits.slice(3, 6)}.${digits.slice(6, 9)}-${digits.slice(9)}`
}

/**
 * Valida CPF pelos dígitos verificadores (mod 11).
 * Retorna null se válido, mensagem de erro caso contrário.
 */
export function validateCpf(value: string): string | null {
  const digits = cleanCpf(value)
  if (digits.length === 0) return null  // vazio é tratado por "required"
  if (digits.length !== 11) return 'CPF deve ter 11 dígitos'

  // Rejeita sequências repetidas (111.111.111-11, etc)
  if (/^(\d)\1{10}$/.test(digits)) return 'CPF inválido'

  // DV1
  let sum = 0
  for (let i = 0; i < 9; i++) sum += parseInt(digits[i], 10) * (10 - i)
  let dv1 = 11 - (sum % 11)
  if (dv1 >= 10) dv1 = 0
  if (dv1 !== parseInt(digits[9], 10)) return 'CPF inválido'

  // DV2
  sum = 0
  for (let i = 0; i < 10; i++) sum += parseInt(digits[i], 10) * (11 - i)
  let dv2 = 11 - (sum % 11)
  if (dv2 >= 10) dv2 = 0
  if (dv2 !== parseInt(digits[10], 10)) return 'CPF inválido'

  return null
}

// ============================================================================
// CEP
// ============================================================================

export function cleanCep(value: string): string {
  return (value || '').replace(/\D/g, '')
}

export function formatCep(value: string): string {
  const digits = cleanCep(value).slice(0, 8)
  if (digits.length <= 5) return digits
  return `${digits.slice(0, 5)}-${digits.slice(5)}`
}

export function validateCep(value: string): string | null {
  const digits = cleanCep(value)
  if (digits.length === 0) return null
  if (digits.length !== 8) return 'CEP deve ter 8 dígitos'
  return null
}

// ============================================================================
// Telefone
// ============================================================================

export function cleanPhone(value: string): string {
  return (value || '').replace(/\D/g, '')
}

export function formatPhone(value: string): string {
  const digits = cleanPhone(value).slice(0, 11)
  if (digits.length === 0) return ''
  if (digits.length <= 2) return `(${digits}`
  if (digits.length <= 6) return `(${digits.slice(0, 2)}) ${digits.slice(2)}`
  if (digits.length <= 10) {
    // Fixo: (75) 1234-5678
    return `(${digits.slice(0, 2)}) ${digits.slice(2, 6)}-${digits.slice(6)}`
  }
  // Celular: (75) 91234-5678
  return `(${digits.slice(0, 2)}) ${digits.slice(2, 7)}-${digits.slice(7)}`
}

export function validatePhone(value: string): string | null {
  const digits = cleanPhone(value)
  if (digits.length === 0) return null
  if (digits.length < 10 || digits.length > 11) return 'Telefone deve ter 10 ou 11 dígitos'
  if (digits.length === 11 && digits[2] !== '9') return 'Celular deve começar com 9 após o DDD'
  return null
}

// ============================================================================
// Data
// ============================================================================

export function cleanDate(value: string): string {
  return (value || '').replace(/\D/g, '')
}

export function formatDateBr(value: string): string {
  const digits = cleanDate(value).slice(0, 8)
  if (digits.length <= 2) return digits
  if (digits.length <= 4) return `${digits.slice(0, 2)}/${digits.slice(2)}`
  return `${digits.slice(0, 2)}/${digits.slice(2, 4)}/${digits.slice(4)}`
}

/**
 * Valida data no formato DD/MM/AAAA.
 * - Verifica dia/mês válidos
 * - Verifica ano entre 1900 e ano atual + 1
 */
export function validateDateBr(value: string, options: {
  minYear?: number
  maxYear?: number
  notFuture?: boolean
} = {}): string | null {
  const digits = cleanDate(value)
  if (digits.length === 0) return null
  if (digits.length !== 8) return 'Data incompleta'

  const day = parseInt(digits.slice(0, 2), 10)
  const month = parseInt(digits.slice(2, 4), 10)
  const year = parseInt(digits.slice(4, 8), 10)

  const now = new Date()
  const minYear = options.minYear ?? 1900
  const maxYear = options.maxYear ?? now.getFullYear() + 1

  if (year < minYear || year > maxYear) return `Ano deve estar entre ${minYear} e ${maxYear}`
  if (month < 1 || month > 12) return 'Mês inválido'

  // Validação real do dia (considera ano bissexto)
  const date = new Date(year, month - 1, day)
  if (date.getFullYear() !== year || date.getMonth() !== month - 1 || date.getDate() !== day) {
    return 'Data inválida'
  }

  if (options.notFuture && date > now) return 'Data não pode ser no futuro'

  return null
}

/**
 * Converte DD/MM/AAAA para AAAA-MM-DD (formato ISO usado pelo banco).
 */
export function brDateToIso(value: string): string {
  const digits = cleanDate(value)
  if (digits.length !== 8) return ''
  return `${digits.slice(4, 8)}-${digits.slice(2, 4)}-${digits.slice(0, 2)}`
}

/**
 * Converte AAAA-MM-DD para DD/MM/AAAA (display em UI).
 */
export function isoDateToBr(iso: string): string {
  if (!iso) return ''
  const m = iso.match(/^(\d{4})-(\d{2})-(\d{2})/)
  if (!m) return iso
  return `${m[3]}/${m[2]}/${m[1]}`
}

// ============================================================================
// Hora
// ============================================================================

export function formatTime(value: string): string {
  const digits = (value || '').replace(/\D/g, '').slice(0, 4)
  if (digits.length <= 2) return digits
  return `${digits.slice(0, 2)}:${digits.slice(2)}`
}

export function validateTime(value: string): string | null {
  if (!value) return null
  const m = value.match(/^(\d{2}):(\d{2})$/)
  if (!m) return 'Hora deve estar no formato HH:MM'
  const h = parseInt(m[1], 10), min = parseInt(m[2], 10)
  if (h > 23) return 'Hora inválida'
  if (min > 59) return 'Minutos inválidos'
  return null
}

// ============================================================================
// Email
// ============================================================================

const EMAIL_RE = /^[^\s@]+@[^\s@]+\.[^\s@]+$/

export function validateEmail(value: string): string | null {
  if (!value) return null
  if (!EMAIL_RE.test(value)) return 'Email inválido'
  return null
}

// ============================================================================
// UF
// ============================================================================

export const UF_LIST = [
  'AC', 'AL', 'AP', 'AM', 'BA', 'CE', 'DF', 'ES', 'GO',
  'MA', 'MT', 'MS', 'MG', 'PA', 'PB', 'PR', 'PE', 'PI',
  'RJ', 'RN', 'RS', 'RO', 'RR', 'SC', 'SP', 'SE', 'TO',
] as const

export function validateUf(value: string): string | null {
  if (!value) return null
  const upper = value.toUpperCase()
  if (!(UF_LIST as readonly string[]).includes(upper)) return 'UF inválida'
  return null
}

'use client'

/**
 * R2 People · Componentes de campo de formulário
 * ============================================================================
 * Inputs reutilizáveis com:
 *   - Label uniforme
 *   - Estado de erro com mensagem inline
 *   - Validação onBlur (chamando validateFn opcional)
 *   - Variantes com máscara (CPF, telefone, CEP, data, hora)
 *
 * Filosofia: cada campo recebe e devolve `string`. A conversão para o
 * formato do banco (ex: DD/MM/AAAA → AAAA-MM-DD) acontece no momento do
 * submit, não no estado controlado.
 * ============================================================================
 */

import { useState, useEffect, useCallback, type InputHTMLAttributes, type TextareaHTMLAttributes } from 'react'
import { AlertCircle } from 'lucide-react'
import {
  formatCpf, validateCpf,
  formatCep, validateCep,
  formatPhone, validatePhone,
  formatDateBr, validateDateBr,
  formatTime, validateTime,
  validateEmail,
} from '@/lib/validation'

// ============================================================================
// Field wrapper
// ============================================================================

interface FieldShellProps {
  label: string
  required?: boolean
  error?: string | null
  hint?: string
  className?: string
  children: React.ReactNode
}

function FieldShell({ label, required, error, hint, className, children }: FieldShellProps) {
  return (
    <div className={className}>
      <label className="block text-xs font-semibold uppercase tracking-wider text-zinc-500 mb-1">
        {label}
        {required && <span className="text-red-600 ml-0.5">*</span>}
      </label>
      {children}
      {error ? (
        <div className="text-xs text-red-600 mt-1 flex items-center gap-1">
          <AlertCircle className="h-3 w-3" />
          {error}
        </div>
      ) : hint ? (
        <div className="text-xs text-zinc-500 mt-1">{hint}</div>
      ) : null}
    </div>
  )
}

// ============================================================================
// TextField · genérico
// ============================================================================

interface TextFieldProps {
  label: string
  value: string
  onChange: (v: string) => void
  required?: boolean
  hint?: string
  placeholder?: string
  maxLength?: number
  className?: string
  type?: 'text' | 'email' | 'number'
  inputMode?: InputHTMLAttributes<HTMLInputElement>['inputMode']
  validate?: (v: string) => string | null
  /** Se true, exibe erro mesmo sem ter recebido blur (usado no submit) */
  showError?: boolean
  /** Erro externo (vem de check do servidor, ex: CPF duplicado) */
  externalError?: string | null
}

export function TextField({
  label, value, onChange, required, hint, placeholder, maxLength, className,
  type = 'text', inputMode, validate, showError, externalError,
}: TextFieldProps) {
  const [touched, setTouched] = useState(false)
  const internalError = (touched || showError) && validate ? validate(value) : null
  const requiredError = (touched || showError) && required && !value.trim() ? 'Campo obrigatório' : null
  const error = externalError || internalError || requiredError

  return (
    <FieldShell label={label} required={required} error={error} hint={hint} className={className}>
      <input
        type={type}
        value={value}
        inputMode={inputMode}
        onChange={(e) => onChange(e.target.value)}
        onBlur={() => setTouched(true)}
        placeholder={placeholder}
        maxLength={maxLength}
        className={[
          'w-full px-3 py-2 text-sm border rounded focus:outline-none focus:ring-2',
          error
            ? 'border-red-300 focus:ring-red-200'
            : 'border-zinc-200 focus:ring-zinc-300',
        ].join(' ')}
      />
    </FieldShell>
  )
}

// ============================================================================
// Campos com máscara
// ============================================================================

interface MaskedFieldProps extends Omit<TextFieldProps, 'validate' | 'inputMode'> {}

export function CpfField({ value, onChange, ...rest }: MaskedFieldProps) {
  return (
    <TextField
      {...rest}
      value={formatCpf(value)}
      onChange={(v) => onChange(v)}
      validate={validateCpf}
      inputMode="numeric"
      maxLength={14}
      placeholder="000.000.000-00"
    />
  )
}

export function CepField({ value, onChange, ...rest }: MaskedFieldProps) {
  return (
    <TextField
      {...rest}
      value={formatCep(value)}
      onChange={(v) => onChange(v)}
      validate={validateCep}
      inputMode="numeric"
      maxLength={9}
      placeholder="00000-000"
    />
  )
}

export function PhoneField({ value, onChange, ...rest }: MaskedFieldProps) {
  return (
    <TextField
      {...rest}
      value={formatPhone(value)}
      onChange={(v) => onChange(v)}
      validate={validatePhone}
      inputMode="tel"
      maxLength={15}
      placeholder="(00) 00000-0000"
    />
  )
}

export function DateField({
  value, onChange, notFuture, ...rest
}: MaskedFieldProps & { notFuture?: boolean }) {
  return (
    <TextField
      {...rest}
      value={formatDateBr(value)}
      onChange={(v) => onChange(v)}
      validate={(v) => validateDateBr(v, { notFuture })}
      inputMode="numeric"
      maxLength={10}
      placeholder="DD/MM/AAAA"
    />
  )
}

export function TimeField({ value, onChange, ...rest }: MaskedFieldProps) {
  return (
    <TextField
      {...rest}
      value={formatTime(value)}
      onChange={(v) => onChange(v)}
      validate={validateTime}
      inputMode="numeric"
      maxLength={5}
      placeholder="HH:MM"
    />
  )
}

export function EmailField({ value, onChange, ...rest }: MaskedFieldProps) {
  return (
    <TextField
      {...rest}
      value={value}
      onChange={onChange}
      type="email"
      validate={validateEmail}
      placeholder="exemplo@dominio.com"
    />
  )
}

// ============================================================================
// SelectField
// ============================================================================

interface SelectFieldProps {
  label: string
  value: string
  onChange: (v: string) => void
  options: ReadonlyArray<readonly [string, string]>
  required?: boolean
  hint?: string
  className?: string
  showError?: boolean
}

export function SelectField({
  label, value, onChange, options, required, hint, className, showError,
}: SelectFieldProps) {
  const [touched, setTouched] = useState(false)
  const requiredError = (touched || showError) && required && !value ? 'Campo obrigatório' : null

  return (
    <FieldShell label={label} required={required} error={requiredError} hint={hint} className={className}>
      <select
        value={value}
        onChange={(e) => onChange(e.target.value)}
        onBlur={() => setTouched(true)}
        className={[
          'w-full px-3 py-2 text-sm border rounded focus:outline-none focus:ring-2 bg-white',
          requiredError
            ? 'border-red-300 focus:ring-red-200'
            : 'border-zinc-200 focus:ring-zinc-300',
        ].join(' ')}
      >
        {options.map(([val, lbl]) => (
          <option key={val} value={val}>{lbl}</option>
        ))}
      </select>
    </FieldShell>
  )
}

// ============================================================================
// TextareaField
// ============================================================================

export function TextareaField({
  label, value, onChange, required, hint, placeholder, maxLength, rows = 3, className,
}: {
  label: string
  value: string
  onChange: (v: string) => void
  required?: boolean
  hint?: string
  placeholder?: string
  maxLength?: number
  rows?: number
  className?: string
}) {
  return (
    <FieldShell label={label} required={required} hint={hint} className={className}>
      <textarea
        value={value}
        onChange={(e) => onChange(e.target.value)}
        placeholder={placeholder}
        maxLength={maxLength}
        rows={rows}
        className="w-full px-3 py-2 text-sm border border-zinc-200 rounded focus:outline-none focus:ring-2 focus:ring-zinc-300"
      />
    </FieldShell>
  )
}

// ============================================================================
// Hook · check de CPF duplicado (debounced)
// ============================================================================

import { Employees, RpcError } from '@/lib/r2'

export interface DuplicateCpfState {
  checking: boolean
  duplicate: {
    id: string
    full_name: string
    matricula_esocial: string | null
    is_active: boolean
  } | null
}

/**
 * Faz check de CPF com debounce. Retorna estado para exibir aviso.
 */
export function useCpfDuplicateCheck(cpf: string): DuplicateCpfState {
  const [state, setState] = useState<DuplicateCpfState>({ checking: false, duplicate: null })

  useEffect(() => {
    // Só checa se CPF é válido
    if (validateCpf(cpf) !== null) {
      setState({ checking: false, duplicate: null })
      return
    }

    setState({ checking: true, duplicate: null })
    const handle = setTimeout(async () => {
      try {
        const r = await Employees.checkCpf(cpf)
        if (r.exists && r.id && r.full_name) {
          setState({
            checking: false,
            duplicate: {
              id: r.id,
              full_name: r.full_name,
              matricula_esocial: r.matricula_esocial ?? null,
              is_active: r.is_active ?? true,
            },
          })
        } else {
          setState({ checking: false, duplicate: null })
        }
      } catch (err) {
        // Se for erro de permissão ou similar, só ignora silenciosamente
        if (!(err instanceof RpcError)) console.error(err)
        setState({ checking: false, duplicate: null })
      }
    }, 500)

    return () => clearTimeout(handle)
  }, [cpf])

  return state
}

// Re-export useCallback caso seja útil
export { useCallback }

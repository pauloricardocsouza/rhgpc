'use client'

/**
 * R2 People · EditSectionDialog
 * ============================================================================
 * Dialog generico para edicao de uma secao da ficha.
 * Recebe lista de fields (key, label, value, options? para select, textarea? etc)
 * e chama onSave com o payload das mudancas.
 *
 * Audit log e populado automaticamente via trigger no banco.
 * ============================================================================
 */

import { useState } from 'react'
import { X, Loader2 } from 'lucide-react'
import type { EmployeePayload } from '@/lib/r2'

export interface EditField {
  key: string
  label: string
  value: string
  required?: boolean
  options?: Array<[string, string]>   // [['solteiro', 'Solteiro(a)'], ...]
  textarea?: boolean
  maxLength?: number
  placeholder?: string
}

export function EditSectionDialog({
  title, fields, onCancel, onSave,
}: {
  title: string
  fields: EditField[]
  onCancel: () => void
  onSave: (payload: EmployeePayload) => Promise<void>
}) {
  const [values, setValues] = useState<Record<string, string>>(
    Object.fromEntries(fields.map(f => [f.key, f.value])),
  )
  const [saving, setSaving] = useState(false)
  const [error, setError] = useState<string | null>(null)

  const handleSave = async () => {
    setError(null)

    // Valida required
    for (const f of fields) {
      if (f.required && !values[f.key]?.trim()) {
        setError(`O campo "${f.label}" é obrigatório`)
        return
      }
    }

    // Monta payload apenas com campos que mudaram
    const payload: Record<string, unknown> = {}
    for (const f of fields) {
      if (values[f.key] !== f.value) {
        // Converte tipos especiais
        if (f.key === 'has_disability') {
          payload[f.key] = values[f.key] === 'true'
        } else if (f.key === 'initial_salary') {
          const v = values[f.key].trim().replace(',', '.')
          payload[f.key] = v ? Number(v) : null
        } else if (values[f.key] === '') {
          payload[f.key] = null
        } else {
          payload[f.key] = values[f.key]
        }
      }
    }

    if (Object.keys(payload).length === 0) {
      onCancel()
      return
    }

    setSaving(true)
    try {
      await onSave(payload as EmployeePayload)
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Erro ao salvar')
    } finally {
      setSaving(false)
    }
  }

  return (
    <div
      className="fixed inset-0 z-50 bg-black/50 flex items-center justify-center p-4"
      onClick={onCancel}
    >
      <div
        className="bg-white rounded-lg max-w-2xl w-full max-h-[90vh] overflow-hidden flex flex-col"
        onClick={(e) => e.stopPropagation()}
      >
        <div className="px-5 py-3 border-b border-zinc-200 flex items-center justify-between flex-shrink-0">
          <h2 className="text-lg font-semibold text-zinc-900">{title}</h2>
          <button
            onClick={onCancel}
            className="p-1 hover:bg-zinc-100 rounded text-zinc-500"
            aria-label="Fechar"
          >
            <X className="h-4 w-4" />
          </button>
        </div>

        <div className="px-5 py-4 overflow-y-auto flex-1">
          {error && (
            <div className="mb-3 px-3 py-2 bg-red-50 border border-red-200 rounded text-sm text-red-800">
              {error}
            </div>
          )}

          <div className="space-y-3">
            {fields.map(f => (
              <div key={f.key}>
                <label className="block text-xs font-semibold uppercase tracking-wider text-zinc-500 mb-1">
                  {f.label}{f.required && <span className="text-red-600 ml-0.5">*</span>}
                </label>
                {f.options ? (
                  <select
                    value={values[f.key]}
                    onChange={(e) => setValues({ ...values, [f.key]: e.target.value })}
                    className="w-full px-3 py-2 text-sm border border-zinc-200 rounded focus:outline-none focus:ring-2 focus:ring-zinc-300 bg-white"
                  >
                    {f.options.map(([val, lbl]) => (
                      <option key={val} value={val}>{lbl}</option>
                    ))}
                  </select>
                ) : f.textarea ? (
                  <textarea
                    value={values[f.key]}
                    onChange={(e) => setValues({ ...values, [f.key]: e.target.value })}
                    rows={3}
                    maxLength={f.maxLength}
                    placeholder={f.placeholder}
                    className="w-full px-3 py-2 text-sm border border-zinc-200 rounded focus:outline-none focus:ring-2 focus:ring-zinc-300"
                  />
                ) : (
                  <input
                    type="text"
                    value={values[f.key]}
                    onChange={(e) => setValues({ ...values, [f.key]: e.target.value })}
                    maxLength={f.maxLength}
                    placeholder={f.placeholder}
                    className="w-full px-3 py-2 text-sm border border-zinc-200 rounded focus:outline-none focus:ring-2 focus:ring-zinc-300"
                  />
                )}
              </div>
            ))}
          </div>

          <p className="mt-4 text-xs text-zinc-500 italic">
            As mudanças ficam registradas na auditoria com seu usuário e data/hora.
          </p>
        </div>

        <div className="px-5 py-3 border-t border-zinc-200 flex gap-2 justify-end flex-shrink-0">
          <button
            onClick={onCancel}
            disabled={saving}
            className="px-4 py-2 text-sm font-medium text-zinc-700 hover:bg-zinc-100 border border-zinc-200 rounded"
          >
            Cancelar
          </button>
          <button
            onClick={handleSave}
            disabled={saving}
            className="px-4 py-2 text-sm font-medium text-white bg-zinc-900 hover:bg-zinc-800 disabled:opacity-50 rounded inline-flex items-center gap-1.5"
          >
            {saving && <Loader2 className="h-3.5 w-3.5 animate-spin" />}
            Salvar
          </button>
        </div>
      </div>
    </div>
  )
}

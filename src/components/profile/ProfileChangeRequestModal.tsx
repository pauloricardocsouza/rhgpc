'use client'

/**
 * R2 People · ProfileChangeRequestModal (Sessao G3)
 * ============================================================================
 * Modal full-screen para o colaborador criar uma solicitacao de alteracao
 * de algum dado pessoal. Suporta 6 fields:
 *   - phone_mobile / phone_home  ({value: "71..."})
 *   - personal_email             ({value: "ex@ex.com"})
 *   - residence_address          ({value: "Rua..."})
 *   - emergency_contact          ({name, phone, relation})
 *   - photo                      (sobe arquivo + envia pending_photo_path)
 *
 * Para o backend ja existem RPCs G3 (rpc_my_profile_request_create).
 *
 * Notas sobre upload de foto:
 * - Em producao usa-se signed URL do Supabase storage no bucket
 *   'employee-photos' com path '<tenant_id>/<employee_id>/<request_id>.<ext>'.
 * - Aqui o componente assume que existe uma funcao uploadProfilePhoto que
 *   retorna o storage_path para passar no campo pending_photo_path.
 *   Como o ambiente local nao tem Storage real, o stub aceita o File e
 *   retorna um path simulado.
 * ============================================================================
 */

import { useState, useEffect, useCallback } from 'react'
import { X, Loader2, AlertCircle, Send, Upload, Image as ImageIcon } from 'lucide-react'

import { myProfileRequestCreate, RpcError, type ProfileChangeField } from '@/lib/r2'

// ============================================================================
// Stub de upload (substituir por createSignedUrl real no Supabase storage)
// ============================================================================
async function uploadProfilePhoto(file: File): Promise<string> {
  // Em producao:
  //   const supabase = createClient()
  //   const path = `${tenantId}/${employeeId}/${crypto.randomUUID()}.${file.name.split('.').pop()}`
  //   const { error } = await supabase.storage.from('employee-photos').upload(path, file)
  //   if (error) throw error
  //   return path
  //
  // Stub local: gera um path sintetico
  const ext = file.name.split('.').pop() || 'jpg'
  return `local-stub/${crypto.randomUUID()}.${ext}`
}

// ============================================================================
// Mensagens de erro friendly
// ============================================================================

const FIELD_LABELS: Record<ProfileChangeField, string> = {
  phone_mobile: 'Telefone celular',
  phone_home: 'Telefone fixo',
  personal_email: 'Email pessoal',
  residence_address: 'Endereço residencial',
  emergency_contact: 'Contato de emergência',
  photo: 'Foto de perfil',
}

function friendlyError(code: string): string {
  const map: Record<string, string> = {
    not_authenticated: 'Sessão expirada. Faça login novamente.',
    employee_not_linked: 'Ficha não vinculada. Peça ao RH para concluir o cadastro.',
    employee_not_found: 'Ficha não encontrada.',
    pending_request_exists: 'Já existe uma solicitação pendente para este campo.',
    phone_invalid: 'Telefone inválido (mínimo 8 dígitos).',
    email_invalid: 'Email inválido.',
    address_invalid: 'Endereço muito curto (mínimo 5 caracteres).',
    emergency_name_invalid: 'Nome do contato deve ter ao menos 2 caracteres.',
    emergency_phone_invalid: 'Telefone do contato inválido.',
    photo_path_required: 'É necessário anexar uma foto.',
    unknown_field: 'Campo desconhecido.',
  }
  return map[code] || `Erro: ${code}`
}

// ============================================================================
// Component
// ============================================================================

export interface ProfileChangeRequestModalProps {
  field: ProfileChangeField
  initialValue?: Record<string, unknown>
  onClose: () => void
  onCreated: () => void
}

export function ProfileChangeRequestModal({
  field, initialValue, onClose, onCreated,
}: ProfileChangeRequestModalProps) {

  // Inputs por field
  const [value, setValue] = useState<string>(
    typeof initialValue?.value === 'string' ? initialValue.value : ''
  )
  const [emergName, setEmergName] = useState<string>(
    typeof initialValue?.name === 'string' ? initialValue.name : ''
  )
  const [emergPhone, setEmergPhone] = useState<string>(
    typeof initialValue?.phone === 'string' ? initialValue.phone : ''
  )
  const [emergRelation, setEmergRelation] = useState<string>(
    typeof initialValue?.relation === 'string' ? initialValue.relation : ''
  )
  const [photoFile, setPhotoFile] = useState<File | null>(null)

  const [busy, setBusy] = useState(false)
  const [error, setError] = useState<string | null>(null)

  useEffect(() => {
    const h = (e: KeyboardEvent) => { if (e.key === 'Escape' && !busy) onClose() }
    window.addEventListener('keydown', h)
    return () => window.removeEventListener('keydown', h)
  }, [onClose, busy])

  const submit = useCallback(async () => {
    setError(null)
    setBusy(true)
    try {
      let newValue: Record<string, unknown>
      let pendingPhotoPath: string | undefined

      if (field === 'emergency_contact') {
        newValue = {
          name: emergName.trim(),
          phone: emergPhone.trim(),
          relation: emergRelation.trim() || null,
        }
      } else if (field === 'photo') {
        if (!photoFile) {
          setError('Selecione uma foto antes de enviar.')
          setBusy(false)
          return
        }
        pendingPhotoPath = await uploadProfilePhoto(photoFile)
        newValue = {}
      } else {
        newValue = { value: value.trim() }
      }

      await myProfileRequestCreate({ field, newValue, pendingPhotoPath })
      onCreated()
    } catch (err) {
      setError(err instanceof RpcError ? friendlyError(err.code) : 'Erro inesperado')
    } finally {
      setBusy(false)
    }
  }, [field, value, emergName, emergPhone, emergRelation, photoFile, onCreated])

  return (
    <div className="fixed inset-0 z-50 bg-black/50 flex" onClick={onClose}>
      <div className="bg-white w-full h-full overflow-y-auto" onClick={(e) => e.stopPropagation()}>
        {/* Header */}
        <div className="sticky top-0 bg-white border-b border-zinc-200 px-6 py-3 flex items-center gap-3 z-10">
          <button
            onClick={onClose}
            className="p-1.5 hover:bg-zinc-100 rounded text-zinc-600"
            title="Fechar (Esc)"
          >
            <X className="h-4 w-4" />
          </button>
          <Send className="h-5 w-5 text-zinc-600" />
          <h1 className="text-lg font-semibold text-zinc-900">
            Solicitar alteração: {FIELD_LABELS[field]}
          </h1>
        </div>

        <div className="px-6 py-6 max-w-2xl mx-auto space-y-5">
          <div className="border border-blue-200 bg-blue-50 rounded p-3 text-xs text-blue-900 flex items-start gap-2">
            <AlertCircle className="h-3.5 w-3.5 mt-0.5 flex-shrink-0" />
            <span>
              Sua solicitação será revisada pelo RH antes de ser aplicada. Você
              pode cancelar enquanto estiver pendente.
            </span>
          </div>

          {field === 'phone_mobile' || field === 'phone_home' ? (
            <Field label={FIELD_LABELS[field]} required hint="Apenas números, mínimo 8 dígitos">
              <input
                type="tel"
                value={value}
                onChange={(e) => setValue(e.target.value.replace(/\D/g, ''))}
                maxLength={15}
                placeholder="71988887777"
                className="w-full px-3 py-2 text-sm border border-zinc-200 rounded focus:outline-none focus:ring-2 focus:ring-zinc-300"
              />
            </Field>
          ) : null}

          {field === 'personal_email' && (
            <Field label="Email pessoal" required hint="Email de contato fora do trabalho">
              <input
                type="email"
                value={value}
                onChange={(e) => setValue(e.target.value)}
                maxLength={120}
                placeholder="seu@email.com"
                className="w-full px-3 py-2 text-sm border border-zinc-200 rounded focus:outline-none focus:ring-2 focus:ring-zinc-300"
              />
            </Field>
          )}

          {field === 'residence_address' && (
            <Field label="Endereço completo" required hint="Rua, número, complemento, bairro, cidade-UF, CEP">
              <textarea
                value={value}
                onChange={(e) => setValue(e.target.value)}
                rows={3}
                maxLength={300}
                placeholder="Rua das Flores, 123, Apto 45, Bairro Centro, Salvador-BA, 40000-000"
                className="w-full px-3 py-2 text-sm border border-zinc-200 rounded focus:outline-none focus:ring-2 focus:ring-zinc-300"
              />
            </Field>
          )}

          {field === 'emergency_contact' && (
            <>
              <Field label="Nome do contato" required>
                <input
                  type="text"
                  value={emergName}
                  onChange={(e) => setEmergName(e.target.value)}
                  maxLength={100}
                  className="w-full px-3 py-2 text-sm border border-zinc-200 rounded focus:outline-none focus:ring-2 focus:ring-zinc-300"
                />
              </Field>
              <Field label="Telefone do contato" required hint="Mínimo 8 dígitos">
                <input
                  type="tel"
                  value={emergPhone}
                  onChange={(e) => setEmergPhone(e.target.value.replace(/\D/g, ''))}
                  maxLength={15}
                  className="w-full px-3 py-2 text-sm border border-zinc-200 rounded focus:outline-none focus:ring-2 focus:ring-zinc-300"
                />
              </Field>
              <Field label="Parentesco" hint="Opcional · ex: mãe, irmã, cônjuge">
                <input
                  type="text"
                  value={emergRelation}
                  onChange={(e) => setEmergRelation(e.target.value)}
                  maxLength={40}
                  className="w-full px-3 py-2 text-sm border border-zinc-200 rounded focus:outline-none focus:ring-2 focus:ring-zinc-300"
                />
              </Field>
            </>
          )}

          {field === 'photo' && (
            <Field label="Foto de perfil" required hint="Formatos: JPG/PNG · max 5MB">
              <PhotoUploader file={photoFile} onChange={setPhotoFile} />
            </Field>
          )}

          {error && (
            <div className="border border-red-200 bg-red-50 rounded p-3 text-sm text-red-900 flex items-start gap-2">
              <AlertCircle className="h-4 w-4 mt-0.5 flex-shrink-0" />
              <span>{error}</span>
            </div>
          )}

          <div className="flex justify-end gap-2 pt-2 border-t border-zinc-100">
            <button
              onClick={onClose}
              disabled={busy}
              className="px-4 py-2 text-sm font-medium text-zinc-700 hover:bg-zinc-100 border border-zinc-200 disabled:opacity-50 rounded"
            >
              Cancelar
            </button>
            <button
              onClick={submit}
              disabled={busy}
              className="px-4 py-2 text-sm font-medium text-white bg-zinc-900 hover:bg-zinc-800 disabled:opacity-50 rounded inline-flex items-center gap-1.5"
            >
              {busy && <Loader2 className="h-3.5 w-3.5 animate-spin" />}
              <Send className="h-3.5 w-3.5" />
              Enviar solicitação
            </button>
          </div>
        </div>
      </div>
    </div>
  )
}

function Field({
  label, required, hint, children,
}: {
  label: string
  required?: boolean
  hint?: string
  children: React.ReactNode
}) {
  return (
    <div>
      <label className="block text-xs font-semibold uppercase tracking-wider text-zinc-500 mb-1">
        {label}
        {required && <span className="text-red-600 ml-0.5">*</span>}
      </label>
      {children}
      {hint && <p className="text-xs text-zinc-500 mt-1">{hint}</p>}
    </div>
  )
}

function PhotoUploader({
  file, onChange,
}: {
  file: File | null
  onChange: (f: File | null) => void
}) {
  const [previewUrl, setPreviewUrl] = useState<string | null>(null)

  useEffect(() => {
    if (!file) { setPreviewUrl(null); return }
    const url = URL.createObjectURL(file)
    setPreviewUrl(url)
    return () => URL.revokeObjectURL(url)
  }, [file])

  return (
    <div className="space-y-2">
      <label className="flex items-center justify-center gap-2 px-4 py-6 border-2 border-dashed border-zinc-300 rounded cursor-pointer hover:bg-zinc-50 transition">
        <Upload className="h-4 w-4 text-zinc-500" />
        <span className="text-sm text-zinc-700">
          {file ? 'Trocar foto' : 'Clique para selecionar uma foto'}
        </span>
        <input
          type="file"
          accept="image/jpeg,image/png,image/webp"
          className="hidden"
          onChange={(e) => {
            const f = e.target.files?.[0] ?? null
            if (f && f.size > 5 * 1024 * 1024) {
              alert('Foto maior que 5MB. Reduza o tamanho.')
              return
            }
            onChange(f)
          }}
        />
      </label>
      {previewUrl && (
        <div className="border border-zinc-200 rounded p-2 inline-flex items-center gap-3">
          {/* Preview · usa native img para nao depender de Next/Image */}
          {/* eslint-disable-next-line @next/next/no-img-element */}
          <img src={previewUrl} alt="Preview" className="h-20 w-20 object-cover rounded" />
          <div className="text-xs text-zinc-600">
            <div className="flex items-center gap-1">
              <ImageIcon className="h-3 w-3" />
              <span className="truncate max-w-xs">{file?.name}</span>
            </div>
            <div className="text-zinc-400 mt-0.5">
              {file ? `${(file.size / 1024).toFixed(0)} KB` : ''}
            </div>
          </div>
        </div>
      )}
    </div>
  )
}

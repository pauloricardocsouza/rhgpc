'use client'

/**
 * R2 People · ImportDialog
 * ============================================================================
 * Dialog para importacao de fichas em batch.
 *
 * Dois modos:
 *   - XLSX · usuario faz upload de planilha, frontend parseia com SheetJS,
 *     mostra preview e chama Employees.importXlsx
 *   - PDF · stub que avisa para usar o script Python `extrair_fichas_dominio.py`
 *     (OCR no servidor sera implementado em sessao futura via edge function)
 *
 * Requer SheetJS instalado: npm install xlsx
 * ============================================================================
 */

import { useState } from 'react'
import { X, Upload, FileSpreadsheet, FileText, Loader2, CheckCircle2, AlertTriangle } from 'lucide-react'
import { Employees, RpcError, type EmployeePayload, type ImportResult } from '@/lib/r2'

type Mode = 'select' | 'xlsx' | 'pdf'

export function ImportDialog({
  onClose, onImported,
}: {
  onClose: () => void
  onImported: () => void
}) {
  const [mode, setMode] = useState<Mode>('select')
  const [parsing, setParsing] = useState(false)
  const [importing, setImporting] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [records, setRecords] = useState<EmployeePayload[]>([])
  const [result, setResult] = useState<ImportResult | null>(null)

  const handleFileXlsx = async (file: File) => {
    setError(null)
    setParsing(true)
    try {
      // Importacao dinamica do SheetJS (so quando precisar)
      const XLSX = await import('xlsx')
      const buf = await file.arrayBuffer()
      const wb = XLSX.read(buf, { type: 'array' })

      // Procura a aba "Colaboradores" (vinda do nosso extrator)
      const sheetName = wb.SheetNames.find(n => n.toLowerCase().includes('colaborador')) || wb.SheetNames[0]
      const sheet = wb.Sheets[sheetName]
      const rows = XLSX.utils.sheet_to_json<Record<string, unknown>>(sheet, { defval: '' })

      // Mapeia para EmployeePayload
      const parsed: EmployeePayload[] = rows.map((row) => mapRowToPayload(row))
      setRecords(parsed)
    } catch (err) {
      setError(`Erro ao ler XLSX: ${err instanceof Error ? err.message : 'desconhecido'}`)
    } finally {
      setParsing(false)
    }
  }

  const handleImport = async () => {
    if (records.length === 0) return
    setError(null)
    setImporting(true)
    try {
      const r = await Employees.importXlsx(records)
      setResult(r)
    } catch (err) {
      setError(err instanceof RpcError ? `${err.code}: ${err.message}` : 'Erro ao importar')
    } finally {
      setImporting(false)
    }
  }

  return (
    <div
      className="fixed inset-0 z-50 bg-black/50 flex items-center justify-center p-4"
      onClick={onClose}
    >
      <div
        className="bg-white rounded-lg max-w-xl w-full max-h-[90vh] overflow-hidden flex flex-col"
        onClick={(e) => e.stopPropagation()}
      >
        <div className="px-5 py-3 border-b border-zinc-200 flex items-center justify-between flex-shrink-0">
          <h2 className="text-lg font-semibold text-zinc-900">Importar fichas</h2>
          <button onClick={onClose} className="p-1 hover:bg-zinc-100 rounded text-zinc-500">
            <X className="h-4 w-4" />
          </button>
        </div>

        <div className="px-5 py-4 overflow-y-auto flex-1">
          {/* Resultado da importacao */}
          {result && (
            <div className="space-y-3">
              <div className="border border-emerald-200 bg-emerald-50 rounded-md p-4">
                <div className="flex items-start gap-2">
                  <CheckCircle2 className="h-5 w-5 text-emerald-700 mt-0.5" />
                  <div className="flex-1">
                    <h3 className="font-semibold text-emerald-900">Importação concluída</h3>
                    <ul className="text-sm text-emerald-800 mt-2 space-y-0.5">
                      <li>{result.created} ficha(s) criada(s)</li>
                      <li>{result.skipped} já existiam (idempotência por CPF)</li>
                      <li>{result.errors.length} erro(s)</li>
                    </ul>
                  </div>
                </div>
              </div>

              {result.errors.length > 0 && (
                <div className="border border-amber-200 bg-amber-50 rounded p-3">
                  <h4 className="text-xs font-semibold uppercase tracking-wider text-amber-900 mb-2">
                    Linhas que falharam
                  </h4>
                  <ul className="text-xs text-amber-900 space-y-1 max-h-40 overflow-y-auto">
                    {result.errors.map((e, i) => (
                      <li key={i} className="font-mono">
                        Linha {e.index} · {e.full_name || '(sem nome)'} · {e.error}
                      </li>
                    ))}
                  </ul>
                </div>
              )}

              <div className="flex justify-end gap-2 pt-2">
                <button
                  onClick={onImported}
                  className="px-4 py-2 text-sm font-medium text-white bg-zinc-900 hover:bg-zinc-800 rounded"
                >
                  Concluir
                </button>
              </div>
            </div>
          )}

          {/* Tela inicial · escolha do modo */}
          {!result && mode === 'select' && (
            <div className="space-y-3">
              <p className="text-sm text-zinc-600">
                Escolha a origem dos dados:
              </p>
              <button
                onClick={() => setMode('xlsx')}
                className="w-full text-left p-4 border border-zinc-200 hover:border-zinc-400 hover:bg-zinc-50 rounded-lg transition"
              >
                <div className="flex items-start gap-3">
                  <FileSpreadsheet className="h-6 w-6 text-emerald-600 flex-shrink-0 mt-0.5" />
                  <div>
                    <div className="font-medium text-zinc-900">Planilha XLSX</div>
                    <div className="text-sm text-zinc-500 mt-0.5">
                      Use o arquivo gerado pelo extrator de fichas Domínio,
                      ou qualquer planilha com as colunas padrão.
                    </div>
                  </div>
                </div>
              </button>
              <button
                onClick={() => setMode('pdf')}
                className="w-full text-left p-4 border border-zinc-200 hover:border-zinc-400 hover:bg-zinc-50 rounded-lg transition"
              >
                <div className="flex items-start gap-3">
                  <FileText className="h-6 w-6 text-red-600 flex-shrink-0 mt-0.5" />
                  <div>
                    <div className="font-medium text-zinc-900">PDF do Domínio</div>
                    <div className="text-sm text-zinc-500 mt-0.5">
                      Upload do PDF de "Registro de Empregado" do sistema Domínio.
                      OCR é executado localmente.
                    </div>
                  </div>
                </div>
              </button>
            </div>
          )}

          {/* Modo XLSX */}
          {!result && mode === 'xlsx' && (
            <div className="space-y-3">
              {records.length === 0 ? (
                <>
                  <p className="text-sm text-zinc-600">
                    Faça upload da planilha. Espera-se uma aba "Colaboradores" com
                    as colunas padrão do extrator (full_name, cpf, hire_date, job_title...).
                  </p>
                  <label className="block border-2 border-dashed border-zinc-300 rounded-lg p-8 text-center cursor-pointer hover:border-zinc-400 hover:bg-zinc-50 transition">
                    <Upload className="h-8 w-8 mx-auto text-zinc-400 mb-2" />
                    <span className="text-sm font-medium text-zinc-700">
                      {parsing ? 'Lendo planilha...' : 'Clique para selecionar o arquivo .xlsx'}
                    </span>
                    <input
                      type="file"
                      accept=".xlsx,.xls,.csv"
                      className="hidden"
                      disabled={parsing}
                      onChange={(e) => {
                        const f = e.target.files?.[0]
                        if (f) handleFileXlsx(f)
                      }}
                    />
                  </label>
                </>
              ) : (
                <>
                  <div className="border border-zinc-200 rounded p-3 bg-zinc-50">
                    <h4 className="font-semibold text-zinc-900 text-sm mb-2">
                      Pré-visualização · {records.length} registro(s) detectado(s)
                    </h4>
                    <div className="max-h-48 overflow-y-auto text-xs space-y-1">
                      {records.slice(0, 8).map((r, i) => (
                        <div key={i} className="font-mono text-zinc-700">
                          {r.full_name || '(sem nome)'} · {r.cpf || 'sem CPF'} · {r.job_title || 'sem cargo'}
                        </div>
                      ))}
                      {records.length > 8 && (
                        <div className="text-zinc-500 italic">e mais {records.length - 8}...</div>
                      )}
                    </div>
                  </div>
                  <div className="bg-blue-50 border border-blue-200 rounded p-3 text-xs text-blue-900">
                    <strong>Idempotência:</strong> fichas com CPF já cadastrado serão puladas, não duplicadas.
                  </div>
                </>
              )}
            </div>
          )}

          {/* Modo PDF · agora redireciona para tela dedicada */}
          {!result && mode === 'pdf' && (
            <div className="space-y-3">
              <div className="bg-blue-50 border border-blue-200 rounded p-3 text-sm text-blue-900">
                <div className="flex gap-2 items-start">
                  <FileText className="h-4 w-4 mt-0.5 flex-shrink-0" />
                  <div>
                    <p>
                      <strong>OCR no servidor pronto.</strong>
                    </p>
                    <p className="mt-2">
                      Use a tela dedicada de importação por PDF, que processa o arquivo em background
                      e mostra uma tela de revisão lote a lote.
                    </p>
                    <p className="mt-2">
                      Você poderá editar campos com baixa confiança, aprovar ou rejeitar cada ficha
                      individualmente, ou aprovar todas em massa.
                    </p>
                  </div>
                </div>
              </div>
              <div className="flex gap-2 justify-end">
                <button
                  onClick={() => setMode('select')}
                  className="px-4 py-2 text-sm font-medium text-zinc-700 hover:bg-zinc-100 border border-zinc-200 rounded"
                >
                  ← Voltar
                </button>
                <a
                  href="/pessoas/importar"
                  className="px-4 py-2 text-sm font-medium text-white bg-zinc-900 hover:bg-zinc-800 rounded inline-flex items-center gap-1.5"
                >
                  Abrir importador PDF
                </a>
              </div>
            </div>
          )}

          {error && (
            <div className="mt-3 px-3 py-2 bg-red-50 border border-red-200 rounded text-sm text-red-800">
              {error}
            </div>
          )}
        </div>

        {/* Footer · ações */}
        {!result && (
          <div className="px-5 py-3 border-t border-zinc-200 flex gap-2 justify-between flex-shrink-0">
            <button
              onClick={() => mode === 'select' ? onClose() : setMode('select')}
              className="px-4 py-2 text-sm font-medium text-zinc-700 hover:bg-zinc-100 border border-zinc-200 rounded"
            >
              {mode === 'select' ? 'Cancelar' : 'Voltar'}
            </button>
            {mode === 'xlsx' && records.length > 0 && (
              <button
                onClick={handleImport}
                disabled={importing}
                className="px-4 py-2 text-sm font-medium text-white bg-zinc-900 hover:bg-zinc-800 disabled:opacity-50 rounded inline-flex items-center gap-1.5"
              >
                {importing && <Loader2 className="h-3.5 w-3.5 animate-spin" />}
                Importar {records.length} ficha(s)
              </button>
            )}
          </div>
        )}
      </div>
    </div>
  )
}

// ============================================================================
// Mapeamento de linha XLSX -> EmployeePayload
// ============================================================================

function mapRowToPayload(row: Record<string, unknown>): EmployeePayload {
  // Tenta mapear tanto por chave normalizada quanto por label PT-BR usado no extrator
  const get = (...keys: string[]): string | undefined => {
    for (const k of keys) {
      const v = row[k]
      if (v !== undefined && v !== null && String(v).trim() !== '') {
        return String(v).trim()
      }
    }
    return undefined
  }

  // Converte data BR (DD/MM/AAAA) para ISO (AAAA-MM-DD)
  const toIso = (v: string | undefined): string | undefined => {
    if (!v) return undefined
    const m = v.match(/^(\d{2})\/(\d{2})\/(\d{4})$/)
    return m ? `${m[3]}-${m[2]}-${m[1]}` : v
  }

  // Normaliza salario "1.119,30" -> 1119.30
  const toNumber = (v: string | undefined): number | undefined => {
    if (!v) return undefined
    const n = Number(v.replace(/\./g, '').replace(',', '.'))
    return isNaN(n) ? undefined : n
  }

  return {
    matricula_esocial: get('matricula_esocial', 'Matrícula eSocial'),
    ficha_numero: get('ficha_numero', 'Nº ficha'),
    full_name: get('full_name', 'nome', 'Nome completo') || '',
    beneficiaries: get('beneficiaries', 'beneficiarios', 'Beneficiários'),
    cpf: get('cpf', 'CPF'),
    rg: get('rg', 'RG'),
    rg_issue_date: toIso(get('rg_issue_date', 'rg_emissao', 'RG emissão')),
    rg_issuer: get('rg_issuer', 'rg_orgao', 'RG órgão emissor'),
    voter_id: get('voter_id', 'titulo_eleitor', 'Título eleitoral'),
    voter_zone: get('voter_zone', 'zona', 'Zona'),
    voter_section: get('voter_section', 'secao', 'Seção'),
    ctps_number: get('ctps_number', 'ctps', 'CTPS'),
    ctps_serie: get('ctps_serie', 'CTPS série'),
    ctps_issue_date: toIso(get('ctps_issue_date', 'ctps_expedicao', 'CTPS expedição')),
    ctps_uf: get('ctps_uf', 'CTPS UF'),
    pis: get('pis', 'PIS'),
    military_doc: get('military_doc', 'doc_militar', 'Doc. militar'),
    birth_date: toIso(get('birth_date', 'data_nascimento', 'Data de nascimento')),
    birth_city: get('birth_city'),  // o extrator gera "naturalidade" combinado
    birth_state: get('birth_state'),
    nationality: get('nationality', 'nacionalidade', 'Nacionalidade'),
    father_name: get('father_name', 'pai', 'Nome do pai'),
    mother_name: get('mother_name', 'mae', 'Nome da mãe'),
    residence_address: get('residence_address', 'residencia_endereco', 'Endereço residencial'),
    residence_cep: get('residence_cep', 'residencia_cep', 'CEP'),
    phone_home: get('phone_home', 'telefone_residencial', 'Tel. residencial'),
    phone_mobile: get('phone_mobile', 'telefone_celular', 'Tel. celular'),
    email: get('email', 'Email'),
    job_title: get('job_title', 'cargo', 'Cargo') || 'Não informado',
    job_function: get('job_function', 'funcao', 'Função'),
    cbo: get('cbo', 'CBO'),
    hire_date: toIso(get('hire_date', 'data_admissao', 'Data de admissão')) || '',
    initial_salary: toNumber(get('initial_salary', 'salario_inicial', 'Salário inicial (R$)')),
    salary_unit: (get('salary_unit', 'periodicidade', 'Periodicidade')?.toLowerCase().startsWith('h')
      ? 'hora' : 'mes') as 'hora' | 'mes',
    work_schedule_start: get('work_schedule_start', 'jornada_inicio', 'Jornada início'),
    work_schedule_end: get('work_schedule_end', 'jornada_fim', 'Jornada fim'),
    break_start: get('break_start', 'intervalo_inicio', 'Intervalo início'),
    break_end: get('break_end', 'intervalo_fim', 'Intervalo fim'),
    fgts_opt_in_date: toIso(get('fgts_opt_in_date', 'fgts_opcao', 'FGTS opção')),
    termination_date: toIso(get('termination_date', 'data_saida', 'Data de saída')),
    termination_reason: get('termination_reason', 'tipo_desligamento', 'Tipo de desligamento'),
    source: 'xlsx_import',
  }
}

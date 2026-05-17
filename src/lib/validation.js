"use strict";
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
Object.defineProperty(exports, "__esModule", { value: true });
exports.UF_LIST = void 0;
exports.cleanCpf = cleanCpf;
exports.formatCpf = formatCpf;
exports.validateCpf = validateCpf;
exports.cleanCep = cleanCep;
exports.formatCep = formatCep;
exports.validateCep = validateCep;
exports.cleanPhone = cleanPhone;
exports.formatPhone = formatPhone;
exports.validatePhone = validatePhone;
exports.cleanDate = cleanDate;
exports.formatDateBr = formatDateBr;
exports.validateDateBr = validateDateBr;
exports.brDateToIso = brDateToIso;
exports.isoDateToBr = isoDateToBr;
exports.formatTime = formatTime;
exports.validateTime = validateTime;
exports.validateEmail = validateEmail;
exports.validateUf = validateUf;
// ============================================================================
// CPF
// ============================================================================
function cleanCpf(value) {
    return (value || '').replace(/\D/g, '');
}
function formatCpf(value) {
    const digits = cleanCpf(value).slice(0, 11);
    if (digits.length <= 3)
        return digits;
    if (digits.length <= 6)
        return `${digits.slice(0, 3)}.${digits.slice(3)}`;
    if (digits.length <= 9)
        return `${digits.slice(0, 3)}.${digits.slice(3, 6)}.${digits.slice(6)}`;
    return `${digits.slice(0, 3)}.${digits.slice(3, 6)}.${digits.slice(6, 9)}-${digits.slice(9)}`;
}
/**
 * Valida CPF pelos dígitos verificadores (mod 11).
 * Retorna null se válido, mensagem de erro caso contrário.
 */
function validateCpf(value) {
    const digits = cleanCpf(value);
    if (digits.length === 0)
        return null; // vazio é tratado por "required"
    if (digits.length !== 11)
        return 'CPF deve ter 11 dígitos';
    // Rejeita sequências repetidas (111.111.111-11, etc)
    if (/^(\d)\1{10}$/.test(digits))
        return 'CPF inválido';
    // DV1
    let sum = 0;
    for (let i = 0; i < 9; i++)
        sum += parseInt(digits[i], 10) * (10 - i);
    let dv1 = 11 - (sum % 11);
    if (dv1 >= 10)
        dv1 = 0;
    if (dv1 !== parseInt(digits[9], 10))
        return 'CPF inválido';
    // DV2
    sum = 0;
    for (let i = 0; i < 10; i++)
        sum += parseInt(digits[i], 10) * (11 - i);
    let dv2 = 11 - (sum % 11);
    if (dv2 >= 10)
        dv2 = 0;
    if (dv2 !== parseInt(digits[10], 10))
        return 'CPF inválido';
    return null;
}
// ============================================================================
// CEP
// ============================================================================
function cleanCep(value) {
    return (value || '').replace(/\D/g, '');
}
function formatCep(value) {
    const digits = cleanCep(value).slice(0, 8);
    if (digits.length <= 5)
        return digits;
    return `${digits.slice(0, 5)}-${digits.slice(5)}`;
}
function validateCep(value) {
    const digits = cleanCep(value);
    if (digits.length === 0)
        return null;
    if (digits.length !== 8)
        return 'CEP deve ter 8 dígitos';
    return null;
}
// ============================================================================
// Telefone
// ============================================================================
function cleanPhone(value) {
    return (value || '').replace(/\D/g, '');
}
function formatPhone(value) {
    const digits = cleanPhone(value).slice(0, 11);
    if (digits.length === 0)
        return '';
    if (digits.length <= 2)
        return `(${digits}`;
    if (digits.length <= 6)
        return `(${digits.slice(0, 2)}) ${digits.slice(2)}`;
    if (digits.length <= 10) {
        // Fixo: (75) 1234-5678
        return `(${digits.slice(0, 2)}) ${digits.slice(2, 6)}-${digits.slice(6)}`;
    }
    // Celular: (75) 91234-5678
    return `(${digits.slice(0, 2)}) ${digits.slice(2, 7)}-${digits.slice(7)}`;
}
function validatePhone(value) {
    const digits = cleanPhone(value);
    if (digits.length === 0)
        return null;
    if (digits.length < 10 || digits.length > 11)
        return 'Telefone deve ter 10 ou 11 dígitos';
    if (digits.length === 11 && digits[2] !== '9')
        return 'Celular deve começar com 9 após o DDD';
    return null;
}
// ============================================================================
// Data
// ============================================================================
function cleanDate(value) {
    return (value || '').replace(/\D/g, '');
}
function formatDateBr(value) {
    const digits = cleanDate(value).slice(0, 8);
    if (digits.length <= 2)
        return digits;
    if (digits.length <= 4)
        return `${digits.slice(0, 2)}/${digits.slice(2)}`;
    return `${digits.slice(0, 2)}/${digits.slice(2, 4)}/${digits.slice(4)}`;
}
/**
 * Valida data no formato DD/MM/AAAA.
 * - Verifica dia/mês válidos
 * - Verifica ano entre 1900 e ano atual + 1
 */
function validateDateBr(value, options = {}) {
    const digits = cleanDate(value);
    if (digits.length === 0)
        return null;
    if (digits.length !== 8)
        return 'Data incompleta';
    const day = parseInt(digits.slice(0, 2), 10);
    const month = parseInt(digits.slice(2, 4), 10);
    const year = parseInt(digits.slice(4, 8), 10);
    const now = new Date();
    const minYear = options.minYear ?? 1900;
    const maxYear = options.maxYear ?? now.getFullYear() + 1;
    if (year < minYear || year > maxYear)
        return `Ano deve estar entre ${minYear} e ${maxYear}`;
    if (month < 1 || month > 12)
        return 'Mês inválido';
    // Validação real do dia (considera ano bissexto)
    const date = new Date(year, month - 1, day);
    if (date.getFullYear() !== year || date.getMonth() !== month - 1 || date.getDate() !== day) {
        return 'Data inválida';
    }
    if (options.notFuture && date > now)
        return 'Data não pode ser no futuro';
    return null;
}
/**
 * Converte DD/MM/AAAA para AAAA-MM-DD (formato ISO usado pelo banco).
 */
function brDateToIso(value) {
    const digits = cleanDate(value);
    if (digits.length !== 8)
        return '';
    return `${digits.slice(4, 8)}-${digits.slice(2, 4)}-${digits.slice(0, 2)}`;
}
/**
 * Converte AAAA-MM-DD para DD/MM/AAAA (display em UI).
 */
function isoDateToBr(iso) {
    if (!iso)
        return '';
    const m = iso.match(/^(\d{4})-(\d{2})-(\d{2})/);
    if (!m)
        return iso;
    return `${m[3]}/${m[2]}/${m[1]}`;
}
// ============================================================================
// Hora
// ============================================================================
function formatTime(value) {
    const digits = (value || '').replace(/\D/g, '').slice(0, 4);
    if (digits.length <= 2)
        return digits;
    return `${digits.slice(0, 2)}:${digits.slice(2)}`;
}
function validateTime(value) {
    if (!value)
        return null;
    const m = value.match(/^(\d{2}):(\d{2})$/);
    if (!m)
        return 'Hora deve estar no formato HH:MM';
    const h = parseInt(m[1], 10), min = parseInt(m[2], 10);
    if (h > 23)
        return 'Hora inválida';
    if (min > 59)
        return 'Minutos inválidos';
    return null;
}
// ============================================================================
// Email
// ============================================================================
const EMAIL_RE = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
function validateEmail(value) {
    if (!value)
        return null;
    if (!EMAIL_RE.test(value))
        return 'Email inválido';
    return null;
}
// ============================================================================
// UF
// ============================================================================
exports.UF_LIST = [
    'AC', 'AL', 'AP', 'AM', 'BA', 'CE', 'DF', 'ES', 'GO',
    'MA', 'MT', 'MS', 'MG', 'PA', 'PB', 'PR', 'PE', 'PI',
    'RJ', 'RN', 'RS', 'RO', 'RR', 'SC', 'SP', 'SE', 'TO',
];
function validateUf(value) {
    if (!value)
        return null;
    const upper = value.toUpperCase();
    if (!exports.UF_LIST.includes(upper))
        return 'UF inválida';
    return null;
}

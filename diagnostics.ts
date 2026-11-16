import { VERSION } from './core'

// Passive local evidence only. Callers record actual outcomes, never capability guesses.
// No network, permission prompts, media capture or automatic export occurs here.
export const DIAGNOSTIC_NAMES = ['capture', 'composition', 'video', 'gps', 'map', 'oauth'] as const
export type DiagnosticName = typeof DIAGNOSTIC_NAMES[number]
export type DiagnosticStatus = 'not-tested' | 'passed' | 'failed'
const LABELS: Record<DiagnosticName, string> = { capture: 'Captura de foto', composition: 'Composição do carimbo', video: 'Gravação de vídeo', gps: 'Localização', map: 'Mapa', oauth: 'Retorno OAuth nativo' }
const CODES = {
  completed: 'Operação concluída', cancelled: 'Cancelado pelo usuário',
  permission_denied: 'Permissão não concedida', unavailable: 'Recurso indisponível',
  timeout: 'Tempo limite excedido', invalid_result: 'Resultado inválido',
  network_error: 'Falha de conexão', operation_failed: 'Operação não concluída',
  disabled: 'Desativado nas configurações', pending: 'Ainda não concluído'
} as const
export type DiagnosticCode = keyof typeof CODES
const KEY = 'momentra.diagnostics.v1.' + VERSION
const MAX_DURATION = 24 * 60 * 60 * 1000
const MAX_TIME = 8640000000000000
interface Entry { status: DiagnosticStatus; code?: DiagnosticCode; at?: number; durationMs?: number; available?: boolean }
type Entries = Partial<Record<DiagnosticName, Entry>>
let cached: Entries | null = null
let persistenceFailed = false
const started: Partial<Record<DiagnosticName, number>> = {}
const own = (value: object, key: string) => Object.prototype.hasOwnProperty.call(value, key)
const isName = (value: unknown): value is DiagnosticName => typeof value === 'string' && (DIAGNOSTIC_NAMES as readonly string[]).includes(value)
const isStatus = (value: unknown): value is DiagnosticStatus => value === 'not-tested' || value === 'passed' || value === 'failed'
const safeCode = (value: unknown): DiagnosticCode | undefined => typeof value === 'string' && own(CODES, value) ? value as DiagnosticCode : undefined
const safeNumber = (value: unknown, max: number): value is number => typeof value === 'number' && Number.isFinite(value) && value >= 0 && value <= max
function read(): Entries {
  if (cached) return cached
  cached = {}
  try {
    const raw = Storage.get(KEY)
    if (!raw || raw.version !== VERSION || !raw.entries || typeof raw.entries !== 'object') return cached
    for (const name of DIAGNOSTIC_NAMES) {
      const item = own(raw.entries, name) ? raw.entries[name] : null
      if (!item || !isStatus(item.status)) continue
      const entry: Entry = { status: item.status }
      if (typeof item.available === 'boolean') entry.available = item.available
      // Reconstruct instead of spreading stored values: even tampered storage cannot leak data.
      if (item.status !== 'not-tested') {
        entry.code = safeCode(item.code)
        if (safeNumber(item.at, MAX_TIME)) entry.at = Math.floor(item.at)
        if (safeNumber(item.durationMs, MAX_DURATION)) entry.durationMs = Math.floor(item.durationMs)
      }
      cached[name] = entry
    }
  } catch { persistenceFailed = true }
  return cached
}
function save() {
  try { persistenceFailed = Storage.set(KEY, { version: VERSION, entries: read() }) !== true }
  catch { persistenceFailed = true }
}
// Starts only a stopwatch. It neither invokes nor approves the named operation.
export function beginDiagnostic(name: DiagnosticName): void {
  if (isName(name)) started[name] = Date.now()
}
export function recordDiagnostic(name: DiagnosticName, status: DiagnosticStatus, code?: DiagnosticCode): void {
  if (!isName(name) || !isStatus(status)) return
  const entries = read(), previous = entries[name]
  const next: Entry = { status }
  if (typeof previous?.available === 'boolean') next.available = previous.available
  if (status !== 'not-tested') {
    const now = Date.now(), start = started[name]
    if (safeNumber(now, MAX_TIME)) next.at = Math.floor(now)
    if (typeof start === 'number' && safeNumber(now - start, MAX_DURATION)) next.durationMs = Math.floor(now - start)
    next.code = safeCode(code) ?? (status === 'failed' ? 'operation_failed' : undefined)
  }
  delete started[name]
  entries[name] = next
  save()
}
// Presence of an API is explicitly separate from a successful hardware/authentication test.
export function recordApiAvailability(name: DiagnosticName, available: boolean): void {
  if (!isName(name) || typeof available !== 'boolean') return
  const entries = read()
  entries[name] = { ...entries[name], status: entries[name]?.status ?? 'not-tested', available }
  save()
}
export function buildDiagnosticReport(): string {
  const entries = read()
  const lines = ['Momentra ' + VERSION + ' · diagnóstico local',
    'Último resultado observado por recurso nesta versão; não é uma certificação completa.',
    'API presente não comprova funcionamento. Nenhum teste é executado ao abrir este relatório.',
    'Sem tokens, conta, coordenadas, imagens ou caminhos de arquivos.']
  if (persistenceFailed) lines.push('Persistência local indisponível: resultados desta sessão podem não sobreviver ao fechamento.')
  for (const name of DIAGNOSTIC_NAMES) {
    const item = entries[name], status = item?.status ?? 'not-tested'
    const result = status === 'passed' ? 'aprovado' : status === 'failed' ? 'falhou' : 'não testado'
    const api = item?.available === true ? 'presente' : item?.available === false ? 'ausente' : 'não verificada'
    let line = LABELS[name] + ': ' + result + ' | API: ' + api
    if (item?.code) line += ' | ' + CODES[item.code]
    if (item?.durationMs !== undefined) line += ' | duração: ' + item.durationMs + ' ms'
    if (item?.at !== undefined) line += ' | UTC: ' + new Date(item.at).toISOString()
    lines.push(line)
  }
  return lines.join('\n')
}

// Pure data/layout logic. No device services or network calls.
export const VERSION = "0.2.0"
export const PROFILE_IDS = ["HAMOA", "PIRESCO", "PESSOAL"] as const
export type ProfileID = typeof PROFILE_IDS[number]
export type Profile = { title: string; note: string; logoPath: string | null; accent: string }
export type Settings = {
  profile: ProfileID; stamp: boolean; gps: boolean; map: boolean
  position: "bottom" | "top"; size: "compact" | "regular"; profiles: Record<ProfileID, Profile>
}
export type Fix = { latitude: number; longitude: number; timestamp: number }
export type CaptureRecord = { handoffKey?: string; id: string; original: string; file: string; capturedAt: number; profile: ProfileID; stamped: boolean; saved: boolean; fix: Fix | null; address: string; warnings: string[] }
export function defaults(): Settings {
  return { profile: "HAMOA", stamp: true, gps: false, map: false, position: "bottom", size: "regular", profiles: {
    HAMOA: { title: "HAMOA", note: "", logoPath: null, accent: "#6FDED2" },
    PIRESCO: { title: "PIRESCO ENGENHARIA", note: "", logoPath: null, accent: "#E8C787" },
    PESSOAL: { title: "MOMENTRA", note: "", logoPath: null, accent: "#BBAAFF" },
  } }
}
export function cleanText(value: unknown, length = 96): string {
  return typeof value === "string" ? value.replace(/[\r\n\t]+/g, " ").trim().slice(0, length) : ""
}
export function normalizeSettings(raw: unknown): Settings {
  const d = defaults(); if (!raw || typeof raw !== "object") return d
  const r = raw as Partial<Settings>
  if (PROFILE_IDS.includes(r.profile as ProfileID)) d.profile = r.profile!
  for (const key of ["stamp", "gps", "map"] as const) if (typeof r[key] === "boolean") d[key] = r[key]!
  if (r.position === "top") d.position = "top"
  if (r.size === "compact") d.size = "compact"
  for (const id of PROFILE_IDS) {
    const p = r.profiles?.[id]; if (!p || typeof p !== "object") continue
    d.profiles[id].title = cleanText(p.title, 40) || d.profiles[id].title
    d.profiles[id].note = cleanText(p.note)
    d.profiles[id].logoPath = typeof p.logoPath === "string" ? p.logoPath : null
  }
  return d
}
export function validFix(fix: Fix | null, now: number): Fix | null {
  if (!fix || !Number.isFinite(fix.latitude) || !Number.isFinite(fix.longitude) || !Number.isFinite(fix.timestamp)) return null
  if (Math.abs(fix.latitude) > 90 || Math.abs(fix.longitude) > 180 || now - fix.timestamp > 60000 || fix.timestamp > now + 5000) return null
  return { ...fix }
}
export function dateLabel(time: number): string {
  const d = new Date(time); const pad = (n: number) => String(n).padStart(2, "0")
  const offset = -d.getTimezoneOffset(); const sign = offset >= 0 ? "+" : "−"
  return `${pad(d.getDate())}/${pad(d.getMonth()+1)}/${d.getFullYear()}  ${pad(d.getHours())}:${pad(d.getMinutes())}:${pad(d.getSeconds())}  UTC${sign}${pad(Math.floor(Math.abs(offset)/60))}:${pad(Math.abs(offset)%60)}`
}
export function coordinates(fix: Fix | null): string { return fix ? `${fix.latitude.toFixed(6)}, ${fix.longitude.toFixed(6)}` : "GPS indisponível no disparo" }
export function outputSize(width: number, height: number, max = 3072) {
  if (!(width > 0 && height > 0 && Number.isFinite(width) && Number.isFinite(height))) throw new Error("Dimensões de foto inválidas")
  const scale = Math.min(1, max / Math.max(width, height))
  return { width: Math.round(width * scale), height: Math.round(height * scale) }
}
export function stampLines(settings: Settings, record: CaptureRecord): string[] {
  const p = settings.profiles[record.profile]
  return [p.title, dateLabel(record.capturedAt), p.note, settings.gps ? coordinates(record.fix) : "", settings.gps ? cleanText(record.address, 120) : ""].filter(Boolean)
}
export function layoutStamp(width: number, height: number, lineCount: number, settings: Settings, hasMap: boolean, hasLogo: boolean) {
  const unit = Math.min(width, height) / 1000
  const pad = 26 * unit, font = (settings.size === "compact" ? 22 : 29) * unit
  const line = font * 1.4, side = hasMap ? 170 * unit : 0, logo = hasLogo ? 70 * unit : 0
  const h = Math.max(line * lineCount, side, logo) + 2 * pad
  const x = pad, y = settings.position === "top" ? pad : height - h - pad
  const w = width - 2 * pad
  return { x, y, w, h, pad, font, line, side, logo, textX: x + pad + (logo ? logo + pad : 0), textY: y + pad, textW: w - 2*pad - (side ? side+pad : 0) - (logo ? logo+pad : 0) }
}
export async function within<T>(promise: Promise<T>, ms: number, fallback: T): Promise<T> {
  let timer: ReturnType<typeof setTimeout> | undefined
  try { return await Promise.race([promise, new Promise<T>(resolve => { timer = setTimeout(() => resolve(fallback), ms) })]) }
  finally { if (timer !== undefined) clearTimeout(timer) }
}

export function orientedSize(width: number, height: number, orientation: number = 1) {
  return orientation >= 5 && orientation <= 8 ? {width:height,height:width} : {width,height}
}

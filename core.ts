import type { ModelWeather } from "./meteorology"
// Pure data/layout logic. No device services or network calls.
export const VERSION = "0.7.0"
export const PROFILE_IDS = ["HAMOA", "PIRESCO", "PESSOAL"] as const
export type ProfileID = typeof PROFILE_IDS[number]
export type Profile = { title: string; note: string; logoPath: string | null; accent: string }
export type Corner = "top-left" | "top-right" | "bottom-left" | "bottom-right"
export type Settings = {
  mapScale: "small" | "medium" | "large"; mapCorner: Corner; logoCorner: Corner
  storageMode: "local" | "cloud"
  profile: ProfileID; allowGallery: boolean; stamp: boolean; gps: boolean; map: boolean
  timestampFont: "system" | "serif" | "mono"; timestampFormat: "numeric" | "long"
  timestampCorner: "top-left" | "top-right" | "bottom-left" | "bottom-right"; aspectRatio: "4:3" | "16:9"
  position: "bottom" | "top"; size: "compact" | "regular"; profiles: Record<ProfileID, Profile>
}
export type Fix = { latitude: number; longitude: number; timestamp: number }
export type HeadingSample = { degrees: number; observedAt: number }
export type CaptureRecord = { forecast?: ModelWeather | null; heading?: HeadingSample | null; storageIntent?: "local" | "cloud"; handoffKey?: string; id: string; original: string; file: string; capturedAt: number; profile: ProfileID; stamped: boolean; saved: boolean; fix: Fix | null; address: string; warnings: string[] }
export function defaults(): Settings {
  return { storageMode:"local", allowGallery:true, mapScale:"medium", mapCorner:"bottom-left", logoCorner:"bottom-right", profile: "HAMOA", stamp: true, gps: false, map: false, timestampFont: "system", timestampFormat: "numeric", timestampCorner: "bottom-right", aspectRatio: "4:3", position: "bottom", size: "regular", profiles: {
    HAMOA: { title: "HAMOA", note: "", logoPath: null, accent: "#6FDED2" },
    PIRESCO: { title: "PIRESCO ENGENHARIA", note: "", logoPath: null, accent: "#E8C787" },
    PESSOAL: { title: "MOMENTRA", note: "", logoPath: null, accent: "#BBAAFF" },
  } }
}
export function cleanText(value: unknown, length = 96): string {
  return typeof value === "string" ? value.replace(/[\r\n\t]+/g, " ").trim().slice(0, length) : ""
}
export function nativeSettingsTransfer(s: Settings) {
  const profiles = Object.fromEntries(PROFILE_IDS.map(id => [id, {title:s.profiles[id].title,note:s.profiles[id].note,hasLogo:!!s.profiles[id].logoPath}]))
  return {format:"momentra-settings",version:1,settings:{profile:s.profile,stamp:s.stamp,gps:s.gps,map:s.map,aspectRatio:s.aspectRatio,storageMode:s.storageMode,allowGallery:s.allowGallery,size:s.size,position:s.position,timestampCorner:s.timestampCorner,timestampFormat:s.timestampFormat,timestampFont:s.timestampFont,mapScale:s.mapScale,mapCorner:s.mapCorner,logoCorner:s.logoCorner,profiles}}
}
export function normalizeSettings(raw: unknown): Settings {
  const d = defaults(); if (!raw || typeof raw !== "object") return d
  const r = raw as Partial<Settings>
  if (PROFILE_IDS.includes(r.profile as ProfileID)) d.profile = r.profile!
  for (const key of ["stamp", "gps", "map", "allowGallery"] as const) if (typeof r[key] === "boolean") d[key] = r[key]!
  if (r.storageMode === "cloud") { d.storageMode="cloud"; d.allowGallery=false }
  if (r.position === "top") d.position = "top"
  if (r.position === "top" || r.position === "bottom") d.timestampCorner = r.position === "top" ? "top-left" : "bottom-left"
  if (["top-left","top-right","bottom-left","bottom-right"].includes(r.timestampCorner!)) d.timestampCorner = r.timestampCorner!
  d.position = d.timestampCorner.startsWith("top") ? "top" : "bottom"
  if (["system","serif","mono"].includes(r.timestampFont!)) d.timestampFont = r.timestampFont!
  if (r.timestampFormat === "long") d.timestampFormat = "long"
  if (["small","medium","large"].includes(r.mapScale!)) d.mapScale = r.mapScale!
  for (const key of ["mapCorner","logoCorner"] as const) if (["top-left","top-right","bottom-left","bottom-right"].includes(r[key]!)) d[key] = r[key]!
  if (r.aspectRatio === "16:9") d.aspectRatio = "16:9"
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
export function dateLabel(time: number, format: Settings["timestampFormat"] = "numeric"): string {
  const d = new Date(time); const pad = (n: number) => String(n).padStart(2, "0")
  const offset = -d.getTimezoneOffset(); const sign = offset >= 0 ? "+" : "−"
  if (format === "long") {
    const months = ["janeiro","fevereiro","março","abril","maio","junho","julho","agosto","setembro","outubro","novembro","dezembro"]
    return `${d.getDate()} de ${months[d.getMonth()]} de ${d.getFullYear()} às ${pad(d.getHours())}h${pad(d.getMinutes())}min${pad(d.getSeconds())}s UTC${sign}${pad(Math.floor(Math.abs(offset)/60))}:${pad(Math.abs(offset)%60)}`
  }
  return `${pad(d.getDate())}/${pad(d.getMonth()+1)}/${d.getFullYear()}  ${pad(d.getHours())}:${pad(d.getMinutes())}:${pad(d.getSeconds())}  UTC${sign}${pad(Math.floor(Math.abs(offset)/60))}:${pad(Math.abs(offset)%60)}`
}
export function coordinates(fix: Fix | null): string { return fix ? `${fix.latitude.toFixed(6)}, ${fix.longitude.toFixed(6)}` : "GPS indisponível no disparo" }
export function outputSize(width: number, height: number, max = 3072) {
  if (!(width > 0 && height > 0 && Number.isFinite(width) && Number.isFinite(height))) throw new Error("Dimensões de foto inválidas")
  const scale = Math.min(1, max / Math.max(width, height))
  return { width: Math.round(width * scale), height: Math.round(height * scale) }
}
export function stampLines(settings: Settings, record: CaptureRecord, live = false): string[] {
  const p = settings.profiles[record.profile]
  const timestamp = dateLabel(record.capturedAt,settings.timestampFormat)
  const timeLines = settings.timestampFormat === "long" ? timestamp.split(" às ") : [timestamp]
  const f=settings.gps ? record.forecast : null
  const forecast = f ? [f.temperatureC !== null ? `${f.temperatureC.toFixed(1)} °C` : "", f.humidityPercent !== null ? `${Math.round(f.humidityPercent)}%` : "", f.windMs !== null ? `${(f.windMs*3.6).toFixed(1)} km/h` : "", f.seaLevelHpa !== null ? `${f.seaLevelHpa.toFixed(1)} hPa (nível do mar)` : ""].filter(Boolean).join(" · ") : ""
  return [p.title, p.note, settings.gps ? cleanText(record.address, 120) : "", settings.gps ? live && !record.fix ? "GPS indisponível" : coordinates(record.fix) : "Localização desativada", ...timeLines, forecast ? "Previsão: "+forecast : "", forecast ? "MET Norway · CC BY 4.0 · creativecommons.org/licenses/by/4.0/" : "", settings.gps && record.heading ? `Direção: ${Math.round(record.heading.degrees)}°` : ""].filter(Boolean)
}
export function layoutStamp(width: number, height: number, lineCount: number, settings: Settings, hasMap: boolean, hasLogo: boolean, textWidth?: number, maxWidth?: number) {
  const unit = Math.min(width, height) / 1000
  const pad = 26 * unit, font = (settings.size === "compact" ? 22 : 29) * unit
  const line = font * 1.4, side = hasMap ? 170 * unit : 0, logo = hasLogo ? 70 * unit : 0
  const h = Math.max(line * lineCount, side, logo) + 2 * pad
  const extras = 2*pad + (side ? side+pad : 0) + (logo ? logo+pad : 0)
  const w = Math.min(width-2*pad, maxWidth ?? width, Math.max(280*unit,(textWidth ?? 620*unit)+extras))
  const x = settings.timestampCorner.endsWith("right") ? width-w-pad : pad
  const y = settings.timestampCorner.startsWith("top") ? pad : height-h-pad
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

// Ratio follows orientation: portrait 3:4/9:16, landscape 4:3/16:9.
export function cropSize(width: number, height: number, aspectRatio: Settings["aspectRatio"]) {
  outputSize(width,height) // validate before division
  const ratio = aspectRatio === "16:9" ? 16/9 : 4/3
  const target = width >= height ? ratio : 1/ratio
  return width/height > target ? {width:height*target,height} : {width,height:width/target}
}
export function timestampFont(font: Settings["timestampFont"], size: number): number | {name:string;size:number} {
  // Canvas accepts the documented {name,size} custom UIFont form, not CSS font strings.
  return font === "serif" ? {name:"Georgia",size} : font === "mono" ? {name:"Courier",size} : size
}

export type OverlayRect = {x:number;y:number;w:number;h:number}
export function layoutOverlays(width:number,height:number,settings:Settings,stamp:OverlayRect,hasMap:boolean,hasLogo:boolean,alignMapWithStamp=false) {
  const unit=Math.min(width,height)/1000, pad=26*unit
  const placed:OverlayRect[]=[stamp]
  const epsilon=1e-7*Math.max(width,height)
  const overlaps=(a:OverlayRect,b:OverlayRect)=>a.x<b.x+b.w+pad-epsilon && a.x+a.w+pad>b.x+epsilon && a.y<b.y+b.h+pad-epsilon && a.y+a.h+pad>b.y+epsilon
  function place(side:number,corner:Corner,align=false):OverlayRect {
    const bottom=corner.startsWith("bottom")
    const rect={x:corner.endsWith("right")?width-pad-side:pad,y:bottom?height-pad-side:pad,w:side,h:side}
    // Stack toward the interior whenever any existing overlay intersects, including opposite-corner wide text.
    for(let i=0;i<placed.length+1;i++) {
      const collisions=placed.filter(p=>overlaps(rect,p))
      if(!collisions.length) break
      rect.y=bottom?Math.min(...collisions.map(p=>p.y))-pad-side:Math.max(...collisions.map(p=>p.y+p.h))+pad
    }
    rect.y=Math.max(pad,Math.min(height-pad-side,rect.y))
    if(align) rect.y=Math.max(pad,Math.min(height-pad-side,stamp.y+pad))
    placed.push(rect);return rect
  }
  return {map:hasMap?place(({small:140,medium:220,large:300}[settings.mapScale])*unit,settings.mapCorner,alignMapWithStamp):null,
    logo:hasLogo?place(90*unit,settings.logoCorner):null}
}

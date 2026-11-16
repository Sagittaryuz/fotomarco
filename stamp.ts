import { CaptureRecord, Settings, layoutStamp, stampLines, timestampFont, layoutOverlays } from "./core"
// The narrow drawing contract is shared by native Canvas and the local pixel tests.
export interface StampContext {
  fillStyle: any; font: any; textBaseline: any
  fillRect(x: number,y: number,w: number,h: number): void
  fillText(text: string,x: number,y: number,maxWidth?: number): void
  measureText(text: string): {width: number}
  drawImage(source: any,x: number,y: number,w: number,h: number): void
}
export function fitText(ctx: StampContext, text: string, width: number): string {
  if (ctx.measureText(text).width <= width) return text
  let lo = 0, hi = text.length
  while (lo < hi) { const mid = Math.ceil((lo+hi)/2); if (ctx.measureText(text.slice(0,mid)+"…").width <= width) lo=mid; else hi=mid-1 }
  return text.slice(0,lo)+"…"
}
export function wrapText(ctx: StampContext, text: string, width: number): string[] {
  const result: string[] = []; let line = ""
  for (const word of text.split(/\s+/).filter(Boolean)) {
    if (line && ctx.measureText(line + " " + word).width <= width) { line += " " + word; continue }
    if (line) { result.push(line); line = "" }
    for (const char of word) {
      if (line && ctx.measureText(line + char).width > width) { result.push(line); line = "" }
      line += char
    }
  }
  if (line) result.push(line)
  return result.length ? result : [""]
}
export function drawStamp(ctx: StampContext, width: number, height: number, settings: Settings, record: CaptureRecord, map: any = null, logo: any = null, live = false) {
  const rawLines = stampLines(settings, record, live)
  const initial = layoutStamp(width, height, rawLines.length, settings, false, false)
  const pair = !!map && settings.mapCorner.startsWith("bottom") === settings.timestampCorner.startsWith("bottom") && settings.mapCorner.endsWith("left") !== settings.timestampCorner.endsWith("left")
  const mapSide = ({small:140,medium:220,large:300}[settings.mapScale]) * Math.min(width,height)/1000
  const maxStampWidth = pair ? width-mapSide-3*initial.pad : width-2*initial.pad
  const maxTextWidth = maxStampWidth - 2*initial.pad
  const lines = rawLines.flatMap((text,i) => {
    ctx.font = timestampFont(settings.timestampFont,i === 0 ? initial.font*1.12 : initial.font)
    return wrapText(ctx,text,maxTextWidth)
  })
  const measured = lines.map((text,i) => { ctx.font = timestampFont(settings.timestampFont,i === 0 ? initial.font*1.12 : initial.font); return ctx.measureText(text).width })
  const b = layoutStamp(width, height, lines.length, settings, false, false,pair ? maxStampWidth : Math.max(...measured),maxStampWidth)
  const overlays = layoutOverlays(width,height,settings,b,!!map,!!logo,pair)
  if (pair && overlays.map) {
    const m=overlays.map, x=Math.max(0,Math.min(b.x,m.x)-b.pad/2), y=Math.max(0,Math.min(b.y,m.y)-b.pad/2)
    const right=Math.min(width,Math.max(b.x+b.w,m.x+m.w)+b.pad/2), bottom=Math.min(height,Math.max(b.y+b.h,m.y+m.h)+b.pad/2)
    ctx.fillStyle="rgba(0,0,0,0.65)";ctx.fillRect(x,y,right-x,bottom-y)
  }
  ctx.textBaseline = "top"
  lines.forEach((line,i) => {
    ctx.font = timestampFont(settings.timestampFont,i === 0 ? b.font * 1.12 : b.font)
    const text = fitText(ctx,line,b.textW)
    const x = !pair && settings.timestampCorner.endsWith("right") ? b.textX+b.textW-ctx.measureText(text).width : b.textX
    const y = b.textY+i*b.line, shadow = Math.max(0.6,b.font/18)
    ctx.fillStyle = "rgba(0,0,0,0.65)"; ctx.fillText(text,x+shadow,y+shadow)
    ctx.fillStyle = "#FFFFFF"; ctx.fillText(text,x,y)
  })
  if (map && overlays.map) { const m=overlays.map; ctx.drawImage(map,m.x,m.y,m.w,m.h) }
  if (logo && overlays.logo) {
    const l=overlays.logo
    const image = logo.image
    const ratio = image && image.width > 0 && image.height > 0 ? image.width/image.height : 1
    const w = ratio >= 1 ? l.w : l.w*ratio, h = ratio >= 1 ? l.h/ratio : l.h
    ctx.drawImage(logo,l.x+(l.w-w)/2,l.y+(l.h-h)/2,w,h)
  }
}

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
export function drawStamp(ctx: StampContext, width: number, height: number, settings: Settings, record: CaptureRecord, map: any = null, logo: any = null, live = false) {
  const lines = stampLines(settings, record, live)
  const initial = layoutStamp(width, height, lines.length, settings, false, false)
  const measured = lines.map((text,i) => { ctx.font = timestampFont(settings.timestampFont,i === 0 ? initial.font*1.12 : initial.font); return ctx.measureText(text).width })
  const b = layoutStamp(width, height, lines.length, settings, false, false,Math.max(...measured))
  ctx.fillStyle = "rgba(7,16,23,0.82)"; ctx.fillRect(b.x,b.y,b.w,b.h)
  ctx.fillStyle = settings.profiles[record.profile].accent; ctx.fillRect(b.x,b.y,Math.max(2,width/400),b.h)
  ctx.textBaseline = "top"
  lines.forEach((line,i) => {
    ctx.font = timestampFont(settings.timestampFont,i === 0 ? b.font * 1.12 : b.font)
    ctx.fillStyle = i === 0 ? settings.profiles[record.profile].accent : "#FFFFFF"
    ctx.fillText(fitText(ctx,line,b.textW),b.textX,b.textY+i*b.line)
  })
  const overlays = layoutOverlays(width,height,settings,b,!!map,!!logo)
  if (map && overlays.map) { const m=overlays.map; ctx.drawImage(map,m.x,m.y,m.w,m.h) }
  if (logo && overlays.logo) {
    const l=overlays.logo
    const image = logo.image
    const ratio = image && image.width > 0 && image.height > 0 ? image.width/image.height : 1
    const w = ratio >= 1 ? l.w : l.w*ratio, h = ratio >= 1 ? l.h/ratio : l.h
    ctx.drawImage(logo,l.x+(l.w-w)/2,l.y+(l.h-h)/2,w,h)
  }
}

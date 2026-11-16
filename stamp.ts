import { CaptureRecord, Settings, layoutStamp, stampLines } from "./core"
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
export function drawStamp(ctx: StampContext, width: number, height: number, settings: Settings, record: CaptureRecord, map: any = null, logo: any = null) {
  const lines = stampLines(settings, record)
  const b = layoutStamp(width, height, lines.length, settings, !!map, !!logo)
  ctx.fillStyle = "rgba(7,16,23,0.82)"; ctx.fillRect(b.x,b.y,b.w,b.h)
  ctx.fillStyle = settings.profiles[record.profile].accent; ctx.fillRect(b.x,b.y,Math.max(2,width/400),b.h)
  ctx.textBaseline = "top"
  lines.forEach((line,i) => {
    ctx.font = i === 0 ? b.font * 1.12 : b.font
    ctx.fillStyle = i === 0 ? settings.profiles[record.profile].accent : "#FFFFFF"
    ctx.fillText(fitText(ctx,line,b.textW),b.textX,b.textY+i*b.line)
  })
  if (map) { ctx.drawImage(map,b.x+b.w-b.pad-b.side,b.y+b.pad,b.side,b.side) }
  if (logo) {
    const image = logo.image
    const ratio = image && image.width > 0 && image.height > 0 ? image.width/image.height : 1
    const w = ratio >= 1 ? b.logo : b.logo*ratio, h = ratio >= 1 ? b.logo/ratio : b.logo
    ctx.drawImage(logo,b.x+b.pad+(b.logo-w)/2,b.y+b.pad+(b.logo-h)/2,w,h)
  }
}

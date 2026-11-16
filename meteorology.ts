// MET Norway forecast parsing only. No network is performed by this module.
// Timeseries is a model forecast, and sea-level pressure is not a barometer reading.
export type ModelWeather = {
  validAt: number; updatedAt: number; temperatureC: number | null;
  humidityPercent: number | null; windMs: number | null; seaLevelHpa: number | null
}
export function parseMetForecast(body: unknown, at: number): ModelWeather | null {
  if (!body || typeof body !== "object" || !Number.isFinite(at)) return null
  const properties = (body as any).properties, meta = properties?.meta
  const updatedAt = Date.parse(meta?.updated_at), series = properties?.timeseries
  if (!Number.isFinite(updatedAt) || updatedAt > at || at-updatedAt>86400000 || !Array.isArray(series)) return null
  const units = meta?.units
  const selected = series.map((entry:any)=>({entry,time:Date.parse(entry?.time)}))
    .filter((x:any)=>Number.isFinite(x.time) && x.time <= at && at-x.time <= 7200000)
    .sort((a:any,b:any)=>b.time-a.time)[0]
  if (!selected) return null
  const d=selected.entry?.data?.instant?.details
  if (!d || typeof d !== "object") return null
  const field=(key:string,unit:string,min:number,max:number):number|null =>
    units?.[key] === unit && typeof d[key] === "number" && Number.isFinite(d[key]) && d[key]>=min && d[key]<=max ? d[key] : null
  const result:ModelWeather={validAt:selected.time,updatedAt,
    temperatureC:field("air_temperature","celsius",-100,70),
    humidityPercent:field("relative_humidity","%",0,100),
    windMs:field("wind_speed","m/s",0,150),
    seaLevelHpa:field("air_pressure_at_sea_level","hPa",800,1100)}
  return [result.temperatureC,result.humidityPercent,result.windMs,result.seaLevelHpa].some(x=>x!==null) ? result : null
}

// Keep a bounded sequence of model times; a cached future entry becomes usable only when its time arrives.
export function parseMetForecastWindow(body:unknown,at:number):ModelWeather[] {
  const properties=(body as any)?.properties, series=properties?.timeseries
  const updatedAt=Date.parse(properties?.meta?.updated_at)
  if(!Array.isArray(series) || !Number.isFinite(updatedAt) || updatedAt>at || at-updatedAt>86400000) return []
  const times=[...new Set<number>(series.map((x:any)=>Date.parse(x?.time)).filter((t:number)=>Number.isFinite(t) && t>=at-7200000 && t<=at+10800000))].sort((a,b)=>a-b)
  return times.slice(0,8).map(time=>parseMetForecast(body,Math.max(at,time))).filter((x):x is ModelWeather=>x!==null)
}

export function validModelWeather(value:unknown,now:number):ModelWeather|null {
  if (!value || typeof value !== "object" || !Number.isFinite(now)) return null
  const v=value as Partial<ModelWeather>
  if (!Number.isFinite(v.validAt) || !Number.isFinite(v.updatedAt) || v.validAt!>now || v.updatedAt!>now || now-v.updatedAt!>86400000 || now-v.validAt!>7200000) return null
  const valid=(n:unknown,min:number,max:number)=>n===null || (typeof n==="number" && Number.isFinite(n) && n>=min && n<=max)
  if (!valid(v.temperatureC,-100,70) || !valid(v.humidityPercent,0,100) || !valid(v.windMs,0,150) || !valid(v.seaLevelHpa,800,1100)) return null
  if ([v.temperatureC,v.humidityPercent,v.windMs,v.seaLevelHpa].every(x=>x===null)) return null
  return {validAt:v.validAt!,updatedAt:v.updatedAt!,temperatureC:v.temperatureC!,humidityPercent:v.humidityPercent!,windMs:v.windMs!,seaLevelHpa:v.seaLevelHpa!}
}

// Prepared adapter. It never runs unless its caller explicitly enables it and supplies a transport.
// Persist the cooldown *before* sending so app restarts cannot bypass MET's minimum interval.
export type MetStore = { get(key:string): unknown; set(key:string,value:unknown): boolean }
export type MetTransport = (url:string, options:{headers:Record<string,string>;timeout:number;handleRedirect:()=>Promise<null>}) => Promise<{status:number;headers?:{get(name:string):string|null};json:()=>Promise<unknown>}>
export function metCoordinateKey(latitude:number,longitude:number):string {
  const coord=(n:number)=>(Math.trunc(n*10000)/10000).toFixed(4)
  return `${coord(latitude)},${coord(longitude)}`
}
export async function requestMetForecast(options:{enabled:boolean;foreground:boolean;latitude:number;longitude:number;now:number;store:MetStore;transport:MetTransport}):Promise<ModelWeather|null> {
  const {enabled,foreground,latitude,longitude,now,store,transport}=options
  if (!enabled || !foreground || !Number.isFinite(latitude) || !Number.isFinite(longitude) || Math.abs(latitude)>90 || Math.abs(longitude)>180 || !Number.isFinite(now)) return null
  const [lat,lon]=metCoordinateKey(latitude,longitude).split(","),key=`momentra.met.v1.${lat},${lon}`
  let existing:any
  try { existing=store.get(key) } catch { return null }
  if (existing && Number.isFinite(existing.at)) {
    if (now<existing.at) return null // clock moved backwards: keep the cooldown
    const retryAt=Number.isFinite(existing.retryAt) ? Math.max(existing.at+10800000,existing.retryAt) : existing.at+10800000
    if (now<retryAt) {
      const candidates=Array.isArray(existing.samples) ? existing.samples.slice(0,8) : [existing.sample]
      return candidates.map((x:unknown)=>validModelWeather(x,now)).filter((x:ModelWeather|null):x is ModelWeather=>x!==null).sort((a:ModelWeather,b:ModelWeather)=>b.validAt-a.validAt)[0] ?? null
    }
  }
  // Conservative fallback survives a failed second write, timeout or crash.
  try { if (!store.set(key,{at:now,retryAt:now+86400000,sample:null})) return null } catch { return null }
  try {
    const url=`https://api.met.no/weatherapi/locationforecast/2.0/compact?lat=${lat}&lon=${lon}`
    const response=await transport(url,{headers:{"User-Agent":"Momentra/0.7 github.com/Sagittaryuz/momentra"},timeout:10,handleRedirect:async()=>null})
    const header=(name:string)=>{ try { return response.headers?.get(name) ?? null } catch { return null } }
    let retryAt=now+10800000
    const expiry=Date.parse(header("Expires") ?? "")
    if (Number.isFinite(expiry)) retryAt=Math.max(retryAt,expiry)
    if(response.status===429) {
      const retry=header("Retry-After"), seconds=retry && /^\d+$/.test(retry) ? Number(retry) : NaN
      const date=retry ? Date.parse(retry) : NaN
      retryAt=Math.max(now+86400000,Number.isFinite(seconds) ? now+seconds*1000 : now,Number.isFinite(date) ? date : now)
      try { store.set(key,{at:now,retryAt,sample:null}) } catch {}
      return null
    }
    if(response.status!==200) return null
    const body=await response.json()
    const sample=parseMetForecast(body,now), samples=parseMetForecastWindow(body,now)
    try { store.set(key,{at:now,retryAt,sample,samples}) } catch { /* The conservative fallback remains. */ }
    return sample
  } catch { return null }
}

// Manual personal-photo integration only. No background upload, deletion, or video.
import { getGooglePhotosIdentity, photosAuthorizedFetch } from './google_auth'
import { PROFILE_IDS } from './core'
export type PersonalCapture = { id:string; file:string; capturedAt:number; profile:string }
export type AppPhoto = { id:string; filename:string; width?:number; height?:number; productUrl?:string; previewUrl?:string; previewExpiresAt?:number }
export type PhotoPage = { items:AppPhoto[]; nextPageToken?:string }
export type PhotoUploadResult = { status:'uploaded'|'verification-pending'|'uncertain'|'failed'; captureId:string; mediaItemId?:string; item?:AppPhoto; message:string }
type Journal = { version:1; captureId:string; capturedAt:number; state:'creating'|'known'|'verified'|'failed'; mediaItemId?:string }
const BASE='https://photoslibrary.googleapis.com/v1', MAX_FILE=20*1024*1024, MAX_RESPONSE=256*1024
const pending=new Map<string,Promise<PhotoUploadResult>>()
const safeId=(v:any):v is string=>typeof v==='string'&&/^[A-Za-z0-9_-]{1,512}$/.test(v)
const failure=()=>new Error('Não foi possível acessar o Google Fotos. Seus arquivos locais foram preservados.')
function account():string { const state=getGooglePhotosIdentity();if(state.status!=='connected'||state.expiresAt<=Date.now())throw new Error('Conecte o Google Fotos antes de continuar.');return state.identity.sub }
function clean(v:any,max=255):string {return typeof v==='string'?v.replace(/[\u0000-\u001f\u007f]/g,'').slice(0,max):''}
function safeURL(v:any,kind:'product'|'image'):string|undefined {
  if(typeof v!=='string'||v.length>8192)return
  try {const u=new URL(v);if(u.protocol!=='https:'||u.username||u.password||u.port||u.hash)return
    if(kind==='product' ? u.hostname!=='photos.google.com' : !/(^|\.)googleusercontent\.com$/.test(u.hostname))return
    return u.toString()
  } catch {return}
}
function photo(raw:any):AppPhoto|null {
  if(!raw||!safeId(raw.id)||raw.mimeType!=='image/jpeg')return null
  const item:AppPhoto={id:raw.id,filename:clean(raw.filename)}
  const width=Number(raw.mediaMetadata?.width),height=Number(raw.mediaMetadata?.height)
  if(Number.isInteger(width)&&width>0&&width<=100000)item.width=width
  if(Number.isInteger(height)&&height>0&&height<=100000)item.height=height
  const product=safeURL(raw.productUrl,'product');if(product)item.productUrl=product
  const base=safeURL(raw.baseUrl,'image');if(base){item.previewUrl=base+'=w600-h600';item.previewExpiresAt=Date.now()+55*60*1000}
  return item
}
async function bounded(response:Response,max:number):Promise<string> {
  const declared=Number(response.headers.get('Content-Length'));if(Number.isFinite(declared)&&declared>max)throw failure()
  const reader=response.body?.getReader();if(!reader)throw failure()
  let size=0;const chunks:Uint8Array[]=[]
  try {while(true){const next=await reader.read();if(next.done)break;size+=next.value.byteLength;if(size>max){await reader.cancel();throw failure()}chunks.push(next.value)}}finally{reader.releaseLock()}
  const joined=new Uint8Array(size);let offset=0;for(const chunk of chunks){joined.set(chunk,offset);offset+=chunk.byteLength}return new TextDecoder().decode(joined)
}
async function request(url:string,sub:string,init:{method?:'GET'|'POST';headers?:Record<string,string>;body?:any}={},max=MAX_RESPONSE):Promise<{status:number;ok:boolean;text:string}> {
  const controller=new AbortController(),timer=setTimeout(()=>controller.abort(),20000)
  try {const r=await photosAuthorizedFetch(url,{...init,signal:controller.signal},sub);const text=await bounded(r,max);if(account()!==sub)throw failure();return {status:r.status,ok:r.ok,text}}
  catch {throw failure()}finally{clearTimeout(timer)}
}
function parse(text:string):any {try{return JSON.parse(text)}catch{throw failure()}}
async function getFor(id:string,sub:string):Promise<AppPhoto> {
  if(!safeId(id))throw failure()
  const r=await request(BASE+'/mediaItems/'+encodeURIComponent(id),sub,{},32768)
  if(!r.ok)throw failure();const item=photo(parse(r.text));if(!item||item.id!==id)throw failure();return item
}
// Returned preview URLs are short-lived memory-only display values. Persist IDs, never these URLs.
export async function getMediaItem(id:string):Promise<AppPhoto> {return getFor(id,account())}
export async function listAppPhotos(pageToken?:string):Promise<PhotoPage> {
  if(pageToken!==undefined&&(typeof pageToken!=='string'||!pageToken||pageToken.length>2048||/[\u0000-\u0020\u007f]/.test(pageToken)))throw failure()
  const sub=account(),params=new URLSearchParams({pageSize:'25'});if(pageToken)params.set('pageToken',pageToken)
  const r=await request(BASE+'/mediaItems?'+params.toString(),sub);if(!r.ok)throw failure();const raw=parse(r.text)
  if(!raw||typeof raw!=='object'||(raw.mediaItems!==undefined&&!Array.isArray(raw.mediaItems))||(raw.mediaItems?.length??0)>25)throw failure()
  const items=(raw.mediaItems??[]).map(photo).filter((p:AppPhoto|null):p is AppPhoto=>p!==null)
  const result:PhotoPage={items}
  if(raw.nextPageToken!==undefined){if(typeof raw.nextPageToken!=='string'||!raw.nextPageToken||raw.nextPageToken.length>2048||/[\u0000-\u0020\u007f]/.test(raw.nextPageToken))throw failure();result.nextPageToken=raw.nextPageToken}
  return result
}
function journalKey(capture:PersonalCapture,sub:string):string {return 'momentra.photos.upload.v1.'+encodeURIComponent(sub)+'.'+capture.id}
function read(key:string,capture:PersonalCapture):Journal|null {
  try {const j=Storage.get<Journal>(key);if(j==null)return null
    if(j.version!==1||j.captureId!==capture.id||j.capturedAt!==capture.capturedAt||!['creating','known','verified','failed'].includes(j.state)||(['known','verified'].includes(j.state)&&!safeId(j.mediaItemId)))throw failure();return j
  }catch{throw failure()}
}
function save(key:string,j:Journal):void {try{if(!Storage.set(key,j))throw failure()}catch{throw failure()}}
const uncertain=(id:string):PhotoUploadResult=>({status:'uncertain',captureId:id,message:'O envio pode ter sido concluído. Confira o Google Fotos; o reenvio desta captura está bloqueado para evitar duplicação. Arquivo local preservado.'})
async function verify(capture:PersonalCapture,sub:string,key:string,id:string):Promise<PhotoUploadResult> {
  try {const item=await getFor(id,sub);save(key,{version:1,captureId:capture.id,capturedAt:capture.capturedAt,state:'verified',mediaItemId:id});return {status:'uploaded',captureId:capture.id,mediaItemId:id,item,message:'Foto pessoal confirmada no Google Fotos. O arquivo local foi preservado.'}}
  catch{return {status:'verification-pending',captureId:capture.id,mediaItemId:id,message:'O Google recebeu a foto, mas a verificação está pendente. A próxima tentativa só verifica o item, sem reenviar.'}}
}
async function perform(capture:PersonalCapture,sub:string,key:string,filename=capture.id+'.jpg'):Promise<PhotoUploadResult> {
  if(await FileManager.isLink(FileManager.documentsDirectory.replace(/\/$/,'')+'/Momentra'))throw failure()
  const old=read(key,capture)
  if(old?.state==='creating')return uncertain(capture.id)
  if(old?.mediaItemId)return verify(capture,sub,key,old.mediaItemId)
  // File selection is restricted to this app's final JPEG for the explicitly chosen capture.
  let data:Data
  try {const stat=await FileManager.stat(capture.file);if(stat.type!=='file'||!Number.isInteger(stat.size)||stat.size<4||stat.size>MAX_FILE||await FileManager.isLink(capture.file))throw failure()
    data=await FileManager.readAsData(capture.file);const signature=data.slice(0,3).toUint8Array();if(data.size!==stat.size||!signature||signature[0]!==255||signature[1]!==216||signature[2]!==255)throw failure()
  }catch{throw new Error('Escolha uma foto JPEG pessoal do Momentra de até 20 MB. Nenhum arquivo foi enviado.')}
  let token:string
  try {const r=await request(BASE+'/uploads',sub,{method:'POST',headers:{'Content-Type':'application/octet-stream','X-Goog-Upload-Content-Type':'image/jpeg','X-Goog-Upload-Protocol':'raw'},body:data},8192)
    if(!r.ok)throw failure();token=r.text.trim();if(!/^[\x21-\x7E]{1,8192}$/.test(token))throw failure()
  }catch{return {status:'failed',captureId:capture.id,message:'A foto não foi confirmada no Google Fotos. O arquivo local está preservado; tente novamente quando houver conexão.'}}
  // Persist before creation: a crash/timeout/ambiguous body must never silently re-upload.
  save(key,{version:1,captureId:capture.id,capturedAt:capture.capturedAt,state:'creating'})
  let raw:any
  try {const r=await request(BASE+'/mediaItems:batchCreate',sub,{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({newMediaItems:[{simpleMediaItem:{uploadToken:token,fileName:filename}}]})},32768)
    if(!r.ok)return uncertain(capture.id);raw=parse(r.text)
  }catch{return uncertain(capture.id)}
  const rows=raw?.newMediaItemResults
  if(!Array.isArray(rows)||rows.length!==1)return uncertain(capture.id)
  const result=rows[0],status=result?.status?.code
  if(Number.isInteger(status)&&status!==0&&!result.mediaItem){save(key,{version:1,captureId:capture.id,capturedAt:capture.capturedAt,state:'failed'});return {status:'failed',captureId:capture.id,message:'O Google não criou esta foto. O arquivo local foi preservado.'}}
  if(status!==undefined&&status!==0)return uncertain(capture.id)
  const id=result?.mediaItem?.id;if(!safeId(id))return uncertain(capture.id)
  try {save(key,{version:1,captureId:capture.id,capturedAt:capture.capturedAt,state:'known',mediaItemId:id})}catch{return uncertain(capture.id)}
  return verify(capture,sub,key,id)
}
// Call ONLY after affirmative personal-use disclosure for this photo and a tap on the chosen capture.
// Profile names are layout presets, not evidence of personal/enterprise purpose. Never call from a timer.
export function uploadPersonalPhoto(capture:PersonalCapture):Promise<PhotoUploadResult> {
  try {if(!capture||!PROFILE_IDS.includes(capture.profile as typeof PROFILE_IDS[number])||!/^momentra-[A-Za-z0-9_-]{1,110}$/.test(capture.id)||!Number.isFinite(capture.capturedAt)||capture.capturedAt<=0||capture.capturedAt>Date.now()+300000)throw failure()
    const expected=FileManager.documentsDirectory.replace(/\/$/,'')+'/Momentra/'+capture.id+'.jpg';if(capture.file!==expected)throw failure()
    const sub=account(),key=journalKey(capture,sub),existing=pending.get(key);if(existing)return existing
    const promise=perform({...capture},sub,key).finally(()=>pending.delete(key));pending.set(key,promise);return promise
  }catch{return Promise.reject(new Error('Selecione uma foto pessoal JPEG do Momentra e conecte o Google Fotos.'))}
}


export type CloudRole = 'original'|'final'
export type CloudManifest = { ownerSub:string;captureId:string;capturedAt:number;roles:Array<{role:CloudRole;path:string;size:number;sha256:string;mediaItemId:string}> }
export function getCurrentPhotosOwner():string|null {try{return account()}catch{return null}}
const cloudPending=new Map<string,Promise<{status:'ready'|'pending';manifest?:CloudManifest;message:string}>>()
const retained=()=>({status:'pending' as const,message:'A cópia completa ainda não foi confirmada. Original e foto final permanecem neste aparelho.'})
function capturePaths(id:string) {const root=FileManager.documentsDirectory.replace(/\/$/,'')+'/Momentra/';return {original:root+id+'-original.jpg',final:root+id+'.jpg'}}
function validCapture(capture:PersonalCapture):boolean {return !!capture&&PROFILE_IDS.includes(capture.profile as typeof PROFILE_IDS[number])&&/^momentra-[A-Za-z0-9_-]{1,110}$/.test(capture.id)&&Number.isFinite(capture.capturedAt)&&capture.capturedAt>0&&capture.capturedAt<=Date.now()+300000}
async function fingerprint(path:string):Promise<{size:number;sha256:string}> {
  if(await FileManager.isLink(FileManager.documentsDirectory.replace(/\/$/,'')+'/Momentra'))throw failure()
  const stat=await FileManager.stat(path)
  if(stat.type!=='file'||!Number.isInteger(stat.size)||stat.size<4||stat.size>MAX_FILE||await FileManager.isLink(path))throw failure()
  const data=await FileManager.readAsData(path),sig=data.slice(0,3).toUint8Array()
  if(data.size!==stat.size||!sig||sig[0]!==255||sig[1]!==216||sig[2]!==255)throw failure()
  const sha256=Crypto.sha256(data).toHexString().toLowerCase();if(!/^[a-f0-9]{64}$/.test(sha256))throw failure()
  return {size:data.size,sha256}
}
// Caller must obtain explicit consent for BOTH personal images. This never deletes local data.
export function prepareCloudUpload(capture:PersonalCapture&{original:string}):Promise<{status:'ready'|'pending';manifest?:CloudManifest;message:string}> {
  try {
    if(!validCapture(capture))throw failure()
    const paths=capturePaths(capture.id)
    if(capture.file!==paths.final||capture.original!==paths.original||capture.file===capture.original)throw failure()
    const ownerSub=account(),lock=ownerSub+'.'+capture.id,existing=cloudPending.get(lock);if(existing)return existing
    const snapshot={...capture}
    const task=(async()=>{
      try {
        // Freeze both byte identities before ANY transfer; caller will rehash again before deletion.
        const original=await fingerprint(snapshot.original),final=await fingerprint(snapshot.file)
        if(account()!==ownerSub)throw failure()
        const result=await uploadPersonalPhoto(snapshot)
        if(result.status!=='uploaded'||!result.mediaItemId||account()!==ownerSub)return retained()
        const key=journalKey(snapshot,ownerSub)+'.original',originalCapture={...snapshot,file:snapshot.original}
        let op=pending.get(key)
        if(!op){op=perform(originalCapture,ownerSub,key,snapshot.id+'-original.jpg').finally(()=>pending.delete(key));pending.set(key,op)}
        const orig=await op
        if(orig.status!=='uploaded'||!orig.mediaItemId||account()!==ownerSub||orig.mediaItemId===result.mediaItemId)return retained()
        const manifest:CloudManifest={ownerSub,captureId:snapshot.id,capturedAt:snapshot.capturedAt,roles:[
          {role:'original',path:snapshot.original,...original,mediaItemId:orig.mediaItemId},
          {role:'final',path:snapshot.file,...final,mediaItemId:result.mediaItemId},
        ]}
        return {status:'ready' as const,manifest,message:'Dois itens encontrados no Google Fotos. A equivalência dos arquivos ainda precisa ser verificada.'}
      }catch{return retained()}
    })().finally(()=>cloudPending.delete(lock))
    cloudPending.set(lock,task);return task
  }catch{return Promise.resolve(retained())}
}
function validManifest(m:CloudManifest):boolean {
  if(!m||typeof m.ownerSub!=='string'||!m.ownerSub||!/^momentra-[A-Za-z0-9_-]{1,110}$/.test(m.captureId)||!Number.isFinite(m.capturedAt)||m.capturedAt<=0||!Array.isArray(m.roles)||m.roles.length!==2)return false
  const paths=capturePaths(m.captureId)
  return new Set(m.roles.map(r=>r.role)).size===2&&m.roles.every(r=>(r.role==='original'||r.role==='final')&&r.path===paths[r.role]&&Number.isInteger(r.size)&&r.size>=4&&r.size<=MAX_FILE&&/^[a-f0-9]{64}$/.test(r.sha256)&&safeId(r.mediaItemId))&&m.roles[0].mediaItemId!==m.roles[1].mediaItemId
}
// A fresh Library API URL is a short-lived capability. Never expose/persist it or send bearer tokens to it.
export async function downloadVerifiedRole(manifest:CloudManifest,role:CloudRole):Promise<{status:'bytes-verified'|'retention-pending';checkedAt?:number}> {
  const retained={status:'retention-pending' as const}
  let timer:ReturnType<typeof setTimeout>|undefined
  let downloadController:AbortController|undefined
  try {
    if(!validManifest(manifest)||account()!==manifest.ownerSub)return retained
    const entry=manifest.roles.find(r=>r.role===role);if(!entry)return retained
    const sub=manifest.ownerSub,expected={...entry}
    const meta=await request(BASE+'/mediaItems/'+encodeURIComponent(expected.mediaItemId),sub,{},32768)
    if(!meta.ok)return retained
    const raw=parse(meta.text),base=safeURL(raw?.baseUrl,'image')
    if(raw?.id!==expected.mediaItemId||raw.mimeType!=='image/jpeg'||!base)return retained
    const url=new URL(base);if(url.search||url.hash)return retained
    const controller=new AbortController();downloadController=controller;timer=setTimeout(()=>controller.abort(),20000)
    const response=await fetch(base+'=d',{method:'GET',handleRedirect:async()=>null,timeout:20,signal:controller.signal})
    if(!response.ok||response.status!==200||account()!==sub)return retained
    const type=(response.headers.get('Content-Type')??'').split(';')[0].trim().toLowerCase()
    if(type!=='image/jpeg'&&type!=='image/jpg'&&type!=='application/octet-stream')return retained
    const declared=response.headers.get('Content-Length');if(declared!==null&&Number(declared)!==expected.size)return retained
    const reader=response.body?.getReader();if(!reader)return retained
    let size=0;const chunks:Uint8Array[]=[]
    try {while(true){const next=await reader.read();if(next.done)break;size+=next.value.byteLength;if(size>expected.size||size>MAX_FILE){await reader.cancel();return retained}chunks.push(next.value)}}finally{reader.releaseLock()}
    if(size!==expected.size||account()!==sub)return retained
    const bytes=new Uint8Array(size);let offset=0;for(const chunk of chunks){bytes.set(chunk,offset);offset+=chunk.byteLength}
    const data=Data.fromUint8Array(bytes);if(!data||Crypto.sha256(data).toHexString().toLowerCase()!==expected.sha256)return retained
    if(account()!==sub)return retained
    return {status:'bytes-verified',checkedAt:Date.now()}
  }catch{return retained}finally{if(timer!==undefined)clearTimeout(timer);downloadController?.abort()}
}

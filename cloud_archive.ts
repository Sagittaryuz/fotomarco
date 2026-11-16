// Explicit cloud archival only. Upload/verification and deletion are separate fail-closed stages.
// UI must obtain per-capture personal-use + deletion consent before invoking this module.
import { prepareCloudUpload, downloadVerifiedRole, getCurrentPhotosOwner } from './google_photos'
import type { CloudManifest } from './google_photos'
import { PROFILE_IDS } from './core'
export type CloudCapture = { id:string; original:string; file:string; capturedAt:number; profile:string; storageIntent?:string; saved:boolean; handoffKey?:string }
export type CloudArchiveState = { status:'pending'|'cloud-only'|'partial'; captureId:string; ownerSub?:string; originalMediaItemId?:string; finalMediaItemId?:string; message:string }
type Role='original'|'final'
type Receipt={version:1;manifest:CloudManifest;verifiedAt:number;phase:'removing'|'complete';removed:Role[]}
const inflight=new Map<string,Promise<CloudArchiveState>>()
const roles:Role[]=['original','final'],MAX=20*1024*1024
const idOK=(v:any):v is string=>typeof v==='string'&&/^momentra-[A-Za-z0-9_-]{1,110}$/.test(v)
const mediaOK=(v:any):v is string=>typeof v==='string'&&/^[A-Za-z0-9_-]{1,512}$/.test(v)
const root=()=>FileManager.documentsDirectory.replace(/\/$/,'')+'/Momentra'
const key=(id:string)=>'momentra.cloud.archive.v1.'+id
const fail=()=>new Error('Cloud archival validation failed')
function paths(id:string){return {original:root()+'/'+id+'-original.jpg',final:root()+'/'+id+'.jpg'}}
function validateCapture(c:CloudCapture):void {
  if(!c||!idOK(c.id)||c.storageIntent!=='cloud'||c.saved!==false||c.handoffKey||!PROFILE_IDS.includes(c.profile as typeof PROFILE_IDS[number])||!Number.isFinite(c.capturedAt)||c.capturedAt<=0||c.capturedAt>Date.now()+300000)throw fail()
  const p=paths(c.id);if(c.original!==p.original||c.file!==p.final||c.file===c.original)throw fail()
}
function manifest(value:any,id:string):CloudManifest {
  if(!value||value.captureId!==id||!idOK(id)||typeof value.ownerSub!=='string'||!value.ownerSub||value.ownerSub.length>255||!Number.isFinite(value.capturedAt)||value.capturedAt<=0||!Array.isArray(value.roles)||value.roles.length!==2)throw fail()
  const p=paths(id),selected=roles.map(role=>{const matches=value.roles.filter((v:any)=>v?.role===role);if(matches.length!==1)throw fail();const r=matches[0]
    if(r.path!==p[role]||!Number.isInteger(r.size)||r.size<4||r.size>MAX||typeof r.sha256!=='string'||!/^[a-fA-F0-9]{64}$/.test(r.sha256)||!mediaOK(r.mediaItemId))throw fail()
    return {role,path:r.path,size:r.size,sha256:r.sha256.toLowerCase(),mediaItemId:r.mediaItemId}
  })
  // Distinct uploaded objects are required even if source/final bytes happen to match.
  if(selected[0].mediaItemId===selected[1].mediaItemId)throw fail()
  return {ownerSub:value.ownerSub,captureId:id,capturedAt:value.capturedAt,roles:selected}
}
function read(id:string):Receipt|null {
  const raw=Storage.get<any>(key(id));if(raw==null)return null
  if(raw.version!==1||!['removing','complete'].includes(raw.phase)||!Number.isFinite(raw.verifiedAt)||raw.verifiedAt<=0||!Array.isArray(raw.removed)||raw.removed.some((r:any)=>!roles.includes(r))||new Set(raw.removed).size!==raw.removed.length)throw fail()
  const m=manifest(raw.manifest,id);if(raw.phase==='complete'&&raw.removed.length!==2)throw fail()
  return {version:1,manifest:m,verifiedAt:raw.verifiedAt,phase:raw.phase,removed:[...raw.removed]}
}
function write(r:Receipt):void {
  if(!Storage.set(key(r.manifest.captureId),r))throw fail()
  // A successful return alone must not authorize removal if the receipt cannot be read back.
  const check=read(r.manifest.captureId);if(!check||JSON.stringify(check)!==JSON.stringify(r))throw fail()
}
function result(id:string,status:CloudArchiveState['status'],message:string,r?:Receipt|null):CloudArchiveState {
  const out:CloudArchiveState={status,captureId:id,message}
  if(r){out.ownerSub=r.manifest.ownerSub;out.originalMediaItemId=r.manifest.roles.find(v=>v.role==='original')!.mediaItemId;out.finalMediaItemId=r.manifest.roles.find(v=>v.role==='final')!.mediaItemId}return out
}
// Local-only receipt lookup. Does not authorize deletion or expose URL/token data.
export function getCloudArchiveState(captureId:string):CloudArchiveState {
  if(!idOK(captureId))return result('', 'pending','Registro de arquivamento indisponível.')
  try {const r=read(captureId);if(!r){const p=paths(captureId);const present=FileManager.existsSync(p.original)&&FileManager.existsSync(p.final);return result(captureId,'pending',present?'Arquivos locais presentes. Arquivamento em nuvem ainda não concluído.':'Arquivamento não confirmado e arquivo local indisponível. Nenhuma cópia remota foi presumida.')}
    const p=paths(captureId),gone=!FileManager.existsSync(p.original)&&!FileManager.existsSync(p.final)
    if(r.phase==='complete'&&gone)return result(captureId,'cloud-only','Original e foto final foram verificados na nuvem; as duas cópias locais desta captura foram removidas.',r)
    return result(captureId,'partial','Há uma etapa de remoção local pendente ou parcial. Retome a verificação; nenhum arquivo será reenviado.',r)
  }catch{return result(captureId,'pending','Não foi possível ler o registro de arquivamento. Não remova arquivos manualmente.')}
}
function sameOwner(sub:string){if(getCurrentPhotosOwner()!==sub)throw fail()}
async function parentSafe(){const directory=root();if(await FileManager.isLink(directory))throw fail();const stat=await FileManager.stat(directory);if(stat.type!=='directory')throw fail()}
async function inspect(path:string,expected?:CloudManifest['roles'][number]):Promise<boolean> {
  if(!await FileManager.exists(path))return false
  if(await FileManager.isLink(path))throw fail()
  const stat=await FileManager.stat(path);if(stat.type!=='file'||!Number.isInteger(stat.size)||stat.size<4||stat.size>MAX)throw fail()
  const data=await FileManager.readAsData(path),sig=data.slice(0,3).toUint8Array()
  if(data.size!==stat.size||!sig||sig[0]!==255||sig[1]!==216||sig[2]!==255)throw fail()
  const hash=Crypto.sha256(data).toHexString().toLowerCase();if(!/^[a-f0-9]{64}$/.test(hash))throw fail()
  if(expected&&(expected.size!==data.size||expected.sha256!==hash))throw fail()
  return true
}
async function run(capture:CloudCapture):Promise<CloudArchiveState> {
  let receipt:Receipt|null=null,removedThisRun=false
  try {
    validateCapture(capture);receipt=read(capture.id)
    const owner=getCurrentPhotosOwner();if(!owner)throw fail()
    if(receipt&&(receipt.manifest.ownerSub!==owner||receipt.manifest.capturedAt!==capture.capturedAt))throw fail()
    await parentSafe()
    let m:CloudManifest
    if(receipt)m=receipt.manifest
    else {
      // Never initiate a new upload from a missing file or unsafe local path.
      if(!await inspect(capture.original)||!await inspect(capture.file))throw fail()
      sameOwner(owner)
      const prepared=await prepareCloudUpload(capture);sameOwner(owner)
      if(prepared.status!=='ready'||!prepared.manifest)return result(capture.id,'pending','Envio ou verificação em nuvem pendente. Os arquivos locais foram preservados.')
      m=manifest(prepared.manifest,capture.id);if(m.ownerSub!==owner||m.capturedAt!==capture.capturedAt)throw fail()
    }
    // BOTH distinct objects must pass a full downloaded-byte comparison before ANY removal.
    for(const role of roles){sameOwner(owner);const verified=await downloadVerifiedRole(m,role);sameOwner(owner);if(verified.status!=='bytes-verified')throw fail()}
    await parentSafe();sameOwner(owner)
    const missing:Role[]=[]
    for(const r of m.roles){const present=await inspect(r.path,r);if(!present){if(!receipt)throw fail();missing.push(r.role)}}
    sameOwner(owner)
    const allowMissing=receipt!==null
    const intent:Receipt={version:1,manifest:m,verifiedAt:Date.now(),phase:'removing',removed:missing}
    write(intent);receipt=intent // A verified, durable receipt exists before the first remove.
    // Recheck BOTH files after the durable write, before making either deletion.
    await parentSafe();sameOwner(owner)
    for(const r of m.roles){if(!await inspect(r.path,r)&&!allowMissing)throw fail()}
    sameOwner(owner)
    for(const r of m.roles){
      sameOwner(owner);await parentSafe();sameOwner(owner)
      const present=await inspect(r.path,r);sameOwner(owner)
      if(present){await FileManager.remove(r.path);removedThisRun=true;if(await FileManager.exists(r.path))throw fail()}
      if(!receipt.removed.includes(r.role)){receipt={...receipt,removed:[...receipt.removed,r.role]};write(receipt)}
    }
    sameOwner(owner)
    if(await FileManager.exists(capture.original)||await FileManager.exists(capture.file))throw fail()
    receipt={...receipt,phase:'complete',removed:[...roles]};write(receipt)
    return result(capture.id,'cloud-only','Original e foto final foram verificados na nuvem; as duas cópias locais desta captura foram removidas.',receipt)
  }catch{
    if(receipt||removedThisRun)return result(capture.id,'partial','O arquivamento possui uma etapa local pendente ou parcial. Os IDs verificados foram preservados; retome a verificação sem reenviar arquivos.',receipt)
    return result(idOK(capture?.id)?capture.id:'','pending','Arquivamento pendente. Nenhum arquivo local foi removido nesta tentativa.')
  }
}
// Manual call after UI consent only. Deduplicates taps; receipt retries verify IDs, never re-upload.
export function archiveCloudCapture(capture:CloudCapture):Promise<CloudArchiveState> {
  const id=capture?.id;if(!idOK(id))return Promise.resolve(result('','pending','Captura inválida; nenhum arquivo foi removido.'))
  const previous=inflight.get(id);if(previous)return previous
  const promise=run({...capture}).finally(()=>inflight.delete(id));inflight.set(id,promise);return promise
}

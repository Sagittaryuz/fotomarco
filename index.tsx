import {
  Button, CaptureVideoPreviewView, GeometryReader, HStack, VStack, ZStack, Text, Image,
  Navigation, NavigationStack, Script, Path, Spacer, ScrollView,
  useEffect, useRef, useState,
} from "scripting"
import type { CameraControlParameter } from "scripting"
import { VERSION, PROFILE_IDS, Settings, CaptureRecord, Fix, normalizeSettings, validFix, coordinates, cleanText, within } from "./core"
import { enrich, folder, persistRecord, renderStamped } from "./services"

type Camera = { device: AVCaptureDevice; session: AVCaptureSession; output: AVCapturePhotoOutput }
let ownedSession: AVCaptureSession | null = null
let pending: Promise<void> | null = null
let startPending: Promise<void> | null = null
let incoming: CameraControlParameter[] = Script.cameraControlParameter ? [Script.cameraControlParameter] : []
let receive: (batch: CameraControlParameter | null) => void = batch => { if (batch) incoming.push(batch) }
let closing = false
const unsubscribe = Script.onResume(event => { if (!closing) receive(event.cameraControlParameter) })
const SETTINGS = "momentra.settings.v2", HISTORY = "momentra.history.v2"

function CameraPage() {
  const dismiss = Navigation.useDismiss()
  const [camera, setCamera] = useState<Camera | null>(null)
  const handoffs = useRef<CameraControlParameter[]>(incoming); incoming = []
  const resumeRequested = useRef(false)
  const startAborted = useRef(false)
  const cameraRef = useRef<Camera | null>(null)
  const alive = useRef(true), locked = useRef(false), locating = useRef(false)
  const [busy, setBusy] = useState(false)
  const [status, setStatus] = useState("Iniciando câmera…")
  const [settings, setSettings] = useState<Settings>(() => normalizeSettings(Storage.get(SETTINGS)))
  const settingsRef = useRef(settings)
  const [fix, setFix] = useState<Fix | null>(null)
  const fixRef = useRef<Fix | null>(null)
  const [last, setLast] = useState<CaptureRecord | null>(null)
  const lastRef = useRef<CaptureRecord | null>(null)
  const [preview, setPreview] = useState(false)
  const [previewImage, setPreviewImage] = useState<UIImage | null>(null)
  const [torch, setTorch] = useState(false)
  const say = (message: string) => { if (alive.current) setStatus(message) }

  function update(next: Settings) {
    settingsRef.current = next; setSettings(next)
    if (!Storage.set(SETTINGS,next)) say("Preferências não foram persistidas; tente novamente")
  }
  function remember(record: CaptureRecord) {
    if (record.handoffKey && Storage.contains(record.handoffKey)) Storage.set(record.handoffKey,record)
    lastRef.current = record
    if (alive.current) { setLast(record); setPreviewImage(UIImage.fromFile(record.file)) }
    const history = Storage.get<CaptureRecord[]>(HISTORY)
    Storage.set(HISTORY,[record,...(Array.isArray(history) ? history.filter(x => x && x.id !== record.id) : [])].slice(0,50))
  }
  async function run(action: () => Promise<void>) {
    if (locked.current || closing || !alive.current) return
    locked.current = true; setBusy(true)
    const task = (async () => {
      try { await action() } catch (error) { say("Não concluído: "+String(error)) }
      finally { locked.current = false; if (alive.current) setBusy(false) }
    })()
    pending = task
    await task
    if (pending === task) pending = null
    if (handoffs.current.length && !closing && alive.current) void processHandoffs()
    else if (resumeRequested.current && !closing && alive.current) { resumeRequested.current = false; void run(restoreCamera) }
  }
  async function restoreCamera() {
    setPreview(false)
    if (cameraRef.current) { await cameraRef.current.session.startRunning(); say("Câmera pronta") }
    else {
      if (ownedSession && startPending) await startPending
      if (!cameraRef.current && !closing) { startAborted.current = false; startPending = start(); await startPending }
    }
  }
  async function closeCamera() {
    if (locked.current || closing) return
    closing = true; setBusy(true); unsubscribe()
    try {
      if (ownedSession) await ownedSession.stopRunning()
      await startPending
    } catch (_) { /* final cleanup still disposes the session */ }
    finally { dismiss() }
  }
  async function processHandoffs() {
    await run(async () => {
      let processed = 0, duplicate = 0, videos = 0, failed = 0
      while (handoffs.current.length) {
        const batch = handoffs.current.shift()!
        for (const asset of batch.assets) {
          if (asset.type !== "photo") { videos++; continue }
          try {
          const key = "momentra.handoff."+batch.captureId+"."+asset.id
          const previous = Storage.get<CaptureRecord>(key)
          if (previous && await FileManager.exists(previous.file)) { remember(previous); duplicate++; continue }
          const image = UIImage.fromFile(asset.filePath)
          if (!image) { say("Foto recebida não pôde ser decodificada; original mantido pelo Scripting"); continue }
          const capturedAt = asset.capturedAt
          if (!Number.isFinite(capturedAt)) throw new Error("Captura recebida sem data válida; original preservado")
          const id = "momentra-"+capturedAt+"-"+Math.random().toString(36).slice(2,7)
          await FileManager.createDirectory(folder,true)
          const original = Path.join(folder,id+"-original.jpg")
          await FileManager.copyFile(asset.filePath,original)
          const options = JSON.parse(JSON.stringify(settingsRef.current)) as Settings
          const record: CaptureRecord = {handoffKey:key,id,original,file:original,capturedAt,profile:options.profile,stamped:false,saved:false,fix:null,address:"",warnings:[]}
          if (options.gps) record.warnings.push("Captura recebida: GPS do disparo não fornecido; localização atual não foi usada")
          remember(record); await persistRecord(record)
          if (options.stamp) {
            try { record.file = await renderStamped(image,record,options,null); record.stamped = true }
            catch (error) { record.warnings.push("Carimbo falhou; original preservado: "+String(error)) }
          }
          remember(record); await persistRecord(record)
          Storage.set(key,record); processed++
          } catch (_) { failed++ /* Original remains in Scripting Captured Files; continue other assets. */ }
        }
      }
      setPreview(true)
      say(`${processed} foto(s) recebida(s) preparada(s), ${duplicate} já processada(s). Veja Recentes para salvar cada uma.`+(failed ? ` ${failed} foto(s) não processada(s); originais preservados nos Arquivos Capturados do Scripting.` : "")+(videos ? ` ${videos} vídeo(s) mantido(s) nos Arquivos Capturados do Scripting; Momentra carimba fotos.` : ""))
    })
  }
  async function locate() {
    if (locating.current || !settingsRef.current.gps) return
    locating.current = true
    try {
      await Location.setAccuracy("best")
      const result = await within(Location.requestCurrent({forceRequest:true}),10000,null)
      const current = validFix(result,Date.now())
      if (alive.current && settingsRef.current.gps) {
        fixRef.current = current; setFix(current)
        say(current ? "GPS atualizado" : "GPS indisponível. Você ainda pode fotografar.")
      }
    } catch (_) { say("Sem acesso ao GPS. A câmera continua disponível.") }
    finally { locating.current = false }
  }
  async function start() {
    try {
      const device = AVCaptureDevice.default("video")
      if (!device) throw new Error("Câmera indisponível neste aparelho")
      const session = new AVCaptureSession(); ownedSession = session
      const output = new AVCapturePhotoOutput(), input = new AVCaptureDeviceInput(device)
      session.configure(() => {
        session.sessionPreset = "photo"
        if (!session.canAddInput(input) || !session.canAddOutput(output)) throw new Error("Não foi possível configurar a câmera")
        session.addInput(input); session.addOutput(output)
      })
      await session.startRunning()
      if (!alive.current || closing || startAborted.current) {
        await session.stopRunning(); session.dispose()
        if (ownedSession === session) ownedSession = null
        return
      }
      const state = {device,session,output}; cameraRef.current = state; setCamera(state)
      say("Pronta para fotografar")
      if (settingsRef.current.gps) void locate()
    } catch (error) {
      const failed = ownedSession; ownedSession = null
      if (failed) { try { await failed.stopRunning() } finally { failed.dispose() } }
      say("Câmera: "+String(error)+". Confira a permissão do Scripting nos Ajustes e reabra.")
    }
  }
  async function capture() {
    if (!cameraRef.current) return
    setPreview(false)
    await run(async () => {
      // Freeze profile, time and GPS at shutter. Never stamp a later GPS fix as capture location.
      const options = JSON.parse(JSON.stringify(settingsRef.current)) as Settings
      const capturedAt = Date.now(), id = "momentra-"+capturedAt+"-"+Math.random().toString(36).slice(2,7)
      const currentFix = options.gps ? validFix(fixRef.current,capturedAt) : null
      await FileManager.createDirectory(folder,true)
      const original = Path.join(folder,id+"-original.jpg")
      say("Capturando…")
      const result = await cameraRef.current!.output.capturePhoto({codec:"jpeg",photoFile:original})
      const record: CaptureRecord = {id,original,file:original,capturedAt,profile:options.profile,stamped:false,saved:false,fix:currentFix,address:"",warnings:[]}
      // Record original first. Rendering/network failures must never discard a successful capture.
      remember(record); await persistRecord(record)
      if (options.gps && !currentFix) record.warnings.push("GPS indisponível no disparo")
      if (options.stamp) {
        say("Aplicando carimbo…")
        try {
          const extra = await enrich(currentFix,options)
          record.address = extra.address; record.warnings.push(...extra.warnings)
          record.file = await renderStamped(result.image,record,options,extra.map)
          record.stamped = true
        } catch (error) { record.warnings.push("Carimbo falhou; original preservado: "+String(error)) }
      }
      remember(record); await persistRecord(record)
      say((record.stamped ? "Foto com carimbo pronta" : options.stamp ? "Original preservado, sem carimbo" : "Foto original pronta")+". Toque em Salvar."+(record.warnings.length ? " "+record.warnings.join(". ") : ""))
      if (options.gps) void locate()
    })
  }
  async function save() {
    await run(async () => {
      const record = lastRef.current
      if (!record || record.saved) return
      say("Salvando no Fotos…")
      const ok = await Photos.savePhoto(record.file,{fileName:record.id+".jpg"})
      if (!ok) { say("Fotos não confirmou o salvamento. Sua foto continua guardada no Momentra."); return }
      // Persist successful save immediately so repeated taps do not duplicate it.
      const saved = {...record,saved:true}; remember(saved)
      await persistRecord(saved); say("Salva no Fotos")
    })
  }
  async function editProfile() {
    await run(async () => {
      const current = settingsRef.current, id = current.profile, profile = current.profiles[id]
      const choice = await Dialog.actionSheet({title:"Padrão "+id,actions:[{label:"Editar título"},{label:"Editar observação / serviço"},{label:"Escolher logotipo nos Arquivos"},{label:"Remover logotipo"},{label:"Posição: "+(current.position === "bottom" ? "rodapé" : "topo")},{label:"Tamanho: "+(current.size === "regular" ? "normal" : "compacto")}],cancelButton:true})
      if (choice === null) return
      const next = JSON.parse(JSON.stringify(current)) as Settings
      if (choice === 0 || choice === 1) {
        const field = choice === 0 ? "title" : "note"
        const value = await Dialog.prompt({title:choice === 0 ? "Título do carimbo" : "Observação do serviço",defaultValue:profile[field],confirmLabel:"Salvar",cancelLabel:"Cancelar"})
        if (value === null) return
        next.profiles[id][field] = cleanText(value,choice === 0 ? 40 : 96)
        if (choice === 0 && !next.profiles[id].title) { say("O título não pode ficar vazio"); return }
      } else if (choice === 2) {
        const files = await DocumentPicker.pickFiles({types:["public.image"],allowsMultipleSelection:false})
        if (!files.length) return
        const logo = UIImage.fromFile(files[0]); if (!logo) throw new Error("O arquivo não é uma imagem compatível")
        const thumb = logo.preparingThumbnail({width:512,height:512}) ?? logo
        const data = await thumb.toPNGData(); if (!data) throw new Error("Não foi possível preparar o logotipo")
        await FileManager.createDirectory(folder,true)
        const path = Path.join(folder,"logo-"+id+"-"+Date.now()+".png")
        await FileManager.writeAsData(path,data); next.profiles[id].logoPath = path
      } else if (choice === 3) next.profiles[id].logoPath = null
      else if (choice === 4) next.position = current.position === "bottom" ? "top" : "bottom"
      else if (choice === 5) next.size = current.size === "regular" ? "compact" : "regular"
      update(next); say("Padrão salvo para as próximas fotos")
    })
  }
  async function gpsMenu() {
    await run(async () => {
      const s = settingsRef.current
      const choice = await Dialog.actionSheet({title:"Localização",message:"GPS é capturado no aparelho. Endereço e mapa usam os serviços Apple quando o GPS está ligado. A foto nunca é enviada.",actions:[{label:s.gps ? "Desligar GPS" : "Ativar GPS"},{label:"Atualizar GPS agora"},{label:s.map ? "Desligar mapa de satélite" : "Ativar mapa de satélite"}],cancelButton:true})
      if (choice === null) return
      if (choice === 0) {
        update({...s,gps:!s.gps}); fixRef.current = null; setFix(null)
        if (!s.gps) await locate(); else say("GPS desativado")
      } else if (choice === 1) {
        if (!s.gps) update({...s,gps:true})
        await locate()
      } else {
        update({...s,map:!s.map,gps:!s.map ? true : s.gps})
        if (!s.map && !s.gps) await locate()
        else say(s.map ? "Mapa desativado" : "Mapa será incluído quando disponível")
      }
    })
  }
  async function history() {
    await run(async () => {
      const rows = Storage.get<CaptureRecord[]>(HISTORY)
      if (!Array.isArray(rows) || !rows.length) { say("Ainda não há fotos no Momentra"); return }
      const choice = await Dialog.actionSheet({title:"Fotos recentes",actions:rows.slice(0,12).map(x=>({label:new Date(x.capturedAt).toLocaleString("pt-BR")+" · "+x.profile+(x.saved ? " ✓" : "")})),cancelButton:true})
      if (choice === null) return
      const record = rows[choice]
      if (!(await FileManager.exists(record.file))) { say("Arquivo não encontrado no armazenamento local"); return }
      remember(record); setPreview(true); say(record.saved ? "Esta foto já foi salva no Fotos" : "Foto recuperada. Toque em Salvar.")
    })
  }
  async function exportFiles() {
    await run(async () => {
      const record = lastRef.current; if (!record) return
      const choice = await Dialog.actionSheet({title:"Exportar para Arquivos",actions:[{label:"Foto final"},{label:"Original sem carimbo"},{label:"Registro JSON de captura"}],cancelButton:true})
      if (choice === null) return
      const path = choice === 0 ? record.file : choice === 1 ? record.original : Path.join(folder,record.id+".json")
      const data = await FileManager.readAsData(path)
      const result = await DocumentPicker.exportFiles({files:[{data,name:Path.basename(path)}]})
      say(result.length ? "Arquivo exportado" : "Exportação cancelada; foto preservada")
    })
  }
  useEffect(() => {
    alive.current = true
    receive = batch => {
      if (!alive.current || closing) return
      if (batch) {
        handoffs.current.push(batch)
        if (!cameraRef.current && ownedSession) {
          startAborted.current = true
          void ownedSession.stopRunning().catch(()=>{})
        }
        if (!locked.current) void processHandoffs()
      }
      else if (Script.env === "camera_control") { resumeRequested.current = true; if (!locked.current) { resumeRequested.current = false; void run(restoreCamera) } }
    }
    if (handoffs.current.length) void processHandoffs()
    else startPending = start()
    const history = Storage.get<CaptureRecord[]>(HISTORY)
    const first = Array.isArray(history) ? history[0] : null
    if (first && FileManager.existsSync(first.file)) remember(first)
    return () => { alive.current = false; receive = () => {} }
  },[])

  function SideButton(props: {title: string; symbol: string; action: () => void; disabled?: boolean}) {
    return <Button title={props.title} systemImage={props.symbol} action={props.action} disabled={busy || props.disabled}
      font="caption" foregroundStyle="white" padding={10} glassEffect accessibilityLabel={props.title} />
  }
  return <NavigationStack onCameraCaptureEvent={{isEnabled:!!camera && !closing,primaryAction:event=>{if(event.phase === "ended") void capture()}}}>
    <GeometryReader>{geometry => {
      const width = geometry.size.width, height = geometry.size.height
      return <VStack spacing={10} background="#071017" foregroundStyle="white" padding={12} frame={{width,height}}>
        <HStack>
          <VStack alignment="leading" spacing={2}>
            <Text font="headline" foregroundStyle="#6FDED2">MOMENTRA</Text>
            <Text font="caption2" foregroundStyle="#B6C7D1">CAPTURE. LOCATE. REMEMBER.</Text>
          </VStack>
          <Spacer />
          <Button title="Fechar" systemImage="xmark" disabled={busy} action={()=>{void closeCamera()}} accessibilityLabel="Fechar câmera" />
        </HStack>
        <ZStack frame={{maxWidth:"infinity",maxHeight:"infinity"}}>
          {camera ? <CaptureVideoPreviewView session={camera.session} videoDevice={camera.device} videoGravity="resizeAspect" frame={{maxWidth:"infinity",maxHeight:"infinity"}} cornerRadius={20} masksToBounds /> : <Text font="callout">{status}</Text>}
          {preview && previewImage ? <Image image={previewImage} resizable scaleToFit background="#071017" frame={{width:Math.min(width*0.58,280),height:Math.min(height*0.32,280)}} cornerRadius={12} /> : null}
          <HStack alignment="center">
            <VStack spacing={16}>
              <SideButton title={settings.profile} symbol="square.stack" action={()=>update({...settingsRef.current,profile:PROFILE_IDS[(PROFILE_IDS.indexOf(settingsRef.current.profile)+1)%PROFILE_IDS.length]})} />
              <SideButton title="Padrão" symbol="slider.horizontal.3" action={()=>{void editProfile()}} />
              <SideButton title={settings.stamp ? "Carimbo ✓" : "Sem carimbo"} symbol="text.viewfinder" action={()=>update({...settingsRef.current,stamp:!settingsRef.current.stamp})} />
            </VStack>
            <Spacer />
            <VStack spacing={16}>
              <SideButton title={settings.gps ? "GPS ✓" : "GPS"} symbol="location" action={()=>{void gpsMenu()}} />
              <SideButton title={torch ? "Luz ✓" : "Luz"} symbol="flashlight.on.fill" disabled={!camera?.device.hasTorch} action={()=>{void run(async()=>{await cameraRef.current!.device.setTorchMode(torch ? "off" : "on");setTorch(!torch)})}} />
              <SideButton title="Recentes" symbol="photo.on.rectangle" action={()=>{void history()}} />
            </VStack>
          </HStack>
        </ZStack>
        <HStack>
          <Button title={preview ? "Câmera" : "Prévia"} systemImage={preview ? "camera" : "photo"} disabled={busy || (!preview && !last)} action={()=>{ if (preview && !camera) void run(restoreCamera); else setPreview(!preview) }} />
          <Spacer />
          <Button title={busy ? "Aguarde" : "Fotografar"} systemImage="camera.circle.fill" font="title" foregroundStyle="#6FDED2" disabled={busy || !camera} action={()=>{void capture()}} accessibilityLabel="Fotografar" />
          <Spacer />
          <Button title={last?.saved ? "Salva ✓" : "Salvar"} systemImage="square.and.arrow.down" disabled={!last || busy || last.saved} action={()=>{void save()}} />
        </HStack>
        <ScrollView frame={{height:height < 500 ? 36 : 64}}><Text font="caption" foregroundStyle="#B6C7D1">{status}</Text></ScrollView>
        <HStack>
          <Text font="caption2" foregroundStyle="#8196A3">{settings.gps ? coordinates(validFix(fix,Date.now())) : "GPS desligado"} · v{VERSION}</Text>
          <Spacer />
          <Button title="Exportar" disabled={!last || busy} font="caption" action={()=>{void exportFiles()}} />
        </HStack>
      </VStack>
    }}</GeometryReader>
  </NavigationStack>
}
async function main() {
  try { await Navigation.present({element:<CameraPage />,modalPresentationStyle:"fullScreen"}) }
  finally {
    closing = true; unsubscribe()
    // Wait for in-flight capture/writes before disposing the camera or exiting.
    await pending?.catch(()=>{})
    const old = ownedSession; ownedSession = null
    if (old) { try { await old.stopRunning(); await startPending?.catch(()=>{}) } finally { old.dispose() } }
    Script.exit()
  }
}
void main()

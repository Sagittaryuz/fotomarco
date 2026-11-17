import {
  Button, Toggle, Canvas, CaptureVideoPreviewView, GeometryReader, GlassEffectContainer, Picker, HStack, VStack, ZStack, Text, Image,
  Navigation, NavigationStack, Script, Path, Spacer, ScrollView, ImageRenderer,
  useEffect, useRef, useState,
} from "scripting"
import type { CameraControlParameter } from "scripting"
import { VERSION, PROFILE_IDS, Settings, CaptureRecord, Fix, HeadingSample, normalizeSettings, validFix, coordinates, cleanText, within, nativeSettingsTransfer } from "./core"
import { enrich, folder, persistRecord, renderStamped } from "./services"
import { requestMetForecast, metCoordinateKey, ModelWeather } from "./meteorology"
import { cameraLayout } from "./camera_layout"
import { drawStamp } from "./stamp"
import { beginDiagnostic, recordDiagnostic, recordApiAvailability, buildDiagnosticReport } from "./diagnostics"
import { getGoogleIdentity, loginGoogle, logoutGoogle } from "./google_auth"
import { GooglePhotosPanel } from "./google_photos_ui"
import { getCloudArchiveState } from "./cloud_archive"

type Camera = { device: AVCaptureDevice; session: AVCaptureSession; output: AVCapturePhotoOutput | null; movie: AVCaptureMovieFileOutput | null }
let ownedSession: AVCaptureSession | null = null
let ownedMovie: AVCaptureMovieFileOutput | null = null
let pending: Promise<void> | null = null
let startPending: Promise<void> | null = null
let incoming: CameraControlParameter[] = Script.cameraControlParameter ? [Script.cameraControlParameter] : []
let receive: (batch: CameraControlParameter | null) => void = batch => { if (batch) incoming.push(batch) }
let closing = false
const unsubscribe = Script.onResume(event => { if (!closing) receive(event.cameraControlParameter) })
const SETTINGS = "momentra.settings.v2", HISTORY = "momentra.history.v2"

// Observe only map requests already needed by the camera; no diagnostic requests added.
async function observedEnrich(fix: Fix | null, settings: Settings) {
  const requested = !!fix && settings.gps && settings.map
  if (requested) beginDiagnostic("map")
  try {
    const extra = await enrich(fix,settings)
    if (requested) recordDiagnostic("map",extra.map ? "passed" : "failed",extra.map ? "completed" : "unavailable")
    return extra
  } catch (error) { if (requested) recordDiagnostic("map","failed","operation_failed"); throw error }
}
function DiagnosticReport() {
  const [report,setReport] = useState("")
  return <VStack alignment="leading" spacing={10}>
    <Button title="Exibir diagnóstico local" buttonStyle="bordered" action={()=>setReport(buildDiagnosticReport())} />
    {report ? <Text font="caption" accessibilityIdentifier="momentra.diagnostic-report">{report}</Text> : null}
  </VStack>
}

// Identity only: camera access and local capture never depend on Google consent.
function GoogleAccount() {
  const [account,setAccount] = useState(getGoogleIdentity)
  const [working,setWorking] = useState(false)
  const [message,setMessage] = useState("")
  const active = useRef(true), connecting = useRef(false)
  useEffect(()=>{
    active.current=true
    let timer: ReturnType<typeof setTimeout>
    const refresh=()=>{ if (!active.current) return; setAccount(getGoogleIdentity()); timer=setTimeout(refresh,15000) }
    timer=setTimeout(refresh,15000)
    return ()=>{active.current=false;clearTimeout(timer)}
  },[])
  async function connect() {
    if (connecting.current) return
    connecting.current=true;setWorking(true);setMessage("");beginDiagnostic("oauth")
    try { const next=await loginGoogle(); if (next.status !== "connected" || next.expiresAt <= Date.now()) throw new Error("Login não concluído"); recordDiagnostic("oauth","passed","completed"); if (active.current) {setAccount(next);setMessage("Identidade conectada. Nenhuma foto foi enviada.")} }
    catch { recordDiagnostic("oauth","failed","operation_failed"); if (active.current) setMessage("Login cancelado ou não concluído. A câmera continua disponível; tente novamente.") }
    finally { connecting.current=false;if (active.current) setWorking(false) }
  }
  function disconnect() {
    try { setAccount(logoutGoogle());setMessage("Conta removida deste iPhone. Isso não revoga a permissão na conta Google.") }
    catch { setMessage("Não foi possível desconectar a conta neste iPhone. Tente novamente.") }
  }
  const hasAccount=account.status === "connected" || account.status === "expired"
  const expired=hasAccount && (account.status === "expired" || account.expiresAt <= Date.now())
  return <VStack alignment="leading" spacing={12}>
    <Text font="headline">Conta Google</Text>
    <Text font="caption">Login opcional para identificar sua conta. Não libera Google Fotos nem armazenamento na nuvem.</Text>
    <Text>{hasAccount ? (expired ? "Sessão expirada · " : "Conectado · ")+(account.identity.name || account.identity.email || "Conta Google") : account.status === "unavailable" ? "Estado da conta indisponível neste aparelho" : "Nenhuma conta conectada"}</Text>
    {hasAccount && account.identity.email ? <Text font="caption">{account.identity.email}</Text> : null}
    <Text font="caption">A sessão expira sem renovação automática. Para continuar depois, toque em Reconectar. As credenciais ficam no Chaves deste iPhone.</Text>
    <Button title={working ? "Conectando…" : hasAccount ? "Reconectar ao Google" : "Entrar com Google"} disabled={working} buttonStyle="bordered" action={()=>{void connect()}} />
    {hasAccount ? <Button title="Desconectar deste iPhone" disabled={working} buttonStyle="bordered" action={disconnect} /> : null}
    {message ? <Text font="caption">{message}</Text> : null}
  </VStack>
}

function GooglePhotosPage({capture,onArchived}:{capture:CaptureRecord|null;onArchived?:()=>void}) {
  const dismiss=Navigation.useDismiss()
  return <NavigationStack preferredColorScheme="light"><VStack spacing={0} background="#F2F2F7" foregroundStyle="#17171B">
    <ZStack frame={{height:64}} background="white"><Text font="headline">Google Fotos pessoal</Text><HStack padding={{leading:16,trailing:16}}><Button buttonStyle="plain" accessibilityLabel="Voltar às configurações" action={dismiss} frame={{width:44,height:44}} background="#F2F2F7" cornerRadius={22} masksToBounds><Image systemName="chevron.left" font="title3" frame={{width:44,height:44}} /></Button><Spacer /></HStack></ZStack>
    <ScrollView><VStack padding={18}><GooglePhotosPanel capture={capture} onArchived={onArchived} /></VStack></ScrollView>
  </VStack></NavigationStack>
}

// Uniform 44pt hit target and circular surface; shutter intentionally remains larger.
function circularControl() {
  return {frame:{width:44,height:44},cornerRadius:22,masksToBounds:true,
    glassEffect:{glass:UIGlass.regular().interactive(),shape:{type:"rect" as const,cornerRadius:22}}}
}

function CameraPage() {
  const dismiss = Navigation.useDismiss()
  const [camera, setCamera] = useState<Camera | null>(null)
  const handoffs = useRef<CameraControlParameter[]>(incoming); incoming = []
  const resumeRequested = useRef(false)
  const startAborted = useRef(false)
  const cameraRef = useRef<Camera | null>(null)
  const cameraPosition = useRef<"back" | "front">("back")
  const alive = useRef(true), locked = useRef(false), locating = useRef(false), settingsOpen = useRef(false)
  const [busy, setBusy] = useState(false)
  const [initializing, setInitializing] = useState(true)
  const initializingRef = useRef(true)
  const [showGoogleIntro,setShowGoogleIntro] = useState(()=>!Storage.get("momentra.google.intro.v1"))
  const [status, setStatus] = useState("Iniciando câmera…")
  const [settings, setSettings] = useState<Settings>(() => normalizeSettings(Storage.get(SETTINGS)))
  const settingsRef = useRef(settings)
  const [fix, setFix] = useState<Fix | null>(null)
  const fixRef = useRef<Fix | null>(null)
  const [forecast,setForecast] = useState<{key:string;value:ModelWeather}|null>(null)
  const forecastRef = useRef<{key:string;value:ModelWeather}|null>(null)
  const headingRef = useRef<HeadingSample | null>(null)
  const headingOps = useRef<Promise<void>>(Promise.resolve())
  const [last, setLast] = useState<CaptureRecord | null>(null)
  const lastRef = useRef<CaptureRecord | null>(null)
  const [preview, setPreview] = useState(false)
  const [previewImage, setPreviewImage] = useState<UIImage | null>(null)
  const [liveNow,setLiveNow] = useState(Date.now())
  const [liveAssets,setLiveAssets] = useState<{key:string;address:string;map:UIImage|null;warnings:string[]}|null>(null)
  const liveAssetsRef = useRef<{key:string;address:string;map:UIImage|null;warnings:string[]}|null>(null)
  const logoCache = useRef<{path:string|null;image:UIImage|null}>({path:null,image:null})
  const [torch, setTorch] = useState(false)
  const [flash, setFlash] = useState<"on"|"auto"|"off">("off")
  const flashRef = useRef<"on"|"auto"|"off">("off")
  const [timer, setTimer] = useState<0|3|10>(0)
  const timerRef = useRef<0|3|10>(0)
  const [countdown, setCountdown] = useState(0)
  const countdownRef = useRef(0), cancelCountdown = useRef(false)
  const [mode, setMode] = useState<"video" | "photo">("photo")
  const modeRef = useRef<"video" | "photo">("photo")
  const [recording, setRecording] = useState(false)
  const recordingRef = useRef(false), stopping = useRef(false)
  const [lastVideo, setLastVideo] = useState<{file:string;saved:boolean}|null>(()=>Storage.get("momentra.video.latest"))
  const lastVideoRef = useRef(lastVideo)
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
          if (options.storageMode === "cloud") record.warnings.push("Capturas recebidas do Scripting permanecem locais; o modo nuvem aplica-se a novas fotos próprias do Momentra")
          remember(record); await persistRecord(record)
          try { beginDiagnostic("composition"); record.file = await renderStamped(image,record,options,null); record.stamped = options.stamp; recordDiagnostic("composition","passed","completed") }
          catch (error) { recordDiagnostic("composition","failed","operation_failed"); record.warnings.push("Composição falhou; original preservado: "+String(error)) }
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
    locating.current = true; beginDiagnostic("gps")
    try {
      await Location.setAccuracy("best")
      const result = await within(Location.requestCurrent({forceRequest:true}),10000,null)
      const current = validFix(result,Date.now())
      recordDiagnostic("gps",current ? "passed" : "failed",current ? "completed" : "invalid_result")
      if (alive.current && settingsRef.current.gps) {
        fixRef.current = current; setFix(current)
        say(current ? "GPS atualizado" : "GPS indisponível. Você ainda pode fotografar.")
      }
    } catch (_) { recordDiagnostic("gps","failed","operation_failed"); fixRef.current=null; if (alive.current) setFix(null); say("Sem acesso ao GPS. A câmera continua disponível.") }
    finally { locating.current = false }
  }
  async function start(target: "video" | "photo" = modeRef.current) {
    initializingRef.current = true; setInitializing(true)
    try {
      const device = cameraPosition.current === "front" ? AVCaptureDevice.defaultDevice("builtInWideAngleCamera","video","front") : AVCaptureDevice.default("video")
      if (!device) throw new Error("Câmera indisponível neste aparelho")
      const session = new AVCaptureSession(); ownedSession = session
      const output = target === "photo" ? new AVCapturePhotoOutput() : null
      const movie = target === "video" ? new AVCaptureMovieFileOutput() : null
      const input = new AVCaptureDeviceInput(device)
      const microphone = target === "video" ? AVCaptureDevice.default("audio") : null
      if (target === "video" && !microphone) throw new Error("Microfone indisponível")
      const audio = microphone ? new AVCaptureDeviceInput(microphone) : null
      const activeOutput = output ?? movie!
      session.configure(() => {
        session.sessionPreset = target === "photo" ? "photo" : "high"
        if (!session.canAddInput(input) || !session.canAddOutput(activeOutput)) throw new Error("Não foi possível configurar a câmera")
        session.addInput(input); session.addOutput(activeOutput)
        // Optional host-provided Camera Control zoom; unsupported devices keep capture working.
        try {
          if (session.supportsControls && typeof AVCaptureSystemZoomSlider !== "undefined") {
            const zoom = new AVCaptureSystemZoomSlider(device)
            if (session.canAddControl(zoom)) session.addControl(zoom)
          }
        } catch (_) { /* Zoom capability is optional. */ }
        if (audio) {
          if (!session.canAddInput(audio)) throw new Error("Não foi possível configurar o áudio")
          session.addInput(audio)
        }
      })
      if (session.supportsControls && typeof session.setControlsDelegate === "function") {
        try { session.setControlsDelegate({didBecomeActive(){},willEnterFullscreenAppearance(){},willExitFullscreenAppearance(){},didBecomeInactive(){}}) } catch (_) { /* Optional system control. */ }
      }
      await session.startRunning()
      if (!alive.current || closing || startAborted.current) {
        await session.stopRunning(); session.dispose()
        if (ownedSession === session) ownedSession = null
        return
      }
      const state = {device,session,output,movie}; cameraRef.current = state; setCamera(state)
      say(target === "photo" ? "Enquadre seu momento e toque no círculo" : "Vídeo com áudio · sem carimbo. Toque no círculo para gravar")
      if (settingsRef.current.gps) void locate()
    } catch (error) {
      const failed = ownedSession; ownedSession = null
      if (failed) {
        try { await failed.stopRunning() } catch (_) { /* Still try to release a failed session. */ }
        try { failed.dispose() } catch (_) { /* Restore path must remain available. */ }
      }
      say("Câmera: "+String(error)+". Confira a permissão do Scripting nos Ajustes e reabra.")
    } finally { initializingRef.current = false; if (alive.current) setInitializing(false) }
  }
  async function capture() {
    if (!cameraRef.current?.output) return
    setPreview(false)
    await run(async () => {
      cancelCountdown.current = false
      for (let remaining = timerRef.current; remaining > 0; remaining--) {
        countdownRef.current = remaining; setCountdown(remaining); say("Foto em "+remaining+"… Toque no obturador para cancelar")
        await new Promise<void>(resolve=>setTimeout(resolve,1000))
        if (cancelCountdown.current || closing || !alive.current) {
          countdownRef.current = 0; setCountdown(0); say("Temporizador cancelado"); return
        }
      }
      countdownRef.current = 0; setCountdown(0)
      // Freeze profile, time and GPS at actual shutter after the countdown.
      const options = JSON.parse(JSON.stringify(settingsRef.current)) as Settings
      const capturedAt = Date.now(), id = "momentra-"+capturedAt+"-"+Math.random().toString(36).slice(2,7)
      const currentFix = options.gps ? validFix(fixRef.current,capturedAt) : null
      const candidate = currentFix && forecastRef.current?.key === metCoordinateKey(currentFix.latitude,currentFix.longitude) ? forecastRef.current.value : null
      const forecast = candidate && candidate.updatedAt<=capturedAt && candidate.validAt<=capturedAt && capturedAt-candidate.validAt<=7200000 ? {...candidate} : null
      const headingValue = headingRef.current
      const heading = options.gps && headingValue && headingValue.observedAt <= capturedAt && capturedAt-headingValue.observedAt <= 10000 ? {...headingValue} : null
      beginDiagnostic("capture")
      let result: {image: UIImage}
      const original = Path.join(folder,id+"-original.jpg")
      say("Capturando…")
      try {
        await FileManager.createDirectory(folder,true)
        result = await cameraRef.current!.output!.capturePhoto({codec:"jpeg",photoFile:original,flashMode:flashRef.current})
        if (!result?.image || !await FileManager.exists(original)) throw new Error("Captura sem arquivo confirmado")
        recordDiagnostic("capture","passed","completed")
      } catch (error) { recordDiagnostic("capture","failed","operation_failed"); throw error }
      const record: CaptureRecord = {storageIntent:options.storageMode,id,original,file:original,capturedAt,profile:options.profile,stamped:false,saved:false,fix:currentFix,address:"",heading,forecast,warnings:[]}
      // Record original first. Rendering/network failures must never discard a successful capture.
      remember(record); await persistRecord(record)
      if (options.gps && !currentFix) record.warnings.push("GPS indisponível no disparo")
      {
        say(options.stamp ? "Aplicando carimbo…" : "Preparando proporção…")
        try {
          const cached = liveAssetsRef.current
          const extra = options.stamp ? cached && cached.key===liveKey(options,currentFix)
            ? {address:cached.address,map:cached.map,warnings:[...cached.warnings]}
            : await observedEnrich(currentFix,options) : {address:"",warnings:[],map:null}
          record.address = extra.address; record.warnings.push(...extra.warnings)
          beginDiagnostic("composition")
          record.file = await renderStamped(result.image,record,options,extra.map)
          record.stamped = options.stamp
          recordDiagnostic("composition","passed","completed")
        } catch (error) { recordDiagnostic("composition","failed","operation_failed"); record.warnings.push("Carimbo falhou; original preservado: "+String(error)) }
      }
      remember(record); await persistRecord(record)
      say((record.stamped ? "Foto com carimbo pronta" : options.stamp ? "Original preservado, sem carimbo" : "Foto original pronta")+(settingsRef.current.allowGallery ? ". Toque em Salvar." : options.storageMode === "cloud" ? ". Nuvem pendente: cópias temporárias locais, sem galeria. Abra Google Fotos pessoal para enviar e verificar." : ". Guardada localmente no Momentra, sem cópia na galeria e sem envio à nuvem.")+(record.warnings.length ? " "+record.warnings.join(". ") : ""))
      if (options.gps) void locate()
    })
  }
  async function changeMode(next: "video" | "photo") {
    if (initializingRef.current || locked.current || recordingRef.current || closing || next === modeRef.current) return
    if (next === "video" && settingsRef.current.storageMode === "cloud") {say("Vídeo exige armazenamento local. Altere Armazenamento nas configurações; o modo nuvem é para fotos.");return}
    await run(async () => {
      const old = cameraRef.current
      if (old) await old.session.stopRunning()
      cameraRef.current = null; setCamera(null); setTorch(false); setPreview(false)
      if (old) { old.session.dispose(); if (ownedSession === old.session) ownedSession = null }
      modeRef.current = next; setMode(next)
      say(next === "video" ? "Preparando vídeo e microfone…" : "Preparando câmera…")
      startPending = start(next); await startPending
    })
  }
  async function flipCamera() {
    if (initializingRef.current || locked.current || recordingRef.current || closing || !cameraRef.current) return
    const next = cameraPosition.current === "back" ? "front" : "back"
    if (next === "front") {
      try {
        if (typeof AVCaptureDevice.defaultDevice !== "function" || !AVCaptureDevice.defaultDevice("builtInWideAngleCamera","video","front")) { say("Câmera frontal indisponível neste aparelho."); return }
      } catch (_) { say("Câmera frontal indisponível neste aparelho."); return }
    }
    await run(async()=>{
      const old=cameraRef.current!
      await old.session.stopRunning(); cameraRef.current=null;setCamera(null);old.session.dispose();if(ownedSession===old.session)ownedSession=null
      cameraPosition.current=next;setTorch(false);setPreview(false)
      startPending=start(modeRef.current);await startPending
      if (!cameraRef.current && !closing && alive.current) {
        cameraPosition.current=next === "front" ? "back" : "front"
        startPending=start(modeRef.current);await startPending
        say(cameraRef.current ? "Troca indisponível; câmera anterior restaurada." : "Não foi possível iniciar a câmera.")
      }
    })
  }
  async function shutter() {
    if (countdownRef.current) { cancelCountdown.current = true; return }
    if (recordingRef.current) {
      if (stopping.current) return
      stopping.current = true; say("Finalizando vídeo…")
      try { await cameraRef.current?.movie?.stopRecording() }
      catch (error) { recordDiagnostic("video","failed","operation_failed"); say("Não foi possível parar o vídeo: "+String(error)); stopping.current = false }
      return
    }
    if (modeRef.current === "photo") { await capture(); return }
    if (settingsRef.current.storageMode === "cloud") {say("Vídeos exigem armazenamento local. O modo nuvem é para fotos.");return}
    if (!cameraRef.current?.movie) return
    await run(async () => {
      beginDiagnostic("video")
      try {
      await FileManager.createDirectory(folder,true)
      const path = Path.join(folder,"momentra-"+Date.now()+"-"+Math.random().toString(36).slice(2,7)+".mov")
      recordingRef.current = true; setRecording(true); stopping.current = false
      say("Gravando com áudio · toque no quadrado para parar")
      try {
        ownedMovie = cameraRef.current!.movie!
        const file = await ownedMovie.startRecording(path)
        if (!file || !await FileManager.exists(file)) throw new Error("Vídeo sem arquivo confirmado")
        recordDiagnostic("video","passed","completed")
        const video = {file,saved:false}; rememberVideo(video)
        say(settingsRef.current.allowGallery ? "Vídeo guardado no Momentra. Toque em Salvar vídeo. Sem carimbo." : "Vídeo guardado localmente no Momentra, sem galeria e sem envio à nuvem. Sem carimbo.")
      } finally { ownedMovie = null; recordingRef.current = false; setRecording(false); stopping.current = false }
      } catch (error) { recordDiagnostic("video","failed","operation_failed"); throw error }
    })
  }
  function rememberVideo(video: {file:string;saved:boolean}) {
    lastVideoRef.current = video; if (alive.current) setLastVideo(video)
    Storage.set("momentra.video.latest",video)
    const rows = Storage.get<{file:string;saved:boolean}[]>("momentra.video.history")
    Storage.set("momentra.video.history",[video,...(Array.isArray(rows) ? rows.filter(x=>x?.file !== video.file) : [])].slice(0,50))
  }
  async function videoHistory() {
    await run(async()=>{
      const rows = Storage.get<{file:string;saved:boolean}[]>("momentra.video.history")
      if (!Array.isArray(rows) || !rows.length) { say("Ainda não há vídeos no Momentra"); return }
      const selected = await Dialog.actionSheet({title:"Vídeos recentes",actions:rows.map(x=>({label:Path.basename(x.file)+(x.saved ? " ✓" : "")})),cancelButton:true})
      if (selected === null) return
      if (!await FileManager.exists(rows[selected].file)) { say("Vídeo não encontrado no armazenamento local"); return }
      rememberVideo(rows[selected]); say(rows[selected].saved ? "Vídeo selecionado já salvo no Fotos" : "Vídeo selecionado. Toque em Salvar vídeo.")
    })
  }
  async function saveVideo() {
    await run(async () => {
      if (settingsRef.current.storageMode === "cloud" || !settingsRef.current.allowGallery) { say("Galeria desativada. Vídeo preservado no armazenamento local do Momentra; não está na nuvem."); return }
      const video = lastVideoRef.current; if (!video || video.saved) return
      if (!await Photos.saveVideo(video.file)) { say("Fotos não confirmou. O vídeo continua no Momentra."); return }
      const saved = {...video,saved:true}; rememberVideo(saved); say("Vídeo salvo no Fotos")
    })
  }
  async function flashMenu() {
    await run(async()=>{
      const values = ["on","auto","off"] as const
      const labels = ["Ligado","Automático","Desligado"]
      const choice = await Dialog.actionSheet({title:"Flash",message:"O disparo depende do suporte da câmera. Automático deixa a decisão com o iPhone.",actions:values.map((v,i)=>({label:labels[i]+(v===flashRef.current ? " ✓" : "")})),cancelButton:true})
      if (choice === null) return
      flashRef.current = values[choice]; setFlash(values[choice]); say("Flash: "+labels[choice])
    })
  }
  async function timerMenu() {
    await run(async()=>{
      const values = [0,3,10] as const
      const choice = await Dialog.actionSheet({title:"Temporizador",actions:values.map(v=>({label:(v ? v+" segundos" : "Desligado")+(v===timerRef.current ? " ✓" : "")})),cancelButton:true})
      if (choice === null) return
      timerRef.current = values[choice]; setTimer(values[choice]); say(values[choice] ? "Foto após "+values[choice]+" segundos" : "Temporizador desligado")
    })
  }
  async function ratioMenu() {
    await run(async()=>{
      const values = ["4:3","16:9"] as const
      const choice = await Dialog.actionSheet({title:"Proporção da foto",message:"A foto final é recortada ao centro. O original permanece inteiro.",actions:values.map(v=>({label:v+(v===settingsRef.current.aspectRatio ? " ✓" : "")})),cancelButton:true})
      if (choice === null) return
      update({...settingsRef.current,aspectRatio:values[choice]}); say("Foto final em "+values[choice])
    })
  }
  function TimestampPage() {
    const dismissSettings = Navigation.useDismiss()
    const [value,setValue] = useState(settingsRef.current)
    const [torchValue,setTorchValue] = useState(torch)
    function change(patch: Partial<Settings>) { const next = {...settingsRef.current,...patch}; if(next.storageMode === "cloud") next.allowGallery=false; update(next); setValue(next) }
    function Icon(props:{symbol:string;color:string}) {
      return <Image systemName={props.symbol} font="title3" foregroundStyle="white" frame={{width:44,height:44}} background={props.color} cornerRadius={22} masksToBounds accessibilityHidden />
    }
    function Row(props:{symbol:string;color:string;children:any}) {
      return <HStack spacing={12} padding={{leading:14,trailing:14,top:10,bottom:10}} frame={{minHeight:64,maxWidth:"infinity",alignment:"leading"}}><Icon symbol={props.symbol} color={props.color} /><VStack alignment="leading" spacing={0} frame={{maxWidth:"infinity",alignment:"leading"}}>{props.children}</VStack></HStack>
    }
    function Rule() { return <HStack frame={{height:1}} background="#E5E5EA" padding={{leading:70,trailing:14}} /> }
    function Group(props:{title:string;children:any;note?:string}) {
      return <VStack alignment="leading" spacing={8} frame={{maxWidth:"infinity",alignment:"leading"}}>
        <Text font="headline" foregroundStyle="#63636C" padding={{leading:18}}>{props.title}</Text>
        <VStack spacing={0} frame={{maxWidth:"infinity",alignment:"leading"}} background="white" cornerRadius={24}>{props.children}</VStack>
        {props.note ? <Text font="caption" foregroundStyle="#63636C" padding={{leading:18,trailing:18}}>{props.note}</Text> : null}
      </VStack>
    }
    return <NavigationStack preferredColorScheme="light"><VStack spacing={0} background="#F2F2F7" foregroundStyle="#17171B" accessibilityIdentifier="momentra.settings" frame={{maxWidth:"infinity",maxHeight:"infinity"}}>
      <ZStack frame={{height:64}} background="white">
        <Text font="headline">Configurações</Text>
        <HStack padding={{leading:16,trailing:16}}><Button buttonStyle="plain" accessibilityLabel="Voltar à câmera" action={dismissSettings} frame={{width:44,height:44}} background="#F2F2F7" cornerRadius={22} masksToBounds><Image systemName="chevron.left" font="title3" frame={{width:44,height:44}} /></Button><Spacer /></HStack>
      </ZStack>
      <ScrollView frame={{maxWidth:"infinity",maxHeight:"infinity"}}><VStack alignment="leading" spacing={28} frame={{maxWidth:"infinity",alignment:"leading"}} padding={{leading:16,trailing:16,top:28,bottom:32}}>
        <HStack><Spacer /><VStack spacing={8}><Icon symbol="camera.fill" color="#3478F6" /><Text font="title2">Momentra</Text><Text font="subheadline" foregroundStyle="#63636C">{ "v"+VERSION }</Text></VStack><Spacer /></HStack>
        <Group title="Câmera"><VStack spacing={0} padding={{leading:14,trailing:14}}><SettingsAction title={value.profile} symbol="square.stack" disabled={mode === "video"} hint="Escolher padrão do carimbo" action={()=>{void chooseProfile().then(()=>setValue(settingsRef.current))}} />
                <SettingsAction title="Padrão" symbol="slider.horizontal.3" disabled={mode === "video"} hint="Editar título, observação e logotipo" action={()=>{void editProfile().then(()=>setValue(settingsRef.current))}} />

              <SettingsAction title={value.gps ? "GPS ✓" : "GPS"} symbol="location" disabled={mode === "video"} value={value.gps ? "Ligado" : "Desligado"} action={()=>{void gpsMenu().then(()=>setValue(settingsRef.current))}} />
                <SettingsAction title={torchValue ? "Luz ✓" : "Luz"} symbol="flashlight.on.fill" disabled={!camera?.device.hasTorch} value={torchValue ? "Ligada" : "Desligada"} action={()=>{void run(async()=>{await cameraRef.current!.device.setTorchMode(torchValue ? "off" : "on");setTorch(!torchValue);setTorchValue(!torchValue)})}} />
                <SettingsAction title="Recentes" symbol={mode === "video" ? "video" : "photo.on.rectangle"} action={()=>{if (mode === "video") void videoHistory(); else void history()}} />
                <SettingsAction title="Exportar ajustes para app nativo" symbol="square.and.arrow.up" disabled={mode === "video"} hint="Exportar apenas opções e textos dos perfis; logotipos não são incluídos" action={()=>{void exportNativeSettings()}} />
                <SettingsAction title="Exportar logotipo do perfil" symbol="photo" disabled={mode === "video" || !value.profiles[value.profile].logoPath} hint="Salvar uma cópia do logotipo atual em Arquivos" action={()=>{void exportNativeLogo()}} />
              </VStack></Group>
        <Group title="Data, hora e localização" note="As três informações ficam sempre juntas. Sem permissão ou sinal, a localização aparece como indisponível. As mudanças valem para as próximas fotos; vídeos não recebem carimbo.">
          <Row symbol="text.viewfinder" color="#3478F6"><Toggle title="Carimbo na foto" value={value.stamp} onChanged={next=>change({stamp:next})} toggleStyle="switch" frame={{maxWidth:"infinity",alignment:"leading"}} /></Row><Rule />
          <Row symbol="textformat" color="#6854DE"><Picker title="Fonte" value={value.timestampFont} onChanged={next=>change({timestampFont:next})} pickerStyle="menu" frame={{maxWidth:"infinity",alignment:"leading"}}><Text tag="system">Sistema</Text><Text tag="serif">Serifada</Text><Text tag="mono">Monoespaçada</Text></Picker></Row><Rule />
          <Row symbol="calendar" color="#F28B32"><Picker title="Data e hora" value={value.timestampFormat} onChanged={next=>change({timestampFormat:next})} pickerStyle="menu" frame={{maxWidth:"infinity",alignment:"leading"}}><Text tag="numeric">Numérico</Text><Text tag="long">Data por extenso · hora h/min/s</Text></Picker></Row><Rule />
          <Row symbol="viewfinder" color="#3478F6"><Picker title="Canto do timestamp" value={value.timestampCorner} onChanged={next=>change({timestampCorner:next})} pickerStyle="menu" frame={{maxWidth:"infinity",alignment:"leading"}}><Text tag="top-left">Superior esquerdo</Text><Text tag="top-right">Superior direito</Text><Text tag="bottom-left">Inferior esquerdo</Text><Text tag="bottom-right">Inferior direito</Text></Picker></Row>
        </Group>
        <Group title="Localização e mapa" note="GPS é uma opção do Momentra, não o estado da permissão do iOS. Ao ativar, o aparelho pode pedir autorização. Endereço e mapa usam serviços Apple; a foto não é enviada. Sem GPS válido, nenhum mapa é inventado. A API de localização disponível não informa precisão nem altitude para o carimbo.">
          <Row symbol="location.fill" color="#F28B32"><Toggle title="GPS" value={value.gps} onChanged={next=>{change({gps:next}); if (next) void locate(); else {fixRef.current=null;setFix(null)}}} toggleStyle="switch" frame={{maxWidth:"infinity",alignment:"leading"}} /></Row><Rule />
          <Row symbol="cloud.sun.fill" color="#E59C25"><VStack alignment="leading"><Button title="Consultar previsão MET Norway" disabled={busy || !value.gps} action={()=>{void consultForecast()}} /><Text font="caption">Consulta manual: dados de modelo e pressão ao nível do mar. MET Norway · CC BY 4.0.</Text><Button title="Termos e fontes meteorológicas" action={()=>{void Safari.openURL("https://docs.api.met.no/doc/TermsOfService")}} /></VStack></Row><Rule />
          <Row symbol="map.fill" color="#4EBF64"><Toggle title="Mapa de satélite" value={value.map} onChanged={next=>change({map:next})} toggleStyle="switch" frame={{maxWidth:"infinity",alignment:"leading"}} /></Row><Rule />
          <Row symbol="arrow.up.left.and.arrow.down.right" color="#3478F6"><Picker title="Tamanho do mapa" value={value.mapScale} onChanged={next=>change({mapScale:next})} pickerStyle="menu" frame={{maxWidth:"infinity",alignment:"leading"}}><Text tag="small">Pequeno</Text><Text tag="medium">Médio</Text><Text tag="large">Grande</Text></Picker></Row><Rule />
          <Row symbol="viewfinder" color="#3478F6"><Picker title="Canto do mapa" value={value.mapCorner} onChanged={next=>change({mapCorner:next})} pickerStyle="menu" frame={{maxWidth:"infinity",alignment:"leading"}}><Text tag="top-left">Superior esquerdo</Text><Text tag="top-right">Superior direito</Text><Text tag="bottom-left">Inferior esquerdo</Text><Text tag="bottom-right">Inferior direito</Text></Picker></Row>
        </Group>
        <Group title="Imagem ou logotipo" note="Escolha a imagem em Câmera → Padrão, nesta página. A proporção da arte é preservada.">
          <Row symbol="photo.fill" color="#4EBF64"><Picker title="Canto da imagem" value={value.logoCorner} onChanged={next=>change({logoCorner:next})} pickerStyle="menu" frame={{maxWidth:"infinity",alignment:"leading"}}><Text tag="top-left">Superior esquerdo</Text><Text tag="top-right">Superior direito</Text><Text tag="bottom-left">Inferior esquerdo</Text><Text tag="bottom-right">Inferior direito</Text></Picker></Row>
        </Group>
        <Group title="Armazenamento" note="Somente nuvem vale para novas fotos próprias, sem galeria. Original e final ficam locais até envio manual e verificação de bytes idênticos; falhas mantêm cópias pendentes. JSON e cache podem permanecer. Vídeos exigem Local. Cópias anteriores não são apagadas.">
          <Row symbol="externaldrive.fill" color="#3478F6"><Picker title="Destino das novas fotos" value={value.storageMode} onChanged={next=>change({storageMode:next})} pickerStyle="menu" frame={{maxWidth:"infinity",alignment:"leading"}}><Text tag="local">Local</Text><Text tag="cloud">Somente nuvem após verificar</Text></Picker></Row><Rule />
          <Row symbol="photo.on.rectangle" color="#4EBF64"><Toggle title="Cópia na galeria Fotos" disabled={value.storageMode === "cloud"} value={value.allowGallery} onChanged={next=>change({allowGallery:next})} toggleStyle="switch" frame={{maxWidth:"infinity",alignment:"leading"}} /></Row>
        </Group>
        <Group title="Conta"><VStack alignment="leading" padding={18}><GoogleAccount /><Button title="Google Fotos pessoal" buttonStyle="bordered" action={()=>{void Navigation.present({modalPresentationStyle:"fullScreen",element:<GooglePhotosPage capture={lastRef.current} onArchived={()=>{setPreviewImage(null);setPreview(false);say("Estado da nuvem atualizado. Consulte Google Fotos pessoal para visualizar.")}} />})}} /><DiagnosticReport /></VStack></Group>
        <Text font="caption" foregroundStyle="#63636C" padding={{leading:18,trailing:18}} accessibilityIdentifier="momentra.cloud-unavailable">Google Fotos pessoal depende de ativação do serviço, consentimento separado e envio manual da foto selecionada. No modo somente nuvem, JPEGs do Momentra só são removidos após confirmar original e final idênticos no Google. Qualquer divergência mantém cópia local pendente.</Text>
        <Text font="caption" foregroundStyle="#63636C" padding={{leading:18,trailing:18}}>Momentra · As opções acima são funções reais do aplicativo. Permissões do sistema são solicitadas apenas ao usar o recurso correspondente.</Text>
      </VStack></ScrollView>
    </VStack></NavigationStack>
  }
  async function openSettings() {
    if (locked.current || closing || settingsOpen.current) return
    settingsOpen.current=true
    try { setShowGoogleIntro(false);Storage.set("momentra.google.intro.v1",true);await Navigation.present({element:<TimestampPage />,modalPresentationStyle:"fullScreen"}) }
    finally { settingsOpen.current=false }
  }
  async function chooseProfile() {
    await run(async () => {
      const selected = await Dialog.actionSheet({title:"Escolha um padrão",actions:PROFILE_IDS.map(id=>({label:id+(id === settingsRef.current.profile ? " ✓" : "")})),cancelButton:true})
      if (selected === null) return
      update({...settingsRef.current,profile:PROFILE_IDS[selected]}); say("Padrão "+PROFILE_IDS[selected]+" selecionado")
    })
  }
  async function save() {
    await run(async () => {
      if (settingsRef.current.storageMode === "cloud" || lastRef.current?.storageIntent === "cloud" || !settingsRef.current.allowGallery) { say("Salvamento na galeria bloqueado. Consulte o estado da captura em Google Fotos pessoal."); return }
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
      const choice = await Dialog.actionSheet({title:"Padrão "+id,actions:[{label:"Editar título"},{label:"Editar observação / serviço"},{label:"Escolher logotipo nos Arquivos"},{label:"Remover logotipo"},{label:"Tamanho: "+(current.size === "regular" ? "normal" : "compacto")}],cancelButton:true})
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
      else if (choice === 4) next.size = current.size === "regular" ? "compact" : "regular"
      update(next); say("Padrão salvo para as próximas fotos")
    })
  }
  async function gpsMenu() {
    await run(async () => {
      const s = settingsRef.current
      const choice = await Dialog.actionSheet({title:"Localização",message:"GPS é capturado no aparelho. Endereço e mapa usam os serviços Apple quando o GPS está ligado. A foto nunca é enviada.",actions:[{label:s.gps ? "Desligar GPS" : "Ativar GPS"},{label:"Atualizar GPS agora"},{label:s.map ? "Desligar mapa de satélite" : "Ativar mapa de satélite"},{label:"Abrir localização no Google Maps (externo)"}],cancelButton:true})
      if (choice === null) return
      if (choice === 0) {
        update({...s,gps:!s.gps}); fixRef.current = null; setFix(null)
        if (!s.gps) await locate(); else say("GPS desativado")
      } else if (choice === 1) {
        if (!s.gps) update({...s,gps:true})
        await locate()
      } else if (choice === 2) {
        update({...s,map:!s.map,gps:!s.map ? true : s.gps})
        if (!s.map && !s.gps) await locate()
        else say(s.map ? "Mapa desativado" : "Mapa será incluído quando disponível")
      } else if (choice === 3) {
        const current=s.gps ? validFix(fixRef.current,Date.now()) : null
        if (!current) {say("Atualize o GPS antes de abrir o Google Maps.");return}
        const approved=await Dialog.actionSheet({title:"Abrir no Google Maps",message:"A localização atual será enviada ao Google para abrir o mapa externo. Isso não altera o mapa Apple no carimbo nem envia sua foto.",actions:[{label:"Abrir localização no Google Maps"}],cancelButton:true})
        if (approved !== 0) return
        const url="https://www.google.com/maps/search/?api=1&query="+encodeURIComponent(current.latitude+","+current.longitude)
        const opened=await Safari.openURL(url)
        say(opened ? "Localização aberta no Google Maps. O carimbo continua usando mapa Apple." : "Não foi possível abrir o Google Maps.")
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
      if (!(await FileManager.exists(record.file))) {
        const archived=getCloudArchiveState(record.id)
        if (record.storageIntent === "cloud" && archived) {
          lastRef.current=record;setLast(record);setPreviewImage(null);setPreview(false)
          await Navigation.present({modalPresentationStyle:"fullScreen",element:<GooglePhotosPage capture={record} onArchived={()=>{setPreviewImage(null);setPreview(false)}} />})
          return
        }
        say("Arquivo não encontrado no armazenamento local"); return
      }
      remember(record); setPreview(true); say(record.storageIntent === "cloud" ? "Nuvem pendente. Abra Google Fotos pessoal para enviar e verificar esta captura." : record.saved ? "Esta foto já foi salva no Fotos" : "Foto recuperada. Toque em Salvar.")
    })
  }
  async function exportFiles() {
    await run(async () => {
      const record = lastRef.current; if (!record) return
      if (record.storageIntent === "cloud") {say("Esta captura usa modo nuvem. Consulte Google Fotos pessoal; exportação local não é feita automaticamente.");return}
      const choice = await Dialog.actionSheet({title:"Exportar para Arquivos",actions:[{label:"Foto final"},{label:"Original sem carimbo"},{label:"Registro JSON de captura"}],cancelButton:true})
      if (choice === null) return
      const path = choice === 0 ? record.file : choice === 1 ? record.original : Path.join(folder,record.id+".json")
      const data = await FileManager.readAsData(path)
      const result = await DocumentPicker.exportFiles({files:[{data,name:Path.basename(path)}]})
      say(result.length ? "Arquivo exportado" : "Exportação cancelada; foto preservada")
    })
  }
  async function exportNativeSettings() {
    await run(async () => {
      const payload = nativeSettingsTransfer(settingsRef.current)
      const json = JSON.stringify(payload,null,2)
      const data = typeof Data.fromRawString === "function" ? Data.fromRawString(json) : Data.fromString(json)
      if (!data) throw new Error("Não foi possível preparar os ajustes para exportação")
      const result = await DocumentPicker.exportFiles({files:[{name:"momentra-ajustes.json",data}]})
      say(result.length ? "Ajustes exportados; logotipos não incluídos" : "Exportação cancelada; ajustes preservados")
    })
  }
  async function exportNativeLogo() {
    await run(async () => {
      const s = settingsRef.current, logoPath = s.profiles[s.profile].logoPath
      if (!logoPath || !await FileManager.exists(logoPath)) { say("Logotipo não encontrado; nenhuma alteração foi feita"); return }
      const data = await FileManager.readAsData(logoPath)
      const result = await DocumentPicker.exportFiles({files:[{name:"momentra-logo-"+s.profile+".png",data}]})
      say(result.length ? "Cópia do logotipo exportada" : "Exportação cancelada; logotipo preservado")
    })
  }
  async function consultForecast() {
    if (locked.current || closing || recordingRef.current) return
    const fix= settingsRef.current.gps ? validFix(fixRef.current,Date.now()) : null
    if (!fix) {say("Ative o GPS e aguarde localização para consultar a previsão.");return}
    if (Storage.get("momentra.met.terms.v1") !== true) {
      const choice=await Dialog.actionSheet({title:"Previsão MET Norway",message:"A consulta envia coordenadas aproximadas e seu IP à MET Norway. A previsão é um modelo; pressão é ao nível do mar. Leia os termos antes de aceitar. Fonte: MET Norway, CC BY 4.0.",actions:[{label:"Ler termos da MET Norway"},{label:"Li e aceito os termos"}],cancelButton:true})
      if(choice===0){await Safari.openURL("https://docs.api.met.no/doc/TermsOfService");return}
      if(choice!==1)return
      if(!Storage.set("momentra.met.terms.v1",true)){say("Não foi possível guardar a escolha.");return}
    }
    await run(async()=>{
      say("Consultando previsão MET Norway…")
      const key=metCoordinateKey(fix.latitude,fix.longitude)
      const value=await requestMetForecast({enabled:true,foreground:true,latitude:fix.latitude,longitude:fix.longitude,now:Date.now(),store:{get:k=>Storage.get(k),set:(k,v)=>Storage.set(k,v)},transport:(url,options)=>fetch(url,options)})
      const current=settingsRef.current.gps ? validFix(fixRef.current,Date.now()) : null
      if (!current || metCoordinateKey(current.latitude,current.longitude)!==key) {say("Localização mudou; previsão descartada.");return}
      const next=value ? {key,value} : null;forecastRef.current=next;setForecast(next)
      say(value ? "Previsão MET Norway disponível para o carimbo." : "Previsão indisponível; a foto continua disponível.")
    })
  }
  function liveKey(options: Settings, current: Fix | null) {
    return options.gps && current ? [current.latitude,current.longitude,current.timestamp,options.map].join(":") : ""
  }
  useEffect(()=>{
    let cancelled=false, started=false
    const listener=(value: {trueHeading:number;headingAccuracy:number;timestamp:Date})=>{
      if (cancelled) return
      const time = value?.timestamp ? new Date(value.timestamp).getTime() : NaN, degrees=value?.trueHeading
      if (Number.isFinite(time) && Number.isFinite(degrees) && degrees>=0 && degrees<360 && Number.isFinite(value?.headingAccuracy) && value.headingAccuracy>=0) headingRef.current={degrees,observedAt:time}
      else headingRef.current=null
    }
    if (settings.gps && mode === "photo" && typeof Location.startUpdatingHeading === "function" && typeof Location.addHeadingListener === "function" && typeof Location.removeHeadingListener === "function" && typeof Location.stopUpdatingHeading === "function") {
      headingOps.current=headingOps.current.then(async()=>{
        if(cancelled)return
        await Location.startUpdatingHeading()
        if(cancelled){Location.stopUpdatingHeading();return}
        Location.addHeadingListener(listener);started=true
      }).catch(()=>{})
    }
    return ()=>{cancelled=true;headingRef.current=null;headingOps.current=headingOps.current.then(()=>{if(started){Location.removeHeadingListener(listener);Location.stopUpdatingHeading()}}).catch(()=>{})}
  },[settings.gps,mode])
  useEffect(()=>{
    let cancelled=false, timer:ReturnType<typeof setTimeout>|undefined, loading=false, lastRequest="", gpsAt=Date.now()
    async function tick() {
      if (cancelled || closing) return
      const now=Date.now(); setLiveNow(now)
      const options=settingsRef.current, current=validFix(fixRef.current,now), key=liveKey(options,current)
      // GPS remains opt-in. Refresh only while the custom photo camera is active.
      if (cameraRef.current && modeRef.current === "photo" && options.gps && now-gpsAt>=30000 && !locked.current) {gpsAt=now;void locate()}
      if (!key) {lastRequest="";liveAssetsRef.current=null;setLiveAssets(null)}
      else if (!loading && options.stamp && modeRef.current === "photo" && key!==lastRequest) {
        loading=true;lastRequest=key
        void observedEnrich(current,JSON.parse(JSON.stringify(options))).then(extra=>{
          if (!cancelled && key===liveKey(settingsRef.current,validFix(fixRef.current,Date.now()))) {
            const value={key,address:extra.address,map:extra.map,warnings:extra.warnings};liveAssetsRef.current=value;setLiveAssets(value)
          }
        }).catch(()=>{}).finally(()=>{loading=false})
      }
      timer=setTimeout(()=>{void tick()},1000)
    }
    void tick()
    return ()=>{cancelled=true;if(timer!==undefined)clearTimeout(timer)}
  },[])
  useEffect(() => {
    alive.current = true
    recordApiAvailability("capture",typeof AVCapturePhotoOutput !== "undefined" && typeof AVCaptureSession !== "undefined")
    recordApiAvailability("composition",typeof ImageRenderer !== "undefined" && typeof ImageRenderer.toJPEGData === "function")
    recordApiAvailability("video",typeof AVCaptureMovieFileOutput !== "undefined")
    recordApiAvailability("gps",typeof Location !== "undefined" && typeof Location.requestCurrent === "function")
    recordApiAvailability("map",typeof MapSnapshotter !== "undefined" && typeof MapSnapshotter.take === "function")
    recordApiAvailability("oauth",typeof OAuth2 !== "undefined")
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

  function SettingsAction(props: {title: string; symbol: string; action: () => void; disabled?: boolean; value?:string; hint?:string}) {
    return <Button action={props.action} disabled={busy || props.disabled} buttonStyle="plain" accessibilityLabel={props.title} accessibilityValue={props.value} accessibilityHint={props.hint} frame={{maxWidth:"infinity",minHeight:54,alignment:"leading"}}>
      <HStack spacing={12}><Image systemName={props.symbol} font="title3" frame={{width:44,height:44}} /><Text>{props.title}</Text><Spacer /><Image systemName="chevron.right" font="caption" /></HStack>
    </Button>
  }
  return <NavigationStack preferredColorScheme="dark" statusBarHidden persistentSystemOverlays="hidden" onCameraCaptureEvent={{isEnabled:!!camera && !closing && !settingsOpen.current,primaryAction:event=>{if(event.phase === "ended" && !settingsOpen.current) void shutter()}}}>
    <ZStack frame={{maxWidth:"infinity",maxHeight:"infinity"}}>
    <VStack frame={{maxWidth:"infinity",maxHeight:"infinity"}} background="black" ignoresSafeArea accessibilityHidden />
    <GeometryReader>{geometry => {
      const width = geometry.size.width, height = geometry.size.height
      const protectTop = mode === "photo" && settings.stamp && (settings.timestampCorner.startsWith("top") || (settings.gps && settings.map && settings.mapCorner.startsWith("top")) || (!!settings.profiles[settings.profile].logoPath && settings.logoCorner.startsWith("top")))
      const layout = cameraLayout(width,height,mode === "video" ? "16:9" : settings.aspectRatio,!protectTop), compact = layout.compact
      const currentFix=settings.gps ? validFix(fix,liveNow) : null
      const assets=liveAssets?.key===liveKey(settings,currentFix) && currentFix ? liveAssets : null
      const logoPath=settings.profiles[settings.profile].logoPath
      if (logoCache.current.path!==logoPath) logoCache.current={path:logoPath,image:logoPath ? UIImage.fromFile(logoPath) : null}
      const liveForecast=currentFix && forecast?.key===metCoordinateKey(currentFix.latitude,currentFix.longitude) && forecast.value.validAt<=liveNow && liveNow-forecast.value.validAt<=7200000 ? forecast.value : null
      const liveRecord:CaptureRecord={id:"live-preview",original:"",file:"",capturedAt:liveNow,profile:settings.profile,stamped:false,saved:false,fix:currentFix,address:assets?.address??"",forecast:liveForecast,heading:settings.gps && headingRef.current && headingRef.current.observedAt<=liveNow && liveNow-headingRef.current.observedAt<=10000 ? headingRef.current : null,warnings:[]}

      const toolbar = (<GlassEffectContainer><HStack frame={{width:layout.contentWidth,height:layout.toolbar}}><HStack spacing={layout.toolbarGap} frame={{width:layout.contentWidth-24,height:layout.toolbar}}>
          <Button buttonStyle="plain" {...circularControl()} disabled={busy || mode === "video"} accessibilityLabel="Flash" accessibilityValue={flash} action={()=>{void flashMenu()}}><Image systemName={flash === "off" ? "bolt.slash.fill" : flash === "auto" ? "bolt.badge.a" : "bolt.fill"} foregroundStyle={flash === "off" ? "white" : "#FFD60A"} font="title3" frame={{width:44,height:44}} /></Button>
          <Button buttonStyle="plain" {...circularControl()} disabled={busy || mode === "video"} accessibilityLabel="Temporizador" accessibilityValue={timer ? timer+" segundos" : "Desligado"} action={()=>{void timerMenu()}}><VStack spacing={0} frame={{width:44,height:44}}><Image systemName="timer" font="title3" />{timer ? <Text font="caption2">{timer+"s"}</Text> : null}</VStack></Button>
          <Button title={settings.aspectRatio} buttonStyle="plain" {...circularControl()} disabled={busy || mode === "video"} accessibilityLabel="Proporção" action={()=>{void ratioMenu()}} font="caption" />
          <Button buttonStyle="plain" {...circularControl()} disabled={busy} accessibilityLabel="Configurações" action={()=>{void openSettings()}}><Image systemName="gearshape" font="title3" frame={{width:44,height:44}} /></Button>
        </HStack></HStack></GlassEffectContainer>)
      const statusBar = (<HStack frame={{width:layout.contentWidth,height:layout.status}}><HStack spacing={8} frame={{width:layout.contentWidth-24,height:layout.status}}>
          <ScrollView><VStack alignment="leading" spacing={2}><Text font="caption2" foregroundStyle="#D0D0D0">{status}</Text>{showGoogleIntro ? <Button title="Google opcional · configurar" font="caption2" buttonStyle="plain" disabled={busy} action={()=>{void openSettings()}} /> : null}</VStack></ScrollView>
          <Button {...circularControl()} buttonStyle="plain" accessibilityLabel={mode === "photo" ? last?.saved ? "Salva ✓" : "Salvar" : lastVideo?.saved ? "Vídeo salvo ✓" : "Salvar vídeo"}
            disabled={!settings.allowGallery || busy || (mode === "photo" ? !last || last.saved || last.storageIntent === "cloud" : !lastVideo || lastVideo.saved)} action={()=>{if (mode === "photo") void save(); else void saveVideo()}}>
            <Image systemName={(mode === "photo" ? last?.saved : lastVideo?.saved) ? "checkmark.circle" : "square.and.arrow.down"} font="title3" frame={{width:44,height:44}} />
          </Button>
          {mode === "photo" ? <Button {...circularControl()} accessibilityLabel="Exportar" buttonStyle="plain" disabled={!last || last.storageIntent === "cloud" || busy} action={()=>{void exportFiles()}}><Image systemName="square.and.arrow.up" font="title3" frame={{width:44,height:44}} /></Button> : null}
          <Button {...circularControl()} buttonStyle="plain" disabled={busy} accessibilityLabel="Fechar" action={()=>{void closeCamera()}}><Image systemName="xmark" font="title3" frame={{width:44,height:44}} /></Button>
        </HStack></HStack>)
      const viewfinder = (<ZStack frame={{width:layout.viewWidth,height:layout.viewHeight}}>
          {camera ? <CaptureVideoPreviewView session={camera.session} videoDevice={camera.device} videoGravity="resizeAspectFill" frame={{width:layout.viewWidth,height:layout.viewHeight}} masksToBounds /> : <Text font="callout">{status}</Text>}
          {camera && mode === "photo" && settings.stamp && !preview ? <Canvas opaque={false} frame={{width:layout.viewWidth,height:layout.viewHeight}} accessibilityIdentifier="momentra.live-overlay" accessibilityHidden draw={ctx=>drawStamp(ctx,layout.viewWidth,layout.viewHeight,settings,liveRecord,settings.map && assets?.map ? {image:assets.map} : null,logoCache.current.image ? {image:logoCache.current.image} : null,true)} /> : null}
          {preview && previewImage ? <Image image={previewImage} resizable scaleToFit background="black" frame={{width:layout.viewWidth*0.72,height:layout.viewHeight*0.72}} /> : null}

        </ZStack>)
      const captureControls = (<HStack frame={{width:layout.captureWidth,height:layout.shutter}}>
          <VStack spacing={2}><Button {...circularControl()} buttonStyle="plain" accessibilityLabel={preview ? "Câmera" : "Prévia"} disabled={busy || mode === "video" || (!preview && !last)} action={()=>{if (preview && !camera) void run(restoreCamera); else setPreview(!preview)}}>
            {previewImage ? <Image image={previewImage} resizable scaleToFill frame={{width:44,height:44}} cornerRadius={22} masksToBounds /> : <Image systemName="photo" font="title3" frame={{width:44,height:44}} />}
          </Button>{!compact ? <Text font="caption2" accessibilityHidden>{preview ? "Câmera" : "Prévia"}</Text> : null}</VStack>
          <Spacer />
          {!layout.landscape ? <VStack spacing={2}><Button {...circularControl()} buttonStyle="plain" accessibilityLabel="Escolher padrão" disabled={busy || mode === "video"} action={()=>{void chooseProfile()}}><Image systemName="square.on.square" font="title3" frame={{width:44,height:44}} /></Button>{!compact ? <Text font="caption2" accessibilityHidden>Padrão</Text> : null}</VStack> : null}
          {!layout.landscape ? <Spacer /> : null}
        <Button buttonStyle="plain" disabled={(!recording && !countdown && busy) || !camera}
          accessibilityLabel={countdown ? "Cancelar temporizador" : recording ? "Parar gravação" : mode === "photo" ? "Fotografar" : "Gravar vídeo"}
          accessibilityHint={mode === "photo" ? "Captura uma foto com o padrão selecionado" : "Toque novamente para parar"}
          action={()=>{void shutter()}}>
          <ZStack frame={{width:layout.shutter,height:layout.shutter}}>
            <Image systemName="circle" font={layout.shutter-2} foregroundStyle="white" />
            <Image systemName={recording ? "stop.fill" : "circle.fill"} font={recording ? 28 : layout.shutter-16} foregroundStyle={mode === "photo" ? "white" : "#FF514D"} />
          {countdown ? <Text font="title" foregroundStyle="black">{String(countdown)}</Text> : null}
          </ZStack>
        </Button>
          <Spacer />
          {!layout.landscape ? <VStack spacing={2}><Button {...circularControl()} buttonStyle="plain" accessibilityLabel="Localização e mapa" disabled={busy || mode === "video"} action={()=>{void gpsMenu()}}><Image systemName="map" font="title3" frame={{width:44,height:44}} /></Button>{!compact ? <Text font="caption2" accessibilityHidden>Mapa</Text> : null}</VStack> : null}
          {!layout.landscape ? <Spacer /> : null}
          <VStack spacing={2}><Button {...circularControl()} buttonStyle="plain" accessibilityLabel="Trocar câmera" disabled={busy || initializing || recording || !camera} action={()=>{void flipCamera()}}><Image systemName="camera.rotate" font="title3" frame={{width:44,height:44}} /></Button>{!compact ? <Text font="caption2" accessibilityHidden>Virar</Text> : null}</VStack>
        </HStack>)
      const modePicker = (<Picker title="Modo de captura" value={mode} onChanged={(next: "video" | "photo")=>{void changeMode(next)}} pickerStyle="segmented" disabled={initializing || busy || recording} frame={{width:layout.modeWidth,height:layout.mode}} cornerRadius={24} accessibilityLabel="Modo de captura">
          <Text tag="photo">Foto</Text><Text tag="video">Vídeo</Text>
        </Picker>)
      return <VStack spacing={0} background="black" foregroundStyle="white" frame={{width,height}}>
        {layout.landscape ? <HStack spacing={layout.gap} frame={{width,height}}>
          <VStack spacing={layout.stackGap} frame={{width:layout.contentWidth,height}}>{toolbar}{viewfinder}{statusBar}</VStack>
          <VStack spacing={12} frame={{width:layout.captureWidth,height}}>{modePicker}{captureControls}</VStack>
        </HStack> : !layout.overlay ? <VStack spacing={layout.stackGap} frame={{width,height}}>{toolbar}{viewfinder}<VStack spacing={layout.gap}>{modePicker}{captureControls}{statusBar}</VStack></VStack> : <VStack spacing={layout.stackGap} frame={{width,height}}><ZStack frame={{width:layout.contentWidth,height:layout.viewHeight}}>{viewfinder}<VStack spacing={0} frame={{width:layout.contentWidth,height:layout.viewHeight}}>{toolbar}<Spacer /></VStack></ZStack><VStack spacing={layout.gap}>{modePicker}{captureControls}{statusBar}</VStack></VStack>}
      </VStack>
    }}</GeometryReader>
    </ZStack>
  </NavigationStack>
}
async function main() {
  try { await Navigation.present({element:<CameraPage />,modalPresentationStyle:"fullScreen"}) }
  finally {
    closing = true; unsubscribe()
    // Finalize recording before waiting for its pending promise (including external dismissal).
    if (ownedMovie) await ownedMovie.stopRecording().catch(()=>{})
    // Wait for in-flight capture/writes before disposing the camera or exiting.
    await pending?.catch(()=>{})
    const old = ownedSession; ownedSession = null
    if (old) { try { await old.stopRunning(); await startPending?.catch(()=>{}) } finally { old.dispose() } }
    Script.exit()
  }
}
void main()

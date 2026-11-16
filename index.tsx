import {
  Button, Toggle, Canvas, CaptureVideoPreviewView, GeometryReader, GlassEffectContainer, Picker, HStack, VStack, ZStack, Text, Image,
  Navigation, NavigationStack, Script, Path, Spacer, ScrollView,
  useEffect, useRef, useState,
} from "scripting"
import type { CameraControlParameter } from "scripting"
import { VERSION, PROFILE_IDS, Settings, CaptureRecord, Fix, normalizeSettings, validFix, coordinates, cleanText, within } from "./core"
import { enrich, folder, persistRecord, renderStamped } from "./services"
import { cameraLayout } from "./camera_layout"
import { drawStamp } from "./stamp"
import { getGoogleIdentity, loginGoogle, logoutGoogle } from "./google_auth"

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
    connecting.current=true;setWorking(true);setMessage("")
    try { const next=await loginGoogle(); if (active.current) {setAccount(next);setMessage("Identidade conectada. Nenhuma foto foi enviada.")} }
    catch { if (active.current) setMessage("Login cancelado ou não concluído. A câmera continua disponível; tente novamente.") }
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
  const alive = useRef(true), locked = useRef(false), locating = useRef(false)
  const [busy, setBusy] = useState(false)
  const [initializing, setInitializing] = useState(true)
  const initializingRef = useRef(true)
  const [showGoogleIntro,setShowGoogleIntro] = useState(()=>!Storage.get("momentra.google.intro.v1"))
  const [status, setStatus] = useState("Iniciando câmera…")
  const [settings, setSettings] = useState<Settings>(() => normalizeSettings(Storage.get(SETTINGS)))
  const settingsRef = useRef(settings)
  const [fix, setFix] = useState<Fix | null>(null)
  const fixRef = useRef<Fix | null>(null)
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
          remember(record); await persistRecord(record)
          try { record.file = await renderStamped(image,record,options,null); record.stamped = options.stamp }
          catch (error) { record.warnings.push("Composição falhou; original preservado: "+String(error)) }
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
    } catch (_) { fixRef.current=null; if (alive.current) setFix(null); say("Sem acesso ao GPS. A câmera continua disponível.") }
    finally { locating.current = false }
  }
  async function start(target: "video" | "photo" = modeRef.current) {
    initializingRef.current = true; setInitializing(true)
    try {
      const device = AVCaptureDevice.default("video")
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
        if (audio) {
          if (!session.canAddInput(audio)) throw new Error("Não foi possível configurar o áudio")
          session.addInput(audio)
        }
      })
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
      if (failed) { try { await failed.stopRunning() } finally { failed.dispose() } }
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
      await FileManager.createDirectory(folder,true)
      const original = Path.join(folder,id+"-original.jpg")
      say("Capturando…")
      const result = await cameraRef.current!.output!.capturePhoto({codec:"jpeg",photoFile:original,flashMode:flashRef.current})
      const record: CaptureRecord = {id,original,file:original,capturedAt,profile:options.profile,stamped:false,saved:false,fix:currentFix,address:"",warnings:[]}
      // Record original first. Rendering/network failures must never discard a successful capture.
      remember(record); await persistRecord(record)
      if (options.gps && !currentFix) record.warnings.push("GPS indisponível no disparo")
      {
        say(options.stamp ? "Aplicando carimbo…" : "Preparando proporção…")
        try {
          const cached = liveAssetsRef.current
          const extra = options.stamp ? cached && cached.key===liveKey(options,currentFix)
            ? {address:cached.address,map:cached.map,warnings:[...cached.warnings]}
            : await enrich(currentFix,options) : {address:"",warnings:[],map:null}
          record.address = extra.address; record.warnings.push(...extra.warnings)
          record.file = await renderStamped(result.image,record,options,extra.map)
          record.stamped = options.stamp
        } catch (error) { record.warnings.push("Carimbo falhou; original preservado: "+String(error)) }
      }
      remember(record); await persistRecord(record)
      say((record.stamped ? "Foto com carimbo pronta" : options.stamp ? "Original preservado, sem carimbo" : "Foto original pronta")+(settingsRef.current.allowGallery ? ". Toque em Salvar." : ". Guardada localmente no Momentra, sem cópia na galeria e sem envio à nuvem.")+(record.warnings.length ? " "+record.warnings.join(". ") : ""))
      if (options.gps) void locate()
    })
  }
  async function changeMode(next: "video" | "photo") {
    if (initializingRef.current || locked.current || recordingRef.current || closing || next === modeRef.current) return
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
  async function shutter() {
    if (countdownRef.current) { cancelCountdown.current = true; return }
    if (recordingRef.current) {
      if (stopping.current) return
      stopping.current = true; say("Finalizando vídeo…")
      try { await cameraRef.current?.movie?.stopRecording() }
      catch (error) { say("Não foi possível parar o vídeo: "+String(error)); stopping.current = false }
      return
    }
    if (modeRef.current === "photo") { await capture(); return }
    if (!cameraRef.current?.movie) return
    await run(async () => {
      await FileManager.createDirectory(folder,true)
      const path = Path.join(folder,"momentra-"+Date.now()+"-"+Math.random().toString(36).slice(2,7)+".mov")
      recordingRef.current = true; setRecording(true); stopping.current = false
      say("Gravando com áudio · toque no quadrado para parar")
      try {
        ownedMovie = cameraRef.current!.movie!
        const file = await ownedMovie.startRecording(path)
        const video = {file,saved:false}; rememberVideo(video)
        say(settingsRef.current.allowGallery ? "Vídeo guardado no Momentra. Toque em Salvar vídeo. Sem carimbo." : "Vídeo guardado localmente no Momentra, sem galeria e sem envio à nuvem. Sem carimbo.")
      } finally { ownedMovie = null; recordingRef.current = false; setRecording(false); stopping.current = false }
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
      if (!settingsRef.current.allowGallery) { say("Galeria desativada. Vídeo preservado no armazenamento local do Momentra; não está na nuvem."); return }
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
    function change(patch: Partial<Settings>) { const next = {...settingsRef.current,...patch}; update(next); setValue(next) }
    function Icon(props:{symbol:string;color:string}) {
      return <Image systemName={props.symbol} font="title3" foregroundStyle="white" frame={{width:44,height:44}} background={props.color} cornerRadius={22} masksToBounds accessibilityHidden />
    }
    function Row(props:{symbol:string;color:string;children:any}) {
      return <HStack spacing={12} padding={{leading:14,trailing:14,top:10,bottom:10}} frame={{minHeight:64}}><Icon symbol={props.symbol} color={props.color} />{props.children}</HStack>
    }
    function Rule() { return <HStack frame={{height:1}} background="#E5E5EA" padding={{leading:70,trailing:14}} /> }
    function Group(props:{title:string;children:any;note?:string}) {
      return <VStack alignment="leading" spacing={8}>
        <Text font="headline" foregroundStyle="#63636C" padding={{leading:18}}>{props.title}</Text>
        <VStack spacing={0} background="white" cornerRadius={24}>{props.children}</VStack>
        {props.note ? <Text font="caption" foregroundStyle="#63636C" padding={{leading:18,trailing:18}}>{props.note}</Text> : null}
      </VStack>
    }
    return <NavigationStack preferredColorScheme="light"><VStack spacing={0} background="#F2F2F7" foregroundStyle="#17171B" accessibilityIdentifier="momentra.settings">
      <ZStack frame={{height:64}} background="white">
        <Text font="headline">Configurações</Text>
        <HStack padding={{leading:16,trailing:16}}><Button buttonStyle="plain" accessibilityLabel="Voltar à câmera" action={dismissSettings} frame={{width:44,height:44}} background="#F2F2F7" cornerRadius={22} masksToBounds><Image systemName="chevron.left" font="title3" frame={{width:44,height:44}} /></Button><Spacer /></HStack>
      </ZStack>
      <ScrollView><VStack alignment="leading" spacing={28} padding={{leading:16,trailing:16,top:28,bottom:32}}>
        <HStack><Spacer /><VStack spacing={8}><Icon symbol="camera.fill" color="#3478F6" /><Text font="title2">Momentra</Text><Text font="subheadline" foregroundStyle="#63636C">{ "v"+VERSION }</Text></VStack><Spacer /></HStack>
        <Group title="Data, hora e localização" note="As três informações ficam sempre juntas. Sem permissão ou sinal, a localização aparece como indisponível. As mudanças valem para as próximas fotos; vídeos não recebem carimbo.">
          <Row symbol="text.viewfinder" color="#3478F6"><Toggle title="Carimbo na foto" value={value.stamp} onChanged={next=>change({stamp:next})} toggleStyle="switch" /></Row><Rule />
          <Row symbol="textformat" color="#6854DE"><Picker title="Fonte" value={value.timestampFont} onChanged={next=>change({timestampFont:next})} pickerStyle="menu"><Text tag="system">Sistema</Text><Text tag="serif">Serifada</Text><Text tag="mono">Monoespaçada</Text></Picker></Row><Rule />
          <Row symbol="calendar" color="#F28B32"><Picker title="Data e hora" value={value.timestampFormat} onChanged={next=>change({timestampFormat:next})} pickerStyle="menu"><Text tag="numeric">Numérico</Text><Text tag="long">Data por extenso · hora h/min/s</Text></Picker></Row><Rule />
          <Row symbol="viewfinder" color="#3478F6"><Picker title="Canto do timestamp" value={value.timestampCorner} onChanged={next=>change({timestampCorner:next})} pickerStyle="menu"><Text tag="top-left">Superior esquerdo</Text><Text tag="top-right">Superior direito</Text><Text tag="bottom-left">Inferior esquerdo</Text><Text tag="bottom-right">Inferior direito</Text></Picker></Row>
        </Group>
        <Group title="Localização e mapa" note="GPS é uma opção do Momentra, não o estado da permissão do iOS. Ao ativar, o aparelho pode pedir autorização. Endereço e mapa usam serviços Apple; a foto não é enviada. Sem GPS válido, nenhum mapa é inventado.">
          <Row symbol="location.fill" color="#F28B32"><Toggle title="GPS" value={value.gps} onChanged={next=>{change({gps:next}); if (next) void locate(); else {fixRef.current=null;setFix(null)}}} toggleStyle="switch" /></Row><Rule />
          <Row symbol="map.fill" color="#4EBF64"><Toggle title="Mapa de satélite" value={value.map} onChanged={next=>change({map:next})} toggleStyle="switch" /></Row><Rule />
          <Row symbol="arrow.up.left.and.arrow.down.right" color="#3478F6"><Picker title="Tamanho do mapa" value={value.mapScale} onChanged={next=>change({mapScale:next})} pickerStyle="menu"><Text tag="small">Pequeno</Text><Text tag="medium">Médio</Text><Text tag="large">Grande</Text></Picker></Row><Rule />
          <Row symbol="viewfinder" color="#3478F6"><Picker title="Canto do mapa" value={value.mapCorner} onChanged={next=>change({mapCorner:next})} pickerStyle="menu"><Text tag="top-left">Superior esquerdo</Text><Text tag="top-right">Superior direito</Text><Text tag="bottom-left">Inferior esquerdo</Text><Text tag="bottom-right">Inferior direito</Text></Picker></Row>
        </Group>
        <Group title="Imagem ou logotipo" note="Escolha a imagem em Padrão, na lateral da câmera. A proporção da arte é preservada.">
          <Row symbol="photo.fill" color="#4EBF64"><Picker title="Canto da imagem" value={value.logoCorner} onChanged={next=>change({logoCorner:next})} pickerStyle="menu"><Text tag="top-left">Superior esquerdo</Text><Text tag="top-right">Superior direito</Text><Text tag="bottom-left">Inferior esquerdo</Text><Text tag="bottom-right">Inferior direito</Text></Picker></Row>
        </Group>
        <Group title="Armazenamento" note="Ativado permite salvar manualmente no Fotos; não salva automaticamente nem indica permissão do iOS. Desativado bloqueia Salvar e Salvar vídeo, sem apagar cópias anteriores. As capturas continuam locais no Momentra, não na nuvem.">
          <Row symbol="photo.on.rectangle" color="#4EBF64"><Toggle title="Cópia na galeria Fotos" value={value.allowGallery} onChanged={next=>change({allowGallery:next})} toggleStyle="switch" /></Row>
        </Group>
        <Group title="Conta"><VStack alignment="leading" padding={18}><GoogleAccount /></VStack></Group>
        <Text font="caption" foregroundStyle="#63636C" padding={{leading:18,trailing:18}} accessibilityIdentifier="momentra.cloud-unavailable">Google Fotos e armazenamento somente na nuvem ainda não estão disponíveis. Nenhuma foto é enviada ao Google. A captura e o carimbo usam armazenamento local; os arquivos permanecem no Momentra.</Text>
        <Text font="caption" foregroundStyle="#63636C" padding={{leading:18,trailing:18}}>Momentra · As opções acima são funções reais do aplicativo. Permissões do sistema são solicitadas apenas ao usar o recurso correspondente.</Text>
      </VStack></ScrollView>
    </VStack></NavigationStack>
  }
  async function openSettings() { await run(async()=>{setShowGoogleIntro(false);Storage.set("momentra.google.intro.v1",true);await Navigation.present({element:<TimestampPage />})}) }
  async function chooseProfile() {
    await run(async () => {
      const selected = await Dialog.actionSheet({title:"Escolha um padrão",actions:PROFILE_IDS.map(id=>({label:id+(id === settingsRef.current.profile ? " ✓" : "")})),cancelButton:true})
      if (selected === null) return
      update({...settingsRef.current,profile:PROFILE_IDS[selected]}); say("Padrão "+PROFILE_IDS[selected]+" selecionado")
    })
  }
  async function save() {
    await run(async () => {
      if (!settingsRef.current.allowGallery) { say("Galeria desativada. Foto preservada no armazenamento local do Momentra; não está na nuvem."); return }
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
  function liveKey(options: Settings, current: Fix | null) {
    return options.gps && current ? [current.latitude,current.longitude,current.timestamp,options.map].join(":") : ""
  }
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
        void enrich(current,JSON.parse(JSON.stringify(options))).then(extra=>{
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

  function SideButton(props: {title: string; symbol: string; action: () => void; disabled?: boolean; value?:string; hint?:string}) {
    return <Button {...circularControl()} action={props.action} disabled={busy || props.disabled} buttonStyle="plain"
      accessibilityLabel={props.title} accessibilityValue={props.value} accessibilityHint={props.hint}>
      <Image systemName={props.symbol} font="title3" frame={{width:44,height:44}} />
    </Button>
  }
  return <NavigationStack preferredColorScheme="dark" onCameraCaptureEvent={{isEnabled:!!camera && !closing,primaryAction:event=>{if(event.phase === "ended") void shutter()}}}>
    <GeometryReader>{geometry => {
      const width = geometry.size.width, height = geometry.size.height
      const layout = cameraLayout(width,height,mode === "video" ? "16:9" : settings.aspectRatio), compact = layout.compact
      const currentFix=settings.gps ? validFix(fix,liveNow) : null
      const assets=liveAssets?.key===liveKey(settings,currentFix) && currentFix ? liveAssets : null
      const logoPath=settings.profiles[settings.profile].logoPath
      if (logoCache.current.path!==logoPath) logoCache.current={path:logoPath,image:logoPath ? UIImage.fromFile(logoPath) : null}
      const liveRecord:CaptureRecord={id:"live-preview",original:"",file:"",capturedAt:liveNow,profile:settings.profile,stamped:false,saved:false,fix:currentFix,address:assets?.address??"",warnings:[]}

      return <VStack spacing={layout.gap} background="black" foregroundStyle="white" frame={{width,height}}>
        <ZStack frame={{width:layout.viewWidth,height:layout.viewHeight}}>
          {camera ? <CaptureVideoPreviewView session={camera.session} videoDevice={camera.device} videoGravity="resizeAspectFill" frame={{width:layout.viewWidth,height:layout.viewHeight}} masksToBounds /> : <Text font="callout">{status}</Text>}
          {camera && mode === "photo" && settings.stamp && !preview ? <Canvas opaque={false} frame={{width:layout.viewWidth,height:layout.viewHeight}} accessibilityIdentifier="momentra.live-overlay" accessibilityHidden draw={ctx=>drawStamp(ctx,layout.viewWidth,layout.viewHeight,settings,liveRecord,settings.map && assets?.map ? {image:assets.map} : null,logoCache.current.image ? {image:logoCache.current.image} : null,true)} /> : null}
          {preview && previewImage ? <Image image={previewImage} resizable scaleToFit background="black" frame={{width:layout.viewWidth*0.72,height:layout.viewHeight*0.72}} /> : null}
          <HStack alignment="center">
            <GlassEffectContainer><ScrollView frame={{width:layout.railWidth,maxHeight:layout.railHeight}}>
              <VStack spacing={6} padding={2} accessibilityElement="contain">
                <SideButton title={settings.profile} symbol="square.stack" disabled={mode === "video"} hint="Escolher padrão do carimbo" action={()=>{void chooseProfile()}} />
                <SideButton title="Padrão" symbol="slider.horizontal.3" disabled={mode === "video"} hint="Editar título, observação e logotipo" action={()=>{void editProfile()}} />
                <SideButton title={settings.stamp ? "Carimbo ✓" : "Sem carimbo"} symbol="text.viewfinder" disabled={mode === "video"} value={settings.stamp ? "Ligado" : "Desligado"} action={()=>update({...settingsRef.current,stamp:!settingsRef.current.stamp})} />
              </VStack>
            </ScrollView></GlassEffectContainer>
            <Spacer />
            <GlassEffectContainer><ScrollView frame={{width:layout.railWidth,maxHeight:layout.railHeight}}>
              <VStack spacing={6} padding={2} accessibilityElement="contain">
                <SideButton title={settings.gps ? "GPS ✓" : "GPS"} symbol="location" disabled={mode === "video"} value={settings.gps ? "Ligado" : "Desligado"} action={()=>{void gpsMenu()}} />
                <SideButton title={torch ? "Luz ✓" : "Luz"} symbol="flashlight.on.fill" disabled={!camera?.device.hasTorch} value={torch ? "Ligada" : "Desligada"} action={()=>{void run(async()=>{await cameraRef.current!.device.setTorchMode(torch ? "off" : "on");setTorch(!torch)})}} />
                <SideButton title="Recentes" symbol={mode === "video" ? "video" : "photo.on.rectangle"} action={()=>{if (mode === "video") void videoHistory(); else void history()}} />
              </VStack>
            </ScrollView></GlassEffectContainer>
          </HStack>
          <VStack spacing={0} frame={{width:layout.viewWidth,height:layout.viewHeight}}>
        <GlassEffectContainer><HStack spacing={Math.max(4,(layout.viewWidth-176)/5)} frame={{height:layout.toolbar}}>
          <Button buttonStyle="plain" {...circularControl()} disabled={busy || mode === "video"} accessibilityLabel="Flash" accessibilityValue={flash} action={()=>{void flashMenu()}}><Image systemName={flash === "off" ? "bolt.slash.fill" : flash === "auto" ? "bolt.badge.a" : "bolt.fill"} foregroundStyle={flash === "off" ? "white" : "#FFD60A"} font="title3" frame={{width:44,height:44}} /></Button>
          <Button buttonStyle="plain" {...circularControl()} disabled={busy || mode === "video"} accessibilityLabel="Temporizador" accessibilityValue={timer ? timer+" segundos" : "Desligado"} action={()=>{void timerMenu()}}><VStack spacing={0} frame={{width:44,height:44}}><Image systemName="timer" font="title3" /><Text font="caption2">{timer ? timer+"s" : ""}</Text></VStack></Button>
          <Button title={settings.aspectRatio} buttonStyle="plain" {...circularControl()} disabled={busy || mode === "video"} accessibilityLabel="Proporção" action={()=>{void ratioMenu()}} font="caption" />
          <Button buttonStyle="plain" {...circularControl()} disabled={busy} accessibilityLabel="Configurações" action={()=>{void openSettings()}}><Image systemName="gearshape" font="title3" frame={{width:44,height:44}} /></Button>
        </HStack></GlassEffectContainer>
            <Spacer />
        <HStack spacing={8} frame={{height:layout.status}} padding={{leading:12,trailing:12}}>
          <ScrollView><VStack alignment="leading" spacing={2}><Text font="caption2" foregroundStyle="#D0D0D0">{status}</Text>{showGoogleIntro ? <Button title="Google opcional · configurar" font="caption2" buttonStyle="plain" disabled={busy} action={()=>{void openSettings()}} /> : null}</VStack></ScrollView>
          {mode === "photo" ? <Button {...circularControl()} accessibilityLabel="Exportar" buttonStyle="plain" disabled={!last || busy} action={()=>{void exportFiles()}}><Image systemName="square.and.arrow.up" font="title3" frame={{width:44,height:44}} /></Button> : null}
          <Button {...circularControl()} buttonStyle="plain" disabled={busy} accessibilityLabel="Fechar" action={()=>{void closeCamera()}}><Image systemName="xmark" font="title3" frame={{width:44,height:44}} /></Button>
        </HStack>
          </VStack>
        </ZStack>
        <HStack frame={{width:Math.min(width-32,380),height:layout.shutter}}>
          <Button {...circularControl()} buttonStyle="plain" accessibilityLabel={preview ? "Câmera" : "Prévia"} disabled={busy || mode === "video" || (!preview && !last)} action={()=>{if (preview && !camera) void run(restoreCamera); else setPreview(!preview)}}>
            {previewImage ? <Image image={previewImage} resizable scaleToFill frame={{width:44,height:44}} cornerRadius={22} masksToBounds /> : <Image systemName="photo" font="title3" frame={{width:44,height:44}} />}
          </Button>
          <Spacer />
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
          <Button {...circularControl()} buttonStyle="plain" accessibilityLabel={mode === "photo" ? last?.saved ? "Salva ✓" : "Salvar" : lastVideo?.saved ? "Vídeo salvo ✓" : "Salvar vídeo"}
            disabled={!settings.allowGallery || busy || (mode === "photo" ? !last || last.saved : !lastVideo || lastVideo.saved)} action={()=>{if (mode === "photo") void save(); else void saveVideo()}}>
            <Image systemName={(mode === "photo" ? last?.saved : lastVideo?.saved) ? "checkmark.circle" : "square.and.arrow.down"} font="title3" frame={{width:44,height:44}} />
          </Button>
        </HStack>
        <Picker title="Modo de captura" value={mode} onChanged={(next: "video" | "photo")=>{void changeMode(next)}} pickerStyle="segmented" disabled={initializing || busy || recording} frame={{width:Math.min(width-48,280),height:layout.mode}} cornerRadius={24} accessibilityLabel="Modo de captura">
          <Text tag="video">Vídeo</Text><Text tag="photo">Câmera</Text>
        </Picker>
      </VStack>
    }}</GeometryReader>
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

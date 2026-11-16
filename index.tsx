import {
  Button, CaptureVideoPreviewView, HStack, VStack, ZStack, Text, Image,
  Navigation, NavigationStack, Script, Path, FileManager, Photos,
  useEffect, useRef, useState,
} from "scripting"

// Momentra 0.1.0 — prototype. Real iPhone validation required.
// Camera Control requires an active preview and a working capture event.
let session: AVCaptureSession | null = null
let alive = true

function CameraPage() {
  const [camera, setCamera] = useState<{ device: AVCaptureDevice; session: AVCaptureSession; output: AVCapturePhotoOutput } | null>(null)
  const cameraRef = useRef<{ device: AVCaptureDevice; session: AVCaptureSession; output: AVCapturePhotoOutput } | null>(null)
  const [status, setStatus] = useState("Iniciando câmera…")
  const [busy, setBusy] = useState(false)
  const busyRef = useRef(false)
  const [profile, setProfile] = useState("HAMOA")
  const [stamp, setStamp] = useState(true)
  const [lastPhoto, setLastPhoto] = useState<string | null>(null)
  const [showLast, setShowLast] = useState(false)

  async function start() {
    try {
      const device = AVCaptureDevice.default("video")
      if (!device) throw new Error("Câmera indisponível")
      const s = new AVCaptureSession()
      const output = new AVCapturePhotoOutput()
      session = s
      const input = new AVCaptureDeviceInput(device)
      s.configure(() => {
        s.sessionPreset = "photo"
        if (!s.canAddInput(input) || !s.canAddOutput(output)) throw new Error("Falha na configuração")
        s.addInput(input)
        s.addOutput(output)
      })
      await s.startRunning()
      if (!alive) { await s.stopRunning(); s.dispose(); return }
      const state = { device, session: s, output }
      cameraRef.current = state
      setCamera(state)
      setStatus("Pronta para fotografar")
    } catch (error) {
      setStatus(String(error))
    }
  }

  async function capture() {
    if (busyRef.current || !cameraRef.current) return
    busyRef.current = true
    setBusy(true)
    try {
      const folder = Path.join(FileManager.documentsDirectory, "Momentra")
      await FileManager.createDirectory(folder, true)
      const file = Path.join(folder, "momentra-" + Date.now() + ".jpg")
      await cameraRef.current.output.capturePhoto({ codec: "jpeg", photoFile: file })
      if (!alive) return
      setLastPhoto(file)
      setStatus("Foto capturada • " + profile + (stamp ? " • carimbo pendente" : ""))
      // Deliberately do not claim the stamp was burned into the pixels.
      // The overlay pipeline, GPS, reverse geocoding and satellite map are next.
    } catch (error) {
      if (alive) setStatus("Falha: " + String(error))
    } finally {
      busyRef.current = false
      if (alive) setBusy(false)
    }
  }

  async function save() {
    if (!lastPhoto) return
    try {
      const ok = await Photos.savePhoto(lastPhoto, { shouldMoveFile: false })
      setStatus(ok ? "Salva no Fotos" : "Não foi possível salvar")
    } catch (error) { setStatus(String(error)) }
  }

  useEffect(() => {
    void start()
    return () => { cameraRef.current = null }
  }, [])

  const cycle = () => setProfile(profile === "HAMOA" ? "PIRESCO" : profile === "PIRESCO" ? "PESSOAL" : "HAMOA")

  return <NavigationStack onCameraCaptureEvent={{
    isEnabled: !!camera,
    primaryAction: event => { if (event.phase === "ended") void capture() },
  }}>
    <VStack spacing={8}>
      <Text font="headline">MOMENTRA</Text>
      <ZStack>
        {camera
          ? <CaptureVideoPreviewView session={camera.session} videoDevice={camera.device}
              videoGravity="resizeAspectFill" frame={{ height: 480 }} accessibilityLabel="Visor da câmera" />
          : <Text>{status}</Text>}
        <HStack spacing={12}>
          <VStack spacing={16}>
            <Button title={profile} action={cycle} />
            <Button title={stamp ? "Carimbo ON" : "Carimbo OFF"} action={() => setStamp(!stamp)} />
          </VStack>
          <VStack spacing={16}>
            <Button title="● Foto" action={() => { void capture() }} disabled={busy || !camera} />
            <Button title="Prévia" action={() => setShowLast(!showLast)} disabled={!lastPhoto} />
            <Button title="Salvar" action={() => { void save() }} disabled={!lastPhoto || busy} />
          </VStack>
        </HStack>
      </ZStack>
      <Text>{status}</Text>
      <Text>{stamp ? "Carimbo visual: em desenvolvimento" : "Carimbo desativado"}</Text>
      {showLast && lastPhoto ? <Image image={UIImage.fromFile(lastPhoto)!} resizable scaleToFit frame={{ height: 160 }} /> : null}
    </VStack>
  </NavigationStack>
}

async function main() {
  try { await Navigation.present({ element: <CameraPage />, modalPresentationStyle: "fullScreen" }) }
  finally {
    alive = false
    const old = session
    session = null
    if (old) { try { await old.stopRunning() } finally { old.dispose() } }
    Script.exit()
  }
}
void main()

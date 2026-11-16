import { Button, Image, VStack, Text, useEffect, useRef, useState } from 'scripting'
import type { CaptureRecord } from './core'
import { getGooglePhotosAvailability, getGooglePhotosIdentity, loginGooglePhotos, logoutGoogle } from './google_auth'
import { getMediaItem, listAppPhotos, uploadPersonalPhoto } from './google_photos'
import type { AppPhoto } from './google_photos'

/** Optional personal integration. Rendering never contacts Google or sends a photo. */
export function GooglePhotosPanel({ capture }: { capture: CaptureRecord | null }) {
  const [available, setAvailable] = useState<boolean | null>(null)
  const [account, setAccount] = useState(getGooglePhotosIdentity)
  const [busy, setBusy] = useState(false)
  const [message, setMessage] = useState('')
  const [items, setItems] = useState<AppPhoto[]>([])
  const [next, setNext] = useState<string | undefined>(undefined)
  const [loaded, setLoaded] = useState(false)
  const active = useRef(true), locked = useRef(false), listOwner = useRef<string | null>(null)
  function currentOwner() {
    const state = getGooglePhotosIdentity()
    return state.status === 'connected' && state.expiresAt > Date.now() ? state.identity.sub : null
  }
  function clearList() { listOwner.current = null; setItems([]); setNext(undefined); setLoaded(false) }
  useEffect(() => {
    active.current = true
    // Local Keychain status only; no polling of Google or background transmission.
    const refresh = () => {
      if (!active.current) return
      setAccount(getGooglePhotosIdentity())
      if (listOwner.current && listOwner.current !== currentOwner()) clearList()
    }
    const timer = setInterval(refresh, 1000)
    return () => { active.current = false; clearInterval(timer) }
  }, [])
  async function run(action: () => Promise<void>) {
    if (locked.current || !active.current) return
    locked.current = true; setBusy(true)
    try { await action() }
    catch { if (active.current) setMessage('Não foi possível concluir. Nenhum arquivo local foi removido. Confira a conexão e a sessão do Google Fotos.') }
    finally { locked.current = false; if (active.current) { setBusy(false); setAccount(getGooglePhotosIdentity()) } }
  }
  async function enabled() {
    const value = await getGooglePhotosAvailability()
    if (active.current) setAvailable(value)
    if (!value) { if (active.current) setMessage('Google Fotos pessoal ainda não está ativado no serviço. Nenhum login de Fotos ou envio foi iniciado.'); return false }
    return active.current
  }
  async function connect() {
    if (!await enabled()) return
    const answer = await Dialog.actionSheet({ title: 'Google Fotos para uso pessoal', message: 'Somente fotos pessoais, não uso profissional, empresarial ou de obras. Você declara esse uso? O login compartilha nome/e-mail com o Momentra e pede ao Google permissão para adicionar fotos e ler somente itens criados por este aplicativo (photoslibrary.appendonly e photoslibrary.readonly.appcreateddata). Nenhuma foto será enviada pelo login. A sessão fica no Chaves deste iPhone, expira e pode exigir reconexão.', actions: [{ label: 'Declaro uso pessoal e autorizo conectar' }], cancelButton: true })
    if (answer !== 0 || !active.current) return
    const state = await loginGooglePhotos()
    if (active.current) { setAccount(state); clearList(); setMessage('Google Fotos conectado. Nenhuma foto foi enviada. Escolha uma foto pessoal e confirme o envio manualmente.') }
  }
  function disconnect() {
    if (locked.current) return
    try { logoutGoogle(); setAccount(getGooglePhotosIdentity()); clearList(); setMessage('Identidade Google e Google Fotos removidos deste iPhone. Isso não revoga permissões na conta Google nem apaga fotos.'); }
    catch { setMessage('Não foi possível remover a sessão local. Tente novamente.'); }
  }
  async function sendSelected() {
    // Freeze the selected capture before the asynchronous confirmation.
    const selected = capture ? { ...capture } : null
    if (!selected) { setMessage('Escolha uma captura antes de enviar. Você deverá declarar que a foto é pessoal, independentemente do padrão.'); return }
    if (!await enabled()) return
    const current = getGooglePhotosIdentity()
    if (current.status !== 'connected' || current.expiresAt <= Date.now()) { setMessage('Conecte ou reconecte o Google Fotos antes de enviar.'); return }
    const answer = await Dialog.actionSheet({ title: 'Enviar esta foto ao Google Fotos?', message: 'Foto selecionada: ' + selected.id + '. Destino: Google Fotos de ' + (current.identity.email || current.identity.name || 'sua conta conectada') + '. Será enviada somente esta foto JPEG final, incluindo data, hora, localização, mapa e logotipo que estiverem visíveis no carimbo. Declaro que esta foto é pessoal e autorizo o envio. Limite: 20 MB. O arquivo local será preservado; não é armazenamento somente na nuvem.', actions: [{ label: 'Confirmar envio desta foto pessoal' }], cancelButton: true })
    if (answer !== 0 || !active.current) return
    const verified = getGooglePhotosIdentity()
    if (verified.status !== 'connected' || verified.identity.sub !== current.identity.sub) throw new Error('Conta alterada')
    const result = await uploadPersonalPhoto(selected)
    if (active.current) setMessage(result.message)
  }
  async function load(more: boolean) {
    if (!await enabled()) return
    const current = getGooglePhotosIdentity()
    if (current.status !== 'connected' || current.expiresAt <= Date.now()) { setItems([]); setNext(undefined); setLoaded(false); setMessage('Reconecte o Google Fotos para consultar as fotos.'); return }
    if (more && listOwner.current !== current.identity.sub) {
      clearList(); setMessage('A conta mudou. Consulte a lista novamente antes de carregar mais.'); return
    }
    const page = await listAppPhotos(more ? next : undefined)
    if (!active.current) return
    const verified = getGooglePhotosIdentity()
    if (verified.status !== 'connected' || verified.identity.sub !== current.identity.sub) throw new Error('Conta alterada')
    listOwner.current = current.identity.sub
    setItems(previous => [...new Map([...(more ? previous : []), ...page.items].map(item => [item.id, item])).values()])
    setNext(page.nextPageToken); setLoaded(true); setMessage('Lista atualizada. Somente fotos criadas pelo Momentra; não é a biblioteca completa do Google Fotos.')
  }
  async function refreshItem(item: AppPhoto, external: boolean) {
    if (!await enabled()) return
    const owner = currentOwner()
    if (!owner || listOwner.current !== owner) { clearList(); setMessage('A sessão mudou. Consulte a lista novamente.'); return }
    // Fetch by ID each time: never rely on saved or expired base URLs.
    const fresh = await getMediaItem(item.id)
    if (!active.current) return
    if (currentOwner() !== owner || listOwner.current !== owner) { clearList(); throw new Error('Conta alterada') }
    setItems(previous => previous.map(value => value.id === fresh.id ? fresh : value))
    if (!external) { setMessage('Miniatura renovada.'); return }
    if (!fresh.productUrl) { setMessage('O Google não forneceu um link para esta foto.'); return }
    if (!await Safari.openURL(fresh.productUrl)) setMessage('Não foi possível abrir a foto no navegador.')
  }
  const connected = account.status === 'connected' && account.expiresAt > Date.now()
  return <VStack alignment="leading" spacing={12} accessibilityIdentifier="momentra.google-photos-personal">
    <Text font="headline">Google Fotos · pessoal</Text>
    <Text font="caption">Opcional, somente para fotos pessoais. Não use para trabalho, empresas ou obras. O nome do padrão não determina a finalidade de uso; você deve declarar que cada foto é pessoal.</Text>
    <Button title="Privacidade do Momentra" disabled={busy} buttonStyle="bordered" action={() => { void run(async () => { if (!await Safari.openURL('https://momentra-auth.mrpires72.workers.dev/privacy')) setMessage('Não foi possível abrir a política de privacidade.'); }) }} />
    <Text font="caption">As fotos usam o espaço disponível da sua conta Google, compartilhado com outros serviços. Não compramos espaço nem ativamos assinatura. Se a cota acabar, o envio pode falhar; a cópia local permanece.</Text>
    <Text font="caption">Integração em teste (Testing): acesso limitado às contas autorizadas. A sessão não tem renovação automática e pode exigir novo login; autorizações de teste também podem expirar.</Text>
    <Text>{available === null ? 'Disponibilidade ainda não consultada' : available ? 'Serviço pessoal disponível' : 'Não ativado no serviço'}</Text>
    <Button title="Verificar disponibilidade" disabled={busy} buttonStyle="bordered" action={() => { void run(async () => { await enabled() }) }} />
    {available ? <Button title={connected ? 'Reconectar Google Fotos' : 'Conectar Google Fotos'} disabled={busy} buttonStyle="bordered" action={() => { void run(connect) }} /> : null}
    <Text font="caption">{connected ? 'Sessão conectada; consulte novamente se ela expirar.' : 'Google Fotos não conectado ou sessão expirada. O login de identidade é separado.'}</Text>
    {account.status === 'connected' || account.status === 'expired' ? <Button title="Desconectar Google" disabled={busy} buttonStyle="bordered" action={disconnect} /> : null}
    <Text font="caption">{capture ? 'Foto selecionada: ' + capture.id + ' · ' + capture.profile : 'Abra uma foto no histórico ou capture uma foto para selecionar o envio.'}</Text>
    <Button title="Enviar foto selecionada" disabled={busy || !available || !connected || !capture} buttonStyle="bordered" action={() => { void run(sendSelected) }} />
    <Text font="caption">Somente JPEG até 20 MB, sem vídeos nem envio automático. Originais e fotos finais continuam no Momentra. Miniaturas podem usar cache local do aplicativo. Não é um modo somente na nuvem.</Text>
    <Button title="Consultar minhas fotos" disabled={busy || !available || !connected} buttonStyle="bordered" action={() => { void run(() => load(false)) }} />
    {loaded && !items.length ? <Text font="caption">Nenhuma foto criada pelo Momentra nesta lista.</Text> : null}
    {(connected && listOwner.current === currentOwner() ? items : []).map(item => <VStack key={item.id} alignment="leading" spacing={6}>
      <Text>{item.filename || 'Foto pessoal'}</Text>
      {item.previewUrl && (item.previewExpiresAt ?? 0) > Date.now() ? <Image imageUrl={item.previewUrl} resizable scaleToFit frame={{height:180}} placeholder={<Text font="caption">Carregando miniatura…</Text>} onError={() => { if (active.current) setMessage('Miniatura indisponível. Toque em Renovar miniatura para tentar novamente.'); }} /> : <Text font="caption">Miniatura expirada ou indisponível. Renove para visualizar.</Text>}
      <Button title="Renovar miniatura" disabled={busy || !available || !connected} buttonStyle="bordered" action={() => { void run(() => refreshItem(item, false)) }} />
      {item.width && item.height ? <Text font="caption">{item.width + ' × ' + item.height}</Text> : null}
      <Button title="Abrir no Google Fotos" disabled={busy || !available || !connected} buttonStyle="bordered" action={() => { void run(() => refreshItem(item, true)) }} />
    </VStack>)}
    {next ? <Button title="Carregar mais fotos" disabled={busy || !available || !connected} buttonStyle="bordered" action={() => { void run(() => load(true)) }} /> : null}
    {message ? <Text font="caption">{message}</Text> : null}
  </VStack>
}

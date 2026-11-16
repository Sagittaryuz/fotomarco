// Scripting host globals. No client secret, tokens in Storage, or automatic browser launch.
export type GoogleIdentity = { sub: string; name: string; email: string }
export type GoogleIdentityStatus =
  | { status: 'signed-out' | 'unavailable' }
  | { status: 'connected' | 'expired'; identity: GoogleIdentity; expiresAt: number }
const CLIENT_ID = '486055841789-ogbp6b16gvl0nhtcdun8fvla56p5e0rc.apps.googleusercontent.com'
const BASE = 'https://momentra-auth.mrpires72.workers.dev'
const CALLBACK = 'scripting://oauth_callback/Momentra'
const KEY = 'momentra.google.identity.v1'
const PHOTOS_KEY = 'momentra.google.photos.personal.v1'
const IDENTITY_SCOPE = 'openid email profile'
const PHOTOS_SCOPE = IDENTITY_SCOPE + ' https://www.googleapis.com/auth/photoslibrary.appendonly https://www.googleapis.com/auth/photoslibrary.readonly.appcreateddata'
const FAILURE = 'Não foi possível conectar ao Google. Tente novamente.'
let generation = 0
let pending: Promise<GoogleIdentityStatus> | null = null
let pendingKind: 'identity' | 'photos' | null = null
const b64url = (data: Data) => data.toBase64String().replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '')
function identity(value: any): value is GoogleIdentity {
  return value && typeof value.sub === 'string' && value.sub.length > 0 && value.sub.length <= 255 && typeof value.name === 'string' && value.name.length <= 512 && typeof value.email === 'string' && value.email.length <= 320
}
// Local only, synchronous and safe for first render. Never prompts or requests the network.
function readStatus(key: string): GoogleIdentityStatus {
  try {
    const raw = Keychain.get(key)
    if (!raw) return { status: 'signed-out' }
    const saved = JSON.parse(raw)
    if (!identity(saved.account) || typeof saved.accessToken !== 'string' || !saved.accessToken || typeof saved.expiresAt !== 'number' || !Number.isFinite(saved.expiresAt)) return { status: 'unavailable' }
    if (key === PHOTOS_KEY && saved.scope !== PHOTOS_SCOPE) return { status: 'unavailable' }
    return { status: saved.expiresAt > Date.now() ? 'connected' : 'expired', identity: { sub: saved.account.sub, name: saved.account.name, email: saved.account.email }, expiresAt: saved.expiresAt }
  } catch { return { status: 'unavailable' } }
}
export function getGoogleIdentity(): GoogleIdentityStatus { return readStatus(KEY) }
export function getGooglePhotosIdentity(): GoogleIdentityStatus {
  const photos = readStatus(PHOTOS_KEY), account = readStatus(KEY)
  if ((photos.status === 'connected' || photos.status === 'expired') && (account.status === 'connected' || account.status === 'expired') && photos.identity.sub !== account.identity.sub) return { status: 'unavailable' }
  return photos
}
// Capability check, not consent or upload. Old production broker honestly reports false.
export async function getGooglePhotosAvailability(): Promise<boolean> {
  try {
    const response = await fetch(BASE + '/health', { handleRedirect: async () => null, timeout: 20 })
    if (!response.ok) return false
    const result = await response.json()
    return result.service === 'momentra-auth' && result.version >= 2 && result.capabilities?.photos === true
  } catch { return false }
}
// Call only from an explicit user login action. Concurrent callers share one consent flow.
function login(kind: 'identity' | 'photos'): Promise<GoogleIdentityStatus> {
  if (pending) return pendingKind === kind ? pending : Promise.reject(new Error('Conclua o login atual antes de iniciar outro.'))
  pendingKind = kind
  const attempt = generation
  pending = (async (): Promise<GoogleIdentityStatus> => {
    try {
      if (kind === 'photos' && !await getGooglePhotosAvailability()) throw new Error()
      if (attempt !== generation) throw new Error()
      const verifier = b64url(Crypto.generateSymmetricKey(256))
      const state = b64url(Crypto.generateSymmetricKey(256))
      const data = Data.fromString(verifier)
      if (!data) throw new Error()
      const oauth = new OAuth2({ consumerKey: CLIENT_ID, consumerSecret: '', authorizeUrl: BASE + '/authorize', accessTokenUrl: BASE + '/token', responseType: 'code', contentType: 'application/x-www-form-urlencoded' })
      oauth.accessTokenBasicAuthentification = false
      oauth.allowMissingStateCheck = false
      const credential = await oauth.authorize({ callbackURL: CALLBACK, scope: kind === 'photos' ? PHOTOS_SCOPE : IDENTITY_SCOPE, state, codeVerifier: verifier, codeChallenge: b64url(Crypto.sha256(data)), codeChallengeMethod: 'S256' })
      if (attempt !== generation || typeof credential.oauthToken !== 'string' || !credential.oauthToken || typeof credential.oauthTokenExpiresAt !== 'number' || !Number.isFinite(credential.oauthTokenExpiresAt) || credential.oauthTokenExpiresAt <= Date.now()) throw new Error()
      const response = await fetch('https://openidconnect.googleapis.com/v1/userinfo', { headers: { Authorization: 'Bearer ' + credential.oauthToken }, handleRedirect: async () => null, timeout: 20 })
      if (!response.ok) throw new Error()
      const profile = await response.json()
      const account = { sub: profile.sub, name: typeof profile.name === 'string' ? profile.name : '', email: profile.email_verified === true && typeof profile.email === 'string' ? profile.email : '' }
      if (!identity(account) || attempt !== generation || credential.oauthTokenExpiresAt <= Date.now()) throw new Error()
      const previous = readStatus(KEY)
      if (kind === 'photos' && (previous.status === 'connected' || previous.status === 'expired') && previous.identity.sub !== account.sub) throw new Error()
      // Switching the identity account cannot retain a usable token for another Photos owner.
      if (kind === 'identity') {
        const oldPhotos = readStatus(PHOTOS_KEY)
        if ((oldPhotos.status === 'connected' || oldPhotos.status === 'expired') && oldPhotos.identity.sub !== account.sub && !Keychain.remove(PHOTOS_KEY)) throw new Error()
      }
      if (!Keychain.set(kind === 'photos' ? PHOTOS_KEY : KEY, JSON.stringify({ accessToken: credential.oauthToken, expiresAt: credential.oauthTokenExpiresAt, account, scope: kind === 'photos' ? PHOTOS_SCOPE : IDENTITY_SCOPE }), { accessibility: 'unlocked_this_device', synchronizable: false })) throw new Error()
      return { status: 'connected', identity: account, expiresAt: credential.oauthTokenExpiresAt }
    } catch { throw new Error(FAILURE) }
  })().finally(() => { pending = null; pendingKind = null })
  return pending
}
export function loginGoogle(): Promise<GoogleIdentityStatus> { return login('identity') }
// Personal Photos only; call from explicit consent UI, never during capture/startup.
export function loginGooglePhotos(): Promise<GoogleIdentityStatus> { return login('photos') }
export type PhotosRequestOptions = { method?: 'GET' | 'POST'; headers?: Record<string,string>; body?: any; signal?: AbortSignal }
// Internal transport for google_photos. No credential getter; bearer never leaves this module.
export async function photosAuthorizedFetch(url: string, init: PhotosRequestOptions, expectedSub: string): Promise<Response> {
  try {
    const target = new URL(url), method = init.method ?? 'GET'
    const path = target.pathname
    const allowed = method === 'POST' ? (path === '/v1/uploads' || path === '/v1/mediaItems:batchCreate') : method === 'GET' && (path === '/v1/mediaItems' || /^\/v1\/mediaItems\/[A-Za-z0-9_-]+$/.test(path))
    if (!allowed || target.origin !== 'https://photoslibrary.googleapis.com' || target.username || target.password || target.hash || !expectedSub) throw new Error()
    if (method === 'POST' && target.search) throw new Error()
    for (const key of target.searchParams.keys()) if (!['pageSize','pageToken'].includes(key) || target.searchParams.getAll(key).length !== 1) throw new Error()
    const headers: Record<string,string> = {}
    for (const [key,value] of Object.entries(init.headers ?? {})) {
      if (!['content-type','x-goog-upload-protocol','x-goog-upload-content-type','x-goog-upload-file-name'].includes(key.toLowerCase())) throw new Error()
      headers[key] = value
    }
    const status = getGooglePhotosIdentity()
    if (status.status !== 'connected' || status.identity.sub !== expectedSub) throw new Error()
    const saved = JSON.parse(Keychain.get(PHOTOS_KEY) ?? 'null')
    if (!saved || saved.scope !== PHOTOS_SCOPE || saved.account?.sub !== expectedSub || saved.expiresAt <= Date.now() || !saved.accessToken) throw new Error()
    const attempt = generation
    const response = await fetch(target.toString(), { ...init, method, headers: { ...headers, Authorization: 'Bearer ' + saved.accessToken }, handleRedirect: async () => null, timeout: 20 })
    const current = getGooglePhotosIdentity()
    if (attempt !== generation || current.status !== 'connected' || current.identity.sub !== expectedSub || response.status >= 300 && response.status < 400) throw new Error()
    return response
  } catch { throw new Error('Não foi possível acessar o Google Fotos. Confira a conta e reconecte se necessário.') }
}
// Local sign-out, not Google permission revocation. Invalidates in-flight consent results.
export function logoutGoogle(): GoogleIdentityStatus {
  generation++
  let failed = false
  for (const key of [KEY, PHOTOS_KEY]) {
    try {
      // A Photos-only session may have no identity key. Absence is already signed out.
      if (Keychain.get(key) == null) continue
      Keychain.remove(key)
      if (Keychain.get(key) != null) failed = true
    } catch { failed = true }
  }
  if (failed) throw new Error('Não foi possível desconectar a conta neste iPhone.')
  return { status: 'signed-out' }
}

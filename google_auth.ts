// Scripting host globals. No client secret, tokens in Storage, or automatic browser launch.
export type GoogleIdentity = { sub: string; name: string; email: string }
export type GoogleIdentityStatus =
  | { status: 'signed-out' | 'unavailable' }
  | { status: 'connected' | 'expired'; identity: GoogleIdentity; expiresAt: number }
const CLIENT_ID = '486055841789-ogbp6b16gvl0nhtcdun8fvla56p5e0rc.apps.googleusercontent.com'
const BASE = 'https://momentra-auth.mrpires72.workers.dev'
const CALLBACK = 'scripting://oauth_callback/Momentra'
const KEY = 'momentra.google.identity.v1'
const FAILURE = 'Não foi possível conectar ao Google. Tente novamente.'
let generation = 0
let pending: Promise<GoogleIdentityStatus> | null = null
const b64url = (data: Data) => data.toBase64String().replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '')
function identity(value: any): value is GoogleIdentity {
  return value && typeof value.sub === 'string' && value.sub.length > 0 && value.sub.length <= 255 && typeof value.name === 'string' && value.name.length <= 512 && typeof value.email === 'string' && value.email.length <= 320
}
// Local only, synchronous and safe for first render. Never prompts or requests the network.
export function getGoogleIdentity(): GoogleIdentityStatus {
  try {
    const raw = Keychain.get(KEY)
    if (!raw) return { status: 'signed-out' }
    const saved = JSON.parse(raw)
    if (!identity(saved.account) || typeof saved.accessToken !== 'string' || !saved.accessToken || typeof saved.expiresAt !== 'number' || !Number.isFinite(saved.expiresAt)) return { status: 'unavailable' }
    return { status: saved.expiresAt > Date.now() ? 'connected' : 'expired', identity: { sub: saved.account.sub, name: saved.account.name, email: saved.account.email }, expiresAt: saved.expiresAt }
  } catch { return { status: 'unavailable' } }
}
// Call only from an explicit user login action. Concurrent callers share one consent flow.
export function loginGoogle(): Promise<GoogleIdentityStatus> {
  if (pending) return pending
  const attempt = generation
  pending = (async (): Promise<GoogleIdentityStatus> => {
    try {
      const verifier = b64url(Crypto.generateSymmetricKey(256))
      const state = b64url(Crypto.generateSymmetricKey(256))
      const data = Data.fromString(verifier)
      if (!data) throw new Error()
      const oauth = new OAuth2({ consumerKey: CLIENT_ID, consumerSecret: '', authorizeUrl: BASE + '/authorize', accessTokenUrl: BASE + '/token', responseType: 'code', contentType: 'application/x-www-form-urlencoded' })
      oauth.accessTokenBasicAuthentification = false
      oauth.allowMissingStateCheck = false
      const credential = await oauth.authorize({ callbackURL: CALLBACK, scope: 'openid email profile', state, codeVerifier: verifier, codeChallenge: b64url(Crypto.sha256(data)), codeChallengeMethod: 'S256' })
      if (attempt !== generation || typeof credential.oauthToken !== 'string' || !credential.oauthToken || typeof credential.oauthTokenExpiresAt !== 'number' || !Number.isFinite(credential.oauthTokenExpiresAt) || credential.oauthTokenExpiresAt <= Date.now()) throw new Error()
      const response = await fetch('https://openidconnect.googleapis.com/v1/userinfo', { headers: { Authorization: 'Bearer ' + credential.oauthToken } })
      if (!response.ok) throw new Error()
      const profile = await response.json()
      const account = { sub: profile.sub, name: typeof profile.name === 'string' ? profile.name : '', email: profile.email_verified === true && typeof profile.email === 'string' ? profile.email : '' }
      if (!identity(account) || attempt !== generation || credential.oauthTokenExpiresAt <= Date.now()) throw new Error()
      if (!Keychain.set(KEY, JSON.stringify({ accessToken: credential.oauthToken, expiresAt: credential.oauthTokenExpiresAt, account }), { accessibility: 'unlocked_this_device', synchronizable: false })) throw new Error()
      return { status: 'connected', identity: account, expiresAt: credential.oauthTokenExpiresAt }
    } catch { throw new Error(FAILURE) }
  })().finally(() => { pending = null })
  return pending
}
// Local sign-out, not Google permission revocation. Invalidates in-flight consent results.
export function logoutGoogle(): GoogleIdentityStatus {
  generation++
  try { if (!Keychain.remove(KEY)) throw new Error() }
  catch { throw new Error('Não foi possível desconectar a conta neste iPhone.') }
  return { status: 'signed-out' }
}

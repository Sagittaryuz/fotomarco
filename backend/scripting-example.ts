// Integration example only: not imported into Momentra and not called automatically.
// Globals OAuth2, Crypto, Data, Keychain and fetch are documented Scripting APIs.
const CLIENT_ID = '486055841789-ogbp6b16gvl0nhtcdun8fvla56p5e0rc.apps.googleusercontent.com'
const BASE = 'https://momentra-auth.mrpires72.workers.dev'
const CALLBACK = 'scripting://oauth_callback/Momentra'
const KEY = 'momentra.google.identity.v1'
const b64url = (data: Data) => data.toBase64String().replace(/\+/g,'-').replace(/\//g,'_').replace(/=+$/,'')

export async function connectGoogleIdentity() {
  // Fresh CSPRNG values per attempt. Never store the verifier or print credential/errors.
  const verifier = b64url(Crypto.generateSymmetricKey(256))
  const state = b64url(Crypto.generateSymmetricKey(256))
  const input = Data.fromString(verifier)
  if (!input) throw new Error('Não foi possível iniciar autenticação segura')
  const challenge = b64url(Crypto.sha256(input))
  const oauth = new OAuth2({consumerKey:CLIENT_ID,consumerSecret:'',authorizeUrl:BASE+'/authorize',accessTokenUrl:BASE+'/token',responseType:'code',contentType:'application/x-www-form-urlencoded'})
  oauth.accessTokenBasicAuthentification = false
  oauth.allowMissingStateCheck = false
  const credential = await oauth.authorize({callbackURL:CALLBACK,scope:'openid email profile',state,codeVerifier:verifier,codeChallenge:challenge,codeChallengeMethod:'S256'})
  if (!credential.oauthToken || !credential.oauthTokenExpiresAt || credential.oauthTokenExpiresAt <= Date.now()) throw new Error('Sessão Google inválida ou expirada')
  const response = await fetch('https://openidconnect.googleapis.com/v1/userinfo',{headers:{Authorization:'Bearer '+credential.oauthToken}})
  if (!response.ok) throw new Error('Não foi possível verificar a identidade Google')
  const profile = await response.json()
  if (typeof profile.sub !== 'string' || !profile.sub) throw new Error('Identidade Google inválida')
  const account = {sub:profile.sub,name:typeof profile.name==='string'?profile.name:'',email:profile.email_verified === true && typeof profile.email === 'string' ? profile.email : ''}
  // Store only what is needed. No refresh token exists in this identity-only release.
  const stored = Keychain.set(KEY,JSON.stringify({accessToken:credential.oauthToken,expiresAt:credential.oauthTokenExpiresAt,account}),{accessibility:'unlocked_this_device',synchronizable:false})
  if (!stored) throw new Error('Não foi possível guardar a sessão no Chaves do iPhone')
  return account
}
export function disconnectGoogleIdentityLocally() { Keychain.remove(KEY) }
// Caller catches failures and shows a generic cancellation/failure message, never raw errors.
// This removes local state only; it is not provider-side revocation.
// On expiration, request a new login. Do not invoke renewAccessToken in this release.

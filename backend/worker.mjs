// Momentra identity-only OAuth bridge. No dependencies, storage, refresh or uploads.
// Never log requests, authorization codes, secrets, or token responses.
const ORIGIN = 'https://momentra-auth.mrpires72.workers.dev';
const CALLBACK = ORIGIN + '/callback';
const APP_CALLBACK = 'scripting://oauth_callback/Momentra';
const SCOPE = 'openid email profile';
const encoder = new TextEncoder();
const decoder = new TextDecoder();
const SAFE = {'Cache-Control':'no-store, max-age=0','Pragma':'no-cache','Referrer-Policy':'no-referrer','X-Content-Type-Options':'nosniff','Content-Security-Policy':"default-src 'none'; frame-ancestors 'none'",'Strict-Transport-Security':'max-age=31536000'};
class Failure extends Error { constructor(code,status=400) { super(code); this.status=status; } }
function json(value,status=200) { return new Response(JSON.stringify(value),{status,headers:{...SAFE,'Content-Type':'application/json'}}); }
function redirect(url) { return new Response(null,{status:302,headers:{...SAFE,Location:url}}); }
function b64(bytes) { return btoa(String.fromCharCode(...bytes)).replaceAll('+','-').replaceAll('/','_').replace(/=+$/,''); }
function unb64(s) { if (!/^[A-Za-z0-9_-]+$/.test(s)) throw new Failure('invalid_request'); return Uint8Array.from(atob(s.replaceAll('-','+').replaceAll('_','/')),c=>c.charCodeAt(0)); }
function unique(params,allowed) { for (const key of params.keys()) if (!allowed.includes(key) || params.getAll(key).length!==1) throw new Failure('invalid_request'); }
function required(params,key,pattern,max=1024) { const s=params.get(key);if(!s || s.length>max || !pattern.test(s))throw new Failure('invalid_request'); return s; }
function now() { return Math.floor(Date.now()/1000); }
async function keyFor(env) { if(!env.BROKER_SECRET || !/^[A-Za-z0-9_-]{43}$/.test(env.BROKER_SECRET))throw new Failure('temporarily_unavailable',503);const raw=unb64(env.BROKER_SECRET);if(raw.length!==32)throw new Failure('temporarily_unavailable',503);return crypto.subtle.importKey('raw',raw,'AES-GCM',false,['encrypt','decrypt']); }
async function seal(env,purpose,payload) {
  const iv=crypto.getRandomValues(new Uint8Array(12));
  const encrypted=await crypto.subtle.encrypt({name:'AES-GCM',iv,additionalData:encoder.encode('momentra-v1:'+purpose)},await keyFor(env),encoder.encode(JSON.stringify(payload)));
  return 'v1.'+b64(iv)+'.'+b64(new Uint8Array(encrypted));
}
async function open(env,purpose,token) {
  try {
    if(typeof token!=='string'||token.length>4096)throw Error();
    const parts=token.split('.');if(parts.length!==3||parts[0]!=='v1')throw Error();
    const iv=unb64(parts[1]);if(iv.length!==12)throw Error();
    const raw=await crypto.subtle.decrypt({name:'AES-GCM',iv,additionalData:encoder.encode('momentra-v1:'+purpose)},await keyFor(env),unb64(parts[2]));
    const data=JSON.parse(decoder.decode(raw));
    if(!Number.isInteger(data.exp)||data.exp<=now()||data.exp>now()+600||data.client!==env.GOOGLE_CLIENT_ID)throw Error();
    return data;
  } catch { throw new Failure('invalid_grant'); }
}
async function limited(request,env) {
  // Fail closed: this binding must be configured for the dedicated Worker.
  if(!env.AUTH_RATE_LIMITER?.limit)throw new Failure('temporarily_unavailable',503);
  const ip=request.headers.get('CF-Connecting-IP');if(!ip)throw new Failure('invalid_request');
  const hash=b64(new Uint8Array(await crypto.subtle.digest('SHA-256',encoder.encode(ip))));
  if(!(await env.AUTH_RATE_LIMITER.limit({key:'momentra:'+hash})).success)throw new Failure('slow_down',429);
}
async function boundedText(request,max) {
  if(Number(request.headers.get('Content-Length'))>max)throw new Failure('invalid_request',413);
  const reader=request.body?.getReader();if(!reader)return '';
  const chunks=[];let size=0;
  while(true){const {done,value}=await reader.read();if(done)break;size+=value.length;if(size>max){await reader.cancel();throw new Failure('invalid_request',413);}chunks.push(value);}
  const data=new Uint8Array(size);let i=0;for(const chunk of chunks){data.set(chunk,i);i+=chunk.length;}return decoder.decode(data);
}
function client(params,env) { if(params.get('client_id')!==env.GOOGLE_CLIENT_ID||params.get('redirect_uri')!==APP_CALLBACK)throw new Failure('invalid_request'); }
async function authorize(url,env) {
  const p=url.searchParams;
  unique(p,['client_id','redirect_uri','response_type','scope','state','code_challenge','code_challenge_method']);
  client(p,env);
  if(p.get('response_type')!=='code'||p.get('code_challenge_method')!=='S256')throw new Failure('invalid_request');
  const scopes=(p.get('scope')??'').trim().split(/\s+/);if(scopes.length!==3||new Set(scopes).size!==3||scopes.some(s=>!SCOPE.split(' ').includes(s)))throw new Failure('invalid_scope');
  const state=required(p,'state',/^[\x21-\x7E]+$/,256);
  if(state.length<32)throw new Failure('invalid_request');
  const challenge=required(p,'code_challenge',/^[A-Za-z0-9_-]{43}$/,43);
  const envelope=await seal(env,'state',{client:env.GOOGLE_CLIENT_ID,state,challenge,exp:now()+600});
  const google=new URL('https://accounts.google.com/o/oauth2/v2/auth');
  google.search=new URLSearchParams({client_id:env.GOOGLE_CLIENT_ID,redirect_uri:CALLBACK,response_type:'code',scope:SCOPE,state:envelope,code_challenge:challenge,code_challenge_method:'S256',access_type:'online',prompt:'select_account'}).toString();
  return redirect(google.toString());
}
async function callback(url,env) {
  const p=url.searchParams;
  unique(p,['code','state','error','error_description','error_uri','scope','authuser','prompt','hd','iss']);
  if(p.has('iss') && p.get('iss')!=='https://accounts.google.com')throw new Failure('invalid_request');
  const state=await open(env,'state',p.get('state'));
  const target=new URL(APP_CALLBACK);target.searchParams.set('state',state.state);
  if(p.has('error')) {
    if(p.has('code'))throw new Failure('invalid_request');
    target.searchParams.set('error',p.get('error')==='access_denied'?'access_denied':'server_error');
  } else {
    const code=required(p,'code',/^[\x21-\x7E]+$/,2048);
    // Authenticated wrapper ensures /token cannot exchange arbitrary non-PKCE Google codes.
    target.searchParams.set('code',await seal(env,'code',{client:env.GOOGLE_CLIENT_ID,code,challenge:state.challenge,exp:Math.min(state.exp,now()+120)}));
  }
  return redirect(target.toString());
}
async function token(request,env,fetcher) {
  if(!(request.headers.get('Content-Type')??'').toLowerCase().startsWith('application/x-www-form-urlencoded'))throw new Failure('invalid_request',415);
  const p=new URLSearchParams(await boundedText(request,8192));
  unique(p,['grant_type','client_id','client_secret','redirect_uri','code','code_verifier']);
  if(p.get('grant_type')!=='authorization_code')throw new Failure('unsupported_grant_type');
  client(p,env);
  // A fixed PUBLIC placeholder is accepted for OAuth2 hosts requiring a nonempty consumerSecret.
  if(p.has('client_secret')&&!['','public-client'].includes(p.get('client_secret')))throw new Failure('invalid_client');
  const verifier=required(p,'code_verifier',/^[A-Za-z0-9._~-]{43,128}$/,128);
  const data=await open(env,'code',p.get('code'));
  const challenge=b64(new Uint8Array(await crypto.subtle.digest('SHA-256',encoder.encode(verifier))));
  if(challenge!==data.challenge)throw new Failure('invalid_grant');
  const body=new URLSearchParams({grant_type:'authorization_code',client_id:env.GOOGLE_CLIENT_ID,client_secret:env.GOOGLE_CLIENT_SECRET,redirect_uri:CALLBACK,code:data.code,code_verifier:verifier});
  let result;
  try {
    const response=await fetcher('https://oauth2.googleapis.com/token',{method:'POST',headers:{'Content-Type':'application/x-www-form-urlencoded'},body,redirect:'manual',signal:AbortSignal.timeout(10000)});
    if(!response.ok)throw new Failure(response.status>=500?'temporarily_unavailable':'invalid_grant',response.status>=500?502:400);
    result=JSON.parse(await boundedText(response,32768));
  }catch(error){if(error instanceof Failure)throw error;throw new Failure('temporarily_unavailable',502);}
  if(typeof result.access_token!=='string'||result.access_token.length>8192||result.token_type!=='Bearer'||!Number.isFinite(result.expires_in)||result.expires_in<=0)throw new Failure('temporarily_unavailable',502);
  // Drop refresh/id tokens and any unapproved scopes; identity is read from Google's userinfo endpoint by the client.
  if(typeof result.scope!=='string'||!result.scope.trim())throw new Failure('temporarily_unavailable',502);
  const returned=result.scope.split(/\s+/);
  const allowed=new Set(['openid','email','profile','https://www.googleapis.com/auth/userinfo.email','https://www.googleapis.com/auth/userinfo.profile']);
  if(returned.some(s=>!allowed.has(s)))throw new Failure('invalid_scope');
  return json({access_token:result.access_token,token_type:'Bearer',expires_in:result.expires_in,scope:SCOPE});
}
export async function handle(request,env,fetcher=fetch) {
  try {
    const url=new URL(request.url);
    if(url.origin!==ORIGIN||url.username||url.password||request.url.length>8192)throw new Failure('invalid_request');
    if(url.pathname==='/health'&&request.method==='GET')return json({service:'momentra-auth',version:1,scope:'identity-only'});
    if(!['/authorize','/callback','/token'].includes(url.pathname))return json({error:'not_found'},404);
    if(request.method!==(url.pathname==='/token'?'POST':'GET'))return json({error:'method_not_allowed'},405);
    if(!/^[A-Za-z0-9_-]+\.apps\.googleusercontent\.com$/.test(env.GOOGLE_CLIENT_ID??'')||!env.GOOGLE_CLIENT_SECRET)throw new Failure('temporarily_unavailable',503);
    if(url.pathname==='/token'&&url.search)throw new Failure('invalid_request');
    await limited(request,env);
    if(url.pathname==='/authorize')return await authorize(url,env);
    if(url.pathname==='/callback')return await callback(url,env);
    return await token(request,env,fetcher);
  }catch(error){return json({error:error instanceof Failure?error.message:'temporarily_unavailable'},error instanceof Failure?error.status:503);}
}
export default {fetch(request,env) { return handle(request,env); }};

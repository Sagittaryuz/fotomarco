/** Public landing page contains only opaque invitation IDs, never credentials. */
export function invitationLanding(request) {
  const headers = { 'content-type': 'text/html; charset=utf-8', 'cache-control': 'no-store',
    'referrer-policy': 'no-referrer', 'x-content-type-options': 'nosniff',
    'content-security-policy': "default-src 'none'; style-src 'unsafe-inline'; base-uri 'none'; frame-ancestors 'none'" };
  if (request.method !== 'GET') return new Response('Método não permitido.', { status: 405, headers });
  const url = new URL(request.url);
  const items = [...url.searchParams];
  const uuid = value => typeof value === 'string' && /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(value);
  const org = url.searchParams.get('organization');
  const invitation = url.searchParams.get('invitation');
  if (items.length !== 2 || !uuid(org) || !uuid(invitation) || url.searchParams.getAll('organization').length !== 1 ||
      url.searchParams.getAll('invitation').length !== 1) return new Response('Convite inválido.', { status: 400, headers });
  const target = `momentra://business/invite?organization=${org.toLowerCase()}&amp;invitation=${invitation.toLowerCase()}`;
  const html = `<!doctype html><html lang="pt-BR"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Convite Photomark</title><style>body{background:#000;color:#fff;font:17px -apple-system,BlinkMacSystemFont,sans-serif;margin:0;padding:12vh 24px;text-align:center}main{max-width:420px;margin:auto}a{display:block;margin:30px auto;padding:17px;border-radius:30px;background:#ffd60a;color:#000;font-weight:700;text-decoration:none}p{color:#bbb;line-height:1.5}</style></head><body><main><h1>Convite para o Photomark</h1><p>Abra o aplicativo e entre com o e-mail que recebeu o convite para confirmar seu acesso.</p><a href="${target}">Abrir no Photomark</a><p>Se o aplicativo ainda não estiver instalado neste iPhone, solicite as instruções de instalação ao administrador da equipe.</p></main></body></html>`;
  return new Response(html, { status: 200, headers });
}

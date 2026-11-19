const crypto = require('node:crypto');
const { issueSignedToken, presignUrl } = require('@vercel/blob');
const { serveIpa, serveBlobIpa } = require('../lib/ipa');

function matches(value, expected) {
  if (typeof value !== 'string' || typeof expected !== 'string' || !expected) return false;
  const a = Buffer.from(value), b = Buffer.from(expected);
  return a.length === b.length && crypto.timingSafeEqual(a, b);
}

function escapeXml(value) {
  return String(value).replace(/[<>&"']/g, ch => ({'<':'&lt;','>':'&gt;','&':'&amp;','"':'&quot;',"'":'&apos;'}[ch]));
}

async function signBlob(pathname, operation, maximumSizeInBytes) {
  const validUntil = Date.now() + 5 * 60 * 1000;
  const constraints = operation === 'put'
    ? { allowedContentTypes: ['application/octet-stream'], maximumSizeInBytes }
    : {};
  const delegation = await issueSignedToken({ pathname, operations: [operation], validUntil, ...constraints });
  const request = await presignUrl(delegation, {
    pathname, operation, access: 'private', validUntil, ...constraints
  });
  return request;
}

module.exports = async function handler(req, res) {
  res.setHeader('Cache-Control', 'no-store');
  res.setHeader('Referrer-Policy', 'no-referrer');
  res.setHeader('X-Content-Type-Options', 'nosniff');
  const stage = typeof req.query.stage === 'string' ? req.query.stage : '';
  if (stage === 'upload') {
    const key = process.env.OTA_UPLOAD_TOKEN;
    const basename = process.env.OTA_UPLOAD_FILE;
    const size = Number(process.env.OTA_UPLOAD_SIZE);
    if (req.method !== 'POST' || !/^[0-9a-f]{64}$/.test(key || '') ||
        !matches(req.headers.authorization, 'Bearer ' + key) ||
        !(Date.now() < Number(process.env.OTA_UPLOAD_EXPIRES)) ||
        !/^ota\/Momentra-\d+\.\d+\.\d+-\d+-[0-9a-f]{12}\.ipa$/.test(basename || '') ||
        !Number.isSafeInteger(size) || size < 1 || size > 150_000_000) {
      return res.status(404).send('Link indisponível.');
    }
    try {
      const signed = await signBlob(basename, 'put', size);
      res.setHeader('Content-Type', 'application/json; charset=utf-8');
      return res.send(JSON.stringify(signed));
    } catch { return res.status(503).send('Armazenamento indisponível.'); }
  }
  const bootstrap = matches(req.query.token, process.env.INSTALL_TOKEN) &&
    Number.isFinite(Number(process.env.INSTALL_EXPIRES)) && Date.now() < Number(process.env.INSTALL_EXPIRES);
  const secret = process.env.DEVICE_UPDATE_TOKEN || '';
  const authorization = req.headers.authorization || '';
  const authorizedDevice = /^[0-9a-f]{64}$/.test(secret) &&
    matches(authorization, 'Bearer ' + secret);
  const signingKey = /^[0-9a-f]{64}$/.test(secret) ? secret : null;
  const ttl = 30 * 60 * 1000;
  const sign = value => crypto.createHmac('sha256', signingKey).update(value).digest('hex');
  const validTicket = value => {
    if (!signingKey || typeof value !== 'string' || !/^[0-9]{13}\.[0-9a-f]{32}\.[0-9a-f]{64}$/.test(value)) return false;
    const [expires, nonce, signature] = value.split('.');
    const deadline = Number(expires), now = Date.now();
    return deadline > now && deadline <= now + ttl && matches(signature, sign(expires + '.' + nonce));
  };
  const ticket = validTicket(req.query.ticket);
  const supportsHead = stage === 'manifest' || stage === 'package';
  if ((req.method !== 'GET' && !(req.method === 'HEAD' && supportsHead)) ||
      !(bootstrap || (stage === 'issue' && authorizedDevice) ||
        (ticket && (stage === 'manifest' || stage === 'package')))) {
    return res.status(404).send('Link indisponível.');
  }
  if (stage === 'activate') {
    if (!bootstrap || !signingKey) return res.status(503).send('Ativação indisponível.');
    res.setHeader('Content-Type', 'application/json; charset=utf-8');
    return res.send(JSON.stringify({deviceToken: secret}));
  }
  const host = req.headers.host || '';
  if (!/^[a-z0-9.-]+\.vercel\.app$/i.test(host)) return res.status(400).send('Endereço inválido.');
  const endpoint = `https://${host}/api/install`;
  const token = encodeURIComponent(req.query.token || '');
  const authorizationQuery = ticket ? 'ticket=' + encodeURIComponent(req.query.ticket) : 'token=' + token;
  const version = process.env.RELEASE_VERSION || '0.1.5';
  if (!/^\d{1,6}\.\d{1,6}\.\d{1,6}$/.test(version)) return res.status(503).send('Versão indisponível.');
  const legacyOrigin = process.env.SIGNED_IPA_URL;
  const build = process.env.RELEASE_BUILD;
  const pathname = process.env.SIGNED_IPA_BLOB;
  const size = Number(process.env.SIGNED_IPA_SIZE);
  const blob = pathname?.startsWith(`ota/Momentra-${version}-${build}-`) &&
    /^ota\/Momentra-\d+\.\d+\.\d+-\d+-[0-9a-f]{12}\.ipa$/.test(pathname) &&
    Number.isSafeInteger(size) && size > 0 && size <= 150_000_000
    ? { pathname, size } : null;
  const available = pathname ? blob !== null : /^https:\/\/cdn\d+\.signulous\.com\/downloads\//.test(legacyOrigin || '');
  if (stage === 'issue') {
    if (!authorizedDevice || !signingKey) return res.status(404).send('Link indisponível.');
    const expires = String(Date.now() + ttl);
    const nonce = crypto.randomBytes(16).toString('hex');
    const payload = expires + '.' + nonce;
    const scopedTicket = payload + '.' + sign(payload);
    const manifest = endpoint + '?stage=manifest&ticket=' + encodeURIComponent(scopedTicket);
    res.setHeader('Content-Type', 'application/json; charset=utf-8');
    return res.send(JSON.stringify({version, manifest}));
  }
  if (req.query.stage === 'metadata') {
    res.setHeader('Content-Type', 'application/json; charset=utf-8');
    return res.send(JSON.stringify({version}));
  }
  if (req.query.stage === 'manifest') {
    if (!available || !build || !/^\d+(?:\.\d+){0,2}$/.test(build)) {
      return res.status(503).send('Arquivo indisponível.');
    }
    const ipa = escapeXml(`${endpoint}?stage=package&${authorizationQuery}`);
    res.setHeader('Content-Type', 'application/xml; charset=utf-8');
    return res.send(`<?xml version="1.0" encoding="UTF-8"?><!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd"><plist version="1.0"><dict><key>items</key><array><dict><key>assets</key><array><dict><key>kind</key><string>software-package</string><key>url</key><string>${ipa}</string></dict></array><key>metadata</key><dict><key>bundle-identifier</key><string>br.com.momentra.camera</string><key>bundle-version</key><string>${build}</string><key>kind</key><string>software</string><key>title</key><string>Momentra</string></dict></dict></array></dict></plist>`);
  }
  if (req.query.stage === 'package') {
    if (!available) return res.status(503).send('Arquivo indisponível.');
    if (blob) return serveBlobIpa(req, res, blob, async (path, method) => (await signBlob(path, method)).presignedUrl);
    return serveIpa(req, res, legacyOrigin);
  }
  const manifest = `${endpoint}?stage=manifest&token=${token}`;
  const install = `itms-services://?action=download-manifest&url=${encodeURIComponent(manifest)}`;
  const activate = `momentra://updates/activate?token=${token}`;
  res.setHeader('Content-Type', 'text/html; charset=utf-8');
  return res.send(`<!doctype html><html lang="pt-BR"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Momentra</title><body style="font:18px system-ui;background:#111;color:white;padding:24px"><h1>Momentra ${version}</h1><p>Instale sobre a versão existente para manter seus dados.</p><a style="display:inline-block;background:#fff;color:#111;padding:16px;border-radius:12px;text-decoration:none" href="${escapeXml(install)}">Instalar atualização</a><p>Depois de instalar e abrir o Momentra, volte aqui para ativar as próximas atualizações dentro do aplicativo.</p><a style="display:inline-block;background:#333;color:white;padding:16px;border-radius:12px;text-decoration:none" href="${escapeXml(activate)}">Ativar atualização direta</a></body></html>`);
};

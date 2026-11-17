const crypto = require('node:crypto');

function matches(value, expected) {
  if (typeof value !== 'string' || typeof expected !== 'string' || !expected) return false;
  const a = Buffer.from(value), b = Buffer.from(expected);
  return a.length === b.length && crypto.timingSafeEqual(a, b);
}

function escapeXml(value) {
  return String(value).replace(/[<>&"']/g, ch => ({'<':'&lt;','>':'&gt;','&':'&amp;','"':'&quot;',"'":'&apos;'}[ch]));
}

module.exports = async function handler(req, res) {
  res.setHeader('Cache-Control', 'no-store');
  res.setHeader('Referrer-Policy', 'no-referrer');
  res.setHeader('X-Content-Type-Options', 'nosniff');
  if (req.method !== 'GET' || !matches(req.query.token, process.env.INSTALL_TOKEN) ||
      !Number.isFinite(Number(process.env.INSTALL_EXPIRES)) || Date.now() >= Number(process.env.INSTALL_EXPIRES)) {
    return res.status(404).send('Link indispon√≠vel.');
  }
  const host = req.headers.host || '';
  if (!/^[a-z0-9.-]+\.vercel\.app$/i.test(host)) return res.status(400).send('Endere√ßo inv√°lido.');
  const endpoint = `https://${host}/api/install`;
  const token = encodeURIComponent(req.query.token);
  const version = process.env.RELEASE_VERSION || '0.1.5';
  if (!/^\d{1,6}\.\d{1,6}\.\d{1,6}$/.test(version)) return res.status(503).send('Vers√£o indispon√≠vel.');
  if (req.query.stage === 'metadata') {
    res.setHeader('Content-Type', 'application/json; charset=utf-8');
    return res.send(JSON.stringify({version}));
  }
  if (req.query.stage === 'manifest') {
    const ipa = escapeXml(`${endpoint}?stage=package&token=${token}`);
    res.setHeader('Content-Type', 'application/xml; charset=utf-8');
    return res.send(`<?xml version="1.0" encoding="UTF-8"?><!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd"><plist version="1.0"><dict><key>items</key><array><dict><key>assets</key><array><dict><key>kind</key><string>software-package</string><key>url</key><string>${ipa}</string></dict></array><key>metadata</key><dict><key>bundle-identifier</key><string>br.com.momentra.camera</string><key>bundle-version</key><string>${version}</string><key>kind</key><string>software</string><key>title</key><string>Momentra</string></dict></dict></array></dict></plist>`);
  }
  if (req.query.stage === 'package') {
    const remote = process.env.SIGNED_IPA_URL;
    if (!remote || !/^https:\/\/cdn\d+\.signulous\.com\/downloads\//.test(remote)) return res.status(503).send('Arquivo indispon√≠vel.');
    // Vercel limits function response bodies; let iOS download the signed IPA
    // directly from the signing service after validating this private link.
    res.setHeader('Location', remote);
    return res.status(302).send('');
  }
  const manifest = `${endpoint}?stage=manifest&token=${token}`;
  const install = `itms-services://?action=download-manifest&url=${encodeURIComponent(manifest)}`;
  const activate = `momentra://updates/activate?token=${token}`;
  res.setHeader('Content-Type', 'text/html; charset=utf-8');
  return res.send(`<!doctype html><html lang="pt-BR"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Momentra</title><body style="font:18px system-ui;background:#111;color:white;padding:24px"><h1>Momentra ${version}</h1><p>Instale sobre a vers√£o existente para manter seus dados.</p><a style="display:inline-block;background:#fff;color:#111;padding:16px;border-radius:12px;text-decoration:none" href="${escapeXml(install)}">Instalar atualiza√ß√£o</a><p>Depois de instalar e abrir o Momentra, volte aqui para ativar as prÛximas atualizaÁıes dentro do aplicativo.</p><a style="display:inline-block;background:#333;color:white;padding:16px;border-radius:12px;text-decoration:none" href="${escapeXml(activate)}">Ativar atualizaÁ„o direta</a></body></html>`);
};

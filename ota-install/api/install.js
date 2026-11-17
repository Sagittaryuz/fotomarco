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
    return res.status(404).send('Link indisponível.');
  }
  const host = req.headers.host || '';
  if (!/^[a-z0-9.-]+\.vercel\.app$/i.test(host)) return res.status(400).send('Endereço inválido.');
  const endpoint = `https://${host}/api/install`;
  const token = encodeURIComponent(req.query.token);
  if (req.query.stage === 'manifest') {
    const ipa = escapeXml(`${endpoint}?stage=package&token=${token}`);
    res.setHeader('Content-Type', 'application/xml; charset=utf-8');
    return res.send(`<?xml version="1.0" encoding="UTF-8"?><!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd"><plist version="1.0"><dict><key>items</key><array><dict><key>assets</key><array><dict><key>kind</key><string>software-package</string><key>url</key><string>${ipa}</string></dict></array><key>metadata</key><dict><key>bundle-identifier</key><string>br.com.momentra.camera</string><key>bundle-version</key><string>0.1.5</string><key>kind</key><string>software</string><key>title</key><string>Momentra</string></dict></dict></array></dict></plist>`);
  }
  if (req.query.stage === 'package') {
    const remote = process.env.SIGNED_IPA_URL;
    if (!remote || !/^https:\/\/cdn\d+\.signulous\.com\/downloads\//.test(remote)) return res.status(503).send('Arquivo indisponível.');
    try {
      const response = await fetch(remote, {redirect:'error', signal:AbortSignal.timeout(20000)});
      if (!response.ok) return res.status(502).send('Arquivo indisponível.');
      const bytes = Buffer.from(await response.arrayBuffer());
      if (!bytes.length || bytes.length > 4_000_000) return res.status(502).send('Arquivo inválido.');
      res.setHeader('Content-Type', 'application/octet-stream');
      return res.send(bytes);
    } catch (_) { return res.status(502).send('Arquivo indisponível.'); }
  }
  const manifest = `${endpoint}?stage=manifest&token=${token}`;
  const install = `itms-services://?action=download-manifest&url=${encodeURIComponent(manifest)}`;
  res.setHeader('Content-Type', 'text/html; charset=utf-8');
  return res.send(`<!doctype html><html lang="pt-BR"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Momentra</title><body style="font:18px system-ui;background:#111;color:white;padding:24px"><h1>Momentra 0.1.5</h1><p>Instale sobre a versão existente para manter seus dados.</p><a style="display:inline-block;background:#fff;color:#111;padding:16px;border-radius:12px;text-decoration:none" href="${escapeXml(install)}">Instalar atualização</a></body></html>`);
};

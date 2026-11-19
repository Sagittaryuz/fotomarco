const test = require('node:test');
const assert = require('node:assert/strict');
const http = require('node:http');
const handler = require('./api/install');
const { serveIpa } = require('./lib/ipa');

async function request(query, authorization = '', method = 'GET') {
  const headers = {};
  const res = { code: 200, setHeader(k, v) { headers[k] = v; }, status(n) { this.code = n; return this; }, send(body) { this.body = body; return this; } };
  await handler({method, query, headers: {host: 'momentra-instalacao.vercel.app', authorization}}, res);
  res.headers = headers;
  return res;
}

test('metadata and manifest require a valid, unexpired access code', async () => {
  process.env.INSTALL_TOKEN = 'a'.repeat(64);
  process.env.INSTALL_EXPIRES = String(Date.now() + 60_000);
  process.env.RELEASE_VERSION = '0.1.6';
  process.env.RELEASE_BUILD = '7';
  process.env.SIGNED_IPA_URL = 'https://cdn4.signulous.com/downloads/test/Momentra.ipa';
  assert.equal((await request({stage: 'metadata', token: 'wrong'})).code, 404);
  const metadata = await request({stage: 'metadata', token: process.env.INSTALL_TOKEN});
  assert.equal(metadata.code, 200);
  assert.deepEqual(JSON.parse(metadata.body), {version: '0.1.6'});
  const landing = await request({token: process.env.INSTALL_TOKEN});
  assert.match(landing.body, /momentra:\/\/updates\/activate\?token=/);
  const manifest = await request({stage: 'manifest', token: process.env.INSTALL_TOKEN});
  assert.match(manifest.body, /<key>bundle-version<\/key><string>7<\/string>/);
  assert.match(manifest.body, /stage=package&amp;token=/);
  assert.equal((await request({stage: 'manifest', token: process.env.INSTALL_TOKEN}, '', 'HEAD')).code, 200);
  assert.equal((await request({stage: 'manifest', token: 'wrong'}, '', 'HEAD')).code, 404);
  process.env.INSTALL_EXPIRES = '1';
  assert.equal((await request({stage: 'metadata', token: process.env.INSTALL_TOKEN})).code, 404);
});


test('package rejects clients without authorization and unapproved sources', async () => {
  process.env.INSTALL_TOKEN = 'b'.repeat(64);
  process.env.INSTALL_EXPIRES = String(Date.now() + 60_000);
  process.env.SIGNED_IPA_URL = 'https://cdn4.signulous.com/downloads/test/Momentra.ipa';
  assert.equal((await request({stage: 'package', token: 'bad'})).code, 404);
  process.env.SIGNED_IPA_URL = 'https://example.com/file.ipa';
  assert.equal((await request({stage: 'package', token: process.env.INSTALL_TOKEN})).code, 503);
});

test('device can issue fresh scoped tickets after bootstrap expires', async () => {
  process.env.INSTALL_TOKEN = 'c'.repeat(64);
  process.env.DEVICE_UPDATE_TOKEN = 'd'.repeat(64);
  process.env.INSTALL_EXPIRES = String(Date.now() + 60_000);
  process.env.RELEASE_VERSION = '0.1.9';
  process.env.SIGNED_IPA_URL = 'https://cdn4.signulous.com/downloads/test/Momentra.ipa';
  const activated = await request({stage: 'activate', token: process.env.INSTALL_TOKEN});
  assert.equal(JSON.parse(activated.body).deviceToken, process.env.DEVICE_UPDATE_TOKEN);
  process.env.INSTALL_EXPIRES = '1';
  assert.equal((await request({stage: 'activate', token: process.env.INSTALL_TOKEN})).code, 404);
  assert.equal((await request({stage: 'issue'}, 'Bearer wrong')).code, 404);
  const issued = JSON.parse((await request({stage: 'issue'}, 'Bearer ' + process.env.DEVICE_UPDATE_TOKEN)).body);
  const next = JSON.parse((await request({stage: 'issue'}, 'Bearer ' + process.env.DEVICE_UPDATE_TOKEN)).body);
  assert.equal(issued.version, '0.1.9');
  assert.notEqual(issued.manifest, next.manifest);
  assert.ok(!issued.manifest.includes(process.env.DEVICE_UPDATE_TOKEN));
  const ticket = new URL(issued.manifest).searchParams.get('ticket');
  const manifest = await request({stage: 'manifest', ticket});
  assert.equal(manifest.code, 200);
  assert.match(manifest.body, /stage=package&amp;ticket=/);
  assert.doesNotMatch(manifest.body, /signulous/);
  assert.equal((await request({stage: 'metadata', ticket})).code, 404);
  const crypto = require('node:crypto');
  const oldPayload = String(Date.now() - 1000) + '.' + 'a'.repeat(32);
  const oldSig = crypto.createHmac('sha256', process.env.DEVICE_UPDATE_TOKEN).update(oldPayload).digest('hex');
  assert.equal((await request({stage: 'manifest', ticket: oldPayload + '.' + oldSig})).code, 404);
  assert.equal((await request({stage: 'manifest', ticket: ticket.slice(0,-1)+'z'})).code, 404);
  process.env.DEVICE_UPDATE_TOKEN = 'e'.repeat(64);
  assert.equal((await request({stage: 'manifest', ticket})).code, 404);
});

test('package streams all bytes in order and supports HEAD and resume', async (t) => {
  const ipa = Buffer.alloc(5 * 1024 * 1024 + 77);
  for (let i = 0; i < ipa.length; i++) ipa[i] = i % 251;
  const requests = [];
  const listen = async (listener) => {
    const server = http.createServer(listener);
    await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
    t.after(() => { server.close(); server.closeAllConnections(); });
    return `http://127.0.0.1:${server.address().port}`;
  };
  const upstream = await listen((req, res) => {
    const range = /^bytes=(\d+)-(\d+)$/.exec(req.headers.range);
    assert.ok(range);
    const first = +range[1], last = +range[2];
    requests.push(first);
    if (first === 512 * 1024 && requests.filter(value => value === first).length === 1) {
      return res.writeHead(503).end();
    }
    res.writeHead(206, { 'Content-Range': `bytes ${first}-${last}/${ipa.length}` });
    res.end(ipa.subarray(first, last + 1));
  });
  const local = await listen((req, res) => {
    res.status = (status) => { res.statusCode = status; return res; };
    res.send = (body) => res.end(body);
    return serveIpa(req, res, upstream);
  });
  const head = await fetch(local, { method: 'HEAD' });
  assert.equal(head.status, 200);
  assert.equal(+head.headers.get('content-length'), ipa.length);
  assert.equal(head.headers.get('accept-ranges'), 'bytes');
  const full = await fetch(local);
  assert.equal(full.status, 200);
  assert.deepEqual(Buffer.from(await full.arrayBuffer()), ipa);
  const resume = await fetch(local, { headers: { Range: 'bytes=100-2097152' } });
  assert.equal(resume.status, 206);
  assert.equal(resume.headers.get('content-range'), `bytes 100-2097152/${ipa.length}`);
  assert.deepEqual(Buffer.from(await resume.arrayBuffer()), ipa.subarray(100, 2097153));
  const invalid = await fetch(local, { headers: { Range: `bytes=${ipa.length}-` } });
  assert.equal(invalid.status, 416);
});

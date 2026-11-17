const test = require('node:test');
const assert = require('node:assert/strict');
const handler = require('./api/install');

async function request(query, authorization = '') {
  const headers = {};
  const res = { code: 200, setHeader(k, v) { headers[k] = v; }, status(n) { this.code = n; return this; }, send(body) { this.body = body; return this; } };
  await handler({method: 'GET', query, headers: {host: 'momentra-instalacao.vercel.app', authorization}}, res);
  res.headers = headers;
  return res;
}

test('metadata and manifest require a valid, unexpired access code', async () => {
  process.env.INSTALL_TOKEN = 'a'.repeat(64);
  process.env.INSTALL_EXPIRES = String(Date.now() + 60_000);
  process.env.RELEASE_VERSION = '0.1.6';
  assert.equal((await request({stage: 'metadata', token: 'wrong'})).code, 404);
  const metadata = await request({stage: 'metadata', token: process.env.INSTALL_TOKEN});
  assert.equal(metadata.code, 200);
  assert.deepEqual(JSON.parse(metadata.body), {version: '0.1.6'});
  const landing = await request({token: process.env.INSTALL_TOKEN});
  assert.match(landing.body, /momentra:\/\/updates\/activate\?token=/);
  const manifest = await request({stage: 'manifest', token: process.env.INSTALL_TOKEN});
  assert.match(manifest.body, /<string>0\.1\.6<\/string>/);
  assert.match(manifest.body, /stage=package&amp;token=/);
  process.env.INSTALL_EXPIRES = '1';
  assert.equal((await request({stage: 'metadata', token: process.env.INSTALL_TOKEN})).code, 404);
});


test('package redirects authorized clients to the signed IPA', async () => {
  process.env.INSTALL_TOKEN = 'b'.repeat(64);
  process.env.INSTALL_EXPIRES = String(Date.now() + 60_000);
  process.env.SIGNED_IPA_URL = 'https://cdn4.signulous.com/downloads/test/Momentra.ipa';
  assert.equal((await request({stage: 'package', token: 'bad'})).code, 404);
  const response = await request({stage: 'package', token: process.env.INSTALL_TOKEN});
  assert.equal(response.code, 302);
  assert.equal(response.headers.Location, process.env.SIGNED_IPA_URL);
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
  assert.equal((await request({stage: 'package', ticket})).code, 302);
  assert.equal((await request({stage: 'metadata', ticket})).code, 404);
  const crypto = require('node:crypto');
  const oldPayload = String(Date.now() - 1000) + '.' + 'a'.repeat(32);
  const oldSig = crypto.createHmac('sha256', process.env.DEVICE_UPDATE_TOKEN).update(oldPayload).digest('hex');
  assert.equal((await request({stage: 'manifest', ticket: oldPayload + '.' + oldSig})).code, 404);
  assert.equal((await request({stage: 'manifest', ticket: ticket.slice(0,-1)+'z'})).code, 404);
  process.env.DEVICE_UPDATE_TOKEN = 'e'.repeat(64);
  assert.equal((await request({stage: 'manifest', ticket})).code, 404);
});

const test = require('node:test');
const assert = require('node:assert/strict');
const handler = require('./api/install');

async function request(query) {
  const headers = {};
  const res = { code: 200, setHeader(k, v) { headers[k] = v; }, status(n) { this.code = n; return this; }, send(body) { this.body = body; return this; } };
  await handler({method: 'GET', query, headers: {host: 'momentra-instalacao.vercel.app'}}, res);
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

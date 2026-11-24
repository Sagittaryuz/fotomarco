import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createBusinessWorker } from './business-worker.mjs';

const headers = { authorization: 'Bearer valid.token', 'content-type': 'application/json', 'cf-connecting-ip': '127.0.0.1' };
const req = object => { const body = JSON.stringify(object); return new Request('https://business.test/v1/organizations',
  { method: 'POST', body, headers: { ...headers, 'content-length': String(Buffer.byteLength(body)) } }); };

test('only the configured verified owner may bootstrap an organization', async () => {
  const commits = [];
  const env = { PHOTOMARK_FIREBASE_PROJECT_ID: 'demo-project', BUSINESS_OWNER_EMAIL: 'owner@example.com',
    BUSINESS_IP_LIMIT: { limit: async () => ({ success: true }) }, BUSINESS_UID_LIMIT: { limit: async () => ({ success: true }) } };
  let identity = { uid: 'uid1', email: 'owner@example.com', emailVerified: false };
  const worker = createBusinessWorker(env, { authenticate: async () => identity, serverAccessToken: async () => 'server-token',
    fetchImpl: async (url, options) => {
      if (url.endsWith(':beginTransaction')) return { ok: true, json: async () => ({ transaction: 'tx' }) };
      if (url.endsWith(':commit')) commits.push(JSON.parse(options.body));
      return { ok: true, json: async () => ({}) };
    } });
  assert.equal((await worker(req({ name: 'Equipe', contactEmail: 'business@example.com' }))).status, 403);
  identity = { ...identity, emailVerified: true };
  assert.equal((await worker(req({ name: 'Equipe', contactEmail: 'business@example.com' }))).status, 201);
  assert.equal(commits.length, 1);
  assert.equal(commits[0].writes.length, 4);
  assert.match(commits[0].writes[2].update.name, /\/users\/uid1\/organizations\//);
});

test('missing security bindings fail closed', () => {
  assert.throws(() => createBusinessWorker({ PHOTOMARK_FIREBASE_PROJECT_ID: 'demo-project' }), /missing-worker-configuration/);
});

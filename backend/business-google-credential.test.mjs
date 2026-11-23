import { test } from 'node:test';
import assert from 'node:assert/strict';
import { exportPKCS8, generateKeyPair, jwtVerify } from 'jose';
import { googleServiceAccountToken } from './business-google-credential.mjs';

test('signs a narrowly scoped assertion and refreshes cached tokens', async () => {
  const keys = await generateKeyPair('RS256', { extractable: true });
  const privateKey = await exportPKCS8(keys.privateKey);
  let clock = 1800000000000, calls = 0;
  const provider = googleServiceAccountToken({ clientEmail: 'worker@demo-project.iam.gserviceaccount.com', privateKey,
    now: () => clock, fetchImpl: async (url, request) => {
      calls++;
      assert.equal(url, 'https://oauth2.googleapis.com/token');
      const form = new URLSearchParams(request.body);
      assert.equal(form.get('grant_type'), 'urn:ietf:params:oauth:grant-type:jwt-bearer');
      const { payload } = await jwtVerify(form.get('assertion'), keys.publicKey, { audience: url, currentDate: new Date(clock) });
      assert.equal(payload.scope, 'https://www.googleapis.com/auth/datastore');
      assert.equal(payload.iss, 'worker@demo-project.iam.gserviceaccount.com');
      assert.equal(payload.exp - payload.iat, 3600);
      return { ok: true, json: async () => ({ access_token: `token-${calls}`, token_type: 'Bearer', expires_in: 3600 }) };
    } });
  assert.deepEqual(await Promise.all([provider(), provider()]), ['token-1', 'token-1']);
  assert.equal(await provider(), 'token-1');
  assert.equal(calls, 1);
  clock += 3481 * 1000;
  assert.equal(await provider(), 'token-2');
});

test('rejects invalid credentials and malformed token responses', async () => {
  assert.throws(() => googleServiceAccountToken({ clientEmail: 'person@example.com', privateKey: 'x' }), /invalid-server-credential/);
  const keys = await generateKeyPair('RS256', { extractable: true });
  const provider = googleServiceAccountToken({ clientEmail: 'worker@demo-project.iam.gserviceaccount.com',
    privateKey: await exportPKCS8(keys.privateKey), fetchImpl: async () => ({ ok: true, json: async () => ({ access_token: 'x', token_type: 'Bearer', expires_in: 2 }) }) });
  await assert.rejects(provider(), /invalid-server-token/);
});

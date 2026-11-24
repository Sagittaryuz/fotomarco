import { test } from 'node:test';
import assert from 'node:assert/strict';
import { microsoftBusinessCredential } from './business-microsoft-oauth.mjs';

const clientId = '12345678-1234-1234-1234-123456789abc';
function provider({ scope = 'openid Files.ReadWrite', driveOwner = 'owner' } = {}) {
  const calls = [];
  return { calls, fetch: async (url, options) => {
    calls.push({ url, options });
    if (url.includes('/token')) return { status: 200, json: async () => ({ access_token: 'access', refresh_token: 'rotated', scope }) };
    if (url.includes('/me?')) return { status: 200, json: async () => ({ id: 'owner' }) };
    return { status: 200, json: async () => ({ id: 'drive', owner: { user: { id: driveOwner } } }) };
  } };
}

test('validates the actual Microsoft owner and required folder access', async () => {
  const mock = provider();
  const exchange = microsoftBusinessCredential({ clientId, fetchImpl: mock.fetch });
  assert.deepEqual(await exchange('refresh'), { refreshToken: 'rotated', providerAccountId: 'owner', driveId: 'drive', accessToken: 'access' });
  assert.equal(mock.calls.length, 3);
  assert.equal(mock.calls.every(call => call.options.redirect === 'manual'), true);
  const narrow = provider({ scope: 'Files.ReadWrite.AppFolder' });
  await assert.rejects(microsoftBusinessCredential({ clientId, fetchImpl: narrow.fetch })('refresh'), /provider-permission-missing/);
  const wrong = provider({ driveOwner: 'another' });
  await assert.rejects(microsoftBusinessCredential({ clientId, fetchImpl: wrong.fetch })('refresh'), /provider-identity-mismatch/);
});

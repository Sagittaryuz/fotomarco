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

test('classifies token and Graph failures without returning provider responses', async () => {
  const tokenFailure = microsoftBusinessCredential({ clientId, fetchImpl: async () => ({
    status: 400, json: async () => ({ error_description: 'private-provider-details' })
  }) });
  await assert.rejects(tokenFailure('refresh'), error => error.message === 'provider-token-unavailable');

  const graphFailure = microsoftBusinessCredential({ clientId, fetchImpl: async url =>
    url.includes('/token')
      ? { status: 200, json: async () => ({ access_token: 'access', scope: 'Files.ReadWrite' }) }
      : { status: 403, json: async () => ({ error: { message: 'private-provider-details' } }) }
  });
  await assert.rejects(graphFailure('refresh'), error => error.message === 'provider-graph-unavailable');
});

test('classifies network and malformed response failures without exposing upstream details', async () => {
  for (const failingStage of ['token', 'graph']) {
    for (const failure of ['network', 'json']) {
      const fetchImpl = async url => {
        const isToken = url.includes('/token');
        if ((failingStage === 'token') === isToken) {
          if (failure === 'network') throw new Error('private network details');
          return { status: 200, json: async () => { throw new Error('private response'); } };
        }
        return { status: 200, json: async () => ({ access_token: 'access', scope: 'Files.ReadWrite' }) };
      };
      const exchange = microsoftBusinessCredential({ clientId, fetchImpl });
      await assert.rejects(exchange('refresh'), error =>
        error.message === `provider-${failingStage}-unavailable`);
    }
  }
});

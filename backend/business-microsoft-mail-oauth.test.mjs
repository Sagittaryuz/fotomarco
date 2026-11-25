import { test } from 'node:test';
import assert from 'node:assert/strict';
import { microsoftBusinessMailCredential } from './business-microsoft-mail-oauth.mjs';
const clientId = '12345678-1234-1234-1234-123456789abc';

function provider(scope, mail = 'Owner@example.com') {
  return async url => url.includes('/token')
    ? { status: 200, json: async () => ({ access_token: 'access', refresh_token: 'rotated', scope }) }
    : { status: 200, json: async () => ({ id: 'owner', mail }) };
}
test('requires delegated mail send and returns account-bound mailbox', async () => {
  const verify = microsoftBusinessMailCredential({ clientId, fetchImpl: provider('User.Read Mail.Send') });
  assert.deepEqual(await verify('refresh'), { accessToken: 'access', refreshToken: 'rotated', providerAccountId: 'owner', email: 'owner@example.com' });
  await assert.rejects(microsoftBusinessMailCredential({ clientId, fetchImpl: provider('User.Read Files.ReadWrite') })('refresh'), /mail-permission-missing/);
  await assert.rejects(microsoftBusinessMailCredential({ clientId, fetchImpl: provider('Mail.Send', null) })('refresh'), /mailbox-unconfirmed/);
});
test('does not expose network or provider errors', async () => {
  const verify = microsoftBusinessMailCredential({ clientId, fetchImpl: async () => { throw new Error('private-provider-details'); } });
  await assert.rejects(verify('refresh'), error => error.message === 'mail-unavailable');
});

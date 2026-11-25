import { test } from 'node:test';
import assert from 'node:assert/strict';
import { verifiedGoogleDriveMember } from './business-google-drive-member.mjs';
function provider({ verified = true, driveEmail = 'member@example.com' } = {}) {
  return async url => ({ status: 200, json: async () => url.includes('/userinfo')
    ? { sub: 'google-user', email: 'Member@example.com', email_verified: verified }
    : { user: { me: true, permissionId: 'permission-id', emailAddress: driveEmail } } });
}
test('binds only a verified Google identity to its own Drive permission ID', async () => {
  assert.deepEqual(await verifiedGoogleDriveMember('token', { fetchImpl: provider() }),
    { providerAccountId: 'google-user', permissionId: 'permission-id', email: 'member@example.com' });
  await assert.rejects(verifiedGoogleDriveMember('token', { fetchImpl: provider({ verified: false }) }), /provider-identity-mismatch/);
  await assert.rejects(verifiedGoogleDriveMember('token', { fetchImpl: provider({ driveEmail: 'other@example.com' }) }), /provider-identity-mismatch/);
});
test('does not leak upstream errors', async () => {
  await assert.rejects(verifiedGoogleDriveMember('token', { fetchImpl: async () => { throw new Error('private-data'); } }), error => error.message === 'provider-unavailable');
});

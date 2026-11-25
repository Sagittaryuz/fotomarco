import { test } from 'node:test';
import assert from 'node:assert/strict';
import { googleBusinessDriveCredential } from './business-google-drive-oauth.mjs';

const clientId = '123456-example.apps.googleusercontent.com';
function provider({ scope = 'openid https://www.googleapis.com/auth/drive.file', email = 'owner@example.com', driveEmail = email } = {}) {
  return async url => ({ status: 200, json: async () => url.includes('/token')
    ? { access_token: 'private-access', refresh_token: 'rotated', scope }
    : url.includes('/userinfo') ? { sub: 'owner', email, email_verified: true }
      : { user: { me: true, permissionId: 'permission-id', emailAddress: driveEmail } } });
}
test('requires Drive scope and binds Google identity to Drive owner', async () => {
  const verify = googleBusinessDriveCredential({ clientId, fetchImpl: provider() });
  assert.deepEqual(await verify('refresh'), { accessToken: 'private-access', refreshToken: 'rotated', providerAccountId: 'owner', ownerPermissionId: 'permission-id', email: 'owner@example.com' });
  await assert.rejects(googleBusinessDriveCredential({ clientId, fetchImpl: provider({ scope: 'openid' }) })('refresh'), /provider-permission-missing/);
  await assert.rejects(googleBusinessDriveCredential({ clientId, fetchImpl: provider({ driveEmail: 'other@example.com' }) })('refresh'), /provider-identity-mismatch/);
});
test('never forwards provider errors', async () => {
  const verify = googleBusinessDriveCredential({ clientId, fetchImpl: async () => { throw new Error('secret-response'); } });
  await assert.rejects(verify('refresh'), error => error.message === 'provider-unavailable');
});

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { BusinessService } from './business-service.mjs';

function fixture() {
  const org = { id: 'org', ownerId: 'owner' };
  const member = { organizationId: 'org', userId: 'member', role: 'member', active: true, storageStatus: 'not-started' };
  const bindings = new Map();
  const tx = { organization: async () => org, membership: async (_, uid) => uid === 'member' ? member : null,
    providerBinding: async (_, key) => bindings.get(key), setProviderBinding: async (_, key, uid) => bindings.set(key, { userId: uid }),
    setMemberProviderIdentity: async (_, __, id, email) => Object.assign(member, { oneDrivePendingIdentityId: id, oneDrivePendingEmail: email }),
    setGoogleDriveMemberIdentity: async (_, __, id, permission, email) => Object.assign(member, { googleDrivePendingIdentityId: id, googleDrivePendingPermissionId: permission, googleDrivePendingEmail: email }) };
  const service = new BusinessService({ verifyToken: async x => x, transaction: action => action(tx),
    verifyMicrosoftMember: async () => ({ providerAccountId: 'verified-id', email: 'onedrive@example.com' }) });
  return { service, member, bindings };
}
const user = { uid: 'member', emailVerified: true };

test('binds only the provider-verified account of an active member', async () => {
  const { service, member } = fixture();
  assert.deepEqual(await service.bindMicrosoftMember(user, 'org', 'token'), { linked: true });
  assert.equal(member.oneDrivePendingIdentityId, 'verified-id');
  assert.equal(member.oneDrivePendingEmail, 'onedrive@example.com');
  assert.equal('accessToken' in member, false);
  service.verifyMicrosoftMember = async () => ({ providerAccountId: 'different-id', email: 'other@example.com' });
  await assert.rejects(service.bindMicrosoftMember(user, 'org', 'other-token'), /storage-account-change-requires-migration/);
});

test('binds verified Google identity without changing the existing Microsoft identity', async () => {
  const { service, member } = fixture();
  await service.bindMicrosoftMember(user, 'org', 'token');
  service.verifyGoogleDriveMember = async () => ({ providerAccountId: 'google-id', permissionId: 'permission-id', email: 'google@example.com' });
  assert.deepEqual(await service.bindGoogleDriveMember(user, 'org', 'token'), { linked: true });
  assert.equal(member.googleDrivePendingPermissionId, 'permission-id');
  assert.equal(member.oneDrivePendingIdentityId, 'verified-id');
  service.verifyGoogleDriveMember = async () => ({ providerAccountId: 'other', permissionId: 'other-permission', email: 'other@example.com' });
  await assert.rejects(service.bindGoogleDriveMember(user, 'org', 'token'), /storage-account-change-requires-migration/);
  assert.equal(member.googleDrivePendingIdentityId, 'google-id');
});

test('rejects revoked members and rechecks access after contacting Microsoft', async () => {
  const { service, member } = fixture();
  service.verifyMicrosoftMember = async () => { member.active = false; return { providerAccountId: 'id', email: 'a@example.com' }; };
  await assert.rejects(service.bindMicrosoftMember(user, 'org', 'token'), /forbidden/);
  assert.equal(member.oneDrivePendingIdentityId, undefined);
  await assert.rejects(service.bindMicrosoftMember({ ...user, emailVerified: false }, 'org', 'token'), /invalid-request/);
});

test('a Microsoft account already bound to another member cannot be reused', async () => {
  const { service, member, bindings } = fixture();
  const digest = new Uint8Array(await crypto.subtle.digest('SHA-256', new TextEncoder().encode('verified-id')));
  bindings.set(Array.from(digest, b => b.toString(16).padStart(2, '0')).join(''), { userId: 'different-member' });
  await assert.rejects(service.bindMicrosoftMember(user, 'org', 'token'), /provider-account-already-linked/);
  assert.equal(member.oneDrivePendingIdentityId, undefined);
});

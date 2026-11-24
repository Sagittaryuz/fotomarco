import { test } from 'node:test';
import assert from 'node:assert/strict';
import { BusinessService } from './business-service.mjs';

function fixture() {
  const org = { id: 'org', ownerId: 'owner' };
  const member = { organizationId: 'org', userId: 'member', role: 'member', active: true, storageStatus: 'not-started' };
  const tx = { organization: async () => org, membership: async (_, uid) => uid === 'member' ? member : null,
    setMemberProviderIdentity: async (_, __, id, email) => Object.assign(member, { oneDrivePendingIdentityId: id, oneDrivePendingEmail: email }) };
  const service = new BusinessService({ verifyToken: async x => x, transaction: action => action(tx),
    verifyMicrosoftMember: async () => ({ providerAccountId: 'verified-id', email: 'onedrive@example.com' }) });
  return { service, member };
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

test('rejects revoked members and rechecks access after contacting Microsoft', async () => {
  const { service, member } = fixture();
  service.verifyMicrosoftMember = async () => { member.active = false; return { providerAccountId: 'id', email: 'a@example.com' }; };
  await assert.rejects(service.bindMicrosoftMember(user, 'org', 'token'), /forbidden/);
  assert.equal(member.oneDrivePendingIdentityId, undefined);
  await assert.rejects(service.bindMicrosoftMember({ ...user, emailVerified: false }, 'org', 'token'), /invalid-request/);
});

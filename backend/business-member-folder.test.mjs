import { test } from 'node:test';
import assert from 'node:assert/strict';
import { BusinessService } from './business-service.mjs';
const marker = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
const lease = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
const person = { uid: 'member', emailVerified: true };
function fixture() {
  const org = { id: 'org', ownerId: 'owner' };
  const member = { organizationId: 'org', userId: 'member', role: 'member', active: true, storageStatus: 'not-started',
    oneDrivePendingIdentityId: 'graph-member', oneDrivePendingEmail: 'ms@example.com', email: 'person@example.com' };
  const storage = { driveId: 'drive', providerAccountId: 'graph-owner', version: 1, iv: 'iv', ciphertext: 'cipher' };
  let tick = 100, id = 0;
  const tx = { organization: async () => org, membership: async () => member, oneDriveCredential: async () => storage, setOneDriveCredential: async () => {},
    leaseMemberFolder: async (_, __, m, n, e, l, expires) => Object.assign(member, { storageStatus: 'provisioning', oneDriveCreationMarker: m, oneDriveProvisionName: n, oneDriveProvisionEmail: e, oneDriveGrantLease: l, oneDriveGrantLeaseExpiresAt: expires }),
    setMemberFolderPendingGrant: async (_, __, f, expires) => Object.assign(member, { oneDriveFolderId: f.folderId, oneDriveParentId: f.parentId, oneDriveMemberIdentityId: f.memberIdentityId, oneDriveGrantLeaseExpiresAt: expires }),
    setMemberFolderReady: async () => Object.assign(member, { storageStatus: 'granted', oneDriveGrantLease: '', oneDriveGrantLeaseExpiresAt: 0 }) };
  const service = new BusinessService({ verifyToken: async token => token, transaction: action => action(tx),
    newId: () => ++id % 2 ? marker : lease, clock: () => tick,
    verifyMicrosoftMember: async () => ({ providerAccountId: 'graph-member', email: 'ms@example.com' }),
    prepareMemberFolder: async () => ({ driveId: 'drive', parentId: 'parent', folderId: 'folder', memberIdentityId: 'graph-member', ownerCredential: storage }),
    grantMemberFolder: async () => true });
  return { service, member, setTime: x => tick = x };
}

test('member folder is bound before a verified share and then becomes ready', async () => {
  const { service, member } = fixture();
  service.grantMemberFolder = async () => { assert.equal(member.oneDriveFolderId, 'folder'); assert.equal(member.storageStatus, 'provisioning'); return true; };
  assert.deepEqual(await service.provisionMemberFolder(person, 'org', 'token'), { ready: true });
  assert.equal(member.storageStatus, 'granted');
});

test('revocation before provider grant prevents sharing', async () => {
  const { service, member } = fixture();
  service.prepareMemberFolder = async ({ storage }) => { member.active = false; return { driveId: 'drive', parentId: 'parent', folderId: 'folder', memberIdentityId: 'graph-member', ownerCredential: storage }; };
  let calls = 0; service.grantMemberFolder = async () => { calls++; return true; };
  await assert.rejects(service.provisionMemberFolder(person, 'org', 'token'), /forbidden/);
  assert.equal(calls, 0); assert.equal(member.oneDriveFolderId, undefined);
});

test('revocation while provider grants never enables member and retains folder for revocation', async () => {
  const { service, member } = fixture();
  service.grantMemberFolder = async () => { member.active = false; return true; };
  await assert.rejects(service.provisionMemberFolder(person, 'org', 'token'), /forbidden/);
  assert.equal(member.storageStatus, 'provisioning'); assert.equal(member.oneDriveFolderId, 'folder');
});

test('provider failure leaves a leased pending state and retry reuses its marker', async () => {
  const { service, member, setTime } = fixture();
  service.grantMemberFolder = async () => { throw new Error('offline'); };
  await assert.rejects(service.provisionMemberFolder(person, 'org', 'token'), /offline/);
  await assert.rejects(service.provisionMemberFolder(person, 'org', 'token'), /storage-busy/);
  setTime(120101); service.grantMemberFolder = async () => true;
  assert.deepEqual(await service.provisionMemberFolder(person, 'org', 'token'), { ready: true });
  assert.equal(member.oneDriveCreationMarker, marker);
});

test('a member cannot claim the organization owner Microsoft identity', async () => {
  const { service, member } = fixture();
  member.oneDrivePendingIdentityId = 'graph-owner';
  service.verifyMicrosoftMember = async () => ({ providerAccountId: 'graph-owner', email: 'ms@example.com' });
  await assert.rejects(service.provisionMemberFolder(person, 'org', 'token'), /provider-identity-mismatch/);
  assert.equal(member.storageStatus, 'not-started');
});

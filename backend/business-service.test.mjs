import { test } from 'node:test';
import assert from 'node:assert/strict';
import { BusinessService } from './business-service.mjs';

function fixture() {
  const organization = { id: 'org', ownerId: 'owner' };
  const records = new Map([['owner', { organizationId: 'org', userId: 'owner', role: 'owner', active: true }]]);
  const invites = new Map();
  let profile;
  let asset;
  const tx = {
    organization: async id => id === 'org' ? organization : null,
    membership: async (_, id) => records.get(id),
    occupiedSeats: async () => [...records.values()].filter(x => x.active).length,
    createInvitation: async value => { invites.set(value.id, value); },
    invitation: async (_, id) => invites.get(id),
    addMember: async value => { records.set(value.userId, value); },
    markInvitationAccepted: async (_, id, userId) => { invites.set(id, { ...invites.get(id), state: 'accepted', userId }); },
    publishProfile: async value => { profile = value; },
    latestProfile: async () => profile,
    createAsset: async value => { asset = value; },
    asset: async () => asset,
  };
  const service = new BusinessService({ verifyToken: async token => token, transaction: fn => fn(tx), newId: () => 'invite', clock: () => 100 });
  return { service, records, invites };
}

test('a verified invited user can join only as member, and cannot reuse invitation', async () => {
  const { service, records } = fixture();
  await service.invite({ uid: 'owner' }, 'org', ' PERSON@example.com ');
  const recipient = { uid: 'member', email: 'person@example.com', emailVerified: true };
  assert.deepEqual(await service.accept(recipient, 'org', 'invite'), { organizationId: 'org' });
  assert.equal(records.get('member').role, 'member');
  await assert.rejects(service.accept(recipient, 'org', 'invite'), /invalid-invitation/);
});

test('organization image is limited to managers for writing and members for reading', async () => {
  const { service, records } = fixture();
  records.set('member', { organizationId: 'org', userId: 'member', role: 'member', active: true });
  const image = 'iVBORw0KGgo=';
  assert.deepEqual(await service.uploadAsset({ uid: 'owner' }, 'org', 'image/png', image), { assetId: 'invite' });
  assert.deepEqual(await service.readAsset({ uid: 'member' }, 'org', 'invite'), { mimeType: 'image/png', base64: image });
  await assert.rejects(service.uploadAsset({ uid: 'member' }, 'org', 'image/png', image), /forbidden/);
  await assert.rejects(service.readAsset({ uid: 'outsider' }, 'org', 'invite'), /forbidden/);
  await assert.rejects(service.uploadAsset({ uid: 'owner' }, 'org', 'image/jpeg', image), /invalid-request/);
});

test('only managers publish layouts; active members can read but not change them', async () => {
  const { service, records } = fixture();
  records.set('member', { organizationId: 'org', userId: 'member', role: 'member', active: true });
  await service.publishProfile({ uid: 'owner' }, 'org', '{"template":"original"}');
  assert.equal((await service.readProfile({ uid: 'member' }, 'org')).layoutJSON, '{"template":"original"}');
  await assert.rejects(service.publishProfile({ uid: 'member' }, 'org', '{}'), /forbidden/);
  await assert.rejects(service.readProfile({ uid: 'outsider' }, 'org'), /forbidden/);
  records.set('member', { ...records.get('member'), active: false });
  await assert.rejects(service.readProfile({ uid: 'member' }, 'org'), /forbidden/);
  await assert.rejects(service.publishProfile({ uid: 'owner' }, 'org', 'invalid'), /invalid-request/);
});

test('a nonmember cannot invite; unverified or mismatched recipients cannot accept', async () => {
  const { service } = fixture();
  await assert.rejects(service.invite({ uid: 'stranger' }, 'org', 'a@example.com'), /forbidden-or-full/);
  await service.invite({ uid: 'owner' }, 'org', 'a@example.com');
  await assert.rejects(service.accept({ uid: 'x', email: 'a@example.com', emailVerified: false }, 'org', 'invite'), /invalid-invitation/);
  await assert.rejects(service.accept({ uid: 'x', email: 'b@example.com', emailVerified: true }, 'org', 'invite'), /invalid-invitation/);
  await assert.rejects(service.accept({ uid: 'x', email: 'a@example.com', emailVerified: true }, 'other', 'invite'), /invalid-invitation/);
});

test('organization creation requires verified identity and a trusted business entitlement', async () => {
  let saved;
  const tx = { initializeOrganization: async value => { saved = value; } };
  const options = { verifyToken: async token => token, transaction: fn => fn(tx), newId: () => 'org', clock: () => 100 };
  const user = { uid: 'owner', email: 'person@example.com', emailVerified: true };
  await assert.rejects(new BusinessService(options).createOrganization(user, 'Empresa', 'business@example.com'), /forbidden/);
  const service = new BusinessService({ ...options, canCreateOrganization: async identity => identity.uid === 'owner' });
  await assert.rejects(service.createOrganization({ ...user, emailVerified: false }, 'Empresa', 'business@example.com'), /invalid-request/);
  assert.deepEqual(await service.createOrganization(user, ' Empresa ', 'BUSINESS@example.com'), { organizationId: 'org' });
  assert.deepEqual(saved, { id: 'org', ownerId: 'owner', name: 'Empresa', contactEmail: 'business@example.com' });
});

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { BusinessService } from './business-service.mjs';

function fixture(withMail = true) {
  const organization = { id: 'org', ownerId: 'owner', name: 'Equipe', contactEmail: 'owner@example.com' };
  const records = new Map([['owner', { organizationId: 'org', userId: 'owner', role: 'owner', active: true }]]);
  const invites = new Map();
  let profile;
  let asset;
  let storedCredential;
  let storedMail = withMail ? { version: 1, iv: 'iv', ciphertext: 'cipher', providerAccountId: 'id', email: 'owner@example.com' } : undefined;
  const sent = [];
  const tx = {
    organization: async id => id === 'org' ? organization : null,
    membership: async (_, id) => records.get(id),
    userOrganizations: async id => records.has(id) ? ['org'] : [],
    activeMembers: async () => [...records.values()].filter(item => item.active || item.revocationState === 'pending'),
    occupiedSeats: async () => [...records.values()].filter(x => x.active).length,
    createInvitation: async value => { invites.set(value.id, value); },
    invitation: async (_, id) => invites.get(id),
    addMember: async value => { records.set(value.userId, value); },
    markInvitationAccepted: async (_, id, userId) => { invites.set(id, { ...invites.get(id), state: 'accepted', userId }); },
    publishProfile: async value => { profile = value; },
    latestProfile: async () => profile,
    createAsset: async value => { asset = value; },
    asset: async () => asset,
    updateOrganization: async (_, updates) => { Object.assign(organization, updates); },
    setOneDriveCredential: async (_, value) => { storedCredential = value; },
    oneDriveCredential: async () => storedCredential,
    setGoogleMailCredential: async (_, value) => { storedMail = value; },
    googleMailCredential: async () => storedMail,
  };
  const service = new BusinessService({ verifyToken: async token => token, transaction: fn => fn(tx), newId: () => 'invite', clock: () => 100,
    prepareMailDelivery: async ({ mail }) => ({ record: mail, send: async values => { sent.push(values); } }) });
  return { service, records, invites, sent, storedCredential: () => storedCredential, storedMail: () => storedMail,
    replaceMail: value => { storedMail = value; } };
}

test('a verified invited user can join only as member, and cannot reuse invitation', async () => {
  const { service, records, sent } = fixture();
  await service.invite({ uid: 'owner' }, 'org', ' PERSON@example.com ');
  assert.equal(sent[0].recipientEmail, 'person@example.com');
  const recipient = { uid: 'member', email: 'person@example.com', emailVerified: true };
  assert.deepEqual(await service.accept(recipient, 'org', 'invite'), { organizationId: 'org' });
  assert.equal(records.get('member').role, 'member');
  await assert.rejects(service.accept(recipient, 'org', 'invite'), /invalid-invitation/);
});

test('a revoked inviter cannot admit a user and missing mail cannot create an invitation', async () => {
  const { service, records } = fixture();
  await service.invite({ uid: 'owner' }, 'org', 'person@example.com');
  records.get('owner').active = false;
  await assert.rejects(service.accept({ uid: 'member', email: 'person@example.com', emailVerified: true }, 'org', 'invite'), /invalid-invitation/);
  const missing = fixture(false);
  await assert.rejects(missing.service.invite({ uid: 'owner' }, 'org', 'person@example.com'), /mail-not-configured/);
  assert.equal(missing.invites.size, 0);
});

test('a member cannot rejoin while provider access revocation is pending', async () => {
  const { service, records } = fixture();
  await service.invite({ uid: 'owner' }, 'org', 'person@example.com');
  records.set('member', { organizationId: 'org', userId: 'member', role: 'member', active: false, revocationState: 'pending' });
  await assert.rejects(service.accept({ uid: 'member', email: 'person@example.com', emailVerified: true }, 'org', 'invite'), /revocation-pending/);
});

test('an invitation is not sent when the sender changes during preparation', async () => {
  const { service, invites, sent, replaceMail } = fixture();
  service.prepareMailDelivery = async ({ mail }) => {
    replaceMail({ ...mail, ciphertext: 'new-credential' });
    return { record: mail, send: async value => { sent.push(value); } };
  };
  await assert.rejects(service.invite({ uid: 'owner' }, 'org', 'person@example.com'), /mail-configuration-changed/);
  assert.equal(invites.size, 0);
  assert.equal(sent.length, 0);
});

test('only the owner may connect the verified organization sender', async () => {
  const { service, records, storedMail } = fixture(false);
  service.prepareGoogleMail = async () => ({ version: 1, iv: 'iv', ciphertext: 'encrypted', providerAccountId: 'id', email: 'other@example.com' });
  records.set('member', { organizationId: 'org', userId: 'member', role: 'member', active: true });
  await assert.rejects(service.connectGoogleMail({ uid: 'member' }, 'org', 'secret'), /forbidden/);
  await assert.rejects(service.connectGoogleMail({ uid: 'owner' }, 'org', 'secret'), /mailbox-mismatch/);
  assert.equal(storedMail(), undefined);
  service.prepareGoogleMail = async () => ({ version: 1, iv: 'iv', ciphertext: 'encrypted', providerAccountId: 'id', email: 'owner@example.com' });
  assert.deepEqual(await service.connectGoogleMail({ uid: 'owner' }, 'org', 'secret'), { connected: true });
  assert.equal(JSON.stringify(storedMail()).includes('secret'), false);
});

test('only the owner can connect a verified and encrypted OneDrive credential', async () => {
  const { service, records, storedCredential } = fixture();
  let calls = 0;
  service.prepareOneDrive = async () => {
    calls++;
    return { version: 1, iv: 'iv', ciphertext: 'encrypted', driveId: 'drive', providerAccountId: 'account' };
  };
  records.set('member', { organizationId: 'org', userId: 'member', role: 'member', active: true });
  await assert.rejects(service.connectOneDrive({ uid: 'member' }, 'org', 'secret'), /forbidden/);
  assert.equal(calls, 0);
  assert.deepEqual(await service.connectOneDrive({ uid: 'owner' }, 'org', 'secret'), { connected: true });
  assert.equal(JSON.stringify(storedCredential()).includes('secret'), false);
  service.prepareOneDrive = async () => ({ version: 1, iv: 'iv', ciphertext: 'other', driveId: 'another-drive', providerAccountId: 'another' });
  await assert.rejects(service.connectOneDrive({ uid: 'owner' }, 'org', 'secret'), /storage-account-change-requires-migration/);
  assert.equal(storedCredential().ciphertext, 'encrypted');
  service.prepareOneDrive = async () => {
    records.get('owner').active = false;
    return { version: 1, iv: 'iv', ciphertext: 'replacement', driveId: 'drive', providerAccountId: 'account' };
  };
  await assert.rejects(service.connectOneDrive({ uid: 'owner' }, 'org', 'secret'), /forbidden/);
  assert.equal(storedCredential().ciphertext, 'encrypted');
});

test('organization discovery checks live membership rather than trusting an index', async () => {
  const { service, records } = fixture();
  records.set('member', { organizationId: 'org', userId: 'member', role: 'member', active: true });
  assert.deepEqual((await service.myOrganizations({ uid: 'member' })).organizations.map(x => x.id), ['org']);
  records.get('member').active = false;
  assert.deepEqual((await service.myOrganizations({ uid: 'member' })).organizations, []);
  assert.deepEqual((await service.myOrganizations({ uid: 'stranger' })).organizations, []);
});

test('only a manager may list active members and their verified email addresses', async () => {
  const { service, records } = fixture();
  records.set('member', { organizationId: 'org', userId: 'member', role: 'member', active: true, email: 'person@example.com' });
  records.set('revoked', { organizationId: 'org', userId: 'revoked', role: 'member', active: false, email: 'old@example.com' });
  records.set('pending', { organizationId: 'org', userId: 'pending', role: 'member', active: false, revocationState: 'pending' });
  const result = await service.listMembers({ uid: 'owner' }, 'org');
  assert.deepEqual(result.members.map(item => item.userId).sort(), ['member', 'owner', 'pending']);
  assert.equal(result.members.find(item => item.userId === 'member').email, 'person@example.com');
  assert.equal(result.members.find(item => item.userId === 'pending').revocationPending, true);
  await assert.rejects(service.listMembers({ uid: 'member' }, 'org'), /forbidden/);
  await assert.rejects(service.listMembers({ uid: 'outsider' }, 'org'), /forbidden/);
});

test('only managers can edit organization data and contact email is withheld from members', async () => {
  const { service, records } = fixture();
  records.set('member', { organizationId: 'org', userId: 'member', role: 'member', active: true });
  const updated = await service.updateOrganization({ uid: 'owner' }, 'org', ' Equipe Nova ', 'TEAM@example.com', '');
  assert.equal(updated.contactEmail, 'team@example.com');
  const memberView = await service.readOrganization({ uid: 'member' }, 'org');
  assert.deepEqual(memberView, { id: 'org', name: 'Equipe Nova', photoAssetId: '' });
  await assert.rejects(service.updateOrganization({ uid: 'member' }, 'org', 'Fraude', 'bad@example.com', ''), /forbidden/);
  await assert.rejects(service.updateOrganization({ uid: 'owner' }, 'org', 'Nome', 'bad@example.com', 'missing'), /invalid-request/);
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

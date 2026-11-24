import { test } from 'node:test';
import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import { firestoreTransactions } from './business-firestore.mjs';
import { BusinessService } from './business-service.mjs';
import { createBusinessApp } from './business-app.mjs';
import { createFirebaseVerifier } from './business-firebase-identity.mjs';
import { generateKeyPair, SignJWT } from 'jose';
import { createBusinessWorker } from './business-worker.mjs';

test('owner folder provisioning commits its recovery marker and verified binding', { skip: !process.env.FIRESTORE_EMULATOR_HOST }, async () => {
  const origin = `http://${process.env.FIRESTORE_EMULATOR_HOST}`;
  const projectId = 'demo-photomark-business', org = randomUUID();
  const transaction = firestoreTransactions({ projectId, accessToken: async () => 'owner', emulatorOrigin: origin });
  const identity = { uid: 'owner', email: 'owner@example.com', emailVerified: true };
  const service = new BusinessService({ transaction, verifyToken: async token => token, newId: () => org, clock: () => 100,
    canCreateOrganization: async () => true, prepareOwnerFolder: async ({ storage, marker, name, email }) => {
      assert.match(marker, /^[0-9a-f-]{36}$/);
      assert.equal(name, 'owner');
      assert.equal(email, identity.email);
      return { driveId: 'drive', folderId: 'folder', parentId: 'parent', memberIdentityId: 'graph-owner', ownerCredential: storage };
    } });
  await service.createOrganization(identity, 'Equipe', identity.email);
  await transaction(tx => tx.setOneDriveCredential(org, { version: 1, iv: 'iv', ciphertext: 'cipher', providerAccountId: 'graph-owner', driveId: 'drive' }));
  assert.deepEqual(await service.provisionOwnerFolder(identity, org), { ready: true });
  const member = await transaction(tx => tx.membership(org, identity.uid));
  assert.equal(member.storageStatus, 'granted');
  assert.equal(member.oneDriveFolderId, 'folder');
  assert.equal(member.oneDriveCreationMarker, org);
  assert.equal(member.oneDriveProvisionEmail, identity.email);
});

test('isolated worker creates a verified owner organization with an emulator', { skip: !process.env.FIRESTORE_EMULATOR_HOST }, async () => {
  const origin = `http://${process.env.FIRESTORE_EMULATOR_HOST}`;
  const projectId = 'demo-photomark-business';
  const env = { PHOTOMARK_FIREBASE_PROJECT_ID: projectId, BUSINESS_OWNER_EMAIL: 'owner@example.com',
    BUSINESS_IP_LIMIT: { limit: async () => ({ success: true }) }, BUSINESS_UID_LIMIT: { limit: async () => ({ success: true }) } };
  let identity = { uid: 'owner', email: 'owner@example.com', emailVerified: true };
  const worker = createBusinessWorker(env, { authenticate: async () => identity, serverAccessToken: async () => 'owner', emulatorOrigin: origin });
  const request = body => { const text = JSON.stringify(body); return new Request('https://business.test/v1/organizations', {
    method: 'POST', body: text, headers: { authorization: 'Bearer token', 'content-type': 'application/json',
      'content-length': String(Buffer.byteLength(text)), 'cf-connecting-ip': '127.0.0.1' } }); };
  const response = await worker(request({ name: 'Equipe', contactEmail: 'contact@example.com' }));
  assert.equal(response.status, 201);
  const { organizationId } = await response.json();
  const root = `${origin}/v1/projects/${projectId}/databases/(default)/documents/organizations/${organizationId}`;
  const member = await fetch(`${root}/members/owner`, { headers: { authorization: 'Bearer owner' } });
  assert.equal((await member.json()).fields.role.stringValue, 'owner');
  identity = { ...identity, email: 'other@example.com' };
  assert.equal((await worker(request({ name: 'Equipe', contactEmail: 'contact@example.com' }))).status, 403);
});

test('organization bootstrap creates owner and seat counter atomically', { skip: !process.env.FIRESTORE_EMULATOR_HOST }, async () => {
  const origin = `http://${process.env.FIRESTORE_EMULATOR_HOST}`;
  const projectId = 'demo-photomark-business';
  const org = `org-${randomUUID()}`;
  const transaction = firestoreTransactions({ projectId, accessToken: async () => 'owner', emulatorOrigin: origin });
  const service = new BusinessService({ transaction, verifyToken: async token => token, newId: () => org, clock: () => 100, canCreateOrganization: async () => true });
  const identity = { uid: 'owner', email: 'owner@example.com', emailVerified: true };
  assert.deepEqual(await service.createOrganization(identity, 'Equipe', 'business@example.com'), { organizationId: org });
  const root = `${origin}/v1/projects/${projectId}/databases/(default)/documents/organizations/${org}`;
  const result = await fetch(`${root}/members/owner`, { headers: { authorization: 'Bearer owner' } });
  assert.equal((await result.json()).fields.role.stringValue, 'owner');
  await assert.rejects(service.createOrganization(identity, 'Outra', 'business@example.com'));
});

test('Firestore emulator commits a real invitation and member transaction', { skip: !process.env.FIRESTORE_EMULATOR_HOST }, async () => {
  const origin = `http://${process.env.FIRESTORE_EMULATOR_HOST}`;
  const projectId = 'demo-photomark-business';
  const root = `${origin}/v1/projects/${projectId}/databases/(default)/documents`;
  const org = `org-${randomUUID()}`;
  const write = async (path, fields) => {
    const res = await fetch(`${root}/${path}`, { method: 'PATCH', headers: { authorization: 'Bearer owner', 'content-type': 'application/json' }, body: JSON.stringify({ fields }) });
    assert.equal(res.ok, true, `seed failed: ${res.status}`);
  };
  const s = stringValue => ({ stringValue });
  await write(`organizations/${org}`, { id: s(org), ownerId: s('owner'), name: s('Equipe'), contactEmail: s('org@example.com') });
  await write(`organizations/${org}/members/owner`, { organizationId: s(org), userId: s('owner'), role: s('owner'), active: { booleanValue: true } });
  await write(`organizations/${org}/state/seats`, { count: { integerValue: '1' } });
  await write(`organizations/${org}/private/gmail`, { version: { integerValue: '1' }, iv: s('iv'), ciphertext: s('cipher'), providerAccountId: s('google'), email: s('org@example.com') });
  const transaction = firestoreTransactions({ projectId, accessToken: async () => 'owner', emulatorOrigin: origin });
  const service = new BusinessService({ transaction, verifyToken: async token => token, newId: () => 'test-invite', clock: () => 100,
    prepareMailDelivery: async ({ mail }) => ({ record: mail, send: async () => {} }) });
  await service.invite({ uid: 'owner' }, org, 'member@example.com');
  await service.accept({ uid: 'member', email: 'member@example.com', emailVerified: true }, org, 'test-invite');
  await service.publishProfile({ uid: 'owner' }, org, '{"template":"original"}');
  const logo = 'iVBORw0KGgo=';
  await service.uploadAsset({ uid: 'owner' }, org, 'image/png', logo);
  assert.equal((await service.readAsset({ uid: 'member' }, org, 'test-invite')).base64, logo);
  assert.equal((await service.readProfile({ uid: 'member' }, org)).layoutJSON, '{"template":"original"}');
  await assert.rejects(service.publishProfile({ uid: 'member' }, org, '{}'), /forbidden/);
  const res = await fetch(`${root}/organizations/${org}/state/seats`, { headers: { authorization: 'Bearer owner' } });
  assert.equal((await res.json()).fields.count.integerValue, '2');
  await assert.rejects(service.accept({ uid: 'member', email: 'member@example.com', emailVerified: true }, org, 'test-invite'), /invalid-invitation/);
});

test('authenticated HTTP invitation and acceptance use the transactional database', { skip: !process.env.FIRESTORE_EMULATOR_HOST }, async () => {
  const origin = `http://${process.env.FIRESTORE_EMULATOR_HOST}`;
  const projectId = 'demo-photomark-business';
  const root = `${origin}/v1/projects/${projectId}/databases/(default)/documents`;
  const org = `org-${randomUUID()}`;
  const s = stringValue => ({ stringValue });
  const write = async (path, fields) => {
    const res = await fetch(`${root}/${path}`, { method: 'PATCH', headers: { authorization: 'Bearer owner', 'content-type': 'application/json' }, body: JSON.stringify({ fields }) });
    assert.equal(res.ok, true);
  };
  await write(`organizations/${org}`, { id: s(org), ownerId: s('owner') });
  await write(`organizations/${org}/members/owner`, { organizationId: s(org), userId: s('owner'), role: s('owner'), active: { booleanValue: true } });
  await write(`organizations/${org}/state/seats`, { count: { integerValue: '1' } });
  await write(`organizations/${org}`, { id: s(org), ownerId: s('owner'), name: s('Equipe'), contactEmail: s('org@example.com') });
  await write(`organizations/${org}/private/gmail`, { version: { integerValue: '1' }, iv: s('iv'), ciphertext: s('encrypted-mail'), providerAccountId: s('google'), email: s('org@example.com') });
  const keys = await generateKeyPair('RS256');
  const seconds = 1800000000;
  const authenticate = createFirebaseVerifier({ projectId, now: () => seconds * 1000, resolveKey: async () => keys.publicKey });
  let allowRevocation = false;
  const app = createBusinessApp({ projectId, authenticate, serverAccessToken: async () => 'owner', emulatorOrigin: origin,
    preAuthLimit: async () => true, rateLimit: async () => true, newId: () => 'invite', clock: () => 100,
    prepareOneDrive: async () => ({ version: 1, iv: 'iv', ciphertext: 'encrypted', providerAccountId: 'account', driveId: 'drive' }),
    prepareGoogleMail: async () => ({ version: 1, iv: 'iv', ciphertext: 'encrypted-mail', providerAccountId: 'google', email: 'org@example.com' }),
    prepareMailDelivery: async ({ mail }) => ({ record: mail, send: async () => {} }),
    revokeMemberStorage: async () => allowRevocation });
  const token = async (uid, email) => new SignJWT({ auth_time: seconds - 1, email, email_verified: true })
    .setProtectedHeader({ alg: 'RS256', kid: 'key1' }).setIssuer(`https://securetoken.google.com/${projectId}`)
    .setAudience(projectId).setSubject(uid).setIssuedAt(seconds - 1).setExpirationTime(seconds + 60).sign(keys.privateKey);
  const req = (path, access, object) => {
    const body = JSON.stringify(object);
    return new Request(`https://test.invalid${path}`, { method: 'POST', body, headers: { authorization: `Bearer ${access}`,
      'content-type': 'application/json', 'content-length': String(Buffer.byteLength(body)) } });
  };
  const base = `/v1/organizations/${org}/invitations`;
  const ownerToken = await token('owner', 'owner@example.com');
  const memberToken = await token('member', 'member@example.com');
  assert.equal((await app(req(base, ownerToken, { email: 'member@example.com' }))).status, 201);
  assert.equal((await app(req(`${base}/invite/accept`, memberToken, {}))).status, 200);
  assert.equal((await app(req(`${base}/invite/accept`, memberToken, {}))).status, 403);
  const mine = await app(req('/v1/organizations/mine', memberToken, {}));
  assert.equal(mine.status, 200);
  assert.ok((await mine.json()).organizations.some(item => item.id === org && item.role === 'member'));
  const membersPath = `/v1/organizations/${org}/members/list`;
  const membersResponse = await app(req(membersPath, ownerToken, {}));
  assert.equal(membersResponse.status, 200);
  const members = (await membersResponse.json()).members;
  assert.deepEqual(members.map(member => member.userId).sort(), ['member', 'owner']);
  assert.equal(members.find(member => member.userId === 'member').email, 'member@example.com');
  assert.equal((await app(req(membersPath, memberToken, {}))).status, 403);
  const storagePath = `/v1/organizations/${org}/storage/onedrive/connect`;
  assert.equal((await app(req(storagePath, memberToken, { refreshToken: 'token-private' }))).status, 403);
  assert.equal((await app(req(storagePath, ownerToken, { refreshToken: 'token-private' }))).status, 200);
  const saved = await fetch(`${root}/organizations/${org}/private/onedrive`, { headers: { authorization: 'Bearer owner' } });
  const persisted = await saved.json();
  assert.equal(persisted.fields.ciphertext.stringValue, 'encrypted');
  assert.equal(JSON.stringify(persisted).includes('token-private'), false);
  const asset = `/v1/organizations/${org}/assets`;
  assert.equal((await app(req(`${asset}/upload`, ownerToken, { mimeType: 'image/png', base64: 'iVBORw0KGgo=' }))).status, 201);
  const logo = await app(req(`${asset}/invite/read`, memberToken, {}));
  assert.equal((await logo.json()).base64, 'iVBORw0KGgo=');
  const settings = `/v1/organizations/${org}/settings`;
  assert.equal((await app(req(`${settings}/update`, ownerToken, { name: 'Equipe', contactEmail: 'org@example.com', photoAssetId: 'invite' }))).status, 200);
  const memberSettings = await (await app(req(`${settings}/read`, memberToken, {}))).json();
  assert.equal(memberSettings.name, 'Equipe');
  assert.equal(memberSettings.photoAssetId, 'invite');
  assert.equal(memberSettings.contactEmail, undefined);
  assert.equal((await app(req(`${settings}/update`, memberToken, { name: 'Alterado', contactEmail: 'x@example.com', photoAssetId: '' }))).status, 403);
  const mailPath = `/v1/organizations/${org}/mail/gmail/connect`;
  assert.equal((await app(req(mailPath, memberToken, { refreshToken: 'mail-private' }))).status, 403);
  assert.equal((await app(req(mailPath, ownerToken, { refreshToken: 'mail-private' }))).status, 200);
  const savedMail = await fetch(`${root}/organizations/${org}/private/gmail`, { headers: { authorization: 'Bearer owner' } });
  assert.equal((await savedMail.json()).fields.ciphertext.stringValue, 'encrypted-mail');
  const profile = `/v1/organizations/${org}/profile`;
  const layoutJSON = '{"logoName":"business-asset:invite"}';
  assert.equal((await app(req(`${profile}/publish`, ownerToken, { layoutJSON }))).status, 201);
  assert.equal((await app(req(`${profile}/publish`, memberToken, { layoutJSON }))).status, 403);
  const current = await app(req(`${profile}/read`, memberToken, {}));
  assert.equal((await current.json()).layoutJSON, layoutJSON);
  const count = await fetch(`${root}/organizations/${org}/state/seats`, { headers: { authorization: 'Bearer owner' } });
  assert.equal((await count.json()).fields.count.integerValue, '2');
  const removal = `/v1/organizations/${org}/members/member/remove`;
  assert.equal((await app(req(removal, memberToken, {}))).status, 403);
  assert.deepEqual(await (await app(req(removal, ownerToken, {}))).json(), { complete: true });
  assert.deepEqual(await (await app(req(removal, ownerToken, {}))).json(), { complete: true });
  const after = await fetch(`${root}/organizations/${org}/state/seats`, { headers: { authorization: 'Bearer owner' } });
  assert.equal((await after.json()).fields.count.integerValue, '1');
  const memberOrgs = await (await app(req('/v1/organizations/mine', memberToken, {}))).json();
  assert.equal(memberOrgs.organizations.some(item => item.id === org), false);
  await write(`organizations/${org}/members/member2`, { organizationId: s(org), userId: s('member2'), role: s('member'),
    active: { booleanValue: true }, storageStatus: s('granted') });
  await write(`organizations/${org}/state/seats`, { count: { integerValue: '2' } });
  const pendingRemoval = `/v1/organizations/${org}/members/member2/remove`;
  assert.equal((await app(req(pendingRemoval, ownerToken, {}))).status, 202);
  const pendingMembers = (await (await app(req(membersPath, ownerToken, {}))).json()).members;
  assert.equal(pendingMembers.find(item => item.userId === 'member2').revocationPending, true);
  allowRevocation = true;
  assert.deepEqual(await (await app(req(pendingRemoval, ownerToken, {}))).json(), { complete: true });
  const finalCount = await fetch(`${root}/organizations/${org}/state/seats`, { headers: { authorization: 'Bearer owner' } });
  assert.equal((await finalCount.json()).fields.count.integerValue, '1');
});

test('capture reservation binds the authenticated member and protects idempotency', { skip: !process.env.FIRESTORE_EMULATOR_HOST }, async () => {
  const origin = `http://${process.env.FIRESTORE_EMULATOR_HOST}`;
  const projectId = 'demo-photomark-business';
  const root = `${origin}/v1/projects/${projectId}/databases/(default)/documents`;
  const org = randomUUID(), capture = randomUUID();
  const s = stringValue => ({ stringValue });
  const write = async (path, fields) => {
    const response = await fetch(`${root}/${path}`, { method: 'PATCH', headers: { authorization: 'Bearer owner', 'content-type': 'application/json' }, body: JSON.stringify({ fields }) });
    assert.equal(response.status, 200);
  };
  await write(`organizations/${org}`, { id: s(org), ownerId: s('owner'), name: s('Equipe') });
  for (const uid of ['member-a', 'member-b']) {
    await write(`organizations/${org}/members/${uid}`, { organizationId: s(org), userId: s(uid), role: s('member'), active: { booleanValue: true },
      storageStatus: s('granted'), oneDriveFolderId: s(`folder-${uid}`), oneDriveParentId: s('parent'), oneDriveMemberIdentityId: s(`graph-${uid}`) });
  }
  await write(`organizations/${org}/private/onedrive`, { driveId: s('drive'), providerAccountId: s('owner-graph'),
    version: { integerValue: '1' }, iv: s('iv'), ciphertext: s('cipher') });
  const app = createBusinessApp({ projectId, emulatorOrigin: origin, serverAccessToken: async () => 'owner',
    authenticate: async token => ({ uid: token, emailVerified: true }), preAuthLimit: async () => true, rateLimit: async () => true,
    prepareUpload: async ({ storage }) => ({ session: { version: 1, iv: 'session-iv', ciphertext: 'encrypted-session' },
      expiresAt: Date.now() + 60000, ownerCredential: { ...storage, iv: 'new-iv', ciphertext: 'new-cipher' } }),
    processUploadChunk: async ({ bytes }) => { assert.equal(bytes.length, 123); return { state: 'uploaded-unverified', itemId: 'remote-item' }; },
    verifyUpload: async ({ storage }) => ({ verified: true, ownerCredential: storage }) });
  const filename = `23-11-2026 - OneDrive - 18-35-02 - ${capture}.1795470002.${org}.VGVzdGU-stamped.jpg`;
  const payload = { captureId: capture, filename, byteCount: 123, sha256: 'a'.repeat(64) };
  const request = (uid, bodyValue) => {
    const body = JSON.stringify(bodyValue);
    return new Request(`https://test.invalid/v1/organizations/${org}/captures/reserve`, { method: 'POST', body,
      headers: { authorization: `Bearer ${uid}`, 'content-type': 'application/json', 'content-length': String(Buffer.byteLength(body)) } });
  };
  assert.equal((await app(request('member-a', payload))).status, 200);
  assert.equal((await app(request('member-a', payload))).status, 200);
  assert.equal((await app(request('member-b', payload))).status, 403);
  const record = await fetch(`${root}/organizations/${org}/captures/${capture}-stamped`, { headers: { authorization: 'Bearer owner' } });
  const fields = (await record.json()).fields;
  assert.equal(fields.authorId.stringValue, 'member-a');
  assert.equal(fields.folderId.stringValue, 'folder-member-a');
  const startBody = '{}';
  const start = uid => new Request(`https://test.invalid/v1/organizations/${org}/captures/${capture}/stamped/start`, { method: 'POST', body: startBody,
    headers: { authorization: `Bearer ${uid}`, 'content-type': 'application/json', 'content-length': String(startBody.length) } });
  const started = await app(start('member-a'));
  assert.deepEqual(await started.json(), { state: 'uploading', nextOffset: 0 });
  assert.deepEqual(await (await app(start('member-a'))).json(), { state: 'uploading', nextOffset: 0 });
  assert.equal((await app(start('member-b'))).status, 403);
  const chunk = uid => new Request(`https://test.invalid/v1/organizations/${org}/captures/${capture}/stamped/chunk`, { method: 'POST', body: new Uint8Array(123),
    headers: { authorization: `Bearer ${uid}`, 'content-type': 'application/octet-stream', 'content-length': '123', 'x-upload-offset': '0' } });
  assert.equal((await app(chunk('member-b'))).status, 403);
  assert.deepEqual(await (await app(chunk('member-a'))).json(), { state: 'verifying', nextOffset: 123 });
  const after = await fetch(`${root}/organizations/${org}/captures/${capture}-stamped`, { headers: { authorization: 'Bearer owner' } });
  assert.equal((await after.json()).fields.state.stringValue, 'verifying');
  const verify = uid => new Request(`https://test.invalid/v1/organizations/${org}/captures/${capture}/stamped/verify`, { method: 'POST', body: startBody,
    headers: { authorization: `Bearer ${uid}`, 'content-type': 'application/json', 'content-length': String(startBody.length) } });
  assert.equal((await app(verify('member-b'))).status, 403);
  assert.deepEqual(await (await app(verify('member-a'))).json(), { state: 'verified', nextOffset: 123 });
});

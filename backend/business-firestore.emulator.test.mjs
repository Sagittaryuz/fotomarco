import { test } from 'node:test';
import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import { firestoreTransactions } from './business-firestore.mjs';
import { BusinessService } from './business-service.mjs';
import { createBusinessApp } from './business-app.mjs';
import { createFirebaseVerifier } from './business-firebase-identity.mjs';
import { generateKeyPair, SignJWT } from 'jose';
import { createBusinessWorker } from './business-worker.mjs';

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
  await write(`organizations/${org}`, { id: s(org), ownerId: s('owner') });
  await write(`organizations/${org}/members/owner`, { organizationId: s(org), userId: s('owner'), role: s('owner'), active: { booleanValue: true } });
  await write(`organizations/${org}/state/seats`, { count: { integerValue: '1' } });
  const transaction = firestoreTransactions({ projectId, accessToken: async () => 'owner', emulatorOrigin: origin });
  const service = new BusinessService({ transaction, verifyToken: async token => token, newId: () => 'test-invite', clock: () => 100 });
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
  const keys = await generateKeyPair('RS256');
  const seconds = 1800000000;
  const authenticate = createFirebaseVerifier({ projectId, now: () => seconds * 1000, resolveKey: async () => keys.publicKey });
  const app = createBusinessApp({ projectId, authenticate, serverAccessToken: async () => 'owner', emulatorOrigin: origin,
    preAuthLimit: async () => true, rateLimit: async () => true, newId: () => 'invite', clock: () => 100 });
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
  const profile = `/v1/organizations/${org}/profile`;
  const layoutJSON = '{"logoName":"business-asset:invite"}';
  assert.equal((await app(req(`${profile}/publish`, ownerToken, { layoutJSON }))).status, 201);
  assert.equal((await app(req(`${profile}/publish`, memberToken, { layoutJSON }))).status, 403);
  const current = await app(req(`${profile}/read`, memberToken, {}));
  assert.equal((await current.json()).layoutJSON, layoutJSON);
  const count = await fetch(`${root}/organizations/${org}/state/seats`, { headers: { authorization: 'Bearer owner' } });
  assert.equal((await count.json()).fields.count.integerValue, '2');
});

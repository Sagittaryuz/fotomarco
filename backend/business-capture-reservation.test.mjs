import { test } from 'node:test';
import assert from 'node:assert/strict';
import { BusinessService } from './business-service.mjs';

const orgId = '11111111-1111-4111-8111-111111111111';
const captureId = '22222222-2222-4222-8222-222222222222';
const name = `23-11-2026 - OneDrive - 18-35-02 - ${captureId}.1795470002.${orgId}.VGVzdGU-stamped.jpg`;
const original = name.replace('-stamped.jpg', '-original.heic');
const sha = 'a'.repeat(64);

function fixture() {
  const org = { id: orgId, ownerId: 'owner' };
  const members = new Map(['member', 'other'].map(uid => [uid, { organizationId: orgId, userId: uid, role: 'member', active: true,
    storageStatus: 'granted', oneDriveFolderId: `folder-${uid}`, oneDriveParentId: 'parent', oneDriveMemberIdentityId: `graph-${uid}` }]));
  const captures = new Map();
  let ownerStorage = { driveId: 'drive', providerAccountId: 'owner-graph', version: 1, iv: 'iv', ciphertext: 'cipher' };
  const tx = { organization: async () => org, membership: async (_, uid) => members.get(uid),
    oneDriveCredential: async () => ownerStorage, setOneDriveCredential: async (_, value) => { ownerStorage = value; },
    capture: async (_, id) => captures.get(id), createCapture: async value => { captures.set(value.recordId, value); },
    beginCaptureUpload: async (_, id, session, expiresAt) => { Object.assign(captures.get(id), { state: 'uploading', nextOffset: 0, sessionExpiresAt: expiresAt,
      sessionVersion: session.version, sessionIv: session.iv, sessionCiphertext: session.ciphertext }); },
    leaseCaptureChunk: async (_, id, leaseId, expiresAt) => { Object.assign(captures.get(id), { leaseId, leaseExpiresAt: expiresAt }); },
    completeCaptureChunk: async (_, id, result, size) => { Object.assign(captures.get(id), result.state === 'pending' ?
      { state: 'uploading', nextOffset: result.nextOffset, leaseId: '', leaseExpiresAt: 0 } :
      { state: 'verifying', nextOffset: size, remoteItemId: result.itemId, leaseId: '', leaseExpiresAt: 0 }); },
    markCaptureVerified: async (_, id, verifiedAt) => { Object.assign(captures.get(id), { state: 'verified', verifiedAt }); },
    reconcileCapture: async (_, id, result, size, verifiedAt) => { Object.assign(captures.get(id), result.state === 'verified' ?
      { state: 'verified', nextOffset: size, remoteItemId: result.itemId, verifiedAt, leaseId: '', leaseExpiresAt: 0 } :
      { state: result.state === 'restart' ? 'reserved' : 'uploading', nextOffset: result.state === 'restart' ? 0 : result.nextOffset, leaseId: '', leaseExpiresAt: 0 }); } };
  const service = new BusinessService({ verifyToken: async identity => identity, transaction: action => action(tx),
    newId: () => 'unused', clock: () => 100 });
  return { service, captures, members };
}

test('reconciles a lost final response only after the provider verifies the file and membership', async () => {
  const { service, captures, members } = fixture();
  const user = { uid: 'member', emailVerified: true };
  await service.reserveCapture(user, orgId, captureId, name, 1, sha);
  service.prepareUpload = async ({ storage }) => ({ session: { version: 1, iv: 'iv', ciphertext: 'secret' }, expiresAt: 1000, ownerCredential: storage });
  await service.startCaptureUpload(user, orgId, captureId, 'stamped');
  service.reconcileUpload = async ({ storage }) => ({ state: 'verified', itemId: 'verified-item', ownerCredential: storage });
  assert.deepEqual(await service.reconcileCapture(user, orgId, captureId, 'stamped'), { state: 'verified', nextOffset: 1 });
  assert.equal(captures.get(`${captureId}-stamped`).remoteItemId, 'verified-item');
  members.get('member').active = false;
  await assert.rejects(service.reconcileCapture(user, orgId, captureId, 'stamped'), /forbidden/);
});

test('does not restart an uncertain upload before the provider session grace period', async () => {
  const { service, captures } = fixture();
  const user = { uid: 'member', emailVerified: true };
  await service.reserveCapture(user, orgId, captureId, name, 1, sha);
  service.prepareUpload = async ({ storage }) => ({ session: { version: 1, iv: 'iv', ciphertext: 'secret' }, expiresAt: 1000, ownerCredential: storage });
  await service.startCaptureUpload(user, orgId, captureId, 'stamped');
  service.reconcileUpload = async ({ storage }) => ({ state: 'restart', ownerCredential: storage });
  await assert.rejects(service.reconcileCapture(user, orgId, captureId, 'stamped'), /upload-result-uncertain/);
  const capture = captures.get(`${captureId}-stamped`);
  assert.equal(capture.state, 'uploading');
  service.clock = () => 700000;
  assert.deepEqual(await service.reconcileCapture(user, orgId, captureId, 'stamped'), { state: 'reserved', nextOffset: 0 });
  assert.equal(capture.state, 'reserved');
});

test('reserves original and stamped files separately and idempotently for their author', async () => {
  const { service, captures } = fixture();
  const user = { uid: 'member', emailVerified: true };
  assert.deepEqual(await service.reserveCapture(user, orgId, captureId, name, 123, sha), { captureId, variant: 'stamped', state: 'reserved' });
  assert.deepEqual(await service.reserveCapture(user, orgId, captureId, name, 123, sha), { captureId, variant: 'stamped', state: 'reserved' });
  assert.deepEqual(await service.reserveCapture(user, orgId, captureId, original, 456, sha), { captureId, variant: 'original', state: 'reserved' });
  assert.equal(captures.size, 2);
  assert.equal(captures.get(`${captureId}-stamped`).folderId, 'folder-member');
  await assert.rejects(service.reserveCapture({ uid: 'other', emailVerified: true }, orgId, captureId, name, 123, sha), /capture-conflict/);
  await assert.rejects(service.reserveCapture(user, orgId, captureId, name, 124, sha), /capture-conflict/);
});

test('starts only an authorized capture session and never returns the bearer upload URL', async () => {
  const { service, captures, members } = fixture();
  const user = { uid: 'member', emailVerified: true };
  await service.reserveCapture(user, orgId, captureId, name, 123, sha);
  let calls = 0;
  service.prepareUpload = async ({ storage }) => {
    calls++;
    return { session: { version: 1, iv: 'session-iv', ciphertext: 'encrypted-session' }, expiresAt: 1000,
      ownerCredential: { ...storage, iv: 'new-iv', ciphertext: 'new-cipher' } };
  };
  assert.deepEqual(await service.startCaptureUpload(user, orgId, captureId, 'stamped'), { state: 'uploading', nextOffset: 0 });
  assert.deepEqual(await service.startCaptureUpload(user, orgId, captureId, 'stamped'), { state: 'uploading', nextOffset: 0 });
  assert.equal(calls, 1);
  assert.equal(captures.get(`${captureId}-stamped`).sessionCiphertext, 'encrypted-session');
  members.get('member').active = false;
  await assert.rejects(service.startCaptureUpload(user, orgId, captureId, 'stamped'), /forbidden/);
});

test('rechecks membership after preparing a provider session', async () => {
  const { service, captures, members } = fixture();
  const user = { uid: 'member', emailVerified: true };
  await service.reserveCapture(user, orgId, captureId, name, 123, sha);
  service.prepareUpload = async ({ storage }) => {
    members.get('member').active = false;
    return { session: { version: 1, iv: 'iv', ciphertext: 'cipher' }, expiresAt: 1000, ownerCredential: storage };
  };
  await assert.rejects(service.startCaptureUpload(user, orgId, captureId, 'stamped'), /forbidden/);
  assert.equal(captures.get(`${captureId}-stamped`).state, 'reserved');
});

test('serializes chunks, handles repeated offsets and requires later integrity verification', async () => {
  const { service, captures } = fixture();
  const user = { uid: 'member', emailVerified: true }, unit = 320 * 1024;
  await service.reserveCapture(user, orgId, captureId, name, unit + 1, sha);
  service.prepareUpload = async ({ storage }) => ({ session: { version: 1, iv: 'iv', ciphertext: 'secret' }, expiresAt: 1000, ownerCredential: storage });
  await service.startCaptureUpload(user, orgId, captureId, 'stamped');
  let calls = 0;
  service.processUploadChunk = async ({ offset, bytes }) => {
    calls++;
    return offset === 0 ? { state: 'pending', nextOffset: bytes.length } : { state: 'uploaded-unverified', itemId: 'item' };
  };
  assert.deepEqual(await service.sendCaptureChunk(user, orgId, captureId, 'stamped', 0, new Uint8Array(unit)), { state: 'uploading', nextOffset: unit });
  assert.deepEqual(await service.sendCaptureChunk(user, orgId, captureId, 'stamped', 0, new Uint8Array(unit)), { state: 'uploading', nextOffset: unit });
  assert.equal(calls, 1);
  assert.deepEqual(await service.sendCaptureChunk(user, orgId, captureId, 'stamped', unit, new Uint8Array(1)), { state: 'verifying', nextOffset: unit + 1 });
  assert.equal(captures.get(`${captureId}-stamped`).state, 'verifying');
});

test('revocation during an upload cannot mark a chunk complete', async () => {
  const { service, captures, members } = fixture();
  const user = { uid: 'member', emailVerified: true };
  await service.reserveCapture(user, orgId, captureId, name, 1, sha);
  service.prepareUpload = async ({ storage }) => ({ session: { version: 1, iv: 'iv', ciphertext: 'secret' }, expiresAt: 1000, ownerCredential: storage });
  await service.startCaptureUpload(user, orgId, captureId, 'stamped');
  service.processUploadChunk = async () => { members.get('member').active = false; return { state: 'uploaded-unverified', itemId: 'item' }; };
  await assert.rejects(service.sendCaptureChunk(user, orgId, captureId, 'stamped', 0, new Uint8Array(1)), /forbidden/);
  assert.equal(captures.get(`${captureId}-stamped`).state, 'uploading');
});

test('a capture becomes verified only after matching remote bytes and renewed membership', async () => {
  const { service, captures, members } = fixture();
  const user = { uid: 'member', emailVerified: true };
  await service.reserveCapture(user, orgId, captureId, name, 1, sha);
  service.prepareUpload = async ({ storage }) => ({ session: { version: 1, iv: 'iv', ciphertext: 'secret' }, expiresAt: 1000, ownerCredential: storage });
  await service.startCaptureUpload(user, orgId, captureId, 'stamped');
  service.processUploadChunk = async () => ({ state: 'uploaded-unverified', itemId: 'item' });
  await service.sendCaptureChunk(user, orgId, captureId, 'stamped', 0, new Uint8Array(1));
  service.verifyUpload = async () => { throw new Error('hash-mismatch'); };
  await assert.rejects(service.verifyCapture(user, orgId, captureId, 'stamped'), /hash-mismatch/);
  assert.equal(captures.get(`${captureId}-stamped`).state, 'verifying');
  service.verifyUpload = async ({ storage }) => { members.get('member').active = false; return { verified: true, ownerCredential: storage }; };
  await assert.rejects(service.verifyCapture(user, orgId, captureId, 'stamped'), /forbidden/);
  assert.equal(captures.get(`${captureId}-stamped`).state, 'verifying');
  members.get('member').active = true;
  service.verifyUpload = async ({ storage }) => ({ verified: true, ownerCredential: storage });
  assert.deepEqual(await service.verifyCapture(user, orgId, captureId, 'stamped'), { state: 'verified', nextOffset: 1 });
  assert.deepEqual(await service.verifyCapture(user, orgId, captureId, 'stamped'), { state: 'verified', nextOffset: 1 });
});

test('rejects a different organization, unverified or inactive users, and unready storage', async () => {
  const { service, members } = fixture();
  const user = { uid: 'member', emailVerified: true };
  await assert.rejects(service.reserveCapture(user, '33333333-3333-4333-8333-333333333333', captureId, name, 1, sha), /invalid-request/);
  await assert.rejects(service.reserveCapture({ ...user, emailVerified: false }, orgId, captureId, name, 1, sha), /invalid-request/);
  members.get('member').storageStatus = 'not-started';
  await assert.rejects(service.reserveCapture(user, orgId, captureId, name, 1, sha), /forbidden/);
  members.get('member').active = false;
  await assert.rejects(service.reserveCapture(user, orgId, captureId, name, 1, sha), /forbidden/);
});

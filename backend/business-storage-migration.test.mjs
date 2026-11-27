import test from 'node:test';
import assert from 'node:assert/strict';
import { createStorageMigration, applyVerifiedMigrationReceipt, canSwitchStorage } from './business-storage-migration.mjs';

const sha256 = 'a'.repeat(64);
const record = { organizationId: 'org', storageIdentity: 'old-drive', authorId: 'member', recordId: 'capture-stamped', remoteItemId: 'old-file', folderId: 'old-folder', state: 'verified', byteCount: 25, sha256 };
const readiness = { organizationId: 'org', currentSource: 'old-drive', currentDestination: 'new-drive', permissionsVerified: true, writesQuiesced: true,
  finalRecords: [record], finalSnapshotComplete: true, pendingUploads: 0 };
const sourceState = { organizationId: 'org', sourceSnapshotComplete: true, pendingUploads: 0 };

test('switch requires every verified copy, verified access and stopped writes', () => {
  const initial = createStorageMigration({ source: 'old-drive', destination: 'new-drive', records: [record], ...sourceState });
  assert.equal(canSwitchStorage(initial, readiness), false);
  const copied = applyVerifiedMigrationReceipt(initial, { recordId: record.recordId, targetItemId: 'new-file', targetFolderId: 'new-folder', byteCount: 25, sha256 });
  assert.equal(canSwitchStorage(copied, readiness), true);
  assert.equal(canSwitchStorage(copied, { ...readiness, permissionsVerified: false }), false);
  assert.equal(canSwitchStorage(copied, { ...readiness, writesQuiesced: false }), false);
  assert.equal(canSwitchStorage(copied, { ...readiness, currentSource: 'other' }), false);
  assert.equal(initial.items[0].targetItemId, null);
});

test('switch refuses captures added, changed or pending after the original snapshot', () => {
  const initial = createStorageMigration({ source: 'old-drive', destination: 'new-drive', records: [record], ...sourceState });
  const copied = applyVerifiedMigrationReceipt(initial, { recordId: record.recordId, targetItemId: 'new-file', targetFolderId: 'new-folder', byteCount: 25, sha256 });
  const added = { ...record, recordId: 'later-capture', remoteItemId: 'later-file' };
  for (const finalState of [
    { finalRecords: [record, added] }, { finalRecords: [] }, { finalRecords: [{ ...record, sha256: 'b'.repeat(64) }] },
    { finalRecords: [{ ...record, authorId: 'another' }] }, { finalRecords: [{ ...record, remoteItemId: 'replacement' }] },
    { finalRecords: [{ ...record, state: 'uploading' }] }, { finalRecords: [{ ...record, organizationId: 'other' }] },
    { finalSnapshotComplete: false }, { pendingUploads: 1 }, { finalRecords: undefined },
  ]) assert.equal(canSwitchStorage(copied, { ...readiness, ...finalState }), false);
  assert.equal(canSwitchStorage(copied, readiness), true);
});

test('refuses incomplete source data, mismatched copies and changed receipts', () => {
  assert.throws(() => createStorageMigration({ source: 'old-drive', destination: 'new-drive', records: [{ ...record, state: 'uploading' }], ...sourceState }), /source-not-ready/);
  assert.throws(() => createStorageMigration({ source: 'old-drive', destination: 'new-drive', records: [record, record], ...sourceState }), /source-not-ready/);
  assert.throws(() => createStorageMigration({ source: 'old-drive', destination: 'old-drive', records: [], ...sourceState }), /invalid-migration/);
  assert.throws(() => createStorageMigration({ source: 'old-drive', destination: 'new-drive', records: [], ...sourceState, sourceSnapshotComplete: false }), /invalid-migration/);
  assert.throws(() => createStorageMigration({ source: 'old-drive', destination: 'new-drive', records: [], ...sourceState, pendingUploads: 1 }), /invalid-migration/);
  assert.throws(() => createStorageMigration({ source: 'old-drive', destination: 'new-drive', records: [{ ...record, organizationId: 'other' }], ...sourceState }), /source-not-ready/);
  const initial = createStorageMigration({ source: 'old-drive', destination: 'new-drive', records: [record], ...sourceState });
  assert.throws(() => applyVerifiedMigrationReceipt(initial, null), /invalid-migration-receipt/);
  assert.equal(canSwitchStorage({ ...initial, items: [null] }, readiness), false);
  assert.throws(() => applyVerifiedMigrationReceipt(initial, { recordId: record.recordId, targetItemId: 'new', targetFolderId: 'folder', byteCount: 26, sha256 }), /receipt-mismatch/);
  const copied = applyVerifiedMigrationReceipt(initial, { recordId: record.recordId, targetItemId: 'new', targetFolderId: 'folder', byteCount: 25, sha256 });
  assert.throws(() => applyVerifiedMigrationReceipt(copied, { recordId: record.recordId, targetItemId: 'other', targetFolderId: 'folder', byteCount: 25, sha256 }), /receipt-mismatch/);
});

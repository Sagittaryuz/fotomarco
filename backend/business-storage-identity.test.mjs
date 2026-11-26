import test from 'node:test';
import assert from 'node:assert/strict';
import { storageFingerprint, compareStorageFingerprints } from './business-storage-identity.mjs';

test('compares stable storage identifiers without exposing them', async () => {
  const first = await storageFingerprint('oneDrive', 'drive-A', 'user-A');
  assert.match(first, /^[0-9a-f]{64}$/);
  assert.equal(first, 'dec8d46104fcfc5f754c8e94a8afcc5e7d029f413995c47e924270686f8a0234');
  assert.equal(first, await storageFingerprint('oneDrive', 'drive-A', 'user-A'));
  assert.notEqual(first, await storageFingerprint('oneDrive', 'drive-B', 'user-A'));
  assert.notEqual(first, await storageFingerprint('googleDrive', 'drive-A', 'user-A'));
  assert.notEqual(first, await storageFingerprint('oneDrive', 'drive-A', 'user-B'));
});

test('rejects missing, unsupported or malformed storage identities', async () => {
  for (const [provider, id] of [['other', 'drive'], ['oneDrive', ''], ['googleDrive', 'x\ny']]) {
    await assert.rejects(storageFingerprint(provider, id, 'user-A'), /invalid-storage-identity/);
  }
  await assert.rejects(storageFingerprint('oneDrive', 'drive-A', ''), /invalid-storage-identity/);
});

test('unknown destinations are not assumed to be different', async () => {
  const a = await storageFingerprint('oneDrive', 'drive-A', 'user-A');
  const b = await storageFingerprint('oneDrive', 'drive-B', 'user-A');
  assert.equal(compareStorageFingerprints(a, a), 'same');
  assert.equal(compareStorageFingerprints(a, b), 'different');
  assert.equal(compareStorageFingerprints(a, undefined), 'unknown');
  assert.equal(compareStorageFingerprints('', b), 'unknown');
});

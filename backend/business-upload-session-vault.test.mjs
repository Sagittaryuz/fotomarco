import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createUploadSessionVault } from './business-upload-session-vault.mjs';

test('encrypts upload credentials and binds them to the organization, author and capture', async () => {
  const key = Buffer.from(crypto.getRandomValues(new Uint8Array(32))).toString('base64');
  let now = 1000;
  const vault = await createUploadSessionVault(key, { now: () => now });
  const value = { uploadUrl: 'https://node.up.1drv.com/upload/private-token', expiresAt: 10000 };
  const sealed = await vault.seal('org', 'user', 'capture-stamped', value);
  assert.equal(JSON.stringify(sealed).includes('private-token'), false);
  assert.deepEqual(await vault.open('org', 'user', 'capture-stamped', sealed), value);
  await assert.rejects(vault.open('other', 'user', 'capture-stamped', sealed), /invalid-vault-data/);
  await assert.rejects(vault.open('org', 'other', 'capture-stamped', sealed), /invalid-vault-data/);
  await assert.rejects(vault.open('org', 'user', 'capture-original', sealed), /invalid-vault-data/);
  const corrupt = Buffer.from(sealed.ciphertext, 'base64'); corrupt[0] ^= 1;
  await assert.rejects(vault.open('org', 'user', 'capture-stamped', { ...sealed, ciphertext: corrupt.toString('base64') }), /invalid-vault-data/);
  now = 10000;
  await assert.rejects(vault.open('org', 'user', 'capture-stamped', sealed), /invalid-vault-data/);
});

test('Google Drive upload session is encrypted and cannot be opened as OneDrive', async () => {
  const key = Buffer.from(crypto.getRandomValues(new Uint8Array(32))).toString('base64');
  const google = await createUploadSessionVault(key, { now: () => 1000, provider: 'google-drive' });
  const onedrive = await createUploadSessionVault(key, { now: () => 1000 });
  const value = { uploadUrl: 'https://www.googleapis.com/upload/drive/v3/files?uploadType=resumable&upload_id=private-token', expiresAt: 10000 };
  const sealed = await google.seal('org', 'user', 'capture', value);
  assert.ok(!JSON.stringify(sealed).includes('private-token'));
  assert.deepEqual(await google.open('org', 'user', 'capture', sealed), value);
  await assert.rejects(onedrive.open('org', 'user', 'capture', sealed), /invalid-vault-data/);
  await assert.rejects(google.open('org', 'other', 'capture', sealed), /invalid-vault-data/);
  await assert.rejects(google.seal('org', 'user', 'capture', { ...value, uploadUrl: 'https://evil.example/' }), /invalid-upload-session/);
});

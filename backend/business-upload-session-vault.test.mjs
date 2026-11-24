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

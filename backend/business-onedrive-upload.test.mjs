import { test } from 'node:test';
import assert from 'node:assert/strict';
import { businessUploadOffset, createBusinessUploadSession, findVerifiedBusinessUpload, sendBusinessUploadChunk, validBusinessPhotoName, verifyBusinessUploadedItem } from './business-onedrive-upload.mjs';
import { createHash } from 'node:crypto';

const captureId = '11111111-1111-4111-8111-111111111111';
const filename = `23-11-2026 - OneDrive - 18-35-02 - ${captureId}.1795470002-stamped.jpg`;
const uploadUrl = 'https://node.up.1drv.com/upload/secret';

test('starts a fail-on-conflict upload session for the bound capture', async () => {
  assert.equal(validBusinessPhotoName(filename, captureId), true);
  assert.equal(validBusinessPhotoName(filename, '22222222-2222-4222-8222-222222222222'), false);
  let calls = 0;
  const result = await createBusinessUploadSession({ ownerToken: 'owner', folderId: 'folder', captureId, filename, now: () => 10,
    fetchImpl: async (url, request) => {
      calls++;
      assert.match(url, /createUploadSession$/);
      assert.equal(request.redirect, 'manual');
      assert.equal(JSON.parse(request.body).item['@microsoft.graph.conflictBehavior'], 'fail');
      return { status: 200, json: async () => ({ uploadUrl, expirationDateTime: '2030-01-01T00:00:00Z' }) };
    } });
  assert.equal(result.uploadUrl, uploadUrl);
  assert.equal(calls, 1);
  await assert.rejects(createBusinessUploadSession({ ownerToken: 'owner', folderId: 'folder', captureId, filename,
    fetchImpl: async () => ({ status: 200, json: async () => ({ uploadUrl: 'https://example.com/private', expirationDateTime: '2030-01-01T00:00:00Z' }) }) }), /invalid-upload-session/);
});

test('uploads ordered chunks and never treats an unchecked receipt as verified', async () => {
  const unit = 320 * 1024;
  const requests = [];
  const fetchImpl = async (_, request) => {
    requests.push(request);
    if (requests.length === 1) return { status: 202, json: async () => ({ nextExpectedRanges: [`${unit}-`] }) };
    return { status: 201, json: async () => ({ id: 'item', name: filename, size: unit + 1, file: {}, parentReference: { id: 'folder', driveId: 'drive' } }) };
  };
  const common = { uploadUrl, total: unit + 1, folderId: 'folder', driveId: 'drive', filename, fetchImpl };
  assert.deepEqual(await sendBusinessUploadChunk({ ...common, offset: 0, bytes: new Uint8Array(unit) }), { state: 'pending', nextOffset: unit });
  assert.deepEqual(await sendBusinessUploadChunk({ ...common, offset: unit, bytes: new Uint8Array(1) }), { state: 'uploaded-unverified', itemId: 'item' });
  assert.equal(requests[0].headers.authorization, undefined);
  await assert.rejects(sendBusinessUploadChunk({ ...common, offset: 1, bytes: new Uint8Array(1) }), /invalid-upload-chunk/);
});

test('rejects unexpected range and unrelated file receipts', async () => {
  const common = { uploadUrl, total: 2, folderId: 'folder', driveId: 'drive', filename, offset: 0, bytes: new Uint8Array(2) };
  await assert.rejects(sendBusinessUploadChunk({ ...common, fetchImpl: async () => ({ status: 201, json: async () => ({ id: 'item', name: 'other.jpg', size: 2, file: {}, parentReference: { id: 'folder', driveId: 'drive' } }) }) }), /upload-result-uncertain/);
});

test('checks Graph state before retrying after an interrupted upload', async () => {
  const unit = 320 * 1024;
  assert.equal(await businessUploadOffset({ uploadUrl, total: unit + 3,
    fetchImpl: async () => ({ status: 200, json: async () => ({ nextExpectedRanges: [`${unit}-`] }) }) }), unit);
  await assert.rejects(businessUploadOffset({ uploadUrl, total: unit + 3,
    fetchImpl: async () => ({ status: 200, json: async () => ({ nextExpectedRanges: ['3-'] }) }) }), /upload-result-uncertain/);
});

test('acknowledges only the exact remote bytes and never forwards the owner token to the download host', async () => {
  const bytes = new TextEncoder().encode('image bytes');
  const hash = createHash('sha256').update(bytes).digest('hex');
  const makeDigest = () => {
    const state = createHash('sha256');
    let done;
    const digest = new Promise(resolve => { done = resolve; });
    const writable = new WritableStream({ write: part => state.update(part), close: () => done(state.digest()) });
    writable.digest = digest;
    return writable;
  };
  const fetchImpl = async (url, options) => {
    if (url.startsWith('https://download.files.1drv.com/')) {
      assert.equal(options.headers, undefined);
      return new Response(bytes);
    }
    assert.equal(options.headers.authorization, 'Bearer owner');
    if (url.endsWith('/content')) return new Response(null, { status: 302, headers: { location: 'https://download.files.1drv.com/file?token=private' } });
    return new Response(JSON.stringify({ id: 'item', name: filename, size: bytes.length, file: {}, parentReference: { id: 'folder', driveId: 'drive' } }));
  };
  const input = { ownerToken: 'owner', driveId: 'drive', folderId: 'folder', itemId: 'item', filename,
    expectedSize: bytes.length, expectedSha256: hash, fetchImpl, makeDigest };
  assert.deepEqual(await verifyBusinessUploadedItem(input), { verified: true, itemId: 'item' });
  await assert.rejects(verifyBusinessUploadedItem({ ...input, expectedSha256: '0'.repeat(64) }), /upload-verification-mismatch/);
});

test('lost upload response is not treated as success from filename alone', async () => {
  const input = { ownerToken: 'owner', driveId: 'drive', folderId: 'folder', captureId, filename,
    expectedSize: 3, expectedSha256: '0'.repeat(64) };
  assert.equal(await findVerifiedBusinessUpload({ ...input, fetchImpl: async () => ({ status: 404 }) }), null);
  await assert.rejects(findVerifiedBusinessUpload({ ...input, fetchImpl: async () => ({ status: 200,
    json: async () => ({ id: 'item', name: filename, size: 2, file: {}, parentReference: { id: 'folder', driveId: 'drive' } }) }) }), /upload-verification-mismatch/);
});

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { googleDriveUploadOffset, sendGoogleDriveChunk, startGoogleDriveUpload } from './business-google-drive-upload.mjs';
const session = 'https://www.googleapis.com/upload/drive/v3/files?uploadType=resumable&upload_id=synthetic';
const marker = '11111111-1111-4111-8111-111111111111';
test('starts a marked resumable upload and rejects an untrusted session URL', async () => {
  const args = { accessToken: 'private', folderId: 'folder', name: 'photo.jpg', mimeType: 'image/jpeg', totalBytes: 8, marker };
  const fetchImpl = async (_, options) => {
    assert.equal(JSON.parse(options.body).appProperties.photomarkMarker, marker);
    return { status: 200, headers: new Headers({ location: session }) };
  };
  assert.deepEqual(await startGoogleDriveUpload({ ...args, fetchImpl }), { session });
  await assert.rejects(startGoogleDriveUpload({ ...args, fetchImpl: async () => ({ status: 200, headers: new Headers({ location: 'https://evil.example/upload' }) }) }), /invalid-upload-session/);
});

test('reconciles interrupted uploads without assuming completion', async () => {
  const ask = (status, range, body = {}) => async (_, options) => {
    assert.equal(options.headers['content-range'], 'bytes */524288');
    return { status, headers: new Headers(range ? { range } : {}), json: async () => body };
  };
  const args = { session, totalBytes: 524288 };
  assert.deepEqual(await googleDriveUploadOffset({ ...args, fetchImpl: ask(308, 'bytes=0-262143') }), { state: 'uploading', nextOffset: 262144 });
  assert.deepEqual(await googleDriveUploadOffset({ ...args, fetchImpl: ask(308) }), { state: 'uploading', nextOffset: 0 });
  assert.deepEqual(await googleDriveUploadOffset({ ...args, fetchImpl: ask(404) }), { state: 'expired' });
  assert.deepEqual(await googleDriveUploadOffset({ ...args, fetchImpl: ask(200, null, { id: 'file-id' }) }), { state: 'uploaded', fileId: 'file-id' });
  await assert.rejects(googleDriveUploadOffset({ ...args, fetchImpl: ask(308, 'bytes=0-9999999') }), /upload-status-uncertain/);
});
test('uses acknowledged offset and leaves uncertain failures for reconciliation', async () => {
  const bytes = new Uint8Array(262144);
  const args = { session, offset: 0, totalBytes: 524288, bytes };
  assert.deepEqual(await sendGoogleDriveChunk({ ...args, fetchImpl: async () => ({ status: 308, headers: new Headers({ range: 'bytes=0-131071' }) }) }), { complete: false, nextOffset: 131072 });
  await assert.rejects(sendGoogleDriveChunk({ ...args, fetchImpl: async () => { throw new Error('network details'); } }), error => error.message === 'upload-status-uncertain');
  await assert.rejects(sendGoogleDriveChunk({ ...args, session: 'https://evil.example/' }), /invalid-upload-session/);
  await assert.rejects(sendGoogleDriveChunk({ ...args, bytes: new Uint8Array(9) }), /invalid-upload-chunk/);
});

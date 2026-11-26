import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createBusinessHandler } from './business-http.mjs';

const request = (path, body, token = 'valid.token') => new Request(`https://example.test${path}`, {
  method: 'POST', headers: { authorization: `Bearer ${token}`, 'content-type': 'application/json',
    'content-length': String(new TextEncoder().encode(body).length) }, body,
});

test('uses the verified identity and never accepts a client-supplied role', async () => {
  const handler = createBusinessHandler({ preAuthLimit: async () => true, authenticate: async token => token === 'valid.token' ? { uid: 'owner' } : null,
    rateLimit: async uid => uid === 'owner', serviceForIdentity: identity => ({
      invite: async (_, org, email) => ({ owner: identity.uid, org, email }),
    }) });
  const result = await handler(request('/v1/organizations/org/invitations', JSON.stringify({ email: 'a@example.com' })));
  assert.equal(result.status, 201);
  assert.equal((await result.json()).owner, 'owner');
  assert.equal((await handler(request('/v1/organizations/org/invitations', JSON.stringify({ email: 'a@example.com', role: 'owner' })))).status, 400);
  assert.equal((await handler(request('/v1/organizations/org/invitations', '{}', 'bad'))).status, 401);
});

test('fails closed when the limiter is unavailable or the body is oversized', async () => {
  let called = false;
  const handler = createBusinessHandler({ preAuthLimit: async () => true, authenticate: async () => ({ uid: 'owner' }),
    rateLimit: async () => { throw new Error('offline'); }, serviceForIdentity: () => { called = true; } });
  assert.equal((await handler(request('/v1/organizations/org/invitations', '{}'))).status, 503);
  assert.equal(called, false);
  const active = createBusinessHandler({ preAuthLimit: async () => true, authenticate: async () => ({ uid: 'owner' }), rateLimit: async () => true, serviceForIdentity: () => ({}) });
  assert.equal((await active(request('/v1/organizations/org/invitations', 'x'.repeat(4097)))).status, 413);
});

test('Microsoft mailbox connection requires authentication and accepts only a credential', async () => {
  let calls = 0;
  const handler = createBusinessHandler({ preAuthLimit: async () => true,
    authenticate: async token => token === 'valid.token' ? { uid: 'owner' } : null,
    rateLimit: async () => true, serviceForIdentity: identity => ({ connectMicrosoftMail: async (_, org, token) => {
      calls++; assert.equal(identity.uid, 'owner'); assert.equal(org, 'org'); assert.equal(token, 'test-token');
      return { connected: true };
    } }) });
  const path = '/v1/organizations/org/mail/microsoft/connect';
  assert.equal((await handler(request(path, '{"refreshToken":"test-token"}', 'bad'))).status, 401);
  assert.equal((await handler(request(path, '{"refreshToken":"test-token","role":"owner"}'))).status, 400);
  assert.equal((await handler(request(path, '{"refreshToken":"test-token"}'))).status, 200);
  assert.equal(calls, 1);
});

test('Google Drive owner connection rejects unauthenticated and extraneous input', async () => {
  let calls = 0;
  const handler = createBusinessHandler({ preAuthLimit: async () => true,
    authenticate: async token => token === 'valid.token' ? { uid: 'owner' } : null,
    rateLimit: async () => true, serviceForIdentity: identity => ({ connectGoogleDrive: async (_, org, token) => {
      calls++; assert.equal(identity.uid, 'owner'); assert.equal(org, 'org'); assert.equal(token, 'test-token');
      return { connected: true };
    } }) });
  const path = '/v1/organizations/org/storage/google-drive/connect';
  assert.equal((await handler(request(path, '{"refreshToken":"test-token"}', 'bad'))).status, 401);
  assert.equal((await handler(request(path, '{"refreshToken":"test-token","role":"owner"}'))).status, 400);
  assert.equal((await handler(request(path, '{"refreshToken":"test-token"}'))).status, 200);
  assert.equal(calls, 1);
});

test('Google Drive member identity binding accepts no caller-supplied identity or role', async () => {
  let calls = 0;
  const handler = createBusinessHandler({ preAuthLimit: async () => true,
    authenticate: async token => token === 'valid.token' ? { uid: 'member' } : null,
    rateLimit: async () => true, serviceForIdentity: identity => ({ bindGoogleDriveMember: async (_, org, token) => {
      calls++; assert.equal(identity.uid, 'member'); assert.equal(org, 'org'); assert.equal(token, 'provider-token');
      return { linked: true };
    } }) });
  const path = '/v1/organizations/org/storage/google-drive/bind-member';
  assert.equal((await handler(request(path, '{"accessToken":"provider-token"}', 'bad'))).status, 401);
  assert.equal((await handler(request(path, '{"accessToken":"provider-token","email":"other@example.com"}'))).status, 400);
  assert.equal((await handler(request(path, '{"accessToken":"provider-token"}'))).status, 200);
  assert.equal(calls, 1);
});

test('Google owner folder accepts only the selected folder after authentication', async () => {
  let calls = 0;
  const handler = createBusinessHandler({ preAuthLimit: async () => true,
    authenticate: async token => token === 'valid.token' ? { uid: 'owner' } : null,
    rateLimit: async () => true, serviceForIdentity: identity => ({ provisionGoogleOwnerFolder: async (_, org, imagesId) => {
      calls++; assert.equal(identity.uid, 'owner'); assert.equal(org, 'org'); assert.equal(imagesId, 'images');
      return { ready: true };
    } }) });
  const path = '/v1/organizations/org/storage/google-drive/provision-owner';
  assert.equal((await handler(request(path, '{"imagesId":"images"}', 'bad'))).status, 401);
  assert.equal((await handler(request(path, '{"imagesId":"images","role":"owner"}'))).status, 400);
  assert.equal((await handler(request(path, '{"imagesId":"images"}'))).status, 200);
  assert.equal(calls, 1);
});

test('OneDrive connection exposes only allowlisted diagnostics, never provider details', async () => {
  let reason = 'provider-token-unavailable';
  const handler = createBusinessHandler({ preAuthLimit: async () => true,
    authenticate: async () => ({ uid: 'owner' }), rateLimit: async () => true,
    serviceForIdentity: () => ({ connectOneDrive: async () => { throw new Error(reason); } }) });
  const path = '/v1/organizations/org/storage/onedrive/connect';
  const body = JSON.stringify({ refreshToken: 'private-test-token' });
  const expected = await handler(request(path, body));
  assert.equal(expected.status, 503);
  assert.deepEqual(await expected.json(), { error: 'provider-token-unavailable' });
  reason = 'private-test-token';
  const unknown = await handler(request(path, body));
  assert.equal(unknown.status, 503);
  assert.deepEqual(await unknown.json(), { error: 'unavailable' });
  for (const [failure, expectedCode] of [['firestore-http-403', 'business-database-unavailable'],
    ['server-token-unavailable', 'business-database-unavailable'], ['invalid-vault-key', 'business-configuration-unavailable']]) {
    reason = failure;
    const response = await handler(request(path, body));
    assert.equal(response.status, 503);
    assert.deepEqual(await response.json(), { error: expectedCode });
  }
});

test('reconciliation requires an authenticated caller and an empty request', async () => {
  let calls = 0;
  const handler = createBusinessHandler({ preAuthLimit: async () => true,
    authenticate: async token => token === 'valid.token' ? { uid: 'member' } : null,
    rateLimit: async () => true, serviceForIdentity: identity => ({
      reconcileCapture: async (_, org, capture, variant) => {
        calls++;
        assert.equal(identity.uid, 'member');
        assert.equal(org, 'org');
        assert.equal(capture, 'capture');
        assert.equal(variant, 'stamped');
        return { state: 'verified', nextOffset: 10 };
      }
    }) });
  const path = '/v1/organizations/org/captures/capture/stamped/reconcile';
  assert.equal((await handler(request(path, '{}', 'bad'))).status, 401);
  assert.equal((await handler(request(path, '{"role":"owner"}'))).status, 400);
  const response = await handler(request(path, '{}'));
  assert.equal(response.status, 200);
  assert.deepEqual(await response.json(), { state: 'verified', nextOffset: 10 });
  assert.equal(calls, 1);
});

test('owner folder provisioning refuses client supplied identities or folder paths', async () => {
  let calls = 0;
  const handler = createBusinessHandler({ preAuthLimit: async () => true,
    authenticate: async () => ({ uid: 'owner' }), rateLimit: async () => true,
    serviceForIdentity: identity => ({ provisionOwnerFolder: async (_, org) => {
      assert.equal(identity.uid, 'owner'); assert.equal(org, 'org'); calls++; return { ready: true };
    } }) });
  const path = '/v1/organizations/org/storage/onedrive/provision-owner';
  assert.equal((await handler(request(path, '{"folderId":"someone-elses"}'))).status, 400);
  assert.equal((await handler(request(path, '{}'))).status, 200);
  assert.equal(calls, 1);
});

test('member account binding accepts only the provider token, never a supplied identity', async () => {
  let calls = 0;
  const handler = createBusinessHandler({ preAuthLimit: async () => true,
    authenticate: async () => ({ uid: 'member' }), rateLimit: async () => true,
    serviceForIdentity: identity => ({ bindMicrosoftMember: async (_, org, token) => {
      assert.equal(identity.uid, 'member'); assert.equal(org, 'org'); assert.equal(token, 'provider-token'); calls++; return { linked: true };
    } }) });
  const path = '/v1/organizations/org/storage/onedrive/bind-member';
  assert.equal((await handler(request(path, '{"accessToken":"provider-token","id":"other"}'))).status, 400);
  assert.equal((await handler(request(path, '{"accessToken":"provider-token"}'))).status, 200);
  assert.equal(calls, 1);
});

test('member provisioning never accepts client supplied folder or account identities', async () => {
  let calls = 0;
  const handler = createBusinessHandler({ preAuthLimit: async () => true,
    authenticate: async () => ({ uid: 'member' }), rateLimit: async () => true,
    serviceForIdentity: () => ({ provisionMemberFolder: async (_, org, token) => {
      assert.equal(org, 'org'); assert.equal(token, 'provider-token'); calls++; return { ready: true };
    } }) });
  const path = '/v1/organizations/org/storage/onedrive/provision-member';
  assert.equal((await handler(request(path, '{"accessToken":"provider-token","folderId":"other"}'))).status, 400);
  assert.equal((await handler(request(path, '{"accessToken":"provider-token"}'))).status, 200);
  assert.equal(calls, 1);
});

test('capture image route requires authorization and returns a private image stream', async () => {
  const handler = createBusinessHandler({ preAuthLimit: async () => true,
    authenticate: async token => token === 'valid.token' ? { uid: 'member' } : null, rateLimit: async () => true,
    serviceForIdentity: () => ({ readCapture: async (_, org, id, thumbnail) => {
      assert.equal(org, 'org'); assert.equal(id, 'capture'); assert.equal(thumbnail, true);
      return new ReadableStream({ start(controller) { controller.enqueue(new Uint8Array([1, 2])); controller.close(); } });
    } }) });
  const path = '/v1/organizations/org/captures/capture/thumbnail';
  assert.equal((await handler(request(path, '{}', 'bad'))).status, 401);
  assert.equal((await handler(request(path, '{"owner":true}'))).status, 400);
  const response = await handler(request(path, '{}'));
  assert.equal(response.status, 200); assert.equal(response.headers.get('cache-control'), 'private, no-store');
  assert.deepEqual([...new Uint8Array(await response.arrayBuffer())], [1, 2]);
});

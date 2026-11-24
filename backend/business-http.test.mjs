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

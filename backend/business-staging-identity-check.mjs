import { randomBytes, randomUUID } from 'node:crypto';

const apiKey = process.env.FIREBASE_API_KEY;
if (!apiKey || !/^[A-Za-z0-9_-]+$/.test(apiKey)) throw Error('Missing Firebase API key');
const identityBase = 'https://identitytoolkit.googleapis.com/v1/accounts:';
const stagingBase = 'https://photomark-business-staging.mrpires72.workers.dev';
const identities = [];
async function identityCall(method, body) {
  const response = await fetch(`${identityBase}${method}?key=${apiKey}`, {
    method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify(body),
  });
  if (!response.ok) throw Error(`Identity ${method} returned HTTP ${response.status}`);
  return response.json();
}
async function businessCall(path, token) {
  return fetch(`${stagingBase}${path}`, { method: 'POST',
    headers: { authorization: `Bearer ${token}`, 'content-type': 'application/json' }, body: '{}' });
}
try {
  for (let i = 0; i < 2; i++) {
    const identity = await identityCall('signUp', {
      email: `photomark-test-${randomUUID()}@example.invalid`,
      password: randomBytes(24).toString('base64url'), returnSecureToken: true,
    });
    if (!identity.idToken) throw Error('Synthetic account did not return a token');
    identities.push(identity.idToken);
  }
  for (const token of identities) {
    const own = await businessCall('/v1/organizations/mine', token);
    if (own.status !== 200) throw Error(`Organization listing returned HTTP ${own.status}`);
    const bootstrap = await businessCall('/v1/organizations/bootstrap-owner', token);
    if (bootstrap.status !== 403) throw Error(`Non-owner bootstrap returned HTTP ${bootstrap.status}`);
    const otherOrg = await businessCall('/v1/organizations/verification-unrelated/profile/read', token);
    if (otherOrg.status !== 403) throw Error(`Unrelated organization access returned HTTP ${otherOrg.status}`);
  }
  console.log('Synthetic identities cannot create the owner organization or access an unrelated organization.');
} finally {
  for (const token of identities) await identityCall('delete', { idToken: token });
}

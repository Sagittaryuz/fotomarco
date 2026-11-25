import assert from 'node:assert/strict';
const base = `http://${process.env.FIRESTORE_EMULATOR_HOST}/v1/projects/demo-photomark-rules/databases/(default)/documents`;
const document = `${base}/organizations/security-probe`;
const mailCredential = `${document}/private/microsoft-mail`;
const seeded = await fetch(document, { method: 'PATCH', headers: { Authorization: 'Bearer owner', 'content-type': 'application/json' }, body: JSON.stringify({ fields: { name: { stringValue: 'Synthetic data' } } }) });
assert.equal(seeded.status, 200, 'emulator setup should succeed with administrator credential');
const seededMail = await fetch(mailCredential, { method: 'PATCH', headers: { Authorization: 'Bearer owner', 'content-type': 'application/json' }, body: JSON.stringify({ fields: { ciphertext: { stringValue: 'synthetic ciphertext' } } }) });
assert.equal(seededMail.status, 200, 'mail credential setup should succeed with administrator credential');
const enc = value => Buffer.from(JSON.stringify(value)).toString('base64url');
const token = `${enc({ alg: 'none', typ: 'JWT' })}.${enc({ iss: 'https://securetoken.google.com/demo-photomark-rules', aud: 'demo-photomark-rules', sub: 'member', user_id: 'member', iat: Math.floor(Date.now()/1000), exp: Math.floor(Date.now()/1000)+3600, firebase: { sign_in_provider: 'password' } })}.`;
for (const identity of [null, token]) {
  for (const target of [document, mailCredential]) for (const method of ['GET', 'PATCH', 'DELETE']) {
    const headers = { ...(identity ? { Authorization: `Bearer ${identity}` } : {}), 'content-type': 'application/json' };
    const response = await fetch(target, { method, headers, ...(method === 'PATCH' ? { body: JSON.stringify({ fields: { name: { stringValue: 'modified' } } }) } : {}) });
    assert.equal(response.status, 403, `${method} must be denied for ${identity ? 'signed-in user' : 'anonymous user'}`);
  }
}
console.log('Firestore rules: anonymous and signed-in reads, writes and deletes denied.');

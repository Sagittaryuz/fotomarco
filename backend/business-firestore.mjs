/** Firestore REST adapter for a trusted backend with a server-side Google credential.
 * Never use an individual user's Firebase token as the server credential. */
const segment = value => {
  if (typeof value !== 'string' || !/^[A-Za-z0-9_-]{1,128}$/.test(value)) throw new Error('invalid-document-id');
  return value;
};
const value = item => {
  if (typeof item === 'string') return { stringValue: item };
  if (typeof item === 'boolean') return { booleanValue: item };
  if (Number.isSafeInteger(item)) return { integerValue: String(item) };
  throw new Error('unsupported-field');
};
const fields = object => Object.fromEntries(Object.entries(object).map(([k, v]) => [k, value(v)]));
const decode = object => Object.fromEntries(Object.entries(object ?? {}).map(([k, v]) => {
  if ('stringValue' in v) return [k, v.stringValue];
  if ('booleanValue' in v) return [k, v.booleanValue];
  if ('integerValue' in v) { const n = Number(v.integerValue); if (Number.isSafeInteger(n)) return [k, n]; }
  throw new Error('invalid-field');
}));

export function firestoreTransactions({ projectId, accessToken, fetchImpl = fetch, emulatorOrigin }) {
  const project = segment(projectId);
  const root = `projects/${project}/databases/(default)/documents`;
  if (emulatorOrigin && !/^http:\/\/(127\.0\.0\.1|localhost):\d{1,5}$/.test(emulatorOrigin)) throw new Error('invalid-emulator-origin');
  const endpoint = `${emulatorOrigin ?? 'https://firestore.googleapis.com'}/v1/${root}`;
  async function transaction(action) {
    const token = await accessToken();
    if (typeof token !== 'string' || !token) throw new Error('missing-server-credential');
    const send = async (suffix, body) => {
      const response = await fetchImpl(endpoint + suffix, { method: 'POST', redirect: 'manual',
        headers: { authorization: `Bearer ${token}`, 'content-type': 'application/json' }, body: JSON.stringify(body) });
      if (!response.ok) throw new Error(`firestore-http-${response.status}`);
      return response.json();
    };
    const started = await send(':beginTransaction', { options: { readWrite: {} } });
    if (typeof started.transaction !== 'string' || !started.transaction) throw new Error('invalid-transaction');
    const txId = started.transaction;
    const writes = [];
    let seatState;
    let activeOrg;
    const path = (org, sub, id) => `${root}/organizations/${segment(org)}${sub ? `/${sub}/${segment(id)}` : ''}`;
    async function read(name) {
      if (writes.length) throw new Error('read-after-write');
      const result = await send(':batchGet', { documents: [name], transaction: txId });
      if (!Array.isArray(result) || result.length !== 1) throw new Error('invalid-read');
      if (result[0].missing === name) return null;
      if (result[0].found?.name !== name) throw new Error('invalid-read');
      return decode(result[0].found.fields);
    }
    function put(name, data, currentDocument) {
      writes.push({ update: { name, fields: fields(data) }, ...(currentDocument ? { currentDocument } : {}) });
    }
    const tx = {
      initializeOrganization: async organization => {
        const org = segment(organization.id);
        const owner = segment(organization.ownerId);
        put(path(org), organization, { exists: false });
        put(path(org, 'members', owner), { organizationId: org, userId: owner, role: 'owner', active: true }, { exists: false });
        put(path(org, 'state', 'seats'), { count: 1 }, { exists: false });
      },
      organization: org => read(path(org)),
      membership: (org, user) => read(path(org, 'members', user)),
      invitation: (org, id) => read(path(org, 'invitations', id)),
      asset: (org, id) => read(path(org, 'assets', id)),
      latestProfile: async org => {
        const head = await read(path(org, 'state', 'profile'));
        if (!head) return null;
        return read(path(org, 'profiles', head.versionId));
      },
      occupiedSeats: async org => {
        activeOrg = segment(org);
        const counter = await read(path(org, 'state', 'seats'));
        if (!counter || !Number.isSafeInteger(counter.count) || counter.count < 0) throw new Error('invalid-seat-counter');
        seatState = counter.count;
        return seatState;
      },
      createInvitation: async invitation => put(path(invitation.organizationId, 'invitations', invitation.id), invitation, { exists: false }),
      createAsset: async asset => put(path(asset.organizationId, 'assets', asset.assetId), asset, { exists: false }),
      publishProfile: async profile => {
        put(path(profile.organizationId, 'profiles', profile.versionId), profile, { exists: false });
        put(path(profile.organizationId, 'state', 'profile'), { versionId: profile.versionId });
      },
      addMember: async member => {
        if (seatState === undefined || activeOrg !== member.organizationId || seatState >= 500) throw new Error('invalid-seat-counter');
        put(path(member.organizationId, 'members', member.userId), member);
        put(path(member.organizationId, 'state', 'seats'), { count: seatState + 1 });
      },
      markInvitationAccepted: async (org, id, userId) => {
        const name = path(org, 'invitations', id);
        writes.push({ update: { name, fields: fields({ state: 'accepted', acceptedBy: userId }) },
          updateMask: { fieldPaths: ['state', 'acceptedBy'] }, currentDocument: { exists: true } });
      },
    };
    try {
      const result = await action(tx);
      await send(':commit', { transaction: txId, writes });
      return result;
    } catch (error) {
      try { await send(':rollback', { transaction: txId }); } catch { /* preserve original error */ }
      throw error;
    }
  }
  return transaction;
}

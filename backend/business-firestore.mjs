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
      initializeOrganization: async (organization, ownerEmail, ownerName) => {
        const org = segment(organization.id);
        const owner = segment(organization.ownerId);
        put(path(org), organization, { exists: false });
        put(path(org, 'members', owner), { organizationId: org, userId: owner, role: 'owner', active: true, storageStatus: 'not-started',
          ...(typeof ownerEmail === 'string' && ownerEmail ? { email: ownerEmail } : {}),
          ...(typeof ownerName === 'string' && ownerName ? { displayName: ownerName } : {}) }, { exists: false });
        put(`${root}/users/${owner}/organizations/${org}`, { organizationId: org }, { exists: false });
        put(path(org, 'state', 'seats'), { count: 1 }, { exists: false });
      },
      updateOrganization: async (org, updates) => {
        writes.push({ update: { name: path(org), fields: fields(updates) },
          updateMask: { fieldPaths: ['name', 'contactEmail', 'photoAssetId'] }, currentDocument: { exists: true } });
      },
      organization: org => read(path(org)),
      membership: (org, user) => read(path(org, 'members', user)),
      userOrganizations: async userId => {
        if (writes.length) throw new Error('read-after-write');
        const user = segment(userId);
        const result = await send(`/users/${user}:runQuery`, { transaction: txId,
          structuredQuery: { from: [{ collectionId: 'organizations' }], limit: 501 } });
        if (!Array.isArray(result) || result.some(entry => !entry || entry.error || (!entry.document && !entry.readTime))) throw new Error('invalid-read');
        return result.filter(entry => entry.document).map(entry => {
          const index = decode(entry.document.fields);
          const org = segment(index.organizationId);
          if (entry.document.name !== `${root}/users/${user}/organizations/${org}`) throw new Error('invalid-read');
          return org;
        });
      },
      activeMembers: async org => {
        if (writes.length) throw new Error('read-after-write');
        const organization = segment(org);
        const query = async (field, queryValue) => {
          const result = await send(`/organizations/${organization}:runQuery`, { transaction: txId,
            structuredQuery: { from: [{ collectionId: 'members' }],
              where: { fieldFilter: { field: { fieldPath: field }, op: 'EQUAL', value: queryValue } }, limit: 501 } });
          if (!Array.isArray(result) || result.some(entry => !entry || entry.error || (!entry.document && !entry.readTime))) throw new Error('invalid-read');
          return result.filter(entry => entry.document).map(entry => {
            const member = decode(entry.document.fields);
            if (entry.document.name !== path(organization, 'members', member.userId)) throw new Error('invalid-read');
            return member;
          });
        };
        return [...await query('active', { booleanValue: true }), ...await query('revocationState', { stringValue: 'pending' })];
      },
      invitation: (org, id) => read(path(org, 'invitations', id)),
      asset: (org, id) => read(path(org, 'assets', id)),
      capture: (org, id) => read(path(org, 'captures', id)),
      oneDriveCredential: org => read(path(org, 'private', 'onedrive')),
      googleMailCredential: org => read(path(org, 'private', 'gmail')),
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
      createCapture: async capture => put(path(capture.organizationId, 'captures', capture.recordId), capture, { exists: false }),
      beginCaptureUpload: async (org, recordId, session, expiresAt) => {
        const data = { state: 'uploading', nextOffset: 0, sessionVersion: session.version,
          sessionIv: session.iv, sessionCiphertext: session.ciphertext, sessionExpiresAt: expiresAt };
        writes.push({ update: { name: path(org, 'captures', recordId), fields: fields(data) },
          updateMask: { fieldPaths: Object.keys(data) }, currentDocument: { exists: true } });
      },
      leaseCaptureChunk: async (org, recordId, leaseId, expiresAt) => {
        const data = { leaseId, leaseExpiresAt: expiresAt };
        writes.push({ update: { name: path(org, 'captures', recordId), fields: fields(data) },
          updateMask: { fieldPaths: Object.keys(data) }, currentDocument: { exists: true } });
      },
      completeCaptureChunk: async (org, recordId, result, byteCount) => {
        const data = result.state === 'pending' ? { state: 'uploading', nextOffset: result.nextOffset, leaseId: '', leaseExpiresAt: 0 } :
          { state: 'verifying', nextOffset: byteCount, remoteItemId: result.itemId, leaseId: '', leaseExpiresAt: 0 };
        writes.push({ update: { name: path(org, 'captures', recordId), fields: fields(data) },
          updateMask: { fieldPaths: Object.keys(data) }, currentDocument: { exists: true } });
      },
      markCaptureVerified: async (org, recordId, verifiedAt) => {
        const data = { state: 'verified', verifiedAt };
        writes.push({ update: { name: path(org, 'captures', recordId), fields: fields(data) },
          updateMask: { fieldPaths: Object.keys(data) }, currentDocument: { exists: true } });
      },
      reconcileCapture: async (org, recordId, result, byteCount, verifiedAt) => {
        const data = result.state === 'verified' ? { state: 'verified', nextOffset: byteCount, remoteItemId: result.itemId, verifiedAt, leaseId: '', leaseExpiresAt: 0 } :
          result.state === 'restart' ? { state: 'reserved', nextOffset: 0, leaseId: '', leaseExpiresAt: 0 } :
          { state: 'uploading', nextOffset: result.nextOffset, leaseId: '', leaseExpiresAt: 0 };
        writes.push({ update: { name: path(org, 'captures', recordId), fields: fields(data) },
          updateMask: { fieldPaths: Object.keys(data) }, currentDocument: { exists: true } });
      },
      setOneDriveCredential: async (org, record) => put(path(org, 'private', 'onedrive'), record),
      setOwnerFolderProvisioning: async (org, uid, marker, name, email) => {
        const data = { storageStatus: 'provisioning', oneDriveCreationMarker: marker, oneDriveProvisionName: name, oneDriveProvisionEmail: email };
        writes.push({ update: { name: path(org, 'members', uid), fields: fields(data) },
          updateMask: { fieldPaths: Object.keys(data) }, currentDocument: { exists: true } });
      },
      setOwnerFolderReady: async (org, uid, folder) => {
        const data = { storageStatus: 'granted', oneDriveFolderId: folder.folderId,
          oneDriveParentId: folder.parentId, oneDriveMemberIdentityId: folder.memberIdentityId };
        writes.push({ update: { name: path(org, 'members', uid), fields: fields(data) },
          updateMask: { fieldPaths: Object.keys(data) }, currentDocument: { exists: true } });
      },
      setMemberProviderIdentity: async (org, uid, providerAccountId, email) => {
        const data = { oneDrivePendingIdentityId: providerAccountId, oneDrivePendingEmail: email };
        writes.push({ update: { name: path(org, 'members', uid), fields: fields(data) },
          updateMask: { fieldPaths: Object.keys(data) }, currentDocument: { exists: true } });
      },
      providerBinding: (org, key) => read(path(org, 'providerBindings', key)),
      setProviderBinding: async (org, key, uid) => put(path(org, 'providerBindings', key), { userId: uid }, { exists: false }),
      leaseMemberFolder: async (org, uid, marker, name, email, lease, expiresAt) => {
        const data = { storageStatus: 'provisioning', oneDriveCreationMarker: marker, oneDriveProvisionName: name,
          oneDriveProvisionEmail: email, oneDriveGrantLease: lease, oneDriveGrantLeaseExpiresAt: expiresAt };
        writes.push({ update: { name: path(org, 'members', uid), fields: fields(data) },
          updateMask: { fieldPaths: Object.keys(data) }, currentDocument: { exists: true } });
      },
      setMemberFolderPendingGrant: async (org, uid, folder, leaseExpiresAt) => {
        const data = { oneDriveFolderId: folder.folderId, oneDriveParentId: folder.parentId,
          oneDriveMemberIdentityId: folder.memberIdentityId, oneDriveGrantLeaseExpiresAt: leaseExpiresAt };
        writes.push({ update: { name: path(org, 'members', uid), fields: fields(data) },
          updateMask: { fieldPaths: Object.keys(data) }, currentDocument: { exists: true } });
      },
      setMemberFolderReady: async (org, uid) => {
        const data = { storageStatus: 'granted', oneDriveGrantLease: '', oneDriveGrantLeaseExpiresAt: 0 };
        writes.push({ update: { name: path(org, 'members', uid), fields: fields(data) },
          updateMask: { fieldPaths: Object.keys(data) }, currentDocument: { exists: true } });
      },
      setGoogleMailCredential: async (org, record) => put(path(org, 'private', 'gmail'), record),
      publishProfile: async profile => {
        put(path(profile.organizationId, 'profiles', profile.versionId), profile, { exists: false });
        put(path(profile.organizationId, 'state', 'profile'), { versionId: profile.versionId });
      },
      addMember: async member => {
        if (seatState === undefined || activeOrg !== member.organizationId || seatState >= 500) throw new Error('invalid-seat-counter');
        put(path(member.organizationId, 'members', member.userId), member);
        put(`${root}/users/${segment(member.userId)}/organizations/${segment(member.organizationId)}`,
          { organizationId: member.organizationId });
        put(path(member.organizationId, 'state', 'seats'), { count: seatState + 1 });
      },
      beginMemberRevocation: async (org, user, revocationId) => {
        writes.push({ update: { name: path(org, 'members', user), fields: fields({ active: false, revocationState: 'pending', revocationId }) },
          updateMask: { fieldPaths: ['active', 'revocationState', 'revocationId'] }, currentDocument: { exists: true } });
      },
      completeMemberRevocation: async (org, user) => {
        if (seatState === undefined || activeOrg !== org || seatState < 2) throw new Error('invalid-seat-counter');
        writes.push({ update: { name: path(org, 'members', user), fields: fields({ revocationState: 'complete' }) },
          updateMask: { fieldPaths: ['revocationState'] }, currentDocument: { exists: true } });
        put(path(org, 'state', 'seats'), { count: seatState - 1 });
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

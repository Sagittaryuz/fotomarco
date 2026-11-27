import { matchesDelegatedDriveOwner, readDelegatedUser } from './business-onedrive-identity.mjs';

/** Prepare only private folders; never rename or change existing sharing. */
export async function ensurePrivateMemberFolder({ ownerToken, expectedOwnerId, expectedDriveId, memberIdentityId, memberName, memberEmail, knownMemberFolderId, creationMarker, fetchImpl = fetch }) {
  const validId = value => typeof value === 'string' && value.length > 0 && value.length <= 256 && !/[\x00-\x20/\\?#]/.test(value);
  if (typeof ownerToken !== 'string' || !ownerToken || !validId(expectedOwnerId) || !validId(expectedDriveId) || !validId(memberIdentityId) ||
      typeof memberName !== 'string' || typeof memberEmail !== 'string') throw new Error('invalid-storage-configuration');
  if (knownMemberFolderId !== undefined && !validId(knownMemberFolderId)) throw new Error('invalid-storage-configuration');
  // This marker must be generated and persisted in trusted storage before the Graph request.
  if (creationMarker !== undefined && !/^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(creationMarker)) throw new Error('invalid-storage-configuration');
  const marker = creationMarker ? `Photomark:${creationMarker.toLowerCase()}` : undefined;
  const name = memberName.trim().replace(/\s+/g, ' ');
  const email = memberEmail.trim().toLowerCase();
  if (!name || name.length > 100 || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email) || email.length > 120 ||
      /[\\/:*?"<>|\x00-\x1f]/.test(name) || /[\\/:*?"<>|\x00-\x1f]/.test(email) || /[. ]$/.test(name)) throw new Error('invalid-member-name');
  const base = 'https://graph.microsoft.com/v1.0/me/drive';
  const headers = { authorization: `Bearer ${ownerToken}` };
  async function read(url) {
    const response = await fetchImpl(base + url, { redirect: 'manual', headers });
    if (response.status === 404) return null;
    if (response.status !== 200) throw new Error('storage-unavailable');
    return response.json();
  }
  async function privateOwnerFolder(itemId, allowedMemberId) {
    const permissions = await read(`/items/${encodeURIComponent(itemId)}/permissions`);
    if (!permissions || !Array.isArray(permissions.value) || permissions['@odata.nextLink'] || !permissions.value.length) throw new Error('unsafe-parent-permissions');
    let owner = false;
    for (const p of permissions.value) {
      const identity = p?.grantedToV2 ?? p?.grantedTo;
      if (!p || p.link || p.grantedToIdentities || p.grantedToIdentitiesV2 || !Array.isArray(p.roles) || !p.roles.length ||
          p.roles.some(role => !['owner', 'read', 'write'].includes(role)) || !identity || identity.group || identity.application ||
          identity.siteGroup || !validId(identity.user?.id) || ![expectedOwnerId, allowedMemberId].includes(identity.user.id) ||
          (identity.siteUser && identity.siteUser.id !== identity.user?.id) ||
          (identity.user?.id !== expectedOwnerId && p.roles.includes('owner'))) {
        throw new Error('unsafe-parent-permissions');
      }
      if (p.roles.includes('owner')) owner = true;
    }
    if (!owner) throw new Error('unsafe-parent-permissions');
  }
  async function child(parent, childName, allowedMemberId, isMemberFolder = false) {
    const relative = `/items/${encodeURIComponent(parent)}:/${encodeURIComponent(childName)}`;
    let folder = await read(relative);
    if (isMemberFolder && folder && (knownMemberFolderId ? folder.id !== knownMemberFolderId : !marker || folder.description !== marker)) throw new Error('folder-name-in-use');
    if (isMemberFolder && !folder && knownMemberFolderId) throw new Error('missing-bound-folder');
    if (!folder) {
      const response = await fetchImpl(`${base}/items/${encodeURIComponent(parent)}/children`, {
        method: 'POST', redirect: 'manual', headers: { ...headers, 'content-type': 'application/json' },
        body: JSON.stringify({ name: childName, folder: {}, ...(isMemberFolder && marker ? { description: marker } : {}), '@microsoft.graph.conflictBehavior': 'fail' })
      });
      if (response.status === 201) folder = await response.json();
      else if (response.status === 409 && !isMemberFolder) folder = await read(relative);
      else if (response.status === 409) throw new Error('folder-name-in-use');
      else throw new Error('storage-unavailable');
    }
    if (!folder || !validId(folder.id) || folder.name !== childName || !folder.folder || folder.file || folder.remoteItem ||
        folder.parentReference?.id !== parent || folder.parentReference?.driveId !== expectedDriveId) throw new Error('invalid-member-folder');
    if (isMemberFolder && marker && !knownMemberFolderId && folder.description !== marker) throw new Error('folder-identity-unconfirmed');
    await privateOwnerFolder(folder.id, allowedMemberId);
    return folder.id;
  }
  const drive = await read('');
  const owner = drive?.owner == null ? await readDelegatedUser(ownerToken, fetchImpl) : { id: expectedOwnerId };
  if (!matchesDelegatedDriveOwner({ user: owner, drive, expectedOwnerId, expectedDriveId })) throw new Error('wrong-owner-account');
  const root = await read('/root');
  if (!root || !validId(root.id) || !root.folder || root.remoteItem) throw new Error('invalid-root');
  await privateOwnerFolder(root.id);
  const images = await child(root.id, 'Imagens');
  const photomark = await child(images, 'Photomark');
  const member = await child(photomark, `${name} (${email})`, memberIdentityId, true);
  return { driveId: expectedDriveId, parentId: photomark, folderId: member };
}

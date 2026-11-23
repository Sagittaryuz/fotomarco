/** Conservative gate for sharing. This is not a substitute for provider-side ACL enforcement. */
export function validateMemberFolderPermissions({ permissionPage, ownerIdentityId, memberIdentityId, isOwnerListing }) {
  if (isOwnerListing !== true || typeof ownerIdentityId !== 'string' || !ownerIdentityId ||
      typeof memberIdentityId !== 'string' || !memberIdentityId || ownerIdentityId === memberIdentityId ||
      !permissionPage || !Array.isArray(permissionPage.value) || permissionPage['@odata.nextLink']) return false;
  let hasOwner = false;
  let hasMemberWrite = false;
  for (const permission of permissionPage.value) {
    if (!permission || permission.link || permission.grantedToIdentities || permission.grantedToIdentitiesV2 ||
        !Array.isArray(permission.roles) || permission.roles.length === 0 ||
        permission.roles.some(role => !['owner', 'read', 'write'].includes(role))) return false;
    const granted = permission.grantedToV2 ?? permission.grantedTo;
    // Groups, applications, anonymous links, and unknown identity forms must be reviewed separately.
    if (!granted || granted.group || granted.application || granted.siteGroup || !granted.user?.id ||
        (granted.siteUser && granted.siteUser.id !== granted.user.id)) return false;
    const id = granted.user.id;
    if (id !== ownerIdentityId && id !== memberIdentityId) return false;
    if (permission.roles.includes('owner')) {
      if (id !== ownerIdentityId) return false;
      hasOwner = true;
    }
    if (id === memberIdentityId && permission.roles.includes('write')) hasMemberWrite = true;
  }
  return hasOwner && hasMemberWrite;
}

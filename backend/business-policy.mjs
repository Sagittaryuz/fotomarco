/** Authorization primitives for a trusted server. Never accept these records from a client. */
const photoActions = new Set(['view', 'edit', 'delete', 'move', 'download']);
const scopes = new Set(['none', 'own', 'all']);

function membershipFor(identity, organization, membership) {
  if (!identity || typeof identity.uid !== 'string' || !identity.uid || !organization ||
      typeof organization.id !== 'string' || !organization.id || typeof organization.ownerId !== 'string' || !organization.ownerId ||
      !membership || membership.organizationId !== organization.id || membership.userId !== identity.uid ||
      membership.active !== true || !['owner', 'administrator', 'member'].includes(membership.role)) return null;
  if (membership.role === 'owner' && membership.userId !== organization.ownerId) return null;
  if (membership.role !== 'owner' && membership.userId === organization.ownerId) return null;
  return membership;
}

export function mayManage(identity, organization, membership) {
  const member = membershipFor(identity, organization, membership);
  return member !== null && (member.role === 'owner' || member.role === 'administrator');
}

export function mayReadPublishedProfile(identity, organization, membership) {
  return membershipFor(identity, organization, membership) !== null;
}

export function mayAccessPhoto(identity, organization, membership, photo, action, permissions = {}) {
  const member = membershipFor(identity, organization, membership);
  if (!member || !photoActions.has(action) || !photo || photo.organizationId !== organization.id ||
      typeof photo.authorId !== 'string' || !photo.authorId) return false;
  if (mayManage(identity, organization, membership)) return true;
  const scope = permissions[action] ?? 'own';
  if (!scopes.has(scope)) return false;
  return scope === 'all' || (scope === 'own' && photo.authorId === identity.uid);
}

export function mayInvite(identity, organization, membership, occupiedSeats) {
  return mayManage(identity, organization, membership) && Number.isInteger(occupiedSeats) &&
    occupiedSeats >= 0 && occupiedSeats < 500;
}

export function mayAcceptInvitation(identity, invitation, now) {
  return !!identity && typeof identity.uid === 'string' && identity.uid.length > 0 &&
    identity.emailVerified === true && typeof identity.email === 'string' && !!invitation &&
    typeof invitation.email === 'string' && identity.email.trim().toLowerCase() === invitation.email.trim().toLowerCase() &&
    invitation.email.includes('@') && invitation.state === 'pending' &&
    Number.isSafeInteger(invitation.expiresAt) && Number.isSafeInteger(now) && now < invitation.expiresAt;
}

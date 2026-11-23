import { mayAcceptInvitation, mayInvite, mayManage, mayReadPublishedProfile } from './business-policy.mjs';

/**
 * Transactional service. The adapter must verify Firebase ID tokens and load records
 * from trusted storage. No client may supply a membership or occupied-seat count.
 * occupiedSeats must read a shared per-organization counter and addMember must
 * increment that same counter atomically in the enclosing transaction.
 */
export class BusinessService {
  constructor({ verifyToken, transaction, newId, clock, canCreateOrganization }) {
    this.verifyToken = verifyToken;
    this.transaction = transaction;
    this.newId = newId;
    this.clock = clock;
    this.canCreateOrganization = canCreateOrganization;
  }

  async createOrganization(token, name, contactEmail) {
    const identity = await this.verifyToken(token);
    const displayName = typeof name === 'string' ? name.trim() : '';
    const address = typeof contactEmail === 'string' ? contactEmail.trim().toLowerCase() : '';
    if (!identity?.uid || identity.emailVerified !== true || !displayName || displayName.length > 160 ||
        address.length > 254 || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(address)) throw new Error('invalid-request');
    if (typeof this.canCreateOrganization !== 'function' || await this.canCreateOrganization(identity) !== true) throw new Error('forbidden');
    const id = this.newId();
    if (typeof id !== 'string' || !id) throw new Error('invalid-id');
    return this.transaction(async tx => {
      await tx.initializeOrganization({ id, ownerId: identity.uid, name: displayName, contactEmail: address });
      return { organizationId: id };
    });
  }

  async invite(token, organizationId, email) {
    const identity = await this.verifyToken(token);
    const address = typeof email === 'string' ? email.trim().toLowerCase() : '';
    if (!identity?.uid || typeof organizationId !== 'string' || !organizationId ||
        address.length > 254 || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(address)) throw new Error('invalid-request');
    const id = this.newId();
    if (typeof id !== 'string' || !id) throw new Error('invalid-id');
    return this.transaction(async tx => {
      const organization = await tx.organization(organizationId);
      const membership = await tx.membership(organizationId, identity.uid);
      const seats = await tx.occupiedSeats(organizationId);
      if (!mayInvite(identity, organization, membership, seats)) throw new Error('forbidden-or-full');
      const invitation = { id, organizationId, email: address, state: 'pending',
        expiresAt: this.clock() + 7 * 24 * 60 * 60 * 1000 };
      await tx.createInvitation(invitation);
      return { id, expiresAt: invitation.expiresAt };
    });
  }

  async accept(token, organizationId, invitationId) {
    const identity = await this.verifyToken(token);
    if (!identity?.uid || typeof organizationId !== 'string' || !organizationId ||
        typeof invitationId !== 'string' || !invitationId) throw new Error('invalid-request');
    return this.transaction(async tx => {
      const organization = await tx.organization(organizationId);
      const invitation = await tx.invitation(organizationId, invitationId);
      if (!organization || organization.id !== organizationId || invitation?.organizationId !== organizationId ||
          invitation.id !== invitationId || !mayAcceptInvitation(identity, invitation, this.clock())) throw new Error('invalid-invitation');
      const existing = await tx.membership(organizationId, identity.uid);
      if (existing?.active) throw new Error('already-member');
      const seats = await tx.occupiedSeats(organizationId);
      if (!Number.isInteger(seats) || seats < 0 || seats >= 500) throw new Error('full');
      await tx.addMember({ organizationId, userId: identity.uid, role: 'member', active: true });
      await tx.markInvitationAccepted(organizationId, invitationId, identity.uid);
      return { organizationId };
    });
  }

  async publishProfile(token, organizationId, layoutJSON) {
    const identity = await this.verifyToken(token);
    if (!identity?.uid || typeof organizationId !== 'string' || !organizationId ||
        typeof layoutJSON !== 'string' || new TextEncoder().encode(layoutJSON).length > 65536) throw new Error('invalid-request');
    let layout;
    try { layout = JSON.parse(layoutJSON); } catch { throw new Error('invalid-request'); }
    if (!layout || typeof layout !== 'object' || Array.isArray(layout)) throw new Error('invalid-request');
    const versionId = this.newId();
    if (typeof versionId !== 'string' || !versionId) throw new Error('invalid-id');
    return this.transaction(async tx => {
      const org = await tx.organization(organizationId);
      const member = await tx.membership(organizationId, identity.uid);
      if (!mayManage(identity, org, member)) throw new Error('forbidden');
      await tx.publishProfile({ organizationId, versionId, layoutJSON, publishedBy: identity.uid, publishedAt: this.clock() });
      return { versionId };
    });
  }

  async readProfile(token, organizationId) {
    const identity = await this.verifyToken(token);
    if (!identity?.uid || typeof organizationId !== 'string' || !organizationId) throw new Error('invalid-request');
    return this.transaction(async tx => {
      const org = await tx.organization(organizationId);
      const member = await tx.membership(organizationId, identity.uid);
      if (!mayReadPublishedProfile(identity, org, member)) throw new Error('forbidden');
      const profile = await tx.latestProfile(organizationId);
      if (!profile || profile.organizationId !== organizationId) throw new Error('not-found');
      return profile;
    });
  }
}

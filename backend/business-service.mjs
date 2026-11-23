import { mayAcceptInvitation, mayInvite } from './business-policy.mjs';

/**
 * Transactional service. The adapter must verify Firebase ID tokens and load records
 * from trusted storage. No client may supply a membership or occupied-seat count.
 * occupiedSeats must read a shared per-organization counter and addMember must
 * increment that same counter atomically in the enclosing transaction.
 */
export class BusinessService {
  constructor({ verifyToken, transaction, newId, clock }) {
    this.verifyToken = verifyToken;
    this.transaction = transaction;
    this.newId = newId;
    this.clock = clock;
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
}

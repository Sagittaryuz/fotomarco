import { mayAcceptInvitation, mayInvite, mayManage, mayReadPublishedProfile } from './business-policy.mjs';

/**
 * Transactional service. The adapter must verify Firebase ID tokens and load records
 * from trusted storage. No client may supply a membership or occupied-seat count.
 * occupiedSeats must read a shared per-organization counter and addMember must
 * increment that same counter atomically in the enclosing transaction.
 */
export class BusinessService {
  constructor({ verifyToken, transaction, newId, clock, canCreateOrganization, prepareOneDrive }) {
    this.verifyToken = verifyToken;
    this.transaction = transaction;
    this.newId = newId;
    this.clock = clock;
    this.canCreateOrganization = canCreateOrganization;
    this.prepareOneDrive = prepareOneDrive;
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

  async readOrganization(token, organizationId) {
    const identity = await this.verifyToken(token);
    if (!identity?.uid || typeof organizationId !== 'string' || !organizationId) throw new Error('invalid-request');
    return this.transaction(async tx => {
      const org = await tx.organization(organizationId);
      const member = await tx.membership(organizationId, identity.uid);
      if (!mayReadPublishedProfile(identity, org, member)) throw new Error('forbidden');
      return { id: org.id, name: org.name, photoAssetId: org.photoAssetId ?? '',
        ...(mayManage(identity, org, member) ? { contactEmail: org.contactEmail } : {}) };
    });
  }

  async myOrganizations(token) {
    const identity = await this.verifyToken(token);
    if (!identity?.uid) throw new Error('invalid-request');
    return this.transaction(async tx => {
      const indexes = await tx.userOrganizations(identity.uid);
      if (!Array.isArray(indexes) || indexes.length > 500 || new Set(indexes).size !== indexes.length) throw new Error('invalid-index');
      const organizations = [];
      for (const id of indexes) {
        const org = await tx.organization(id);
        const member = await tx.membership(id, identity.uid);
        if (org?.id === id && mayReadPublishedProfile(identity, org, member)) {
          organizations.push({ id, name: org.name, role: member.role, photoAssetId: org.photoAssetId ?? '' });
        }
      }
      return { organizations };
    });
  }

  async updateOrganization(token, organizationId, name, contactEmail, photoAssetId) {
    const identity = await this.verifyToken(token);
    const displayName = typeof name === 'string' ? name.trim() : '';
    const address = typeof contactEmail === 'string' ? contactEmail.trim().toLowerCase() : '';
    if (!identity?.uid || typeof organizationId !== 'string' || !organizationId || !displayName || displayName.length > 160 ||
        address.length > 254 || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(address) ||
        typeof photoAssetId !== 'string' || (photoAssetId && !/^[A-Za-z0-9_-]{1,128}$/.test(photoAssetId))) throw new Error('invalid-request');
    return this.transaction(async tx => {
      const org = await tx.organization(organizationId);
      const member = await tx.membership(organizationId, identity.uid);
      if (!mayManage(identity, org, member)) throw new Error('forbidden');
      if (photoAssetId) {
        const photo = await tx.asset(organizationId, photoAssetId);
        if (!photo || photo.organizationId !== organizationId || photo.assetId !== photoAssetId) throw new Error('invalid-request');
      }
      await tx.updateOrganization(organizationId, { name: displayName, contactEmail: address, photoAssetId });
      return { id: organizationId, name: displayName, contactEmail: address, photoAssetId };
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

  async listMembers(token, organizationId) {
    const identity = await this.verifyToken(token);
    if (!identity?.uid || typeof organizationId !== 'string' || !organizationId) throw new Error('invalid-request');
    return this.transaction(async tx => {
      const organization = await tx.organization(organizationId);
      const membership = await tx.membership(organizationId, identity.uid);
      if (!mayManage(identity, organization, membership)) throw new Error('forbidden');
      const members = await tx.activeMembers(organizationId);
      if (!Array.isArray(members) || members.length > 500 || members.some(member =>
        member.organizationId !== organizationId || typeof member.userId !== 'string' ||
        !member.userId || member.active !== true || !['owner', 'administrator', 'member'].includes(member.role))) {
        throw new Error('invalid-members');
      }
      return { members: members.map(({ userId, role, email }) => ({ userId, role, ...(typeof email === 'string' ? { email } : {}) })) };
    });
  }

  async connectOneDrive(token, organizationId, refreshToken) {
    const identity = await this.verifyToken(token);
    if (!identity?.uid || typeof organizationId !== 'string' || !organizationId ||
        typeof refreshToken !== 'string' || !refreshToken || refreshToken.length > 16384 ||
        typeof this.prepareOneDrive !== 'function') throw new Error('invalid-request');
    const verifyOwner = async tx => {
      const org = await tx.organization(organizationId);
      const member = await tx.membership(organizationId, identity.uid);
      if (!mayManage(identity, org, member) || member.role !== 'owner') throw new Error('forbidden');
    };
    await this.transaction(verifyOwner);
    const record = await this.prepareOneDrive({ organizationId, ownerId: identity.uid, refreshToken });
    if (!record || record.version !== 1 || typeof record.iv !== 'string' || typeof record.ciphertext !== 'string' ||
        typeof record.driveId !== 'string' || typeof record.providerAccountId !== 'string' ||
        Object.keys(record).sort().join(',') !== 'ciphertext,driveId,iv,providerAccountId,version') throw new Error('invalid-provider-credential');
    return this.transaction(async tx => {
      await verifyOwner(tx);
      const existing = await tx.oneDriveCredential(organizationId);
      if (existing && (existing.providerAccountId !== record.providerAccountId || existing.driveId !== record.driveId)) {
        throw new Error('storage-account-change-requires-migration');
      }
      await tx.setOneDriveCredential(organizationId, record);
      return { connected: true };
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
      await tx.addMember({ organizationId, userId: identity.uid, role: 'member', active: true,
        email: identity.email.trim().toLowerCase() });
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

  async uploadAsset(token, organizationId, mimeType, base64) {
    const identity = await this.verifyToken(token);
    if (!identity?.uid || typeof organizationId !== 'string' || !organizationId ||
        !['image/jpeg', 'image/png'].includes(mimeType) || typeof base64 !== 'string' ||
        base64.length > 349528 || base64.length % 4 !== 0 ||
        !/^(?:[A-Za-z0-9+/]{4})*(?:[A-Za-z0-9+/]{2}==|[A-Za-z0-9+/]{3}=)?$/.test(base64)) throw new Error('invalid-request');
    let bytes;
    try { bytes = atob(base64); } catch { throw new Error('invalid-request'); }
    const png = bytes.length >= 8 && [137,80,78,71,13,10,26,10].every((v, i) => bytes.charCodeAt(i) === v);
    const jpeg = bytes.length >= 3 && [255,216,255].every((v, i) => bytes.charCodeAt(i) === v);
    if (bytes.length > 262144 || (mimeType === 'image/png' ? !png : !jpeg)) throw new Error('invalid-request');
    const assetId = this.newId();
    if (typeof assetId !== 'string' || !assetId) throw new Error('invalid-id');
    return this.transaction(async tx => {
      const org = await tx.organization(organizationId);
      const member = await tx.membership(organizationId, identity.uid);
      if (!mayManage(identity, org, member)) throw new Error('forbidden');
      await tx.createAsset({ organizationId, assetId, mimeType, base64, createdBy: identity.uid, createdAt: this.clock() });
      return { assetId };
    });
  }

  async readAsset(token, organizationId, assetId) {
    const identity = await this.verifyToken(token);
    if (!identity?.uid || typeof organizationId !== 'string' || !organizationId || typeof assetId !== 'string' || !assetId) throw new Error('invalid-request');
    return this.transaction(async tx => {
      const org = await tx.organization(organizationId);
      const member = await tx.membership(organizationId, identity.uid);
      if (!mayReadPublishedProfile(identity, org, member)) throw new Error('forbidden');
      const asset = await tx.asset(organizationId, assetId);
      if (!asset || asset.organizationId !== organizationId || asset.assetId !== assetId) throw new Error('not-found');
      return { mimeType: asset.mimeType, base64: asset.base64 };
    });
  }
}

import { mayAcceptInvitation, mayInvite, mayManage, mayReadPublishedProfile } from './business-policy.mjs';
import { validBusinessPhotoName } from './business-onedrive-upload.mjs';

/**
 * Transactional service. The adapter must verify Firebase ID tokens and load records
 * from trusted storage. No client may supply a membership or occupied-seat count.
 * occupiedSeats must read a shared per-organization counter and addMember must
 * increment that same counter atomically in the enclosing transaction.
 */
export class BusinessService {
  constructor({ verifyToken, transaction, newId, clock, canCreateOrganization, prepareOneDrive, prepareGoogleMail, prepareMailDelivery, revokeMemberStorage, prepareUpload, processUploadChunk, verifyUpload }) {
    this.verifyToken = verifyToken;
    this.transaction = transaction;
    this.newId = newId;
    this.clock = clock;
    this.canCreateOrganization = canCreateOrganization;
    this.prepareOneDrive = prepareOneDrive;
    this.prepareGoogleMail = prepareGoogleMail;
    this.prepareMailDelivery = prepareMailDelivery;
    this.revokeMemberStorage = revokeMemberStorage;
    this.prepareUpload = prepareUpload;
    this.processUploadChunk = processUploadChunk;
    this.verifyUpload = verifyUpload;
  }

  async createOrganization(token, name, contactEmail) {
    const identity = await this.verifyToken(token);
    const displayName = typeof name === 'string' ? name.trim() : '';
    const address = typeof contactEmail === 'string' ? contactEmail.trim().toLowerCase() : '';
    if (!identity?.uid || identity.emailVerified !== true || typeof identity.email !== 'string' || !identity.email || !displayName || displayName.length > 160 ||
        address.length > 254 || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(address)) throw new Error('invalid-request');
    if (typeof this.canCreateOrganization !== 'function' || await this.canCreateOrganization(identity) !== true) throw new Error('forbidden');
    const id = this.newId();
    if (typeof id !== 'string' || !id) throw new Error('invalid-id');
    return this.transaction(async tx => {
      await tx.initializeOrganization({ id, ownerId: identity.uid, name: displayName, contactEmail: address },
        identity.email.trim().toLowerCase(), identity.displayName);
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
          const captureReady = member.storageStatus === 'granted' && typeof member.oneDriveFolderId === 'string' && !!member.oneDriveFolderId &&
            typeof member.oneDriveParentId === 'string' && !!member.oneDriveParentId &&
            typeof member.oneDriveMemberIdentityId === 'string' && !!member.oneDriveMemberIdentityId;
          organizations.push({ id, name: org.name, role: member.role, photoAssetId: org.photoAssetId ?? '', captureReady });
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
    const loadInvitationContext = async tx => {
      const organization = await tx.organization(organizationId);
      const membership = await tx.membership(organizationId, identity.uid);
      const seats = await tx.occupiedSeats(organizationId);
      if (!mayInvite(identity, organization, membership, seats)) throw new Error('forbidden-or-full');
      const mail = await tx.googleMailCredential(organizationId);
      if (!mail || mail.email !== organization.contactEmail || typeof this.prepareMailDelivery !== 'function') throw new Error('mail-not-configured');
      return { organization, mail };
    };
    const context = await this.transaction(loadInvitationContext);
    const prepared = await this.prepareMailDelivery({ organizationId, organization: context.organization, mail: context.mail });
    if (!prepared || typeof prepared.send !== 'function' || !prepared.record || prepared.record.version !== 1 ||
        typeof prepared.record.iv !== 'string' || !prepared.record.iv || typeof prepared.record.ciphertext !== 'string' || !prepared.record.ciphertext ||
        prepared.record.email !== context.organization.contactEmail || prepared.record.providerAccountId !== context.mail.providerAccountId ||
        Object.keys(prepared.record).sort().join(',') !== 'ciphertext,email,iv,providerAccountId,version') throw new Error('invalid-provider-credential');
    const receipt = await this.transaction(async tx => {
      const current = await loadInvitationContext(tx);
      if (current.organization.ownerId !== context.organization.ownerId || current.organization.contactEmail !== context.organization.contactEmail ||
          current.mail.ciphertext !== context.mail.ciphertext || current.mail.iv !== context.mail.iv) throw new Error('mail-configuration-changed');
      const invitation = { id, organizationId, email: address, invitedBy: identity.uid, state: 'pending',
        expiresAt: this.clock() + 7 * 24 * 60 * 60 * 1000 };
      await tx.createInvitation(invitation);
      await tx.setGoogleMailCredential(organizationId, prepared.record);
      return { id, expiresAt: invitation.expiresAt };
    });
    await prepared.send({ recipientEmail: address, organizationName: context.organization.name, organizationId, invitationId: id });
    return receipt;
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
        !member.userId || (member.active !== true && !(member.active === false && member.revocationState === 'pending')) ||
        !['owner', 'administrator', 'member'].includes(member.role)) || new Set(members.map(member => member.userId)).size !== members.length) {
        throw new Error('invalid-members');
      }
      return { members: members.map(({ userId, role, email, displayName, revocationState }) => ({ userId, role,
        ...(typeof email === 'string' ? { email } : {}), ...(typeof displayName === 'string' ? { displayName } : {}),
        ...(revocationState === 'pending' ? { revocationPending: true } : {}) })) };
    });
  }

  async removeMember(token, organizationId, targetId) {
    const identity = await this.verifyToken(token);
    if (!identity?.uid || typeof organizationId !== 'string' || !organizationId ||
        typeof targetId !== 'string' || !targetId || targetId === identity.uid) throw new Error('invalid-request');
    const marker = this.newId();
    if (typeof marker !== 'string' || !marker) throw new Error('invalid-id');
    const authorize = async tx => {
      const org = await tx.organization(organizationId);
      const actor = await tx.membership(organizationId, identity.uid);
      const target = await tx.membership(organizationId, targetId);
      if (!mayManage(identity, org, actor) || !target || target.organizationId !== organizationId ||
          target.userId !== targetId || target.role === 'owner' || !['member', 'administrator'].includes(target.role) ||
          (target.role === 'administrator' && actor.role !== 'owner')) throw new Error('forbidden');
      return { org, target };
    };
    const started = await this.transaction(async tx => {
      const { org, target } = await authorize(tx);
      if (target.active === false && target.revocationState === 'complete') return { complete: true };
      if (target.active === false && target.revocationState === 'pending' && target.revocationId) return { org, target };
      if (target.active !== true) throw new Error('forbidden');
      await tx.beginMemberRevocation(organizationId, targetId, marker);
      return { org, target: { ...target, active: false, revocationState: 'pending', revocationId: marker } };
    });
    if (started.complete) return { complete: true };
    if (started.target.storageStatus !== 'not-started') {
      if (typeof this.revokeMemberStorage !== 'function') return { complete: false };
      try {
        if (await this.revokeMemberStorage({ organizationId, organization: started.org, member: started.target }) !== true) return { complete: false };
      } catch { return { complete: false }; }
    }
    return this.transaction(async tx => {
      const { target } = await authorize(tx);
      if (target.active === false && target.revocationState === 'complete') return { complete: true };
      if (target.active !== false || target.revocationState !== 'pending' || target.revocationId !== started.target.revocationId ||
          target.storageStatus !== started.target.storageStatus) throw new Error('revocation-conflict');
      const seats = await tx.occupiedSeats(organizationId);
      if (!Number.isInteger(seats) || seats < 2) throw new Error('invalid-seat-counter');
      await tx.completeMemberRevocation(organizationId, targetId);
      return { complete: true };
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

  async reserveCapture(token, organizationId, captureId, filename, byteCount, sha256) {
    const identity = await this.verifyToken(token);
    if (!identity?.uid || identity.emailVerified !== true || !validBusinessPhotoName(filename, captureId, organizationId) ||
        !Number.isSafeInteger(byteCount) || byteCount < 1 || byteCount > 200 * 1024 * 1024 ||
        typeof sha256 !== 'string' || !/^[0-9a-f]{64}$/.test(sha256)) throw new Error('invalid-request');
    const variant = /-stamped\.jpg$/i.test(filename) ? 'stamped' : 'original';
    const recordId = `${captureId.toLowerCase()}-${variant}`;
    return this.transaction(async tx => {
      const org = await tx.organization(organizationId);
      const member = await tx.membership(organizationId, identity.uid);
      if (!mayReadPublishedProfile(identity, org, member) || member.storageStatus !== 'granted' ||
          typeof member.oneDriveFolderId !== 'string' || !member.oneDriveFolderId ||
          typeof member.oneDriveParentId !== 'string' || !member.oneDriveParentId ||
          typeof member.oneDriveMemberIdentityId !== 'string' || !member.oneDriveMemberIdentityId) throw new Error('forbidden');
      const ownerStorage = await tx.oneDriveCredential(organizationId);
      if (!ownerStorage?.driveId || !ownerStorage?.providerAccountId) throw new Error('storage-unavailable');
      const existing = await tx.capture(organizationId, recordId);
      if (existing) {
        if (existing.authorId !== identity.uid || existing.filename !== filename || existing.byteCount !== byteCount ||
            existing.sha256 !== sha256 || existing.folderId !== member.oneDriveFolderId || existing.driveId !== ownerStorage.driveId ||
            !['reserved', 'uploading', 'verifying', 'verified', 'uncertain'].includes(existing.state)) throw new Error('capture-conflict');
        return { captureId, variant, state: existing.state };
      }
      await tx.createCapture({ organizationId, captureId, recordId, variant, authorId: identity.uid, filename, byteCount, sha256,
        folderId: member.oneDriveFolderId, parentId: member.oneDriveParentId, memberProviderId: member.oneDriveMemberIdentityId,
        driveId: ownerStorage.driveId, ownerProviderId: ownerStorage.providerAccountId, state: 'reserved', createdAt: this.clock() });
      return { captureId, variant, state: 'reserved' };
    });
  }

  async captureContext(tx, identity, organizationId, recordId) {
    const org = await tx.organization(organizationId);
    const member = await tx.membership(organizationId, identity.uid);
    const capture = await tx.capture(organizationId, recordId);
    const storage = await tx.oneDriveCredential(organizationId);
    if (identity.emailVerified !== true || !mayReadPublishedProfile(identity, org, member) || member.storageStatus !== 'granted' ||
        !capture || capture.organizationId !== organizationId || capture.recordId !== recordId || capture.authorId !== identity.uid ||
        capture.folderId !== member.oneDriveFolderId || capture.parentId !== member.oneDriveParentId ||
        capture.memberProviderId !== member.oneDriveMemberIdentityId || capture.driveId !== storage?.driveId ||
        capture.ownerProviderId !== storage?.providerAccountId) throw new Error('forbidden');
    return { org, member, capture, storage };
  }

  async startCaptureUpload(token, organizationId, captureId, variant) {
    const identity = await this.verifyToken(token);
    if (!identity?.uid || typeof organizationId !== 'string' || typeof captureId !== 'string' ||
        !/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(captureId) ||
        !['original', 'stamped'].includes(variant) || typeof this.prepareUpload !== 'function') throw new Error('invalid-request');
    const recordId = `${captureId.toLowerCase()}-${variant}`;
    const context = await this.transaction(tx => this.captureContext(tx, identity, organizationId, recordId));
    if (context.capture.state === 'uploading') {
      if (!Number.isSafeInteger(context.capture.nextOffset) || context.capture.nextOffset < 0 ||
          context.capture.nextOffset >= context.capture.byteCount || !Number.isSafeInteger(context.capture.sessionExpiresAt) || context.capture.sessionExpiresAt <= this.clock()) throw new Error('upload-result-uncertain');
      return { state: 'uploading', nextOffset: context.capture.nextOffset };
    }
    if (context.capture.state === 'verified') return { state: 'verified', nextOffset: context.capture.byteCount };
    if (context.capture.state !== 'reserved') throw new Error('upload-result-uncertain');
    const prepared = await this.prepareUpload({ organizationId, identity, ...context });
    if (!prepared || !prepared.session || prepared.session.version !== 1 || !prepared.session.iv || !prepared.session.ciphertext ||
        !Number.isSafeInteger(prepared.expiresAt) || prepared.expiresAt <= this.clock() || !prepared.ownerCredential ||
        prepared.ownerCredential.version !== 1 || !prepared.ownerCredential.iv || !prepared.ownerCredential.ciphertext ||
        prepared.ownerCredential.driveId !== context.storage.driveId || prepared.ownerCredential.providerAccountId !== context.storage.providerAccountId) throw new Error('invalid-upload-session');
    return this.transaction(async tx => {
      const current = await this.captureContext(tx, identity, organizationId, recordId);
      if (current.capture.state === 'uploading') {
        if (!Number.isSafeInteger(current.capture.nextOffset) || current.capture.nextOffset < 0 ||
            current.capture.nextOffset >= current.capture.byteCount || !Number.isSafeInteger(current.capture.sessionExpiresAt) || current.capture.sessionExpiresAt <= this.clock()) throw new Error('upload-result-uncertain');
        return { state: 'uploading', nextOffset: current.capture.nextOffset };
      }
      if (current.capture.state !== 'reserved' || current.storage.ciphertext !== context.storage.ciphertext ||
          current.storage.iv !== context.storage.iv) throw new Error('upload-configuration-changed');
      await tx.setOneDriveCredential(organizationId, prepared.ownerCredential);
      await tx.beginCaptureUpload(organizationId, recordId, prepared.session, prepared.expiresAt);
      return { state: 'uploading', nextOffset: 0 };
    });
  }

  async sendCaptureChunk(token, organizationId, captureId, variant, offset, bytes) {
    const identity = await this.verifyToken(token);
    if (!identity?.uid || typeof organizationId !== 'string' || typeof captureId !== 'string' ||
        !/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(captureId) ||
        !['original', 'stamped'].includes(variant) || !Number.isSafeInteger(offset) || offset < 0 ||
        !(bytes instanceof Uint8Array) || bytes.length < 1 || bytes.length > 320 * 1024 * 10 ||
        typeof this.processUploadChunk !== 'function') throw new Error('invalid-request');
    const recordId = `${captureId.toLowerCase()}-${variant}`;
    const leaseId = this.newId();
    if (typeof leaseId !== 'string' || !leaseId) throw new Error('invalid-id');
    const acquired = await this.transaction(async tx => {
      const context = await this.captureContext(tx, identity, organizationId, recordId);
      const capture = context.capture;
      if (capture.state !== 'uploading' || !Number.isSafeInteger(capture.nextOffset) ||
          !Number.isSafeInteger(capture.sessionExpiresAt) || capture.sessionExpiresAt <= this.clock()) throw new Error('upload-result-uncertain');
      if (offset !== capture.nextOffset) return { state: 'uploading', nextOffset: capture.nextOffset };
      const chunkUnit = 320 * 1024;
      if (offset % chunkUnit !== 0 || offset + bytes.length > capture.byteCount ||
          (offset + bytes.length < capture.byteCount && bytes.length % chunkUnit !== 0)) throw new Error('invalid-request');
      if (capture.leaseId && (!Number.isSafeInteger(capture.leaseExpiresAt) || capture.leaseExpiresAt > this.clock())) throw new Error('upload-busy');
      await tx.leaseCaptureChunk(organizationId, recordId, leaseId, this.clock() + 120000);
      return context;
    });
    if (acquired.state === 'uploading') return acquired;
    const result = await this.processUploadChunk({ organizationId, identity, ...acquired, offset, bytes });
    if (!result || !['pending', 'uploaded-unverified'].includes(result.state) ||
        (result.state === 'pending' && (!Number.isSafeInteger(result.nextOffset) || result.nextOffset !== offset + bytes.length || result.nextOffset >= acquired.capture.byteCount)) ||
        (result.state === 'uploaded-unverified' && (typeof result.itemId !== 'string' || !result.itemId || offset + bytes.length !== acquired.capture.byteCount))) throw new Error('upload-result-uncertain');
    return this.transaction(async tx => {
      const current = await this.captureContext(tx, identity, organizationId, recordId);
      if (current.capture.state !== 'uploading' || current.capture.leaseId !== leaseId || current.capture.nextOffset !== offset ||
          current.capture.sessionCiphertext !== acquired.capture.sessionCiphertext) throw new Error('upload-configuration-changed');
      await tx.completeCaptureChunk(organizationId, recordId, result, current.capture.byteCount);
      return result.state === 'pending' ? { state: 'uploading', nextOffset: result.nextOffset } :
        { state: 'verifying', nextOffset: current.capture.byteCount };
    });
  }

  async verifyCapture(token, organizationId, captureId, variant) {
    const identity = await this.verifyToken(token);
    if (!identity?.uid || typeof organizationId !== 'string' || typeof captureId !== 'string' ||
        !/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(captureId) ||
        !['original', 'stamped'].includes(variant) || typeof this.verifyUpload !== 'function') throw new Error('invalid-request');
    const recordId = `${captureId.toLowerCase()}-${variant}`;
    const context = await this.transaction(tx => this.captureContext(tx, identity, organizationId, recordId));
    if (context.capture.state === 'verified') return { state: 'verified', nextOffset: context.capture.byteCount };
    if (context.capture.state !== 'verifying' || typeof context.capture.remoteItemId !== 'string' || !context.capture.remoteItemId) throw new Error('upload-result-uncertain');
    const result = await this.verifyUpload({ organizationId, identity, ...context });
    if (!result || result.verified !== true || !result.ownerCredential || result.ownerCredential.version !== 1 ||
        !result.ownerCredential.iv || !result.ownerCredential.ciphertext || result.ownerCredential.driveId !== context.storage.driveId ||
        result.ownerCredential.providerAccountId !== context.storage.providerAccountId) throw new Error('upload-verification-unavailable');
    return this.transaction(async tx => {
      const current = await this.captureContext(tx, identity, organizationId, recordId);
      if (current.capture.state === 'verified') return { state: 'verified', nextOffset: current.capture.byteCount };
      if (current.capture.state !== 'verifying' || current.capture.remoteItemId !== context.capture.remoteItemId ||
          current.capture.sha256 !== context.capture.sha256 || current.capture.byteCount !== context.capture.byteCount) throw new Error('upload-configuration-changed');
      if (current.storage.ciphertext === context.storage.ciphertext && current.storage.iv === context.storage.iv) {
        await tx.setOneDriveCredential(organizationId, result.ownerCredential);
      }
      await tx.markCaptureVerified(organizationId, recordId, this.clock());
      return { state: 'verified', nextOffset: current.capture.byteCount };
    });
  }

  async connectGoogleMail(token, organizationId, refreshToken) {
    const identity = await this.verifyToken(token);
    if (!identity?.uid || typeof organizationId !== 'string' || !organizationId ||
        typeof refreshToken !== 'string' || !refreshToken || refreshToken.length > 16384 ||
        typeof this.prepareGoogleMail !== 'function') throw new Error('invalid-request');
    const readOwner = async tx => {
      const org = await tx.organization(organizationId);
      const member = await tx.membership(organizationId, identity.uid);
      if (!mayManage(identity, org, member) || member.role !== 'owner') throw new Error('forbidden');
      return org;
    };
    const org = await this.transaction(readOwner);
    const record = await this.prepareGoogleMail({ organizationId, ownerId: identity.uid, refreshToken });
    if (!record || record.version !== 1 || typeof record.iv !== 'string' || typeof record.ciphertext !== 'string' ||
        typeof record.providerAccountId !== 'string' || typeof record.email !== 'string' ||
        Object.keys(record).sort().join(',') !== 'ciphertext,email,iv,providerAccountId,version' ||
        record.email !== org.contactEmail) throw new Error('mailbox-mismatch');
    return this.transaction(async tx => {
      const current = await readOwner(tx);
      if (current.contactEmail !== record.email) throw new Error('mailbox-mismatch');
      await tx.setGoogleMailCredential(organizationId, record);
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
      if (typeof invitation.invitedBy !== 'string' || !invitation.invitedBy) throw new Error('invalid-invitation');
      const inviter = await tx.membership(organizationId, invitation.invitedBy);
      if (!mayManage({ uid: invitation.invitedBy }, organization, inviter)) throw new Error('invalid-invitation');
      const existing = await tx.membership(organizationId, identity.uid);
      if (existing?.active) throw new Error('already-member');
      if (existing?.revocationState === 'pending') throw new Error('revocation-pending');
      const seats = await tx.occupiedSeats(organizationId);
      if (!Number.isInteger(seats) || seats < 0 || seats >= 500) throw new Error('full');
      await tx.addMember({ organizationId, userId: identity.uid, role: 'member', active: true, storageStatus: 'not-started',
        email: identity.email.trim().toLowerCase(), ...(identity.displayName ? { displayName: identity.displayName } : {}) });
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

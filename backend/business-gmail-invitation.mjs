/** Sends only after the mailbox is verified to be the organization's sender. */
export function gmailInvitationSender({ invitationOrigin, fetchImpl = fetch }) {
  let origin;
  try { origin = new URL(invitationOrigin); } catch { throw new Error('invalid-invitation-origin'); }
  if (origin.protocol !== 'https:' || !origin.hostname || origin.username || origin.password || origin.port ||
      origin.pathname !== '/' || origin.search || origin.hash) throw new Error('invalid-invitation-origin');
  const email = value => typeof value === 'string' && value.length <= 254 &&
    /^[^\s@<>]+@[^\s@<>]+\.[^\s@<>]+$/.test(value) && !/[\r\n]/.test(value);
  const uuid = value => typeof value === 'string' && /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(value);
  return async ({ accessToken, senderEmail, recipientEmail, organizationName, organizationId, invitationId }) => {
    if (typeof accessToken !== 'string' || !accessToken || accessToken.length > 16384 ||
        !email(senderEmail) || !email(recipientEmail) || typeof organizationName !== 'string' ||
        !organizationName.trim() || organizationName.length > 160 || /[\x00-\x1f\x7f]/.test(organizationName) ||
        !uuid(organizationId) || !uuid(invitationId)) throw new Error('invalid-mail-request');
    const headers = { authorization: `Bearer ${accessToken}` };
    const profile = await fetchImpl('https://openidconnect.googleapis.com/v1/userinfo', { headers, redirect: 'manual' });
    if (profile.status !== 200) throw new Error('mail-unavailable');
    const mailbox = await profile.json();
    if (mailbox.email_verified !== true || typeof mailbox.email !== 'string' || mailbox.email.toLowerCase() !== senderEmail.toLowerCase()) throw new Error('mailbox-mismatch');
    const link = new URL('/convite', origin);
    link.searchParams.set('organization', organizationId.toLowerCase());
    link.searchParams.set('invitation', invitationId.toLowerCase());
    const text = `${organizationName.trim()} convidou você para uma organização no Photomark.\r\n\r\nAbra o convite e entre com o e-mail que o recebeu:\r\n${link.href}\r\n\r\nSe não esperava este convite, ignore esta mensagem.`;
    const subject = 'Convite para o Photomark';
    const mime = `From: ${senderEmail}\r\nTo: ${recipientEmail}\r\nSubject: ${subject}\r\nMIME-Version: 1.0\r\nContent-Type: text/plain; charset=UTF-8\r\nContent-Transfer-Encoding: 8bit\r\n\r\n${text}`;
    const bytes = new TextEncoder().encode(mime);
    const raw = btoa(Array.from(bytes, byte => String.fromCharCode(byte)).join('')).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
    const sent = await fetchImpl('https://gmail.googleapis.com/gmail/v1/users/me/messages/send', { method: 'POST', redirect: 'manual',
      headers: { ...headers, 'content-type': 'application/json' }, body: JSON.stringify({ raw }) });
    if (sent.status !== 200) throw new Error('mail-delivery-unconfirmed');
    const result = await sent.json();
    if (typeof result.id !== 'string' || !result.id) throw new Error('mail-delivery-unconfirmed');
    return { delivered: true };
  };
}

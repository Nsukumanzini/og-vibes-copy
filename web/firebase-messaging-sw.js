importScripts('/firebase-config.js');
importScripts('https://www.gstatic.com/firebasejs/12.7.0/firebase-app-compat.js');
importScripts('https://www.gstatic.com/firebasejs/12.7.0/firebase-messaging-compat.js');

const config = self.OG_VIBES_FIREBASE_CONFIG;
const configured = config && !config.apiKey.startsWith('REPLACE_');

if (configured) {
  firebase.initializeApp(config);
  const messaging = firebase.messaging();

  messaging.onBackgroundMessage((payload) => {
    const data = payload.data || {};
    if (data.event === 'student_notification' && data.route) {
      return self.registration.showNotification(data.title || 'OG Vibes update', {
        body: data.body || 'You have a new update.',
        icon: '/icons/Icon-192.png',
        badge: '/icons/Icon-192.png',
        tag: `og-vibes-${data.notification_id || data.route}`,
        renotify: true,
        data
      });
    }
    if (data.event !== 'incoming_call' || !data.call_id) return;
    const video = data.call_type === 'video';
    const title = data.group_call === 'true'
      ? (video ? 'Incoming group video call' : 'Incoming group voice call')
      : (video ? 'Incoming video call' : 'Incoming voice call');
    return self.registration.showNotification(
      title,
      {
        body: data.caller_name || 'OG Vibes student',
        icon: '/icons/Icon-192.png',
        badge: '/icons/Icon-192.png',
        tag: `og-vibes-call-${data.call_id}`,
        renotify: true,
        requireInteraction: true,
        silent: false,
        data,
        actions: [
          { action: 'decline', title: 'Decline' },
          { action: 'accept', title: 'Accept' }
        ]
      }
    );
  });
}

self.addEventListener('notificationclick', (event) => {
  const data = event.notification.data || {};
  if (data.event === 'student_notification' && data.route) {
    event.notification.close();
    const target = `${self.location.origin}/?notificationRoute=${encodeURIComponent(data.route)}`
      + `&notificationEntity=${encodeURIComponent(data.entity_id || '')}`;
    event.waitUntil(
      clients.matchAll({ type: 'window', includeUncontrolled: true }).then((windows) => {
        const existing = windows[0];
        if (existing) {
          existing.navigate(target);
          return existing.focus();
        }
        return clients.openWindow(target);
      })
    );
    return;
  }
  const invitationId = data.invitation_id;
  if (data.event === 'module_invitation' && invitationId) {
    event.notification.close();
    const target = `${self.location.origin}/?moduleInvite=${encodeURIComponent(invitationId)}`;
    event.waitUntil(
      clients.matchAll({ type: 'window', includeUncontrolled: true }).then((windows) => {
        const existing = windows[0];
        if (existing) {
          existing.navigate(target);
          return existing.focus();
        }
        return clients.openWindow(target);
      })
    );
    return;
  }
  const callId = data.call_id;
  if (!callId) return;
  event.notification.close();
  const action = event.action === 'accept' || event.action === 'decline'
    ? event.action
    : 'open';
  const callParameter = data.group_call === 'true' ? 'groupCallId' : 'callId';
  const target = `${self.location.origin}/?${callParameter}=${encodeURIComponent(callId)}&callAction=${action}`;
  event.waitUntil(
    clients.matchAll({ type: 'window', includeUncontrolled: true }).then((windows) => {
      const existing = windows[0];
      if (existing) {
        existing.navigate(target);
        return existing.focus();
      }
      return clients.openWindow(target);
    })
  );
});

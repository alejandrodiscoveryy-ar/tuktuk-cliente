// Scoped strictly to /cliente/tuk/, independent from TUKTUK Conductor's worker.
importScripts('https://www.gstatic.com/firebasejs/12.17.0/firebase-app-compat.js');
importScripts('https://www.gstatic.com/firebasejs/12.17.0/firebase-messaging-compat.js');

firebase.initializeApp({
  apiKey: 'AIzaSyAVDRuwMJZStQGCqHRGMuoNydCbG3JeUIo',
  authDomain: 'tuktuk-control-9e74c.firebaseapp.com',
  projectId: 'tuktuk-control-9e74c',
  storageBucket: 'tuktuk-control-9e74c.firebasestorage.app',
  messagingSenderId: '835856456604',
  appId: '1:835856456604:web:f9ce95c62e04f050fec659'
});

const messaging = firebase.messaging();

messaging.onBackgroundMessage((payload) => {
  if (payload.data?.kind !== 'customer_exchange_rate_update') return;
  const title = payload.data.title || 'elTOQUE · TUKTUK Cliente';
  const body = payload.data.body || 'La tasa de cambio ha variado.';
  self.registration.showNotification(title, {
    body,
    tag: `eltoque-rate-${payload.data.rate_history_id || 'recent'}`,
    icon: 'icons/Icon-192.png',
    data: { kind: 'customer_exchange_rate_update' }
  });
});

self.addEventListener('notificationclick', (event) => {
  if (event.notification.data?.kind !== 'customer_exchange_rate_update') return;
  event.notification.close();
  event.waitUntil((async () => {
    const pages = await clients.matchAll({ type: 'window', includeUncontrolled: true });
    for (const page of pages) {
      if (page.url.startsWith(self.registration.scope)) {
        await page.focus();
        return;
      }
    }
    await clients.openWindow(self.registration.scope);
  })());
});

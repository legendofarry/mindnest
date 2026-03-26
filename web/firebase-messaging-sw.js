/* eslint-disable no-undef */
importScripts(
  'https://www.gstatic.com/firebasejs/10.13.2/firebase-app-compat.js'
);
importScripts(
  'https://www.gstatic.com/firebasejs/10.13.2/firebase-messaging-compat.js'
);

firebase.initializeApp({
  apiKey: 'AIzaSyA6f1SvmxQljip0KkGeAvbNz2wC9gCThtc',
  authDomain: 'mindnest-45772.firebaseapp.com',
  projectId: 'mindnest-45772',
  storageBucket: 'mindnest-45772.firebasestorage.app',
  messagingSenderId: '853014272041',
  appId: '1:853014272041:web:02d41914790c2a056ce438',
});

const messaging = firebase.messaging();

messaging.onBackgroundMessage((payload) => {
  const title =
    payload?.notification?.title || payload?.data?.title || 'MindNest';
  const body =
    payload?.notification?.body ||
    payload?.data?.body ||
    'You have a new update.';

  self.registration.showNotification(title, {
    body,
    icon: '/icons/Icon-192.png',
    badge: '/icons/Icon-192.png',
    data: {
      ...payload?.data,
      clickUrl: payload?.data?.clickUrl || '/#/notifications',
    },
    vibrate: [200, 100, 200],
  });
});

self.addEventListener('notificationclick', (event) => {
  event.notification.close();
  const clickUrl = event?.notification?.data?.clickUrl || '/#/notifications';

  event.waitUntil(
    clients.matchAll({ type: 'window', includeUncontrolled: true }).then(
      (clientList) => {
        for (const client of clientList) {
          if ('focus' in client) {
            client.navigate(clickUrl);
            return client.focus();
          }
        }
        if (clients.openWindow) {
          return clients.openWindow(clickUrl);
        }
        return undefined;
      }
    )
  );
});

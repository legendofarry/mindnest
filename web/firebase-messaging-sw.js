/* eslint-disable no-undef */
importScripts(
  'https://www.gstatic.com/firebasejs/10.13.2/firebase-app-compat.js'
);
importScripts(
  'https://www.gstatic.com/firebasejs/10.13.2/firebase-messaging-compat.js'
);

firebase.initializeApp({
  apiKey: 'AIzaSyDcam7IEdnmJnfAYDl6sriE0mXr_IJMBys',
  authDomain: 'mindnest-923fb.firebaseapp.com',
  projectId: 'mindnest-923fb',
  storageBucket: 'mindnest-923fb.firebasestorage.app',
  messagingSenderId: '253632223556',
  appId: '1:253632223556:web:4d4d0039f0c223fe56df11',
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

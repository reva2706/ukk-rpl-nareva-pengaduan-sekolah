importScripts('https://www.gstatic.com/firebasejs/10.7.0/firebase-app-compat.js');
importScripts('https://www.gstatic.com/firebasejs/10.7.0/firebase-messaging-compat.js');

firebase.initializeApp({
  apiKey: "YOUR_FIREBASE_WEB_API_KEY",
  authDomain: "pengaduansekolah-eb875.firebaseapp.com",
  projectId: "pengaduansekolah-eb875",
  storageBucket: "pengaduansekolah-eb875.firebasestorage.app",
  messagingSenderId: "265155033945",
  appId: "1:265155033945:web:87b10e00993670c2922a48",
  measurementId: "G-WN6RZCQHEL"
});

const messaging = firebase.messaging();

messaging.onBackgroundMessage(function(payload) {
  console.log('[firebase-messaging-sw.js] Received background message ', payload);
  const notificationTitle = payload.notification.title;
  const notificationOptions = {
    body: payload.notification.body,
    icon: '/icons/Icon-192.png'
  };

  self.registration.showNotification(notificationTitle, notificationOptions);
});

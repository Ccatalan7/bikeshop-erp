importScripts("https://www.gstatic.com/firebasejs/9.22.0/firebase-app-compat.js");
importScripts("https://www.gstatic.com/firebasejs/9.22.0/firebase-messaging-compat.js");

firebase.initializeApp({
    apiKey: "AIzaSyCu00oqAuIPBLlBBHziNCKMMrgPy7u6wQ4",
    authDomain: "project-vinabike.firebaseapp.com",
    projectId: "project-vinabike",
    storageBucket: "project-vinabike.firebasestorage.app",
    messagingSenderId: "452996097799",
    appId: "1:452996097799:web:6af010266020d8ee7e47a2"
});

const messaging = firebase.messaging();

messaging.onBackgroundMessage((payload) => {
    console.log('[firebase-messaging-sw.js] Received background message ', payload);
    // Customize notification here if needed
    const notificationTitle = payload.notification.title;
    const notificationOptions = {
        body: payload.notification.body,
        icon: '/icons/icon-192.png'
    };

    self.registration.showNotification(notificationTitle, notificationOptions);
});

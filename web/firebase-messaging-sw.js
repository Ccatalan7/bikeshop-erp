// Firebase Messaging Service Worker
// Handles background push notifications for web

importScripts('https://www.gstatic.com/firebasejs/10.7.0/firebase-app-compat.js');
importScripts('https://www.gstatic.com/firebasejs/10.7.0/firebase-messaging-compat.js');

// Initialize Firebase with web config
firebase.initializeApp({
    apiKey: 'AIzaSyCu00oqAuIPBLlBBHziNCKMMrgPy7u6wQ4',
    authDomain: 'project-vinabike.firebaseapp.com',
    projectId: 'project-vinabike',
    storageBucket: 'project-vinabike.firebasestorage.app',
    messagingSenderId: '452996097799',
    appId: '1:452996097799:web:6af010266020d8ee7e47a2'
});

const messaging = firebase.messaging();

// Handle background messages (when app is not in foreground)
// NOTE: FCM handles notification display via webpush.notification config
// We only log here for debugging - DO NOT call showNotification (causes duplicates)
messaging.onBackgroundMessage((payload) => {
    console.log('[FCM SW] Background message received:', payload);
    // FCM automatically shows notification via webpush.notification config
    // No need to call showNotification here
});

// Handle notification click - deep link to specific chat
self.addEventListener('notificationclick', (event) => {
    console.log('[FCM SW] Notification clicked:', event.notification.data);
    event.notification.close();

    const conversationId = event.notification.data?.conversation_id;
    const targetUrl = conversationId
        ? `/chat?conversation=${conversationId}`
        : '/chat';

    event.waitUntil(
        clients.matchAll({ type: 'window', includeUncontrolled: true }).then((clientList) => {
            // Try to focus an existing window
            for (const client of clientList) {
                if ('focus' in client) {
                    return client.focus().then(() => {
                        // Navigate to the chat after focusing
                        return client.navigate(targetUrl);
                    });
                }
            }
            // No existing window, open a new one
            return clients.openWindow(targetUrl);
        })
    );
});

console.log('[FCM SW] Firebase Messaging Service Worker loaded');

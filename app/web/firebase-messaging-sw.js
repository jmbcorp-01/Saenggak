// Shows push alerts while the web app is closed. firebase-config.js is
// written by the deploy; without Firebase set up it holds null and this
// worker does nothing.
try {
  importScripts('/firebase-config.js');
} catch (e) {
  self.FIREBASE_CONFIG = null;
}
if (self.FIREBASE_CONFIG) {
  importScripts(
    'https://www.gstatic.com/firebasejs/13.3.0/firebase-app-compat.js',
    'https://www.gstatic.com/firebasejs/13.3.0/firebase-messaging-compat.js',
  );
  firebase.initializeApp(self.FIREBASE_CONFIG);
  // Alerts with a notification part are shown by Firebase itself, and a tap
  // opens the link the server set (a post, or the notifications tab).
  firebase.messaging();
}

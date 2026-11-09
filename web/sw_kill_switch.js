// Published as flutter_service_worker.js by tool/build_web.ps1.
//
// The app no longer uses a service worker, but browsers that visited an
// older version still have one that serves stale cached files (e.g. an old
// icon font with blank icons) and even a stale index.html. Browsers re-check
// this file on every visit; this version takes over immediately, deletes
// every cache, removes itself and reloads open pages from the server.
self.addEventListener('install', function () {
  self.skipWaiting();
});

self.addEventListener('activate', function (event) {
  event.waitUntil((async function () {
    const keys = await caches.keys();
    await Promise.all(keys.map(function (k) { return caches.delete(k); }));
    await self.registration.unregister();
    const windows = await self.clients.matchAll({ type: 'window' });
    for (const w of windows) {
      try { await w.navigate(w.url); } catch (e) { /* ignore */ }
    }
  })());
});
// No fetch handler: every request goes to the network.

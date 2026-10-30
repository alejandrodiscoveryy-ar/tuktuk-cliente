'use strict';
// Cachea solo HTML/JS publicos de Lite. Configuracion de Admin NO se guarda aqui.
const CACHE = 'tuktuk-lite-static-v1';
const SCOPE = new URL(self.registration.scope);
const SHELL = [new URL('./', SCOPE).href, new URL('lite.js', SCOPE).href];
self.addEventListener('install', event => {
  event.waitUntil((async () => {
    const cache = await caches.open(CACHE);
    await Promise.all(SHELL.map(async url => {
      try {
        const response = await fetch(url, { cache: 'no-cache' });
        if (response.ok && response.type === 'basic') await cache.put(url, response);
      } catch (_) { /* La falta de red no bloquea la instalacion. */ }
    }));
    await self.skipWaiting();
  })());
});
self.addEventListener('activate', event => {
  event.waitUntil((async () => {
    const keys = await caches.keys();
    await Promise.all(keys.filter(k => k.startsWith('tuktuk-lite-static-') && k !== CACHE)
      .map(k => caches.delete(k)));
    await self.clients.claim();
  })());
});
async function networkFirst(request, key) {
  const cache = await caches.open(CACHE);
  const cached = await cache.match(key);
  const controller = cached ? new AbortController() : null;
  const timeout = controller ? setTimeout(() => controller.abort(), 3000) : null;
  try {
    const fresh = controller
      ? await fetch(request, { signal: controller.signal })
      : await fetch(request);
    if (fresh.ok && fresh.type === 'basic') await cache.put(key, fresh.clone());
    return fresh;
  } catch (error) {
    if (cached) return cached;
    throw error;
  } finally {
    if (timeout !== null) clearTimeout(timeout);
  }
}
self.addEventListener('fetch', event => {
  const request = event.request;
  if (request.method !== 'GET' || request.headers.has('authorization')) return;
  const url = new URL(request.url);
  if (url.origin !== SCOPE.origin || !url.pathname.startsWith(SCOPE.pathname)) return;
  const relative = url.pathname.slice(SCOPE.pathname.length);
  if (request.mode === 'navigate' && (relative === '' || relative === 'index.html')) {
    event.respondWith(networkFirst(request, SHELL[0]));
  } else if (relative === 'lite.js' && !url.search) {
    event.respondWith(networkFirst(request, SHELL[1]));
  }
});

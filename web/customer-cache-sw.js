// Lightweight, scoped static shell cache for /cliente/tuk/ only.
// Never cache network APIs, sessions, requests, prices, private media or Mapbox traffic.
const TUKTUK_CACHE_PREFIX = 'tuktuk-cliente-static-';
const TUKTUK_CACHE_NAME = TUKTUK_CACHE_PREFIX + '__TUKTUK_RELEASE__';
const TUKTUK_SCOPE = new URL(self.registration.scope);
const TUKTUK_SHELL = [
  '', 'index.html', 'main.dart.js',
  'manifest.json', 'favicon.png', 'icons/Icon-192.png',
];
const TUKTUK_REVALIDATE = /^(?:index\.html|flutter_bootstrap\.js|flutter\.js|main\.dart\.js|manifest\.json)$/;
const TUKTUK_STATIC = /^(?:favicon\.png|icons\/[^/]+\.png|assets\/|canvaskit\/)/;
const tuktukUrl = (name) => new URL(name, TUKTUK_SCOPE).href;

self.addEventListener('install', (event) => {
  event.waitUntil((async () => {
    const cache = await caches.open(TUKTUK_CACHE_NAME);
    // Reuse HTTP validators for the application shell. No map tiles or photos.
    await Promise.all(TUKTUK_SHELL.map(async (path) => {
      const url = tuktukUrl(path);
      try {
        const response = await fetch(url);
        if (response.ok && response.type === 'basic') await cache.put(url, response);
      } catch (_) {
        // Do not prevent the notification worker from installing on a weak link.
      }
    }));
  })());
});

self.addEventListener('activate', (event) => {
  event.waitUntil((async () => {
    const names = await caches.keys();
    await Promise.all(names.filter((name) =>
      name.startsWith(TUKTUK_CACHE_PREFIX) && name !== TUKTUK_CACHE_NAME
    ).map((name) => caches.delete(name)));
    await self.clients.claim();
  })());
});

// Prefer a fresh response. After three seconds, a previously cached PUBLIC
// shell is better than waiting indefinitely on a congested connection.
// CRITICAL: Never time out a first visit with no cached copy.
async function tuktukNetworkFirst(request, fallback) {
  const cache = await caches.open(TUKTUK_CACHE_NAME);
  const cacheKey = fallback || request;
  const cached = await cache.match(cacheKey);
  const controller = cached ? new AbortController() : null;
  const timeoutId = controller ? setTimeout(() => controller.abort(), 3000) : null;
  try {
    const response = controller
      ? await fetch(request, { signal: controller.signal })
      : await fetch(request);
    if (response.ok && response.type === 'basic') {
      await cache.put(cacheKey, response.clone());
    }
    return response;
  } catch (error) {
    if (cached) return cached;
    throw error;
  } finally {
    if (timeoutId !== null) clearTimeout(timeoutId);
  }
}
async function tuktukCacheFirst(request) {
  const cache = await caches.open(TUKTUK_CACHE_NAME);
  const hit = await cache.match(request);
  if (hit) return hit;
  const response = await fetch(request);
  if (response.ok && response.type === 'basic') {
    await cache.put(request, response.clone());
  }
  return response;
}

self.addEventListener('fetch', (event) => {
  const request = event.request;
  if (request.method !== 'GET' || request.headers.has('authorization')) return;
  const url = new URL(request.url);
  if (url.origin !== TUKTUK_SCOPE.origin || !url.pathname.startsWith(TUKTUK_SCOPE.pathname)) return;
  const relative = url.pathname.substring(TUKTUK_SCOPE.pathname.length);
  // A versioned public asset is safe, but arbitrary query keys could encode session data.
  if (url.search && !/^[?](?:v|version|release)=[A-Za-z0-9._-]+$/.test(url.search)) return;
  if (request.mode === 'navigate' && (relative === '' || relative === 'index.html')) {
    event.respondWith(tuktukNetworkFirst(request, tuktukUrl('')));
  } else if (TUKTUK_REVALIDATE.test(relative)) {
    event.respondWith(tuktukNetworkFirst(request));
  } else if (TUKTUK_STATIC.test(relative)) {
    event.respondWith(tuktukCacheFirst(request));
  }
});

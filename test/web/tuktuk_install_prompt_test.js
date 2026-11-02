'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const installer = require('../../web/install-prompt.js');
const mainHtml = fs.readFileSync('web/index.html', 'utf8');
const liteHtml = fs.readFileSync('web/lite/index.html', 'utf8');
const manifest = JSON.parse(fs.readFileSync('web/manifest.json', 'utf8'));

test('Android y iPhone identificados, incluido iPad moderno', () => {
  assert.equal(installer.platform('Mozilla/5.0 (Linux; Android 15)', 5), 'android');
  assert.equal(installer.platform('Mozilla/5.0 (iPhone; CPU iPhone OS)', 5), 'ios');
  assert.equal(installer.platform('Mozilla/5.0 (Macintosh; Intel Mac OS X)', 5), 'ios');
  assert.equal(installer.platform('Mozilla/5.0 (Windows NT 10.0)', 0), 'other');
});

test('cerrar invitacion respeta 21 dias y detecta sesiones futuras', () => {
  const now = Date.now();
  assert.equal(installer.cooldownActive(String(now - 1000), now), true);
  assert.equal(installer.cooldownActive(String(now - 22 * 86400000), now), false);
  assert.equal(installer.cooldownActive('invalido', now), false);
  assert.equal(installer.cooldownActive(String(now + 1000), now), false);
});

test('si esta instalada no invita de nuevo', () => {
  assert.equal(installer.installed({ navigator: { standalone: true } }), true);
  assert.equal(installer.installed({ navigator: { standalone: false }, matchMedia: () => ({ matches: true }) }), true);
  assert.equal(installer.installed({ navigator: { standalone: false }, matchMedia: () => ({ matches: false }) }), false);
});

test('manifiesto PWA estable, modo aplicacion y alcance exclusivo cliente', () => {
  assert.equal(manifest.id, '/cliente/tuk/');
  assert.equal(manifest.scope, '/cliente/tuk/');
  assert.equal(manifest.start_url, '/cliente/tuk/');
  assert.equal(manifest.display, 'standalone');
  assert.ok(manifest.icons.some(icon => icon.sizes === '192x192'));
  assert.ok(manifest.icons.some(icon => icon.sizes === '512x512'));
});

test('instalador compartido, tambien cuando el acceso redirige a Lite', () => {
  assert.match(mainHtml, /<script src="install-prompt\.js" defer><\/script>/);
  assert.match(liteHtml, /<script src="\.\.\/install-prompt\.js" defer><\/script>/);
  assert.match(liteHtml, /<link rel="manifest" href="\.\.\/manifest\.json">/);
  assert.match(mainHtml, /TUKTUK_UNIFIED_ENTRY_BEGIN/);
  assert.match(mainHtml, /flutter-first-frame/);
});

test('boton exige gesto; no hay instalacion automatica ni cambios a notificaciones', () => {
  const js = fs.readFileSync('web/install-prompt.js', 'utf8');
  assert.match(js, /beforeinstallprompt/);
  assert.match(js, /appinstalled/);
  assert.match(js, /event\.prompt\(\)/);
  assert.match(js, /addEventListener\('click'/);
  assert.match(js, /flutter-first-frame/);
  assert.match(js, /DOMContentLoaded/);
  assert.match(js, /Cerrar sugerencia de instalación/);
  assert.match(mainHtml, /firebase-messaging-sw\.js/);
  assert.doesNotMatch(js, /sendBeacon|fetch\(|geolocation|serviceWorker\.register|firebase/);
});

test('la oferta Android solo abre la instalacion tras tocar Instalar', async () => {
  const listeners = {};
  const queued = [];
  const clicks = {};
  const help = { hidden: true, textContent: '' };
  const action = { textContent: '', hidden: false, addEventListener(name, cb) { clicks['action:' + name] = cb; } };
  const close = { addEventListener(name, cb) { clicks['close:' + name] = cb; } };
  let bannerAdded = false;
  let removed = false;
  const banner = {
    id: '', innerHTML: '', setAttribute() {},
    querySelector(query) {
      return query.includes('close') ? close : query.includes('action') ? action : help;
    },
    remove() { removed = true; }
  };
  const doc = {
    readyState: 'complete',
    head: { appendChild() {} },
    body: { appendChild() { bannerAdded = true; } },
    createElement(tag) { return tag === 'aside' ? banner : { id: '', textContent: '' }; },
    getElementById() { return null; }
  };
  const win = {
    document: doc, navigator: { userAgent: 'Mozilla/5.0 Android 15 Chrome', maxTouchPoints: 5 },
    location: { pathname: '/cliente/tuk/' },
    localStorage: { getItem() { return null; }, setItem() {} },
    addEventListener(name, cb) { listeners[name] = cb; },
    setTimeout(cb) { queued.push(cb); },
    matchMedia() { return { matches: false }; }
  };
  win.top = win.self = win;
  installer.start(win);
  let prompts = 0;
  listeners.beforeinstallprompt({ preventDefault() {}, prompt() { prompts++; return Promise.resolve(); }, userChoice: Promise.resolve({ outcome: 'accepted' }) });
  assert.equal(prompts, 0);
  listeners['flutter-first-frame']();
  assert.equal(queued.length, 1);
  queued.shift()();
  assert.equal(bannerAdded, true);
  assert.equal(action.textContent, 'Instalar');
  clicks['action:click']();
  assert.equal(prompts, 1);
  await new Promise(resolve => setImmediate(resolve));
  assert.equal(removed, true);
});

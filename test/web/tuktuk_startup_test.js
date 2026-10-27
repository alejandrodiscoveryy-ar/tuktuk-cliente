'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const html = fs.readFileSync('web/index.html', 'utf8');
const found = html.match(/<!-- TUKTUK_STARTUP_SCRIPT_BEGIN -->\s*<script>([\s\S]*?)<\/script>\s*<!-- TUKTUK_STARTUP_SCRIPT_END -->/);

function setup() {
  assert.ok(found, 'El controlador de arranque debe existir');
  const events = {};
  const frames = [];
  const timers = [];
  let removed = false;
  let reloaded = false;
  const classes = new Set();
  const splash = {
    classList: { add(value) { classes.add(value); } },
    addEventListener(name, callback) { events[name] = callback; },
    remove() { removed = true; }
  };
  const message = { textContent: 'Iniciando la aplicacion...' };
  const retry = {
    hidden: true,
    addEventListener(name, callback) { events['retry:' + name] = callback; }
  };
  const elements = { 'tuktuk-startup': splash, 'tuktuk-startup-message': message, 'tuktuk-startup-retry': retry };
  const sandbox = {
    document: { getElementById(id) { return elements[id]; } },
    window: {
      addEventListener(name, callback) { events[name] = callback; },
      setTimeout(callback, milliseconds) { timers.push({ callback, milliseconds, cancelled: false }); return timers.length; },
      clearTimeout(id) { if (timers[id - 1]) timers[id - 1].cancelled = true; },
      requestAnimationFrame(callback) { frames.push(callback); },
      location: { reload() { reloaded = true; } }
    }
  };
  vm.runInNewContext(found[1], sandbox, { timeout: 1000 });
  return { events, frames, timers, classes, message, retry, get removed() { return removed; }, get reloaded() { return reloaded; } };
}

test('HTML dibuja un fondo oscuro y marca el inicio antes de bootstrap', () => {
  assert.match(html, /<link rel="preload" href="main\.dart\.js" as="script" fetchpriority="high">/);
  assert.match(html, /<script>\{\{flutter_bootstrap_js\}\}<\/script>/);
  assert.doesNotMatch(html, /<script src="flutter_bootstrap\.js" async><\/script>/);
  assert.match(html, /<meta name="viewport" content="width=device-width, initial-scale=1">/);
  assert.match(html, /class="tuktuk-startup-tuk-white">TUK<\/span>/);
  assert.match(html, /class="tuktuk-startup-tuk-gold">TUK<\/span>/);
  assert.match(html, /class="tuktuk-startup-slogan">TU CIUDAD TE MUEVE<\/div>/);
  assert.doesNotMatch(html, /class="tuktuk-startup-subtitle"/);
  assert.match(html, /<meta name="theme-color" content="#050B10">/);
  assert.match(html, /html, body \{[^}]*background:\s*#050B10/i);
  assert.match(html, /id="tuktuk-startup"/);
  assert.match(html, /src="icons\/Icon-192\.png"/);
  assert.ok(html.indexOf('TUKTUK_STARTUP_SCRIPT_BEGIN') < html.indexOf('<script>{{flutter_bootstrap_js}}</script>'));
  assert.match(html, /prefers-reduced-motion/);
});

test('No retira la pantalla hasta recibir el primer fotograma de Flutter', () => {
  const h = setup();
  assert.equal(h.removed, false);
  assert.equal(h.classes.has('tuktuk-startup-hidden'), false);
  assert.equal(typeof h.events['flutter-first-frame'], 'function');
  h.events['flutter-first-frame']();
  assert.equal(h.removed, false);
  assert.equal(h.frames.length, 1);
  h.frames.shift()();
  assert.equal(h.removed, false);
  h.frames.shift()();
  assert.equal(h.classes.has('tuktuk-startup-hidden'), true);
  assert.equal(h.removed, false);
  h.events.transitionend();
  assert.equal(h.removed, true);
  assert.equal(h.timers[0].cancelled, true);
});

test('Tras inicio lento ofrece reintentar sin ocultar la pantalla', () => {
  const h = setup();
  const slow = h.timers.find(t => t.milliseconds === 20000);
  assert.ok(slow);
  slow.callback();
  assert.equal(h.retry.hidden, false);
  assert.match(h.message.textContent, /conexion/);
  assert.equal(h.removed, false);
  h.events['retry:click']();
  assert.equal(h.reloaded, true);
});
test('Firebase se inicializa despues del primer fotograma sin perder las alertas', () => {
  const main = fs.readFileSync('lib/main.dart', 'utf8');
  const banner = fs.readFileSync('lib/presentation/customer_eltoque_banner.dart', 'utf8');
  const start = main.indexOf('Future<void> main() async {');
  const end = main.indexOf('\ndouble _marketNumber(');
  assert.ok(start >= 0 && end > start);
  const entrypoint = main.slice(start, end);
  assert.doesNotMatch(entrypoint, /await Firebase\.initializeApp/);
  assert.match(entrypoint, /await MarketplaceMapService\.loadPublicConfiguration/);
  assert.match(entrypoint, /addPostFrameCallback/);
  assert.match(entrypoint, /runApp\(MarketplaceCustomerApp/);
  assert.match(main, /customerFirebaseReady = ready\.future/);
  assert.match(main, /ready\.complete\(true\)/);
  assert.match(main, /ready\.complete\(false\)/);
  assert.match(banner, /final ready = await customerFirebaseReady/);
  assert.match(banner, /if \(_pushEnabled\) unawaited\(_pushClient\.refreshExisting\(\)\)/);
  assert.match(banner, /FirebaseMessaging\.onMessage\.listen/);
  assert.match(banner, /_pushBusy \|\| \(!_pushReady && !_pushEnabled\)/);
});

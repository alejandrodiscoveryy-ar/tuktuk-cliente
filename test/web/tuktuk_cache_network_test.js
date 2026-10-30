'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const source = fs.readFileSync('web/customer-cache-sw.js', 'utf8');

function runWorker(options = {}) {
  const handlers = {};
  const timers = [];
  const puts = [];
  const cached = options.cached ? { name: 'cached-shell' } : undefined;
  let resolveNetwork;
  let rejectNetwork;
  let fetchOptions;
  class FakeAbortController {
    constructor() {
      const listeners = [];
      this.signal = { addEventListener: (_name, callback) => listeners.push(callback) };
      this.abort = () => listeners.forEach(callback => callback());
    }
  }
  const cache = {
    async match() { return cached; },
    async put(key, value) { puts.push({ key, value }); }
  };
  const sandbox = {
    URL,
    AbortController: FakeAbortController,
    setTimeout(callback, milliseconds) {
      timers.push({ callback, milliseconds, cancelled: false });
      return timers.length;
    },
    clearTimeout(id) { if (timers[id - 1]) timers[id - 1].cancelled = true; },
    caches: { open: async () => cache, keys: async () => [] },
    fetch(_request, opts) {
      fetchOptions = opts;
      return new Promise((resolve, reject) => {
        resolveNetwork = resolve;
        rejectNetwork = reject;
        if (opts && opts.signal) {
          opts.signal.addEventListener('abort', () => reject(new Error('timed out')));
        }
      });
    },
    self: {
      registration: { scope: 'https://example.com/cliente/tuk/' },
      clients: { claim: async () => {} },
      addEventListener(name, callback) { handlers[name] = callback; }
    }
  };
  vm.createContext(sandbox);
  vm.runInContext(source, sandbox, { timeout: 1500 });
  return {
    run: vm.runInContext('tuktukNetworkFirst', sandbox),
    handlers,
    timers,
    puts,
    get fetchOptions() { return fetchOptions; },
    get resolveNetwork() { return resolveNetwork; },
    get rejectNetwork() { return rejectNetwork; }
  };
}
const nextTick = () => new Promise(resolve => setImmediate(resolve));

test('cache previo + red lenta: ofrece version publica guardada en 3 segundos', async () => {
  const h = runWorker({ cached: true });
  const result = h.run('https://example.com/cliente/tuk/main.dart.js');
  await nextTick();
  assert.equal(h.timers.length, 1);
  assert.equal(h.timers[0].milliseconds, 3000);
  h.timers[0].callback();
  assert.equal((await result).name, 'cached-shell');
  assert.equal(h.puts.length, 0);
});

test('cache previo + red rapida: usa red actual y actualiza cache', async () => {
  const h = runWorker({ cached: true });
  const result = h.run('https://example.com/cliente/tuk/main.dart.js');
  await nextTick();
  const response = { ok: true, type: 'basic', clone() { return this; }, name: 'fresh' };
  h.resolveNetwork(response);
  assert.equal((await result).name, 'fresh');
  assert.equal(h.puts.length, 1);
  assert.equal(h.timers[0].cancelled, true);
});

test('primera visita sin cache: NO interrumpe conexion lenta a los 3 s', async () => {
  const h = runWorker({ cached: false });
  const result = h.run('https://example.com/cliente/tuk/main.dart.js');
  await nextTick();
  assert.equal(h.timers.length, 0);
  const response = { ok: true, type: 'basic', clone() { return this; }, name: 'first-online' };
  h.resolveNetwork(response);
  assert.equal((await result).name, 'first-online');
  assert.equal(h.puts.length, 1);
});

test('red fallida y sin copia: nunca finge disponibilidad', async () => {
  const h = runWorker({ cached: false });
  const result = h.run('https://example.com/cliente/tuk/main.dart.js');
  await nextTick();
  h.rejectNetwork(new Error('offline'));
  await assert.rejects(result, /offline/);
});

test('solicitudes privadas, POST y otras webs no son interceptadas', () => {
  const h = runWorker();
  let intercepted = 0;
  const event = (url, method, authorized) => ({
    request: {
      method,
      url,
      headers: { has(key) { return key === 'authorization' && authorized; } },
      mode: 'navigate'
    },
    respondWith() { intercepted += 1; }
  });
  h.handlers.fetch(event('https://example.com/cliente/tuk/', 'POST', false));
  h.handlers.fetch(event('https://example.com/cliente/tuk/', 'GET', true));
  h.handlers.fetch(event('https://other.example/cliente/tuk/', 'GET', false));
  h.handlers.fetch(event('https://example.com/cliente/tuk/api/request', 'GET', false));
  assert.equal(intercepted, 0);
});
'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const html = fs.readFileSync('web/lite/index.html', 'utf8');
const js = fs.readFileSync('web/lite/lite.js', 'utf8');

test('Lite muestra primero solo el recorrido y deja el contacto para el segundo paso', () => {
  const first = html.match(/<section id="lite-step-route"[\s\S]*?<\/section>/);
  const second = html.match(/<section id="lite-step-contact"[^>]*hidden>[\s\S]*?<\/section>/);
  assert.ok(first);
  assert.ok(second);
  for (const name of ['service','origin','destination']) assert.match(first[0], new RegExp('name="' + name + '"'));
  assert.doesNotMatch(first[0], /name="(?:phone|name|notes)"/);
  for (const name of ['name','phone','notes']) assert.match(second[0], new RegExp('name="' + name + '"'));
  assert.match(html, /id="lite-next"/);
  assert.match(html, /id="lite-back"/);
  assert.match(js, /next\.addEventListener\('click'/);
  assert.match(js, /back\.addEventListener\('click'/);
  assert.match(js, /validateRoute\(readForm\(\)\)/);
});

test('Un solo botón principal por etapa; el enlace a Completa es discreto', () => {
  assert.match(html, /id="lite-send" disabled/);
  assert.match(html, /href="\.\.\/\?mode=full"/);
  assert.match(html, /id="lite-retry" type="button" hidden/);
  assert.match(html, /<details><summary>Agregar indicaciones/);
  assert.match(html, /id="lite-consent" type="checkbox" required/);
  assert.doesNotMatch(html, /Alternativa para conexiones lentas|que TukTuk Admin ya tiene|Comprobar operador|Usar aplicación completa/);
});

test('Se conserva verificación actual antes de abrir WhatsApp y sin crear carreras', () => {
  assert.match(js, /const number = await verify\(false\);/);
  assert.match(js, /root\.location\.assign\(whatsappUrl\(number, fields\)\)/);
  assert.match(js, /fetchCurrentSupport/);
  assert.doesNotMatch(js, /create_marketplace_customer_request|publish_marketplace_customer_job|create_request/);
  assert.doesNotMatch(html, /main\.dart\.js|flutter_bootstrap|firebase|mapbox/i);
});

test('recorrido y contacto se muestran en secuencia y el número se revalida al enviar', async () => {
  const vm = require('node:vm');
  const handlers = {};
  const make = (id, hidden = false) => ({
    hidden,
    textContent: '',
    checked: false,
    classList: { toggle() {} },
    addEventListener(type, cb) { handlers[id + ':' + type] = cb; }
  });
  const elements = {
    'lite-form': make('form'), 'lite-status': make('status'),
    'lite-send': make('send'), 'lite-consent': make('consent'),
    'lite-retry': make('retry', true), 'lite-next': make('next'),
    'lite-back': make('back'), 'lite-step-route': make('route'),
    'lite-step-contact': make('contact', true),
    'lite-feedback': make('feedback', true)
  };
  const fields = { service: 'Moto', origin: '', destination: '', name: '', phone: '', notes: '' };
  const projectId = 'dfb41cea-a812-46f2-b511-7a60bd3d78af';
  let supportReads = 0;
  let launched = '';
  elements['lite-form'].elements = { namedItem: () => ({ focus() {} }) };
  const win = {
    navigator: { connection: { effectiveType: '2g', downlink: 0.5 } },
    location: { search: '?preview=1', replace() { throw new Error('unexpected redirect'); }, assign(url) { launched = url; } },
    scrollTo() {},
    fetch: async (url) => {
      let result;
      if (url === './config.json') {
        result = { projectId, supabaseUrl: 'https://test-project.supabase.co', supabasePublishableKey: 'sb_publishable_test_123' };
      } else {
        supportReads++;
        result = { project_id: projectId, support: { enabled: true, number: '+5355555555' } };
      }
      return { ok: true, headers: { get: () => 'application/json' }, json: async () => result };
    }
  };
  const sandbox = {
    window: win,
    document: { getElementById: id => elements[id] },
    URL, URLSearchParams, AbortController, setTimeout, clearTimeout,
    FormData: class { constructor() {} entries() { return Object.entries(fields)[Symbol.iterator](); } }
  };
  vm.runInNewContext(js, sandbox, { timeout: 1500 });
  await new Promise(resolve => setImmediate(resolve));
  assert.equal(elements['lite-step-route'].hidden, false);
  assert.equal(elements['lite-step-contact'].hidden, true);
  handlers['next:click']();
  assert.equal(elements['lite-step-contact'].hidden, true, 'un recorrido vacío no avanza');
  fields.origin = 'Calle 10 y 15';
  fields.destination = 'Hospital central';
  handlers['next:click']();
  assert.equal(elements['lite-step-route'].hidden, true);
  assert.equal(elements['lite-step-contact'].hidden, false);
  handlers['back:click']();
  assert.equal(elements['lite-step-route'].hidden, false);
  handlers['next:click']();
  fields.name = 'Ana Pérez';
  fields.phone = '+5350000000';
  elements['lite-consent'].checked = true;
  handlers['consent:change']();
  assert.equal(elements['lite-send'].disabled, false);
  await handlers['form:submit']({ preventDefault() {} });
  assert.equal(supportReads, 2, 'consulta inicial y nueva consulta antes de enviar');
  assert.match(launched, /^https:\/\/wa\.me\/5355555555\?text=/);
});

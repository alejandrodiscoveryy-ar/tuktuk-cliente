'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const html = fs.readFileSync('web/index.html', 'utf8');
const match = html.match(/<!-- TUKTUK_UNIFIED_ENTRY_BEGIN -->\s*<script>([\s\S]*?)<\/script>\s*<!-- TUKTUK_UNIFIED_ENTRY_END -->/);
function run(search, connection) {
  assert.ok(match, 'Falta router unificado');
  const redirects = [];
  const preloads = [];
  const sandbox = {
    URL, URLSearchParams,
    window: { location: { search, replace(url) { redirects.push(url); } } },
    navigator: connection ? { connection } : {},
    document: {
      baseURI: 'http://127.0.0.1:8765/',
      createElement(tag) { assert.equal(tag, 'link'); return {setAttribute(k,v) { this[k]=v; }}; },
      head: { appendChild(x) { preloads.push(x); } }
    }
  };
  vm.runInNewContext(match[1], sandbox, { timeout: 1000 });
  return { redirects, preloads };
}
test('entrada comun: conexion buena mantiene Cliente completo', () => {
  const v = run('', { effectiveType:'4g', downlink:10, rtt:80 });
  assert.equal(v.redirects.length, 0);
  assert.equal(v.preloads.length, 1);
  assert.equal(v.preloads[0].href, 'main.dart.js');
});
test('entrada comun: red lenta entra a Lite antes de precargar Flutter', () => {
  const v = run('', { effectiveType:'3g', downlink:0.8, rtt:900 });
  assert.deepEqual(v.redirects, ['http://127.0.0.1:8765/lite/']);
  assert.equal(v.preloads.length, 0);
});
test('sin API de red, conserva Cliente completo por seguridad', () => {
  const v = run('', null);
  assert.equal(v.redirects.length, 0);
  assert.equal(v.preloads.length, 1);
});
test('regresar de Lite sin operador NO entra en bucle', () => {
  const v = run('?lite=unavailable', { effectiveType:'2g', downlink:0.3 });
  assert.equal(v.redirects.length, 0);
  assert.equal(v.preloads.length, 1);
});
test('elegir Completa desde Lite no entra en bucle', () => {
  const v = run('?mode=full', { effectiveType:'2g', downlink:0.3 });
  assert.equal(v.redirects.length, 0);
  assert.equal(v.preloads.length, 1);
});
test('prueba manual de Lite conserva una sola URL de entrada', () => {
  const v = run('?preview=lite', { effectiveType:'4g', downlink:10 });
  assert.deepEqual(v.redirects, ['http://127.0.0.1:8765/lite/?preview=1']);
  assert.equal(v.preloads.length, 0);
});
test('Lite nunca se combina con la carga de Flutter en el arranque', () => {
  assert.ok(html.indexOf('TUKTUK_UNIFIED_ENTRY_BEGIN') < html.indexOf('{{flutter_bootstrap_js}}'));
  assert.doesNotMatch(html, /id="tuktuk-lite-entry"/);
  assert.doesNotMatch(html, /<link rel="preload" href="main\.dart\.js"/);
  const lite = fs.readFileSync('web/lite/lite.js','utf8');
  assert.match(lite, /root\.location\.replace\('\.\.\/\?mode=full'\)/);
  assert.match(lite, /\?lite=unavailable/);
});
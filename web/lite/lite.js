'use strict';
// TukTuk Lite: sin Flutter, Firebase, Mapbox ni creacion automatica de carreras.
// El numero se resuelve EN VIVO mediante la RPC publica ya existente en Admin.
(function (root) {
  const E164 = /^\+[1-9][0-9]{7,14}$/;
  const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
  const TIMEOUT_MS = 7500;
  const ALLOWED_SERVICES = new Set(['Moto', 'Auto', 'Bicitaxi', 'Triciclo', 'Mensajería', 'Carga']);

  function slowNetwork(connection) {
    if (!connection) return false;
    return connection.saveData === true ||
      connection.effectiveType === 'slow-2g' || connection.effectiveType === '2g' ||
      (typeof connection.downlink === 'number' && connection.downlink > 0 && connection.downlink <= 1.5) ||
      (typeof connection.rtt === 'number' && connection.rtt >= 700);
  }

  function validateForm(fields) {
    const name = String(fields.name || '').trim();
    const phone = String(fields.phone || '').trim();
    const origin = String(fields.origin || '').trim();
    const destination = String(fields.destination || '').trim();
    const service = String(fields.service || '');
    const notes = String(fields.notes || '').trim();
    if (name.length < 2 || name.length > 100) return 'Escribe un nombre válido (2 a 100 caracteres).';
    if (!/^\+?[0-9 ()-]{8,22}$/.test(phone)) return 'Escribe un teléfono de contacto válido.';
    if (!ALLOWED_SERVICES.has(service)) return 'Selecciona un servicio.';
    if (origin.length < 4 || origin.length > 240) return 'Indica un origen reconocible.';
    if (destination.length < 4 || destination.length > 240) return 'Indica un destino reconocible.';
    if (notes.length > 500) return 'Las indicaciones deben tener 500 caracteres o menos.';
    return null;
  }

  function messageFor(fields) {
    return [
      'TUKTUK CLIENTE LITE - SOLICITUD POR WHATSAPP',
      'Servicio: ' + String(fields.service).trim(),
      'Cliente: ' + String(fields.name).trim(),
      'Contacto: ' + String(fields.phone).trim(),
      'Origen: ' + String(fields.origin).trim(),
      'Destino: ' + String(fields.destination).trim(),
      'Indicaciones: ' + (String(fields.notes || '').trim() || 'Sin indicaciones'),
      'Canal: WhatsApp Lite',
      'Solicitud pendiente de respuesta humana. No hay precio ni reserva confirmados.'
    ].join('\n');
  }

  function whatsappUrl(phone, fields) {
    if (!E164.test(phone)) throw new Error('INVALID_SUPPORT_NUMBER');
    const issue = validateForm(fields);
    if (issue) throw new Error(issue);
    return 'https://wa.me/' + phone.slice(1) + '?text=' + encodeURIComponent(messageFor(fields));
  }

  // SMS uses the same dynamic support number. The line must be able to receive SMS.
  function smsMessageFor(fields) {
    return [
      'TukTuk - Solicitud',
      'Servicio: ' + String(fields.service).trim(),
      'Origen: ' + String(fields.origin).trim(),
      'Destino: ' + String(fields.destination).trim(),
      'Nombre: ' + String(fields.name).trim(),
      'Tel: ' + String(fields.phone).trim(),
      String(fields.notes || '').trim() ? 'Nota: ' + String(fields.notes).trim() : '',
      'Pendiente de respuesta'
    ].filter(Boolean).join('\n');
  }
  function smsUrl(phone, fields, userAgent) {
    if (!E164.test(phone)) throw new Error('INVALID_SUPPORT_NUMBER');
    const issue = validateForm(fields);
    if (issue) throw new Error(issue);
    const separator = /iPad|iPhone|iPod/i.test(String(userAgent || '')) ? '&' : '?';
    return 'sms:' + phone + separator + 'body=' + encodeURIComponent(smsMessageFor(fields));
  }

  function parseConfig(cfg) {
    if (!cfg || typeof cfg !== 'object' || Array.isArray(cfg)) return null;
    if (!UUID.test(cfg.projectId) || typeof cfg.supabasePublishableKey !== 'string') return null;
    if (!(cfg.supabasePublishableKey.startsWith('sb_publishable_') || cfg.supabasePublishableKey.startsWith('eyJ'))) return null;
    try {
      const url = new URL(cfg.supabaseUrl);
      if (url.protocol !== 'https:' || url.username || url.password || url.search || url.hash ||
          !(url.hostname.endsWith('.supabase.co') || url.hostname.endsWith('.supabase.in'))) return null;
      return { supabaseUrl: url.origin, supabasePublishableKey: cfg.supabasePublishableKey, projectId: cfg.projectId };
    } catch (_) { return null; }
  }

  function currentSupportNumber(data, projectId) {
    if (!data || typeof data !== 'object' || Array.isArray(data)) return null;
    if (data.project_id !== projectId) return null;
    const support = data.support;
    if (!support || support.enabled !== true || typeof support.number !== 'string') return null;
    if (!E164.test(support.number)) return null;
    // payment.number NO determina disponibilidad de un operador; soporte manda.
    return support.number;
  }

  async function requestJson(fetchFn, url, options, timeoutMs = TIMEOUT_MS) {
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), timeoutMs);
    try {
      const response = await fetchFn(url, { ...options, signal: controller.signal });
      if (!response.ok) return null;
      const type = response.headers && response.headers.get('content-type');
      if (typeof type !== 'string' || !type.toLowerCase().includes('application/json')) return null;
      return await response.json();
    } catch (_) { return null; }
    finally { clearTimeout(timer); }
  }

  async function loadConfig(fetchFn) {
    const raw = await requestJson(fetchFn, './config.json', {
      method: 'GET', cache: 'no-store', credentials: 'omit', headers: { Accept: 'application/json' }
    });
    return parseConfig(raw);
  }

  async function fetchCurrentSupport(fetchFn, config) {
    if (!config) return null;
    const data = await requestJson(fetchFn,
      config.supabaseUrl + '/rest/v1/rpc/get_public_whatsapp_settings', {
        method: 'POST', cache: 'no-store', credentials: 'omit', redirect: 'error',
        headers: {
          apikey: config.supabasePublishableKey,
          'Content-Type': 'application/json',
          Accept: 'application/json'
        },
        body: JSON.stringify({ target_project_id: config.projectId })
      });
    return currentSupportNumber(data, config.projectId);
  }

  const core = { slowNetwork, validateForm, messageFor, whatsappUrl, smsMessageFor, smsUrl, parseConfig,
    currentSupportNumber, requestJson, loadConfig, fetchCurrentSupport };
  if (typeof module === 'object' && module.exports) module.exports = core;
  if (typeof document === 'undefined') return;

  const form = document.getElementById('lite-form');
  const status = document.getElementById('lite-status');
  const submit = document.getElementById('lite-send');
  const consent = document.getElementById('lite-consent');
  const retry = document.getElementById('lite-retry');
  const next = document.getElementById('lite-next');
  const back = document.getElementById('lite-back');
  const stepRoute = document.getElementById('lite-step-route');
  const stepContact = document.getElementById('lite-step-contact');
  const feedback = document.getElementById('lite-feedback');
  const smsButton = document.getElementById('lite-send-sms');
  const thanks = document.getElementById('lite-thanks');
  const another = document.getElementById('lite-another');
  const intro = document.getElementById('lite-intro');
  if (!form || !status || !submit || !consent || !retry || !smsButton ||
      !next || !back || !stepRoute || !stepContact || !feedback || !thanks || !another || !intro) return;
  const connection = root.navigator && (root.navigator.connection || root.navigator.mozConnection || root.navigator.webkitConnection);
  const params = new URLSearchParams(root.location.search);
  // Acceso directo con red claramente buena: se prioriza siempre la app completa.
  // La URL ?preview=1 permite pruebas manuales, sin afectar a usuarios normales.
  if (connection && !slowNetwork(connection) && params.get('preview') !== '1') {
    root.location.replace('../?mode=full');
    return;
  }

  let busy = false;
  let enabled = false;
  let config = null;
  let externalPending = false;
  let leftBrowser = false;
  const RETURN_KEY = 'tuktuk_lite_message_return_v1';
  function rememberExternal(left) {
    try { root.sessionStorage?.setItem(RETURN_KEY, JSON.stringify({ at: Date.now(), left })); } catch (_) {}
  }
  function clearExternal() {
    try { root.sessionStorage?.removeItem(RETURN_KEY); } catch (_) {}
  }
  function showThanks() {
    const title = document.getElementById('lite-heading');
    if (title) title.textContent = String.fromCharCode(161) + 'Hasta pronto!';
    externalPending = false;
    leftBrowser = false;
    clearExternal();
    form.hidden = true;
    status.hidden = true;
    retry.hidden = true;
    intro.hidden = true;
    thanks.hidden = false;
    if (typeof root.scrollTo === 'function') root.scrollTo(0, 0);
  }
  function markLeaving() {
    if (!externalPending) return;
    leftBrowser = true;
    rememberExternal(true);
  }
  function handleReturn() {
    if (externalPending && leftBrowser) { showThanks(); return; }
    try {
      const state = JSON.parse(root.sessionStorage?.getItem(RETURN_KEY) || 'null');
      if (state && state.left === true && Date.now() - state.at < 600000) showThanks();
    } catch (_) {}
  }
  // External apps do not disclose whether the message was actually sent.
  // The thank-you screen is only shown on return from another app.
  if (typeof root.addEventListener === 'function') {
    root.addEventListener('pagehide', markLeaving);
    root.addEventListener('pageshow', handleReturn);
  }
  if (typeof document.addEventListener === 'function') {
    document.addEventListener('visibilitychange', () => {
      if (document.visibilityState === 'hidden') markLeaving();
      if (document.visibilityState === 'visible') handleReturn();
    });
  }
  another.addEventListener('click', () => {
    const title = document.getElementById('lite-heading');
    if (title) title.textContent = String.fromCharCode(191) + 'A d' + String.fromCharCode(243) + 'nde vamos?';
    clearExternal();
    externalPending = false;
    leftBrowser = false;
    if (typeof form.reset === 'function') form.reset();
    consent.checked = false;
    thanks.hidden = true;
    form.hidden = false;
    status.hidden = false;
    intro.hidden = false;
    changeStep(false);
    enabled = false;
    render('Comprobando contacto...');
    void verify(false);
  });
  function render(message) {
    status.textContent = message;
    status.classList.toggle('is-ready', enabled);
    status.classList.toggle('is-unavailable', !busy && !enabled);
    retry.hidden = busy || enabled;
    submit.disabled = busy || !enabled || !consent.checked;
    smsButton.disabled = busy || !enabled || !consent.checked;
  }
  function readForm() { return Object.fromEntries(new FormData(form).entries()); }
  function showError(message) {
    feedback.textContent = message;
    feedback.hidden = false;
  }
  function clearError() {
    feedback.textContent = '';
    feedback.hidden = true;
  }
  function validateRoute(fields) {
    const service = String(fields.service || '');
    const origin = String(fields.origin || '').trim();
    const destination = String(fields.destination || '').trim();
    if (!ALLOWED_SERVICES.has(service)) return 'Selecciona un servicio.';
    if (origin.length < 4 || origin.length > 240) return 'Escribe dónde te recogemos.';
    if (destination.length < 4 || destination.length > 240) return 'Escribe a dónde vas.';
    return null;
  }
  function changeStep(contact) {
    stepRoute.hidden = contact;
    stepContact.hidden = !contact;
    clearError();
    if (typeof root.scrollTo === 'function') root.scrollTo(0, 0);
    if (contact) {
      const nameInput = form.elements.namedItem('name');
      if (nameInput && typeof nameInput.focus === 'function') nameInput.focus();
    }
  }
  next.addEventListener('click', () => {
    const issue = validateRoute(readForm());
    if (issue) { showError(issue); return; }
    changeStep(true);
  });
  back.addEventListener('click', () => changeStep(false));
  form.addEventListener('input', () => { if (!feedback.hidden) clearError(); });
  async function verify(initial) {
    if (busy) return null;
    busy = true;
    enabled = false;
    render('Comprobando canal de WhatsApp...');
    if (!config) config = await loadConfig(root.fetch.bind(root));
    const number = await fetchCurrentSupport(root.fetch.bind(root), config);
    busy = false;
    enabled = Boolean(number);
    render(enabled ? 'Mensajeria disponible' :
      'WhatsApp no disponible. Usa TukTuk completo.');
    // Si no hay canal verificable, el cliente vuelve al servicio automatico.
    // No se utiliza nunca un numero almacenado previamente.
    if (!number && initial) root.location.replace('../?lite=unavailable');
    return number;
  }
  consent.addEventListener('change', () => render(enabled ?
    'Mensajeria disponible. Elige WhatsApp o SMS.' :
    'WhatsApp no disponible. Usa TukTuk completo.'));
  async function openMessaging(channel) {
    if (busy || !consent.checked || !enabled) return;
    const fields = readForm();
    const issue = validateForm(fields);
    if (issue) { showError(issue); return; }
    // Recheck the configured number immediately before EVERY external launch.
    const number = await verify(false);
    if (!number) return;
    try {
      externalPending = true;
      leftBrowser = false;
      rememberExternal(false);
      if (channel === 'sms') {
        const userAgent = root.navigator && root.navigator.userAgent;
        root.location.assign(smsUrl(number, fields, userAgent));
      } else {
        root.location.assign(whatsappUrl(number, fields));
      }
      render('Confirma el envío en tu aplicación de mensajes.');
    } catch (_) {
      externalPending = false;
      clearExternal();
      showError('No se pudo abrir la aplicación de mensajes. Intenta de nuevo.');
    }
  }
  form.addEventListener('submit', async (event) => {
    event.preventDefault();
    await openMessaging('whatsapp');
  });
  smsButton.addEventListener('click', () => { void openMessaging('sms'); });
  retry.addEventListener('click', () => { void verify(false); });
  render('Comprobando WhatsApp...');
  void verify(true);
})(typeof window !== 'undefined' ? window : globalThis);

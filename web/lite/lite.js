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

  const core = { slowNetwork, validateForm, messageFor, whatsappUrl, parseConfig,
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
  if (!form || !status || !submit || !consent || !retry ||
      !next || !back || !stepRoute || !stepContact || !feedback) return;
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
  function render(message) {
    status.textContent = message;
    status.classList.toggle('is-ready', enabled);
    status.classList.toggle('is-unavailable', !busy && !enabled);
    retry.hidden = busy || enabled;
    submit.disabled = busy || !enabled || !consent.checked;
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
    render(enabled ? 'WhatsApp disponible' :
      'WhatsApp no disponible. Usa TukTuk completo.');
    // Si no hay canal verificable, el cliente vuelve al servicio automatico.
    // No se utiliza nunca un numero almacenado previamente.
    if (!number && initial) root.location.replace('../?lite=unavailable');
    return number;
  }
  consent.addEventListener('change', () => render(enabled ?
    'WhatsApp habilitado. Confirma el envío en WhatsApp.' :
    'WhatsApp no disponible. Usa TukTuk completo.'));
  form.addEventListener('submit', async (event) => {
    event.preventDefault();
    if (busy || !consent.checked || !enabled) return;
    const fields = readForm();
    const issue = validateForm(fields);
    if (issue) { showError(issue); return; }
    // Consulta de numero en vivo JUSTO ANTES de la apertura de WhatsApp.
    const number = await verify(false);
    if (!number) return; // Formulario intacto; el usuario puede reintentar.
    try {
      root.location.assign(whatsappUrl(number, fields));
      render('Se abrirá WhatsApp. Confirma el envío.');
    } catch (_) { render('No se pudo preparar el mensaje. Vuelve a intentarlo.'); }
  });
  retry.addEventListener('click', () => { void verify(false); });
  render('Comprobando WhatsApp...');
  void verify(true);
})(typeof window !== 'undefined' ? window : globalThis);

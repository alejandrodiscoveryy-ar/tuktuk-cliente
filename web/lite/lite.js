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

  // Proyecto publico: permite verificar la ultima configuracion si la red falla.
  // Solo se guarda el numero que una consulta RPC valida devolvio como activo.
  const PUBLIC_PROJECT_ID = 'dfb41cea-a812-46f2-b511-7a60bd3d78af';
  const SUPPORT_CACHE_KEY = 'tuktuk_lite_support_cache_v1';
  const SUPPORT_CACHE_TTL = 24 * 60 * 60 * 1000;
  function saveCachedSupport(storage, number, projectId, now = Date.now()) {
    if (!storage || !E164.test(number) || !UUID.test(projectId)) return false;
    try {
      storage.setItem(SUPPORT_CACHE_KEY, JSON.stringify({ number, projectId, checkedAt: now }));
      return true;
    } catch (_) { return false; }
  }
  function readCachedSupport(storage, projectId = PUBLIC_PROJECT_ID, now = Date.now()) {
    if (!storage) return null;
    try {
      const data = JSON.parse(storage.getItem(SUPPORT_CACHE_KEY) || 'null');
      if (!data || data.projectId !== projectId || !E164.test(data.number) ||
          !Number.isFinite(data.checkedAt) || data.checkedAt > now ||
          now - data.checkedAt > SUPPORT_CACHE_TTL) return null;
      return data.number;
    } catch (_) { return null; }
  }
  function clearCachedSupport(storage) {
    try { storage?.removeItem(SUPPORT_CACHE_KEY); } catch (_) {}
  }

  function cleanMessage(value) {
    return String(value || '').replace(/[\r\n\t]+/g, ' ').trim();
  }
  function originGps(fields) {
    const lat = fields.originLatitude;
    const lng = fields.originLongitude;
    if (typeof lat !== 'number' || typeof lng !== 'number' ||
        !Number.isFinite(lat) || !Number.isFinite(lng) ||
        lat < -90 || lat > 90 || lng < -180 || lng > 180) return null;
    const coords = lat.toFixed(6) + ',' + lng.toFixed(6);
    const accuracy = fields.originAccuracy;
    return { coords, url: 'https://maps.google.com/?q=' + coords,
      accuracy: Number.isFinite(accuracy) && accuracy >= 0 ? Math.round(accuracy) : null };
  }
  function addressMapSearch(address) {
    return 'https://www.google.com/maps/search/?api=1&query=' + encodeURIComponent(cleanMessage(address));
  }

  function messageFor(fields) {
    const gps = originGps(fields);
    const origin = cleanMessage(fields.origin);
    const destination = cleanMessage(fields.destination);
    return [
      '🚕 *TUKTUK | NUEVA SOLICITUD*',
      '',
      '🛵 *Servicio:* ' + cleanMessage(fields.service),
      '👤 *Cliente:* ' + cleanMessage(fields.name),
      '📞 *Contacto:* ' + cleanMessage(fields.phone),
      '',
      '📍 *RECOGIDA*',
      origin,
      gps ? '🧭 *GPS:* ' + gps.coords + (gps.accuracy === null ? '' : ' (precisión aprox. ' + gps.accuracy + ' m)') : '🧭 *GPS:* No proporcionado',
      gps ? '🗺️ *Abrir pin de recogida:* ' + gps.url : '🗺️ *Buscar origen (dirección, no pin):* ' + addressMapSearch(origin),
      '',
      '🏁 *DESTINO*',
      destination,
      '🗺️ *Buscar destino (dirección, no pin):* ' + addressMapSearch(destination),
      '',
      '📝 *Indicaciones:* ' + (cleanMessage(fields.notes) || 'Ninguna'),
      '📲 *Canal:* WhatsApp Lite',
      '⏳ *Estado:* Pendiente de respuesta humana.',
      '_No hay precio ni reserva confirmados._'
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
    const gps = originGps(fields);
    return [
      'TukTuk - Solicitud',
      'Servicio: ' + cleanMessage(fields.service),
      'Origen: ' + cleanMessage(fields.origin),
      gps ? 'GPS origen: ' + gps.coords + (gps.accuracy === null ? '' : ' +/-' + gps.accuracy + 'm') : '',
      gps ? 'Mapa origen: ' + gps.url : '',
      'Destino: ' + cleanMessage(fields.destination),
      'Buscar destino: ' + addressMapSearch(fields.destination),
      'Nombre: ' + cleanMessage(fields.name),
      'Tel: ' + cleanMessage(fields.phone),
      cleanMessage(fields.notes) ? 'Nota: ' + cleanMessage(fields.notes) : '',
      'Pendiente de respuesta, sin precio confirmado'
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

  async function fetchSupportState(fetchFn, config) {
    if (!config) return { status: 'unreachable' };
    const data = await requestJson(fetchFn,
      config.supabaseUrl + '/rest/v1/rpc/get_public_whatsapp_settings', {
        method: 'POST', cache: 'no-store', credentials: 'omit', redirect: 'error',
        headers: {
          apikey: config.supabasePublishableKey,
          'Content-Type': 'application/json', Accept: 'application/json'
        },
        body: JSON.stringify({ target_project_id: config.projectId })
      });
    if (!data) return { status: 'unreachable' };
    // Respuesta explicita de Admin: una desactivacion invalida la cache.
    const number = currentSupportNumber(data, config.projectId);
    return number ? { status: 'active', number } : { status: 'inactive' };
  }

  const core = { slowNetwork, validateForm, messageFor, whatsappUrl, smsMessageFor, smsUrl, parseConfig,
    currentSupportNumber, requestJson, loadConfig, fetchCurrentSupport, fetchSupportState,
    saveCachedSupport, readCachedSupport, clearCachedSupport, originGps, addressMapSearch };
  if (typeof module === 'object' && module.exports) module.exports = core;
  if (typeof document === 'undefined') return;

  const form = document.getElementById('lite-form');
  const status = document.getElementById('lite-status');
  const stepIndicator = document.getElementById('lite-step-indicator');
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
  const locate = document.getElementById('lite-locate');
  const geoStatus = document.getElementById('lite-geo-status');
  if (!form || !status || !submit || !consent || !retry || !smsButton ||
      !next || !back || !stepRoute || !stepContact || !feedback || !thanks || !another || !intro) return;
  const connection = root.navigator && (root.navigator.connection || root.navigator.mozConnection || root.navigator.webkitConnection);
  const params = new URLSearchParams(root.location.search);
  // Permite reabrir Lite desde la carcasa publica previamente cacheada.
  if (root.location.protocol === 'https:' && root.navigator && root.navigator.serviceWorker) {
    root.navigator.serviceWorker.register('./lite-sw.js', { scope: './' }).catch(() => {});
  }
  // Acceso directo con red claramente buena: se prioriza siempre la app completa.
  // La URL ?preview=1 permite pruebas manuales, sin afectar a usuarios normales.
  if (connection && !slowNetwork(connection) && params.get('preview') !== '1') {
    root.location.replace('../?mode=full');
    return;
  }

  let busy = false;
  let enabled = false;
  let config = null;
  let liveNumber = null;
  let cachedNumber = readCachedSupport(root.localStorage);
  let pickedOrigin = null;
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
    clearExternal();
    externalPending = false;
    leftBrowser = false;
    if (typeof form.reset === 'function') form.reset();
    consent.checked = false;
    pickedOrigin = null;
    if (geoStatus) geoStatus.hidden = true;
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
    const available = Boolean(liveNumber || cachedNumber);
    status.classList.toggle('is-ready', available);
    status.classList.toggle('is-unavailable', !busy && !available);
    retry.hidden = busy || Boolean(liveNumber);
    submit.disabled = busy || !liveNumber || !consent.checked;
    smsButton.disabled = busy || !available || !consent.checked;
  }
  function readForm() {
    const fields = Object.fromEntries(new FormData(form).entries());
    if (pickedOrigin) {
      fields.originLatitude = pickedOrigin.latitude;
      fields.originLongitude = pickedOrigin.longitude;
      fields.originAccuracy = pickedOrigin.accuracy;
    }
    return fields;
  }
  function showError(message) {
    feedback.textContent = message;
    feedback.hidden = false;
  }
  function clearError() {
    feedback.textContent = '';
    feedback.hidden = true;
  }
  // GPS nativo, opcional; no descarga mapas, no bloquea el formulario.
  const originField = form.elements.namedItem('origin');
  if (originField && typeof originField.addEventListener === 'function') {
    originField.addEventListener('input', () => {
      pickedOrigin = null;
      if (geoStatus) geoStatus.hidden = true;
    });
  }
  if (locate) locate.addEventListener('click', () => {
    const geolocation = root.navigator && root.navigator.geolocation;
    if (!geolocation || typeof geolocation.getCurrentPosition !== 'function') {
      if (geoStatus) {
        geoStatus.hidden = false;
        geoStatus.textContent = 'GPS no disponible. Escribe la dirección de recogida.';
      }
      return;
    }
    locate.disabled = true;
    if (geoStatus) {
      geoStatus.hidden = false;
      geoStatus.textContent = 'Buscando ubicación GPS...';
    }
    geolocation.getCurrentPosition(position => {
      locate.disabled = false;
      const coords = position && position.coords;
      const latitude = coords && coords.latitude;
      const longitude = coords && coords.longitude;
      const accuracy = coords && coords.accuracy;
      if (!Number.isFinite(latitude) || !Number.isFinite(longitude) ||
          latitude < -90 || latitude > 90 || longitude < -180 || longitude > 180) {
        if (geoStatus) geoStatus.textContent = 'No se obtuvo una posición válida. Escribe la dirección.';
        return;
      }
      pickedOrigin = { latitude, longitude, accuracy: Number.isFinite(accuracy) && accuracy >= 0 ? accuracy : null };
      if (originField) originField.value = 'Mi ubicación actual (GPS)';
      if (geoStatus) {
        const precision = pickedOrigin.accuracy === null ? '' : ' (precisión estimada: ' + Math.round(pickedOrigin.accuracy) + ' m)';
        geoStatus.textContent = 'Ubicación obtenida' + precision + '. Puedes corregir el origen escribiendo otra dirección.';
      }
      clearError();
    }, () => {
      locate.disabled = false;
      if (geoStatus) geoStatus.textContent = 'No se pudo obtener GPS. Puedes escribir la dirección manualmente.';
    }, { enableHighAccuracy: true, timeout: 12000, maximumAge: 0 });
  });

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
    if (stepIndicator) stepIndicator.textContent = contact ? 'Paso 2 de 2' : 'Paso 1 de 2';
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
    liveNumber = null;
    render('Comprobando contacto de soporte...');
    // navigator.onLine es orientativo; si indica offline evitamos esperar el timeout.
    const offline = root.navigator && root.navigator.onLine === false;
    if (!offline && !config) config = await loadConfig(root.fetch.bind(root));
    const info = offline ? { status: 'unreachable' } :
      await fetchSupportState(root.fetch.bind(root), config);
    busy = false;
    if (info.status === 'active') {
      liveNumber = info.number;
      cachedNumber = info.number;
      saveCachedSupport(root.localStorage, info.number, config.projectId);
      render('Servicio disponible');
    } else if (info.status === 'inactive') {
      liveNumber = null;
      cachedNumber = null;
      clearCachedSupport(root.localStorage);
      render('Contacto desactivado. Usa TukTuk completo.');
    } else {
      liveNumber = null;
      cachedNumber = readCachedSupport(root.localStorage,
        config ? config.projectId : PUBLIC_PROJECT_ID);
      render(cachedNumber ?
        'Servicio disponible' :
        'Contacto no disponible. Usa TukTuk completo.');
    }
    if (!liveNumber && !cachedNumber && initial) root.location.replace('../?lite=unavailable');
    return liveNumber;
  }
  consent.addEventListener('change', () => render(
    liveNumber || cachedNumber ? 'Servicio disponible' :
      'Contacto no disponible. Usa TukTuk completo.'));
  async function openMessaging(channel) {
    if (busy || !consent.checked ||
        (channel === 'sms' ? !liveNumber && !cachedNumber : !liveNumber)) return;
    const fields = readForm();
    const issue = validateForm(fields);
    if (issue) { showError(issue); return; }
    // Consultar siempre Admin si la red lo permite; desactivacion borra cache.
    const number = await verify(false);
    const target = channel === 'sms' ? (number || cachedNumber) : number;
    if (!target) {
      showError('No hay contacto válido para este canal. Comprueba la conexión.');
      return;
    }
    try {
      externalPending = true;
      leftBrowser = false;
      rememberExternal(false);
      if (channel === 'sms') {
        const userAgent = root.navigator && root.navigator.userAgent;
        root.location.assign(smsUrl(target, fields, userAgent));
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

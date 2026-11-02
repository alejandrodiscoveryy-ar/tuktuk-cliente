/* TUKTUK Cliente — instalacion voluntaria de la WebApp, sin APK ni dependencias. */
(function (root, factory) {
  'use strict';
  var installer = factory();
  if (typeof module === 'object' && module.exports) module.exports = installer;
  if (root && root.document && root.navigator) installer.start(root);
}(typeof window === 'undefined' ? null : window, function () {
  'use strict';
  var STORAGE_KEY = 'tuktuk-cliente-install-dismissed-v1';
  var COOLDOWN_MS = 21 * 24 * 60 * 60 * 1000;

  function platform(userAgent, maxTouchPoints) {
    var ua = String(userAgent || '');
    if (/iPad|iPhone|iPod/i.test(ua) || (/Macintosh/i.test(ua) && maxTouchPoints > 1)) return 'ios';
    if (/Android/i.test(ua)) return 'android';
    return 'other';
  }

  function cooldownActive(saved, now) {
    var timestamp = Number(saved);
    return Number.isFinite(timestamp) && timestamp > 0 && now >= timestamp && (now - timestamp) < COOLDOWN_MS;
  }

  function installed(win) {
    try {
      return Boolean(win.navigator.standalone ||
        (win.matchMedia && (win.matchMedia('(display-mode: standalone)').matches ||
          win.matchMedia('(display-mode: fullscreen)').matches)));
    } catch (_) { return false; }
  }

  function start(win) {
    var doc = win.document;
    if (win.__tuktukInstallPromptStarted || win.top !== win.self) return;
    win.__tuktukInstallPromptStarted = true;

    var kind = platform(win.navigator.userAgent, win.navigator.maxTouchPoints);
    var isLite = /\/lite\/?$/.test(win.location.pathname);
    var ready = false;
    var deferred = null;
    var banner = null;
    var scheduled = false;
    var blockedForSession = false;

    function readDismissed() {
      try { return win.localStorage.getItem(STORAGE_KEY); } catch (_) { return null; }
    }
    function remember() {
      try { win.localStorage.setItem(STORAGE_KEY, String(Date.now())); } catch (_) { /* Almacenamiento opcional. */ }
    }
    function allowed() {
      return ready && !blockedForSession && !installed(win) &&
        !cooldownActive(readDismissed(), Date.now()) &&
        (kind === 'ios' || kind === 'android' || deferred !== null);
    }
    function hide(rememberChoice) {
      if (rememberChoice) { blockedForSession = true; remember(); }
      if (banner) { banner.remove(); banner = null; }
    }
    function helpText() {
      if (kind === 'ios') {
        return 'En el navegador, toca Compartir y selecciona «Añadir a pantalla de inicio». Si no aparece, abre TUKTUK en Safari.';
      }
      return 'En Chrome, abre el menú ⋮ y selecciona «Instalar aplicación» o «Añadir a pantalla principal».';
    }
    function refreshButton() {
      if (!banner) return;
      var button = banner.querySelector('[data-tuktuk-install-action]');
      if (button) button.textContent = deferred ? 'Instalar' : 'Cómo instalar';
    }
    function render() {
      if (!allowed() || !doc.body || banner) return;
      var style = doc.getElementById('tuktuk-install-banner-style');
      if (!style) {
        style = doc.createElement('style');
        style.id = 'tuktuk-install-banner-style';
        style.textContent = '\n' +
          '#tuktuk-install-banner{position:fixed;z-index:2147483000;left:12px;right:12px;bottom:calc(12px + env(safe-area-inset-bottom));max-width:420px;margin:0 auto;background:#10232b;color:#f3f8f7;border:1px solid #416a66;border-radius:18px;box-shadow:0 12px 34px #0009;padding:13px 12px 13px 13px;font:14px/1.35 system-ui,-apple-system,Segoe UI,sans-serif;box-sizing:border-box}' +
          '#tuktuk-install-banner *{box-sizing:border-box}' +
          '#tuktuk-install-banner .tuk-install-main{display:flex;align-items:center;gap:10px}' +
          '#tuktuk-install-banner .tuk-install-icon{width:47px;height:47px;object-fit:contain;border-radius:12px;flex:none}' +
          '#tuktuk-install-banner .tuk-install-copy{flex:1;min-width:0}' +
          '#tuktuk-install-banner strong{font-size:14px;display:block;line-height:1.25}' +
          '#tuktuk-install-banner .tuk-install-description{display:block;color:#b8c8c9;font-size:12px;margin-top:3px}' +
          '#tuktuk-install-banner button{font:inherit;cursor:pointer}' +
          '#tuktuk-install-banner .tuk-install-action{background:#2dd4a3;border:0;border-radius:10px;color:#083025;font-weight:800;font-size:12px;padding:11px 12px;flex:none;min-height:41px}' +
          '#tuktuk-install-banner .tuk-install-close{position:absolute;right:4px;top:1px;border:0;background:transparent;color:#dce8e8;font-size:22px;padding:1px 7px;min-width:30px;min-height:30px}' +
          '#tuktuk-install-banner .tuk-install-help{margin:10px 0 0;color:#d2e4e1;font-size:12px;line-height:1.45}' +
          '#tuktuk-install-banner :focus-visible{outline:2px solid #e5a84e;outline-offset:2px}' +
          '@media(max-width:360px){#tuktuk-install-banner{padding:12px 9px}#tuktuk-install-banner .tuk-install-action{padding:9px 8px}#tuktuk-install-banner .tuk-install-icon{width:39px;height:39px}}';
        doc.head.appendChild(style);
      }
      banner = doc.createElement('aside');
      banner.id = 'tuktuk-install-banner';
      banner.setAttribute('role', 'region');
      banner.setAttribute('aria-label', 'Instalar TUKTUK Cliente');
      banner.innerHTML = '<button type="button" class="tuk-install-close" data-tuktuk-install-close aria-label="Cerrar sugerencia de instalación">×</button>' +
        '<div class="tuk-install-main"><img class="tuk-install-icon" alt="" src="' +
        (isLite ? '../icons/Icon-192.png' : 'icons/Icon-192.png') + '">' +
        '<div class="tuk-install-copy"><strong>Instala TUKTUK</strong>' +
        '<span class="tuk-install-description">Accede desde la pantalla de inicio, sin descargar APK.</span></div>' +
        '<button type="button" class="tuk-install-action" data-tuktuk-install-action>Cómo instalar</button></div>' +
        '<p class="tuk-install-help" data-tuktuk-install-help hidden></p>';
      doc.body.appendChild(banner);
      refreshButton();
      banner.querySelector('[data-tuktuk-install-close]').addEventListener('click', function () { hide(true); });
      banner.querySelector('[data-tuktuk-install-action]').addEventListener('click', function () {
        if (deferred) {
          var event = deferred;
          deferred = null;
          // El prompt del navegador debe dispararse directamente con este clic.
          try {
            var result = event.prompt();
            Promise.resolve(result).then(function () { return event.userChoice; }).then(function (choice) {
              if (choice && choice.outcome === 'accepted') hide(true);
              else { hide(true); }
            }).catch(function () { hide(true); });
          } catch (_) {
            showInstructions();
          }
          refreshButton();
        } else {
          showInstructions();
        }
      });
    }
    function showInstructions() {
      if (!banner) return;
      var help = banner.querySelector('[data-tuktuk-install-help]');
      if (help) { help.textContent = helpText(); help.hidden = false; }
      var action = banner.querySelector('[data-tuktuk-install-action]');
      if (action) action.hidden = true;
    }
    function schedule() {
      if (scheduled || !ready) return;
      scheduled = true;
      win.setTimeout(function () { scheduled = false; render(); }, 4000);
    }
    function onReady() { if (ready) return; ready = true; schedule(); }

    win.addEventListener('beforeinstallprompt', function (event) {
      if (event && typeof event.preventDefault === 'function') event.preventDefault();
      deferred = event;
      if (ready && !banner) schedule();
      refreshButton();
    });
    win.addEventListener('appinstalled', function () { hide(true); deferred = null; });
    if (isLite) {
      if (doc.readyState === 'loading') doc.addEventListener('DOMContentLoaded', onReady, { once: true });
      else onReady();
    } else {
      win.addEventListener('flutter-first-frame', onReady, { once: true });
    }
  }

  return { start: start, platform: platform, cooldownActive: cooldownActive, installed: installed };
}));

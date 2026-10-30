'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const lite = require('../../web/lite/lite.js');
const html = fs.readFileSync('web/lite/index.html','utf8');
const js = fs.readFileSync('web/lite/lite.js','utf8');
const sw = fs.readFileSync('web/lite/lite-sw.js','utf8');
const projectId = 'dfb41cea-a812-46f2-b511-7a60bd3d78af';
const fields = {name:'Ana Pérez',phone:'+5350000000',service:'Moto',origin:'Calle 10 y 15',destination:'Hospital central',notes:'Puerta norte'};
function storage() {
  const values = new Map();
  return {getItem:k=>values.get(k)||null, setItem:(k,v)=>values.set(k,v),removeItem:k=>values.delete(k)};
}
test('WhatsApp tiene iconos, bloques y enlaces; nunca inventa un pin',()=>{
  const message = lite.messageFor(fields);
  assert.match(message,/🚕 \*TUKTUK \| NUEVA SOLICITUD\*/);
  assert.match(message,/📍 \*RECOGIDA\*/);
  assert.match(message,/🏁 \*DESTINO\*/);
  assert.match(message,/No proporcionado/);
  assert.match(message,/Buscar destino \(dirección, no pin\)/);
  assert.match(message,/No hay precio ni reserva confirmados/);
  assert.doesNotMatch(message,/Abrir pin de recogida/);
  const withGps = {...fields,origin:'Mi ubicación actual (GPS)',originLatitude:23.1254,originLongitude:-82.3876,originAccuracy:25.3};
  const gpsMessage = lite.messageFor(withGps);
  assert.match(gpsMessage,/Abrir pin de recogida/);
  assert.match(gpsMessage,/https:\/\/maps.google.com\/\?q=23.125400,-82.387600/);
  assert.match(gpsMessage,/precisión aprox. 25 m/);
  assert.match(lite.whatsappUrl('+5355555555',withGps),/^https:\/\/wa.me\/5355555555\?text=/);
});
test('SMS sin emojis incluye coordenadas y enlace si hay GPS confirmado',()=>{
  const gps = {...fields,originLatitude:23.1254,originLongitude:-82.3876,originAccuracy:30};
  const message = lite.smsMessageFor(gps);
  assert.match(message,/Origen: Calle 10 y 15/);
  assert.match(message,/GPS origen: 23.125400,-82.387600/);
  assert.match(message,/Mapa origen: https:\/\/maps.google.com\/\?q=23.125400,-82.387600/);
  assert.match(message,/Buscar destino:/);
  assert.doesNotMatch(lite.smsMessageFor(fields),/GPS origen:/);
});
test('cache local de soporte solo conserva numero E164 verificado por 24 horas',()=>{
  const store=storage(); const now=1700000000000;
  assert.equal(lite.readCachedSupport(store,projectId,now),null);
  assert.equal(lite.saveCachedSupport(store,'123',projectId,now),false);
  assert.equal(lite.saveCachedSupport(store,'+5355555555',projectId,now),true);
  assert.equal(lite.readCachedSupport(store,projectId,now+60*60*1000),'+5355555555');
  assert.equal(lite.readCachedSupport(store,projectId,now+24*60*60*1000+1),null);
  assert.equal(lite.readCachedSupport(store,'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',now+1),null);
  assert.equal(lite.readCachedSupport(store,projectId,now-1),null);
  lite.clearCachedSupport(store);
  assert.equal(lite.readCachedSupport(store,projectId,now),null);
});
test('desactivacion explicita del Admin nunca autoriza contacto almacenado',async()=>{
  const config = {projectId,supabaseUrl:'https://test-project.supabase.co',supabasePublishableKey:'sb_publishable_testing_123'};
  const enabled = async()=>({ok:true,headers:{get:()=> 'application/json'},json:async()=>({project_id:projectId,support:{enabled:true,number:'+5355555555'}})});
  const disabled = async()=>({ok:true,headers:{get:()=> 'application/json'},json:async()=>({project_id:projectId,support:{enabled:false,number:'+5355555555'}})});
  assert.deepEqual(await lite.fetchSupportState(enabled,config),{status:'active',number:'+5355555555'});
  assert.deepEqual(await lite.fetchSupportState(disabled,config),{status:'inactive'});
  assert.deepEqual(await lite.fetchSupportState(async()=>{throw Error('offline')},config),{status:'unreachable'});
});
test('sin internet, el SMS acepta un contacto cacheado y WhatsApp no se habilita',async()=>{
  const callbacks = {};
  const make = id => ({ hidden:false, disabled:false, checked:false, textContent:'', classList:{toggle(){}},
    addEventListener(type,cb){ callbacks[id+':'+type] = cb; } });
  const ids = ['lite-form','lite-status','lite-send','lite-consent','lite-retry',
    'lite-next','lite-back','lite-step-route','lite-step-contact','lite-feedback',
    'lite-send-sms','lite-thanks','lite-another','lite-intro','lite-locate','lite-geo-status'];
  const elements = Object.fromEntries(ids.map(id=>[id, make(id)]));
  const originInput = { addEventListener() {}, value:'' };
  elements['lite-form'].elements={ namedItem: () => originInput };
  const store=storage();
  lite.saveCachedSupport(store,'+5355555555',projectId,Date.now());
  let launched='';
  const fields={name:'Ana Pérez',phone:'+5350000000',service:'Moto',origin:'Calle 10 y 15',destination:'Hospital central',notes:''};
  const win={navigator:{onLine:false,connection:{effectiveType:'2g'},userAgent:'Android'},
    location:{protocol:'https:',search:'?preview=1',assign(url){launched=url},replace(){throw Error('No redireccionar si cache valido')}},
    localStorage:store,scrollTo(){},fetch(){throw Error('No consultar red offline')}};
  const sandbox={window:win,document:{getElementById:id=>elements[id]},
    URL,URLSearchParams,AbortController,setTimeout,clearTimeout,Date,
    FormData:class {entries(){return Object.entries(fields)[Symbol.iterator]()}}};
  vm.runInNewContext(js,sandbox,{timeout:1500});
  await new Promise(resolve=>setImmediate(resolve));
  elements['lite-consent'].checked=true;
  callbacks['lite-consent:change']();
  assert.equal(elements['lite-send'].disabled,true,'WhatsApp nunca con cache offline');
  assert.equal(elements['lite-send-sms'].disabled,false,'SMS habilitado con numero reciente');
  assert.match(elements['lite-status'].textContent,/último contacto verificado/);
  callbacks['lite-send-sms:click']();
  await new Promise(resolve=>setImmediate(resolve));
  assert.match(launched,/^sms:\+5355555555\?body=/);
});
test('service worker de Lite solo recupera carcasa pública ya cacheada',async()=>{
  const handlers={};
  const cached={ok:true,type:'basic',clone(){return this},source:'cache'};
  const cache={match:async()=>cached,put:async()=>{}};
  const context={self:{registration:{scope:'https://example.com/cliente/tuk/lite/'},
    addEventListener(type,cb){handlers[type]=cb}},
    caches:{open:async()=>cache,keys:async()=>[]},URL,AbortController,setTimeout,clearTimeout,
    fetch:async()=>{throw Error('sin internet')}};
  vm.runInNewContext(sw,context,{timeout:1500});
  let promise=null;
  const fire=(relative,mode)=>{
    promise=null;
    handlers.fetch({request:{method:'GET',url:'https://example.com/cliente/tuk/lite/'+relative,
      headers:{has:()=>false},mode},respondWith(x){promise=x}});
  };
  fire('', 'navigate');
  assert.equal((await promise).source,'cache');
  fire('lite.js','no-cors');
  assert.equal((await promise).source,'cache');
  fire('config.json','no-cors');
  assert.equal(promise,null,'no almacenar configuracion online de Admin');
});
test('interfaz GPS opcional sin mapa pesado y estado SMS cache',()=>{
  assert.match(html,/id="lite-locate"/);
  assert.match(html,/id="lite-geo-status"/);
  assert.match(js,/getCurrentPosition/);
  assert.match(js,/readCachedSupport\(root\.localStorage/);
  assert.match(js,/SMS con último contacto verificado/);
  assert.match(js,/serviceWorker.register/);
  assert.match(sw,/tuktuk-lite-static-v1/);
  assert.match(sw,/relative === 'lite.js'/);
  assert.doesNotMatch(sw,/main\.dart\.js|config\.json|firebase/i);
  assert.doesNotMatch(html,/flutter_bootstrap|main\.dart\.js|firebase|mapbox/i);
});

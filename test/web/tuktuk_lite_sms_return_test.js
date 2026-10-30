'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const lite = require('../../web/lite/lite.js');
const html = fs.readFileSync('web/lite/index.html','utf8');
const js = fs.readFileSync('web/lite/lite.js','utf8');
const fields = {name:'Ana Pérez',phone:'+5350000000',service:'Moto',origin:'Calle 10 y 15',destination:'Hospital',notes:''};

test('SMS usa el mismo telefono verificado y cambia separador según plataforma',()=>{
  assert.match(lite.smsUrl('+5355555555',fields,'Android'),/^sms:\+5355555555\?body=/);
  assert.match(lite.smsUrl('+5355555555',fields,'iPhone'),/^sms:\+5355555555&body=/);
  assert.match(decodeURIComponent(lite.smsUrl('+5355555555',fields,'Android')),/Origen: Calle 10 y 15/);
  assert.throws(()=>lite.smsUrl('123',fields));
  assert.match(js,/const number = await verify\(false\);/);
});

test('Interfaz muestra SMS y pantalla de gracias sin afirmar recepción',()=>{
  assert.match(html,/id="lite-send-sms" disabled/);
  assert.match(html,/id="lite-thanks"[^>]*hidden/);
  assert.match(html,/En breve, una operadora se pondrá en contacto con usted/);
  assert.match(html,/id="lite-another"/);
  assert.match(js,/visibilitychange/);
  assert.match(js,/pageshow/);
  assert.match(js,/sessionStorage/);
  assert.doesNotMatch(html,/Hemos recibido tu solicitud|Solicitud enviada correctamente/);
});

test('No crea carreras ni añade Flutter, Mapbox o Firebase',()=>{
  assert.doesNotMatch(js,/create_marketplace_customer_request|publish_marketplace_customer_job|create_request/);
  assert.doesNotMatch(html,/main\.dart\.js|flutter_bootstrap|firebase|mapbox/i);
});

test('El cartel aparece solo al regresar, y otra carrera restablece la pantalla inicial',async()=>{
  const handlers={};const docHandlers={};const winHandlers={};
  const el=(id,hidden=false)=>({hidden,disabled:false,checked:false,textContent:'',
    classList:{toggle(){}},addEventListener(type,cb){handlers[id+':'+type]=cb;}});
  const elements={'lite-form':el('form'),'lite-status':el('status'),'lite-send':el('send'),
    'lite-consent':el('consent'),'lite-retry':el('retry',true),'lite-next':el('next'),
    'lite-back':el('back'),'lite-step-route':el('route'),'lite-step-contact':el('contact',true),
    'lite-feedback':el('feedback',true),'lite-send-sms':el('sms'),'lite-thanks':el('thanks',true),
    'lite-another':el('another'),'lite-intro':el('intro')};
  const input={...fields};const storage=new Map();let launched='';let reads=0;
  elements['lite-form'].elements={namedItem:()=>({focus(){}})};
  elements['lite-form'].reset=()=>{input.origin='';input.destination='';input.name='';input.phone='';};
  const projectId='dfb41cea-a812-46f2-b511-7a60bd3d78af';
  const window={navigator:{connection:{effectiveType:'2g'},userAgent:'Android'},
    location:{search:'?preview=1',replace(){throw Error('unexpected redirect')},assign(url){launched=url}},
    sessionStorage:{getItem(k){return storage.get(k)||null},setItem(k,v){storage.set(k,v)},removeItem(k){storage.delete(k)}},
    scrollTo(){},addEventListener(type,cb){winHandlers[type]=cb},
    fetch:async(url)=>({ok:true,headers:{get:()=> 'application/json'},json:async()=>url==='./config.json'
      ? {projectId,supabaseUrl:'https://test-project.supabase.co',supabasePublishableKey:'sb_publishable_test_123'}
      : (reads++,{project_id:projectId,support:{enabled:true,number:'+5355555555'}})})};
  const document={visibilityState:'visible',getElementById:id=>elements[id],addEventListener(type,cb){docHandlers[type]=cb}};
  const sandbox={window,document,URL,URLSearchParams,AbortController,setTimeout,clearTimeout,Date,FormData:class{entries(){return Object.entries(input)[Symbol.iterator]()}}};
  vm.runInNewContext(js,sandbox,{timeout:1500});
  await new Promise(resolve=>setImmediate(resolve));
  assert.equal(elements['lite-thanks'].hidden,true);
  handlers['next:click']();elements['lite-consent'].checked=true;handlers['consent:change']();
  assert.equal(elements['lite-send-sms'].disabled,false);
  handlers['sms:click']();await new Promise(resolve=>setImmediate(resolve));
  assert.match(launched,/^sms:\+5355555555\?body=/);
  assert.equal(reads,2);
  assert.equal(elements['lite-thanks'].hidden,true,'No se anuncia recepción sin regresar');
  document.visibilityState='hidden';docHandlers.visibilitychange();
  document.visibilityState='visible';docHandlers.visibilitychange();
  assert.equal(elements['lite-thanks'].hidden,false);
  handlers['another:click']();await new Promise(resolve=>setImmediate(resolve));
  assert.equal(elements['lite-thanks'].hidden,true);
  assert.equal(elements['lite-form'].hidden,false);
  assert.equal(elements['lite-step-route'].hidden,false);
  assert.equal(elements['lite-consent'].checked,false);
});

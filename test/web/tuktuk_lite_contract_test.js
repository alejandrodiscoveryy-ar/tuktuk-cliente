'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const core = require('../../web/lite/lite.js');
const html = fs.readFileSync('web/lite/index.html', 'utf8');
const js = fs.readFileSync('web/lite/lite.js', 'utf8');
const projectId = 'dfb41cea-a812-46f2-b511-7a60bd3d78af';
const config = { projectId, supabaseUrl:'https://test-project.supabase.co', supabasePublishableKey:'sb_publishable_testing_123' };
const settings = { project_id:projectId, support:{enabled:true,number:'+5355555555'},payment:{enabled:true,number:'+5355555555'},version:11 };
const fields = {name:'Ana Pérez',phone:'+5350000000',service:'Moto',origin:'Calle 10 esquina 15',destination:'Hospital central',notes:'Puerta norte'};
const response = (data) => ({ok:true,headers:{get:()=> 'application/json; charset=utf-8'},json:async()=>data});

test('buena conexion usa siempre la version completa y red debil puede ofrecer Lite',()=>{
  assert.equal(core.slowNetwork({effectiveType:'4g',downlink:10,rtt:80}),false);
  assert.equal(core.slowNetwork({effectiveType:'3g',downlink:1.1,rtt:450}),true);
  assert.equal(core.slowNetwork({effectiveType:'4g',downlink:10,rtt:900}),true);
  assert.equal(core.slowNetwork({effectiveType:'4g',downlink:5,rtt:80,saveData:true}),true);
  assert.equal(core.slowNetwork(undefined),false);
});

test('lee exclusivamente la configuracion publica de soporte actual de Admin',()=>{
  assert.equal(core.currentSupportNumber(settings,projectId),'+5355555555');
  assert.equal(core.currentSupportNumber({...settings,support:{enabled:false,number:'+5355555555'}},projectId),null);
  assert.equal(core.currentSupportNumber({...settings,support:{enabled:false},payment:{enabled:true,number:'+5355555555'}},projectId),null);
  assert.equal(core.currentSupportNumber({...settings,support:{enabled:true,number:'123'}},projectId),null);
  assert.equal(core.currentSupportNumber({...settings,project_id:'wrong'},projectId),null);
});

test('configuracion publica validada, sin claves secretas ni numeros fijos',()=>{
  assert.deepEqual(core.parseConfig(config),config);
  assert.equal(core.parseConfig({...config,supabasePublishableKey:'sb_secret_insegura'}),null);
  assert.equal(core.parseConfig({...config,supabaseUrl:'http://not-secure.example'}),null);
  assert.equal(core.parseConfig({...config,supabaseUrl:'https://malicious.example'}),null);
  assert.equal(core.parseConfig({...config,projectId:'invalid'}),null);
  assert.doesNotMatch(js, /\+53\d{8}|const\s+\w+\s*=\s*['"]sb_secret|importScripts\(|new\s+MapWidget\(/);
});

test('consulta dinamica Supabase por RPC publica con cache no-store y nueva lectura por envio',async()=>{
  const calls=[];
  let next='+5355555555';
  const fetchFn=async(url,options)=>{
    calls.push({url,options});
    return response({...settings,support:{enabled:true,number:next}});
  };
  assert.equal(await core.fetchCurrentSupport(fetchFn,config),'+5355555555');
  next='+5355555556';
  assert.equal(await core.fetchCurrentSupport(fetchFn,config),'+5355555556');
  assert.equal(calls.length,2);
  for(const call of calls) {
    assert.equal(call.url,'https://test-project.supabase.co/rest/v1/rpc/get_public_whatsapp_settings');
    assert.equal(call.options.method,'POST');
    assert.equal(call.options.cache,'no-store');
    assert.equal(call.options.headers.apikey, config.supabasePublishableKey);
    assert.deepEqual(JSON.parse(call.options.body),{target_project_id:projectId});
  }
  assert.match(js,/const number = await verify\(false\);/);
});

test('errores y respuestas HTML nunca permiten enviar al numero equivocado',async()=>{
  assert.equal(await core.fetchCurrentSupport(async()=>{throw new Error('offline')},config),null);
  const badHtml=async()=>({ok:true,headers:{get:()=> 'text/html'},json:async()=>settings});
  assert.equal(await core.fetchCurrentSupport(badHtml,config),null);
  assert.equal(await core.fetchCurrentSupport(async()=>response({...settings,support:{enabled:false}}),config),null);
  assert.equal(await core.loadConfig(async()=>response(config)).then(x=>x.projectId),projectId);
});

test('formulario usa consentimiento, datos validos y mensaje sin precio inventado',()=>{
  assert.equal(core.validateForm(fields),null);
  assert.match(core.validateForm({...fields,origin:'a'}),/origen/);
  assert.match(core.validateForm({...fields,service:'Sin tarifa'}),/servicio/);
  const msg=core.messageFor(fields);
  assert.match(msg,/WhatsApp Lite/);
  assert.match(msg,/No hay precio ni reserva confirmados/);
  const url=core.whatsappUrl('+5355555555',fields);
  assert.match(url,/^https:\/\/wa\.me\/5355555555\?text=/);
  assert.match(decodeURIComponent(url),/Ana Pérez/);
  assert.throws(()=>core.whatsappUrl('123',fields));
  assert.match(html,/id="lite-consent"/);
  assert.match(html,/id="lite-send" disabled/);
  assert.match(html,/href="\.\.\/\?mode=full"/);
});

test('Lite es HTML minimo independiente y sin creacion de carreras automatica',()=>{
  assert.doesNotMatch(html,/flutter_bootstrap|main\.dart\.js|firebase|mapbox/i);
  assert.match(js,/\?lite=unavailable/);
  assert.match(js,/form\.addEventListener\('submit'/);
  assert.doesNotMatch(js, /create_marketplace_customer_request|publish_marketplace_customer_job|create_request/);
});

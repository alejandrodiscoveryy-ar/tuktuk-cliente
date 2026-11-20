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
  assert.match(msg,/TUKTUK Lite \| Solicitud/);
  assert.match(msg,/Sin precio ni reserva confirmados/);
  const url=core.whatsappUrl('+5355555555',fields);
  assert.match(url,/^https:\/\/wa\.me\/5355555555\?text=/);
  assert.match(decodeURIComponent(url),/Ana Pérez/);
  assert.throws(()=>core.whatsappUrl('123',fields));
  assert.match(html,/id="lite-consent"/);
  assert.match(html,/id="lite-send" disabled/);
  assert.match(html,/href="\.\.\/\?mode=full"/);
});

test('Lite conserva fuente y campaña al volver a completo, no parámetros privados',()=>{
  assert.equal(core.fullAppUrl('?utm_source=facebook&utm_campaign=tuktuk_hospitales&telefono=1234'),
    '../?mode=full&utm_source=facebook&utm_campaign=tuktuk_hospitales');
  assert.equal(core.fullAppUrl('?utm_source=qr&utm_campaign=tuktuk_impresos','lite'),
    '../?lite=unavailable&utm_source=qr&utm_campaign=tuktuk_impresos');
  assert.equal(core.fullAppUrl('?utm_source=evil&utm_campaign=a%40b&conductor=1234'),
    '../?mode=full');
  assert.equal(core.fullAppUrl(''), '../?mode=full');
});
test('Lite registra su carga real con fuente comercial, nunca una solicitud confirmada',()=>{
  const posts=[];
  const state=new Map();
  const host={
    location:{search:'?utm_source=whatsapp_groups&utm_campaign=tuktuk_hospitales&phone=12345678'},
    navigator:{},
    crypto:{randomUUID:()=> '12345678-1234-4234-8234-123456789abc'},
    sessionStorage:{getItem:k=>state.get(k)||null,setItem:(k,v)=>state.set(k,v)},
    fetch:(url,init)=>{ posts.push({url,init,body:JSON.parse(init.body)});return Promise.resolve({status:204}); },
  };
  assert.equal(core.trackLiteOpen(host),true);
  assert.equal(posts.length,1);
  assert.equal(posts[0].body.event,'app_open');
  assert.equal(posts[0].body.channel,'whatsapp_groups');
  assert.equal(posts[0].body.campaign,'tuktuk_hospitales');
  assert.equal(posts[0].body.promo_code,null);
  assert.equal(posts[0].body.session_id,'12345678-1234-4234-8234-123456789abc');
  assert.ok(!JSON.stringify(posts[0].body).includes('phone'));
  assert.equal(posts[0].init.keepalive,true);
  assert.equal(posts[0].init.credentials,'omit');
  assert.equal(posts[0].init.headers['Content-Type'],'text/plain');
  // Misma sesión que el acceso completo; el backend evita duplicar la etapa.
  core.trackLiteOpen(host);
  assert.equal(state.size,1);
  assert.equal(posts[1].body.session_id,posts[0].body.session_id);
  assert.match(js,/trackLiteOpen\(root\);/);
  assert.ok(js.indexOf('trackLiteOpen(root);') > js.indexOf('root.location.replace(fullModeUrl);'));
});

test('Lite respeta privacidad y la telemetría nunca interrumpe el servicio',()=>{
  const body=[];
  const base={
    location:{search:'?utm_source=invalid&utm_campaign=nombre%40invalido'},
    navigator:{},
    crypto:{randomUUID:()=> '12345678-1234-4234-8234-123456789abc'},
    sessionStorage:{getItem:()=>null,setItem:()=>{}},
    fetch:(url,options)=>{body.push(JSON.parse(options.body));throw new Error('sin red');},
  };
  assert.equal(core.trackLiteOpen(base),false);
  assert.equal(body[0].channel,'unknown');
  assert.equal(body[0].campaign,null);
  assert.equal(core.trackLiteOpen({...base,navigator:{doNotTrack:'1'}}),false);
  assert.equal(core.trackLiteOpen({...base,navigator:{globalPrivacyControl:true}}),false);
  assert.equal(core.trackLiteOpen({...base,fetch:undefined}),false);
  assert.equal(body.length,1);
});

test('Lite es HTML minimo independiente y sin creacion de carreras automatica',()=>{
  assert.doesNotMatch(html,/flutter_bootstrap|main\.dart\.js|firebase|mapbox/i);
  assert.match(js,/fullAppUrl\(root\.location\.search, 'lite'\)/);
  assert.match(js,/form\.addEventListener\('submit'/);
  assert.doesNotMatch(js, /create_marketplace_customer_request|publish_marketplace_customer_job|create_request/);
});

'use strict';
const test=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs');
const vm=require('node:vm');
const html=fs.readFileSync('web/index.html','utf8');
const match=html.match(/<!-- IMPULSA_COMMUNICATION_ANALYTICS_V1 -->\s*<script>([\s\S]*?)<\/script>\s*<!-- IMPULSA_COMMUNICATION_ANALYTICS_V1_END -->/);
const code='0123456789abcdef0123456789abcdef';
function simulate(search,privacy={}) {
  assert.ok(match,'Missing Impulsa analytics bridge');
  const posts=[];
  const persisted=new Map();
  const window={
    location:{search},crypto:{randomUUID:()=> '12345678-1234-4234-8234-123456789abc'},
    sessionStorage:{getItem(k){return persisted.get(k)||null},setItem(k,v){persisted.set(k,v)}},
    fetch:async (url,init)=>{posts.push({url,init,body:JSON.parse(init.body)});return {status:204}},
  };
  const navigator={...privacy};
  vm.runInNewContext(match[1],{window,navigator,URLSearchParams,Set,Number,RegExp,JSON},
    {timeout:1000});
  return {window,posts,persisted};
}
test('Impulsa preserves only safe tagged channel and campaign and ephemeral session',()=>{
  const {window,posts,persisted}=simulate('?conductor='+code+'&utm_source=whatsapp_groups&utm_campaign=grupo-centro&phone=1234');
  assert.equal(posts.length,1);
  assert.equal(posts[0].body.event,'link_open');
  assert.equal(posts[0].body.channel,'whatsapp_groups');
  assert.equal(posts[0].body.campaign,'grupo-centro');
  assert.equal(posts[0].body.promo_code,code);
  assert.ok(!JSON.stringify(posts[0].body).includes('phone'));
  assert.equal(posts[0].init.keepalive,true);
  assert.equal(posts[0].init.credentials,'omit');
  assert.equal(persisted.size,1);
  window.tuktukImpulsaTrack('quote_ready',3900.3);
  window.tuktukImpulsaTrack('request_created');
  window.tuktukImpulsaTrack('survey_answer',null,'price');
  assert.deepEqual(posts.slice(1).map(p=>p.body.event),['quote_ready','request_created','survey_answer']);
  assert.equal(posts[1].body.price_cup,3900.3);
  assert.equal(posts[3].body.reason,'price');
});
test('invalid promo and campaign cannot become driver attribution',()=>{
  const x=simulate('?conductor=not-a-code&utm_source=evil&utm_campaign=secret@example.com');
  assert.equal(x.posts.length,0);
  x.window.tuktukImpulsaTrack('app_open');
  assert.equal(x.posts[0].body.promo_code,null);
  assert.equal(x.posts[0].body.campaign,null);
  assert.equal(x.posts[0].body.channel,'unknown');
  x.window.tuktukImpulsaTrack('survey_answer',null,'bank_account');
  assert.equal(x.posts.length,1);
});
test('global privacy control and Do Not Track disable telemetry',()=>{
  for(const privacy of [{doNotTrack:'1'},{globalPrivacyControl:true}]){
    const x=simulate('?conductor='+code,privacy);
    assert.equal(x.posts.length,0);
    assert.equal(x.window.tuktukImpulsaTrack,undefined);
  }
});
test('first Flutter frame is measured; analytics never blocks the app preload',()=>{
  assert.match(html,/flutter-first-frame[\s\S]*tuktukImpulsaTrack\('app_open'\)/);
  assert.ok(html.indexOf('TUKTUK_UNIFIED_ENTRY_BEGIN') < html.indexOf('IMPULSA_COMMUNICATION_ANALYTICS_V1'));
  assert.ok(html.indexOf('IMPULSA_COMMUNICATION_ANALYTICS_V1') < html.indexOf('flutter-first-frame'));
});

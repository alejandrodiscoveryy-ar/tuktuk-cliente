'use strict';
const test=require('node:test');
const assert=require('node:assert/strict');
const {readFileSync}=require('node:fs');
const lite=require('../../web/lite/lite.js');
const js=readFileSync('web/lite/lite.js','utf8');
const projectId='dfb41cea-a812-46f2-b511-7a60bd3d78af';
const hours={enabled:true,days:[1,2,3,4,5],open:'09:00',close:'17:00',timezone:'America/Havana'};
const mockStorage=()=>{const map=new Map();return {getItem:k=>map.get(k)||null,setItem:(k,v)=>map.set(k,v),removeItem:k=>map.delete(k)}};
test('horario cubano permite dia y hora laboral y rechaza horario cerrado',()=>{
  assert.equal(lite.supportHoursOpen(hours,new Date('2026-01-12T15:00:00Z')),true); // lun 10:00
  assert.equal(lite.supportHoursOpen(hours,new Date('2026-01-12T23:00:00Z')),false); // lun 18:00
  assert.equal(lite.supportHoursOpen(hours,new Date('2026-01-11T15:00:00Z')),false); // domingo
  assert.equal(lite.supportHoursOpen({...hours,timezone:'UTC'},new Date('2026-01-12T15:00:00Z')),false);
  assert.equal(lite.supportHoursOpen({enabled:false},new Date('2026-01-12T23:00:00Z')),true);
});
test('cache offline con horario no ofrece SMS fuera de la atencion',()=>{
  const store=mockStorage();
  const inside=Date.parse('2026-01-12T15:00:00Z');
  const outside=Date.parse('2026-01-12T23:00:00Z');
  assert.equal(lite.saveCachedSupport(store,'+5355555555',projectId,inside,hours),true);
  assert.equal(lite.readCachedSupport(store,projectId,inside+1000),'+5355555555');
  assert.equal(lite.readCachedSupport(store,projectId,outside),null);
  assert.equal(lite.readCachedSupport(store,projectId,inside+24*60*60*1000+1),null);
});
test('cache legacy sin horario confirmado se invalida, pero el nuevo guarda esquema seguro',()=>{
  const store=mockStorage(), now=Date.parse('2026-01-12T15:00:00Z');
  store.setItem('tuktuk_lite_support_cache_v1',JSON.stringify({number:'+5355555555',projectId,checkedAt:now}));
  assert.equal(lite.readCachedSupport(store,projectId,now+1),null);
  assert.equal(lite.saveCachedSupport(store,'+5355555555',projectId,now),true);
  assert.equal(lite.readCachedSupport(store,projectId,now+1),'+5355555555');
});
test('respuesta publica activa trae horario, desactivada no habilita telefono',async()=>{
  const config={projectId,supabaseUrl:'https://test.supabase.co',supabasePublishableKey:'sb_publishable_testing_123'};
  const data={project_id:projectId,support:{enabled:true,number:'+5355555555',hours}};
  const fetcher=async()=>({ok:true,headers:{get:()=> 'application/json'},json:async()=>data});
  assert.deepEqual(await lite.fetchSupportState(fetcher,config),{status:'active',number:'+5355555555',hours});
  data.support.lite_open=false;
  assert.deepEqual(await lite.fetchSupportState(fetcher,config),{status:'inactive'});
  data.support.lite_open=true; data.support.enabled=false;
  assert.deepEqual(await lite.fetchSupportState(fetcher,config),{status:'inactive'}); // legacy RPC
  data.support.lite_enabled=true;
  assert.deepEqual(await lite.fetchSupportState(fetcher,config),{status:'active',number:'+5355555555',hours});
  data.support.lite_enabled=false; data.support.enabled=true;
  assert.deepEqual(await lite.fetchSupportState(fetcher,config),{status:'inactive'});
  assert.match(js,/root\.location\.replace\('\.\.\/\?lite=unavailable'\);/);
});

// PENDING review/deploy; standalone Supabase Edge Function for TUKTUK Cliente.
// Uses Firebase service-account ENV (never shipped in the app) and service-role Supabase.
import { withSupabase } from 'npm:@supabase/server@1.5.2';

type ServiceAccount = { project_id: string; client_email: string; private_key: string };
type Claim = {
  delivery_id: number;
  claim_uuid: string;
  subscription_id: string;
  fcm_token: string;
  rate_history_id: number;
  current_rate: number;
  previous_rate: number | null;
  attempt_number: number;
};
const ORIGIN = 'https://www.vrixora.com';
const TABLE = 'marketplace_customer_eltoque_push_subscriptions';
const DELIVERIES = 'marketplace_customer_eltoque_push_deliveries';
const HEADER = 'x-tuktuk-dispatch-secret';
const TOKEN_PATTERN = /^[a-zA-Z0-9_:\-.]{80,4096}$/;
const SECRET_PATTERN = /^[a-f0-9]{64}$/;

function cors(origin: string | null) {
  return origin === ORIGIN ? {
    'access-control-allow-origin': ORIGIN,
    'access-control-allow-methods': 'POST, OPTIONS',
    'access-control-allow-headers': 'content-type, authorization, apikey, x-client-info',
    'vary': 'Origin',
  } : {};
}
function json(body: unknown, status = 200, headers: Record<string, string> = {}) {
  return Response.json(body, { status, headers: { ...headers, 'cache-control': 'no-store' } });
}
function errorText(e: unknown) { return e instanceof Error ? e.message : String(e); }
async function sha256(value: string) {
  const hash = new Uint8Array(await crypto.subtle.digest('SHA-256', new TextEncoder().encode(value)));
  return [...hash].map(x => x.toString(16).padStart(2, '0')).join('');
}
async function sameSecret(actual: string, expected: string) {
  if (!actual || !expected) return false;
  const [a, b] = await Promise.all([sha256(actual), sha256(expected)]);
  return a === b;
}
function b64url(bytes: Uint8Array) {
  let s = '';
  for (const byte of bytes) s += String.fromCharCode(byte);
  return btoa(s).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/g, '');
}
function b64text(value: string) { return b64url(new TextEncoder().encode(value)); }
function pemBuffer(pem: string) {
  const s = pem.replace('-----BEGIN PRIVATE KEY-----','').replace('-----END PRIVATE KEY-----','').replace(/\s/g,'');
  const binary = atob(s), bytes = new Uint8Array(binary.length);
  for (let i=0; i<binary.length; i++) bytes[i]=binary.charCodeAt(i);
  return bytes.buffer;
}
async function googleAccessToken(account: ServiceAccount) {
  const now = Math.floor(Date.now()/1000);
  const header = b64text(JSON.stringify({ alg:'RS256',typ:'JWT' }));
  const payload = b64text(JSON.stringify({
    iss:account.client_email,scope:'https://www.googleapis.com/auth/firebase.messaging',
    aud:'https://oauth2.googleapis.com/token',iat:now,exp:now+3600,
  }));
  const input=`${header}.${payload}`;
  const key=await crypto.subtle.importKey('pkcs8',pemBuffer(account.private_key),
    {name:'RSASSA-PKCS1-v1_5',hash:'SHA-256'},false,['sign']);
  const signature=await crypto.subtle.sign('RSASSA-PKCS1-v1_5',key,new TextEncoder().encode(input));
  const assertion=`${input}.${b64url(new Uint8Array(signature))}`;
  const resp=await fetch('https://oauth2.googleapis.com/token',{
    method:'POST',headers:{'content-type':'application/x-www-form-urlencoded'},
    body:new URLSearchParams({grant_type:'urn:ietf:params:oauth:jwt-bearer',assertion}),
  });
  const data=await resp.json();
  if (!resp.ok || typeof data.access_token!=='string') throw new Error('Firebase OAuth unavailable');
  return data.access_token as string;
}
function accountFromEnvironment(): ServiceAccount {
  const raw=Deno.env.get('FIREBASE_SERVICE_ACCOUNT_JSON') ?? Deno.env.get('FIREBASE_SERVICE_ACCOUNT') ?? '';
  if (!raw) throw new Error('Missing Firebase service-account secret');
  const account=JSON.parse(raw) as ServiceAccount;
  if (!account.project_id || !account.client_email || !account.private_key) throw new Error('Invalid Firebase configuration');
  return account;
}
function rateBody(row: Claim) {
  const current=Number(row.current_rate);
  const previous=row.previous_rate === null ? null : Number(row.previous_rate);
  const direction=previous === null ? '' : current>previous ? 'subió' : current<previous ? 'bajó' : 'cambió';
  return {
    title:'elTOQUE · TUKTUK Cliente',
    body: previous === null ? `1 USD = ${current} CUP. Valor referencial.` :
      `El USD ${direction}: ${current} CUP (antes ${previous}). Valor referencial.`,
  };
}
async function dispatch(admin: any) {
  const service=accountFromEnvironment();
  const accessToken=await googleAccessToken(service);
  const {data, error}=await admin.rpc('marketplace_customer_eltoque_push_claim',{batch_limit:60});
  if (error) throw new Error(`Could not claim push batch (${error.code || 'database'})`);
  const rows=(data??[]) as Claim[];
  let sent=0, retry=0, disabled=0;
  // Bounded concurrency, retries and a short processing window.
  for (let offset=0;offset<rows.length;offset+=6) {
    await Promise.all(rows.slice(offset,offset+6).map(async row=>{
      let permanent=false, invalid=false, failure='';
      try {
        const {title,body}=rateBody(row);
        const message={
          token:row.fcm_token,
          data:{kind:'customer_exchange_rate_update',title,body,
            rate_history_id:String(row.rate_history_id)},
          webpush:{headers:{Urgency:'normal'}},
        };
        const result=await fetch(`https://fcm.googleapis.com/v1/projects/${encodeURIComponent(service.project_id)}/messages:send`,{
          method:'POST',headers:{authorization:`Bearer ${accessToken}`,'content-type':'application/json'},
          body:JSON.stringify({message}),signal:AbortSignal.timeout(10000),
        });
        if (result.ok) {
          const {error}=await admin.from(DELIVERIES).update({status:'sent',sent_at:new Date().toISOString(),claimed_until:null,last_error:null})
            .eq('id',row.delivery_id).eq('claim_id',row.claim_uuid);
          if (error) throw new Error('Failed recording FCM delivery');
          sent++;
          return;
        }
        const payload=await result.json().catch(()=>({}));
        const err=payload?.error || {};
        const code=(err.details||[]).find((x:any)=>typeof x?.errorCode==='string')?.errorCode ?? err.status ?? String(result.status);
        invalid=code==='UNREGISTERED';
        permanent=['UNREGISTERED','INVALID_ARGUMENT','SENDER_ID_MISMATCH','THIRD_PARTY_AUTH_ERROR'].includes(code) ||
          (result.status>=400 && result.status<500 && result.status!==408 && result.status!==429);
        failure=String(code).slice(0,100);
      } catch (e) { failure=errorText(e).slice(0,140); }
      if (invalid) {
        await admin.from(TABLE).update({enabled:false}).eq('id',row.subscription_id);
        disabled++;
      }
      const terminal=permanent || row.attempt_number>=5;
      await admin.from(DELIVERIES).update({
        status:terminal?'failed':'retry',last_error:failure,claimed_until:null,
        next_attempt_at:new Date(Date.now()+Math.min(900000,30000*2**Math.max(0,row.attempt_number-1))).toISOString(),
      }).eq('id',row.delivery_id).eq('claim_id',row.claim_uuid);
      retry++;
    }));
  }
  return {ok:true,claimed:rows.length,sent,retry,disabled};
}

export default {
  fetch: withSupabase({auth:'none'}, async (request, context) => {
    const origin=request.headers.get('origin');
    const headers=cors(origin);
    if (request.method==='OPTIONS') return new Response(null,{status:origin===ORIGIN?204:403,headers});
    if (request.method!=='POST') return json({ok:false,error:'method_not_allowed'},405,headers);
    const bodyText=await request.text();
    if (bodyText.length>8192) return json({ok:false,error:'payload_too_large'},413,headers);
    let body:Record<string,unknown>;
    try {body=JSON.parse(bodyText); if (!body || typeof body!=='object') throw new Error();}
    catch {return json({ok:false,error:'invalid_json'},400,headers);}
    const admin:any=context.supabaseAdmin;
    const action=body.action;
    if (action==='dispatch') {
      const expected=Deno.env.get('TUKTUK_PUSH_DISPATCH_SECRET') ?? '';
      const provided=request.headers.get(HEADER) ?? '';
      if (!await sameSecret(provided,expected)) return json({ok:false,error:'forbidden'},403,headers);
      try {return json(await dispatch(admin),200,headers);}
      catch (e) {return json({ok:false,error:'dispatch_unavailable',detail:errorText(e).slice(0,160)},503,headers);}
    }
    if (origin!==ORIGIN) return json({ok:false,error:'origin_forbidden'},403,headers);
    if (action!=='subscribe' && action!=='unsubscribe') return json({ok:false,error:'unknown_action'},400,headers);
    const token=body.token, secret=body.device_secret;
    if (typeof token!=='string' || !TOKEN_PATTERN.test(token) ||
        typeof secret!=='string' || !SECRET_PATTERN.test(secret)) {
      return json({ok:false,error:'invalid_subscription'},400,headers);
    }
    const tokenHash=await sha256(token), secretHash=await sha256(secret);
    try {
      if (action==='unsubscribe') {
        const {error}=await admin.from(TABLE).delete().eq('token_hash',tokenHash).eq('secret_hash',secretHash);
        if (error) throw error;
        return json({ok:true},200,headers);
      }
      const limiterKey = Deno.env.get('TUKTUK_PUSH_DISPATCH_SECRET') ?? '';
      const rawAddress = request.headers.get('cf-connecting-ip') ||
        request.headers.get('x-real-ip') ||
        (request.headers.get('x-forwarded-for') || '').split(',')[0].trim();
      if (!rawAddress || !limiterKey) {
        return json({ok:false,error:'registration_unavailable'},503,headers);
      }
      // The address is not stored: only a salted digest. Reverse-proxy headers
      // can still be forged unless verified by the hosting platform; WAF review
      // is a deployment prerequisite.
      const ipDigest=await sha256(`${limiterKey}:${rawAddress}`);
      const {data:allowed,error:rateError}=await admin.rpc(
        'marketplace_customer_eltoque_push_allow_signup',{ip_digest:ipDigest});
      if (rateError) throw rateError;
      if (allowed!==true) return json({ok:false,error:'too_many_requests'},429,headers);
      const {data:existing,error:lookupError}=await admin.from(TABLE)
        .select('id,secret_hash').eq('token_hash',tokenHash).maybeSingle();
      if (lookupError) throw lookupError;
      if (existing && existing.secret_hash!==secretHash)
        return json({ok:false,error:'token_registered_elsewhere'},409,headers);
      // One active FCM token per device-secret; supports Firebase token rotation.
      if (!existing) {
        const {error:removeError}=await admin.from(TABLE).delete()
          .eq('secret_hash',secretHash).neq('token_hash',tokenHash);
        if (removeError) throw removeError;
      }
      const dataToSave={token_hash:tokenHash,fcm_token:token,secret_hash:secretHash,enabled:true,
        updated_at:new Date().toISOString(),expires_at:new Date(Date.now()+180*86400000).toISOString()};
      const {error}=await admin.from(TABLE).upsert(dataToSave,{onConflict:'token_hash'});
      if (error) throw error;
      return json({ok:true},200,headers);
    } catch (_e) {
      return json({ok:false,error:'subscription_unavailable'},503,headers);
    }
  }),
};

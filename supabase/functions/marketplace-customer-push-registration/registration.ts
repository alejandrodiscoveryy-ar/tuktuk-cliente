// Registration only. No FCM sender, Firebase service account, claim RPC or dispatch.
const ORIGIN = "https://www.vrixora.com";
const TABLE = "marketplace_customer_eltoque_push_subscriptions";
const TOKEN_PATTERN = /^[a-zA-Z0-9_:\-.]{80,4096}$/;
const SECRET_PATTERN = /^[a-f0-9]{64}$/;
export type ProofVerdict = "valid" | "invalid" | "unavailable";

async function boundedBody(request: Request): Promise<string | null> {
  const reader = request.body?.getReader();
  if (!reader) return "";
  const chunks: Uint8Array[] = [];
  let size = 0;
  try {
    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      size += value.byteLength;
      if (size > 8192) { await reader.cancel(); return null; }
      chunks.push(value);
    }
  } finally { reader.releaseLock(); }
  const bytes = new Uint8Array(size);
  let offset = 0;
  for (const chunk of chunks) { bytes.set(chunk, offset); offset += chunk.byteLength; }
  return new TextDecoder().decode(bytes);
}

export async function sha256(value: string): Promise<string> {
  const hash = new Uint8Array(await crypto.subtle.digest("SHA-256", new TextEncoder().encode(value)));
  return [...hash].map(x => x.toString(16).padStart(2, "0")).join("");
}

function equalHash(a: string, b: string): boolean {
  let difference = a.length ^ b.length;
  for (let i = 0; i < Math.max(a.length, b.length); i++) difference |= (a.charCodeAt(i) || 0) ^ (b.charCodeAt(i) || 0);
  return difference === 0;
}

export async function verifyTurnstile(proof: string, secret: string, request: typeof fetch = fetch): Promise<ProofVerdict> {
  if (!secret) return "unavailable";
  try {
    const response = await request("https://challenges.cloudflare.com/turnstile/v0/siteverify", {
      method: "POST",
      headers: { "content-type": "application/x-www-form-urlencoded" },
      body: new URLSearchParams({ secret, response: proof }),
      signal: AbortSignal.timeout(8000),
    });
    if (!response.ok) return "unavailable";
    const verdict = await response.json();
    return verdict.success === true && verdict.hostname === "www.vrixora.com" &&
      verdict.action === "customer-rate-subscribe" ? "valid" : "invalid";
  } catch { return "unavailable"; }
}

// The admin client is supplied by the service-only Edge wrapper; never by a caller.
// deno-lint-ignore no-explicit-any
export async function handleRegistration(request: Request, admin: any, verifyProof: (proof: string) => Promise<ProofVerdict>): Promise<Response> {
  const origin = request.headers.get("origin");
  const headers: Record<string, string> = { "cache-control": "no-store", "vary": "Origin" };
  if (origin === ORIGIN) Object.assign(headers, {
    "access-control-allow-origin": ORIGIN,
    "access-control-allow-methods": "POST, OPTIONS",
    "access-control-allow-headers": "content-type, authorization, apikey, x-client-info",
  });
  const json = (body: unknown, status = 200) => Response.json(body, { status, headers });
  if (request.method === "OPTIONS") return new Response(null, { status: origin === ORIGIN ? 204 : 403, headers });
  if (request.method !== "POST") return json({ ok: false, error: "method_not_allowed" }, 405);
  // CORS is browser hygiene, not authorization: Turnstile or secret possession is required below.
  let text: string | null;
  try { text = await boundedBody(request); }
  catch { return json({ ok: false, error: "invalid_body" }, 400); }
  if (text === null) return json({ ok: false, error: "payload_too_large" }, 413);
  let body: Record<string, unknown>;
  try {
    body = JSON.parse(text);
    if (!body || typeof body !== "object" || Array.isArray(body)) throw new Error();
  } catch { return json({ ok: false, error: "invalid_json" }, 400); }
  if (body.action !== "subscribe" && body.action !== "unsubscribe") return json({ ok: false, error: "unknown_action" }, 400);
  if (typeof body.token !== "string" || !TOKEN_PATTERN.test(body.token) ||
    typeof body.device_secret !== "string" || !SECRET_PATTERN.test(body.device_secret)) {
    return json({ ok: false, error: "invalid_subscription" }, 400);
  }
  const tokenHash = await sha256(body.token);
  const secretHash = await sha256(body.device_secret);
  try {
    const { data: byToken, error: tokenError } = await admin.from(TABLE)
      .select("id,secret_hash,token_hash,enabled").eq("token_hash", tokenHash).maybeSingle();
    if (tokenError) throw tokenError;
    if (byToken && !equalHash(byToken.secret_hash, secretHash)) return json({ ok: false, error: "token_registered_elsewhere" }, 409);
    const { data: bySecret, error: secretError } = await admin.from(TABLE)
      .select("id,token_hash,enabled").eq("secret_hash", secretHash).maybeSingle();
    if (secretError) throw secretError;
    if (byToken && bySecret && byToken.id !== bySecret.id) return json({ ok: false, error: "subscription_conflict" }, 409);
    const knownDevice = byToken ?? bySecret;
    if (body.action === "unsubscribe") {
      // Token may have rotated before this request. Secret possession identifies the device;
      // a supplied token owned by another device is already rejected above.
      if (!knownDevice) return json({ ok: false, error: "subscription_not_found" }, 403);
      const { data, error } = await admin.from(TABLE).update({ enabled: false, updated_at: new Date().toISOString() })
        .eq("id", knownDevice.id).eq("secret_hash", secretHash).eq("token_hash", knownDevice.token_hash).select("id");
      if (error) throw error;
      if (!data?.length) return json({ ok: false, error: "subscription_conflict" }, 409);
      return json({ ok: true });
    }
    // A background renewal must never undo an explicit opt-out. Re-enabling
    // requires a new explicit subscribe request without renew_only.
    if (body.renew_only === true && (!knownDevice || !knownDevice.enabled)) {
      return json({ ok: false, error: "subscription_disabled" }, 403);
    }
    if (!knownDevice) {
      if (typeof body.turnstile_token !== "string" || body.turnstile_token.length < 10 || body.turnstile_token.length > 2048) {
        return json({ ok: false, error: "verification_required" }, 403);
      }
      const verdict = await verifyProof(body.turnstile_token);
      if (verdict !== "valid") return json({ ok: false, error: verdict === "unavailable" ? "verification_unavailable" : "verification_failed" }, verdict === "unavailable" ? 503 : 403);
    }
    const values = { token_hash: tokenHash, fcm_token: body.token, secret_hash: secretHash, enabled: true,
      updated_at: new Date().toISOString(), expires_at: new Date(Date.now() + 180 * 86400000).toISOString() };
    if (knownDevice) {
      const { data, error } = await admin.from(TABLE).update(values).eq("id", knownDevice.id)
        .eq("secret_hash", secretHash).eq("token_hash", knownDevice.token_hash)
        .eq("enabled", knownDevice.enabled).select("id");
      if (error) throw error;
      if (!data?.length) return json({ ok: false, error: "subscription_conflict" }, 409);
    } else {
      const { error } = await admin.from(TABLE).insert(values);
      if (error?.code === "23505") return json({ ok: false, error: "subscription_conflict" }, 409);
      if (error) throw error;
    }
    return json({ ok: true });
  } catch { return json({ ok: false, error: "subscription_unavailable" }, 503); }
}

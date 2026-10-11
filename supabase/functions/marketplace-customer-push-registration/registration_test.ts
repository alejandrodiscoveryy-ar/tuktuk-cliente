import { deepStrictEqual as equal, ok } from "node:assert/strict";
import { handleRegistration, sha256, verifyTurnstile, type ProofVerdict } from "./registration.ts";
import { FakeAdmin } from "./fake_admin_test_support.ts";
const TABLE = "marketplace_customer_eltoque_push_subscriptions";
const token = "a".repeat(100), secret = "b".repeat(64), proof = "synthetic-proof";
function request(values: Record<string, unknown>, headers: Record<string, string> = {}) {
  return new Request("http://localhost/registration", { method: "POST", headers, body: JSON.stringify({ action: "subscribe", token, device_secret: secret, ...values }) });
}
async function known() {
  const db = new FakeAdmin();
  db.tables[TABLE] = [{ id: "device-1", token_hash: await sha256(token), fcm_token: token, secret_hash: await sha256(secret), enabled: true }];
  return db;
}
Deno.test("registration: new device requires a verified challenge even with forged Origin/IP", async () => {
  const db = new FakeAdmin(); let checks = 0;
  const verify = () => { checks++; return Promise.resolve("valid" as ProofVerdict); };
  equal((await handleRegistration(request({}, { origin: "https://www.vrixora.com", "x-forwarded-for": "127.0.0.1" }), db, verify)).status, 403);
  equal(checks, 0); equal(db.tables[TABLE].length, 0);
  equal((await handleRegistration(request({ turnstile_token: proof }), db, verify)).status, 200);
  equal(checks, 1); equal(db.tables[TABLE].length, 1);
  ok(db.tables[TABLE][0].secret_hash !== secret);
});
for (const verdict of ["invalid", "unavailable"] as const) {
  Deno.test("registration: proof " + verdict + " cannot enroll", async () => {
    const db = new FakeAdmin();
    equal((await handleRegistration(request({ turnstile_token: proof }), db, () => Promise.resolve(verdict))).status, verdict === "invalid" ? 403 : 503);
    equal(db.tables[TABLE].length, 0);
  });
}
Deno.test("registration: Turnstile checks success, hostname, action and outage", async () => {
  const valid = { success: true, hostname: "www.vrixora.com", action: "customer-rate-subscribe" };
  for (const value of [valid, { ...valid, success: false }, { ...valid, hostname: "other.com" }, { ...valid, action: "other-action" }]) {
    const fetchMock: typeof fetch = () => Promise.resolve(Response.json(value));
    equal(await verifyTurnstile(proof, "synthetic-server-secret", fetchMock), value === valid ? "valid" : "invalid");
  }
  equal(await verifyTurnstile(proof, ""), "unavailable");
  equal(await verifyTurnstile(proof, "synthetic", () => Promise.reject(new Error("offline"))), "unavailable");
  equal(await verifyTurnstile(proof, "synthetic", () => Promise.resolve(new Response("", { status: 503 }))), "unavailable");
});
Deno.test("registration: renewal, token rotation and retry preserve device id without new challenge", async () => {
  const db = await known(); let checks = 0;
  const verify = () => { checks++; return Promise.resolve("invalid" as ProofVerdict); };
  for (const current of [token, "c".repeat(100), "c".repeat(100)]) {
    equal((await handleRegistration(request({ token: current }), db, verify)).status, 200);
    equal(db.tables[TABLE].length, 1); equal(db.tables[TABLE][0].id, "device-1");
  }
  equal(checks, 0);
});
Deno.test("registration: wrong secret or foreign token cannot subscribe/unsubscribe", async () => {
  for (const action of ["subscribe", "unsubscribe"]) {
    const db = await known();
    equal((await handleRegistration(request({ action, device_secret: "d".repeat(64) }), db, () => Promise.resolve("valid"))).status, 409);
    equal(db.tables[TABLE][0].enabled, true);
    equal((await handleRegistration(request({ action: "unsubscribe", token: "e".repeat(100), device_secret: "d".repeat(64) }), db, () => Promise.resolve("valid"))).status, 403);
  }
});
Deno.test("registration: unsubscribe is idempotent, preserves history, handles stale rotated token", async () => {
  const db = await known();
  const verify = () => Promise.resolve("invalid" as ProofVerdict);
  equal((await handleRegistration(request({ token: "c".repeat(100) }), db, verify)).status, 200);
  for (let i = 0; i < 2; i++) equal((await handleRegistration(request({ action: "unsubscribe" }), db, verify)).status, 200);
  equal(db.tables[TABLE].length, 1); equal(db.tables[TABLE][0].enabled, false);
});
Deno.test("registration: concurrent token rotation detects zero affected rows", async () => {
  const db = await known();
  db.beforeQuery = (_table, operation) => { if (operation === "update") db.tables[TABLE][0].token_hash = "changed"; };
  equal((await handleRegistration(request({ token: "c".repeat(100) }), db, () => Promise.resolve("valid"))).status, 409);
});
Deno.test("registration: database unavailable fails closed without exposing details", async () => {
  const db = await known(); db.failures.add(TABLE);
  const result = await handleRegistration(request({}), db, () => Promise.resolve("valid"));
  equal(result.status, 503); equal(await result.json(), { ok: false, error: "subscription_unavailable" });
});
Deno.test("registration: background renewal cannot reverse opt-out or win a revocation race", async () => {
  const db = await known(), verify = () => Promise.resolve("valid" as ProofVerdict);
  equal((await handleRegistration(request({ action: "unsubscribe" }), db, verify)).status, 200);
  equal((await handleRegistration(request({ renew_only: true }), db, verify)).status, 403);
  equal(db.tables[TABLE][0].enabled, false);
  equal((await handleRegistration(request({}), db, verify)).status, 200);
  db.beforeQuery = (_table, operation) => { if (operation === "update") db.tables[TABLE][0].enabled = false; };
  equal((await handleRegistration(request({ renew_only: true }), db, verify)).status, 409);
  equal(db.tables[TABLE][0].enabled, false);
});
Deno.test("registration: dispatch rejected even with dispatch secret header", async () => {
  const db = new FakeAdmin();
  equal((await handleRegistration(request({ action: "dispatch" }, { "x-tuktuk-dispatch-secret": "synthetic" }), db, () => Promise.resolve("valid"))).status, 400);
  equal(db.calls.length, 0);
});
Deno.test("registration: input bounds and HTTP/CORS handling", async () => {
  const db = new FakeAdmin(), verify = () => Promise.resolve("valid" as ProofVerdict);
  for (const values of [{ token: "short" }, { device_secret: "x".repeat(64) }]) equal((await handleRegistration(request(values), db, verify)).status, 400);
  equal((await handleRegistration(new Request("http://localhost/", { method: "GET" }), db, verify)).status, 405);
  equal((await handleRegistration(new Request("http://localhost/", { method: "OPTIONS", headers: { origin: "https://www.vrixora.com" } }), db, verify)).status, 204);
  equal((await handleRegistration(new Request("http://localhost/", { method: "POST", body: "x".repeat(8193) }), db, verify)).status, 413);
  equal((await handleRegistration(new Request("http://localhost/", { method: "POST", body: "[]" }), db, verify)).status, 400);
});

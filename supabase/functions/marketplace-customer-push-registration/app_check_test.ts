import { deepStrictEqual as equal } from "node:assert/strict";
import { verifyFirebaseAppCheck } from "./app_check.ts";

function b64u(bytes: Uint8Array): string {
  return btoa(String.fromCharCode(...bytes)).replaceAll("+", "-").replaceAll("/", "_").replaceAll("=", "");
}
function payload64(value: unknown): string {
  return b64u(new TextEncoder().encode(JSON.stringify(value)));
}
Deno.test("Android App Check validates RSA signature, audience, issuer, app subject and expiry", async () => {
  const keys = await crypto.subtle.generateKey(
    { name: "RSASSA-PKCS1-v1_5", modulusLength: 2048, publicExponent: new Uint8Array([1, 0, 1]), hash: "SHA-256" },
    true, ["sign", "verify"],
  );
  const publicJwk = await crypto.subtle.exportKey("jwk", keys.publicKey);
  const getJwks: typeof fetch = () => Promise.resolve(Response.json({ keys: [{ ...publicJwk, kid: "test-key", alg: "RS256", use: "sig" }] }));
  const now = Math.floor(Date.now() / 1000);
  const good = {
    iss: "https://firebaseappcheck.googleapis.com/835856456604",
    aud: ["projects/835856456604"],
    sub: "1:835856456604:android:49f0f8437cd4bffefec659",
    iat: now - 5,
    exp: now + 600,
  };
  const make = async (payload: object, header: object = { alg: "RS256", typ: "JWT", kid: "test-key" }) => {
    const message = `${payload64(header)}.${payload64(payload)}`;
    const signature = new Uint8Array(await crypto.subtle.sign("RSASSA-PKCS1-v1_5", keys.privateKey, new TextEncoder().encode(message)));
    return `${message}.${b64u(signature)}`;
  };
  equal(await verifyFirebaseAppCheck(await make(good), getJwks, now), "valid");
  equal(await verifyFirebaseAppCheck(await make({ ...good, sub: "1:835856456604:android:5c5e26856224e4cafec659" }), getJwks, now), "invalid");
  equal(await verifyFirebaseAppCheck(await make({ ...good, exp: now - 1 }), getJwks, now), "invalid");
  equal(await verifyFirebaseAppCheck(await make({ ...good, aud: ["projects/other"] }), getJwks, now), "invalid");
  equal(await verifyFirebaseAppCheck(await make({ ...good, iss: "https://example.com" }), getJwks, now), "invalid");
  equal(await verifyFirebaseAppCheck(await make(good, { alg: "none", typ: "JWT", kid: "test-key" }), getJwks, now), "invalid");
  const original = await make(good);
  const parts = original.split(".");
  parts[1] = payload64({ ...good, sub: "forged" });
  equal(await verifyFirebaseAppCheck(parts.join("."), getJwks, now), "invalid");
  equal(await verifyFirebaseAppCheck(original, () => Promise.reject(new Error("offline")), now), "unavailable");
});

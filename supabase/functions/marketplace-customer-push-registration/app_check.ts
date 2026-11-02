// Android-only enrollment proof. Never trust an unverified token, package name,
// Origin header or client-provided Firebase application identifier.
const FIREBASE_PROJECT_NUMBER = "835856456604";
const CLIENT_FIREBASE_APP_ID = "1:835856456604:android:49f0f8437cd4bffefec659";
const FIREBASE_APPCHECK_JWKS = "https://firebaseappcheck.googleapis.com/v1/jwks";
export type AppCheckVerdict = "valid" | "invalid" | "unavailable";

type Claims = {
  iss?: unknown;
  aud?: unknown;
  sub?: unknown;
  exp?: unknown;
  iat?: unknown;
  nbf?: unknown;
};
type Header = { alg?: unknown; typ?: unknown; kid?: unknown };

function decodeBase64Url(input: string): Uint8Array {
  if (!/^[A-Za-z0-9_-]+$/.test(input)) throw new Error("invalid base64url");
  const normalized = input.replaceAll("-", "+").replaceAll("_", "/");
  const decoded = atob(normalized.padEnd(Math.ceil(normalized.length / 4) * 4, "="));
  return Uint8Array.from(decoded, (char) => char.charCodeAt(0));
}

function decodeJSON<T>(segment: string): T {
  const decoded = new TextDecoder("utf-8", { fatal: true }).decode(decodeBase64Url(segment));
  return JSON.parse(decoded) as T;
}

/** A proof is valid only after RSA signature verification and strict claim checks. */
export async function verifyFirebaseAppCheck(
  token: string,
  fetcher: typeof fetch = fetch,
  now: number = Math.floor(Date.now() / 1000),
): Promise<AppCheckVerdict> {
  if (token.length < 100 || token.length > 7000) return "invalid";
  const parts = token.split(".");
  if (parts.length !== 3) return "invalid";
  let header: Header;
  let claims: Claims;
  let signature: Uint8Array;
  try {
    header = decodeJSON<Header>(parts[0]);
    claims = decodeJSON<Claims>(parts[1]);
    signature = decodeBase64Url(parts[2]);
  } catch {
    return "invalid";
  }
  if (!header || header.alg !== "RS256" || header.typ !== "JWT" ||
      typeof header.kid !== "string" || !header.kid ||
      !claims || claims.iss !== `https://firebaseappcheck.googleapis.com/${FIREBASE_PROJECT_NUMBER}` ||
      !Array.isArray(claims.aud) || !claims.aud.includes(`projects/${FIREBASE_PROJECT_NUMBER}`) ||
      claims.sub !== CLIENT_FIREBASE_APP_ID ||
      typeof claims.exp !== "number" || !Number.isSafeInteger(claims.exp) || claims.exp <= now ||
      typeof claims.iat !== "number" || !Number.isSafeInteger(claims.iat) || claims.iat > now + 60 ||
      (claims.nbf !== undefined && (typeof claims.nbf !== "number" || claims.nbf > now + 60))) {
    return "invalid";
  }
  let jwks: { keys?: JsonWebKey[] };
  try {
    const response = await fetcher(FIREBASE_APPCHECK_JWKS, {
      signal: AbortSignal.timeout(8000),
      headers: { accept: "application/json" },
    });
    if (!response.ok) return "unavailable";
    jwks = await response.json();
  } catch {
    return "unavailable";
  }
  const jwk = jwks?.keys?.find((key) => key.kid === header.kid && key.kty === "RSA" &&
    (key.alg === undefined || key.alg === "RS256") && key.use !== "enc");
  if (!jwk) return "invalid";
  try {
    const key = await crypto.subtle.importKey("jwk", jwk, {
      name: "RSASSA-PKCS1-v1_5", hash: "SHA-256",
    }, false, ["verify"]);
    const signedBytes = new TextEncoder().encode(`${parts[0]}.${parts[1]}`);
    const valid = await crypto.subtle.verify("RSASSA-PKCS1-v1_5", key, signature, signedBytes);
    return valid ? "valid" : "invalid";
  } catch {
    return "invalid";
  }
}

import { withSupabase } from "npm:@supabase/server@1.5.2";
import { handleRegistration, verifyTurnstile } from "./registration.ts";
import { verifyFirebaseAppCheck } from "./app_check.ts";

export default {
  fetch: withSupabase({ auth: "none" }, (request, context) => handleRegistration(
    request, context.supabaseAdmin,
    proof => verifyTurnstile(proof, Deno.env.get("TUKTUK_CUSTOMER_TURNSTILE_SECRET") ?? ""),
    verifyFirebaseAppCheck,
  )),
};

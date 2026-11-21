import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";
import { allowedOrigins, createSubmitHandler, headersFor } from "../_shared/error-report-submit-handler.mjs";

const url = Deno.env.get("SUPABASE_URL");
const key = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? Deno.env.get("SUPABASE_SECRET_KEY");
const handler = createSubmitHandler({
  submitReport: async (fields) => {
    if (!url || !key) throw new Error("Backend configuration unavailable");
    const db = createClient(url, key, { auth: { persistSession: false, autoRefreshToken: false } });
    const { data: allowed, error: limitError } = await db.rpc("atina_error_report_consume_global_limit", { p_limit: 50 });
    if (limitError) return { error: limitError };
    if (allowed !== true) return { limited: true };
    const { data, error } = await db.from("atina_error_reports").insert(fields).select("report_id,created_at").single();
    return { data, error };
  },
});

Deno.serve((req) => {
  const origin = req.headers.get("Origin") ?? "";
  if (allowedOrigins.has(origin) && (!url || !key)) {
    return new Response(JSON.stringify({ error: "Server configuration unavailable" }), {
      status: 503,
      headers: headersFor(req),
    });
  }
  return handler(req);
});

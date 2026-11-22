import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";
import { allowedOrigins, createSubmitHandler, headersFor } from "../_shared/error-report-submit-handler.mjs";
const url = Deno.env.get("SUPABASE_URL");
const key = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? Deno.env.get("SUPABASE_SECRET_KEY");
const handler = createSubmitHandler({
  submitReport: async (fields: { nickname: string; category: string; description: string; game_version: string | null; game_area: string | null; screenshot: { content_type: string; base64: string } | null }) => {
    if (!url || !key) throw new Error("Backend configuration unavailable");
    const db = createClient(url, key, { auth: { persistSession: false, autoRefreshToken: false } });
    const { data: allowed, error: limitError } = await db.rpc("atina_error_report_consume_global_limit", { p_limit: 50 });
    if (limitError) return { error: limitError };
    if (allowed !== true) return { limited: true };
    let screenshot_path: string | null = null;
    if (fields.screenshot) {
      const reportId = crypto.randomUUID(), ext = fields.screenshot.content_type === "image/png" ? "png" : fields.screenshot.content_type === "image/webp" ? "webp" : "jpg";
      screenshot_path = `${reportId}.${ext}`;
      const bytes = Uint8Array.from(atob(fields.screenshot.base64), c => c.charCodeAt(0));
      const { error: uploadError } = await db.storage.from("atina-error-report-screenshots").upload(screenshot_path, bytes, { contentType: fields.screenshot.content_type, upsert: false });
      if (uploadError) return { error: uploadError };
    }
    const { screenshot: _screenshot, ...reportFields } = fields;
    const { data, error } = await db.from("atina_error_reports").insert({ ...reportFields, screenshot_path }).select("report_id,created_at").single();
    if (error && screenshot_path) await db.storage.from("atina-error-report-screenshots").remove([screenshot_path]);
    return { data, error };
  },
});
Deno.serve((req) => { const origin = req.headers.get("Origin") ?? ""; if (allowedOrigins.has(origin) && (!url || !key)) return new Response(JSON.stringify({ error: "Server configuration unavailable" }), { status: 503, headers: headersFor(req) }); return handler(req); });

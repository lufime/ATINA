import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";

const allowedOrigins = new Set(["https://lufime.github.io", "http://localhost:5173"]);
const headersFor = (req: Request) => {
  const origin = req.headers.get("Origin") ?? "";
  return { ...(allowedOrigins.has(origin) ? { "Access-Control-Allow-Origin": origin } : {}), "Access-Control-Allow-Headers": "authorization, apikey, content-type", "Access-Control-Allow-Methods": "GET, PATCH, OPTIONS", "Vary": "Origin", "Content-Type": "application/json" };
};
const json = (req: Request, body: unknown, status = 200) => new Response(JSON.stringify(body), { status, headers: headersFor(req) });
const statuses = new Set(["new", "in_review", "fixing", "resolved", "archived"]);
const uuidPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

Deno.serve(async (req) => {
const origin = req.headers.get("Origin") ?? "";\n  if (!allowedOrigins.has(origin)) return json(req, { error: "Origin not allowed" }, 403);\n  if (req.method === "OPTIONS") return new Response("ok", { status: 204, headers: headersFor(req) });
  if (!["GET", "PATCH"].includes(req.method)) return json(req, { error: "Method not allowed" }, 405);
  const url = Deno.env.get("SUPABASE_URL");
  const key = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? Deno.env.get("SUPABASE_SECRET_KEY");
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
  if (!url || !key || !anonKey) return json(req, { error: "Server configuration unavailable" }, 503);
  const authHeader = req.headers.get("Authorization") ?? "";
  const token = authHeader.startsWith("Bearer ") ? authHeader.slice(7) : "";
  if (!token) return json(req, { error: "Unauthorized" }, 401);
  const authClient = createClient(url, anonKey, { auth: { persistSession: false, autoRefreshToken: false } });
  const { data: userData, error: authError } = await authClient.auth.getUser(token);
  if (authError || !userData.user) return json(req, { error: "Unauthorized" }, 401);
  const db = createClient(url, key, { auth: { persistSession: false, autoRefreshToken: false } });
  const { data: admin, error: adminError } = await db.from("atina_error_report_admins").select("user_id").eq("user_id", userData.user.id).maybeSingle();
  if (adminError) return json(req, { error: "Admin authorization check failed" }, 503);
  if (!admin) return json(req, { error: "Forbidden" }, 403);
  if (req.method === "GET") {
    const { data, error } = await db.from("atina_error_reports").select("report_id,nickname,category,description,game_version,game_area,status,internal_note,created_at,updated_at").order("created_at", { ascending: false }).limit(200);
    if (error) return json(req, { error: "Could not load reports" }, 500);
    return json(req, { reports: data ?? [] });
  }
  try {
    const body = await req.json();
    const reportId = typeof body.report_id === "string" ? body.report_id : "";
    if (!uuidPattern.test(reportId)) return json(req, { error: "Report ID inválido" }, 400);
    const update: Record<string, unknown> = { updated_at: new Date().toISOString() };
    if (typeof body.status === "string") {
      if (!statuses.has(body.status)) return json(req, { error: "Estado inválido" }, 400);
      update.status = body.status;
    }
    if (body.internal_note !== undefined) {
      if (typeof body.internal_note !== "string" || body.internal_note.length > 2000) return json(req, { error: "Nota inválida" }, 400);
      update.internal_note = body.internal_note.trim() || null;
    }
    if (Object.keys(update).length === 1) return json(req, { error: "No update fields supplied" }, 400);
    const { data, error } = await db.from("atina_error_reports").update(update).eq("report_id", reportId).select("report_id,status,internal_note,updated_at").single();
    if (error) return json(req, { error: "Could not update report" }, 500);
    return json(req, { report: data });
  } catch {
    return json(req, { error: "Invalid JSON" }, 400);
  }
});

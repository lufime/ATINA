import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";

const allowedOrigins = new Set(["https://lufime.github.io", "http://localhost:5173"]);
const headersFor = (req: Request) => {
  const origin = req.headers.get("Origin") ?? "";
  return { ...(allowedOrigins.has(origin) ? { "Access-Control-Allow-Origin": origin } : {}), "Access-Control-Allow-Headers": "authorization, apikey, content-type", "Access-Control-Allow-Methods": "POST, OPTIONS", "Vary": "Origin", "Content-Type": "application/json" };
};
const json = (req: Request, body: unknown, status = 200) => new Response(JSON.stringify(body), { status, headers: headersFor(req) });
const categories = new Set(["visual", "game", "points_xp", "technical", "other"]);
const clean = (value: unknown, max: number) => typeof value === "string" ? value.trim().slice(0, max) : "";

Deno.serve(async (req) => {
  const origin = req.headers.get("Origin") ?? "";
  // Reject browser origins outside the allowlist before processing a request.
  if (origin && !allowedOrigins.has(origin)) return json(req, { error: "Origin not allowed" }, 403);
  if (req.method === "OPTIONS") return new Response("ok", { headers: headersFor(req) });
  if (req.method !== "POST") return json(req, { error: "Method not allowed" }, 405);
  const url = Deno.env.get("SUPABASE_URL");
  const key = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? Deno.env.get("SUPABASE_SECRET_KEY");
  if (!url || !key) return json(req, { error: "Server configuration unavailable" }, 503);
  let body: Record<string, unknown>;
  try {
    const parsed = await req.json();
    if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) return json(req, { error: "Invalid JSON body" }, 400);
    body = parsed as Record<string, unknown>;
  } catch {
    return json(req, { error: "Invalid JSON" }, 400);
  }
  try {
    const nickname = clean(body.nickname, 40);
    const category = clean(body.category, 24);
    const description = clean(body.description, 2000);
    const gameVersion = clean(body.game_version, 40) || null;
    const gameArea = clean(body.game_area, 80) || null;
    if (!nickname) return json(req, { error: "Pseudónimo obrigatório" }, 400);
    if (!categories.has(category)) return json(req, { error: "Categoria inválida" }, 400);
    if (description.length < 20) return json(req, { error: "A descrição deve ter pelo menos 20 caracteres." }, 400);
    const db = createClient(url, key, { auth: { persistSession: false, autoRefreshToken: false } });
    const { data: allowed, error: limitError } = await db.rpc("atina_error_report_consume_global_limit", { p_limit: 50 });
    if (limitError) throw limitError;
    if (allowed !== true) return json(req, { error: "O limite temporário de reportes foi atingido. Tenta novamente mais tarde." }, 429);
    const { data, error } = await db.from("atina_error_reports").insert({
      nickname, category, description, game_version: gameVersion, game_area: gameArea,
    }).select("report_id,created_at").single();
    if (error) throw error;
    return json(req, { success: true, report_id: data.report_id, created_at: data.created_at });
  } catch (e) {
    return json(req, { error: "Não foi possível enviar o reporte. Tenta novamente." }, 500);
  }
});

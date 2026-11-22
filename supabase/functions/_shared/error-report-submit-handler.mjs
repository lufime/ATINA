// Shared HTTP handler for ATINA error-report submission (Deno + Node integration tests).
export const allowedOrigins = new Set(["https://lufime.github.io", "http://localhost:5173"]);
const categories = new Set(["visual", "game", "points_xp", "technical", "other"]);
const clean = (value, max) => typeof value === "string" ? value.trim().slice(0, max) : "";
export const headersFor = (req) => { const origin = req.headers.get("Origin") ?? ""; return { ...(allowedOrigins.has(origin) ? { "Access-Control-Allow-Origin": origin } : {}), "Access-Control-Allow-Headers": "authorization, apikey, content-type", "Access-Control-Allow-Methods": "POST, OPTIONS", "Vary": "Origin", "Content-Type": "application/json" }; };
const json = (req, body, status = 200) => new Response(JSON.stringify(body), { status, headers: headersFor(req) });
export function createSubmitHandler({ submitReport }) {
 return async (req) => {
  const origin = req.headers.get("Origin") ?? "";
  if (!allowedOrigins.has(origin)) return json(req, { error: "Origin not allowed" }, 403);
  if (req.method === "OPTIONS") return new Response("ok", { headers: headersFor(req) });
  if (req.method !== "POST") return json(req, { error: "Method not allowed" }, 405);
  let body; try { const parsed = await req.json(); if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) return json(req, { error: "Invalid JSON body" }, 400); body = parsed; } catch { return json(req, { error: "Invalid JSON" }, 400); }
  const nickname = clean(body.nickname, 40), category = clean(body.category, 24), description = clean(body.description, 2000), gameVersion = clean(body.game_version, 40) || null, gameArea = clean(body.game_area, 80) || null;
  const screenshot = body.screenshot && typeof body.screenshot === "object" ? body.screenshot : null, screenshotContentType = screenshot ? clean(screenshot.content_type, 40) : "", screenshotBase64 = screenshot ? clean(screenshot.base64, 4200000) : "";
  if (screenshot && (!["image/png","image/jpeg","image/webp"].includes(screenshotContentType) || !/^[A-Za-z0-9+/]*={0,2}$/.test(screenshotBase64) || screenshotBase64.length > 4194304)) return json(req, { error: "Screenshot inválida ou demasiado grande (máximo 3 MB)." }, 400);
  const screenshotBytes = screenshotBase64 ? Math.floor(screenshotBase64.length * 3 / 4) - (screenshotBase64.endsWith("==") ? 2 : screenshotBase64.endsWith("=") ? 1 : 0) : 0;
  if (screenshotBytes > 3145728) return json(req, { error: "Screenshot excede o limite de 3 MB." }, 400);
  if (!nickname) return json(req, { error: "Pseudónimo obrigatório" }, 400);
  if (!categories.has(category)) return json(req, { error: "Categoria inválida" }, 400);
  if (description.length < 20) return json(req, { error: "A descrição deve ter pelo menos 20 caracteres." }, 400);
  try {
   const result = await submitReport({ nickname, category, description, game_version: gameVersion, game_area: gameArea, screenshot: screenshotBase64 ? { content_type: screenshotContentType, base64: screenshotBase64 } : null });
   if (result?.limited) return json(req, { error: "O limite temporário de reportes foi atingido. Tenta novamente mais tarde." }, 429);
   if (result?.error || !result?.data) throw result?.error ?? new Error("Missing report data");
   return json(req, { success: true, report_id: result.data.report_id, created_at: result.data.created_at });
  } catch { return json(req, { error: "Não foi possível enviar o reporte. Tenta novamente." }, 500); }
 };
}

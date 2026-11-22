// HTTP contract handler for ATINA reports administration. Dependencies injected for offline tests.
export const allowedOrigins = new Set(["https://lufime.github.io", "http://localhost:5173"]);
const statuses = new Set(["new", "in_review", "fixing", "resolved", "archived"]);
const uuidPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const headersFor = (req) => { const origin = req.headers.get("Origin") ?? ""; return { ...(allowedOrigins.has(origin) ? { "Access-Control-Allow-Origin": origin } : {}), "Access-Control-Allow-Headers": "authorization, apikey, content-type", "Access-Control-Allow-Methods": "GET, PATCH, DELETE, OPTIONS", "Vary": "Origin", "Content-Type": "application/json" }; };
const json = (req, body, status = 200) => new Response(JSON.stringify(body), { status, headers: headersFor(req) });
export function createAdminHandler({ authenticate, isAdmin, listReports, updateReport, getReportForDelete, deleteReport, removeScreenshot, clearScreenshotPath, signedScreenshotUrl }) {
 return async (req) => {
  const origin = req.headers.get("Origin") ?? "";
  if (!allowedOrigins.has(origin)) return json(req, { error: "Origin not allowed" }, 403);
  if (req.method === "OPTIONS") return new Response(null, { status: 204, headers: headersFor(req) });
  if (!["GET", "PATCH", "DELETE"].includes(req.method)) return json(req, { error: "Method not allowed" }, 405);
  const authHeader = req.headers.get("Authorization") ?? "", token = authHeader.startsWith("Bearer ") ? authHeader.slice(7) : "";
  if (!token) return json(req, { error: "Unauthorized" }, 401);
  let user; try { user = await authenticate(token); } catch { return json(req, { error: "Unauthorized" }, 401); }
  if (!user) return json(req, { error: "Unauthorized" }, 401);
  let adminAllowed; try { adminAllowed = await isAdmin(user.id); } catch { return json(req, { error: "Admin authorization check failed" }, 503); }
  if (!adminAllowed) return json(req, { error: "Administrador não autorizado: a conta autenticada não está registada para gerir reports." }, 403);
  if (req.method === "GET") { try { const reports = (await listReports()) ?? []; const enriched = await Promise.all(reports.map(async report => { let screenshot_url = null, screenshot_error = false; if (report.screenshot_path) { try { screenshot_url = await signedScreenshotUrl(report.screenshot_path); } catch { screenshot_error = true; } } return { ...report, screenshot_url, ...(screenshot_error ? { screenshot_error: true } : {}) }; })); return json(req, { reports: enriched }); } catch { return json(req, { error: "Could not load reports" }, 500); } }
  if (req.method === "DELETE") {
   try {
    const body = await req.json();
    if (!body || typeof body !== "object" || Array.isArray(body)) return json(req, { error: "Invalid JSON body" }, 400);
    const reportId = typeof body.report_id === "string" ? body.report_id : "";
    if (!uuidPattern.test(reportId)) return json(req, { error: "Report ID inválido" }, 400);
    const existing = await getReportForDelete(reportId);
    if (!existing) return json(req, { error: "Report não encontrado" }, 404);
    let deleted;
    try { deleted = await deleteReport(reportId); }
    catch { return json(req, { error: "Não foi possível apagar o report. O report e a screenshot foram preservados." }, 503); }
    if (!deleted) return json(req, { error: "Report não encontrado ou já apagado." }, 404);
    let screenshot_cleanup_warning = false;
    if (existing.screenshot_path) {
     try { await removeScreenshot(existing.screenshot_path); }
     catch { screenshot_cleanup_warning = true; }
    }
    return json(req, { success: true, report_id: reportId, screenshot_cleanup_warning });
   } catch (error) { if (error instanceof SyntaxError) return json(req, { error: "Invalid JSON" }, 400); return json(req, { error: "Could not delete report" }, 500); }
  }
  try {
   const body = await req.json();
   if (!body || typeof body !== "object" || Array.isArray(body)) return json(req, { error: "Invalid JSON body" }, 400);
   const reportId = typeof body.report_id === "string" ? body.report_id : "";
   if (!uuidPattern.test(reportId)) return json(req, { error: "Report ID inválido" }, 400);
   const update = {};
   if (body.status !== undefined) { if (typeof body.status !== "string" || !statuses.has(body.status)) return json(req, { error: "Estado inválido" }, 400); update.status = body.status; }
   if (body.internal_note !== undefined) { if (typeof body.internal_note !== "string" || body.internal_note.length > 2000) return json(req, { error: "Nota inválida" }, 400); update.internal_note = body.internal_note.trim() || null; }
   if (!Object.keys(update).length) return json(req, { error: "No update fields supplied" }, 400);
   const report = await updateReport(reportId, update); if (!report) return json(req, { error: "Could not update report" }, 500);
   return json(req, { report });
  } catch (error) { if (error instanceof SyntaxError) return json(req, { error: "Invalid JSON" }, 400); return json(req, { error: "Could not update report" }, 500); }
 };
}

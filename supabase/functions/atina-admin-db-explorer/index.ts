import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? Deno.env.get("SUPABASE_SECRET_KEY");
const ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY");
const corsHeaders = {
  "Access-Control-Allow-Origin": "https://lufime.github.io",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Vary": "Origin",
};
const TABLES = {
  atina_points_ranking: { label: "Classificação", columns: ["id","nickname","score","mode","created_at","player_number"], key: "id", searchColumn: "nickname", orderColumn: "created_at", editable: ["nickname","score","mode","player_number"] },
  atina_site_notice: { label: "Avisos do site", columns: ["id","active","message","updated_at"], key: "id", searchColumn: "message", orderColumn: "updated_at", editable: ["active","message"] },
  atina_social_game_catalog: { label: "Catálogo de jogos sociais", columns: ["game_code","display_name","default_duration_seconds","supports_teams","active","created_at"], key: "game_code", searchColumn: "display_name", orderColumn: "created_at", editable: ["display_name","default_duration_seconds","supports_teams","active"] },
} as const;
type TableName = keyof typeof TABLES;
function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), { status, headers: { ...corsHeaders, "Content-Type": "application/json; charset=utf-8" } });
}
function validChanges(table: TableName, changes: unknown): changes is Record<string, unknown> {
  if (!changes || typeof changes !== "object" || Array.isArray(changes)) return false;
  const config = TABLES[table];
  const entries = Object.entries(changes as Record<string, unknown>);
  if (!entries.length || entries.some(([key]) => !(config.editable as readonly string[]).includes(key))) return false;
  for (const [key, value] of entries) {
    if (key === "active" || key === "supports_teams") { if (typeof value !== "boolean") return false; }
    else if (key === "score" || key === "player_number" || key === "default_duration_seconds") { if (!Number.isInteger(value)) return false; }
    else if (key === "nickname" || key === "mode" || key === "message" || key === "display_name") { if (typeof value !== "string" || value.length > 2000) return false; }
  }
  return true;
}
Deno.serve(async (request: Request) => {
  if (request.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (request.method !== "POST") return json({ error: "Método não permitido." }, 405);
  if (!SUPABASE_URL || !SERVICE_KEY || !ANON_KEY) return json({ error: "Configuração do serviço indisponível." }, 500);
  try {
    const authorization = request.headers.get("Authorization") ?? "";
    const token = authorization.startsWith("Bearer ") ? authorization.slice(7) : "";
    if (!token) return json({ error: "Autenticação necessária." }, 401);
    const authClient = createClient(SUPABASE_URL, ANON_KEY, { auth: { persistSession: false, autoRefreshToken: false } });
    const { data: authData, error: authError } = await authClient.auth.getUser(token);
    if (authError || !authData.user) return json({ error: "Sessão inválida." }, 401);
    const db = createClient(SUPABASE_URL, SERVICE_KEY, { auth: { persistSession: false, autoRefreshToken: false } });
    const { data: admin, error: adminError } = await db.from("atina_error_report_admins").select("user_id").eq("user_id", authData.user.id).maybeSingle();
    if (adminError) throw adminError;
    if (!admin) return json({ error: "Acesso reservado à administração." }, 403);
    const body = await request.json().catch(() => ({}));
    if (body.action === "tables") return json({ tables: Object.entries(TABLES).map(([name, config]) => ({ name, label: config.label, columns: config.columns, key: config.key, editable: config.editable })) });
    if (typeof body.table !== "string" || !Object.prototype.hasOwnProperty.call(TABLES, body.table)) return json({ error: "Tabela não autorizada." }, 400);
    const table = body.table as TableName;
    const config = TABLES[table];
    if (body.action === "rows") {
      const page = Number.isInteger(body.page) ? Math.max(0, Math.min(body.page, 100000)) : 0;
      const pageSize = 30;
      const search = typeof body.search === "string" ? body.search.trim().slice(0, 80) : "";
      let query = db.from(table).select(config.columns.join(","), { count: "exact" }).order(config.orderColumn, { ascending: false }).range(page * pageSize, page * pageSize + pageSize - 1);
      if (search) query = query.ilike(config.searchColumn, `%${search.replace(/[\\%_]/g, "")}%`);
      const { data, count, error } = await query;
      if (error) throw error;
      return json({ table, columns: config.columns, key: config.key, editable: config.editable, rows: data ?? [], total: count ?? 0, page, pageSize });
    }
    if (body.action === "update") {
      if (body.key === undefined || !validChanges(table, body.changes)) return json({ error: "Registo ou campos de edição inválidos." }, 400);
      const { data: before, error: readError } = await db.from(table).select(config.key).eq(config.key, body.key).maybeSingle();
      if (readError) throw readError;
      if (!before) return json({ error: "Registo não encontrado." }, 404);
      const { data: audit, error: auditError } = await db.from("atina_admin_db_explorer_audit").insert({ actor_user_id: authData.user.id, operation: "update", table_name: table, record_keys: [body.key], changed_columns: Object.keys(body.changes), outcome: "started" }).select("id").single();
      if (auditError) throw auditError;
      const { data, error } = await db.from(table).update(body.changes).eq(config.key, body.key).select(config.columns.join(",")).maybeSingle();
      await db.from("atina_admin_db_explorer_audit").update({ outcome: error ? "failed" : "completed", result_count: data ? 1 : 0 }).eq("id", audit.id);
      if (error) throw error;
      if (!data) return json({ error: "O registo não foi alterado." }, 409);
      return json({ row: data });
    }
    if (body.action === "delete") {
      const keys = Array.isArray(body.keys) ? [...new Set(body.keys.filter((key: unknown) => typeof key === "string" || typeof key === "number"))] : [];
      if (!keys.length || keys.length > 50 || keys.length !== body.keys.length) return json({ error: "Seleciona entre 1 e 50 registos válidos." }, 400);
      const { data: existing, error: readError } = await db.from(table).select(config.key).in(config.key, keys);
      if (readError) throw readError;
      if (!existing || existing.length !== keys.length) return json({ error: "Um ou mais registos já não existem. Atualiza a lista antes de apagar." }, 409);
      const { data: audit, error: auditError } = await db.from("atina_admin_db_explorer_audit").insert({ actor_user_id: authData.user.id, operation: "delete", table_name: table, record_keys: keys, changed_columns: [], outcome: "started" }).select("id").single();
      if (auditError) throw auditError;
      const { data, error } = await db.from(table).delete().in(config.key, keys).select(config.key);
      await db.from("atina_admin_db_explorer_audit").update({ outcome: error ? "failed" : "completed", result_count: data?.length ?? 0 }).eq("id", audit.id);
      if (error) throw error;
      return json({ deleted: data?.length ?? 0 });
    }
    return json({ error: "Operação não autorizada." }, 400);
  } catch (error) {
    console.error("[atina-admin-db-explorer]", error);
    return json({ error: "Não foi possível concluir a operação na base de dados." }, 500);
  }
});

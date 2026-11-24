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
  atina_points_ranking: {
    label: "Classificação",
    columns: ["id", "nickname", "score", "mode", "created_at", "player_number"],
    searchColumn: "nickname",
    orderColumn: "created_at",
  },
  atina_site_notice: {
    label: "Avisos do site",
    columns: ["id", "active", "message", "updated_at"],
    searchColumn: "message",
    orderColumn: "updated_at",
  },
  atina_social_game_catalog: {
    label: "Catálogo de jogos sociais",
    columns: ["game_code", "display_name", "default_duration_seconds", "supports_teams", "active", "created_at"],
    searchColumn: "display_name",
    orderColumn: "created_at",
  },
} as const;

type TableName = keyof typeof TABLES;

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json; charset=utf-8" },
  });
}

Deno.serve(async (request: Request) => {
  if (request.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (request.method !== "POST") return json({ error: "Método não permitido." }, 405);
  if (!SUPABASE_URL || !SERVICE_KEY || !ANON_KEY) return json({ error: "Configuração do serviço indisponível." }, 500);

  try {
    const authorization = request.headers.get("Authorization") ?? "";
    const token = authorization.startsWith("Bearer ") ? authorization.slice(7) : "";
    if (!token) return json({ error: "Autenticação necessária." }, 401);

    const authClient = createClient(SUPABASE_URL, ANON_KEY, {
      auth: { persistSession: false, autoRefreshToken: false },
    });
    const { data: authData, error: authError } = await authClient.auth.getUser(token);
    if (authError || !authData.user) return json({ error: "Sessão inválida." }, 401);

    const db = createClient(SUPABASE_URL, SERVICE_KEY, {
      auth: { persistSession: false, autoRefreshToken: false },
    });
    const { data: admin, error: adminError } = await db
      .from("atina_error_report_admins")
      .select("user_id")
      .eq("user_id", authData.user.id)
      .maybeSingle();
    if (adminError) throw adminError;
    if (!admin) return json({ error: "Acesso reservado à administração." }, 403);

    const body = await request.json().catch(() => ({}));
    if (body.action === "tables") {
      return json({
        tables: Object.entries(TABLES).map(([name, config]) => ({
          name,
          label: config.label,
          columns: config.columns,
        })),
      });
    }

    if (body.action !== "rows" || typeof body.table !== "string" || !Object.prototype.hasOwnProperty.call(TABLES, body.table)) {
      return json({ error: "Tabela ou operação não autorizada." }, 400);
    }

    const table = body.table as TableName;
    const config = TABLES[table];
    const page = Number.isInteger(body.page) ? Math.max(0, Math.min(body.page, 100000)) : 0;
    const pageSize = 30;
    const search = typeof body.search === "string" ? body.search.trim().slice(0, 80) : "";

    let query = db.from(table)
      .select(config.columns.join(","), { count: "exact" })
      .order(config.orderColumn, { ascending: false })
      .range(page * pageSize, page * pageSize + pageSize - 1);

    if (search) query = query.ilike(config.searchColumn, `%${search.replace(/[\\%_]/g, "")}%`);

    const { data, count, error } = await query;
    if (error) throw error;

    return json({
      table,
      columns: config.columns,
      rows: data ?? [],
      total: count ?? 0,
      page,
      pageSize,
    });
  } catch (error) {
    console.error("[atina-admin-db-explorer]", error);
    return json({ error: "Não foi possível consultar a base de dados." }, 500);
  }
});

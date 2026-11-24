import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const BUCKET = "atina-challenge-images";
const admin = createClient(SUPABASE_URL, SERVICE_ROLE_KEY, {
  auth: { autoRefreshToken: false, persistSession: false },
});
const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, apikey, x-client-info, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Vary": "Origin",
};
const reply = (value: unknown, status = 200) => new Response(JSON.stringify(value), {
  status,
  headers: { ...cors, "Content-Type": "application/json", "Cache-Control": "no-store" },
});

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return reply({ error: "Use POST." }, 405);

  const authorization = req.headers.get("Authorization") ?? "";
  const token = authorization.startsWith("Bearer ") ? authorization.slice(7) : "";
  if (!token) return reply({ error: "Authentication required." }, 401);

  const { data, error } = await admin.auth.getUser(token);
  if (error || !data.user) return reply({ error: "Invalid session." }, 401);
  const metadata = data.user.app_metadata ?? {};
  if (!(metadata.atina_admin === true || metadata.role === "admin")) {
    return reply({ error: "Administrator access required." }, 403);
  }

  try {
    const payload = await req.json().catch(() => ({}));
    if (payload?.action === "delete") {
      const path = typeof payload.storage_path === "string" ? payload.storage_path.trim() : "";
      const segments = path.split("/");
      if (!path || path.length > 1024 || path.startsWith("/") || path.includes("\\") ||
          segments.some((part: string) => !part || part === "." || part === "..")) {
        return reply({ error: "Caminho de imagem inválido." }, 400);
      }
      const { data: removed, error: removeError } = await admin.storage.from(BUCKET).remove([path]);
      if (removeError) throw removeError;
      if (!removed?.length) return reply({ error: "O ficheiro não foi encontrado ou não foi apagado." }, 404);
      return reply({ deleted: true, storage_path: path });
    }

    const bucket = admin.storage.from(BUCKET);
    const queue = [""];
    const visited = new Set<string>();
    const assets: Record<string, unknown>[] = [];
    let foldersVisited = 0;

    while (queue.length) {
      const folder = queue.shift()!;
      if (visited.has(folder)) continue;
      visited.add(folder);
      foldersVisited++;
      if (foldersVisited > 5000) throw new Error("Limite de pastas excedido.");

      let offset = 0;
      while (true) {
        const { data: entries, error: listError } = await bucket.list(folder, {
          limit: 1000,
          offset,
          sortBy: { column: "name", order: "asc" },
        });
        if (listError) throw listError;
        const page = entries ?? [];

        for (const item of page) {
          const path = folder ? folder + "/" + item.name : item.name;
          if (item.id === null) {
            if (!visited.has(path)) queue.push(path);
            continue;
          }

          const mime = String(item.metadata?.mimetype ?? "");
          const extension = item.name.match(/\.(png|jpe?g|webp|gif|avif|bmp|tiff?)$/i);
          if (!mime.startsWith("image/") && !extension) continue;

          const segments = path.split("/");
          const parentId = [...segments].reverse().find((part) => /^\d+$/.test(part));
          const filenameId = item.name.match(/^(\d+)[-_]/)?.[1] ?? null;
          const challengeId = parentId ?? filenameId;
          const isOriginal = /(^|\/)originals(\/|$)/i.test(path);
          const inferredMime = extension
            ? ({ png: "image/png", jpg: "image/jpeg", jpeg: "image/jpeg", webp: "image/webp", gif: "image/gif", avif: "image/avif", bmp: "image/bmp", tif: "image/tiff", tiff: "image/tiff" } as Record<string, string>)[extension[1].toLowerCase()]
            : "";
          const { data: publicData } = bucket.getPublicUrl(path);
          assets.push({
            asset_key: "storage:" + path,
            challenge_id: challengeId ? Number(challengeId) : null,
            image_url: publicData.publicUrl,
            storage_path: path,
            original_storage_path: isOriginal ? path : null,
            storage_paths: [path],
            original_storage_paths: isOriginal ? [path] : [],
            mime_type: mime || inferredMime || "application/octet-stream",
            file_size_bytes: Number(item.metadata?.size ?? 0),
            status: "stored",
            author: "ATINA",
            source: "Supabase Storage",
            stored_file_count: 1,
            updated_at: item.updated_at ?? item.created_at ?? null,
            created_at: item.created_at ?? null,
            file_name: item.name,
            is_original: isOriginal,
          });
        }

        if (page.length < 1000) break;
        offset += page.length;
      }
    }

    assets.sort((a, b) => String(a.storage_path).localeCompare(String(b.storage_path), "pt"));
    return reply({ assets, total: assets.length, folders_scanned: foldersVisited, bucket: BUCKET });
  } catch (err) {
    return reply({ error: err instanceof Error ? err.message : "Storage operation failed." }, 500);
  }
});

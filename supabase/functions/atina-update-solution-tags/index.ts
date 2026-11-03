import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });

async function authorized(req: Request) {
  const expected = Deno.env.get("ATINA_IMAGE_UPLOAD_TOKEN") ?? "";
  const supplied = req.headers.get("x-atina-upload-token") ?? "";
  if (!expected || supplied.length !== expected.length) return false;
  const [a, b] = await Promise.all([
    crypto.subtle.digest("SHA-256", new TextEncoder().encode(supplied)),
    crypto.subtle.digest("SHA-256", new TextEncoder().encode(expected)),
  ]);
  const aa = new Uint8Array(a), bb = new Uint8Array(b);
  let diff = 0;
  for (let i = 0; i < aa.length; i++) diff |= aa[i] ^ bb[i];
  return diff === 0;
}

Deno.serve(async (req) => {
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);
  if (!(await authorized(req))) return json({ error: "Unauthorized" }, 401);
  const apiKey = Deno.env.get("OPENAI_API_KEY");
  const url = Deno.env.get("SUPABASE_URL");
  const dbKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? Deno.env.get("SUPABASE_SECRET_KEY");
  if (!apiKey || !url || !dbKey) return json({ error: "Missing server configuration" }, 503);

  try {
    const body = await req.json().catch(() => ({}));
    const limit = Math.min(3, Math.max(1, Number.isInteger(body.limit) ? body.limit : 2));
    const after = Number.isInteger(body.after_challenge_id) ? body.after_challenge_id : -1;
    const supabase = createClient(url, dbKey, { auth: { persistSession: false, autoRefreshToken: false } });
    const { data: rows, error } = await supabase.schema("private").from("atina_challenges")
      .select("challenge_id,category,answer,difficulty,solution_tags,solution_description")
      .eq("active", true).gt("challenge_id", after).order("challenge_id").limit(limit);
    if (error) throw error;
    if (!rows?.length) return json({ success: true, processed: 0, done: true, next_after_challenge_id: after });

    const results = [];
    let cursor = after;
    for (const row of rows) {
      const prompt = `Cria uma descrição visual interna, em português europeu, da solução do desafio, para encontrar uma fotografia ou ilustração que corresponda realmente ao que a solução representa. A descrição deve identificar o objeto, pessoa, lugar ou conceito e explicar os seus elementos visuais reconhecíveis: forma, partes, materiais, cores, arquitetura, contexto e enquadramento. Sê concreta e específica, sem floreados, sem pistas do jogo e sem inventar detalhes incertos. Para conceitos abstratos, descreve uma representação visual reconhecível e não enganadora. Depois cria 6 a 12 etiquetas de pesquisa curtas, específicas e úteis, coerentes com a descrição. Não uses a descrição nem as etiquetas como variantes da resposta; são apenas metadados internos para pesquisa de imagens. Responde exclusivamente em JSON: {"description":"...","tags":["..."]}.\nCategoria: ${row.category}\nSolução oficial: ${row.answer}\nDificuldade: ${row.difficulty ?? "geral"}\nDescrição anterior (se existir, melhora-a e mantém o sentido): ${row.solution_description ?? ""}\nEtiquetas existentes (não repetir): ${JSON.stringify(row.solution_tags ?? [])}`;
      const response = await fetch("https://api.openai.com/v1/chat/completions", {
        method: "POST",
        headers: { Authorization: `Bearer ${apiKey}`, "Content-Type": "application/json" },
        body: JSON.stringify({
          model: "gpt-4.1-mini", temperature: 0.2, response_format: { type: "json_object" },
          messages: [
            { role: "system", content: "Responde apenas com JSON válido. Escreve etiquetas em português europeu." },
            { role: "user", content: prompt },
          ],
        }),
      });
      const generatedBody = await response.json().catch(() => ({}));
      if (!response.ok) throw new Error(generatedBody?.error?.message ?? `OpenAI HTTP ${response.status}`);
      let additions: unknown;
      try { additions = JSON.parse(generatedBody?.choices?.[0]?.message?.content ?? "{}").tags; } catch { additions = null; }
      if (!Array.isArray(additions) || additions.some((tag) => typeof tag !== "string")) throw new Error("Resposta de etiquetas inválida");

      const existing = Array.isArray(row.solution_tags) ? row.solution_tags.filter((x) => typeof x === "string") : [];
      const seen = new Set(existing.map((x) => x.trim().toLocaleLowerCase("pt-PT")));
      const unique = additions.map((x) => x.trim()).filter((x) => x.length > 1 && x.length <= 100)
        .filter((x) => { const k = x.toLocaleLowerCase("pt-PT"); if (seen.has(k)) return false; seen.add(k); return true; });
      const { error: updateError } = await supabase.schema("private").from("atina_challenges")
        .update({ solution_description: description, solution_tags: [...existing, ...unique] }).eq("challenge_id", row.challenge_id).eq("active", true);
      if (updateError) throw updateError;
      cursor = row.challenge_id;
      results.push({ challenge_id: row.challenge_id, success: true, description_updated: true, added: unique.length });
    }
    const processed = results.length;
    return json({ success: true, processed, results, next_after_challenge_id: cursor, done: rows.length < limit });
  } catch (e) {
    return json({ error: e instanceof Error ? e.message : "Update failed" }, 500);
  }
});
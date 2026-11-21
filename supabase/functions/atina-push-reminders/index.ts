import webpush from "npm:web-push@3.6.7";
import { buildReminderPayload, endpointHost } from "./helpers.ts";

const corsHeaders = { "Access-Control-Allow-Origin": "*", "Access-Control-Allow-Headers": "authorization, apikey, content-type", "Access-Control-Allow-Methods": "POST, OPTIONS" };
const json = (body: unknown, status = 200) => new Response(JSON.stringify(body), { status, headers: { ...corsHeaders, "Content-Type": "application/json" } });
const env = (name: string) => Deno.env.get(name) ?? "";
const url = env("SUPABASE_URL");
const serviceKey = env("SUPABASE_SERVICE_ROLE_KEY");
const cronSecret = env("CRON_SECRET");
const publicKey = env("VAPID_PUBLIC_KEY");
const privateKey = env("VAPID_PRIVATE_KEY");
const subject = env("VAPID_SUBJECT");

function ready() {
  return Boolean(url && serviceKey && cronSecret && publicKey && privateKey && subject);
}
async function rest(path: string, init: RequestInit = {}) {
  const response = await fetch(url + path, { ...init, headers: { apikey: serviceKey, Authorization: "Bearer " + serviceKey, "Content-Type": "application/json", ...(init.headers || {}) } });
  const text = await response.text();
  if (!response.ok) throw new Error("Supabase REST error " + response.status + ": " + text.slice(0, 500));
  return text ? JSON.parse(text) : null;
}
async function markSent(id: string) {
  await rest("/rest/v1/atina_push_subscriptions?id=eq." + encodeURIComponent(id), { method: "PATCH", headers: { Prefer: "return=minimal" }, body: JSON.stringify({ last_reminded_at: new Date().toISOString() }) });
}
async function removeSubscription(id: string) {
  await rest("/rest/v1/atina_push_subscriptions?id=eq." + encodeURIComponent(id), { method: "DELETE", headers: { Prefer: "return=minimal" } });
}
async function claimBatch(limit = 100) {
  return await rest("/rest/v1/rpc/atina_push_reminders_claim", { method: "POST", body: JSON.stringify({ p_limit: limit }) }) as Array<{ id: string; subscription: Record<string, unknown> }>;
}
Deno.serve(async (request) => {
  if (request.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (request.method !== "POST") return json({ error: "Method not allowed" }, 405);
  if (!ready()) return json({ error: "Push sender is not configured." }, 503);
  const authorization = request.headers.get("authorization") ?? "";
  if (authorization !== "Bearer " + cronSecret) return json({ error: "Unauthorized" }, 401);

  webpush.setVapidDetails(subject, publicKey, privateKey);
  let claimed: Array<{ id: string; subscription: Record<string, unknown> }>;
  try { claimed = await claimBatch(100); } catch (error) { return json({ error: "Could not claim reminder batch", detail: String(error) }, 500); }

  const payload = JSON.stringify(buildReminderPayload(env("ATINA_PUBLIC_URL") || "https://atina.lufime.pt/"));
  let sent = 0, expired = 0, failed = 0, invalid = 0;
  for (const item of claimed) {
    const host = endpointHost(item.subscription);
    if (!host) { invalid++; continue; }
    try {
      await webpush.sendNotification(item.subscription as Parameters<typeof webpush.sendNotification>[0], payload, { TTL: 86400, urgency: "normal" });
      await markSent(item.id);
      sent++;
    } catch (error) {
      const statusCode = Number((error as { statusCode?: number })?.statusCode || 0);
      if (statusCode === 404 || statusCode === 410) {
        await removeSubscription(item.id).catch(() => {});
        expired++;
      } else {
        failed++;
        console.error("Push send failed for endpoint host", host, "status", statusCode);
      }
    }
  }
  return json({ ok: true, claimed: claimed.length, sent, expired, failed, invalid });
});

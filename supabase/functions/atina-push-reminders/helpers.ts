// Shared reminder eligibility helpers. Pure functions, easy to unit-test.
export const INACTIVITY_MS = 48 * 60 * 60 * 1000;
export const REMINDER_COOLDOWN_MS = 7 * 24 * 60 * 60 * 1000;
export const CLAIM_COOLDOWN_MS = 15 * 60 * 1000;

export function isReminderDue(row: Record<string, unknown>, nowMs: number): boolean {
  const activity = Date.parse(String(row.last_activity_at ?? ""));
  if (!Number.isFinite(activity) || nowMs - activity < INACTIVITY_MS) return false;
  const lastSent = row.last_reminded_at ? Date.parse(String(row.last_reminded_at)) : NaN;
  if (Number.isFinite(lastSent) && nowMs - lastSent < REMINDER_COOLDOWN_MS) return false;
  const lastAttempt = row.last_attempt_at ? Date.parse(String(row.last_attempt_at)) : NaN;
  if (Number.isFinite(lastAttempt) && nowMs - lastAttempt < CLAIM_COOLDOWN_MS) return false;
  return true;
}

export function buildReminderPayload(baseUrl: string) {
  return {
    title: "O ATINA tem novos desafios!",
    body: "Há algum tempo que não jogas. Volta quando te apetecer pôr a mente à prova.",
    url: baseUrl,
  };
}

const PUSH_HOST_SUFFIXES = [".fcm.googleapis.com", ".push.services.mozilla.com"];
const PUSH_EXACT_HOSTS = ["fcm.googleapis.com", "web.push.apple.com", "notify.windows.com", "wns.windows.com"];

export function endpointHost(subscription: unknown): string | null {
  if (!subscription || typeof subscription !== "object") return null;
  const endpoint = (subscription as { endpoint?: unknown }).endpoint;
  if (typeof endpoint !== "string" || endpoint.length > 2048) return null;
  try {
    const parsed = new URL(endpoint);
    if (parsed.protocol !== "https:" || parsed.username || parsed.password || (parsed.port && parsed.port !== "443")) return null;
    const host = parsed.hostname.toLowerCase();
    if (PUSH_EXACT_HOSTS.includes(host) || PUSH_HOST_SUFFIXES.some(suffix => host.endsWith(suffix))) return host;
    return null;
  } catch {
    return null;
  }
}

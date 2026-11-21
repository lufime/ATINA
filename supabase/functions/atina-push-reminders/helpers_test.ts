import { buildReminderPayload, endpointHost, isValidPushEndpoint, isReminderDue, INACTIVITY_MS, REMINDER_COOLDOWN_MS, CLAIM_COOLDOWN_MS } from "./helpers.ts";

Deno.test("sends only after 48h inactivity", () => {
  const now = Date.parse("2026-11-21T12:00:00Z");
  const row: Record<string, unknown> = { last_activity_at: new Date(now - INACTIVITY_MS).toISOString() };
  if (!isReminderDue(row, now)) throw new Error("exactly 48h should be due");
  row.last_activity_at = new Date(now - INACTIVITY_MS + 1).toISOString();
  if (isReminderDue(row, now)) throw new Error("under 48h must not be due");
});

Deno.test("cooldown suppresses repeat reminders for 7 days", () => {
  const now = Date.now();
  const row: Record<string, unknown> = { last_activity_at: new Date(now - INACTIVITY_MS * 2).toISOString(), last_reminded_at: new Date(now - REMINDER_COOLDOWN_MS + 1000).toISOString() };
  if (isReminderDue(row, now)) throw new Error("cooldown must suppress reminder");
  row.last_reminded_at = new Date(now - REMINDER_COOLDOWN_MS - 1).toISOString();
  if (!isReminderDue(row, now)) throw new Error("after cooldown reminder should be due");
});

Deno.test("claim cooldown suppresses repeated attempts for 15 minutes", () => {
  const now = Date.now();
  const row: Record<string, unknown> = { last_activity_at: new Date(now - INACTIVITY_MS * 2).toISOString(), last_attempt_at: new Date(now - CLAIM_COOLDOWN_MS + 1000).toISOString() };
  if (isReminderDue(row, now)) throw new Error("recent claim should suppress");
});

Deno.test("payload includes ATINA destination", () => {
  const payload = buildReminderPayload("https://atina.lufime.pt/");
  if (payload.url !== "https://atina.lufime.pt/" || !payload.title || !payload.body) throw new Error("payload incomplete");
});

Deno.test("invalid endpoints are distinguished from valid unsupported providers", () => {
  if (isValidPushEndpoint({ endpoint: "http://invalid.test" })) throw new Error("http endpoint must be invalid");
  if (isValidPushEndpoint({ endpoint: "not a url" })) throw new Error("malformed endpoint must be invalid");
  if (isValidPushEndpoint({ endpoint: "https://fcm.googleapis.com:8443/id" })) throw new Error("nonstandard port must be invalid");
  if (!isValidPushEndpoint({ endpoint: "https://unknown-push.example/id" })) throw new Error("valid unsupported endpoint must be retained");
  if (endpointHost({ endpoint: "https://unknown-push.example/id" }) !== null) throw new Error("unsupported host must not be sent");
  if (endpointHost({ endpoint: "https://fcm.googleapis.com:443/id" }) !== "fcm.googleapis.com") throw new Error("explicit default port accepted");
  if (endpointHost({ endpoint: "https://fcm.googleapis.com/id" }) !== "fcm.googleapis.com") throw new Error("valid Google endpoint accepted");
  if (endpointHost({ endpoint: "https://foo.push.services.mozilla.com/abc" }) !== "foo.push.services.mozilla.com") throw new Error("valid Mozilla subdomain accepted");
  if (endpointHost({ endpoint: "https://push.services.mozilla.com/wpush/v2/abc" }) !== "push.services.mozilla.com") throw new Error("standard Mozilla endpoint accepted");
});

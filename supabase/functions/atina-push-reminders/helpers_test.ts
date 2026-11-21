import { buildReminderPayload, endpointHost, isReminderDue, INACTIVITY_MS, REMINDER_COOLDOWN_MS, CLAIM_COOLDOWN_MS } from "./helpers.ts";

Deno.test("sends only after 48h inactivity", () => {
  const now = Date.parse("2026-11-21T12:00:00Z");
  const row = { last_activity_at: new Date(now - INACTIVITY_MS).toISOString() };
  if (!isReminderDue(row, now)) throw new Error("exactly 48h should be due");
  row.last_activity_at = new Date(now - INACTIVITY_MS + 1).toISOString();
  if (isReminderDue(row, now)) throw new Error("under 48h must not be due");
});

Deno.test("cooldown suppresses repeat reminders for 7 days", () => {
  const now = Date.now();
  const row = { last_activity_at: new Date(now - INACTIVITY_MS * 2).toISOString(), last_reminded_at: new Date(now - REMINDER_COOLDOWN_MS + 1000).toISOString() };
  if (isReminderDue(row, now)) throw new Error("cooldown must suppress reminder");
  row.last_reminded_at = new Date(now - REMINDER_COOLDOWN_MS - 1).toISOString();
  if (!isReminderDue(row, now)) throw new Error("after cooldown reminder should be due");
});

Deno.test("claim cooldown suppresses parallel/retry attempt", () => {
  const now = Date.now();
  const row = { last_activity_at: new Date(now - INACTIVITY_MS * 2).toISOString(), last_attempt_at: new Date(now - CLAIM_COOLDOWN_MS + 1000).toISOString() };
  if (isReminderDue(row, now)) throw new Error("recent claim should suppress");
});

Deno.test("payload directs notification to ATINA", () => {
  const payload = buildReminderPayload("https://atina.example/");
  if (payload.url !== "https://atina.example/" || !payload.title || !payload.body) throw new Error("payload incomplete");
});

Deno.test("rejects non-https and malformed push endpoints", () => {
  if (endpointHost({ endpoint: "http://invalid.test" }) !== null) throw new Error("http endpoint must be rejected");
  if (endpointHost({ endpoint: "not a url" }) !== null) throw new Error("malformed endpoint must be rejected");
  if (endpointHost({ endpoint: "https://push.example/sub/1" }) !== "push.example") throw new Error("valid endpoint host mismatch");
});

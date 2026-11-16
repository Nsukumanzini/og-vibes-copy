import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";

const json = (body: unknown, status = 200) => new Response(JSON.stringify(body), {
  status,
  headers: { "Content-Type": "application/json" },
});

const normalizedEvents: Record<string, string> = {
  request: "sent",
  sent: "sent",
  delivered: "delivered",
  opened: "opened",
  uniqueopened: "unique_opened",
  unique_opened: "unique_opened",
  click: "click",
  clicked: "click",
  deferred: "deferred",
  softbounce: "soft_bounce",
  soft_bounce: "soft_bounce",
  hardbounce: "hard_bounce",
  hard_bounce: "hard_bounce",
  blocked: "blocked",
  spam: "spam",
  complaint: "spam",
  invalid: "invalid",
  invalidemail: "invalid",
  error: "error",
  unsubscribed: "unsubscribed",
  proxyopen: "proxy_open",
  proxy_open: "proxy_open",
};

const text = (value: unknown, max = 500) =>
  typeof value === "string" ? value.trim().slice(0, max) : null;

const eventTime = (event: Record<string, unknown>) => {
  const epoch = Number(event.ts_event ?? event.ts ?? 0);
  const parsed = epoch > 0 ? new Date(epoch * 1000) : new Date();
  return Number.isNaN(parsed.valueOf()) ? new Date().toISOString() : parsed.toISOString();
};

const secureEquals = (actual: string, expected: string) => {
  if (actual.length !== expected.length) return false;
  let difference = 0;
  for (let index = 0; index < actual.length; index += 1) {
    difference |= actual.charCodeAt(index) ^ expected.charCodeAt(index);
  }
  return difference === 0;
};

Deno.serve(async (request) => {
  if (request.method !== "POST") return json({ error: "Method not allowed" }, 405);

  const expectedSecret = Deno.env.get("BREVO_WEBHOOK_SECRET") ?? "";
  const authorization = request.headers.get("authorization") ?? "";
  const suppliedSecret = authorization.toLowerCase().startsWith("bearer ")
    ? authorization.slice(7).trim()
    : request.headers.get("x-og-webhook-secret") ?? "";
  if (!expectedSecret || !secureEquals(suppliedSecret, expectedSecret)) {
    return json({ error: "Unauthorized" }, 401);
  }

  const contentLength = Number(request.headers.get("content-length") ?? 0);
  if (contentLength > 131_072) return json({ error: "Payload too large" }, 413);

  try {
    const payload = await request.json();
    const events = (Array.isArray(payload) ? payload : [payload])
      .filter((item): item is Record<string, unknown> => Boolean(item) && typeof item === "object")
      .slice(0, 100);
    const rows = events.flatMap((event) => {
      const rawEvent = String(event.event ?? "").trim();
      const normalizedKey = rawEvent.replaceAll(/[-\s]/g, "").toLowerCase();
      const eventType = normalizedEvents[rawEvent] ?? normalizedEvents[normalizedKey];
      if (!eventType) return [];
      const email = text(event.email, 320);
      const messageId = text(event["message-id"] ?? event.message_id, 500);
      const providerEventId = String(event.id ?? "").slice(0, 120) || null;
      const occurredAt = eventTime(event);
      const eventKey = [providerEventId, messageId, email, eventType, occurredAt].filter(Boolean).join(":");
      return [{
        event_key: eventKey,
        message_id: messageId,
        event_type: eventType,
        recipient_email: email,
        recipient_domain: email?.includes("@") ? email.split("@").at(-1)?.toLowerCase() : null,
        subject: text(event.subject, 500),
        reason: text(event.reason ?? event.description, 1000),
        provider_event_id: providerEventId,
        occurred_at: occurredAt,
        metadata: {
          template_id: event.template_id ?? null,
          tags: Array.isArray(event.tags) ? event.tags.slice(0, 20) : [],
          sending_ip: text(event.sending_ip, 80),
        },
      }];
    });

    if (!rows.length) return json({ received: events.length, recorded: 0 });
    const admin = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
      { auth: { persistSession: false } },
    );
    const { error } = await admin.from("email_delivery_events").upsert(rows, {
      onConflict: "event_key",
      ignoreDuplicates: true,
    });
    if (error) throw error;
    return json({ received: events.length, recorded: rows.length });
  } catch (error) {
    console.error("brevo-webhook", error);
    return json({ error: "Unable to record delivery event" }, 500);
  }
});

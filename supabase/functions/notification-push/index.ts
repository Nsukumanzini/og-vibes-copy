import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2.57.4";
import { JWT } from "npm:google-auth-library@9.15.1";

const jsonHeaders = { "Content-Type": "application/json" };

function response(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), { status, headers: jsonHeaders });
}

async function firebaseCredentials() {
  const encoded = Deno.env.get("FIREBASE_SERVICE_ACCOUNT_JSON_BASE64");
  if (!encoded) throw new Error("Firebase service account is not configured");
  const bytes = Uint8Array.from(atob(encoded), (character) => character.charCodeAt(0));
  const account = JSON.parse(new TextDecoder().decode(bytes));
  const client = new JWT({
    email: account.client_email,
    key: account.private_key,
    scopes: ["https://www.googleapis.com/auth/firebase.messaging"],
  });
  const credentials = await client.authorize();
  if (!credentials.access_token) throw new Error("Unable to authorize Firebase messaging");
  return { token: credentials.access_token, projectId: account.project_id as string };
}

function cleanData(input: Record<string, unknown>) {
  return Object.fromEntries(
    Object.entries(input).map(([key, value]) => [key, value == null ? "" : String(value)]),
  );
}

const templates: Record<string, { title: string; body: string }> = {
  messages: { title: "New private message", body: "Open OG Vibes to read your new message." },
  group_chats: { title: "New group message", body: "A group you joined has new activity." },
  alerts: { title: "Campus update", body: "A new campus notice is available in Alerts." },
  quizzes: { title: "New quiz available", body: "A quiz was published for one of your modules." },
  assessments: { title: "New assessment available", body: "An assessment was published for one of your modules." },
  online_classes: { title: "Online class scheduled", body: "A new online class was scheduled for your module." },
  icass: { title: "New ICASS mark", body: "A new mark is available. Open OG Vibes to view it." },
  friends: { title: "New friend request", body: "A student wants to connect with you." },
  events: { title: "Campus event update", body: "You have a new campus event update." },
  marketplace: { title: "Marketplace update", body: "One of your marketplace orders has new activity." },
  lost_found: { title: "Lost and found update", body: "One of your reports or claims has new activity." },
  feed: { title: "New post activity", body: "Someone interacted with your post." },
  career: { title: "Career application updated", body: "One of your career applications has a new status." },
};

Deno.serve(async (request: Request) => {
  if (request.method !== "POST") return response({ error: "Method not allowed" }, 405);

  const url = Deno.env.get("SUPABASE_URL")!;
  const serviceRole = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
  const admin = createClient(url, serviceRole, { auth: { persistSession: false } });

  const suppliedSecret = request.headers.get("x-og-notification-secret");
  const { data: config } = await admin
    .from("notification_webhook_config")
    .select("secret")
    .eq("singleton", true)
    .maybeSingle();
  if (!suppliedSecret || !config?.secret || suppliedSecret !== config.secret) {
    return response({ error: "Invalid webhook signature" }, 401);
  }

  let notificationId: string | null = null;
  try {
    const body = await request.json();
    notificationId = typeof body.notification_id === "string" ? body.notification_id : null;
  } catch {
    return response({ error: "Invalid JSON body" }, 400);
  }
  if (!notificationId) return response({ error: "Missing notification identifier" }, 400);

  const { data: notification, error: claimError } = await admin
    .from("student_notifications")
    .update({ delivery_status: "processing", delivery_error: null })
    .eq("id", notificationId)
    .eq("delivery_status", "pending")
    .select("id,user_id,category,title,body,route,entity_id,metadata")
    .maybeSingle();
  if (claimError) return response({ error: "Unable to claim notification" }, 500);
  if (!notification) return response({ duplicate: true });

  const routeAliases: Record<string, string> = {
    home: "feed",
    quiz: "quizzes",
  };
  const templateRoute = routeAliases[notification.route] ?? notification.route;
  const categoryFallbacks: Record<string, string> = {
    messages: "messages",
    academics: "assessments",
    campus: "alerts",
    social: "feed",
    marketplace: "marketplace",
  };
  const template = templates[templateRoute]
    ?? templates[categoryFallbacks[notification.category]]
    ?? { title: "OG Vibes update", body: "Open OG Vibes to view this update." };

  const finish = async (deliveryStatus: string, error?: string) => {
    await admin.from("student_notifications").update({
      delivery_status: deliveryStatus,
      delivery_error: error?.slice(0, 500) ?? null,
      pushed_at: new Date().toISOString(),
    }).eq("id", notification.id);
    if (deliveryStatus === "failed") {
      await admin.from("system_health_events").insert({
        source: "notification-push",
        event_type: "edge_function_failure",
        severity: "error",
        outcome: "failed",
        user_id: notification.user_id,
        message: (error || "Notification delivery failed").slice(0, 1000),
        metadata: { notification_id: notification.id, category: notification.category },
      });
    }
  };

  const { data: preferences } = await admin
    .from("notification_preferences")
    .select("messages,academics,campus,social,marketplace")
    .eq("user_id", notification.user_id)
    .maybeSingle();
  if (preferences && preferences[notification.category as keyof typeof preferences] === false) {
    await finish("suppressed");
    return response({ suppressed: true });
  }

  const { data: registrations, error: tokenError } = await admin
    .from("device_push_tokens")
    .select("id,token,platform")
    .eq("user_id", notification.user_id)
    .gte("last_seen_at", new Date(Date.now() - 1000 * 60 * 60 * 24 * 90).toISOString());
  if (tokenError) {
    await finish("failed", "Unable to load device registrations");
    return response({ error: "Unable to load device registrations" }, 500);
  }
  if (!registrations?.length) {
    await finish("no_devices");
    return response({ sent: 0, failed: 0 });
  }

  let credentials;
  try {
    credentials = await firebaseCredentials();
  } catch (error) {
    await finish("failed", String(error));
    return response({ error: "Firebase sender is not configured" }, 503);
  }

  const webBase = Deno.env.get("STUDENT_APP_URL") || "https://student.ogvibes.co.za/";
  const separator = webBase.includes("?") ? "&" : "?";
  const webLink = `${webBase}${separator}notificationRoute=${encodeURIComponent(notification.route)}`;
  const ttlSeconds = notification.category === "messages"
    ? 86400
    : notification.category === "academics" || notification.category === "campus"
    ? 1209600
    : 604800;
  const safeTitle = String(notification.title || template.title).trim() || template.title;
  const safeBody = String(notification.body || template.body).trim() || template.body;
  const data = cleanData({
    event: "student_notification",
    notification_id: notification.id,
    category: notification.category,
    title: safeTitle,
    body: safeBody,
    kind: notification.metadata?.kind || notification.category,
    route: notification.route,
    entity_id: notification.entity_id,
  });

  let sent = 0;
  let failed = 0;
  const attempts: Record<string, unknown>[] = [];
  for (const registration of registrations) {
    const firebaseResponse = await fetch(
      `https://fcm.googleapis.com/v1/projects/${credentials.projectId}/messages:send`,
      {
        method: "POST",
        headers: {
          Authorization: `Bearer ${credentials.token}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          message: {
            token: registration.token,
            data,
            android: { priority: "high", ttl: `${ttlSeconds}s` },
            webpush: {
              headers: { Urgency: "high", TTL: String(ttlSeconds) },
              fcm_options: { link: webLink },
            },
          },
        }),
      },
    );
    if (firebaseResponse.ok) {
      sent += 1;
      attempts.push({
        notification_id: notification.id,
        user_id: notification.user_id,
        device_token_id: registration.id,
        platform: registration.platform,
        outcome: "accepted",
        provider_status: firebaseResponse.status,
      });
      continue;
    }
    failed += 1;
    const payload: any = await firebaseResponse.json().catch(() => ({}));
    const serialized = JSON.stringify(payload);
    const errorCode = String(
      payload?.error?.details?.find?.((detail: Record<string, unknown>) => detail?.errorCode)?.errorCode
        ?? payload?.error?.status
        ?? "FCM_ERROR",
    ).slice(0, 120);
    const invalidToken = firebaseResponse.status === 404
      || ["UNREGISTERED", "INVALID_ARGUMENT", "SENDER_ID_MISMATCH"].includes(errorCode)
      || serialized.includes("UNREGISTERED");
    attempts.push({
      notification_id: notification.id,
      user_id: notification.user_id,
      device_token_id: registration.id,
      platform: registration.platform,
      outcome: invalidToken ? "invalid_token" : "failed",
      provider_status: firebaseResponse.status,
      error_code: errorCode,
    });
    if (invalidToken) {
      await admin.from("device_push_tokens").delete().eq("id", registration.id);
    }
  }

  if (attempts.length) {
    const { error: attemptError } = await admin.from("push_delivery_attempts").insert(attempts);
    if (attemptError) console.error("push-delivery-attempts", attemptError);
  }

  await finish(sent > 0 ? (failed > 0 ? "partial" : "sent") : "failed",
    sent === 0 && failed > 0 ? "Firebase rejected every registered device" : undefined);
  return response({ sent, failed });
});

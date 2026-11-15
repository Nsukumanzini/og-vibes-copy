import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2.57.4";
import { JWT } from "npm:google-auth-library@9.15.1";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...cors, "Content-Type": "application/json" },
  });
}

async function firebaseCredentials() {
  const encoded = Deno.env.get("FIREBASE_SERVICE_ACCOUNT_JSON_BASE64");
  if (!encoded) throw new Error("Firebase service account is not configured");
  const account = JSON.parse(
    new TextDecoder().decode(Uint8Array.from(atob(encoded), (c) => c.charCodeAt(0))),
  );
  const client = new JWT({
    email: account.client_email,
    key: account.private_key,
    scopes: ["https://www.googleapis.com/auth/firebase.messaging"],
  });
  const credentials = await client.authorize();
  if (!credentials.access_token) throw new Error("Firebase authorization failed");
  return { token: credentials.access_token, projectId: account.project_id as string };
}

Deno.serve(async (request: Request) => {
  if (request.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (request.method !== "POST") return json({ error: "Method not allowed" }, 405);
  const authorization = request.headers.get("Authorization");
  if (!authorization) return json({ error: "Authentication required" }, 401);

  const url = Deno.env.get("SUPABASE_URL")!;
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY")!;
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
  const userClient = createClient(url, anonKey, {
    global: { headers: { Authorization: authorization } },
    auth: { persistSession: false },
  });
  const admin = createClient(url, serviceKey, { auth: { persistSession: false } });
  const { data: authData, error: authError } = await userClient.auth.getUser();
  if (authError || !authData.user) return json({ error: "Invalid session" }, 401);

  let body: Record<string, unknown>;
  try {
    body = await request.json();
  } catch {
    return json({ error: "Invalid request" }, 400);
  }
  const incidentId = typeof body.incidentId === "string" ? body.incidentId : "";
  if (!incidentId) return json({ error: "Incident identifier required" }, 400);

  const { data: incident, error: incidentError } = await admin
    .from("sos_incidents")
    .select("id,student_id,emergency_type,silent_mode,status,campus,maps_url")
    .eq("id", incidentId)
    .maybeSingle();
  if (incidentError || !incident) return json({ error: "Incident not found" }, 404);
  if (incident.student_id !== authData.user.id) return json({ error: "Not allowed" }, 403);

  const [{ data: student }, { data: responders }, { data: contacts }, { data: admins }] = await Promise.all([
    admin.from("profiles").select("name,surname,nickname,phone").eq("id", incident.student_id).maybeSingle(),
    admin.from("safety_responders").select("user_id,responder_type,campus").eq("active", true),
    admin.from("sos_trusted_contacts").select("phone").eq("user_id", incident.student_id),
    admin.from("profiles").select("id").eq("role", "admin"),
  ]);

  const responderIds = (responders ?? [])
    .filter((row) => !row.campus || row.campus === incident.campus)
    .map((row) => row.user_id as string);
  const contactPhones = (contacts ?? []).map((row) => row.phone as string);
  let trustedIds: string[] = [];
  if (contactPhones.length) {
    const normalise = (value: string) => value.replace(/[^+0-9]/g, "");
    const wanted = new Set(contactPhones.map(normalise));
    const { data: trustedProfiles } = await admin.from("profiles").select("id,phone").not("phone", "is", null);
    trustedIds = (trustedProfiles ?? [])
      .filter((row) => wanted.has(normalise(row.phone as string)))
      .map((row) => row.id as string);
  }
  const adminIds = (admins ?? []).map((row) => row.id as string);
  const recipientIds = [...new Set([...responderIds, ...adminIds, ...trustedIds])];
  if (!recipientIds.length) return json({ sent: 0, failed: 0, recipients: 0 });

  const { data: registrations } = await admin
    .from("device_push_tokens")
    .select("id,user_id,token")
    .in("user_id", recipientIds)
    .gte("last_seen_at", new Date(Date.now() - 1000 * 60 * 60 * 24 * 90).toISOString());
  if (!registrations?.length) return json({ sent: 0, failed: 0, recipients: recipientIds.length });

  let firebase;
  try {
    firebase = await firebaseCredentials();
  } catch {
    return json({ error: "Firebase sender is not configured" }, 503);
  }
  const displayName = student?.nickname?.trim() ||
    [student?.name, student?.surname].filter(Boolean).join(" ").trim() ||
    "OG Vibes student";
  let sent = 0;
  let failed = 0;
  for (const registration of registrations) {
    const response = await fetch(
      `https://fcm.googleapis.com/v1/projects/${firebase.projectId}/messages:send`,
      {
        method: "POST",
        headers: {
          Authorization: `Bearer ${firebase.token}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          message: {
            token: registration.token,
            notification: {
              title: `Emergency SOS: ${incident.emergency_type}`,
              body: `${displayName} needs help${incident.campus ? ` at ${incident.campus}` : ""}.`,
            },
            data: {
              event: "sos_alert",
              incident_id: incident.id,
              emergency_type: incident.emergency_type,
              student_name: displayName,
              campus: incident.campus ?? "",
              maps_url: incident.maps_url ?? "",
            },
            android: { priority: "high", ttl: "3600s" },
            webpush: {
              headers: { Urgency: "high", TTL: "3600" },
              fcm_options: { link: `https://cloud.ogtechnologies.co.za/?sosId=${incident.id}` },
            },
          },
        }),
      },
    );
    if (response.ok) {
      sent++;
    } else {
      failed++;
      const payload = await response.text();
      if (response.status === 404 || payload.includes("UNREGISTERED")) {
        await admin.from("device_push_tokens").delete().eq("id", registration.id);
      }
    }
  }
  await admin.from("sos_incidents")
    .update({ responder_notified_at: new Date().toISOString() })
    .eq("id", incident.id);
  return json({ sent, failed, recipients: recipientIds.length });
});

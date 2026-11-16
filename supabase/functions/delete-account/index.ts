import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

Deno.serve(async (request: Request) => {
  if (request.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (request.method !== "POST") {
    return json({ error: "Method not allowed" }, 405);
  }

  const authorization = request.headers.get("Authorization");
  if (!authorization?.startsWith("Bearer ")) {
    return json({ error: "Authentication required" }, 401);
  }

  const url = Deno.env.get("SUPABASE_URL");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
  if (!url || !serviceRoleKey || !anonKey) {
    return json({ error: "Server configuration is incomplete" }, 500);
  }

  const userClient = createClient(url, anonKey, {
    global: { headers: { Authorization: authorization } },
    auth: { persistSession: false },
  });
  const { data: userData, error: userError } = await userClient.auth.getUser();
  if (userError || !userData.user) {
    return json({ error: "Session is invalid or expired" }, 401);
  }

  let body: { confirmation?: string } = {};
  try {
    body = await request.json();
  } catch {
    return json({ error: "A confirmation is required" }, 400);
  }
  if (body.confirmation !== "DELETE") {
    return json({ error: "Type DELETE to confirm account deletion" }, 400);
  }

  const admin = createClient(url, serviceRoleKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const userId = userData.user.id;

  // Remove the user's known private media before deleting the auth identity.
  await Promise.allSettled([
    removeFolder(admin, "posts", userId),
    removeFolder(admin, "documents", userId),
    removeFolder(admin, "chat-media", userId),
    removeFolder(admin, "group-media", userId),
    removeFolder(admin, "products", userId),
    removeFolder(admin, "lost-and-found", `lost_and_found/${userId}`),
    admin.storage.from("profile_images").remove([`${userId}.jpg`, `${userId}.png`, `${userId}.webp`]),
  ]);

  const { error: deleteError } = await admin.auth.admin.deleteUser(userId);
  if (deleteError) {
    console.error("Account deletion failed", deleteError.message);
    return json({ error: "Account could not be deleted" }, 500);
  }
  return json({ deleted: true });
});

async function removeFolder(client: ReturnType<typeof createClient>, bucket: string, folder: string) {
  const { data, error } = await client.storage.from(bucket).list(folder, { limit: 1000 });
  if (error || !data?.length) return;
  const paths = data.filter((entry) => entry.id).map((entry) => `${folder}/${entry.name}`);
  if (paths.length) await client.storage.from(bucket).remove(paths);
}

function json(payload: Record<string, unknown>, status = 200) {
  return new Response(JSON.stringify(payload), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

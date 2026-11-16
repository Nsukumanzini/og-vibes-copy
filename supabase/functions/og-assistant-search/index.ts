import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2.57.4";

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

const embeddingModel = new Supabase.ai.Session("gte-small");

Deno.serve(async (request: Request) => {
  if (request.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (request.method !== "POST") return json({ error: "Method not allowed" }, 405);

  const authorization = request.headers.get("Authorization");
  if (!authorization) return json({ error: "Sign in to use OG Assistant." }, 401);

  const client = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_ANON_KEY")!,
    {
      global: { headers: { Authorization: authorization } },
      auth: { persistSession: false },
    },
  );
  const { data: authData, error: authError } = await client.auth.getUser();
  if (authError || !authData.user) return json({ error: "Your session has expired." }, 401);

  let body: Record<string, unknown>;
  try {
    body = await request.json();
  } catch (_) {
    return json({ error: "Invalid request." }, 400);
  }

  const question = String(body.question ?? "").trim().replace(/\s+/g, " ");
  const moduleId = body.moduleId == null ? null : String(body.moduleId);
  const limit = Math.min(Math.max(Number(body.limit ?? 6), 1), 10);
  if (question.length < 3 || question.length > 500) {
    return json({ error: "Enter a study question between 3 and 500 characters." }, 400);
  }

  try {
    const embedding = await embeddingModel.run(question, {
      mean_pool: true,
      normalize: true,
    });
    const { data, error } = await client.rpc("match_academic_chunks", {
      query_embedding: embedding,
      match_threshold: 0.52,
      match_count: limit,
      filter_module_id: moduleId,
    });
    if (error) throw error;
    return json({
      question,
      grounded: Array.isArray(data) && data.length > 0,
      results: data ?? [],
    });
  } catch (error) {
    console.error("OG Assistant search failed", error);
    return json({ error: "Approved material could not be searched right now." }, 500);
  }
});

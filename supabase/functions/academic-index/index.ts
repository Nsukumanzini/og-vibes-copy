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

type AcademicChunk = { pageNumber: number; chunkIndex: number; content: string };
const embeddingModel = new Supabase.ai.Session("gte-small");

Deno.serve(async (request: Request) => {
  if (request.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (request.method !== "POST") return json({ error: "Method not allowed" }, 405);

  const authorization = request.headers.get("Authorization");
  if (!authorization) return json({ error: "Authentication required" }, 401);
  const client = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_ANON_KEY")!,
    {
      global: { headers: { Authorization: authorization } },
      auth: { persistSession: false },
    },
  );
  const { data: authData, error: authError } = await client.auth.getUser();
  if (authError || !authData.user) return json({ error: "Invalid session" }, 401);

  let body: Record<string, unknown>;
  try {
    body = await request.json();
  } catch (_) {
    return json({ error: "Invalid request" }, 400);
  }
  const document = body.document as Record<string, unknown> | undefined;
  const chunks = Array.isArray(body.chunks) ? body.chunks as AcademicChunk[] : [];
  if (!document || chunks.length === 0 || chunks.length > 16) {
    return json({ error: "Send a document and between 1 and 16 text chunks." }, 400);
  }

  const sourceType = String(document.sourceType ?? "");
  const sourceId = String(document.sourceId ?? "");
  const moduleId = String(document.moduleId ?? "");
  const title = String(document.title ?? "").trim();
  const storagePath = String(document.storagePath ?? "");
  if (!sourceId || !moduleId || !title || !storagePath ||
      !["lecture_slide", "academic_note", "past_paper"].includes(sourceType)) {
    return json({ error: "Document metadata is incomplete." }, 400);
  }
  for (const chunk of chunks) {
    const content = String(chunk.content ?? "").trim();
    if (!Number.isInteger(chunk.pageNumber) || chunk.pageNumber < 1 ||
        !Number.isInteger(chunk.chunkIndex) || chunk.chunkIndex < 0 ||
        content.length < 20 || content.length > 2400) {
      return json({ error: "One or more document passages are invalid." }, 400);
    }
  }

  try {
    const { data: indexedDocument, error: documentError } = await client
      .from("academic_assistant_documents")
      .upsert({
        source_type: sourceType,
        source_id: sourceId,
        module_id: moduleId,
        title,
        storage_path: storagePath,
        approved: true,
        approved_by: authData.user.id,
        index_status: "indexing",
        updated_at: new Date().toISOString(),
      }, { onConflict: "source_type,source_id" })
      .select("id")
      .single();
    if (documentError) throw documentError;

    if (body.replace === true) {
      const { error } = await client
        .from("academic_assistant_chunks")
        .delete()
        .eq("document_id", indexedDocument.id);
      if (error) throw error;
    }

    const rows = [];
    for (const chunk of chunks) {
      const content = String(chunk.content).trim();
      const embedding = await embeddingModel.run(content, {
        mean_pool: true,
        normalize: true,
      });
      rows.push({
        document_id: indexedDocument.id,
        page_number: chunk.pageNumber,
        chunk_index: chunk.chunkIndex,
        content,
        embedding,
      });
    }
    const { error: chunkError } = await client
      .from("academic_assistant_chunks")
      .upsert(rows, { onConflict: "document_id,page_number,chunk_index" });
    if (chunkError) throw chunkError;

    if (body.finalBatch === true) {
      const { error } = await client
        .from("academic_assistant_documents")
        .update({
          index_status: "ready",
          indexed_at: new Date().toISOString(),
          updated_at: new Date().toISOString(),
        })
        .eq("id", indexedDocument.id);
      if (error) throw error;
    }
    return json({ documentId: indexedDocument.id, indexed: rows.length });
  } catch (error) {
    console.error("Academic indexing failed", error);
    return json({ error: "This document could not be indexed for OG Assistant." }, 500);
  }
});

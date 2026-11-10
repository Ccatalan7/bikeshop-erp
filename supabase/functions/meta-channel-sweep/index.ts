// The scheduled sweep of a Meta channel: the names of its contacts and the
// files of its messages that no webhook event comes for. Started by the
// database on a schedule, and by nobody else: see `runScheduledMetaChannelSweep`.
import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { runScheduledMetaChannelSweep } from "../_shared/meta_channel_sweep.ts";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";

// A ticket is a channel id and 64 hex characters.
const MAX_REQUEST_BYTES = 512;

function jsonResponse(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

serve(async (request) => {
  if (request.method !== "POST") {
    return jsonResponse({ ok: false, error: "method_not_allowed" }, 405);
  }
  const raw = await request.text();
  let payload: unknown = null;
  if (raw.length <= MAX_REQUEST_BYTES) {
    try {
      payload = JSON.parse(raw);
    } catch (_) {
      payload = null;
    }
  }
  if (!SUPABASE_URL || !SUPABASE_SERVICE_ROLE_KEY) {
    console.error("[META-CHANNEL-SWEEP] Required server configuration is absent");
    return jsonResponse({ ok: false, error: "server_not_configured" }, 503);
  }
  const client = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, {
    auth: { autoRefreshToken: false, persistSession: false },
  });
  const answer = await runScheduledMetaChannelSweep({ client, payload });
  if (answer.status === 200) {
    // Counts and codes only: never a name, an id or a URL.
    console.log("[META-CHANNEL-SWEEP] Sweep", JSON.stringify(answer.body));
  }
  return jsonResponse(answer.body, answer.status);
});

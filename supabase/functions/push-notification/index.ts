import { createClient } from "@supabase/supabase-js";
import { JWT } from "google-auth-library";
import { pushWebhookAuthorized } from "../_shared/push_notification_auth.ts";
import {
  buildConversationReadPushData,
  buildMessagingPushData,
  isSilentMessagingRow,
  messagePushBody,
  readSignalIsStale,
  resolveMessagingRecipientIds,
} from "./recipient_policy.ts";
import type {
  PushConversation,
  PushMessageRecord,
  PushParticipant,
} from "./recipient_policy.ts";

interface NotificationPayload {
  type: "INSERT";
  table: "messages";
  record: PushMessageRecord;
  schema: "public";
}

/** A teammate read a conversation: other devices drop its notification. */
interface ConversationReadPayload {
  type: "READ";
  table: "conversations";
  record: {
    id?: string;
    tenant_id?: string;
    staff_last_read_message_sequence?: number | null;
  };
  schema: "public";
}

interface TenantMemberRow {
  user_id?: string | null;
  auth_user_id?: string | null;
  name?: string | null;
}

function jsonResponse(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

function cleanText(value: unknown, fallback: string) {
  if (typeof value !== "string") return fallback;
  const clean = value.replaceAll(/[\r\n\t]+/g, " ").trim().slice(0, 120);
  return clean || fallback;
}

function metadataRecord(value: unknown): Record<string, unknown> {
  return value != null && typeof value === "object" && !Array.isArray(value)
    ? value as Record<string, unknown>
    : {};
}

async function resolveSenderName(params: {
  supabase: ReturnType<typeof createClient>;
  record: PushMessageRecord;
  conversation: PushConversation;
  activeStaffUserIds: Set<string>;
  customerNamesByUserId: Map<string, string>;
}) {
  const { supabase, record, conversation } = params;
  const metadata = metadataRecord(record.metadata);

  if (!record.sender_id) {
    if (record.external_provider === "whatsapp") {
      return cleanText(metadata.contact_name, "WhatsApp");
    }
    if (record.external_provider === "instagram") {
      return cleanText(
        metadata.contact_label ?? metadata.contact_name ?? metadata.username,
        "Instagram",
      );
    }
    if (record.external_provider === "facebook_messenger") {
      return cleanText(
        metadata.contact_label ?? metadata.contact_name,
        "Messenger",
      );
    }
    return "Cliente";
  }

  const customerName = params.customerNamesByUserId.get(record.sender_id);
  if (customerName) return cleanText(customerName, "Cliente");

  if (!params.activeStaffUserIds.has(record.sender_id)) return "Cliente";

  try {
    const { data: rawUserProfile } = await supabase
      .from("user_profiles")
      .select("employee_id")
      .eq("user_id", record.sender_id)
      .eq("tenant_id", conversation.tenant_id)
      .or("is_active.eq.true,is_active.is.null")
      .maybeSingle();
    const userProfile = rawUserProfile as
      | { employee_id?: string | null }
      | null;

    if (userProfile?.employee_id) {
      const { data: rawEmployee } = await supabase
        .from("employees")
        .select("first_name, last_name")
        .eq("id", userProfile.employee_id)
        .eq("tenant_id", conversation.tenant_id)
        .eq("status", "active")
        .maybeSingle();
      const employee = rawEmployee as {
        first_name?: string | null;
        last_name?: string | null;
      } | null;

      if (employee) {
        const fullName = `${employee.first_name ?? ""} ${
          employee.last_name ?? ""
        }`.trim();
        if (fullName) return cleanText(fullName, "Equipo Viñabike");
      }
    }
  } catch (error) {
    console.error("Sender display-name lookup failed", error);
  }

  return "Equipo Viñabike";
}

console.log("Push Notification Function Initialized");

Deno.serve(async (req) => {
  if (req.method !== "POST") {
    return jsonResponse({ error: "Method not allowed" }, 405);
  }

  const webhookSecret = Deno.env.get("PUSH_NOTIFICATION_WEBHOOK_SECRET");
  if (!pushWebhookAuthorized(req.headers, webhookSecret)) {
    return jsonResponse({ error: "Unauthorized" }, 401);
  }

  let payload: NotificationPayload | ConversationReadPayload;
  try {
    payload = await req.json();
  } catch (_) {
    return jsonResponse({ error: "Invalid JSON body" }, 400);
  }

  if (payload.type === "READ" && payload.table === "conversations") {
    return await handleConversationRead(payload);
  }

  if (payload.type !== "INSERT" || payload.table !== "messages") {
    return jsonResponse({ message: "Ignored non-message insert" });
  }

  const record = payload.record;
  if (!record?.id || !record.conversation_id) {
    return jsonResponse({
      error: "Message id and conversation_id are required",
    }, 400);
  }
  if (isSilentMessagingRow(record)) {
    return jsonResponse({
      message: "Ignored silent messaging row",
      message_id: record.id,
    });
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!supabaseUrl || !serviceRoleKey) {
    return jsonResponse({
      error: "Supabase service configuration is incomplete",
    }, 500);
  }
  const supabase = createClient(supabaseUrl, serviceRoleKey);

  // The parent conversation is the authoritative tenant boundary. Never fan
  // out using a tenant or participant list supplied by the webhook payload.
  const { data: rawConversation, error: conversationError } = await supabase
    .from("conversations")
    .select("id, tenant_id, type, channel, counterparty_type")
    .eq("id", record.conversation_id)
    .maybeSingle();

  if (conversationError) {
    console.error("Conversation scope lookup failed", conversationError);
    return jsonResponse({ error: "Could not resolve conversation scope" }, 500);
  }
  if (
    !rawConversation?.tenant_id ||
    !["internal", "support"].includes(rawConversation.type)
  ) {
    return jsonResponse({
      message: "Ignored invalid conversation scope",
      message_id: record.id,
    });
  }

  const conversation = rawConversation as PushConversation;
  if (record.tenant_id != null && record.tenant_id !== conversation.tenant_id) {
    console.error("Rejected cross-tenant message webhook", {
      message_id: record.id,
      conversation_id: record.conversation_id,
    });
    return jsonResponse({
      message: "Ignored tenant mismatch",
      message_id: record.id,
    });
  }

  const [participantResult, staffResult, customerResult] = await Promise.all([
    supabase
      .from("conversation_participants")
      .select("user_id, tenant_id")
      .eq("conversation_id", conversation.id)
      .eq("tenant_id", conversation.tenant_id),
    supabase
      .from("user_profiles")
      .select("user_id")
      .eq("tenant_id", conversation.tenant_id)
      // Historical memberships may predate the nullable flag. Match the
      // database authorization helpers, where NULL still means active.
      .or("is_active.eq.true,is_active.is.null"),
    supabase
      .from("customers")
      .select("auth_user_id, name")
      .eq("tenant_id", conversation.tenant_id)
      .or("is_active.eq.true,is_active.is.null")
      .not("auth_user_id", "is", null),
  ]);

  const membershipError = participantResult.error ?? staffResult.error ??
    customerResult.error;
  if (membershipError) {
    console.error("Tenant recipient lookup failed", membershipError);
    return jsonResponse(
      { error: "Could not resolve notification recipients" },
      500,
    );
  }

  const participants = (participantResult.data ?? []) as PushParticipant[];
  const activeStaffUserIds = ((staffResult.data ?? []) as TenantMemberRow[])
    .map((row) => row.user_id)
    .filter((userId): userId is string => Boolean(userId));
  const activeCustomers = (customerResult.data ?? []) as TenantMemberRow[];
  const activeCustomerUserIds = activeCustomers
    .map((row) => row.auth_user_id)
    .filter((userId): userId is string => Boolean(userId));

  const recipientIds = resolveMessagingRecipientIds({
    record,
    conversation,
    participants,
    activeStaffUserIds,
    activeCustomerUserIds,
  });
  if (recipientIds.length === 0) {
    return jsonResponse({
      message: "No eligible recipients",
      message_id: record.id,
    });
  }

  const { data: tokens, error: tokenError } = await supabase
    .from("user_fcm_tokens")
    .select("fcm_token, user_id")
    .in("user_id", recipientIds);

  if (tokenError) {
    console.error("FCM token lookup failed", tokenError);
    return jsonResponse(
      { error: "Could not resolve notification devices" },
      500,
    );
  }
  if (!tokens?.length) {
    return jsonResponse({
      message: "Eligible recipients have no registered devices",
      message_id: record.id,
      recipient_count: recipientIds.length,
    });
  }

  const customerNamesByUserId = new Map(
    activeCustomers.flatMap((row) =>
      row.auth_user_id && row.name
        ? [[row.auth_user_id, row.name] as const]
        : []
    ),
  );
  const senderName = await resolveSenderName({
    supabase,
    record,
    conversation,
    activeStaffUserIds: new Set(activeStaffUserIds),
    customerNamesByUserId,
  });
  const body = messagePushBody(record);
  const data = buildMessagingPushData(
    record,
    senderName,
    body,
    conversation.counterparty_type ?? null,
  );

  let accessToken: string;
  try {
    accessToken = await getAccessToken();
  } catch (error) {
    console.error("Firebase authorization failed", error);
    return jsonResponse(
      { error: "Could not authorize Firebase delivery" },
      500,
    );
  }

  const results = await Promise.all(tokens.map(async (tokenRow) => {
    try {
      const response = await fetch(
        `https://fcm.googleapis.com/v1/projects/${
          Deno.env.get("FIREBASE_PROJECT_ID")
        }/messages:send`,
        {
          method: "POST",
          headers: {
            "Content-Type": "application/json",
            "Authorization": `Bearer ${accessToken}`,
          },
          body: JSON.stringify({
            message: {
              token: tokenRow.fcm_token,
              data,
              android: {
                priority: "high",
                notification: {
                  title: senderName,
                  body,
                  channel_id: "chat_messages",
                  tag: record.conversation_id,
                },
              },
              apns: {
                payload: {
                  aps: {
                    contentAvailable: true,
                    mutableContent: true,
                    alert: { title: senderName, body },
                    threadId: record.conversation_id,
                  },
                },
              },
              webpush: {
                headers: { Urgency: "high" },
                notification: {
                  title: senderName,
                  body,
                  icon: "/icons/Icon-192.png",
                  badge: "/icons/Icon-192.png",
                  tag: record.conversation_id,
                  renotify: true,
                },
                fcm_options: {
                  link: `/chat?conversation=${record.conversation_id}`,
                },
              },
            },
          }),
        },
      );
      if (!response.ok) {
        console.error("FCM delivery rejected", {
          message_id: record.id,
          status: response.status,
        });
        await pruneIfUnregistered(supabase, response, tokenRow);
      }
      return response.ok;
    } catch (error) {
      console.error("FCM delivery failed", error);
      return false;
    }
  }));

  const delivered = results.filter((result) => result).length;
  return jsonResponse({
    message: delivered === results.length
      ? "Notifications sent"
      : "Notification delivery incomplete",
    message_id: record.id,
    conversation_id: record.conversation_id,
    recipient_count: recipientIds.length,
    device_count: tokens.length,
    delivered,
    failed: results.length - delivered,
  }, delivered > 0 ? 200 : 502);
});

async function sendFcmMessage(
  accessToken: string,
  message: Record<string, unknown>,
) {
  return await fetch(
    `https://fcm.googleapis.com/v1/projects/${
      Deno.env.get("FIREBASE_PROJECT_ID")
    }/messages:send`,
    {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "Authorization": `Bearer ${accessToken}`,
      },
      body: JSON.stringify({ message }),
    },
  );
}

/**
 * Removes a device token FCM reports as no longer registered.
 *
 * El 2026-10-08 cada aviso iba a 68 dispositivos de 3 personas y llegaba a 4:
 * los otros eran instalaciones borradas o reinstaladas desde diciembre, que FCM
 * contesta con 404 `UNREGISTERED`. Nadie los quitaba. Sólo ese código borra:
 * cualquier otro error deja el token como estaba.
 */
async function pruneIfUnregistered(
  supabase: ReturnType<typeof createClient>,
  response: Response,
  tokenRow: { fcm_token: string; user_id: string },
) {
  if (response.status !== 404) {
    await response.body?.cancel();
    return;
  }
  let unregistered = false;
  try {
    const body = await response.json() as {
      error?: { details?: Array<{ errorCode?: string }> };
    };
    unregistered = (body.error?.details ?? []).some((detail) =>
      detail.errorCode === "UNREGISTERED"
    );
  } catch (_) {
    unregistered = false;
  }
  if (!unregistered) return;
  const { error } = await supabase
    .from("user_fcm_tokens")
    .delete()
    .eq("user_id", tokenRow.user_id)
    .eq("fcm_token", tokenRow.fcm_token);
  if (error) console.error("Unregistered token cleanup failed", error);
}

/**
 * Someone at Viñabike read a support conversation. Every staff device gets a
 * silent signal and drops that chat's notification, so a message read on the
 * desktop stops waiting on the phone (owner, 2026-10-08: «cuando se lee en
 * uno, que actualice eso automáticamente para todos, como lo hace WhatsApp»).
 * The conversation row read here, not the payload, decides the tenant.
 */
async function handleConversationRead(payload: ConversationReadPayload) {
  const conversationId = payload.record?.id;
  if (!conversationId) {
    return jsonResponse({ error: "Conversation id is required" }, 400);
  }
  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!supabaseUrl || !serviceRoleKey) {
    return jsonResponse({
      error: "Supabase service configuration is incomplete",
    }, 500);
  }
  const supabase = createClient(supabaseUrl, serviceRoleKey);
  const { data: rawConversation, error: conversationError } = await supabase
    .from("conversations")
    .select("id, tenant_id, type, staff_last_read_message_sequence")
    .eq("id", conversationId)
    .maybeSingle();
  if (conversationError) {
    console.error("Read signal conversation lookup failed", conversationError);
    return jsonResponse({ error: "Could not resolve conversation scope" }, 500);
  }
  const conversation = rawConversation as {
    id: string;
    tenant_id: string | null;
    type: string;
    staff_last_read_message_sequence: number | null;
  } | null;
  if (!conversation?.tenant_id || conversation.type !== "support") {
    return jsonResponse({ message: "Ignored read outside support" });
  }
  if (
    payload.record?.tenant_id != null &&
    payload.record.tenant_id !== conversation.tenant_id
  ) {
    return jsonResponse({ message: "Ignored tenant mismatch" });
  }
  // The cursor this read reached, as the trigger saw it. The live cursor may
  // already be another read, which sends its own signal.
  const readThrough = Number(
    payload.record?.staff_last_read_message_sequence ??
      conversation.staff_last_read_message_sequence,
  );
  if (!Number.isFinite(readThrough)) {
    return jsonResponse({ message: "Ignored read without a cursor" });
  }

  const { data: staffRows, error: staffError } = await supabase
    .from("user_profiles")
    .select("user_id")
    .eq("tenant_id", conversation.tenant_id)
    .or("is_active.eq.true,is_active.is.null");
  if (staffError) {
    console.error("Read signal staff lookup failed", staffError);
    return jsonResponse({ error: "Could not resolve staff" }, 500);
  }
  const staffIds = ((staffRows ?? []) as TenantMemberRow[])
    .map((row) => row.user_id)
    .filter((userId): userId is string => Boolean(userId));
  if (staffIds.length === 0) {
    return jsonResponse({ message: "No staff to signal" });
  }

  // Something the customer side wrote after this read is unread again: its
  // alert must stay on every device. Staff replies are skipped in the query
  // and the rest is read in order, page by page: a fixed window could miss
  // the supplier's message behind a run of team rows.
  const staffSet = new Set(staffIds);
  const pageSize = 200;
  const maxRows = 2000;
  let stale = false;
  for (let from = 0; from < maxRows && !stale; from += pageSize) {
    const { data: laterRows, error: laterError } = await supabase
      .from("messages")
      .select("sender_id, message_direction, type, metadata")
      .eq("conversation_id", conversation.id)
      .eq("tenant_id", conversation.tenant_id)
      .gt("message_sequence", readThrough)
      .or("message_direction.is.null,message_direction.neq.outbound")
      .order("message_sequence", { ascending: true })
      .range(from, from + pageSize - 1);
    if (laterError) {
      console.error("Read signal later-message lookup failed", laterError);
      return jsonResponse({ error: "Could not resolve later messages" }, 500);
    }
    const rows = (laterRows ?? []) as PushMessageRecord[];
    stale = readSignalIsStale(rows, staffSet);
    if (rows.length < pageSize) break;
    // Too many rows to prove the chat is read: keep the alerts.
    if (from + pageSize >= maxRows) stale = true;
  }
  if (stale) {
    return jsonResponse({
      message: "Ignored read overtaken by an unread message",
      conversation_id: conversation.id,
    });
  }

  const { data: tokens, error: tokenError } = await supabase
    .from("user_fcm_tokens")
    .select("fcm_token, user_id")
    .in("user_id", staffIds)
    // Only installations that declare they understand the signal: a browser
    // must show something for every push, and the app published before
    // 2026-10-08 does not send device_type.
    .in("device_type", ["android", "ios"]);
  if (tokenError) {
    console.error("Read signal token lookup failed", tokenError);
    return jsonResponse({ error: "Could not resolve devices" }, 500);
  }
  if (!tokens?.length) {
    return jsonResponse({ message: "No staff devices registered" });
  }

  let accessToken: string;
  try {
    accessToken = await getAccessToken();
  } catch (error) {
    console.error("Firebase authorization failed", error);
    return jsonResponse(
      { error: "Could not authorize Firebase delivery" },
      500,
    );
  }

  const data = buildConversationReadPushData(conversation.id, readThrough);
  const results = await Promise.all(tokens.map(async (tokenRow) => {
    try {
      const response = await sendFcmMessage(accessToken, {
        token: tokenRow.fcm_token,
        data,
        android: {
          // Normal, not high: FCM deprioritizes an app whose high-priority
          // messages show nothing, and that would delay real message alerts.
          priority: "normal",
          // A newer read of the same chat replaces a pending one.
          collapse_key: `read-${conversation.id}`,
        },
        apns: {
          headers: { "apns-push-type": "background", "apns-priority": "5" },
          payload: { aps: { "content-available": 1 } },
        },
      });
      if (!response.ok) {
        await pruneIfUnregistered(supabase, response, tokenRow);
      }
      return response.ok;
    } catch (error) {
      console.error("Read signal delivery failed", error);
      return false;
    }
  }));
  const delivered = results.filter((result) => result).length;
  return jsonResponse({
    message: "Read signal sent",
    conversation_id: conversation.id,
    device_count: tokens.length,
    delivered,
  });
}

async function getAccessToken() {
  const serviceAccount = JSON.parse(
    Deno.env.get("FIREBASE_SERVICE_ACCOUNT") || "{}",
  );
  if (!serviceAccount.private_key) {
    throw new Error("FIREBASE_SERVICE_ACCOUNT secret is missing or invalid");
  }

  const client = new JWT({
    email: serviceAccount.client_email,
    key: serviceAccount.private_key,
    scopes: ["https://www.googleapis.com/auth/firebase.messaging"],
  });

  const result = await client.authorize();
  if (!result.access_token) {
    throw new Error("Firebase authorization returned no access token");
  }
  return result.access_token;
}

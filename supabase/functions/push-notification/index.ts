import { createClient } from "@supabase/supabase-js";
import { JWT } from "google-auth-library";
import { pushWebhookAuthorized } from "../_shared/push_notification_auth.ts";
import {
  buildMessagingPushData,
  isSilentMessagingRow,
  resolveMessagingRecipientIds,
} from "./recipient_policy.ts";
import type { PushConversation, PushMessageRecord, PushParticipant } from "./recipient_policy.ts";

interface NotificationPayload {
  type: "INSERT";
  table: "messages";
  record: PushMessageRecord;
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

function messageBody(record: PushMessageRecord) {
  if (record.type === "text" || record.type === "action_request") {
    return cleanText(record.content, "Nuevo mensaje");
  }
  if (record.type === "image") return "Imagen adjunta";
  if (record.type === "file") return "Archivo adjunto";
  return "Nuevo mensaje";
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
        const fullName = `${employee.first_name ?? ""} ${employee.last_name ?? ""}`.trim();
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

  let payload: NotificationPayload;
  try {
    payload = await req.json();
  } catch (_) {
    return jsonResponse({ error: "Invalid JSON body" }, 400);
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
    .select("id, tenant_id, type, channel")
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
      row.auth_user_id && row.name ? [[row.auth_user_id, row.name] as const] : []
    ),
  );
  const senderName = await resolveSenderName({
    supabase,
    record,
    conversation,
    activeStaffUserIds: new Set(activeStaffUserIds),
    customerNamesByUserId,
  });
  const body = messageBody(record);
  const data = buildMessagingPushData(record, senderName, body);

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

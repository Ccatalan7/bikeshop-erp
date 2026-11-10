// Who a push says an external message is from.
//
// A WhatsApp message carries its sender's profile name. An Instagram or
// Messenger message carries only a pseudonymous label («Instagram • 1B5849»),
// by design: the name Meta gives for the contact lives in the conversation
// title. So for those two channels the title speaks first, and the label only
// when the conversation has none (2026-11-09: the push kept showing the code
// after the inbox learned the name).

function clean(value: unknown): string {
  if (typeof value !== "string") return "";
  return value.replaceAll(/[\r\n\t]+/g, " ").trim().slice(0, 120);
}

export function externalSenderName(params: {
  provider: string | null | undefined;
  metadata: Record<string, unknown>;
  conversationTitle: string | null | undefined;
}): string {
  const { provider, metadata } = params;
  if (provider === "whatsapp") {
    return clean(metadata.contact_name) || "WhatsApp";
  }
  if (provider === "instagram") {
    return clean(params.conversationTitle) ||
      clean(
        metadata.contact_label ?? metadata.contact_name ?? metadata.username,
      ) ||
      "Instagram";
  }
  if (provider === "facebook_messenger") {
    return clean(params.conversationTitle) ||
      clean(metadata.contact_label ?? metadata.contact_name) ||
      "Messenger";
  }
  return "Cliente";
}

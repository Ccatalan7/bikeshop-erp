// El código por WhatsApp con que una cuenta del portal confirma su teléfono
// (20261105010000). Lo que se puede probar sin red: qué pide la llamada, qué
// se le responde al portal y cómo sale el mensaje.

import {
  buildAuthenticationTemplateMessage,
  findWhatsAppTemplate,
  phoneVerificationTemplateName,
} from "./whatsapp_templates.ts";

const uuidPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

export interface PhoneVerificationRequest {
  tenantId: string;
  phone: string;
}

/// La tienda y el número que el portal manda, o null si no se puede usar.
export function parsePhoneVerificationRequest(
  body: unknown,
): PhoneVerificationRequest | null {
  if (!body || typeof body !== "object") return null;
  const record = body as Record<string, unknown>;
  const tenantId = typeof record.tenantId === "string" ? record.tenantId.trim() : "";
  const phone = typeof record.phone === "string" ? record.phone.trim() : "";
  if (!uuidPattern.test(tenantId)) return null;
  if (phone.length < 8 || phone.length > 40) return null;
  return { tenantId, phone };
}

/// Lo que la base respondió al pedir el código, en lo que el portal puede
/// saber: nunca el código ni el número entero.
export type PhoneVerificationAnswer =
  | { status: "sent"; phone_hint: string; expires_at: string }
  | { status: "too_soon"; retry_after_seconds: number }
  | {
    status:
      | "invalid_phone"
      | "too_many_requests"
      | "disabled"
      | "not_sent"
      | "unavailable";
  };

export function phoneVerificationRefusal(
  started: Record<string, unknown>,
): PhoneVerificationAnswer | null {
  switch (started.status) {
    case "issued":
      return null;
    case "too_soon":
      return {
        status: "too_soon",
        retry_after_seconds: Math.max(Number(started.retry_after_seconds) || 60, 1),
      };
    case "invalid_phone":
    case "too_many_requests":
    case "disabled":
      return { status: started.status };
    default:
      return { status: "unavailable" };
  }
}

/// El mensaje de Meta con el código, con la plantilla del catálogo.
export function phoneVerificationMessage(to: string, code: string) {
  const template = findWhatsAppTemplate(phoneVerificationTemplateName);
  if (!template?.authentication) {
    throw new Error("phone_verification_template_missing");
  }
  return buildAuthenticationTemplateMessage({ to, template, code });
}

/// El id del mensaje que Meta aceptó, o null.
export function acceptedMessageId(result: unknown): string | null {
  if (!result || typeof result !== "object") return null;
  const messages = (result as Record<string, unknown>).messages;
  if (!Array.isArray(messages)) return null;
  const first = messages[0];
  if (!first || typeof first !== "object") return null;
  const id = (first as Record<string, unknown>).id;
  return typeof id === "string" && id.trim() ? id.trim() : null;
}

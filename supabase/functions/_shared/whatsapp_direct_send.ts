import { defaultWhatsAppTemplates, renderWhatsAppTemplateBody } from "./whatsapp_templates.ts";

export const directSendUtilityStrategy = "direct_send_utility" as const;

type JsonRecord = Record<string, unknown>;

export interface DirectSendUtilityRequest {
  deliveryStrategy?: unknown;
  type?: unknown;
  templateName?: unknown;
  templateLanguage?: unknown;
  templateComponents?: unknown;
}

export interface DirectSendUtilityResolution {
  requested: boolean;
  enabled: boolean;
  reason:
    | "not_requested"
    | "eligible"
    | "not_a_template"
    | "template_not_registered_as_utility"
    | "invalid_body_parameters"
    | "body_too_long";
  body?: string;
  templateName?: string;
}

function cleanText(value: unknown): string | null {
  if (typeof value !== "string") return null;
  const text = value.trim();
  return text.length > 0 ? text : null;
}

function bodyParameters(components: unknown): string[] | null {
  if (!Array.isArray(components)) return null;
  const body = components.find((component) =>
    component &&
    typeof component === "object" &&
    cleanText((component as JsonRecord).type)?.toLowerCase() === "body"
  ) as JsonRecord | undefined;
  if (!body || !Array.isArray(body.parameters)) return null;

  const values: string[] = [];
  for (const rawParameter of body.parameters) {
    if (!rawParameter || typeof rawParameter !== "object") return null;
    const parameter = rawParameter as JsonRecord;
    if (cleanText(parameter.type)?.toLowerCase() !== "text") return null;
    const value = cleanText(parameter.text);
    if (!value) return null;
    values.push(value);
  }
  return values;
}

/// Resolves Direct Send only from the repository-owned utility catalog.
///
/// The caller never gets to label arbitrary text as `utility`: the transport
/// reconstructs the body from the same registered definition and positional
/// parameters used by the classic approved-template fallback.
export function resolveDirectSendUtility(
  request: DirectSendUtilityRequest,
): DirectSendUtilityResolution {
  const explicitlyRequested = request.deliveryStrategy === directSendUtilityStrategy;
  if (
    request.deliveryStrategy != null &&
    request.deliveryStrategy !== directSendUtilityStrategy
  ) {
    return { requested: false, enabled: false, reason: "not_requested" };
  }
  if (request.type !== "template") {
    return explicitlyRequested
      ? { requested: true, enabled: false, reason: "not_a_template" }
      : { requested: false, enabled: false, reason: "not_requested" };
  }

  const templateName = cleanText(request.templateName);
  const templateLanguage = cleanText(request.templateLanguage) ?? "es";
  const definition = defaultWhatsAppTemplates.find((template) =>
    template.name === templateName &&
    template.language === templateLanguage &&
    template.category === "UTILITY"
  );
  if (!definition) {
    return explicitlyRequested
      ? {
        requested: true,
        enabled: false,
        reason: "template_not_registered_as_utility",
        templateName: templateName ?? undefined,
      }
      : { requested: false, enabled: false, reason: "not_requested" };
  }

  const parameters = bodyParameters(request.templateComponents);
  if (!parameters) {
    return {
      requested: true,
      enabled: false,
      reason: "invalid_body_parameters",
      templateName: definition.name,
    };
  }

  const body = renderWhatsAppTemplateBody(definition.body, parameters);
  if (/\{\{\d+\}\}/.test(body)) {
    return {
      requested: true,
      enabled: false,
      reason: "invalid_body_parameters",
      templateName: definition.name,
    };
  }
  if (body.length > 1024) {
    return {
      requested: true,
      enabled: false,
      reason: "body_too_long",
      templateName: definition.name,
    };
  }

  return {
    requested: true,
    enabled: true,
    reason: "eligible",
    body,
    templateName: definition.name,
  };
}

export function buildDirectSendUtilityPayload({
  to,
  body,
}: {
  to: string;
  body: string;
}): JsonRecord {
  return {
    messaging_product: "whatsapp",
    recipient_type: "individual",
    to,
    type: "text",
    text: { body },
    category: "utility",
  };
}

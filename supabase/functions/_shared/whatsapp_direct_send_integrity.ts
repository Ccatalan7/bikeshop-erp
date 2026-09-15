type JsonRecord = Record<string, unknown>;

export interface DirectSendIntegrityNotice {
  kind:
    | "category_mismatch"
    | "template_paused"
    | "template_recovered"
    | "warning"
    | "restriction"
    | "recovery";
  severity: "success" | "warning" | "critical";
  notificationType: string;
  title: string;
  body: string;
  templateId?: string;
  templateName?: string;
  violationType?: string;
  blocksDirectSend: boolean;
}

export interface DirectSendPolicyBlock {
  reason:
    | "category_mismatch"
    | "template_paused"
    | "account_warning_or_restriction"
    | "integrity_lookup_failed";
  detail?: string;
}

function text(value: unknown): string | null {
  if (typeof value !== "string" && typeof value !== "number") return null;
  const normalized = String(value).trim();
  return normalized.length > 0 ? normalized : null;
}

function safeToken(value: string): string {
  return value.toLowerCase().replace(/[^a-z0-9_]+/g, "_").slice(0, 80);
}

function isDirectSendGeneratedTemplate(name: string): boolean {
  const normalized = name.toLowerCase();
  return normalized.startsWith("direct_send_") ||
    normalized.startsWith("auto_generated_");
}

export function parseDirectSendIntegrityNotice(
  field: unknown,
  rawValue: unknown,
): DirectSendIntegrityNotice | null {
  const normalizedField = text(field);
  const value = rawValue && typeof rawValue === "object" && !Array.isArray(rawValue)
    ? rawValue as JsonRecord
    : null;
  if (!normalizedField || !value) return null;

  if (normalizedField === "message_template_status_update") {
    const templateId = text(value.message_template_id);
    const templateName = text(value.message_template_name);
    const event = text(value.event)?.toUpperCase();
    if (
      !templateId || !templateName || !event ||
      !isDirectSendGeneratedTemplate(templateName)
    ) {
      return null;
    }
    if (event !== "PAUSED" && event !== "DISABLED" && event !== "APPROVED") {
      return null;
    }
    const recovered = event === "APPROVED";
    return {
      kind: recovered ? "template_recovered" : "template_paused",
      severity: recovered ? "success" : "critical",
      notificationType: `whatsapp_direct_send_template_${safeToken(templateId)}_${
        safeToken(event)
      }`,
      title: recovered
        ? "Meta restauró un caso de Direct Send"
        : "Meta pausó un caso de Direct Send",
      body: recovered
        ? "Meta volvió a aprobar el mensaje generado. El ERP puede retomar Direct Send para ese caso."
        : "Meta pausó el mensaje generado por baja calidad. El ERP usará la plantilla clásica de respaldo.",
      templateId,
      templateName,
      blocksDirectSend: !recovered,
    };
  }

  if (normalizedField === "template_correct_category_detection") {
    const templateId = text(value.message_template_id);
    const templateName = text(value.message_template_name);
    const correctCategory = text(value.correct_category)?.toUpperCase();
    if (!templateId || !correctCategory) return null;
    return {
      kind: "category_mismatch",
      severity: "critical",
      notificationType: `whatsapp_direct_send_category_${safeToken(templateId)}`,
      title: "Meta detectó una categoría incorrecta",
      body: `Direct Send marcó ${templateName ?? templateId} como ${correctCategory}. ` +
        "El ERP dejará de usar Direct Send para ese caso hasta revisarlo.",
      templateId,
      templateName: templateName ?? undefined,
      blocksDirectSend: true,
    };
  }

  if (
    normalizedField !== "account_update" ||
    text(value.event)?.toUpperCase() !== "ACCOUNT_RESTRICTION"
  ) {
    return null;
  }

  const violationInfo = value.violation_info &&
      typeof value.violation_info === "object" &&
      !Array.isArray(value.violation_info)
    ? value.violation_info as JsonRecord
    : {};
  const violationType = text(violationInfo.violation_type)?.toUpperCase();
  if (!violationType?.startsWith("DIRECT_SEND_")) return null;

  const recovery = violationType.endsWith("_UNBAN") ||
    violationType.endsWith("_RATE_LIMIT_RECOVERY");
  const warning = violationType.endsWith("_WARN") ||
    violationType.endsWith("_TEMPLATE_ABUSE");
  const kind = recovery ? "recovery" : warning ? "warning" : "restriction";

  return {
    kind,
    severity: recovery ? "success" : warning ? "warning" : "critical",
    notificationType: `whatsapp_direct_send_${safeToken(violationType)}`,
    title: recovery
      ? "Meta restauró Direct Send"
      : warning
      ? "Meta advirtió sobre Direct Send"
      : "Meta restringió Direct Send",
    body: recovery
      ? "La restricción de Direct Send fue levantada. El ERP volverá a intentar mensajes utilitarios por esa vía."
      : warning
      ? "Meta detectó posible uso incorrecto de la categoría utility. El ERP usará el respaldo clásico mientras se revisa."
      : "Direct Send está restringido por Meta. El ERP usará plantillas clásicas como respaldo para evitar interrupciones.",
    violationType,
    blocksDirectSend: !recovery,
  };
}

export function directSendIntegrityEventKey({
  field,
  entryTime,
  notice,
}: {
  field: string;
  entryTime: unknown;
  notice: DirectSendIntegrityNotice;
}): string {
  const identity = notice.templateId ?? notice.violationType ?? notice.kind;
  return `${field}:${identity}:${text(entryTime) ?? "unknown"}`;
}

/// Evaluates newest-first webhook evidence. A recovery clears older account
/// restrictions, while a category mismatch stays blocked for that ERP-owned
/// use case until it is deliberately reviewed.
export function directSendPolicyBlockFromEvents(
  rows: readonly unknown[],
  templateName?: string,
): DirectSendPolicyBlock | null {
  let accountStateResolved = false;
  const resolvedGeneratedTemplateIds = new Set<string>();
  for (const rawRow of rows) {
    const row = rawRow && typeof rawRow === "object" && !Array.isArray(rawRow)
      ? rawRow as JsonRecord
      : {};
    const payload = row.payload && typeof row.payload === "object" && !Array.isArray(row.payload)
      ? row.payload as JsonRecord
      : {};
    const field = text(payload.field);
    const notice = parseDirectSendIntegrityNotice(field, payload.value);
    if (!notice) continue;

    if (
      notice.kind === "category_mismatch" &&
      templateName &&
      (!text(payload.source_template_name) ||
        text(payload.source_template_name) === templateName)
    ) {
      return { reason: "category_mismatch", detail: notice.templateId };
    }

    if (
      (notice.kind === "template_paused" ||
        notice.kind === "template_recovered") &&
      notice.templateId &&
      !resolvedGeneratedTemplateIds.has(notice.templateId)
    ) {
      resolvedGeneratedTemplateIds.add(notice.templateId);
      const sourceTemplateName = text(payload.source_template_name);
      const appliesToRequestedCase = !sourceTemplateName ||
        (templateName != null && sourceTemplateName === templateName);
      if (appliesToRequestedCase && notice.blocksDirectSend) {
        return { reason: "template_paused", detail: notice.templateId };
      }
    }

    if (field === "account_update" && !accountStateResolved) {
      accountStateResolved = true;
      if (notice.blocksDirectSend) {
        return {
          reason: "account_warning_or_restriction",
          detail: notice.violationType,
        };
      }
    }
  }
  return null;
}

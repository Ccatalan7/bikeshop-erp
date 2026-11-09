// A customer's tap on a WhatsApp card (approve or reject a quote, confirm a
// delivery) that the database refuses for a business reason never passes on a
// redelivery. On 2026-11-08 the webhook answered such a refusal with 500 and
// Meta did not deliver the tap again in the 2½ hours after the fix was live,
// so the tap was lost and nobody in the workshop knew. A refusal is
// therefore answered 200 and recorded where the workshop sees it; only a
// failure that may pass on a redelivery keeps the 500.

export type JobActionFailure =
  | { kind: "refused"; code: string; detail: string }
  | { kind: "transient"; detail: string };

// What `apply_whatsapp_job_action` and the commands it calls raise for a
// business decision. `P0001` is a plain RAISE without an explicit code.
// Anything else — serialization, deadlock, timeout, connection, PostgREST,
// network — may pass when the tap arrives again.
const REFUSAL_CODES = new Set(["23514", "42501", "22023", "P0001"]);

function textOf(value: unknown) {
  return typeof value === "string" ? value.trim() : "";
}

export function classifyJobActionFailure(error: unknown): JobActionFailure {
  const record = (error && typeof error === "object")
    ? error as Record<string, unknown>
    : {};
  const code = textOf(record.code);
  const detail = textOf(record.message) || String(error);
  if (REFUSAL_CODES.has(code)) return { kind: "refused", code, detail };
  return { kind: "transient", detail };
}

// The database's reason, in the workshop's words. Order matters: the first
// fragment found in the database message wins.
const REASONS: ReadonlyArray<readonly [string, string]> = [
  [
    "already has a terminal response",
    "La tarjeta ya tenía otra respuesta del cliente.",
  ],
  [
    "superseded by a newer card",
    "Respondió un presupuesto anterior: ya tiene uno más nuevo.",
  ],
  ["La cotización ya no está pendiente", "El presupuesto ya no estaba pendiente."],
  ["La cotización venció", "El presupuesto estaba vencido."],
  ["El trabajo no es una cotización", "El trabajo ya no es un presupuesto."],
  [
    "aún no está terminado para confirmar entrega",
    "El trabajo todavía no estaba terminado.",
  ],
  ["conversation is closed", "La conversación estaba cerrada."],
  ["sender does not match", "Lo tocó otro número, no el del cliente."],
  [
    "does not match its outbound card",
    "El botón no corresponde a ninguna tarjeta enviada.",
  ],
  [
    "message, customer, tenant, and job are not linked",
    "El chat no está ligado a ese trabajo.",
  ],
  [
    "message, binding, customer, and tenant are not linked",
    "El chat no está ligado a una ficha de cliente activa.",
  ],
];

export function describeJobActionRefusal(detail: string): string {
  for (const [fragment, reason] of REASONS) {
    if (detail.includes(fragment)) return reason;
  }
  return `La base lo rechazó: ${detail}`;
}

const BUTTON_LABELS: Readonly<Record<string, string>> = {
  approve_quote: "Aprobar presupuesto",
  approve_budget: "Aprobar presupuesto",
  approve_estimate: "Aprobar presupuesto",
  reject_quote: "Rechazar presupuesto",
  reject_budget: "Rechazar presupuesto",
  reject_estimate: "Rechazar presupuesto",
  confirm_delivery: "Confirmar entrega",
  cancel_delivery: "Cancelar entrega",
};

export function jobActionRefusalNotice(params: {
  jobNumber: string | null;
  action: string;
  buttonText: string;
  detail: string;
}) {
  const label = params.buttonText.trim() || BUTTON_LABELS[params.action] ||
    params.action;
  const job = params.jobNumber?.trim() || "Un trabajo";
  return {
    title: `${job}: «${label}» no se aplicó`,
    body: `El cliente lo tocó en WhatsApp. ${
      describeJobActionRefusal(params.detail)
    }`,
  };
}

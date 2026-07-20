export interface WhatsAppActionTarget {
  kind: "job" | "invoice";
  targetId: string;
  action: string;
  revisionMs?: number;
  legacy?: boolean;
}

const UUID_PATTERN =
  "[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}";
const ACTION_PATTERN = "[a-z_]+";
const MODERN_JOB_ACTION = new RegExp(
  `^job:(${UUID_PATTERN}):(${ACTION_PATTERN}):(\\d{10,16})$`,
);
const LEGACY_JOB_ACTION = new RegExp(
  `^job:(${UUID_PATTERN}):(${ACTION_PATTERN})$`,
);
const LEGACY_INVOICE_ACTION = new RegExp(
  `^invoice:(${UUID_PATTERN}):(${ACTION_PATTERN})$`,
);

export function buildJobActionToken(params: {
  jobId: string;
  action: string;
  revisionMs: number;
}) {
  if (!new RegExp(`^${UUID_PATTERN}$`).test(params.jobId)) {
    throw new Error("invalid_job_action_target");
  }
  if (!new RegExp(`^${ACTION_PATTERN}$`).test(params.action)) {
    throw new Error("invalid_job_action_name");
  }
  if (
    !Number.isSafeInteger(params.revisionMs) ||
    params.revisionMs < 1_000_000_000 ||
    String(params.revisionMs).length > 16
  ) {
    throw new Error("invalid_job_action_revision");
  }
  return `job:${params.jobId}:${params.action}:${params.revisionMs}`;
}

export function parseWhatsAppActionToken(
  rawValue: unknown,
): WhatsAppActionTarget | null {
  const rawId = typeof rawValue === "string" ? rawValue.trim() : "";
  const jobMatch = MODERN_JOB_ACTION.exec(rawId);
  if (jobMatch) {
    const revisionMs = Number(jobMatch[3]);
    if (!Number.isSafeInteger(revisionMs)) return null;
    return {
      kind: "job",
      targetId: jobMatch[1],
      action: jobMatch[2],
      revisionMs,
    };
  }

  const legacyJobMatch = LEGACY_JOB_ACTION.exec(rawId);
  if (legacyJobMatch) {
    return {
      kind: "job",
      targetId: legacyJobMatch[1],
      action: legacyJobMatch[2],
      legacy: true,
    };
  }

  const invoiceMatch = LEGACY_INVOICE_ACTION.exec(rawId);
  return invoiceMatch
    ? {
      kind: "invoice",
      targetId: invoiceMatch[1],
      action: invoiceMatch[2],
      legacy: true,
    }
    : null;
}

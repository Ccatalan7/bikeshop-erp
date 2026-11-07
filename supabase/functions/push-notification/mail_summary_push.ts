/**
 * The morning summary of the mail on the office phones (Correo que trabaja,
 * 20261106290000): what came in and what to do, without opening the mail.
 * Pure rules, tested in `mail_summary_push_test.ts`; `index.ts` reads the
 * summary with the service key and delivers it like a web order alert.
 */

import { chileanPesos } from "./online_order_push.ts";

/** `mail_morning_summary_internal`, as the database returns it. */
export interface MailMorningSummary {
  today?: number | null;
  payments?: number | null;
  payments_amount?: number | string | null;
  invoices?: number | null;
  statements?: number | null;
  customers?: number | null;
  follow_ups?: number | null;
  reviews?: number | null;
  security?: number | null;
  transfers_24h?: number | null;
  transfers_24h_amount?: number | string | null;
  transfers_24h_done?: number | null;
}

export interface MailSummaryPush {
  title: string;
  body: string;
  route: string;
  tag: string;
  data: Record<string, string>;
}

/** Only the office answers the mail: not the workshop phones. */
export const MAIL_SUMMARY_ROLES = ["admin", "manager", "accountant", "cashier"];

function count(value: unknown): number {
  const number = Number(value ?? 0);
  return Number.isFinite(number) && number > 0 ? Math.floor(number) : 0;
}

function plural(n: number, one: string, many: string): string {
  return `${n} ${n === 1 ? one : many}`;
}

/**
 * The alert, or null when there is nothing to do («sale sólo si hay algo que
 * hacer»). The text names what came in overnight and the three things that
 * weigh most; the full list is one tap away in «Para hoy».
 */
export function buildMailSummaryPush(
  summary: MailMorningSummary,
  localDate: string,
): MailSummaryPush | null {
  const today = count(summary.today);
  if (today === 0) return null;

  const lines: string[] = [];
  const payments = count(summary.payments);
  if (payments > 0) {
    const amount = Number(summary.payments_amount ?? 0);
    lines.push(
      plural(payments, "pago por confirmar", "pagos por confirmar") +
        (Number.isFinite(amount) && amount > 0
          ? ` (${chileanPesos(amount)})`
          : ""),
    );
  }
  const invoices = count(summary.invoices);
  if (invoices > 0) {
    lines.push(
      plural(invoices, "factura por registrar", "facturas por registrar"),
    );
  }
  const customers = count(summary.customers);
  if (customers > 0) {
    lines.push(
      plural(
        customers,
        "cliente espera respuesta",
        "clientes esperan respuesta",
      ),
    );
  }
  const followUps = count(summary.follow_ups);
  if (followUps > 0) {
    lines.push(
      plural(
        followUps,
        "seguimiento por atender",
        "seguimientos por atender",
      ),
    );
  }
  const statements = count(summary.statements);
  if (statements > 0) {
    lines.push(
      plural(statements, "cartola por importar", "cartolas por importar"),
    );
  }
  const security = count(summary.security);
  if (security > 0) {
    lines.push(plural(security, "aviso de seguridad", "avisos de seguridad"));
  }
  const reviews = count(summary.reviews);
  if (reviews > 0) {
    lines.push(
      plural(reviews, "reseña por agradecer", "reseñas por agradecer"),
    );
  }

  const transfers = count(summary.transfers_24h);
  const transferAmount = Number(summary.transfers_24h_amount ?? 0);
  const opening = transfers > 0 && Number.isFinite(transferAmount) &&
      transferAmount > 0
    ? `Desde ayer entraron ${chileanPesos(transferAmount)} en ${
      plural(transfers, "transferencia", "transferencias")
    }. `
    : "";
  const shown = lines.slice(0, 3);
  const rest = lines.length - shown.length;
  const list = shown.join(", ") + (rest > 0 ? ` y ${rest} más` : "");
  const body = `${opening}Para hoy: ${list}.`;
  const title = today === 1
    ? "Correo: 1 cosa para hoy"
    : `Correo: ${today} cosas para hoy`;
  const route = "/mail";
  return {
    title,
    body,
    route,
    // One summary a day: a repeated delivery replaces it.
    tag: `mail-summary-${localDate}`,
    data: {
      type: "mail",
      kind: "mail_summary",
      route,
      title,
      body,
    },
  };
}

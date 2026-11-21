/**
 * The phone alert for a payroll that is ready to pay (owner, 2026-11-21:
 * «cuando Vicente la complete y quede el borrador, que me llegue una
 * notificación, así yo puedo transferirles en ese momento»). Pure rules,
 * tested in `payroll_voucher_push_test.ts`; `index.ts` reads the voucher, its
 * lines and who may pay it, and sends it through the same delivery as a web
 * order.
 *
 * The alert names the week and the people, never an amount: the voucher total
 * does not subtract the advances, and the owner pays from the bank looking at
 * «A pagar», which does (`PayrollAdvanceProjection`, 2026-11-08). A gross
 * figure on the phone would invite paying an advance twice.
 */

export interface PayrollVoucherPushRow {
  id: string;
  tenant_id: string | null;
  voucher_number?: string | null;
  period_label?: string | null;
  status?: string | null;
  created_by?: string | null;
  created_at?: string | null;
}

export interface PayrollVoucherPushLine {
  employee_name?: string | null;
  payment_method?: string | null;
  total_amount?: number | string | null;
  is_included?: boolean | null;
}

export interface PayrollPayerProfile {
  user_id?: string | null;
  role?: string | null;
  is_active?: boolean | null;
  permissions?: unknown;
}

export interface PayrollVoucherPush {
  title: string;
  body: string;
  route: string;
  tag: string;
  data: Record<string, string>;
}

/**
 * A draft saved longer ago than this is not news. A restored backup inserts
 * old drafts again with the triggers alive; the trigger already skips them by
 * the same rule, and this repeats it for a late or replayed request.
 */
export const PAYROLL_ALERT_FRESH_MS = 60 * 60 * 1000;

/** The roles `can_manage_tenant_accounting` lets pay a payroll. */
export const PAYROLL_PAYER_ROLES = ["admin", "manager", "accountant"];

/** More people than this are counted instead of named. */
const MAX_NAMED_PEOPLE = 4;

/**
 * Whether the voucher is a payroll just saved and still waiting to be paid.
 * A request that arrives after it was deleted, confirmed or paid finds
 * nothing to do and rings no phone.
 */
export function payrollVoucherIsNew(
  row: PayrollVoucherPushRow,
  now: Date,
): boolean {
  if (row.status !== "draft") return false;
  const created = Date.parse(row.created_at ?? "");
  if (!Number.isFinite(created)) return false;
  return now.getTime() - created <= PAYROLL_ALERT_FRESH_MS;
}

function record(value: unknown): Record<string, unknown> {
  return value != null && typeof value === "object" && !Array.isArray(value)
    ? value as Record<string, unknown>
    : {};
}

/**
 * Who gets the alert: whoever the database lets pay a payroll
 * (`can_manage_tenant_payroll`: an active admin, manager or accountant, or
 * someone with `access_accounting`), except whoever saved it. The one who
 * just made it does not need to be told.
 */
export function payrollPayerIds(
  profiles: PayrollPayerProfile[],
  creatorId: string | null | undefined,
): string[] {
  const ids = new Set<string>();
  for (const profile of profiles) {
    const userId = profile.user_id;
    if (!userId || userId === creatorId) continue;
    if (profile.is_active !== true) continue;
    const pays = PAYROLL_PAYER_ROLES.includes(profile.role ?? "") ||
      record(profile.permissions).access_accounting === true;
    if (pays) ids.add(userId);
  }
  return [...ids];
}

function clean(value: unknown): string {
  if (typeof value !== "string") return "";
  return value.replaceAll(/[\r\n\t]+/g, " ").replaceAll(/\s+/g, " ").trim()
    .slice(0, 80);
}

function firstName(name: string): string {
  return name.split(" ")[0] ?? name;
}

/**
 * The people this payroll pays, by first name (the full name only when two
 * share it), and «(efectivo)» for whoever is paid in cash, since the owner
 * transfers to the rest. A line left out or worth nothing is not paid.
 */
export function payrollPeople(lines: PayrollVoucherPushLine[]): string[] {
  const paid = lines.flatMap((line) => {
    const name = clean(line.employee_name);
    const amount = Number(line.total_amount ?? 0);
    if (line.is_included === false || !name) return [];
    if (!Number.isFinite(amount) || amount <= 0) return [];
    return [{ name, cash: line.payment_method === "cash" }];
  });
  const firstNames = paid.map((person) => firstName(person.name));
  return paid
    .map((person, index) => {
      const shared = firstNames.filter((first) =>
        first === firstNames[index]
      ).length > 1;
      const shown = shared ? person.name : firstNames[index];
      return person.cash ? `${shown} (efectivo)` : shown;
    })
    .sort((a, b) => a.localeCompare(b, "es"));
}

function joinNames(names: string[]): string {
  if (names.length <= 1) return names.join("");
  return `${names.slice(0, -1).join(", ")} y ${names[names.length - 1]}`;
}

/**
 * Title, text and destination of the alert: the payroll itself, where «A
 * pagar» already subtracts the advances.
 */
export function buildPayrollVoucherPush(
  row: PayrollVoucherPushRow,
  facts: { people: string[]; creatorName?: string | null },
): PayrollVoucherPush {
  const title = "Nómina lista para pagar";
  const period = clean(row.period_label) || clean(row.voucher_number);
  const people = facts.people.length > MAX_NAMED_PEOPLE
    ? `${facts.people.length} personas`
    : joinNames(facts.people);
  const head = [period, people].filter((part) => part.length > 0).join(" · ");
  const creator = clean(facts.creatorName);
  const body = [
    head ? `${head}.` : "",
    creator ? `La hizo ${creator}.` : "",
  ].filter((part) => part.length > 0).join(" ") ||
    "Ábrela para ver cuánto transferir.";
  const route = `/hr/payroll?voucher=${row.id}`;
  return {
    title,
    body,
    route,
    // A repeated request for the same payroll replaces its alert.
    tag: `payroll-voucher-${row.id}`,
    data: {
      kind: "payroll_voucher",
      voucher_id: row.id,
      route,
      title,
      body,
    },
  };
}

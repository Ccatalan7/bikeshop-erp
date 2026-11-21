import {
  buildPayrollVoucherPush,
  payrollPayerIds,
  payrollPeople,
  payrollVoucherIsNew,
} from "./payroll_voucher_push.ts";
import type {
  PayrollPayerProfile,
  PayrollVoucherPushLine,
  PayrollVoucherPushRow,
} from "./payroll_voucher_push.ts";

function assertEquals(actual: unknown, expected: unknown, message: string) {
  const actualJson = JSON.stringify(actual);
  const expectedJson = JSON.stringify(expected);
  if (actualJson !== expectedJson) {
    throw new Error(
      `${message}: expected ${expectedJson}, received ${actualJson}`,
    );
  }
}

const SAVED_AT = "2026-11-16T16:11:00.000Z";
const NOW = new Date("2026-11-16T16:11:20.000Z");

function voucher(
  overrides: Partial<PayrollVoucherPushRow> = {},
): PayrollVoucherPushRow {
  return {
    id: "voucher-048",
    tenant_id: "tenant-a",
    voucher_number: "NOM-00048",
    period_label: "Semana 46 · 09 – 15 nov",
    status: "draft",
    created_by: "user-vicente",
    created_at: SAVED_AT,
    ...overrides,
  };
}

// The week of 2026-11-16 as it was saved: two out, one in cash.
const LINES: PayrollVoucherPushLine[] = [
  {
    employee_name: "Vicente Díaz",
    payment_method: "transfer",
    total_amount: "150360.00",
    is_included: true,
  },
  {
    employee_name: "Rodrigo Guillermo Nieto",
    payment_method: "cash",
    total_amount: 53000,
    is_included: true,
  },
  {
    employee_name: "Braulio Muñoz",
    payment_method: "transfer",
    total_amount: 56350,
    is_included: true,
  },
  {
    employee_name: "Fernando José Tapia Carrillo",
    payment_method: "transfer",
    total_amount: 0,
    is_included: false,
  },
  {
    employee_name: "Lucas Pacheco",
    payment_method: "transfer",
    total_amount: "0.00",
    is_included: false,
  },
];

Deno.test("a payroll just saved as a draft rings", () => {
  assertEquals(payrollVoucherIsNew(voucher(), NOW), true, "fresh draft");
});

Deno.test("a payroll that is no longer a draft, or is old, does not ring", () => {
  for (const status of ["confirmed", "partial", "paid", "voided", null]) {
    assertEquals(
      payrollVoucherIsNew(voucher({ status }), NOW),
      false,
      `status ${status}`,
    );
  }
  // A restored backup brings back drafts saved weeks ago.
  assertEquals(
    payrollVoucherIsNew(
      voucher({ created_at: "2026-10-25T17:34:00.000Z" }),
      NOW,
    ),
    false,
    "restored draft",
  );
  assertEquals(
    payrollVoucherIsNew(voucher({ created_at: null }), NOW),
    false,
    "no date",
  );
  assertEquals(
    payrollVoucherIsNew(
      voucher(),
      new Date(Date.parse(SAVED_AT) + 61 * 60 * 1000),
    ),
    false,
    "an hour late",
  );
});

Deno.test("whoever can pay a payroll gets it, except whoever made it", () => {
  const profiles: PayrollPayerProfile[] = [
    { user_id: "user-owner", role: "admin", is_active: true },
    { user_id: "user-vicente", role: "admin", is_active: true },
    { user_id: "user-old", role: "admin", is_active: false },
    { user_id: "user-legacy", role: "admin", is_active: null },
    { user_id: "user-books", role: "accountant", is_active: true },
    { user_id: "user-boss", role: "manager", is_active: true },
    { user_id: "user-mechanic", role: "mechanic", is_active: true },
    {
      user_id: "user-cashier-books",
      role: "cashier",
      is_active: true,
      permissions: { access_accounting: true },
    },
    {
      user_id: "user-cashier",
      role: "cashier",
      is_active: true,
      permissions: { access_accounting: false },
    },
    { user_id: null, role: "admin", is_active: true },
    { user_id: "user-owner", role: "admin", is_active: true },
  ];
  assertEquals(
    payrollPayerIds(profiles, "user-vicente"),
    ["user-owner", "user-books", "user-boss", "user-cashier-books"],
    "payers",
  );
  assertEquals(
    payrollPayerIds(profiles, null).includes("user-vicente"),
    true,
    "without a known author every payer is told",
  );
});

Deno.test("the alert names who to pay, never an amount", () => {
  const people = payrollPeople(LINES);
  assertEquals(
    people,
    ["Braulio", "Rodrigo (efectivo)", "Vicente"],
    "people",
  );
  const push = buildPayrollVoucherPush(voucher(), {
    people,
    creatorName: "Vicente",
  });
  assertEquals(push.title, "Nómina lista para pagar", "title");
  assertEquals(
    push.body,
    "Semana 46 · 09 – 15 nov · Braulio, Rodrigo (efectivo) y Vicente. La hizo Vicente.",
    "body",
  );
  assertEquals(/\$|\d{3}\.\d{3}/.test(push.body), false, "no money");
  assertEquals(push.route, "/hr/payroll?voucher=voucher-048", "route");
  assertEquals(push.tag, "payroll-voucher-voucher-048", "tag");
  assertEquals(
    push.data,
    {
      kind: "payroll_voucher",
      voucher_id: "voucher-048",
      route: "/hr/payroll?voucher=voucher-048",
      title: "Nómina lista para pagar",
      body: push.body,
    },
    "data",
  );
});

Deno.test("two people with the same first name keep their full names", () => {
  assertEquals(
    payrollPeople([
      { employee_name: "Juan Pérez", total_amount: 1, is_included: true },
      { employee_name: "Juan Soto", total_amount: 1, is_included: true },
      { employee_name: "Ana  Rojas\n", total_amount: 1, is_included: true },
    ]),
    ["Ana", "Juan Pérez", "Juan Soto"],
    "shared first name",
  );
});

Deno.test("a long payroll is counted, and a missing author is left out", () => {
  const people = ["Ana", "Beto", "Caro", "Dani", "Eli"];
  assertEquals(
    buildPayrollVoucherPush(voucher(), { people, creatorName: null }).body,
    "Semana 46 · 09 – 15 nov · 5 personas.",
    "five people",
  );
  assertEquals(
    buildPayrollVoucherPush(voucher({ period_label: null }), {
      people: ["Ana"],
    }).body,
    "NOM-00048 · Ana.",
    "no label",
  );
  assertEquals(
    buildPayrollVoucherPush(
      voucher({ period_label: null, voucher_number: null }),
      { people: [] },
    ).body,
    "Ábrela para ver cuánto transferir.",
    "nothing to name",
  );
});

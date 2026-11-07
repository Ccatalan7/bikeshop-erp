import {
  buildMailSummaryPush,
  MAIL_SUMMARY_ROLES,
} from "./mail_summary_push.ts";

function assertEquals(actual: unknown, expected: unknown) {
  const actualJson = JSON.stringify(actual);
  const expectedJson = JSON.stringify(expected);
  if (actualJson !== expectedJson) {
    throw new Error(`expected ${expectedJson}, received ${actualJson}`);
  }
}

Deno.test("nothing to do rings no phone", () => {
  assertEquals(buildMailSummaryPush({ today: 0 }, "2026-11-06"), null);
  assertEquals(buildMailSummaryPush({}, "2026-11-06"), null);
});

Deno.test("the summary names what came in and what weighs most", () => {
  const push = buildMailSummaryPush({
    today: 7,
    payments: 2,
    payments_amount: 63990,
    invoices: 2,
    customers: 1,
    follow_ups: 2,
    transfers_24h: 2,
    transfers_24h_amount: 63990,
  }, "2026-11-06");
  assertEquals(push?.title, "Correo: 7 cosas para hoy");
  assertEquals(
    push?.body,
    "Desde ayer entraron $63.990 en 2 transferencias. Para hoy: 2 pagos por " +
      "confirmar ($63.990), 2 facturas por registrar, 1 cliente espera " +
      "respuesta y 1 más.",
  );
  assertEquals(push?.route, "/mail");
  assertEquals(push?.tag, "mail-summary-2026-11-06");
  assertEquals(push?.data.type, "mail");
  assertEquals(push?.data.route, "/mail");
});

Deno.test("one thing reads in the singular, without the overnight line", () => {
  const push = buildMailSummaryPush(
    { today: 1, follow_ups: 1 },
    "2026-11-07",
  );
  assertEquals(push?.title, "Correo: 1 cosa para hoy");
  assertEquals(push?.body, "Para hoy: 1 seguimiento por atender.");
});

Deno.test("only the office phones ring", () => {
  assertEquals(MAIL_SUMMARY_ROLES.includes("mechanic"), false);
  assertEquals(MAIL_SUMMARY_ROLES.includes("admin"), true);
});

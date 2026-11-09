import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  classifyJobActionFailure,
  describeJobActionRefusal,
  jobActionRefusalNotice,
} from "./whatsapp_job_action_refusal.ts";

Deno.test("a business refusal from the database is not retried", () => {
  for (const code of ["23514", "42501", "22023", "P0001"]) {
    assertEquals(
      classifyJobActionFailure({ code, message: "La cotización ya no está pendiente" }),
      { kind: "refused", code, detail: "La cotización ya no está pendiente" },
    );
  }
});

Deno.test("a failure that may pass on a redelivery stays retryable", () => {
  for (const code of ["40001", "40P01", "57014", "08006", "53300", "PGRST301", ""]) {
    assertEquals(
      classifyJobActionFailure({ code, message: "boom" }).kind,
      "transient",
    );
  }
  assertEquals(classifyJobActionFailure(new TypeError("fetch failed")), {
    kind: "transient",
    detail: "fetch failed",
  });
  assertEquals(classifyJobActionFailure(null).kind, "transient");
});

Deno.test("the workshop reads the refusal in its own words", () => {
  assertEquals(
    describeJobActionRefusal("WhatsApp action request already has a terminal response"),
    "La tarjeta ya tenía otra respuesta del cliente.",
  );
  assertEquals(
    describeJobActionRefusal("WhatsApp action request was superseded by a newer card"),
    "Respondió un presupuesto anterior: ya tiene uno más nuevo.",
  );
  assertEquals(
    describeJobActionRefusal("La cotización venció y requiere revisión del taller"),
    "El presupuesto estaba vencido.",
  );
  assertEquals(
    describeJobActionRefusal("Workshop record does not belong to the active tenant"),
    "La base lo rechazó: Workshop record does not belong to the active tenant",
  );
});

Deno.test("the notice names the job and the button the customer tapped", () => {
  assertEquals(
    jobActionRefusalNotice({
      jobNumber: "PG-00672",
      action: "approve_quote",
      buttonText: "Aprobar presupuesto",
      detail: "La cotización ya no está pendiente",
    }),
    {
      title: "PG-00672: «Aprobar presupuesto» no se aplicó",
      body: "El cliente lo tocó en WhatsApp. El presupuesto ya no estaba pendiente.",
    },
  );
  assertEquals(
    jobActionRefusalNotice({
      jobNumber: null,
      action: "confirm_delivery",
      buttonText: " ",
      detail: "El trabajo aún no está terminado para confirmar entrega",
    }).title,
    "Un trabajo: «Confirmar entrega» no se aplicó",
  );
});

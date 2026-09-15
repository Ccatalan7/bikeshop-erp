import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  buildDirectSendUtilityPayload,
  directSendUtilityStrategy,
  resolveDirectSendUtility,
} from "./whatsapp_direct_send.ts";

const utilityRequest = {
  deliveryStrategy: directSendUtilityStrategy,
  type: "template",
  templateName: "actualizacion_servicio_bicicleta",
  templateLanguage: "es_CL",
  templateComponents: [{
    type: "body",
    parameters: [
      { type: "text", text: "Claudio" },
      { type: "text", text: "Viñabike" },
    ],
  }],
};

Deno.test("Direct Send reconstructs registered utility body on the server", () => {
  assertEquals(resolveDirectSendUtility(utilityRequest), {
    requested: true,
    enabled: true,
    reason: "eligible",
    body:
      "Hola Claudio, tenemos una actualización sobre tu bicicleta en Viñabike. Responde este mensaje para continuar la conversación.",
    templateName: "actualizacion_servicio_bicicleta",
  });
});

Deno.test("existing ERP clients inherit Direct Send for known utility templates", () => {
  const result = resolveDirectSendUtility({
    ...utilityRequest,
    deliveryStrategy: undefined,
  });

  assertEquals(result.enabled, true);
  assertEquals(result.requested, true);
});

Deno.test("Direct Send rejects marketing templates", () => {
  const result = resolveDirectSendUtility({
    ...utilityRequest,
    templateName: "proveedor_saludo_v1",
    templateComponents: [{
      type: "body",
      parameters: [{ type: "text", text: "Felipe" }],
    }],
  });

  assertEquals(result.enabled, false);
  assertEquals(result.reason, "template_not_registered_as_utility");
});

Deno.test("Direct Send cannot label arbitrary text as utility", () => {
  const result = resolveDirectSendUtility({
    deliveryStrategy: directSendUtilityStrategy,
    type: "text",
    templateName: "actualizacion_servicio_bicicleta",
    templateLanguage: "es_CL",
    templateComponents: utilityRequest.templateComponents,
  });

  assertEquals(result.enabled, false);
  assertEquals(result.reason, "not_a_template");
});

Deno.test("Direct Send utility payload omits unsupported link previews", () => {
  assertEquals(
    buildDirectSendUtilityPayload({
      to: "56912345678",
      body: "Revisa https://vinabike.cl/p/123",
    }),
    {
      messaging_product: "whatsapp",
      recipient_type: "individual",
      to: "56912345678",
      type: "text",
      text: { body: "Revisa https://vinabike.cl/p/123" },
      category: "utility",
    },
  );
});

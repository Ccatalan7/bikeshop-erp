import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  acceptedMessageId,
  parsePhoneVerificationRequest,
  phoneVerificationMessage,
  phoneVerificationRefusal,
} from "./customer_phone_verification.ts";
import {
  buildAuthenticationTemplateComponents,
  findWhatsAppTemplate,
  phoneVerificationTemplateName,
} from "./whatsapp_templates.ts";

const tenant = "5443b130-cc28-45af-a420-cd500b288890";

Deno.test("la llamada trae una tienda y un número usables", () => {
  assertEquals(parsePhoneVerificationRequest({ tenantId: tenant, phone: "+56 9 1234 5678" }), {
    tenantId: tenant,
    phone: "+56 9 1234 5678",
  });
  assertEquals(parsePhoneVerificationRequest({ tenantId: "x", phone: "+56912345678" }), null);
  assertEquals(parsePhoneVerificationRequest({ tenantId: tenant, phone: "123" }), null);
  assertEquals(parsePhoneVerificationRequest({ tenantId: tenant, phone: "9".repeat(41) }), null);
  assertEquals(parsePhoneVerificationRequest(null), null);
});

Deno.test("al portal no vuelve el código: sólo qué pasó", () => {
  assertEquals(phoneVerificationRefusal({ status: "issued", code: "123456" }), null);
  assertEquals(phoneVerificationRefusal({ status: "too_soon", retry_after_seconds: 42 }), {
    status: "too_soon",
    retry_after_seconds: 42,
  });
  assertEquals(phoneVerificationRefusal({ status: "invalid_phone" }), { status: "invalid_phone" });
  assertEquals(phoneVerificationRefusal({ status: "disabled" }), { status: "disabled" });
  assertEquals(phoneVerificationRefusal({ status: "otra cosa" }), { status: "unavailable" });
});

Deno.test("el código va en el texto y en el botón que lo copia", () => {
  const message = phoneVerificationMessage("56912345678", "482913");
  assertEquals(message, {
    messaging_product: "whatsapp",
    recipient_type: "individual",
    to: "56912345678",
    type: "template",
    template: {
      name: "codigo_verificacion_v1",
      language: { code: "es_CL" },
      components: [
        { type: "body", parameters: [{ type: "text", text: "482913" }] },
        {
          type: "button",
          sub_type: "url",
          index: "0",
          parameters: [{ type: "text", text: "482913" }],
        },
      ],
    },
  });
});

Deno.test("la plantilla se crea como de autenticación, con vencimiento y botón de copiar", () => {
  const template = findWhatsAppTemplate(phoneVerificationTemplateName);
  assertEquals(template?.category, "AUTHENTICATION");
  assertEquals(buildAuthenticationTemplateComponents(template!.authentication!), [
    { type: "BODY", add_security_recommendation: true },
    { type: "FOOTER", code_expiration_minutes: 10 },
    {
      type: "BUTTONS",
      buttons: [{ type: "OTP", otp_type: "COPY_CODE", text: "Copiar código" }],
    },
  ]);
});

Deno.test("sólo un mensaje con id cuenta como aceptado", () => {
  assertEquals(acceptedMessageId({ messages: [{ id: "wamid.ABC" }] }), "wamid.ABC");
  assertEquals(acceptedMessageId({ messages: [] }), null);
  assertEquals(acceptedMessageId({ error: { code: 132001 } }), null);
});

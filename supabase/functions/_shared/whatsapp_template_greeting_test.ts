import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  normalizeWhatsAppTemplateGreeting,
  resolveWhatsAppTemplateGreetingName,
} from "./whatsapp_template_greeting.ts";

Deno.test("WhatsApp template greeting preserves compound given names", () => {
  assertEquals(resolveWhatsAppTemplateGreetingName("José Luis Campodónico"), "José Luis");
  assertEquals(resolveWhatsAppTemplateGreetingName("Jose Luis Campodónico"), "Jose Luis");
  assertEquals(resolveWhatsAppTemplateGreetingName("Juan Pablo González Pérez"), "Juan Pablo");
  assertEquals(resolveWhatsAppTemplateGreetingName("Ana María Muñoz"), "Ana María");
  assertEquals(resolveWhatsAppTemplateGreetingName("Paul Calderón"), "Paul");
  assertEquals(resolveWhatsAppTemplateGreetingName("Pedro González Pérez"), "Pedro");
});

Deno.test("WhatsApp transport normalizes body and durable caption without renaming binding", () => {
  const request = {
    type: "template",
    contactName: "Jose Luis Campodónico",
    caption:
      "Hola Jose Luis Campodónico, buen día. Soy parte del equipo de Viñabike y te escribo por el servicio de tu bicicleta.",
    metadata: { template_purpose: "first_contact" },
    templateComponents: [{
      type: "body",
      parameters: [
        { type: "text", text: "Jose Luis Campodónico" },
        { type: "text", text: "parte del equipo" },
      ],
    }],
  };

  const normalized = normalizeWhatsAppTemplateGreeting(request);
  assertEquals(normalized.contactName, "Jose Luis Campodónico");
  assertEquals(
    normalized.caption,
    "Hola Jose Luis, buen día. Soy parte del equipo de Viñabike y te escribo por el servicio de tu bicicleta.",
  );
  assertEquals(
    (normalized.templateComponents[0].parameters[0] as { text: string }).text,
    "Jose Luis",
  );
  assertEquals(
    (request.templateComponents[0].parameters[0] as { text: string }).text,
    "Jose Luis Campodónico",
  );
});

Deno.test("WhatsApp transport leaves unrelated templates untouched", () => {
  const request = {
    type: "template",
    caption: "Código: 123456",
    metadata: { template_purpose: "authentication" },
    templateComponents: [{
      type: "body",
      parameters: [{ type: "text", text: "123456" }],
    }],
  };

  assertEquals(normalizeWhatsAppTemplateGreeting(request), request);
});

Deno.test("WhatsApp transport keeps the greeting chosen in the contact's sheet", () => {
  // «María José» a secas son dos palabras: la regla de nombres la cortaba a
  // «María». Con la marca de la app, va tal cual.
  const request = {
    type: "template",
    caption: "Hola María José, buen día.",
    metadata: {
      template_purpose: "supplier_greeting",
      greeting_name_source: "contact_preference",
    },
    templateComponents: [{
      type: "body",
      parameters: [{ type: "text", text: "María José" }],
    }],
  };

  assertEquals(normalizeWhatsAppTemplateGreeting(request), request);
});

Deno.test("WhatsApp transport still trims a supplier greeting without the mark", () => {
  // Una app sin esta versión manda el nombre sin la marca: se normaliza como
  // siempre.
  const request = {
    type: "template",
    caption: "Hola Paul Calderón, buen día.",
    metadata: { template_purpose: "supplier_greeting" },
    templateComponents: [{
      type: "body",
      parameters: [{ type: "text", text: "Paul Calderón" }],
    }],
  };

  const normalized = normalizeWhatsAppTemplateGreeting(request);
  assertEquals(normalized.caption, "Hola Paul, buen día.");
  assertEquals(
    (normalized.templateComponents[0].parameters[0] as { text: string }).text,
    "Paul",
  );
});

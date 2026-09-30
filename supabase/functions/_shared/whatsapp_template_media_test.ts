import {
  assert,
  assertEquals,
} from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  directSendUtilityStrategy,
  resolveDirectSendUtility,
} from "./whatsapp_direct_send.ts";
import { normalizeWhatsAppTemplateGreeting } from "./whatsapp_template_greeting.ts";
import {
  templateMediaHeader,
  withTemplateDocumentHeader,
} from "./whatsapp_template_media.ts";
import {
  buildSamplePdf,
  documentAttachedTemplateName,
  findWhatsAppTemplate,
} from "./whatsapp_templates.ts";

Deno.test("sólo la plantilla del catálogo con encabezado lleva archivo", () => {
  const header = templateMediaHeader({
    type: "template",
    templateName: documentAttachedTemplateName,
    templateLanguage: "es_CL",
  });
  assertEquals(header?.format, "DOCUMENT");
  assertEquals(header?.acceptedContentTypes, ["application/pdf"]);
  assertEquals(
    templateMediaHeader({
      type: "template",
      templateName: "seguimiento_servicio_bicicleta",
      templateLanguage: "es_CL",
    }),
    undefined,
  );
  assertEquals(
    templateMediaHeader({ type: "document", templateName: documentAttachedTemplateName }),
    undefined,
  );
});

Deno.test("el encabezado lo arma el servidor y descarta el del llamador", () => {
  const components = withTemplateDocumentHeader(
    [
      {
        type: "HEADER",
        parameters: [{ type: "document", document: { link: "https://ajeno.example/x.pdf" } }],
      },
      { type: "body", parameters: [{ type: "text", text: "Claudio" }] },
    ],
    "media-123",
    "presupuesto.pdf",
  );
  assertEquals(components, [
    {
      type: "header",
      parameters: [{
        type: "document",
        document: { id: "media-123", filename: "presupuesto.pdf" },
      }],
    },
    { type: "body", parameters: [{ type: "text", text: "Claudio" }] },
  ]);
});

Deno.test("una plantilla con archivo nunca sale por Direct Send", () => {
  const resolution = resolveDirectSendUtility({
    deliveryStrategy: directSendUtilityStrategy,
    type: "template",
    templateName: documentAttachedTemplateName,
    templateLanguage: "es_CL",
    templateComponents: [{
      type: "body",
      parameters: [{ type: "text", text: "Claudio" }],
    }],
  });
  assertEquals(resolution.enabled, false);
});

Deno.test("la plantilla con archivo saluda por el nombre de pila", () => {
  const normalized = normalizeWhatsAppTemplateGreeting({
    type: "template",
    templateName: documentAttachedTemplateName,
    caption: "Hola Marcelo Silva, te enviamos el documento adjunto desde Viñabike.",
    templateComponents: [{
      type: "body",
      parameters: [{ type: "text", text: "Marcelo Silva" }],
    }],
    metadata: { template_purpose: "document_attached" },
  });
  const body = (normalized.templateComponents as Array<Record<string, unknown>>)[0];
  assertEquals((body.parameters as Array<Record<string, unknown>>)[0].text, "Marcelo");
  assert(String(normalized.caption).startsWith("Hola Marcelo,"));
});

Deno.test("el ejemplo para Meta es un PDF con su tabla de referencias al día", () => {
  const header = findWhatsAppTemplate(documentAttachedTemplateName, "es_CL")?.header;
  assert(header);
  const pdf = new TextDecoder().decode(buildSamplePdf(header.sampleLines));
  assert(pdf.startsWith("%PDF-1.4\n"));
  assert(pdf.trimEnd().endsWith("%%EOF"));
  const startXref = Number(pdf.match(/startxref\n(\d+)\n/)?.[1]);
  assertEquals(pdf.slice(startXref, startXref + 4), "xref");
  const offsets = [...pdf.matchAll(/^(\d{10}) 00000 n $/gm)].map((match) => Number(match[1]));
  assertEquals(offsets.length, 5);
  offsets.forEach((offset, index) => {
    assertEquals(pdf.slice(offset, offset + `${index + 1} 0 obj`.length), `${index + 1} 0 obj`);
  });
  const length = Number(pdf.match(/\/Length (\d+)/)?.[1]);
  const stream = pdf.slice(pdf.indexOf("stream\n") + 7, pdf.indexOf("\nendstream"));
  assertEquals(stream.length, length);
});

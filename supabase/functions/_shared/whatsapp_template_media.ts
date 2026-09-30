import {
  findWhatsAppTemplate,
  type TemplateHeaderDefinition,
} from "./whatsapp_templates.ts";

/// El encabezado con archivo de la plantilla pedida, si el catálogo le da
/// uno. Lo decide el catálogo del servidor, nunca el llamador: un cliente no
/// puede convertir una plantilla de texto en una con archivo.
export function templateMediaHeader(request: {
  type?: string;
  templateName?: string;
  templateLanguage?: string;
}): TemplateHeaderDefinition | undefined {
  if (request.type !== "template") return undefined;
  return findWhatsAppTemplate(request.templateName, request.templateLanguage)
    ?.header;
}

/// Los componentes de una plantilla con encabezado de documento: el
/// encabezado lo arma el servidor con el archivo ya validado y subido a Meta
/// ([mediaId]); cualquier encabezado que traiga el llamador se descarta, para
/// que nadie mande un enlace o un medio ajeno en nombre del taller.
export function withTemplateDocumentHeader(
  components: readonly unknown[] | undefined,
  mediaId: string,
  filename: string,
): unknown[] {
  const rest = (components ?? []).filter((component) =>
    !(component && typeof component === "object" &&
      String((component as Record<string, unknown>).type ?? "").toLowerCase() ===
        "header")
  );
  return [
    {
      type: "header",
      parameters: [
        { type: "document", document: { id: mediaId, filename } },
      ],
    },
    ...rest,
  ];
}

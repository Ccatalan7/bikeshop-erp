// Las plantillas aprobadas de WhatsApp viven aquí y en un solo lugar: las usa
// el gestor de plantillas para desplegarlas en Meta, y el asistente para
// previsualizar EXACTAMENTE lo que le llegará al cliente antes de enviar.
// Duplicarlas sería garantizar que un día digan cosas distintas.

/// Un encabezado con archivo: el documento viaja dentro de la plantilla. Es la
/// única forma de mandarle un archivo a quien no escribió en las últimas 24 h
/// (fuera de esa ventana Meta rechaza un documento suelto).
export interface TemplateHeaderDefinition {
  format: "DOCUMENT";
  /// Lo que Meta acepta en un encabezado DOCUMENT: sólo PDF.
  acceptedContentTypes: readonly string[];
  /// El PDF de ejemplo que se sube con la plantilla para la revisión de Meta.
  sampleFilename: string;
  sampleLines: readonly string[];
}

export interface TemplateDefinition {
  name: string;
  language: string;
  category: "UTILITY" | "MARKETING" | "AUTHENTICATION";
  body: string;
  examples: string[];
  allowCategoryChange?: boolean;
  header?: TemplateHeaderDefinition;
}

/// La plantilla con PDF adjunto: cliente o proveedor que no ha escrito en 24 h.
export const documentAttachedTemplateName = "documento_adjunto_v1";

/// El pedido de reseña de Google que sale solo después de una entrega.
export const reviewRequestTemplateName = "resena_google_v1";

export const defaultWhatsAppTemplates: TemplateDefinition[] = [
  {
    // Quien escribe se presenta por su nombre: al cliente le habla una persona
    // del taller, no un sistema. Dos parámetros —cliente y quien escribe—
    // porque así está aprobada y así la manda `contactAndAgent`; el negocio va
    // en el texto, no como parámetro.
    name: "seguimiento_servicio_bicicleta",
    language: "es_CL",
    category: "UTILITY",
    body:
      "Hola {{1}}, hablas con {{2}} de Viñabike. Te escribo por el servicio de tu bicicleta.",
    examples: ["Claudio", "Claudio Catalán"],
  },
  {
    name: "actualizacion_servicio_bicicleta",
    language: "es_CL",
    category: "UTILITY",
    body:
      "Hola {{1}}, tenemos una actualización sobre tu bicicleta en {{2}}. Responde este mensaje para continuar la conversación.",
    examples: ["Claudio", "Vinabike"],
  },
  {
    name: "bicicleta_lista_retiro",
    language: "es_CL",
    category: "UTILITY",
    body:
      "Hola {{1}}, tu bicicleta está lista para retiro en {{2}}. Responde este mensaje si necesitas coordinar algo.",
    examples: ["Claudio", "Vinabike"],
  },
  {
    name: "seguimiento_presupuesto_bicicleta",
    language: "es_CL",
    category: "UTILITY",
    body:
      "Hola {{1}}, necesitamos tu respuesta sobre un presupuesto o aprobación pendiente en {{2}}. Responde este mensaje para continuar.",
    examples: ["Claudio", "Vinabike"],
  },
  {
    name: "proveedor_presentacion_nuevo_numero_v1",
    language: "es_CL",
    category: "MARKETING",
    body:
      "Hola {{1}}, buen día. Soy {{2}}, del equipo de Viñabike en Viña del Mar, razón social NEWEN SpA. Con nuestro equipo estamos usando este nuevo número para comunicarnos con nuestros proveedores, así que quería presentarme y confirmar que podemos coordinarnos por aquí para compras, cotizaciones, documentos y despachos.\n\nQuedo atento. Saludos.",
    examples: ["Felipe", "Claudio"],
  },
  {
    name: "proveedor_saludo_v1",
    language: "es_CL",
    category: "MARKETING",
    body: "Hola {{1}}, buen día.",
    examples: ["Felipe"],
  },
  {
    name: "proveedor_retomar_contacto_v1",
    language: "es_CL",
    category: "MARKETING",
    body: "Hola {{1}}, buen día. Cuando puedas me hablas, porfa. Quedo atento. Saludos.",
    examples: ["Felipe"],
  },
  {
    name: "proveedor_consulta_novedades_v1",
    language: "es_CL",
    category: "MARKETING",
    body:
      "Hola {{1}}, buen día. Cuando puedas me cuentas si hay alguna novedad, porfa. Quedo atento. Saludos.",
    examples: ["Felipe"],
  },
  {
    name: "proveedor_pedido_pendiente_v3",
    language: "es_CL",
    category: "UTILITY",
    body:
      "Hola {{1}}, buen día. Te escribo para seguir con el pedido que tenemos pendiente. Cuando puedas me hablas, porfa. Quedo atento, saludos.",
    examples: ["Felipe"],
    allowCategoryChange: false,
  },
  {
    // Pedido de reseña de Google después de entregar la bici (2026-10-08).
    // Nombra la atención concreta y no ofrece nada, como pide Meta para un
    // mensaje de servicio; Meta decide la categoría al aprobarla. `{{2}}` es
    // el enlace de reseña del lugar de Google del sitio. Lo manda la base
    // (`process_whatsapp_review_requests_v1`) con este mismo texto: cambiarlo
    // aquí es cambiarlo allá y volver a revisión en Meta.
    name: reviewRequestTemplateName,
    language: "es_CL",
    category: "UTILITY",
    body:
      "Hola {{1}}, ya entregamos tu bicicleta en Viñabike. ¿Cómo te fue con el servicio? Puedes contarnos con una reseña en Google: {{2}} Gracias por preferirnos.",
    examples: [
      "Claudio",
      "https://search.google.com/local/writereview?placeid=ChIJY-oKKDDdiZYRhWzM_W5dB-A",
    ],
  },
  {
    // Sirve igual para un cliente y para un proveedor: el texto no promete
    // nada ni vende, sólo acompaña el archivo que el taller manda. `{{1}}` es
    // el nombre de pila, como en todas las demás (`template_purpose`
    // `document_attached` en whatsapp_template_greeting.ts).
    name: documentAttachedTemplateName,
    language: "es_CL",
    category: "UTILITY",
    body:
      "Hola {{1}}, te enviamos el documento adjunto desde Viñabike. Si tienes dudas, responde este mensaje.",
    examples: ["Claudio"],
    allowCategoryChange: false,
    header: {
      format: "DOCUMENT",
      acceptedContentTypes: ["application/pdf"],
      sampleFilename: "presupuesto_vinabike.pdf",
      sampleLines: [
        "Vinabike - Taller de bicicletas",
        "Presupuesto de ejemplo",
        "Cambio de cassette 11-46 y cadena: $59.990",
      ],
    },
  },
];

/// La definición de una plantilla por nombre e idioma (sin idioma, la primera
/// con ese nombre).
export function findWhatsAppTemplate(
  name: string | undefined | null,
  language?: string | null,
): TemplateDefinition | undefined {
  if (!name) return undefined;
  return defaultWhatsAppTemplates.find((template) =>
    template.name === name && (!language || template.language === language)
  ) ?? defaultWhatsAppTemplates.find((template) => template.name === name);
}

/// Un PDF de una página con [lines], para el ejemplo que Meta revisa junto a
/// una plantilla con encabezado de documento. Texto ASCII: Helvetica estándar
/// sin incrustar fuentes.
export function buildSamplePdf(lines: readonly string[]): Uint8Array {
  const escape = (value: string) =>
    value.replace(/[^\x20-\x7e]/g, "?").replace(/([\\()])/g, "\\$1");
  const text = lines
    .map((line, index) =>
      `BT /F1 ${index === 0 ? 20 : 14} Tf 72 ${760 - index * 32} Td (${escape(line)}) Tj ET`
    )
    .join("\n");
  const objects = [
    "<< /Type /Catalog /Pages 2 0 R >>",
    "<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
    "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 595 842] /Contents 4 0 R " +
    "/Resources << /Font << /F1 5 0 R >> >> >>",
    `<< /Length ${text.length} >>\nstream\n${text}\nendstream`,
    "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>",
  ];
  let pdf = "%PDF-1.4\n";
  const offsets: number[] = [];
  objects.forEach((body, index) => {
    offsets.push(pdf.length);
    pdf += `${index + 1} 0 obj\n${body}\nendobj\n`;
  });
  const xref = pdf.length;
  pdf += `xref\n0 ${objects.length + 1}\n0000000000 65535 f \n`;
  for (const offset of offsets) {
    pdf += `${String(offset).padStart(10, "0")} 00000 n \n`;
  }
  pdf += `trailer\n<< /Size ${objects.length + 1} /Root 1 0 R >>\n` +
    `startxref\n${xref}\n%%EOF\n`;
  return new TextEncoder().encode(pdf);
}

/// Reemplaza los parámetros posicionales `{{1}}`, `{{2}}`… por valores reales.
/// Lo que queda sin valor se deja visible como marcador, nunca en blanco: el
/// operador tiene que ver que ahí falta algo antes de confirmar.
export function renderWhatsAppTemplateBody(
  body: string,
  parameters: readonly string[],
): string {
  return body.replace(/\{\{(\d+)\}\}/g, (match, index) => {
    const value = parameters[Number(index) - 1];
    return value && value.trim() ? value.trim() : match;
  });
}

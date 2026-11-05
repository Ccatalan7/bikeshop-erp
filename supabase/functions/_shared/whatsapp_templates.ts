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

/// Una plantilla de autenticación: Meta fija el texto («123456 es tu código
/// de verificación.»), la recomendación de seguridad y el aviso de
/// vencimiento; el botón copia el código.
export interface TemplateAuthenticationDefinition {
  codeExpirationMinutes: number;
  addSecurityRecommendation: boolean;
  copyCodeButtonText: string;
}

export interface TemplateDefinition {
  name: string;
  language: string;
  category: "UTILITY" | "MARKETING" | "AUTHENTICATION";
  body: string;
  examples: string[];
  allowCategoryChange?: boolean;
  header?: TemplateHeaderDefinition;
  authentication?: TemplateAuthenticationDefinition;
}

/// La plantilla con PDF adjunto: cliente o proveedor que no ha escrito en 24 h.
export const documentAttachedTemplateName = "documento_adjunto_v1";

/// El pedido de reseña de Google que sale solo después de una entrega.
export const reviewRequestTemplateName = "resena_google_v1";

/// El código con que una cuenta del portal confirma su teléfono.
export const phoneVerificationTemplateName = "codigo_verificacion_v1";

/// Los avisos del taller al cliente (20261105130000). Los manda la base
/// (`workshop_notice_dispatch_whatsapp_internal`) con este mismo texto:
/// cambiarlo aquí es cambiarlo allá y volver a revisión en Meta.
export const workshopReceivedTemplateName = "taller_recibida_v1";
export const workshopQuoteReadyTemplateName = "taller_presupuesto_v1";
export const workshopReadyTemplateName = "taller_lista_v1";
export const workshopDeliveredTemplateName = "taller_entregada_v1";
export const workshopNoticeTemplateNames = [
  workshopReceivedTemplateName,
  workshopQuoteReadyTemplateName,
  workshopReadyTemplateName,
  workshopDeliveredTemplateName,
] as const;

export const defaultWhatsAppTemplates: TemplateDefinition[] = [
  {
    // Quien escribe se presenta por su nombre: al cliente le habla una persona
    // del taller, no un sistema. Dos parámetros —cliente y quien escribe—
    // porque así está aprobada y así la manda `contactAndAgent`; el negocio va
    // en el texto, no como parámetro.
    name: "seguimiento_servicio_bicicleta",
    language: "es_CL",
    category: "UTILITY",
    body: "Hola {{1}}, hablas con {{2}} de Viñabike. Te escribo por el servicio de tu bicicleta.",
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
  {
    // La bici recibida (20261105130000). `{{2}}` es lo que dejó: «Trek Marlin
    // 7», «bicicleta» o el elemento de un trabajo de componente; `{{4}}`, la
    // ficha del cliente en la tienda o el enlace para crear su cuenta ligada.
    name: workshopReceivedTemplateName,
    language: "es_CL",
    category: "UTILITY",
    body:
      "Hola {{1}}, recibimos tu {{2}} en Viñabike. Tu número de trabajo es {{3}} y aquí puedes seguir su estado: {{4}} Te avisaremos por este medio cuando esté listo.",
    examples: [
      "Claudio",
      "Trek Marlin 7",
      "PG-00333",
      "https://vinabike.cl/cuenta/vincular#c=Qx7mP2kR9vT4wL8nB3cF6hJ1sD5gY0aZ",
    ],
    allowCategoryChange: false,
  },
  {
    name: workshopQuoteReadyTemplateName,
    language: "es_CL",
    category: "UTILITY",
    body:
      "Hola {{1}}, el presupuesto de tu trabajo {{2}} está listo. Puedes verlo aquí: {{3}} Para aprobarlo o hacer una consulta, responde este mensaje.",
    examples: ["Claudio", "PG-00333", "https://vinabike.cl/cuenta/servicios"],
    allowCategoryChange: false,
  },
  {
    // «tu trabajo… está listo»: sirve igual para una bici y para un componente.
    name: workshopReadyTemplateName,
    language: "es_CL",
    category: "UTILITY",
    body:
      "Hola {{1}}, tu trabajo {{2}} está listo para retirar en Viñabike. El detalle está aquí: {{3}} Si necesitas coordinar el retiro, responde este mensaje.",
    examples: ["Claudio", "PG-00333", "https://vinabike.cl/cuenta/servicios"],
    allowCategoryChange: false,
  },
  {
    // `{{3}}` es la fecha en que vence la garantía del servicio («19 de
    // noviembre»), la del comprobante.
    name: workshopDeliveredTemplateName,
    language: "es_CL",
    category: "UTILITY",
    body:
      "Hola {{1}}, gracias por retirar tu trabajo {{2}}. La garantía del servicio vale hasta el {{3}} y tu comprobante está aquí: {{4}} Gracias por confiar en Viñabike.",
    examples: [
      "Claudio",
      "PG-00333",
      "19 de noviembre",
      "https://vinabike.cl/cuenta/vincular#c=Qx7mP2kR9vT4wL8nB3cF6hJ1sD5gY0aZ",
    ],
    allowCategoryChange: false,
  },
  {
    // El código con que una cuenta del portal confirma su teléfono para
    // quedar con su ficha del taller (`customer-phone-verification`,
    // 20261105010000). Meta fija el texto de una plantilla de autenticación:
    // `body` sólo muestra en el ERP lo que llega, con el código como `{{1}}`.
    name: phoneVerificationTemplateName,
    language: "es_CL",
    category: "AUTHENTICATION",
    body: "{{1}} es tu código de verificación. Por tu seguridad, no lo compartas.",
    examples: ["482913"],
    authentication: {
      codeExpirationMinutes: 10,
      addSecurityRecommendation: true,
      copyCodeButtonText: "Copiar código",
    },
  },
];

/// Lo que Meta pide para crear una plantilla de autenticación: su texto lo
/// pone Meta; aquí van la recomendación, el vencimiento y el botón.
export function buildAuthenticationTemplateComponents(
  authentication: TemplateAuthenticationDefinition,
): Record<string, unknown>[] {
  return [
    {
      type: "BODY",
      add_security_recommendation: authentication.addSecurityRecommendation,
    },
    {
      type: "FOOTER",
      code_expiration_minutes: authentication.codeExpirationMinutes,
    },
    {
      type: "BUTTONS",
      buttons: [{
        type: "OTP",
        otp_type: "COPY_CODE",
        text: authentication.copyCodeButtonText,
      }],
    },
  ];
}

/// El mensaje que manda [code] con una plantilla de autenticación: el código
/// va en el texto y en el botón que lo copia.
export function buildAuthenticationTemplateMessage(params: {
  to: string;
  template: TemplateDefinition;
  code: string;
}): Record<string, unknown> {
  return {
    messaging_product: "whatsapp",
    recipient_type: "individual",
    to: params.to,
    type: "template",
    template: {
      name: params.template.name,
      language: { code: params.template.language },
      components: [
        { type: "body", parameters: [{ type: "text", text: params.code }] },
        {
          type: "button",
          sub_type: "url",
          index: "0",
          parameters: [{ type: "text", text: params.code }],
        },
      ],
    },
  };
}

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

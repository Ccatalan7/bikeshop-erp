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
  /// Quién pone el archivo. Sin esto, el equipo lo adjunta (una reserva
  /// privada de la conversación). `workshop_notice`: lo dibuja el servidor de
  /// la tienda con el código de un solo uso que deja la base en el aviso
  /// (`templateDocumentToken`, 20261107130000); el llamador nunca lo aporta.
  serverDocument?: "workshop_notice";
}

/// Una plantilla de autenticación: Meta fija el texto («123456 es tu código
/// de verificación.»), la recomendación de seguridad y el aviso de
/// vencimiento; el botón copia el código.
export interface TemplateAuthenticationDefinition {
  codeExpirationMinutes: number;
  addSecurityRecommendation: boolean;
  copyCodeButtonText: string;
}

/// Un botón de la plantilla. Uno de link lleva `{{1}}` sólo al final (así lo
/// exige Meta) y el sufijo se manda al enviar sin caracteres especiales: Meta
/// pide codificarlos, y un `#` codificado deja de ser fragmento. Lo fijo del
/// link, `#` incluido, va en `url`. Uno de respuesta rápida contesta con su
/// texto, que llega al chat del ERP.
export type TemplateButtonDefinition =
  | { type: "URL"; text: string; url: string; example?: string }
  | {
    type: "QUICK_REPLY";
    text: string;
    /// La acción del trabajo que dispara al tocarla: whatsapp-send le pone
    /// la clave de un solo uso de la tarjeta (`job:<id>:<acción>:<revisión>`)
    /// y `apply_whatsapp_job_action` la aplica. Sin acción, sólo responde.
    action?: "approve_quote";
  };

export interface TemplateDefinition {
  name: string;
  language: string;
  category: "UTILITY" | "MARKETING" | "AUTHENTICATION";
  body: string;
  examples: string[];
  allowCategoryChange?: boolean;
  header?: TemplateHeaderDefinition;
  authentication?: TemplateAuthenticationDefinition;
  /// El título del mensaje, en negrita (HEADER TEXT, sin parámetros).
  headerText?: string;
  /// Un mapa del lugar arriba del mensaje (HEADER LOCATION); el punto, el
  /// nombre y la dirección se mandan al enviar.
  headerLocation?: boolean;
  /// El pie gris bajo el texto (FOOTER).
  footer?: string;
  buttons?: readonly TemplateButtonDefinition[];
}

/// Una plantilla que es sólo texto: la única que Direct Send puede mandar
/// como texto plano sin perder nada. Con título, mapa, pie, botones o archivo
/// tiene que viajar como plantilla (2026-11-07: los avisos del taller llegaban
/// como texto y su link largo parecía estafa).
export function isPlainBodyTemplate(template: TemplateDefinition): boolean {
  return template.header == null &&
    template.authentication == null &&
    template.headerText == null &&
    template.headerLocation !== true &&
    template.footer == null &&
    (template.buttons?.length ?? 0) === 0;
}

/// Los componentes con que se crea una plantilla en Meta (sin las de
/// autenticación, cuyo texto pone Meta). `headerHandle` es el ejemplo ya
/// subido de un encabezado con archivo.
export function buildTemplateCreationComponents(
  template: TemplateDefinition,
  headerHandle?: string,
): Record<string, unknown>[] {
  const components: Record<string, unknown>[] = [];
  if (template.header) {
    if (!headerHandle) throw new Error("header_handle_required");
    components.push({
      type: "HEADER",
      format: template.header.format,
      example: { header_handle: [headerHandle] },
    });
  } else if (template.headerLocation) {
    components.push({ type: "HEADER", format: "LOCATION" });
  } else if (template.headerText) {
    components.push({ type: "HEADER", format: "TEXT", text: template.headerText });
  }
  components.push({
    type: "BODY",
    text: template.body,
    example: { body_text: [template.examples] },
  });
  if (template.footer) {
    components.push({ type: "FOOTER", text: template.footer });
  }
  if (template.buttons?.length) {
    components.push({
      type: "BUTTONS",
      buttons: template.buttons.map((button) =>
        button.type === "QUICK_REPLY"
          ? { type: "QUICK_REPLY", text: button.text }
          : button.url.includes("{{1}}")
          ? {
            type: "URL",
            text: button.text,
            url: button.url,
            example: [button.url.replace("{{1}}", button.example ?? "")],
          }
          : { type: "URL", text: button.text, url: button.url }
      ),
    });
  }
  return components;
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

/// Los avisos con título, pie y botón (20261107120000; dueño, 2026-11-07:
/// «parecen de esos SPAM que te mandan desde la cárcel»). El link largo sale
/// del texto: el botón lleva al cliente a su ficha con el código como sufijo.
/// «Listo para retirar» trae el mapa del taller arriba del mensaje. La base
/// las prefiere apenas Meta las aprueba; mientras tanto siguen las `_v1`.
export const workshopReceivedV2TemplateName = "taller_recibida_v2";
export const workshopQuoteReadyV2TemplateName = "taller_presupuesto_v2";
export const workshopReadyV2TemplateName = "taller_lista_v2";
export const workshopDeliveredV2TemplateName = "taller_entregada_v2";
export const workshopNoticeV2TemplateNames = [
  workshopReceivedV2TemplateName,
  workshopQuoteReadyV2TemplateName,
  workshopReadyV2TemplateName,
  workshopDeliveredV2TemplateName,
] as const;

/// «Lista para retirar» con el mapa y palabras de retiro (20261107140000):
/// Meta dejó la `_v2` como MARKETING, y un aviso sale sólo con una de
/// servicio (UTILITY).
export const workshopReadyV3TemplateName = "taller_lista_v3";

/// La versión con el PDF arriba (20261107130000; dueño, 2026-11-07, sobre
/// el lienzo premium: «perfecto, me gustaron todos»): el presupuesto con su
/// monto y «Aprobar presupuesto» / «Tengo una consulta», y el comprobante con
/// «Guardar en mi cuenta». El PDF lo dibuja el servidor de la tienda al
/// enviar; la base las prefiere sólo con la tienda lista para dibujarlos.
export const workshopQuotePdfTemplateName = "taller_presupuesto_pdf_v1";
export const workshopDeliveredPdfTemplateName = "taller_entregada_pdf_v1";

/// El pedido de reseña con botón en vez del link de Google en el texto.
export const reviewRequestV2TemplateName = "resena_google_v2";

/// Los avisos con trato humano (dueño, 2026-11-08: «para de centrarte tanto
/// en que lo más importante es el número de trabajo… el contacto humano con
/// el cliente es lo primero»). Nombran la bici o el componente (`{{2}}`, lo
/// mismo que en `taller_recibida_v2`) en vez del número de trabajo, y el
/// presupuesto ya no dice el monto: el número y la plata siguen en el PDF y
/// en la ficha. La base los prefiere apenas Meta los aprueba como UTILITY;
/// mientras tanto siguen los anteriores.
export const workshopReceivedV3TemplateName = "taller_recibida_v3";
export const workshopQuotePdfV2TemplateName = "taller_presupuesto_pdf_v2";
export const workshopReadyV4TemplateName = "taller_lista_v4";
export const workshopDeliveredPdfV2TemplateName = "taller_entregada_pdf_v2";
export const reviewRequestV3TemplateName = "resena_google_v3";

/// El pie de todos los avisos con botón.
export const workshopNoticeFooter = "Viñabike · Taller de bicicletas";

/// El botón de un aviso abre la ficha del cliente en la tienda con un código
/// para crear o entrar a su cuenta (`customer_portal_claim_codes`, 120 días).
/// La dirección fija es la de la tienda al crear la plantilla: si la tienda
/// cambiara de dominio, va una versión nueva.
export const workshopNoticeClaimUrl = "https://vinabike.cl/cuenta/vincular#c={{1}}";
const workshopNoticeClaimExample = "Qx7mP2kR9vT4wL8nB3cF6hJ1sD5gY0aZ";

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
    // La bici recibida, con botón (20261107120000). `{{2}}` es lo mismo que
    // en la v1: «Trek Marlin 7», «bicicleta» o el elemento de un componente.
    name: workshopReceivedV2TemplateName,
    language: "es_CL",
    category: "UTILITY",
    headerText: "Trabajo recibido",
    body:
      "Hola {{1}}, recibimos tu {{2}}. Tu número de trabajo es {{3}} y te avisaremos por aquí cuando esté listo.",
    examples: ["Camila", "Trek Marlin 7", "PG-00671"],
    footer: workshopNoticeFooter,
    buttons: [{
      type: "URL",
      text: "Seguir mi trabajo",
      url: workshopNoticeClaimUrl,
      example: workshopNoticeClaimExample,
    }],
    allowCategoryChange: false,
  },
  {
    name: workshopQuoteReadyV2TemplateName,
    language: "es_CL",
    category: "UTILITY",
    headerText: "Presupuesto listo",
    body:
      "Hola {{1}}, el presupuesto de tu trabajo {{2}} está listo. Revísalo y respóndenos por aquí para aprobarlo o hacer una consulta.",
    examples: ["Camila", "PG-00671"],
    footer: workshopNoticeFooter,
    buttons: [{
      type: "URL",
      text: "Ver presupuesto",
      url: workshopNoticeClaimUrl,
      example: workshopNoticeClaimExample,
    }],
    allowCategoryChange: false,
  },
  {
    // El mapa del taller arriba del mensaje: al tocarlo se abre la
    // navegación (el punto, el nombre y la dirección van al enviar, desde la
    // ficha de Google del sitio). `{{3}}` es el horario de atención como se
    // dice: «de lunes a viernes de 10:30 a 19:00 y los sábados de 10:30 a
    // 15:30».
    name: workshopReadyV2TemplateName,
    language: "es_CL",
    category: "UTILITY",
    headerLocation: true,
    body:
      "Hola {{1}}, tu trabajo {{2}} está listo para retirar. Te esperamos {{3}}. Si necesitas coordinar el retiro, respóndenos por aquí.",
    examples: [
      "Camila",
      "PG-00671",
      "de lunes a viernes de 10:30 a 19:00 y los sábados de 10:30 a 15:30",
    ],
    footer: workshopNoticeFooter,
    buttons: [{
      type: "URL",
      text: "Ver mi trabajo",
      url: workshopNoticeClaimUrl,
      example: workshopNoticeClaimExample,
    }],
    allowCategoryChange: false,
  },
  {
    // La misma `_v2` con palabras de retiro (20261107140000): Meta dejó la
    // `_v2` como MARKETING al crearla, y «Te esperamos …» es la frase que más
    // se parece a una invitación. Un aviso del taller sale sólo con una
    // plantilla que Meta deja como UTILITY.
    name: workshopReadyV3TemplateName,
    language: "es_CL",
    category: "UTILITY",
    headerLocation: true,
    body:
      "Hola {{1}}, tu trabajo {{2}} está listo. Puedes retirarlo {{3}}. Si necesitas coordinar el retiro, respóndenos por aquí.",
    examples: [
      "Camila",
      "PG-00671",
      "de lunes a viernes de 10:30 a 19:00 y los sábados de 10:30 a 15:30",
    ],
    footer: workshopNoticeFooter,
    buttons: [{
      type: "URL",
      text: "Ver mi trabajo",
      url: workshopNoticeClaimUrl,
      example: workshopNoticeClaimExample,
    }],
    allowCategoryChange: false,
  },
  {
    // `{{3}}` es la fecha en que vence la garantía del servicio, la del
    // comprobante («21 de noviembre»).
    name: workshopDeliveredV2TemplateName,
    language: "es_CL",
    category: "UTILITY",
    headerText: "Trabajo entregado",
    body:
      "Hola {{1}}, tu trabajo {{2}} quedó entregado. La garantía del servicio vale hasta el {{3}}. Gracias por confiar en Viñabike.",
    examples: ["Camila", "PG-00671", "21 de noviembre"],
    footer: workshopNoticeFooter,
    buttons: [{
      type: "URL",
      text: "Ver comprobante",
      url: workshopNoticeClaimUrl,
      example: workshopNoticeClaimExample,
    }],
    allowCategoryChange: false,
  },
  {
    // El presupuesto en PDF arriba del mensaje, con el monto en el texto y dos
    // respuestas rápidas. «Aprobar presupuesto» lleva la clave de un solo uso
    // del trabajo (`job:<id>:approve_quote:<revisión>`, la pone whatsapp-send
    // al enviar) y aprueba con `apply_whatsapp_job_action`; «Tengo una
    // consulta» sólo abre la conversación. Meta no muestra las respuestas
    // rápidas en WhatsApp de escritorio: el texto dice igual qué hacer.
    name: workshopQuotePdfTemplateName,
    language: "es_CL",
    category: "UTILITY",
    body:
      "Hola {{1}}, te enviamos el presupuesto de tu trabajo {{2}} por {{3}}. ¿Lo apruebas?",
    examples: ["Camila", "PG-00671", "$59.990"],
    footer: workshopNoticeFooter,
    buttons: [
      { type: "QUICK_REPLY", text: "Aprobar presupuesto", action: "approve_quote" },
      { type: "QUICK_REPLY", text: "Tengo una consulta" },
    ],
    allowCategoryChange: false,
    header: {
      format: "DOCUMENT",
      acceptedContentTypes: ["application/pdf"],
      sampleFilename: "presupuesto_PG-00671.pdf",
      sampleLines: [
        "Vinabike - Taller de bicicletas",
        "Presupuesto PG-00671",
        "Cambio de cassette 11-46: $39.990",
        "Cadena 10 velocidades: $20.000",
        "Total: $59.990",
      ],
      serverDocument: "workshop_notice",
    },
  },
  {
    // El comprobante de entrega y garantía en PDF, el mismo que el cliente ve
    // en su cuenta (`buildDeliveryWarrantyPdf`); el botón abre la ficha con un
    // código para crear la cuenta o entrar.
    name: workshopDeliveredPdfTemplateName,
    language: "es_CL",
    category: "UTILITY",
    body:
      "Hola {{1}}, tu trabajo {{2}} quedó entregado. Te dejamos tu comprobante; la garantía del servicio vale hasta el {{3}}. Gracias por confiar en Viñabike.",
    examples: ["Camila", "PG-00671", "21 de noviembre"],
    footer: workshopNoticeFooter,
    buttons: [{
      type: "URL",
      text: "Guardar en mi cuenta",
      url: workshopNoticeClaimUrl,
      example: workshopNoticeClaimExample,
    }],
    allowCategoryChange: false,
    header: {
      format: "DOCUMENT",
      acceptedContentTypes: ["application/pdf"],
      sampleFilename: "comprobante_PG-00671.pdf",
      sampleLines: [
        "Vinabike - Taller de bicicletas",
        "Comprobante de entrega PG-00671",
        "Garantia del servicio hasta el 21 de noviembre",
      ],
      serverDocument: "workshop_notice",
    },
  },
  {
    // La reseña con botón: el lugar de Google del sitio va como sufijo
    // (`website_settings.google_maps_place_id`). Como la v1, Meta decide la
    // categoría al aprobarla.
    name: reviewRequestV2TemplateName,
    language: "es_CL",
    category: "UTILITY",
    body:
      "Hola {{1}}, gracias por elegir Viñabike. Si te gustó el servicio, una reseña en Google nos ayuda mucho.",
    examples: ["Camila"],
    footer: workshopNoticeFooter,
    buttons: [{
      type: "URL",
      text: "Dejar una reseña",
      url: "https://search.google.com/local/writereview?placeid={{1}}",
      example: "ChIJY-oKKDDdiZYRhWzM_W5dB-A",
    }],
  },
  {
    // Trato humano (2026-11-08): la bici en vez del número de trabajo.
    name: workshopReceivedV3TemplateName,
    language: "es_CL",
    category: "UTILITY",
    headerText: "Trabajo recibido",
    body:
      "Hola {{1}}, ya tenemos tu {{2}} en el taller. Te iremos contando por aquí cómo va el trabajo, y si te surge cualquier duda, respóndenos en este mismo chat.",
    examples: ["Camila", "Trek Marlin 7"],
    footer: workshopNoticeFooter,
    buttons: [{
      type: "URL",
      text: "Seguir mi trabajo",
      url: workshopNoticeClaimUrl,
      example: workshopNoticeClaimExample,
    }],
    allowCategoryChange: false,
  },
  {
    // El presupuesto en PDF sin el monto en el texto: el cliente lo revisa
    // en el PDF y aprueba con el mismo botón que la v1.
    name: workshopQuotePdfV2TemplateName,
    language: "es_CL",
    category: "UTILITY",
    body:
      "Hola {{1}}, te dejamos el presupuesto para tu {{2}} en el PDF adjunto. Revísalo con calma: si quieres cambiar algo o tienes alguna duda, cuéntanos por aquí y lo conversamos. Si está todo en orden, puedes aprobarlo directamente desde este mensaje.",
    examples: ["Camila", "Trek Marlin 7"],
    footer: workshopNoticeFooter,
    buttons: [
      { type: "QUICK_REPLY", text: "Aprobar presupuesto", action: "approve_quote" },
      { type: "QUICK_REPLY", text: "Tengo una consulta" },
    ],
    allowCategoryChange: false,
    header: {
      format: "DOCUMENT",
      acceptedContentTypes: ["application/pdf"],
      sampleFilename: "presupuesto_PG-00671.pdf",
      sampleLines: [
        "Vinabike - Taller de bicicletas",
        "Presupuesto PG-00671",
        "Cambio de cassette 11-46: $39.990",
        "Cadena 10 velocidades: $20.000",
        "Total: $59.990",
      ],
      serverDocument: "workshop_notice",
    },
  },
  {
    // Con el mapa, como la v3; `{{3}}` es el horario de atención.
    name: workshopReadyV4TemplateName,
    language: "es_CL",
    category: "UTILITY",
    headerLocation: true,
    body:
      "Hola {{1}}, terminamos el trabajo en tu {{2}} y ya está todo listo para el retiro. Puedes pasar {{3}}. Si necesitas coordinar el retiro, avísanos por aquí.",
    examples: [
      "Camila",
      "Trek Marlin 7",
      "de lunes a viernes de 10:30 a 19:00 y los sábados de 10:30 a 15:30",
    ],
    footer: workshopNoticeFooter,
    buttons: [{
      type: "URL",
      text: "Ver mi trabajo",
      url: workshopNoticeClaimUrl,
      example: workshopNoticeClaimExample,
    }],
    allowCategoryChange: false,
  },
  {
    // El comprobante en PDF; `{{3}}` es la fecha en que vence la garantía.
    name: workshopDeliveredPdfV2TemplateName,
    language: "es_CL",
    category: "UTILITY",
    body:
      "Hola {{1}}, gracias por dejar tu {{2}} en nuestras manos. Te dejamos el comprobante del trabajo: el servicio tiene garantía hasta el {{3}}, así que si antes de esa fecha algo no funciona como debería, escríbenos por aquí y lo revisamos.",
    examples: ["Camila", "Trek Marlin 7", "21 de noviembre"],
    footer: workshopNoticeFooter,
    buttons: [{
      type: "URL",
      text: "Guardar en mi cuenta",
      url: workshopNoticeClaimUrl,
      example: workshopNoticeClaimExample,
    }],
    allowCategoryChange: false,
    header: {
      format: "DOCUMENT",
      acceptedContentTypes: ["application/pdf"],
      sampleFilename: "comprobante_PG-00671.pdf",
      sampleLines: [
        "Vinabike - Taller de bicicletas",
        "Comprobante de entrega PG-00671",
        "Garantia del servicio hasta el 21 de noviembre",
      ],
      serverDocument: "workshop_notice",
    },
  },
  {
    // La reseña nombrando la bici. Como las anteriores, Meta decide la
    // categoría al aprobarla.
    name: reviewRequestV3TemplateName,
    language: "es_CL",
    category: "UTILITY",
    body:
      "Hola {{1}}, ojalá estés disfrutando tu {{2}}. Si quedaste conforme con el servicio, una reseña en Google nos ayuda mucho.",
    examples: ["Camila", "Trek Marlin 7"],
    footer: workshopNoticeFooter,
    buttons: [{
      type: "URL",
      text: "Dejar una reseña",
      url: "https://search.google.com/local/writereview?placeid={{1}}",
      example: "ChIJY-oKKDDdiZYRhWzM_W5dB-A",
    }],
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

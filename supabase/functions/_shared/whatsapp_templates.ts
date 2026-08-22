// Las plantillas aprobadas de WhatsApp viven aquí y en un solo lugar: las usa
// el gestor de plantillas para desplegarlas en Meta, y el asistente para
// previsualizar EXACTAMENTE lo que le llegará al cliente antes de enviar.
// Duplicarlas sería garantizar que un día digan cosas distintas.

export interface TemplateDefinition {
  name: string;
  language: string;
  category: "UTILITY" | "MARKETING" | "AUTHENTICATION";
  body: string;
  examples: string[];
  allowCategoryChange?: boolean;
}

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
];

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

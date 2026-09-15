type JsonRecord = Record<string, unknown>;

const greetingTemplatePurposes = new Set([
  "first_contact",
  "job_update",
  "ready_for_pickup",
  "quote_follow_up",
  "supplier_introduction",
  "supplier_greeting",
  "supplier_resume_contact",
  "supplier_ask_for_news",
  "supplier_pending_purchase",
]);

const compoundGivenNames = new Set([
  "ana maria",
  "ana paula",
  "ana sofia",
  "carmen gloria",
  "francisco javier",
  "jorge luis",
  "jose antonio",
  "jose carlos",
  "jose francisco",
  "jose ignacio",
  "jose luis",
  "jose manuel",
  "jose maria",
  "jose miguel",
  "jose pablo",
  "juan antonio",
  "juan carlos",
  "juan francisco",
  "juan ignacio",
  "juan jose",
  "juan luis",
  "juan manuel",
  "juan miguel",
  "juan pablo",
  "juan sebastian",
  "luis alberto",
  "luis enrique",
  "luis felipe",
  "luis miguel",
  "luz maria",
  "marco antonio",
  "maria angelica",
  "maria carolina",
  "maria elena",
  "maria fernanda",
  "maria ignacia",
  "maria isabel",
  "maria jesus",
  "maria jose",
  "maria paz",
  "maria soledad",
  "maria teresa",
  "miguel angel",
  "pedro pablo",
  "rosa maria",
]);

function record(value: unknown): JsonRecord | null {
  return value && typeof value === "object" && !Array.isArray(value) ? value as JsonRecord : null;
}

function foldedNameToken(value: string) {
  return value
    .toLocaleLowerCase("es")
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "");
}

export function resolveWhatsAppTemplateGreetingName(fullName: string) {
  const parts = fullName.trim().split(/\s+/).filter(Boolean);
  if (parts.length <= 1) return parts[0] ?? "";

  const firstPair = `${foldedNameToken(parts[0])} ${foldedNameToken(parts[1])}`;
  const preservesCompoundName = parts.length >= 3 && compoundGivenNames.has(firstPair);
  const hasTwoGivenNames = parts.length >= 4 &&
    !new Set(["de", "del", "la", "las", "los"]).has(foldedNameToken(parts[1]));

  return preservesCompoundName || hasTwoGivenNames ? `${parts[0]} ${parts[1]}` : parts[0];
}

export function normalizeWhatsAppTemplateGreeting<T extends JsonRecord>(request: T): T {
  if (request.type !== "template") return request;

  const metadata = record(request.metadata);
  const purpose = typeof metadata?.template_purpose === "string"
    ? metadata.template_purpose.trim()
    : "";
  if (!greetingTemplatePurposes.has(purpose) || !Array.isArray(request.templateComponents)) {
    return request;
  }

  let originalName = "";
  let greetingName = "";
  let changed = false;
  const templateComponents = request.templateComponents.map((rawComponent) => {
    const component = record(rawComponent);
    if (!component || String(component.type ?? "").toLowerCase() !== "body") {
      return rawComponent;
    }

    const parameters = Array.isArray(component.parameters) ? component.parameters : [];
    if (parameters.length === 0) return rawComponent;
    const firstParameter = record(parameters[0]);
    if (!firstParameter || String(firstParameter.type ?? "").toLowerCase() !== "text") {
      return rawComponent;
    }

    originalName = typeof firstParameter.text === "string" ? firstParameter.text.trim() : "";
    greetingName = resolveWhatsAppTemplateGreetingName(originalName);
    if (!greetingName || greetingName === originalName) return rawComponent;

    changed = true;
    return {
      ...component,
      parameters: [
        { ...firstParameter, text: greetingName },
        ...parameters.slice(1),
      ],
    };
  });

  if (!changed) return request;

  const caption = typeof request.caption === "string" ? request.caption : null;
  const originalPrefix = `Hola ${originalName},`;
  const normalizedCaption = caption?.startsWith(originalPrefix)
    ? `Hola ${greetingName},${caption.slice(originalPrefix.length)}`
    : caption;

  return {
    ...request,
    templateComponents,
    ...(normalizedCaption == null ? {} : { caption: normalizedCaption }),
  };
}

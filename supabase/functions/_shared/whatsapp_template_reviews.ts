// Lo que Meta dice de cada plantilla de WhatsApp, guardado en la base
// (`whatsapp_template_reviews`, 20261105130000). La base no puede preguntarle a
// Meta, y los avisos del taller sólo deben salir con una plantilla aprobada:
// el gestor de plantillas lo deja al listar y el worker de correo lo refresca
// cada media hora, así una plantilla recién aprobada empieza a usarse sola.

type JsonRecord = Record<string, unknown>;

export type WhatsAppTemplateReview = {
  name: string;
  language: string;
  status: string;
  category?: string;
  rejected_reason?: string;
};

type RpcResult = { data: unknown; error: { message: string } | null };

export type TemplateReviewStore = {
  rpc(name: string, params: Record<string, unknown>): PromiseLike<RpcResult>;
};

/** Cada cuánto se vuelve a preguntar a Meta. */
export const templateReviewRefreshMinutes = 30;

function clean(value: unknown): string | undefined {
  return typeof value === "string" && value.trim() ? value.trim() : undefined;
}

/** De la lista de Meta, sólo lo que la base guarda. */
export function templateReviewsFromMeta(items: unknown): WhatsAppTemplateReview[] {
  if (!Array.isArray(items)) return [];
  const reviews: WhatsAppTemplateReview[] = [];
  for (const raw of items) {
    if (!raw || typeof raw !== "object" || Array.isArray(raw)) continue;
    const item = raw as JsonRecord;
    const name = clean(item.name);
    const language = clean(item.language);
    const status = clean(item.status);
    if (!name || !language || !status) continue;
    const category = clean(item.category);
    const rejected = clean(item.rejected_reason);
    reviews.push({
      name,
      language,
      status,
      ...(category ? { category } : {}),
      ...(rejected ? { rejected_reason: rejected } : {}),
    });
  }
  return reviews;
}

/** Deja en la base la lista completa de la tienda. Nunca lanza. */
export async function recordTemplateReviews(
  store: TemplateReviewStore,
  tenantId: string,
  items: unknown,
): Promise<boolean> {
  try {
    const { error } = await store.rpc("record_whatsapp_template_reviews_v1", {
      p_tenant_id: tenantId,
      p_templates: templateReviewsFromMeta(items),
    });
    if (error) {
      console.error("[WHATSAPP-TEMPLATES] No se guardó el estado de las plantillas", error.message);
      return false;
    }
    return true;
  } catch (error) {
    console.error("[WHATSAPP-TEMPLATES] No se guardó el estado de las plantillas", String(error));
    return false;
  }
}

/** Las plantillas de la cuenta de WhatsApp Business, como las da Meta. */
export async function listMetaTemplates(params: {
  businessAccountId: string;
  accessToken: string;
  apiVersion: string;
  fetchFn?: typeof fetch;
}): Promise<JsonRecord[]> {
  const fields = ["name", "language", "status", "category", "rejected_reason"].join(",");
  const response = await (params.fetchFn ?? fetch)(
    `https://graph.facebook.com/${params.apiVersion}/${
      encodeURIComponent(params.businessAccountId)
    }` +
      `/message_templates?fields=${encodeURIComponent(fields)}&limit=250`,
    { headers: { Authorization: `Bearer ${params.accessToken}` } },
  );
  const body = await response.json().catch(() => ({})) as JsonRecord;
  if (!response.ok) throw new Error(`meta_templates_${response.status}`);
  return Array.isArray(body.data) ? body.data as JsonRecord[] : [];
}

export type TemplateReviewRefresh = "fresh" | "refreshed" | "no_channel" | "failed";

/**
 * Vuelve a preguntar a Meta si la última consulta tiene más de media hora.
 * Nunca lanza: un error aquí no debe frenar los correos que la llaman.
 */
export async function refreshTemplateReviewsIfStale(params: {
  store: TemplateReviewStore;
  tenantId: string;
  businessAccountId: () => Promise<string | null>;
  accessToken: string;
  apiVersion: string;
  now?: Date;
  fetchFn?: typeof fetch;
}): Promise<TemplateReviewRefresh> {
  try {
    if (!params.accessToken) return "failed";
    const { data, error } = await params.store.rpc("whatsapp_template_reviews_checked_at_v1", {
      p_tenant_id: params.tenantId,
    });
    if (error) return "failed";
    const checked = typeof data === "string" ? new Date(data) : null;
    const now = params.now ?? new Date();
    if (
      checked && !Number.isNaN(checked.getTime()) &&
      now.getTime() - checked.getTime() < templateReviewRefreshMinutes * 60_000
    ) {
      return "fresh";
    }
    const businessAccountId = await params.businessAccountId();
    if (!businessAccountId) return "no_channel";
    const items = await listMetaTemplates({
      businessAccountId,
      accessToken: params.accessToken,
      apiVersion: params.apiVersion,
      fetchFn: params.fetchFn,
    });
    return await recordTemplateReviews(params.store, params.tenantId, items)
      ? "refreshed"
      : "failed";
  } catch (error) {
    console.error("[WHATSAPP-TEMPLATES] No se pudo consultar a Meta", String(error));
    return "failed";
  }
}

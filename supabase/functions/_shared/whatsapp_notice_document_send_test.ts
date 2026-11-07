import { assert, assertEquals } from "https://deno.land/std@0.168.0/testing/asserts.ts";
import type { TrustedWhatsAppOutbox } from "../whatsapp-send/index.ts";

// El aviso «Presupuesto listo» con su PDF (20261107130000), de la cola a
// Meta: whatsapp-send pide el PDF a la tienda con el código del aviso, lo
// sube a Meta, lo pone en el encabezado y deja la clave del trabajo en
// «Aprobar presupuesto». Base y proveedores sintéticos: nada sale de la prueba.
Deno.env.set("SUPABASE_URL", "https://outbox-test.invalid");
Deno.env.set("WHATSAPP_ACCESS_TOKEN", "synthetic-test-token");
const { handleWhatsAppSend } = await import("../whatsapp-send/index.ts");

const tenant = "9f032200-0000-4000-8000-000000000001";
const conversation = "9f032200-0000-4000-8000-000000000141";
const actor = "9f032200-0000-4000-8000-000000000091";
const message = "9f032200-0000-4000-8000-000000000151";
const customer = "9f032200-0000-4000-8000-000000000011";
const job = "9f032200-0000-4000-8000-000000000021";
const code = "Zq81TfY0LwmR4pXc".padEnd(43, "q");
const pdf = new TextEncoder().encode("%PDF-1.4\n%sintetico\n");

function fakeDatabase(options: { storeUrl?: string; quotationStatus?: string } = {}) {
  return {
    from(table: string) {
      const filters: Record<string, unknown> = {};
      let updating = false;
      const result = () => {
        if (updating) return { data: null, error: null };
        if (table === "website_settings") {
          assertEquals(filters.tenant_id, tenant);
          assertEquals(filters.key, "store_url");
          return { data: { value: options.storeUrl ?? "https://vinabike.cl" }, error: null };
        }
        if (table === "conversations") {
          return {
            data: { id: conversation, tenant_id: tenant, context_type: "job", context_id: job },
            error: null,
          };
        }
        if (table === "whatsapp_channels") {
          return {
            data: { id: "channel", phone_number_id: "synthetic-channel", is_active: true },
            error: null,
          };
        }
        if (table === "mechanic_jobs") {
          assertEquals(filters.tenant_id, tenant);
          return {
            data: {
              id: job,
              tenant_id: tenant,
              customer_id: customer,
              deleted_at: null,
              quotation_status: options.quotationStatus ?? "pending",
              quotation_valid_until: null,
            },
            error: null,
          };
        }
        return { data: [], error: null };
      };
      const query = {
        select(_value: string) { return query; },
        update(_value: unknown) { updating = true; return query; },
        eq(key: string, value: unknown) { filters[key] = value; return query; },
        is(_key: string, _value: unknown) { return query; },
        in(_key: string, _value: unknown) { return query; },
        lt(_key: string, _value: unknown) { return query; },
        limit(_value: number) { return query; },
        maybeSingle() { return Promise.resolve(result()); },
        then(resolve: (value: unknown) => unknown) { return Promise.resolve(result()).then(resolve); },
      };
      return query;
    },
    rpc(name: string) {
      return Promise.resolve({
        data: name === "ensure_whatsapp_conversation_binding"
          ? { binding_id: "binding", conversation_id: conversation, customer_id: customer }
          : null,
        error: null,
      });
    },
    storage: { from: () => ({ download: () => Promise.resolve({ data: null, error: null }) }) },
  } as unknown as TrustedWhatsAppOutbox["adminClient"];
}

async function send(options: {
  store?: (request: Request) => Response;
  storeUrl?: string;
  quotationStatus?: string;
  body?: Record<string, unknown>;
}) {
  const previousFetch = globalThis.fetch;
  const calls: { url: string; request: Request }[] = [];
  const patches: Parameters<TrustedWhatsAppOutbox["persist"]>[0][] = [];
  globalThis.fetch = ((input: Request | URL | string, init?: RequestInit) => {
    const request = new Request(input, init);
    calls.push({ url: request.url, request: request.clone() });
    if (request.url.endsWith("/cuenta/aviso.pdf")) {
      return Promise.resolve(
        options.store?.(request) ??
          new Response(pdf, {
            headers: {
              "content-type": "application/pdf",
              "content-disposition": 'attachment; filename="Presupuesto PG-00671.pdf"',
            },
          }),
      );
    }
    if (request.url.endsWith("/media")) {
      return Promise.resolve(Response.json({ id: "synthetic-media-id" }));
    }
    return Promise.resolve(Response.json({ messages: [{ id: "wamid.synthetic" }] }));
  }) as typeof fetch;
  try {
    const response = await handleWhatsAppSend(
      new Request("https://outbox-test.invalid", {
        method: "POST",
        body: JSON.stringify({
          conversationId: conversation,
          phoneNumber: "+56923234545",
          contactName: "Camila Torres Soto",
          customerId: customer,
          contextType: "job",
          contextId: job,
          type: "template",
          templateName: "taller_presupuesto_pdf_v1",
          templateLanguage: "es_CL",
          caption: "Hola Camila Torres Soto, te enviamos el presupuesto de tu trabajo PG-00671 por $59.990. ¿Lo apruebas?",
          templateComponents: [{
            type: "body",
            parameters: [
              { type: "text", text: "Camila Torres Soto" },
              { type: "text", text: "PG-00671" },
              { type: "text", text: "$59.990" },
            ],
          }],
          templateDocumentToken: code,
          actionType: "approve_quote",
          actionKind: "job",
          actionTargetId: job,
          amount: 59990,
          metadata: {
            client_message_id: "workshop-notice:sintetico",
            template_purpose: "workshop_quote_ready",
          },
          ...(options.body ?? {}),
        }),
      }),
      {
        adminClient: fakeDatabase(options),
        userId: actor,
        tenantId: tenant,
        messageId: message,
        beforeProviderSend: async () => true,
        persist: async (patch) => { patches.push(patch); },
      },
    );
    return { response, calls, patches };
  } finally {
    globalThis.fetch = previousFetch;
  }
}

Deno.test("the quote travels as a PDF with its approval key in the reply button", async () => {
  const { response, calls, patches } = await send({});
  assertEquals(response.status, 200, await response.clone().text());

  const store = calls.find((call) => call.url.endsWith("/cuenta/aviso.pdf"))!;
  assertEquals(store.url, "https://vinabike.cl/cuenta/aviso.pdf");
  assertEquals(await store.request.json(), { token: code });
  assert(calls.some((call) => call.url.endsWith("/synthetic-channel/media")), "the PDF goes to Meta");

  const graph = calls.find((call) => call.url.endsWith("/synthetic-channel/messages"))!;
  const payload = await graph.request.json();
  assertEquals(payload.type, "template");
  assertEquals(payload.template.name, "taller_presupuesto_pdf_v1");
  const components = payload.template.components as Record<string, unknown>[];
  assertEquals(components[0], {
    type: "header",
    parameters: [{
      type: "document",
      document: { id: "synthetic-media-id", filename: "Presupuesto PG-00671.pdf" },
    }],
  });
  assertEquals((components[1].parameters as { text: string }[])[0].text, "Camila", "first name");
  const replies = components.filter((component) => component.sub_type === "quick_reply");
  assertEquals(replies.length, 2);
  const approve = (replies[0].parameters as { payload: string }[])[0].payload;
  assert(
    new RegExp(`^job:${job}:approve_quote:\\d{13}$`).test(approve),
    `the approve reply carries the job key, got ${approve}`,
  );
  assertEquals(replies[1], {
    type: "button",
    sub_type: "quick_reply",
    index: "1",
    parameters: [{ type: "payload", payload: "respuesta:1" }],
  });

  // The chat keeps the quote card with the same key, waiting for the answer.
  const persisted = patches.at(-1)!;
  assertEquals(persisted.type, "action_request");
  const metadata = persisted.metadata as Record<string, unknown>;
  assertEquals(metadata.action_token, approve);
  assertEquals(metadata.target_id, job);
  assertEquals(metadata.status, "pending");
  assertEquals(metadata.amount, 59990);
  assertEquals(metadata.workshop_notice_document_filename, "Presupuesto PG-00671.pdf");
});

Deno.test("without its PDF the notice is not sent", async () => {
  const refused = await send({ store: () => new Response("no", { status: 404 }) });
  assertEquals(refused.response.status, 502);
  assert(!refused.calls.some((call) => call.url.endsWith("/messages")), "nothing reaches Meta");

  const badStore = await send({ storeUrl: "http://127.0.0.1:8080" });
  assertEquals(badStore.response.status, 409);
  assert(!badStore.calls.some((call) => call.url.includes("127.0.0.1")), "an unsafe address is never asked");
});

Deno.test("a caller can neither attach a file nor skip the code", async () => {
  const withFile = await send({ body: { attachmentId: "9f032200-0000-4000-8000-000000000161" } });
  assertEquals(withFile.response.status, 400);
  const withoutCode = await send({ body: { templateDocumentToken: undefined } });
  assertEquals(withoutCode.response.status, 400);
  const codeOnAnother = await send({
    body: { templateName: "taller_presupuesto_v2", actionType: undefined },
  });
  assertEquals(codeOnAnother.response.status, 400);
});

import { assertEquals } from "jsr:@std/assert";
import type {
  AgentProviderRequest,
  AgentToolDefinition,
} from "../contracts.ts";
import { createGeminiAgentProvider } from "./gemini.ts";
import { ProviderError } from "./provider.ts";

const draftTool: AgentToolDefinition = {
  name: "prepare_supply_request",
  description: "Validates a structured supply-request draft.",
  parameters: {
    type: "object",
    properties: { items: { type: "array", items: { type: "object" } } },
    required: ["items"],
    additionalProperties: false,
  },
  requiredPermissions: ["purchases.read"],
};

const otherTool: AgentToolDefinition = {
  name: "search_inventory",
  description: "Searches the authorized tenant inventory.",
  parameters: {
    type: "object",
    properties: { query: { type: "string" } },
    required: ["query"],
    additionalProperties: false,
  },
  requiredPermissions: ["inventory.read"],
};

function forcedRequest(): AgentProviderRequest {
  return {
    modelRole: "deep",
    systemInstruction: "Server-owned policy",
    messages: [{ role: "user", text: "necesito 4 cámaras 29 con válvula Schrader" }],
    tools: [draftTool, otherTool],
    requiredToolName: draftTool.name,
    maxOutputTokens: 512,
    continuationToken: undefined,
  };
}

function geminiToolCallResponse(): Response {
  return new Response(
    JSON.stringify({
      candidates: [{
        content: {
          role: "model",
          parts: [{
            functionCall: { name: draftTool.name, args: { items: [] } },
          }],
        },
        finishReason: "STOP",
      }],
      usageMetadata: { promptTokenCount: 12, candidatesTokenCount: 4 },
    }),
    { status: 200 },
  );
}

function toolConfigOf(init: RequestInit | undefined): unknown {
  return JSON.parse(String(init?.body ?? "{}")).toolConfig;
}

function declaredToolsOf(init: RequestInit | undefined): readonly string[] {
  const tools = JSON.parse(String(init?.body ?? "{}")).tools ?? [];
  return (tools[0]?.functionDeclarations ?? []).map(
    (declaration: { name: string }) => declaration.name,
  );
}

// **El defecto del 2026-08-18.** El Asistente de compras fallaba SIEMPRE en su
// sexta llamada: las cinco anteriores respondían `tool_calls` y la sexta es la
// única que fuerza `prepare_supply_request` con
// `functionCallingConfig.mode = "ANY"`. `gemini-3.1-pro-preview` rechaza esa
// restricción con 4xx, y con ella se caía la corrida entera. Ningún borrador
// conversacional podía cerrarse nunca.
Deno.test("a rejected forced-tool constraint degrades instead of losing the run", async () => {
  const sent: unknown[] = [];
  const declared: (readonly string[])[] = [];
  const provider = createGeminiAgentProvider({
    apiKey: "gemini-test-key",
    fetchImpl: (_input, init) => {
      sent.push(toolConfigOf(init));
      declared.push(declaredToolsOf(init));
      return Promise.resolve(
        sent.length === 1
          ? new Response(
            JSON.stringify({ error: { status: "INVALID_ARGUMENT" } }),
            { status: 400 },
          )
          : geminiToolCallResponse(),
      );
    },
  });

  const turn = await provider.generate(forcedRequest(), new AbortController().signal);

  assertEquals(sent.length, 2, "se reintenta exactamente una vez");
  assertEquals(
    (sent[0] as { functionCallingConfig: { mode: string } }).functionCallingConfig.mode,
    "ANY",
    "el primer intento sí fuerza la herramienta",
  );
  assertEquals(sent[1], undefined, "el reintento suelta la restricción de transporte");
  // Y la expresa en el catálogo: si el modelo no ve otra función, no puede
  // llamar otra. Sin esto el reintento llamaba a `search_inventory` y el turno
  // moría en `assertRequiredProviderToolTurn`.
  assertEquals(declared[0], [draftTool.name, otherTool.name], "el primero declara todo");
  assertEquals(declared[1], [draftTool.name], "el reintento declara sólo la requerida");
  // Y la herramienta sigue llegando: quien garantiza el contrato es
  // `assertRequiredProviderToolTurn` en el runtime, no la pista del transporte.
  assertEquals(turn.toolCalls?.[0]?.name, draftTool.name);
});

// La degradación es sólo para la restricción forzada. Sin ella, un rechazo
// sigue siendo un rechazo y no se reintenta a ciegas.
Deno.test("an unforced rejection is not retried", async () => {
  let calls = 0;
  const provider = createGeminiAgentProvider({
    apiKey: "gemini-test-key",
    fetchImpl: () => {
      calls++;
      return Promise.resolve(
        new Response(JSON.stringify({ error: { status: "PERMISSION_DENIED" } }), {
          status: 403,
        }),
      );
    },
  });

  const request = forcedRequest();
  const unforced = { ...request, requiredToolName: undefined };
  let captured: ProviderError | undefined;
  try {
    await provider.generate(unforced, new AbortController().signal);
  } catch (error) {
    captured = error as ProviderError;
  }
  assertEquals(calls, 1, "no hay reintento cuando no se forzó nada");
  assertEquals(captured?.code, "provider_rejected");
  assertEquals(captured?.status, 403);
  assertEquals(captured?.upstreamReason, "PERMISSION_DENIED");
});

// Un 5xx ya lo reintenta el runtime con su propia política: degradar acá
// enmascararía una caída del proveedor como si fuera la restricción.
Deno.test("a retryable status keeps the forced constraint", async () => {
  let calls = 0;
  const provider = createGeminiAgentProvider({
    apiKey: "gemini-test-key",
    fetchImpl: () => {
      calls++;
      return Promise.resolve(new Response("", { status: 503 }));
    },
  });
  let captured: ProviderError | undefined;
  try {
    await provider.generate(forcedRequest(), new AbortController().signal);
  } catch (error) {
    captured = error as ProviderError;
  }
  assertEquals(calls, 1, "un 503 no degrada la pista");
  assertEquals(captured?.code, "provider_unavailable");
  assertEquals(captured?.retryable, true);
});

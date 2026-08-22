import {
  type AgentFinishReason,
  type AgentMessage,
  type AgentProviderTurn,
  type AgentToolCall,
  type AgentUsage,
  emptyUsage,
  isJsonObject,
  type JsonObject,
  type JsonValue,
  type LogicalModelRole,
} from "../contracts.ts";
import { type AgentModelProvider, ProviderError, requiredToolNameFor } from "./provider.ts";
import {
  discardProviderBody,
  providerRejectionReason,
  readProviderJson,
} from "./http.ts";

const defaultModels: Readonly<Record<LogicalModelRole, string>> = {
  fast: "gemini-3.6-flash",
  // `gemini-3.7-flash` es el Flash estable más nuevo y el que Google describe
  // para «agentic workflows and reliable multi-step execution», que es
  // exactamente esta carga: el asistente encadena herramientas en varios
  // pasos. Reemplazó a `gemini-3.1-pro-preview` el 2026-08-21, cuando ese
  // preview empezó a rechazar por cuota 12 de cada 12 llamadas.
  deep: "gemini-3.7-flash",
  vision: "gemini-3.6-flash",
};

export interface GeminiAgentProviderConfig {
  apiKey: string;
  fetchImpl?: typeof fetch;
  endpointBase?: string;
  modelByRole?: Readonly<Record<LogicalModelRole, string>>;
  allowedModels?: readonly string[];
}

interface GeminiContinuationGroup {
  readonly callIds: readonly string[];
  readonly callNames: readonly string[];
  readonly text: string;
  readonly parts: readonly JsonObject[];
}

interface GeminiContinuationState {
  readonly version: 2;
  readonly nextRound: number;
  readonly groups: readonly GeminiContinuationGroup[];
}

export function createGeminiAgentProvider(config: GeminiAgentProviderConfig): AgentModelProvider {
  const apiKey = requireValue(config.apiKey, "Gemini API key");
  const fetchImpl = config.fetchImpl ?? fetch;
  const endpointBase = validateEndpointBase(
    config.endpointBase ?? "https://generativelanguage.googleapis.com/v1beta/",
  );
  const modelByRole = config.modelByRole ?? defaultModels;
  const allowedModels = new Set(
    config.allowedModels ??
      ["gemini-3.7-flash", "gemini-3.6-flash", "gemini-3.1-pro-preview"],
  );
  assertServerModelConfiguration(modelByRole, allowedModels);

  return {
    id: "gemini",
    modelFor: (role) => modelByRole[role],
    async generate(request, signal) {
      const model = modelByRole[request.modelRole];
      const endpoint = new URL(`models/${encodeURIComponent(model)}:generateContent`, endpointBase);
      const continuation = decodeGeminiContinuation(request.continuationToken);
      const requiredToolName = requiredToolNameFor(request);
      // `narrowToolName` deja declarada **sólo** esa herramienta. Es el
      // repliegue cuando el proveedor rechaza `mode: ANY`: si la restricción no
      // se puede expresar en el transporte, se expresa en el catálogo, porque
      // un modelo no puede llamar a una función que no ve.
      const buildPayload = (
        forcedToolName: string | undefined,
        narrowToolName: string | undefined,
      ) => {
        const declared = narrowToolName === undefined
          ? request.tools
          : request.tools.filter((tool) => tool.name === narrowToolName);
        return {
          systemInstruction: { parts: [{ text: request.systemInstruction }] },
          contents: geminiContents(request.messages, continuation.groups),
          tools: declared.length === 0 ? undefined : [{
            functionDeclarations: declared.map((tool) => ({
              name: tool.name,
              description: tool.description,
              parametersJsonSchema: tool.parameters,
            })),
          }],
          toolConfig: forcedToolName
            ? {
              functionCallingConfig: {
                mode: "ANY",
                allowedFunctionNames: [forcedToolName],
              },
            }
            : undefined,
          generationConfig: { maxOutputTokens: request.maxOutputTokens },
        };
      };

      const send = async (
        forcedToolName: string | undefined,
        narrowToolName?: string,
      ): Promise<Response> => {
        try {
          return await fetchImpl(endpoint, {
            method: "POST",
            headers: {
              "Content-Type": "application/json",
              "x-goog-api-key": apiKey,
            },
            body: JSON.stringify(buildPayload(forcedToolName, narrowToolName)),
            signal,
          });
        } catch (_) {
          throw new ProviderError("provider_unavailable", 503, !signal.aborted);
        }
      };

      const rejectionIsRetryable = (status: number) =>
        status === 408 || status === 429 || status >= 500;

      let response = await send(requiredToolName, undefined);

      // **Forzar la herramienta es una pista, no el contrato.**
      //
      // `functionCallingConfig.mode = "ANY"` le pide al modelo que la llamada
      // terminal sea sí o sí una función concreta. Un modelo que no admite esa
      // restricción rechaza la petición entera con 4xx, y entonces se pierde no
      // la pista sino la conversación completa: el 2026-08-18 el Asistente de
      // compras fallaba SIEMPRE en la sexta llamada —las cinco anteriores
      // respondían `tool_calls` sin problema— porque esa sexta es la única que
      // fuerza `prepare_supply_request`. Ningún borrador podía cerrarse nunca.
      //
      // Quien de verdad garantiza el contrato es `assertRequiredProviderToolTurn`
      // en el runtime, que exige que el turno traiga esa herramienta y sólo esa.
      // Por eso degradar la pista es seguro: si el modelo no la llama, sigue
      // fallando con su error tipado de siempre; lo que ya no ocurre es tirar la
      // corrida por una restricción de transporte que el proveedor no acepta.
      if (
        !response.ok && requiredToolName !== undefined &&
        !rejectionIsRetryable(response.status)
      ) {
        await discardProviderBody(response);
        response = await send(undefined, requiredToolName);
      }

      if (!response.ok) {
        const retryable = rejectionIsRetryable(response.status);
        // Un rechazo no reintentable es el único que hay que poder diagnosticar
        // después: se rescata su enum de estado y se descarta el resto.
        const reason = retryable
          ? undefined
          : await providerRejectionReason(response);
        await discardProviderBody(response);
        throw new ProviderError(
          retryable ? "provider_unavailable" : "provider_rejected",
          response.status,
          retryable,
          reason,
        );
      }

      return normalizeGeminiResponse(await readProviderJson(response, signal), continuation);
    },
  };
}

function geminiContents(
  messages: readonly AgentMessage[],
  continuationGroups: readonly GeminiContinuationGroup[],
): JsonObject[] {
  const contents: JsonObject[] = [];
  let continuationIndex = 0;
  for (const message of messages) {
    const hasToolCalls = message.role === "assistant" && (message.toolCalls?.length ?? 0) > 0;
    const continuationGroup = hasToolCalls ? continuationGroups[continuationIndex++] : undefined;
    contents.push(geminiContent(message, continuationGroup));
  }
  if (continuationIndex !== continuationGroups.length) {
    throw new ProviderError("provider_invalid_response", 502, false);
  }
  return contents;
}

function geminiContent(
  message: AgentMessage,
  continuationGroup: GeminiContinuationGroup | undefined,
): JsonObject {
  if (message.role === "tool") {
    return {
      role: "user",
      parts: [{
        functionResponse: {
          id: message.toolCallId,
          name: message.toolName,
          response: { output: message.text },
        },
      }],
    };
  }

  const parts: JsonValue[] = [];
  if (message.text) parts.push({ text: message.text });
  if (message.role === "assistant") {
    const calls = message.toolCalls ?? [];
    if (calls.length > 0) {
      if (
        !continuationGroup || continuationGroup.text !== message.text.trim() ||
        !sameStrings(continuationGroup.callIds, calls.map((call) => call.id)) ||
        !sameStrings(continuationGroup.callNames, calls.map((call) => call.name))
      ) {
        throw new ProviderError("provider_invalid_response", 502, false);
      }
      // Gemini associates thought signatures with the response part stream,
      // not one signature per function call. A signature may live on text,
      // only the first call, or be absent when thinking is disabled. Replay
      // the exact provider-owned assistant parts instead of reconstructing a
      // shape that can be invalid even when the original response was valid.
      return { role: "model", parts: [...continuationGroup.parts] };
    }
  }
  return { role: message.role === "assistant" ? "model" : "user", parts };
}

function normalizeGeminiResponse(
  value: unknown,
  continuation: GeminiContinuationState,
): AgentProviderTurn {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new ProviderError("provider_invalid_response", 502, false);
  }
  const body = value as Record<string, unknown>;
  const candidates = Array.isArray(body.candidates) ? body.candidates : [];
  const candidate = candidates[0];
  if (!candidate || typeof candidate !== "object" || Array.isArray(candidate)) {
    return {
      text: "",
      toolCalls: [],
      usage: parseGeminiUsage(body.usageMetadata),
      finishReason: "blocked",
    };
  }
  const candidateRecord = candidate as Record<string, unknown>;
  const content = candidateRecord.content;
  const parts = content && typeof content === "object" && !Array.isArray(content) &&
      Array.isArray((content as Record<string, unknown>).parts)
    ? (content as Record<string, unknown>).parts as unknown[]
    : [];

  const text: string[] = [];
  const toolCalls: AgentToolCall[] = [];
  const continuationParts: JsonObject[] = [];
  for (let index = 0; index < parts.length; index++) {
    const part = parts[index];
    if (!isJsonObject(part)) {
      throw new ProviderError("provider_invalid_response", 502, false);
    }
    const record = part as JsonObject;
    continuationParts.push(record);
    if (typeof record.text === "string") text.push(record.text);
    const functionCall = record.functionCall;
    if (functionCall && typeof functionCall === "object" && !Array.isArray(functionCall)) {
      const call = functionCall as Record<string, unknown>;
      if (typeof call.name !== "string" || !call.name || !isJsonObject(call.args)) {
        throw new ProviderError("provider_invalid_response", 502, false);
      }
      const callId = typeof call.id === "string" && call.id
        ? call.id
        : `gemini-call-r${continuation.nextRound}-p${index}`;
      toolCalls.push({
        id: callId,
        name: call.name,
        arguments: call.args,
      });
    }
  }

  const nextContinuation: GeminiContinuationState = {
    version: 2,
    nextRound: continuation.nextRound + 1,
    groups: toolCalls.length > 0
      ? [
        ...continuation.groups,
        {
          callIds: toolCalls.map((call) => call.id),
          callNames: toolCalls.map((call) => call.name),
          text: text.join("").trim(),
          parts: continuationParts,
        },
      ]
      : continuation.groups,
  };
  const continuationToken = toolCalls.length > 0 ? encodeContinuation(nextContinuation) : undefined;

  return {
    text: text.join("").trim(),
    toolCalls,
    usage: parseGeminiUsage(body.usageMetadata),
    finishReason: geminiFinishReason(candidateRecord.finishReason, toolCalls),
    continuationToken,
  };
}

function parseGeminiUsage(value: unknown): AgentUsage {
  if (!value || typeof value !== "object" || Array.isArray(value)) return emptyUsage();
  const usage = value as Record<string, unknown>;
  // Gemini reports tool-schema/tool-use prompt tokens separately from the
  // ordinary prompt and thinking tokens separately from visible candidates.
  // Both are billable: tool-use prompt tokens are input, while thinking tokens
  // are output. Keep the ledger decomposition exact so pricing and quota
  // checks do not reject a perfectly valid thinking-model response.
  const inputTokens = safeTokenSum(
    safeTokenCount(usage.promptTokenCount),
    safeTokenCount(usage.toolUsePromptTokenCount),
  );
  let outputTokens = safeTokenSum(
    safeTokenCount(usage.candidatesTokenCount),
    safeTokenCount(usage.thoughtsTokenCount),
  );
  const reportedTotal = safeTokenCount(usage.totalTokenCount);
  const componentTotal = safeTokenSum(inputTokens, outputTokens);
  // A future Gemini metadata revision may expose another internal token class
  // before this adapter knows its name. Preserve total billed usage and charge
  // any positive residual at the more conservative output rate.
  if (reportedTotal > componentTotal) {
    outputTokens = safeTokenSum(outputTokens, reportedTotal - componentTotal);
  }
  return {
    // Cuántos de los tokens de entrada los sirvió el caché del proveedor. El
    // 70% de cada petición es prefijo idéntico —catálogo de herramientas y
    // reglas—, así que saber si Gemini lo está descontando decide si vale la
    // pena implementar caché explícito o ya no hace falta.
    cachedInputTokens: safeTokenCount(usage.cachedContentTokenCount),
    inputTokens,
    outputTokens,
    totalTokens: safeTokenSum(inputTokens, outputTokens),
  };
}

function geminiFinishReason(value: unknown, calls: readonly AgentToolCall[]): AgentFinishReason {
  if (calls.length > 0) return "tool_calls";
  switch (value) {
    case "STOP":
      return "stop";
    case "MAX_TOKENS":
      return "length";
    case "SAFETY":
    case "RECITATION":
    case "BLOCKLIST":
    case "PROHIBITED_CONTENT":
      return "blocked";
    default:
      return "unknown";
  }
}

function assertServerModelConfiguration(
  models: Readonly<Record<LogicalModelRole, string>>,
  allowlist: ReadonlySet<string>,
): void {
  for (const model of Object.values(models)) {
    if (!model || !allowlist.has(model)) {
      throw new Error("Gemini model route is outside the server allowlist");
    }
  }
}

function validateEndpointBase(value: string): URL {
  const url = new URL(value);
  if (url.protocol !== "https:") throw new Error("Gemini endpoint must use HTTPS");
  if (!url.pathname.endsWith("/")) url.pathname += "/";
  return url;
}

function requireValue(value: string, label: string): string {
  if (!value.trim()) throw new Error(`${label} is not configured`);
  return value;
}

function safeTokenCount(value: unknown): number {
  return typeof value === "number" && Number.isSafeInteger(value) && value >= 0 ? value : 0;
}

function safeTokenSum(left: number, right: number): number {
  const total = left + right;
  if (!Number.isSafeInteger(total) || total < 0) {
    throw new ProviderError("provider_invalid_response", 502, false);
  }
  return total;
}

function encodeContinuation(value: GeminiContinuationState): string {
  const token = encodeBase64Url(new TextEncoder().encode(JSON.stringify(value)));
  if (token.length > 256 * 1024) {
    // Reject in the same round, before a caller can execute tool calls whose
    // continuation would be impossible to replay safely.
    throw new ProviderError("provider_invalid_response", 502, false);
  }
  return token;
}

function decodeGeminiContinuation(token: string | undefined): GeminiContinuationState {
  if (!token) return { version: 2, nextRound: 0, groups: [] };
  if (token.length > 256 * 1024) {
    throw new ProviderError("provider_invalid_response", 502, false);
  }
  try {
    const decoded = new TextDecoder().decode(decodeBase64Url(token));
    const value = JSON.parse(decoded);
    if (!isGeminiContinuationState(value)) {
      throw new Error();
    }
    return value;
  } catch (_) {
    throw new ProviderError("provider_invalid_response", 502, false);
  }
}

function isGeminiContinuationState(value: unknown): value is GeminiContinuationState {
  if (!value || typeof value !== "object" || Array.isArray(value)) return false;
  const state = value as Record<string, unknown>;
  if (
    state.version !== 2 || !Number.isSafeInteger(state.nextRound) ||
    (state.nextRound as number) < 0 || !Array.isArray(state.groups)
  ) {
    return false;
  }
  if ((state.nextRound as number) < state.groups.length) return false;
  return state.groups.every((rawGroup) => {
    if (!rawGroup || typeof rawGroup !== "object" || Array.isArray(rawGroup)) return false;
    const group = rawGroup as Record<string, unknown>;
    if (
      !Array.isArray(group.callIds) || group.callIds.length === 0 ||
      !group.callIds.every((id) => typeof id === "string" && id.length > 0) ||
      !Array.isArray(group.callNames) ||
      !group.callNames.every((name) => typeof name === "string" && name.length > 0) ||
      group.callNames.length !== group.callIds.length || typeof group.text !== "string" ||
      !Array.isArray(group.parts) || group.parts.length === 0 ||
      !group.parts.every(isJsonObject)
    ) {
      return false;
    }
    const callIds = group.callIds as string[];
    const callNames = group.callNames as string[];
    const groupParts = group.parts as JsonObject[];
    const partCalls = groupParts.flatMap((rawPart) => {
      const part = rawPart as Record<string, unknown>;
      const rawCall = part.functionCall;
      if (!rawCall || typeof rawCall !== "object" || Array.isArray(rawCall)) return [];
      const call = rawCall as Record<string, unknown>;
      return [{ id: call.id, name: call.name }];
    });
    const partText = groupParts
      .map((rawPart) => (rawPart as Record<string, unknown>).text)
      .filter((text): text is string => typeof text === "string")
      .join("")
      .trim();
    return partCalls.length === callIds.length && partText === group.text &&
      partCalls.every((call, index) =>
        call.name === callNames[index] &&
        (call.id === undefined || call.id === callIds[index])
      );
  });
}

function sameStrings(left: readonly string[], right: readonly string[]): boolean {
  return left.length === right.length && left.every((value, index) => value === right[index]);
}

function encodeBase64Url(bytes: Uint8Array): string {
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary).replaceAll("+", "-").replaceAll("/", "_").replaceAll("=", "");
}

function decodeBase64Url(value: string): Uint8Array {
  const normalized = value.replaceAll("-", "+").replaceAll("_", "/");
  const padded = normalized + "=".repeat((4 - normalized.length % 4) % 4);
  const binary = atob(padded);
  return Uint8Array.from(binary, (character) => character.charCodeAt(0));
}

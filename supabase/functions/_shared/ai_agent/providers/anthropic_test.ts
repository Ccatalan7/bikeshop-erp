import type {
  AgentMessage,
  AgentProviderRequest,
  AgentToolDefinition,
  LogicalModelRole,
} from "../contracts.ts";
import { createAnthropicMessagesProvider } from "./anthropic.ts";
import { ProviderError } from "./provider.ts";

function assert(condition: unknown, message: string): asserts condition {
  if (!condition) throw new Error(message);
}

function assertEquals(actual: unknown, expected: unknown, message: string): void {
  const actualJson = JSON.stringify(actual);
  const expectedJson = JSON.stringify(expected);
  if (actualJson !== expectedJson) {
    throw new Error(`${message}: expected ${expectedJson}, received ${actualJson}`);
  }
}

async function assertProviderError(
  operation: Promise<unknown>,
  code: ProviderError["code"],
  message: string,
): Promise<ProviderError> {
  try {
    await operation;
  } catch (error) {
    assert(error instanceof ProviderError, `${message}: expected ProviderError`);
    assertEquals(error.code, code, message);
    return error;
  }
  throw new Error(`${message}: operation unexpectedly succeeded`);
}

const inventoryTool: AgentToolDefinition = {
  name: "search_inventory",
  description: "Searches the authorized tenant inventory using a bounded query.",
  parameters: {
    type: "object",
    properties: {
      query: { type: "string", minLength: 1, maxLength: 240 },
      filters: {
        type: "object",
        properties: {
          lowStockOnly: { type: "boolean" },
        },
        additionalProperties: false,
      },
    },
    required: ["query"],
    additionalProperties: false,
  },
  requiredPermissions: ["inventory.read"],
};

const tasksTool: AgentToolDefinition = {
  name: "search_tasks",
  description: "Searches authorized tasks with bounded status filters.",
  parameters: {
    type: "object",
    properties: {
      status: { type: "string", enum: ["pending", "completed"] },
    },
    additionalProperties: false,
  },
  requiredPermissions: ["tasks.read"],
};

function request(
  messages: readonly AgentMessage[],
  options: {
    continuationToken?: string;
    modelRole?: LogicalModelRole;
    tools?: readonly AgentToolDefinition[];
  } = {},
): AgentProviderRequest {
  return {
    modelRole: options.modelRole ?? "fast",
    systemInstruction: "Server-owned policy",
    messages,
    tools: options.tools ?? [],
    maxOutputTokens: 512,
    continuationToken: options.continuationToken,
  };
}

function anthropicResponse(options: {
  content: readonly Record<string, unknown>[];
  stopReason: string;
  model?: string;
  usage?: Record<string, unknown>;
}): Response {
  return new Response(
    JSON.stringify({
      id: "msg_test",
      type: "message",
      role: "assistant",
      model: options.model ?? "claude-sonnet-5",
      content: options.content,
      stop_reason: options.stopReason,
      stop_sequence: null,
      usage: options.usage ?? { input_tokens: 10, output_tokens: 4 },
    }),
    { status: 200 },
  );
}

Deno.test("Anthropic keeps model routing, effort, strict tools, and abort ownership on server", async () => {
  let capturedInput: URL | Request | string | undefined;
  let capturedInit: RequestInit | undefined;
  const provider = createAnthropicMessagesProvider({
    apiKey: "anthropic-test-key",
    fetchImpl: (input, init) => {
      capturedInput = input;
      capturedInit = init;
      return Promise.resolve(
        anthropicResponse({
          model: "claude-opus-5",
          content: [{ type: "text", text: "Análisis listo." }],
          stopReason: "end_turn",
          usage: {
            input_tokens: 10,
            cache_creation_input_tokens: 3,
            cache_read_input_tokens: 2,
            output_tokens: 5,
          },
        }),
      );
    },
  });
  const controller = new AbortController();
  const turn = await provider.generate(
    request([{ role: "user", text: "Analiza" }], {
      modelRole: "deep",
      tools: [inventoryTool],
    }),
    controller.signal,
  );

  assertEquals(
    String(capturedInput),
    "https://api.anthropic.com/v1/messages",
    "the endpoint is server-owned",
  );
  assert(capturedInit?.signal === controller.signal, "the caller abort signal reaches fetch");
  const headers = new Headers(capturedInit?.headers);
  assertEquals(headers.get("anthropic-version"), "2023-06-01", "API version is pinned");
  assertEquals(headers.get("x-api-key"), "anthropic-test-key", "server key uses its header");
  const payload = JSON.parse(capturedInit?.body as string);
  assert(
    !(capturedInit?.body as string).includes("anthropic-test-key"),
    "the provider key never enters the serialized request body",
  );
  assertEquals(payload.model, "claude-opus-5", "deep role selects the fixed Opus route");
  assertEquals(payload.output_config, { effort: "high" }, "deep effort is server-owned");
  assertEquals(
    payload.thinking,
    { type: "adaptive", display: "omitted" },
    "private thinking stays omitted while signatures remain available",
  );
  assertEquals(payload.tools[0].strict, true, "Anthropic validates tool inputs strictly");
  assertEquals(
    payload.tools[0].input_schema.additionalProperties,
    false,
    "the closed neutral schema is forwarded unchanged",
  );
  assertEquals(
    turn.usage,
    { inputTokens: 15, outputTokens: 5, totalTokens: 20 },
    "cache tokens count as input usage",
  );
  assertEquals(turn.finishReason, "stop", "end_turn is normalized");
});

Deno.test("Anthropic replays exact thinking, signatures, redactions, calls, and results across three rounds", async () => {
  const firstBlocks = [
    { type: "thinking", thinking: "", signature: "signature-round-1" },
    { type: "text", text: "Revisaré inventario. " },
    {
      type: "tool_use",
      id: "toolu_inventory",
      name: "search_inventory",
      input: { query: "cadena" },
    },
  ];
  const secondBlocks = [
    { type: "redacted_thinking", data: "encrypted-redaction-round-2" },
    { type: "thinking", thinking: "", signature: "signature-round-2" },
    {
      type: "tool_use",
      id: "toolu_tasks",
      name: "search_tasks",
      input: { status: "pending" },
    },
  ];
  const payloads: Array<Record<string, unknown>> = [];
  const provider = createAnthropicMessagesProvider({
    apiKey: "anthropic-test-key",
    fetchImpl: (_input, init) => {
      payloads.push(JSON.parse(init?.body as string));
      if (payloads.length === 1) {
        return Promise.resolve(anthropicResponse({ content: firstBlocks, stopReason: "tool_use" }));
      }
      if (payloads.length === 2) {
        return Promise.resolve(
          anthropicResponse({ content: secondBlocks, stopReason: "tool_use" }),
        );
      }
      return Promise.resolve(
        anthropicResponse({
          content: [{ type: "text", text: "Inventario y tareas revisados." }],
          stopReason: "end_turn",
        }),
      );
    },
  });
  const signal = new AbortController().signal;
  const tools = [inventoryTool, tasksTool];
  const initial: AgentMessage[] = [{ role: "user", text: "Organiza el día" }];

  const first = await provider.generate(request(initial, { tools }), signal);
  assert(first.continuationToken, "the first tool round returns opaque continuation state");
  assertEquals(first.text, "Revisaré inventario.", "thinking is never exposed as text");
  const afterFirst: AgentMessage[] = [
    ...initial,
    { role: "assistant", text: first.text, toolCalls: first.toolCalls },
    {
      role: "tool",
      text: JSON.stringify({ products: [{ name: "Cadena 10v" }] }),
      toolCallId: first.toolCalls[0].id,
      toolName: first.toolCalls[0].name,
    },
  ];

  const second = await provider.generate(
    request(afterFirst, { continuationToken: first.continuationToken, tools }),
    signal,
  );
  assert(second.continuationToken, "the second round accumulates continuation state");
  const afterSecond: AgentMessage[] = [
    ...afterFirst,
    { role: "assistant", text: second.text, toolCalls: second.toolCalls },
    {
      role: "tool",
      text: JSON.stringify({ tasks: [{ title: "Llamar proveedor" }] }),
      toolCallId: second.toolCalls[0].id,
      toolName: second.toolCalls[0].name,
    },
  ];

  const third = await provider.generate(
    request(afterSecond, { continuationToken: second.continuationToken, tools }),
    signal,
  );
  const thirdMessages = payloads[2].messages as Array<Record<string, unknown>>;
  assertEquals(
    (thirdMessages[1] as Record<string, unknown>).content,
    firstBlocks,
    "round three replays the first assistant block stream exactly",
  );
  assertEquals(
    (thirdMessages[3] as Record<string, unknown>).content,
    secondBlocks,
    "round three keeps every later thinking and redacted block in place",
  );
  assertEquals(
    (thirdMessages[2] as Record<string, unknown>).content,
    [{
      type: "tool_result",
      tool_use_id: "toolu_inventory",
      content: JSON.stringify({ products: [{ name: "Cadena 10v" }] }),
    }],
    "the first result immediately follows its exact tool-use turn",
  );
  assertEquals(third.text, "Inventario y tareas revisados.", "final text remains normalized");
  assertEquals(third.toolCalls, [], "the final answer releases no stale calls");
});

Deno.test("Anthropic groups parallel tool results first and preserves thinking-off calls", async () => {
  const originalBlocks = [
    {
      type: "tool_use",
      id: "toolu_inventory",
      name: "search_inventory",
      input: { query: "freno" },
    },
    { type: "text", text: "También revisaré tareas." },
    {
      type: "tool_use",
      id: "toolu_tasks",
      name: "search_tasks",
      input: { status: "pending" },
    },
  ];
  const payloads: Array<Record<string, unknown>> = [];
  const provider = createAnthropicMessagesProvider({
    apiKey: "anthropic-test-key",
    fetchImpl: (_input, init) => {
      payloads.push(JSON.parse(init?.body as string));
      return Promise.resolve(
        payloads.length === 1
          ? anthropicResponse({ content: originalBlocks, stopReason: "tool_use" })
          : anthropicResponse({
            content: [{ type: "text", text: "Listo." }],
            stopReason: "end_turn",
          }),
      );
    },
  });
  const tools = [inventoryTool, tasksTool];
  const initial: AgentMessage[] = [{ role: "user", text: "Busca" }];
  const first = await provider.generate(
    request(initial, { tools }),
    new AbortController().signal,
  );

  await provider.generate(
    request([
      ...initial,
      { role: "assistant", text: first.text, toolCalls: first.toolCalls },
      ...first.toolCalls.map((call): AgentMessage => ({
        role: "tool",
        text: `result-${call.id}`,
        toolCallId: call.id,
        toolName: call.name,
      })),
    ], { continuationToken: first.continuationToken, tools }),
    new AbortController().signal,
  );

  const messages = payloads[1].messages as Array<Record<string, unknown>>;
  assertEquals(messages[1].content, originalBlocks, "thinking-off assistant blocks replay exactly");
  assertEquals(
    messages[2].content,
    [
      {
        type: "tool_result",
        tool_use_id: "toolu_inventory",
        content: "result-toolu_inventory",
      },
      {
        type: "tool_result",
        tool_use_id: "toolu_tasks",
        content: "result-toolu_tasks",
      },
    ],
    "all tool_result blocks share the immediate user turn and precede later text",
  );
});

Deno.test("Anthropic rejects mismatched or incomplete tool-result chronology before fetch", async () => {
  let fetchCount = 0;
  const provider = createAnthropicMessagesProvider({
    apiKey: "anthropic-test-key",
    fetchImpl: () => {
      fetchCount++;
      return Promise.resolve(
        anthropicResponse({
          content: [{
            type: "tool_use",
            id: "toolu_inventory",
            name: "search_inventory",
            input: { query: "cadena" },
          }],
          stopReason: "tool_use",
        }),
      );
    },
  });
  const initial: AgentMessage[] = [{ role: "user", text: "Busca" }];
  const first = await provider.generate(
    request(initial, { tools: [inventoryTool] }),
    new AbortController().signal,
  );

  await assertProviderError(
    provider.generate(
      request([
        ...initial,
        { role: "assistant", text: first.text, toolCalls: first.toolCalls },
        {
          role: "tool",
          text: "{}",
          toolCallId: "wrong-call-id",
          toolName: "search_inventory",
        },
      ], { continuationToken: first.continuationToken, tools: [inventoryTool] }),
      new AbortController().signal,
    ),
    "provider_invalid_response",
    "a mismatched tool result fails closed",
  );
  assertEquals(fetchCount, 1, "invalid continuation never reaches Anthropic");

  await assertProviderError(
    provider.generate(
      request([
        ...initial,
        {
          role: "assistant",
          text: first.text,
          toolCalls: [{
            ...first.toolCalls[0],
            arguments: { query: "tampered-after-execution" },
          }],
        },
        {
          role: "tool",
          text: "{}",
          toolCallId: first.toolCalls[0].id,
          toolName: first.toolCalls[0].name,
        },
      ], { continuationToken: first.continuationToken, tools: [inventoryTool] }),
      new AbortController().signal,
    ),
    "provider_invalid_response",
    "tool arguments cannot drift after execution",
  );
  assertEquals(fetchCount, 1, "argument tampering also fails before fetch");
});

Deno.test("Anthropic rejects oversized private continuation before releasing tool calls", async () => {
  const provider = createAnthropicMessagesProvider({
    apiKey: "anthropic-test-key",
    fetchImpl: () =>
      Promise.resolve(
        anthropicResponse({
          content: [
            { type: "thinking", thinking: "", signature: "s".repeat(400_000) },
            {
              type: "tool_use",
              id: "toolu_inventory",
              name: "search_inventory",
              input: { query: "cadena" },
            },
          ],
          stopReason: "tool_use",
        }),
      ),
  });

  await assertProviderError(
    provider.generate(
      request([{ role: "user", text: "Busca" }], { tools: [inventoryTool] }),
      new AbortController().signal,
    ),
    "provider_invalid_response",
    "an oversized signature makes the originating round non-executable",
  );
});

Deno.test("Anthropic rejects open schemas and unadvertised calls before execution", async () => {
  let fetchCount = 0;
  const provider = createAnthropicMessagesProvider({
    apiKey: "anthropic-test-key",
    fetchImpl: () => {
      fetchCount++;
      return Promise.resolve(
        anthropicResponse({
          content: [{
            type: "tool_use",
            id: "toolu_unknown",
            name: "unadvertised_tool",
            input: {},
          }],
          stopReason: "tool_use",
        }),
      );
    },
  });
  const openTool: AgentToolDefinition = {
    ...inventoryTool,
    parameters: {
      type: "object",
      properties: { query: { type: "string" } },
      required: ["query"],
    },
  };

  await assertProviderError(
    provider.generate(
      request([{ role: "user", text: "Busca" }], { tools: [openTool] }),
      new AbortController().signal,
    ),
    "provider_invalid_response",
    "an open schema is never sent",
  );
  assertEquals(fetchCount, 0, "open schema rejection happens before fetch");

  await assertProviderError(
    provider.generate(
      request([{ role: "user", text: "Busca" }], { tools: [inventoryTool] }),
      new AbortController().signal,
    ),
    "provider_invalid_response",
    "an unadvertised response call is never released",
  );
  assertEquals(fetchCount, 1, "the malformed provider response was fetched only once");
});

Deno.test("Anthropic rejects duplicate tool-use ids before releasing ambiguous calls", async () => {
  const provider = createAnthropicMessagesProvider({
    apiKey: "anthropic-test-key",
    fetchImpl: () =>
      Promise.resolve(
        anthropicResponse({
          content: [
            {
              type: "tool_use",
              id: "toolu_duplicate",
              name: "search_inventory",
              input: { query: "cadena" },
            },
            {
              type: "tool_use",
              id: "toolu_duplicate",
              name: "search_tasks",
              input: { status: "pending" },
            },
          ],
          stopReason: "tool_use",
        }),
      ),
  });

  await assertProviderError(
    provider.generate(
      request([{ role: "user", text: "Organiza" }], {
        tools: [inventoryTool, tasksTool],
      }),
      new AbortController().signal,
    ),
    "provider_invalid_response",
    "duplicate call ids cannot create ambiguous result ownership",
  );
});

Deno.test("Anthropic binds private continuation to its server-selected model", async () => {
  let fetchCount = 0;
  const provider = createAnthropicMessagesProvider({
    apiKey: "anthropic-test-key",
    fetchImpl: () => {
      fetchCount++;
      return Promise.resolve(
        anthropicResponse({
          content: [{
            type: "tool_use",
            id: "toolu_inventory",
            name: "search_inventory",
            input: { query: "cadena" },
          }],
          stopReason: "tool_use",
        }),
      );
    },
  });
  const initial: AgentMessage[] = [{ role: "user", text: "Busca" }];
  const first = await provider.generate(
    request(initial, { tools: [inventoryTool] }),
    new AbortController().signal,
  );

  await assertProviderError(
    provider.generate(
      request([
        ...initial,
        { role: "assistant", text: first.text, toolCalls: first.toolCalls },
        {
          role: "tool",
          text: "{}",
          toolCallId: first.toolCalls[0].id,
          toolName: first.toolCalls[0].name,
        },
      ], {
        modelRole: "deep",
        continuationToken: first.continuationToken,
        tools: [inventoryTool],
      }),
      new AbortController().signal,
    ),
    "provider_invalid_response",
    "Sonnet thinking signatures cannot cross into the Opus route",
  );
  assertEquals(fetchCount, 1, "cross-model continuation fails before a second request");
});

Deno.test("Anthropic turns aborted fetches into a fixed sanitized provider failure", async () => {
  let seenSignal: AbortSignal | null = null;
  const provider = createAnthropicMessagesProvider({
    apiKey: "anthropic-test-key",
    fetchImpl: (_input, init) => {
      seenSignal = init?.signal as AbortSignal;
      return new Promise((_resolve, reject) => {
        seenSignal?.addEventListener(
          "abort",
          () => reject(new Error("upstream-secret-and-request-body")),
          { once: true },
        );
      });
    },
  });
  const controller = new AbortController();
  const operation = provider.generate(
    request([{ role: "user", text: "Hola" }]),
    controller.signal,
  );
  controller.abort("gateway_timeout");
  const error = await assertProviderError(
    operation,
    "provider_unavailable",
    "an abort is normalized",
  );

  assert(seenSignal === controller.signal, "timeout cancellation reaches the exact fetch signal");
  assertEquals(error.message, "AI provider request failed", "upstream details never escape");
  assertEquals(error.retryable, true, "aborted transport is retry-classified without details");
});

Deno.test("Anthropic discards upstream rejection bodies and exposes only fixed metadata", async () => {
  const provider = createAnthropicMessagesProvider({
    apiKey: "anthropic-test-key",
    fetchImpl: () =>
      Promise.resolve(
        new Response(
          JSON.stringify({
            error: {
              message: "customer-prompt-and-provider-internals-must-never-escape",
            },
          }),
          { status: 400 },
        ),
      ),
  });

  const error = await assertProviderError(
    provider.generate(
      request([{ role: "user", text: "Hola" }]),
      new AbortController().signal,
    ),
    "provider_rejected",
    "a provider rejection is sanitized",
  );
  assertEquals(error.message, "AI provider request failed", "upstream body is never echoed");
  assertEquals(error.status, 400, "only fixed transport metadata remains available");
  assertEquals(error.retryable, false, "a validation rejection is not retried");
});

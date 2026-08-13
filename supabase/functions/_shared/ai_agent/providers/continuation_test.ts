import type { AgentMessage, AgentProviderRequest, AgentToolDefinition } from "../contracts.ts";
import { createGeminiAgentProvider } from "./gemini.ts";
import { createOpenAIResponsesProvider } from "./openai_responses.ts";
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

async function assertInvalidProviderResponse(
  operation: Promise<unknown>,
  message: string,
): Promise<void> {
  try {
    await operation;
  } catch (error) {
    assert(error instanceof ProviderError, `${message}: expected ProviderError`);
    assertEquals(error.code, "provider_invalid_response", message);
    return;
  }
  throw new Error(`${message}: operation unexpectedly succeeded`);
}

function request(
  messages: readonly AgentMessage[],
  continuationToken?: string,
): AgentProviderRequest {
  return {
    modelRole: "fast",
    systemInstruction: "Server policy",
    messages,
    tools: [],
    maxOutputTokens: 512,
    continuationToken,
  };
}

const publicResearchTool: AgentToolDefinition = {
  name: "research_public_web",
  description: "Researches public web evidence for the current server-owned request.",
  parameters: {
    type: "object",
    properties: {},
    required: [],
    additionalProperties: false,
  },
  requiredPermissions: ["ai.read.operational"],
};

Deno.test("Gemini protocol-forces one named tool and omits the choice otherwise", async () => {
  const payloads: Array<Record<string, unknown>> = [];
  const provider = createGeminiAgentProvider({
    apiKey: "gemini-test-key",
    fetchImpl: (_input, init) => {
      payloads.push(JSON.parse(String(init?.body)));
      return Promise.resolve(
        new Response(
          JSON.stringify({
            candidates: [{
              finishReason: "STOP",
              content: {
                parts: payloads.length === 1
                  ? [{
                    functionCall: {
                      id: "gemini-research",
                      name: "research_public_web",
                      args: {},
                    },
                  }]
                  : [{ text: "Listo." }],
              },
            }],
          }),
          { status: 200 },
        ),
      );
    },
  });
  const base = {
    ...request([{ role: "user", text: "Investiga" }]),
    tools: [publicResearchTool],
  };

  await provider.generate(
    { ...base, requiredToolName: "research_public_web" },
    new AbortController().signal,
  );
  await provider.generate(base, new AbortController().signal);

  assertEquals(payloads[0].toolConfig, {
    functionCallingConfig: {
      mode: "ANY",
      allowedFunctionNames: ["research_public_web"],
    },
  }, "Gemini receives an exact server-owned required function");
  assertEquals(
    Object.hasOwn(payloads[1], "toolConfig"),
    false,
    "normal Gemini planning has no forced tool choice",
  );
  await assertInvalidProviderResponse(
    provider.generate(
      { ...base, requiredToolName: "missing_tool" },
      new AbortController().signal,
    ),
    "Gemini rejects a required tool outside the advertised set",
  );
  assertEquals(payloads.length, 2, "invalid required tools fail before network egress");
  await assertInvalidProviderResponse(
    provider.generate(
      {
        ...base,
        tools: [publicResearchTool, publicResearchTool],
        requiredToolName: "research_public_web",
      },
      new AbortController().signal,
    ),
    "Gemini rejects an ambiguously duplicated required tool",
  );
  assertEquals(payloads.length, 2, "duplicate required tools also fail before egress");
});

Deno.test("OpenAI protocol-forces one named tool and omits the choice otherwise", async () => {
  const payloads: Array<Record<string, unknown>> = [];
  const provider = createOpenAIResponsesProvider({
    apiKey: "openai-test-key",
    fetchImpl: (_input, init) => {
      payloads.push(JSON.parse(String(init?.body)));
      return Promise.resolve(
        new Response(
          JSON.stringify({
            status: "completed",
            output: payloads.length === 1
              ? [{
                type: "function_call",
                call_id: "openai-research",
                name: "research_public_web",
                arguments: "{}",
              }]
              : [{
                type: "message",
                content: [{ type: "output_text", text: "Listo." }],
              }],
          }),
          { status: 200 },
        ),
      );
    },
  });
  const base = {
    ...request([{ role: "user", text: "Investiga" }]),
    tools: [publicResearchTool],
  };

  await provider.generate(
    { ...base, requiredToolName: "research_public_web" },
    new AbortController().signal,
  );
  await provider.generate(base, new AbortController().signal);

  assertEquals(payloads[0].tool_choice, {
    type: "function",
    name: "research_public_web",
  }, "OpenAI receives an exact server-owned required function");
  assertEquals(
    Object.hasOwn(payloads[1], "tool_choice"),
    false,
    "normal OpenAI planning has no forced tool choice",
  );
  await assertInvalidProviderResponse(
    provider.generate(
      { ...base, requiredToolName: "missing_tool" },
      new AbortController().signal,
    ),
    "OpenAI rejects a required tool outside the advertised set",
  );
  assertEquals(payloads.length, 2, "invalid required tools fail before network egress");
});

Deno.test("Gemini defaults route fast and vision to stable Flash and deep to Pro preview", async () => {
  const urls: string[] = [];
  const provider = createGeminiAgentProvider({
    apiKey: "gemini-test-key",
    fetchImpl: (input) => {
      urls.push(input.toString());
      return Promise.resolve(
        new Response(
          JSON.stringify({
            candidates: [{ finishReason: "STOP", content: { parts: [{ text: "Listo." }] } }],
          }),
          { status: 200 },
        ),
      );
    },
  });
  const base = request([{ role: "user", text: "Revisa" }]);
  await provider.generate(base, new AbortController().signal);
  await provider.generate({ ...base, modelRole: "deep" }, new AbortController().signal);
  await provider.generate({ ...base, modelRole: "vision" }, new AbortController().signal);
  assert(urls[0].includes("models/gemini-3.6-flash:generateContent"), "fast stable model");
  assert(urls[1].includes("models/gemini-3.1-pro-preview:generateContent"), "deep Pro model");
  assert(urls[2].includes("models/gemini-3.6-flash:generateContent"), "vision stable model");
});

Deno.test("Gemini accounts tool prompts and thinking tokens in the billed usage ledger", async () => {
  const provider = createGeminiAgentProvider({
    apiKey: "gemini-test-key",
    fetchImpl: () =>
      Promise.resolve(
        new Response(
          JSON.stringify({
            candidates: [{ finishReason: "STOP", content: { parts: [{ text: "Listo." }] } }],
            usageMetadata: {
              promptTokenCount: 120,
              toolUsePromptTokenCount: 30,
              candidatesTokenCount: 20,
              thoughtsTokenCount: 300,
              totalTokenCount: 470,
            },
          }),
          { status: 200 },
        ),
      ),
  });

  const turn = await provider.generate(
    request([{ role: "user", text: "Organiza el día" }]),
    new AbortController().signal,
  );

  assertEquals(
    turn.usage,
    { inputTokens: 150, outputTokens: 320, totalTokens: 470 },
    "tool prompts are input and hidden thinking is billed output",
  );
});

Deno.test("Gemini preserves every historical thought signature across three rounds", async () => {
  const payloads: Array<Record<string, unknown>> = [];
  const provider = createGeminiAgentProvider({
    apiKey: "gemini-test-key",
    fetchImpl: (_input, init) => {
      payloads.push(JSON.parse(init?.body as string));
      const round = payloads.length;
      if (round <= 2) {
        return Promise.resolve(
          new Response(
            JSON.stringify({
              candidates: [{
                finishReason: "STOP",
                content: {
                  parts: [{
                    thoughtSignature: `signature-${round}`,
                    functionCall: {
                      name: round === 1 ? "search_inventory" : "search_tasks",
                      args: round === 1 ? { query: "cadena" } : { status: "pending" },
                    },
                  }],
                },
              }],
            }),
            { status: 200 },
          ),
        );
      }
      return Promise.resolve(
        new Response(
          JSON.stringify({
            candidates: [{
              finishReason: "STOP",
              content: { parts: [{ text: "Inventario y tareas revisados." }] },
            }],
          }),
          { status: 200 },
        ),
      );
    },
  });
  const signal = new AbortController().signal;
  const initialMessages: AgentMessage[] = [{ role: "user", text: "Organiza el día" }];

  const first = await provider.generate(request(initialMessages), signal);
  assert(first.continuationToken, "first round must return a continuation token");
  assertEquals(
    first.toolCalls[0].id,
    "gemini-call-r0-p0",
    "first missing provider id receives a round-scoped fallback",
  );

  const firstMessages: AgentMessage[] = [
    ...initialMessages,
    { role: "assistant", text: "", toolCalls: first.toolCalls },
    {
      role: "tool",
      text: JSON.stringify({ products: [{ name: "Cadena 10v" }] }),
      toolCallId: first.toolCalls[0].id,
      toolName: first.toolCalls[0].name,
    },
  ];
  const second = await provider.generate(
    request(firstMessages, first.continuationToken),
    signal,
  );
  assert(second.continuationToken, "second round must return the accumulated token");
  assertEquals(
    second.toolCalls[0].id,
    "gemini-call-r1-p0",
    "second missing provider id receives a different round-scoped fallback",
  );
  assert(first.toolCalls[0].id !== second.toolCalls[0].id, "fallback ids never collide by round");

  const secondMessages: AgentMessage[] = [
    ...firstMessages,
    { role: "assistant", text: "", toolCalls: second.toolCalls },
    {
      role: "tool",
      text: JSON.stringify({ tasks: [{ title: "Llamar al proveedor" }] }),
      toolCallId: second.toolCalls[0].id,
      toolName: second.toolCalls[0].name,
    },
  ];
  const third = await provider.generate(
    request(secondMessages, second.continuationToken),
    signal,
  );

  const thirdContents = payloads[2].contents as Array<Record<string, unknown>>;
  const firstHistoricalParts = thirdContents[1].parts as Array<Record<string, unknown>>;
  const secondHistoricalParts = thirdContents[3].parts as Array<Record<string, unknown>>;
  assertEquals(
    firstHistoricalParts[0].thoughtSignature,
    "signature-1",
    "third round replays the first call's exact thought signature",
  );
  assertEquals(
    secondHistoricalParts[0].thoughtSignature,
    "signature-2",
    "third round replays the second call's exact thought signature",
  );
  assertEquals(third.text, "Inventario y tareas revisados.", "third round remains normalized");
});

Deno.test("OpenAI preserves encrypted reasoning beside each historical call over three rounds", async () => {
  const payloads: Array<Record<string, unknown>> = [];
  const provider = createOpenAIResponsesProvider({
    apiKey: "openai-test-key",
    fetchImpl: (_input, init) => {
      payloads.push(JSON.parse(init?.body as string));
      const round = payloads.length;
      if (round <= 2) {
        return Promise.resolve(
          new Response(
            JSON.stringify({
              status: "completed",
              output: [
                {
                  type: "reasoning",
                  id: `reasoning-${round}`,
                  encrypted_content: `encrypted-${round}`,
                  summary: [],
                },
                {
                  type: "function_call",
                  call_id: `call-${round}`,
                  name: round === 1 ? "search_inventory" : "search_tasks",
                  arguments: JSON.stringify(
                    round === 1 ? { query: "cadena" } : { status: "pending" },
                  ),
                },
              ],
            }),
            { status: 200 },
          ),
        );
      }
      return Promise.resolve(
        new Response(
          JSON.stringify({
            status: "completed",
            output: [{
              type: "message",
              content: [{ type: "output_text", text: "Inventario y tareas revisados." }],
            }],
          }),
          { status: 200 },
        ),
      );
    },
  });
  const signal = new AbortController().signal;
  const initialMessages: AgentMessage[] = [{ role: "user", text: "Organiza el día" }];

  const first = await provider.generate(request(initialMessages), signal);
  assert(first.continuationToken, "first round must return encrypted continuation state");
  const firstMessages: AgentMessage[] = [
    ...initialMessages,
    { role: "assistant", text: "", toolCalls: first.toolCalls },
    {
      role: "tool",
      text: JSON.stringify({ products: [{ name: "Cadena 10v" }] }),
      toolCallId: first.toolCalls[0].id,
      toolName: first.toolCalls[0].name,
    },
  ];

  const second = await provider.generate(
    request(firstMessages, first.continuationToken),
    signal,
  );
  assert(second.continuationToken, "second round must return accumulated encrypted state");
  const secondMessages: AgentMessage[] = [
    ...firstMessages,
    { role: "assistant", text: "", toolCalls: second.toolCalls },
    {
      role: "tool",
      text: JSON.stringify({ tasks: [{ title: "Llamar al proveedor" }] }),
      toolCallId: second.toolCalls[0].id,
      toolName: second.toolCalls[0].name,
    },
  ];

  const third = await provider.generate(
    request(secondMessages, second.continuationToken),
    signal,
  );
  const thirdInput = payloads[2].input as Array<Record<string, unknown>>;
  assertEquals(
    thirdInput.map((item) => item.type ?? item.role),
    [
      "user",
      "reasoning",
      "function_call",
      "function_call_output",
      "reasoning",
      "function_call",
      "function_call_output",
    ],
    "each reasoning artifact stays immediately before its associated historical call",
  );
  assertEquals(
    [thirdInput[1].encrypted_content, thirdInput[4].encrypted_content],
    ["encrypted-1", "encrypted-2"],
    "encrypted reasoning remains complete and chronological",
  );
  assertEquals(
    [thirdInput[2].call_id, thirdInput[5].call_id],
    ["call-1", "call-2"],
    "reasoning groups remain associated with the correct calls",
  );
  assertEquals(third.text, "Inventario y tareas revisados.", "third round remains normalized");
});

Deno.test("Gemini replays mixed signed text and multi-call parts exactly", async () => {
  const originalParts = [
    { text: "Plan listo. ", thoughtSignature: "signature-on-text" },
    {
      thoughtSignature: "signature-on-first-call",
      functionCall: { name: "search_inventory", args: { query: "cadena" } },
    },
    {
      functionCall: { name: "search_tasks", args: { status: "pending" } },
    },
  ];
  const payloads: Array<Record<string, unknown>> = [];
  const provider = createGeminiAgentProvider({
    apiKey: "gemini-test-key",
    fetchImpl: (_input, init) => {
      payloads.push(JSON.parse(init?.body as string));
      return Promise.resolve(
        new Response(
          JSON.stringify({
            candidates: [{
              finishReason: "STOP",
              content: {
                parts: payloads.length === 1 ? originalParts : [{ text: "Completado." }],
              },
            }],
          }),
          { status: 200 },
        ),
      );
    },
  });
  const signal = new AbortController().signal;
  const initial: AgentMessage[] = [{ role: "user", text: "Organiza" }];
  const first = await provider.generate(request(initial), signal);
  assert(first.continuationToken, "mixed Gemini parts must produce continuation state");
  assertEquals(first.toolCalls.length, 2, "both Gemini calls remain executable");

  const messages: AgentMessage[] = [
    ...initial,
    { role: "assistant", text: first.text, toolCalls: first.toolCalls },
    ...first.toolCalls.map((call): AgentMessage => ({
      role: "tool",
      text: "{}",
      toolCallId: call.id,
      toolName: call.name,
    })),
  ];
  await provider.generate(request(messages, first.continuationToken), signal);

  const replayed = (payloads[1].contents as Array<Record<string, unknown>>)[1]
    .parts;
  assertEquals(
    replayed,
    originalParts,
    "Gemini signature placement and part order remain byte-shape equivalent",
  );
});

Deno.test("Gemini thinking-off calls still receive replayable continuation", async () => {
  let fetchCount = 0;
  const provider = createGeminiAgentProvider({
    apiKey: "gemini-test-key",
    fetchImpl: () => {
      fetchCount++;
      return Promise.resolve(
        new Response(
          JSON.stringify({
            candidates: [{
              finishReason: "STOP",
              content: {
                parts: fetchCount === 1
                  ? [{ functionCall: { name: "search_inventory", args: { query: "cadena" } } }]
                  : [{ text: "Listo." }],
              },
            }],
          }),
          { status: 200 },
        ),
      );
    },
  });
  const signal = new AbortController().signal;
  const initial: AgentMessage[] = [{ role: "user", text: "Busca" }];
  const first = await provider.generate(request(initial), signal);
  assert(first.continuationToken, "a signature-free call still needs a continuation token");

  await provider.generate(
    request([
      ...initial,
      { role: "assistant", text: first.text, toolCalls: first.toolCalls },
      {
        role: "tool",
        text: "{}",
        toolCallId: first.toolCalls[0].id,
        toolName: first.toolCalls[0].name,
      },
    ], first.continuationToken),
    signal,
  );
  assertEquals(fetchCount, 2, "thinking-off continuation reaches the second fetch");
});

Deno.test("Gemini rejects oversized continuation before releasing tool calls", async () => {
  const provider = createGeminiAgentProvider({
    apiKey: "gemini-test-key",
    fetchImpl: () =>
      Promise.resolve(
        new Response(
          JSON.stringify({
            candidates: [{
              finishReason: "STOP",
              content: {
                parts: [{
                  thoughtSignature: "s".repeat(200_000),
                  functionCall: { name: "search_inventory", args: { query: "cadena" } },
                }],
              },
            }],
          }),
          { status: 200 },
        ),
      ),
  });

  await assertInvalidProviderResponse(
    provider.generate(
      request([{ role: "user", text: "Busca" }]),
      new AbortController().signal,
    ),
    "oversized Gemini continuation fails in its originating round",
  );
});

Deno.test("OpenAI preserves an interleaved multi-call output stream exactly", async () => {
  const originalItems = [
    { type: "reasoning", id: "r1", encrypted_content: "encrypted-1", summary: [] },
    {
      type: "function_call",
      call_id: "call-1",
      name: "search_inventory",
      arguments: JSON.stringify({ query: "cadena" }),
    },
    { type: "reasoning", id: "r2", encrypted_content: "encrypted-2", summary: [] },
    {
      type: "function_call",
      call_id: "call-2",
      name: "search_tasks",
      arguments: JSON.stringify({ status: "pending" }),
    },
  ];
  const payloads: Array<Record<string, unknown>> = [];
  const provider = createOpenAIResponsesProvider({
    apiKey: "openai-test-key",
    fetchImpl: (_input, init) => {
      payloads.push(JSON.parse(init?.body as string));
      return Promise.resolve(
        new Response(
          JSON.stringify({
            status: "completed",
            output: payloads.length === 1 ? originalItems : [{
              type: "message",
              content: [{ type: "output_text", text: "Completado." }],
            }],
          }),
          { status: 200 },
        ),
      );
    },
  });
  const signal = new AbortController().signal;
  const initial: AgentMessage[] = [{ role: "user", text: "Organiza" }];
  const first = await provider.generate(request(initial), signal);
  assert(first.continuationToken, "interleaved OpenAI items need continuation state");

  await provider.generate(
    request([
      ...initial,
      { role: "assistant", text: first.text, toolCalls: first.toolCalls },
      ...first.toolCalls.map((call): AgentMessage => ({
        role: "tool",
        text: "{}",
        toolCallId: call.id,
        toolName: call.name,
      })),
    ], first.continuationToken),
    signal,
  );

  const replayed = (payloads[1].input as Array<Record<string, unknown>>).slice(1, 5);
  assertEquals(replayed, originalItems, "OpenAI output item chronology is unchanged");
});

Deno.test("OpenAI calls without reasoning remain replayable", async () => {
  let fetchCount = 0;
  const provider = createOpenAIResponsesProvider({
    apiKey: "openai-test-key",
    fetchImpl: () => {
      fetchCount++;
      return Promise.resolve(
        new Response(
          JSON.stringify({
            status: "completed",
            output: fetchCount === 1
              ? [{
                type: "function_call",
                call_id: "call-plain",
                name: "search_inventory",
                arguments: JSON.stringify({ query: "cadena" }),
              }]
              : [{
                type: "message",
                content: [{ type: "output_text", text: "Listo." }],
              }],
          }),
          { status: 200 },
        ),
      );
    },
  });
  const signal = new AbortController().signal;
  const initial: AgentMessage[] = [{ role: "user", text: "Busca" }];
  const first = await provider.generate(request(initial), signal);
  assert(first.continuationToken, "plain function calls still need continuation state");

  await provider.generate(
    request([
      ...initial,
      { role: "assistant", text: first.text, toolCalls: first.toolCalls },
      {
        role: "tool",
        text: "{}",
        toolCallId: first.toolCalls[0].id,
        toolName: first.toolCalls[0].name,
      },
    ], first.continuationToken),
    signal,
  );
  assertEquals(fetchCount, 2, "plain function-call continuation reaches the second fetch");
});

Deno.test("OpenAI reasoning effort is selected server-side from the logical role", async () => {
  const payloads: Array<Record<string, unknown>> = [];
  const provider = createOpenAIResponsesProvider({
    apiKey: "openai-test-key",
    reasoningEffortByRole: { fast: "low", deep: "high", vision: "medium" },
    fetchImpl: (_input, init) => {
      payloads.push(JSON.parse(String(init?.body)));
      return Promise.resolve(
        new Response(
          JSON.stringify({
            status: "completed",
            output: [{ type: "message", content: [{ type: "output_text", text: "Listo." }] }],
            usage: { input_tokens: 1, output_tokens: 1, total_tokens: 2 },
          }),
          { status: 200 },
        ),
      );
    },
  });
  const fast = request([{ role: "user", text: "Resume" }]);
  await provider.generate(fast, new AbortController().signal);
  await provider.generate({ ...fast, modelRole: "deep" }, new AbortController().signal);
  assertEquals(payloads[0].reasoning, { effort: "low" }, "fast role uses configured low effort");
  assertEquals(payloads[1].reasoning, { effort: "high" }, "deep role uses configured high effort");
  assertEquals("reasoningEffort" in payloads[0], false, "client cannot inject an effort field");
});

Deno.test("OpenAI rejects oversized continuation before releasing tool calls", async () => {
  const provider = createOpenAIResponsesProvider({
    apiKey: "openai-test-key",
    fetchImpl: () =>
      Promise.resolve(
        new Response(
          JSON.stringify({
            status: "completed",
            output: [
              {
                type: "reasoning",
                id: "reasoning-large",
                encrypted_content: "e".repeat(400_000),
                summary: [],
              },
              {
                type: "function_call",
                call_id: "call-large",
                name: "search_inventory",
                arguments: JSON.stringify({ query: "cadena" }),
              },
            ],
          }),
          { status: 200 },
        ),
      ),
  });

  await assertInvalidProviderResponse(
    provider.generate(
      request([{ role: "user", text: "Busca" }]),
      new AbortController().signal,
    ),
    "oversized OpenAI continuation fails in its originating round",
  );
});

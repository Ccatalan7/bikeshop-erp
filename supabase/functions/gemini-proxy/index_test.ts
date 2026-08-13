import { normalizeGenerateResponse, safeProviderFailure } from "./index.ts";

function assert(condition: unknown, message: string): asserts condition {
  if (!condition) throw new Error(message);
}

Deno.test("generate response exposes only redacted completion metadata", () => {
  const result = normalizeGenerateResponse({
    candidates: [{
      finishReason: "STOP",
      content: {
        parts: [{ text: '{"schema_version":"3"}' }],
      },
    }],
  });

  assert(result.text === '{"schema_version":"3"}', "text is normalized");
  assert(result.finishReason === "STOP", "finish reason is transported");
  assert(result.candidateCount === 1, "candidate count is transported");
  assert(
    Object.keys(result).sort().join(",") ===
      "candidateCount,finishReason,functionCalls,text",
    "raw provider payload is never returned",
  );
});

Deno.test("provider schema error keeps code and pointer but drops messages", async () => {
  const secret = "supplier title and signed-url must never escape";
  const response = new Response(
    JSON.stringify({
      error: {
        code: 400,
        status: "INVALID_ARGUMENT",
        message: secret,
        details: [{
          fieldViolations: [{
            field: "generationConfig.responseSchema.properties.identity",
            description: secret,
          }],
        }],
      },
    }),
    { status: 400 },
  );

  const failure = await safeProviderFailure(response);
  const encoded = JSON.stringify(failure);
  assert(failure.upstreamStatus === 400, "upstream status is retained");
  assert(
    failure.upstreamStatusText === "INVALID_ARGUMENT",
    "provider status is retained",
  );
  assert(
    Array.isArray(failure.providerFieldPaths) &&
      failure.providerFieldPaths[0] ===
        "generationConfig.responseSchema.properties.identity",
    "safe field pointer is retained",
  );
  assert(!encoded.includes(secret), "provider message and description are redacted");
});

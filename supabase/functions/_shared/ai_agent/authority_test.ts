import { createSupabaseAuthorityDataSource } from "./authority.ts";
import { createDefaultAgentToolRegistry } from "./tool_registry.ts";

const userId = "11111111-1111-4111-8111-111111111111";
const tenantId = "22222222-2222-4222-8222-222222222222";
const authorityFingerprint = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa";

function authorityEnvelope(capabilities: unknown) {
  return {
    authorityTenantId: tenantId,
    actorUserId: userId,
    role: "owner",
    permissions: {},
    capabilities,
    authorityFingerprint,
    asOf: "2026-08-11T12:00:00Z",
  };
}

function assertEquals(actual: unknown, expected: unknown, message: string): void {
  if (JSON.stringify(actual) !== JSON.stringify(expected)) {
    throw new Error(`${message}: ${JSON.stringify(actual)} != ${JSON.stringify(expected)}`);
  }
}

Deno.test("caller-bound authority capabilities, not presentation role, gate accounting", async () => {
  const source = createSupabaseAuthorityDataSource({
    rpc: () =>
      Promise.resolve(authorityEnvelope([
        "ai.read.operational",
        "ai.read.sales",
        "ai.read.purchases",
        "ai.read.accounting",
      ])),
  });
  const authority = await source.resolve();
  const names = createDefaultAgentToolRegistry().advertisedFor(authority).map((tool) => tool.name);
  assertEquals(authority.role, "owner", "presentation role is preserved");
  assertEquals(
    names.includes("analyze_cash_and_receivables"),
    true,
    "server-derived profile capability grants accounting",
  );

  const ownerOnly = await createSupabaseAuthorityDataSource({
    rpc: () => Promise.resolve(authorityEnvelope(["ai.read.operational"])),
  }).resolve();
  assertEquals(
    createDefaultAgentToolRegistry().advertisedFor(ownerOnly).some((tool) =>
      tool.name === "list_recent_expenses"
    ),
    false,
    "owner label alone never grants accounting",
  );
});

Deno.test("authority rejects unknown or duplicated capability claims", async () => {
  for (
    const capabilities of [
      ["ai.read.operational", "ai.write.everything"],
      ["ai.read.operational", "ai.read.operational"],
      "ai.read.operational",
    ]
  ) {
    let rejected = false;
    try {
      await createSupabaseAuthorityDataSource({
        rpc: () => Promise.resolve(authorityEnvelope(capabilities)),
      }).resolve();
    } catch (_) {
      rejected = true;
    }
    assertEquals(rejected, true, "untrusted capability projection fails closed");
  }
});

Deno.test("missing authority capability projection fails closed", async () => {
  const missing = authorityEnvelope(["ai.read.operational"]);
  delete (missing as Record<string, unknown>).capabilities;
  let rejected = false;
  try {
    await createSupabaseAuthorityDataSource({
      rpc: () => Promise.resolve(missing),
    }).resolve();
  } catch (_) {
    rejected = true;
  }
  assertEquals(rejected, true, "Edge never reconstructs authority from presentation role");
});

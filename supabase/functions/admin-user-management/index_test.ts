import {
  deactivateAccountPreservingMessagingHistory,
  getMessagingDeletionEvidence,
  hardDeletedAccountResult,
  preservedMessagingHistoryResult,
} from "./index.ts";

function assertEquals(actual: unknown, expected: unknown, message: string) {
  const actualJson = JSON.stringify(actual);
  const expectedJson = JSON.stringify(expected);
  if (actualJson !== expectedJson) {
    throw new Error(
      `${message}: expected ${expectedJson}, received ${actualJson}`,
    );
  }
}

function assert(condition: unknown, message: string): asserts condition {
  if (!condition) throw new Error(message);
}

interface RecordedUpdate {
  table: string;
  payload: Record<string, unknown>;
  filters: Array<[string, unknown]>;
}

interface RecordedRead {
  table: string;
  filters: Array<[string, unknown]>;
}

class FakeQuery {
  readonly filters: Array<[string, unknown]> = [];
  private payload: Record<string, unknown> | null = null;

  constructor(
    private readonly client: FakeServiceClient,
    readonly table: string,
  ) {}

  select(_columns: string) {
    return this;
  }

  or(filter: string) {
    this.filters.push(["or", filter]);
    return this;
  }

  eq(column: string, value: unknown) {
    this.filters.push([column, value]);
    return this;
  }

  update(payload: Record<string, unknown>) {
    this.payload = payload;
    return this;
  }

  limit(_count: number) {
    this.client.reads.push({
      table: this.table,
      filters: [...this.filters],
    });
    const error = this.client.queryErrors.get(this.table) ?? null;
    const data = this.client.evidenceTables.has(this.table)
      ? [{ id: `${this.table}-evidence` }]
      : [];
    return Promise.resolve({ data, error });
  }

  then<TResult1 = unknown, TResult2 = never>(
    onfulfilled?: ((value: { data: null; error: null }) => TResult1 | PromiseLike<TResult1>) | null,
    onrejected?: ((reason: unknown) => TResult2 | PromiseLike<TResult2>) | null,
  ): Promise<TResult1 | TResult2> {
    if (this.payload != null) {
      this.client.updates.push({
        table: this.table,
        payload: this.payload,
        filters: [...this.filters],
      });
    }
    return Promise.resolve({ data: null, error: null }).then(
      onfulfilled,
      onrejected,
    );
  }
}

class FakeServiceClient {
  readonly evidenceTables = new Set<string>();
  readonly queryErrors = new Map<string, { message: string }>();
  readonly updates: RecordedUpdate[] = [];
  readonly reads: RecordedRead[] = [];
  readonly authUpdates: Array<{
    userId: string;
    payload: Record<string, unknown>;
  }> = [];

  readonly auth = {
    admin: {
      updateUserById: async (
        userId: string,
        payload: Record<string, unknown>,
      ) => {
        this.authUpdates.push({ userId, payload });
        return { data: null, error: null };
      },
    },
  };

  from(table: string) {
    return new FakeQuery(this, table);
  }
}

Deno.test("messaging evidence covers authorship, participation and durable commands", async () => {
  const client = new FakeServiceClient();
  client.evidenceTables.add("conversations");
  client.evidenceTables.add("conversation_participants");
  client.evidenceTables.add("conversation_contexts");
  client.evidenceTables.add("messages");
  client.evidenceTables.add("messaging_attachments");
  client.evidenceTables.add("messaging_command_receipts");
  client.evidenceTables.add("messaging_participant_reconciliation_audit");

  const evidence = await getMessagingDeletionEvidence(
    client,
    "11111111-1111-4111-8111-111111111111",
  );

  assertEquals(
    evidence,
    {
      hasEvidence: true,
      sources: [
        "conversations",
        "conversation_participants",
        "conversation_contexts",
        "messages",
        "messaging_attachments",
        "messaging_command_receipts",
        "messaging_participant_reconciliation_audit",
      ],
    },
    "all retained messaging identity surfaces must block Auth deletion",
  );
});

Deno.test("messaging evidence lookup fails closed when a source cannot be verified", async () => {
  const client = new FakeServiceClient();
  client.queryErrors.set("conversation_contexts", {
    message: "relation unavailable",
  });

  let error: unknown = null;
  try {
    await getMessagingDeletionEvidence(
      client,
      "11111111-1111-4111-8111-111111111111",
    );
  } catch (caught) {
    error = caught;
  }

  assert(error instanceof Error, "an incomplete evidence check must throw");
  assert(
    error.message.includes("conversation_contexts"),
    "the failed evidence surface must be named",
  );
});

Deno.test("history-preserving deactivation bans Auth and disables tenant access records", async () => {
  const client = new FakeServiceClient();
  const tenantId = "22222222-2222-4222-8222-222222222222";
  const userId = "11111111-1111-4111-8111-111111111111";

  const result = await deactivateAccountPreservingMessagingHistory(
    client,
    tenantId,
    userId,
    "internal",
  );

  assertEquals(result, { authBanned: true }, "exclusive Auth identity is banned");
  assertEquals(
    client.authUpdates,
    [{ userId, payload: { ban_duration: "876600h" } }],
    "Auth access must be suspended without deleting the identity",
  );
  assertEquals(
    client.updates.map((update) => update.table),
    ["user_profiles"],
    "only the requested internal membership is deactivated",
  );
  for (const update of client.updates) {
    assertEquals(update.payload.is_active, false, `${update.table} is inactive`);
    assert(
      update.filters.some(([column, value]) => column === "tenant_id" && value === tenantId),
      `${update.table} remains tenant scoped`,
    );
  }
});

Deno.test("shared Auth identity keeps another active membership usable", async () => {
  const client = new FakeServiceClient();
  client.evidenceTables.add("user_profiles");
  const tenantId = "22222222-2222-4222-8222-222222222222";
  const userId = "11111111-1111-4111-8111-111111111111";

  const result = await deactivateAccountPreservingMessagingHistory(
    client,
    tenantId,
    userId,
    "customer",
  );

  assertEquals(result, { authBanned: false }, "shared Auth must remain usable");
  assertEquals(client.authUpdates, [], "shared Auth is not globally banned");
  assertEquals(
    client.updates.map((update) => update.table),
    ["customers"],
    "only the requested customer membership is deactivated",
  );
  const activeStaffRead = client.reads.find((read) =>
    read.table === "user_profiles" &&
    read.filters.some(([column]) => column === "or")
  );
  assert(activeStaffRead != null, "remaining staff membership is checked");
  assert(
    !activeStaffRead.filters.some(([column]) => column === "tenant_id"),
    "remaining memberships must be checked globally across tenants",
  );
});

Deno.test("deletion results explicitly distinguish preservation from hard deletion", () => {
  assertEquals(
    preservedMessagingHistoryResult(
      {
        hasEvidence: true,
        sources: ["messages"],
      },
      true,
    ),
    {
      success: true,
      authDeleted: false,
      authBanned: true,
      authDetachedOnly: false,
      accountDeactivated: true,
      preservedForMessagingHistory: true,
      outcome: "deactivated_preserved_messaging_history",
      messagingEvidence: ["messages"],
    },
    "preserved result contract",
  );
  assertEquals(
    hardDeletedAccountResult(),
    {
      success: true,
      authDeleted: true,
      authBanned: false,
      authDetachedOnly: false,
      accountDeactivated: false,
      preservedForMessagingHistory: false,
      outcome: "auth_deleted",
      messagingEvidence: [],
    },
    "hard-delete result contract",
  );
});

Deno.test("admin deletion never nulls immutable messaging authorship", async () => {
  const source = await Deno.readTextFile(
    new URL("./index.ts", import.meta.url),
  );

  for (
    const forbiddenMutation of [
      "update({ created_by: null })",
      "update({ accepted_by: null })",
      "update({ added_by: null })",
      "update({ sender_id: null })",
    ]
  ) {
    assert(
      !source.includes(forbiddenMutation),
      `forbidden audit mutation remains: ${forbiddenMutation}`,
    );
  }
  assert(
    !source.includes("clearCustomerAuthReferencesForDelete"),
    "legacy destructive cleanup helper must stay removed",
  );
});

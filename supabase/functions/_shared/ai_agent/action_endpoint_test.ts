import {
  AgentApprovalActionError,
  createSupabaseAgentApprovalActionExecutor,
  parseApprovalActionRequest,
} from "./action_endpoint.ts";
import type { AgentAuthority, JsonObject } from "./contracts.ts";
import { SupabaseUserDataError } from "./supabase_user_data.ts";

const tenantId = "22222222-2222-4222-8222-222222222222";
const userId = "33333333-3333-4333-8333-333333333333";
const approvalId = "44444444-4444-4444-8444-444444444444";
const clientActionId = "55555555-5555-4555-8555-555555555555";
const taskId = "66666666-6666-4666-8666-666666666666";
const authority: AgentAuthority = {
  tenantId,
  userId,
  role: "manager",
  permissions: {},
  capabilities: ["ai.read.operational"],
  authorityFingerprint: "a".repeat(64),
};

function request(action: "approve" | "discard" = "approve") {
  return parseApprovalActionRequest({
    version: 1,
    operation: "approval_action",
    approvalId,
    approvalAction: action,
    clientActionId,
  });
}

function assertEquals(actual: unknown, expected: unknown, message: string): void {
  if (JSON.stringify(actual) !== JSON.stringify(expected)) {
    throw new Error(`${message}: ${JSON.stringify(actual)} != ${JSON.stringify(expected)}`);
  }
}

Deno.test("approval parser accepts only the exact post-click wire", () => {
  assertEquals(request(), {
    version: 1,
    operation: "approval_action",
    approvalId,
    approvalAction: "approve",
    clientActionId,
  }, "exact request");
  for (
    const invalid of [
      {},
      { ...request(), payload: { title: "injected" } },
      { ...request(), approvalId: "not-a-uuid" },
      { ...request(), approvalAction: "execute" },
      { ...request(), clientActionId: approvalId, version: 2 },
    ]
  ) {
    let rejected = false;
    try {
      parseApprovalActionRequest(invalid);
    } catch (error) {
      rejected = error instanceof AgentApprovalActionError &&
        error.code === "approval_invalid";
    }
    assertEquals(rejected, true, "invalid request is closed");
  }
});

Deno.test("approved task uses only server read-back and yields one task card", async () => {
  let parameters: JsonObject | null = null;
  const executor = createSupabaseAgentApprovalActionExecutor({
    rpc(name, next) {
      assertEquals(name, "assistant_apply_task_approval_v1", "fixed RPC");
      parameters = next;
      return Promise.resolve({
        authorityTenantId: tenantId,
        actorUserId: userId,
        approvalId,
        clientActionId,
        approvalState: "approved",
        task: {
          entityId: taskId,
          title: "Llamar al cliente",
          description: "Confirmar retiro",
          status: "pending",
          priority: "high",
          dueAt: "2026-08-12T18:00:00.000000Z",
          assigneeName: "Tú",
        },
      });
    },
  });
  const response = await executor.apply(request(), authority, new AbortController().signal);
  assertEquals(parameters, {
    p_approval_id: approvalId,
    p_action: "approve",
    p_client_action_id: clientActionId,
  }, "client cannot send a task payload");
  assertEquals(response.approvalState, "approved", "terminal state");
  assertEquals(response.cards.length, 1, "one committed task card");
  assertEquals(response.cards[0].kind, "task", "preview is replaced");
  assertEquals(response.cards[0].title, "Llamar al cliente", "read-back title");
  assertEquals(response.cards[0].approvalRef ?? null, null, "committed card has no approval");
});

Deno.test("discard and expiry are terminal and never fabricate task cards", async () => {
  for (const state of ["discarded", "expired"] as const) {
    const executor = createSupabaseAgentApprovalActionExecutor({
      rpc() {
        return Promise.resolve({
          authorityTenantId: tenantId,
          actorUserId: userId,
          approvalId,
          clientActionId,
          approvalState: state,
          task: null,
        });
      },
    });
    const response = await executor.apply(
      request("discard"),
      authority,
      new AbortController().signal,
    );
    assertEquals(response.approvalState, state, `${state} state`);
    assertEquals(response.cards, [], `${state} has no task card`);
  }
});

Deno.test("approval response is authority-bound and upstream details stay closed", async () => {
  const wrongTenant = createSupabaseAgentApprovalActionExecutor({
    rpc() {
      return Promise.resolve({
        authorityTenantId: "77777777-7777-4777-8777-777777777777",
        actorUserId: userId,
        approvalId,
        clientActionId,
        approvalState: "discarded",
        task: null,
      });
    },
  });
  let invalidResponse = false;
  try {
    await wrongTenant.apply(request(), authority, new AbortController().signal);
  } catch (error) {
    invalidResponse = error instanceof AgentApprovalActionError &&
      error.code === "approval_unavailable";
  }
  assertEquals(invalidResponse, true, "cross-tenant response rejected");

  for (
    const [outcome, code] of [
      ["forbidden", "approval_forbidden"],
      ["idempotency_conflict", "approval_idempotency_conflict"],
      ["unavailable", "approval_unavailable"],
    ] as const
  ) {
    const executor = createSupabaseAgentApprovalActionExecutor({
      rpc() {
        return Promise.reject(new SupabaseUserDataError("rpc_unavailable", false, outcome));
      },
    });
    let actual: string | null = null;
    try {
      await executor.apply(request(), authority, new AbortController().signal);
    } catch (error) {
      actual = error instanceof AgentApprovalActionError ? error.code : null;
    }
    assertEquals(actual, code, `${outcome} maps without upstream text`);
  }
});

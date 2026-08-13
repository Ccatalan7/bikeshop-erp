import { committedTaskCard } from "./cards.ts";
import type {
  AgentApprovalActionRequest,
  AgentApprovalActionResponse,
  AgentAuthority,
  JsonObject,
  JsonValue,
} from "./contracts.ts";
import type { AgentRpcClient } from "./supabase_user_data.ts";
import { SupabaseUserDataError } from "./supabase_user_data.ts";

export class AgentApprovalActionError extends Error {
  constructor(
    readonly status: 400 | 403 | 409 | 503,
    readonly code:
      | "approval_invalid"
      | "approval_forbidden"
      | "approval_idempotency_conflict"
      | "approval_unavailable",
    readonly publicMessage: string,
  ) {
    super(publicMessage);
    this.name = "AgentApprovalActionError";
  }
}

export interface AgentApprovalActionExecutor {
  apply(
    request: AgentApprovalActionRequest,
    authority: AgentAuthority,
    signal: AbortSignal,
  ): Promise<AgentApprovalActionResponse>;
}

export function parseApprovalActionRequest(value: unknown): AgentApprovalActionRequest {
  if (
    !isRecord(value) ||
    !hasExactKeys(value, [
      "version",
      "operation",
      "approvalId",
      "approvalAction",
      "clientActionId",
    ]) ||
    value.version !== 1 || value.operation !== "approval_action" ||
    typeof value.approvalId !== "string" || !validUuid(value.approvalId) ||
    (value.approvalAction !== "approve" && value.approvalAction !== "discard") ||
    typeof value.clientActionId !== "string" || !validUuid(value.clientActionId)
  ) throw invalidApproval();
  return Object.freeze({
    version: 1,
    operation: "approval_action",
    approvalId: value.approvalId.toLowerCase(),
    approvalAction: value.approvalAction,
    clientActionId: value.clientActionId.toLowerCase(),
  });
}

export function createSupabaseAgentApprovalActionExecutor(
  client: AgentRpcClient,
): AgentApprovalActionExecutor {
  return Object.freeze({
    async apply(
      request: AgentApprovalActionRequest,
      authority: AgentAuthority,
      signal: AbortSignal,
    ) {
      let value: unknown;
      try {
        value = await client.rpc("assistant_apply_task_approval_v1", {
          p_approval_id: request.approvalId,
          p_action: request.approvalAction,
          p_client_action_id: request.clientActionId,
        }, AbortSignal.any([signal, AbortSignal.timeout(5_000)]));
      } catch (error) {
        if (signal.aborted) throw error;
        if (error instanceof SupabaseUserDataError) {
          if (error.outcome === "forbidden") {
            // Absence and cross-authority access deliberately collapse to one
            // result so an approval UUID is never an existence oracle.
            throw new AgentApprovalActionError(
              403,
              "approval_forbidden",
              "Approval is unavailable",
            );
          }
          if (error.outcome === "idempotency_conflict") {
            throw new AgentApprovalActionError(
              409,
              "approval_idempotency_conflict",
              "Approval was already used differently",
            );
          }
        }
        throw new AgentApprovalActionError(
          503,
          "approval_unavailable",
          "Approval could not be completed",
        );
      }
      return responseFromRpc(value, request, authority);
    },
  });
}

function responseFromRpc(
  value: unknown,
  request: AgentApprovalActionRequest,
  authority: AgentAuthority,
): AgentApprovalActionResponse {
  if (
    !isRecord(value) ||
    !hasExactKeys(value, [
      "authorityTenantId",
      "actorUserId",
      "approvalId",
      "clientActionId",
      "approvalState",
      "task",
    ]) ||
    value.authorityTenantId !== authority.tenantId ||
    value.actorUserId !== authority.userId ||
    value.approvalId !== request.approvalId ||
    value.clientActionId !== request.clientActionId ||
    !["approved", "discarded", "expired"].includes(String(value.approvalState))
  ) throw unavailableApproval();
  const approvalState = value.approvalState as "approved" | "discarded" | "expired";
  const task = value.task;
  if ((approvalState === "approved") !== isRecord(task)) throw unavailableApproval();
  const cards = approvalState === "approved" && isRecord(task)
    ? [committedTaskCard(validateTask(task))]
    : [];
  return Object.freeze({
    version: 1,
    operation: "approval_action",
    approvalId: request.approvalId,
    clientActionId: request.clientActionId,
    approvalState,
    text: approvalState === "approved"
      ? "Tarea creada."
      : approvalState === "discarded"
      ? "No se creó la tarea."
      : "La confirmación venció; no se creó la tarea.",
    cards: Object.freeze(cards),
    status: "completed",
  });
}

function validateTask(value: Record<string, JsonValue>): JsonObject {
  if (
    !hasExactKeys(value, [
      "entityId",
      "title",
      "description",
      "status",
      "priority",
      "dueAt",
      "assigneeName",
    ]) ||
    typeof value.entityId !== "string" || !validUuid(value.entityId) ||
    typeof value.title !== "string" || !value.title.trim() || utf8Bytes(value.title) > 160 ||
    !(value.description === null ||
      (typeof value.description === "string" && utf8Bytes(value.description) <= 2000)) ||
    value.status !== "pending" ||
    !["low", "normal", "high", "urgent"].includes(String(value.priority)) ||
    !(value.dueAt === null ||
      (typeof value.dueAt === "string" && isoInstant(value.dueAt))) ||
    typeof value.assigneeName !== "string" || !value.assigneeName.trim() ||
    utf8Bytes(value.assigneeName) > 160
  ) throw unavailableApproval();
  return Object.freeze({ ...value });
}

function invalidApproval(): AgentApprovalActionError {
  return new AgentApprovalActionError(400, "approval_invalid", "Approval request is invalid");
}

function unavailableApproval(): AgentApprovalActionError {
  return new AgentApprovalActionError(
    503,
    "approval_unavailable",
    "Approval could not be completed",
  );
}

function isRecord(value: unknown): value is Record<string, JsonValue> {
  return Boolean(value) && typeof value === "object" && !Array.isArray(value);
}

function hasExactKeys(value: Record<string, unknown>, expected: readonly string[]): boolean {
  return JSON.stringify(Object.keys(value).sort()) === JSON.stringify([...expected].sort());
}

function validUuid(value: string): boolean {
  return /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i
    .test(value);
}

function isoInstant(value: string): boolean {
  return /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,6})?(?:Z|[+-]\d{2}:\d{2})$/.test(value) &&
    Number.isFinite(Date.parse(value));
}

function utf8Bytes(value: string): number {
  return new TextEncoder().encode(value).byteLength;
}

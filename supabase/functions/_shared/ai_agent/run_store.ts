import type {
  AgentActionCard,
  AgentAuthority,
  AgentUsage,
  JsonObject,
  LogicalModelRole,
} from "./contracts.ts";
import type { AgentRpcClient } from "./supabase_user_data.ts";
import { SupabaseUserDataError } from "./supabase_user_data.ts";
import { validateStoredCards } from "./cards.ts";
import type { PublicResearchAccounting } from "./public_research.ts";

export type RunTerminalStatus = "succeeded" | "failed" | "cancelled" | "timed_out";
const LEASE_TTL_SECONDS = 110;

export type RunBeginFailure = "idempotency_conflict" | "forbidden" | "quota_exceeded";

export class RunBeginError extends Error {
  constructor(readonly outcome: RunBeginFailure) {
    super("AI run admission failed");
    this.name = "RunBeginError";
  }
}

export interface CanonicalVisibleMessage {
  role: "user" | "assistant";
  content: string;
  /**
   * Closed server-owned presentation state persisted with an assistant turn.
   * The runtime projects only the safe conversational subset it needs; raw
   * entity IDs and approval payloads never enter provider history.
   *
   * Optional keeps in-memory test stores and rolling callers source-compatible.
   * The production admission RPC always publishes this field.
   */
  cards?: readonly AgentActionCard[];
}

export interface AgentRunLease {
  authorityTenantId: string;
  actorUserId: string;
  authorityFingerprint: string;
  threadId: string;
  runId: string;
  runStatus: string;
  runDisposition: "claimed" | "in_progress" | "terminal";
  terminalErrorCode: string | null;
  replayed: boolean;
  leaseToken: string | null;
  fenceToken: number | null;
  canonicalSummary: string | null;
  canonicalMessages: readonly CanonicalVisibleMessage[];
  terminalResponse: { content: string; cards: readonly AgentActionCard[] } | null;
  nextProviderAttemptNo: number;
  nextToolOrdinal: number;
}

export interface AgentRunStore {
  begin(input: {
    authority: AgentAuthority;
    clientRequestId: string;
    requestHash: string;
    userContent: string;
    modelRole: LogicalModelRole;
    threadId: string | null;
    maxOutputTokens: number;
  }, signal: AbortSignal): Promise<AgentRunLease>;
  heartbeat(lease: AgentRunLease, signal: AbortSignal): Promise<{ cancelRequested: boolean }>;
  recordProviderAttempt(input: {
    lease: AgentRunLease;
    attemptNo: number;
    provider: string;
    model: string;
    modelRole: LogicalModelRole;
    status: "succeeded" | "failed" | "timed_out" | "cancelled";
    finishReason?: string;
    usage?: AgentUsage;
    estimatedCostMicrousd: number;
    requestHash?: string;
    responseHash?: string;
    errorCode?: string;
    startedAt: string;
    completedAt: string;
  }, signal: AbortSignal): Promise<void>;
  recordToolReceipt(input: {
    lease: AgentRunLease;
    ordinal: number;
    providerAttemptNo: number;
    providerCallHash: string;
    toolName: string;
    risk: "read" | "public_research" | "draft";
    policyDecision?: "allowed" | "approval_required";
    approvalUsed?: boolean;
    status: "succeeded" | "failed" | "timed_out" | "cancelled" | "rejected";
    argumentsHash: string;
    outputHash?: string;
    resultCount: number;
    outputBytes: number;
    failureCode?: string;
    externalAccounting?: PublicResearchAccounting;
    startedAt: string;
    completedAt: string;
  }, signal: AbortSignal): Promise<void>;
  complete(input: {
    lease: AgentRunLease;
    status: RunTerminalStatus;
    content?: string;
    cards?: readonly AgentActionCard[];
    errorCode?: string;
  }, signal: AbortSignal): Promise<{
    threadId: string;
    runId: string;
    runStatus: RunTerminalStatus;
    terminalErrorCode: string | null;
    response: { content: string; cards: readonly AgentActionCard[] } | null;
  }>;
}

export function createSupabaseAgentRunStore(
  callerClient: AgentRpcClient,
  runtimeClient: AgentRpcClient,
): AgentRunStore {
  return {
    async begin(input, signal) {
      let raw: unknown;
      try {
        raw = await callerClient.rpc("assistant_begin_run_v1", {
          p_client_request_id: input.clientRequestId,
          p_request_hash: input.requestHash,
          p_user_content: input.userContent,
          p_model_role: input.modelRole,
          p_thread_id: input.threadId,
          p_turn_budget: 5,
          p_tool_call_budget: 8,
          p_max_output_tokens: input.maxOutputTokens,
          p_lease_owner: "ai-agent-gateway-v1",
          p_lease_ttl_seconds: LEASE_TTL_SECONDS,
        }, signal);
      } catch (error) {
        if (
          error instanceof SupabaseUserDataError &&
          (error.outcome === "idempotency_conflict" || error.outcome === "forbidden" ||
            error.outcome === "quota_exceeded")
        ) {
          throw new RunBeginError(error.outcome);
        }
        throw error;
      }
      const value = requireRecord(raw);
      const authorityTenantId = requiredUuid(value, "authorityTenantId");
      if (authorityTenantId !== input.authority.tenantId) throw invalidStoreResponse();
      const response = parseStoredResponse(value.response);
      const runDisposition = requiredRunDisposition(value.runDisposition);
      const runStatus = requiredRunStatus(value.runStatus);
      const terminalErrorCode = optionalErrorCode(value.terminalErrorCode);
      const actorUserId = requiredUuid(value, "actorUserId");
      const authorityFingerprint = requiredFingerprint(value.authorityFingerprint);
      if (
        actorUserId !== input.authority.userId ||
        authorityFingerprint !== input.authority.authorityFingerprint
      ) throw invalidStoreResponse();
      const messagesValue = value.canonicalMessages;
      if (!Array.isArray(messagesValue) || messagesValue.length > 20) {
        throw invalidStoreResponse();
      }
      const canonicalMessages = messagesValue.map((item) => {
        const record = requireRecord(item);
        const role = recordString(record, "role");
        const content = boundedString(record.content, 64 * 1024, true);
        if ((role !== "user" && role !== "assistant") || content === null) {
          throw invalidStoreResponse();
        }
        const cards = validateStoredCards(record.cards ?? []);
        if (role === "user" && cards.length !== 0) throw invalidStoreResponse();
        return { role, content, cards } as CanonicalVisibleMessage;
      });
      const leaseToken = optionalUuid(value.leaseToken);
      const fenceToken = optionalSafeInteger(value.fenceToken);
      if (
        (runDisposition === "claimed" &&
          (!leaseToken || fenceToken === null || response || terminalErrorCode ||
            runStatus !== "running")) ||
        (runDisposition === "in_progress" &&
          (leaseToken || fenceToken !== null || response || terminalErrorCode ||
            runStatus !== "running")) ||
        (runDisposition === "terminal" &&
          (runStatus === "running" || leaseToken || fenceToken !== null ||
            (runStatus === "succeeded") !== Boolean(response) ||
            (runStatus === "succeeded" ? terminalErrorCode !== null : terminalErrorCode === null)))
      ) throw invalidStoreResponse();
      return {
        authorityTenantId,
        actorUserId,
        authorityFingerprint,
        threadId: requiredUuid(value, "threadId"),
        runId: requiredUuid(value, "runId"),
        runStatus,
        runDisposition,
        terminalErrorCode,
        replayed: value.replayed === true,
        leaseToken,
        fenceToken,
        canonicalSummary: boundedString(value.canonicalSummary, 16 * 1024, false),
        canonicalMessages,
        terminalResponse: response,
        nextProviderAttemptNo: positiveSafeInteger(value.nextProviderAttemptNo),
        nextToolOrdinal: positiveSafeInteger(value.nextToolOrdinal),
      };
    },

    async heartbeat(lease, signal) {
      const value = requireRecord(
        await runtimeClient.rpc("assistant_heartbeat_run_v2", {
          ...runtimeAuthorityParameters(lease),
          p_run_id: lease.runId,
          p_lease_token: requireLeaseToken(lease),
          p_fence_token: requireFenceToken(lease),
          p_lease_ttl_seconds: LEASE_TTL_SECONDS,
        }, signal),
      );
      validateRunEnvelope(value, lease);
      if (typeof value.cancelRequested !== "boolean") throw invalidStoreResponse();
      return { cancelRequested: value.cancelRequested };
    },

    async recordProviderAttempt(input, signal) {
      const usage = input.usage ?? { inputTokens: 0, outputTokens: 0, totalTokens: 0 };
      const value = requireRecord(
        await runtimeClient.rpc("assistant_record_provider_attempt_v2", {
          ...runtimeAuthorityParameters(input.lease),
          p_run_id: input.lease.runId,
          p_lease_token: requireLeaseToken(input.lease),
          p_fence_token: requireFenceToken(input.lease),
          p_attempt_no: input.attemptNo,
          p_provider: input.provider,
          p_model: input.model,
          p_model_role: input.modelRole,
          p_status: input.status,
          p_finish_reason: input.finishReason ?? null,
          p_cached_input_tokens: usage.cachedInputTokens ?? 0,
          p_input_tokens: usage.inputTokens,
          p_output_tokens: usage.outputTokens,
          p_estimated_cost_microusd: input.estimatedCostMicrousd,
          p_provider_request_hash: input.requestHash ?? null,
          p_response_hash: input.responseHash ?? null,
          p_error_code: input.errorCode ?? null,
          p_started_at: input.startedAt,
          p_completed_at: input.completedAt,
        }, signal),
      );
      validateRunEnvelope(value, input.lease);
    },

    async recordToolReceipt(input, signal) {
      const external = input.externalAccounting;
      const value = requireRecord(
        await runtimeClient.rpc("assistant_record_tool_receipt_v2", {
          ...runtimeAuthorityParameters(input.lease),
          p_run_id: input.lease.runId,
          p_lease_token: requireLeaseToken(input.lease),
          p_fence_token: requireFenceToken(input.lease),
          p_ordinal: input.ordinal,
          p_provider_attempt_no: input.providerAttemptNo,
          p_provider_call_hash: input.providerCallHash,
          p_tool_name: input.toolName,
          p_tool_version: "v1",
          p_risk: input.risk,
          p_policy_decision: input.policyDecision ?? "allowed",
          p_status: input.status,
          p_arguments_hash: input.argumentsHash,
          p_output_hash: input.outputHash ?? null,
          p_result_count: input.resultCount,
          p_output_bytes: input.outputBytes,
          p_approval_used: input.approvalUsed ?? false,
          p_read_back_verified: input.status === "succeeded",
          p_failure_code: input.failureCode ?? null,
          p_external_provider: external?.provider ?? null,
          p_external_model: external?.model ?? null,
          p_external_usage_state: external?.state ?? null,
          p_external_input_tokens: external?.inputTokens ?? 0,
          p_external_output_tokens: external?.outputTokens ?? 0,
          p_external_meter: external?.meter ?? null,
          p_external_meter_units: external?.meterUnits ?? 0,
          p_external_cost_microusd: external?.costMicrousd ?? 0,
          p_started_at: input.startedAt,
          p_completed_at: input.completedAt,
        }, signal),
      );
      validateRunEnvelope(value, input.lease);
    },

    async complete(input, signal) {
      const value = requireRecord(
        await runtimeClient.rpc("assistant_complete_run_v2", {
          ...runtimeAuthorityParameters(input.lease),
          p_run_id: input.lease.runId,
          p_lease_token: requireLeaseToken(input.lease),
          p_fence_token: requireFenceToken(input.lease),
          p_status: input.status,
          p_assistant_content: input.content ?? null,
          p_final_cards: [...(input.cards ?? [])] as unknown as JsonObject,
          p_error_code: input.errorCode ?? null,
        }, signal),
      );
      validateRunEnvelope(value, input.lease);
      const runStatus = requiredRunStatus(value.runStatus);
      if (runStatus === "running") throw invalidStoreResponse();
      const terminalErrorCode = optionalErrorCode(value.terminalErrorCode);
      const response = parseStoredResponse(value.response);
      if (
        (runStatus === "succeeded") !== Boolean(response) ||
        (runStatus === "succeeded" ? terminalErrorCode !== null : terminalErrorCode === null)
      ) throw invalidStoreResponse();
      return {
        threadId: requiredUuid(value, "threadId"),
        runId: requiredUuid(value, "runId"),
        runStatus,
        terminalErrorCode,
        response,
      };
    },
  };
}

function parseStoredResponse(
  value: unknown,
): { content: string; cards: readonly AgentActionCard[] } | null {
  if (value === null || value === undefined) return null;
  const record = requireRecord(value);
  const content = requiredString(record, "content", 64 * 1024);
  const cards = record.cards;
  return { content, cards: validateStoredCards(cards) };
}

function validateRunEnvelope(value: Record<string, unknown>, lease: AgentRunLease): void {
  if (
    requiredUuid(value, "authorityTenantId") !== lease.authorityTenantId ||
    requiredUuid(value, "runId") !== lease.runId
  ) throw invalidStoreResponse();
}

function requireLeaseToken(lease: AgentRunLease): string {
  if (!lease.leaseToken) throw new Error("Run has no active lease");
  return lease.leaseToken;
}

function requireFenceToken(lease: AgentRunLease): number {
  if (lease.fenceToken === null) throw new Error("Run has no active fence");
  return lease.fenceToken;
}

function requireRecord(value: unknown): Record<string, unknown> {
  if (!value || typeof value !== "object" || Array.isArray(value)) throw invalidStoreResponse();
  return value as Record<string, unknown>;
}

function requiredString(value: Record<string, unknown>, key: string, max: number): string {
  const parsed = boundedString(value[key], max, true);
  if (parsed === null) throw invalidStoreResponse();
  return parsed;
}

function recordString(value: Record<string, unknown>, key: string): string | null {
  return typeof value[key] === "string" ? value[key] as string : null;
}

function boundedString(value: unknown, max: number, allowEmpty: boolean): string | null {
  if (
    typeof value !== "string" || new TextEncoder().encode(value).byteLength > max ||
    (!allowEmpty && !value.trim())
  ) {
    return null;
  }
  return value;
}

function requiredUuid(value: Record<string, unknown>, key: string): string {
  const parsed = optionalUuid(value[key]);
  if (!parsed) throw invalidStoreResponse();
  return parsed;
}

function optionalUuid(value: unknown): string | null {
  return typeof value === "string" &&
      /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i
        .test(value)
    ? value
    : null;
}

function optionalSafeInteger(value: unknown): number | null {
  return typeof value === "number" && Number.isSafeInteger(value) && value >= 0 ? value : null;
}

function positiveSafeInteger(value: unknown): number {
  if (typeof value !== "number" || !Number.isSafeInteger(value) || value < 1) {
    throw invalidStoreResponse();
  }
  return value;
}

function requiredRunDisposition(value: unknown): AgentRunLease["runDisposition"] {
  if (value === "claimed" || value === "in_progress" || value === "terminal") return value;
  throw invalidStoreResponse();
}

function requiredRunStatus(value: unknown): "running" | RunTerminalStatus {
  if (
    value === "running" || value === "succeeded" || value === "failed" ||
    value === "cancelled" || value === "timed_out"
  ) return value;
  throw invalidStoreResponse();
}

function runtimeAuthorityParameters(lease: AgentRunLease): JsonObject {
  return {
    p_tenant_id: lease.authorityTenantId,
    p_actor_user_id: lease.actorUserId,
    p_authority_fingerprint: lease.authorityFingerprint,
  };
}

function requiredFingerprint(value: unknown): string {
  if (typeof value !== "string" || !/^[A-Za-z0-9._:-]{32,256}$/.test(value)) {
    throw invalidStoreResponse();
  }
  return value;
}

function optionalErrorCode(value: unknown): string | null {
  if (value === null || value === undefined) return null;
  if (typeof value !== "string" || !/^[a-z][a-z0-9_]{1,63}$/.test(value)) {
    throw invalidStoreResponse();
  }
  return value;
}

function invalidStoreResponse(): Error {
  return new Error("AI run store returned an invalid response");
}

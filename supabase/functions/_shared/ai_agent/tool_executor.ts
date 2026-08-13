import type {
  AgentAuthority,
  AgentToolCall,
  AgentToolResultEnvelope,
  JsonObject,
  JsonValue,
} from "./contracts.ts";
import { type AgentRpcClient, SupabaseUserDataError } from "./supabase_user_data.ts";
import {
  type AgentPublicResearchClient,
  createPublicResearchRequest,
  type PublicResearchAccounting,
  PublicResearchError,
  type PublicResearchEvidenceCompleteness,
  validatePublicResearchArguments,
} from "./public_research.ts";

const MAX_TOOL_OUTPUT_BYTES = 48 * 1024;

const workshopViewFields = [
  "jobNumber",
  "customerName",
  "status",
  "priority",
  "arrivalDate",
  "deliveryDeadline",
  "clientRequest",
  "assignedTechnicianName",
] as const;

const toolContracts = {
  inspect_inventory_schema: {
    rpc: "assistant_inspect_inventory_schema_v1",
    parameters: inventorySchemaInspectionParameters,
    fields: [
      "kind",
      "category",
      "categoryPath",
      "technicalFamily",
      "field",
      "label",
      "dataType",
      "unit",
      "operators",
      "allowedValues",
      "productCount",
      "populatedCount",
    ],
    maxItems: 40,
  },
  search_inventory: {
    rpc: "assistant_search_inventory_v5",
    parameters: inventorySearchParameters,
    fields: [
      "entityId",
      "name",
      "sku",
      "brand",
      "category",
      "price",
      "stock",
      "minimumStock",
      "availability",
      "tracksInventory",
      "location",
      "technicalMatch",
    ],
  },
  find_inventory_risks: {
    rpc: "assistant_find_inventory_risks_v1",
    parameters: (args: JsonObject) => ({
      p_query: normalizedOptionalQuery(args.query),
      p_risk: args.risk,
      p_limit: args.limit,
    }),
    fields: [
      "entityId",
      "name",
      "sku",
      "category",
      "stock",
      "minimumStock",
      "risk",
      "isSet",
      "updatedAt",
    ],
  },
  list_attention_items: {
    rpc: "assistant_list_attention_items_v1",
    parameters: (args: JsonObject) => ({ p_horizon: args.horizon }),
    fields: ["source", "reason", "title", "detail", "priorityRank", "dueAt"],
  },
  get_business_snapshot: {
    rpc: "assistant_get_business_snapshot_v1",
    parameters: (args: JsonObject) => ({ p_horizon: args.horizon }),
    fields: [
      "source",
      "sourceStatus",
      "horizon",
      "openCount",
      "overdueCount",
      "dueInHorizonCount",
      "urgentCount",
      "awaitingApprovalCount",
      "assignedToMeCount",
      "trackedItemCount",
      "lowStockCount",
      "outOfStockCount",
    ],
    maxItems: 3,
  },
  search_workshop_jobs: {
    rpc: "assistant_query_workshop_jobs_v2",
    parameters: workshopQueryParameters,
    fields: [
      "entityId",
      "jobNumber",
      "customerName",
      "status",
      "priority",
      "arrivalDate",
      "deliveryDeadline",
      "clientRequest",
      "assignedTechnicianName",
    ],
  },
  search_tasks: {
    rpc: "assistant_query_tasks_v2",
    parameters: taskQueryParameters,
    fields: [
      "entityId",
      "title",
      "status",
      "priority",
      "dueDate",
      "assigneeName",
      "linkedContext",
    ],
  },
  search_customers: {
    rpc: "assistant_search_customers_v1",
    parameters: boundedSearchParameters,
    fields: ["entityId", "name", "isActive", "updatedAt"],
  },
  search_suppliers: {
    rpc: "assistant_search_suppliers_v1",
    parameters: boundedSearchParameters,
    fields: ["entityId", "name", "isActive", "updatedAt"],
  },
  search_sales_invoices: {
    rpc: "assistant_search_sales_invoices_v1",
    parameters: boundedSearchParameters,
    fields: [
      "entityId",
      "invoiceNumber",
      "customerName",
      "status",
      "date",
      "dueDate",
      "total",
      "balance",
    ],
  },
  search_purchase_invoices: {
    rpc: "assistant_search_purchase_invoices_v1",
    parameters: boundedSearchParameters,
    fields: [
      "entityId",
      "invoiceNumber",
      "supplierName",
      "status",
      "date",
      "dueDate",
      "total",
      "balance",
    ],
  },
  list_recent_expenses: {
    rpc: "assistant_list_recent_expenses_v1",
    parameters: (args: JsonObject) => ({
      p_query: normalizedOptionalQuery(args.query),
      p_days: args.days,
      p_posting_status: args.postingStatus,
      p_payment_status: args.paymentStatus,
      p_approval_status: args.approvalStatus,
      p_limit: args.limit,
    }),
    fields: [
      "entityId",
      "expenseNumber",
      "category",
      "issueDate",
      "dueDate",
      "postingStatus",
      "paymentStatus",
      "approvalStatus",
      "currency",
      "totalAmount",
      "amountPaid",
      "balance",
    ],
  },
  analyze_cash_and_receivables: {
    rpc: "assistant_analyze_cash_and_receivables_v1",
    parameters: (args: JsonObject) => ({
      p_horizon: args.horizon,
      p_limit: args.limit,
    }),
    fields: [],
    maxItems: 9,
  },
  search_conversations: {
    rpc: "assistant_search_conversations_v1",
    parameters: (args: JsonObject) => ({
      p_query: normalizedOptionalQuery(args.query),
      p_channel: args.channel,
      p_status: args.status,
      p_context_type: args.contextType,
      p_unread_only: args.unreadOnly,
      p_needs_reply_only: args.needsReplyOnly,
      p_days: args.days,
      p_limit: args.limit,
    }),
    fields: [
      "entityId",
      "channel",
      "counterpartyType",
      "status",
      "isGroup",
      "contextType",
      "contextEntityId",
      "contextLabel",
      "lastMessageAt",
      "lastMessageType",
      "lastMessageDirection",
      "unreadCount",
      "needsReply",
    ],
  },
  prepare_task: {
    rpc: "assistant_prepare_task_v1",
    parameters: (args: JsonObject, context?: AgentToolExecutionContext) => {
      if (!context) throw new InvalidToolArguments();
      return {
        p_title: args.title,
        p_description: args.description,
        p_priority: args.priority,
        p_due_at: args.dueAt,
        p_assignee_mode: args.assigneeMode,
        p_assignee_name: args.assigneeName,
        p_run_id: context.runId,
        p_provider_attempt_no: context.providerAttemptNo,
        p_provider_call_hash: context.providerCallHash,
        p_arguments_hash: context.argumentsHash,
      };
    },
    fields: [
      "approvalId",
      "action",
      "state",
      "title",
      "description",
      "priority",
      "dueAt",
      "assigneeMode",
      "assigneeName",
      "expiresAt",
    ],
    maxItems: 1,
  },
} as const;

export interface AgentToolExecution {
  result: AgentToolResultEnvelope;
  outputText: string;
  outputBytes: number;
  succeeded: boolean;
  failureCode?: string;
  externalAccounting?: PublicResearchAccounting;
  publicResearchCompleteness?: PublicResearchEvidenceCompleteness;
}

export interface AgentToolExecutor {
  execute(
    call: AgentToolCall,
    authority: AgentAuthority,
    signal: AbortSignal,
    context?: AgentToolExecutionContext,
  ): Promise<AgentToolExecution>;
  workshopViewContext(
    jobIds: readonly string[],
    authority: AgentAuthority,
    signal: AbortSignal,
  ): Promise<AgentToolResultEnvelope>;
}

export interface AgentToolExecutionContext {
  runId: string;
  providerAttemptNo: number;
  providerCallHash: string;
  argumentsHash: string;
  currentUserMessage: string;
}

export function createSupabaseAgentToolExecutor(
  client: AgentRpcClient,
  options: { publicResearch?: AgentPublicResearchClient } = {},
): AgentToolExecutor {
  return {
    async execute(call, authority, signal, context) {
      if (call.name === "research_public_web") {
        return await executePublicResearch(
          call,
          authority,
          options.publicResearch,
          signal,
          context,
        );
      }
      if (call.name === "report_capability_gap") {
        return capabilityGapExecution(call.arguments, authority.tenantId);
      }
      const contract = toolContracts[call.name as keyof typeof toolContracts];
      if (!contract) return unavailable(authority.tenantId, "unknown_tool");
      try {
        throwIfAborted(signal);
        const toolSignal = AbortSignal.any([signal, AbortSignal.timeout(5_000)]);
        const parameters = contract.parameters(call.arguments, context) as JsonObject;
        validateRpcParameters(call.name, parameters);
        const value = await client.rpc(
          contract.rpc,
          parameters,
          toolSignal,
        );
        const requestedLimit = typeof call.arguments.limit === "number"
          ? call.arguments.limit
          : null;
        const maxItems = call.name === "get_business_snapshot"
          ? 3
          : requestedLimit ?? ("maxItems" in contract ? contract.maxItems : 10);
        const result = call.name === "analyze_cash_and_receivables"
          ? validateCashAndReceivablesEnvelope(value, authority, call.arguments)
          : validateEnvelope(value, authority, contract.fields, maxItems);
        if (call.name === "get_business_snapshot") validateBusinessSnapshot(result, call.arguments);
        validateSpecializedResult(call.name, result, call.arguments);
        const outputText = JSON.stringify(modelVisibleResult(result));
        const outputBytes = new TextEncoder().encode(outputText).byteLength;
        if (outputBytes > MAX_TOOL_OUTPUT_BYTES) {
          return unavailable(authority.tenantId, "tool_output_too_large");
        }
        return { result, outputText, outputBytes, succeeded: true };
      } catch (error) {
        throwIfAborted(signal);
        return unavailable(
          authority.tenantId,
          error instanceof InvalidToolArguments ||
            (error instanceof SupabaseUserDataError &&
              error.outcome === "idempotency_conflict")
            ? "tool_arguments_invalid"
            : "tool_source_unavailable",
        );
      }
    },

    async workshopViewContext(jobIds, authority, signal) {
      try {
        throwIfAborted(signal);
        const value = await client.rpc("assistant_get_workshop_view_context_v1", {
          p_job_ids: [...jobIds],
        }, AbortSignal.any([signal, AbortSignal.timeout(5_000)]));
        return validateEnvelope(
          value,
          authority,
          workshopViewFields,
          20,
        );
      } catch (error) {
        throwIfAborted(signal);
        throw error;
      }
    },
  };
}

async function executePublicResearch(
  call: AgentToolCall,
  authority: AgentAuthority,
  client: AgentPublicResearchClient | undefined,
  signal: AbortSignal,
  context: AgentToolExecutionContext | undefined,
): Promise<AgentToolExecution> {
  if (!client) return unavailable(authority.tenantId, "tool_not_activated");
  try {
    validatePublicResearchArguments(call.arguments);
    if (!context) throw new PublicResearchError("invalid_response");
  } catch (_) {
    return unavailable(authority.tenantId, "tool_arguments_invalid");
  }
  let incurredAccounting: PublicResearchAccounting | undefined;
  try {
    throwIfAborted(signal);
    const research = await client.research(
      createPublicResearchRequest(context.currentUserMessage),
      AbortSignal.any([signal, AbortSignal.timeout(70_000)]),
    );
    incurredAccounting = research.accounting;
    const publicSources = modelVisiblePublicResearchSources(
      research.sources,
      research.accounting,
    );
    const result: AgentToolResultEnvelope = Object.freeze({
      authorityTenantId: authority.tenantId,
      asOf: research.asOf,
      status: research.status,
      items: publicSources,
      resultCount: publicSources.length,
      hasMore: research.hasMore,
    });
    const outputText = JSON.stringify({
      ...modelVisibleResult(result),
      ...(research.evidenceCompleteness.targets.length
        ? {
          evidenceCompleteness: {
            targets: modelVisiblePublicResearchTargets(research.evidenceCompleteness),
          },
        }
        : {}),
    });
    const outputBytes = new TextEncoder().encode(outputText).byteLength;
    if (outputBytes > MAX_TOOL_OUTPUT_BYTES) {
      return {
        ...unavailable(authority.tenantId, "tool_output_too_large"),
        externalAccounting: research.accounting,
      };
    }
    return {
      result,
      outputText,
      outputBytes,
      succeeded: research.status !== "unavailable",
      failureCode: research.status === "unavailable" ? "tool_source_unavailable" : undefined,
      externalAccounting: research.accounting,
      publicResearchCompleteness: research.evidenceCompleteness,
    };
  } catch (error) {
    return {
      ...unavailable(authority.tenantId, "tool_source_unavailable"),
      ...(error instanceof PublicResearchError && error.accounting
        ? { externalAccounting: error.accounting }
        : incurredAccounting
        ? { externalAccounting: incurredAccounting }
        : {}),
    };
  }
}

function modelVisiblePublicResearchSources(
  sources: readonly JsonObject[],
  accounting: PublicResearchAccounting,
): readonly JsonObject[] {
  if (!Array.isArray(sources)) {
    throw new PublicResearchError("invalid_response", accounting);
  }
  return Object.freeze(sources.map((source) => {
    if (
      !isRecord(source) || typeof source.title !== "string" ||
      typeof source.url !== "string" || typeof source.snippet !== "string" ||
      (source.publishedAt !== undefined && typeof source.publishedAt !== "string")
    ) {
      throw new PublicResearchError("invalid_response", accounting);
    }
    return Object.freeze({
      title: source.title,
      url: source.url,
      snippet: source.snippet,
      ...(source.publishedAt === undefined ? {} : { publishedAt: source.publishedAt }),
    });
  }));
}

function modelVisiblePublicResearchTargets(
  completeness: PublicResearchEvidenceCompleteness,
): readonly JsonObject[] {
  return completeness.targets.map((target) => ({
    id: target.id,
    fact: target.fact,
    position: target.position,
    state: target.state,
    evidence: target.evidence.map((item) => ({
      sourceUrl: item.sourceUrl,
      quote: item.quote,
    })),
  }));
}

function throwIfAborted(signal: AbortSignal): void {
  if (signal.aborted) throw new DOMException("Request aborted", "AbortError");
}

function boundedSearchParameters(args: JsonObject): JsonObject {
  return { p_query: args.query, p_limit: args.limit };
}

function inventorySchemaInspectionParameters(args: JsonObject): JsonObject {
  if (
    !hasExactKeys(args, ["query", "category"]) ||
    typeof args.query !== "string" || !args.query.trim() ||
    utf8Bytes(args.query.trim()) > 240 ||
    !(args.category === null ||
      (typeof args.category === "string" && args.category.trim() &&
        utf8Bytes(args.category.trim()) <= 160))
  ) throw new InvalidToolArguments();
  return {
    p_query: args.query.trim(),
    p_category: typeof args.category === "string" ? args.category.trim() : null,
  };
}

function inventorySearchParameters(args: JsonObject): JsonObject {
  if (
    !hasExactKeys(args, [
      "query",
      "category",
      "availability",
      "presentation",
      "technicalPredicates",
    ]) ||
    !(args.query === null ||
      (typeof args.query === "string" && args.query.trim() &&
        utf8Bytes(args.query.trim()) <= 240)) ||
    !(args.category === null ||
      (typeof args.category === "string" && args.category.trim() &&
        utf8Bytes(args.category.trim()) <= 160)) ||
    !["any", "in_stock", "low_stock", "out_of_stock"].includes(
      String(args.availability),
    ) ||
    !["answer", "open_list"].includes(String(args.presentation))
  ) throw new InvalidToolArguments();
  const technicalPredicates = normalizedInventoryTechnicalPredicates(
    args.technicalPredicates,
  );
  if (args.query === null && args.category === null && technicalPredicates.length === 0) {
    throw new InvalidToolArguments();
  }
  return {
    p_query: typeof args.query === "string" ? args.query.trim() : null,
    p_category: typeof args.category === "string" ? args.category.trim() : null,
    p_availability: args.availability,
    p_technical_predicates: technicalPredicates,
  };
}

function normalizedInventoryTechnicalPredicates(value: JsonValue): JsonValue[] {
  if (!Array.isArray(value) || value.length > 8) throw new InvalidToolArguments();
  const fields = new Set<string>();
  return value.map((predicate) => {
    if (
      !isRecord(predicate) ||
      !hasExactKeys(predicate, ["field", "operator", "values"]) ||
      typeof predicate.field !== "string" ||
      !/^[a-z][a-z0-9_]{1,63}$/.test(predicate.field) ||
      fields.has(predicate.field) ||
      typeof predicate.operator !== "string" ||
      !["eq", "neq", "lt", "lte", "gt", "gte", "between", "in", "contains"]
        .includes(predicate.operator) ||
      !Array.isArray(predicate.values) || predicate.values.length < 1 ||
      predicate.values.length > 10 ||
      (predicate.operator === "between" && predicate.values.length !== 2) ||
      (predicate.operator !== "between" && predicate.operator !== "in" &&
        predicate.values.length !== 1) ||
      predicate.values.some((item) =>
        !["string", "number", "boolean"].includes(typeof item) ||
        (typeof item === "string" &&
          (!item.trim() || utf8Bytes(item.trim()) > 120))
      )
    ) throw new InvalidToolArguments();
    fields.add(predicate.field);
    return {
      field: predicate.field,
      operator: predicate.operator,
      values: predicate.values.map((item) => typeof item === "string" ? item.trim() : item),
    };
  });
}

function workshopQueryParameters(args: JsonObject): JsonObject {
  return {
    p_query: normalizedOptionalQuery(args.query),
    p_horizon: args.horizon,
    p_status: args.status,
    p_priority: args.priority,
    p_limit: args.limit,
  };
}

function normalizedOptionalQuery(value: JsonValue): string | null {
  return typeof value === "string" && value.trim() ? value.trim() : null;
}

function taskQueryParameters(args: JsonObject): JsonObject {
  return {
    ...workshopQueryParameters(args),
    p_assignee: args.assignee,
  };
}

class InvalidToolArguments extends Error {}

function validateRpcParameters(toolName: string, parameters: JsonObject): void {
  if (toolName === "prepare_task") {
    if (
      typeof parameters.p_title !== "string" || !parameters.p_title.trim() ||
      utf8Bytes(parameters.p_title) > 160 ||
      !(parameters.p_description === null ||
        (typeof parameters.p_description === "string" &&
          parameters.p_description.trim() && utf8Bytes(parameters.p_description) <= 2000)) ||
      !["low", "normal", "high", "urgent"].includes(String(parameters.p_priority)) ||
      !(parameters.p_due_at === null ||
        (typeof parameters.p_due_at === "string" && isoInstant(parameters.p_due_at))) ||
      !["me", "unassigned", "name"].includes(String(parameters.p_assignee_mode)) ||
      ((parameters.p_assignee_mode === "name") !==
        (typeof parameters.p_assignee_name === "string" &&
          Boolean(parameters.p_assignee_name.trim()) &&
          utf8Bytes(parameters.p_assignee_name) <= 160)) ||
      typeof parameters.p_run_id !== "string" || !validUuid(parameters.p_run_id) ||
      !boundedInteger(parameters.p_provider_attempt_no, 1, 42) ||
      typeof parameters.p_provider_call_hash !== "string" ||
      !/^[0-9a-f]{64}$/.test(parameters.p_provider_call_hash) ||
      typeof parameters.p_arguments_hash !== "string" ||
      !/^[0-9a-f]{64}$/.test(parameters.p_arguments_hash)
    ) throw new InvalidToolArguments();
    return;
  }
  if (toolName === "list_attention_items") {
    if (parameters.p_horizon !== "today" && parameters.p_horizon !== "tomorrow") {
      throw new InvalidToolArguments();
    }
    return;
  }
  if (toolName === "get_business_snapshot") {
    if (!["today", "tomorrow", "next_7_days"].includes(String(parameters.p_horizon))) {
      throw new InvalidToolArguments();
    }
    return;
  }
  if (toolName === "analyze_cash_and_receivables") {
    if (
      !["today", "next_7_days", "next_30_days"].includes(String(parameters.p_horizon)) ||
      !boundedInteger(parameters.p_limit, 1, 8)
    ) throw new InvalidToolArguments();
    return;
  }
  const query = parameters.p_query;
  if (
    query !== null &&
    (typeof query !== "string" || !query.trim() ||
      new TextEncoder().encode(query).byteLength > 240)
  ) throw new InvalidToolArguments();
  if (toolName === "inspect_inventory_schema") {
    if (
      typeof query !== "string" ||
      !(parameters.p_category === null ||
        (typeof parameters.p_category === "string" && parameters.p_category.trim()))
    ) throw new InvalidToolArguments();
    return;
  }
  if (
    toolName === "search_inventory" &&
    query === null && parameters.p_category === null &&
    Array.isArray(parameters.p_technical_predicates) &&
    parameters.p_technical_predicates.length === 0
  ) {
    throw new InvalidToolArguments();
  }
  if (
    toolName === "search_inventory" &&
    !["any", "in_stock", "low_stock", "out_of_stock"].includes(
      String(parameters.p_availability),
    )
  ) throw new InvalidToolArguments();
  if (
    toolName === "search_inventory" &&
    !Array.isArray(parameters.p_technical_predicates)
  ) {
    throw new InvalidToolArguments();
  }
  if (
    toolName === "find_inventory_risks" &&
    !["any", "low_stock", "out_of_stock"].includes(String(parameters.p_risk))
  ) throw new InvalidToolArguments();
  if (toolName === "list_recent_expenses") {
    if (
      !boundedInteger(parameters.p_days, 1, 365) ||
      !["any", "draft", "posted", "void"].includes(String(parameters.p_posting_status)) ||
      !["any", "pending", "scheduled", "partial", "paid", "void"].includes(
        String(parameters.p_payment_status),
      ) ||
      !["any", "pending", "approved", "rejected"].includes(
        String(parameters.p_approval_status),
      )
    ) throw new InvalidToolArguments();
  }
  if (toolName === "search_conversations") {
    if (
      !["any", "internal", "website_portal", "whatsapp", "instagram", "facebook_messenger"]
        .includes(String(parameters.p_channel)) ||
      !["any", "pending", "active", "resolved", "rejected"].includes(
        String(parameters.p_status),
      ) ||
      ![
        "any",
        "job",
        "invoice",
        "order",
        "purchase_invoice",
        "supplier",
        "customer",
        "product",
        "bike",
      ]
        .includes(String(parameters.p_context_type)) ||
      typeof parameters.p_unread_only !== "boolean" ||
      typeof parameters.p_needs_reply_only !== "boolean" ||
      !boundedInteger(parameters.p_days, 1, 365)
    ) throw new InvalidToolArguments();
  }
  if (toolName === "search_workshop_jobs" || toolName === "search_tasks") {
    if (
      !["any", "today", "tomorrow", "week", "overdue"].includes(String(parameters.p_horizon)) ||
      !["any", "urgent", "high", "normal", "low"].includes(String(parameters.p_priority)) ||
      (toolName === "search_workshop_jobs" &&
        !["any", "open", "completed", "delivered", "cancelled"].includes(
          String(parameters.p_status),
        )) ||
      (toolName === "search_tasks" &&
        !["any", "pending", "in_progress", "completed", "cancelled"].includes(
          String(parameters.p_status),
        )) ||
      (toolName === "search_tasks" &&
        !["any", "me", "unassigned"].includes(String(parameters.p_assignee)))
    ) throw new InvalidToolArguments();
  }
  if (toolName !== "search_inventory") {
    const limit = parameters.p_limit;
    if (!Number.isSafeInteger(limit) || (limit as number) < 1 || (limit as number) > 10) {
      throw new InvalidToolArguments();
    }
  }
}

function boundedInteger(value: JsonValue, minimum: number, maximum: number): boolean {
  return Number.isSafeInteger(value) && (value as number) >= minimum &&
    (value as number) <= maximum;
}

function validateEnvelope(
  value: unknown,
  authority: AgentAuthority,
  allowedFields: readonly string[],
  maxItems: number,
): AgentToolResultEnvelope {
  if (
    !isRecord(value) || !hasExactKeys(value, [
      "authorityTenantId",
      "asOf",
      "status",
      "items",
      "resultCount",
      "hasMore",
    ])
  ) throw new Error("invalid tool envelope");
  if (value.authorityTenantId !== authority.tenantId) throw new Error("tool tenant mismatch");
  if (typeof value.asOf !== "string" || !Date.parse(value.asOf)) {
    throw new Error("invalid tool timestamp");
  }
  if (value.status !== "success" && value.status !== "verifiedEmpty") {
    throw new Error("invalid tool status");
  }
  if (
    !Array.isArray(value.items) || value.items.length > maxItems ||
    !Number.isSafeInteger(value.resultCount) || value.resultCount !== value.items.length ||
    typeof value.hasMore !== "boolean"
  ) throw new Error("invalid tool result count");
  if (
    (value.status === "verifiedEmpty" &&
      (value.items.length !== 0 || value.resultCount !== 0 || value.hasMore)) ||
    (value.status === "success" && value.items.length === 0)
  ) {
    throw new Error("invalid verified empty result");
  }
  const allowed = new Set(allowedFields);
  const items = value.items.map((item) => {
    if (
      !isRecord(item) || !hasExactKeys(item, allowedFields) ||
      Object.keys(item).some((key) => !allowed.has(key))
    ) {
      throw new Error("invalid tool item");
    }
    for (const [key, field] of Object.entries(item)) {
      if (field !== null && !["string", "number", "boolean"].includes(typeof field)) {
        throw new Error("invalid tool field");
      }
      if (typeof field === "string" && new TextEncoder().encode(field).byteLength > 512) {
        throw new Error("tool field too long");
      }
      if (typeof field === "number" && !Number.isFinite(field)) throw new Error("invalid number");
      if (key === "entityId" && (typeof field !== "string" || !validUuid(field))) {
        throw new Error("invalid entity id");
      }
    }
    return Object.freeze({ ...item }) as JsonObject;
  });
  return Object.freeze({
    authorityTenantId: authority.tenantId,
    asOf: value.asOf,
    status: value.status,
    items,
    resultCount: value.resultCount as number,
    hasMore: value.hasMore,
  });
}

const snapshotMetricFields = [
  "openCount",
  "overdueCount",
  "dueInHorizonCount",
  "urgentCount",
  "awaitingApprovalCount",
  "assignedToMeCount",
  "trackedItemCount",
  "lowStockCount",
  "outOfStockCount",
] as const;

function validateBusinessSnapshot(result: AgentToolResultEnvelope, args: JsonObject): void {
  if (
    result.status !== "success" || result.resultCount !== 3 || result.items.length !== 3 ||
    result.hasMore ||
    JSON.stringify(result.items.map((item) => item.source)) !==
      JSON.stringify(["workshop_jobs", "tasks", "inventory"])
  ) throw new Error("invalid business snapshot");
  for (const item of result.items) {
    if (
      item.horizon !== args.horizon ||
      !["success", "verifiedEmpty", "unavailable"].includes(String(item.sourceStatus))
    ) throw new Error("invalid business snapshot");
    for (const field of snapshotMetricFields) {
      const value = item[field];
      if (value !== null && (!Number.isSafeInteger(value) || (value as number) < 0)) {
        throw new Error("invalid business snapshot");
      }
      if (item.sourceStatus === "unavailable" && value !== null) {
        throw new Error("invalid unavailable snapshot");
      }
    }
    const numericFields = item.source === "workshop_jobs"
      ? new Set([
        "openCount",
        "overdueCount",
        "dueInHorizonCount",
        "urgentCount",
        "awaitingApprovalCount",
      ])
      : item.source === "tasks"
      ? new Set([
        "openCount",
        "overdueCount",
        "dueInHorizonCount",
        "urgentCount",
        "assignedToMeCount",
      ])
      : new Set(["trackedItemCount", "lowStockCount", "outOfStockCount"]);
    if (
      item.sourceStatus !== "unavailable" &&
      snapshotMetricFields.some((field) => numericFields.has(field) !== (item[field] !== null))
    ) throw new Error("invalid snapshot projection");
    if (
      item.sourceStatus === "verifiedEmpty" &&
      [...numericFields].some((field) => item[field] !== 0)
    ) throw new Error("invalid verified-empty snapshot");
    const primaryCount = item.source === "inventory" ? item.trackedItemCount : item.openCount;
    if (item.sourceStatus === "success" && (typeof primaryCount !== "number" || primaryCount < 1)) {
      throw new Error("invalid successful snapshot");
    }
  }
}

function validateSpecializedResult(
  toolName: string,
  result: AgentToolResultEnvelope,
  args: JsonObject,
): void {
  if (toolName === "search_inventory") validateInventorySearch(result, args);
  if (toolName === "inspect_inventory_schema") {
    validateInventorySchemaInspection(result);
  }
  if (toolName === "find_inventory_risks") validateInventoryRisks(result, args);
  if (toolName === "list_recent_expenses") validateRecentExpenses(result, args);
  if (toolName === "search_conversations") validateConversations(result, args);
  if (toolName === "prepare_task") validatePreparedTask(result, args);
}

function validateInventorySearch(result: AgentToolResultEnvelope, args: JsonObject): void {
  for (const item of result.items) {
    const stock = item.stock;
    const minimumStock = item.minimumStock;
    const availability = item.availability;
    const tracksInventory = item.tracksInventory;
    if (
      typeof item.name !== "string" || !item.name.trim() ||
      !nullableString(item.sku) || !nullableString(item.brand) ||
      !nullableString(item.category) || !nullableString(item.location) ||
      !["not_applicable", "product_spec", "identity_fallback"].includes(
        String(item.technicalMatch),
      ) ||
      ((args.technicalPredicates as JsonValue[]).length === 0
        ? item.technicalMatch !== "not_applicable"
        : item.technicalMatch === "not_applicable") ||
      !finiteNumber(item.price) || !Number.isSafeInteger(stock) ||
      !Number.isSafeInteger(minimumStock) || (minimumStock as number) < 0 ||
      typeof tracksInventory !== "boolean" ||
      !["not_tracked", "in_stock", "low_stock", "out_of_stock"].includes(
        String(availability),
      ) ||
      (tracksInventory === false && availability !== "not_tracked") ||
      (tracksInventory === true && availability === "not_tracked") ||
      (availability === "in_stock" && (stock as number) <= (minimumStock as number)) ||
      (availability === "low_stock" &&
        ((stock as number) <= 0 || (stock as number) > (minimumStock as number))) ||
      (availability === "out_of_stock" && (stock as number) > 0) ||
      (args.availability === "in_stock" && (stock as number) <= 0) ||
      (args.availability === "low_stock" && availability !== "low_stock") ||
      (args.availability === "out_of_stock" && availability !== "out_of_stock")
    ) throw new Error("invalid inventory search");
  }
}

function validateInventorySchemaInspection(result: AgentToolResultEnvelope): void {
  for (const item of result.items) {
    if (
      !["category", "field"].includes(String(item.kind)) ||
      typeof item.category !== "string" || !item.category.trim() ||
      typeof item.categoryPath !== "string" || !item.categoryPath.trim() ||
      !nullableString(item.technicalFamily) ||
      !nullableString(item.field) || !nullableString(item.label) ||
      !nullableString(item.dataType) || !nullableString(item.unit) ||
      !nullableString(item.operators) || !nullableString(item.allowedValues) ||
      !Number.isSafeInteger(item.productCount) || (item.productCount as number) < 0 ||
      !Number.isSafeInteger(item.populatedCount) || (item.populatedCount as number) < 0 ||
      (item.populatedCount as number) > (item.productCount as number) ||
      (item.kind === "category" &&
        [item.field, item.label, item.dataType, item.unit, item.operators, item.allowedValues]
          .some((value) => value !== null)) ||
      (item.kind === "field" &&
        (typeof item.field !== "string" ||
          !/^[a-z][a-z0-9_]{1,63}$/.test(item.field) ||
          typeof item.label !== "string" ||
          !["text", "number", "boolean", "single_select", "multi_select", "range"]
            .includes(String(item.dataType)) ||
          typeof item.operators !== "string" || !item.operators.trim()))
    ) throw new Error("invalid inventory schema inspection");
  }
}

function validatePreparedTask(result: AgentToolResultEnvelope, args: JsonObject): void {
  if (result.status !== "success" || result.resultCount !== 1 || result.hasMore) {
    throw new Error("invalid prepared task");
  }
  const item = result.items[0];
  if (
    typeof item.approvalId !== "string" || !validUuid(item.approvalId) ||
    item.action !== "create_task" || item.state !== "pending" ||
    item.title !== args.title || item.description !== args.description ||
    item.priority !== args.priority || item.dueAt !== args.dueAt ||
    item.assigneeMode !== args.assigneeMode ||
    typeof item.assigneeName !== "string" || !item.assigneeName.trim() ||
    typeof item.expiresAt !== "string" || !isoInstant(item.expiresAt) ||
    Date.parse(item.expiresAt) <= Date.now()
  ) throw new Error("invalid prepared task");
}

function validateInventoryRisks(result: AgentToolResultEnvelope, args: JsonObject): void {
  for (const item of result.items) {
    if (
      typeof item.name !== "string" || !item.name.trim() ||
      !nullableString(item.sku) || !nullableString(item.category) ||
      !Number.isSafeInteger(item.stock) || !Number.isSafeInteger(item.minimumStock) ||
      (item.minimumStock as number) < 0 ||
      !["low_stock", "out_of_stock"].includes(String(item.risk)) ||
      (item.risk === "out_of_stock" && (item.stock as number) > 0) ||
      (item.risk === "low_stock" &&
        ((item.stock as number) <= 0 || (item.stock as number) > (item.minimumStock as number))) ||
      (args.risk !== "any" && item.risk !== args.risk) ||
      typeof item.isSet !== "boolean" || !nullableTimestamp(item.updatedAt)
    ) throw new Error("invalid inventory risk");
  }
}

function validateRecentExpenses(result: AgentToolResultEnvelope, args: JsonObject): void {
  for (const item of result.items) {
    if (
      typeof item.expenseNumber !== "string" || !item.expenseNumber.trim() ||
      !nullableString(item.category) || !temporalString(item.issueDate) ||
      !nullableTemporal(item.dueDate) ||
      !["draft", "posted", "void"].includes(String(item.postingStatus)) ||
      !["pending", "scheduled", "partial", "paid", "void"].includes(
        String(item.paymentStatus),
      ) ||
      !["pending", "approved", "rejected"].includes(String(item.approvalStatus)) ||
      typeof item.currency !== "string" || !item.currency.trim() ||
      !finiteNumber(item.totalAmount) || !finiteNumber(item.amountPaid) ||
      !finiteNumber(item.balance) ||
      (args.postingStatus !== "any" && item.postingStatus !== args.postingStatus) ||
      (args.paymentStatus !== "any" && item.paymentStatus !== args.paymentStatus) ||
      (args.approvalStatus !== "any" && item.approvalStatus !== args.approvalStatus)
    ) throw new Error("invalid recent expense");
  }
}

function validateCashAndReceivablesEnvelope(
  value: unknown,
  authority: AgentAuthority,
  args: JsonObject,
): AgentToolResultEnvelope {
  const itemFields = [
    "kind",
    "asOfDate",
    "horizon",
    "cashSourceStatus",
    "bookLiquidFundsBalance",
    "cashAccountCount",
    "receivablesSourceStatus",
    "receivablesTotal",
    "overdueReceivables",
    "dueInHorizonReceivables",
    "noDueDateReceivables",
    "openInvoiceCount",
    "overdueInvoiceCount",
  ] as const;
  const receivableFields = [
    "kind",
    "entityId",
    "invoiceNumber",
    "balance",
    "dueDate",
    "daysOverdue",
    "timing",
  ] as const;
  const requestedLimit = args.limit as number;
  const envelope = validateEnvelopeBase(value, authority, requestedLimit + 1);
  if (envelope.status !== "success" || envelope.items.length < 1) {
    throw new Error("invalid cash analysis");
  }
  const items = envelope.items.map((item, index) => {
    const fields = index === 0 ? itemFields : receivableFields;
    if (!isRecord(item) || !hasExactKeys(item, fields)) throw new Error("invalid cash item");
    const projected = Object.freeze({ ...item }) as JsonObject;
    if (index === 0) validateCashSummary(projected, args);
    else validateReceivable(projected);
    return projected;
  });
  const summary = items[0];
  const receivables = items.slice(1);
  const sourceStatus = summary.receivablesSourceStatus;
  const openInvoiceCount = summary.openInvoiceCount;
  if (
    (sourceStatus === "success" &&
      (!Number.isSafeInteger(openInvoiceCount) || (openInvoiceCount as number) < 1)) ||
    ((sourceStatus === "verifiedEmpty" || sourceStatus === "unavailable") &&
      receivables.length !== 0) ||
    (sourceStatus === "verifiedEmpty" && openInvoiceCount !== 0) ||
    (sourceStatus === "unavailable" && openInvoiceCount !== null) ||
    (sourceStatus === "success" &&
      (receivables.length !== Math.min(openInvoiceCount as number, requestedLimit) ||
        envelope.hasMore !== ((openInvoiceCount as number) > requestedLimit))) ||
    (sourceStatus !== "success" && envelope.hasMore)
  ) throw new Error("inconsistent receivables projection");
  return Object.freeze({ ...envelope, items });
}

function validateCashSummary(item: JsonObject, args: JsonObject): void {
  if (
    item.kind !== "summary" || !dateString(item.asOfDate) || item.horizon !== args.horizon ||
    !sourceStatus(item.cashSourceStatus) || !sourceStatus(item.receivablesSourceStatus)
  ) throw new Error("invalid cash summary");
  validateSourceMetrics(
    item.cashSourceStatus,
    [item.bookLiquidFundsBalance],
    [item.cashAccountCount],
  );
  if (
    (item.cashSourceStatus === "success" && (item.cashAccountCount as number) < 1) ||
    (item.receivablesSourceStatus === "success" &&
      ((item.openInvoiceCount as number) < 1 || (item.receivablesTotal as number) <= 0)) ||
    (item.receivablesSourceStatus !== "unavailable" &&
      ([
        item.receivablesTotal,
        item.overdueReceivables,
        item.dueInHorizonReceivables,
        item.noDueDateReceivables,
      ] as JsonValue[]).some((value) => (value as number) < 0)) ||
    (item.receivablesSourceStatus !== "unavailable" &&
      ((item.overdueReceivables as number) > (item.receivablesTotal as number) ||
        (item.dueInHorizonReceivables as number) > (item.receivablesTotal as number) ||
        (item.noDueDateReceivables as number) > (item.receivablesTotal as number) ||
        (item.overdueInvoiceCount as number) > (item.openInvoiceCount as number)))
  ) throw new Error("invalid successful source metrics");
  validateSourceMetrics(
    item.receivablesSourceStatus,
    [
      item.receivablesTotal,
      item.overdueReceivables,
      item.dueInHorizonReceivables,
      item.noDueDateReceivables,
    ],
    [item.openInvoiceCount, item.overdueInvoiceCount],
  );
}

function validateSourceMetrics(
  status: JsonValue,
  numbers: readonly JsonValue[],
  integers: readonly JsonValue[],
): void {
  const unavailable = status === "unavailable";
  if (
    numbers.some((value) => unavailable ? value !== null : !finiteNumber(value)) ||
    integers.some((value) =>
      unavailable ? value !== null : !Number.isSafeInteger(value) || (value as number) < 0
    )
  ) throw new Error("invalid source metrics");
  if (
    status === "verifiedEmpty" &&
    [...numbers, ...integers].some((value) => value !== 0)
  ) throw new Error("invalid verified-empty metrics");
}

function validateReceivable(item: JsonObject): void {
  if (
    item.kind !== "receivable" || typeof item.entityId !== "string" ||
    !validUuid(item.entityId) || typeof item.invoiceNumber !== "string" ||
    !item.invoiceNumber.trim() || utf8Bytes(item.invoiceNumber) > 100 ||
    !finiteNumber(item.balance) || (item.balance as number) <= 0 ||
    !nullableTemporal(item.dueDate) ||
    !["overdue", "due_today", "due_in_horizon", "later", "no_due_date"].includes(
      String(item.timing),
    ) ||
    (item.timing === "overdue"
      ? !Number.isSafeInteger(item.daysOverdue) || (item.daysOverdue as number) < 1
      : item.daysOverdue !== null)
  ) throw new Error("invalid receivable");
}

function validateConversations(result: AgentToolResultEnvelope, args: JsonObject): void {
  for (const item of result.items) {
    if (
      !["internal", "website_portal", "whatsapp", "instagram", "facebook_messenger"].includes(
        String(item.channel),
      ) || !nullableString(item.counterpartyType) ||
      !["pending", "active", "resolved", "rejected"].includes(String(item.status)) ||
      typeof item.isGroup !== "boolean" ||
      !nullableEnum(item.contextType, [
        "job",
        "invoice",
        "order",
        "purchase_invoice",
        "supplier",
        "customer",
        "product",
        "bike",
      ]) ||
      !(item.contextEntityId === null ||
        (typeof item.contextEntityId === "string" && validUuid(item.contextEntityId))) ||
      !nullableString(item.contextLabel) || !nullableTimestamp(item.lastMessageAt) ||
      !nullableEnum(item.lastMessageType, ["text", "image", "file", "system", "action_request"]) ||
      !nullableEnum(item.lastMessageDirection, ["inbound", "outbound", "system"]) ||
      !Number.isSafeInteger(item.unreadCount) || (item.unreadCount as number) < 0 ||
      typeof item.needsReply !== "boolean" ||
      (args.channel !== "any" && item.channel !== args.channel) ||
      (args.status !== "any" && item.status !== args.status) ||
      (args.contextType !== "any" && item.contextType !== args.contextType) ||
      (args.unreadOnly === true && (item.unreadCount as number) < 1) ||
      (args.needsReplyOnly === true && item.needsReply !== true)
    ) throw new Error("invalid conversation");
  }
}

function validateEnvelopeBase(
  value: unknown,
  authority: AgentAuthority,
  maxItems: number,
): AgentToolResultEnvelope {
  if (
    !isRecord(value) || !hasExactKeys(value, [
      "authorityTenantId",
      "asOf",
      "status",
      "items",
      "resultCount",
      "hasMore",
    ]) || value.authorityTenantId !== authority.tenantId ||
    typeof value.asOf !== "string" || !Date.parse(value.asOf) ||
    !["success", "verifiedEmpty"].includes(String(value.status)) ||
    !Array.isArray(value.items) || value.items.length > maxItems ||
    !Number.isSafeInteger(value.resultCount) || value.resultCount !== value.items.length ||
    typeof value.hasMore !== "boolean" ||
    (value.status === "verifiedEmpty" &&
      (value.items.length !== 0 || value.resultCount !== 0 || value.hasMore)) ||
    (value.status === "success" && value.items.length === 0)
  ) throw new Error("invalid tool envelope");
  return Object.freeze({
    authorityTenantId: authority.tenantId,
    asOf: value.asOf,
    status: value.status,
    items: value.items as JsonObject[],
    resultCount: value.resultCount as number,
    hasMore: value.hasMore,
  }) as AgentToolResultEnvelope;
}

function nullableString(value: JsonValue): boolean {
  return value === null || typeof value === "string";
}

function nullableEnum(value: JsonValue, values: readonly string[]): boolean {
  return value === null || (typeof value === "string" && values.includes(value));
}

function finiteNumber(value: JsonValue): boolean {
  return typeof value === "number" && Number.isFinite(value);
}

function dateString(value: JsonValue): boolean {
  return typeof value === "string" && /^\d{4}-\d{2}-\d{2}$/.test(value) &&
    Boolean(Date.parse(value));
}

function temporalString(value: JsonValue): boolean {
  return typeof value === "string" && utf8Bytes(value) <= 64 && Boolean(Date.parse(value));
}

function nullableTemporal(value: JsonValue): boolean {
  return value === null || temporalString(value);
}

function nullableTimestamp(value: JsonValue): boolean {
  return value === null || (typeof value === "string" && Boolean(Date.parse(value)));
}

function sourceStatus(value: JsonValue): boolean {
  return ["success", "verifiedEmpty", "unavailable"].includes(String(value));
}

function utf8Bytes(value: string): number {
  return new TextEncoder().encode(value).byteLength;
}

function validUuid(value: string): boolean {
  return /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i
    .test(value);
}

function modelVisibleResult(result: AgentToolResultEnvelope): JsonObject {
  return {
    asOf: result.asOf,
    status: result.status,
    items: result.items.map((item) => {
      const {
        entityId: _serverOwnedEntityId,
        approvalId: _serverOwnedApprovalId,
        action: _serverOwnedApprovalAction,
        contextEntityId: _serverOwnedContextEntityId,
        contextLabel: _potentiallyIdentifyingContextLabel,
        counterpartyType: _potentiallyIdentifyingCounterpartyType,
        ...visible
      } = item;
      return visible;
    }),
    resultCount: result.resultCount,
    hasMore: result.hasMore,
  };
}

function isoInstant(value: string): boolean {
  return /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,6})?(?:Z|[+-]\d{2}:\d{2})$/.test(value) &&
    Number.isFinite(Date.parse(value));
}

function unavailable(tenantId: string, failureCode: string): AgentToolExecution {
  const result: AgentToolResultEnvelope = {
    authorityTenantId: tenantId,
    asOf: new Date().toISOString(),
    status: "unavailable",
    items: [],
    resultCount: 0,
    hasMore: false,
  };
  const outputText = JSON.stringify({
    status: "unavailable",
    message: "La fuente autorizada no estuvo disponible.",
  });
  return {
    result,
    outputText,
    outputBytes: new TextEncoder().encode(outputText).byteLength,
    succeeded: false,
    failureCode,
  };
}

function capabilityGapExecution(
  argumentsValue: JsonObject,
  tenantId: string,
): AgentToolExecution {
  const exactKeys = ["domain", "operation", "reason", "alternative", "field"];
  const domains = [
    "inventory",
    "workshop",
    "sales",
    "purchases",
    "accounting",
    "customers",
    "suppliers",
    "tasks",
    "communications",
    "files",
    "public_web",
    "other",
  ];
  const operations = [
    "read",
    "filter",
    "compare",
    "aggregate",
    "draft",
    "mutate",
    "navigate",
    "research",
    "other",
  ];
  const reasons = [
    "missing_tool",
    "unsupported_filter",
    "missing_structured_data",
    "permission_required",
    "ambiguous_request",
    "source_unavailable",
  ];
  const alternatives = [
    "none",
    "broader_search",
    "exact_match",
    "ask_clarification",
    "public_research",
  ];
  const field = argumentsValue.field;
  if (
    !hasExactKeys(argumentsValue, exactKeys) ||
    !domains.includes(String(argumentsValue.domain)) ||
    !operations.includes(String(argumentsValue.operation)) ||
    !reasons.includes(String(argumentsValue.reason)) ||
    !alternatives.includes(String(argumentsValue.alternative)) ||
    !(field === null ||
      (typeof field === "string" && /^[a-z][a-z0-9_]{1,63}$/.test(field))) ||
    (argumentsValue.reason === "missing_structured_data" ? field === null : field !== null)
  ) {
    return unavailable(tenantId, "tool_arguments_invalid");
  }
  const item = Object.freeze({ ...argumentsValue });
  const result: AgentToolResultEnvelope = Object.freeze({
    authorityTenantId: tenantId,
    asOf: new Date().toISOString(),
    status: "success",
    items: Object.freeze([item]),
    resultCount: 1,
    hasMore: false,
  });
  const outputText = JSON.stringify({
    status: "accepted",
    message: "El servidor redactará una respuesta honesta sobre esta limitación.",
  });
  return {
    result,
    outputText,
    outputBytes: new TextEncoder().encode(outputText).byteLength,
    succeeded: true,
  };
}

function isRecord(value: unknown): value is Record<string, JsonValue> {
  return Boolean(value) && typeof value === "object" && !Array.isArray(value);
}

function hasExactKeys(value: Record<string, unknown>, expected: readonly string[]): boolean {
  const actual = Object.keys(value).sort();
  return JSON.stringify(actual) === JSON.stringify([...expected].sort());
}

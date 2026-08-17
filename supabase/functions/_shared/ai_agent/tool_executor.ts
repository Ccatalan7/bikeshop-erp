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
    rpc: "assistant_inspect_inventory_schema_v2",
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
    rpc: "assistant_search_inventory_v7",
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
      "matchedCount",
      "trackedCount",
      "totalStock",
      "inventoryRetailValue",
      "averagePrice",
      "minimumPrice",
      "maximumPrice",
    ],
  },
  rank_purchase_candidates: {
    rpc: "assistant_rank_purchase_candidates_v1",
    parameters: purchaseRankingParameters,
    fields: [
      "entityId",
      "rank",
      "rankingProfile",
      "rankingVersion",
      "rankingScore",
      "productName",
      "productSku",
      "brand",
      "category",
      "supplierName",
      "supplierWebsite",
      "supplierLocation",
      "isConfirmedLocal",
      "supplierAvailability",
      "currency",
      "latestBaseUnitCostNet",
      "latestAllocatedFreightNet",
      "latestLandedUnitCostNet",
      "catalogSalePriceGross",
      "catalogSalePriceNet",
      "projectedUnitGrossProfit",
      "projectedGrossMarginRatio",
      "purchaseCount",
      "purchasedUnits",
      "lastPurchaseAt",
      "evidenceAgeDays",
      "evidenceQuality",
      "freightEvidence",
      "economyScore",
      "historyScore",
      "recencyScore",
      "stabilityScore",
      "evidenceScore",
    ],
  },
  build_purchase_scenarios: {
    rpc: "assistant_build_purchase_scenarios_v1",
    parameters: purchaseScenarioParameters,
    fields: [
      "scenarioKey",
      "kind",
      "label",
      "coverageLineCount",
      "externalCoverageLineCount",
      "totalLineCount",
      "externalLineCount",
      "complete",
      "supplierCount",
      "historicalSubtotals",
      "supplierAvailability",
      "freightAssumption",
      "lines",
      "explanationCodes",
    ],
    maxItems: 3,
  },
  prepare_supply_request: {
    rpc: "assistant_prepare_supply_request_v1",
    parameters: supplyRequestParameters,
    fields: [
      "entityId",
      "lineRef",
      "description",
      "productName",
      "productSku",
      "identityState",
      "quantity",
      "unit",
      "technicalPredicates",
      "preference",
      "clarification",
      "clarificationRequired",
      "clarificationPrompts",
      "profile",
    ],
    maxItems: 8,
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
    rpc: "assistant_query_workshop_jobs_v3",
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
      "invoiceNumber",
      "bikeSummary",
      "bikeCount",
    ],
  },
  get_workshop_job_context: {
    rpc: "assistant_get_workshop_job_context_v1",
    parameters: (args: JsonObject) => ({ p_job_id: args.jobId }),
    fields: [
      "entityId",
      "jobBikeId",
      "jobNumber",
      "customerName",
      "bikeLabel",
      "jobType",
      "jobStatus",
      "jobUpdatedAt",
      "invoiceId",
      "invoiceNumber",
      "invoiceStatus",
      "diagnosisUpdatedAt",
      "canUpdateDiagnosis",
      "canAddWorkshopItem",
    ],
    maxItems: 10,
  },
  inspect_diagnosis_schema: {
    rpc: "assistant_inspect_diagnosis_schema_v1",
    parameters: (args: JsonObject) => ({ p_section: args.section }),
    fields: [
      "section",
      "field",
      "label",
      "valueType",
      "storedUnit",
      "inputUnits",
      "allowedValues",
      "minimumValue",
      "maximumValue",
    ],
    maxItems: 40,
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
    rpc: "assistant_analyze_cash_and_receivables_v2",
    parameters: (args: JsonObject) => ({
      p_horizon: args.horizon,
      p_limit: args.limit,
    }),
    fields: [],
    maxItems: 9,
  },
  analyze_sales_period: {
    rpc: "assistant_analyze_sales_period_v1",
    parameters: (args: JsonObject) => ({
      p_basis: args.basis,
      p_range_mode: args.rangeMode,
      p_relative_period: args.relativePeriod,
      p_start_date: args.startDate,
      p_end_date: args.endDate,
      p_invoice_status: args.invoiceStatus,
    }),
    fields: [
      "basis",
      "startDate",
      "endDate",
      "invoiceStatus",
      "invoiceCount",
      "eventCount",
      "totalAmount",
      "averagePerInvoice",
      "highestInvoiceId",
      "highestInvoiceNumber",
      "highestInvoiceCustomerName",
      "highestInvoiceTotal",
      "highestPeriodAmount",
    ],
    maxItems: 1,
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
  prepare_diagnosis_update: {
    rpc: "assistant_prepare_diagnosis_update_v1",
    parameters: (args: JsonObject, context?: AgentToolExecutionContext) => {
      if (!context) throw new InvalidToolArguments();
      return {
        p_job_id: args.jobId,
        p_job_bike_id: args.jobBikeId,
        p_field: args.field,
        p_number_value: args.numberValue,
        p_text_value: args.textValue,
        p_unit: args.unit,
        p_expected_updated_at: args.expectedUpdatedAt,
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
      "jobId",
      "jobBikeId",
      "jobNumber",
      "bikeLabel",
      "field",
      "fieldLabel",
      "previousValue",
      "newValue",
      "expiresAt",
    ],
    maxItems: 1,
  },
  prepare_workshop_item: {
    rpc: "assistant_prepare_workshop_item_v1",
    parameters: (args: JsonObject, context?: AgentToolExecutionContext) => {
      if (!context) throw new InvalidToolArguments();
      return {
        p_job_id: args.jobId,
        p_job_bike_id: args.jobBikeId,
        p_catalog_item_id: args.catalogItemId,
        p_quantity: args.quantity,
        p_notes: args.notes,
        p_expected_job_updated_at: args.expectedJobUpdatedAt,
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
      "jobId",
      "jobBikeId",
      "jobNumber",
      "bikeLabel",
      "catalogItemId",
      "itemName",
      "itemType",
      "quantity",
      "unitPrice",
      "lineTotal",
      "invoiceNumber",
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
  entityReferences?: readonly AgentToolEntityReference[];
  externalAccounting?: PublicResearchAccounting;
  publicResearchCompleteness?: PublicResearchEvidenceCompleteness;
}

export interface AgentToolEntityReference {
  ref: string;
  kind: "workshop_job" | "catalog_item";
  entityId: string;
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
          : call.name === "build_purchase_scenarios"
          ? validatePurchaseScenarioEnvelope(value, authority, call.arguments)
          : call.name === "prepare_supply_request"
          ? validateSupplyRequestEnvelope(value, authority, {
            items: parameters.p_items,
            profile: parameters.p_profile,
          }, call.arguments)
          : validateEnvelope(value, authority, contract.fields, maxItems);
        if (call.name === "get_business_snapshot") validateBusinessSnapshot(result, call.arguments);
        validateSpecializedResult(call.name, result, call.arguments);
        const projection = modelVisibleResult(call.name, result);
        const outputText = JSON.stringify(projection.value);
        const outputBytes = new TextEncoder().encode(outputText).byteLength;
        if (outputBytes > MAX_TOOL_OUTPUT_BYTES) {
          return unavailable(authority.tenantId, "tool_output_too_large");
        }
        return {
          result,
          outputText,
          outputBytes,
          succeeded: true,
          entityReferences: projection.entityReferences,
        };
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
    const visibleResult = modelVisibleResult("research_public_web", result);
    const outputText = JSON.stringify({
      ...visibleResult.value,
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
      "sort",
      "limit",
      "selectionMode",
      "technicalPredicates",
      "operationalPredicates",
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
    !["answer", "open_list"].includes(String(args.presentation)) ||
    !isRecord(args.sort) ||
    !hasExactKeys(args.sort, ["field", "direction"]) ||
    !["relevance", "name", "stock", "minimum_stock", "price"].includes(
      String(args.sort.field),
    ) ||
    !["asc", "desc"].includes(String(args.sort.direction)) ||
    (args.sort.field === "relevance" && args.sort.direction !== "desc") ||
    !boundedInteger(args.limit, 1, 10) ||
    !["all_matches", "top_n"].includes(String(args.selectionMode))
  ) throw new InvalidToolArguments();
  const technicalPredicates = normalizedInventoryTechnicalPredicates(
    args.technicalPredicates,
  );
  const operationalPredicates = normalizedInventoryOperationalPredicates(
    args.operationalPredicates,
  );
  return {
    p_query: typeof args.query === "string" ? args.query.trim() : null,
    p_category: typeof args.category === "string" ? args.category.trim() : null,
    p_availability: args.availability,
    p_technical_predicates: technicalPredicates,
    p_operational_predicates: operationalPredicates,
    p_sort_field: args.sort.field,
    p_sort_direction: args.sort.direction,
    p_limit: args.limit,
    p_selection_mode: args.selectionMode,
  };
}

function purchaseRankingParameters(args: JsonObject): JsonObject {
  if (
    !hasExactKeys(args, ["catalogItemId", "query", "profile", "limit"]) ||
    !(args.catalogItemId === null || validUuidValue(args.catalogItemId)) ||
    !(args.query === null ||
      (typeof args.query === "string" && args.query.trim() &&
        utf8Bytes(args.query.trim()) <= 240)) ||
    ((args.catalogItemId === null) === (args.query === null)) ||
    !["balanced", "profitability", "urgent_local"].includes(
      String(args.profile),
    ) ||
    !boundedInteger(args.limit, 1, 10)
  ) throw new InvalidToolArguments();
  return {
    p_query: typeof args.query === "string" ? args.query.trim() : null,
    p_product_id: args.catalogItemId,
    p_profile: args.profile,
    p_limit: args.limit,
  };
}

function purchaseScenarioParameters(args: JsonObject): JsonObject {
  if (
    !hasExactKeys(args, ["items", "profile", "maxSuppliers", "limit"]) ||
    !Array.isArray(args.items) || args.items.length < 2 || args.items.length > 8 ||
    !["balanced", "profitability", "urgent_local"].includes(
      String(args.profile),
    ) ||
    !boundedInteger(args.maxSuppliers, 1, 3) ||
    !boundedInteger(args.limit, 1, 3)
  ) throw new InvalidToolArguments();

  const lineReferences = new Set<string>();
  const items = args.items.map((item) => {
    if (
      !isRecord(item) ||
      !hasExactKeys(item, ["lineRef", "productId", "quantity", "sourcingMode"]) ||
      typeof item.lineRef !== "string" ||
      !/^line-[1-8]$/.test(item.lineRef) ||
      lineReferences.has(item.lineRef) ||
      !validUuidValue(item.productId) ||
      !finiteNumber(item.quantity) || (item.quantity as number) < 0.001 ||
      (item.quantity as number) > 999999 ||
      !["stock_first", "external_only"].includes(String(item.sourcingMode))
    ) throw new InvalidToolArguments();
    lineReferences.add(item.lineRef);
    return {
      lineRef: item.lineRef,
      productId: item.productId,
      quantity: item.quantity,
      sourcingMode: item.sourcingMode,
    };
  });

  return {
    p_items: items,
    p_profile: args.profile,
    p_max_suppliers: args.maxSuppliers,
    p_limit: args.limit,
  };
}

function supplyRequestParameters(args: JsonObject): JsonObject {
  if (
    !hasExactKeys(args, ["items", "profile"]) ||
    !Array.isArray(args.items) || args.items.length < 1 || args.items.length > 8 ||
    !["balanced", "profitability", "urgent_local"].includes(String(args.profile))
  ) throw new InvalidToolArguments();

  const items = args.items.map((item, index) => {
    const baseFields = [
      "description",
      "productId",
      "quantity",
      "unit",
      "technicalPredicates",
      "preference",
      "clarification",
      "clarificationRequired",
    ] as const;
    if (
      !isRecord(item) ||
      (!hasExactKeys(item, baseFields) &&
        !hasExactKeys(item, [...baseFields, "clarificationPrompts"])) ||
      !(item.productId === null || validUuidValue(item.productId)) ||
      typeof item.description !== "string" || !item.description.trim() ||
      utf8Bytes(item.description.trim()) > 2000 ||
      !finiteNumber(item.quantity) || (item.quantity as number) < 0.001 ||
      (item.quantity as number) > 999999 ||
      typeof item.unit !== "string" || !item.unit.trim() ||
      utf8Bytes(item.unit.trim()) > 32 ||
      !(item.preference === null ||
        (typeof item.preference === "string" && item.preference.trim() &&
          utf8Bytes(item.preference.trim()) <= 240)) ||
      !(item.clarification === null ||
        (typeof item.clarification === "string" && item.clarification.trim() &&
          utf8Bytes(item.clarification.trim()) <= 500)) ||
      typeof item.clarificationRequired !== "boolean" ||
      (item.clarificationRequired === true && item.clarification === null) ||
      (item.clarificationRequired === true && item.productId !== null) ||
      ("clarificationPrompts" in item &&
        !validSupplyClarificationPrompts(
          item.clarificationPrompts,
          item.clarificationRequired === true,
        ))
    ) throw new InvalidToolArguments();

    return {
      lineRef: `line-${index + 1}`,
      description: item.description.trim(),
      productId: item.productId,
      quantity: item.quantity,
      unit: item.unit.trim(),
      technicalPredicates: normalizedInventoryTechnicalPredicates(
        item.technicalPredicates,
      ),
      preference: typeof item.preference === "string" ? item.preference.trim() : null,
      clarification: typeof item.clarification === "string" ? item.clarification.trim() : null,
      clarificationRequired: item.clarificationRequired,
    };
  });

  return { p_items: items, p_profile: args.profile };
}

function validSupplyClarificationPrompts(
  value: JsonValue,
  required: boolean,
): boolean {
  if (!Array.isArray(value) || value.length > 3) return false;
  if (!required) return value.length === 0;
  if (value.length < 1) return false;
  const ids = new Set<string>();
  for (const prompt of value) {
    if (
      !isRecord(prompt) ||
      !hasExactKeys(prompt, [
        "id",
        "question",
        "inputKind",
        "options",
        "unit",
        "allowUnknown",
      ]) ||
      typeof prompt.id !== "string" ||
      !/^[a-z][a-z0-9_]{1,31}$/.test(prompt.id) || ids.has(prompt.id) ||
      typeof prompt.question !== "string" || !prompt.question.trim() ||
      utf8Bytes(prompt.question.trim()) > 320 ||
      !["single_choice", "text", "number"].includes(String(prompt.inputKind)) ||
      !Array.isArray(prompt.options) || prompt.options.length > 5 ||
      typeof prompt.allowUnknown !== "boolean" ||
      !(prompt.unit === null ||
        (typeof prompt.unit === "string" && prompt.unit.trim() &&
          utf8Bytes(prompt.unit.trim()) <= 32))
    ) return false;
    ids.add(prompt.id);
    if (prompt.inputKind === "single_choice") {
      if (prompt.options.length < 2 || prompt.unit !== null) return false;
      const values = new Set<string>();
      for (const option of prompt.options) {
        if (
          !isRecord(option) || !hasExactKeys(option, ["value", "label"]) ||
          typeof option.value !== "string" ||
          !/^[a-z0-9][a-z0-9_-]{0,63}$/.test(option.value) ||
          values.has(option.value) || typeof option.label !== "string" ||
          !option.label.trim() || utf8Bytes(option.label.trim()) > 160
        ) return false;
        values.add(option.value);
      }
    } else if (prompt.options.length !== 0) {
      return false;
    } else if (prompt.inputKind !== "number" && prompt.unit !== null) {
      return false;
    }
  }
  return true;
}

function normalizedSupplyClarificationPrompts(value: JsonValue): JsonObject[] {
  if (!Array.isArray(value)) throw new InvalidToolArguments();
  return value.map((prompt) => {
    if (!isRecord(prompt) || !Array.isArray(prompt.options)) {
      throw new InvalidToolArguments();
    }
    return {
      id: String(prompt.id),
      question: String(prompt.question).trim(),
      inputKind: String(prompt.inputKind),
      options: prompt.options.map((option) => {
        if (!isRecord(option)) throw new InvalidToolArguments();
        return {
          value: String(option.value),
          label: String(option.label).trim(),
        };
      }),
      unit: typeof prompt.unit === "string" ? prompt.unit.trim() : null,
      allowUnknown: prompt.allowUnknown as boolean,
    };
  });
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

function normalizedInventoryOperationalPredicates(value: JsonValue): JsonValue[] {
  if (!Array.isArray(value) || value.length > 6) throw new InvalidToolArguments();
  const fields = new Set<string>();
  return value.map((predicate) => {
    if (
      !isRecord(predicate) ||
      !hasExactKeys(predicate, ["field", "operator", "values"]) ||
      typeof predicate.field !== "string" ||
      !["stock", "minimum_stock", "price"].includes(predicate.field) ||
      fields.has(predicate.field) ||
      typeof predicate.operator !== "string" ||
      !["eq", "neq", "lt", "lte", "gt", "gte", "between", "in"]
        .includes(predicate.operator) ||
      !Array.isArray(predicate.values) || predicate.values.length < 1 ||
      predicate.values.length > 10 ||
      (predicate.operator === "between" && predicate.values.length !== 2) ||
      (predicate.operator !== "between" && predicate.operator !== "in" &&
        predicate.values.length !== 1) ||
      predicate.values.some((item) => typeof item !== "number" || !Number.isFinite(item))
    ) throw new InvalidToolArguments();
    fields.add(predicate.field);
    return {
      field: predicate.field,
      operator: predicate.operator,
      values: [...predicate.values],
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
  if (toolName === "prepare_diagnosis_update") {
    if (
      !validUuidValue(parameters.p_job_id) ||
      !validUuidValue(parameters.p_job_bike_id) ||
      typeof parameters.p_field !== "string" ||
      !/^[a-z][a-z0-9_]*\.[a-z][a-z0-9_]*$/.test(parameters.p_field) ||
      ((typeof parameters.p_number_value === "number") ===
        (typeof parameters.p_text_value === "string")) ||
      !(parameters.p_number_value === null || finiteNumber(parameters.p_number_value)) ||
      !(parameters.p_text_value === null ||
        (typeof parameters.p_text_value === "string" && parameters.p_text_value.trim() &&
          utf8Bytes(parameters.p_text_value) <= 1000)) ||
      !["none", "display_fraction", "percent", "millimeter"].includes(
        String(parameters.p_unit),
      ) ||
      !(parameters.p_expected_updated_at === null ||
        (typeof parameters.p_expected_updated_at === "string" &&
          isoInstant(parameters.p_expected_updated_at))) ||
      !validPreparationBinding(parameters)
    ) throw new InvalidToolArguments();
    return;
  }
  if (toolName === "prepare_workshop_item") {
    if (
      !validUuidValue(parameters.p_job_id) ||
      !(parameters.p_job_bike_id === null || validUuidValue(parameters.p_job_bike_id)) ||
      !validUuidValue(parameters.p_catalog_item_id) ||
      !finiteNumber(parameters.p_quantity) ||
      (parameters.p_quantity as number) < 0.01 ||
      (parameters.p_quantity as number) > 999 ||
      !(parameters.p_notes === null ||
        (typeof parameters.p_notes === "string" && parameters.p_notes.trim() &&
          utf8Bytes(parameters.p_notes) <= 500)) ||
      typeof parameters.p_expected_job_updated_at !== "string" ||
      !isoInstant(parameters.p_expected_job_updated_at) ||
      !validPreparationBinding(parameters)
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
  if (toolName === "analyze_sales_period") {
    const relativePeriods = [
      "today",
      "yesterday",
      "this_week",
      "last_week",
      "last_7_days",
      "this_month",
      "last_month",
      "this_year",
      "last_year",
    ];
    if (
      !["issued", "collected"].includes(String(parameters.p_basis)) ||
      !["relative", "absolute"].includes(String(parameters.p_range_mode)) ||
      (parameters.p_range_mode === "relative" &&
        (!relativePeriods.includes(String(parameters.p_relative_period)) ||
          parameters.p_start_date !== null || parameters.p_end_date !== null)) ||
      (parameters.p_range_mode === "absolute" &&
        (parameters.p_relative_period !== null ||
          typeof parameters.p_start_date !== "string" ||
          typeof parameters.p_end_date !== "string" ||
          !isoDate(parameters.p_start_date) || !isoDate(parameters.p_end_date) ||
          parameters.p_start_date > parameters.p_end_date)) ||
      !["any", "open", "paid", "cancelled"].includes(
        String(parameters.p_invoice_status),
      )
    ) throw new InvalidToolArguments();
    return;
  }
  if (toolName === "get_workshop_job_context") {
    if (!validUuidValue(parameters.p_job_id)) throw new InvalidToolArguments();
    return;
  }
  if (toolName === "rank_purchase_candidates") {
    if (
      !(parameters.p_query === null ||
        (typeof parameters.p_query === "string" && parameters.p_query.trim() &&
          utf8Bytes(parameters.p_query) <= 240)) ||
      !(parameters.p_product_id === null || validUuidValue(parameters.p_product_id)) ||
      ((parameters.p_query === null) === (parameters.p_product_id === null)) ||
      !["balanced", "profitability", "urgent_local"].includes(
        String(parameters.p_profile),
      ) ||
      !boundedInteger(parameters.p_limit, 1, 10)
    ) throw new InvalidToolArguments();
    return;
  }
  if (toolName === "build_purchase_scenarios") {
    if (
      !Array.isArray(parameters.p_items) ||
      parameters.p_items.length < 2 || parameters.p_items.length > 8 ||
      !["balanced", "profitability", "urgent_local"].includes(
        String(parameters.p_profile),
      ) ||
      !boundedInteger(parameters.p_max_suppliers, 1, 3) ||
      !boundedInteger(parameters.p_limit, 1, 3)
    ) throw new InvalidToolArguments();
    for (const item of parameters.p_items) {
      if (
        !isRecord(item) ||
        !hasExactKeys(item, ["lineRef", "productId", "quantity", "sourcingMode"]) ||
        typeof item.lineRef !== "string" || !/^line-[1-8]$/.test(item.lineRef) ||
        !validUuidValue(item.productId) || !finiteNumber(item.quantity) ||
        (item.quantity as number) < 0.001 || (item.quantity as number) > 999999 ||
        !["stock_first", "external_only"].includes(String(item.sourcingMode))
      ) throw new InvalidToolArguments();
    }
    return;
  }
  if (toolName === "prepare_supply_request") {
    if (
      !Array.isArray(parameters.p_items) ||
      parameters.p_items.length < 1 || parameters.p_items.length > 8 ||
      !["balanced", "profitability", "urgent_local"].includes(
        String(parameters.p_profile),
      )
    ) throw new InvalidToolArguments();
    return;
  }
  if (toolName === "inspect_diagnosis_schema") {
    if (
      ![
        "any",
        "suspension",
        "drivetrain",
        "front_brake",
        "rear_brake",
        "front_wheel",
        "rear_wheel",
        "bottom_bracket",
        "cockpit",
      ].includes(String(parameters.p_section))
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
    toolName === "search_inventory" &&
    !Array.isArray(parameters.p_operational_predicates)
  ) {
    throw new InvalidToolArguments();
  }
  if (
    toolName === "search_inventory" &&
    (!["relevance", "name", "stock", "minimum_stock", "price"].includes(
      String(parameters.p_sort_field),
    ) ||
      !["asc", "desc"].includes(String(parameters.p_sort_direction)) ||
      (parameters.p_sort_field === "relevance" &&
        parameters.p_sort_direction !== "desc") ||
      !boundedInteger(parameters.p_limit, 1, 10) ||
      !["all_matches", "top_n"].includes(String(parameters.p_selection_mode)))
  ) throw new InvalidToolArguments();
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

function validPreparationBinding(parameters: JsonObject): boolean {
  return validUuidValue(parameters.p_run_id) &&
    boundedInteger(parameters.p_provider_attempt_no, 1, 42) &&
    typeof parameters.p_provider_call_hash === "string" &&
    /^[0-9a-f]{64}$/.test(parameters.p_provider_call_hash) &&
    typeof parameters.p_arguments_hash === "string" &&
    /^[0-9a-f]{64}$/.test(parameters.p_arguments_hash);
}

function validUuidValue(value: JsonValue): value is string {
  return typeof value === "string" && validUuid(value);
}

function isoDate(value: string): boolean {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(value)) return false;
  const parsed = new Date(`${value}T00:00:00Z`);
  return Number.isFinite(parsed.getTime()) && parsed.toISOString().slice(0, 10) === value;
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

function validatePurchaseScenarioEnvelope(
  value: unknown,
  authority: AgentAuthority,
  args: JsonObject,
): AgentToolResultEnvelope {
  const requestedLimit = args.limit as number;
  const envelope = validateEnvelopeBase(value, authority, requestedLimit);
  if (!Array.isArray(args.items)) throw new Error("invalid purchase scenarios");
  const requestedByRef = new Map<string, JsonObject>();
  for (const item of args.items) {
    if (!isRecord(item) || typeof item.lineRef !== "string") {
      throw new Error("invalid purchase scenarios");
    }
    requestedByRef.set(item.lineRef, item);
  }

  const scenarioFields = [
    "scenarioKey",
    "kind",
    "label",
    "coverageLineCount",
    "externalCoverageLineCount",
    "totalLineCount",
    "externalLineCount",
    "complete",
    "supplierCount",
    "historicalSubtotals",
    "supplierAvailability",
    "freightAssumption",
    "lines",
    "explanationCodes",
  ] as const;
  const lineFields = new Set([
    "lineRef",
    "productName",
    "productSku",
    "requestedQuantity",
    "availableToPromise",
    "sourcing",
    "covered",
    "supplierName",
    "isConfirmedLocal",
    "supplierAvailability",
    "currency",
    "latestLandedUnitCostNet",
    "projectedGrossMarginRatio",
    "purchaseCount",
    "evidenceAgeDays",
    "evidenceQuality",
    "freightEvidence",
  ]);
  const projectedItems = envelope.items.map((scenario) => {
    if (
      !isRecord(scenario) || !hasExactKeys(scenario, scenarioFields) ||
      typeof scenario.scenarioKey !== "string" ||
      !scenario.scenarioKey.trim() || utf8Bytes(scenario.scenarioKey) > 128 ||
      !["internal_stock", "recommended", "consolidated", "lowest_historical_cost"]
        .includes(String(scenario.kind)) ||
      typeof scenario.label !== "string" || !scenario.label.trim() ||
      utf8Bytes(scenario.label) > 120 ||
      !Number.isSafeInteger(scenario.coverageLineCount) ||
      !Number.isSafeInteger(scenario.externalCoverageLineCount) ||
      !Number.isSafeInteger(scenario.totalLineCount) ||
      !Number.isSafeInteger(scenario.externalLineCount) ||
      typeof scenario.complete !== "boolean" ||
      !Number.isSafeInteger(scenario.supplierCount) ||
      (scenario.supplierCount as number) < 0 ||
      (scenario.supplierCount as number) > (args.maxSuppliers as number) ||
      !["not_applicable", "historical_only_unverified"].includes(
        String(scenario.supplierAvailability),
      ) ||
      ![
        "not_applicable",
        "sum_historical_landed_line_costs_no_consolidation_saving",
      ].includes(String(scenario.freightAssumption)) ||
      !Array.isArray(scenario.historicalSubtotals) ||
      scenario.historicalSubtotals.length > 8 ||
      !Array.isArray(scenario.lines) ||
      scenario.lines.length !== requestedByRef.size ||
      !Array.isArray(scenario.explanationCodes) ||
      scenario.explanationCodes.length < 1 ||
      scenario.explanationCodes.length > 5
    ) throw new Error("invalid purchase scenarios");

    for (const subtotal of scenario.historicalSubtotals) {
      if (
        !isRecord(subtotal) ||
        !hasExactKeys(subtotal, ["currency", "historicalLandedSubtotalNet"]) ||
        typeof subtotal.currency !== "string" || !subtotal.currency.trim() ||
        utf8Bytes(subtotal.currency) > 8 ||
        !finiteNumber(subtotal.historicalLandedSubtotalNet) ||
        (subtotal.historicalLandedSubtotalNet as number) < 0
      ) throw new Error("invalid purchase scenario subtotal");
    }

    const seenRefs = new Set<string>();
    let covered = 0;
    let external = 0;
    let coveredExternal = 0;
    for (const line of scenario.lines) {
      if (
        !isRecord(line) ||
        Object.keys(line).some((key) => !lineFields.has(key)) ||
        typeof line.lineRef !== "string" || seenRefs.has(line.lineRef) ||
        typeof line.productName !== "string" || !line.productName.trim() ||
        !finiteNumber(line.requestedQuantity) ||
        !Number.isSafeInteger(line.availableToPromise) ||
        (line.availableToPromise as number) < 0 ||
        !["internal", "external", "uncovered"].includes(String(line.sourcing)) ||
        typeof line.covered !== "boolean"
      ) throw new Error("invalid purchase scenario line");
      const requested = requestedByRef.get(line.lineRef);
      if (
        !requested || requested.quantity !== line.requestedQuantity ||
        (line.productSku !== undefined &&
          (typeof line.productSku !== "string" || !line.productSku.trim()))
      ) throw new Error("purchase scenario line mismatch");
      seenRefs.add(line.lineRef);

      if (line.covered) covered += 1;
      if (line.sourcing !== "internal") external += 1;
      if (line.sourcing === "external") coveredExternal += 1;
      if (
        (line.sourcing === "internal" &&
          (line.covered !== true || requested.sourcingMode === "external_only")) ||
        (line.sourcing === "uncovered" && line.covered !== false) ||
        (line.sourcing === "external" &&
          (line.covered !== true || typeof line.supplierName !== "string" ||
            !line.supplierName.trim() || line.supplierAvailability !== "unverified" ||
            typeof line.currency !== "string" || !line.currency.trim() ||
            !finiteNumber(line.latestLandedUnitCostNet)))
      ) throw new Error("invalid purchase scenario sourcing");
    }

    if (
      seenRefs.size !== requestedByRef.size ||
      scenario.coverageLineCount !== covered ||
      scenario.externalLineCount !== external ||
      scenario.externalCoverageLineCount !== coveredExternal ||
      scenario.totalLineCount !== requestedByRef.size ||
      scenario.complete !== (covered === requestedByRef.size) ||
      (scenario.kind === "internal_stock" &&
        (external !== 0 || scenario.supplierCount !== 0)) ||
      scenario.explanationCodes.some((code) =>
        typeof code !== "string" || ![
          "stock_first",
          "external_only",
          "complete_external_coverage",
          "partial_external_coverage",
          "supplier_consolidation",
          "historical_cost_comparison",
          "profile_ranked",
          "historical_availability_unverified",
          "no_consolidation_freight_saving_assumed",
        ].includes(code)
      )
    ) throw new Error("invalid purchase scenario coverage");
    return Object.freeze({ ...scenario }) as JsonObject;
  });

  return Object.freeze({
    ...envelope,
    items: Object.freeze(projectedItems),
  }) as AgentToolResultEnvelope;
}

function validateSupplyRequestEnvelope(
  value: unknown,
  authority: AgentAuthority,
  args: JsonObject,
  sourceArgs: JsonObject,
): AgentToolResultEnvelope {
  const requestedItems = args.items;
  const sourceItems = sourceArgs.items;
  if (
    !Array.isArray(requestedItems) || !Array.isArray(sourceItems) ||
    requestedItems.length !== sourceItems.length
  ) throw new Error("invalid supply request draft");
  const envelope = validateEnvelopeBase(value, authority, 8);
  const fields = [
    "entityId",
    "lineRef",
    "description",
    "productName",
    "productSku",
    "identityState",
    "quantity",
    "unit",
    "technicalPredicates",
    "preference",
    "clarification",
    "clarificationRequired",
    "profile",
  ] as const;
  if (
    envelope.status !== "success" || envelope.hasMore ||
    envelope.items.length !== requestedItems.length
  ) throw new Error("invalid supply request draft");

  const projected = envelope.items.map((item, index) => {
    const requested = requestedItems[index];
    const source = sourceItems[index];
    if (
      !isRecord(requested) || !isRecord(source) || !isRecord(item) ||
      !hasExactKeys(item, fields) ||
      !(item.entityId === null ||
        (typeof item.entityId === "string" && validUuid(item.entityId))) ||
      item.entityId !== requested.productId ||
      item.lineRef !== requested.lineRef ||
      item.description !== requested.description ||
      item.quantity !== requested.quantity || item.unit !== requested.unit ||
      item.preference !== requested.preference ||
      item.clarification !== requested.clarification ||
      item.clarificationRequired !== requested.clarificationRequired ||
      item.profile !== args.profile ||
      !sameTechnicalPredicates(
        item.technicalPredicates,
        requested.technicalPredicates,
      ) ||
      !["unresolved", "confirmed"].includes(String(item.identityState)) ||
      (item.entityId === null &&
        (item.identityState !== "unresolved" || item.productName !== null ||
          item.productSku !== null)) ||
      (item.entityId !== null &&
        (item.identityState !== "confirmed" ||
          typeof item.productName !== "string" || !item.productName.trim() ||
          !(item.productSku === null ||
            (typeof item.productSku === "string" && item.productSku.trim()))))
    ) throw new Error("invalid supply request draft");
    const prompts = normalizedSupplyClarificationPrompts(
      source.clarificationPrompts ?? [],
    );
    if (
      "clarificationPrompts" in source &&
      !validSupplyClarificationPrompts(
        prompts,
        requested.clarificationRequired === true,
      )
    ) throw new Error("invalid supply request draft");
    return Object.freeze({
      ...item,
      clarificationPrompts: prompts,
    }) as JsonObject;
  });

  return Object.freeze({
    ...envelope,
    items: Object.freeze(projected),
  }) as AgentToolResultEnvelope;
}

function sameTechnicalPredicates(actual: unknown, expected: unknown): boolean {
  if (!Array.isArray(actual) || !Array.isArray(expected) || actual.length !== expected.length) {
    return false;
  }
  return actual.every((predicate, index) => {
    const requested = expected[index];
    if (
      !isRecord(predicate) || !isRecord(requested) ||
      !hasExactKeys(predicate, ["field", "operator", "values"]) ||
      !hasExactKeys(requested, ["field", "operator", "values"]) ||
      predicate.field !== requested.field ||
      predicate.operator !== requested.operator
    ) return false;
    const actualValues = predicate.values;
    const requestedValues = requested.values;
    if (
      !Array.isArray(actualValues) || !Array.isArray(requestedValues) ||
      actualValues.length !== requestedValues.length
    ) return false;
    return actualValues.every((value, valueIndex) => value === requestedValues[valueIndex]);
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
  if (toolName === "get_workshop_job_context") validateWorkshopJobContext(result, args);
  if (toolName === "inspect_diagnosis_schema") validateDiagnosisSchema(result, args);
  if (toolName === "analyze_sales_period") validateSalesPeriod(result, args);
  if (toolName === "prepare_diagnosis_update") {
    validatePreparedDiagnosisUpdate(result, args);
  }
  if (toolName === "prepare_workshop_item") validatePreparedWorkshopItem(result, args);
}

function validateInventorySearch(result: AgentToolResultEnvelope, args: JsonObject): void {
  if (
    result.resultCount > (args.limit as number) ||
    (result.status === "verifiedEmpty" && result.hasMore)
  ) throw new Error("invalid inventory search");
  let summaryFingerprint: string | null = null;
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
      (args.availability === "out_of_stock" && availability !== "out_of_stock") ||
      !Number.isSafeInteger(item.matchedCount) || (item.matchedCount as number) < 1 ||
      !Number.isSafeInteger(item.trackedCount) || (item.trackedCount as number) < 0 ||
      (item.trackedCount as number) > (item.matchedCount as number) ||
      !Number.isSafeInteger(item.totalStock) ||
      !finiteNumber(item.inventoryRetailValue) ||
      !finiteNumber(item.averagePrice) ||
      !finiteNumber(item.minimumPrice) ||
      !finiteNumber(item.maximumPrice) ||
      (item.minimumPrice as number) > (item.averagePrice as number) ||
      (item.averagePrice as number) > (item.maximumPrice as number) ||
      (item.matchedCount as number) < result.resultCount ||
      !(args.operationalPredicates as JsonValue[]).every((predicate) =>
        inventoryOperationalPredicateMatches(item, predicate)
      )
    ) throw new Error("invalid inventory search");
    const fingerprint = JSON.stringify([
      item.matchedCount,
      item.trackedCount,
      item.totalStock,
      item.inventoryRetailValue,
      item.averagePrice,
      item.minimumPrice,
      item.maximumPrice,
    ]);
    if (summaryFingerprint !== null && summaryFingerprint !== fingerprint) {
      throw new Error("invalid inventory search");
    }
    summaryFingerprint = fingerprint;
  }
  if (result.items.length > 0) {
    const matchedCount = result.items[0].matchedCount as number;
    if (
      (args.selectionMode === "all_matches" &&
        result.hasMore !== (matchedCount > result.resultCount)) ||
      (args.selectionMode === "top_n" && result.hasMore)
    ) throw new Error("invalid inventory search");
    validateInventoryOrder(result.items, args.sort as JsonObject);
  }
}

function validateInventoryOrder(items: readonly JsonObject[], sort: JsonObject): void {
  const field = sort.field;
  if (!["stock", "minimum_stock", "price"].includes(String(field))) return;
  const key = field === "minimum_stock" ? "minimumStock" : field;
  for (let index = 1; index < items.length; index += 1) {
    const previous = items[index - 1][key as string];
    const current = items[index][key as string];
    if (
      typeof previous !== "number" || typeof current !== "number" ||
      (sort.direction === "asc" && previous > current) ||
      (sort.direction === "desc" && previous < current)
    ) throw new Error("invalid inventory sort");
  }
}

function inventoryOperationalPredicateMatches(item: JsonObject, value: JsonValue): boolean {
  if (!isRecord(value) || !Array.isArray(value.values)) return false;
  const actual = value.field === "stock"
    ? item.stock
    : value.field === "minimum_stock"
    ? item.minimumStock
    : value.field === "price"
    ? item.price
    : undefined;
  if (typeof actual !== "number" || !Number.isFinite(actual)) return false;
  if (
    (value.field === "stock" || value.field === "minimum_stock") &&
    item.tracksInventory !== true
  ) return false;
  const values = value.values;
  if (values.some((entry) => typeof entry !== "number" || !Number.isFinite(entry))) {
    return false;
  }
  const first = values[0] as number;
  switch (value.operator) {
    case "eq":
      return actual === first;
    case "neq":
      return actual !== first;
    case "lt":
      return actual < first;
    case "lte":
      return actual <= first;
    case "gt":
      return actual > first;
    case "gte":
      return actual >= first;
    case "between": {
      const second = values[1] as number;
      return actual >= Math.min(first, second) && actual <= Math.max(first, second);
    }
    case "in":
      return (values as number[]).includes(actual);
    default:
      return false;
  }
}

function validateInventorySchemaInspection(result: AgentToolResultEnvelope): void {
  for (const item of result.items) {
    if (
      !["category", "field", "operational_field"].includes(String(item.kind)) ||
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
          typeof item.operators !== "string" || !item.operators.trim())) ||
      (item.kind === "operational_field" &&
        (item.technicalFamily !== null ||
          !["stock", "minimum_stock", "price"].includes(String(item.field)) ||
          item.dataType !== "number" || item.allowedValues !== null ||
          item.operators !== "eq,neq,lt,lte,gt,gte,between,in"))
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

function validateWorkshopJobContext(
  result: AgentToolResultEnvelope,
  args: JsonObject,
): void {
  if (result.hasMore || result.resultCount > 10) throw new Error("invalid workshop context");
  for (const item of result.items) {
    if (
      item.entityId !== args.jobId ||
      !nullableUuid(item.jobBikeId) ||
      typeof item.jobNumber !== "string" || !item.jobNumber.trim() ||
      typeof item.customerName !== "string" || !item.customerName.trim() ||
      !nullableString(item.bikeLabel) ||
      typeof item.jobType !== "string" || !item.jobType.trim() ||
      typeof item.jobStatus !== "string" || !item.jobStatus.trim() ||
      !nullableTimestamp(item.jobUpdatedAt) || item.jobUpdatedAt === null ||
      !nullableUuid(item.invoiceId) || !nullableString(item.invoiceNumber) ||
      !nullableString(item.invoiceStatus) ||
      !nullableTimestamp(item.diagnosisUpdatedAt) ||
      typeof item.canUpdateDiagnosis !== "boolean" ||
      typeof item.canAddWorkshopItem !== "boolean" ||
      (item.canUpdateDiagnosis && item.jobBikeId === null) ||
      ((item.invoiceId === null) !== (item.invoiceNumber === null))
    ) throw new Error("invalid workshop context");
  }
}

function validateDiagnosisSchema(
  result: AgentToolResultEnvelope,
  args: JsonObject,
): void {
  if (result.hasMore || result.resultCount > 40) throw new Error("invalid diagnosis schema");
  const fields = new Set<string>();
  for (const item of result.items) {
    if (
      typeof item.section !== "string" ||
      (args.section !== "any" && item.section !== args.section) ||
      typeof item.field !== "string" ||
      !/^[a-z][a-z0-9_]*\.[a-z][a-z0-9_]*$/.test(item.field) ||
      !item.field.startsWith(`${item.section}.`) || fields.has(item.field) ||
      typeof item.label !== "string" || !item.label.trim() ||
      !["number", "text"].includes(String(item.valueType)) ||
      typeof item.storedUnit !== "string" ||
      typeof item.inputUnits !== "string" || !item.inputUnits.trim() ||
      !nullableString(item.allowedValues) ||
      !(item.minimumValue === null || finiteNumber(item.minimumValue)) ||
      !(item.maximumValue === null || finiteNumber(item.maximumValue)) ||
      ((item.minimumValue === null) !== (item.maximumValue === null)) ||
      (typeof item.minimumValue === "number" && typeof item.maximumValue === "number" &&
        item.minimumValue > item.maximumValue)
    ) throw new Error("invalid diagnosis schema");
    fields.add(item.field);
  }
}

function validateSalesPeriod(result: AgentToolResultEnvelope, args: JsonObject): void {
  if (result.status !== "success" || result.resultCount !== 1 || result.hasMore) {
    throw new Error("invalid sales period");
  }
  const item = result.items[0];
  if (
    item.basis !== args.basis || item.invoiceStatus !== args.invoiceStatus ||
    typeof item.startDate !== "string" || !dateString(item.startDate) ||
    typeof item.endDate !== "string" || !dateString(item.endDate) ||
    item.startDate > item.endDate ||
    (args.rangeMode === "absolute" &&
      (item.startDate !== args.startDate || item.endDate !== args.endDate)) ||
    !Number.isSafeInteger(item.invoiceCount) || (item.invoiceCount as number) < 0 ||
    !Number.isSafeInteger(item.eventCount) || (item.eventCount as number) < 0 ||
    !finiteNumber(item.totalAmount) || (item.totalAmount as number) < 0 ||
    !finiteNumber(item.averagePerInvoice) || (item.averagePerInvoice as number) < 0 ||
    !nullableUuid(item.highestInvoiceId) ||
    !nullableString(item.highestInvoiceNumber) ||
    !nullableString(item.highestInvoiceCustomerName) ||
    !(item.highestInvoiceTotal === null || finiteNumber(item.highestInvoiceTotal)) ||
    !(item.highestPeriodAmount === null || finiteNumber(item.highestPeriodAmount)) ||
    ((item.invoiceCount as number) === 0) !== (item.highestInvoiceId === null) ||
    ((item.highestInvoiceId === null) !== (item.highestInvoiceNumber === null))
  ) throw new Error("invalid sales period");
}

function validatePreparedDiagnosisUpdate(
  result: AgentToolResultEnvelope,
  args: JsonObject,
): void {
  if (result.status !== "success" || result.resultCount !== 1 || result.hasMore) {
    throw new Error("invalid prepared diagnosis update");
  }
  const item = result.items[0];
  if (
    typeof item.approvalId !== "string" || !validUuid(item.approvalId) ||
    item.action !== "update_diagnosis" || item.state !== "pending" ||
    item.jobId !== args.jobId || item.jobBikeId !== args.jobBikeId ||
    typeof item.jobNumber !== "string" || !item.jobNumber.trim() ||
    typeof item.bikeLabel !== "string" || !item.bikeLabel.trim() ||
    item.field !== args.field ||
    typeof item.fieldLabel !== "string" || !item.fieldLabel.trim() ||
    !nullableString(item.previousValue) ||
    typeof item.newValue !== "string" || !item.newValue.trim() ||
    typeof item.expiresAt !== "string" || !isoInstant(item.expiresAt) ||
    Date.parse(item.expiresAt) <= Date.now()
  ) throw new Error("invalid prepared diagnosis update");
}

function validatePreparedWorkshopItem(
  result: AgentToolResultEnvelope,
  args: JsonObject,
): void {
  if (result.status !== "success" || result.resultCount !== 1 || result.hasMore) {
    throw new Error("invalid prepared workshop item");
  }
  const item = result.items[0];
  if (
    typeof item.approvalId !== "string" || !validUuid(item.approvalId) ||
    item.action !== "add_workshop_item" || item.state !== "pending" ||
    item.jobId !== args.jobId || item.jobBikeId !== args.jobBikeId ||
    item.catalogItemId !== args.catalogItemId ||
    typeof item.jobNumber !== "string" || !item.jobNumber.trim() ||
    !nullableString(item.bikeLabel) ||
    typeof item.itemName !== "string" || !item.itemName.trim() ||
    !["product", "service"].includes(String(item.itemType)) ||
    item.quantity !== args.quantity || !finiteNumber(item.unitPrice) ||
    !finiteNumber(item.lineTotal) ||
    Math.abs(
        (item.lineTotal as number) -
          (item.quantity as number) * (item.unitPrice as number),
      ) > 0.011 ||
    !nullableString(item.invoiceNumber) ||
    typeof item.expiresAt !== "string" || !isoInstant(item.expiresAt) ||
    Date.parse(item.expiresAt) <= Date.now()
  ) throw new Error("invalid prepared workshop item");
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

function nullableUuid(value: JsonValue): boolean {
  return value === null || (typeof value === "string" && validUuid(value));
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

function modelVisibleResult(
  toolName: string,
  result: AgentToolResultEnvelope,
): {
  value: JsonObject;
  entityReferences: readonly AgentToolEntityReference[];
} {
  const referenceKind = toolName === "search_workshop_jobs" ||
      toolName === "get_workshop_job_context"
    ? "workshop_job"
    : toolName === "search_inventory"
    ? "catalog_item"
    : null;
  const referenceField = referenceKind === "workshop_job"
    ? "jobRef"
    : referenceKind === "catalog_item"
    ? "catalogItemRef"
    : null;
  const referencesByEntityId = new Map<string, AgentToolEntityReference>();
  const entityReferences: AgentToolEntityReference[] = [];
  const value: JsonObject = {
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
      if (
        referenceKind !== null && referenceField !== null &&
        typeof _serverOwnedEntityId === "string" && validUuid(_serverOwnedEntityId)
      ) {
        let reference = referencesByEntityId.get(_serverOwnedEntityId);
        if (!reference) {
          reference = Object.freeze({
            ref: crypto.randomUUID(),
            kind: referenceKind,
            entityId: _serverOwnedEntityId,
          });
          referencesByEntityId.set(_serverOwnedEntityId, reference);
          entityReferences.push(reference);
        }
        visible[referenceField] = reference.ref;
      }
      return visible;
    }),
    resultCount: result.resultCount,
    hasMore: result.hasMore,
  };
  return { value, entityReferences: Object.freeze(entityReferences) };
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

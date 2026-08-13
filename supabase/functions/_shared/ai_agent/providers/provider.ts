import type { AgentProviderRequest, AgentProviderTurn, LogicalModelRole } from "../contracts.ts";

export type AgentProviderId = "anthropic" | "gemini" | "openai";

export interface AgentModelProvider {
  readonly id: AgentProviderId;
  modelFor(role: LogicalModelRole): string;
  generate(request: AgentProviderRequest, signal: AbortSignal): Promise<AgentProviderTurn>;
}

export class ProviderError extends Error {
  constructor(
    readonly code: "provider_unavailable" | "provider_invalid_response" | "provider_rejected",
    readonly status: number,
    readonly retryable: boolean,
  ) {
    super("AI provider request failed");
    this.name = "ProviderError";
  }
}

export function requiredToolNameFor(request: AgentProviderRequest): string | undefined {
  const requiredToolName = request.requiredToolName;
  if (requiredToolName === undefined) return undefined;
  if (
    !requiredToolName ||
    request.tools.filter((tool) => tool.name === requiredToolName).length !== 1
  ) {
    throw new ProviderError("provider_invalid_response", 502, false);
  }
  return requiredToolName;
}

export interface ProviderRoute {
  provider: AgentProviderId;
}

export class AgentProviderRouter {
  readonly #providers: ReadonlyMap<AgentProviderId, AgentModelProvider>;
  readonly #routes: Readonly<Record<LogicalModelRole, ProviderRoute>>;

  constructor(options: {
    providers: readonly AgentModelProvider[];
    routes: Readonly<Record<LogicalModelRole, ProviderRoute>>;
  }) {
    const providers = new Map<AgentProviderId, AgentModelProvider>();
    for (const provider of options.providers) {
      if (providers.has(provider.id)) throw new Error("Duplicate provider registration");
      providers.set(provider.id, provider);
    }
    for (const route of Object.values(options.routes)) {
      if (!providers.has(route.provider)) throw new Error("Provider route is not configured");
    }
    this.#providers = providers;
    this.#routes = Object.freeze({ ...options.routes });
  }

  providerFor(role: LogicalModelRole): AgentModelProvider {
    const provider = this.#providers.get(this.#routes[role].provider);
    if (!provider) throw new Error("Provider route is not configured");
    return provider;
  }
}

export function sanitizeProviderStatus(status: number): number {
  if (status === 408 || status === 429) return status;
  if (status >= 500 && status <= 599) return 502;
  return 502;
}

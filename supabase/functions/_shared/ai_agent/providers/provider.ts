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
    /// Motivo tipado del upstream, cuando existe: sólo el enum de estado del
    /// proveedor, jamás su texto libre. Alimenta el ledger de intentos para
    /// que un rechazo sea diagnosticable después; no participa del control de
    /// flujo, que sigue mirando `code`.
    readonly upstreamReason?: string,
  ) {
    super("AI provider request failed");
    this.name = "ProviderError";
  }
}

/// El código con el que un intento fallido queda en el ledger.
///
/// `code` solo dice «el proveedor rechazó». El status HTTP es lo que separa la
/// clave (401), el modelo (404) y la petición inválida (400), y sin él un
/// rechazo no se puede diagnosticar sin volver a reproducirlo. El código del
/// run **no** cambia: esto es evidencia, no control de flujo.
export function providerAttemptErrorCode(error: ProviderError): string {
  // El estado HTTP se guarda SIEMPRE que exista, no sólo en los rechazos
  // definitivos. Los reintentables —429 por cuota, 503 por saturación— son
  // justo los que hay que poder distinguir después, y hasta el 2026-08-21 se
  // registraban todos como `provider_unavailable` a secas: con eso no se puede
  // saber si al taller le falta cuota o si el proveedor está caído.
  const status = Number.isInteger(error.status) &&
      error.status >= 400 && error.status < 600
    ? `_${error.status}`
    : "";
  const reason = error.upstreamReason ? `_${error.upstreamReason}` : "";
  return `${error.code}${status}${reason}`;
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

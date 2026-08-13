import type { AgentUsage } from "./contracts.ts";

export interface AgentModelPrice {
  inputMicrousdPerMillionTokens: number;
  outputMicrousdPerMillionTokens: number;
}

export class AgentPricingCatalog {
  readonly #prices: ReadonlyMap<string, AgentModelPrice>;

  private constructor(prices: ReadonlyMap<string, AgentModelPrice>) {
    this.#prices = prices;
  }

  static parse(raw: string): AgentPricingCatalog {
    let decoded: unknown;
    try {
      decoded = JSON.parse(raw);
    } catch (_) {
      throw new Error("AI model pricing catalog is invalid");
    }
    if (!isRecord(decoded) || Object.keys(decoded).length === 0) {
      throw new Error("AI model pricing catalog is invalid");
    }
    const prices = new Map<string, AgentModelPrice>();
    for (const [model, value] of Object.entries(decoded)) {
      if (
        !/^[A-Za-z0-9][A-Za-z0-9._:-]{0,127}$/.test(model) || !isRecord(value) ||
        !hasExactKeys(value, [
          "inputMicrousdPerMillionTokens",
          "outputMicrousdPerMillionTokens",
        ])
      ) throw new Error("AI model pricing catalog is invalid");
      prices.set(
        model,
        Object.freeze({
          inputMicrousdPerMillionTokens: validRate(value.inputMicrousdPerMillionTokens),
          outputMicrousdPerMillionTokens: validRate(value.outputMicrousdPerMillionTokens),
        }),
      );
    }
    return new AgentPricingCatalog(prices);
  }

  requireModel(model: string): AgentModelPrice {
    const value = this.#prices.get(model);
    if (!value) throw new Error("AI routed model has no pricing entry");
    return value;
  }

  estimateMicrousd(model: string, usage: AgentUsage): number {
    const price = this.requireModel(model);
    const inputTokens = validTokens(usage.inputTokens);
    const outputTokens = validTokens(usage.outputTokens);
    if (validTokens(usage.totalTokens) !== inputTokens + outputTokens) {
      throw new Error("AI provider usage is invalid");
    }
    const numerator = BigInt(inputTokens) * BigInt(price.inputMicrousdPerMillionTokens) +
      BigInt(outputTokens) * BigInt(price.outputMicrousdPerMillionTokens);
    const estimate = (numerator + 999_999n) / 1_000_000n;
    if (estimate > BigInt(Number.MAX_SAFE_INTEGER)) {
      throw new Error("AI provider cost is out of range");
    }
    return Number(estimate);
  }
}

function validRate(value: unknown): number {
  if (!Number.isSafeInteger(value) || (value as number) < 0 || (value as number) > 1_000_000_000) {
    throw new Error("AI model pricing catalog is invalid");
  }
  return value as number;
}

function validTokens(value: unknown): number {
  if (!Number.isSafeInteger(value) || (value as number) < 0 || (value as number) > 100_000_000) {
    throw new Error("AI provider usage is invalid");
  }
  return value as number;
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return Boolean(value) && typeof value === "object" && !Array.isArray(value);
}

function hasExactKeys(value: Record<string, unknown>, expected: readonly string[]): boolean {
  return JSON.stringify(Object.keys(value).sort()) === JSON.stringify([...expected].sort());
}

/** Canonical tax classes accepted by storefront checkout and Merchant feed. */
export type EcommerceTaxRate = 0 | 19;

export function normalizeEcommerceTaxRate(value: unknown): EcommerceTaxRate | null {
  if (value === null || value === undefined || value === "") return null;
  const rate = typeof value === "number" ? value : Number(value);
  if (!Number.isFinite(rate)) return null;
  if (rate === 0) return 0;
  if (rate === 19 || Math.abs(rate - 0.19) < 1e-9) return 19;
  return null;
}

export function hasSupportedEcommerceTaxRate(value: unknown): boolean {
  return normalizeEcommerceTaxRate(value) !== null;
}

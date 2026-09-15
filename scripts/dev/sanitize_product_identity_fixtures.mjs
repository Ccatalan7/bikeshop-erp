#!/usr/bin/env node

import { readFile, rename, writeFile } from "node:fs/promises";
import { dirname, resolve } from "node:path";
import { randomUUID } from "node:crypto";

function usage() {
  console.error(
    "Usage: node scripts/dev/sanitize_product_identity_fixtures.mjs " +
      "RAW_CATALOG RAW_CATEGORIES OUTPUT_CATALOG OUTPUT_CATEGORIES",
  );
  process.exitCode = 64;
}

const [, , rawCatalogPath, rawCategoriesPath, outputCatalogPath, outputCategoriesPath] =
  process.argv;
if (
  !rawCatalogPath ||
  !rawCategoriesPath ||
  !outputCatalogPath ||
  !outputCategoriesPath
) {
  usage();
} else {
  await main();
}

async function main() {
  const rawCatalog = JSON.parse(await readFile(rawCatalogPath, "utf8"));
  const rawCategories = JSON.parse(await readFile(rawCategoriesPath, "utf8"));
  if (!Array.isArray(rawCatalog.products) || !Array.isArray(rawCategories.categories)) {
    throw new Error("Expected products[] and categories[] source fixtures.");
  }

  const seenSkus = new Set();
  const products = rawCatalog.products.map((product) => {
    const sku = requiredText(product.sku, "product.sku");
    if (seenSkus.has(sku)) throw new Error(`Duplicate fixture SKU: ${sku}`);
    seenSkus.add(sku);
    return {
      id: `fixture-product-${sku.toLowerCase()}`,
      tenant_id: "fixture-tenant",
      sku,
      name: requiredText(product.name, `${sku}.name`),
      description: optionalText(product.description) ?? "",
      category_id: optionalText(product.category_id),
      category_name: optionalText(product.category_name),
      brand: optionalText(product.brand),
      model: optionalText(product.model),
      manufacturer_sku: optionalText(product.manufacturer_sku),
      tags: Array.isArray(product.tags)
        ? product.tags.filter((tag) => typeof tag === "string")
        : [],
      is_active: product.is_active === true,
      is_service: product.is_service === true,
      price: 0,
      cost: 0,
    };
  });

  const categories = rawCategories.categories.map((category) => ({
    id: requiredText(category.id, "category.id"),
    parent_id: optionalText(category.parent_id),
    level: Number.isInteger(category.level) ? category.level : 0,
    name: requiredText(category.name, "category.name"),
    full_path: requiredText(category.full_path, "category.full_path"),
    tenant_id: "fixture-tenant",
  }));

  await atomicJsonWrite(outputCatalogPath, {
    source: "sanitized_product_identity_regression_fixture",
    privacy: {
      synthetic_record_ids: true,
      synthetic_tenant_id: true,
      monetary_values_zeroed: true,
      supplier_fields_omitted: true,
      image_fields_omitted: true,
    },
    products,
  });
  await atomicJsonWrite(outputCategoriesPath, {
    source: "sanitized_category_identity_regression_fixture",
    privacy: { synthetic_tenant_id: true },
    categories,
  });
}

function requiredText(value, label) {
  const normalized = optionalText(value);
  if (normalized == null) throw new Error(`Missing ${label}.`);
  return normalized;
}

function optionalText(value) {
  if (typeof value !== "string") return null;
  const normalized = value.trim();
  return normalized.length === 0 ? null : normalized;
}

async function atomicJsonWrite(path, value) {
  const absolute = resolve(path);
  const temporary = resolve(dirname(absolute), `.${randomUUID()}.tmp`);
  await writeFile(temporary, `${JSON.stringify(value, null, 2)}\n`, {
    mode: 0o600,
  });
  await rename(temporary, absolute);
}

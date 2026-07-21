import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  isProductAvailable,
  mergeCanonicalAvailableQuantities,
  resolveAvailableProductQuantity,
} from "./product_availability.ts";

Deno.test("ordinary products use persisted physical stock", () => {
  assertEquals(resolveAvailableProductQuantity({ stock_quantity: 3 }), 3);
  assertEquals(
    resolveAvailableProductQuantity({
      stock_quantity: null,
      inventory_qty: 2,
    }),
    2,
  );
});

Deno.test("set headers use complete component-backed availability", () => {
  assertEquals(
    resolveAvailableProductQuantity({
      is_set: true,
      stock_quantity: 0,
      full_sets_available: 4,
    }),
    4,
  );
  assertEquals(
    isProductAvailable({
      is_set: true,
      stock_quantity: 0,
      full_sets_available: 1,
    }),
    true,
  );
});

Deno.test("missing maps fail closed and untracked products remain available", () => {
  assertEquals(
    resolveAvailableProductQuantity({
      is_set: true,
      stock_quantity: 99,
      full_sets_available: null,
    }),
    0,
  );
  assertEquals(
    isProductAvailable({ track_stock: false, stock_quantity: 0 }),
    true,
  );
});

Deno.test("reservation-aware projection replaces raw headers and ordinary stock", () => {
  assertEquals(
    mergeCanonicalAvailableQuantities(
      [
        { id: "set", is_set: true, stock_quantity: 0 },
        { id: "ordinary", is_set: false, stock_quantity: 5 },
        { id: "missing", is_set: true, stock_quantity: 99 },
      ],
      [
        { product_id: "set", available_quantity: 2 },
        { product_id: "ordinary", available_quantity: 3 },
      ],
    ),
    [
      {
        id: "set",
        is_set: true,
        stock_quantity: 2,
        full_sets_available: 2,
      },
      { id: "ordinary", is_set: false, stock_quantity: 3 },
      {
        id: "missing",
        is_set: true,
        stock_quantity: 0,
        full_sets_available: 0,
      },
    ],
  );
});

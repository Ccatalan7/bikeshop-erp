import { expect, test } from "@playwright/test";

import { loginAsStagingStaff } from "./support/session";
import {
  readStagingFixtureStock,
  resetStagingInventoryFixture,
} from "./support/staging-fixture";

test.beforeEach(() => {
  // Playwright retries the test in the same suite. Reset here so every attempt
  // starts at stock 10 instead of inheriting a failed attempt's database state.
  resetStagingInventoryFixture();
});

async function registerAdjustment(
  page: Parameters<typeof loginAsStagingStaff>[0],
  direction: "Entrada" | "Salida",
  note: string,
  expectedStock: number,
) {
  const adjustmentButton = page.getByRole("button", {
    name: "Registrar ajuste de stock",
  });
  await adjustmentButton.click();
  const dialog = page.getByRole("alertdialog");
  await expect(dialog).toBeVisible();
  await expect(
    dialog.getByText("Registrar ajuste de stock", { exact: true }),
  ).toBeVisible();
  await dialog.getByRole("checkbox", { name: direction, exact: true }).click();
  await dialog.getByLabel("Cantidad", { exact: true }).fill("1");
  await dialog.getByLabel("Detalle / observación", { exact: true }).fill(note);
  await dialog
    .getByRole("button", { name: "Registrar ajuste", exact: true })
    .click();

  await expect(dialog).toBeHidden({ timeout: 15_000 });
  await expect
    .poll(readStagingFixtureStock, {
      timeout: 15_000,
      intervals: [500, 1_000, 2_000],
      message: `Expected the recorded adjustment to leave stock at ${expectedStock}`,
    })
    .toBe(expectedStock);
  await expect(adjustmentButton).toBeEnabled();
}

test("manual stock adjustment records a forward movement and an exact reversal", async ({
  page,
}) => {
  await loginAsStagingStaff(page);
  await page.getByRole("button", { name: "Inventario", exact: true }).click();
  await page.getByRole("button", { name: "Productos", exact: true }).click();
  await expect(page).toHaveURL(/\/inventory\/products$/);

  const fixtureProduct = page.getByRole("group", {
    name: /Producto E2E - Ajuste reversible.*10.*2\.500.*1\.000/,
  });
  await expect(fixtureProduct).toBeVisible({ timeout: 15_000 });
  await fixtureProduct.getByRole("button", { name: "Mostrar menú" }).click();
  await page.getByRole("menuitem", { name: "Editar", exact: true }).click();

  await expect(page.getByText("Editar producto", { exact: true })).toBeVisible({
    timeout: 15_000,
  });

  const stock = page.getByLabel("Stock actual", { exact: true });
  await stock.scrollIntoViewIfNeeded();
  await expect(stock).toBeVisible();

  await registerAdjustment(page, "Salida", "[E2E] Forward stock adjustment", 9);
  await registerAdjustment(
    page,
    "Entrada",
    "[E2E] Reverse stock adjustment",
    10,
  );
});

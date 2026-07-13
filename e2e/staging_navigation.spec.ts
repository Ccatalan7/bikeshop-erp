import { expect, test } from "@playwright/test";

import { loginAsStagingStaff } from "./support/session";

test("staging staff can open the inventory, sales and purchase control surfaces", async ({
  page,
}) => {
  await loginAsStagingStaff(page);

  await page.getByRole("button", { name: "Inventario", exact: true }).click();
  await page.getByRole("button", { name: "Movimientos", exact: true }).click();
  await expect(page).toHaveURL(/\/inventory\/movements$/);
  await expect(
    page.getByText("Movimientos de Stock", { exact: true }),
  ).toBeVisible();

  await page.getByRole("button", { name: "Ventas", exact: true }).click();
  await page
    .getByRole("button", { name: "Facturas de venta", exact: true })
    .click();
  await expect(page).toHaveURL(/\/sales\/invoices$/);
  await expect(
    page.getByText("Facturas de Venta", { exact: true }),
  ).toBeVisible();

  const purchasesButtons = page.getByRole("button", {
    name: "Compras",
    exact: true,
  });
  await expect(purchasesButtons).toHaveCount(2);
  await purchasesButtons.nth(0).click();
  await page
    .getByRole("button", { name: "Facturas de compra", exact: true })
    .click();
  await expect(page).toHaveURL(/\/purchases$/);
  await expect(
    page.getByText("Facturas de Compra", { exact: true }),
  ).toBeVisible();
});

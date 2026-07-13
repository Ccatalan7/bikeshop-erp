import { expect, test, type Page } from "@playwright/test";

import { loginAsStagingStaff } from "./support/session";
import {
  readStagingPaymentFixture,
  resetStagingInventoryFixture,
  type PaymentFixtureState,
} from "./support/staging-fixture";

const invoiceId = "e2e00000-0000-4000-8000-000000000201";

test.beforeEach(() => resetStagingInventoryFixture());

async function expectPaymentState(expected: PaymentFixtureState) {
  await expect
    .poll(readStagingPaymentFixture, {
      timeout: 15_000,
      intervals: [500, 1_000, 2_000],
    })
    .toEqual(expected);
}

async function registerPayment(page: Page, amount: string) {
  await page
    .getByRole("button", { name: "Registrar pago", exact: true })
    .click();
  await expect(page.getByText("Pagar factura", { exact: true })).toBeVisible({
    timeout: 15_000,
  });
  const amountField = page.getByLabel("Monto", { exact: true });
  await expect(amountField).toBeVisible({ timeout: 15_000 });
  await amountField.click();
  await amountField.press("ControlOrMeta+A");
  await amountField.pressSequentially(amount);
  await expect(amountField).toHaveValue(amount);
  await page
    .getByRole("button", { name: "Registrar pago", exact: true })
    .click();
  await expect(
    page.getByText("Factura E2E-PAY-ROUNDING", { exact: true }),
  ).toBeVisible({ timeout: 15_000 });
}

async function undoLastPayment(page: Page) {
  await page
    .getByRole("button", { name: "Deshacer pago", exact: true })
    .click();
  const dialog = page.getByRole("alertdialog");
  await expect(
    dialog.getByText("Deshacer pago", { exact: true }),
  ).toBeVisible();
  await dialog
    .getByRole("button", { name: "Eliminar pago", exact: true })
    .click();
}

test("CLP 8,999 + 1 partial payments reverse without phantom balance or duplicate accounting", async ({
  page,
}) => {
  await loginAsStagingStaff(page);
  await page.getByRole("button", { name: "Ventas", exact: true }).click();
  await page
    .getByRole("button", { name: "Facturas de venta", exact: true })
    .click();
  await expect(page).toHaveURL(/\/sales\/invoices$/);
  const search = page.getByRole("textbox", {
    name: "Buscar en Facturas ( / )",
    exact: true,
  });
  await expect(search).toBeVisible({ timeout: 15_000 });
  await search.fill("E2E-PAY-ROUNDING");
  const invoiceRow = page.getByRole("group", {
    name: /E2E-PAY-ROUNDING.*Cliente E2E - Pago reversible/,
  });
  await expect(invoiceRow).toBeVisible();
  await invoiceRow.getByRole("button").click();
  await page.getByRole("menuitem", { name: "Editar", exact: true }).click();
  await expect(page).toHaveURL(new RegExp(`/sales/invoices/${invoiceId}$`));
  await expect(
    page.getByText("Factura E2E-PAY-ROUNDING", { exact: true }),
  ).toBeVisible({ timeout: 15_000 });

  await registerPayment(page, "8999");
  await expectPaymentState({
    status: "confirmed",
    total: 9000,
    paid: 8999,
    balance: 1,
    activePayments: 1,
    paymentJournals: 1,
    paymentStockMovements: 0,
    incompleteOperations: 0,
  });

  await registerPayment(page, "1");
  await expectPaymentState({
    status: "paid",
    total: 9000,
    paid: 9000,
    balance: 0,
    activePayments: 2,
    paymentJournals: 2,
    paymentStockMovements: 0,
    incompleteOperations: 0,
  });

  await undoLastPayment(page);
  await expectPaymentState({
    status: "confirmed",
    total: 9000,
    paid: 8999,
    balance: 1,
    activePayments: 1,
    paymentJournals: 1,
    paymentStockMovements: 0,
    incompleteOperations: 0,
  });

  await undoLastPayment(page);
  await expectPaymentState({
    status: "confirmed",
    total: 9000,
    paid: 0,
    balance: 9000,
    activePayments: 0,
    paymentJournals: 0,
    paymentStockMovements: 0,
    incompleteOperations: 0,
  });
});

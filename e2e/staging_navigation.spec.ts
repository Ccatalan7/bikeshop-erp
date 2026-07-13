import {expect, test, type Page} from '@playwright/test';

async function enableFlutterSemantics(page: Page) {
  const placeholder = page.locator('flt-semantics-placeholder');
  await placeholder.waitFor({state: 'attached', timeout: 15_000});
  await placeholder.evaluate((element) => (element as HTMLElement).click());
  if ((await placeholder.count()) === 1) {
    await placeholder.press('Enter');
  }
}

test('staging staff can open the inventory, sales and purchase control surfaces', async ({
  page,
}) => {
  const email = process.env.E2E_EMAIL;
  const password = process.env.E2E_PASSWORD;
  if (!email || !password) {
    throw new Error('E2E_EMAIL and E2E_PASSWORD are required');
  }

  await page.goto('/login');
  await enableFlutterSemantics(page);

  const emailInput = page.getByLabel('Correo Electrónico', {exact: true});
  const passwordInput = page.getByLabel('Contraseña', {exact: true});
  await expect(emailInput).toBeVisible({timeout: 10_000});
  await emailInput.click();
  await emailInput.pressSequentially(email);
  await passwordInput.click();
  await passwordInput.pressSequentially(password);
  await page.getByRole('button', {name: 'Iniciar Sesión', exact: true}).click();

  await expect(page).toHaveURL(/\/dashboard$/);
  await expect(page.getByText('Bienvenido a Vinabike ERP', {exact: true})).toBeVisible();
  await expect(page.getByText('No pudimos cargar los datos contables')).toHaveCount(0);

  await page.getByRole('button', {name: 'Inventario', exact: true}).click();
  await page.getByRole('button', {name: 'Movimientos', exact: true}).click();
  await expect(page).toHaveURL(/\/inventory\/movements$/);
  await expect(page.getByText('Movimientos de Stock', {exact: true})).toBeVisible();

  await page.getByRole('button', {name: 'Ventas', exact: true}).click();
  await page.getByRole('button', {name: 'Facturas de venta', exact: true}).click();
  await expect(page).toHaveURL(/\/sales\/invoices$/);
  await expect(page.getByText('Facturas de Venta', {exact: true})).toBeVisible();

  const purchasesButtons = page.getByRole('button', {name: 'Compras', exact: true});
  await expect(purchasesButtons).toHaveCount(2);
  await purchasesButtons.nth(0).click();
  await page.getByRole('button', {name: 'Facturas de compra', exact: true}).click();
  await expect(page).toHaveURL(/\/purchases$/);
  await expect(page.getByText('Facturas de Compra', {exact: true})).toBeVisible();
});

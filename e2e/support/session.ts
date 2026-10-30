import type { Page } from "@playwright/test";

export async function enableFlutterSemantics(page: Page) {
  const placeholder = page.locator("flt-semantics-placeholder");
  await placeholder.waitFor({ state: "attached", timeout: 15_000 });
  await placeholder.evaluate((element) => (element as HTMLElement).click());
  if ((await placeholder.count()) === 1) {
    await placeholder.press("Enter");
  }
}

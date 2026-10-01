// C2 en escritorio (PLANS.md, 2026-09-30): recuperar desde Configuración →
// Respaldos un trabajo perdido, con su bici y su tarea, con lib/main.dart
// contra Auth y REST locales. La fixture (backup_journey_local_fixture.sql)
// arma el taller, el respaldo real, lo que cambió después y la pérdida; el
// readback compara cada fila del grafo con el respaldo. Lo lanza
// `scripts/e2e/run_android_local_journey.sh --journey backup --surface web`
// (que exporta WORKSHOP_E2E_ENABLED, _FRAMES_DIR y _HOLD_DIR para todo
// recorrido web); sin ese script la prueba se salta. La contraseña llega por
// el entorno y sólo se teclea en el login.
import { existsSync, mkdirSync, readFileSync, unlinkSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { expect, test, type Locator, type Page } from "@playwright/test";
import { enableFlutterSemantics } from "./support/session";

const enabled = process.env.WORKSHOP_E2E_ENABLED === "1";

test.use({
  channel: "chrome",
  viewport: { width: 1440, height: 900 },
  actionTimeout: 20_000,
  screenshot: "off",
  trace: "off",
  video: "off",
});

const evidence: string[] = [];

function required(name: string): string {
  const value = process.env[name];
  if (!value) {
    throw new Error(`Falta ${name}: correr scripts/e2e/run_android_local_journey.sh --journey backup --surface web`);
  }
  return value;
}

const escapeRegExp = (text: string) => text.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");

function named(name: string | RegExp): RegExp {
  return typeof name === "string"
    ? new RegExp(`^${escapeRegExp(name)}(\\s+${escapeRegExp(name)})?$`)
    : name;
}

function control(scope: Page | Locator, name: string | RegExp): Locator {
  const options = { name: named(name) };
  return scope
    .getByRole("button", options)
    .or(scope.getByRole("menuitem", options))
    .or(scope.getByRole("radio", options))
    .or(scope.getByRole("link", options))
    .first();
}

function notice(scope: Page | Locator, text: string | RegExp): Locator {
  const pattern = typeof text === "string" ? new RegExp(escapeRegExp(text)) : text;
  return scope
    .getByText(pattern)
    .or(scope.getByLabel(pattern))
    .or(scope.getByRole("group", { name: pattern }))
    .first();
}

async function type(page: Page, target: Locator, text: string, check = true) {
  await expect(target).toBeVisible({ timeout: 30_000 });
  await target.click();
  await expect(target).toBeFocused();
  await page.waitForTimeout(250);
  await target.pressSequentially(text);
  if (check) await expect(target).toHaveValue(text);
}

async function tree(page: Page): Promise<string> {
  return page
    .locator("body")
    .ariaSnapshot({ timeout: 15_000 })
    .catch((error) => `sin árbol: ${error}`);
}

test("recuperar un trabajo perdido desde Respaldos", async ({ page }) => {
  test.skip(!enabled, "Sólo con scripts/e2e/run_android_local_journey.sh --surface web");
  const holdDir = process.env.WORKSHOP_E2E_HOLD_DIR ?? "";
  test.setTimeout(holdDir ? 0 : 10 * 60_000);

  const framesDir = required("WORKSHOP_E2E_FRAMES_DIR");
  const backupName = required("BACKUP_E2E_NAME");
  const jobId = required("BACKUP_E2E_JOB_ID");
  mkdirSync(framesDir, { recursive: true });
  let frameNumber = 0;
  let onLogin = true;

  async function themed(name: string) {
    if (onLogin) throw new Error("no se capturan frames del login");
    frameNumber += 1;
    writeFileSync(
      `${framesDir}/${String(frameNumber).padStart(2, "0")}-${name}-semantica.txt`,
      `${page.url()}\n${await tree(page)}\n`,
    );
    for (const scheme of ["light", "dark"] as const) {
      await page.emulateMedia({ colorScheme: scheme });
      await page.waitForTimeout(700);
      await page.screenshot({
        path: `${framesDir}/${String(frameNumber).padStart(2, "0")}-${name}-${
          scheme === "light" ? "claro" : "oscuro"
        }.png`,
      });
    }
    await page.emulateMedia({ colorScheme: "light" });
    await page.waitForTimeout(400);
  }

  const h = { control, notice, type, tree, themed, escapeRegExp, evidence };

  // Flutter web expone el AlertDialog como `alertdialog` y funde su cuerpo
  // en un solo grupo: el texto se lee de ese grupo, no de nodos sueltos.
  async function openReview(): Promise<Locator> {
    const menu = control(page, `Acciones del respaldo ${backupName}`);
    await expect(menu).toBeVisible({ timeout: 60_000 });
    await menu.click();
    await control(page, "Restaurar").click();
    const dialog = page.getByRole("alertdialog");
    await expect(notice(dialog, "Vuelve lo que falta del taller")).toBeVisible({ timeout: 60_000 });
    return dialog;
  }

  // En web, un AlertDialog cuya única acción es un VbButton no publica ese
  // nodo (el árbol del framework sí lo tiene): «Entendido» del resultado y
  // «Cerrar» de la revisión sin nada que recuperar. Con dos acciones ambas
  // aparecen. Defecto abierto del checkpoint C2: se deja constancia y se
  // cierra con Escape, la salida de teclado.
  async function close(dialog: Locator, name: string, key: string) {
    const action = control(dialog, name);
    if (await action.isVisible()) {
      await action.click();
      evidence.push(`${key}=boton`);
    } else {
      writeFileSync(`${framesDir}/${key}-dom.html`, await page.evaluate(() =>
        document.querySelector("flt-semantics[role=alertdialog]")?.outerHTML ?? "sin alertdialog"));
      await page.keyboard.press("Escape");
      evidence.push(`${key}=sin_nodo_web`);
    }
    await expect(page.getByRole("alertdialog")).toHaveCount(0);
  }

  async function says(dialog: Locator, pattern: RegExp) {
    await expect.poll(async () => (await dialog.ariaSnapshot()).replace(/\s+/g, " "),
      { timeout: 30_000 }).toMatch(pattern);
  }

  async function journey() {
    // 1. Entra la operadora (admin) por el login real; tema «Sistema».
    await page.goto("/login");
    await enableFlutterSemantics(page);
    await type(page, page.getByLabel("Correo Electrónico", { exact: true }),
      required("BACKUP_E2E_EMAIL"));
    await type(page, page.getByLabel("Contraseña", { exact: true }),
      required("BACKUP_E2E_PASSWORD"), false);
    await control(page, "Iniciar Sesión").click();
    await expect(page).not.toHaveURL(/\/login/, { timeout: 60_000 });
    onLogin = false;
    evidence.push("login=ok");
    await control(page, "Configuración rápida").click();
    await control(page, "Sistema").click();
    await expect(page.getByRole("radio", { name: "Sistema" })).toBeChecked();
    await control(page.getByRole("dialog"), "Cerrar").click();

    // 2. La revisión del respaldo: la base corre el motor y lo deshace.
    await page.goto("/settings/backup");
    await enableFlutterSemantics(page);
    const review = await openReview();
    // Lo que el taller reconoce va primero: el trabajo, la bici, la tarea.
    await says(review, /Vuelve Trabajos 1 Trabajo PG-\d+ Bicis 1 Bici Trek Marlin 7 Tareas 1 Tarea Purgar y medir el rotor/);
    await says(review, /No vuelve Líneas de los trabajos 1 Parche — su trabajo existe hoy y se queda con lo que tiene hoy\./);
    await says(review, /Ventas, compras, contabilidad, inventario, mensajes, productos y ajustes no se tocan/);
    const jobNumber = /Trabajo (PG-\d+)/.exec(await review.ariaSnapshot())?.[1];
    expect(jobNumber, "la revisión nombra el trabajo que vuelve").toBeTruthy();
    await expect(control(review, "Restaurar")).toBeVisible();
    await themed("revision-del-respaldo");
    evidence.push(`revision=vuelve_${jobNumber}`);

    // 3. Restaurar: vuelve lo que faltaba y se informa lo que no.
    await control(review, "Restaurar").click();
    const result = page.getByRole("alertdialog");
    await expect(notice(result, "Respaldo restaurado")).toBeVisible({ timeout: 60_000 });
    await says(result, new RegExp(`Volvió Trabajos 1 Trabajo ${jobNumber} Bicis 1`));
    await says(result, /No vuelve Líneas de los trabajos 1/);
    await themed("resultado-de-la-recuperacion");
    await close(result, "Entendido", "entendido");
    evidence.push("recuperado=ok");

    // 4. En el teléfono, la misma revisión ya no encuentra nada que falte.
    await page.setViewportSize({ width: 390, height: 844 });
    await page.waitForTimeout(800);
    const again = await openReview();
    await says(again, /No falta nada\.? Todo lo que guarda este respaldo existe hoy/);
    await says(again, /No vuelve Líneas de los trabajos 1/);
    await expect(control(again, "Restaurar")).toHaveCount(0);
    await themed("revision-despues-telefono");
    await close(again, "Cerrar", "cerrar_revision");
    evidence.push("telefono=no_falta_nada");

    // 5. El trabajo recuperado se abre en el taller con su cliente, su bici,
    //    sus dos líneas (Rotor 160 mm $32.990 + Purga de frenos $25.000) y la
    //    solicitud que el mecánico anotó. La ficha no muestra el número.
    await page.setViewportSize({ width: 1440, height: 900 });
    await page.goto(`/taller/pegas/${jobId}`);
    await enableFlutterSemantics(page);
    await expect.poll(async () => (await tree(page)).replace(/\s+/g, " "), { timeout: 60_000 })
      .toMatch(/Editar Trabajo[\s\S]*Camila Rojas[\s\S]*Trek Marlin 7[\s\S]*Subtotal: \$57,990/);
    const request = page.getByRole("textbox", { name: "Solicitud del cliente" }).first();
    await request.click();
    await expect(request).toHaveValue("Frena poco adelante");
    await request.blur();
    await themed("trabajo-recuperado");
    evidence.push("trabajo=abre");
  }

  try {
    await journey();
    console.log(`C2 escritorio evidencia: ${evidence.join(" | ")} | estados=${frameNumber}`);
  } catch (error) {
    console.log(`C2 escritorio evidencia hasta el fallo: ${evidence.join(" | ")}`);
    if (!onLogin) {
      await page.screenshot({ path: `${framesDir}/fallo.png` }).catch(() => undefined);
      writeFileSync(`${framesDir}/fallo-arbol.txt`, `${page.url()}\n${await tree(page)}\n`);
    }
    if (holdDir && !onLogin) await hold(page, holdDir, h);
    throw error;
  }
});

// Retenido: la página sigue con su sesión y ejecuta lo que llegue a cmd.js.
async function hold(page: Page, dir: string, h: Record<string, unknown>) {
  const AsyncFunction = Object.getPrototypeOf(async () => undefined).constructor;
  const command = join(dir, "cmd.js");
  const answer = join(dir, "out.txt");
  writeFileSync(join(dir, "ready"), `${page.url()}\n`);
  for (;;) {
    if (existsSync(command)) {
      const code = readFileSync(command, "utf8");
      unlinkSync(command);
      if (code.trim() === "exit") {
        writeFileSync(answer, "bye\n");
        return;
      }
      let result: string;
      try {
        const value = await new AsyncFunction("page", "h", "expect", code)(page, h, expect);
        result = typeof value === "string" ? value : JSON.stringify(value ?? null, null, 1);
      } catch (error) {
        result = `ERROR ${error instanceof Error ? error.message : String(error)}`;
      }
      writeFileSync(answer, `${result}\n`);
    }
    await page.waitForTimeout(300);
  }
}

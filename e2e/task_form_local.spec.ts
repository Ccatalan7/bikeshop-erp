// C1 por la app (PLANS.md, 2026-09-30): el mecánico adjunta, abre y retira
// archivos desde el TaskFormDialog real de lib/main.dart, contra Auth, REST y
// Storage locales. Lo lanza scripts/e2e/run_task_form_local.sh, que crea antes
// el empleado sintético y sirve la app con `web_preview.sh --local`; sin ese
// script la prueba se salta.
//
// Nada de dobles: la caída de Storage es el contenedor local detenido y vuelto
// a arrancar, y la limpieza pendiente la retoma la app al volver a entrar.
// La contraseña llega por el entorno y sólo se teclea en el login.
import { execFileSync } from "node:child_process";
import { mkdirSync, writeFileSync } from "node:fs";
import { deflateSync } from "node:zlib";
import { expect, test, type Locator, type Page } from "@playwright/test";
import { enableFlutterSemantics } from "./support/session";

const enabled = process.env.TASK_FORM_E2E_ENABLED === "1";

test.use({
  channel: "chrome",
  viewport: { width: 1440, height: 900 },
  actionTimeout: 20_000,
  screenshot: "off",
  trace: "off",
  video: "off",
});

const evidence: string[] = [];

// Al fallar: captura, ruta y árbol accesible del estado real. Nunca en el
// login, donde el campo de contraseña del DOM guarda lo tecleado.
test.afterEach(async ({ page }, testInfo) => {
  const dir = process.env.TASK_FORM_E2E_FRAMES_DIR;
  if (!enabled || !dir || testInfo.status === testInfo.expectedStatus) return;
  mkdirSync(dir, { recursive: true });
  console.log(`C1 UI evidencia hasta el fallo: ${evidence.join(" | ")}`);
  if (new URL(page.url()).pathname.startsWith("/login")) return;
  await page.screenshot({ path: `${dir}/fallo.png` }).catch(() => undefined);
  const tree = await page
    .locator("body")
    .ariaSnapshot({ timeout: 10_000 })
    .catch((error) => `sin árbol: ${error}`);
  writeFileSync(`${dir}/fallo-arbol.txt`, `${page.url()}\n${tree}\n`);
});

function required(name: string): string {
  const value = process.env[name];
  if (!value) {
    throw new Error(`Falta ${name}: correr scripts/e2e/run_task_form_local.sh`);
  }
  return value;
}

// ── PNG pequeños hechos aquí: una foto de taller no cabe en el repo ─────────
const crcTable = Array.from({ length: 256 }, (_, n) => {
  let c = n;
  for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
  return c >>> 0;
});

function crc32(bytes: Buffer): number {
  let c = 0xffffffff;
  for (const byte of bytes) c = crcTable[(c ^ byte) & 0xff] ^ (c >>> 8);
  return (c ^ 0xffffffff) >>> 0;
}

function chunk(type: string, data: Buffer): Buffer {
  const length = Buffer.alloc(4);
  length.writeUInt32BE(data.length);
  const body = Buffer.concat([Buffer.from(type, "ascii"), data]);
  const crc = Buffer.alloc(4);
  crc.writeUInt32BE(crc32(body));
  return Buffer.concat([length, body, crc]);
}

function png(width: number, height: number, tint: [number, number, number]): Buffer {
  const header = Buffer.alloc(13);
  header.writeUInt32BE(width, 0);
  header.writeUInt32BE(height, 4);
  header.set([8, 2, 0, 0, 0], 8);
  const rows: number[] = [];
  for (let y = 0; y < height; y++) {
    rows.push(0);
    for (let x = 0; x < width; x++) {
      const ring = Math.hypot(x - width / 2, y - height / 2) % 18 < 9 ? 1 : 0.72;
      rows.push(...tint.map((channel) => Math.round(channel * ring)));
    }
  }
  return Buffer.concat([
    Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]),
    chunk("IHDR", header),
    chunk("IDAT", deflateSync(Buffer.from(rows))),
    chunk("IEND", Buffer.alloc(0)),
  ]);
}

// ── Controles por su nombre accesible (Flutter web los expone con semántica) ─
const escapeRegExp = (text: string) => text.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");

// Un nombre exacto acepta también su duplicado «X X»: VbShellIconButton suma
// hoy su tooltip a la etiqueta (defecto del control compartido, reportado).
function control(scope: Page | Locator, name: string | RegExp): Locator {
  const pattern =
    typeof name === "string"
      ? new RegExp(`^${escapeRegExp(name)}(\\s+${escapeRegExp(name)})?$`)
      : name;
  const options = { name: pattern };
  return scope
    .getByRole("button", options)
    .or(scope.getByRole("menuitem", options))
    .or(scope.getByRole("radio", options))
    .or(scope.getByRole("tab", options))
    .first();
}

// Primera respuesta (o caída de red) de una escritura en el bucket privado.
function storageOutcome(page: Page, method: string): Promise<string> {
  const matches = (url: string, requestMethod: string) =>
    url.includes("/storage/v1/object/task-attachments") && requestMethod === method;
  const answered = page
    .waitForResponse((response) => matches(response.url(), response.request().method()), {
      timeout: 90_000,
    })
    .then((response) => `HTTP ${response.status()}`);
  const dropped = page
    .waitForEvent("requestfailed", {
      predicate: (request) => matches(request.url(), request.method()),
      timeout: 90_000,
    })
    .then(() => "sin respuesta");
  answered.catch(() => undefined);
  dropped.catch(() => undefined);
  return Promise.any([answered, dropped]);
}

// Flutter web monta el campo editable al tomar el foco: teclear antes pierde
// la primera letra («astillas» en la corrida del 2026-09-30). Se espera el
// foco y se comprueba lo escrito.
async function type(page: Page, label: string, text: string) {
  const field = page.getByLabel(label, { exact: true });
  await expect(field).toBeVisible({ timeout: 30_000 });
  await field.click();
  await expect(field).toBeFocused();
  await page.waitForTimeout(250);
  await field.pressSequentially(text);
  await expect(field).toHaveValue(text);
}

// Un aviso dentro del diálogo: texto visible y anunciado por la semántica.
function notice(page: Page, text: RegExp): Locator {
  return page.getByText(text).or(page.getByLabel(text)).first();
}

test("el mecánico adjunta, abre y retira archivos desde la tarea", async ({ page }) => {
  test.skip(!enabled, "Sólo con scripts/e2e/run_task_form_local.sh (stack local)");
  test.setTimeout(12 * 60_000);

  const apiUrl = required("TASK_FORM_E2E_API_URL");
  const container = required("TASK_FORM_E2E_STORAGE_CONTAINER");
  const framesDir = required("TASK_FORM_E2E_FRAMES_DIR");
  const title = required("TASK_FORM_E2E_TASK_TITLE");
  const assignee = required("TASK_FORM_E2E_ASSIGNEE");
  mkdirSync(framesDir, { recursive: true });
  let frameNumber = 0;

  async function frame(name: string) {
    frameNumber += 1;
    await page.screenshot({
      path: `${framesDir}/${String(frameNumber).padStart(2, "0")}-${name}.png`,
    });
  }

  // Claro y oscuro del mismo estado: la app sigue al sistema («Sistema»).
  async function themedFrames(name: string, compact = false) {
    const sizes = compact
      ? [
          { suffix: "escritorio", width: 1440, height: 900 },
          { suffix: "telefono-web", width: 390, height: 844 },
        ]
      : [{ suffix: "escritorio", width: 1440, height: 900 }];
    for (const size of sizes) {
      await page.setViewportSize({ width: size.width, height: size.height });
      for (const scheme of ["light", "dark"] as const) {
        await page.emulateMedia({ colorScheme: scheme });
        await page.waitForTimeout(600);
        await frame(`${name}-${size.suffix}-${scheme === "light" ? "claro" : "oscuro"}`);
      }
    }
    await page.setViewportSize({ width: 1440, height: 900 });
    await page.emulateMedia({ colorScheme: "light" });
    await page.waitForTimeout(600);
  }

  async function storageStatus(): Promise<number> {
    try {
      const response = await fetch(`${apiUrl}/storage/v1/status`, {
        signal: AbortSignal.timeout(3_000),
      });
      return response.status;
    } catch {
      return 0;
    }
  }

  async function storage(action: "stop" | "start") {
    execFileSync("docker", [action, container], { stdio: "ignore" });
    const up = action === "start";
    await expect
      .poll(async () => {
        const status = await storageStatus();
        return up ? status > 0 && status < 500 : status === 0 || status >= 500;
      }, { timeout: 90_000, intervals: [500, 1_000, 2_000] })
      .toBe(true);
    evidence.push(`storage_${up ? "arriba" : "caido"}`);
  }

  // El directorio de asignación: estado y tamaño, nunca su contenido.
  let directory = "sin_llamada";
  let directoryCalls = 0;
  page.on("response", async (response) => {
    if (!response.url().includes("/rpc/get_smart_task_assignment_directory_v1")) return;
    directoryCalls += 1;
    const body = await response.text().catch(() => "");
    let detail = `${body.length}B`;
    try {
      const parsed = JSON.parse(body);
      detail = Array.isArray(parsed) ? `${parsed.length}_personas` : String(parsed?.message ?? "");
    } catch {
      /* cuerpo no JSON */
    }
    directory = `HTTP_${response.status()}_${detail.replace(/\s+/g, "_").slice(0, 80)}`;
  });

  // Lo que la app deja en consola sobre el directorio o el formulario.
  const appLog: string[] = [];
  let consoleCount = 0;
  page.on("console", (message) => {
    consoleCount += 1;
    const text = message.text();
    if (/assignment directory|TaskFormDialog|Assignment directory/i.test(text)) {
      appLog.push(text.replace(/\s+/g, " ").slice(0, 240));
    }
  });

  // 1. Entra el empleado por el login real de la app.
  await page.goto("/login");
  await enableFlutterSemantics(page);
  await type(page, "Correo Electrónico", required("TASK_FORM_E2E_EMAIL"));
  await type(page, "Contraseña", required("TASK_FORM_E2E_PASSWORD"));
  await control(page, "Iniciar Sesión").click();
  await expect(page).not.toHaveURL(/\/login/, { timeout: 60_000 });
  evidence.push(`login=${new URL(page.url()).pathname}`);

  // 2. Tema «Sistema», para tomar claro y oscuro del mismo estado.
  await control(page, "Configuración rápida").click();
  await control(page, "Sistema").click();
  await expect(page.getByRole("radio", { name: "Sistema" })).toBeChecked();
  await control(page.getByRole("dialog"), "Cerrar").click();
  await expect(page.getByRole("dialog")).toHaveCount(0);
  evidence.push("tema=sistema");

  // 3. Taller → Vista: Tareas → Nueva tarea.
  await page.goto("/taller/pegas");
  await enableFlutterSemantics(page);
  // El selector lleva un glifo delante: «📋 Vista: Tabla».
  await control(page, /Vista: /).click();
  await control(page, /^\S*\s*Tareas$/).click();
  await expect(control(page, /Vista: Tareas$/)).toBeVisible();
  const directoryCallsBeforeForm = directoryCalls;
  await control(page, "Nueva tarea").click();
  await expect(page.getByText("Nueva Tarea", { exact: true })).toBeVisible();

  await type(page, "Título de la tarea", title);
  await type(
    page,
    "Descripción (Opcional)",
    "Pastillas gastadas hasta el metal; fotos antes del cambio.",
  );

  // Asignar a la compañera. Se registra lo que ofrece el campo y se exige al
  // final, para que un campo vacío no oculte el resto del recorrido.
  await control(page, /Asignar a/).click();
  const assigneeOption = control(page, assignee);
  let assigned = false;
  // El menú abre con una animación: sus opciones no tienen nombre ni se ven
  // hasta terminarla, e `isVisible` no espera.
  if (
    await assigneeOption
      .waitFor({ state: "visible", timeout: 10_000 })
      .then(() => true)
      .catch(() => false)
  ) {
    await assigneeOption.click();
    await expect(notice(page, new RegExp(escapeRegExp(assignee)))).toBeVisible();
    assigned = true;
  } else {
    await frame("asignar-opciones");
    const menu = await page
      .locator("body")
      .ariaSnapshot({ timeout: 10_000 })
      .catch((error) => `sin árbol: ${error}`);
    writeFileSync(`${framesDir}/asignar-opciones-arbol.txt`, `${menu}\n`);
    await page.keyboard.press("Escape");
  }
  evidence.push(
    `asignar=${assigned ? "companera_elegida" : "companera_ausente"} directorio=${directory} ` +
      `llamadas_antes=${directoryCallsBeforeForm} llamadas_despues=${directoryCalls} consola=${consoleCount}` +
      (appLog.length ? ` log=${appLog.join(" / ")}` : ""),
  );

  const chooser = page.waitForEvent("filechooser");
  await control(page, "Agregar archivo").click();
  await (await chooser).setFiles([
    { name: "pastilla-trasera.png", mimeType: "image/png", buffer: png(160, 120, [196, 120, 64]) },
    { name: "rotor-delantero.png", mimeType: "image/png", buffer: png(160, 120, [96, 128, 168]) },
  ]);
  await expect(page.getByText("Adjuntos (2)", { exact: true })).toBeVisible();
  await expect(page.getByText("Pendiente", { exact: true })).toHaveCount(2);
  evidence.push("elegidos=2_pendientes");
  await themedFrames("nueva-tarea-con-pendientes", true);

  // 4. Storage caído al guardar: la tarea queda, los archivos siguen pendientes.
  await storage("stop");
  const created = page.waitForResponse((response) =>
    response.url().includes("/rpc/smart_task_create_v1"),
  );
  const failedUpload = storageOutcome(page, "POST");
  await control(page, "Guardar").click();
  expect((await created).status()).toBe(200);
  const uploadOutcome = await failedUpload;
  expect(uploadOutcome).not.toBe("HTTP 200");
  await expect(control(page, "Guardar")).toBeVisible({ timeout: 60_000 });
  await expect(page.getByText("Pendiente", { exact: true })).toHaveCount(2);
  await expect(
    notice(page, /La tarea quedó guardada, pero 2 archivos no se subieron\. Pulsa Guardar para reintentar\./),
  ).toBeVisible();
  await expect(page.getByText(/StorageException/)).toHaveCount(0);
  evidence.push(
    `guardar_sin_storage=tarea_200 subida_${uploadOutcome.replace(" ", "_")} ` +
      "2_pendientes aviso_en_dialogo",
  );
  await themedFrames("subida-fallida");

  // Cerrar con pendientes pregunta; «Seguir aquí» conserva el formulario.
  await control(page, "Cancelar").click();
  await expect(page.getByText("La tarea ya quedó guardada", { exact: true })).toBeVisible();
  await themedFrames("cerrar-con-pendientes");
  await control(page, "Seguir aquí").click();
  await expect(page.getByText("Pendiente", { exact: true })).toHaveCount(2);

  // 5. Storage vuelve: «Guardar» reintenta los pendientes y cierra.
  await storage("start");
  const retriedUpload = storageOutcome(page, "POST");
  await control(page, "Guardar").click();
  expect(await retriedUpload).toBe("HTTP 200");
  await expect(page.getByText("Nueva Tarea", { exact: true })).toHaveCount(0, {
    timeout: 90_000,
  });
  await expect(
    page.getByRole("button", { name: new RegExp(`^${escapeRegExp(title)}`) }),
  ).toBeVisible();
  evidence.push("reintento=subida_HTTP_200_y_cerrado");
  await themedFrames("lista-con-adjuntos", true);

  // 6. Reabre la tarea desde su celda de adjuntos.
  const attachmentsCell = page.locator('[aria-label*="Ver 2 adjuntos"]').first();
  if (await attachmentsCell.count()) {
    await attachmentsCell.click();
  } else {
    await control(page, "Acciones").click();
    await control(page, "Editar").click();
  }
  await expect(page.getByText("Editar Tarea", { exact: true })).toBeVisible();
  await expect(page.getByText("Adjuntos (2)", { exact: true })).toBeVisible();
  await expect(page.getByText("Pendiente", { exact: true })).toHaveCount(0);
  evidence.push("reabierta=2_subidos");
  await themedFrames("tarea-con-adjuntos", true);

  // Salida tras fallo: un tercer archivo no sube y el mecánico sale sin él.
  const thirdChooser = page.waitForEvent("filechooser");
  await control(page, "Agregar archivo").click();
  await (await thirdChooser).setFiles([
    { name: "cadena-estirada.png", mimeType: "image/png", buffer: png(160, 120, [120, 150, 96]) },
  ]);
  await expect(page.getByText("Pendiente", { exact: true })).toHaveCount(1);
  await storage("stop");
  const abandonedUpload = storageOutcome(page, "POST");
  await control(page, "Actualizar").click();
  expect(await abandonedUpload).not.toBe("HTTP 200");
  await expect(control(page, "Actualizar")).toBeVisible({ timeout: 60_000 });
  await expect(
    notice(page, /1 archivo no se subió\. Pulsa Actualizar para reintentar\./),
  ).toBeVisible();
  await control(page, "Cancelar").click();
  await expect(page.getByText("La tarea ya quedó guardada", { exact: true })).toBeVisible();
  await expect(page.getByText(/Queda 1 archivo sin adjuntar/)).toBeVisible();
  await themedFrames("salida-tras-fallo");
  await control(page, "Cerrar sin adjuntar").click();
  await expect(page.getByText("Editar Tarea", { exact: true })).toHaveCount(0, {
    timeout: 30_000,
  });
  await storage("start");
  evidence.push("salida_tras_fallo=cerrado_sin_el_tercero");

  const reopened = page.locator('[aria-label*="Ver 2 adjuntos"]').first();
  if (await reopened.count()) {
    await reopened.click();
  } else {
    await control(page, "Acciones").click();
    await control(page, "Editar").click();
  }
  await expect(page.getByText("Editar Tarea", { exact: true })).toBeVisible();
  await expect(page.getByText("Adjuntos (2)", { exact: true })).toBeVisible();
  await expect(page.getByText("cadena-estirada.png", { exact: true })).toHaveCount(0);

  // 7. Abre el adjunto por su URL firmada: el visor trae los bytes privados.
  const signed = page.waitForResponse(
    (response) =>
      response.url().includes("/storage/v1/object/sign/task-attachments/") &&
      response.request().method() === "POST",
  );
  const served = page.waitForResponse(
    (response) =>
      response.url().includes("/storage/v1/object/sign/task-attachments/") &&
      response.request().method() === "GET",
  );
  await page.getByRole("button", { name: "Abrir adjunto" }).first().click();
  expect((await signed).status()).toBe(200);
  expect((await served).status()).toBe(200);
  await expect(page.getByRole("button", { name: "Acercar" })).toBeVisible();
  await page.waitForTimeout(1_000);
  evidence.push("abrir=firma_200_bytes_200_visor");
  await themedFrames("visor-adjunto");
  await control(page.getByRole("dialog").last(), "Cerrar").click();
  await expect(page.getByText("Editar Tarea", { exact: true })).toBeVisible();

  // 8. Quita uno con Storage arriba: vínculo y bytes fuera, sin aviso.
  await page.getByRole("button", { name: "Quitar adjunto" }).first().click();
  await expect(page.getByText("¿Eliminar adjunto?", { exact: true })).toBeVisible();
  const removedBytes = storageOutcome(page, "DELETE");
  const acknowledgedNow = page.waitForResponse((response) =>
    response.url().includes("/rpc/smart_task_attachment_ack_cleanup_v1"),
  );
  await control(page, "Eliminar").click();
  expect(await removedBytes).toBe("HTTP 200");
  expect((await acknowledgedNow).status()).toBe(200);
  await expect(page.getByText("Adjuntos (1)", { exact: true })).toBeVisible({ timeout: 60_000 });
  evidence.push("quitar=bytes_HTTP_200_acuse_200");

  // 9. Quita el otro con Storage caído: sale de la tarea, limpieza pendiente.
  await storage("stop");
  await page.getByRole("button", { name: "Quitar adjunto" }).first().click();
  const blockedBytes = storageOutcome(page, "DELETE");
  await control(page, "Eliminar").click();
  expect(await blockedBytes).not.toBe("HTTP 200");
  await expect(page.getByText("Sin archivos adjuntos", { exact: true })).toBeVisible({
    timeout: 60_000,
  });
  await expect(
    notice(page, /Archivo retirado de la tarea\. La limpieza pendiente se retomará al iniciar sesión\./),
  ).toBeVisible();
  evidence.push("quitar_sin_storage=oculto aviso_en_dialogo");
  await themedFrames("limpieza-pendiente");
  // La X del diálogo tiene nombre: «Cerrar».
  await control(page.getByRole("dialog"), "Cerrar").click();
  await expect(page.getByText("Editar Tarea", { exact: true })).toHaveCount(0);

  // 10. Storage vuelve y el empleado entra otra vez: la app retoma la limpieza.
  await storage("start");
  const acknowledged = page.waitForResponse(
    (response) =>
      response.url().includes("/rpc/smart_task_attachment_ack_cleanup_v1") &&
      response.status() === 200,
    { timeout: 120_000 },
  );
  await page.reload();
  await enableFlutterSemantics(page);
  await acknowledged;
  await expect(control(page, /Vista: /)).toBeVisible({ timeout: 60_000 });
  if ((await control(page, /Vista: Tareas$/).count()) === 0) {
    await control(page, /Vista: /).click();
    await control(page, /^\S*\s*Tareas$/).click();
  }
  await expect(
    page.getByRole("button", { name: `Agregar archivo a ${title}`, exact: true }),
  ).toBeVisible({ timeout: 60_000 });
  evidence.push("reentrada=limpieza_acusada_sin_adjuntos");
  await themedFrames("lista-tras-limpieza");

  console.log(`C1 UI evidencia: ${evidence.join(" | ")} | frames=${frameNumber}`);
  expect(assigned, `el campo «Asignar a» no ofreció a ${assignee}`).toBe(true);
});

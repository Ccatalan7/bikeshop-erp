// C1/C4 en escritorio (PLANS.md, 2026-09-30): el mismo recorrido del taller
// que scripts/e2e/android_workshop_journey.py, en Chrome a 1440 px, con
// lib/main.dart contra Auth, REST y Storage locales y la misma fixture
// (workshop_journey_local_fixture.sql). Lo lanza
// `scripts/e2e/run_android_local_journey.sh --journey workshop --surface web`;
// sin ese script la prueba se salta. La contraseña llega por el entorno y sólo
// se teclea en el login.
//
// Con --hold, si un paso falla, la página queda abierta con su sesión y lee
// órdenes de WORKSHOP_E2E_HOLD_DIR/cmd.js (cuerpo de una función async con
// `page`, `h` y `expect`; la respuesta va a out.txt) hasta recibir `exit`:
// el análogo de explorar la app retenida en Android con android_ui.py.
import { existsSync, mkdirSync, readFileSync, unlinkSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { deflateSync } from "node:zlib";
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
const SERVICE = "Enrayado de rueda";
const TIRE_FITS = "Neumático Maxxis Ardent 29 x 2.25";
const TIRE_WRONG = "Neumático Kenda 27.5 x 2.10";

function required(name: string): string {
  const value = process.env[name];
  if (!value) {
    throw new Error(`Falta ${name}: correr scripts/e2e/run_android_local_journey.sh --surface web`);
  }
  return value;
}

// ── PNG pequeño hecho aquí: una foto de taller no cabe en el repo ───────────
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

function named(name: string | RegExp): RegExp {
  return typeof name === "string"
    ? new RegExp(`^${escapeRegExp(name)}(\\s+${escapeRegExp(name)})?$`)
    : name;
}

// Lo que se toca: botón, opción, pestaña, casilla o fila con nombre.
function control(scope: Page | Locator, name: string | RegExp): Locator {
  const options = { name: named(name) };
  return scope
    .getByRole("button", options)
    .or(scope.getByRole("menuitem", options))
    .or(scope.getByRole("option", options))
    .or(scope.getByRole("radio", options))
    .or(scope.getByRole("tab", options))
    .or(scope.getByRole("checkbox", options))
    .or(scope.getByRole("menuitemcheckbox", options))
    .or(scope.getByRole("link", options))
    .first();
}

// Texto visible o anunciado por la semántica.
// Un aviso o una fila con nombre también llegan como `group` en Flutter web.
function notice(scope: Page | Locator, text: string | RegExp): Locator {
  const pattern = typeof text === "string" ? new RegExp(escapeRegExp(text)) : text;
  return scope
    .getByText(pattern)
    .or(scope.getByLabel(pattern))
    .or(scope.getByRole("group", { name: pattern }))
    .first();
}

function field(scope: Page | Locator, label: string | RegExp): Locator {
  const pattern = typeof label === "string" ? new RegExp(`${escapeRegExp(label)}$`) : label;
  return scope.getByRole("textbox", { name: pattern }).first();
}

// Flutter web monta el campo editable al tomar el foco: teclear antes pierde
// la primera letra. Se espera el foco y se comprueba lo escrito.
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

test("el recorrido del taller, de la bici del modelo a su historial", async ({ page }) => {
  test.skip(!enabled, "Sólo con scripts/e2e/run_android_local_journey.sh --surface web");
  const holdDir = process.env.WORKSHOP_E2E_HOLD_DIR ?? "";
  test.setTimeout(holdDir ? 0 : 20 * 60_000);

  const framesDir = required("WORKSHOP_E2E_FRAMES_DIR");
  const customer = required("WORKSHOP_E2E_CUSTOMER");
  const brand = required("WORKSHOP_E2E_BRAND");
  const model = required("WORKSHOP_E2E_MODEL");
  const coworker = required("WORKSHOP_E2E_COWORKER");
  mkdirSync(framesDir, { recursive: true });
  let frameNumber = 0;
  let onLogin = true;

  async function semantics(name: string) {
    if (onLogin) return;
    writeFileSync(
      `${framesDir}/${String(frameNumber).padStart(2, "0")}-${name}-semantica.txt`,
      `${page.url()}\n${await tree(page)}\n`,
    );
  }

  // Claro y oscuro del mismo estado: la app sigue al sistema («Sistema»).
  async function themed(name: string) {
    if (onLogin) throw new Error("no se capturan frames del login");
    frameNumber += 1;
    await semantics(name);
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

  const h = { control, notice, field, type, tree, themed, semantics, escapeRegExp, evidence };

  async function journey() {
    // 1. Entra el mecánico por el login real; tema «Sistema».
    await page.goto("/login");
    await enableFlutterSemantics(page);
    await type(page, page.getByLabel("Correo Electrónico", { exact: true }),
      required("WORKSHOP_E2E_EMAIL"));
    await type(page, page.getByLabel("Contraseña", { exact: true }),
      required("WORKSHOP_E2E_PASSWORD"), false);
    await control(page, "Iniciar Sesión").click();
    await expect(page).not.toHaveURL(/\/login/, { timeout: 60_000 });
    onLogin = false;
    evidence.push("login=ok");
    await control(page, "Configuración rápida").click();
    await control(page, "Sistema").click();
    await expect(page.getByRole("radio", { name: "Sistema" })).toBeChecked();
    await control(page.getByRole("dialog"), "Cerrar").click();
    evidence.push("tema=sistema");

    // 2. Trabajo nuevo; la bici nace del modelo del catálogo (criterio 1).
    await page.goto("/taller/pegas/nueva");
    await enableFlutterSemantics(page);
    await control(page, /Seleccionar cliente/).click();
    await page.getByRole("group", { name: new RegExp(`^${escapeRegExp(customer)}`) }).click();
    await expect(control(page, new RegExp(`^Cliente ${escapeRegExp(customer)}`))).toBeVisible();
    evidence.push("clienta=elegida");

    // En escritorio el editor de la bici es un diálogo con pestañas por
    // sección; el mapa técnico elige el sistema.
    await control(page, /Bicicleta \* Seleccione/).click();
    await control(page, "Nueva bicicleta").click();
    await type(page, field(page, "Marca *"), brand.slice(0, 3));
    await control(page, brand).click();
    await type(page, field(page, "Modelo *"), model.slice(0, 3));
    await control(page, model).click();
    await control(page, "Buscar").click();
    await control(page, `${brand} ${model} (2024)`).click();
    await expect(notice(page, /Trajo \d+ datos sin confirmar/)).toBeVisible();
    // El aro que copió el modelo dice de dónde viene.
    await expect(control(page, /^Aro 29/)).toBeVisible();
    await expect(notice(page, `Del modelo ${brand} ${model} 2024 · sin confirmar`)).toBeVisible();
    await themed("bici-desde-el-modelo");
    evidence.push("bici=del_modelo");
    // Sin familia de pedalier la bici no se guarda.
    await control(page, "Ficha Técnica").click();
    await control(page, "Pedalier / BB").click();
    await control(page, "Familia pedalier / BB").click();
    await control(page, "BSA roscado").click();
    await control(page, "Siguiente").click();
    await control(page, "Guardar").click();
    await expect(control(page, new RegExp(`Bicicleta \\* ${escapeRegExp(`${brand} ${model}`)}`)))
      .toBeVisible({ timeout: 60_000 });
    evidence.push("bici=guardada");

    // 3. El diagnóstico sale de la ficha (criterios 2 y 4): freno de disco,
    // el freno tiene rotor y el rotor se mide.
    await control(page, "Diagnóstico").click();
    await control(page, /^Mapa de la bicicleta/).click();
    await control(page, "Freno delantero").click();
    await control(page, /^Rotor Sin revisar/).click();
    await expect(field(page, "Medicion rotor delantero (mm)")).toBeVisible();
    await themed("diagnostico-segun-la-ficha");
    evidence.push("diagnostico=rotor_por_disco");

    // 4. Servicio y repuestos con lo que la ficha ya sabe.
    const search = async (query: string) => {
      await field(page, /^Agregar repuesto o parte/).click();
      await expect(notice(page, "Motor de compatibilidad")).toBeVisible();
      await page.keyboard.type(query);
      await page.waitForTimeout(1_500);
    };
    const side = async (which: string, verdict: RegExp) => {
      await control(page, /Sin fijar lado$/).click();
      await page.getByRole("menuitemcheckbox", { name: which, exact: true }).click();
      await expect(notice(page, verdict)).toBeVisible();
    };
    await control(page, /^Productos y servicios$/i).click();
    await search("Enrayado");
    await control(page, new RegExp(`^${escapeRegExp(SERVICE)} SKU`)).click();
    await control(page, /Falta: Cantidad de rayos/).click();
    await control(page, "Trasera").click();
    // El freno lo trae la ficha: el asistente no lo pregunta en blanco.
    await expect(control(page, "Disco hidráulico")).toBeVisible();
    await themed("asistente-con-lo-que-sabe-la-ficha");
    await control(page, "Selecciona una opción").click();
    await control(page, "28").click();
    await control(page, "Aplicar").click();
    await expect(notice(page, /Cantidad de rayos \/ hoyos: 28/)).toBeVisible();
    evidence.push("enrayado_trasero=28H");

    await search("Ardent");
    await control(page, new RegExp(`^${escapeRegExp(TIRE_FITS)} SKU`)).click();
    await side("Trasero", /La ficha lo anota al terminar: rueda trasera 622/);
    evidence.push("neumatico_29=trasero");

    await search("Kenda");
    await expect(notice(page, /Agregar: "Kenda"/)).toBeVisible();
    await expect(control(page, new RegExp(`^${escapeRegExp(TIRE_WRONG)} SKU`))).toHaveCount(0);
    await themed("buscador-solo-compatibles");
    await control(page, "Mostrar todo").click();
    await expect(control(page, new RegExp(`^${escapeRegExp(TIRE_WRONG)} SKU: No compatible`)))
      .toBeVisible();
    await themed("buscador-mostrar-todo");
    await control(page, new RegExp(`^${escapeRegExp(TIRE_WRONG)} SKU`)).click();
    await side("Delantero", /No calza con el aro 29/);
    await themed("lineas-del-trabajo");
    evidence.push("neumatico_27_5=delantero_no_calza");

    await control(page, "Guardar").click();
    const row = page.getByRole("button", { name: /^PG-\d+ \d\d\/\d\d\/\d\d$/ });
    await expect(row).toBeVisible({ timeout: 60_000 });
    const jobNumber = /PG-\d+/.exec((await row.textContent()) ?? "")?.[0];
    if (!jobNumber) throw new Error("sin número de trabajo en la fila");
    evidence.push(`trabajo=${jobNumber}`);

    // 5. Presupuesto aprobado y facturado; los avisos con acción se van solos.
    const statusButton = control(page, /^Cambiar estado y ver acciones/);
    // El aviso dura 4-8 s: se lo espera desde antes de la acción que lo pide.
    const goesAway = async (text: RegExp, name: string, action: () => Promise<void>) => {
      const shown = notice(page, text)
        .waitFor({ state: "visible", timeout: 20_000 })
        .then(() => true)
        .catch(() => false);
      await action();
      if (!(await shown)) throw new Error(`no apareció el aviso «${name}»`);
      await expect(notice(page, text)).toHaveCount(0, { timeout: 20_000 });
      evidence.push(`aviso_${name}=se_fue_solo`);
    };
    // Por si un clic vuelve a caer en la celda «Detalles» (ver scrollTable):
    // su editor se cierra tocando afuera, como pide, y queda anotado.
    const strayDetails = async () => {
      const editor = page.getByRole("textbox", { name: /Ingresa el diagnóstico/ });
      // Aparece un instante después de que la fila se redibuja.
      const opened = await editor
        .waitFor({ state: "visible", timeout: 4_000 })
        .then(() => true)
        .catch(() => false);
      if (!opened) return;
      await page.mouse.click(700, 700);
      await expect(editor).toHaveCount(0);
      evidence.push("editor_detalles=abierto_sin_tocarlo");
    };
    // Mientras ese editor está abierto, lo demás sale del árbol: el aviso de
    // aprobado podría no verse. Se exige que no quede (en teléfono se vio irse).
    const approved = notice(page, /Presupuesto aprobado\. Puedes facturarlo/);
    const approvedSeen = approved
      .waitFor({ state: "visible", timeout: 10_000 })
      .then(() => true)
      .catch(() => false);
    await statusButton.click();
    await control(page, "Aprobado").click();
    await expect(control(page, /^Cambiar estado y ver acciones .*Presupuesto Aprobado$/)).toBeVisible();
    await strayDetails();
    await expect(approved).toHaveCount(0, { timeout: 20_000 });
    evidence.push(`aviso_aprobado=${(await approvedSeen) ? "se_fue_solo" : "no_queda"}`);
    // La columna «Factura» queda fuera del ancho visible, y su nodo semántico
    // no sigue el desplazamiento horizontal de la tabla: sin desplazarla, el
    // clic del menú caía sobre la celda «Detalles» y abría su editor
    // (2026-09-30). Se desplaza con la rueda, como una persona.
    const scrollTable = async (dx: number) => {
      await page.mouse.move(800, 400);
      await page.mouse.wheel(dx, 0);
      await page.waitForTimeout(800);
    };
    await scrollTable(900);
    await control(page, /^Descargar o ver más acciones de presupuesto/).click();
    await control(page, /Facturar presupuesto/).click();
    await goesAway(/fue facturado conservando/, "facturado", async () => {
      await control(page, "Crear factura").click();
    });
    await scrollTable(-900);
    evidence.push("presupuesto=aprobado_y_facturado");

    // 6. El encargo con /tarea, sobre la línea del Enrayado.
    await page.keyboard.type("/tarea");
    await page.keyboard.press("Enter");
    await control(page, new RegExp(`^\\w{1,3} ${escapeRegExp(coworker)}`)).click();
    await control(page, new RegExp(`^#${jobNumber}\\b`)).click();
    await control(page, /^Hacer el trabajo/).click();
    await expect(page.getByRole("group", {
      name: new RegExp(`^${escapeRegExp(SERVICE)} .*Cantidad de rayos / hoyos: 28`),
    })).toBeVisible();
    await themed("encargo-sobre-la-linea");
    await control(page, "Crear tarea").click();
    await control(page, "Ver la tarea").click();
    await expect(page.getByRole("group", {
      name: new RegExp(`^TRABAJO #${jobNumber} 0 de 1 servicios hechos ${escapeRegExp(SERVICE)}`),
    })).toBeVisible();
    await themed("tarea-ligada-a-la-linea");
    evidence.push("encargo=a_la_companera_sobre_la_linea");
    // La × del panel tiene nombre desde el 2026-09-30. Su caja semántica no
    // coincidía con el dibujo (el clic abrió el menú de espacios de trabajo):
    // se anota dónde está y el panel se cierra con su botón del riel.
    const closePanel = page.getByRole("button", { name: "Cerrar Tareas", exact: true });
    await expect(closePanel).toHaveCount(1);
    const closeBox = await closePanel.boundingBox();
    evidence.push(`cerrar_tareas=nombrado@${Math.round(closeBox?.x ?? -1)},${Math.round(closeBox?.y ?? -1)}`);
    await control(page, "Tareas, herramienta").click();
    await expect(page.getByRole("button", { name: "Conversar sobre esta tarea" })).toHaveCount(0);

    // 7. La foto en la tarea, y el visor en oscuro.
    await control(page, /Vista: /).click();
    await control(page, /^\S*\s*Tareas$/).click();
    await control(page, /^Agregar archivo a Hacer el trabajo/).click();
    await expect(page.getByText("Editar Tarea", { exact: true })).toBeVisible();
    await type(page, field(page, "Descripción (Opcional)"), "Foto de la rueda antes de armar.");
    const chooser = page.waitForEvent("filechooser");
    await control(page, "Agregar archivo").click();
    await (await chooser).setFiles([
      { name: "rueda-trasera.png", mimeType: "image/png", buffer: png(160, 120, [84, 140, 120]) },
    ]);
    await expect(notice(page, "Adjuntos (1)")).toBeVisible();
    await control(page, "Actualizar").click();
    await expect(page.getByText("Editar Tarea", { exact: true })).toHaveCount(0, { timeout: 120_000 });
    await control(page, "Ver adjunto").click();
    await control(page, "Abrir adjunto").click();
    await expect(control(page.getByRole("dialog"), "Alejar")).toBeVisible({ timeout: 60_000 });
    await page.waitForTimeout(1_000);
    await themed("visor-de-la-foto");
    await page.getByRole("dialog").getByRole("button", { name: "Cerrar", exact: true }).click();
    await control(page, "Cancelar").click();
    evidence.push("foto=subida_y_vista");

    // 8. Cierre rechazado y corregido desde «Revisar líneas».
    await control(page, /Vista: /).click();
    await control(page, /^\S*\s*Tabla$/).click();
    const status = async (target: string) => {
      await statusButton.click();
      await control(page, new RegExp(`^Cambiar estado a ${target}`)).click();
    };
    await status("En Curso");
    await expect(control(page, /^Cambiar estado y ver acciones EN CURSO/)).toBeVisible();
    await status("Finalizado");
    await expect(notice(page, /sin cerrar/)).toBeVisible({ timeout: 60_000 });
    await expect(notice(page, new RegExp(`«${escapeRegExp(TIRE_WRONG)}» dice 584`))).toBeVisible();
    await themed("cierre-rechazado");
    evidence.push("cierre=rechazado_por_neumatico_que_no_calza");
    await control(page, "Revisar líneas").click();
    await control(page, new RegExp(`^Acciones de Línea \\d+, ${escapeRegExp(TIRE_WRONG)}`)).click();
    await control(page, "Cambiar por otro artículo").click();
    await field(page, "Buscar por nombre...").click();
    await expect(notice(page, "Motor de compatibilidad")).toBeVisible();
    await page.keyboard.type("Ardent");
    await control(page, new RegExp(`^${escapeRegExp(TIRE_FITS)} SKU`)).click();
    await side("Delantero", /La ficha lo anota al terminar: rueda delantera 622/);
    await themed("linea-corregida");
    await control(page, "Guardar").click();
    await status("Finalizado");
    await expect(control(page, /^Cambiar estado y ver acciones FINALIZADO/))
      .toBeVisible({ timeout: 60_000 });
    await themed("trabajo-terminado");
    evidence.push("cierre=terminado_tras_corregir");

    // 9. La ficha y el historial (criterios 5, 6 y 7).
    await control(page, `${brand} ${model} 2024`).click();
    await control(page, "Ficha Técnica").click();
    await control(page, "Rueda trasera").click();
    await expect(control(page, /^Llanta \(BSD\) 622/)).toBeVisible();
    await expect(notice(page, "Instalado en un trabajo terminado · sin confirmar")).toBeVisible();
    await themed("ficha-rueda-trasera");
    evidence.push("ficha=bsd_trasero_del_trabajo_sin_confirmar");
    await control(page, "Cerrar editor").click();
    await control(page, new RegExp(`^${escapeRegExp(customer)}`)).click();
    await page.getByRole("group", { name: new RegExp(`^${escapeRegExp(`${brand} ${model}`)} 2024`) })
      .click();
    await page.getByRole("tabpanel").getByRole("button", { name: /^Ficha Técnica/ }).click();
    await expect(notice(page, /^32 \/ 28$/)).toBeVisible();
    await expect(notice(page, /^622 \(29″\/700c\)$/)).toBeVisible();
    await themed("ficha-tecnica-resumen");
    evidence.push("resumen=rayos_32_28_bsd_622");
    await page.getByRole("tabpanel").getByRole("button", { name: /^Historial$/ }).click();
    await control(page, /^Rueda trasera$/).click();
    // La memoria de la rueda trasera nombra el Enrayado (el texto trae
    // saltos de línea: `.` no los cruza).
    await expect(notice(page, new RegExp(`Activo: Rueda trasera[\\s\\S]*${escapeRegExp(SERVICE)}`)))
      .toBeVisible();
    await themed("historial-rueda-trasera");
    evidence.push("historial=enrayado_en_la_rueda_trasera");
  }

  try {
    await journey();
    console.log(`C1/C4 escritorio evidencia: ${evidence.join(" | ")} | estados=${frameNumber}`);
  } catch (error) {
    console.log(`C1/C4 escritorio evidencia hasta el fallo: ${evidence.join(" | ")}`);
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

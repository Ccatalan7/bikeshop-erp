import {
  defaultWhatsAppTemplates,
  reviewRequestV2TemplateName,
  workshopNoticeClaimUrl,
  workshopNoticeFooter,
  workshopNoticeTemplateNames,
  workshopNoticeV2TemplateNames,
} from "./whatsapp_templates.ts";

function assert(condition: unknown, message: string): asserts condition {
  if (!condition) throw new Error(message);
}

const migration = await Deno.readTextFile(
  new URL("../../migrations/20261105130000_workshop_customer_notices.sql", import.meta.url),
);

// La base manda estos avisos con el texto aprobado escrito a mano: si el
// catálogo y la migración dejaran de decir lo mismo, la bandeja guardaría un
// texto que el cliente nunca recibió.
Deno.test("the text the database writes is the approved body of each workshop template", () => {
  for (const name of workshopNoticeTemplateNames) {
    const template = defaultWhatsAppTemplates.find((item) => item.name === name);
    assert(template, `${name} is in the catalog`);
    assert(
      template.category === "UTILITY" && template.language === "es_CL",
      `${name} is a utility template in es_CL`,
    );
    const asFormat = template.body.replace(/\{\{\d+\}\}/g, "%s");
    assert(migration.includes(`'${asFormat}'`), `${name}: the migration writes «${asFormat}»`);
    const parameters = new Set(template.body.match(/\{\{\d+\}\}/g) ?? []);
    assert(parameters.size === template.examples.length, `${name}: one example per parameter`);
    assert(
      !/^\{\{\d+\}\}|\{\{\d+\}\}$/.test(template.body),
      `${name}: Meta refuses a body that starts or ends with a parameter`,
    );
    assert(migration.includes(`'${name}'`), `${name} is the template the database picks`);
  }
});

Deno.test("the older templates the database falls back to keep their approved text", () => {
  for (const name of ["seguimiento_presupuesto_bicicleta", "bicicleta_lista_retiro"]) {
    const template = defaultWhatsAppTemplates.find((item) => item.name === name);
    assert(template, `${name} is in the catalog`);
    const asFormat = template.body.replace(/\{\{\d+\}\}/g, "%s");
    assert(migration.includes(`'${asFormat}'`), `${name}: the migration writes «${asFormat}»`);
  }
});

const withButtons = await Deno.readTextFile(
  new URL("../../migrations/20261107120000_workshop_notices_with_buttons.sql", import.meta.url),
);

// Las plantillas con botón (20261107120000): la base escribe el mismo cuerpo
// que Meta aprueba, sin el link, y manda el código o el lugar de Google como
// sufijo del botón. Si dejaran de calzar, el cliente vería un texto y la
// bandeja otro.
Deno.test("the button notices write their approved body and carry a link button", () => {
  for (const name of [...workshopNoticeV2TemplateNames, reviewRequestV2TemplateName]) {
    const template = defaultWhatsAppTemplates.find((item) => item.name === name);
    assert(template, `${name} is in the catalog`);
    assert(
      template.category === "UTILITY" && template.language === "es_CL",
      `${name} is a utility template in es_CL`,
    );
    const asFormat = template.body.replace(/\{\{\d+\}\}/g, "%s");
    assert(withButtons.includes(`'${asFormat}'`), `${name}: the migration writes «${asFormat}»`);
    assert(!/https?:\/\//.test(template.body), `${name}: no link in the text`);
    assert(template.footer === workshopNoticeFooter, `${name}: the workshop footer`);
    const buttons = template.buttons ?? [];
    assert(
      buttons.length === 1 && buttons[0].type === "URL" && buttons[0].url.endsWith("{{1}}"),
      `${name}: one link button with its suffix`,
    );
    assert(withButtons.includes(`'${name}'`), `${name} is a template the database picks`);
  }
  for (const name of workshopNoticeV2TemplateNames) {
    const template = defaultWhatsAppTemplates.find((item) => item.name === name)!;
    const button = template.buttons![0] as { url: string };
    assert(button.url === workshopNoticeClaimUrl, `${name}: the button opens the customer's page`);
  }
  const ready = defaultWhatsAppTemplates.find((item) => item.name === "taller_lista_v2")!;
  assert(ready.headerLocation === true, "the ready notice brings the map");
  assert(
    withButtons.includes("'type', 'location', 'location', v_location"),
    "the database sends the map with the ready notice",
  );
});

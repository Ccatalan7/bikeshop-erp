import { defaultWhatsAppTemplates, workshopNoticeTemplateNames } from "./whatsapp_templates.ts";

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

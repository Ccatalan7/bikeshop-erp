import {
  defaultWhatsAppTemplates,
  reviewRequestV2TemplateName,
  workshopDeliveredPdfTemplateName,
  workshopQuotePdfTemplateName,
  workshopNoticeClaimUrl,
  workshopNoticeFooter,
  workshopNoticeTemplateNames,
  workshopNoticeV2TemplateNames,
  workshopReadyV3TemplateName,
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

const withDocuments = await Deno.readTextFile(
  new URL("../../migrations/20261107130000_workshop_notice_documents.sql", import.meta.url),
);

// Las plantillas con el PDF arriba (20261107130000): la base escribe el
// cuerpo aprobado y deja el PDF a la tienda; el presupuesto aprueba con su
// primera respuesta rápida.
Deno.test("the PDF notices write their approved body and leave the PDF to the store", () => {
  for (const name of [workshopQuotePdfTemplateName, workshopDeliveredPdfTemplateName]) {
    const template = defaultWhatsAppTemplates.find((item) => item.name === name);
    assert(template, `${name} is in the catalog`);
    assert(template.header?.serverDocument === "workshop_notice", `${name}: the store draws the PDF`);
    assert(template.header?.format === "DOCUMENT", `${name}: a document header`);
    const asFormat = template.body.replace(/\{\{\d+\}\}/g, "%s");
    assert(withDocuments.includes(`'${asFormat}'`), `${name}: the migration writes «${asFormat}»`);
    assert(!/https?:\/\//.test(template.body), `${name}: no link in the text`);
    assert(template.footer === workshopNoticeFooter, `${name}: the workshop footer`);
    assert(withDocuments.includes(`'${name}'`), `${name} is a template the database picks`);
  }
  const quote = defaultWhatsAppTemplates.find((item) => item.name === workshopQuotePdfTemplateName)!;
  assert(
    quote.buttons?.length === 2 &&
      quote.buttons.every((button) => button.type === "QUICK_REPLY") &&
      quote.buttons[0].type === "QUICK_REPLY" && quote.buttons[0].action === "approve_quote",
    "the quote answers with «Aprobar presupuesto» (the approval) and «Tengo una consulta»",
  );
  assert(
    withDocuments.includes("'actionType', 'approve_quote'"),
    "the database asks the sender for the approval card",
  );
  const delivered = defaultWhatsAppTemplates.find((item) =>
    item.name === workshopDeliveredPdfTemplateName
  )!;
  const button = delivered.buttons?.[0];
  assert(
    delivered.buttons?.length === 1 && button?.type === "URL" && button.url === workshopNoticeClaimUrl,
    "the receipt keeps the account button",
  );
});

const utilityOnly = await Deno.readTextFile(
  new URL("../../migrations/20261107140000_workshop_notices_utility_only.sql", import.meta.url),
);

// «Lista para retirar» con palabras de retiro (20261107140000): Meta dejó la
// `_v2` como MARKETING. La `_v3` lleva lo mismo —mapa, horario y botón— y la
// base escribe su cuerpo aprobado.
Deno.test("the ready notice v3 keeps the map and the button with pickup words", () => {
  const v2 = defaultWhatsAppTemplates.find((item) => item.name === "taller_lista_v2")!;
  const v3 = defaultWhatsAppTemplates.find((item) => item.name === workshopReadyV3TemplateName);
  assert(v3, "taller_lista_v3 is in the catalog");
  assert(v3.category === "UTILITY" && v3.language === "es_CL", "a utility template in es_CL");
  assert(v3.headerLocation === true, "the v3 brings the map");
  assert(!/te esperamos/i.test(v3.body), "no invitation in the text");
  const asFormat = v3.body.replace(/\{\{\d+\}\}/g, "%s");
  assert(utilityOnly.includes(`'${asFormat}'`), `the migration writes «${asFormat}»`);
  assert(utilityOnly.includes("'taller_lista_v3'"), "the database picks the v3");
  assert(
    v3.examples.length === v2.examples.length &&
      v3.examples.every((example, index) => example === v2.examples[index]),
    "the same three parameters as the v2: name, job number and hours",
  );
  assert(v3.footer === workshopNoticeFooter, "the workshop footer");
  const button = v3.buttons?.[0];
  assert(
    v3.buttons?.length === 1 && button?.type === "URL" && button.url === workshopNoticeClaimUrl,
    "the button opens the customer's page",
  );
  assert(
    utilityOnly.includes("coalesce(review.category, 'UTILITY') = 'UTILITY'"),
    "a notice only goes with a template Meta keeps as utility",
  );
});

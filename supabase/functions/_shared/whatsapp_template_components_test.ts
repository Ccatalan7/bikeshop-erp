import {
  buildTemplateCreationComponents,
  defaultWhatsAppTemplates,
  isPlainBodyTemplate,
  type TemplateDefinition,
} from "./whatsapp_templates.ts";

function assert(condition: unknown, message: string): asserts condition {
  if (!condition) throw new Error(message);
}

function assertEquals(actual: unknown, expected: unknown, message = "") {
  const a = JSON.stringify(actual);
  const e = JSON.stringify(expected);
  if (a !== e) throw new Error(`${message} expected ${e}, received ${a}`);
}

const structured: TemplateDefinition = {
  name: "aviso_de_prueba_v1",
  language: "es_CL",
  category: "UTILITY",
  headerText: "Listo para retirar",
  body: "Hola {{1}}, tu trabajo {{2}} está listo.",
  examples: ["Camila", "PG-00671"],
  footer: "Viñabike · Taller de bicicletas",
  buttons: [
    {
      type: "URL",
      text: "Ver mi trabajo",
      url: "https://vinabike.cl/cuenta/vincular#c={{1}}",
      example: "Zq81TfY0LwmR4pXc",
    },
    { type: "QUICK_REPLY", text: "Tengo una consulta" },
  ],
};

Deno.test("a structured template is created with title, footer and buttons", () => {
  assertEquals(buildTemplateCreationComponents(structured), [
    { type: "HEADER", format: "TEXT", text: "Listo para retirar" },
    {
      type: "BODY",
      text: "Hola {{1}}, tu trabajo {{2}} está listo.",
      example: { body_text: [["Camila", "PG-00671"]] },
    },
    { type: "FOOTER", text: "Viñabike · Taller de bicicletas" },
    {
      type: "BUTTONS",
      buttons: [
        {
          type: "URL",
          text: "Ver mi trabajo",
          url: "https://vinabike.cl/cuenta/vincular#c={{1}}",
          example: ["https://vinabike.cl/cuenta/vincular#c=Zq81TfY0LwmR4pXc"],
        },
        { type: "QUICK_REPLY", text: "Tengo una consulta" },
      ],
    },
  ]);
});

Deno.test("a map header and a fixed link need no example", () => {
  const components = buildTemplateCreationComponents({
    ...structured,
    headerText: undefined,
    headerLocation: true,
    buttons: [{ type: "URL", text: "Cómo llegar", url: "https://maps.example/viñabike" }],
  });
  assertEquals(components[0], { type: "HEADER", format: "LOCATION" });
  assertEquals((components[3] as { buttons: unknown[] }).buttons[0], {
    type: "URL",
    text: "Cómo llegar",
    url: "https://maps.example/viñabike",
  });
});

Deno.test("only a plain body can travel as Direct Send text", () => {
  const plain: TemplateDefinition = {
    name: "solo_texto_v1",
    language: "es_CL",
    category: "UTILITY",
    body: "Hola {{1}}.",
    examples: ["Camila"],
  };
  assert(isPlainBodyTemplate(plain), "a body alone is plain");
  assert(!isPlainBodyTemplate(structured), "title, footer and buttons are not");
  assert(!isPlainBodyTemplate({ ...plain, footer: "Viñabike" }), "a footer alone is not");
  assert(!isPlainBodyTemplate({ ...plain, headerLocation: true }), "a map is not");
});

// Lo que Meta rechaza al crear o al enviar, revisado en todo el catálogo
// (límites de la documentación de componentes de plantillas, 2026-11-07).
Deno.test("every template in the catalog stays within Meta's limits", () => {
  for (const template of defaultWhatsAppTemplates) {
    const name = template.name;
    const headers = [template.header, template.headerText, template.headerLocation]
      .filter((value) => value != null && value !== false);
    assert(headers.length <= 1, `${name}: one header at most`);
    if (template.headerText != null) {
      assert(template.headerText.length <= 60, `${name}: title up to 60 characters`);
      assert(!/\{\{\d+\}\}/.test(template.headerText), `${name}: title without parameters`);
    }
    if (template.footer != null) {
      assert(template.footer.length <= 60, `${name}: footer up to 60 characters`);
      assert(!/\{\{\d+\}\}/.test(template.footer), `${name}: footer without parameters`);
    }
    const buttons = template.buttons ?? [];
    assert(buttons.length <= 10, `${name}: up to 10 buttons`);
    assert(
      buttons.filter((button) => button.type === "URL").length <= 2,
      `${name}: up to two link buttons`,
    );
    const kinds = buttons.map((button) => button.type === "QUICK_REPLY" ? "Q" : "O").join("");
    assert(!/Q+O+Q/.test(kinds) && !/O+Q+O/.test(kinds), `${name}: quick replies grouped`);
    for (const button of buttons) {
      assert(button.text.length <= 25, `${name}: «${button.text}» up to 25 characters`);
      if (button.type !== "URL") continue;
      const variables = button.url.match(/\{\{\d+\}\}/g) ?? [];
      assert(variables.length <= 1, `${name}: one parameter per link`);
      if (variables.length === 1) {
        assert(button.url.endsWith("{{1}}"), `${name}: the link parameter goes at the end`);
        assert(
          /^[A-Za-z0-9_-]+$/.test(button.example ?? ""),
          `${name}: the link example needs no percent-encoding`,
        );
      }
    }
  }
});

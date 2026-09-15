import type { AgentAuthority, JsonObject } from "./contracts.ts";
import { createSupabaseAgentToolExecutor } from "./tool_executor.ts";
import { createDefaultAgentToolRegistry, ToolRegistryError } from "./tool_registry.ts";

/// Fase A — la categoría sobrevive a la captura sin que el modelo vea un UUID.
///
/// Lo que estas pruebas defienden es una frontera, no un formato: la identidad
/// de la categoría nace en el inspector, viaja como referencia opaca de un
/// turno, y el UUID sólo existe del lado del servidor. Si alguien la publica
/// al modelo, la acepta desde otro turno, o deja que el modelo contradiga la
/// ficha de un producto exacto, estas pruebas se ponen rojas.

const tenantId = "22222222-2222-4222-8222-222222222222";
const authority: AgentAuthority = {
  userId: "11111111-1111-4111-8111-111111111111",
  tenantId,
  role: "admin",
  permissions: {},
  capabilities: [
    "ai.read.operational",
    "ai.read.sales",
    "ai.read.purchases",
    "ai.read.accounting",
  ],
  authorityFingerprint: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
};

const categoryId = "31313131-3131-4131-8131-313131313131";
const productId = "41414141-4141-4141-8141-414141414141";

function assertEquals(actual: unknown, expected: unknown, message: string): void {
  if (JSON.stringify(actual) !== JSON.stringify(expected)) {
    throw new Error(
      `${message}: ${JSON.stringify(actual)} != ${JSON.stringify(expected)}`,
    );
  }
}

function envelope(items: JsonObject[] = []) {
  return {
    authorityTenantId: tenantId,
    asOf: "2026-08-17T12:00:00Z",
    status: "success",
    items,
    resultCount: items.length,
    hasMore: false,
  };
}

function inspectorRow(overrides: JsonObject = {}): JsonObject {
  return {
    kind: "category",
    entityId: categoryId,
    category: "Cadenas",
    categoryPath: "Componentes / Transmisión / Cadenas",
    technicalFamily: "chain",
    field: null,
    label: null,
    dataType: null,
    unit: null,
    operators: null,
    allowedValues: null,
    productCount: 12,
    populatedCount: 0,
    ...overrides,
  };
}

function draftItem(overrides: JsonObject = {}): JsonObject {
  return {
    catalogItemRef: null,
    categoryRef: null,
    commercialTarget: null,
    description: "Cadena de 10 velocidades",
    quantity: 1,
    unit: "unit",
    technicalPredicates: [],
    preference: null,
    clarification: null,
    clarificationRequired: false,
    clarificationPrompts: [],
    ...overrides,
  };
}

Deno.test("la identidad de categoría sale opaca y nunca como UUID", async () => {
  const executor = createSupabaseAgentToolExecutor({
    rpc(name) {
      if (name !== "assistant_inspect_inventory_schema_v3") {
        throw new Error(`unexpected rpc ${name}`);
      }
      return Promise.resolve(envelope([inspectorRow()]));
    },
  });

  const inspection = await executor.execute(
    {
      id: "inspect",
      name: "inspect_inventory_schema",
      arguments: { query: "cadena 10 velocidades", category: null },
    },
    authority,
    new AbortController().signal,
  );

  assertEquals(inspection.succeeded, true, "la inspección corre");
  assertEquals(
    inspection.outputText.includes(categoryId),
    false,
    "el UUID de la categoría no llega al modelo",
  );
  assertEquals(
    inspection.outputText.includes("categoryRef"),
    true,
    "el modelo recibe una referencia opaca",
  );
  assertEquals(
    inspection.outputText.includes("Componentes / Transmisión / Cadenas"),
    true,
    "la ruta legible sí es visible",
  );
  assertEquals(
    inspection.entityReferences?.map((reference) => reference.kind),
    ["product_category"],
    "la referencia se tipa como categoría",
  );
  assertEquals(
    inspection.entityReferences?.[0].entityId,
    categoryId,
    "el servidor conserva la identidad real",
  );
  assertEquals(
    inspection.entityReferences?.[0].ref === categoryId,
    false,
    "la referencia no es el UUID disfrazado",
  );
});

Deno.test("una fila operativa no finge tener identidad de categoría", async () => {
  const executor = createSupabaseAgentToolExecutor({
    rpc() {
      return Promise.resolve(envelope([
        inspectorRow(),
        inspectorRow({
          kind: "operational_field",
          entityId: null,
          category: "Inventario",
          categoryPath: "Inventario",
          technicalFamily: null,
          field: "stock",
          label: "Stock disponible",
          dataType: "number",
          unit: "unidades",
          operators: "eq,neq,lt,lte,gt,gte,between,in",
          populatedCount: 0,
        }),
      ]));
    },
  });

  const inspection = await executor.execute(
    {
      id: "inspect",
      name: "inspect_inventory_schema",
      arguments: { query: "cadena 10 velocidades", category: null },
    },
    authority,
    new AbortController().signal,
  );

  assertEquals(
    [inspection.succeeded, inspection.failureCode],
    [true, undefined],
    "la inspección corre",
  );
  // «Inventario» no es una categoría del catálogo: no puede recibir una
  // referencia que después alguien use para fijar la familia de una línea.
  assertEquals(
    inspection.entityReferences?.length,
    1,
    "sólo la categoría real publica referencia",
  );
});

Deno.test("una ficha exacta y una categoría del modelo no pueden convivir", () => {
  const registry = createDefaultAgentToolRegistry();
  let rejected = false;
  let feedback = "";
  try {
    registry.validateProviderCalls([{
      id: "prepare",
      name: "prepare_supply_request",
      arguments: {
        items: [draftItem({
          catalogItemRef: "51515151-5151-4151-8151-515151515151",
          categoryRef: "61616161-6161-4161-8161-616161616161",
          commercialTarget: null,
        })],
        profile: "balanced",
      },
    }], authority);
  } catch (error) {
    rejected = error instanceof ToolRegistryError &&
      error.code === "invalid_tool_arguments";
    feedback = error instanceof ToolRegistryError ? error.message : "";
  }
  assertEquals(
    rejected,
    true,
    "con producto exacto la categoría la deriva el servidor, no el modelo",
  );
  assertEquals(
    feedback.includes("con catalogItemRef exacto categoryRef debe ser null"),
    true,
    "el rechazo le dice al proveedor cómo converger",
  );
});

Deno.test("una necesidad general no puede cerrarse eligiendo producto antes de aclarar", () => {
  const registry = createDefaultAgentToolRegistry();
  let feedback = "";
  try {
    registry.validateProviderCalls([{
      id: "prepare-general-need",
      name: "prepare_supply_request",
      arguments: {
        items: [draftItem({
          description: "2 neumáticos aro 29",
          catalogItemRef: "51515151-5151-4151-8151-515151515151",
          clarification: "Falta definir el ancho.",
          clarificationRequired: true,
          clarificationPrompts: [{
            id: "tire_width",
            question: "¿Qué ancho necesitas?",
            inputKind: "number",
            options: [],
            unit: "pulgadas",
            allowUnknown: true,
          }],
        })],
        profile: "balanced",
      },
    }], authority);
  } catch (error) {
    feedback = error instanceof ToolRegistryError ? error.message : "";
  }
  assertEquals(
    feedback.includes("catalogItemRef=null"),
    true,
    "la reparación conserva la necesidad general en vez de escoger un SKU",
  );
});

Deno.test("una opción técnica inválida recibe una corrección accionable", () => {
  const registry = createDefaultAgentToolRegistry();
  let feedback = "";
  try {
    registry.validateProviderCalls([{
      id: "prepare-tire-options",
      name: "prepare_supply_request",
      arguments: {
        items: [draftItem({
          description: "2 neumáticos aro 29",
          clarification: "Falta definir el ancho.",
          clarificationRequired: true,
          clarificationPrompts: [{
            id: "tire_width",
            question: "¿Qué ancho necesitas?",
            inputKind: "single_choice",
            options: [
              { value: "2.25", label: "2.25 pulgadas" },
              { value: "2.40", label: "2.40 pulgadas" },
            ],
            unit: null,
            allowUnknown: true,
          }],
        })],
        profile: "balanced",
      },
    }], authority);
  } catch (error) {
    feedback = error instanceof ToolRegistryError ? error.message : "";
  }
  assertEquals(
    feedback.includes("value debe usar sólo minúsculas, números, guion o guion bajo"),
    true,
    "la medida visible queda en label y el proveedor recibe el formato de value",
  );
});

Deno.test("una línea sin producto puede llevar categoría, y una sin nada también", () => {
  const registry = createDefaultAgentToolRegistry();
  registry.validateProviderCalls([{
    id: "prepare-with-category",
    name: "prepare_supply_request",
    arguments: {
      items: [draftItem({
        categoryRef: "61616161-6161-4161-8161-616161616161",
        commercialTarget: null,
      })],
      profile: "balanced",
    },
  }], authority);
  registry.validateProviderCalls([{
    id: "prepare-without-category",
    name: "prepare_supply_request",
    arguments: { items: [draftItem()], profile: "balanced" },
  }], authority);
});

Deno.test("el borrador rechaza una categoría que no salió de esta ronda", async () => {
  const executor = createSupabaseAgentToolExecutor({
    rpc() {
      return Promise.resolve(envelope());
    },
  });

  // El ejecutor recibe argumentos **ya resueltos**: si el runtime no pudo
  // canjear la referencia, nunca llega hasta acá. Esta prueba fija el otro
  // extremo: un `categoryId` que no es un UUID válido no pasa el mapper.
  const execution = await executor.execute(
    {
      id: "prepare",
      name: "prepare_supply_request",
      arguments: {
        items: [{
          description: "Cadena de 10 velocidades",
          productId: null,
          categoryId: "no-es-un-uuid",
          quantity: 1,
          unit: "unit",
          technicalPredicates: [],
          preference: null,
          clarification: null,
          clarificationRequired: false,
          clarificationPrompts: [],
        }],
        profile: "balanced",
      },
    },
    authority,
    new AbortController().signal,
  );

  assertEquals(execution.succeeded, false, "una categoría no válida no ejecuta");
  assertEquals(
    execution.failureCode,
    "tool_arguments_invalid",
    "y se reporta como argumento inválido, no como fuente caída",
  );
});

Deno.test("el servidor no puede inventar una categoría para una línea que no la pidió", async () => {
  const executor = createSupabaseAgentToolExecutor({
    rpc() {
      return Promise.resolve(envelope([{
        entityId: null,
        lineRef: "line-1",
        description: "Cadena de 10 velocidades",
        productName: null,
        productSku: null,
        identityState: "unresolved",
        // Ni el modelo pidió categoría ni la línea tiene producto del que
        // derivarla: una categoría acá sería una invención del servidor.
        categoryId: categoryId,
        categoryPath: "Componentes / Transmisión / Cadenas",
        technicalFamily: "chain",
        quantity: 1,
        unit: "unit",
        technicalPredicates: [],
        preference: null,
        clarification: null,
        clarificationRequired: false,
        profile: "balanced",
      }]));
    },
  });

  const execution = await executor.execute(
    {
      id: "prepare",
      name: "prepare_supply_request",
      arguments: {
        items: [{
          description: "Cadena de 10 velocidades",
          productId: null,
          categoryId: null,
          quantity: 1,
          unit: "unit",
          technicalPredicates: [],
          preference: null,
          clarification: null,
          clarificationRequired: false,
          clarificationPrompts: [],
        }],
        profile: "balanced",
      },
    },
    authority,
    new AbortController().signal,
  );

  assertEquals(execution.succeeded, false, "la procedencia inventada se rechaza");
});

Deno.test("un producto exacto sí puede traer su categoría derivada", async () => {
  const executor = createSupabaseAgentToolExecutor({
    rpc() {
      return Promise.resolve(envelope([{
        entityId: productId,
        lineRef: "line-1",
        description: "Cadena KMC X10",
        productName: "Cadena KMC X10 116L",
        productSku: "KMC-X10-116",
        identityState: "confirmed",
        // Derivada de la ficha por el servidor, no enviada por el modelo.
        categoryId: categoryId,
        categoryPath: "Componentes / Transmisión / Cadenas",
        technicalFamily: "chain",
        quantity: 1,
        unit: "unit",
        technicalPredicates: [],
        preference: null,
        clarification: null,
        clarificationRequired: false,
        profile: "balanced",
      }]));
    },
  });

  const execution = await executor.execute(
    {
      id: "prepare",
      name: "prepare_supply_request",
      arguments: {
        items: [{
          description: "Cadena KMC X10",
          productId,
          categoryId: null,
          commercialTarget: null,
          quantity: 1,
          unit: "unit",
          technicalPredicates: [],
          preference: null,
          clarification: null,
          clarificationRequired: false,
          clarificationPrompts: [],
        }],
        profile: "balanced",
      },
    },
    authority,
    new AbortController().signal,
  );

  assertEquals(execution.succeeded, true, "la derivación server-side es válida");
  assertEquals(
    execution.result.items[0].categoryId,
    categoryId,
    "la tarjeta cerrada conserva la identidad",
  );
  assertEquals(
    execution.outputText.includes(categoryId),
    false,
    "y el modelo sigue sin ver el UUID",
  );
});

Deno.test("una ruta de categoría sin identidad detrás se rechaza", async () => {
  const executor = createSupabaseAgentToolExecutor({
    rpc() {
      return Promise.resolve(envelope([{
        entityId: null,
        lineRef: "line-1",
        description: "Cadena de 10 velocidades",
        productName: null,
        productSku: null,
        identityState: "unresolved",
        categoryId: null,
        categoryPath: "Componentes / Transmisión / Cadenas",
        technicalFamily: "chain",
        quantity: 1,
        unit: "unit",
        technicalPredicates: [],
        preference: null,
        clarification: null,
        clarificationRequired: false,
        profile: "balanced",
      }]));
    },
  });

  const execution = await executor.execute(
    {
      id: "prepare",
      name: "prepare_supply_request",
      arguments: {
        items: [{
          description: "Cadena de 10 velocidades",
          productId: null,
          categoryId: null,
          quantity: 1,
          unit: "unit",
          technicalPredicates: [],
          preference: null,
          clarification: null,
          clarificationRequired: false,
          clarificationPrompts: [],
        }],
        profile: "balanced",
      },
    },
    authority,
    new AbortController().signal,
  );

  // Una glosa de familia sin identidad que la respalde es una afirmación sin
  // fuente: se rechaza en vez de mostrarse.
  assertEquals(execution.succeeded, false, "ruta sin identidad no pasa");
});

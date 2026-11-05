import {
  dayAndMonth,
  renderWorkshopNotice,
  safeWorkshopLink,
  WorkshopNoticeRenderError,
} from "./workshop_notice_templates.ts";

function assert(condition: unknown, message: string): asserts condition {
  if (!condition) throw new Error(message);
}

const claimLink =
  "https://vinabike.cl/cuenta/vincular#c=AbCdEfGhIjKlMnOpQrStUvWxYz0123456789_-abcde";

const base = {
  link: claimLink,
  linkKind: "claim",
  preferencesLink: "https://vinabike.cl/cuenta/perfil",
  store: {
    name: "Viñabike",
    storeUrl: "https://vinabike.cl",
    brandColor: "#0D3B66",
    timezone: "America/Santiago",
  },
  job: {
    number: "PG-00333",
    customerName: "María José Rojas Pérez",
    item: "Trek Marlin 7",
    intake: "bike",
    request: "Mantención general <y frenos>",
    receivedAt: "2026-11-05T14:00:00Z",
  },
};

Deno.test("the received notice greets by given name, names the bike and links to create the account", () => {
  const email = renderWorkshopNotice({ ...base, kind: "received" });
  assert(email.subject === "Recibimos tu bicicleta · PG-00333", email.subject);
  assert(email.html.includes("Hola María José,"), "compound given name");
  assert(email.html.includes("TRABAJO PG-00333"), "eyebrow");
  assert(email.html.includes("Trek Marlin 7"), "the bike");
  assert(email.html.includes("Recibida"), "received on");
  assert(email.html.includes("5 de noviembre"), "date in the shop's time");
  assert(email.html.includes("Mantención general &lt;y frenos&gt;"), "what was asked, escaped");
  assert(email.html.includes(`href="${claimLink}"`), "claim link");
  assert(email.html.includes("Con tu cuenta ves el estado"), "says what the account gives");
  assert(!email.html.includes("Elige por dónde recibir"), "no preferences link without an account");
  assert(email.text.includes(`Ver el estado: ${claimLink}`), "text part");
});

Deno.test("a customer with an account goes to the portal and can choose the channels", () => {
  const email = renderWorkshopNotice({
    ...base,
    kind: "ready",
    link: "https://vinabike.cl/cuenta/servicios",
    linkKind: "portal",
  });
  assert(email.subject === "Tu bicicleta está lista · PG-00333", email.subject);
  assert(email.html.includes("Puedes pasar a retirarla al taller."), "lead");
  assert(!email.html.includes("Con tu cuenta ves"), "no account pitch to whoever has one");
  assert(email.html.includes("Elige por dónde recibir estos avisos"), "preferences link");
  assert(
    email.text.includes("Elige por dónde recibir estos avisos: https://vinabike.cl/cuenta/perfil"),
    "text",
  );
});

Deno.test("a component job says what was received and never «tu bicicleta»", () => {
  const email = renderWorkshopNotice({
    ...base,
    kind: "ready",
    job: { ...base.job, item: "rueda trasera", intake: "component" },
  });
  assert(email.subject === "Tu trabajo está listo · PG-00333", email.subject);
  assert(email.html.includes("Puedes pasar a retirarlo al taller."), "masculine lead");
  assert(email.html.includes("Rueda trasera"), "the component, capitalized");
  assert(!email.html.includes("bicicleta"), "never a bike");
  const received = renderWorkshopNotice({
    ...base,
    kind: "received",
    job: { ...base.job, item: "rueda trasera", intake: "component" },
  });
  assert(received.subject === "Recibimos tu rueda trasera · PG-00333", received.subject);
});

Deno.test("the quote notice shows the total", () => {
  const email = renderWorkshopNotice({
    ...base,
    kind: "quote_ready",
    job: { ...base.job, total: 45990 },
  });
  assert(email.subject === "Tu presupuesto está listo · PG-00333", email.subject);
  assert(email.html.includes("$45.990"), "total");
  assert(email.html.includes("Ver el presupuesto"), "button");
});

Deno.test("the delivery notice ends with both warranties and the legal line", () => {
  const email = renderWorkshopNotice({
    ...base,
    kind: "delivered",
    delivery: {
      deliveredAt: "2026-11-05T14:50:00Z",
      workPerformed: "Cambio de cadena y ajuste de cambios",
      serviceWarrantyUntil: "2026-11-19T14:50:00Z",
      partsWarrantyUntil: "2027-01-05T14:50:00Z",
    },
  });
  assert(email.subject === "Tu comprobante de entrega · PG-00333", email.subject);
  assert(email.html.includes("Entregamos tu bicicleta el 5 de noviembre."), "lead with the date");
  const work = email.html.indexOf("Trabajo realizado");
  const service = email.html.indexOf("Garantía del servicio");
  const parts = email.html.indexOf("Garantía de repuestos");
  assert(work > 0 && service > work && parts > service, "the warranties go last");
  assert(email.html.includes("Válida hasta el 19 de noviembre"), "service warranty");
  assert(email.html.includes("Válida hasta el 5 de enero"), "parts warranty");
  assert(email.html.includes("Sin perjuicio de la garantía legal (Ley 19.496)."), "legal line");
  assert(email.html.includes("Gracias por confiar en Viñabike."), "closing");
  assert(
    !email.html.includes("Servicio solicitado"),
    "the receipt says what was done, not what was asked",
  );
});

Deno.test("a delivery without its receipt is refused", () => {
  let refused = false;
  try {
    renderWorkshopNotice({ ...base, kind: "delivered" });
  } catch (error) {
    refused = error instanceof WorkshopNoticeRenderError;
  }
  assert(refused, "must refuse");
});

Deno.test("only the portal page or the claim page is a valid link", () => {
  assert(safeWorkshopLink("https://vinabike.cl/cuenta/servicios") !== null, "portal");
  assert(safeWorkshopLink(claimLink) !== null, "claim");
  assert(safeWorkshopLink("http://vinabike.cl/cuenta/servicios") === null, "https only");
  assert(safeWorkshopLink("https://vinabike.cl/cuenta/vincular#c=short") === null, "a real code");
  assert(
    safeWorkshopLink("https://vinabike.cl/cuenta/vincular?c=" + "a".repeat(43)) === null,
    "never in the query",
  );
  assert(
    safeWorkshopLink("https://user:pass@vinabike.cl/cuenta/servicios") === null,
    "no credentials",
  );
  assert(safeWorkshopLink("https://vinabike.cl/otra") === null, "nowhere else");
  let refused = false;
  try {
    renderWorkshopNotice({ ...base, kind: "received", link: "https://evil.example/x" });
  } catch (error) {
    refused = error instanceof WorkshopNoticeRenderError;
  }
  assert(refused, "an unexpected link is refused");
});

Deno.test("dates are read in the shop's time zone", () => {
  assert(
    dayAndMonth("2026-11-06T02:30:00Z", "America/Santiago") === "5 de noviembre",
    "still the 5th in Chile",
  );
  assert(dayAndMonth("nope", "America/Santiago") === "", "an invalid date is empty");
});

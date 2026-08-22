import { assertEquals } from "jsr:@std/assert";
import { providerAttemptErrorCode, ProviderError } from "./provider.ts";
import { providerRejectionReason } from "./http.ts";

// El ledger de intentos decía sólo `provider_rejected`. Con eso, un 401
// (clave), un 404 (modelo) y un 400 (petición inválida) son el mismo hecho y un
// rechazo obliga a reproducirlo para diagnosticarlo. El 2026-08-18 esa
// ambigüedad costó una ronda entera en el Asistente de compras.
Deno.test("a rejected attempt records the upstream status", () => {
  assertEquals(
    providerAttemptErrorCode(new ProviderError("provider_rejected", 401, false)),
    "provider_rejected_401",
  );
  assertEquals(
    providerAttemptErrorCode(new ProviderError("provider_rejected", 404, false)),
    "provider_rejected_404",
  );
});

Deno.test("a typed upstream reason travels with the status", () => {
  assertEquals(
    providerAttemptErrorCode(
      new ProviderError("provider_rejected", 400, false, "INVALID_ARGUMENT"),
    ),
    "provider_rejected_400_INVALID_ARGUMENT",
  );
});

// El control de flujo mira `code`, no esto: los otros códigos no se decoran,
// porque su status es sintético del cliente y no dice nada del upstream.
// El estado HTTP se registra siempre que exista, también en los fallos
// reintentables. Antes sólo se decoraba el rechazo definitivo, y por eso un
// 429 por cuota y un 503 por saturación quedaban indistinguibles en el
// ledger: los dos aparecían como `provider_unavailable` a secas.
Deno.test("every attempt keeps the status it failed with", () => {
  assertEquals(
    providerAttemptErrorCode(new ProviderError("provider_unavailable", 429, true)),
    "provider_unavailable_429",
  );
  assertEquals(
    providerAttemptErrorCode(new ProviderError("provider_unavailable", 503, true)),
    "provider_unavailable_503",
  );
  assertEquals(
    providerAttemptErrorCode(
      new ProviderError("provider_invalid_response", 502, false),
    ),
    "provider_invalid_response_502",
  );
});

// El cuerpo del proveedor no se registra nunca: puede llevar eco del prompt.
// Sólo se rescata el enum de estado, que es un dominio cerrado.
Deno.test("only the closed status enum is rescued from the body", async () => {
  assertEquals(
    await providerRejectionReason(
      new Response(
        JSON.stringify({
          error: {
            status: "INVALID_ARGUMENT",
            message: "necesito 4 camaras 29 con valvula schrader",
          },
        }),
        { status: 400 },
      ),
    ),
    "INVALID_ARGUMENT",
  );
  // Texto libre disfrazado de estado: se descarta.
  assertEquals(
    await providerRejectionReason(
      new Response(
        JSON.stringify({ error: { status: "el taller pidió camaras 29" } }),
        { status: 400 },
      ),
    ),
    undefined,
  );
  assertEquals(
    await providerRejectionReason(new Response("<html>502</html>", { status: 502 })),
    undefined,
  );
});

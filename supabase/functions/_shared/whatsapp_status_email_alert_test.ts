import {
  parseWhatsAppStatusEmailAlertMetadata,
  renderWhatsAppStatusAlertVerificationEmail,
  renderWhatsAppStatusEmail,
  terminalWhatsAppStatus,
  whatsappProviderErrorSummary,
  whatsappStatusAlertIdempotencyKey,
  whatsappStatusOccurredAt,
} from "./whatsapp_status_email_alert.ts";

function assert(condition: unknown, message: string): asserts condition {
  if (!condition) throw new Error(message);
}

const activationId = "9ed86645-4f92-4f45-a7eb-4eb33533f8e0";
const metadata = {
  status_email_alert: {
    active: true,
    activation_id: activationId,
    recipient_email: "vinabikechile@gmail.com",
    contact_name: "José Luis",
    time_zone: "America/Los_Angeles",
    notify_statuses: ["read", "failed", "read"],
  },
};

Deno.test("WhatsApp status email configuration is explicit and preserves a compound given name", () => {
  const config = parseWhatsAppStatusEmailAlertMetadata(metadata);
  assert(config, "configuration was rejected");
  assert(config.contactName === "José Luis", "compound given name changed");
  assert(config.recipientEmail === "vinabikechile@gmail.com", "recipient changed");
  assert(config.notifyStatuses.join(",") === "read,failed", "statuses were not normalized");
  assert(
    whatsappStatusAlertIdempotencyKey(config, "read") ===
      `whatsapp-status-alert/${activationId}/read`,
    "read alert idempotency changed",
  );
});

Deno.test("inactive or malformed WhatsApp status email configuration fails closed", () => {
  assert(parseWhatsAppStatusEmailAlertMetadata({}) === null, "missing config was accepted");
  assert(
    parseWhatsAppStatusEmailAlertMetadata({
      status_email_alert: { ...metadata.status_email_alert, recipient_email: "not-an-email" },
    }) === null,
    "invalid recipient was accepted",
  );
  assert(terminalWhatsAppStatus("delivered") === null, "non-terminal status was accepted");
});

Deno.test("read email uses the provider timestamp in the configured local timezone", () => {
  const config = parseWhatsAppStatusEmailAlertMetadata(metadata);
  assert(config, "configuration was rejected");
  const occurredAt = whatsappStatusOccurredAt({ timestamp: "1786738833" });
  const rendered = renderWhatsAppStatusEmail({ config, status: "read", occurredAt });
  assert(rendered.subject === "José Luis leyó tu mensaje de WhatsApp", "wrong subject");
  assert(rendered.text.includes("José Luis leyó el mensaje"), "wrong read body");
  assert(rendered.text.includes("America/Los_Angeles"), "timezone is not explicit");
  assert(!rendered.text.includes("Campodónico"), "surname leaked into alert");
});

Deno.test("failed email includes only the bounded provider reason", () => {
  const config = parseWhatsAppStatusEmailAlertMetadata(metadata);
  assert(config, "configuration was rejected");
  const payload = {
    errors: [{
      code: 131000,
      title: "Something went wrong",
      error_data: { details: "Retry later" },
    }],
  };
  const providerError = whatsappProviderErrorSummary(payload);
  assert(providerError?.includes("131000"), "provider code is missing");
  const rendered = renderWhatsAppStatusEmail({
    config,
    status: "failed",
    occurredAt: new Date("2026-08-14T21:00:00Z"),
    providerError,
  });
  assert(rendered.text.includes("Something went wrong"), "provider reason is missing");
});

Deno.test("verification email states that the alarm is server-side", () => {
  const config = parseWhatsAppStatusEmailAlertMetadata(metadata);
  assert(config, "configuration was rejected");
  const rendered = renderWhatsAppStatusAlertVerificationEmail(config);
  assert(rendered.subject === "Alerta de lectura de WhatsApp conectada", "wrong subject");
  assert(rendered.text.includes("Supabase"), "server-side ownership is not explicit");
  assert(rendered.text.includes("José Luis"), "contact is missing");
});

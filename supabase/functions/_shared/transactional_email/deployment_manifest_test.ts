import { resendOperationalEmailEvents } from "./types.ts";

function assert(condition: unknown, message: string): asserts condition {
  if (!condition) throw new Error(message);
}

const manifestUrl = new URL(
  "../../../transactional_email_deployment_manifest.json",
  import.meta.url,
);
const migrationUrl = new URL(
  "../../../migrations/20260718230000_prepare_transactional_email_delivery.sql",
  import.meta.url,
);

Deno.test("deployment manifest fixes the reviewed Viñabike sender and starts fail-closed", async () => {
  const manifest = JSON.parse(await Deno.readTextFile(manifestUrl));
  assert(manifest.projectRef === "xzdvtzdqjeyqxnkqprtf", "wrong production project");
  assert(manifest.tenantId === "5443b130-cc28-45af-a420-cd500b288890", "wrong tenant");
  assert(manifest.sender.name === "Ventas Viñabike", "wrong sender name");
  assert(manifest.sender.email === "ventas@vinabike.cl", "wrong sender email");
  assert(manifest.sender.replyTo === "ventas@vinabike.cl", "wrong reply-to");
  assert(manifest.sender.publicStoreUrl === "https://vinabike.cl", "wrong store URL");
  assert(manifest.edgeConfiguration.defaultMode === "dry_run", "Edge default is not dry-run");
  assert(manifest.worker.defaultEnabled === false, "scheduler must start disabled");
  assert(manifest.worker.defaultMode === "dry_run", "scheduler must start in dry-run");
});

Deno.test("manifest, webhook code and required secret names stay aligned", async () => {
  const manifest = JSON.parse(await Deno.readTextFile(manifestUrl));
  assert(
    JSON.stringify(manifest.webhook.events) === JSON.stringify(resendOperationalEmailEvents),
    "Resend subscription events drifted from endpoint handling",
  );
  const edgeSecrets = new Set(manifest.edgeConfiguration.secretNames);
  for (
    const required of [
      "RESEND_API_KEY",
      "RESEND_WEBHOOK_SECRET",
      "TRANSACTIONAL_EMAIL_WORKER_SECRET",
    ]
  ) {
    assert(edgeSecrets.has(required), `missing Edge secret name ${required}`);
  }
  assert(
    manifest.databaseVaultSecretNames.includes("transactional_email_worker_secret"),
    "database scheduler Vault secret is missing",
  );
});

Deno.test("activation migration contains no credential and cannot default to send", async () => {
  const source = await Deno.readTextFile(migrationUrl);
  assert(source.includes("'Ventas Viñabike'"), "sender seed is missing");
  assert(source.includes("'ventas@vinabike.cl'"), "sender address seed is missing");
  assert(source.includes("values (true, false, 'dry_run', 20)"), "runtime is not fail-closed");
  assert(
    source.includes("configure_transactional_email_delivery_phase"),
    "explicit phase gate is missing",
  );
  assert(
    source.includes("from vault.decrypted_secrets"),
    "worker secret is not loaded from Vault",
  );
  assert(!source.includes("whsec_"), "webhook secret value was committed");
  assert(!/\bre_[A-Za-z0-9]{10,}/.test(source), "Resend API key value was committed");
});

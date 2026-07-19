import { assertEquals, assertThrows } from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  AttachmentManifestError,
  validateAttachmentDeliveryPolicy,
} from "./attachment_manifest.ts";

const sha256 = "a".repeat(64);
const issuedAt = "2026-07-18T15:00:00.000Z";
const providerDocumentId = "official-document-1";

function officialArtifact(kind: "payment_voucher" | "tax_document") {
  return [{
    kind,
    url: "https://documents.vinabike.cl/orders/document.pdf?signature=opaque",
    sha256,
    mimeType: "application/pdf",
    providerDocumentId,
    issuedAt,
  }];
}

function officialEvidence() {
  return {
    downloadUrl: "https://documents.vinabike.cl/orders/document.pdf?signature=opaque",
    artifactSha256: sha256,
    providerDocumentId,
    issuedAt,
  };
}

Deno.test("voucher and DTE manifests use link-only delivery in dry-run or send", () => {
  assertEquals(
    validateAttachmentDeliveryPolicy(
      "payment_voucher_available",
      officialArtifact("payment_voucher"),
      {
        officialPaymentVoucher: officialEvidence(),
      },
    ),
    "link_only",
  );

  assertEquals(
    validateAttachmentDeliveryPolicy(
      "tax_document_issued",
      officialArtifact("tax_document"),
      {
        officialTaxDocument: officialEvidence(),
      },
    ),
    "link_only",
  );
});

Deno.test("ordinary messages accept only an empty manifest", () => {
  assertEquals(
    validateAttachmentDeliveryPolicy("order_received", [], {}),
    "none",
  );
  assertEquals(
    validateAttachmentDeliveryPolicy(
      "mercadopago_payment_voucher_available",
      [],
      {},
    ),
    "none",
  );
  assertThrows(
    () =>
      validateAttachmentDeliveryPolicy(
        "order_received",
        officialArtifact("tax_document"),
        {},
      ),
    AttachmentManifestError,
  );
});

Deno.test("unsafe, mismatched or unhashed official artifacts are rejected", () => {
  for (
    const manifest of [
      [{ ...officialArtifact("tax_document")[0], url: "http://documents.test/x.pdf" }],
      [{ ...officialArtifact("tax_document")[0], url: "https://user:pass@documents.test/x.pdf" }],
      [{ ...officialArtifact("tax_document")[0], sha256: "not-a-hash" }],
      [{ ...officialArtifact("tax_document")[0], mimeType: "text/html" }],
      [{ ...officialArtifact("tax_document")[0], providerDocumentId: "other-document" }],
      [{ ...officialArtifact("tax_document")[0], issuedAt: "2026-07-18T16:00:00.000Z" }],
    ]
  ) {
    assertThrows(
      () =>
        validateAttachmentDeliveryPolicy(
          "tax_document_issued",
          manifest,
          {
            officialTaxDocument: officialEvidence(),
          },
        ),
      AttachmentManifestError,
    );
  }
});

import { assert, assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";

Deno.test({
  name: "public orphan deletion is sequenced after private quarantine receipt",
  permissions: { read: true },
  async fn() {
    const source = await Deno.readTextFile(
      new URL("./backfill_private_attachments.ts", import.meta.url),
    );
    const quarantineUpload = source.indexOf(
      "uploadPrivateObject(\n      QUARANTINE_BUCKET",
    );
    const quarantineReceipt = source.indexOf(
      'rpc("finalize_legacy_messaging_orphan_quarantine"',
    );
    const publicDelete = source.indexOf("await deletePublicObjects(");

    assert(quarantineUpload >= 0);
    assert(quarantineReceipt > quarantineUpload);
    assert(publicDelete > quarantineReceipt);
    assert(source.includes("orphan_delete_without_quarantine_receipt"));
  },
});

Deno.test({
  name: "receipts use the no-PII quarantine contract version",
  permissions: { read: true },
  async fn() {
    const source = await Deno.readTextFile(
      new URL("./backfill_private_attachments.ts", import.meta.url),
    );
    assertEquals(source.match(/receipt_version: 2/g)?.length, 3);
    assert(source.includes("contains_paths_or_pii: false"));
    assert(source.includes("private_content_hash_quarantine_before_delete"));
  },
});

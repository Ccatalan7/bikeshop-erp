# WhatsApp Catalog + Commerce Handoff

Date: 2026-06-11  
Repo: `bikeshop-erp`  
Tenant: Viñabike production, `5443b130-cc28-45af-a420-cd500b288890`

## Current Status

**RESOLVED 2026-06-12.** Root cause: customer visibility is gated by Meta's
asynchronous per-product field `capability_to_review_status[WHATSAPP]`, which
must equal `APPROVED`. Catalog upsert success (a returned product id and
`visibility = published`) only places the product in the catalog container;
it does not prove customer visibility. Fresh uploads start `NO_REVIEW` and Meta
approves them asynchronously. So `whatsapp_catalog_sync_status = synced`, a Meta
product ID, `visibility = published`, and Graph `product_count` are NOT proof
that a customer can see the item.

The ERP now reports the real customer-visible state honestly:

- `products.whatsapp_catalog_sync_status` constraint expanded to
  `not_synced, pending, syncing, synced, under_review, customer_visible,
  rejected, removed, failed` (migration
  `20260612190000_whatsapp_catalog_review_aware_status.sql`, DEPLOYED + verified;
  mirrored in `core_schema.sql`). Only `customer_visible` means live-to-customers;
  `under_review` means accepted-but-hidden.
- `whatsapp-catalog-sync` Edge function (DEPLOYED) maps Meta's review status into
  that column and supports `mode:'sync'` (upload/update) and `mode:'refresh'`
  (read-only review re-check, no re-upload). It returns `syncStatus` +
  `whatsappReview`.
- Probe gotcha: the field `whatsapp_product_can_appear_in_search` does NOT exist
  (Graph error 100). Use
  `id,retailer_id,name,availability,visibility,review_status,capability_to_review_status,errors,image_url,url,price,currency`.
- Flutter product form shows an honest status panel + "Re-verificar estado"
  button backed by `WhatsAppCatalogSyncService.refreshStatus()`. Save-time
  success message is review-aware (visible / en revisión / retirado).

Verification 2026-06-12 (refresh mode + DB rows): the seat
`2000000305660` (Meta `26956061997426308`) and N079 (Meta `36596330423313700`)
both now return `syncStatus = customer_visible`, `whatsappReview = APPROVED` —
Meta finished its async review. Rows persisted with fresh `whatsapp_catalog_synced_at`.

### Original symptom (for history)

Meta Graph accepted new catalog product upserts and returned product IDs, but
accepted products did not immediately appear in the customer-facing WhatsApp
catalog. The seat (`a5c79c90-f226-41e7-a2f4-7f1cf12b7291`, retailer
`2000000305660`) was hidden minutes after a `synced` record while Araña ZTTO was
customer-visible despite a `failed` status — proving the old status column
described the last API attempt, not real WhatsApp visibility. The honest-status
model above resolves this.

Latest failed visibility test:

- Product: `Asiento Radical Mountain Paseo N708A Con Resorte Negro`.
- ERP product id: `a5c79c90-f226-41e7-a2f4-7f1cf12b7291`.
- SKU / retailer id: `2000000305660`.
- Database trigger requested sync at `2026-06-12 18:26:43 UTC`.
- Edge Function recorded `synced` at `2026-06-12 18:26:54 UTC`.
- Meta product id returned: `26956061997426308`.
- User screenshot taken at approximately `2026-06-12 11:31 PDT`, about four
  minutes after the recorded sync.
- The seat is absent from the customer-facing WhatsApp catalog screenshot.
- The screenshot shows five older items: camera 27.5, RideXC camera, Vuelta
  tire, Maxxis camera, and Araña ZTTO.
- Important contradiction: Araña ZTTO is customer-visible even though the new
  persistent status currently says `failed` because it lacks a description.
  Therefore the current status column describes the most recent API attempt,
  not actual WhatsApp visibility.

Fresh probe on 2026-06-11:

- Meta Business `751663314343298` (`Vinabike`): `verification_status = pending`.
- WABA `912031294920516` (`Viñabike`): `account_review_status = APPROVED`, `business_verification_status = pending`, `ownership_type = SELF`.
- Phone `1107058485829123`: `whatsapp_commerce_settings` still returns `data: []`.

Business verification for NEWEN SpA has been resubmitted and is under review. Meta UI says it should take about two business days.

## Important IDs

- Business Manager: `751663314343298` (`Vinabike`).
- Meta app: `26325303243793949` (`Viñabike App`).
- System user: `122128515075009168` (`ccatalan`).
- Active WABA: `912031294920516` (`Viñabike`).
- Active phone number id: `1107058485829123`.
- Cloud API display phone: `+56 9 4188 4520`.
- Active ERP channel display name: `Viñabike Oficial`.
- Working WhatsApp catalog: `932738139825582` (`Viñabike Catálogo WhatsApp`).
- Dead/abandoned old UI catalog: `647068650790417`.
- Test product: N079, product id `9eaf3153-6bb8-4e2b-8d2e-69c5ec06c493`, Meta product id `36596330423313700`.

## What Was Done

1. Domain verification completed.
   - `vinabike.cl` was added to Meta Business and verified using Cloudflare DNS.
   - DNS record used: TXT at root with `facebook-domain-verification=...`.
   - Cloudflare is the DNS host, even though the domain was registered through NIC.cl.

2. Business verification was resubmitted.
   - Earlier rejection was caused by trying to verify against a personal phone number.
   - The new submission used the address path because Meta accepts a document containing business phone OR business address.
   - Current state is `pending`, which means the fresh submission is under review.

3. WhatsApp public business profile was updated through the Edge Function helper.
   - Category / vertical: `RETAIL`.
   - About: `Tienda y taller de bicicletas en Viña del Mar.`
   - Description: `Venta, reparación y mantención de bicicletas, repuestos y accesorios en Viña del Mar.`
   - Address: `Álvarez 32, Local 17, Viña del Mar, Chile`.
   - Email: `contacto@vinabike.cl`.
   - Website: `https://vinabike.cl/`.
   - Profile image uploaded from `.github/Logo Viñabike Fondo Blanco Canva 2.jpeg`.

4. `supabase/functions/whatsapp-profile-admin/index.ts` was built out as the operational helper.
   - Auth: `x-admin-token` checked against `WHATSAPP_PROFILE_ADMIN_TOKEN`, or service-role bearer.
   - Actions now include `inspect`, `inspect_token`, `inspect_catalog`, `inspect_catalog_id`, `inspect_catalog_assets`, `graph_get`, `graph_post`, `connect_catalog`, `upsert_catalog_product`, `update_profile`, and `upload_profile_picture`.
   - `upload_profile_picture` uses Meta's resumable upload flow to get a profile picture handle before updating the WhatsApp Business Profile.
   - `upsert_catalog_product` loads product data from Supabase and maps ERP fields into Meta catalog fields.
   - `connect_catalog` posts URL-encoded `catalog_id`, `is_catalog_visible=true`, and `is_cart_enabled=true` to phone-level `whatsapp_commerce_settings`.

5. A real API-visible catalog was created and connected.
   - The old catalog `647068650790417` is a dead end. It returned Graph code `100` / subcode `33` on `/{catalog_id}` and `/{catalog_id}/products` even after connection attempts.
   - A new catalog was created through Graph: `POST 751663314343298/owned_product_catalogs` with `{name, vertical:"commerce"}`.
   - New catalog id: `932738139825582`.
   - The catalog was connected to WABA `912031294920516` via `POST 912031294920516/product_catalogs` with `{catalog_id:932738139825582}`.
   - `912031294920516/product_catalogs` confirmed it with `product_count:1`.

6. Product N079 was uploaded successfully to the working catalog.
   - SKU / retailer id: `N079`.
   - Name: `Neumático Vuelta MTB CB531 26x1.95" Negro`.
   - Price: `$15.000` CLP.
   - Availability: `in stock`.
   - Visibility: `published`.
   - Meta product id: `36596330423313700`.

7. ERP product data now has a WhatsApp catalog preparation layer.
   - Migration: `supabase/migrations/20260610173000_add_whatsapp_catalog_product_fields.sql`.
   - Deployment status in that file is marked deployed to production on 2026-06-10.
   - Added product columns:
     - `is_whatsapp_catalog boolean not null default false`
     - `whatsapp_catalog_title text`
     - `whatsapp_catalog_description text`
     - `whatsapp_catalog_price numeric(12,2)`
   - Added partial index: `idx_products_whatsapp_catalog` on `(tenant_id, updated_at desc)` where `is_whatsapp_catalog = true`.
   - Mirrored in `supabase/sql/core_schema.sql`.
   - Flutter model and form surfaces were updated:
     - `lib/modules/inventory/models/inventory_models.dart`
     - `lib/modules/inventory/pages/product_form_page.dart`
   - The product form's `Tienda Online` tab now includes a `Catálogo WhatsApp` section with enable toggle, title, description, price, readiness checks, preview, and public URL helper.
   - Empty WhatsApp fields intentionally fall back to website/product fields.

8. Product N079 was marked for WhatsApp catalog in production.
   - `is_whatsapp_catalog = true`.
   - `whatsapp_catalog_title`, `whatsapp_catalog_description`, and `whatsapp_catalog_price` populated conservatively from real product data.

9. Token handling was cleaned up operationally.
   - The Meta access token was rotated in Supabase after exposure in prior chat/terminal context.
   - Do not print `WHATSAPP_ACCESS_TOKEN`, service-role keys, or admin tokens.

10. The ERP product toggle now performs the real Meta catalog sync.
   - Root cause found on 2026-06-11: the toggle only persisted `is_whatsapp_catalog`; the product save flow never called Meta.
   - New authenticated Edge Function: `supabase/functions/whatsapp-catalog-sync/index.ts`.
   - Saving an enabled product creates or updates it in the connected Meta catalog using the server-side token.
   - Saving after disabling the toggle removes the matching Meta catalog item.
   - Meta sync failures keep the product form open and explicitly report that the ERP product saved but WhatsApp sync failed.
   - Product AE0037 exposed the missing workflow and was uploaded during diagnosis. The live catalog then contained two products: AE0037 and N079.

11. Meta catalog stock now uses the current quantity field.
   - The apparent stock mismatch came from inspecting Meta's deprecated `inventory` field, which Graph reports as `100` for these products even when the current sellable quantity is correct.
   - Live inspection of `quantity_to_sell_on_facebook` showed the correct ERP quantities: N079 `2`, AE0037 `3`, and Maxxis tube `8`.
   - Both catalog sync paths now send `quantity_to_sell_on_facebook` from ERP `stock_quantity` / `inventory_qty`.

12. WhatsApp catalog descriptions must contain real product content.
   - The Maxxis tube exposed that Meta Graph can report a title-only item as `PUBLISHED` and include it in `product_count`, while the customer-facing WhatsApp catalog still omits it during item approval/review.
   - Catalog upload no longer duplicates the title into an empty description.
   - Enabled products without a WhatsApp, website, or base product description now fail sync explicitly so the ERP can correct the content.
   - The product form now offers `Generar descripción con IA`, using the existing secured Gemini proxy and known product metadata only. Generated text remains editable and is not saved until the user reviews and saves the product.
   - Missing-field validation is aligned between the form and server. The description field shows an inline Spanish requirement before save, and server errors return exact missing fields instead of a generic English message.
   - SKU `16008`, Cámara RideXC Butyl 29, initially failed sync because its effective description was empty. A conservative real-data description was added and the product synced successfully as Meta product `27196373593390810`, bringing the catalog to four products.

13. Catalog synchronization was moved to a database-triggered backend path.
   - Migration: `supabase/migrations/20260612034500_automate_whatsapp_catalog_sync.sql`.
   - Relevant product inserts/updates now enqueue `whatsapp-catalog-sync`
     independently of the running desktop app version.
   - Sync status columns were added:
     - `whatsapp_catalog_sync_status`
     - `whatsapp_catalog_sync_error`
     - `whatsapp_catalog_sync_requested_at`
     - `whatsapp_catalog_synced_at`
     - `whatsapp_catalog_meta_product_id`
   - The service-role credential used by the trigger is stored in Supabase
     Vault as `whatsapp_catalog_sync_service_role_key`.
   - `whatsapp-catalog-sync` version `20` records API attempt status and Meta
     product IDs.
   - This automation reliably invokes Meta, but it has **not** solved or proven
     customer-facing visibility. The status name `synced` is currently too
     strong and should probably become `accepted_by_meta` until visibility is
     independently confirmed.

## Files Touched In This Thread

- `.github/copilot-instructions.md`
  - Updated runbook with WhatsApp profile/catalog state and the working catalog path.
- `supabase/functions/whatsapp-profile-admin/index.ts`
  - Edge Function helper for profile, token, catalog, Graph, and product upload operations.
- `supabase/functions/whatsapp-catalog-sync/index.ts`
  - Authenticated product-form sync path for Meta catalog upsert/removal.
- `supabase/migrations/20260610173000_add_whatsapp_catalog_product_fields.sql`
  - Deployed migration for WhatsApp product publishing fields.
- `supabase/migrations/20260612034500_automate_whatsapp_catalog_sync.sql`
  - Deployed database-triggered sync and persistent API-attempt status.
- `supabase/sql/core_schema.sql`
  - Canonical schema mirrored with the WhatsApp product fields, sync status,
    function, and triggers.
- `lib/modules/inventory/models/inventory_models.dart`
  - Product model/list select/toJson/copyWith support for WhatsApp catalog fields.
- `lib/modules/inventory/pages/product_form_page.dart`
  - Product form UI, save/load state, and automatic WhatsApp catalog sync.
- `lib/modules/inventory/services/whatsapp_catalog_sync_service.dart`
  - Flutter client wrapper for the authenticated catalog-sync Edge Function.
- `.github/Logo Viñabike Fondo Blanco Canva 2.jpeg`
  - Used as the source image for WhatsApp profile picture upload.

There were unrelated right-toolbar/quick-message files visible in earlier status output. Do not mix those into this WhatsApp/catalog work unless the user explicitly asks.

## Verified Commands / Results

Schema/migration:

```bash
supabase db query --linked --file supabase/migrations/20260610173000_add_whatsapp_catalog_product_fields.sql --output table
```

Verified production columns exist:

- `is_whatsapp_catalog`
- `whatsapp_catalog_title`
- `whatsapp_catalog_description`
- `whatsapp_catalog_price`

Verified production index exists:

- `idx_products_whatsapp_catalog`

Flutter analysis was run on the touched inventory files:

```bash
flutter analyze lib/modules/inventory/models/inventory_models.dart lib/modules/inventory/pages/product_form_page.dart
```

It returned only pre-existing info-level lint noise in those files, no blocking errors from this work.

Build status in current session:

```bash
flutter build macos --release
```

Exit code was `0`.

WhatsApp catalog sync verification:

- `whatsapp-catalog-sync` deployed active with JWT verification enabled.
- Enabled product N079 returned `action: upserted` through the new authenticated sync path and retained Meta product id `36596330423313700`.
- Disabled product SKU `18768` returned `action: already_absent`, verifying the removal/no-op path without deleting either live catalog item.
- Final Meta catalog inspection returned `product_count: 2`: N079 and AE0037.
- On 2026-06-12 the automatic database trigger successfully invoked the Edge
  Function for the new seat SKU `2000000305660`; Meta returned product id
  `26956061997426308`.
- Despite that successful API response, the seat was absent from the user's
  customer-facing WhatsApp catalog screenshot approximately four minutes
  later. This is the unresolved problem.

## Safe Helper Invocation Pattern

Use a fresh temporary admin token, set it in Supabase, call the helper, then unset it locally. Do not print secrets.

```bash
TEMP_WHATSAPP_ADMIN_TOKEN=$(openssl rand -hex 32)
supabase secrets set --project-ref xzdvtzdqjeyqxnkqprtf \
  WHATSAPP_PROFILE_ADMIN_TOKEN="$TEMP_WHATSAPP_ADMIN_TOKEN" >/dev/null

curl -sS 'https://xzdvtzdqjeyqxnkqprtf.supabase.co/functions/v1/whatsapp-profile-admin' \
  -H "x-admin-token: $TEMP_WHATSAPP_ADMIN_TOKEN" \
  -H 'Content-Type: application/json' \
  -d '{"action":"inspect","tenantId":"5443b130-cc28-45af-a420-cd500b288890"}' \
  | jq .

unset TEMP_WHATSAPP_ADMIN_TOKEN
```

Supabase CLI calls should be run sequentially, not in parallel.

## Next Steps

### 1. Diagnose Graph-Accepted But Customer-Hidden Products

This is the immediate next task. Do not upload or manually patch another
product and call that a fix.

Start with seat SKU `2000000305660`, ERP id
`a5c79c90-f226-41e7-a2f4-7f1cf12b7291`, and Meta product id
`26956061997426308`.

Required investigation:

- Inspect the exact Meta product object and every available review/approval,
  visibility, rejection, issue, and commerce-status field.
- Compare the hidden seat object against a customer-visible product such as
  SKU `6927116100278` or `N079`, field by field.
- Inspect catalog-level product diagnostics/issues and Commerce Manager review
  state, not only `/{catalog_id}/products`.
- Determine whether the catalog connected to the WABA/phone is definitely the
  same catalog receiving the upserts.
- Determine whether WhatsApp applies an approval delay, rejects particular
  image URLs/content, or requires another field not enforced by the current
  sync function.
- Verify visibility from the customer-facing WhatsApp catalog after each test.
  Graph success alone is insufficient.
- Change persistent status semantics so `synced` cannot imply customer-visible
  without evidence. At minimum distinguish `accepted_by_meta`, `under_review`,
  `rejected`, and `customer_visible` when Meta exposes enough data.
- Add an ERP diagnostic/retry surface instead of requiring terminal
  intervention.

Evidence to preserve:

- User screenshot:
  `/Users/Claudio/Library/Containers/net.whatsapp.WhatsApp/Data/tmp/documents/9517072F-E975-42A0-86A3-6555D17B1EED/PHOTO-2026-06-12-11-31-22.jpg`
- Screenshot shows the seat absent while five older items are visible.
- Do not expose or print Meta, Supabase service-role, or admin tokens.

### 2. Wait For Meta Business Verification

Current state is `pending`. Do not resubmit unless Meta rejects or asks for more info.

Check status with:

```bash
TEMP_WHATSAPP_ADMIN_TOKEN=$(openssl rand -hex 32)
supabase secrets set --project-ref xzdvtzdqjeyqxnkqprtf \
  WHATSAPP_PROFILE_ADMIN_TOKEN="$TEMP_WHATSAPP_ADMIN_TOKEN" >/dev/null

curl -sS 'https://xzdvtzdqjeyqxnkqprtf.supabase.co/functions/v1/whatsapp-profile-admin' \
  -H "x-admin-token: $TEMP_WHATSAPP_ADMIN_TOKEN" \
  -H 'Content-Type: application/json' \
  -d '{"action":"graph_get","tenantId":"5443b130-cc28-45af-a420-cd500b288890","path":"751663314343298?fields=id,name,verification_status"}' \
  | jq '.payload'

curl -sS 'https://xzdvtzdqjeyqxnkqprtf.supabase.co/functions/v1/whatsapp-profile-admin' \
  -H "x-admin-token: $TEMP_WHATSAPP_ADMIN_TOKEN" \
  -H 'Content-Type: application/json' \
  -d '{"action":"graph_get","tenantId":"5443b130-cc28-45af-a420-cd500b288890","path":"912031294920516?fields=id,name,account_review_status,business_verification_status,country,ownership_type"}' \
  | jq '.payload'

unset TEMP_WHATSAPP_ADMIN_TOKEN
```

Proceed only when verification is approved/verified.

### 3. Retry In-Chat Commerce Toggle

When business verification clears, retry phone-level commerce settings against the working catalog `932738139825582`:

```bash
TEMP_WHATSAPP_ADMIN_TOKEN=$(openssl rand -hex 32)
supabase secrets set --project-ref xzdvtzdqjeyqxnkqprtf \
  WHATSAPP_PROFILE_ADMIN_TOKEN="$TEMP_WHATSAPP_ADMIN_TOKEN" >/dev/null

curl -sS 'https://xzdvtzdqjeyqxnkqprtf.supabase.co/functions/v1/whatsapp-profile-admin' \
  -H "x-admin-token: $TEMP_WHATSAPP_ADMIN_TOKEN" \
  -H 'Content-Type: application/json' \
  -d '{"action":"connect_catalog","tenantId":"5443b130-cc28-45af-a420-cd500b288890","catalogId":"932738139825582"}' \
  | jq .

unset TEMP_WHATSAPP_ADMIN_TOKEN
```

Expected successful state would show visible catalog/cart settings on `1107058485829123/whatsapp_commerce_settings`. If Graph still returns code `1`, treat it as Meta commerce eligibility/onboarding, not a local code bug.

### 4. Keep Using Catalog `932738139825582`

Do not use catalog `647068650790417` for API work. It can return `{success:true}` when attaching, but product operations fail because Graph cannot load the object.

For product sync, pass the working catalog id explicitly:

```bash
TEMP_WHATSAPP_ADMIN_TOKEN=$(openssl rand -hex 32)
supabase secrets set --project-ref xzdvtzdqjeyqxnkqprtf \
  WHATSAPP_PROFILE_ADMIN_TOKEN="$TEMP_WHATSAPP_ADMIN_TOKEN" >/dev/null

curl -sS 'https://xzdvtzdqjeyqxnkqprtf.supabase.co/functions/v1/whatsapp-profile-admin' \
  -H "x-admin-token: $TEMP_WHATSAPP_ADMIN_TOKEN" \
  -H 'Content-Type: application/json' \
  -d '{"action":"upsert_catalog_product","tenantId":"5443b130-cc28-45af-a420-cd500b288890","productId":"9eaf3153-6bb8-4e2b-8d2e-69c5ec06c493","catalogId":"932738139825582"}' \
  | jq '{catalogId, retailerId: .catalogProduct.retailer_id, metaOk: .upsert.ok, metaStatus: .upsert.status, metaId: .upsert.payload.id, metaError: .upsert.payload.error.message}'

unset TEMP_WHATSAPP_ADMIN_TOKEN
```

### 5. Extend The Sync Workflow Later

The product-form toggle now performs a real Meta catalog sync. Future implementation may still add:

- List products where `is_whatsapp_catalog = true`.
- Validate required catalog data: title, description, image, price, public URL, stock.
- Store sync status / last synced id / last error if needed.
- Add bulk and scheduled sync for stock/price changes made outside the product form.
- Avoid exposing Meta tokens to Flutter.

### 6. Clean Temporary Files Before Commit

Earlier terminal work created `.agent/tmp/` with temporary profile-logo derivatives. Do not commit `.agent/tmp/` or generated scratch files.

## Caveats

- WhatsApp Business Profile updates are separate from the physical Chile WhatsApp Business app profile. Do not expect avatar/about/catalog to sync automatically from the physical SIM.
- Meta Graph accepting a catalog product does not prove the item is visible in
  the customer-facing WhatsApp catalog. This is now the main unresolved issue.
- Production Cloud API removes sandbox allowlist restrictions but does not remove the 24-hour service-window and template rules.
- Approved templates observed include `seguimiento_presupuesto_bicicleta`, `bicicleta_lista_retiro`, `actualizacion_servicio_bicicleta`, and `seguimiento_servicio_bicicleta` in `es_CL`.
- Phone `code_verification_status` was previously observed as `EXPIRED`; the phone itself is still connected/usable.
- If Meta rejects business verification again, compare the legal name/address exactly against the uploaded document. The current submission used address verification, so the phone should not be the checked field.

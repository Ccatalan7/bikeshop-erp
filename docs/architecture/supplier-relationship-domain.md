# Supplier relationship domain

Status: canonical architecture and migration contract.

This module owns the relationship with an external counterparty. It is not a
purchase-invoice list with extra contact fields, and it is not an accounting
subledger. It must represent a bicycle-parts vendor, carrier, digital service,
utility, landlord, public authority, professional, or portal-only resource
without forcing them through one form or one commercial type.

## 1. Ownership

The dependency direction is:

1. `external_parties` owns durable identity.
2. `suppliers` owns the tenant's relationship with that party.
3. roles, capabilities, and tags describe the relationship without being
   mutually exclusive.
4. `supplier_engagements` owns a concrete contract, service account,
   subscription, lease, utility account, tax obligation, or portal; its
   versions own terms that change over time.
5. accounting policies and rules own suggestions for a particular effective
   context. They never own a posted journal.
6. source documents and their normalized lines own the transaction facts.
7. accounting/tax read models publish posted results back to the supplier
   workspace.

The supplier UI may launch a canonical purchase, expense, payment, contract,
or accounting workflow. It must not calculate a competing balance, mutate a
posted journal, or rewrite historical classifications when a relationship is
edited.

Every supplier mutation has one command owner. The profile command creates or
updates durable identity and relationship fields with an operation ID and
optimistic version. Quick-create surfaces in a purchase invoice or expense are
adapters to that same command: they create an unclassified `other` party with
neutral `no_tax` posture and never infer IVA, role, or accounting behavior from
the screen that launched them. A lost acknowledgement retains the exact
operation ID until the matching command succeeds. OCR-template maintenance is
a separate narrow command that updates only `ocr_template`, also with retained
operation ID and expected `updated_at`; it never resubmits a partial legacy
supplier row or clears classifications. Hard delete is not a general client
operation; ordinary retirement changes relationship status through the profile
command.

## 2. Classification is multidimensional internally, guided operationally

A single `SupplierType` cannot describe geography, commercial position, and
business nature at once. The canonical classification has separate axes:

- identity kind: organization, person, public authority, or other;
- relationship roles: seller of goods, service provider, carrier, landlord,
  public authority, creditor, digital resource, and future tenant-defined
  roles;
- capabilities: inventory supply, workshop consumption, recurring billing,
  portal access, tax documents, logistics, and other observable abilities;
- operational tags: bicycle, workshop, logistics, digital, facilities,
  taxes, marketing, and tenant vocabulary;
- engagement kind: the concrete contract or account through which the
  relationship operates;
- operational nature: the typed purpose suggested for a particular
  transaction or line;
- accounting treatment: effective accounts, tax posture, and other defaults
  proposed by a versioned policy.

Roles, capabilities, tags, engagements, and policies are all many-valued
storage and audit facts. A supplier may sell parts and charge freight, or host
several utilities at different sites. That normalization is not the operator's
form model: the editor starts from one explained operational relationship and
maps it explicitly to compatible internal facts. The mapping is visible and
validated; it is never an unlabelled inference from a supplier name, invoice or
legacy type.

The editor must not expose roles, capabilities and tags as three peer
checklists. Their system vocabularies overlap by design history (for example,
digital, transport, utilities, government and facilities), so independent
selection creates combinations that have no business meaning. The
operator-facing purposes are goods, services, digital services, logistics,
utilities, leasing, public obligations and resource/portal access. A mixed
supplier adds another complete purpose. Each purpose owns only its compatible
subtypes, and a subtype is offered only when its value can be persisted and
read back without changing meaning. System capabilities are derived by the
adapter and system tags that duplicate the purpose are not authored in this
workflow. Tenant-created tags remain optional organizational metadata and
cannot enable behavior.

An `observed` assignment is evidence awaiting review, not a current
classification. It remains visible only in the audit/candidate workflow and
can become `manual` only through the explicit candidate-review command. Saving
identity or already confirmed classifications must neither promote nor close
observed evidence.

The database owns the tenant business date used for every effective role,
capability, tag, engagement, policy, and credential binding. It derives that
civil date from `tenants.timezone` and publishes it with the supplier profile;
clients never substitute the device, browser, or PostgreSQL session date.
Read surfaces resolve the version effective on that business date. An append
writer instead starts from the latest authored version, including a future
one, and requires an explicit later civil `effective_from`; otherwise a second
edit on the same day can collide with or conceal already scheduled history.

The legacy `suppliers.type` remains readable only during migration. It is not
the owner of new behavior.

## 3. Accounting policy is a suggestion, not history

An accounting policy is eligible only when all of the following are true:

- it is active and effective for the transaction date;
- the supplier and, when present, engagement match exactly;
- every required rule has positive evidence;
- one highest-priority policy remains after evaluation; and
- any automatic field fill was explicitly enabled for that policy.

Even then, automatic classification is not automatic posting. The operator
reviews the source facts and the canonical posting command remains the only
writer of journal evidence. Ambiguous, missing, conflicting, or unreadable
evidence stays explicit and blocks an automatic choice.

Every suggestion, acceptance, override, rejection, or exact auto-fill writes
application evidence with snapshots of what was proposed. Later policy edits
never rewrite that evidence or a posted transaction.

Supplier-wide defaults are a last resort. A more specific engagement,
document, or line policy wins because the same counterparty may produce
inventory, freight, services, taxes, or non-expense settlements.

Creating a policy therefore requires an explicit scope: one concrete
engagement, or a consciously confirmed supplier-wide fallback. A version with
no rules is also an explicit decision, never the silent result of an editor
that forgot to carry the previous rule set. Appending a version preserves the
current rules unless the operator changes or removes them deliberately. The
database validates the closed kind/operator/operand shape for every rule; the
client may expose a smaller, friendlier subset but is never the integrity
owner.

This foundation release owns policy configuration, version history, readback,
and decision evidence; it does not yet replace the canonical expense or
purchase posting commands with a policy evaluator. Until a later transaction
slice evaluates one unambiguous policy and records acceptance or override with
the saved document atomically, these criteria are configuration only: no UI
may claim that they classified, auto-filled, or posted an expense or invoice.
Legacy expense templates remain a migration consumer, not proof that the new
policy engine is active.

## 4. Source-document truth

`received_tax_documents` owns issuer, document type, and normalized folio. The
same issuer, type, and folio may be captured only once per tenant. OCR, import,
integration, and manual entry are acquisition methods, not alternate document
owners.

`purchase_invoice_lines` is the normalized line owner. Product identity is
optional: a rent, utility, freight, tax, or service line must remain valid
without inventing a catalog product. Its typed line nature and monetary
snapshots preserve the source even when the supplier profile changes.

Every posted journal entry names its source document, and every relevant
journal line may name the external party plus a typed counterparty context.
The supplier economic projection reads this provenance; it does not recover
ownership by matching labels or amounts.

Taxes paid to a public authority may settle a liability rather than create an
expense or purchase invoice. The supplier workspace must not force that role
through the purchase workflow.

## 5. Credentials are a separate security boundary

Public portal metadata such as the supplier name and navigation URL may support
the corporate browser catalog. Credential metadata — including usernames,
credential keys, exact origins, and engagement bindings — is visible only to
the dedicated credential authority. Neither credential metadata nor secret
material belongs in a general supplier row, cache, read model, log, URL,
suggestion model, or tenant-wide backup projection.

Server-side Vault stores secret bytes. `supplier_credentials` stores only
tenant/supplier metadata and a Vault reference. Client access is available
only through narrow security-definer commands guarded by the explicit supplier
credential permission. Each successful create, rotation, reveal, and delete
writes an append-only access event containing actor and scope but no username
or secret. General supplier reads are secret-free.

A secret is released only for the exact registered HTTPS origin, including its
scheme, host, and effective port. An HTTP page never receives or fills it; a
warning after DOM injection is already too late. Domain suggestions and portal
navigation need metadata only and therefore never trigger a secret read.

The purchasing assistant is another consumer of that same boundary, not a
second credential system. A proven authenticated supplier response may keep
its existing browser session alive with a low-frequency GET scoped to the
current ERP user. If the cookie has already expired, the provider probe may
declare one HTTPS login URL; the headless runner inspects its live form before
requesting any bytes and retries the original catalog question at most once.
An origin mismatch, HTTP form action, CAPTCHA, OTP, extra required field,
authority transition, ambiguous credential binding, or stale live URL fails
closed. Login pages, credentials, cookies, and authenticated body text never
become purchasing evidence.

The cutover is deliberately staged and may not be collapsed into one migration:

1. release a transition client in which every supplier read and mutation uses
   an explicit secret-free projection, every credential consumer uses the
   narrow service, and browser matching uses an exact registered HTTPS origin;
2. copy every legacy secret to Vault and verify counts without deleting the
   source;
3. enforce the minimum transition-client version and verify automatic login,
   reveal, copy, rotation, and deletion with authorized and unauthorized
   profiles;
4. apply a separate ACL cutover that revokes the legacy username/password
   columns and obsolete commands only after its client/Vault preflight passes;
5. redact new and historical tenant backups and verify that raw backup access
   cannot bypass the credential permission; then
6. null the legacy plaintext columns in a later forward migration after live
   read-back proves the bridge is unused.

The copy-first interval is compatibility debt, not the final design. It must
not become the permanent fallback after the Vault-aware client is released.

### 5.1 Legacy login transport: the destination is what is legacy, not the page

A portal whose login form posts over HTTP can still initiate its own session,
but only through an explicit declaration in
`supplier_portal_probes.session_login_legacy`. That declaration is
**`page_urls` (a closed set of exact source URLs) plus one exact `action_url`**,
and `supplier_credentials` keeps holding only identity and secret under its
HTTPS `origin_url`.

**Measured on the real portal, 2026-08-30.** `portal.rburgos.cl` links its
login from the home page in *both* schemes — `http://portal.rburgos.cl/login/`
and `https://portal.rburgos.cl/login/`. Both answer 200, neither redirects to
the other, and **both serve the same form**, whose action is always
`http://www.rburgos.cl/sitio/aplicaciones/valida_ingreso.asp`. An earlier
declaration named only the HTTP page, so the exception was unreachable on the
normal path: entering through the HTTPS link produced a page that was not the
declared one, and the client failed closed — correctly. The declaration
described the portal wrongly.

Three rules follow, and each one closed a hole found in review:

- **The page is matched by full URL, never by origin or host.** If the origin
  were enough, any other page of the same portal could have posted the
  credential to the legacy destination.
- **With a declaration, the declared destination is the only acceptable one** —
  a different `https://` action on the declared page is refused too. Choosing
  the rule from the *page* scheme (`securePage ? secureAction : declaredAction`)
  is what left the real case out.
- **Each variant that is actually used is declared literally.** Deriving the
  second one by rewriting the first one's scheme is describing the portal by
  hearsay.

Guards: `test/unit/supplier_legacy_login_policy_test.dart`,
`test/unit/browser_credential_autofill_test.dart`, and the read-back
`supabase/manual_checks/verify_legacy_login_pages_are_exact.sql`, which executes
`supplier_legacy_login_declaration_ok` itself rather than a hand-written copy.

## 6. UI contract

The collection is a classification-and-relationship workspace, not an
alphabetical wall. Its frozen entry contract is `Explorar` plus `Directorio`:
six image-led operational category blocks provide the first entry, while the
complete directory owns search, status, confirmed-category scope, selection,
and deterministic ranking. A supplier may appear in several categories. The
surface has no KPI grid, chip-cloud navigation, or client-inferred attention;
categories require a currently effective non-observed assignment and attention
copy comes from the server projection.

The profile is read-only by default. Its frozen section contract is `Resumen`,
`Identidad`, `Para qué lo usamos`, `Relaciones`, `Criterios contables`, optional
`Accesos`, and optional `Movimientos`. Desktop uses one section index; compact
hosts use the canonical short select and bottom sheet. There is one `Editar`
action owned by the record header, never a duplicate module action. A profile
without server-recognized economic activity does not show an empty Movimientos
section; a free resource instead states its operational value and current
billing cycle. The profile publishes:

- identity and relationship status;
- roles, capabilities, and operational tags;
- engagements and their current terms;
- accounting suggestions with their effective context and confidence limits;
- purchase, expense, payment, and document history from canonical read models;
- links and contacts; and
- credential availability without exposing the secret to the general read.

Editing is an explicit adaptive workflow. Its first business question is
`¿Qué relación tenemos con este proveedor?`, answered through the canonical
compact selector with explanations, not through a wall of checkboxes or chips.
Adding another relationship is explicit. Sections appear because that selected
relationship or one of its engagements needs them; identity remains available
to every profile, while commercial, logistics, recurrence, accounting, site,
and portal sections are conditional. The surface states the real consequence:
the relationship controls directory placement and which details may be
configured; it does not classify, post or automate a transaction by itself. A
portal-only free service is valid without RUT, invoice, bank or payment fields
and may later gain additional roles or engagements without changing identity
or losing history.

Identity kind is legal metadata, not supplier classification. The editor calls
it `Tipo de entidad`, keeps it under optional legal details, and represents an
unknown historical value as `Sin especificar`; it never presents `other` as a
meaningful commercial choice or changes the value silently from a selected
relationship.

`free` is a billing cycle on an effective engagement version. It is never a
supplier role, capability, tag, or accounting shortcut. Changing from free to
paid appends a version and closes the prior validity range; it does not
reclassify the supplier or rewrite historical transactions.

Routed editors open with `push` and close through `ReturnNavigation.close`.
Desktop, tablet, and phone compose the same commands and validation owners;
compact UI is not a reduced writer.

## 7. Migration boundary

This is an architectural replacement with compatibility bridges, not a second
supplier system:

- existing `suppliers.id` values and foreign keys remain stable;
- each existing supplier receives one `external_parties` identity and a
  tenant-scoped `party_id`;
- current JSON purchase items are backfilled once into normalized lines while
  the source JSON remains available for audit and old-client compatibility;
- existing expense-template defaults may seed draft policy candidates, but
  are never promoted automatically to active policy;
- legacy expense categories may be referenced only by an explicitly named
  compatibility field; new policy behavior uses the canonical operational
  nature and account/tax owners;
- inferred roles, capabilities, or policies are proposed for human review and
  never accepted from a supplier name alone; and
- destructive column/table retirement happens only after every registered
  consumer has moved and production read-back proves the bridge is unused.

Backup, restore, and tenant reset are registered consumers of the foundation.
They must either round-trip the complete dependency graph in a documented,
transactional order or fail before deleting anything with an explicit
unsupported-version error. Swallowing a foreign-key/RLS failure and reporting
success is never an acceptable compatibility mode.

Restore serializes its durable-identity comparison and mutation with ordinary
supplier and purchase-invoice writes for that tenant. Comparing ID sets and
then restoring under `READ COMMITTED` without a shared/exclusive transaction
lock is not a same-identity guarantee: a concurrent insert or delete can change
the set after preflight while the restore still reports success.

## 8. Minimum regression and read-back

The foundation is not complete without tests that prove:

- one party can carry several simultaneous roles, tags, engagements, and
  policy versions;
- the same UTC instant resolves one tenant business date at a timezone
  boundary, and every supplier projection consumes that date;
- saving a profile preserves observed evidence without exposing or promoting
  it as a confirmed classification;
- a free portal engagement can become paid through a new effective version;
- a mixed supplier classifies different lines differently;
- ambiguous policy matches never auto-fill or post;
- policy edits do not rewrite prior evidence or journals;
- normalized line backfill preserves all source rows and totals without
  inventing products or inventory treatment;
- received-document uniqueness is tenant, issuer, type, and folio scoped;
- tenant isolation covers every new table, view, and command;
- unauthorized users cannot read, reveal, mutate, or delete a credential;
- browser lookup failure or ambiguity cannot copy a managed secret into the
  local vault, and a confirmed managed binding removes any local duplicate;
- quick-create and OCR retries reuse their operation ID after a lost
  acknowledgement, while a changed intent receives a new ID;
- general supplier reads contain no secret; and
- supplier history totals equal their authoritative purchase, expense, and
  payment sources for the same tenant.

Production rollout follows the database contract: idempotent migration,
bootstrap mirror, focused pgTAP, complete local gate, immutable
production-derived validation, guarded forward apply, and exact live read-back.

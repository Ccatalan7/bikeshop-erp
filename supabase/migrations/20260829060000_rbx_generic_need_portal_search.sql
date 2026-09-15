-- RBX exposes one authenticated "Por Palabra" catalogue search for every
-- product family, not only the native motor selects observed first.
--
-- The natural-language need is already reviewed into category + typed
-- predicates. This flag allows the shared client adapter to use the canonical
-- family head noun as the broad portal query, then apply the same deterministic
-- eliminate-then-rank matcher to the returned rows. No SKU, product name or
-- family-specific Dart branch is introduced.

begin;

update public.supplier_portal_probes probe
set need_search_adapter = jsonb_set(
      probe.need_search_adapter,
      '{generic_family_search}',
      'true'::jsonb,
      true
    ),
    updated_at = now()
from public.suppliers supplier
where supplier.id = probe.supplier_id
  and supplier.tenant_id = probe.tenant_id
  and supplier.name = 'RBX'
  and probe.is_enabled
  and probe.need_search_url_template is not null
  and probe.need_search_adapter->>'version' = '1';

commit;

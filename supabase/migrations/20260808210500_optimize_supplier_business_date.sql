-- Keep the supplier profile projection inside the authenticated PostgREST
-- timeout without weakening the canonical tenant-business-date contract.
--
-- Forward behavior:
--   * computes public.tenant_business_date once per RLS-visible tenant;
--   * materializes that result before the supplier-correlated aggregates;
--   * preserves the view column order, security-invoker boundary, grants,
--     credential helpers, and every existing business-date rule.
--
-- Recovery behavior: reapply the prior supplier_profile_read_model definition.
-- No data is backfilled or deleted. CREATE OR REPLACE VIEW takes a short lock
-- on the view while its stored query is replaced.

begin;

create or replace view public.supplier_profile_read_model
with (security_invoker = true)
as
with tenant_business_dates as materialized (
  select
    date_supplier.tenant_id,
    public.tenant_business_date(date_supplier.tenant_id)
      as effective_business_date
  from public.suppliers date_supplier
  where
    coalesce(auth.jwt()->>'role', auth.role(), '') = 'service_role'
    or (
      coalesce(auth.jwt()->>'role', auth.role(), '') = ''
      and session_user in ('postgres', 'supabase_admin')
    )
    or public.is_active_tenant_member(date_supplier.tenant_id)
  group by date_supplier.tenant_id
)
select
  supplier.tenant_id,
  supplier.id as supplier_id,
  business_date.effective_business_date,
  supplier.party_id,
  coalesce(party.party_kind, 'other') as party_kind,
  coalesce(party.display_name, supplier.name) as display_name,
  coalesce(party.legal_name, supplier.legal_name) as legal_name,
  coalesce(party.trade_name, supplier.trade_name) as trade_name,
  party.country_code,
  party.notes as party_notes,
  coalesce(party.metadata, '{}'::jsonb) as party_metadata,
  identifier.identifier_id as tax_identifier_id,
  identifier.tax_identifier,
  identifier.tax_country_code,
  supplier.is_active,
  supplier.email,
  supplier.phone,
  supplier.website,
  supplier.contact_person,
  supplier.address,
  supplier.city,
  supplier.region,
  supplier.comuna,
  supplier.type as legacy_type,
  supplier.payment_terms,
  supplier.notes,
  supplier.aliases,
  supplier.default_tax_treatment,
  public.has_supplier_portal_credential(
    supplier.tenant_id,
    supplier.id
  ) as has_portal_credential,
  relationship_summary.service_relationship_summary,
  coalesce(roles.items, '[]'::jsonb) as relationship_roles,
  coalesce(capabilities.items, '[]'::jsonb) as relationship_capabilities,
  coalesce(tags.items, '[]'::jsonb) as relationship_tags,
  coalesce(engagements.active_count, 0)::bigint as active_engagement_count,
  coalesce(policies.active_count, 0)::bigint as active_policy_count,
  coalesce(activity.recognized_document_count, 0)::bigint
    as recognized_document_count,
  coalesce(data_issues.pending_count, 0)::bigint
    as validation_issue_count,
  coalesce(data_issues.items, '[]'::jsonb) as validation_incidents,
  case
    when coalesce(data_issues.pending_count, 0) > 0 then 'partial'
    else 'known'
  end::text as data_completeness_status,
  case
    when coalesce(activity.recognized_document_count, 0) = 0
      then 'not_applicable'
    when coalesce(roles.confirmed_count, 0)
       + coalesce(capabilities.confirmed_count, 0)
       + coalesce(tags.confirmed_count, 0) = 0
      then 'unclassified'
    else 'classified'
  end::text as classification_status,
  case
    when coalesce(activity.recognized_document_count, 0) = 0
      then 'not_applicable'
    when coalesce(policies.active_count, 0) = 0 then 'missing_policy'
    else 'configured'
  end::text as accounting_policy_status,
  supplier.created_at,
  supplier.updated_at,
  public.has_supplier_credential_reference(
    supplier.tenant_id,
    supplier.id
  ) as has_credential_reference
from public.suppliers supplier
join tenant_business_dates business_date
  on business_date.tenant_id = supplier.tenant_id
left join public.external_parties party
  on party.tenant_id = supplier.tenant_id
 and party.id = supplier.party_id
left join lateral (
  select
    id.id as identifier_id,
    coalesce(id.display_value, id.normalized_value) as tax_identifier,
    id.country_code as tax_country_code
  from public.external_party_identifiers id
  where id.tenant_id = supplier.tenant_id
    and id.party_id = supplier.party_id
    and id.identifier_kind = 'tax_id'
    and id.valid_from <= business_date.effective_business_date
    and (
      id.valid_to is null
      or id.valid_to >= business_date.effective_business_date
    )
  order by id.is_primary desc, id.valid_from desc, id.id
  limit 1
) identifier on true
left join lateral (
  select
    jsonb_agg(
      jsonb_build_object(
        'id', role.id,
        'definition_id', definition.id,
        'code', role.role_code,
        'label', definition.label,
        'valid_from', role.valid_from,
        'valid_to', role.valid_to,
        'source', role.assignment_source,
        'metadata', role.metadata
      ) order by role.role_code
    ) as items,
    count(*) as confirmed_count
  from public.supplier_relationship_roles role
  join public.supplier_role_definitions definition
    on definition.tenant_id = role.tenant_id
   and definition.code = role.role_code
  where role.tenant_id = supplier.tenant_id
    and role.supplier_id = supplier.id
    and role.assignment_source <> 'observed'
    and role.valid_from <= business_date.effective_business_date
    and (
      role.valid_to is null
      or role.valid_to >= business_date.effective_business_date
    )
) roles on true
left join lateral (
  select
    jsonb_agg(
      jsonb_build_object(
        'id', capability.id,
        'definition_id', definition.id,
        'code', capability.capability_code,
        'label', definition.label,
        'valid_from', capability.valid_from,
        'valid_to', capability.valid_to,
        'source', capability.assignment_source,
        'metadata', capability.metadata
      ) order by capability.capability_code
    ) as items,
    count(*) as confirmed_count
  from public.supplier_relationship_capabilities capability
  join public.supplier_capability_definitions definition
    on definition.tenant_id = capability.tenant_id
   and definition.code = capability.capability_code
  where capability.tenant_id = supplier.tenant_id
    and capability.supplier_id = supplier.id
    and capability.assignment_source <> 'observed'
    and capability.valid_from <= business_date.effective_business_date
    and (
      capability.valid_to is null
      or capability.valid_to >= business_date.effective_business_date
    )
) capabilities on true
left join lateral (
  select
    jsonb_agg(
      jsonb_build_object(
        'id', tag.id,
        'definition_id', definition.id,
        'code', tag.tag_code,
        'label', definition.label,
        'valid_from', tag.valid_from,
        'valid_to', tag.valid_to,
        'source', tag.assignment_source,
        'metadata', tag.metadata
      ) order by definition.label, tag.tag_code
    ) as items,
    count(*) as confirmed_count
  from public.supplier_relationship_tags tag
  join public.supplier_tag_definitions definition
    on definition.tenant_id = tag.tenant_id
   and definition.code = tag.tag_code
  where tag.tenant_id = supplier.tenant_id
    and tag.supplier_id = supplier.id
    and tag.assignment_source <> 'observed'
    and tag.valid_from <= business_date.effective_business_date
    and (
      tag.valid_to is null
      or tag.valid_to >= business_date.effective_business_date
    )
) tags on true
left join lateral (
  select case
    when summary.relationship_count = 0 then null
    when summary.relationship_count = 1 then summary.first_label
    else summary.first_label || ' y ' ||
      (summary.relationship_count - 1)::text || ' más'
  end::text as service_relationship_summary
  from (
    select
      count(*)::integer as relationship_count,
      (array_agg(
        engagement.name || case when site.id is null
          then '' else ' · ' || site.name end
        order by engagement.name, engagement.id
      ))[1] as first_label
    from public.supplier_engagements engagement
    left join public.business_sites site
      on site.tenant_id = engagement.tenant_id
     and site.id = engagement.site_id
    where engagement.tenant_id = supplier.tenant_id
      and engagement.supplier_id = supplier.id
      and engagement.status = 'active'
      and (
        engagement.starts_on is null
        or engagement.starts_on <= business_date.effective_business_date
      )
      and (
        engagement.ends_on is null
        or engagement.ends_on >= business_date.effective_business_date
      )
      and exists (
        select 1
        from public.supplier_engagement_versions version
        where version.tenant_id = engagement.tenant_id
          and version.engagement_id = engagement.id
          and version.effective_from <= business_date.effective_business_date
          and (
            version.effective_to is null
            or version.effective_to >= business_date.effective_business_date
          )
      )
  ) summary
) relationship_summary on true
left join lateral (
  select count(*) as active_count
  from public.supplier_engagements engagement
  where engagement.tenant_id = supplier.tenant_id
    and engagement.supplier_id = supplier.id
    and engagement.status = 'active'
    and (
      engagement.starts_on is null
      or engagement.starts_on <= business_date.effective_business_date
    )
    and (
      engagement.ends_on is null
      or engagement.ends_on >= business_date.effective_business_date
    )
    and exists (
      select 1
      from public.supplier_engagement_versions version
      where version.tenant_id = engagement.tenant_id
        and version.engagement_id = engagement.id
        and version.effective_from <= business_date.effective_business_date
        and (
          version.effective_to is null
          or version.effective_to >= business_date.effective_business_date
        )
    )
) engagements on true
left join lateral (
  select count(*) as active_count
  from public.supplier_accounting_policies policy
  where policy.tenant_id = supplier.tenant_id
    and policy.supplier_id = supplier.id
    and policy.status = 'active'
    and exists (
      select 1
      from public.supplier_accounting_policy_versions version
      where version.tenant_id = policy.tenant_id
        and version.policy_id = policy.id
        and version.effective_from <= business_date.effective_business_date
        and (
          version.effective_to is null
          or version.effective_to >= business_date.effective_business_date
        )
    )
) policies on true
left join lateral (
  select (
    select count(*)
    from public.purchase_invoices invoice
    where invoice.tenant_id = supplier.tenant_id
      and invoice.supplier_id = supplier.id
      and invoice.status in ('confirmed', 'received', 'paid')
  ) + (
    select count(*)
    from public.expenses expense
    where expense.tenant_id = supplier.tenant_id
      and expense.supplier_id = supplier.id
      and expense.posting_status = 'posted'
  ) as recognized_document_count
) activity on true
left join lateral (
  select
    count(*) as pending_count,
    jsonb_agg(
      jsonb_build_object(
        'code', candidate.issue_code,
        'severity', candidate.severity,
        'scope_type', candidate.scope_type,
        'scope_id', coalesce(candidate.scope_id, candidate.supplier_id),
        'related_code', candidate.related_code,
        'field_key', candidate.field_key,
        'display_reason', candidate.display_reason,
        'source', candidate.issue_source,
        'status', candidate.status
      ) order by candidate.severity desc, candidate.issue_code,
        candidate.id
    ) as items
  from public.supplier_data_quality_candidates candidate
  where candidate.tenant_id = supplier.tenant_id
    and candidate.supplier_id = supplier.id
    and candidate.status = 'pending'
) data_issues on true;

comment on view public.supplier_profile_read_model is
  'Secret-free supplier profile projection. It publishes the tenant effective business date, excludes observed evidence from current editable classifications, and deliberately excludes legacy portal_password, Vault ids, and decrypted credentials.';

commit;

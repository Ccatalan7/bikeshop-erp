-- La imagen del proveedor, en el modelo de lectura del directorio.
--
-- La ficha la obtiene con una lectura extra por proveedor; el directorio tiene
-- 91 filas y no puede pagar 91 lecturas, así que la columna viaja en la misma
-- vista que ya trae nombre, RUT y telefono. La vista es `security_invoker`, de
-- modo que cada quien sigue viendo exactamente lo que sus politicas permiten.
--
-- La columna se agrega **al final**: `create or replace view` sólo admite
-- columnas nuevas al final de la lista, y reemplazar la vista entera con un
-- drop perderia los grants y las dependencias.
--
-- Definición vigente leida con pg_get_viewdef el 2026-09-17 más
-- `supplier.image_url`.

-- **`with (security_invoker = true)` es obligatorio acá.** `create or replace
-- view` NO conserva las reloptions: sin esta clausula la vista pasa a
-- ejecutarse con los permisos de su dueño y deja de aplicar las politicas
-- del que consulta. Medido en produccion el 2026-09-17: el primer intento
-- de esta misma migracion las borró, y el read-back lo detuvo.
create or replace view public.supplier_profile_read_model
with (security_invoker = true) as
 WITH tenant_business_dates AS MATERIALIZED (
         SELECT date_supplier.tenant_id,
            tenant_business_date(date_supplier.tenant_id) AS effective_business_date
           FROM suppliers date_supplier
          WHERE COALESCE(auth.jwt() ->> 'role'::text, auth.role(), ''::text) = 'service_role'::text OR COALESCE(auth.jwt() ->> 'role'::text, auth.role(), ''::text) = ''::text AND (SESSION_USER = ANY (ARRAY['postgres'::name, 'supabase_admin'::name])) OR is_active_tenant_member(date_supplier.tenant_id)
          GROUP BY date_supplier.tenant_id
        )
 SELECT supplier.tenant_id,
    supplier.id AS supplier_id,
    business_date.effective_business_date,
    supplier.party_id,
    COALESCE(party.party_kind, 'other'::text) AS party_kind,
    COALESCE(party.display_name, supplier.name) AS display_name,
    COALESCE(party.legal_name, supplier.legal_name) AS legal_name,
    COALESCE(party.trade_name, supplier.trade_name) AS trade_name,
    party.country_code,
    party.notes AS party_notes,
    COALESCE(party.metadata, '{}'::jsonb) AS party_metadata,
    identifier.identifier_id AS tax_identifier_id,
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
    supplier.type AS legacy_type,
    supplier.payment_terms,
    supplier.notes,
    supplier.aliases,
    supplier.default_tax_treatment,
    has_supplier_portal_credential(supplier.tenant_id, supplier.id) AS has_portal_credential,
    relationship_summary.service_relationship_summary,
    COALESCE(roles.items, '[]'::jsonb) AS relationship_roles,
    COALESCE(capabilities.items, '[]'::jsonb) AS relationship_capabilities,
    COALESCE(tags.items, '[]'::jsonb) AS relationship_tags,
    COALESCE(engagements.active_count, 0::bigint) AS active_engagement_count,
    COALESCE(policies.active_count, 0::bigint) AS active_policy_count,
    COALESCE(activity.recognized_document_count, 0::bigint) AS recognized_document_count,
    COALESCE(data_issues.pending_count, 0::bigint) AS validation_issue_count,
    COALESCE(data_issues.items, '[]'::jsonb) AS validation_incidents,
        CASE
            WHEN COALESCE(data_issues.pending_count, 0::bigint) > 0 THEN 'partial'::text
            ELSE 'known'::text
        END AS data_completeness_status,
        CASE
            WHEN COALESCE(activity.recognized_document_count, 0::bigint) = 0 THEN 'not_applicable'::text
            WHEN (COALESCE(roles.confirmed_count, 0::bigint) + COALESCE(capabilities.confirmed_count, 0::bigint) + COALESCE(tags.confirmed_count, 0::bigint)) = 0 THEN 'unclassified'::text
            ELSE 'classified'::text
        END AS classification_status,
        CASE
            WHEN COALESCE(activity.recognized_document_count, 0::bigint) = 0 THEN 'not_applicable'::text
            WHEN COALESCE(policies.active_count, 0::bigint) = 0 THEN 'missing_policy'::text
            ELSE 'configured'::text
        END AS accounting_policy_status,
    supplier.created_at,
    supplier.updated_at,
    has_supplier_credential_reference(supplier.tenant_id, supplier.id) AS has_credential_reference,
    supplier.image_url
   FROM suppliers supplier
     JOIN tenant_business_dates business_date ON business_date.tenant_id = supplier.tenant_id
     LEFT JOIN external_parties party ON party.tenant_id = supplier.tenant_id AND party.id = supplier.party_id
     LEFT JOIN LATERAL ( SELECT id.id AS identifier_id,
            COALESCE(id.display_value, id.normalized_value) AS tax_identifier,
            id.country_code AS tax_country_code
           FROM external_party_identifiers id
          WHERE id.tenant_id = supplier.tenant_id AND id.party_id = supplier.party_id AND id.identifier_kind = 'tax_id'::text AND id.valid_from <= business_date.effective_business_date AND (id.valid_to IS NULL OR id.valid_to >= business_date.effective_business_date)
          ORDER BY id.is_primary DESC, id.valid_from DESC, id.id
         LIMIT 1) identifier ON true
     LEFT JOIN LATERAL ( SELECT jsonb_agg(jsonb_build_object('id', role.id, 'definition_id', definition.id, 'code', role.role_code, 'label', definition.label, 'valid_from', role.valid_from, 'valid_to', role.valid_to, 'source', role.assignment_source, 'metadata', role.metadata) ORDER BY role.role_code) AS items,
            count(*) AS confirmed_count
           FROM supplier_relationship_roles role
             JOIN supplier_role_definitions definition ON definition.tenant_id = role.tenant_id AND definition.code = role.role_code
          WHERE role.tenant_id = supplier.tenant_id AND role.supplier_id = supplier.id AND role.assignment_source <> 'observed'::text AND role.valid_from <= business_date.effective_business_date AND (role.valid_to IS NULL OR role.valid_to >= business_date.effective_business_date)) roles ON true
     LEFT JOIN LATERAL ( SELECT jsonb_agg(jsonb_build_object('id', capability.id, 'definition_id', definition.id, 'code', capability.capability_code, 'label', definition.label, 'valid_from', capability.valid_from, 'valid_to', capability.valid_to, 'source', capability.assignment_source, 'metadata', capability.metadata) ORDER BY capability.capability_code) AS items,
            count(*) AS confirmed_count
           FROM supplier_relationship_capabilities capability
             JOIN supplier_capability_definitions definition ON definition.tenant_id = capability.tenant_id AND definition.code = capability.capability_code
          WHERE capability.tenant_id = supplier.tenant_id AND capability.supplier_id = supplier.id AND capability.assignment_source <> 'observed'::text AND capability.valid_from <= business_date.effective_business_date AND (capability.valid_to IS NULL OR capability.valid_to >= business_date.effective_business_date)) capabilities ON true
     LEFT JOIN LATERAL ( SELECT jsonb_agg(jsonb_build_object('id', tag.id, 'definition_id', definition.id, 'code', tag.tag_code, 'label', definition.label, 'valid_from', tag.valid_from, 'valid_to', tag.valid_to, 'source', tag.assignment_source, 'metadata', tag.metadata) ORDER BY definition.label, tag.tag_code) AS items,
            count(*) AS confirmed_count
           FROM supplier_relationship_tags tag
             JOIN supplier_tag_definitions definition ON definition.tenant_id = tag.tenant_id AND definition.code = tag.tag_code
          WHERE tag.tenant_id = supplier.tenant_id AND tag.supplier_id = supplier.id AND tag.assignment_source <> 'observed'::text AND tag.valid_from <= business_date.effective_business_date AND (tag.valid_to IS NULL OR tag.valid_to >= business_date.effective_business_date)) tags ON true
     LEFT JOIN LATERAL ( SELECT
                CASE
                    WHEN summary.relationship_count = 0 THEN NULL::text
                    WHEN summary.relationship_count = 1 THEN summary.first_label
                    ELSE ((summary.first_label || ' y '::text) || ((summary.relationship_count - 1)::text)) || ' más'::text
                END AS service_relationship_summary
           FROM ( SELECT count(*)::integer AS relationship_count,
                    (array_agg(engagement.name ||
                        CASE
                            WHEN site.id IS NULL THEN ''::text
                            ELSE ' · '::text || site.name
                        END ORDER BY engagement.name, engagement.id))[1] AS first_label
                   FROM supplier_engagements engagement
                     LEFT JOIN business_sites site ON site.tenant_id = engagement.tenant_id AND site.id = engagement.site_id
                  WHERE engagement.tenant_id = supplier.tenant_id AND engagement.supplier_id = supplier.id AND engagement.status = 'active'::text AND (engagement.starts_on IS NULL OR engagement.starts_on <= business_date.effective_business_date) AND (engagement.ends_on IS NULL OR engagement.ends_on >= business_date.effective_business_date) AND (EXISTS ( SELECT 1
                           FROM supplier_engagement_versions version
                          WHERE version.tenant_id = engagement.tenant_id AND version.engagement_id = engagement.id AND version.effective_from <= business_date.effective_business_date AND (version.effective_to IS NULL OR version.effective_to >= business_date.effective_business_date)))) summary) relationship_summary ON true
     LEFT JOIN LATERAL ( SELECT count(*) AS active_count
           FROM supplier_engagements engagement
          WHERE engagement.tenant_id = supplier.tenant_id AND engagement.supplier_id = supplier.id AND engagement.status = 'active'::text AND (engagement.starts_on IS NULL OR engagement.starts_on <= business_date.effective_business_date) AND (engagement.ends_on IS NULL OR engagement.ends_on >= business_date.effective_business_date) AND (EXISTS ( SELECT 1
                   FROM supplier_engagement_versions version
                  WHERE version.tenant_id = engagement.tenant_id AND version.engagement_id = engagement.id AND version.effective_from <= business_date.effective_business_date AND (version.effective_to IS NULL OR version.effective_to >= business_date.effective_business_date)))) engagements ON true
     LEFT JOIN LATERAL ( SELECT count(*) AS active_count
           FROM supplier_accounting_policies policy
          WHERE policy.tenant_id = supplier.tenant_id AND policy.supplier_id = supplier.id AND policy.status = 'active'::text AND (EXISTS ( SELECT 1
                   FROM supplier_accounting_policy_versions version
                  WHERE version.tenant_id = policy.tenant_id AND version.policy_id = policy.id AND version.effective_from <= business_date.effective_business_date AND (version.effective_to IS NULL OR version.effective_to >= business_date.effective_business_date)))) policies ON true
     LEFT JOIN LATERAL ( SELECT (( SELECT count(*) AS count
                   FROM purchase_invoices invoice
                  WHERE invoice.tenant_id = supplier.tenant_id AND invoice.supplier_id = supplier.id AND (invoice.status = ANY (ARRAY['confirmed'::text, 'received'::text, 'paid'::text])))) + (( SELECT count(*) AS count
                   FROM expenses expense
                  WHERE expense.tenant_id = supplier.tenant_id AND expense.supplier_id = supplier.id AND expense.posting_status = 'posted'::text)) AS recognized_document_count) activity ON true
     LEFT JOIN LATERAL ( SELECT count(*) AS pending_count,
            jsonb_agg(jsonb_build_object('code', candidate.issue_code, 'severity', candidate.severity, 'scope_type', candidate.scope_type, 'scope_id', COALESCE(candidate.scope_id, candidate.supplier_id), 'related_code', candidate.related_code, 'field_key', candidate.field_key, 'display_reason', candidate.display_reason, 'source', candidate.issue_source, 'status', candidate.status) ORDER BY candidate.severity DESC, candidate.issue_code, candidate.id) AS items
           FROM supplier_data_quality_candidates candidate
          WHERE candidate.tenant_id = supplier.tenant_id AND candidate.supplier_id = supplier.id AND candidate.status = 'pending'::text) data_issues ON true;

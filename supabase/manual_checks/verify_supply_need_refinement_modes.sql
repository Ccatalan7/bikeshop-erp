-- Read-back ejecutable para 20260829160000_supply_need_refinement_modes.sql.
--
-- Se corre después del SQL y antes de registrar la migración. Cada garantía
-- material aborta con división por cero cuando falta: imprimir un diagnóstico
-- no se confunde con demostrar que el rollout quedó correcto.

-- -------------------------------------------------------------------------
-- Diagnóstico legible
-- -------------------------------------------------------------------------

select table_name, column_name, data_type, is_nullable
from information_schema.columns
where table_schema = 'public'
  and (
    (table_name = 'supply_need_interpretation_revisions'
     and column_name in (
       'supersedes_revision_no', 'continuity', 'technical_family'
     ))
    or (
      table_name = 'supplier_need_portal_searches'
      and column_name in (
        'need_version_at_search', 'interpretation_revision_no',
        'interpretation_category_id', 'interpretation_technical_family'
      )
    )
  )
order by table_name, column_name;

select
  proc.proname,
  proc.pronargs,
  proc.pronargdefaults,
  language.lanname,
  proc.prosecdef,
  has_function_privilege('authenticated', proc.oid, 'execute')
    as authenticated_exec,
  has_function_privilege('anon', proc.oid, 'execute') as anon_exec
from pg_proc proc
join pg_namespace namespace on namespace.oid = proc.pronamespace
join pg_language language on language.oid = proc.prolang
where namespace.nspname = 'public'
  and proc.proname in (
    'refine_supply_need_v1',
    'set_supply_need_quantity_v1',
    'replace_supply_need_v1',
    'supplier_last_need_portal_search_v1',
    'record_supplier_need_portal_search_v1'
  )
order by proc.proname, proc.pronargs;

select
  trigger.tgname,
  trigger.tgenabled,
  trigger.tgrelid::regclass as relation
from pg_trigger trigger
where not trigger.tgisinternal
  and trigger.tgname in (
    'trg_supply_need_interpretation_revisions_immutable',
    'supplier_need_portal_search_scope_guard'
  )
order by trigger.tgname;

-- -------------------------------------------------------------------------
-- Estructura y validación
-- -------------------------------------------------------------------------

select 1 / (case when (
  select count(*)
  from information_schema.columns
  where table_schema = 'public'
    and table_name = 'supply_need_interpretation_revisions'
    and column_name in (
      'supersedes_revision_no', 'continuity', 'technical_family'
    )
) = 3 then 1 else 0 end) as revision_lineage_columns_present;

select 1 / (case when (
  select count(*)
  from information_schema.columns
  where table_schema = 'public'
    and table_name = 'supplier_need_portal_searches'
    and column_name in (
      'need_version_at_search', 'interpretation_revision_no',
      'interpretation_category_id', 'interpretation_technical_family'
    )
) = 4 then 1 else 0 end) as portal_search_scope_columns_present;

select 1 / (case when (
  select count(*)
  from pg_constraint constraint_
  where constraint_.conrelid
      in (
        'public.supply_need_interpretation_revisions'::regclass,
        'public.supplier_need_portal_searches'::regclass
      )
    and constraint_.conname in (
      'supply_need_interpretation_revisions_continuity_check',
      'supply_need_interpretation_revisions_supersedes_check',
      'supply_need_interpretation_revisions_lineage_check',
      'supplier_need_portal_searches_interpretation_scope_check',
      'supplier_need_portal_searches_category_fkey'
    )
    and constraint_.convalidated
) = 5 then 1 else 0 end) as lineage_and_scope_constraints_validated;

select 1 / (case when (
  select count(*)
  from pg_trigger trigger
  where not trigger.tgisinternal
    and trigger.tgenabled in ('O', 'A')
    and (
      (
        trigger.tgrelid
          = 'public.supply_need_interpretation_revisions'::regclass
        and trigger.tgname
          = 'trg_supply_need_interpretation_revisions_immutable'
      )
      or (
        trigger.tgrelid = 'public.supplier_need_portal_searches'::regclass
        and trigger.tgname = 'supplier_need_portal_search_scope_guard'
      )
    )
) = 2 then 1 else 0 end) as immutable_and_scope_guards_enabled;

-- -------------------------------------------------------------------------
-- Firmas, permisos y compatibilidad hacia atrás
-- -------------------------------------------------------------------------

select 1 / (case when (
  select count(*)
  from pg_proc proc
  join pg_namespace namespace on namespace.oid = proc.pronamespace
  where namespace.nspname = 'public'
    and proc.proname = 'record_supplier_need_portal_search_v1'
    and proc.pronargs in (7, 8, 12)
    and proc.pronargdefaults = 0
) = 3 then 1 else 0 end) as portal_receipt_signatures_are_exact;

select 1 / (case when exists (
  select 1
  from pg_proc proc
  join pg_namespace namespace on namespace.oid = proc.pronamespace
  join pg_language language on language.oid = proc.prolang
  where namespace.nspname = 'public'
    and proc.proname = 'record_supplier_need_portal_search_v1'
    and proc.pronargs = 12
    and proc.pronargdefaults = 0
    and language.lanname = 'plpgsql'
    and proc.prosecdef
    and pg_get_functiondef(proc.oid) ilike '%insert into public.supplier_need_portal_searches%'
) then 1 else 0 end) as stamped_receipt_is_the_only_writer;

select 1 / (case when (
  select bool_and(
    language.lanname = 'sql'
    and not proc.prosecdef
    and pg_get_functiondef(proc.oid) ilike '%client_upgrade_required%'
    and pg_get_functiondef(proc.oid) not ilike '%insert into%'
  )
  from pg_proc proc
  join pg_namespace namespace on namespace.oid = proc.pronamespace
  join pg_language language on language.oid = proc.prolang
  where namespace.nspname = 'public'
    and proc.proname = 'record_supplier_need_portal_search_v1'
    and proc.pronargs in (7, 8)
) then 1 else 0 end) as legacy_receipts_fail_closed_without_writing;

select 1 / (case when (
  select bool_and(
    has_function_privilege('authenticated', proc.oid, 'execute')
    and not has_function_privilege('anon', proc.oid, 'execute')
  )
  from pg_proc proc
  join pg_namespace namespace on namespace.oid = proc.pronamespace
  where namespace.nspname = 'public'
    and (
      (proc.proname = 'refine_supply_need_v1' and proc.pronargs = 7)
      or (proc.proname = 'set_supply_need_quantity_v1' and proc.pronargs = 5)
      or (proc.proname = 'replace_supply_need_v1' and proc.pronargs = 6)
      or (
        proc.proname = 'supplier_last_need_portal_search_v1'
        and proc.pronargs = 2
      )
      or (
        proc.proname = 'record_supplier_need_portal_search_v1'
        and proc.pronargs in (7, 8, 12)
      )
    )
) then 1 else 0 end) as public_rpcs_are_authenticated_only;

select 1 / (case when (
  select count(*)
  from pg_proc proc
  join pg_namespace namespace on namespace.oid = proc.pronamespace
  where namespace.nspname = 'public'
    and (
      (proc.proname = 'refine_supply_need_v1' and proc.pronargs = 7)
      or (proc.proname = 'set_supply_need_quantity_v1' and proc.pronargs = 5)
      or (proc.proname = 'replace_supply_need_v1' and proc.pronargs = 6)
      or (
        proc.proname = 'supplier_last_need_portal_search_v1'
        and proc.pronargs = 2
      )
    )
) = 4 then 1 else 0 end) as edit_and_reader_signatures_present;

-- -------------------------------------------------------------------------
-- Invariantes sobre los datos reales
-- -------------------------------------------------------------------------

-- Toda revisión cuya categoría tiene un mapping autoritativo activo lleva la
-- misma familia. Esto prueba el backfill que preserva el feed histórico.
select 1 / (case when not exists (
  select 1
  from public.supply_need_interpretation_revisions revision
  join public.product_categories category
    on category.tenant_id = revision.tenant_id
   and category.id = revision.category_id
   and category.is_active is true
  join public.category_tech_mappings mapping
    on mapping.tenant_id = revision.tenant_id
   and mapping.category_id = revision.category_id
   and mapping.status = 'active'
  where revision.technical_family is distinct from mapping.technical_family
) then 1 else 0 end) as revision_family_matches_authority;

-- Una búsqueda estampada coincide exactamente con la revisión que declara;
-- no puede haber terminado vieja y haber sido reetiquetada como vigente.
select 1 / (case when not exists (
  select 1
  from public.supplier_need_portal_searches search
  left join public.supply_need_interpretation_revisions revision
    on revision.tenant_id = search.tenant_id
   and revision.supply_need_id = search.supply_need_id
   and revision.revision_no = search.interpretation_revision_no
  where search.interpretation_revision_no is not null
    and (
      revision.id is null
      or search.interpretation_category_id is distinct from revision.category_id
      or search.interpretation_technical_family
          is distinct from revision.technical_family
    )
) then 1 else 0 end) as stamped_searches_match_their_revision;

-- El backfill sólo declara continuidad para una procedencia que por contrato
-- conserva alcance. Las revisiones nuevas de precisión tienen su propia
-- procedencia explícita; todo legacy desconocido queda nulo y falla cerrado.
select 1 / (case when not exists (
  select 1
  from public.supply_need_interpretation_revisions revision
  where revision.continuity = 'refined'
    and revision.formula_version not in (
      'family-choice-v1', 'operator-refinement-v1'
    )
) then 1 else 0 end) as refined_lineage_has_known_provenance;

select 1 / (case when not exists (
  select 1
  from public.supply_need_interpretation_revisions revision
  where revision.continuity in ('refined', 'replaced')
    and not exists (
      select 1
      from public.supply_need_interpretation_revisions previous
      where previous.tenant_id = revision.tenant_id
        and previous.supply_need_id = revision.supply_need_id
        and previous.revision_no = revision.supersedes_revision_no
    )
) then 1 else 0 end) as every_declared_predecessor_exists;

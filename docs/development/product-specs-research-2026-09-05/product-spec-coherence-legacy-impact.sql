-- Read-only effect of consolidating the four inherited scalar bounds.
with pairs(lo,hi) as (values
 ('smallest_cog_teeth','largest_cog_teeth'),('tube_width_min_mm','tube_width_max_mm'),
 ('tube_width_min_in','tube_width_max_in'),('bearing_inner_diameter_mm','bearing_outer_diameter_mm')),
 units as (
 select t.id template_id,t.key template_key,p.*,a.unit lower_unit,b.unit upper_unit,
 a.data_type lower_type,b.data_type upper_type,a.id lower_id,b.id upper_id
 from pairs p join public.spec_definitions a on a.key=p.lo
 join public.spec_template_fields af on af.spec_definition_id=a.id
 join public.spec_templates t on t.id=af.template_id
 join public.spec_template_fields bf on bf.template_id=t.id
 join public.spec_definitions b on b.id=bf.spec_definition_id and b.key=p.hi
 where coalesce(t.form_contract->'roles'->>a.key,'primary')<>'legacy'
 and coalesce(t.form_contract->'roles'->>b.key,'primary')<>'legacy'
), paired_facts as (
 select distinct f.subject_id product_id,f.tenant_id,u.template_key,u.lo,u.hi,f.value_number lower_value,g.value_number upper_value
 from units u join public.spec_facts f on f.spec_definition_id=u.lower_id and f.subject_type='product' and f.subject_scope is null
 join public.spec_facts g on g.spec_definition_id=u.upper_id and g.subject_type='product' and g.subject_scope is null
   and g.subject_id=f.subject_id and g.tenant_id=f.tenant_id
 join public.product_spec_bindings_internal_v1 b on b.product_id=f.subject_id and b.template_id=u.template_id
)
select jsonb_build_object('active_template_pairs',(select coalesce(jsonb_agg(to_jsonb(u) order by template_key,lo),'[]') from units u),
 'unit_mismatches',(select count(*) from units where lower_unit is distinct from upper_unit or lower_type<>'number' or upper_type<>'number'),
 'observed_pairs',(select count(*) from paired_facts),
 'inverted_pairs',(select coalesce(jsonb_agg(to_jsonb(p) order by product_id,lo),'[]') from paired_facts p where lower_value>upper_value)) as impact;

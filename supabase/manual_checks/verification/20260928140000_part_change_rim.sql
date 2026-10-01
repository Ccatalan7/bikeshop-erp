-- Read-back de 20260928140000_part_change_rim. Antes de desplegar tiene que
-- fallar contra producción (la relación no existe o no tiene la llanta).

-- La relación única: la llanta cambia el BSD y las perforaciones de la rueda
-- que eligió el mecánico (sin condición de posición: ninguna llanta la
-- dice). Lo de antes sigue igual: el neumático calza, la maza revisa.
select 1 / (case when
  (select count(*) from public.bike_fact_spec_links) = 19
  and (select count(*) from public.bike_fact_spec_links
        where template_key = 'rim'
          and on_mismatch = 'change'
          and product_condition is null
          and value_map is null
          and (
            (spec_key = 'bead_seat_diameter_mm' and min_value = 150 and max_value = 700
             and bike_fact_key = case position when 'front' then 'frontWheelBsdMm' else 'rearWheelBsdMm' end)
            or (spec_key = 'spoke_hole_count' and min_value = 12 and max_value = 48
             and bike_fact_key = case position when 'front' then 'frontSpokeHoles' else 'rearSpokeHoles' end)
          )) = 4
  and (select count(*) from public.bike_fact_spec_links
        where template_key = 'tire'
          and spec_key = 'bead_seat_diameter_mm'
          and on_mismatch = 'conflict') = 2
  and (select count(*) from public.bike_fact_spec_links
        where template_key = 'hub'
          and spec_key = 'spoke_hole_count'
          and on_mismatch = 'check') = 2
then 1 else 0 end) as relacion_llanta;

-- Con el inventario real: las 44 llantas dicen sus perforaciones y sólo las
-- que tienen BSD en su ficha técnica lo proponen (9 el 2026-09-28); ninguna
-- lo toma de su nombre. La U32 TL 29" propone 622 y 32; la FOSS F22 sólo 32.
select 1 / (case when
  (select count(*)
     from public.products p
     join public.product_spec_bindings_internal_v1 b on b.product_id = p.id
     join public.bike_fact_spec_links l
       on l.template_key = 'rim' and l.position = 'rear' and l.spec_key = 'spoke_hole_count'
    where b.template_key = 'rim'
      and public.bike_fact_link_value_internal(l,
            public.product_bike_fact_spec_internal(p.tenant_id, p.id, l.spec_key)) is not null)
  = (select count(*)
       from public.products p
       join public.product_spec_bindings_internal_v1 b on b.product_id = p.id
      where b.template_key = 'rim')
  and (select count(*)
         from public.products p
         join public.product_spec_bindings_internal_v1 b on b.product_id = p.id
         join public.bike_fact_spec_links l
           on l.template_key = 'rim' and l.position = 'rear' and l.spec_key = 'bead_seat_diameter_mm'
        where b.template_key = 'rim'
          and public.bike_fact_link_value_internal(l,
                public.product_bike_fact_spec_internal(p.tenant_id, p.id, l.spec_key)) is not null)
      = (select count(*)
           from public.products p
           join public.product_spec_bindings_internal_v1 b on b.product_id = p.id
          where b.template_key = 'rim'
            and public.product_bike_fact_spec_internal(p.tenant_id, p.id, 'bead_seat_diameter_mm')->>'value'
                is not null)
  and (select jsonb_agg(public.bike_fact_link_value_internal(l,
                public.product_bike_fact_spec_internal(p.tenant_id, p.id, l.spec_key))
                order by l.spec_key)
         from public.products p, public.bike_fact_spec_links l
        where p.name = 'Llanta Weinmann U32 TL 29" Ojetillos 32H Presta Negro'
          and l.template_key = 'rim' and l.position = 'rear')
      = '[622, 32]'::jsonb
  and (select jsonb_agg(public.bike_fact_link_value_internal(l,
                public.product_bike_fact_spec_internal(p.tenant_id, p.id, l.spec_key))
                order by l.spec_key)
         from public.products p, public.bike_fact_spec_links l
        where p.name = 'Llanta FOSS F22 Aluminio Doble Pared con Ojetillos 29x32H'
          and l.template_key = 'rim' and l.position = 'rear')
      = '[null, 32]'::jsonb
then 1 else 0 end) as inventario_real;

-- Las reglas: la llanta es una pieza que calza con su Enrayado, su maza y su
-- neumático; el neumático se mide con la llanta del trabajo; una pieza sin
-- medida no esconde la que la dice; el aro escrito que la ficha contradice no
-- refuta; la maza que queda es la de antes del trabajo; la puerta mira el
-- neumático; el comando de guardado abre una espera privada y corre la
-- puerta una vez, después de «Configurar»; y las bicis del trabajo pasan sus
-- líneas de General por la puerta.
select 1 / (case when
  public.bike_fact_requirement_text('rearHubSpokeHoles', '28') = 'la maza trasera tiene 28 perforaciones'
  and public.bike_fact_requirement_text('frontTireBsdMm', '584') = 'el neumático delantero es 584 (27,5″/650b)'
  and public.bike_fact_requirement_text('rearRimBsdMm', '622') = 'la llanta trasera es 622 (29″/700c)'
  and public.bike_fact_requirement_advice('rearTireBsdMm') like 'Una llanta y su neumático tienen el mismo BSD%'
  and pg_get_functiondef('public.bike_fact_part_checks_internal(uuid,uuid,uuid,text,jsonb)'::regprocedure)
    like '%bike_fact_rim_checks_internal%'
  and pg_get_functiondef('public.bike_fact_rim_checks_internal(uuid,uuid,uuid,text,jsonb)'::regprocedure)
    like '%bike_fact_before_job_internal%'
  and pg_get_functiondef('public.bike_fact_part_conflict_internal(uuid,uuid,uuid,text,jsonb,jsonb,jsonb,text)'::regprocedure)
    like '%RimBsdMm%'
  and pg_get_functiondef('public.job_hub_at_wheel_internal(uuid,uuid,uuid,text)'::regprocedure)
    like '%holes_either%'
  and (select count(*) from regexp_matches(
         pg_get_functiondef('public.apply_job_installed_bike_facts_internal(uuid,uuid,boolean)'::regprocedure),
         'el neumático que instala el trabajo', 'g')) = 2
  and pg_get_functiondef('public.job_line_gate_check_internal(public.mechanic_job_items,boolean,jsonb)'::regprocedure)
    like '%when ''tire'' then ''job_tire''%'
  and pg_get_functiondef('public.job_wheel_bsd_internal(uuid,uuid,uuid,text,text)'::regprocedure)
    not like '%count(*) = count(bsd)%'
  and pg_get_functiondef('public.job_hub_at_wheel_internal(uuid,uuid,uuid,text)'::regprocedure)
    not like '%count(*) = count(holes)%'
  and pg_get_functiondef('public.bike_fact_rim_checks_internal(uuid,uuid,uuid,text,jsonb)'::regprocedure)
    like '%or v_before::numeric::integer = any (v_candidates)%'
  and pg_get_functiondef('public.apply_installed_bike_facts_on_job_line_change()'::regprocedure)
    like '%mechanic_job_line_gate_deferrals%'
  and pg_get_functiondef('public.apply_installed_bike_facts_on_job_line_change()'::regprocedure)
    not like '%vinabike.job_line_gate_job%'
  and pg_get_functiondef('public.apply_installed_bike_facts_on_job_line_change()'::regprocedure)
    like '%not in (''hub'', ''rim'', ''tire'')%'
  and (select count(*) from regexp_matches(
         pg_get_functiondef('public.save_mechanic_job_lines_v1(text,uuid,jsonb,jsonb,jsonb,jsonb,jsonb,boolean)'::regprocedure),
         'mechanic_job_line_gate_deferrals', 'g')) = 2
  and position('La puerta del trabajo terminado, una vez, sobre lo que quedó.' in
        pg_get_functiondef('public.save_mechanic_job_lines_v1(text,uuid,jsonb,jsonb,jsonb,jsonb,jsonb,boolean)'::regprocedure))
      > position('Lo que confirmó «Configurar», en la misma transacción que sus líneas.' in
        pg_get_functiondef('public.save_mechanic_job_lines_v1(text,uuid,jsonb,jsonb,jsonb,jsonb,jsonb,boolean)'::regprocedure))
  and position('Lo que confirmó «Configurar», en la misma transacción que sus líneas.' in
        pg_get_functiondef('public.save_mechanic_job_lines_v1(text,uuid,jsonb,jsonb,jsonb,jsonb,jsonb,boolean)'::regprocedure)) > 0
  and (select count(*) from pg_trigger t
        where not t.tgisinternal
          and t.tgfoid = 'public.gate_job_lines_on_job_bike_change()'::regprocedure
          and t.tgrelid in ('public.mechanic_job_bikes'::regclass, 'public.mechanic_jobs'::regclass)) = 2
  and (select c.relrowsecurity from pg_class c
        where c.oid = 'public.mechanic_job_line_gate_deferrals'::regclass)
  and not has_table_privilege('authenticated',
    'public.mechanic_job_line_gate_deferrals', 'SELECT,INSERT,UPDATE,DELETE')
  and not has_table_privilege('service_role',
    'public.mechanic_job_line_gate_deferrals', 'SELECT,INSERT,UPDATE,DELETE')
  and not has_function_privilege('authenticated',
    'public.job_lines_bike_changed_internal(uuid,uuid)', 'EXECUTE')
  and not exists (select 1 from public.mechanic_job_line_gate_deferrals)
  and not has_function_privilege('authenticated',
    'public.bike_fact_rim_checks_internal(uuid,uuid,uuid,text,jsonb)', 'EXECUTE')
  and not has_function_privilege('authenticated',
    'public.job_wheel_bsd_internal(uuid,uuid,uuid,text,text)', 'EXECUTE')
  and not has_function_privilege('authenticated',
    'public.bike_fact_before_job_internal(uuid,uuid,uuid,text,jsonb)', 'EXECUTE')
  and not has_function_privilege('authenticated',
    'public.job_line_gate_check_internal(public.mechanic_job_items,boolean,jsonb)', 'EXECUTE')
  and not has_function_privilege('authenticated',
    'public.mechanic_job_line_gate_internal(uuid,uuid,text)', 'EXECUTE')
  and not has_function_privilege('service_role',
    'public.mechanic_job_line_gate_internal(uuid,uuid,text)', 'EXECUTE')
then 1 else 0 end) as reglas_de_la_llanta;

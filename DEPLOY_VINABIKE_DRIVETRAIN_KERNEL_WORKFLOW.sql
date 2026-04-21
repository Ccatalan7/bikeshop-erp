do $$
declare
  v_profile_id uuid;
begin
  select id
    into v_profile_id
    from public.service_profiles
   where tenant_id is null
     and key = 'derailleur_adjustment'
   limit 1;

  if v_profile_id is null then
    raise exception 'Global service profile derailleur_adjustment not found';
  end if;

  insert into public.service_profile_questions (
    id,
    tenant_id,
    service_profile_id,
    key,
    label,
    question_type,
    is_required,
    sort_order,
    options_json
  )
  values
    (
      '00000000-0003-0001-0000-000000000004'::uuid,
      null,
      v_profile_id,
      'front_chainring_count',
      'Platos delanteros',
      'single_select',
      false,
      1,
      '[{"value":"1","label":"1 plato"},{"value":"2","label":"2 platos"},{"value":"3","label":"3 platos"}]'::jsonb
    ),
    (
      '00000000-0003-0001-0000-000000000005'::uuid,
      null,
      v_profile_id,
      'rear_cog_count',
      'Pinones traseros',
      'single_select',
      false,
      2,
      '[{"value":"1","label":"1 pinon"},{"value":"3","label":"3 pinones"},{"value":"5","label":"5 pinones"},{"value":"6","label":"6 pinones"},{"value":"7","label":"7 pinones"},{"value":"8","label":"8 pinones"},{"value":"9","label":"9 pinones"},{"value":"10","label":"10 pinones"},{"value":"11","label":"11 pinones"},{"value":"12","label":"12 pinones"},{"value":"13","label":"13 pinones"},{"value":"14","label":"14 pinones"}]'::jsonb
    ),
    (
      '00000000-0003-0001-0000-000000000006'::uuid,
      null,
      v_profile_id,
      'freehub_type',
      'Driver / freehub',
      'single_select',
      false,
      3,
      '[{"value":"shimano_hg","label":"Shimano HG"},{"value":"microspline","label":"Micro Spline"},{"value":"sram_xd","label":"SRAM XD"},{"value":"campagnolo","label":"Campagnolo"},{"value":"threaded_freewheel","label":"Rueda libre roscada"},{"value":"bmx_driver","label":"Driver BMX"},{"value":"fixed_threaded","label":"Rosca fija / contratuerca"},{"value":"coaster_hub","label":"Maza contrapedal"},{"value":"unknown","label":"Desconocido / sin confirmar"}]'::jsonb
    )
  on conflict (service_profile_id, key) do update
    set label = excluded.label,
        question_type = excluded.question_type,
        is_required = excluded.is_required,
        sort_order = excluded.sort_order,
        options_json = excluded.options_json,
        updated_at = now();
end
$$;
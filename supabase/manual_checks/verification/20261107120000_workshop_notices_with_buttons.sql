-- Read-back of 20261107120000. Fails before the migration (the helpers do
-- not exist and the notices and the review request only know their `_v1`)
-- and passes after:
-- * Viñabike's real hours and map point come out as the notice says them;
-- * each notice prefers its `_v2` and still falls back to the `_v1`;
-- * the sender builds the button and the map, and the review request knows
--   `resena_google_v2`;
-- * every helper stays closed to every caller role.

select 1 / (case when
  to_regprocedure('public.workshop_notice_hours_internal(uuid)') is not null
  and to_regprocedure('public.workshop_notice_location_internal(uuid)') is not null
  and to_regprocedure('public.workshop_notice_claim_code_internal(public.mechanic_jobs,text,uuid)') is not null
then 1 else 0 end) as ayudantes_existen;

select 1 / (case when
  public.workshop_notice_hours_internal('5443b130-cc28-45af-a420-cd500b288890')
    = 'de lunes a viernes de 10:30 a 19:00 y los sábados de 10:30 a 15:30'
  and public.workshop_notice_location_internal('5443b130-cc28-45af-a420-cd500b288890') ->> 'name' = 'Viñabike'
  and public.workshop_notice_location_internal('5443b130-cc28-45af-a420-cd500b288890') ->> 'address'
    = 'Alvarez 32, Local 17, Viña del Mar'
  and (public.workshop_notice_location_internal('5443b130-cc28-45af-a420-cd500b288890') ->> 'latitude')::numeric
    between -34 and -33
then 1 else 0 end) as horario_y_mapa_de_vinabike;

select 1 / (case when
  pg_get_functiondef('public.workshop_notice_template_internal(uuid, text, text)'::regprocedure)
    like '%array[''taller_recibida_v2'', ''taller_recibida_v1'']%'
  and pg_get_functiondef('public.workshop_notice_template_internal(uuid, text, text)'::regprocedure)
    like '%''taller_lista_v2'', ''taller_lista_v1'', ''bicicleta_lista_retiro''%'
  and pg_get_functiondef('public.workshop_notice_dispatch_whatsapp_internal(uuid, timestamp with time zone, boolean)'::regprocedure)
    like '%''sub_type'', ''url''%'
  and pg_get_functiondef('public.workshop_notice_dispatch_whatsapp_internal(uuid, timestamp with time zone, boolean)'::regprocedure)
    like '%''type'', ''location'', ''location'', v_location%'
  and pg_get_functiondef('public.process_whatsapp_review_requests_v1(timestamp with time zone)'::regprocedure)
    like '%resena_google_v2%'
then 1 else 0 end) as avisos_prefieren_la_v2;

-- An e-mail retry with no time left before the notice expires closes as
-- failed instead of breaking the row's window.
select 1 / (case when
  pg_get_functiondef('public.complete_workshop_customer_notice_v1(uuid, text, text, text, text)'::regprocedure)
    like '%and v_next_at < v_notice.expires_at then%'
  and has_function_privilege('service_role',
    'public.complete_workshop_customer_notice_v1(uuid, text, text, text, text)', 'EXECUTE')
  and not has_function_privilege('authenticated',
    'public.complete_workshop_customer_notice_v1(uuid, text, text, text, text)', 'EXECUTE')
then 1 else 0 end) as reintento_sin_plazo_falla;

-- With nothing approved for this tenant the choice is still null, and the
-- `_v1` that is approved in production stays the one in use until Meta
-- approves the `_v2`.
select 1 / (case when
  public.workshop_notice_template_internal('5443b130-cc28-45af-a420-cd500b288890', 'received', 'bike')
    in ('taller_recibida_v1', 'taller_recibida_v2')
  and public.workshop_notice_template_internal('5443b130-cc28-45af-a420-cd500b288890', 'delivered', 'bike')
    in ('taller_entregada_v1', 'taller_entregada_v2')
  and public.workshop_notice_template_internal('00000000-0000-4000-8000-000000000000', 'received', 'bike') is null
then 1 else 0 end) as la_v1_sigue_mientras_meta_revisa;

select 1 / (case when
  not has_function_privilege('authenticated', 'public.workshop_notice_hours_internal(uuid)', 'EXECUTE')
  and not has_function_privilege('service_role', 'public.workshop_notice_hours_internal(uuid)', 'EXECUTE')
  and not has_function_privilege('anon', 'public.workshop_notice_hours_internal(uuid)', 'EXECUTE')
  and not has_function_privilege('authenticated', 'public.workshop_notice_location_internal(uuid)', 'EXECUTE')
  and not has_function_privilege('service_role', 'public.workshop_notice_location_internal(uuid)', 'EXECUTE')
  and not has_function_privilege('anon', 'public.workshop_notice_location_internal(uuid)', 'EXECUTE')
  and not has_function_privilege('authenticated',
    'public.workshop_notice_claim_code_internal(public.mechanic_jobs, text, uuid)', 'EXECUTE')
  and not has_function_privilege('service_role',
    'public.workshop_notice_claim_code_internal(public.mechanic_jobs, text, uuid)', 'EXECUTE')
  and not has_function_privilege('anon',
    'public.workshop_notice_claim_code_internal(public.mechanic_jobs, text, uuid)', 'EXECUTE')
  and not has_function_privilege('authenticated',
    'public.workshop_notice_dispatch_whatsapp_internal(uuid, timestamp with time zone, boolean)', 'EXECUTE')
  and has_function_privilege('service_role',
    'public.process_whatsapp_review_requests_v1(timestamp with time zone)', 'EXECUTE')
  and not has_function_privilege('authenticated',
    'public.process_whatsapp_review_requests_v1(timestamp with time zone)', 'EXECUTE')
then 1 else 0 end) as ayudantes_cerrados;

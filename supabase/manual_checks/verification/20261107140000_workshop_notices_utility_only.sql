-- Read-back of 20261107140000. Fails before the migration (the helper does
-- not exist) and passes after:
-- * every notice of Viñabike still has a template, and none is one that Meta
--   keeps as anything but UTILITY (`taller_lista_v2` came back MARKETING);
-- * the dispatcher knows `taller_lista_v3` and the notices page reads the
--   category;
-- * the helper stays closed.

select 1 / (case when
  to_regprocedure('public.workshop_notice_template_usable_internal(uuid,text)') is not null
then 1 else 0 end) as ayuda_existe;

select 1 / (case when not exists (
  select 1
    from (values ('received'), ('quote_ready'), ('ready'), ('delivered')) as moment(kind)
    cross join lateral (
      select public.workshop_notice_template_internal(
        '5443b130-cc28-45af-a420-cd500b288890', moment.kind, 'bike') as name
    ) chosen
    left join public.whatsapp_template_reviews review
      on review.tenant_id = '5443b130-cc28-45af-a420-cd500b288890'
     and review.template_name = chosen.name
     and review.template_language = 'es_CL'
   where chosen.name is null
      or review.category is distinct from 'UTILITY'
) then 1 else 0 end) as avisos_solo_de_servicio;

select 1 / (case when
  position('review.category' in
    pg_get_functiondef('public.workshop_customer_notice_overview_v1(uuid)'::regprocedure)) > 0
  and position('taller_lista_v3' in
    pg_get_functiondef('public.workshop_notice_dispatch_whatsapp_internal(uuid,timestamptz,boolean)'::regprocedure)) > 0
  and has_function_privilege('authenticated', 'public.workshop_customer_notice_overview_v1(uuid)', 'EXECUTE')
  and not has_function_privilege('anon', 'public.workshop_notice_template_usable_internal(uuid, text)', 'EXECUTE')
  and not has_function_privilege('authenticated', 'public.workshop_notice_template_usable_internal(uuid, text)', 'EXECUTE')
  and not has_function_privilege('service_role', 'public.workshop_notice_template_usable_internal(uuid, text)', 'EXECUTE')
then 1 else 0 end) as pagina_y_envio_al_dia;

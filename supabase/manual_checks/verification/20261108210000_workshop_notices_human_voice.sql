-- Read-back of 20261108210000. Fails before the migration and passes after:
-- * each notice prefers its human-voice template once Meta approves it;
-- * the sender writes the bike, not the job number, in the new templates;
-- * the review request prefers resena_google_v3;
-- * the three functions keep their grants.

select 1 / (case when
  position('taller_recibida_v3' in pg_get_functiondef(
    'public.workshop_notice_template_v2_internal(uuid,text,text,boolean)'::regprocedure)) > 0
  and position('taller_presupuesto_pdf_v2' in pg_get_functiondef(
    'public.workshop_notice_template_v2_internal(uuid,text,text,boolean)'::regprocedure)) > 0
  and position('taller_lista_v4' in pg_get_functiondef(
    'public.workshop_notice_template_v2_internal(uuid,text,text,boolean)'::regprocedure)) > 0
  and position('taller_entregada_pdf_v2' in pg_get_functiondef(
    'public.workshop_notice_template_v2_internal(uuid,text,text,boolean)'::regprocedure)) > 0
then 1 else 0 end) as avisos_prefieren_trato_humano;

select 1 / (case when
  position('ya tenemos tu %s en el taller' in pg_get_functiondef(
    'public.workshop_notice_dispatch_whatsapp_internal(uuid,timestamptz,boolean)'::regprocedure)) > 0
  and position('te dejamos el presupuesto para tu %s' in pg_get_functiondef(
    'public.workshop_notice_dispatch_whatsapp_internal(uuid,timestamptz,boolean)'::regprocedure)) > 0
then 1 else 0 end) as envio_nombra_la_bici;

select 1 / (case when
  position('resena_google_v3' in pg_get_functiondef(
    'public.process_whatsapp_review_requests_v1(timestamptz)'::regprocedure)) > 0
then 1 else 0 end) as resena_nombra_la_bici;

select 1 / (case when
  not has_function_privilege('authenticated', 'public.workshop_notice_dispatch_whatsapp_internal(uuid,timestamptz,boolean)', 'EXECUTE')
  and not has_function_privilege('service_role', 'public.workshop_notice_dispatch_whatsapp_internal(uuid,timestamptz,boolean)', 'EXECUTE')
  and not has_function_privilege('authenticated', 'public.workshop_notice_template_v2_internal(uuid,text,text,boolean)', 'EXECUTE')
  and has_function_privilege('service_role', 'public.process_whatsapp_review_requests_v1(timestamptz)', 'EXECUTE')
  and not has_function_privilege('authenticated', 'public.process_whatsapp_review_requests_v1(timestamptz)', 'EXECUTE')
  and not has_function_privilege('anon', 'public.process_whatsapp_review_requests_v1(timestamptz)', 'EXECUTE')
then 1 else 0 end) as permisos_iguales;

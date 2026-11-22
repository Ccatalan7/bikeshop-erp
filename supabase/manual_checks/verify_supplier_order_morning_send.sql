-- 20261122030000: el pedido abierto de un proveedor sale solo en la mañana.
-- Falla si faltan los feriados, la hora de envío o su regla, la pasada de
-- cada minuto o la de los feriados, el código del PDF que lee la tienda, la
-- guardia que no deja reabrir un pedido enviado, o si alguno de los internos
-- quedó a la mano del equipo. SQL plano, sin control de transacción: corre por
-- el envoltorio de lectura.

-- Los feriados de 2026 y 2027 y la regla del día hábil.
select 1 / case
  when (select count(*) from public.chile_public_holidays
         where holiday_date between date '2026-01-01' and date '2027-12-31') >= 33
   and not public.chile_business_day_internal(date '2026-12-08')
   and public.chile_business_day_internal(date '2026-11-23')
   and not public.chile_business_day_internal(date '2026-11-21')
  then 1 else 0 end as business_days;

-- La hora de cada proveedor: 09:30 si nadie la cambia, nunca de noche.
select 1 / case
  when exists (
    select 1 from information_schema.columns
     where table_schema = 'public' and table_name = 'suppliers'
       and column_name = 'order_send_time')
   and exists (
    select 1 from pg_constraint
     where conrelid = 'public.suppliers'::regclass
       and conname = 'suppliers_order_send_time_hours')
   and public.supplier_order_next_send_at_internal(
         timestamptz '2026-11-20 18:00 America/Santiago', time '09:30')
       = timestamptz '2026-11-23 09:30 America/Santiago'
  then 1 else 0 end as send_hour_rule;

-- Las pasadas: la del envío cada minuto y la de los feriados cada hora.
select 1 / case
  when (select count(*) from cron.job
         where jobname = 'vinabike_supplier_order_dispatch'
           and schedule = '* * * * *' and active) = 1
   and (select count(*) from cron.job
         where jobname = 'vinabike_chile_public_holidays'
           and schedule = '17 * * * *' and active) = 1
  then 1 else 0 end as cron_jobs;

-- La tienda lee el pedido con su código; los avisos del taller siguen igual.
select 1 / case
  when position('supplier_order_document_tokens' in pg_get_functiondef(
         'public.workshop_notice_document_v1(text)'::regprocedure)) > 0
   and position('job_quote_document_projection_internal' in pg_get_functiondef(
         'public.workshop_notice_document_v1(text)'::regprocedure)) > 0
   and has_function_privilege('anon', 'public.workshop_notice_document_v1(text)', 'EXECUTE')
  then 1 else 0 end as store_reads_the_order;

-- Un pedido enviado con ventas web no vuelve a borrador desde una app.
select 1 / case
  when position('supplier_order_already_sent' in pg_get_functiondef(
         'public.supplier_open_order_guard()'::regprocedure)) > 0
   and exists (
    select 1 from pg_trigger t
     where t.tgrelid = 'public.purchase_invoices'::regclass
       and t.tgname = 'trg_supplier_open_order_guard'
       and t.tgenabled <> 'D')
  then 1 else 0 end as sent_order_stays_sent;

-- El equipo lee cuándo sale; sólo la base envía.
select 1 / case
  when has_function_privilege('authenticated',
         'public.supplier_open_order_schedule_v1(uuid,uuid)', 'EXECUTE')
   and not has_function_privilege('anon',
         'public.supplier_open_order_schedule_v1(uuid,uuid)', 'EXECUTE')
   and not has_function_privilege('authenticated',
         'public.process_supplier_order_dispatches_v1(timestamptz)', 'EXECUTE')
   and not has_function_privilege('authenticated',
         'public.supplier_order_dispatch_internal(uuid,timestamptz,timestamptz)', 'EXECUTE')
   and not has_function_privilege('authenticated',
         'public.purchase_order_mark_sent_internal(uuid,uuid)', 'EXECUTE')
   and has_function_privilege('authenticated',
         'public.purchase_order_mark_sent_v1(uuid,uuid,jsonb)', 'EXECUTE')
  then 1 else 0 end as only_the_database_sends;

-- El aviso al teléfono y la proyección de Pedidos web.
select 1 / case
  when exists (
    select 1 from pg_trigger t
     where t.tgrelid = 'public.supplier_order_dispatches'::regclass
       and t.tgname = 'trg_supplier_order_dispatch_push_alert'
       and t.tgenabled <> 'D')
   and position('''send_at''' in pg_get_functiondef(
         'public.online_order_on_order_projection_internal(uuid)'::regprocedure)) > 0
  then 1 else 0 end as alert_and_projection;

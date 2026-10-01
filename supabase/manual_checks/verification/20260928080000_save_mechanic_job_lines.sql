-- Read-back de 20260928080000_save_mechanic_job_lines. Antes de desplegar
-- tiene que fallar contra producción (no existen el comando ni sus recibos).

-- El comando es del empleado autenticado; ni el anónimo ni service_role.
select 1 / (case when
  to_regprocedure('public.save_mechanic_job_lines_v1(text,uuid,jsonb,jsonb,jsonb,jsonb,jsonb,boolean)') is not null
  and has_function_privilege('authenticated',
    'public.save_mechanic_job_lines_v1(text,uuid,jsonb,jsonb,jsonb,jsonb,jsonb,boolean)', 'EXECUTE')
  and not has_function_privilege('anon',
    'public.save_mechanic_job_lines_v1(text,uuid,jsonb,jsonb,jsonb,jsonb,jsonb,boolean)', 'EXECUTE')
  and not has_function_privilege('service_role',
    'public.save_mechanic_job_lines_v1(text,uuid,jsonb,jsonb,jsonb,jsonb,jsonb,boolean)', 'EXECUTE')
then 1 else 0 end) as comando_y_permisos;

-- Los recibos: uno por taller y llave, con RLS y sin escritura directa.
select 1 / (case when
  to_regclass('public.mechanic_job_line_saves') is not null
  and (select relrowsecurity from pg_class
        where oid = 'public.mechanic_job_line_saves'::regclass)
  and exists (
    select 1 from pg_constraint
     where conrelid = 'public.mechanic_job_line_saves'::regclass
       and contype = 'u'
       and pg_get_constraintdef(oid) = 'UNIQUE (tenant_id, operation_key)')
  and not has_table_privilege('authenticated',
    'public.mechanic_job_line_saves', 'INSERT')
  and not has_table_privilege('anon',
    'public.mechanic_job_line_saves', 'SELECT')
then 1 else 0 end) as recibos;

-- Versión de las líneas, ficha en la misma transacción con llave derivada, y
-- ningún 40001 que PostgREST reintente sin fin.
select 1 / (case when
  pg_get_functiondef('public.save_mechanic_job_lines_v1(text,uuid,jsonb,jsonb,jsonb,jsonb,jsonb,boolean)'::regprocedure)
    like '%job_lines_changed%'
  and pg_get_functiondef('public.save_mechanic_job_lines_v1(text,uuid,jsonb,jsonb,jsonb,jsonb,jsonb,boolean)'::regprocedure)
    like '%patch_bike_technical_facts_v1%'
  and pg_get_functiondef('public.save_mechanic_job_lines_v1(text,uuid,jsonb,jsonb,jsonb,jsonb,jsonb,boolean)'::regprocedure)
    like '%'':ficha:''%'
  and pg_get_functiondef('public.save_mechanic_job_lines_v1(text,uuid,jsonb,jsonb,jsonb,jsonb,jsonb,boolean)'::regprocedure)
    not like '%errcode = ''40001''%'
then 1 else 0 end) as versiones_y_ficha;

-- La cabecera por campo con su valor visto y protegida con la factura
-- pagada, el total recalculado tras el descuento, las bicis del trabajo en
-- la misma transacción, y las tareas sólo desde su disparador (ninguna
-- descripción llega del formulario). Las formas anteriores no quedaron.
select 1 / (case when
  pg_get_functiondef('public.save_mechanic_job_lines_v1(text,uuid,jsonb,jsonb,jsonb,jsonb,jsonb,boolean)'::regprocedure)
    like '%job_header_changed%'
  and pg_get_functiondef('public.save_mechanic_job_lines_v1(text,uuid,jsonb,jsonb,jsonb,jsonb,jsonb,boolean)'::regprocedure)
    like '%v_paid_protected_columns%'
  and pg_get_functiondef('public.save_mechanic_job_lines_v1(text,uuid,jsonb,jsonb,jsonb,jsonb,jsonb,boolean)'::regprocedure)
    like '%recalculate_mechanic_job_costs%'
  and pg_get_functiondef('public.save_mechanic_job_lines_v1(text,uuid,jsonb,jsonb,jsonb,jsonb,jsonb,boolean)'::regprocedure)
    like '%job_bikes_changed%'
  and pg_get_functiondef('public.save_mechanic_job_lines_v1(text,uuid,jsonb,jsonb,jsonb,jsonb,jsonb,boolean)'::regprocedure)
    not like '%auto_task_description%'
  and exists (
    select 1 from pg_trigger
     where tgrelid = 'public.mechanic_job_items'::regclass
       and tgname = 'trg_auto_parse_item_description'
       and tgenabled <> 'D')
  and to_regprocedure('public.save_mechanic_job_lines_v1(text,uuid,jsonb,jsonb,jsonb)') is null
  and to_regprocedure('public.save_mechanic_job_lines_v1(text,uuid,jsonb,jsonb,jsonb,jsonb)') is null
  and to_regprocedure('public.save_mechanic_job_lines_v1(text,uuid,jsonb,jsonb,jsonb,jsonb,jsonb)') is null
then 1 else 0 end) as cabecera_bicis_y_tareas;

-- La factura del trabajo en la misma transacción que el recibo, decidida en
-- un solo lugar: confirmada no se reescribe (y el comando rechaza antes lo
-- que cambiaría lo que se cobra), un error pasajero deshace todo como 55P03 y
-- uno del dato queda `failed`. La repetición de la llave la vuelve a intentar.
select 1 / (case when
  to_regprocedure('public.mechanic_job_invoice_step_internal(uuid,uuid)') is not null
  and pg_get_functiondef('public.mechanic_job_invoice_step_internal(uuid,uuid)'::regprocedure)
    like '%create_billable_invoice_from_mechanic_job%'
  and pg_get_functiondef('public.mechanic_job_invoice_step_internal(uuid,uuid)'::regprocedure)
    like '%perform public.sync_job_to_invoice(p_job_id)%'
  and pg_get_functiondef('public.mechanic_job_invoice_step_internal(uuid,uuid)'::regprocedure)
    like '%v_action := ''posted''%'
  and pg_get_functiondef('public.mechanic_job_invoice_step_internal(uuid,uuid)'::regprocedure)
    like '%invoice_retry%'
  and pg_get_functiondef('public.mechanic_job_invoice_step_internal(uuid,uuid)'::regprocedure)
    not like '%errcode = ''40001''%'
  and not has_function_privilege('authenticated',
    'public.mechanic_job_invoice_step_internal(uuid,uuid)', 'EXECUTE')
  and not has_function_privilege('anon',
    'public.mechanic_job_invoice_step_internal(uuid,uuid)', 'EXECUTE')
  and pg_get_functiondef('public.save_mechanic_job_lines_v1(text,uuid,jsonb,jsonb,jsonb,jsonb,jsonb,boolean)'::regprocedure)
    like '%invoice_posted%'
  and pg_get_functiondef('public.save_mechanic_job_lines_v1(text,uuid,jsonb,jsonb,jsonb,jsonb,jsonb,boolean)'::regprocedure)
    like '%mechanic_job_invoice_lock_internal%'
  and pg_get_functiondef('public.mechanic_job_invoice_step_internal(uuid,uuid)'::regprocedure)
    like '%mechanic_job_invoice_lock_internal%'
  and pg_get_functiondef('public.save_mechanic_job_lines_v1(text,uuid,jsonb,jsonb,jsonb,jsonb,jsonb,boolean)'::regprocedure)
    like '%result_snapshot->''invoice''->>''action'' = ''failed''%'
then 1 else 0 end) as factura_en_el_comando;

-- La continuación de la factura: del empleado autenticado, por llave y
-- taller, y escribe el resultado en el recibo.
select 1 / (case when
  to_regprocedure('public.continue_mechanic_job_invoice_v1(text)') is not null
  and has_function_privilege('authenticated',
    'public.continue_mechanic_job_invoice_v1(text)', 'EXECUTE')
  and not has_function_privilege('anon',
    'public.continue_mechanic_job_invoice_v1(text)', 'EXECUTE')
  and not has_function_privilege('service_role',
    'public.continue_mechanic_job_invoice_v1(text)', 'EXECUTE')
  and pg_get_functiondef('public.continue_mechanic_job_invoice_v1(text)'::regprocedure)
    like '%mechanic_job_invoice_step_internal%'
  and pg_get_functiondef('public.continue_mechanic_job_invoice_v1(text)'::regprocedure)
    like '%update public.mechanic_job_line_saves%'
then 1 else 0 end) as continuacion_de_la_factura;

-- El parche de la ficha toma el trabajo antes que la llave y la bici con
-- cualquier fuente.
select 1 / (case when
  position('Con cualquier fuente, el trabajo antes que la bici' in pg_get_functiondef(
    'public.patch_bike_technical_facts_v1(text,uuid,uuid,text,jsonb)'::regprocedure))
    between 1 and position('pg_advisory_xact_lock' in pg_get_functiondef(
    'public.patch_bike_technical_facts_v1(text,uuid,uuid,text,jsonb)'::regprocedure))
then 1 else 0 end) as parche_toma_el_trabajo;

-- La consulta del recibo existe, sólo para el empleado autenticado.
select 1 / (case when
  to_regprocedure('public.get_mechanic_job_line_save_v1(text)') is not null
  and has_function_privilege('authenticated',
    'public.get_mechanic_job_line_save_v1(text)', 'EXECUTE')
  and not has_function_privilege('anon',
    'public.get_mechanic_job_line_save_v1(text)', 'EXECUTE')
then 1 else 0 end) as consulta_del_recibo;

-- Una línea que cambia de bici recalcula también la bici de antes.
select 1 / (case when
  pg_get_functiondef('public.recalculate_job_bike_costs()'::regprocedure)
    like '%array[OLD.job_bike_id, NEW.job_bike_id]%'
  and pg_get_functiondef('public.recalculate_job_bike_costs()'::regprocedure)
    like '%search_path%'
then 1 else 0 end) as costos_por_bici;

-- Una sola regla de lo que protege la factura (pagos, confirmada, nota de
-- crédito), también para las escrituras directas y `sync_job_to_invoice`.
select 1 / (case when
  to_regprocedure('public.mechanic_job_invoice_lock_internal(uuid,uuid)') is not null
  and pg_get_functiondef('public.mechanic_job_invoice_lock_internal(uuid,uuid)'::regprocedure)
    like '%sales_credit_notes%'
  and not has_function_privilege('authenticated',
    'public.mechanic_job_invoice_lock_internal(uuid,uuid)', 'EXECUTE')
  and pg_get_functiondef('public.guard_paid_workshop_child_mutation()'::regprocedure)
    like '%mechanic_job_invoice_lock_internal%'
  and pg_get_functiondef('public.guard_paid_workshop_job_commercial_update()'::regprocedure)
    like '%mechanic_job_invoice_lock_internal%'
  and pg_get_functiondef('public.sync_job_to_invoice(uuid)'::regprocedure)
    like '%mechanic_job_invoice_lock_internal%'
then 1 else 0 end) as una_regla_de_factura;

-- Read-back de 20260928051000_workshop_command_attempts. Antes de desplegar
-- tiene que fallar contra producción (la tabla no existe).

select 1 / (case when
  to_regclass('public.workshop_command_attempts') is not null
  and (select relrowsecurity from pg_class
        where oid = 'public.workshop_command_attempts'::regclass)
  and has_table_privilege('authenticated', 'public.workshop_command_attempts', 'SELECT')
  and not has_table_privilege('authenticated', 'public.workshop_command_attempts', 'INSERT')
  and not has_table_privilege('authenticated', 'public.workshop_command_attempts', 'UPDATE')
  and not has_table_privilege('authenticated', 'public.workshop_command_attempts', 'DELETE')
  and not has_table_privilege('anon', 'public.workshop_command_attempts', 'SELECT')
then 1 else 0 end) as tabla_de_intentos;

select 1 / (case when
  has_function_privilege('authenticated',
    'public.record_workshop_command_attempts_v1(jsonb)', 'EXECUTE')
  and not has_function_privilege('anon',
    'public.record_workshop_command_attempts_v1(jsonb)', 'EXECUTE')
  and not has_function_privilege('service_role',
    'public.record_workshop_command_attempts_v1(jsonb)', 'EXECUTE')
  and pg_get_functiondef('public.record_workshop_command_attempts_v1(jsonb)'::regprocedure)
    like '%on conflict (tenant_id, attempt_id) do nothing%'
  and pg_get_functiondef('public.record_workshop_command_attempts_v1(jsonb)'::regprocedure)
    like '%public.user_tenant_id()%'
then 1 else 0 end) as anotar_intentos;

select 1 / (case when
  pg_get_constraintdef((select oid from pg_constraint
    where conname = 'workshop_command_attempts_outcome_check'))
    like '%committed%reconciled%rejected%stale%offline%discarded%'
then 1 else 0 end) as seis_resultados;

-- Los comandos que anota la bandeja, también la continuación de la factura
-- de un guardado del trabajo (20260928080000), la decisión de garantía, el
-- alta del trabajo y el registro de su garantía (20260929010000).
select 1 / (case when
  pg_get_constraintdef((select oid from pg_constraint
    where conname = 'workshop_command_attempts_kind_check'))
    like '%job_line_save%job_invoice_continuation%job_status_transition%job_warranty_decision%job_create%job_warranty_registration%'
then 1 else 0 end) as comandos_anotados;

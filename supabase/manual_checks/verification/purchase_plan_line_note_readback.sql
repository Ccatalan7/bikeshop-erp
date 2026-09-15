-- Read-back de la nota de la línea del plan (20260819100000).
-- Falla a nivel SQL —división por cero— si algo no quedó instalado.
--
-- Es de sólo lectura: no escribe ninguna nota ni toca ningún plan real. Lo que
-- exige es la forma del contrato, no un dato del taller.

-- La columna existe y es de texto, o el comando no tiene dónde escribir.
select 1 / (case when exists (
  select 1 from information_schema.columns
  where table_schema = 'public'
    and table_name = 'purchase_plan_lines'
    and column_name = 'note'
    and data_type = 'text'
) then 1 else 0 end) as note_column_installed;

-- Su check rechaza el blanco: «sin nota» es NULL y nunca una cadena vacía que
-- después nadie sabe si es un dato o un descuido.
select 1 / (case when exists (
  select 1 from pg_constraint
  where conrelid = 'public.purchase_plan_lines'::regclass
    and conname = 'purchase_plan_lines_note_check'
    and contype = 'c'
) then 1 else 0 end) as blank_note_refused_by_the_column;

-- El ledger admite la acción, o el recibo del comando revienta al insertarse
-- y el replay deja de existir.
select 1 / (case when exists (
  select 1 from pg_constraint
  where conrelid = 'public.purchase_plan_events'::regclass
    and conname = 'purchase_plan_events_action_check'
    and pg_get_constraintdef(oid) like '%line_note_changed%'
) then 1 else 0 end) as ledger_admits_line_note_changed;

-- La función está con su firma exacta, es SECURITY DEFINER y trae el
-- `search_path` fijado: sin eso, un esquema en el path del llamador podría
-- cambiar a qué tabla escribe.
select 1 / (case when exists (
  select 1
  from pg_proc p
  where p.oid = to_regprocedure(
    'public.set_purchase_plan_line_note_v1(uuid,bigint,uuid,text,text)'
  )
    and p.prosecdef
    and array_to_string(p.proconfig, ',') like '%search_path=%'
) then 1 else 0 end) as command_installed_with_its_guards;

-- El operador puede ejecutarla.
select 1 / (case when has_function_privilege(
  'authenticated',
  'public.set_purchase_plan_line_note_v1(uuid,bigint,uuid,text,text)',
  'execute'
) then 1 else 0 end) as operator_may_run_it;

-- Y `public` no.
select 1 / (case when not has_function_privilege(
  'public',
  'public.set_purchase_plan_line_note_v1(uuid,bigint,uuid,text,text)',
  'execute'
) then 1 else 0 end) as public_may_not_run_it;

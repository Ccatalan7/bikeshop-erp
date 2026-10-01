-- Restaurar un respaldo cuando falta el archivo de un adjunto o una foto
-- (cierre del Master Schema, 2026-09-29).
--
-- El respaldo guarda las filas, no los archivos de Storage. Desde
-- 20260929020000 un trabajo o una bici no acepta una URL nueva de
-- `job-images` o `bike-images` cuyo archivo no está (o que es de otra
-- carpeta), y restaurar inserta las filas de nuevo: un solo archivo que faltara
-- detenía la restauración entera (el bloque de `restore_backup_legacy_*`
-- atrapa el error y deshace todo).
--
-- Decisión (Codex y Claude, con la delegación del dueño del 2026-09-29): se
-- restauran los datos y se omite sólo la URL que el disparador no admitiría
-- (`managed_image_url_problem`: el archivo ya no está, o es de la carpeta de
-- otro trabajo o bici). Nada queda apuntando a un archivo que no existe o que es
-- de otro registro, y nada se omite en silencio:
-- - la respuesta trae `omitted_attachments`: tabla, registro, rótulo (número
--   del trabajo, marca y modelo de la bici), campo, URL y motivo; una lista
--   vacía dice que no faltó nada;
-- - el respaldo guarda ese informe en `restore_report` (fecha y lista), para
--   verlo después en Respaldos;
-- - el respaldo mismo no cambia (sigue nombrando la URL, para quien lo
--   descargue).
-- Las URL de otros buckets o sitios no se juzgan, como en el disparador.
--
-- La restauración sigue siendo una sola: la función de antes (renombrada
-- `restore_backup_legacy_rows_internal`, sin cambios) borra e inserta dentro
-- de su bloque, y si algo falla no queda nada a medias.
--
-- Lo que se encontró al revisarla con datos reales (2026-09-29), y la
-- revisión de Codex:
-- - El respaldo guarda 38 tablas y la restauración las borra y reinserta,
--   pero el esquema creció. En producción, 173 llaves foráneas desde tablas
--   que el respaldo no guarda bloquean ese borrado (hoy falla en todos los
--   talleres en `payment_terminal_terms`, que cada taller trae al crearse), 70
--   borrarían en cascada lo que el respaldo no devuelve (fichas técnicas,
--   historia de las bicis, bicis de los trabajos, tareas, fotos de productos,
--   líneas de facturas de compra…) y 48 dejarían vínculos en null. Que falle
--   era lo único que protegía esos datos.
-- - Un respaldo antiguo no trae todas las tablas: el único completado del
--   taller principal (2025-12-09) no guarda las 7 de la mensajería (es de
--   antes de 20260508164500). Restaurarlo borraba todos los mensajes de hoy
--   y no los reponía, con éxito. (Las que guarda en `null` estaban vacías.)
-- Decisión: restaurar nunca borra lo que el respaldo no devuelve.
-- - `restore_backup` se niega antes de tocar nada si al respaldo le falta una
--   tabla (`restore_backup_incomplete`) o si hay filas que dependen de lo que
--   borraría y que el respaldo no guarda o son de otro taller
--   (`restore_would_lose_uncovered_data`, leído del catálogo de llaves con el
--   mismo alcance que el borrado: `restore_backup_covered_scope`).
-- - El motor repite esas dos comprobaciones después de cercar las tablas que
--   va a reemplazar y tomar las filas del taller: la negativa vale también
--   para quien lo llame directo (`restore_backup_internal` admite
--   `service_role`) y para una fila que otra sesión agregue entre la consulta
--   y el borrado.
-- - La app pregunta lo mismo antes de ofrecer el botón
--   (`restore_backup_preflight`), también si cambiaron los proveedores o las
--   facturas de compra, que el motor exige iguales.
-- Reconstruir la restauración para que cubra todo el esquema es trabajo aparte.
begin;

alter table public.database_backups
  add column if not exists restore_report jsonb;

comment on column public.database_backups.restore_report is
  'Informe de la última restauración: restored_at y omitted_attachments (los adjuntos y fotos cuyo archivo ya no estaba y se omitieron; lista vacía si no faltó ninguno).';

-- [p_rows] (las filas de [p_table] del respaldo) sin las URL de [p_bucket]
-- cuyo archivo falta o no es de la carpeta de su fila, y lo que se omitió.
create or replace function public.backup_rows_without_missing_images(
  p_rows jsonb,
  p_table text,
  p_bucket text,
  p_tenant_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'public'
as $function$
declare
  v_row jsonb;
  v_rows jsonb := '[]'::jsonb;
  v_omitted jsonb := '[]'::jsonb;
  v_kept jsonb;
  v_url text;
  v_problem text;
  v_prefix text;
  v_label text;
begin
  if p_rows is null or jsonb_typeof(p_rows) <> 'array' then
    return jsonb_build_object('rows', p_rows, 'omitted', '[]'::jsonb);
  end if;

  for v_row in select value from jsonb_array_elements(p_rows)
  loop
    -- La carpeta que el disparador exige a esta fila.
    v_prefix := coalesce(nullif(v_row ->> 'tenant_id', ''), p_tenant_id::text)
      || '/' || coalesce(v_row ->> 'id', '') || '/';
    v_label := case p_table
      when 'mechanic_jobs' then coalesce(nullif(v_row ->> 'job_number', ''),
                                         v_row ->> 'id')
      else coalesce(nullif(btrim(concat_ws(' ', v_row ->> 'brand',
                                                v_row ->> 'model')), ''),
                    v_row ->> 'id')
    end;

    if jsonb_typeof(v_row -> 'image_urls') = 'array' then
      v_kept := '[]'::jsonb;
      for v_url in select value from jsonb_array_elements_text(v_row -> 'image_urls')
      loop
        if v_url is null then
          v_kept := v_kept || 'null'::jsonb;
          continue;
        end if;
        v_problem := public.managed_image_url_problem(v_url, p_bucket, v_prefix);
        if v_problem is null then
          v_kept := v_kept || to_jsonb(v_url);
        else
          v_omitted := v_omitted || jsonb_build_object(
            'table', p_table,
            'record_id', v_row ->> 'id',
            'label', v_label,
            'field', 'image_urls',
            'url', v_url,
            'reason', v_problem
          );
        end if;
      end loop;
      v_row := jsonb_set(v_row, '{image_urls}', v_kept);
    end if;

    if p_table = 'bikes' and jsonb_typeof(v_row -> 'image_url') = 'string' then
      v_url := v_row ->> 'image_url';
      v_problem := public.managed_image_url_problem(v_url, p_bucket, v_prefix);
      if v_problem is not null then
        v_row := jsonb_set(v_row, '{image_url}', 'null'::jsonb);
        v_omitted := v_omitted || jsonb_build_object(
          'table', p_table,
          'record_id', v_row ->> 'id',
          'label', v_label,
          'field', 'image_url',
          'url', v_url,
          'reason', v_problem
        );
      end if;
    end if;

    v_rows := v_rows || jsonb_build_array(v_row);
  end loop;

  return jsonb_build_object('rows', v_rows, 'omitted', v_omitted);
end;
$function$;

comment on function public.backup_rows_without_missing_images(jsonb, text, text, uuid) is
  'Las filas de un respaldo sin las URL de un bucket administrado cuyo archivo falta o es de otra carpeta (el criterio del disparador), y lo omitido. Sólo para restaurar.';

-- La función que borra e inserta, tal como estaba, con otro nombre: la de
-- abajo la llama con los datos ya limpios.
do $rename$
begin
  if to_regprocedure('public.restore_backup_legacy_rows_internal(uuid,uuid)') is null then
    alter function public.restore_backup_legacy_unsafe_internal(uuid, uuid)
      rename to restore_backup_legacy_rows_internal;
  end if;
end;
$rename$;

-- Las tablas que el respaldo guarda y cómo las borra la restauración: la
-- condición es, letra por letra, la de `restore_backup_legacy_rows_internal`
-- (el read-back lo comprueba). La guardia, el bloqueo y la cuenta usan este
-- mismo alcance: las tablas hijas se borran por su padre, no por su taller.
create or replace function public.restore_backup_covered_scope()
returns table(ord integer, table_name text, predicate text)
language sql
immutable
set search_path to 'public'
as $function$
  values
    (1, 'journal_lines', 'entry_id in (select id from journal_entries where tenant_id = p_tenant_id)'),
    (2, 'mechanic_job_items', 'job_id in (select id from mechanic_jobs where tenant_id = p_tenant_id)'),
    (3, 'mechanic_job_timeline', 'job_id in (select id from mechanic_jobs where tenant_id = p_tenant_id)'),
    (4, 'online_order_items', 'order_id in (select id from online_orders where tenant_id = p_tenant_id)'),
    (5, 'employee_contracts', 'tenant_id = p_tenant_id'),
    (6, 'attendance_records', 'tenant_id = p_tenant_id'),
    (7, 'messages', 'conversation_id in (select id from conversations where tenant_id = p_tenant_id)'),
    (8, 'conversation_contexts', 'tenant_id = p_tenant_id or conversation_id in (select id from conversations where tenant_id = p_tenant_id)'),
    (9, 'conversation_participants', 'tenant_id = p_tenant_id or conversation_id in (select id from conversations where tenant_id = p_tenant_id)'),
    (10, 'whatsapp_conversation_bindings', 'tenant_id = p_tenant_id'),
    (11, 'whatsapp_webhook_events', 'tenant_id = p_tenant_id'),
    (12, 'journal_entries', 'tenant_id = p_tenant_id'),
    (13, 'sales_payments', 'tenant_id = p_tenant_id'),
    (14, 'purchase_payments', 'tenant_id = p_tenant_id'),
    (15, 'mechanic_jobs', 'tenant_id = p_tenant_id'),
    (16, 'bikes', 'tenant_id = p_tenant_id'),
    (17, 'online_orders', 'tenant_id = p_tenant_id'),
    (18, 'stock_movements', 'tenant_id = p_tenant_id'),
    (19, 'conversations', 'tenant_id = p_tenant_id'),
    (20, 'whatsapp_channels', 'tenant_id = p_tenant_id'),
    (21, 'sales_invoices', 'tenant_id = p_tenant_id'),
    (22, 'purchase_invoices', 'tenant_id = p_tenant_id'),
    (23, 'featured_products', 'tenant_id = p_tenant_id'),
    (24, 'website_blocks', 'tenant_id = p_tenant_id'),
    (25, 'website_content', 'tenant_id = p_tenant_id'),
    (26, 'website_banners', 'tenant_id = p_tenant_id'),
    (27, 'website_settings', 'tenant_id = p_tenant_id'),
    (28, 'company_settings', 'tenant_id = p_tenant_id'),
    (29, 'payment_methods', 'tenant_id = p_tenant_id'),
    (30, 'products', 'tenant_id = p_tenant_id'),
    (31, 'employees', 'tenant_id = p_tenant_id'),
    (32, 'bike_models', 'tenant_id = p_tenant_id'),
    (33, 'accounts', 'tenant_id = p_tenant_id'),
    (34, 'product_categories', 'tenant_id = p_tenant_id'),
    (35, 'product_brands', 'tenant_id = p_tenant_id'),
    (36, 'bike_brands', 'tenant_id = p_tenant_id'),
    (37, 'customers', 'tenant_id = p_tenant_id'),
    (38, 'suppliers', 'tenant_id = p_tenant_id')
$function$;

create or replace function public.restore_backup_covered_tables()
returns text[]
language sql
immutable
set search_path to 'public'
as $function$
  select array_agg(scope.table_name order by scope.ord)
    from public.restore_backup_covered_scope() scope
$function$;

-- El nombre de una tabla en palabras del taller (la tabla misma si no tiene).
create or replace function public.restore_backup_table_label(p_table text)
returns text
language sql
immutable
set search_path to 'public'
as $function$
  select coalesce((
    select label.name
      from (values
        -- Las que el respaldo guarda.
        ('product_brands', 'marcas de productos'),
        ('product_categories', 'categorías de productos'),
        ('products', 'productos'),
        ('customers', 'clientes'),
        ('suppliers', 'proveedores'),
        ('whatsapp_channels', 'canales de WhatsApp'),
        ('conversations', 'conversaciones'),
        ('conversation_participants', 'participantes de las conversaciones'),
        ('conversation_contexts', 'contextos de las conversaciones'),
        ('messages', 'mensajes'),
        ('whatsapp_conversation_bindings', 'vínculos de WhatsApp'),
        ('whatsapp_webhook_events', 'eventos de WhatsApp'),
        ('sales_invoices', 'facturas de venta'),
        ('sales_payments', 'pagos de ventas'),
        ('purchase_invoices', 'facturas de compra'),
        ('purchase_payments', 'pagos de compras'),
        ('employees', 'trabajadores'),
        ('employee_contracts', 'contratos'),
        ('attendance_records', 'asistencias'),
        ('accounts', 'cuentas contables'),
        ('payment_methods', 'medios de pago'),
        ('journal_entries', 'asientos contables'),
        ('journal_lines', 'líneas de los asientos'),
        ('stock_movements', 'movimientos de inventario'),
        ('bike_brands', 'marcas de bicis'),
        ('bike_models', 'modelos de bicis'),
        ('bikes', 'bicis'),
        ('mechanic_jobs', 'trabajos'),
        ('mechanic_job_items', 'líneas de los trabajos'),
        ('mechanic_job_timeline', 'bitácora de los trabajos'),
        ('company_settings', 'datos de la empresa'),
        ('website_settings', 'ajustes del sitio web'),
        ('website_banners', 'banners del sitio web'),
        ('website_content', 'contenido del sitio web'),
        ('website_blocks', 'bloques del sitio web'),
        ('featured_products', 'productos destacados'),
        ('online_orders', 'pedidos web'),
        ('online_order_items', 'líneas de los pedidos web'),
        -- Las que no guarda y dependen de las que sí.
        ('bike_profiles', 'fichas técnicas de las bicis'),
        ('bike_events', 'historia de las bicis'),
        ('bike_observations', 'observaciones de las bicis'),
        ('bike_interventions', 'intervenciones de las bicis'),
        ('bike_component_lifecycles', 'vida de los componentes'),
        ('bike_system_states', 'estado de los sistemas de las bicis'),
        ('mechanic_job_bikes', 'bicis de los trabajos'),
        ('mechanic_job_tasks', 'tareas de los trabajos'),
        ('smart_tasks', 'tareas'),
        ('payment_terminal_terms', 'condiciones de las terminales de pago'),
        ('payment_terminal_profiles', 'terminales de pago'),
        ('product_images', 'fotos de productos'),
        ('product_spec_values', 'fichas técnicas de productos'),
        ('purchase_invoice_lines', 'líneas de facturas de compra'),
        ('supplier_credentials', 'claves de portales de proveedores'),
        ('supplier_contacts', 'contactos de proveedores'),
        ('customer_addresses', 'direcciones de clientes'),
        ('expenses', 'gastos'),
        ('expense_lines', 'líneas de gastos'),
        ('expense_payments', 'pagos de gastos'),
        ('expense_categories', 'categorías de gastos'),
        ('payroll_entries', 'nómina'),
        ('payroll_voucher_lines', 'liquidaciones de sueldo'),
        ('mechanic_job_status_transition_events', 'historia de estados de los trabajos'),
        ('mechanic_job_status_transitions', 'cambios de estado de los trabajos'),
        ('mechanic_job_delivery_events', 'entregas de los trabajos'),
        ('mechanic_job_warranty_claim_events', 'garantías de los trabajos'),
        ('purchase_receipts', 'recepciones de compras'),
        ('purchase_receipt_lines', 'líneas de recepciones de compras'),
        ('stock_adjustments', 'ajustes de inventario'),
        ('smart_purchase_list', 'lista de compras'),
        ('attendances', 'asistencia'),
        ('loyalty', 'puntos de clientes'),
        ('whatsapp_outbox', 'mensajes de WhatsApp por enviar'),
        ('messaging_attachments', 'adjuntos de mensajes'),
        ('online_order_events', 'historia de los pedidos web')
      ) as label(tbl, name)
     where label.tbl = p_table), p_table)
$function$;

-- Las tablas que la restauración borraría y que el respaldo no trae (un
-- respaldo de antes de que se agregaran). `null` o `[]` sí cuentan: es como
-- `create_backup` guarda una tabla vacía.
create or replace function public.restore_backup_missing_tables(p_data jsonb)
returns text[]
language sql
immutable
set search_path to 'public'
as $function$
  select coalesce(array_agg(scope.table_name order by scope.ord), array[]::text[])
    from public.restore_backup_covered_scope() scope
   where not (p_data ? scope.table_name)
      or jsonb_typeof(p_data -> scope.table_name) not in ('array', 'null')
$function$;

create or replace function public.restore_backup_incomplete_message(p_missing text[])
returns text
language sql
immutable
set search_path to 'public'
as $function$
  select 'No se restauró nada: este respaldo es de una versión anterior y no guarda '
    || (select string_agg(public.restore_backup_table_label(t), ', ' order by o)
          from unnest(p_missing) with ordinality as missing(t, o)
         where o <= 4)
    || case when cardinality(p_missing) > 4
            then ' y ' || (cardinality(p_missing) - 4)::text || ' más'
            else '' end
    || '; restaurarlo los borraría sin reponerlos. Puedes descargarlo para consultarlo.'
$function$;

-- Por taller: las filas que dependen de lo que la restauración borraría y que
-- ella no devuelve —de tablas que el respaldo no guarda, o de otro taller en
-- las que sí guarda—, por tabla, con lo que les pasaría. Lee todas las llaves
-- foráneas del catálogo: una tabla nueva aparece sola.
create or replace function public.restore_backup_uncovered_dependents(
  p_tenant_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'public'
as $function$
declare
  v_scope jsonb;
  v_fk record;
  v_src_cols text;
  v_dst_cols text;
  v_dst_scope text;
  v_src_scope text;
  v_count bigint;
  v_key text;
  v_found jsonb := '{}'::jsonb;
  v_effect text;
  v_rank integer;
begin
  select jsonb_object_agg(scope.table_name,
                          replace(scope.predicate, 'p_tenant_id', '$1'))
    into v_scope
    from public.restore_backup_covered_scope() scope;

  for v_fk in
    select c.conname, src.relname as src, dst.relname as dst, c.confdeltype,
           c.conkey, c.confkey, c.conrelid, c.confrelid
      from pg_constraint c
      join pg_class src on src.oid = c.conrelid
      join pg_namespace ns on ns.oid = src.relnamespace and ns.nspname = 'public'
      join pg_class dst on dst.oid = c.confrelid
      join pg_namespace nd on nd.oid = dst.relnamespace and nd.nspname = 'public'
     where c.contype = 'f'
       and v_scope ? dst.relname
     order by src.relname, c.conname
  loop
    select string_agg(format('s.%I', a.attname), ', ' order by k.ord)
      into v_src_cols
      from unnest(v_fk.conkey) with ordinality as k(attnum, ord)
      join pg_attribute a on a.attrelid = v_fk.conrelid and a.attnum = k.attnum;
    select string_agg(format('d.%I', a.attname), ', ' order by k.ord)
      into v_dst_cols
      from unnest(v_fk.confkey) with ordinality as k(attnum, ord)
      join pg_attribute a on a.attrelid = v_fk.confrelid and a.attnum = k.attnum;
    v_dst_scope := v_scope ->> v_fk.dst;
    v_src_scope := v_scope ->> v_fk.src;

    if v_src_scope is null then
      execute format(
        'select count(*) from public.%I s where (%s) in '
        '(select %s from public.%I d where %s)',
        v_fk.src, v_src_cols, v_dst_cols, v_fk.dst, v_dst_scope)
        into v_count
        using p_tenant_id;
      v_key := v_fk.src;
    else
      -- Una tabla que el respaldo guarda: cuentan sólo sus filas que la
      -- restauración no borra (de otro taller) y apuntan a las que sí.
      execute format(
        'select count(*) from public.%I s where not coalesce((%s), false) '
        'and (%s) in (select %s from public.%I d where %s)',
        v_fk.src, v_src_scope, v_src_cols, v_dst_cols, v_fk.dst, v_dst_scope)
        into v_count
        using p_tenant_id;
      v_key := v_fk.src || ':otro_taller';
    end if;
    continue when v_count = 0;

    -- Por tabla, lo más grave: impedir > borrar > desconectar. Las filas son
    -- las de la llave con más: al menos esas.
    v_effect := case v_fk.confdeltype
      when 'c' then 'se borraría'
      when 'n' then 'quedaría desconectado'
      when 'd' then 'quedaría desconectado'
      else 'impide restaurar'
    end;
    v_rank := case v_effect when 'impide restaurar' then 3
                            when 'se borraría' then 2 else 1 end;
    if not (v_found ? v_key)
       or (v_found -> v_key ->> 'rank')::integer < v_rank then
      v_found := v_found || jsonb_build_object(v_key, jsonb_build_object(
        'table', v_fk.src,
        'other_tenant', v_src_scope is not null,
        'rank', v_rank, 'effect', v_effect,
        'rows', greatest(v_count,
                         coalesce((v_found -> v_key ->> 'rows')::bigint, 0))));
    else
      v_found := jsonb_set(v_found, array[v_key, 'rows'],
        to_jsonb(greatest(v_count, (v_found -> v_key ->> 'rows')::bigint)));
    end if;
  end loop;

  return coalesce((
    select jsonb_agg(jsonb_build_object(
             'table', entry.value ->> 'table',
             'label', public.restore_backup_table_label(entry.value ->> 'table')
                      || case when (entry.value ->> 'other_tenant')::boolean
                              then ' de otro taller' else '' end,
             'other_tenant', (entry.value ->> 'other_tenant')::boolean,
             'rows', (entry.value ->> 'rows')::bigint,
             'effect', entry.value ->> 'effect')
           order by (entry.value ->> 'rank')::integer desc,
                    (entry.value ->> 'rows')::bigint desc, entry.key)
      from jsonb_each(v_found) as entry
  ), '[]'::jsonb);
end;
$function$;

comment on function public.restore_backup_uncovered_dependents(uuid) is
  'Por taller, las filas que la restauración borraría, desconectaría o que le impiden restaurar, y que no devuelve: de tablas que el respaldo no guarda o de otro taller. Vacía: restaurar no pierde nada fuera del respaldo.';

-- El motivo de no restaurar, en palabras del taller: primero lo que tiene
-- nombre conocido (fichas técnicas, historia de las bicis, tareas…), hasta
-- cuatro, y cuántas tablas más. La lista completa va en uncovered_dependents.
create or replace function public.restore_backup_refusal_message(
  p_dependents jsonb
)
returns text
language sql
immutable
set search_path to 'public'
as $function$
  with items as (
    select item, ordinality,
           (item ->> 'label') <> (item ->> 'table') as named
      from jsonb_array_elements(coalesce(p_dependents, '[]'::jsonb))
             with ordinality as dependent(item, ordinality)
  ), shown as (
    select item, ordinality
      from items
     order by named desc, ordinality
     limit 4
  )
  select 'No se restauró nada: el taller tiene datos que este respaldo no '
    || 'guarda y restaurar los perdería ('
    || (select string_agg((item ->> 'label') || ': ' || (item ->> 'rows'), ', '
                          order by ordinality)
          from shown)
    || case when (select count(*) from items) > 4
            then ' y ' || ((select count(*) from items) - 4)::text || ' más'
            else '' end
    || '). Puedes descargar el respaldo para consultarlo.'
$function$;

-- Lo que `restore_backup_internal` exige de proveedores y facturas de compra
-- (los mismos ids que ahora), para que la app no ofrezca una restauración que
-- el motor va a negar. Null si no hay nada que lo impida.
create or replace function public.restore_backup_foundation_blocker(
  p_data jsonb,
  p_tenant_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'public'
as $function$
declare
  v_backup_ids uuid[];
  v_current_ids uuid[];
begin
  select coalesce(array_agg(id order by id), array[]::uuid[]) into v_backup_ids
    from (select nullif(item ->> 'id', '')::uuid as id
            from jsonb_array_elements(case when jsonb_typeof(p_data -> 'suppliers') = 'array'
                                           then p_data -> 'suppliers' else '[]'::jsonb end) item) ids;
  select coalesce(array_agg(id order by id), array[]::uuid[]) into v_current_ids
    from public.suppliers where tenant_id = p_tenant_id;
  if v_backup_ids is distinct from v_current_ids then
    return jsonb_build_object(
      'error_code', 'supplier_foundation_restore_supplier_set_changed',
      'message', format('Desde este respaldo cambiaron los proveedores (%s ahora, %s en el respaldo), y restaurar exige los mismos.',
                        cardinality(v_current_ids), cardinality(v_backup_ids)));
  end if;

  select coalesce(array_agg(id order by id), array[]::uuid[]) into v_backup_ids
    from (select nullif(item ->> 'id', '')::uuid as id
            from jsonb_array_elements(case when jsonb_typeof(p_data -> 'purchase_invoices') = 'array'
                                           then p_data -> 'purchase_invoices' else '[]'::jsonb end) item) ids;
  select coalesce(array_agg(id order by id), array[]::uuid[]) into v_current_ids
    from public.purchase_invoices where tenant_id = p_tenant_id;
  if v_backup_ids is distinct from v_current_ids then
    return jsonb_build_object(
      'error_code', 'supplier_foundation_restore_purchase_invoice_set_changed',
      'message', format('Desde este respaldo cambiaron las facturas de compra (%s ahora, %s en el respaldo), y restaurar exige las mismas.',
                        cardinality(v_current_ids), cardinality(v_backup_ids)));
  end if;
  return null;
end;
$function$;

create or replace function public.restore_backup_legacy_unsafe_internal(
  p_backup_id uuid,
  p_tenant_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog', 'public', 'extensions', 'pg_temp'
as $function$
declare
  v_data jsonb;
  v_jobs jsonb;
  v_bikes jsonb;
  v_omitted jsonb;
  v_missing text[];
  v_dependents jsonb;
  v_scope record;
  v_copy_id uuid := gen_random_uuid();
  v_result jsonb;
begin
  select backup.backup_data
    into v_data
    from public.database_backups backup
   where backup.id = p_backup_id
     and backup.tenant_id = p_tenant_id
     and backup.status = 'completed';

  if v_data is null then
    return public.restore_backup_legacy_rows_internal(p_backup_id, p_tenant_id);
  end if;

  -- Lo que el respaldo no trae no se borra.
  v_missing := public.restore_backup_missing_tables(v_data);
  if cardinality(v_missing) > 0 then
    return jsonb_build_object(
      'success', false,
      'error_code', 'restore_backup_incomplete',
      'error', public.restore_backup_incomplete_message(v_missing),
      'missing_tables', to_jsonb(v_missing),
      'backup_id', p_backup_id
    );
  end if;

  -- Antes de contar, nadie escribe en las tablas que se van a reemplazar
  -- (cerco de tabla, como el de proveedores y facturas en
  -- `restore_backup_internal`: una fila nueva de un cliente con su dirección
  -- no puede aparecer entre la cuenta y el borrado), y las filas del taller
  -- quedan tomadas (otra sesión que quiera colgarles una fila espera, y
  -- después falla o apunta a la restaurada). Frena las escrituras de todos
  -- los talleres en esas tablas mientras dura: restaurar es excepcional. Un
  -- interbloqueo con un escritor aborta la restauración entera, sin nada a
  -- medias.
  execute (
    select 'lock table '
      || string_agg(format('public.%I', scope.table_name), ', ' order by scope.ord)
      || ' in share row exclusive mode'
      from public.restore_backup_covered_scope() scope);

  for v_scope in
    select scope.table_name, scope.predicate
      from public.restore_backup_covered_scope() scope
     order by scope.ord
  loop
    execute format(
      'select count(*) from (select 1 from public.%I where %s for update) locked',
      v_scope.table_name, replace(v_scope.predicate, 'p_tenant_id', '$1'))
      using p_tenant_id;
  end loop;

  -- La misma negativa que `restore_backup`, aquí también: para quien llame
  -- al motor directo y para lo que otra sesión agregó antes del bloqueo.
  v_dependents := public.restore_backup_uncovered_dependents(p_tenant_id);
  if jsonb_array_length(v_dependents) > 0 then
    return jsonb_build_object(
      'success', false,
      'error_code', 'restore_would_lose_uncovered_data',
      'error', public.restore_backup_refusal_message(v_dependents),
      'uncovered_dependents', v_dependents,
      'backup_id', p_backup_id
    );
  end if;

  v_jobs := public.backup_rows_without_missing_images(
    v_data -> 'mechanic_jobs', 'mechanic_jobs', 'job-images', p_tenant_id);
  v_bikes := public.backup_rows_without_missing_images(
    v_data -> 'bikes', 'bikes', 'bike-images', p_tenant_id);
  v_omitted := (v_bikes -> 'omitted') || (v_jobs -> 'omitted');

  if jsonb_array_length(v_omitted) = 0 then
    v_result := public.restore_backup_legacy_rows_internal(p_backup_id, p_tenant_id);
    return case when coalesce((v_result ->> 'success')::boolean, false)
                then v_result || jsonb_build_object('omitted_attachments', '[]'::jsonb)
                else v_result end;
  end if;

  -- Una copia de trabajo con las filas limpias: el respaldo no cambia.
  v_data := jsonb_set(v_data, '{mechanic_jobs}', v_jobs -> 'rows');
  v_data := jsonb_set(v_data, '{bikes}', v_bikes -> 'rows');

  insert into public.database_backups (
    id, tenant_id, backup_name, backup_type, status, backup_data, summary,
    created_by, created_at, backup_size_bytes, notes
  )
  select v_copy_id, backup.tenant_id,
         backup.backup_name || ' [adjuntos faltantes omitidos]',
         backup.backup_type, 'completed', v_data, backup.summary,
         backup.created_by, backup.created_at, length(v_data::text),
         backup.notes
    from public.database_backups backup
   where backup.id = p_backup_id
     and backup.tenant_id = p_tenant_id;

  v_result := public.restore_backup_legacy_rows_internal(v_copy_id, p_tenant_id);

  delete from public.database_backups where id = v_copy_id;

  if coalesce((v_result ->> 'success')::boolean, false) then
    return (v_result - 'backup_id') || jsonb_build_object(
      'backup_id', p_backup_id,
      'omitted_attachments', v_omitted
    );
  end if;
  -- Si falló, no se restauró nada: no hay nada omitido que informar.
  return (v_result - 'backup_id') || jsonb_build_object('backup_id', p_backup_id);
end;
$function$;

comment on function public.restore_backup_legacy_unsafe_internal(uuid, uuid) is
  'Restaura las filas del respaldo: se niega si al respaldo le falta una tabla o si perdería filas que no devuelve (después de bloquear las del taller), y omite sólo las URL de job-images o bike-images que el disparador no admitiría (omitted_attachments). La restauración misma es restore_backup_legacy_rows_internal.';

-- Lo que la app muestra antes de ofrecer Restaurar: si se puede sin perder
-- nada fuera del respaldo, y qué adjuntos se omitirían.
create or replace function public.restore_backup_preflight(
  p_backup_id uuid,
  p_tenant_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'pg_catalog', 'public', 'extensions', 'pg_temp'
as $function$
declare
  v_data jsonb;
  v_missing text[];
  v_dependents jsonb;
  v_blocker jsonb;
begin
  if auth.role() is distinct from 'service_role'
     and not public.can_manage_tenant_backups(p_tenant_id) then
    raise exception 'Backup access denied' using errcode = '42501';
  end if;

  select backup.backup_data
    into v_data
    from public.database_backups backup
   where backup.id = p_backup_id
     and backup.tenant_id = p_tenant_id
     and backup.status = 'completed';
  if v_data is null then
    raise exception 'Backup access denied' using errcode = '42501';
  end if;

  v_missing := public.restore_backup_missing_tables(v_data);
  v_dependents := public.restore_backup_uncovered_dependents(p_tenant_id);
  v_blocker := public.restore_backup_foundation_blocker(v_data, p_tenant_id);
  return jsonb_build_object(
    'can_restore', cardinality(v_missing) = 0
                   and jsonb_array_length(v_dependents) = 0
                   and v_blocker is null,
    'message', case
      when cardinality(v_missing) > 0
        then public.restore_backup_incomplete_message(v_missing)
      when jsonb_array_length(v_dependents) > 0
        then public.restore_backup_refusal_message(v_dependents)
      else v_blocker ->> 'message' end,
    'missing_tables', coalesce((
      select jsonb_agg(jsonb_build_object(
               'table', t, 'label', public.restore_backup_table_label(t))
             order by o)
        from unnest(v_missing) with ordinality as missing(t, o)), '[]'::jsonb),
    'uncovered_dependents', v_dependents,
    'foundation_blocker', v_blocker,
    'omitted_attachments',
    (public.backup_rows_without_missing_images(
       v_data -> 'bikes', 'bikes', 'bike-images', p_tenant_id) -> 'omitted')
    || (public.backup_rows_without_missing_images(
       v_data -> 'mechanic_jobs', 'mechanic_jobs', 'job-images', p_tenant_id)
       -> 'omitted')
  );
end;
$function$;

comment on function public.restore_backup_preflight(uuid, uuid) is
  'Antes de restaurar: si se puede (el respaldo trae todas las tablas, no se perderían filas que no devuelve, y proveedores y facturas de compra son los mismos) y qué adjuntos se omitirían.';

create or replace function public.restore_backup(p_backup_id uuid, p_tenant_id uuid)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog', 'public', 'extensions', 'pg_temp'
as $function$
declare
  v_data jsonb;
  v_missing text[];
  v_result jsonb;
  v_dependents jsonb;
begin
  if auth.role() is distinct from 'service_role'
     and not public.can_manage_tenant_backups(p_tenant_id) then
    raise exception 'Backup access denied'
      using errcode = '42501';
  end if;

  select backup.backup_data
    into v_data
    from public.database_backups backup
   where backup.id = p_backup_id
     and backup.tenant_id = p_tenant_id
     and backup.status = 'completed';
  if v_data is null then
    raise exception 'Backup access denied'
      using errcode = '42501';
  end if;

  -- Restaurar nunca borra lo que no devuelve: ni una tabla que el respaldo no
  -- trae, ni filas que dependen de lo que borraría. No se toca nada y se dice
  -- qué. El motor lo vuelve a comprobar con las filas ya tomadas.
  v_missing := public.restore_backup_missing_tables(v_data);
  if cardinality(v_missing) > 0 then
    return jsonb_build_object(
      'success', false,
      'error_code', 'restore_backup_incomplete',
      'message', public.restore_backup_incomplete_message(v_missing),
      'missing_tables', to_jsonb(v_missing),
      'backup_id', p_backup_id
    );
  end if;

  v_dependents := public.restore_backup_uncovered_dependents(p_tenant_id);
  if jsonb_array_length(v_dependents) > 0 then
    return jsonb_build_object(
      'success', false,
      'error_code', 'restore_would_lose_uncovered_data',
      'message', public.restore_backup_refusal_message(v_dependents),
      'uncovered_dependents', v_dependents,
      'backup_id', p_backup_id
    );
  end if;

  v_result := public.restore_backup_internal(p_backup_id, p_tenant_id);

  -- El informe queda en el respaldo: qué adjuntos se omitieron (o ninguno).
  if coalesce((v_result ->> 'success')::boolean, false) then
    update public.database_backups backup
       set restore_report = jsonb_build_object(
             'restored_at', clock_timestamp(),
             'omitted_attachments',
             coalesce(v_result -> 'omitted_attachments', '[]'::jsonb))
     where backup.id = p_backup_id
       and backup.tenant_id = p_tenant_id;
  end if;

  return v_result;
end;
$function$;

revoke all on function public.backup_rows_without_missing_images(jsonb, text, text, uuid)
  from public, anon, authenticated, service_role;
revoke all on function public.restore_backup_legacy_unsafe_internal(uuid, uuid)
  from public, anon, authenticated, service_role;
revoke all on function public.restore_backup_legacy_rows_internal(uuid, uuid)
  from public, anon, authenticated, service_role;
revoke all on function public.restore_backup_uncovered_dependents(uuid)
  from public, anon, authenticated, service_role;
revoke all on function public.restore_backup_covered_scope()
  from public, anon, authenticated, service_role;
revoke all on function public.restore_backup_covered_tables()
  from public, anon, authenticated, service_role;
revoke all on function public.restore_backup_table_label(text)
  from public, anon, authenticated, service_role;
revoke all on function public.restore_backup_missing_tables(jsonb)
  from public, anon, authenticated, service_role;
revoke all on function public.restore_backup_incomplete_message(text[])
  from public, anon, authenticated, service_role;
revoke all on function public.restore_backup_refusal_message(jsonb)
  from public, anon, authenticated, service_role;
revoke all on function public.restore_backup_foundation_blocker(jsonb, uuid)
  from public, anon, authenticated, service_role;
revoke all on function public.restore_backup_preflight(uuid, uuid)
  from public, anon, authenticated, service_role;
grant execute on function public.restore_backup_preflight(uuid, uuid)
  to authenticated, service_role;

commit;

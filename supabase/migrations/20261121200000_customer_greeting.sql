-- «Cómo saludarle» también para los clientes (dueño, 2026-11-21: «Sí, clientes
-- y publica»), y que el cliente lo elija en «Mi cuenta» de la tienda: «así yo
-- no voy a tener que yo manualmente estar uno por uno definiendo cómo se le va
-- a llamar a cada uno».
--
-- Opciones (las mismas de `contactGreetingName`, en el núcleo de la tienda:
-- packages/vinabike_public_core/lib/public_store/models/contact_greeting.dart):
--   first_name   la primera palabra del nombre (lo que se usa si nadie eligió)
--   two_names    los dos primeros nombres, con los de/del/la/las/los entremedio
--   second_name  sólo el segundo nombre
--   full_name    el nombre entero, como quedó registrado
--   custom       el texto de greeting_custom_name, tal cual
-- Las palabras del nombre se escriben como en un saludo: «JUAN» o «juan» son
-- «Juan»; lo que mezcla mayúsculas queda como lo escribieron.
--
-- Antes, los avisos del taller y el pedido de reseña mandaban el nombre
-- entero y whatsapp-send lo recortaba con una regla de nombres compuestos; el
-- chat del ERP lo recortaba antes de mandarlo y el servidor lo volvía a
-- recortar («José Luis» llegaba «José»). Ahora el saludo sale de esta regla y
-- el mensaje lleva la marca `greeting_name_source = contact_preference`, que
-- whatsapp-send respeta sin recortar (20261119200000). Los correos (avisos,
-- cotizaciones, pedidos), el QR del portal y las respuestas a los botones
-- saludan igual.

alter table public.customers
  add column if not exists greeting_style text not null default 'first_name',
  add column if not exists greeting_custom_name text;

alter table public.customers
  drop constraint if exists customers_greeting_style_known;
alter table public.customers
  add constraint customers_greeting_style_known
    check (greeting_style in ('first_name', 'two_names', 'second_name', 'full_name', 'custom'));

alter table public.customers
  drop constraint if exists customers_greeting_custom_name_shape;
alter table public.customers
  add constraint customers_greeting_custom_name_shape
    check (
      greeting_custom_name is null
      or (
        char_length(greeting_custom_name) <= 60
        and greeting_custom_name ~ '^\S+( \S+)*$'
        and greeting_custom_name !~ '[[:cntrl:]]'
      )
    );

alter table public.customers
  drop constraint if exists customers_greeting_custom_matches_style;
alter table public.customers
  add constraint customers_greeting_custom_matches_style
    check ((greeting_style = 'custom') = (greeting_custom_name is not null));

comment on column public.customers.greeting_style is
  'How messages greet this customer: first_name (default), two_names, second_name, full_name or custom (greeting_custom_name). The shop sets it in the customer sheet and the customer in the store account. Rendered by contact_greeting_name_internal and by contactGreetingName in the store core.';
comment on column public.customers.greeting_custom_name is
  'The exact name used in the greeting when greeting_style = custom; null otherwise.';

-- Una palabra del nombre como se escribe en un saludo.
create or replace function public.contact_greeting_word_internal(
  p_word text,
  p_inner boolean
)
returns text
language sql
immutable
set search_path = pg_catalog, pg_temp
as $$
  select case
    when upper(p_word) = lower(p_word) then p_word
    when not ((p_word = upper(p_word) and char_length(p_word) > 1)
              or p_word = lower(p_word)) then p_word
    when p_inner and lower(p_word) in ('de', 'del', 'la', 'las', 'los') then lower(p_word)
    else upper(left(p_word, 1)) || lower(substr(p_word, 2))
  end;
$$;

-- La regla del saludo: la misma de `contactGreetingName`. Null sin nombre.
create or replace function public.contact_greeting_name_internal(
  p_name text,
  p_style text,
  p_custom_name text
)
returns text
language plpgsql
immutable
set search_path = pg_catalog, public, pg_temp
as $$
declare
  v_name text := btrim(regexp_replace(coalesce(p_name, ''), '\s+', ' ', 'g'));
  v_custom text := btrim(regexp_replace(coalesce(p_custom_name, ''), '\s+', ' ', 'g'));
  v_words text[];
  v_count integer;
  v_second integer := 2;
  v_from integer := 1;
  v_to integer := 1;
  v_out text[] := '{}';
  v_index integer;
begin
  if p_style = 'custom' and v_custom <> '' then
    return v_custom;
  end if;
  if v_name = '' then
    return null;
  end if;
  v_words := string_to_array(v_name, ' ');
  v_count := cardinality(v_words);
  -- El segundo nombre: la primera palabra después de la primera que no es un
  -- de/del/la/las/los (o la última, si sólo quedan ésos).
  while v_second < v_count
        and lower(v_words[v_second]) in ('de', 'del', 'la', 'las', 'los') loop
    v_second := v_second + 1;
  end loop;
  if p_style = 'two_names' and v_second <= v_count then
    v_to := v_second;
  elsif p_style = 'second_name' and v_second <= v_count then
    v_from := v_second;
    v_to := v_second;
  elsif p_style = 'full_name' then
    v_to := v_count;
  end if;
  for v_index in v_from..v_to loop
    v_out := v_out || public.contact_greeting_word_internal(v_words[v_index], v_index > 1);
  end loop;
  return array_to_string(v_out, ' ');
end;
$$;

-- Los nombres compuestos que los avisos ya saludaban enteros («María José»,
-- «Juan Pablo»: la lista de whatsapp-send) parten con los dos nombres; el
-- resto, con el primero. Es sólo el punto de partida: cualquiera se cambia en
-- la ficha o en «Mi cuenta».
create or replace function public.contact_greeting_is_compound_internal(p_name text)
returns boolean
language sql
immutable
set search_path = pg_catalog, pg_temp
as $$
  select lower(translate(
           split_part(regexp_replace(btrim(coalesce(p_name, '')), '\s+', ' ', 'g'), ' ', 1) || ' ' ||
           split_part(regexp_replace(btrim(coalesce(p_name, '')), '\s+', ' ', 'g'), ' ', 2),
           'ÁÉÍÓÚáéíóúÜüÑñ', 'AEIOUaeiouUuNn'))
         in ('ana maria', 'ana paula', 'ana sofia', 'carmen gloria', 'francisco javier',
             'jorge luis', 'jose antonio', 'jose carlos', 'jose francisco', 'jose ignacio',
             'jose luis', 'jose manuel', 'jose maria', 'jose miguel', 'jose pablo',
             'juan antonio', 'juan carlos', 'juan francisco', 'juan ignacio', 'juan jose',
             'juan luis', 'juan manuel', 'juan miguel', 'juan pablo', 'juan sebastian',
             'luis alberto', 'luis enrique', 'luis felipe', 'luis miguel', 'luz maria',
             'marco antonio', 'maria angelica', 'maria carolina', 'maria elena',
             'maria fernanda', 'maria ignacia', 'maria isabel', 'maria jesus', 'maria jose',
             'maria paz', 'maria soledad', 'maria teresa', 'miguel angel', 'pedro pablo',
             'rosa maria');
$$;

update public.customers customer
   set greeting_style = 'two_names'
 where customer.greeting_style = 'first_name'
   and customer.greeting_custom_name is null
   and public.contact_greeting_is_compound_internal(customer.name);

-- Y un cliente nuevo igual: el taller o el sitio lo crean sin elegir.
create or replace function public.customer_greeting_default_internal()
returns trigger
language plpgsql
set search_path = pg_catalog, public, pg_temp
as $$
begin
  if new.greeting_style = 'first_name'
     and new.greeting_custom_name is null
     and public.contact_greeting_is_compound_internal(new.name) then
    new.greeting_style := 'two_names';
  end if;
  return new;
end;
$$;

drop trigger if exists trg_customers_greeting_default on public.customers;
create trigger trg_customers_greeting_default
  before insert on public.customers
  for each row execute function public.customer_greeting_default_internal();

create or replace function public.customer_greeting_internal(
  p_customer public.customers
)
returns text
language sql
immutable
set search_path = pg_catalog, public, pg_temp
as $$
  select public.contact_greeting_name_internal(
    p_customer.name, p_customer.greeting_style, p_customer.greeting_custom_name);
$$;

-- El saludo de un pedido o una cotización: el que eligió su cliente si está
-- ligado a uno; si no, el primer nombre con que se escribió.
create or replace function public.customer_greeting_for_internal(
  p_tenant_id uuid,
  p_customer_id uuid,
  p_fallback_name text
)
returns text
language sql
stable
set search_path = pg_catalog, public, pg_temp
as $$
  select coalesce(
    (select public.customer_greeting_internal(customer)
       from public.customers customer
      where customer.id = p_customer_id
        and customer.tenant_id = p_tenant_id),
    public.contact_greeting_name_internal(p_fallback_name, 'first_name', null));
$$;

-- `greeting_name` como columna calculada de PostgREST
-- (`customers?select=name,greeting_name`): el encabezado de la tienda saluda
-- con ella sin repetir la regla en JavaScript. Lee la fila que el que llama
-- ya puede leer.
create or replace function public.greeting_name(
  p_customer public.customers
)
returns text
language sql
immutable
set search_path = pg_catalog, public, pg_temp
as $$
  select public.customer_greeting_internal(p_customer);
$$;

-- «Mi cuenta» puede cambiar también el saludo (antes sólo nombre, teléfono,
-- RUT y foto).
create or replace function public.guard_customer_identity_update()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public, pg_temp
as $function$
begin
  if auth.uid() is null or auth.role() is distinct from 'authenticated' then
    return new;
  end if;

  if new.tenant_id is distinct from old.tenant_id
     or new.auth_user_id is distinct from old.auth_user_id then
    if new.tenant_id is not distinct from old.tenant_id
       and coalesce(current_setting('vinabike.portal_claim_relink', true), '')
         = txid_current()::text || ':' || old.id::text then
      return new;
    end if;
    raise exception 'Customer tenant and Auth identity are immutable'
      using errcode = '42501';
  end if;

  if old.auth_user_id = auth.uid()
     and not public.is_active_tenant_member(old.tenant_id)
     and (
       to_jsonb(new) - array[
         'name',
         'phone',
         'rut',
         'image_url',
         'greeting_style',
         'greeting_custom_name',
         'updated_at'
       ]::text[]
     ) is distinct from (
       to_jsonb(old) - array[
         'name',
         'phone',
         'rut',
         'image_url',
         'greeting_style',
         'greeting_custom_name',
         'updated_at'
       ]::text[]
     ) then
    raise exception 'Customer self-service may update profile fields only'
      using errcode = '42501';
  end if;

  return new;
end;
$function$;

-- El saludo de la cuenta, como lo dibuja «Mi cuenta».
create or replace function public.customer_greeting_json_internal(
  p_customer public.customers
)
returns jsonb
language sql
immutable
set search_path = pg_catalog, public, pg_temp
as $$
  select jsonb_build_object(
    'status', 'linked',
    'name', p_customer.name,
    'greeting_style', p_customer.greeting_style,
    'greeting_custom_name', p_customer.greeting_custom_name,
    'greeting', public.customer_greeting_internal(p_customer));
$$;

-- «Cómo te saludamos», en «Mi cuenta»: sólo la ficha de la propia cuenta, en
-- su tienda.
create or replace function public.set_my_customer_greeting_v1(
  p_tenant_id uuid,
  p_greeting_style text,
  p_greeting_custom_name text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_customer public.customers%rowtype;
  v_style text := btrim(coalesce(p_greeting_style, ''));
  v_custom text := nullif(btrim(regexp_replace(
    coalesce(p_greeting_custom_name, ''), '\s+', ' ', 'g')), '');
begin
  if v_style not in ('first_name', 'two_names', 'second_name', 'full_name', 'custom') then
    raise exception 'customer_greeting_invalid' using errcode = '22023';
  end if;
  if v_style = 'custom' then
    if v_custom is null or char_length(v_custom) > 60 or v_custom ~ '[[:cntrl:]]' then
      raise exception 'customer_greeting_custom_invalid' using errcode = '22023';
    end if;
  else
    v_custom := null;
  end if;
  v_customer := public.my_workshop_notice_customer_internal(p_tenant_id);
  if v_customer.id is null then
    raise exception 'customer_greeting_not_linked' using errcode = '42501';
  end if;
  update public.customers customer
     set greeting_style = v_style,
         greeting_custom_name = v_custom,
         updated_at = now()
   where customer.id = v_customer.id
     and customer.tenant_id = p_tenant_id
  returning * into v_customer;
  return public.customer_greeting_json_internal(v_customer);
end;
$$;

-- La llama el disparador de un alta, que corre como quien da el alta (el
-- equipo en el ERP, la cuenta en la tienda): es pura, sin datos.
revoke all on function public.contact_greeting_is_compound_internal(text) from public, anon;
grant execute on function public.contact_greeting_is_compound_internal(text) to authenticated, service_role;
revoke all on function public.customer_greeting_default_internal() from public, anon, authenticated;
revoke all on function public.contact_greeting_word_internal(text, boolean) from public, anon;
grant execute on function public.contact_greeting_word_internal(text, boolean) to authenticated, service_role;
revoke all on function public.contact_greeting_name_internal(text, text, text) from public, anon;
grant execute on function public.contact_greeting_name_internal(text, text, text) to authenticated, service_role;
revoke all on function public.customer_greeting_internal(public.customers) from public, anon;
grant execute on function public.customer_greeting_internal(public.customers) to authenticated, service_role;
revoke all on function public.greeting_name(public.customers) from public, anon;
grant execute on function public.greeting_name(public.customers) to authenticated, service_role;
revoke all on function public.customer_greeting_for_internal(uuid, uuid, text) from public, anon;
grant execute on function public.customer_greeting_for_internal(uuid, uuid, text) to authenticated, service_role;
revoke all on function public.customer_greeting_json_internal(public.customers) from public, anon, authenticated;
grant execute on function public.customer_greeting_json_internal(public.customers) to service_role;
revoke all on function public.set_my_customer_greeting_v1(uuid, text, text) from public, anon;
grant execute on function public.set_my_customer_greeting_v1(uuid, text, text) to authenticated;

-- Lo que ya existía, con el saludo elegido donde antes iba el nombre entero o
-- la primera palabra (definiciones tomadas de producción el 2026-11-21).

CREATE OR REPLACE FUNCTION public.workshop_notice_dispatch_whatsapp_internal(p_notice_id uuid, p_now timestamp with time zone, p_in_hours boolean)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_notice public.workshop_customer_notices%rowtype;
  v_job public.mechanic_jobs%rowtype;
  v_customer public.customers%rowtype;
  v_reason text;
  v_template text;
  v_actor uuid;
  v_channel uuid;
  v_link text;
  v_code text;
  v_location jsonb;
  v_hours text;
  v_name text;
  v_greeting text;
  v_item text;
  v_number text;
  v_until text;
  v_params text[];
  v_caption text;
  v_components jsonb;
  v_binding jsonb;
  v_conversation uuid;
  v_result jsonb;
  v_message uuid;
  v_document_ready boolean := false;
  v_document_token text;
  v_total numeric;
  v_amount text;
  v_request jsonb;
begin
  select * into v_notice
    from public.workshop_customer_notices notice
   where notice.id = p_notice_id
     and notice.channel = 'whatsapp'
     and notice.state = 'pending'
   for update skip locked;
  if not found then
    return null;
  end if;

  select * into v_job
    from public.mechanic_jobs job
   where job.id = v_notice.job_id and job.tenant_id = v_notice.tenant_id;
  v_reason := public.workshop_notice_stale_reason_internal(v_notice.kind, v_job);
  if v_reason is null then
    v_document_ready := public.workshop_notice_document_ready_internal(v_notice.kind, v_job);
    v_template := public.workshop_notice_template_v2_internal(
      v_notice.tenant_id, v_notice.kind, v_job.intake_kind, v_document_ready);
  end if;

  if v_reason is null and p_now >= v_notice.expires_at then
    v_reason := case when v_template is null then 'template_not_approved' else 'expired' end;
  end if;
  if v_reason is not null then
    update public.workshop_customer_notices
       set state = 'skipped', reason = v_reason, updated_at = clock_timestamp()
     where id = v_notice.id;
    return 'skipped';
  end if;
  -- De noche, o sin plantilla aprobada todavía: espera la siguiente pasada.
  if not p_in_hours or v_template is null then
    return 'pending';
  end if;

  select * into v_customer
    from public.customers customer
   where customer.id = v_job.customer_id and customer.tenant_id = v_job.tenant_id;
  v_name := nullif(btrim(coalesce(v_customer.name, '')), '');
  v_greeting := public.customer_greeting_internal(v_customer);
  v_actor := public.workshop_notice_actor_internal(v_notice.tenant_id, v_notice.actor_id, v_job.created_by);
  select channel.id into v_channel
    from public.whatsapp_channels channel
   where channel.tenant_id = v_notice.tenant_id and channel.is_active
   order by channel.created_at
   limit 1;

  v_reason := case
    when v_name is null then 'no_customer'
    when v_actor is null then 'no_actor'
    when v_channel is null then 'no_channel'
  end;

  if v_reason is null then
    v_number := coalesce(nullif(btrim(v_job.job_number), ''), 'de taller');
    v_item := public.workshop_notice_item_internal(v_job);
  end if;

  if v_reason is null and v_template in ('taller_lista_v2', 'taller_lista_v3', 'taller_lista_v4') then
    v_location := public.workshop_notice_location_internal(v_notice.tenant_id);
    v_hours := coalesce(public.workshop_notice_hours_internal(v_notice.tenant_id),
      'en nuestro horario de atención');
    if v_location is null then
      v_reason := 'no_store_location';
    end if;
  end if;

  if v_reason is null
     and v_template in ('taller_entregada_v1', 'taller_entregada_v2', 'taller_entregada_pdf_v1',
                        'taller_entregada_pdf_v2') then
    select public.workshop_notice_date_internal(document.service_warranty_expires_at)
      into v_until
      from public.mechanic_job_delivery_documents document
     where document.tenant_id = v_job.tenant_id and document.job_id = v_job.id;
    if v_until is null then
      select public.workshop_notice_date_internal(event.warranty_expires_at)
        into v_until
        from public.mechanic_job_delivery_events event
       where event.id = v_notice.source_id;
    end if;
    if v_until is null then
      v_reason := 'no_warranty';
    end if;
  end if;

  -- El link o el código, al final: cada uno deja un código de cuenta nuevo,
  -- y un aviso que no sale no debe dejar códigos sueltos.
  if v_reason is null then
    if v_template in ('taller_recibida_v1', 'taller_presupuesto_v1', 'taller_lista_v1', 'taller_entregada_v1') then
      v_link := public.workshop_notice_link_internal(v_job, v_notice.kind, v_actor);
      if v_link is null then
        v_reason := 'no_store_url';
      end if;
    elsif v_template in ('taller_recibida_v2', 'taller_presupuesto_v2', 'taller_lista_v2',
                         'taller_lista_v3', 'taller_entregada_v2', 'taller_entregada_pdf_v1',
                         'taller_recibida_v3', 'taller_lista_v4', 'taller_entregada_pdf_v2') then
      v_code := public.workshop_notice_claim_code_internal(v_job, v_notice.kind, v_actor);
      if v_code is null then
        v_reason := 'no_customer';
      end if;
    end if;
  end if;

  -- El PDF: el código de un solo uso con que la tienda lo dibuja al enviar.
  if v_reason is null and v_template in ('taller_presupuesto_pdf_v1', 'taller_presupuesto_pdf_v2') then
    v_total := public.workshop_notice_quote_total_internal(v_job);
    v_amount := public.workshop_notice_money_internal(v_total);
    v_document_token := public.workshop_notice_document_token_internal(v_notice, 'quote');
  elsif v_reason is null and v_template in ('taller_entregada_pdf_v1', 'taller_entregada_pdf_v2') then
    v_document_token := public.workshop_notice_document_token_internal(v_notice, 'delivery');
  end if;

  if v_reason is null then
    -- Trato humano (2026-11-08): la bici o el componente en vez del número
    -- de trabajo, y el presupuesto sin el monto, que va en el PDF.
    if v_template = 'taller_recibida_v3' then
      v_params := array[v_greeting, v_item];
      v_caption := format(
        'Hola %s, ya tenemos tu %s en el taller. Te iremos contando por aquí cómo va el trabajo, y si te surge cualquier duda, respóndenos en este mismo chat.',
        v_greeting, v_item);
    elsif v_template = 'taller_presupuesto_pdf_v2' then
      v_params := array[v_greeting, v_item];
      v_caption := format(
        'Hola %s, te dejamos el presupuesto para tu %s en el PDF adjunto. Revísalo con calma: si quieres cambiar algo o tienes alguna duda, cuéntanos por aquí y lo conversamos. Si está todo en orden, puedes aprobarlo directamente desde este mensaje.',
        v_greeting, v_item);
    elsif v_template = 'taller_lista_v4' then
      v_params := array[v_greeting, v_item, v_hours];
      v_caption := format(
        'Hola %s, terminamos el trabajo en tu %s y ya está todo listo para el retiro. Puedes pasar %s. Si necesitas coordinar el retiro, avísanos por aquí.',
        v_greeting, v_item, v_hours);
    elsif v_template = 'taller_entregada_pdf_v2' then
      v_params := array[v_greeting, v_item, v_until];
      v_caption := format(
        'Hola %s, gracias por dejar tu %s en nuestras manos. Te dejamos el comprobante del trabajo: el servicio tiene garantía hasta el %s, así que si antes de esa fecha algo no funciona como debería, escríbenos por aquí y lo revisamos.',
        v_greeting, v_item, v_until);
    elsif v_template = 'taller_presupuesto_pdf_v1' then
      v_params := array[v_greeting, v_number, v_amount];
      v_caption := format(
        'Hola %s, te enviamos el presupuesto de tu trabajo %s por %s. ¿Lo apruebas?',
        v_greeting, v_number, v_amount);
    elsif v_template = 'taller_entregada_pdf_v1' then
      v_params := array[v_greeting, v_number, v_until];
      v_caption := format(
        'Hola %s, tu trabajo %s quedó entregado. Te dejamos tu comprobante; la garantía del servicio vale hasta el %s. Gracias por confiar en Viñabike.',
        v_greeting, v_number, v_until);
    elsif v_template = 'taller_recibida_v2' then
      v_params := array[v_greeting, v_item, v_number];
      v_caption := format(
        'Hola %s, recibimos tu %s. Tu número de trabajo es %s y te avisaremos por aquí cuando esté listo.',
        v_greeting, v_item, v_number);
    elsif v_template = 'taller_presupuesto_v2' then
      v_params := array[v_greeting, v_number];
      v_caption := format(
        'Hola %s, el presupuesto de tu trabajo %s está listo. Revísalo y respóndenos por aquí para aprobarlo o hacer una consulta.',
        v_greeting, v_number);
    elsif v_template = 'taller_lista_v3' then
      v_params := array[v_greeting, v_number, v_hours];
      v_caption := format(
        'Hola %s, tu trabajo %s está listo. Puedes retirarlo %s. Si necesitas coordinar el retiro, respóndenos por aquí.',
        v_greeting, v_number, v_hours);
    elsif v_template = 'taller_lista_v2' then
      v_params := array[v_greeting, v_number, v_hours];
      v_caption := format(
        'Hola %s, tu trabajo %s está listo para retirar. Te esperamos %s. Si necesitas coordinar el retiro, respóndenos por aquí.',
        v_greeting, v_number, v_hours);
    elsif v_template = 'taller_entregada_v2' then
      v_params := array[v_greeting, v_number, v_until];
      v_caption := format(
        'Hola %s, tu trabajo %s quedó entregado. La garantía del servicio vale hasta el %s. Gracias por confiar en Viñabike.',
        v_greeting, v_number, v_until);
    elsif v_template = 'taller_recibida_v1' then
      v_params := array[v_greeting, v_item, v_number, v_link];
      v_caption := format(
        'Hola %s, recibimos tu %s en Viñabike. Tu número de trabajo es %s y aquí puedes seguir su estado: %s Te avisaremos por este medio cuando esté listo.',
        v_greeting, v_item, v_number, v_link);
    elsif v_template = 'taller_presupuesto_v1' then
      v_params := array[v_greeting, v_number, v_link];
      v_caption := format(
        'Hola %s, el presupuesto de tu trabajo %s está listo. Puedes verlo aquí: %s Para aprobarlo o hacer una consulta, responde este mensaje.',
        v_greeting, v_number, v_link);
    elsif v_template = 'taller_lista_v1' then
      v_params := array[v_greeting, v_number, v_link];
      v_caption := format(
        'Hola %s, tu trabajo %s está listo para retirar en Viñabike. El detalle está aquí: %s Si necesitas coordinar el retiro, responde este mensaje.',
        v_greeting, v_number, v_link);
    elsif v_template = 'taller_entregada_v1' then
      v_params := array[v_greeting, v_number, v_until, v_link];
      v_caption := format(
        'Hola %s, gracias por retirar tu trabajo %s. La garantía del servicio vale hasta el %s y tu comprobante está aquí: %s Gracias por confiar en Viñabike.',
        v_greeting, v_number, v_until, v_link);
    elsif v_template = 'seguimiento_presupuesto_bicicleta' then
      v_params := array[v_greeting, 'Viñabike'];
      v_caption := format(
        'Hola %s, necesitamos tu respuesta sobre un presupuesto o aprobación pendiente en %s. Responde este mensaje para continuar.',
        v_greeting, 'Viñabike');
    elsif v_template = 'bicicleta_lista_retiro' then
      v_params := array[v_greeting, 'Viñabike'];
      v_caption := format(
        'Hola %s, tu bicicleta está lista para retiro en %s. Responde este mensaje si necesitas coordinar algo.',
        v_greeting, 'Viñabike');
    end if;

    v_components := jsonb_build_array(jsonb_build_object(
      'type', 'body',
      'parameters', (
        select jsonb_agg(jsonb_build_object('type', 'text', 'text', value) order by ord)
          from unnest(v_params) with ordinality as param(value, ord)
      )));
    if v_location is not null then
      v_components := jsonb_build_array(jsonb_build_object(
        'type', 'header',
        'parameters', jsonb_build_array(jsonb_build_object(
          'type', 'location', 'location', v_location)))) || v_components;
    end if;
    if v_code is not null then
      v_components := v_components || jsonb_build_array(jsonb_build_object(
        'type', 'button',
        'sub_type', 'url',
        'index', '0',
        'parameters', jsonb_build_array(jsonb_build_object('type', 'text', 'text', v_code))));
    end if;
  end if;

  if v_reason is null then
    begin
      -- Como quien hizo el cambio: la cola, la conversación y la bandeja
      -- aplican sus reglas de equipo y de tienda a esa persona.
      perform set_config('request.jwt.claims', jsonb_build_object(
        'sub', v_actor, 'role', 'authenticated')::text, true);
      perform set_config('request.jwt.claim.sub', v_actor::text, true);

      v_binding := public.ensure_whatsapp_conversation_binding(
        p_tenant_id => v_notice.tenant_id,
        p_channel_id => v_channel,
        p_wa_id => v_notice.recipient,
        p_phone_number => v_notice.recipient,
        p_contact_name => v_name,
        p_customer_id => v_customer.id,
        p_context_type => 'job',
        p_context_id => v_job.id,
        p_conversation_id => null);
      v_conversation := (v_binding->>'conversation_id')::uuid;

      v_request := jsonb_build_object(
        'conversationId', v_conversation,
        'phoneNumber', v_notice.recipient,
        'contactName', v_name,
        'customerId', v_customer.id,
        'contextType', 'job',
        'contextId', v_job.id,
        'type', 'template',
        'templateName', v_template,
        'templateLanguage', 'es_CL',
        'caption', v_caption,
        'templateComponents', v_components,
        'metadata', jsonb_build_object(
          'source', 'workshop_notice',
          'client_message_id', 'workshop-notice:' || v_notice.id,
          'greeting_name_source', 'contact_preference',
          'template_purpose', 'workshop_' || v_notice.kind,
          'template_name', v_template,
          'template_language', 'es_CL',
          'message_category', 'utility',
          'workshop_notice_id', v_notice.id,
          'job_id', v_job.id));
      if v_document_token is not null then
        v_request := v_request || jsonb_build_object('templateDocumentToken', v_document_token);
      end if;
      -- «Aprobar presupuesto» aprueba de verdad: whatsapp-send verifica el
      -- trabajo, pone la clave de un solo uso en la respuesta rápida y deja
      -- la tarjeta del presupuesto en la conversación
      -- (`apply_whatsapp_job_action`).
      if v_template in ('taller_presupuesto_pdf_v1', 'taller_presupuesto_pdf_v2') then
        v_request := v_request || jsonb_build_object(
          'actionType', 'approve_quote',
          'actionKind', 'job',
          'actionTargetId', v_job.id,
          'amount', v_total);
      end if;
      v_result := public.enqueue_whatsapp_message_v1(v_request);
      v_message := nullif(v_result->>'message_id', '')::uuid;
      if v_message is null then
        v_reason := 'send_not_accepted';
      end if;
    exception when others then
      v_reason := left('send_failed: ' || sqlerrm, 280);
    end;
    perform set_config('request.jwt.claims', '', true);
    perform set_config('request.jwt.claim.sub', '', true);
  end if;

  if v_message is not null then
    update public.workshop_customer_notices
       set state = 'sent', sent_at = clock_timestamp(), template_name = v_template,
           message_id = v_message, attempt_count = attempt_count + 1,
           reason = null, updated_at = clock_timestamp()
     where id = v_notice.id;
    return 'sent';
  end if;

  update public.workshop_customer_notices
     set state = case when v_reason like 'send_%' then 'failed' else 'skipped' end,
         reason = v_reason, template_name = v_template,
         attempt_count = attempt_count + 1, updated_at = clock_timestamp()
   where id = v_notice.id;
  return case when v_reason like 'send_%' then 'failed' else 'skipped' end;
end;
$function$
;

CREATE OR REPLACE FUNCTION public.process_whatsapp_review_requests_v1(p_now timestamp with time zone DEFAULT now())
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'extensions'
AS $function$
declare
  v_local_hour integer := extract(hour from (p_now at time zone 'America/Santiago'))::integer;
  v_row record;
  v_phone text;
  v_place text;
  v_channel uuid;
  v_reason text;
  v_name text;
  v_greeting text;
  v_link text;
  v_template text;
  v_caption text;
  v_components jsonb;
  v_binding jsonb;
  v_conversation uuid;
  v_result jsonb;
  v_message uuid;
  v_job public.mechanic_jobs%rowtype;
  v_item text;
  v_sent integer := 0;
  v_skipped integer := 0;
begin
  -- Nadie recibe un pedido de reseña de noche: lo que llega fuera de la
  -- ventana espera a la siguiente pasada dentro de ella (la entrega sigue
  -- vigente 3 días).
  if v_local_hour < 10 or v_local_hour >= 20 then
    return jsonb_build_object('sent', 0, 'skipped', 0, 'outside_hours', true);
  end if;

  for v_row in
    select e.id as event_id, e.tenant_id, e.job_id, e.actor_id,
           j.status as job_status, j.customer_id,
           c.name as customer_name, c.greeting_style as customer_greeting_style,
           c.greeting_custom_name as customer_greeting_custom_name, c.phone as customer_phone
      from public.mechanic_job_delivery_events e
      join public.company_settings s
        on s.tenant_id = e.tenant_id
       and s.key = 'whatsapp_review_request_enabled'
       and s.value = 'true'
      join public.mechanic_jobs j
        on j.id = e.job_id and j.tenant_id = e.tenant_id
      left join public.customers c
        on c.id = j.customer_id and c.tenant_id = j.tenant_id
     where e.event_kind = 'delivered'
       and e.source = 'status_transition'
       and e.occurred_at > p_now - interval '3 days'
       and e.occurred_at <= p_now - interval '3 hours'
       and not exists (
         select 1 from public.whatsapp_review_requests r
          where r.tenant_id = e.tenant_id and r.job_id = e.job_id)
     order by e.occurred_at
     limit 20
  loop
    v_reason := null;
    v_message := null;
    v_phone := public.normalize_whatsapp_phone(v_row.customer_phone);
    v_name := nullif(btrim(coalesce(v_row.customer_name, '')), '');
    v_greeting := public.contact_greeting_name_internal(
      v_row.customer_name, v_row.customer_greeting_style, v_row.customer_greeting_custom_name);

    select nullif(btrim(value), '') into v_place
      from public.website_settings
     where tenant_id = v_row.tenant_id and key = 'google_maps_place_id';
    select id into v_channel
      from public.whatsapp_channels
     where tenant_id = v_row.tenant_id and is_active
     order by created_at
     limit 1;

    if v_row.job_status is distinct from 'ENTREGADO' then
      v_reason := 'job_not_delivered';
    elsif v_row.customer_id is null or v_name is null then
      v_reason := 'no_customer';
    elsif v_phone is null or v_phone !~ '^569[0-9]{8}$' then
      v_reason := 'no_mobile';
    elsif v_row.actor_id is null then
      v_reason := 'no_actor';
    elsif exists (
      select 1 from public.whatsapp_review_requests r
       where r.tenant_id = v_row.tenant_id
         and r.status = 'sent'
         and r.created_at > p_now - interval '365 days'
         and (r.customer_id = v_row.customer_id or r.phone = v_phone)) then
      v_reason := 'asked_this_year';
    elsif v_place is null or v_place !~ '^[A-Za-z0-9_-]{10,}$' then
      v_reason := 'no_review_link';
    elsif v_channel is null then
      v_reason := 'no_channel';
    end if;

    if v_reason is null then
      -- El lugar va sin codificar en el botón: el patrón de arriba sólo deja
      -- letras, números, guion y guion bajo.
      if public.whatsapp_template_approved_internal(v_row.tenant_id, 'resena_google_v3') then
        -- Trato humano (2026-11-08): nombra la bici en vez de la tienda.
        select * into v_job
          from public.mechanic_jobs job
         where job.id = v_row.job_id and job.tenant_id = v_row.tenant_id;
        v_item := public.workshop_notice_item_internal(v_job);
        v_template := 'resena_google_v3';
        v_caption := format(
          'Hola %s, ojalá estés disfrutando tu %s. Si quedaste conforme con el servicio, una reseña en Google nos ayuda mucho.',
          v_greeting, v_item);
        v_components := jsonb_build_array(
          jsonb_build_object(
            'type', 'body',
            'parameters', jsonb_build_array(
              jsonb_build_object('type', 'text', 'text', v_greeting),
              jsonb_build_object('type', 'text', 'text', v_item))),
          jsonb_build_object(
            'type', 'button',
            'sub_type', 'url',
            'index', '0',
            'parameters', jsonb_build_array(jsonb_build_object('type', 'text', 'text', v_place))));
      elsif public.whatsapp_template_approved_internal(v_row.tenant_id, 'resena_google_v2') then
        v_template := 'resena_google_v2';
        v_caption := format(
          'Hola %s, gracias por elegir Viñabike. Si te gustó el servicio, una reseña en Google nos ayuda mucho.',
          v_greeting);
        v_components := jsonb_build_array(
          jsonb_build_object(
            'type', 'body',
            'parameters', jsonb_build_array(jsonb_build_object('type', 'text', 'text', v_greeting))),
          jsonb_build_object(
            'type', 'button',
            'sub_type', 'url',
            'index', '0',
            'parameters', jsonb_build_array(jsonb_build_object('type', 'text', 'text', v_place))));
      else
        v_template := 'resena_google_v1';
        v_link := 'https://search.google.com/local/writereview?placeid=' || v_place;
        v_caption := format(
          'Hola %s, ya entregamos tu bicicleta en Viñabike. ¿Cómo te fue con el servicio? Puedes contarnos con una reseña en Google: %s Gracias por preferirnos.',
          v_greeting, v_link);
        v_components := jsonb_build_array(jsonb_build_object(
          'type', 'body',
          'parameters', jsonb_build_array(
            jsonb_build_object('type', 'text', 'text', v_greeting),
            jsonb_build_object('type', 'text', 'text', v_link))));
      end if;

      begin
        -- Como quien entregó la bici: la cola, la conversación y la bandeja
        -- aplican sus reglas de equipo y de tienda a esa persona.
        perform set_config('request.jwt.claims', jsonb_build_object(
          'sub', v_row.actor_id, 'role', 'authenticated')::text, true);
        perform set_config('request.jwt.claim.sub', v_row.actor_id::text, true);

        v_binding := public.ensure_whatsapp_conversation_binding(
          p_tenant_id => v_row.tenant_id,
          p_channel_id => v_channel,
          p_wa_id => v_phone,
          p_phone_number => v_phone,
          p_contact_name => v_name,
          p_customer_id => v_row.customer_id,
          p_context_type => 'job',
          p_context_id => v_row.job_id,
          p_conversation_id => null);
        v_conversation := (v_binding->>'conversation_id')::uuid;

        -- El texto es el cuerpo aprobado de la plantilla con sus parámetros;
        -- el envío lo acorta al nombre de pila igual que en las demás
        -- plantillas (`template_purpose`).
        v_result := public.enqueue_whatsapp_message_v1(jsonb_build_object(
          'conversationId', v_conversation,
          'phoneNumber', v_phone,
          'contactName', v_name,
          'customerId', v_row.customer_id,
          'contextType', 'job',
          'contextId', v_row.job_id,
          'type', 'template',
          'templateName', v_template,
          'templateLanguage', 'es_CL',
          'caption', v_caption,
          'templateComponents', v_components,
          'metadata', jsonb_build_object(
            'source', 'review_request',
            'client_message_id', 'review-request:' || v_row.job_id,
            'greeting_name_source', 'contact_preference',
            'template_purpose', 'google_review_request',
            'template_name', v_template,
            'template_language', 'es_CL',
            'message_category', 'utility',
            'job_id', v_row.job_id)));
        v_message := nullif(v_result->>'message_id', '')::uuid;
        if v_message is null then
          v_reason := 'send_not_accepted';
        end if;
      exception when others then
        v_reason := left('send_failed: ' || sqlerrm, 240);
      end;
      perform set_config('request.jwt.claims', '', true);
      perform set_config('request.jwt.claim.sub', '', true);
    end if;

    insert into public.whatsapp_review_requests(
      tenant_id, job_id, delivery_event_id, customer_id, phone, actor_id,
      status, reason, message_id)
    values (
      v_row.tenant_id, v_row.job_id, v_row.event_id, v_row.customer_id, v_phone,
      v_row.actor_id,
      case when v_reason is null then 'sent' else 'skipped' end,
      v_reason, v_message)
    on conflict (tenant_id, job_id) do nothing;

    if v_reason is null then
      v_sent := v_sent + 1;
    else
      v_skipped := v_skipped + 1;
    end if;
  end loop;

  return jsonb_build_object('sent', v_sent, 'skipped', v_skipped);
end;
$function$
;

CREATE OR REPLACE FUNCTION public.peek_customer_portal_claim_code_v1(p_tenant_id uuid, p_code text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
declare
  v_code public.customer_portal_claim_codes%rowtype;
  v_customer public.customers%rowtype;
  v_job public.mechanic_jobs%rowtype;
  v_bike text;
begin
  if p_tenant_id is null
     or length(coalesce(p_code, '')) < 40
     or length(p_code) > 128 then
    return jsonb_build_object('status', 'invalid');
  end if;

  select * into v_code
    from public.customer_portal_claim_codes code
   where code.tenant_id = p_tenant_id
     and code.code_sha256 = encode(extensions.digest(convert_to(p_code, 'UTF8'), 'sha256'), 'hex');
  if not found or v_code.revoked_at is not null then
    return jsonb_build_object('status', 'invalid');
  end if;

  select * into v_customer
    from public.customers
   where id = v_code.customer_id
     and tenant_id = p_tenant_id;
  if not found or v_customer.is_active is not true then
    return jsonb_build_object('status', 'invalid');
  end if;
  if v_customer.auth_user_id is not null then
    -- Ya tiene cuenta: que entre. No se dice cuál.
    return jsonb_build_object('status', 'linked');
  end if;
  if v_code.expires_at <= clock_timestamp() then
    return jsonb_build_object('status', 'expired');
  end if;

  select * into v_job
    from public.mechanic_jobs
   where id = v_code.job_id
     and tenant_id = p_tenant_id;

  select nullif(btrim(concat_ws(' ', nullif(btrim(bike.brand), ''), nullif(btrim(bike.model), ''))), '')
    into v_bike
    from public.mechanic_job_bikes job_bike
    join public.bikes bike
      on bike.id = job_bike.bike_id
     and bike.tenant_id = job_bike.tenant_id
   where job_bike.tenant_id = p_tenant_id
     and job_bike.job_id = v_code.job_id
   order by job_bike.order_index, job_bike.created_at
   limit 1;
  if v_bike is null and v_job.bike_id is not null then
    select nullif(btrim(concat_ws(' ', nullif(btrim(bike.brand), ''), nullif(btrim(bike.model), ''))), '')
      into v_bike
      from public.bikes bike
     where bike.id = v_job.bike_id
       and bike.tenant_id = p_tenant_id;
  end if;

  return jsonb_strip_nulls(jsonb_build_object(
    'status', 'valid',
    'first_name', public.customer_greeting_internal(v_customer),
    'purpose', v_code.purpose,
    'job_number', v_job.job_number,
    'bike', v_bike,
    'delivered', coalesce(v_job.status = 'ENTREGADO' or v_job.delivered_at is not null, false),
    'expires_at', v_code.expires_at
  ));
end;
$function$
;

CREATE OR REPLACE FUNCTION public.claim_customer_portal_code_v1(p_tenant_id uuid, p_code text, p_phone text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
declare
  v_uid uuid := auth.uid();
  v_email text;
  v_code public.customer_portal_claim_codes%rowtype;
  v_customer public.customers%rowtype;
  v_code_text text := nullif(trim(p_code), '');
  v_phone_text text := nullif(trim(p_phone), '');
  v_pending jsonb;
  v_typed_digits text;
  v_record_digits text;
  v_failures integer;
  v_outcome text;
begin
  if v_uid is null then
    raise exception 'claim_account_required' using errcode = '42501';
  end if;

  -- Sin código, el que dejó pendiente la propia cuenta al crearse desde el
  -- QR (`vinabike_claim_code` en sus metadatos): así se liga aunque confirme
  -- el correo en otro navegador. Sigue siendo un código que se comprueba.
  if v_code_text is null then
    select coalesce(auth_user.raw_user_meta_data, '{}'::jsonb) into v_pending
      from auth.users auth_user
     where auth_user.id = v_uid;
    v_code_text := nullif(trim(v_pending ->> 'vinabike_claim_code'), '');
    v_phone_text := coalesce(v_phone_text, nullif(trim(v_pending ->> 'vinabike_claim_phone'), ''));
    if v_code_text is null then
      return jsonb_build_object('status', 'nothing_pending');
    end if;
  end if;
  v_typed_digits := regexp_replace(coalesce(v_phone_text, ''), '[^0-9]', '', 'g');

  select lower(nullif(trim(auth_user.email), '')) into v_email
    from auth.users auth_user
   where auth_user.id = v_uid
     and auth_user.email_confirmed_at is not null;
  if v_email is null then
    raise exception 'A confirmed Auth email is required' using errcode = '42501';
  end if;

  select count(*) into v_failures
    from public.customer_portal_claim_attempts attempt
   where attempt.auth_user_id = v_uid
     and attempt.attempted_at > clock_timestamp() - interval '1 hour'
     and attempt.outcome not in ('linked', 'already_yours');
  if v_failures >= 10 then
    return jsonb_build_object('status', 'too_many_attempts');
  end if;

  if length(v_code_text) < 40 or length(v_code_text) > 128 then
    v_outcome := 'invalid';
  else
    select * into v_code
      from public.customer_portal_claim_codes code
     where code.tenant_id = p_tenant_id
       and code.code_sha256 = encode(extensions.digest(convert_to(v_code_text, 'UTF8'), 'sha256'), 'hex')
     for update;
    if not found or v_code.revoked_at is not null then
      v_outcome := 'invalid';
    elsif v_code.expires_at <= clock_timestamp() then
      v_outcome := 'expired';
    end if;
  end if;

  if v_outcome is null then
    select * into v_customer
      from public.customers
     where id = v_code.customer_id
       and tenant_id = p_tenant_id
     for update;
    if not found or v_customer.is_active is not true then
      v_outcome := 'invalid';
    elsif v_customer.auth_user_id = v_uid then
      v_outcome := 'already_yours';
    elsif v_customer.auth_user_id is not null then
      v_outcome := 'linked_elsewhere';
    else
      v_record_digits := regexp_replace(coalesce(v_customer.phone, ''), '[^0-9]', '', 'g');
      if length(v_record_digits) >= 8
         and (length(v_typed_digits) < 8
              or right(v_typed_digits, 8) <> right(v_record_digits, 8)) then
        v_outcome := 'phone_mismatch';
      end if;
    end if;
  end if;

  if v_outcome is null then
    v_outcome := public.link_portal_account_to_customer_internal(
      p_tenant_id, v_uid, v_email, v_customer.id, v_phone_text, 'con el QR'
    );
  end if;

  if v_outcome is not null then
    insert into public.customer_portal_claim_attempts (tenant_id, auth_user_id, outcome)
    values (p_tenant_id, v_uid, v_outcome);
    -- Un código pendiente se usa una vez: si no sirvió, se vuelve a escanear.
    update auth.users
       set raw_user_meta_data = coalesce(raw_user_meta_data, '{}'::jsonb)
         - 'vinabike_claim_code' - 'vinabike_claim_phone'
     where id = v_uid
       and coalesce(raw_user_meta_data, '{}'::jsonb) ?| array['vinabike_claim_code', 'vinabike_claim_phone'];
    return jsonb_build_object('status', v_outcome);
  end if;

  update public.customer_portal_claim_codes
     set claimed_at = clock_timestamp(),
         claimed_by = v_uid
   where tenant_id = p_tenant_id
     and customer_id = v_customer.id
     and claimed_at is null
     and revoked_at is null;

  insert into public.customer_portal_claim_attempts (tenant_id, auth_user_id, outcome)
  values (p_tenant_id, v_uid, 'linked');
  update auth.users
     set raw_user_meta_data = coalesce(raw_user_meta_data, '{}'::jsonb)
       - 'vinabike_claim_code' - 'vinabike_claim_phone'
   where id = v_uid
     and coalesce(raw_user_meta_data, '{}'::jsonb) ?| array['vinabike_claim_code', 'vinabike_claim_phone'];

  return jsonb_build_object(
    'status', 'linked',
    'customer_id', v_customer.id,
    'job_id', v_code.job_id,
    'purpose', v_code.purpose,
    'first_name', public.customer_greeting_internal(v_customer)
  );
end;
$function$
;

CREATE OR REPLACE FUNCTION public.issue_customer_portal_claim_code_v1(p_job_id uuid, p_purpose text DEFAULT 'reception'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
declare
  v_job public.mechanic_jobs%rowtype;
  v_customer public.customers%rowtype;
  v_raw text;
  v_expires timestamptz := clock_timestamp() + interval '120 days';
begin
  if p_purpose is null or p_purpose not in ('reception', 'delivery', 'manual') then
    raise exception 'Invalid claim-code purpose' using errcode = '22023';
  end if;

  select * into v_job from public.mechanic_jobs where id = p_job_id;
  if not found or not public.is_active_tenant_member(v_job.tenant_id) then
    raise exception 'Job not found or not accessible' using errcode = 'P0002';
  end if;

  select * into v_customer
    from public.customers
   where id = v_job.customer_id
     and tenant_id = v_job.tenant_id;
  if not found or v_customer.is_active is not true then
    return jsonb_build_object('status', 'no_customer');
  end if;
  if v_customer.auth_user_id is not null then
    return jsonb_build_object('status', 'already_linked');
  end if;

  v_raw := rtrim(translate(encode(extensions.gen_random_bytes(32), 'base64'), '+/', '-_'), '=');
  insert into public.customer_portal_claim_codes (
    tenant_id, customer_id, job_id, purpose, code_sha256, expires_at, created_by
  ) values (
    v_job.tenant_id,
    v_customer.id,
    v_job.id,
    p_purpose,
    encode(extensions.digest(convert_to(v_raw, 'UTF8'), 'sha256'), 'hex'),
    v_expires,
    auth.uid()
  );

  return jsonb_build_object(
    'status', 'issued',
    'code', v_raw,
    'expires_at', v_expires,
    -- Adonde lleva el QR y a quién saluda: lo que el ERP dibuja en la
    -- recepción, de la misma regla que el comprobante.
    'store_url', (
      select nullif(btrim(setting.value), '')
        from public.website_settings setting
       where setting.tenant_id = v_job.tenant_id
         and setting.key = 'store_url'
    ),
    'customer_first_name', public.customer_greeting_internal(v_customer)
  );
end;
$function$
;

CREATE OR REPLACE FUNCTION public.whatsapp_card_reply_internal(p_tenant_id uuid, p_conversation_id uuid, p_customer_id uuid, p_phone text, p_job_id uuid, p_kind text, p_key text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_job public.mechanic_jobs%rowtype;
  v_customer public.customers%rowtype;
  v_first text;
  v_item text;
  v_text text;
  v_actor uuid;
  v_claims text := current_setting('request.jwt.claims', true);
  v_sub text := current_setting('request.jwt.claim.sub', true);
  v_result jsonb;
begin
  select * into v_job
    from public.mechanic_jobs job
   where job.id = p_job_id and job.tenant_id = p_tenant_id;
  select * into v_customer
    from public.customers customer
   where customer.id = p_customer_id and customer.tenant_id = p_tenant_id;
  v_first := public.customer_greeting_internal(v_customer);
  v_actor := public.workshop_notice_actor_internal(p_tenant_id, null, v_job.created_by);
  if v_job.id is null or v_first is null or v_actor is null
     or nullif(btrim(coalesce(p_phone, '')), '') is null then
    return null;
  end if;
  v_item := public.workshop_notice_item_internal(v_job);
  v_text := case p_kind
    when 'quote_approved' then format(
      'Gracias, %s, quedó aprobado. Ya nos ponemos manos a la obra con tu %s y te avisamos por aquí apenas terminemos.',
      v_first, v_item)
    when 'question' then format(
      'Claro, %s. Cuéntanos tu consulta por aquí y te respondemos lo antes posible.',
      v_first)
  end;
  if v_text is null then
    return null;
  end if;

  begin
    perform set_config('request.jwt.claims', jsonb_build_object(
      'sub', v_actor, 'role', 'authenticated')::text, true);
    perform set_config('request.jwt.claim.sub', v_actor::text, true);
    v_result := public.enqueue_whatsapp_message_v1(jsonb_build_object(
      'conversationId', p_conversation_id,
      'phoneNumber', p_phone,
      'contactName', v_customer.name,
      'customerId', v_customer.id,
      'contextType', 'job',
      'contextId', v_job.id,
      'type', 'text',
      'text', v_text,
      'metadata', jsonb_build_object(
        'source', 'workshop_card_reply',
        'client_message_id', p_key,
        'card_reply_kind', p_kind,
        'job_id', v_job.id)));
    perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);
    perform set_config('request.jwt.claim.sub', coalesce(v_sub, ''), true);
    return nullif(v_result->>'message_id', '')::uuid;
  exception when others then
    -- Una respuesta de cortesía nunca deshace el toque que la pidió.
    raise warning 'whatsapp_card_reply_internal(%): %', p_kind, sqlerrm;
    return null;
  end;
end;
$function$
;

CREATE OR REPLACE FUNCTION public.confirm_customer_phone_verification_v1(p_tenant_id uuid, p_code text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
declare
  v_uid uuid := auth.uid();
  v_email text;
  v_row public.customer_portal_phone_verifications%rowtype;
  v_code text := regexp_replace(coalesce(p_code, ''), '[^0-9]', '', 'g');
  v_current public.customers%rowtype;
  v_candidate uuid;
  v_candidates integer;
  v_outcome text;
begin
  if v_uid is null then
    raise exception 'phone_verification_account_required' using errcode = '42501';
  end if;
  select lower(nullif(trim(auth_user.email), '')) into v_email
    from auth.users auth_user
   where auth_user.id = v_uid
     and auth_user.email_confirmed_at is not null;
  if v_email is null then
    raise exception 'A confirmed Auth email is required' using errcode = '42501';
  end if;

  select * into v_row
    from public.customer_portal_phone_verifications verification
   where verification.tenant_id = p_tenant_id
     and verification.auth_user_id = v_uid
     and verification.confirmed_at is null
     and verification.send_outcome = 'sent'
   order by verification.created_at desc
   limit 1
   for update;
  if not found or v_row.expires_at <= clock_timestamp() then
    return jsonb_build_object('status', 'expired');
  end if;
  if v_row.attempts >= 5 then
    return jsonb_build_object('status', 'too_many_attempts');
  end if;
  if length(v_code) <> 6
     or encode(extensions.digest(convert_to(v_row.id::text || ':' || v_code, 'UTF8'), 'sha256'), 'hex')
        <> v_row.code_sha256 then
    update public.customer_portal_phone_verifications
       set attempts = attempts + 1
     where id = v_row.id;
    if v_row.attempts + 1 >= 5 then
      return jsonb_build_object('status', 'too_many_attempts');
    end if;
    return jsonb_build_object('status', 'wrong_code', 'attempts_left', 5 - (v_row.attempts + 1));
  end if;

  update public.customer_portal_phone_verifications
     set confirmed_at = clock_timestamp()
   where id = v_row.id;
  insert into public.customer_portal_verified_phones (tenant_id, auth_user_id, phone_digits, verified_at)
  values (p_tenant_id, v_uid, v_row.phone_digits, clock_timestamp())
  on conflict (tenant_id, auth_user_id) do update
    set phone_digits = excluded.phone_digits,
        verified_at = excluded.verified_at;

  select * into v_current
    from public.customers customer
   where customer.tenant_id = p_tenant_id
     and customer.auth_user_id = v_uid;
  if not found then
    perform public.provision_current_public_store_customer(p_tenant_id);
    select * into v_current
      from public.customers customer
     where customer.tenant_id = p_tenant_id
       and customer.auth_user_id = v_uid;
  end if;

  select candidate.customer_id, candidate.candidates
    into v_candidate, v_candidates
    from public.customer_phone_link_candidate_internal(p_tenant_id, v_row.phone_digits, v_current.id) candidate;

  if v_candidates = 1 then
    v_outcome := public.link_portal_account_to_customer_internal(
      p_tenant_id,
      v_uid,
      v_email,
      v_candidate,
      public.customer_phone_display_internal(v_row.phone_digits),
      'con su teléfono verificado'
    );
    if v_outcome is null then
      return jsonb_build_object(
        'status', 'linked',
        'customer_id', v_candidate,
        'first_name', (select public.customer_greeting_internal(customer)
                         from public.customers customer where customer.id = v_candidate)
      );
    end if;
  end if;

  -- Sin ficha que ligar: el número confirmado queda en la ficha de la cuenta
  -- si no tenía uno.
  update public.customers
     set phone = public.customer_phone_display_internal(v_row.phone_digits),
         updated_at = clock_timestamp()
   where id = v_current.id
     and tenant_id = p_tenant_id
     and nullif(trim(phone), '') is null;

  return jsonb_build_object(
    'status',
    case
      when v_candidates = 0 then 'verified'
      when v_candidates > 1 then 'verified_ambiguous'
      else 'verified_has_history'
    end
  );
end;
$function$
;

CREATE OR REPLACE FUNCTION public.workshop_notice_email_payload_internal(p_notice_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_notice public.workshop_customer_notices%rowtype;
  v_job public.mechanic_jobs%rowtype;
  v_customer public.customers%rowtype;
  v_tenant public.tenants%rowtype;
  v_settings public.transactional_email_settings%rowtype;
  v_document public.mechanic_job_delivery_documents%rowtype;
  v_store text;
  v_link text;
  v_has_parts boolean := false;
begin
  select * into v_notice from public.workshop_customer_notices where id = p_notice_id;
  select * into v_job from public.mechanic_jobs
   where id = v_notice.job_id and tenant_id = v_notice.tenant_id;
  select * into v_customer from public.customers
   where id = v_job.customer_id and tenant_id = v_job.tenant_id;
  select * into v_tenant from public.tenants where id = v_notice.tenant_id;
  select * into v_settings from public.transactional_email_settings where tenant_id = v_notice.tenant_id;
  v_store := public.workshop_notice_store_url_internal(v_notice.tenant_id);
  v_link := public.workshop_notice_link_internal(v_job, v_notice.kind, v_notice.actor_id);
  if v_notice.kind = 'delivered' then
    select * into v_document from public.mechanic_job_delivery_documents
     where tenant_id = v_job.tenant_id and job_id = v_job.id;
    v_has_parts := coalesce((
      select bool_or(line->>'kind' = 'part')
        from jsonb_array_elements(coalesce(v_document.snapshot->'lines', '[]'::jsonb)) line
    ), false);
  end if;

  return jsonb_build_object(
    'noticeId', v_notice.id,
    'kind', v_notice.kind,
    'recipient', v_notice.recipient,
    'sender', jsonb_strip_nulls(jsonb_build_object(
      'enabled', coalesce(v_settings.enabled, false) and v_settings.delivery_mode = 'send',
      'name', v_settings.from_name,
      'email', v_settings.from_email,
      'replyTo', v_settings.reply_to_email
    )),
    'store', jsonb_strip_nulls(jsonb_build_object(
      'name', v_tenant.shop_name,
      'logoUrl', case
        when v_tenant.logo_url ~* '^https://[^[:space:]]+$' then v_tenant.logo_url
        else (
          select setting.value from public.website_settings setting
           where setting.tenant_id = v_notice.tenant_id
             and setting.key = 'company_logo_url'
             and setting.value ~* '^https://[^[:space:]]+$'
           limit 1
        )
      end,
      'storeUrl', v_store,
      'timezone', coalesce(v_tenant.timezone, 'America/Santiago'),
      'brandColor', (
        select case
          when setting.value ~ '^#[0-9A-Fa-f]{6}$' then upper(setting.value)
          when setting.value ~ '^[0-9]{1,10}$'
            then '#' || upper(lpad(to_hex(setting.value::bigint & 16777215), 6, '0'))
        end
          from public.website_settings setting
         where setting.tenant_id = v_notice.tenant_id and setting.key = 'theme_primary_color'
         limit 1
      )
    )),
    'job', jsonb_strip_nulls(jsonb_build_object(
      'number', v_job.job_number,
      -- El saludo que eligió el cliente (20261121200000); el nombre entero
      -- queda para un correo anterior al cambio.
      'customerName', nullif(btrim(v_customer.name), ''),
      'customerGreeting', public.customer_greeting_internal(v_customer),
      'item', public.workshop_notice_item_internal(v_job),
      'intake', coalesce(v_job.intake_kind, 'bike'),
      'request', nullif(btrim(v_job.client_request), ''),
      'receivedAt', coalesce(v_job.arrival_date, v_job.created_at),
      'total', case
        when v_notice.kind = 'quote_ready' and coalesce(v_job.total_cost, 0) > 0 then v_job.total_cost
      end
    )),
    'delivery', case when v_notice.kind = 'delivered' and v_document.id is not null then
      jsonb_strip_nulls(jsonb_build_object(
        'deliveredAt', v_document.delivered_at,
        'workPerformed', coalesce(
          nullif(btrim(v_document.snapshot->>'work_performed'), ''),
          nullif(btrim(v_job.work_performed), '')),
        'serviceWarrantyUntil', case
          when v_document.service_warranty_days > 0 then v_document.service_warranty_expires_at
        end,
        'partsWarrantyUntil', case
          when v_has_parts and v_document.parts_warranty_months > 0 then v_document.parts_warranty_expires_at
        end
      ))
    end,
    'link', v_link,
    'linkKind', case when v_link like '%/cuenta/vincular#c=%' then 'claim' else 'portal' end,
    'preferencesLink', case when v_store is null then null else v_store || '/cuenta/perfil' end
  );
end;
$function$
;

CREATE OR REPLACE FUNCTION public.customer_quote_email_payload_internal(p_message_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_message public.customer_quote_messages%rowtype;
  v_quote public.customer_quotes%rowtype;
  v_tenant public.tenants%rowtype;
  v_settings public.transactional_email_settings%rowtype;
  v_store_url text;
  v_access jsonb;
  v_offer_id uuid;
begin
  select * into v_message from public.customer_quote_messages where id = p_message_id;
  select * into v_quote from public.customer_quotes where id = v_message.quote_id;
  select * into v_tenant from public.tenants where id = v_quote.tenant_id;
  select * into v_settings from public.transactional_email_settings where tenant_id = v_quote.tenant_id;
  v_store_url := public.transactional_email_store_url(v_settings.public_store_url, v_tenant.custom_domain);
  v_offer_id := coalesce(v_message.offer_id, v_quote.current_offer_id);
  v_access := public.customer_quote_issue_token_internal(
    v_quote.id, array['view_quote', 'respond_quote'], clock_timestamp() + interval '60 days'
  );

  return jsonb_build_object(
    'messageId', v_message.id,
    'kind', v_message.kind,
    'recipient', v_message.recipient,
    'sender', jsonb_strip_nulls(jsonb_build_object(
      'enabled', coalesce(v_settings.enabled, false) and v_settings.delivery_mode = 'send',
      'name', v_settings.from_name,
      'email', v_settings.from_email,
      'replyTo', v_settings.reply_to_email
    )),
    'store', jsonb_strip_nulls(jsonb_build_object(
      'name', v_tenant.shop_name,
      'logoUrl', case
        when v_tenant.logo_url ~* '^https://[^[:space:]]+$' then v_tenant.logo_url
        else (
          select setting.value from public.website_settings setting
           where setting.tenant_id = v_quote.tenant_id
             and setting.key = 'company_logo_url'
             and setting.value ~* '^https://[^[:space:]]+$'
           limit 1
        )
      end,
      'storeUrl', v_store_url,
      'timezone', coalesce(v_tenant.timezone, 'America/Santiago'),
      'brandColor', (
        select case
          when setting.value ~ '^#[0-9A-Fa-f]{6}$' then upper(setting.value)
          when setting.value ~ '^[0-9]{1,10}$'
            then '#' || upper(lpad(to_hex(setting.value::bigint & 16777215), 6, '0'))
        end
          from public.website_settings setting
         where setting.tenant_id = v_quote.tenant_id and setting.key = 'theme_primary_color'
         limit 1
      )
    )),
    'quote', jsonb_strip_nulls(jsonb_build_object(
      'number', v_quote.quote_number,
      'status', v_quote.status,
      'customerName', v_quote.customer_name,
      'customerGreeting', public.customer_greeting_for_internal(
        v_quote.tenant_id, v_quote.customer_id, v_quote.customer_name),
      'requestedAt', v_quote.requested_at,
      'expiresAt', v_quote.expires_at
    )),
    'requested', coalesce((
      select jsonb_agg(jsonb_build_object('name', l.product_name, 'quantity', l.quantity) order by l.line_no)
        from public.customer_quote_lines l where l.quote_id = v_quote.id
    ), '[]'::jsonb),
    'offer', (
      select jsonb_strip_nulls(jsonb_build_object(
        'number', o.offer_no,
        'validUntil', o.valid_until,
        'subtotal', o.subtotal,
        'taxAmount', o.tax_amount,
        'total', o.total,
        'notes', o.notes_to_customer,
        'lines', coalesce((
          select jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
            'name', ol.product_name,
            'availability', ol.availability,
            'quantityRequested', ol.quantity_requested,
            'quantity', ol.quantity_offered,
            'unitPrice', ol.unit_price,
            'lineTotal', case when ol.quantity_offered > 0 then ol.unit_price * ol.quantity_offered end,
            'leadDaysMin', ol.lead_days_min,
            'leadDaysMax', ol.lead_days_max,
            'note', ol.customer_note
          )) order by ol.line_no)
            from public.customer_quote_offer_lines ol where ol.offer_id = o.id
        ), '[]'::jsonb)
      ))
        from public.customer_quote_offers o
       where o.id = v_offer_id and o.status <> 'draft'
    ),
    'prepayPercent', (public.customer_quote_settings_internal(v_quote.tenant_id)).on_order_prepay_percent,
    'link', case
      when v_store_url is null then null
      else rtrim(v_store_url, '/') || '/cotizacion#t=' || (v_access ->> 'token')
    end
  );
end;
$function$
;

CREATE OR REPLACE FUNCTION public.transactional_email_render_payload(p_order online_orders, p_message_kind text, p_shipment online_order_shipments DEFAULT NULL::online_order_shipments)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare
  v_tenant public.tenants%rowtype;
  v_settings public.transactional_email_settings%rowtype;
  v_store_url text;
  v_items jsonb;
  v_payload jsonb;
begin
  select * into v_tenant
  from public.tenants
  where id = p_order.tenant_id;

  select * into v_settings
  from public.transactional_email_settings
  where tenant_id = p_order.tenant_id;

  v_store_url := public.transactional_email_store_url(
    v_settings.public_store_url,
    v_tenant.custom_domain
  );

  select coalesce(jsonb_agg(
    jsonb_build_object(
      'name', item.product_name,
      'sku', item.product_sku,
      'quantity', item.quantity,
      'unitPrice', item.unit_price,
      'subtotal', item.subtotal,
      -- Lo que todavía trae el proveedor lleva su plazo de despacho; el
      -- correo dice sólo ese plazo, nunca «a pedido» (20261120210000).
      'leadDaysMin', case
        when item.fulfillment = 'on_order' and item.arrived_at is null
          then item.lead_days_min
      end,
      'leadDaysMax', case
        when item.fulfillment = 'on_order' and item.arrived_at is null
          then item.lead_days_max
      end
    ) order by item.created_at, item.id
  ), '[]'::jsonb)
  into v_items
  from public.online_order_items item
  where item.order_id = p_order.id
    and item.tenant_id = p_order.tenant_id;

  v_payload := jsonb_build_object(
    'schemaVersion', 1,
    'eventType', p_message_kind,
    'store', jsonb_strip_nulls(jsonb_build_object(
      'name', v_tenant.shop_name,
      'logoUrl', case
        when v_tenant.logo_url ~* '^https://[^[:space:]]+$' then v_tenant.logo_url
        else (
          select setting.value
            from public.website_settings setting
           where setting.tenant_id = p_order.tenant_id
             and setting.key = 'company_logo_url'
             and setting.value ~* '^https://[^[:space:]]+$'
           limit 1
        )
      end,
      'storeUrl', v_store_url,
      'currency', coalesce(v_tenant.currency, 'CLP'),
      'timezone', coalesce(v_tenant.timezone, 'America/Santiago'),
      -- La marca del correo es la del tema del editor del sitio.
      'brandColor', (
        select case
          when setting.value ~ '^#[0-9A-Fa-f]{6}$' then upper(setting.value)
          when setting.value ~ '^[0-9]{1,10}$'
            then '#' || upper(lpad(to_hex(setting.value::bigint & 16777215), 6, '0'))
        end
          from public.website_settings setting
         where setting.tenant_id = p_order.tenant_id
           and setting.key = 'theme_primary_color'
         limit 1
      ),
      'headingFont', (
        select btrim(setting.value)
          from public.website_settings setting
         where setting.tenant_id = p_order.tenant_id
           and setting.key = 'theme_heading_font'
           and btrim(setting.value) ~ '^[A-Za-z0-9 ]{1,40}$'
         limit 1
      ),
      'bodyFont', (
        select btrim(setting.value)
          from public.website_settings setting
         where setting.tenant_id = p_order.tenant_id
           and setting.key = 'theme_body_font'
           and btrim(setting.value) ~ '^[A-Za-z0-9 ]{1,40}$'
         limit 1
      )
    )),
    'customer', jsonb_build_object(
      'name', p_order.customer_name,
      'greeting', public.customer_greeting_for_internal(
        p_order.tenant_id, p_order.customer_id, p_order.customer_name)),
    'order', jsonb_strip_nulls(jsonb_build_object(
      'id', p_order.id,
      'number', p_order.order_number,
      'status', p_order.status,
      'paymentStatus', p_order.payment_status,
      'createdAt', p_order.created_at,
      'deliveryType', p_order.delivery_type,
      'subtotal', p_order.subtotal,
      'shippingCost', p_order.shipping_cost,
      'discountAmount', p_order.discount_amount,
      'total', p_order.total,
      'trackingCarrier', p_order.shipping_carrier,
      'trackingNumber', p_order.tracking_number,
      'trackingUrl', case
        when p_order.tracking_url ~* '^https://[^[:space:]]+$' then p_order.tracking_url
        else null
      end,
      'refundedAmount', case
        when p_message_kind = 'refund_completed' then p_order.refund_amount
        else null
      end,
      'refundedAt', case
        when p_message_kind = 'refund_completed' then p_order.refunded_at
        else null
      end
    )),
    'items', v_items,
    'document', jsonb_build_object(
      'kind', 'order_receipt',
      'taxStatus', 'not_a_tax_document',
      'label', 'Comprobante de pedido · No constituye documento tributario'
    )
  );

  -- «Va en camino» cuenta con qué se envió y adónde (20261013210000).
  if p_message_kind = 'shipped' then
    v_payload := v_payload || jsonb_build_object(
      'shipment', case
        when p_shipment is null then null
        else jsonb_strip_nulls(jsonb_build_object(
          'carrier', p_shipment.carrier,
          'carrierCode', p_shipment.carrier_code,
          'service', p_shipment.service,
          'trackingNumber', p_shipment.tracking_number,
          'trackingUrl', p_shipment.tracking_url,
          'admittedAt', p_shipment.admitted_at
        ))
      end,
      'delivery', jsonb_strip_nulls(jsonb_build_object(
        'name', nullif(btrim(p_order.customer_name), ''),
        'addressLine1', nullif(btrim(p_order.shipping_address_line1), ''),
        'addressLine2', nullif(btrim(p_order.shipping_address_line2), ''),
        'city', nullif(btrim(p_order.shipping_city), ''),
        'state', nullif(btrim(p_order.shipping_state), '')
      ))
    );
  end if;

  return v_payload;
end;
$function$
;

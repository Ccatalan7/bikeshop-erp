-- El mismo cliente no se crea dos veces seguidas (2026-11-25).
--
-- Con la conexión cortada, el primer «Guardar» de un cliente nuevo llegaba y
-- la respuesta se perdía; cada toque siguiente mandaba otra identidad y
-- quedaba otro cliente. Karla Concha quedó seis veces en 25 segundos el
-- 2026-10-30 (el dueño la buscó en Mensajes y vio seis filas iguales), y en
-- producción había 15 fichas sobrantes en 9 grupos desde marzo: mismo nombre,
-- mismo teléfono, creadas con segundos de diferencia. La app ahora sostiene
-- la identidad de un alta entre intentos (`CustomerService.createCustomer`);
-- la regla va también en la base, para las versiones instaladas que todavía
-- no lo hacen y para cualquier otro escritor:
--
-- * Un disparador BEFORE INSERT rechaza un cliente cuyo nombre (sin
--   mayúsculas ni espacios de más) y teléfono (sus últimos nueve dígitos) son
--   los de otro cliente del mismo taller creado en los últimos 10 minutos.
-- * Sólo las altas del taller (`auth_user_id` nulo): una cuenta del portal o
--   de la tienda se crea con su propio flujo.
-- * Lo de hace más de 10 minutos pasa: una restauración reinserta filas con su
--   fecha original, y dos clientes iguales creados con días de diferencia los
--   decide una persona.
-- * El intento que trae la misma identidad que la fila ya creada no lo juzga
--   esta regla: choca con su propia llave primaria y la app lo reconoce como
--   el intento anterior que sí llegó.
-- * Dos altas iguales que se cruzan se ordenan con un candado de la
--   transacción por taller y teléfono: la segunda espera, ve la primera y se
--   rechaza.
-- * El error es SQLSTATE 23505 con `customer_recent_duplicate` en el detalle
--   y el id del cliente que ya existe en la pista: la app nueva devuelve ese
--   cliente y la vieja muestra el mensaje.

create or replace function public.guard_customer_recent_duplicate()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_digits text := regexp_replace(coalesce(new.phone, ''), '\D', '', 'g');
  v_phone text := right(v_digits, 9);
  v_name text := lower(regexp_replace(btrim(coalesce(new.name, '')), '\s+', ' ', 'g'));
  v_existing uuid;
begin
  if new.auth_user_id is not null or length(v_digits) < 8 or v_name = '' then
    return new;
  end if;

  perform pg_advisory_xact_lock(
    hashtextextended('customer_recent_duplicate|' || new.tenant_id::text || '|' || v_phone, 0)
  );

  select c.id
    into v_existing
    from public.customers c
   where c.tenant_id = new.tenant_id
     and c.id is distinct from new.id
     and c.auth_user_id is null
     and c.created_at > now() - interval '10 minutes'
     and right(regexp_replace(coalesce(c.phone, ''), '\D', '', 'g'), 9) = v_phone
     and lower(regexp_replace(btrim(coalesce(c.name, '')), '\s+', ' ', 'g')) = v_name
   order by c.created_at
   limit 1;

  if v_existing is not null then
    raise exception 'Este cliente ya se creó hace un momento: búscalo en la lista.'
      using errcode = '23505',
            detail = 'customer_recent_duplicate',
            hint = v_existing::text;
  end if;

  return new;
end;
$$;

comment on function public.guard_customer_recent_duplicate() is
  'Rechaza crear otra vez, dentro de 10 minutos, un cliente del taller con el mismo nombre y teléfono (23505, detalle customer_recent_duplicate, pista con el id del que ya existe). No juzga cuentas del portal (auth_user_id) ni el reintento con la misma identidad.';

revoke all on function public.guard_customer_recent_duplicate() from public, anon, authenticated, service_role;

drop trigger if exists trg_guard_customer_recent_duplicate on public.customers;
create trigger trg_guard_customer_recent_duplicate
  before insert on public.customers
  for each row execute function public.guard_customer_recent_duplicate();

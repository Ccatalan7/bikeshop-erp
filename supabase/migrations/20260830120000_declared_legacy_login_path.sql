-- Un portal legacy declara la ruta HTTP exacta a la que degrada. Sólo esa.
--
-- **El problema medido (2026-08-30).** `portal.rburgos.cl` publica su ingreso
-- por HTTPS y, al abrir el formulario, **degrada a `http://`** —confirmado en
-- la ventana real: la barra pasa a `http://portal.rburgos.cl/login/` con el
-- candado tachado—. Desde ese instante `normalizeSupplierBrowserOrigin`
-- devuelve `null` y el autofill retorna **antes de consultar la credencial
-- administrada**: la sesión del proveedor no puede iniciarse sola, que es como
-- está configurada.
--
-- Reescribir el `action` a HTTPS no es salida: los equivalentes HTTPS de
-- `www.rburgos.cl` para `valida_ingreso.asp` y `seleccion.asp` **resetean la
-- conexión**. El transporte legacy es real y hay que reconocerlo, no negarlo.
--
-- **La excepción, y por qué es estrecha.** No se abre un autofill HTTP
-- genérico. La autorización parte del binding canónico HTTPS que ya existe en
-- `supplier_credentials.origin_url` y sólo agrega **la ruta exacta** a la que
-- ese portal degrada. Sin declaración no hay excepción; con ella, el permiso
-- alcanza a un host, un puerto y una ruta, y a nada más. `tenant_id`,
-- `supplier_id`, `credential_kind`, `credential_key` y el secreto del vault no
-- se tocan: la credencial se sigue resolviendo contra el origen canónico.
--
-- Que el envío sea automático es el comportamiento configurado por el dueño
-- para este proveedor, no una decisión de la app.

begin;

alter table public.supplier_credentials
  add column if not exists legacy_login_path text;

alter table public.supplier_credentials
  drop constraint if exists supplier_credentials_legacy_login_path_check;

-- La forma la fija la base, no el llamador: una ruta absoluta, sin esquema, sin
-- host, sin query y sin espacios. Así una declaración no puede convertirse en
-- «otro origen» ni arrastrar parámetros.
alter table public.supplier_credentials
  add constraint supplier_credentials_legacy_login_path_check
  check (
    legacy_login_path is null
    or (
      legacy_login_path = btrim(legacy_login_path)
      and legacy_login_path ~ '^/[A-Za-z0-9._~%!$&''()*+,;=:@/-]{0,120}$'
      and legacy_login_path !~ '//'
      and position('?' in legacy_login_path) = 0
      and position('#' in legacy_login_path) = 0
    )
  );

comment on column public.supplier_credentials.legacy_login_path is
  'Ruta HTTP exacta a la que este portal degrada su formulario de ingreso. Autoriza el autofill administrado SÓLO en ese host, puerto y ruta; la credencial se sigue resolviendo contra origin_url (HTTPS). Sin declaración no hay excepción.';

-- El único portal que hoy lo necesita, y con el mismo camino que ya publica.
update public.supplier_credentials c
set legacy_login_path = '/login/',
    updated_at = now()
from public.suppliers s
where s.id = c.supplier_id
  and c.origin_url = 'https://portal.rburgos.cl'
  and c.credential_kind = 'portal_password'
  and c.legacy_login_path is distinct from '/login/';

commit;

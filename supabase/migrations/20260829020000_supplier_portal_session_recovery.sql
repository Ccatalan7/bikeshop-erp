-- Las sesiones de proveedor comparten el perfil persistente del navegador.
-- Cuando una cookie vence, el cliente necesita una ruta de login declarada
-- por proveedor para evaluar si puede recuperarla de forma segura. La ruta es
-- dato: ningún hostname ni formulario queda codificado en Dart.

begin;

alter table public.supplier_portal_probes
  add column if not exists session_login_url text;

alter table public.supplier_portal_probes
  drop constraint if exists supplier_portal_probes_session_login_url_check;
alter table public.supplier_portal_probes
  add constraint supplier_portal_probes_session_login_url_check check (
    session_login_url is null
    or (
      session_login_url = btrim(session_login_url)
      and char_length(session_login_url) between 1 and 500
      and session_login_url ~ '^https://'
      and split_part(session_login_url, '/', 3) <> ''
      and position('@' in split_part(session_login_url, '/', 3)) = 0
      and position('#' in session_login_url) = 0
      and session_login_url !~ '[[:space:][:cntrl:]]'
    )
  );

comment on column public.supplier_portal_probes.session_login_url is
  'Ruta HTTPS exacta para preflight de recuperación de sesión. El cliente sólo revela una credencial después de comprobar origen, formulario y acción HTTPS sin CAPTCHA/OTP.';

-- RBX publica el formulario bajo HTTPS, aunque su acción legacy sigue siendo
-- HTTP. El preflight del cliente detectará esa acción y no enviará el secreto;
-- mientras la sesión está activa, el keep-alive evita su expiración por ocio.
update public.supplier_portal_probes probe
set session_login_url = 'https://portal.rburgos.cl/login/',
    updated_at = now()
from public.suppliers supplier
where supplier.id = probe.supplier_id
  and supplier.tenant_id = probe.tenant_id
  and supplier.name = 'RBX';

commit;

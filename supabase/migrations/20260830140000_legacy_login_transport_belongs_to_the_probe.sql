-- El transporte legacy lo declara la sonda del portal, no la credencial.
--
-- **Corrige a `20260830140000`'s predecesora.** `20260830120000` puso
-- `legacy_login_path` en `supplier_credentials`. Es el dueño equivocado:
-- `supplier_credentials` es **identidad y secreto** —tenant, proveedor, kind,
-- key, `origin_url` HTTPS y el `vault_secret_id`— y no debe saber nada de cómo
-- se comporta el transporte de un portal. Eso pertenece a
-- `supplier_portal_probes`, que ya describe cómo se navega ese sitio.
--
-- **Y una autorización de media pieza no autoriza nada.** La declaración
-- anterior sólo fijaba la página `/login/` de `portal.rburgos.cl`, pero **el
-- secreto no viaja ahí**: el `action` real del formulario es
-- `http://www.rburgos.cl/sitio/aplicaciones/valida_ingreso.asp`, otro host. Sin
-- atar el destino, autorizar la página deja abierto a dónde se manda la
-- credencial. Ahora se declaran y se comprueban **las dos**: página de origen y
-- destino del envío. Si falta cualquiera, o si alguna no calza exacto, no hay
-- excepción — falla cerrado.
--
-- Reescribir el destino a HTTPS no es salida: los equivalentes HTTPS de
-- `www.rburgos.cl` para `valida_ingreso.asp` y `seleccion.asp` resetean la
-- conexión. El transporte legacy es real y se reconoce, no se falsifica.

begin;

-- 1. Devolver `supplier_credentials` a lo suyo.
alter table public.supplier_credentials
  drop constraint if exists supplier_credentials_legacy_login_path_check;
alter table public.supplier_credentials
  drop column if exists legacy_login_path;

-- 2. El transporte, donde vive el comportamiento del portal.
alter table public.supplier_portal_probes
  add column if not exists session_login_legacy jsonb;

alter table public.supplier_portal_probes
  drop constraint if exists supplier_portal_probes_session_login_legacy_check;

-- La base impone la forma: las dos URL, ambas `http://`, con host y ruta, sin
-- credenciales incrustadas ni fragmentos. Una declaración a medias se rechaza
-- acá y no llega nunca al cliente.
alter table public.supplier_portal_probes
  add constraint supplier_portal_probes_session_login_legacy_check
  check (
    session_login_legacy is null
    or (
      jsonb_typeof(session_login_legacy) = 'object'
      and session_login_legacy ? 'page_url'
      and session_login_legacy ? 'action_url'
      and (session_login_legacy ->> 'page_url') ~ '^http://[A-Za-z0-9.-]+/[^ #]*$'
      and (session_login_legacy ->> 'action_url') ~ '^http://[A-Za-z0-9.-]+/[^ #?]*$'
      and position('@' in split_part(session_login_legacy ->> 'page_url', '/', 3)) = 0
      and position('@' in split_part(session_login_legacy ->> 'action_url', '/', 3)) = 0
      and octet_length(session_login_legacy::text) <= 512
    )
  );

comment on column public.supplier_portal_probes.session_login_legacy is
  'Transporte legacy declarado de este portal: la página HTTP exacta donde aparece su formulario de ingreso y el action HTTP exacto al que envía. Autoriza el autofill administrado SÓLO para ese par; la credencial se sigue resolviendo contra el origen HTTPS canónico de supplier_credentials. Sin declaración, o si cualquiera de las dos no calza, no hay excepción.';

-- 3. El único portal que hoy lo necesita, con sus dos extremos reales.
update public.supplier_portal_probes p
set session_login_legacy = jsonb_build_object(
      'page_url', 'http://portal.rburgos.cl/login/',
      'action_url',
        'http://www.rburgos.cl/sitio/aplicaciones/valida_ingreso.asp'
    ),
    updated_at = now()
from public.suppliers s
where s.id = p.supplier_id
  and s.name = 'RBX'
  and p.session_login_url = 'https://portal.rburgos.cl/login/';

commit;

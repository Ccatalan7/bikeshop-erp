-- Las páginas del transporte legacy son URLs exactas, y pueden ser HTTPS.
--
-- **Lo que se midió en el portal, no lo que se supuso.** `portal.rburgos.cl`
-- publica su ingreso en las dos variantes: la home enlaza `http://portal.
-- rburgos.cl/login/` y `https://portal.rburgos.cl/login/`, las dos responden
-- 200 sin redirigirse entre sí, y **las dos sirven el mismo formulario**, cuyo
-- `action` es siempre `http://www.rburgos.cl/sitio/aplicaciones/
-- valida_ingreso.asp`. Lo legacy es el destino, no la página.
--
-- **Por qué la declaración anterior no podía dispararse.** Fijaba
-- `page_url = http://portal.rburgos.cl/login/`, así que al entrar por el enlace
-- HTTPS —el camino normal, y el que se ve en la ventana real con el candado
-- intacto— la página cargada no era la declarada y el cliente fallaba cerrado,
-- correctamente. La declaración describía mal el portal.
--
-- **Lo que cambia.** `page_url` (uno, HTTP) pasa a `page_urls` (conjunto
-- cerrado de URLs exactas, HTTP o HTTPS). El destino sigue siendo uno solo y
-- sigue siendo HTTP: un destino HTTPS no necesita excepción, así que no la
-- recibe por acá. Cada variante que de verdad se usa se declara; ninguna se
-- infiere de un host, un esquema ni un prefijo.

begin;

create or replace function public.supplier_legacy_login_declaration_ok(
  p_declaration jsonb
)
 returns boolean
 language sql
 immutable
 parallel safe
 set search_path to 'pg_catalog'
as $function$
  select p_declaration is null
    or (
      jsonb_typeof(p_declaration) = 'object'
      and p_declaration ? 'page_urls'
      and p_declaration ? 'action_url'
      and jsonb_typeof(p_declaration -> 'page_urls') = 'array'
      and jsonb_array_length(p_declaration -> 'page_urls') between 1 and 4
      and octet_length(p_declaration::text) <= 512
      -- El destino: uno, HTTP, sin query, fragmento ni credencial incrustada.
      and (p_declaration ->> 'action_url')
          ~ '^http://[A-Za-z0-9.-]+/[^ #?]*$'
      -- Cada página: exacta, HTTP o HTTPS, con las mismas exclusiones.
      and not exists (
        select 1
        from jsonb_array_elements(p_declaration -> 'page_urls') as page
        where jsonb_typeof(page.value) <> 'string'
           or (page.value #>> '{}') !~ '^https?://[A-Za-z0-9.-]+/[^ #?]*$'
      )
    );
$function$
;

comment on function public.supplier_legacy_login_declaration_ok(jsonb) is
  'Forma del transporte legacy declarado: page_urls exactas (HTTP o HTTPS, 1 a 4) y un action_url HTTP exacto, sin query, fragmento ni credencial incrustada.';

alter table public.supplier_portal_probes
  drop constraint if exists supplier_portal_probes_session_login_legacy_check;

-- La segunda variante se escribe **literal**, no se deriva de la primera:
-- declararla por inferencia —cambiarle el esquema a la que había— sería volver
-- a describir el portal de oídas. Estas dos URLs son las que la home enlaza.
update public.supplier_portal_probes
   set session_login_legacy = jsonb_build_object(
         'page_urls', jsonb_build_array(
           'https://portal.rburgos.cl/login/',
           'http://portal.rburgos.cl/login/'
         ),
         'action_url',
           'http://www.rburgos.cl/sitio/aplicaciones/valida_ingreso.asp'
       )
 where session_login_legacy ->> 'page_url' = 'http://portal.rburgos.cl/login/'
   and session_login_legacy ->> 'action_url'
       = 'http://www.rburgos.cl/sitio/aplicaciones/valida_ingreso.asp';

-- Cualquier otra declaración vieja que quedara con la forma anterior no se
-- adivina: se retira, y el portal vuelve a fallar cerrado hasta que alguien la
-- vuelva a declarar con sus URLs reales.
update public.supplier_portal_probes
   set session_login_legacy = null
 where session_login_legacy is not null
   and session_login_legacy ? 'page_url';

alter table public.supplier_portal_probes
  add constraint supplier_portal_probes_session_login_legacy_check
  check (public.supplier_legacy_login_declaration_ok(session_login_legacy));

commit;

-- La página declarada tampoco puede traer query.
--
-- **El borde que quedó abierto.** El CHECK de `20260830140000` usa para
-- `page_url` el patrón `^http://[A-Za-z0-9.-]+/[^ #]*$`, que **acepta `?`**,
-- mientras el de `action_url` sí lo excluye con `[^ #?]*`. La asimetría era
-- accidental y el read-back no la vio porque sólo probaba la query en el
-- destino. El cliente ya falla cerrado ante una página con query, pero decir
-- «la base impone los dos extremos sin query» todavía no era cierto — y una
-- garantía que sólo vive en el cliente no es una garantía de la base.
--
-- Una página con query no es el formulario declarado: es una redirección con
-- parámetros, que es justo lo que no queremos autorizar.

begin;

alter table public.supplier_portal_probes
  drop constraint if exists supplier_portal_probes_session_login_legacy_check;

alter table public.supplier_portal_probes
  add constraint supplier_portal_probes_session_login_legacy_check
  check (
    session_login_legacy is null
    or (
      jsonb_typeof(session_login_legacy) = 'object'
      and session_login_legacy ? 'page_url'
      and session_login_legacy ? 'action_url'
      and (session_login_legacy ->> 'page_url') ~ '^http://[A-Za-z0-9.-]+/[^ #?]*$'
      and (session_login_legacy ->> 'action_url') ~ '^http://[A-Za-z0-9.-]+/[^ #?]*$'
      and position('@' in split_part(session_login_legacy ->> 'page_url', '/', 3)) = 0
      and position('@' in split_part(session_login_legacy ->> 'action_url', '/', 3)) = 0
      and octet_length(session_login_legacy::text) <= 512
    )
  );

commit;

-- Read-back de `20260830200000_legacy_login_pages_are_exact`.
--
-- **Se ejecuta la regla real.** Todos los candidatos pasan por
-- `supplier_legacy_login_declaration_ok`, la misma función que impone el CHECK.
-- La asimetría anterior —`page_url` aceptaba `?` y el read-back no lo vio— se
-- coló justo porque el read-back evaluaba una copia escrita a mano.

-- 1. El CHECK vigente es esa función y ninguna otra expresión.
select 1 / (
  case when count(*) = 1 then 1 else 0 end
) as el_check_llama_a_la_regla
from pg_constraint
where conrelid = 'public.supplier_portal_probes'::regclass
  and conname = 'supplier_portal_probes_session_login_legacy_check'
  and pg_get_constraintdef(oid)
      like '%supplier_legacy_login_declaration_ok%';

-- 2. Lo que la regla rechaza. Incluye los bordes que costaron una ronda cada
--    uno: query en cualquiera de los dos extremos, credencial incrustada,
--    destino HTTPS —que no necesita excepción—, y la forma vieja de una sola
--    página, que ya no autoriza nada.
select 1 / (
  case when bool_and(not aceptada) then 1 else 0 end
) as rechaza_lo_que_no_es_el_par_declarado
from (
  select
    etiqueta,
    public.supplier_legacy_login_declaration_ok(candidato) as aceptada
  from (values
    ('la forma vieja de una sola página',
      '{"page_url":"http://portal.rburgos.cl/login/","action_url":"http://www.rburgos.cl/x.asp"}'::jsonb),
    ('sólo las páginas',
      '{"page_urls":["https://portal.rburgos.cl/login/"]}'::jsonb),
    ('sólo el destino',
      '{"action_url":"http://www.rburgos.cl/x.asp"}'::jsonb),
    ('sin ninguna página',
      '{"page_urls":[],"action_url":"http://www.rburgos.cl/x.asp"}'::jsonb),
    ('página con query',
      '{"page_urls":["https://portal.rburgos.cl/login/?next=http://evil.cl"],"action_url":"http://www.rburgos.cl/x.asp"}'::jsonb),
    ('página con fragmento',
      '{"page_urls":["https://portal.rburgos.cl/login/#x"],"action_url":"http://www.rburgos.cl/x.asp"}'::jsonb),
    ('destino con query',
      '{"page_urls":["https://portal.rburgos.cl/login/"],"action_url":"http://www.rburgos.cl/x.asp?to=evil"}'::jsonb),
    ('destino https',
      '{"page_urls":["https://portal.rburgos.cl/login/"],"action_url":"https://www.rburgos.cl/x.asp"}'::jsonb),
    ('credencial incrustada en la página',
      '{"page_urls":["https://user:pass@portal.rburgos.cl/login/"],"action_url":"http://www.rburgos.cl/x.asp"}'::jsonb),
    ('credencial incrustada en el destino',
      '{"page_urls":["https://portal.rburgos.cl/login/"],"action_url":"http://user:pass@www.rburgos.cl/x.asp"}'::jsonb),
    ('una página que no es texto',
      '{"page_urls":[{"url":"https://portal.rburgos.cl/login/"}],"action_url":"http://www.rburgos.cl/x.asp"}'::jsonb),
    ('una página buena y otra podrida',
      '{"page_urls":["https://portal.rburgos.cl/login/","javascript:alert(1)"],"action_url":"http://www.rburgos.cl/x.asp"}'::jsonb),
    ('no es un objeto', '"http://portal.rburgos.cl/login/"'::jsonb)
  ) as t(etiqueta, candidato)
) evaluadas;

-- 3. Y lo que sí acepta: el par real, con sus dos variantes exactas.
select 1 / (
  case when bool_and(aceptada) then 1 else 0 end
) as acepta_el_par_real
from (
  select public.supplier_legacy_login_declaration_ok(candidato) as aceptada
  from (values
    ('{"page_urls":["https://portal.rburgos.cl/login/","http://portal.rburgos.cl/login/"],"action_url":"http://www.rburgos.cl/sitio/aplicaciones/valida_ingreso.asp"}'::jsonb),
    (null::jsonb)
  ) as t(candidato)
) evaluadas;

-- 4. La declaración productiva quedó con las DOS páginas que la home enlaza, y
--    la que el runner abre —`session_login_url`— es una de ellas.
select 1 / (
  case when count(*) = 1 then 1 else 0 end
) as rbx_declara_las_dos_paginas_reales
from public.supplier_portal_probes p
join public.suppliers s on s.id = p.supplier_id
where s.name = 'RBX'
  and p.session_login_url = 'https://portal.rburgos.cl/login/'
  and p.session_login_legacy -> 'page_urls'
      @> '["https://portal.rburgos.cl/login/","http://portal.rburgos.cl/login/"]'::jsonb
  and jsonb_array_length(p.session_login_legacy -> 'page_urls') = 2
  and p.session_login_legacy ->> 'action_url'
      = 'http://www.rburgos.cl/sitio/aplicaciones/valida_ingreso.asp'
  and p.session_login_legacy -> 'page_urls'
      @> to_jsonb(array[p.session_login_url]);

-- 5. Nadie más quedó autorizado, y no sobrevive ninguna declaración con la
--    forma vieja.
select 1 / (
  case when count(*) = 1 then 1 else 0 end
) as solo_un_portal_declarado
from public.supplier_portal_probes
where session_login_legacy is not null;

select 1 / (
  case when count(*) = 0 then 1 else 0 end
) as no_sobrevive_la_forma_vieja
from public.supplier_portal_probes
where session_login_legacy ? 'page_url';

-- 6. La identidad de la credencial no se movió: mismo origen canónico, mismo
--    kind, misma key, mismo secreto.
select 1 / (
  case when count(*) = 1 then 1 else 0 end
) as la_credencial_sigue_igual
from public.supplier_credentials c
join public.suppliers s on s.id = c.supplier_id
where s.name = 'RBX'
  and c.origin_url = 'https://portal.rburgos.cl'
  and c.credential_kind = 'portal_password'
  and c.credential_key = 'default'
  and c.vault_secret_id is not null;

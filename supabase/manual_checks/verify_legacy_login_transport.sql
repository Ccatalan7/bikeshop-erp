-- Read-back de `20260830140000_legacy_login_transport_belongs_to_the_probe`.

-- 1. La credencial volvió a ser sólo identidad y secreto.
select 1 / (
  case when count(*) = 0 then 1 else 0 end
) as la_credencial_no_sabe_de_transporte
from information_schema.columns
where table_schema = 'public'
  and table_name = 'supplier_credentials'
  and column_name = 'legacy_login_path';

-- 2. El transporte vive en la sonda, con su forma impuesta por la base.
select 1 / (
  case when count(*) = 1 then 1 else 0 end
) as la_sonda_declara_el_transporte
from information_schema.columns
where table_schema = 'public'
  and table_name = 'supplier_portal_probes'
  and column_name = 'session_login_legacy';

select 1 / (
  case when count(*) = 1 then 1 else 0 end
) as la_base_impone_la_forma
from pg_constraint
where conrelid = 'public.supplier_portal_probes'::regclass
  and conname = 'supplier_portal_probes_session_login_legacy_check';

-- 3. La forma la impone la base, y desde `20260830200000` la regla vive en
--    `supplier_legacy_login_declaration_ok`, con `page_urls` exactas. Sus
--    candidatos y el par productivo se verifican en
--    `verify_legacy_login_pages_are_exact.sql`, que ejecuta esa función real en
--    vez de una copia escrita a mano.

-- 4. Acá sólo queda lo que este forward movió: el transporte pertenece a la
--    sonda, junto a la URL de ingreso que el runner abre.
select 1 / (
  case when count(*) = 1 then 1 else 0 end
) as la_sonda_es_la_duena_del_transporte
from public.supplier_portal_probes p
join public.suppliers s on s.id = p.supplier_id
where s.name = 'RBX'
  and p.session_login_url = 'https://portal.rburgos.cl/login/'
  and p.session_login_legacy is not null;

-- 5. La identidad de la credencial quedó intacta.
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

-- 6. Nadie más quedó autorizado.
select 1 / (
  case when count(*) = 1 then 1 else 0 end
) as solo_un_portal_declarado
from public.supplier_portal_probes
where session_login_legacy is not null;

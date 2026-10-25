-- Read-back of 20261025030000_catalog_category_counts_one_pass.sql (plain
-- SQL, no transaction control: it runs through the read-only hosted wrapper).

select
  position(
    'per_root' in pg_get_functiondef(
      'public.catalog_category_counts_v1(uuid)'::regprocedure
    )
  ) > 0 as counts_in_one_pass,
  has_function_privilege(
    'authenticated',
    'public.catalog_category_counts_v1(uuid)',
    'EXECUTE'
  ) as signed_in_can_read,
  has_function_privilege(
    'anon',
    'public.catalog_category_counts_v1(uuid)',
    'EXECUTE'
  ) as anon_can_read;

select 1 / (
  case
    when position(
      'per_root' in pg_get_functiondef(
        'public.catalog_category_counts_v1(uuid)'::regprocedure
      )
    ) > 0 then 1
    else 0
  end
) as afirma_cuenta_en_una_pasada;

select 1 / (
  case
    when has_function_privilege(
      'authenticated',
      'public.catalog_category_counts_v1(uuid)',
      'EXECUTE'
    )
    and not has_function_privilege(
      'anon',
      'public.catalog_category_counts_v1(uuid)',
      'EXECUTE'
    ) then 1
    else 0
  end
) as afirma_solo_con_sesion;

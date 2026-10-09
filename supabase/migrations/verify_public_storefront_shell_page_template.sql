-- Read-back of 20261009010000_public_storefront_shell_page_template.sql
-- (plain SQL, no transaction control: it runs through the read-only hosted
-- wrapper).

select
  position(
    'wp.template' in pg_get_functiondef(
      'public.get_public_storefront_shell_v1(uuid)'::regprocedure
    )
  ) > 0 as shell_pages_carry_template,
  has_function_privilege(
    'anon',
    'public.get_public_storefront_shell_v1(uuid)',
    'EXECUTE'
  ) as anon_can_read_shell;

select 1 / (
  case
    when position(
      'wp.template' in pg_get_functiondef(
        'public.get_public_storefront_shell_v1(uuid)'::regprocedure
      )
    ) > 0 then 1
    else 0
  end
) as afirma_plantilla_en_paginas;

select 1 / (
  case
    when has_function_privilege(
      'anon',
      'public.get_public_storefront_shell_v1(uuid)',
      'EXECUTE'
    ) then 1
    else 0
  end
) as afirma_lectura_publica;

select 1 / (
  case
    when exists (
      select 1
        from jsonb_array_elements(
          public.get_public_storefront_shell_v1(
            '5443b130-cc28-45af-a420-cd500b288890'::uuid
          ) -> 'pages'
        ) page
       where page ? 'template'
    ) then 1
    else 0
  end
) as afirma_tienda_devuelve_plantilla;

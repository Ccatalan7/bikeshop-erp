-- Read-back of 20261031010000_public_storefront_shell_if_changed.sql (plain
-- SQL, no transaction control: it runs through the read-only hosted wrapper).

select
  has_function_privilege(
    'anon',
    'public.get_public_storefront_shell_if_changed_v1(uuid, text)',
    'EXECUTE'
  ) as anon_can_ask,
  (
    select not p.prosecdef
      from pg_proc p
     where p.oid =
       'public.get_public_storefront_shell_if_changed_v1(uuid, text)'::regprocedure
  ) as security_invoker;

select 1 / (
  case
    when has_function_privilege(
      'anon',
      'public.get_public_storefront_shell_if_changed_v1(uuid, text)',
      'EXECUTE'
    ) then 1
    else 0
  end
) as afirma_lectura_publica;

-- Without a stamp the shell travels, and it is the shell.
select 1 / (
  case
    when (
      select answer -> 'shell'
        from (
          select public.get_public_storefront_shell_if_changed_v1(
            '5443b130-cc28-45af-a420-cd500b288890'
          ) as answer
        ) a
    ) = public.get_public_storefront_shell_v1(
      '5443b130-cc28-45af-a420-cd500b288890'
    ) then 1
    else 0
  end
) as afirma_trae_el_armazon;

-- With the current stamp only the stamp travels.
select 1 / (
  case
    when (
      select public.get_public_storefront_shell_if_changed_v1(
        '5443b130-cc28-45af-a420-cd500b288890',
        md5(public.get_public_storefront_shell_v1(
          '5443b130-cc28-45af-a420-cd500b288890'
        )::text)
      ) ? 'shell'
    ) then 0
    else 1
  end
) as afirma_sin_cambio_no_viaja;

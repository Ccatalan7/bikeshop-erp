-- Read-back de 20260923190000_products_authenticated_reads_own_tenant_only.
-- SQL plano: cada afirmación divide por cero si el estado esperado falta.
-- Antes de desplegar tiene que fallar contra producción (la rama «publicado»
-- sigue en la política).

select policyname,
       array_to_string(roles, ',') as roles,
       cmd,
       qual
  from pg_policies
 where schemaname = 'public'
   and tablename = 'products'
 order by policyname;

-- La política de los usuarios con sesión sólo deja ver la propia empresa.
select 1 / (case when exists (
  select 1
    from pg_policies
   where schemaname = 'public'
     and tablename = 'products'
     and policyname = 'products_select'
     and cmd = 'SELECT'
     and roles = array['authenticated']::name[]
     and lower(qual) like '%tenant_id = ( select user_tenant_id() as user_tenant_id)%'
     and lower(qual) not like '%is_published%'
     and lower(qual) not like '%show_on_website%'
) then 1 else 0 end) as con_sesion_solo_su_empresa;

-- Ninguna otra política de SELECT abre products a los usuarios con sesión.
select 1 / (case when not exists (
  select 1
    from pg_policies
   where schemaname = 'public'
     and tablename = 'products'
     and cmd in ('SELECT', 'ALL')
     and policyname <> 'products_select'
     and (roles && array['authenticated', 'public']::name[])
) then 1 else 0 end) as sin_otra_puerta_con_sesion;

-- Anónimo conserva su política pública (la tienda lee el catálogo así).
select 1 / (case when exists (
  select 1
    from pg_policies
   where schemaname = 'public'
     and tablename = 'products'
     and policyname = 'public_products_select'
     and roles = array['anon']::name[]
     and lower(qual) like '%is_published%'
) then 1 else 0 end) as anonimo_conserva_catalogo;

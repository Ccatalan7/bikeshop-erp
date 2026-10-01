-- Una línea de General no es de ninguna bici (dueño, 2026-10-01).
--
-- General es lo que el cliente compra aparte en el mismo trabajo (un casco,
-- un bombín, luces), también cuando el trabajo tiene una sola bici. Hasta hoy
-- `job_line_bike_internal` le daba a una línea de General la única bici del
-- trabajo (y, sin filas de bicis, la de la cabecera), así que al terminar el
-- trabajo esa línea podía cambiar la ficha de la bici y entrar en su memoria
-- («General también instala», 20260928020000). El Master dice que la memoria
-- de la bici son las acciones que cambiaron su estado; una compra aparte no lo
-- cambia. Ahora la bici de una línea es la de su fila, y nada más: lo que
-- pasa por este lector —el aplicador de lo instalado, la puerta de cambio de
-- partes, la rueda que arma el trabajo, el parche de la ficha— deja de contar
-- General como de la bici. Una línea de General que dijera un cambio de ficha
-- se informa `line_without_bike` y se asigna con «Asignar a…». En producción,
-- ninguna línea de General tiene marca de ficha (`part_change`/`hole_count`)
-- al 2026-10-01, y `20261001200000` pasa a su bici el trabajo de la bici que
-- había quedado en General.
begin;
set local lock_timeout = '5s';
set local statement_timeout = '30s';

create or replace function public.job_line_bike_internal(
  p_tenant_id uuid,
  p_item_id uuid
)
returns uuid
language plpgsql
stable
security definer
set search_path to 'public'
as $function$
begin
  return (
    select jb.bike_id
      from public.mechanic_job_items i
      join public.mechanic_job_bikes jb
        on jb.id = i.job_bike_id
       and jb.job_id = i.job_id
       and jb.tenant_id = i.tenant_id
     where i.id = p_item_id
       and i.tenant_id = p_tenant_id
  );
end;
$function$;

revoke all on function public.job_line_bike_internal(uuid, uuid)
  from public, anon, authenticated, service_role;

commit;

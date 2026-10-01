-- Un adjunto nuevo de un trabajo, o una foto nueva de una bici, en los
-- buckets que la app administra (`job-images`, `bike-images`), tiene que
-- existir en Storage y estar en la carpeta de ese trabajo o esa bici
-- (carrera del barrido de adjuntos, 2026-09-29).
--
-- La bandeja del equipo borra los adjuntos que nadie se llevó. Desde este
-- bloque los marca antes de borrarlos, bajo su candado, y no respalda un
-- comando que lleve uno marcado o ya borrado. Eso protege este equipo
-- mientras su bandeja se acuerda; no protege una escritura desde otro
-- equipo, una pestaña sin Web Locks ni un formulario que vuelve después de
-- que la lápida venció. Esta regla es la garantía de la base: el trabajo o la
-- bici nunca guarda una URL nueva de esos buckets cuyo archivo no está, ni
-- una de la carpeta de otro trabajo u otra bici. Vale para todo escritor
-- (el alta, el guardado de líneas, la tabla, el guardado de la bici o una
-- escritura directa), porque va en la tabla y no en cada comando.
--
-- Sólo mira lo nuevo (lo que la fila no tenía): una URL que ya estaba se
-- queda aunque su archivo falte, y quitar URLs siempre se puede. Las URL de
-- otros buckets (`vinabike-assets`, lo anterior) o de otros sitios no se
-- juzgan.
begin;

-- null si [p_url] puede entrar en la fila de [p_owner_prefix]; si no, por qué.
create or replace function public.managed_image_url_problem(
  p_url text,
  p_bucket text,
  p_owner_prefix text
)
returns text
language plpgsql
stable
security definer
set search_path to 'public'
as $function$
declare
  -- Sin consulta ni fragmento: no son parte del nombre del archivo (segunda
  -- revisión de Codex).
  v_rest text := split_part(split_part(split_part(coalesce(p_url, ''),
    '/storage/v1/object/public/', 2), '?', 1), '#', 1);
  v_path text;
begin
  if v_rest = '' or split_part(v_rest, '/', 1) <> p_bucket then
    return null;
  end if;
  v_path := substr(v_rest, length(p_bucket) + 2);
  if left(v_path, length(p_owner_prefix)) <> p_owner_prefix then
    return 'es de la carpeta de otro trabajo o bici';
  end if;
  if not exists (
    select 1
      from storage.objects object
     where object.bucket_id = p_bucket
       and object.name = v_path
  ) then
    return 'ya no está en Storage (se borró o no terminó de subir)';
  end if;
  return null;
end;
$function$;

comment on function public.managed_image_url_problem(text, text, text) is
  'Por qué una URL nueva de un bucket administrado no puede entrar en su fila (otra carpeta, o sin archivo); null si puede. Sólo para los disparadores de adjuntos.';

create or replace function public.mechanic_job_image_urls_exist()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_url text;
  v_problem text;
  v_old text[] := case when tg_op = 'UPDATE'
                       then coalesce(old.image_urls, '{}'::text[])
                       else '{}'::text[] end;
begin
  foreach v_url in array coalesce(new.image_urls, '{}'::text[])
  loop
    continue when v_url = any (v_old);
    v_problem := public.managed_image_url_problem(
      v_url, 'job-images', new.tenant_id::text || '/' || new.id::text || '/');
    if v_problem is not null then
      raise exception 'Un adjunto nuevo del trabajo %: %', v_problem, v_url
        using errcode = '22023';
    end if;
  end loop;
  return new;
end;
$function$;

create or replace function public.bike_image_urls_exist()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_url text;
  v_problem text;
  v_new text[] := coalesce(new.image_urls, '{}'::text[])
    || case when new.image_url is null then '{}'::text[]
            else array[new.image_url] end;
  v_old text[] := case when tg_op = 'UPDATE'
                       then coalesce(old.image_urls, '{}'::text[])
                         || case when old.image_url is null then '{}'::text[]
                                 else array[old.image_url] end
                       else '{}'::text[] end;
begin
  foreach v_url in array v_new
  loop
    continue when v_url = any (v_old);
    v_problem := public.managed_image_url_problem(
      v_url, 'bike-images', new.tenant_id::text || '/' || new.id::text || '/');
    if v_problem is not null then
      raise exception 'Una foto nueva de la bici %: %', v_problem, v_url
        using errcode = '22023';
    end if;
  end loop;
  return new;
end;
$function$;

drop trigger if exists trg_mechanic_job_image_urls_exist on public.mechanic_jobs;
create trigger trg_mechanic_job_image_urls_exist
  before insert or update of image_urls on public.mechanic_jobs
  for each row execute function public.mechanic_job_image_urls_exist();

drop trigger if exists trg_bike_image_urls_exist on public.bikes;
create trigger trg_bike_image_urls_exist
  before insert or update of image_urls, image_url on public.bikes
  for each row execute function public.bike_image_urls_exist();

revoke all on function public.managed_image_url_problem(text, text, text)
  from public, anon, authenticated, service_role;
revoke all on function public.mechanic_job_image_urls_exist()
  from public, anon, authenticated, service_role;
revoke all on function public.bike_image_urls_exist()
  from public, anon, authenticated, service_role;

commit;

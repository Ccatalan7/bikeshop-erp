-- Deployment status: NOT DEPLOYED
-- Fotos y adjuntos del trabajo (BIKE_WORKSHOP_MASTER_SCHEMA.md, «Checkpoint:
-- fotos, cierre con ficha pendiente y partes»).
--
-- Hasta aquí el formulario del trabajo y la tabla subían los adjuntos a
-- `vinabike-assets/mechanic_jobs/<cliente>/`, sin taller en la ruta y con
-- reglas que sólo piden una sesión: cualquier cuenta de cualquier taller
-- podía subir, reemplazar o borrar ahí. El formulario tragaba el error de
-- subida (el trabajo se guardaba sin la foto y nadie lo sabía), ninguna foto
-- se anotaba en la bandeja del equipo (un cierre a mitad dejaba archivos que
-- nadie borra: 2 de 8 en producción el 2026-09-28) y cada adjunto se nombraba
-- `.jpg`, también un PDF.
--
-- Cada adjunto nuevo vive en `<taller>/<trabajo>/<archivo al azar>`, como las
-- fotos de la bici (`20260928050000`): el primer segmento es el taller, para
-- que sólo su personal pueda subirlo, listarlo o borrarlo; el segundo es el
-- trabajo, para que el barrido de huérfanas sepa de quién es. La lectura es
-- pública por URL, como hasta ahora: el PDF del trabajo y el portal del
-- cliente los muestran, y la ruta lleva dos uuid y un nombre al azar. Acepta
-- fotos y PDF (lo que se adjunta en el taller). No hay política de update: un
-- adjunto no se reemplaza, se sube otro. Los adjuntos que ya existen se quedan
-- donde están, con su URL.
begin;

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'job-images',
  'job-images',
  true,
  20971520,
  array[
    'image/jpeg', 'image/png', 'image/webp', 'image/heic', 'image/heif',
    'image/gif', 'application/pdf'
  ]
)
on conflict (id) do update
set public = excluded.public,
    file_size_limit = excluded.file_size_limit,
    allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists job_images_select on storage.objects;
drop policy if exists job_images_insert on storage.objects;
drop policy if exists job_images_delete on storage.objects;

create policy job_images_select on storage.objects
  for select
  to authenticated
  using (
    bucket_id = 'job-images'
    and split_part(name, '/', 1) = public.user_tenant_id()::text
  );

create policy job_images_insert on storage.objects
  for insert
  to authenticated
  with check (
    bucket_id = 'job-images'
    and split_part(name, '/', 1) = public.user_tenant_id()::text
    and split_part(name, '/', 2) <> ''
    and split_part(name, '/', 3) <> ''
  );

create policy job_images_delete on storage.objects
  for delete
  to authenticated
  using (
    bucket_id = 'job-images'
    and split_part(name, '/', 1) = public.user_tenant_id()::text
  );

commit;

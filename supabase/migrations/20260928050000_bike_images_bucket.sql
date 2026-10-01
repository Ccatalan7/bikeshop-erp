-- Deployment status: NOT DEPLOYED
-- Fotos de la bici (BIKE_WORKSHOP_MASTER_SCHEMA.md, ítem 3 de la cola:
-- limpieza de fotos huérfanas).
--
-- El formulario de la bici sube sus fotos al bucket `bike-images` desde
-- octubre de 2025, pero el bucket nunca se creó: en producción hay seis
-- buckets y ninguno se llama así, y ninguna bici tiene foto (2026-09-27). Al
-- principio el error se tragaba y la bici se guardaba sin la foto; hoy el
-- formulario dice «No se pudo guardar la foto» y no envía la bici.
--
-- Cada foto vive en `<taller>/<bici>/<archivo>`: el primer segmento es el
-- taller, igual que en `vinabike-files`, para que sólo su personal pueda
-- subirla, listarla o borrarla; el segundo es la bici, para que un barrido de
-- huérfanas no tenga que adivinar de quién es. La lectura es pública, como las
-- fotos del trabajo en `vinabike-assets`: la ficha, el PDF y el portal del
-- cliente las muestran por URL, y la ruta lleva dos uuid y un nombre al azar.
-- No hay política de update: una foto no se reemplaza, se sube otra.
begin;

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'bike-images',
  'bike-images',
  true,
  10485760,
  array['image/jpeg', 'image/png', 'image/webp', 'image/heic', 'image/heif']
)
on conflict (id) do update
set public = excluded.public,
    file_size_limit = excluded.file_size_limit,
    allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists bike_images_select on storage.objects;
drop policy if exists bike_images_insert on storage.objects;
drop policy if exists bike_images_delete on storage.objects;

create policy bike_images_select on storage.objects
  for select
  to authenticated
  using (
    bucket_id = 'bike-images'
    and split_part(name, '/', 1) = public.user_tenant_id()::text
  );

create policy bike_images_insert on storage.objects
  for insert
  to authenticated
  with check (
    bucket_id = 'bike-images'
    and split_part(name, '/', 1) = public.user_tenant_id()::text
    and split_part(name, '/', 2) <> ''
    and split_part(name, '/', 3) <> ''
  );

create policy bike_images_delete on storage.objects
  for delete
  to authenticated
  using (
    bucket_id = 'bike-images'
    and split_part(name, '/', 1) = public.user_tenant_id()::text
  );

commit;

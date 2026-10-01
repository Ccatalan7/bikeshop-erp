-- Read-back de 20260928050000_bike_images_bucket. Antes de desplegar tiene
-- que fallar contra producción (el bucket no existe).

-- El bucket existe, se lee por URL y sólo acepta imágenes de hasta 10 MB.
select 1 / (case when exists (
  select 1 from storage.buckets
   where id = 'bike-images'
     and public is true
     and file_size_limit = 10485760
     and allowed_mime_types @> array['image/jpeg', 'image/png', 'image/webp']
) then 1 else 0 end) as bucket_de_fotos_de_bici;

-- Subir, listar y borrar: sólo el personal del taller, en su carpeta; subir
-- exige la bici en la ruta. No hay política de update.
select 1 / (case when
  (select count(*) from pg_policies
    where schemaname = 'storage' and tablename = 'objects'
      and policyname in ('bike_images_select', 'bike_images_insert', 'bike_images_delete')
      and roles = '{authenticated}'
      and coalesce(qual, with_check) like '%bike-images%'
      and coalesce(qual, with_check) like '%user_tenant_id()%') = 3
  and exists (select 1 from pg_policies
    where schemaname = 'storage' and tablename = 'objects'
      and policyname = 'bike_images_insert'
      and with_check like '%split_part(name, ''/''::text, 3)%')
  and not exists (select 1 from pg_policies
    where schemaname = 'storage' and tablename = 'objects'
      and policyname like 'bike_images%' and cmd = 'UPDATE')
then 1 else 0 end) as fotos_por_taller;

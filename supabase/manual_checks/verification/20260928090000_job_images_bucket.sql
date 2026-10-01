-- Read-back de 20260928090000_job_images_bucket. Antes de desplegar tiene que
-- fallar contra producción (el bucket no existe).

-- El bucket: lectura por URL, fotos y PDF, hasta 20 MB.
select 1 / (case when
  (select public from storage.buckets where id = 'job-images')
  and (select file_size_limit from storage.buckets where id = 'job-images') = 20971520
  and (select allowed_mime_types from storage.buckets where id = 'job-images')
      @> array['image/jpeg', 'application/pdf']
then 1 else 0 end) as bucket_de_adjuntos;

-- Sólo el personal del taller, en su carpeta, con el trabajo en la ruta; sin
-- reemplazo.
select 1 / (case when
  (select count(*) from pg_policies
    where schemaname = 'storage' and tablename = 'objects'
      and policyname in ('job_images_select', 'job_images_insert', 'job_images_delete')) = 3
  and not exists (
    select 1 from pg_policies
     where schemaname = 'storage' and tablename = 'objects'
       and cmd = 'UPDATE'
       and coalesce(qual, with_check) like '%job-images%')
  and (select with_check from pg_policies
        where schemaname = 'storage' and tablename = 'objects'
          and policyname = 'job_images_insert')
      like '%user_tenant_id()%'
then 1 else 0 end) as reglas_por_taller;

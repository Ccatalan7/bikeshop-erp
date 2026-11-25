-- 20261125191800: las 15 fichas sobrantes ya no están, las 9 que se quedan
-- sí, la segunda bici de Karla está en su ficha y no queda ningún grupo de
-- clientes iguales (nombre y teléfono) creados con menos de 5 minutos.
-- SQL plano, sin control de transacción: corre por el envoltorio de lectura.
select 1 / case
  when not exists (
         select 1 from public.customers
          where id in (
            'cfaa8ce7-8d6f-4bf2-ab6b-19cf35f32c6e', '233c807c-a014-4246-b6ba-a1a0dec7f86c',
            'a779cd16-d3fb-4314-969e-ef8012689567', '582d7aba-bb65-4dc9-83ab-6a1409e961ec',
            'd5bb1e44-699c-422f-bc13-57c531fe0b41', 'fcccac1c-20e2-4c48-b951-57d29f600691',
            '453b8ed9-be03-4271-a983-b47e5bcaae54', '2c5ee744-f382-48af-907c-3bf8a200ff56',
            '750ad256-1247-4ddc-9e2b-d26fe598f6ef', '88b94895-0392-4d5e-9f27-011a3697dcaf',
            '85428426-9d86-44f2-9697-f46f66388fcd', 'c38007e0-48f1-4d90-a91e-d82b5533dafe',
            'fb4a2029-3632-494f-a333-b3c7e48e69ca', '00449203-c245-46e2-a742-48be880b0324',
            'f051ab01-43ee-4ad0-bdc0-1e2954430326'))
   and (select count(*) from public.customers
         where tenant_id = '5443b130-cc28-45af-a420-cd500b288890'
           and id in (
             '5aa44433-53ce-419a-b66d-e4b9317ccdcd', 'f6c01b08-772f-46e1-a76e-519d790533a9',
             '15d65a81-36f1-4371-b973-1845c001f264', 'c118d8cd-b3d0-4b4b-a8e0-2784b35d4ce6',
             '4d9a17bb-cbe6-4461-a125-8a839e9753b2', '4feb7c70-78ae-46c6-8430-6a983879fa09',
             '2e7fd018-3044-4939-aac6-8c2bd828bd0a', '219ea42a-dfc8-439f-99fc-60ef4ffa4f05',
             'e960333d-cd22-46b4-97dd-411d0f238bd9')) = 9
   and (select count(*) from public.bikes
         where tenant_id = '5443b130-cc28-45af-a420-cd500b288890'
           and customer_id = '4feb7c70-78ae-46c6-8430-6a983879fa09') = 2
  then 1 else 0 end as burst_duplicates_merged;

with n as (
  select right(regexp_replace(coalesce(phone, ''), '\D', '', 'g'), 9) as tel,
         lower(regexp_replace(btrim(name), '\s+', ' ', 'g')) as nm,
         created_at
    from public.customers
   where tenant_id = '5443b130-cc28-45af-a420-cd500b288890'
     and length(regexp_replace(coalesce(phone, ''), '\D', '', 'g')) >= 8
)
select 1 / case
  when not exists (
         select 1 from n
          group by tel, nm
         having count(*) > 1 and max(created_at) - min(created_at) < interval '5 minutes')
  then 1 else 0 end as no_burst_duplicates_left;

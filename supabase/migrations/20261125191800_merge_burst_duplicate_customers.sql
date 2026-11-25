-- Los clientes que quedaron repetidos por guardados repetidos (2026-11-25).
--
-- 15 fichas sobrantes en 9 grupos, del 2026-03-09 al 2026-11-16: mismo
-- nombre, mismo teléfono, creadas con segundos de diferencia y sin ningún
-- otro dato (correo, RUT, dirección, notas y foto vacíos en todas). Es el
-- defecto que cierra 20261125191700: el primer «Guardar» llegaba, la
-- respuesta se perdía y cada toque siguiente creaba otra ficha. El dueño vio
-- a Karla Concha seis veces al buscarla en Mensajes.
--
-- Cada grupo queda en una ficha: la que tiene bicis, trabajos o ventas, o la
-- más antigua si ninguna tiene. Una sola sobrante tenía algo: la segunda bici
-- de Karla («MTB doble suspensión», 2026-10-30), que pasa a la ficha que
-- tiene su trabajo del 2026-11-03. Las demás sólo tenían su fila de
-- fidelización vacía, que se va con ellas en cascada.
--
-- Antes de tocar nada se comprueba que cada sobrante sigue igual a la ficha
-- que se queda y que nada más la apunta; si no, la migración se detiene sin
-- cambios. Se borra con `guard_customer_delete_activity` encendido. Correrla
-- otra vez no hace nada: las sobrantes ya no están.

do $$
declare
  v_tenant constant uuid := '5443b130-cc28-45af-a420-cd500b288890';
  v_keep constant uuid[] := array[
    '5aa44433-53ce-419a-b66d-e4b9317ccdcd',
    'f6c01b08-772f-46e1-a76e-519d790533a9',
    '15d65a81-36f1-4371-b973-1845c001f264',
    'c118d8cd-b3d0-4b4b-a8e0-2784b35d4ce6',
    '4d9a17bb-cbe6-4461-a125-8a839e9753b2',
    '4d9a17bb-cbe6-4461-a125-8a839e9753b2',
    '4feb7c70-78ae-46c6-8430-6a983879fa09',
    '4feb7c70-78ae-46c6-8430-6a983879fa09',
    '4feb7c70-78ae-46c6-8430-6a983879fa09',
    '4feb7c70-78ae-46c6-8430-6a983879fa09',
    '4feb7c70-78ae-46c6-8430-6a983879fa09',
    '2e7fd018-3044-4939-aac6-8c2bd828bd0a',
    '219ea42a-dfc8-439f-99fc-60ef4ffa4f05',
    '219ea42a-dfc8-439f-99fc-60ef4ffa4f05',
    'e960333d-cd22-46b4-97dd-411d0f238bd9'
  ]::uuid[];
  v_drop constant uuid[] := array[
    'cfaa8ce7-8d6f-4bf2-ab6b-19cf35f32c6e',
    '233c807c-a014-4246-b6ba-a1a0dec7f86c',
    'a779cd16-d3fb-4314-969e-ef8012689567',
    '582d7aba-bb65-4dc9-83ab-6a1409e961ec',
    'd5bb1e44-699c-422f-bc13-57c531fe0b41',
    'fcccac1c-20e2-4c48-b951-57d29f600691',
    '453b8ed9-be03-4271-a983-b47e5bcaae54',
    '2c5ee744-f382-48af-907c-3bf8a200ff56',
    '750ad256-1247-4ddc-9e2b-d26fe598f6ef',
    '88b94895-0392-4d5e-9f27-011a3697dcaf',
    '85428426-9d86-44f2-9697-f46f66388fcd',
    'c38007e0-48f1-4d90-a91e-d82b5533dafe',
    'fb4a2029-3632-494f-a333-b3c7e48e69ca',
    '00449203-c245-46e2-a742-48be880b0324',
    'f051ab01-43ee-4ad0-bdc0-1e2954430326'
  ]::uuid[];
  v_karla_keep constant uuid := '4feb7c70-78ae-46c6-8430-6a983879fa09';
  v_karla_drop constant uuid := '85428426-9d86-44f2-9697-f46f66388fcd';
  v_karla_bike constant uuid := 'cc606c54-9c64-41f3-a580-2007050c3470';
  v_problems text;
  v_moved integer;
  v_deleted integer;
begin
  select string_agg(format('%s: %s', p.drop_id, w.why), '; ')
    into v_problems
    from unnest(v_keep, v_drop) as p(keep_id, drop_id)
    join public.customers d on d.id = p.drop_id
    left join public.customers k on k.id = p.keep_id
   cross join lateral (
     select case
       when d.tenant_id <> v_tenant then 'otro taller'
       when k.id is null or k.tenant_id <> v_tenant then 'la ficha que se queda no está'
       when lower(btrim(d.name)) <> lower(btrim(k.name))
         or coalesce(d.phone, '') <> coalesce(k.phone, '') then 'nombre o teléfono distinto'
       when coalesce(nullif(btrim(d.email), ''), nullif(btrim(d.rut), ''),
                     nullif(btrim(d.address), ''), nullif(btrim(d.notes), ''),
                     nullif(btrim(d.image_url), ''), d.auth_user_id::text) is not null
         then 'tiene datos propios'
       when exists (select 1 from public.bikes b
                     where b.customer_id = d.id
                       and not (d.id = v_karla_drop and b.id = v_karla_bike))
         or exists (select 1 from public.mechanic_jobs x where x.customer_id = d.id or x.assigned_to = d.id)
         or exists (select 1 from public.mechanic_job_timeline x where x.created_by = d.id)
         or exists (select 1 from public.sales_invoices x where x.customer_id = d.id)
         or exists (select 1 from public.sales_orders x where x.customer_id = d.id)
         or exists (select 1 from public.online_orders x where x.customer_id = d.id)
         or exists (select 1 from public.orders x where x.customer_id = d.id)
         or exists (select 1 from public.work_orders x where x.customer_id = d.id)
         or exists (select 1 from public.vehicles x where x.customer_id = d.id)
         or exists (select 1 from public.customer_quotes x where x.customer_id = d.id)
         or exists (select 1 from public.customer_addresses x where x.customer_id = d.id)
         or exists (select 1 from public.customer_portal_claim_codes x where x.customer_id = d.id)
         or exists (select 1 from public.customer_workshop_notice_preferences x where x.customer_id = d.id)
         or exists (select 1 from public.smart_tasks x where x.linked_customer_id = d.id)
         or exists (select 1 from public.whatsapp_conversation_bindings x where x.customer_id = d.id)
         or exists (select 1 from public.whatsapp_review_requests x where x.customer_id = d.id)
         or exists (select 1 from public.workshop_customer_notices x where x.customer_id = d.id)
         or exists (select 1 from public.workshop_legacy_asset_copies x where x.customer_id = d.id)
         or exists (select 1 from public.mail_messages x where x.sender_party_id = d.id)
         or exists (select 1 from public.mail_senders x where x.party_id = d.id)
         or exists (select 1 from public.mail_message_links x where x.record_id::text = d.id::text)
         or exists (select 1 from public.erp_notifications x where x.entity_id::text = d.id::text)
         or exists (select 1 from public.external_party_identifiers x where x.party_id = d.id)
         or exists (select 1 from public.legacy_auth_identity_repair_receipts x where x.target_customer_id = d.id)
         then 'algo más la apunta'
     end as why
   ) w
   where w.why is not null;

  if v_problems is not null then
    raise exception 'customer_burst_merge_precheck: %', v_problems;
  end if;

  update public.bikes
     set customer_id = v_karla_keep
   where id = v_karla_bike
     and tenant_id = v_tenant
     and customer_id = v_karla_drop;
  get diagnostics v_moved = row_count;

  delete from public.customers c
   using unnest(v_drop) as p(drop_id)
   where c.id = p.drop_id
     and c.tenant_id = v_tenant;
  get diagnostics v_deleted = row_count;

  if exists (select 1 from public.customers where id = any (v_drop)) then
    raise exception 'customer_burst_merge: quedaron sobrantes';
  end if;
  if (select count(*) from public.customers where id = any (v_keep) and tenant_id = v_tenant) <> 9 then
    raise exception 'customer_burst_merge: falta una ficha que se queda';
  end if;
  if not exists (select 1 from public.bikes
                  where id = v_karla_bike and customer_id = v_karla_keep) then
    raise exception 'customer_burst_merge: la segunda bici de Karla no quedó en su ficha';
  end if;

  raise notice 'customer_burst_merge: % bici movida, % fichas sobrantes borradas', v_moved, v_deleted;
end;
$$;

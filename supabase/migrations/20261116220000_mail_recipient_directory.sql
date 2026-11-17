-- Correo: a quién se le puede escribir (dueño, 2026-11-16).
--
-- «la lista de correos como de destinatarios posibles que aparezcan ahí en
-- nuestro correo que está integrado, aparezcan todos los correos que tú
-- agregaste a los proveedores formales… aparte de los que vayamos usando y
-- vayamos agregando como contacto y como en cualquier otra aplicación de
-- email». El campo «Para» de Redactar no sugería nada: había que tipear la
-- dirección completa aunque el proveedor la tuviera en su ficha.
--
-- mail_recipient_directory_v1 entrega en una sola lectura la libreta del
-- taller, una fila por dirección:
--   * los proveedores activos: su correo, el de su vendedor y el de cada
--     contacto activo (con el nombre de la persona y el del proveedor);
--   * los clientes activos con correo;
--   * las direcciones a las que el taller ya escribió desde una casilla
--     encendida (Para y CC de lo enviado), con cuántas veces y la última
--     fecha. Si esa persona nos escribió, su nombre sale de su último correo,
--     y lo que el correo ya sabe de su dirección o su dominio (proveedor,
--     banco, courier) va como organización.
-- Lo más usado va primero; después los contactos con nombre, los proveedores
-- y los clientes. Sólo lo lee el personal del taller y sólo de su taller
-- (mail_require_staff_internal). No escribe nada.

create or replace function public.mail_recipient_directory_v1()
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public
as $$
declare
  v_tenant uuid := public.mail_require_staff_internal();
  v_valid constant text := '^[^[:space:]@,;<>"]+@[^[:space:]@,;<>"]+\.[^[:space:]@,;<>"]+$';
begin
  return coalesce((
    with known as (
      select lower(btrim(supplier.email)) as address,
             btrim(supplier.name) as name,
             null::text as org,
             'supplier'::text as kind,
             2 as rank
        from public.suppliers supplier
       where supplier.tenant_id = v_tenant
         and coalesce(supplier.is_active, true)
         and nullif(btrim(supplier.email), '') is not null
      union all
      select lower(btrim(supplier.sales_rep_email)),
             coalesce(nullif(btrim(supplier.sales_rep_name), ''), btrim(supplier.name)),
             case when nullif(btrim(supplier.sales_rep_name), '') is not null then btrim(supplier.name) end,
             'supplier',
             1
        from public.suppliers supplier
       where supplier.tenant_id = v_tenant
         and coalesce(supplier.is_active, true)
         and nullif(btrim(supplier.sales_rep_email), '') is not null
      union all
      select lower(btrim(contact.email)),
             btrim(contact.name),
             btrim(supplier.name),
             'supplier',
             1
        from public.supplier_contacts contact
        join public.suppliers supplier
          on supplier.id = contact.supplier_id and supplier.tenant_id = contact.tenant_id
       where contact.tenant_id = v_tenant
         and contact.is_active
         and coalesce(supplier.is_active, true)
         and nullif(btrim(contact.email), '') is not null
      union all
      select lower(btrim(customer.email)),
             nullif(btrim(customer.name), ''),
             null,
             'customer',
             3
        from public.customers customer
       where customer.tenant_id = v_tenant
         and coalesce(customer.is_active, true)
         and nullif(btrim(customer.email), '') is not null
    ),
    best as (
      select distinct on (k.address) k.address, k.name, k.org, k.kind, k.rank
        from known k
       where k.address ~ v_valid
       order by k.address, k.rank, k.name nulls last
    ),
    sent as (
      select lower(btrim(recipient.address)) as address,
             count(*)::integer as uses,
             max(message.received_at) as last_used
        from public.mail_messages message
        join public.mail_mailboxes mailbox
          on mailbox.id = message.mailbox_id
         and mailbox.tenant_id = message.tenant_id
         and mailbox.is_active
       cross join lateral unnest(message.to_addresses || message.cc_addresses) as recipient(address)
       where message.tenant_id = v_tenant
         and message.direction = 'out'
       group by 1
    ),
    heard as (
      select distinct on (message.from_address)
             message.from_address as address,
             btrim(message.from_name) as name
        from public.mail_messages message
        join public.mail_mailboxes mailbox
          on mailbox.id = message.mailbox_id
         and mailbox.tenant_id = message.tenant_id
         and mailbox.is_active
       where message.tenant_id = v_tenant
         and message.direction = 'in'
         and nullif(btrim(message.from_name), '') is not null
         and message.from_address in (select s.address from sent s)
       order by message.from_address, message.received_at desc
    ),
    merged as (
      select coalesce(b.address, s.address) as address,
             coalesce(b.name, h.name) as name,
             coalesce(b.org, sender.label) as org,
             coalesce(b.kind, 'sent') as kind,
             coalesce(b.rank, 4) as rank,
             coalesce(s.uses, 0) as uses,
             s.last_used
        from best b
        full join sent s on s.address = b.address
        left join heard h on b.address is null and h.address = s.address
        left join lateral (
          select nullif(btrim(rule.label), '') as label
            from public.mail_senders rule
           where b.address is null
             and rule.tenant_id = v_tenant
             and nullif(btrim(rule.label), '') is not null
             and ((rule.match_type = 'address' and rule.match_value = s.address)
               or (rule.match_type = 'domain' and rule.match_value = split_part(s.address, '@', 2)))
           order by (rule.match_type = 'address') desc, rule.updated_at desc
           limit 1
        ) sender on true
       where coalesce(b.address, s.address) ~ v_valid
    )
    select jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
             'address', m.address,
             'name', m.name,
             'org', case when m.org is distinct from m.name then m.org end,
             'kind', m.kind,
             'uses', m.uses,
             'last_used', m.last_used
           )) order by m.uses desc, m.last_used desc nulls last, m.rank, lower(m.name) nulls last, m.address)
      from merged m
  ), '[]'::jsonb);
end;
$$;

comment on function public.mail_recipient_directory_v1() is
  'Libreta de destinatarios del correo integrado: proveedores activos (correo, vendedor y contactos), clientes activos con correo y direcciones a las que el taller ya escribió desde una casilla encendida. Una fila por dirección; sólo personal del taller y sólo su taller (20261116220000).';

revoke all on function public.mail_recipient_directory_v1() from public, anon, authenticated, service_role;
grant execute on function public.mail_recipient_directory_v1() to authenticated, service_role;

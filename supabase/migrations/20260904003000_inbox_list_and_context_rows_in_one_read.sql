-- Opening the inbox paid row-level security per embedded row on the base
-- list (735-900 ms) and then ran about fifteen dependent reads to build the
-- context chips (~4 s, one round trip each). Both become one read that decides
-- access once: the list as the same JSON shape the client already parses, and
-- a bundle of every row the chip logic may need (a superset; the app keeps
-- choosing among them with its own rules).
begin;

create or replace function public.inbox_conversations_v1(p_type text default null)
returns setof jsonb
language sql stable security definer
set search_path = pg_catalog, public
as $$
  with me as (
    select auth.uid() as user_id
  ),
  -- Same predicate as messaging_is_staff_in_tenant, evaluated once.
  staff_tenants as (
    select profile.tenant_id
    from public.user_profiles profile
    join public.tenants tenant on tenant.id = profile.tenant_id and tenant.is_active is true
    join me on me.user_id = profile.user_id
    where profile.is_active is true
  ),
  scoped as (
    select c.*
    from public.conversations c
    cross join me
    where me.user_id is not null
      and (p_type is null or c.type = p_type)
      and (
        (c.type = 'support'
          and (exists (select 1 from staff_tenants st where st.tenant_id = c.tenant_id)
               or public.messaging_can_access_conversation(c.id)))
        or (c.type = 'internal'
          and exists (select 1 from public.conversation_participants p
                      where p.conversation_id = c.id and p.tenant_id = c.tenant_id)
          and public.messaging_can_access_conversation(c.id))
      )
  )
  select to_jsonb(s) || jsonb_build_object(
    'conversation_participants',
    coalesce((select jsonb_agg(jsonb_build_object('user_id', p.user_id))
              from public.conversation_participants p
              where p.conversation_id = s.id and p.tenant_id = s.tenant_id), '[]'::jsonb),
    'conversation_contexts',
    coalesce((select jsonb_agg(to_jsonb(x))
              from public.conversation_contexts x
              where x.conversation_id = s.id and x.tenant_id = s.tenant_id), '[]'::jsonb))
  from scoped s
  order by coalesce(s.last_message_at, s.updated_at) desc nulls last, s.id;
$$;
revoke all on function public.inbox_conversations_v1(text) from public, anon;
grant execute on function public.inbox_conversations_v1(text) to authenticated, service_role;

create or replace function public.inbox_context_hint_rows_v1(
  p_conversation_ids uuid[],
  p_job_ids uuid[] default '{}',
  p_invoice_ids uuid[] default '{}',
  p_purchase_invoice_ids uuid[] default '{}',
  p_order_ids uuid[] default '{}',
  p_creator_ids uuid[] default '{}',
  p_supplier_ids uuid[] default '{}'
)
returns jsonb
language sql stable security definer
set search_path = pg_catalog, public
as $$
  with me as (
    select auth.uid() as user_id, public.user_tenant_id() as tenant_id
  ),
  staff as (
    select me.tenant_id from me where public.messaging_is_staff_in_tenant(me.tenant_id)
  ),
  convs as (
    select c.id, c.tenant_id
    from public.conversations c
    join staff on staff.tenant_id = c.tenant_id
    where c.id = any(coalesce(p_conversation_ids, '{}'::uuid[]))
      and cardinality(p_conversation_ids) <= 500
  ),
  bindings as (
    select b.conversation_id, b.customer_id, b.contact_name, b.external_phone_number, b.supplier_contact_id
    from public.whatsapp_conversation_bindings b
    join convs on convs.id = b.conversation_id and convs.tenant_id = b.tenant_id
  ),
  -- A phone matches on its last eight digits here; the app keeps its exact
  -- candidate matching on top, so this is a superset, never a decision.
  phone_keys as (
    select distinct right(regexp_replace(b.external_phone_number, '\D', '', 'g'), 8) as key
    from bindings b
    where b.external_phone_number is not null
      and length(regexp_replace(b.external_phone_number, '\D', '', 'g')) >= 8
  ),
  suppliers as (
    select s.id, s.name, s.phone, s.sales_rep_phone, s.sales_rep_name, s.is_active
    from public.suppliers s join staff on staff.tenant_id = s.tenant_id
  ),
  contacts as (
    select sc.id, sc.name, sc.role, sc.is_primary, sc.is_active
    from public.supplier_contacts sc join staff on staff.tenant_id = sc.tenant_id
    where sc.id in (select supplier_contact_id from bindings where supplier_contact_id is not null)
  ),
  orders as (
    select o.id, o.customer_id, o.customer_name, o.customer_phone
    from public.online_orders o join staff on staff.tenant_id = o.tenant_id
    where o.id = any(coalesce(p_order_ids, '{}'::uuid[]))
  ),
  explicit_invoices as (
    select i.id, i.customer_id, i.customer_name, i.invoice_number, i.status, i.total, i.balance, i.date
    from public.sales_invoices i join staff on staff.tenant_id = i.tenant_id
    where i.id = any(coalesce(p_invoice_ids, '{}'::uuid[]))
  ),
  explicit_purchase_invoices as (
    select pi.id, pi.supplier_id, pi.supplier_name, pi.invoice_number, pi.status, pi.total, pi.balance, pi.date, pi.due_date, pi.updated_at
    from public.purchase_invoices pi join staff on staff.tenant_id = pi.tenant_id
    where pi.id = any(coalesce(p_purchase_invoice_ids, '{}'::uuid[]))
  ),
  job_base as (
    select j.id, j.tenant_id, j.customer_id, j.bike_id, j.job_number, j.status, j.status_id,
           j.status_updated_at, j.invoice_id, j.arrival_date, j.updated_at
    from public.mechanic_jobs j join staff on staff.tenant_id = j.tenant_id
    where j.deleted_at is null
      and (j.id = any(coalesce(p_job_ids, '{}'::uuid[]))
           or (cardinality(p_invoice_ids) > 0 and j.invoice_id = any(p_invoice_ids)))
  ),
  customer_ids as (
    select customer_id as id from bindings where customer_id is not null
    union select customer_id from explicit_invoices where customer_id is not null
    union select customer_id from orders where customer_id is not null
    union select customer_id from job_base where customer_id is not null
  ),
  customers as (
    select cu.id, cu.auth_user_id, cu.name, cu.phone, cu.image_url
    from public.customers cu join staff on staff.tenant_id = cu.tenant_id
    where cu.id in (select id from customer_ids)
       or cu.auth_user_id = any(coalesce(p_creator_ids, '{}'::uuid[]))
       or (cu.phone is not null
           and right(regexp_replace(cu.phone, '\D', '', 'g'), 8) in (select key from phone_keys))
  ),
  customer_jobs as (
    select j.id, j.tenant_id, j.customer_id, j.bike_id, j.job_number, j.status, j.status_id,
           j.status_updated_at, j.invoice_id, j.arrival_date, j.updated_at
    from customers cu
    cross join lateral (
      select x.* from public.mechanic_jobs x join staff on staff.tenant_id = x.tenant_id
      where x.customer_id = cu.id and x.deleted_at is null
      order by x.updated_at desc nulls last limit 100
    ) j
  ),
  jobs as (
    select * from job_base union select * from customer_jobs
  ),
  jobs_json as (
    select j.*,
           (select jsonb_build_object('name', js.name, 'color', js.color)
            from public.job_statuses js where js.id = j.status_id) as job_status
    from jobs j
  ),
  invoices as (
    select * from explicit_invoices
    union
    select i.id, i.customer_id, i.customer_name, i.invoice_number, i.status, i.total, i.balance, i.date
    from public.sales_invoices i join staff on staff.tenant_id = i.tenant_id
    where i.id in (select invoice_id from jobs where invoice_id is not null)
  ),
  supplier_ids as (
    select unnest(coalesce(p_supplier_ids, '{}'::uuid[])) as id
    union select supplier_id from explicit_purchase_invoices where supplier_id is not null
    union select s.id from suppliers s
      where (s.phone is not null and right(regexp_replace(s.phone, '\D', '', 'g'), 8) in (select key from phone_keys))
         or (s.sales_rep_phone is not null and right(regexp_replace(s.sales_rep_phone, '\D', '', 'g'), 8) in (select key from phone_keys))
  ),
  purchase_invoices as (
    select * from explicit_purchase_invoices
    union
    select * from (
      select pi.id, pi.supplier_id, pi.supplier_name, pi.invoice_number, pi.status, pi.total, pi.balance, pi.date, pi.due_date, pi.updated_at
      from public.purchase_invoices pi join staff on staff.tenant_id = pi.tenant_id
      where pi.supplier_id in (select id from supplier_ids)
      order by pi.date desc nulls last limit 500
    ) recent
  ),
  bikes as (
    select b.id, b.brand, b.model, b.year
    from public.bikes b join staff on staff.tenant_id = b.tenant_id
    where b.id in (select bike_id from jobs where bike_id is not null)
  ),
  job_bikes as (
    select jb.job_id, jb.bike_id, jb.order_index,
           (select jsonb_build_object('id', b.id, 'brand', b.brand, 'model', b.model, 'year', b.year)
            from public.bikes b where b.id = jb.bike_id and b.tenant_id = jb.tenant_id) as bike
    from public.mechanic_job_bikes jb join staff on staff.tenant_id = jb.tenant_id
    where jb.job_id in (select id from jobs)
  )
  select jsonb_build_object(
    'bindings', coalesce((select jsonb_agg(to_jsonb(b)) from bindings b), '[]'::jsonb),
    'supplier_contacts', coalesce((select jsonb_agg(to_jsonb(c)) from contacts c), '[]'::jsonb),
    'suppliers', coalesce((select jsonb_agg(to_jsonb(s)) from suppliers s), '[]'::jsonb),
    'customers', coalesce((select jsonb_agg(to_jsonb(cu)) from customers cu), '[]'::jsonb),
    'sales_invoices', coalesce((select jsonb_agg(to_jsonb(i)) from invoices i), '[]'::jsonb),
    'purchase_invoices', coalesce((select jsonb_agg(to_jsonb(p) order by p.date desc nulls last, p.updated_at desc nulls last) from purchase_invoices p), '[]'::jsonb),
    'online_orders', coalesce((select jsonb_agg(to_jsonb(o)) from orders o), '[]'::jsonb),
    'mechanic_jobs', coalesce((select jsonb_agg(to_jsonb(j) order by j.updated_at desc nulls last) from jobs_json j), '[]'::jsonb),
    'bikes', coalesce((select jsonb_agg(to_jsonb(b)) from bikes b), '[]'::jsonb),
    'mechanic_job_bikes', coalesce((select jsonb_agg(to_jsonb(jb) order by jb.order_index) from job_bikes jb), '[]'::jsonb)
  );
$$;
revoke all on function public.inbox_context_hint_rows_v1(uuid[], uuid[], uuid[], uuid[], uuid[], uuid[], uuid[]) from public, anon;
grant execute on function public.inbox_context_hint_rows_v1(uuid[], uuid[], uuid[], uuid[], uuid[], uuid[], uuid[]) to authenticated, service_role;

comment on function public.inbox_conversations_v1(text) is
  'Inbox list for auth.uid() in the PostgREST embed shape; access decided once per conversation (staff of the tenant, or the messaging access predicate).';
comment on function public.inbox_context_hint_rows_v1(uuid[], uuid[], uuid[], uuid[], uuid[], uuid[], uuid[]) is
  'Every row the inbox context chips may need, for staff of the tenant only, in one read; a superset the client selects from with its own rules.';
commit;

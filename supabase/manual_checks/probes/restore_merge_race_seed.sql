-- Local-only two-connection gate for the installed C2 RPC. Own synthetic namespace.
begin;
do $guard$ begin
  if exists(select 1 from vault.secrets) then raise exception 'local only'; end if;
  if exists(select 1 from public.tenants where id='e2899100-0000-4000-8000-000000000001') then
    raise exception 'probe fixture already exists; inspect before cleanup';
  end if;
end; $guard$;
insert into public.tenants(id,shop_name) values('e2899100-0000-4000-8000-000000000001','Concurrencia de recuperación');
select set_config('request.jwt.claims','{}',true);
select set_config('request.jwt.claim.sub','',true);
insert into auth.users(id,aud,role,email,encrypted_password,email_confirmed_at,
 raw_app_meta_data,raw_user_meta_data,created_at,updated_at)
values('e2899100-0000-4000-8000-000000000091','authenticated','authenticated','merge-race@example.invalid','',now(),'{}','{}',now(),now());
insert into public.user_profiles(user_id,tenant_id,role) values('e2899100-0000-4000-8000-000000000091','e2899100-0000-4000-8000-000000000001','admin');
insert into public.customers(id,tenant_id,name,phone) values('e2899100-0000-4000-8000-000000000010','e2899100-0000-4000-8000-000000000001','Cliente sintético','222');
insert into public.database_backups(id,tenant_id,backup_name,backup_type,status,backup_data)
values('e2899100-0000-4000-8000-000000000050','e2899100-0000-4000-8000-000000000001','Carrera local','manual','completed',jsonb_build_object('customers',
jsonb_build_array(jsonb_build_object('id','e2899100-0000-4000-8000-000000000010','tenant_id','e2899100-0000-4000-8000-000000000001','phone','111'))));
commit;

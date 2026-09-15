select
  has_function_privilege(
    'authenticated',
    'public.get_public_user_info(uuid)',
    'EXECUTE'
  ) as authenticated_can_resolve,
  not has_function_privilege(
    'anon',
    'public.get_public_user_info(uuid)',
    'EXECUTE'
  ) as anonymous_cannot_resolve;

select 1 / case
  when has_function_privilege(
         'authenticated',
         'public.get_public_user_info(uuid)',
         'EXECUTE'
       )
   and not has_function_privilege(
         'anon',
         'public.get_public_user_info(uuid)',
         'EXECUTE'
       )
  then 1 else 0
end as assert_sender_lookup_acl;

select set_config(
  'request.jwt.claims',
  jsonb_build_object(
    'sub', 'f0d091c5-85cc-4c7b-8688-fc352b0e8136',
    'role', 'authenticated'
  )::text,
  true
) as viewer_claims_set;
select set_config(
  'request.jwt.claim.sub',
  'f0d091c5-85cc-4c7b-8688-fc352b0e8136',
  true
) as viewer_id_set;

select public.get_public_user_info(
  '7bb76d88-5455-462e-a838-5f78af922914'
) as company_owner_sender;

select 1 / case
  when public.get_public_user_info(
         '7bb76d88-5455-462e-a838-5f78af922914'
       )->>'name' = 'Viñabike'
   and public.get_public_user_info(
         '7bb76d88-5455-462e-a838-5f78af922914'
       )->>'role' = 'erp_user'
  then 1 else 0
end as assert_company_owner_wins_over_customer;

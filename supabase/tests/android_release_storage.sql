begin;

select plan(11);

select ok(
  exists (
    select 1
    from storage.buckets
    where id = 'erp-mobile-releases'
  ),
  'the Android ERP release bucket exists'
);

select is(
  (
    select public
    from storage.buckets
    where id = 'erp-mobile-releases'
  ),
  false,
  'the Android ERP release bucket is private'
);

select is(
  (
    select file_size_limit
    from storage.buckets
    where id = 'erp-mobile-releases'
  ),
  262144000::bigint,
  'the bucket has a 250 MiB ceiling'
);

select ok(
  exists (
    select 1
    from storage.buckets bucket,
      unnest(bucket.allowed_mime_types) mime_type
    where bucket.id = 'erp-mobile-releases'
      and mime_type = 'application/vnd.android.package-archive'
  ),
  'the bucket accepts Android package artifacts'
);

select ok(
  exists (
    select 1
    from storage.buckets bucket,
      unnest(bucket.allowed_mime_types) mime_type
    where bucket.id = 'erp-mobile-releases'
      and mime_type = 'application/json'
  ),
  'the bucket accepts release manifests'
);

select ok(
  exists (
    select 1
    from pg_policies
    where schemaname = 'storage'
      and tablename = 'objects'
      and policyname = 'android_release_objects_select_staff'
      and cmd = 'SELECT'
      and roles = array['authenticated']::name[]
  ),
  'only authenticated clients receive the release read policy'
);

select ok(
  position(
    'erp-mobile-releases' in (
      select qual
      from pg_policies
      where schemaname = 'storage'
        and tablename = 'objects'
        and policyname = 'android_release_objects_select_staff'
    )
  ) > 0,
  'the read policy is limited to the mobile release bucket'
);

select ok(
  position(
    'user_profiles' in (
      select qual
      from pg_policies
      where schemaname = 'storage'
        and tablename = 'objects'
        and policyname = 'android_release_objects_select_staff'
    )
  ) > 0,
  'the read policy requires an ERP staff profile'
);

select ok(
  position(
    'is_active' in (
      select qual
      from pg_policies
      where schemaname = 'storage'
        and tablename = 'objects'
        and policyname = 'android_release_objects_select_staff'
    )
  ) > 0,
  'the read policy requires an active staff profile'
);

select ok(
  position(
    'foldername' in (
      select qual
      from pg_policies
      where schemaname = 'storage'
        and tablename = 'objects'
        and policyname = 'android_release_objects_select_staff'
    )
  ) > 0,
  'the read policy binds the first object folder to the tenant'
);

select is(
  (
    select count(*)::bigint
    from pg_policies
    where schemaname = 'storage'
      and tablename = 'objects'
      and policyname like 'android_release_objects_%'
      and cmd <> 'SELECT'
  ),
  0::bigint,
  'no client write policy exists for Android releases'
);

select * from finish();
rollback;

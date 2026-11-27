-- Read-back for 20261126230000_meta_outbound_photos.sql.
-- Each denominator is catalog-derived: an absent gate fails SQL.
select 1 / count(*)::integer as attempt_carries_its_photo
from information_schema.columns
where table_schema = 'public'
  and table_name = 'meta_outbound_send_attempts'
  and column_name = 'attachment_id'
  and data_type = 'uuid';

select 1 / count(*)::integer as one_attempt_per_photo
from pg_indexes
where schemaname = 'public'
  and tablename = 'meta_outbound_send_attempts'
  and indexname = 'meta_outbound_send_attempts_attachment_unique'
  and indexdef like '%(attachment_id)%WHERE (attachment_id IS NOT NULL)%';

select 1 / count(*)::integer as photo_send_is_service_only
from pg_proc
where oid = 'public.begin_meta_outbound_media_send(uuid, uuid, text, text, uuid)'::regprocedure
  and prosecdef
  and has_function_privilege('service_role', oid, 'execute')
  and not has_function_privilege('authenticated', oid, 'execute')
  and not has_function_privilege('anon', oid, 'execute')
  and pg_get_functiondef(oid) like '%hint = ''reply_window_closed''%'
  and pg_get_functiondef(oid) like '%(''image/jpeg'', ''image/png'', ''image/gif'')%'
  and pg_get_functiondef(oid) like '%v_attachment.size_bytes > 8388608%'
  and pg_get_functiondef(oid) like '%v_attachment.created_by is distinct from p_actor_id%'
  and pg_get_functiondef(oid) like '%hint = ''attachment_not_uploaded''%';

select 1 / count(*)::integer as finalize_writes_the_image_bubble
from pg_proc
where oid = 'public.finalize_meta_outbound_send(uuid, text, jsonb)'::regprocedure
  and prosecdef
  and has_function_privilege('service_role', oid, 'execute')
  and not has_function_privilege('authenticated', oid, 'execute')
  and not has_function_privilege('anon', oid, 'execute')
  and pg_get_functiondef(oid) like '%case when v_attempt.attachment_id is null then ''text'' else ''image'' end%'
  and pg_get_functiondef(oid) like '%Meta send attachment belongs to another message%'
  and pg_get_functiondef(oid) like '%''attachment_access'', ''private_signed_runtime''%'
  and pg_get_functiondef(oid) like '%else ''Imagen enviada''%';

select 1 / count(*)::integer as receipts_say_which_were_photos
from pg_proc
where oid = 'public.list_meta_outbound_send_receipts(uuid)'::regprocedure
  and prosecdef
  and has_function_privilege('authenticated', oid, 'execute')
  and not has_function_privilege('anon', oid, 'execute')
  and pg_get_function_result(oid) like '%attachment_id uuid)'
  and pg_get_functiondef(oid) like '%attempt.attachment_id%';

select 1 / count(*)::integer as guard_admits_only_the_attempts_own_photo
from pg_proc
where oid = 'public.enforce_messaging_tenant_consistency()'::regprocedure
  and prosecdef
  and pg_get_functiondef(oid) like '%and new.type in (''text'', ''image'')%'
  and pg_get_functiondef(oid) like '%(attempt.attachment_id is null and new.type = ''text'')%'
  and pg_get_functiondef(oid) like '%attempt.attachment_id::text =%coalesce(new.metadata, ''{}''::jsonb)->>''attachment_id''%'
  and pg_get_functiondef(oid) like '%Meta conversations require trusted provider transport%';

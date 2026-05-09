-- Enable trustworthy scheduled tenant backups, including messaging tables.
-- The schedule is evaluated server-side so backups continue even when the ERP UI is closed.

create or replace function public.calculate_next_backup_run(
  p_frequency text,
  p_time_of_day time default null,
  p_day_of_week int default null,
  p_day_of_month int default null,
  p_from timestamp with time zone default now()
)
returns timestamp with time zone
language plpgsql
stable
as $$
declare
  v_time time := coalesce(p_time_of_day, time '02:00:00');
  v_next timestamp with time zone;
  v_target_dow int;
  v_current_dow int;
  v_days_ahead int;
  v_month_start date;
  v_last_day int;
  v_day int;
begin
  case p_frequency
    when 'hourly' then
      v_next := date_trunc('hour', p_from) + interval '1 hour';

    when 'weekly' then
      v_target_dow := least(greatest(coalesce(p_day_of_week, 0), 0), 6);
      v_current_dow := extract(dow from p_from)::int;
      v_days_ahead := (v_target_dow - v_current_dow + 7) % 7;
      v_next := date_trunc('day', p_from) + (v_days_ahead || ' days')::interval + v_time;
      if v_next <= p_from then
        v_next := v_next + interval '7 days';
      end if;

    when 'monthly' then
      v_month_start := date_trunc('month', p_from)::date;
      v_last_day := extract(day from (v_month_start + interval '1 month - 1 day'))::int;
      v_day := least(greatest(coalesce(p_day_of_month, 1), 1), v_last_day);
      v_next := (v_month_start + (v_day - 1))::timestamp + v_time;

      if v_next <= p_from then
        v_month_start := (v_month_start + interval '1 month')::date;
        v_last_day := extract(day from (v_month_start + interval '1 month - 1 day'))::int;
        v_day := least(greatest(coalesce(p_day_of_month, 1), 1), v_last_day);
        v_next := (v_month_start + (v_day - 1))::timestamp + v_time;
      end if;

    else
      v_next := date_trunc('day', p_from) + v_time;
      if v_next <= p_from then
        v_next := v_next + interval '1 day';
      end if;
  end case;

  return v_next;
end;
$$;

grant execute on function public.calculate_next_backup_run(text, time, int, int, timestamp with time zone) to authenticated;

create or replace function public.set_backup_schedule_next_run()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  new.updated_at := now();

  if new.enabled is not true then
    new.next_run_at := null;
    return new;
  end if;

  if tg_op = 'INSERT'
    or new.next_run_at is null
    or new.enabled is distinct from old.enabled
    or new.frequency is distinct from old.frequency
    or new.time_of_day is distinct from old.time_of_day
    or new.day_of_week is distinct from old.day_of_week
    or new.day_of_month is distinct from old.day_of_month then
    new.next_run_at := public.calculate_next_backup_run(
      new.frequency,
      new.time_of_day,
      new.day_of_week,
      new.day_of_month,
      now()
    );
  end if;

  return new;
end;
$$;

drop trigger if exists trg_backup_schedules_next_run on public.backup_schedules;
create trigger trg_backup_schedules_next_run
  before insert or update on public.backup_schedules
  for each row execute function public.set_backup_schedule_next_run();

create or replace function public.run_due_backup_schedules(
  p_now timestamp with time zone default now()
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_schedule record;
  v_result jsonb;
  v_results jsonb := '[]'::jsonb;
  v_created_count int := 0;
  v_failed_count int := 0;
  v_next_run timestamp with time zone;
begin
  for v_schedule in
    select *
    from public.backup_schedules
    where enabled = true
      and coalesce(next_run_at, p_now) <= p_now
    order by next_run_at nulls first
    limit 50
  loop
    begin
      v_result := public.create_backup(
        v_schedule.tenant_id,
        'Respaldo automático ' || to_char(p_now at time zone 'UTC', 'YYYY-MM-DD HH24:MI') || ' UTC',
        'scheduled',
        'Respaldo automático completo creado por el programador del servidor.'
      );

      if coalesce((v_result->>'success')::boolean, false) then
        v_created_count := v_created_count + 1;
      else
        v_failed_count := v_failed_count + 1;
      end if;

      if v_schedule.auto_delete_old then
        perform public.cleanup_old_backups(v_schedule.tenant_id);
      end if;

      v_next_run := public.calculate_next_backup_run(
        v_schedule.frequency,
        v_schedule.time_of_day,
        v_schedule.day_of_week,
        v_schedule.day_of_month,
        p_now
      );

      update public.backup_schedules
      set last_run_at = p_now,
          next_run_at = v_next_run,
          updated_at = now()
      where id = v_schedule.id;

      v_results := v_results || jsonb_build_array(jsonb_build_object(
        'tenant_id', v_schedule.tenant_id,
        'schedule_id', v_schedule.id,
        'next_run_at', v_next_run,
        'result', v_result
      ));
    exception
      when others then
        v_failed_count := v_failed_count + 1;
        v_next_run := public.calculate_next_backup_run(
          v_schedule.frequency,
          v_schedule.time_of_day,
          v_schedule.day_of_week,
          v_schedule.day_of_month,
          p_now
        );

        update public.backup_schedules
        set last_run_at = p_now,
            next_run_at = v_next_run,
            updated_at = now()
        where id = v_schedule.id;

        v_results := v_results || jsonb_build_array(jsonb_build_object(
          'tenant_id', v_schedule.tenant_id,
          'schedule_id', v_schedule.id,
          'next_run_at', v_next_run,
          'error', sqlerrm
        ));
    end;
  end loop;

  return jsonb_build_object(
    'success', true,
    'created_count', v_created_count,
    'failed_count', v_failed_count,
    'checked_at', p_now,
    'results', v_results
  );
end;
$$;

revoke all on function public.run_due_backup_schedules(timestamp with time zone) from public;
revoke execute on function public.run_due_backup_schedules(timestamp with time zone) from authenticated;
revoke execute on function public.run_due_backup_schedules(timestamp with time zone) from anon;

create or replace function public.cleanup_old_backups(p_tenant_id uuid)
returns jsonb
security definer
language plpgsql
as $$
declare
  v_keep_count int;
  v_auto_delete boolean;
  v_deleted_count int := 0;
  v_backup_ids uuid[];
begin
  select keep_last_n_backups, auto_delete_old
  into v_keep_count, v_auto_delete
  from backup_schedules
  where tenant_id = p_tenant_id;

  if not found or not v_auto_delete then
    return jsonb_build_object('success', true, 'deleted_count', 0, 'message', 'Auto-delete disabled');
  end if;

  select array_agg(id) into v_backup_ids
  from (
    select id
    from database_backups
    where tenant_id = p_tenant_id
      and status = 'completed'
      and backup_type in ('automatic', 'scheduled')
    order by created_at desc
    offset v_keep_count
  ) old_backups;

  if v_backup_ids is not null then
    delete from database_backups
    where id = any(v_backup_ids);

    get diagnostics v_deleted_count = row_count;
  end if;

  return jsonb_build_object(
    'success', true,
    'deleted_count', v_deleted_count,
    'kept_count', v_keep_count,
    'scope', 'automatic_and_scheduled_only'
  );
end;
$$;

grant execute on function public.cleanup_old_backups(uuid) to authenticated;

do $$
begin
  if exists (select 1 from pg_namespace where nspname = 'cron') then
    perform cron.unschedule(jobid)
    from cron.job
    where jobname = 'vinabike_run_due_backup_schedules';

    perform cron.schedule(
      'vinabike_run_due_backup_schedules',
      '*/15 * * * *',
      'select public.run_due_backup_schedules();'
    );
  end if;
exception
  when others then
    raise notice 'Could not install scheduled backup cron job: %', sqlerrm;
end $$;

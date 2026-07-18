begin;

-- The aggregate temporarily moves a posted expense to draft so the old
-- journal can be archived. prepare_expense_record() clears posted_at on that
-- transition, so the final post must explicitly restore the original audit
-- timestamp instead of falling back to the document issue date.
do $$
declare
  v_definition text;
  v_old text := $old$set posting_status = 'posted',
      updated_at = clock_timestamp()$old$;
  v_new text := $new$set posting_status = 'posted',
      -- Preserve the original accounting timestamp across the draft bridge.
      posted_at = coalesce(v_before.posted_at, v_before.issue_date),
      updated_at = clock_timestamp()$new$;
  v_count integer;
begin
  select pg_get_functiondef(
    'public.save_expense_aggregate(text,uuid,timestamptz,jsonb)'::regprocedure
  ) into v_definition;

  if position('Preserve the original accounting timestamp across the draft bridge' in v_definition) > 0 then
    return;
  end if;

  v_count := (
    length(v_definition) - length(replace(v_definition, v_old, ''))
  ) / length(v_old);

  if v_count <> 1 then
    raise exception
      'Expected one aggregate repost assignment, found %',
      v_count;
  end if;

  execute replace(v_definition, v_old, v_new);
end;
$$;

comment on function public.save_expense_aggregate(text, uuid, timestamptz, jsonb) is
  'Atomically edits one simple expense, preserves its audit timestamps, archives its previous posted journal, persists integer CLP tax amounts, and returns an idempotent command receipt.';

commit;

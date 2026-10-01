-- LOCAL ONLY. Send the whole reviewed file as query.sh local --sql, using
-- an argv API to pass its contents. --file sends separate client commands and
-- would not reproduce multiple statements in one PostgreSQL query message.
-- No business rows or persistent definitions; all temporary state rolls back.
begin;
set local statement_timeout = '5s';
create temporary table restore_packet_clock on commit drop as
  select statement_timestamp() as first_command_clock;
select pg_sleep(0.003);
do $probe$
begin
  if statement_timestamp() is distinct from
      (select first_command_clock from restore_packet_clock) then
    raise exception 'This probe was not sent as one client query message';
  end if;
  if clock_timestamp() <= (select first_command_clock from restore_packet_clock) then
    raise exception 'The wall clock did not advance';
  end if;
end;
$probe$;
select statement_timestamp() = first_command_clock as several_statements_share_clock,
       clock_timestamp() > first_command_clock as wall_clock_advanced
  from restore_packet_clock;
rollback;

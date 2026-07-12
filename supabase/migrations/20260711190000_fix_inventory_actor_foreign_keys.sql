-- Production drift fix: trace actor IDs come from auth.uid(), so inventory
-- evidence must reference auth.users rather than the empty legacy users_profiles.
-- No business row is rewritten.

begin;

alter table public.stock_movements
  drop constraint if exists stock_movements_created_by_fkey;
alter table public.stock_movements
  add constraint stock_movements_created_by_fkey
  foreign key (created_by) references auth.users(id) on delete set null;

alter table public.journal_entries
  drop constraint if exists journal_entries_created_by_fkey;
alter table public.journal_entries
  add constraint journal_entries_created_by_fkey
  foreign key (created_by) references auth.users(id) on delete set null;

commit;

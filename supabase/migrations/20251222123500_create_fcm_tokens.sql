create table if not exists public.user_fcm_tokens (
  user_id uuid references auth.users(id) on delete cascade not null,
  fcm_token text not null,
  device_type text,
  updated_at timestamp with time zone default now(),
  primary key (user_id, fcm_token)
);

-- Enable RLS
alter table public.user_fcm_tokens enable row level security;

-- Policy: Users can insert/select/update their own tokens
create policy "Users can manage their own FCM tokens"
  on public.user_fcm_tokens
  for all
  to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

-- Policy: Service Role can access all (Edge Functions use service role)
-- Implicitly allowed for service_role usually, but good to be aware.

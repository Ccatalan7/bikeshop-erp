create table if not exists public.google_oauth_connections (
  integration_key text primary key,
  provider text not null default 'google',
  account_email text,
  access_token text not null,
  refresh_token text,
  token_type text,
  scope text,
  expires_at timestamptz,
  updated_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.google_oauth_connections enable row level security;

create table if not exists public.google_oauth_states (
  state text primary key,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  expires_at timestamptz not null default (now() + interval '15 minutes')
);

alter table public.google_oauth_states enable row level security;

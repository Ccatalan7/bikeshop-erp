-- Server-side mail account connections for Gmail/Zoho.
-- Flutter must not store or read provider access/refresh tokens locally.

create table if not exists public.email_accounts (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid references public.tenants(id) on delete cascade not null,
  user_id uuid references auth.users(id) on delete cascade not null,
  provider text not null check (provider in ('gmail', 'zoho')),
  account_email text not null,
  provider_account_id text,
  access_token text,
  refresh_token text not null,
  token_type text,
  scope text,
  token_expires_at timestamp with time zone,
  provider_metadata jsonb not null default '{}'::jsonb,
  is_active boolean not null default true,
  last_connected_at timestamp with time zone not null default now(),
  last_token_refresh_at timestamp with time zone,
  last_error text,
  created_at timestamp with time zone default now(),
  updated_at timestamp with time zone default now(),
  unique(user_id, provider)
);

create index if not exists idx_email_accounts_tenant on public.email_accounts(tenant_id);
create index if not exists idx_email_accounts_user on public.email_accounts(user_id);
create index if not exists idx_email_accounts_provider_email on public.email_accounts(provider, account_email);

alter table public.email_accounts enable row level security;

-- No authenticated policies on purpose: token-bearing rows are server-only.
revoke all on table public.email_accounts from anon, authenticated;
grant all on table public.email_accounts to service_role;

drop trigger if exists trg_email_accounts_updated_at on public.email_accounts;
create trigger trg_email_accounts_updated_at
  before update on public.email_accounts
  for each row execute function public.set_updated_at();

comment on table public.email_accounts is
  'Server-side Gmail/Zoho OAuth tokens. Access only through authenticated Edge Functions.';
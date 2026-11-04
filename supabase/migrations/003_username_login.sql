-- AU · Inicio de sesión con nombres de usuario.
-- Los alias no son accesibles desde anon/authenticated; solo la Edge Function usa service_role.

create table if not exists public.login_aliases (
  username text primary key
    check (username = lower(username) and username ~ '^[a-z0-9._-]{3,32}$'),
  user_id uuid not null unique references auth.users(id) on delete cascade,
  is_active boolean not null default true,
  created_at timestamptz not null default now()
);

alter table public.login_aliases enable row level security;
revoke all on table public.login_aliases from public, anon, authenticated;
grant select on table public.login_aliases to service_role;

insert into public.login_aliases (username, user_id, is_active)
values
  ('lasflores', 'df606f9c-229b-4e9b-a330-81ce8d510a0b', true),
  ('lafabio', '84a728d2-4740-49ba-8f7f-1af38fcda950', true)
on conflict (username) do update
set user_id = excluded.user_id,
    is_active = excluded.is_active;

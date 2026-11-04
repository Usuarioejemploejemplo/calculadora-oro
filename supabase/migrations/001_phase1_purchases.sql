-- AU · Fase 1: base segura para clientes y compras
-- Instalar una sola vez en un proyecto Supabase nuevo.
-- El primer usuario administrador se vincula por separado desde SQL Editor.
-- Esta migración NO crea credenciales, recibos definitivos ni flujo de cierre de compra.

create extension if not exists pgcrypto;

create table public.organizations (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  country_code text not null default 'HN',
  currency_code text not null default 'HNL',
  created_at timestamptz not null default now()
);

create table public.branches (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete restrict,
  code text not null,
  name text not null,
  address text,
  phone text,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  unique (organization_id, code),
  unique (id, organization_id)
);

create table public.user_profiles (
  user_id uuid primary key references auth.users(id) on delete cascade,
  organization_id uuid not null references public.organizations(id) on delete restrict,
  full_name text not null,
  role text not null check (role in ('owner','admin','manager','employee','viewer')),
  is_active boolean not null default true,
  created_at timestamptz not null default now()
);

create table public.branch_memberships (
  user_id uuid not null references public.user_profiles(user_id) on delete cascade,
  branch_id uuid not null references public.branches(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (user_id, branch_id)
);

create table public.customers (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete restrict,
  full_name text not null,
  phone text,
  identity_document text,
  address text,
  notes text,
  created_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (id, organization_id)
);

create index customers_org_name_idx on public.customers (organization_id, lower(full_name));
create index customers_org_phone_idx on public.customers (organization_id, phone);

create table public.purchases (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete restrict,
  branch_id uuid not null,
  purchase_number text not null,
  customer_id uuid not null,
  employee_id uuid not null references auth.users(id),
  status text not null default 'draft' check (status in ('draft','completed','voided')),
  gold_quote_hnl_per_gram numeric(14,4) not null check (gold_quote_hnl_per_gram > 0),
  discount_percent numeric(5,2) not null check (discount_percent between 0 and 100),
  subtotal_hnl numeric(14,2) not null default 0 check (subtotal_hnl >= 0),
  total_paid_hnl numeric(14,2) not null default 0 check (total_paid_hnl >= 0),
  notes text,
  void_reason text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (branch_id, purchase_number),
  foreign key (branch_id, organization_id)
    references public.branches(id, organization_id) on delete restrict,
  foreign key (customer_id, organization_id)
    references public.customers(id, organization_id) on delete restrict
);

create index purchases_org_date_idx on public.purchases (organization_id, created_at desc);
create index purchases_branch_date_idx on public.purchases (branch_id, created_at desc);
create index purchases_customer_idx on public.purchases (customer_id);

create table public.purchase_items (
  id uuid primary key default gen_random_uuid(),
  purchase_id uuid not null references public.purchases(id) on delete restrict,
  item_type text not null,
  description text,
  weight_grams numeric(12,3) not null check (weight_grams > 0),
  karat smallint not null check (karat between 1 and 24),
  purity_percent numeric(6,3) not null check (purity_percent between 0 and 100),
  unit_price_hnl numeric(14,4) not null check (unit_price_hnl >= 0),
  line_total_hnl numeric(14,2) not null check (line_total_hnl >= 0),
  stone_weight_grams numeric(12,3) not null default 0 check (stone_weight_grams >= 0),
  created_at timestamptz not null default now()
);

create index purchase_items_purchase_idx on public.purchase_items (purchase_id);

create table public.purchase_attachments (
  id uuid primary key default gen_random_uuid(),
  purchase_id uuid not null references public.purchases(id) on delete restrict,
  storage_path text not null unique,
  file_name text not null,
  content_type text,
  uploaded_by uuid not null references auth.users(id),
  created_at timestamptz not null default now()
);

create table public.audit_events (
  id bigint generated always as identity primary key,
  organization_id uuid not null references public.organizations(id) on delete restrict,
  branch_id uuid,
  actor_user_id uuid references auth.users(id),
  entity_type text not null,
  entity_id uuid,
  action text not null,
  details jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  foreign key (branch_id, organization_id)
    references public.branches(id, organization_id) on delete restrict
);

create index audit_org_date_idx on public.audit_events (organization_id, created_at desc);

-- Helpers SECURITY DEFINER para consultar membresías sin recursión de RLS.
create or replace function public.is_org_member(target_org uuid)
returns boolean
language sql stable security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.user_profiles p
    where p.user_id = (select auth.uid())
      and p.organization_id = target_org
      and p.is_active = true
  );
$$;

create or replace function public.has_org_role(target_org uuid, allowed_roles text[])
returns boolean
language sql stable security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.user_profiles p
    where p.user_id = (select auth.uid())
      and p.organization_id = target_org
      and p.is_active = true
      and p.role = any(allowed_roles)
  );
$$;

create or replace function public.can_access_branch(target_branch uuid)
returns boolean
language sql stable security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.branches b
    join public.user_profiles p
      on p.organization_id = b.organization_id
     and p.user_id = (select auth.uid())
     and p.is_active = true
    left join public.branch_memberships bm
      on bm.branch_id = b.id and bm.user_id = p.user_id
    where b.id = target_branch
      and b.is_active = true
      and (p.role in ('owner','admin') or bm.user_id is not null)
  );
$$;

revoke all on function public.is_org_member(uuid) from public, anon;
revoke all on function public.has_org_role(uuid, text[]) from public, anon;
revoke all on function public.can_access_branch(uuid) from public, anon;
grant execute on function public.is_org_member(uuid) to authenticated;
grant execute on function public.has_org_role(uuid, text[]) to authenticated;
grant execute on function public.can_access_branch(uuid) to authenticated;

alter table public.organizations enable row level security;
alter table public.branches enable row level security;
alter table public.user_profiles enable row level security;
alter table public.branch_memberships enable row level security;
alter table public.customers enable row level security;
alter table public.purchases enable row level security;
alter table public.purchase_items enable row level security;
alter table public.purchase_attachments enable row level security;
alter table public.audit_events enable row level security;

create policy org_read_members on public.organizations
for select to authenticated using (public.is_org_member(id));

create policy branches_read_org on public.branches
for select to authenticated using (public.is_org_member(organization_id));

create policy profiles_read_self_or_managers on public.user_profiles
for select to authenticated using (
  user_id = (select auth.uid())
  or public.has_org_role(organization_id, array['owner','admin','manager'])
);

create policy memberships_read_self_or_branch_admins on public.branch_memberships
for select to authenticated using (
  user_id = (select auth.uid())
  or public.has_org_role(
    (select b.organization_id from public.branches b where b.id = branch_id),
    array['owner','admin','manager']
  )
);

create policy customers_read_org on public.customers
for select to authenticated using (public.is_org_member(organization_id));

create policy customers_insert_staff on public.customers
for insert to authenticated with check (
  public.has_org_role(organization_id, array['owner','admin','manager','employee'])
  and (created_by is null or created_by = (select auth.uid()))
);

create policy customers_update_managers on public.customers
for update to authenticated
using (public.has_org_role(organization_id, array['owner','admin','manager']))
with check (public.has_org_role(organization_id, array['owner','admin','manager']));

create policy purchases_read_branch on public.purchases
for select to authenticated using (public.can_access_branch(branch_id));

-- Solo se pueden crear borradores desde el cliente. Cerrar/anular compras será
-- una operación backend transaccional; no hay UPDATE ni DELETE directo.
create policy purchases_insert_draft on public.purchases
for insert to authenticated with check (
  status = 'draft'
  and employee_id = (select auth.uid())
  and public.has_org_role(organization_id, array['owner','admin','manager','employee'])
  and public.can_access_branch(branch_id)
);

create policy purchase_items_read_parent on public.purchase_items
for select to authenticated using (
  exists (
    select 1 from public.purchases p
    where p.id = purchase_id and public.can_access_branch(p.branch_id)
  )
);

create policy purchase_items_insert_draft_parent on public.purchase_items
for insert to authenticated with check (
  exists (
    select 1 from public.purchases p
    where p.id = purchase_id
      and p.status = 'draft'
      and p.employee_id = (select auth.uid())
      and public.can_access_branch(p.branch_id)
  )
);

create policy attachments_read_parent on public.purchase_attachments
for select to authenticated using (
  exists (
    select 1 from public.purchases p
    where p.id = purchase_id and public.can_access_branch(p.branch_id)
  )
);

create policy attachments_insert_draft_parent on public.purchase_attachments
for insert to authenticated with check (
  uploaded_by = (select auth.uid())
  and exists (
    select 1 from public.purchases p
    where p.id = purchase_id
      and p.status = 'draft'
      and p.employee_id = (select auth.uid())
      and public.can_access_branch(p.branch_id)
  )
);

create policy audit_read_branch_or_org on public.audit_events
for select to authenticated using (
  (branch_id is not null and public.can_access_branch(branch_id))
  or (branch_id is null and public.is_org_member(organization_id))
);

-- No se conceden escrituras directas a tablas administrativas ni a auditoría.
-- No se habilitan UPDATE/DELETE en compras/items: las operaciones definitivas
-- se implementarán mediante funciones backend con transacción y auditoría.

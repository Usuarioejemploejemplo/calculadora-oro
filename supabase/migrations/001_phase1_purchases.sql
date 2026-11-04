-- AU · Fase 1: estructura inicial multi-sucursal para compras y clientes
-- Ejecutar en Supabase SQL Editor después de crear el proyecto.
-- No contiene credenciales ni crea usuarios: el primer administrador se configura aparte.

create extension if not exists pgcrypto;

create table if not exists public.organizations (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  country_code text not null default 'HN',
  currency_code text not null default 'HNL',
  created_at timestamptz not null default now()
);

create table if not exists public.branches (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id),
  code text not null,
  name text not null,
  address text,
  phone text,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  unique (organization_id, code),
  unique (id, organization_id)
);

create table if not exists public.user_profiles (
  user_id uuid primary key references auth.users(id) on delete cascade,
  organization_id uuid not null references public.organizations(id),
  full_name text not null,
  role text not null check (role in ('owner','admin','manager','employee','viewer')),
  is_active boolean not null default true,
  created_at timestamptz not null default now()
);

create table if not exists public.branch_memberships (
  user_id uuid not null references public.user_profiles(user_id) on delete cascade,
  branch_id uuid not null references public.branches(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (user_id, branch_id)
);

create table if not exists public.customers (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id),
  full_name text not null,
  phone text,
  identity_document text,
  address text,
  notes text,
  created_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists customers_org_name_idx
  on public.customers (organization_id, lower(full_name));
create index if not exists customers_org_phone_idx
  on public.customers (organization_id, phone);

create table if not exists public.purchases (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id),
  branch_id uuid not null,
  purchase_number text not null,
  customer_id uuid not null references public.customers(id),
  employee_id uuid not null references auth.users(id),
  status text not null default 'completed'
    check (status in ('draft','completed','voided')),
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
    references public.branches(id, organization_id)
);

create index if not exists purchases_org_date_idx
  on public.purchases (organization_id, created_at desc);
create index if not exists purchases_branch_date_idx
  on public.purchases (branch_id, created_at desc);
create index if not exists purchases_customer_idx on public.purchases (customer_id);

create table if not exists public.purchase_items (
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

create index if not exists purchase_items_purchase_idx
  on public.purchase_items (purchase_id);

create table if not exists public.purchase_attachments (
  id uuid primary key default gen_random_uuid(),
  purchase_id uuid not null references public.purchases(id) on delete restrict,
  storage_path text not null unique,
  file_name text not null,
  content_type text,
  uploaded_by uuid not null references auth.users(id),
  created_at timestamptz not null default now()
);

create table if not exists public.audit_events (
  id bigint generated always as identity primary key,
  organization_id uuid not null references public.organizations(id),
  branch_id uuid references public.branches(id),
  actor_user_id uuid references auth.users(id),
  entity_type text not null,
  entity_id uuid,
  action text not null,
  details jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create index if not exists audit_org_date_idx
  on public.audit_events (organization_id, created_at desc);

-- Funciones de autorización: las políticas consultan membresías y rol del usuario.
create or replace function public.is_org_member(target_org uuid)
returns boolean
language sql stable security definer
set search_path = public
as $$
  select exists (
    select 1 from public.user_profiles p
    where p.user_id = auth.uid()
      and p.organization_id = target_org
      and p.is_active = true
  );
$$;

create or replace function public.can_access_branch(target_branch uuid)
returns boolean
language sql stable security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.branches b
    join public.user_profiles p
      on p.organization_id = b.organization_id
     and p.user_id = auth.uid()
     and p.is_active = true
    left join public.branch_memberships bm
      on bm.branch_id = b.id and bm.user_id = p.user_id
    where b.id = target_branch
      and b.is_active = true
      and (p.role in ('owner','admin') or bm.user_id is not null)
  );
$$;

alter table public.organizations enable row level security;
alter table public.branches enable row level security;
alter table public.user_profiles enable row level security;
alter table public.branch_memberships enable row level security;
alter table public.customers enable row level security;
alter table public.purchases enable row level security;
alter table public.purchase_items enable row level security;
alter table public.purchase_attachments enable row level security;
alter table public.audit_events enable row level security;

create policy "organization members read organization"
on public.organizations for select
using (public.is_org_member(id));

create policy "organization members read branches"
on public.branches for select
using (public.is_org_member(organization_id));

create policy "users read own profile or organization admins read profiles"
on public.user_profiles for select
using (
  user_id = auth.uid()
  or (
    public.is_org_member(organization_id)
    and exists (
      select 1 from public.user_profiles me
      where me.user_id = auth.uid()
        and me.organization_id = user_profiles.organization_id
        and me.role in ('owner','admin','manager')
        and me.is_active = true
    )
  )
);

create policy "users read their branch memberships"
on public.branch_memberships for select
using (
  user_id = auth.uid()
  or public.can_access_branch(branch_id)
);

create policy "organization members read customers"
on public.customers for select
using (public.is_org_member(organization_id));

create policy "organization members create customers"
on public.customers for insert
with check (
  public.is_org_member(organization_id)
  and (created_by is null or created_by = auth.uid())
);

create policy "organization members update customers"
on public.customers for update
using (public.is_org_member(organization_id))
with check (public.is_org_member(organization_id));

create policy "branch members read purchases"
on public.purchases for select
using (public.can_access_branch(branch_id));

create policy "branch members create purchases as themselves"
on public.purchases for insert
with check (
  public.can_access_branch(branch_id)
  and employee_id = auth.uid()
  and exists (
    select 1 from public.branches b
    where b.id = branch_id and b.organization_id = purchases.organization_id
  )
  and public.is_org_member(organization_id)
);

create policy "branch members update purchases"
on public.purchases for update
using (public.can_access_branch(branch_id))
with check (public.can_access_branch(branch_id));

create policy "purchase items follow parent purchase access"
on public.purchase_items for select
using (exists (
  select 1 from public.purchases p
  where p.id = purchase_id and public.can_access_branch(p.branch_id)
));

create policy "branch members add purchase items"
on public.purchase_items for insert
with check (exists (
  select 1 from public.purchases p
  where p.id = purchase_id and public.can_access_branch(p.branch_id)
));

create policy "branch members read purchase attachments"
on public.purchase_attachments for select
using (exists (
  select 1 from public.purchases p
  where p.id = purchase_id and public.can_access_branch(p.branch_id)
));

create policy "branch members add purchase attachments"
on public.purchase_attachments for insert
with check (
  uploaded_by = auth.uid()
  and exists (
    select 1 from public.purchases p
    where p.id = purchase_id and public.can_access_branch(p.branch_id)
  )
);

create policy "branch members read audit events"
on public.audit_events for select
using (
  (branch_id is not null and public.can_access_branch(branch_id))
  or (branch_id is null and public.is_org_member(organization_id))
);

-- Nota de seguridad:
-- No se habilitan escrituras directas para audit_events desde el cliente.
-- Las anulaciones, secuencias de recibos y cambios de permisos deben pasar
-- por funciones backend transaccionales y autorizadas antes de producción.

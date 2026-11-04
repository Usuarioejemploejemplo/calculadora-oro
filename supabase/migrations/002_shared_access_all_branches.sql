-- AU · Acceso compartido entre las dos cuentas administradoras.
-- Ejecutar después de 001_phase1_purchases.sql.
-- Los administradores activos acceden a todas las sucursales de su organización.
-- Los demás usuarios conservan el acceso limitado a sus sucursales asignadas.

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
      on bm.branch_id = b.id
     and bm.user_id = p.user_id
    where b.id = target_branch
      and b.is_active = true
      and (p.role in ('owner','admin') or bm.user_id is not null)
  );
$$;

revoke all on function public.can_access_branch(uuid) from public, anon;
grant execute on function public.can_access_branch(uuid) to authenticated;

-- Los administradores pueden ver todas las sucursales de la organización;
-- los demás usuarios solo ven sucursales a las que pertenecen.
drop policy if exists branches_read_org on public.branches;
create policy branches_read_org on public.branches
for select to authenticated
using (
  public.has_org_role(organization_id, array['owner','admin'])
  or public.can_access_branch(id)
);

-- Los administradores pueden consultar perfiles dentro de su organización.
drop policy if exists profiles_read_self_or_managers on public.user_profiles;
create policy profiles_read_self_or_managers on public.user_profiles
for select to authenticated
using (
  user_id = (select auth.uid())
  or public.has_org_role(organization_id, array['owner','admin','manager'])
);

-- Para permisos idénticos, las dos cuentas deben tener role='admin'
-- y is_active=true en public.user_profiles.

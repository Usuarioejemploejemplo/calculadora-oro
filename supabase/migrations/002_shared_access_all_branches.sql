-- AU · Acceso compartido entre sucursales para todos los miembros activos.
-- Ejecutar después de 001_phase1_purchases.sql.
-- La autenticación individual se conserva; el aislamiento entre organizaciones también.

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
    where b.id = target_branch
      and b.is_active = true
  );
$$;

revoke all on function public.can_access_branch(uuid) from public, anon;
grant execute on function public.can_access_branch(uuid) to authenticated;

-- Todos los miembros activos pueden ver todas las sucursales de su organización.
drop policy if exists branches_read_org on public.branches;
create policy branches_read_org on public.branches
for select to authenticated
using (public.is_org_member(organization_id));

-- Los perfiles de ambos administradores se pueden consultar dentro de la organización.
drop policy if exists profiles_read_self_or_managers on public.user_profiles;
create policy profiles_read_self_or_managers on public.user_profiles
for select to authenticated
using (
  user_id = (select auth.uid())
  or public.has_org_role(organization_id, array['owner','admin','manager'])
);

-- Nota: para que las dos cuentas tengan idénticos permisos administrativos,
-- ambas deben tener role='admin' en user_profiles y estar activas.

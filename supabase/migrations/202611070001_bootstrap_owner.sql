do $$
declare
  target_user_id uuid;
  target_organization_id constant uuid := '00000000-0000-4000-8000-000000000001';
begin
  select id
    into target_user_id
    from auth.users
   where lower(email) = lower('dbsuarez@gmail.com')
   limit 1;

  if target_user_id is null then
    raise exception 'Cannot bootstrap owner: Auth user dbsuarez@gmail.com does not exist';
  end if;

  insert into public.organizations (id, name)
  values (target_organization_id, 'Lending Manager')
  on conflict (id) do nothing;

  insert into public.organization_members (
    organization_id,
    user_id,
    role,
    status
  )
  values (
    target_organization_id,
    target_user_id,
    'owner',
    'active'
  )
  on conflict (organization_id, user_id) do update
    set role = excluded.role,
        status = excluded.status;
end
$$;

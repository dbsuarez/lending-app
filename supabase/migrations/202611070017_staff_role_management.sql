create or replace function public.set_organization_member_role(
  p_organization_id uuid,
  p_user_id uuid,
  p_role public.app_role
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_current public.app_role;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  if not public.has_org_role(p_organization_id, array['owner']::public.app_role[]) then
    raise exception 'Owner access required';
  end if;
  select role into v_current from public.organization_members
  where organization_id = p_organization_id and user_id = p_user_id and status = 'active' for update;
  if not found then raise exception 'Active organization member not found'; end if;
  if v_current = 'owner' and p_role <> 'owner' and (
    select count(*) from public.organization_members
    where organization_id = p_organization_id and status = 'active' and role = 'owner'
  ) <= 1 then raise exception 'The last owner cannot be demoted'; end if;
  update public.organization_members set role = p_role
  where organization_id = p_organization_id and user_id = p_user_id;
  insert into public.audit_events (organization_id, actor_id, action, record_type, record_id, payload)
  values (p_organization_id, auth.uid(), 'member_role_changed', 'organization_member', p_user_id,
    jsonb_build_object('previous_role', v_current, 'new_role', p_role));
end;
$$;

revoke all on function public.set_organization_member_role(uuid, uuid, public.app_role) from public;
grant execute on function public.set_organization_member_role(uuid, uuid, public.app_role) to authenticated;

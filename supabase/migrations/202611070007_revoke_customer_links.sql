create or replace function public.revoke_loan_share_link(
  p_link_id uuid
) returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor_id uuid := auth.uid();
  target_link public.loan_share_links%rowtype;
begin
  if actor_id is null then raise exception 'Authentication is required'; end if;
  select * into target_link from public.loan_share_links where id = p_link_id for update;
  if target_link.id is null then raise exception 'Link was not found'; end if;
  if not public.has_org_role(target_link.organization_id, array['owner','manager']::public.app_role[]) then
    raise exception 'Owner or manager access is required';
  end if;
  if target_link.revoked_at is null then
    update public.loan_share_links set revoked_at = now() where id = target_link.id;
    insert into public.audit_events (organization_id, actor_id, action, record_type, record_id, payload)
    values (target_link.organization_id, actor_id, 'loan_share_link_revoked', 'loan_share_link', target_link.id,
      jsonb_build_object('loan_id', target_link.loan_id));
  end if;
  return target_link.id;
end
$$;

revoke all on function public.revoke_loan_share_link(uuid) from public;
grant execute on function public.revoke_loan_share_link(uuid) to authenticated;

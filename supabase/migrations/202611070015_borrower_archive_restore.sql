create or replace function public.set_borrower_archived(
  p_borrower_id uuid,
  p_archived boolean
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_borrower public.borrowers%rowtype;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  select * into v_borrower from public.borrowers where id = p_borrower_id for update;
  if not found then raise exception 'Borrower not found'; end if;
  if not public.has_org_role(
    v_borrower.organization_id,
    array['owner', 'manager', 'collector']::public.app_role[]
  ) then raise exception 'Borrower write access required'; end if;
  update public.borrowers set archived_at = case when p_archived then now() else null end, updated_at = now()
  where id = p_borrower_id;
  insert into public.audit_events (organization_id, actor_id, action, record_type, record_id, payload)
  values (v_borrower.organization_id, auth.uid(), case when p_archived then 'borrower_archived' else 'borrower_restored' end,
    'borrower', p_borrower_id, '{}'::jsonb);
end;
$$;

revoke all on function public.set_borrower_archived(uuid, boolean) from public;
grant execute on function public.set_borrower_archived(uuid, boolean) to authenticated;

create or replace function public.cancel_loan_draft(
  p_loan_id uuid,
  p_reason text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_loan public.loans%rowtype;
  v_reason text := btrim(coalesce(p_reason, ''));
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;

  if char_length(v_reason) < 3 then
    raise exception 'A cancellation reason is required';
  end if;

  select * into v_loan
  from public.loans
  where id = p_loan_id
  for update;

  if not found then
    raise exception 'Loan not found';
  end if;

  if not public.has_org_role(
    v_loan.organization_id,
    array['owner', 'manager']::public.app_role[]
  ) then
    raise exception 'Owner or manager access required';
  end if;

  if v_loan.status <> 'draft' then
    raise exception 'Only draft loans can be cancelled';
  end if;

  update public.loans
  set status = 'cancelled'
  where id = p_loan_id;

  insert into public.audit_events (
    organization_id, actor_user_id, entity_type, entity_id, action, details
  ) values (
    v_loan.organization_id,
    auth.uid(),
    'loan',
    p_loan_id,
    'loan_draft_cancelled',
    jsonb_build_object('reason', v_reason)
  );
end;
$$;

revoke all on function public.cancel_loan_draft(uuid, text) from public;
grant execute on function public.cancel_loan_draft(uuid, text) to authenticated;

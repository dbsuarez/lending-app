alter table public.collection_activities add column if not exists client_operation_id uuid;
create unique index if not exists collection_activities_org_operation_idx
  on public.collection_activities (organization_id, client_operation_id)
  where client_operation_id is not null;

drop function if exists public.record_collection_activity(uuid, text, text, text, date, bigint);
create or replace function public.record_collection_activity(
  p_loan_id uuid,
  p_activity_type text,
  p_outcome text,
  p_notes text default '',
  p_promised_on date default null,
  p_promised_amount_centavos bigint default null,
  p_client_operation_id uuid default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_loan public.loans%rowtype;
  v_id uuid;
  v_type text := lower(btrim(coalesce(p_activity_type, '')));
  v_outcome text := btrim(coalesce(p_outcome, ''));
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  select * into v_loan from public.loans where id = p_loan_id;
  if not found then raise exception 'Loan not found'; end if;
  if not public.has_org_role(v_loan.organization_id, array['owner', 'manager', 'collector']::public.app_role[]) then
    raise exception 'Collection access required';
  end if;
  if p_client_operation_id is not null then
    select id into v_id from public.collection_activities
    where organization_id = v_loan.organization_id and client_operation_id = p_client_operation_id;
    if found then return v_id; end if;
  end if;
  if v_type not in ('call', 'sms', 'visit', 'email', 'promise') then raise exception 'Unsupported activity type'; end if;
  if char_length(v_outcome) < 2 then raise exception 'Outcome is required'; end if;
  if v_type = 'promise' and (p_promised_on is null or coalesce(p_promised_amount_centavos, 0) <= 0) then
    raise exception 'Promise date and amount are required';
  end if;
  insert into public.collection_activities (
    organization_id, loan_id, activity_type, outcome, notes, promised_on,
    promised_amount_centavos, created_by, client_operation_id
  ) values (
    v_loan.organization_id, p_loan_id, v_type, v_outcome, btrim(coalesce(p_notes, '')),
    case when v_type = 'promise' then p_promised_on end,
    case when v_type = 'promise' then p_promised_amount_centavos end,
    auth.uid(), p_client_operation_id
  ) returning id into v_id;
  insert into public.audit_events (organization_id, actor_id, action, record_type, record_id, payload)
  values (v_loan.organization_id, auth.uid(), 'collection_activity_recorded', 'collection_activity', v_id,
    jsonb_build_object('loan_id', p_loan_id, 'type', v_type, 'outcome', v_outcome));
  return v_id;
end;
$$;

revoke all on function public.record_collection_activity(uuid, text, text, text, date, bigint, uuid) from public;
grant execute on function public.record_collection_activity(uuid, text, text, text, date, bigint, uuid) to authenticated;

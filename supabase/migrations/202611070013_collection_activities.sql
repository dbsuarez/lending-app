create table public.collection_activities (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id),
  loan_id uuid not null references public.loans(id),
  activity_type text not null check (activity_type in ('call', 'sms', 'visit', 'email', 'promise')),
  outcome text not null,
  notes text not null default '',
  promised_on date,
  promised_amount_centavos bigint check (promised_amount_centavos is null or promised_amount_centavos > 0),
  contacted_at timestamptz not null default now(),
  created_by uuid not null references auth.users(id),
  created_at timestamptz not null default now(),
  check (
    (activity_type = 'promise' and promised_on is not null and promised_amount_centavos is not null)
    or
    (activity_type <> 'promise' and promised_on is null and promised_amount_centavos is null)
  )
);

create index collection_activities_org_contacted_idx
  on public.collection_activities (organization_id, contacted_at desc);
create index collection_activities_loan_contacted_idx
  on public.collection_activities (loan_id, contacted_at desc);

alter table public.collection_activities enable row level security;
create policy members_read_collection_activities
  on public.collection_activities for select
  using (public.is_org_member(organization_id));

create or replace function public.record_collection_activity(
  p_loan_id uuid,
  p_activity_type text,
  p_outcome text,
  p_notes text default '',
  p_promised_on date default null,
  p_promised_amount_centavos bigint default null
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
  if not public.has_org_role(
    v_loan.organization_id,
    array['owner', 'manager', 'collector']::public.app_role[]
  ) then
    raise exception 'Collection access required';
  end if;
  if v_type not in ('call', 'sms', 'visit', 'email', 'promise') then
    raise exception 'Unsupported activity type';
  end if;
  if char_length(v_outcome) < 2 then raise exception 'Outcome is required'; end if;
  if v_type = 'promise' and (p_promised_on is null or coalesce(p_promised_amount_centavos, 0) <= 0) then
    raise exception 'Promise date and amount are required';
  end if;

  insert into public.collection_activities (
    organization_id, loan_id, activity_type, outcome, notes,
    promised_on, promised_amount_centavos, created_by
  ) values (
    v_loan.organization_id, p_loan_id, v_type, v_outcome, btrim(coalesce(p_notes, '')),
    case when v_type = 'promise' then p_promised_on end,
    case when v_type = 'promise' then p_promised_amount_centavos end,
    auth.uid()
  ) returning id into v_id;

  insert into public.audit_events (
    organization_id, actor_id, action, record_type, record_id, payload
  ) values (
    v_loan.organization_id, auth.uid(), 'collection_activity_recorded',
    'collection_activity', v_id,
    jsonb_build_object('loan_id', p_loan_id, 'type', v_type, 'outcome', v_outcome)
  );
  return v_id;
end;
$$;

revoke all on function public.record_collection_activity(uuid, text, text, text, date, bigint) from public;
grant execute on function public.record_collection_activity(uuid, text, text, text, date, bigint) to authenticated;

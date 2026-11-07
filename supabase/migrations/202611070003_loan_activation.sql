create table public.loan_disbursements (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations,
  loan_id uuid not null references public.loans,
  amount_centavos bigint not null check (amount_centavos > 0),
  disbursed_on date not null,
  method text not null check (length(trim(method)) > 0),
  reference text,
  client_operation_id uuid not null,
  created_by uuid not null references auth.users,
  created_at timestamptz not null default now(),
  unique (organization_id, client_operation_id),
  unique (loan_id)
);

create index loan_disbursements_org_date_idx
  on public.loan_disbursements (organization_id, disbursed_on);

alter table public.loan_disbursements enable row level security;

create policy members_read_loan_disbursements
  on public.loan_disbursements
  for select
  using (public.is_org_member(organization_id));

drop policy if exists managers_add_loans on public.loans;
drop policy if exists managers_update_loans on public.loans;

create or replace function public.activate_loan(
  p_loan_id uuid,
  p_disbursed_on date,
  p_method text,
  p_reference text,
  p_client_operation_id uuid
) returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor_id uuid := auth.uid();
  target_loan public.loans%rowtype;
  existing_disbursement_id uuid;
  new_disbursement_id uuid;
begin
  if actor_id is null then
    raise exception 'Authentication is required';
  end if;

  select *
    into target_loan
    from public.loans
   where id = p_loan_id
   for update;

  if target_loan.id is null then
    raise exception 'Loan was not found';
  end if;

  if not public.has_org_role(
    target_loan.organization_id,
    array['owner', 'manager']::public.app_role[]
  ) then
    raise exception 'Owner or manager access is required';
  end if;

  select id
    into existing_disbursement_id
    from public.loan_disbursements
   where organization_id = target_loan.organization_id
     and client_operation_id = p_client_operation_id;
  if existing_disbursement_id is not null then
    return existing_disbursement_id;
  end if;

  if target_loan.status <> 'draft' then
    raise exception 'Only a draft loan can be activated';
  end if;

  if p_disbursed_on is null
     or length(trim(coalesce(p_method, ''))) = 0
     or p_client_operation_id is null then
    raise exception 'Complete disbursement details are required';
  end if;

  insert into public.loan_disbursements (
    organization_id,
    loan_id,
    amount_centavos,
    disbursed_on,
    method,
    reference,
    client_operation_id,
    created_by
  ) values (
    target_loan.organization_id,
    target_loan.id,
    target_loan.principal_centavos,
    p_disbursed_on,
    trim(p_method),
    nullif(trim(coalesce(p_reference, '')), ''),
    p_client_operation_id,
    actor_id
  ) returning id into new_disbursement_id;

  update public.loans
     set status = 'active',
         terms_snapshot = target_loan.terms_snapshot || jsonb_build_object(
           'confirmed_at', now(),
           'confirmed_by', actor_id
         )
   where id = target_loan.id;

  insert into public.audit_events (
    organization_id,
    actor_id,
    action,
    record_type,
    record_id,
    payload
  ) values (
    target_loan.organization_id,
    actor_id,
    'loan_activated',
    'loan',
    target_loan.id,
    jsonb_build_object(
      'disbursement_id', new_disbursement_id,
      'client_operation_id', p_client_operation_id
    )
  );

  return new_disbursement_id;
end
$$;

revoke all on function public.activate_loan(
  uuid, date, text, text, uuid
) from public;
grant execute on function public.activate_loan(
  uuid, date, text, text, uuid
) to authenticated;

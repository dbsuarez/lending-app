alter table public.loans
  add column if not exists client_operation_id uuid;

create unique index if not exists loans_org_client_operation_idx
  on public.loans (organization_id, client_operation_id)
  where client_operation_id is not null;

create or replace function public.create_loan_draft(
  p_organization_id uuid,
  p_borrower_id uuid,
  p_principal_centavos bigint,
  p_monthly_rate_basis_points integer,
  p_term_months integer,
  p_first_due_date date,
  p_payday_pattern integer[],
  p_installments jsonb,
  p_client_operation_id uuid
) returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor_id uuid := auth.uid();
  new_loan_id uuid;
  expected_interest bigint;
  expected_total bigint;
  supplied_total bigint;
  supplied_principal bigint;
  supplied_interest bigint;
  installment_count integer;
begin
  if actor_id is null then
    raise exception 'Authentication is required';
  end if;

  if not public.has_org_role(
    p_organization_id,
    array['owner', 'manager']::public.app_role[]
  ) then
    raise exception 'Owner or manager access is required';
  end if;

  if not exists (
    select 1
      from public.borrowers b
     where b.id = p_borrower_id
       and b.organization_id = p_organization_id
       and b.archived_at is null
  ) then
    raise exception 'Borrower is unavailable for this organization';
  end if;

  if p_principal_centavos <= 0
     or p_monthly_rate_basis_points < 0
     or p_term_months <= 0
     or p_first_due_date is null
     or coalesce(array_length(p_payday_pattern, 1), 0) = 0
     or p_client_operation_id is null then
    raise exception 'Invalid loan terms';
  end if;

  select l.id
    into new_loan_id
    from public.loans l
   where l.organization_id = p_organization_id
     and l.client_operation_id = p_client_operation_id;
  if new_loan_id is not null then
    return new_loan_id;
  end if;

  expected_interest := round(
    (p_principal_centavos::numeric * p_monthly_rate_basis_points * p_term_months)
      / 10000
  )::bigint;
  expected_total := p_principal_centavos + expected_interest;

  select
    count(*),
    coalesce(sum(x.scheduled_centavos), 0),
    coalesce(sum(x.principal_centavos), 0),
    coalesce(sum(x.interest_centavos), 0)
  into
    installment_count,
    supplied_total,
    supplied_principal,
    supplied_interest
  from jsonb_to_recordset(p_installments) as x(
    sequence integer,
    due_date date,
    principal_centavos bigint,
    interest_centavos bigint,
    scheduled_centavos bigint
  );

  if installment_count = 0
     or supplied_total <> expected_total
     or supplied_principal <> p_principal_centavos
     or supplied_interest <> expected_interest
     or exists (
       select 1
       from jsonb_to_recordset(p_installments) as x(
         sequence integer,
         due_date date,
         principal_centavos bigint,
         interest_centavos bigint,
         scheduled_centavos bigint
       )
       where x.sequence <= 0
          or x.due_date < p_first_due_date
          or x.principal_centavos < 0
          or x.interest_centavos < 0
          or x.scheduled_centavos <> x.principal_centavos + x.interest_centavos
     ) then
    raise exception 'Installment schedule does not match authoritative totals';
  end if;

  insert into public.loans (
    organization_id,
    borrower_id,
    principal_centavos,
    monthly_rate_basis_points,
    term_months,
    total_centavos,
    status,
    terms_snapshot,
    created_by,
    client_operation_id
  ) values (
    p_organization_id,
    p_borrower_id,
    p_principal_centavos,
    p_monthly_rate_basis_points,
    p_term_months,
    expected_total,
    'draft',
    jsonb_build_object(
      'calculation', 'flat_monthly',
      'first_due_date', p_first_due_date,
      'payday_pattern', p_payday_pattern,
      'penalty_policy', 'none'
    ),
    actor_id,
    p_client_operation_id
  ) returning id into new_loan_id;

  insert into public.installments (
    organization_id,
    loan_id,
    sequence,
    due_date,
    principal_centavos,
    interest_centavos,
    scheduled_centavos
  )
  select
    p_organization_id,
    new_loan_id,
    x.sequence,
    x.due_date,
    x.principal_centavos,
    x.interest_centavos,
    x.scheduled_centavos
  from jsonb_to_recordset(p_installments) as x(
    sequence integer,
    due_date date,
    principal_centavos bigint,
    interest_centavos bigint,
    scheduled_centavos bigint
  );

  insert into public.audit_events (
    organization_id,
    actor_id,
    action,
    record_type,
    record_id,
    payload
  ) values (
    p_organization_id,
    actor_id,
    'loan_draft_created',
    'loan',
    new_loan_id,
    jsonb_build_object('client_operation_id', p_client_operation_id)
  );

  return new_loan_id;
end
$$;

revoke all on function public.create_loan_draft(
  uuid, uuid, bigint, integer, integer, date, integer[], jsonb, uuid
) from public;
grant execute on function public.create_loan_draft(
  uuid, uuid, bigint, integer, integer, date, integer[], jsonb, uuid
) to authenticated;

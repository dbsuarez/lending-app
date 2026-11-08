-- Loan corrections.
--
--   correct_loan             Edit a draft, or correct an active loan that has
--                            no payments yet: borrower, principal, rate, term,
--                            first due date, payday pattern (schedule is
--                            rebuilt) and, for active loans, the money-release
--                            record (old one voided, new one recorded).
--   correct_disbursement     Fix the release date, method or reference of a
--                            disbursed loan (payments or not). The amount
--                            always equals the principal and is not editable.
--   undo_loan_correction     Undo either of the above, by the same person,
--                            while nothing changed after it.
--
-- Every correction is a loan_amendments row (previous and new values, reason,
-- who) plus an audit event. Loans with payments get "Correct terms" later.

alter table public.loan_amendments
  drop constraint if exists loan_amendments_amendment_type_check;
alter table public.loan_amendments
  add constraint loan_amendments_amendment_type_check
  check (amendment_type in ('due_date', 'refinance', 'correction', 'disbursement'));

-- Fails unless the schedule matches the terms (same rules as create_loan_draft).
-- Returns the authoritative total.
create or replace function public._assert_loan_schedule(
  p_principal_centavos bigint, p_monthly_rate_basis_points integer,
  p_term_months integer, p_first_due_date date, p_payday_pattern integer[],
  p_installments jsonb
) returns bigint language plpgsql immutable set search_path = '' as $$
declare
  v_interest bigint; v_total bigint; v_count integer;
  v_sum bigint; v_principal bigint; v_sum_interest bigint;
begin
  if p_principal_centavos is null or p_principal_centavos <= 0
     or p_monthly_rate_basis_points is null or p_monthly_rate_basis_points < 0
     or p_term_months is null or p_term_months <= 0
     or p_first_due_date is null
     or coalesce(array_length(p_payday_pattern, 1), 0) = 0 then
    raise exception 'Invalid loan terms';
  end if;
  v_interest := round((p_principal_centavos::numeric * p_monthly_rate_basis_points * p_term_months) / 10000)::bigint;
  v_total := p_principal_centavos + v_interest;
  select count(*), coalesce(sum(x.scheduled_centavos), 0), coalesce(sum(x.principal_centavos), 0),
         coalesce(sum(x.interest_centavos), 0)
    into v_count, v_sum, v_principal, v_sum_interest
    from jsonb_to_recordset(p_installments) as x(
      sequence integer, due_date date, principal_centavos bigint,
      interest_centavos bigint, scheduled_centavos bigint);
  if v_count = 0 or v_sum <> v_total or v_principal <> p_principal_centavos
     or v_sum_interest <> v_interest
     or exists (
       select 1 from jsonb_to_recordset(p_installments) as x(
         sequence integer, due_date date, principal_centavos bigint,
         interest_centavos bigint, scheduled_centavos bigint)
       where x.sequence <= 0 or x.due_date is null or x.due_date < p_first_due_date
          or x.principal_centavos < 0 or x.interest_centavos < 0
          or x.scheduled_centavos <> x.principal_centavos + x.interest_centavos) then
    raise exception 'Installment schedule does not match authoritative totals';
  end if;
  return v_total;
end $$;
revoke all on function public._assert_loan_schedule(bigint, integer, integer, date, integer[], jsonb) from public;

-- Fails when money has moved on the loan (any pending/verified payment, or
-- any allocation left on its installments).
create or replace function public._assert_no_payments(p_loan_id uuid)
returns void language plpgsql security definer set search_path = '' as $$
begin
  if exists (select 1 from public.payments where loan_id = p_loan_id and status in ('pending', 'verified'))
     or exists (select 1 from public.payment_allocations pa
                join public.installments i on i.id = pa.installment_id
                where i.loan_id = p_loan_id) then
    raise exception 'This loan has payments. Reverse or reject them first, or use Refinance';
  end if;
end $$;
revoke all on function public._assert_no_payments(uuid) from public;

create or replace function public.correct_loan(
  p_loan_id uuid,
  p_borrower_id uuid,
  p_principal_centavos bigint,
  p_monthly_rate_basis_points integer,
  p_term_months integer,
  p_first_due_date date,
  p_payday_pattern integer[],
  p_installments jsonb,
  p_disbursed_on date,
  p_method text,
  p_reference text,
  p_reason text,
  p_client_operation_id uuid
) returns uuid
language plpgsql security definer set search_path = '' as $$
declare
  v_loan public.loans%rowtype;
  v_disbursement public.loan_disbursements%rowtype;
  v_id uuid;
  v_total bigint;
  v_reason text := btrim(coalesce(p_reason, ''));
  v_previous jsonb;
  v_new_disbursement uuid;
  v_disbursed_on date;
  v_method text;
begin
  if auth.uid() is null then raise exception 'Authentication is required'; end if;
  if p_client_operation_id is null then raise exception 'Invalid request'; end if;
  select * into v_loan from public.loans where id = p_loan_id for update;
  if v_loan.id is null then raise exception 'Loan was not found'; end if;
  if not public.has_org_role(v_loan.organization_id, array['owner','manager']::public.app_role[]) then
    raise exception 'Owner or manager access is required';
  end if;
  select id into v_id from public.loan_amendments
   where organization_id = v_loan.organization_id and client_operation_id = p_client_operation_id;
  if v_id is not null then return v_id; end if;

  if v_loan.status = 'active' then
    if length(v_reason) < 3 then raise exception 'A clear reason is required'; end if;
    perform public._assert_no_payments(p_loan_id);
    select * into v_disbursement from public.loan_disbursements
     where loan_id = p_loan_id and voided_at is null for update;
    if v_disbursement.id is null then raise exception 'No disbursement was found for this loan'; end if;
    v_disbursed_on := coalesce(p_disbursed_on, v_disbursement.disbursed_on);
    v_method := coalesce(nullif(btrim(coalesce(p_method, '')), ''), v_disbursement.method);
    if v_disbursed_on > current_date + 1 then raise exception 'The release date cannot be in the future'; end if;
  elsif v_loan.status = 'draft' then
    if length(v_reason) < 3 then v_reason := 'Draft edited'; end if;
  else
    raise exception 'Only a draft or an active loan can be edited';
  end if;

  if not exists (select 1 from public.borrowers b where b.id = p_borrower_id
                 and b.organization_id = v_loan.organization_id and b.archived_at is null) then
    raise exception 'Borrower is unavailable for this organization';
  end if;
  v_total := public._assert_loan_schedule(p_principal_centavos, p_monthly_rate_basis_points,
    p_term_months, p_first_due_date, p_payday_pattern, p_installments);

  v_previous := jsonb_build_object(
    'status', v_loan.status,
    'borrower_id', v_loan.borrower_id,
    'principal_centavos', v_loan.principal_centavos,
    'monthly_rate_basis_points', v_loan.monthly_rate_basis_points,
    'term_months', v_loan.term_months,
    'total_centavos', v_loan.total_centavos,
    'first_due_date', v_loan.terms_snapshot->'first_due_date',
    'payday_pattern', v_loan.terms_snapshot->'payday_pattern',
    'disbursement_id', v_disbursement.id,
    'disbursed_on', v_disbursement.disbursed_on,
    'method', v_disbursement.method,
    'reference', v_disbursement.reference,
    'installments', (select coalesce(jsonb_agg(jsonb_build_object(
        'sequence', i.sequence, 'due_date', i.due_date,
        'principal_centavos', i.principal_centavos, 'interest_centavos', i.interest_centavos,
        'scheduled_centavos', i.scheduled_centavos) order by i.sequence), '[]'::jsonb)
      from public.installments i where i.loan_id = p_loan_id));

  delete from public.installments where loan_id = p_loan_id;
  insert into public.installments (organization_id, loan_id, sequence, due_date,
    principal_centavos, interest_centavos, scheduled_centavos)
  select v_loan.organization_id, p_loan_id, x.sequence, x.due_date,
         x.principal_centavos, x.interest_centavos, x.scheduled_centavos
    from jsonb_to_recordset(p_installments) as x(sequence integer, due_date date,
      principal_centavos bigint, interest_centavos bigint, scheduled_centavos bigint);

  update public.loans
     set borrower_id = p_borrower_id,
         principal_centavos = p_principal_centavos,
         monthly_rate_basis_points = p_monthly_rate_basis_points,
         term_months = p_term_months,
         total_centavos = v_total,
         terms_snapshot = terms_snapshot || jsonb_build_object(
           'first_due_date', p_first_due_date, 'payday_pattern', p_payday_pattern)
   where id = p_loan_id;

  if v_loan.status = 'active' then
    update public.loan_disbursements set voided_at = now(), voided_by = auth.uid()
     where id = v_disbursement.id;
    insert into public.loan_disbursements (organization_id, loan_id, amount_centavos,
      disbursed_on, method, reference, client_operation_id, created_by)
    values (v_loan.organization_id, p_loan_id, p_principal_centavos, v_disbursed_on, v_method,
      nullif(btrim(coalesce(p_reference, '')), ''), p_client_operation_id, auth.uid())
    returning id into v_new_disbursement;
  end if;

  insert into public.loan_amendments (organization_id, loan_id, amendment_type, reason,
    consent_date, previous_values, new_values, client_operation_id, created_by)
  values (v_loan.organization_id, p_loan_id, 'correction', v_reason, current_date, v_previous,
    jsonb_build_object(
      'borrower_id', p_borrower_id,
      'principal_centavos', p_principal_centavos,
      'monthly_rate_basis_points', p_monthly_rate_basis_points,
      'term_months', p_term_months,
      'total_centavos', v_total,
      'first_due_date', p_first_due_date,
      'payday_pattern', to_jsonb(p_payday_pattern),
      'disbursement_id', v_new_disbursement,
      'disbursed_on', v_disbursed_on,
      'method', v_method,
      'reference', nullif(btrim(coalesce(p_reference, '')), '')),
    p_client_operation_id, auth.uid())
  returning id into v_id;

  insert into public.audit_events (organization_id, actor_id, action, record_type, record_id, payload)
  values (v_loan.organization_id, auth.uid(),
    case when v_loan.status = 'draft' then 'loan_draft_edited' else 'loan_corrected' end,
    'loan', p_loan_id,
    jsonb_build_object('amendment_id', v_id, 'reason', v_reason,
      'previous_principal_centavos', v_loan.principal_centavos, 'new_principal_centavos', p_principal_centavos,
      'previous_rate_basis_points', v_loan.monthly_rate_basis_points, 'new_rate_basis_points', p_monthly_rate_basis_points,
      'previous_term_months', v_loan.term_months, 'new_term_months', p_term_months,
      'borrower_changed', v_loan.borrower_id <> p_borrower_id));
  return v_id;
end $$;
revoke all on function public.correct_loan(uuid, uuid, bigint, integer, integer, date, integer[], jsonb, date, text, text, text, uuid) from public;
grant execute on function public.correct_loan(uuid, uuid, bigint, integer, integer, date, integer[], jsonb, date, text, text, text, uuid) to authenticated;

create or replace function public.correct_disbursement(
  p_loan_id uuid, p_disbursed_on date, p_method text, p_reference text,
  p_reason text, p_client_operation_id uuid
) returns uuid
language plpgsql security definer set search_path = '' as $$
declare
  v_loan public.loans%rowtype;
  v_disbursement public.loan_disbursements%rowtype;
  v_id uuid;
  v_method text;
  v_reference text;
begin
  if auth.uid() is null then raise exception 'Authentication is required'; end if;
  if p_client_operation_id is null then raise exception 'Invalid request'; end if;
  select * into v_loan from public.loans where id = p_loan_id for update;
  if v_loan.id is null then raise exception 'Loan was not found'; end if;
  if not public.has_org_role(v_loan.organization_id, array['owner','manager']::public.app_role[]) then
    raise exception 'Owner or manager access is required';
  end if;
  select id into v_id from public.loan_amendments
   where organization_id = v_loan.organization_id and client_operation_id = p_client_operation_id;
  if v_id is not null then return v_id; end if;
  if length(btrim(coalesce(p_reason, ''))) < 3 then raise exception 'A clear reason is required'; end if;
  select * into v_disbursement from public.loan_disbursements
   where loan_id = p_loan_id and voided_at is null for update;
  if v_disbursement.id is null then raise exception 'This loan has no money release to correct'; end if;
  if p_disbursed_on is null or p_disbursed_on > current_date + 1 then
    raise exception 'The release date cannot be in the future';
  end if;
  v_method := coalesce(nullif(btrim(coalesce(p_method, '')), ''), v_disbursement.method);
  v_reference := nullif(btrim(coalesce(p_reference, '')), '');
  if p_disbursed_on = v_disbursement.disbursed_on and v_method = v_disbursement.method
     and v_reference is not distinct from v_disbursement.reference then
    raise exception 'Nothing was changed';
  end if;

  insert into public.loan_amendments (organization_id, loan_id, amendment_type, reason,
    consent_date, previous_values, new_values, client_operation_id, created_by)
  values (v_loan.organization_id, p_loan_id, 'disbursement', btrim(p_reason), current_date,
    jsonb_build_object('disbursement_id', v_disbursement.id, 'disbursed_on', v_disbursement.disbursed_on,
      'method', v_disbursement.method, 'reference', v_disbursement.reference),
    jsonb_build_object('disbursement_id', v_disbursement.id, 'disbursed_on', p_disbursed_on,
      'method', v_method, 'reference', v_reference),
    p_client_operation_id, auth.uid())
  returning id into v_id;

  update public.loan_disbursements
     set disbursed_on = p_disbursed_on, method = v_method, reference = v_reference
   where id = v_disbursement.id;

  insert into public.audit_events (organization_id, actor_id, action, record_type, record_id, payload)
  values (v_loan.organization_id, auth.uid(), 'loan_disbursement_corrected', 'loan', p_loan_id,
    jsonb_build_object('amendment_id', v_id, 'reason', btrim(p_reason),
      'previous_disbursed_on', v_disbursement.disbursed_on, 'new_disbursed_on', p_disbursed_on,
      'previous_method', v_disbursement.method, 'new_method', v_method,
      'previous_reference', v_disbursement.reference, 'new_reference', v_reference));
  return v_id;
end $$;
revoke all on function public.correct_disbursement(uuid, date, text, text, text, uuid) from public;
grant execute on function public.correct_disbursement(uuid, date, text, text, text, uuid) to authenticated;

create or replace function public.undo_loan_correction(p_amendment_id uuid)
returns uuid
language plpgsql security definer set search_path = '' as $$
declare
  v_amendment public.loan_amendments%rowtype;
  v_loan public.loans%rowtype;
  v_prev jsonb;
  v_new jsonb;
  v_disbursement public.loan_disbursements%rowtype;
begin
  if auth.uid() is null then raise exception 'Authentication is required'; end if;
  select * into v_amendment from public.loan_amendments where id = p_amendment_id for update;
  if v_amendment.id is null or v_amendment.amendment_type not in ('correction', 'disbursement') then
    raise exception 'Correction was not found';
  end if;
  if v_amendment.undone_at is not null then raise exception 'This correction was already undone'; end if;
  if v_amendment.created_by <> auth.uid() then
    raise exception 'Only the person who made this correction can undo it';
  end if;
  select * into v_loan from public.loans where id = v_amendment.loan_id for update;
  if exists (select 1 from public.loan_amendments a where a.loan_id = v_amendment.loan_id
             and a.undone_at is null and a.created_at > v_amendment.created_at) then
    raise exception 'A later change exists on this loan; undo is no longer available';
  end if;
  v_prev := v_amendment.previous_values;
  v_new := v_amendment.new_values;

  if v_amendment.amendment_type = 'disbursement' then
    select * into v_disbursement from public.loan_disbursements
     where id = (v_new->>'disbursement_id')::uuid for update;
    if v_disbursement.id is null or v_disbursement.voided_at is not null
       or v_disbursement.disbursed_on <> (v_new->>'disbursed_on')::date
       or v_disbursement.method <> v_new->>'method'
       or v_disbursement.reference is distinct from v_new->>'reference' then
      raise exception 'The money release changed after this correction; undo is no longer available';
    end if;
    update public.loan_disbursements
       set disbursed_on = (v_prev->>'disbursed_on')::date, method = v_prev->>'method',
           reference = v_prev->>'reference'
     where id = v_disbursement.id;
  else
    if v_loan.status::text <> v_prev->>'status' then
      raise exception 'The loan changed after this correction; undo is no longer available';
    end if;
    if v_loan.status = 'active' then
      perform public._assert_no_payments(v_loan.id);
    end if;
    delete from public.installments where loan_id = v_loan.id;
    insert into public.installments (organization_id, loan_id, sequence, due_date,
      principal_centavos, interest_centavos, scheduled_centavos)
    select v_loan.organization_id, v_loan.id, x.sequence, x.due_date,
           x.principal_centavos, x.interest_centavos, x.scheduled_centavos
      from jsonb_to_recordset(v_prev->'installments') as x(sequence integer, due_date date,
        principal_centavos bigint, interest_centavos bigint, scheduled_centavos bigint);
    update public.loans
       set borrower_id = (v_prev->>'borrower_id')::uuid,
           principal_centavos = (v_prev->>'principal_centavos')::bigint,
           monthly_rate_basis_points = (v_prev->>'monthly_rate_basis_points')::integer,
           term_months = (v_prev->>'term_months')::integer,
           total_centavos = (v_prev->>'total_centavos')::bigint,
           terms_snapshot = (terms_snapshot - 'first_due_date' - 'payday_pattern')
             || jsonb_strip_nulls(jsonb_build_object(
                  'first_due_date', v_prev->'first_due_date',
                  'payday_pattern', v_prev->'payday_pattern'))
     where id = v_loan.id;
    if v_loan.status = 'active' then
      update public.loan_disbursements set voided_at = now(), voided_by = auth.uid()
       where id = (v_new->>'disbursement_id')::uuid and voided_at is null;
      update public.loan_disbursements set voided_at = null, voided_by = null
       where id = (v_prev->>'disbursement_id')::uuid;
    end if;
  end if;

  update public.loan_amendments set undone_at = now(), undone_by = auth.uid()
   where id = v_amendment.id;
  insert into public.audit_events (organization_id, actor_id, action, record_type, record_id, payload)
  values (v_amendment.organization_id, auth.uid(), 'loan_correction_undone', 'loan', v_loan.id,
    jsonb_build_object('amendment_id', v_amendment.id, 'type', v_amendment.amendment_type));
  return v_amendment.id;
end $$;
revoke all on function public.undo_loan_correction(uuid) from public;
grant execute on function public.undo_loan_correction(uuid) to authenticated;

-- Draft edits are amendments too; they happen before the money release and
-- must not block undoing the release. Only amendments made after the release
-- (still in effect) block it now. Otherwise unchanged from 202611070033.
create or replace function public.undo_loan_activation(p_loan_id uuid)
returns uuid language plpgsql security definer set search_path = '' as $$
declare v_loan public.loans%rowtype; v_disbursement public.loan_disbursements%rowtype;
begin
  if auth.uid() is null then raise exception 'Authentication is required'; end if;
  select * into v_loan from public.loans where id = p_loan_id for update;
  if v_loan.id is null then raise exception 'Loan was not found'; end if;
  if v_loan.status <> 'active' then raise exception 'Only an active loan can be returned to draft'; end if;
  select * into v_disbursement from public.loan_disbursements
   where loan_id = p_loan_id and voided_at is null for update;
  if v_disbursement.id is null then raise exception 'No disbursement was found for this loan'; end if;
  if v_disbursement.created_by <> auth.uid() then
    raise exception 'Only the person who disbursed this loan can undo it';
  end if;
  if exists (select 1 from public.payments where loan_id = p_loan_id and status in ('pending', 'verified')) then
    raise exception 'Payments exist on this loan; undo is no longer available';
  end if;
  if exists (select 1 from public.loan_amendments where loan_id = p_loan_id and undone_at is null
             and created_at >= v_disbursement.created_at) then
    raise exception 'This loan was amended; undo is no longer available';
  end if;
  update public.loan_disbursements set voided_at = now(), voided_by = auth.uid()
   where id = v_disbursement.id;
  update public.loans
     set status = 'draft', terms_snapshot = terms_snapshot - 'confirmed_at' - 'confirmed_by'
   where id = p_loan_id;
  insert into public.audit_events (organization_id, actor_id, action, record_type, record_id, payload)
  values (v_loan.organization_id, auth.uid(), 'loan_activation_undone', 'loan', p_loan_id,
    jsonb_build_object('disbursement_id', v_disbursement.id));
  return p_loan_id;
end $$;
revoke all on function public.undo_loan_activation(uuid) from public;
grant execute on function public.undo_loan_activation(uuid) to authenticated;

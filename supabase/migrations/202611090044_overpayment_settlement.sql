-- Settling an overpayment (money a verified payment brought in beyond what
-- the loan needed, payments.unapplied_centavos): refunded to the borrower, or
-- kept (with a reason). Recorded on the payment itself so it travels with
-- backups and restores; the open credit is unapplied - settled.

alter table public.payments
  add column if not exists unapplied_settled_centavos bigint not null default 0,
  add column if not exists unapplied_settlement jsonb;

create or replace function public.settle_overpayment(
  p_payment_id uuid, p_kind text, p_settled_on date, p_method text, p_reference text, p_reason text
) returns void language plpgsql security definer set search_path = '' as $$
declare v_p public.payments%rowtype; v_open bigint;
begin
  if auth.uid() is null then raise exception 'Authentication is required'; end if;
  select * into v_p from public.payments where id = p_payment_id for update;
  if v_p.id is null then raise exception 'Payment was not found'; end if;
  if not public.has_org_role(v_p.organization_id, array['owner','manager']::public.app_role[]) then
    raise exception 'Owner or manager access is required';
  end if;
  if v_p.status <> 'verified' then raise exception 'Only a verified payment can be settled'; end if;
  v_open := v_p.unapplied_centavos - v_p.unapplied_settled_centavos;
  if v_open <= 0 then raise exception 'This payment has no overpayment to settle'; end if;
  if p_kind not in ('refunded', 'kept') then raise exception 'Choose refunded or kept'; end if;
  if p_settled_on is null or p_settled_on > (now() at time zone 'Asia/Manila')::date + 1 then
    raise exception 'Enter the date (not in the future)';
  end if;
  if p_kind = 'refunded' and length(btrim(coalesce(p_method, ''))) = 0 then
    raise exception 'Enter how the refund was sent';
  end if;
  if p_kind = 'kept' and length(btrim(coalesce(p_reason, ''))) < 3 then
    raise exception 'Enter a short reason for keeping it (kept in the history)';
  end if;
  update public.payments set
    unapplied_settled_centavos = v_p.unapplied_centavos,
    unapplied_settlement = jsonb_strip_nulls(jsonb_build_object(
      'kind', p_kind, 'amount_centavos', v_open, 'settled_on', p_settled_on,
      'method', nullif(btrim(coalesce(p_method, '')), ''),
      'reference', nullif(btrim(coalesce(p_reference, '')), ''),
      'reason', nullif(btrim(coalesce(p_reason, '')), ''),
      'by', auth.uid(), 'at', now()))
  where id = p_payment_id;
  insert into public.audit_events (organization_id, actor_id, action, record_type, record_id, payload)
  values (v_p.organization_id, auth.uid(), 'overpayment_settled', 'payment', p_payment_id,
    jsonb_strip_nulls(jsonb_build_object('loan_id', v_p.loan_id, 'kind', p_kind, 'amount_centavos', v_open,
      'settled_on', p_settled_on, 'method', nullif(btrim(coalesce(p_method, '')), ''),
      'reference', nullif(btrim(coalesce(p_reference, '')), ''), 'reason', nullif(btrim(coalesce(p_reason, '')), ''))));
end $$;
revoke all on function public.settle_overpayment(uuid, text, date, text, text, text) from public;
grant execute on function public.settle_overpayment(uuid, text, date, text, text, text) to authenticated;

create or replace function public.undo_overpayment_settlement(p_payment_id uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare v_p public.payments%rowtype;
begin
  if auth.uid() is null then raise exception 'Authentication is required'; end if;
  select * into v_p from public.payments where id = p_payment_id for update;
  if v_p.id is null or v_p.unapplied_settlement is null then raise exception 'Nothing to undo'; end if;
  if (v_p.unapplied_settlement->>'by')::uuid <> auth.uid() then
    raise exception 'Only the person who recorded it can undo it';
  end if;
  update public.payments set unapplied_settled_centavos = 0, unapplied_settlement = null where id = p_payment_id;
  insert into public.audit_events (organization_id, actor_id, action, record_type, record_id, payload)
  values (v_p.organization_id, auth.uid(), 'overpayment_settlement_undone', 'payment', p_payment_id,
    jsonb_build_object('loan_id', v_p.loan_id, 'previous', v_p.unapplied_settlement));
end $$;
revoke all on function public.undo_overpayment_settlement(uuid) from public;
grant execute on function public.undo_overpayment_settlement(uuid) to authenticated;

-- Single-loan restore: older backups lack the settlement columns.
-- Otherwise as 202611090043.
-- Replaces everything about a loan with the given state (null = remove it).
create or replace function public._replace_loan_state(p_loan_id uuid, p_state jsonb)
returns void language plpgsql security definer set search_path = '' as $$
declare v_exists boolean;
begin
  v_exists := exists (select 1 from public.loans where id = p_loan_id);
  if v_exists then
    delete from public.payment_allocations
     where payment_id in (select id from public.payments where loan_id = p_loan_id)
        or installment_id in (select id from public.installments where loan_id = p_loan_id);
    delete from public.payment_corrections
     where payment_id in (select id from public.payments where loan_id = p_loan_id);
    delete from public.penalty_charges where loan_id = p_loan_id;
    delete from public.payments where loan_id = p_loan_id;
    delete from public.installments where loan_id = p_loan_id;
    delete from public.loan_disbursements where loan_id = p_loan_id;
    delete from public.loan_amendments where loan_id = p_loan_id;
    delete from public.collection_activities where loan_id = p_loan_id;
    delete from public.loan_share_links where loan_id = p_loan_id;
    if p_state is null then
      if exists (select 1 from public.loan_documents where loan_id = p_loan_id) then
        raise exception 'This loan has uploaded evidence, so it cannot be removed';
      end if;
      delete from public.loans where id = p_loan_id;
      return;
    end if;
    update public.loans l set
      borrower_id = s.borrower_id, principal_centavos = s.principal_centavos,
      monthly_rate_basis_points = s.monthly_rate_basis_points, term_months = s.term_months,
      total_centavos = s.total_centavos, status = s.status, terms_snapshot = s.terms_snapshot,
      created_by = s.created_by, created_at = s.created_at,
      client_operation_id = s.client_operation_id, is_personal = s.is_personal
    from jsonb_populate_record(null::public.loans, p_state->'loan') s
    where l.id = p_loan_id;
  elsif p_state is null then
    return;
  else
    insert into public.loans select * from jsonb_populate_record(null::public.loans, p_state->'loan');
  end if;
  -- Backups from before penalties have no penalty_centavos: treat as 0.
  insert into public.installments (id, organization_id, loan_id, sequence, due_date,
      principal_centavos, interest_centavos, scheduled_centavos, penalty_centavos)
    select id, organization_id, loan_id, sequence, due_date, principal_centavos,
      interest_centavos, scheduled_centavos, coalesce(penalty_centavos, 0)
    from jsonb_populate_recordset(null::public.installments, coalesce(p_state->'installments', '[]'::jsonb));
  insert into public.loan_disbursements
    select * from jsonb_populate_recordset(null::public.loan_disbursements, coalesce(p_state->'loan_disbursements', '[]'::jsonb));
  -- Backups from before overpayment settlement have no settled amount: 0.
  insert into public.payments
    select (r).id, (r).organization_id, (r).loan_id, (r).amount_centavos, (r).received_at, (r).method,
           (r).reference, (r).status, (r).client_operation_id, (r).device_id, (r).created_by, (r).created_at,
           (r).verified_at, (r).verified_by, (r).reversed_at, (r).reversed_by, (r).reversal_reason,
           (r).unapplied_centavos, (r).late_reason,
           coalesce((r).unapplied_settled_centavos, 0), (r).unapplied_settlement
    from (select jsonb_populate_record(null::public.payments, e) r
          from jsonb_array_elements(coalesce(p_state->'payments', '[]'::jsonb)) e) x;
  insert into public.payment_allocations
    select * from jsonb_populate_recordset(null::public.payment_allocations, coalesce(p_state->'payment_allocations', '[]'::jsonb));
  insert into public.payment_corrections
    select * from jsonb_populate_recordset(null::public.payment_corrections, coalesce(p_state->'payment_corrections', '[]'::jsonb));
  insert into public.loan_amendments
    select * from jsonb_populate_recordset(null::public.loan_amendments, coalesce(p_state->'loan_amendments', '[]'::jsonb));
  insert into public.collection_activities
    select * from jsonb_populate_recordset(null::public.collection_activities, coalesce(p_state->'collection_activities', '[]'::jsonb));
  insert into public.loan_share_links
    select * from jsonb_populate_recordset(null::public.loan_share_links, coalesce(p_state->'loan_share_links', '[]'::jsonb));
  insert into public.penalty_charges
    select * from jsonb_populate_recordset(null::public.penalty_charges, coalesce(p_state->'penalty_charges', '[]'::jsonb));
end $$;
revoke all on function public._replace_loan_state(uuid, jsonb) from public;

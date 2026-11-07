-- Single-level undo for recent transactions.
--
-- Rules shared by every undo_* function:
--   * Only the person who performed the original action may undo it.
--   * The server refuses when later activity depends on the action
--     (for example, a payment recorded after a disbursement).
--   * Nothing is deleted except derived payment allocations (the same thing
--     reverse_payment already does); originals are marked voided/undone and
--     every undo writes an "*_undone" audit event.
-- The app offers undo only for the latest transaction in the session; these
-- checks keep that safe when several staff members work at the same time.

-- ---------------------------------------------------------------------------
-- Schema: mark records as voided/undone instead of deleting them.
-- ---------------------------------------------------------------------------
alter table public.loan_disbursements
  add column if not exists voided_at timestamptz,
  add column if not exists voided_by uuid references auth.users;

-- A loan can be disbursed again after an undo, so only one *active*
-- disbursement per loan is unique.
alter table public.loan_disbursements
  drop constraint if exists loan_disbursements_loan_id_key;
create unique index if not exists loan_disbursements_active_loan_idx
  on public.loan_disbursements (loan_id) where voided_at is null;

alter table public.loan_amendments
  add column if not exists undone_at timestamptz,
  add column if not exists undone_by uuid references auth.users;

alter table public.collection_activities
  add column if not exists undone_at timestamptz,
  add column if not exists undone_by uuid references auth.users;

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

-- Fails unless no other payment on the loan was verified after p_verified_at;
-- later allocations were computed on top of this payment's allocation.
create or replace function public._assert_latest_verified_payment(
  p_loan_id uuid, p_payment_id uuid, p_verified_at timestamptz
) returns void language plpgsql security definer set search_path = '' as $$
begin
  if exists (
    select 1 from public.payments p
    where p.loan_id = p_loan_id and p.id <> p_payment_id and p.status = 'verified'
      and p.verified_at > p_verified_at
  ) then
    raise exception 'A later payment was verified on this loan; undo is no longer available';
  end if;
end $$;
revoke all on function public._assert_latest_verified_payment(uuid, uuid, timestamptz) from public;

-- True when the payment is the settlement payment of an early payoff.
create or replace function public._is_early_payoff_payment(p_payment_id uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.audit_events e
    where e.action = 'loan_settled_early' and e.payload->>'payment_id' = p_payment_id::text
  );
$$;
revoke all on function public._is_early_payoff_payment(uuid) from public;

-- ---------------------------------------------------------------------------
-- Record payment (pending, or Cash which is verified immediately)
-- ---------------------------------------------------------------------------
create or replace function public.undo_payment_record(p_payment_id uuid)
returns uuid language plpgsql security definer set search_path = '' as $$
declare v_payment public.payments%rowtype;
begin
  if auth.uid() is null then raise exception 'Authentication is required'; end if;
  select * into v_payment from public.payments where id = p_payment_id for update;
  if v_payment.id is null then raise exception 'Payment was not found'; end if;
  if v_payment.created_by <> auth.uid() then
    raise exception 'Only the person who recorded this payment can undo it';
  end if;
  if public._is_early_payoff_payment(v_payment.id) then
    raise exception 'Use early payoff undo for this payment';
  end if;
  if v_payment.status not in ('pending', 'verified') then
    raise exception 'This payment can no longer be undone';
  end if;
  perform 1 from public.loans where id = v_payment.loan_id for update;
  if v_payment.status = 'verified' then
    perform public._assert_latest_verified_payment(v_payment.loan_id, v_payment.id, v_payment.verified_at);
    delete from public.payment_allocations where payment_id = v_payment.id;
    update public.loans set status = 'active' where id = v_payment.loan_id and status = 'fully_paid';
  end if;
  update public.payments set status = 'rejected', unapplied_centavos = 0 where id = v_payment.id;
  insert into public.audit_events (organization_id, actor_id, action, record_type, record_id, payload)
  values (v_payment.organization_id, auth.uid(), 'payment_record_undone', 'payment', v_payment.id,
    jsonb_build_object('loan_id', v_payment.loan_id, 'amount_centavos', v_payment.amount_centavos,
      'previous_status', v_payment.status));
  return v_payment.id;
end $$;
revoke all on function public.undo_payment_record(uuid) from public;
grant execute on function public.undo_payment_record(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- Verify payment -> back to pending
-- ---------------------------------------------------------------------------
create or replace function public.undo_payment_verification(p_payment_id uuid)
returns uuid language plpgsql security definer set search_path = '' as $$
declare v_payment public.payments%rowtype;
begin
  if auth.uid() is null then raise exception 'Authentication is required'; end if;
  select * into v_payment from public.payments where id = p_payment_id for update;
  if v_payment.id is null then raise exception 'Payment was not found'; end if;
  if v_payment.status <> 'verified' then raise exception 'Only a verified payment can be returned to pending'; end if;
  if v_payment.verified_by is distinct from auth.uid() then
    raise exception 'Only the person who verified this payment can undo it';
  end if;
  if public._is_early_payoff_payment(v_payment.id) then
    raise exception 'Use early payoff undo for this payment';
  end if;
  perform 1 from public.loans where id = v_payment.loan_id for update;
  perform public._assert_latest_verified_payment(v_payment.loan_id, v_payment.id, v_payment.verified_at);
  delete from public.payment_allocations where payment_id = v_payment.id;
  update public.payments
     set status = 'pending', verified_at = null, verified_by = null, unapplied_centavos = 0
   where id = v_payment.id;
  update public.loans set status = 'active' where id = v_payment.loan_id and status = 'fully_paid';
  insert into public.audit_events (organization_id, actor_id, action, record_type, record_id, payload)
  values (v_payment.organization_id, auth.uid(), 'payment_verification_undone', 'payment', v_payment.id,
    jsonb_build_object('loan_id', v_payment.loan_id));
  return v_payment.id;
end $$;
revoke all on function public.undo_payment_verification(uuid) from public;
grant execute on function public.undo_payment_verification(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- Confirm & Disburse -> back to draft
-- ---------------------------------------------------------------------------
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
  if exists (select 1 from public.loan_amendments where loan_id = p_loan_id and undone_at is null) then
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

-- ---------------------------------------------------------------------------
-- Amend due date -> previous date
-- ---------------------------------------------------------------------------
create or replace function public.undo_due_date_amendment(p_amendment_id uuid)
returns uuid language plpgsql security definer set search_path = '' as $$
declare
  v_amendment public.loan_amendments%rowtype; v_installment public.installments%rowtype;
  v_sequence integer; v_previous date; v_new date;
begin
  if auth.uid() is null then raise exception 'Authentication is required'; end if;
  select * into v_amendment from public.loan_amendments where id = p_amendment_id for update;
  if v_amendment.id is null or v_amendment.amendment_type <> 'due_date' then
    raise exception 'Due-date amendment was not found';
  end if;
  if v_amendment.undone_at is not null then raise exception 'This amendment was already undone'; end if;
  if v_amendment.created_by <> auth.uid() then
    raise exception 'Only the person who made this amendment can undo it';
  end if;
  perform 1 from public.loans where id = v_amendment.loan_id for update;
  if exists (
    select 1 from public.loan_amendments a
    where a.loan_id = v_amendment.loan_id and a.undone_at is null and a.created_at > v_amendment.created_at
  ) then
    raise exception 'A later amendment exists on this loan; undo is no longer available';
  end if;
  v_sequence := (v_amendment.new_values->>'sequence')::integer;
  v_previous := (v_amendment.previous_values->>'due_date')::date;
  v_new := (v_amendment.new_values->>'due_date')::date;
  select * into v_installment from public.installments
   where loan_id = v_amendment.loan_id and sequence = v_sequence for update;
  if v_installment.id is null or v_installment.due_date <> v_new then
    raise exception 'The installment changed after this amendment; undo is no longer available';
  end if;
  if exists (
    select 1 from public.payment_allocations pa join public.payments p on p.id = pa.payment_id
    where pa.installment_id = v_installment.id and p.status = 'verified'
  ) then
    raise exception 'The installment now has verified payments; undo is no longer available';
  end if;
  update public.installments set due_date = v_previous where id = v_installment.id;
  update public.loan_amendments set undone_at = now(), undone_by = auth.uid() where id = v_amendment.id;
  insert into public.audit_events (organization_id, actor_id, action, record_type, record_id, payload)
  values (v_amendment.organization_id, auth.uid(), 'loan_due_date_amendment_undone', 'loan', v_amendment.loan_id,
    jsonb_build_object('amendment_id', v_amendment.id, 'sequence', v_sequence,
      'restored_due_date', v_previous, 'undone_due_date', v_new));
  return v_amendment.id;
end $$;
revoke all on function public.undo_due_date_amendment(uuid) from public;
grant execute on function public.undo_due_date_amendment(uuid) to authenticated;

-- Return the amendment id so the app can offer undo.
-- (amend_installment_due_date already returns it; no change needed.)

-- ---------------------------------------------------------------------------
-- Early payoff: snapshot what the payoff rewrites so it can be restored.
-- Same body as 202611070022 (+ PalPay from 202611070031), plus "previous".
-- ---------------------------------------------------------------------------
create or replace function public.record_early_payoff(
  p_loan_id uuid, p_payoff_date date, p_method text, p_reference text,
  p_client_operation_id uuid, p_device_id text
) returns uuid language plpgsql security definer set search_path = '' as $$
declare
  v_loan public.loans%rowtype; v_quote jsonb; v_amount bigint; v_payment_id uuid;
  v_i record; v_paid_principal bigint; v_paid_interest bigint;
  v_principal bigint; v_interest bigint; v_previous jsonb;
begin
  select * into v_loan from public.loans where id=p_loan_id for update;
  if v_loan.id is null or v_loan.status<>'active' then raise exception 'Early payoff requires an active loan'; end if;
  if not public.has_org_role(v_loan.organization_id,array['owner','manager']::public.app_role[]) then raise exception 'Owner or manager access is required'; end if;
  if p_method not in ('Cash','GCash','AUB','MariBank','PalPay') or p_client_operation_id is null or length(btrim(coalesce(p_device_id,'')))=0 then
    raise exception 'Complete payoff details are required';
  end if;
  select id into v_payment_id from public.payments where organization_id=v_loan.organization_id and client_operation_id=p_client_operation_id;
  if v_payment_id is not null then return v_payment_id; end if;
  v_quote := public.early_payoff_quote(p_loan_id,p_payoff_date);
  v_amount := (v_quote->>'payoff_centavos')::bigint;
  if v_amount<=0 then raise exception 'No payoff balance remains'; end if;
  select jsonb_build_object(
    'total_centavos', v_loan.total_centavos,
    'terms_snapshot', v_loan.terms_snapshot,
    'installments', coalesce(jsonb_agg(jsonb_build_object(
      'id', i.id, 'interest_centavos', i.interest_centavos, 'scheduled_centavos', i.scheduled_centavos)), '[]'::jsonb)
  ) into v_previous from public.installments i where i.loan_id = p_loan_id;
  insert into public.payments(organization_id,loan_id,amount_centavos,received_at,method,reference,status,client_operation_id,device_id,created_by,verified_at,verified_by)
  values(v_loan.organization_id,v_loan.id,v_amount,p_payoff_date::timestamptz,p_method,nullif(btrim(coalesce(p_reference,'')),''),'verified',p_client_operation_id,btrim(p_device_id),auth.uid(),now(),auth.uid())
  returning id into v_payment_id;
  for v_i in select * from public.installments where loan_id=p_loan_id order by due_date,sequence for update loop
    select coalesce(sum(pa.principal_centavos),0),coalesce(sum(pa.interest_centavos),0)
      into v_paid_principal,v_paid_interest from public.payment_allocations pa join public.payments p on p.id=pa.payment_id
      where pa.installment_id=v_i.id and p.status='verified';
    v_principal := greatest(v_i.principal_centavos-v_paid_principal,0);
    v_interest := case when v_i.due_date<=p_payoff_date then greatest(v_i.interest_centavos-v_paid_interest,0) else 0 end;
    if v_principal+v_interest>0 then
      insert into public.payment_allocations(organization_id,payment_id,installment_id,principal_centavos,interest_centavos,penalty_centavos)
      values(v_loan.organization_id,v_payment_id,v_i.id,v_principal,v_interest,0);
    end if;
    if v_i.due_date>p_payoff_date then
      update public.installments set interest_centavos=v_paid_interest,
        scheduled_centavos=principal_centavos+v_paid_interest where id=v_i.id;
    end if;
  end loop;
  update public.loans set status='fully_paid', total_centavos=(
    select sum(scheduled_centavos) from public.installments where loan_id=p_loan_id
  ), terms_snapshot=terms_snapshot||jsonb_build_object('early_payoff_date',p_payoff_date,'future_interest_waived',true)
  where id=p_loan_id;
  insert into public.audit_events(organization_id,actor_id,action,record_type,record_id,payload)
  values(v_loan.organization_id,auth.uid(),'loan_settled_early','loan',v_loan.id,
    v_quote||jsonb_build_object('payment_id',v_payment_id,'previous',v_previous));
  return v_payment_id;
end $$;
revoke all on function public.record_early_payoff(uuid,date,text,text,uuid,text) from public;
grant execute on function public.record_early_payoff(uuid,date,text,text,uuid,text) to authenticated;

create or replace function public.undo_early_payoff(p_payment_id uuid)
returns uuid language plpgsql security definer set search_path = '' as $$
declare
  v_payment public.payments%rowtype; v_loan public.loans%rowtype;
  v_previous jsonb; v_item jsonb;
begin
  if auth.uid() is null then raise exception 'Authentication is required'; end if;
  select * into v_payment from public.payments where id = p_payment_id for update;
  if v_payment.id is null then raise exception 'Payment was not found'; end if;
  if v_payment.created_by <> auth.uid() then
    raise exception 'Only the person who recorded this payoff can undo it';
  end if;
  if v_payment.status <> 'verified' then raise exception 'This payoff can no longer be undone'; end if;
  select payload->'previous' into v_previous from public.audit_events
   where action = 'loan_settled_early' and payload->>'payment_id' = p_payment_id::text
   order by created_at desc limit 1;
  if v_previous is null then
    raise exception 'This payoff was recorded before undo was available';
  end if;
  select * into v_loan from public.loans where id = v_payment.loan_id for update;
  if v_loan.status <> 'fully_paid' then raise exception 'The loan changed after this payoff; undo is no longer available'; end if;
  if exists (
    select 1 from public.payments p
    where p.loan_id = v_loan.id and p.id <> v_payment.id and p.status in ('pending', 'verified')
      and p.created_at > v_payment.created_at
  ) then
    raise exception 'A later payment exists on this loan; undo is no longer available';
  end if;
  delete from public.payment_allocations where payment_id = v_payment.id;
  for v_item in select * from jsonb_array_elements(v_previous->'installments') loop
    update public.installments
       set interest_centavos = (v_item->>'interest_centavos')::bigint,
           scheduled_centavos = (v_item->>'scheduled_centavos')::bigint
     where id = (v_item->>'id')::uuid and loan_id = v_loan.id;
  end loop;
  update public.loans
     set status = 'active', total_centavos = (v_previous->>'total_centavos')::bigint,
         terms_snapshot = v_previous->'terms_snapshot'
   where id = v_loan.id;
  update public.payments
     set status = 'reversed', reversed_at = now(), reversed_by = auth.uid(),
         reversal_reason = 'Early payoff undone', unapplied_centavos = 0
   where id = v_payment.id;
  insert into public.audit_events (organization_id, actor_id, action, record_type, record_id, payload)
  values (v_loan.organization_id, auth.uid(), 'loan_early_payoff_undone', 'loan', v_loan.id,
    jsonb_build_object('payment_id', v_payment.id));
  return v_payment.id;
end $$;
revoke all on function public.undo_early_payoff(uuid) from public;
grant execute on function public.undo_early_payoff(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- Log collection activity -> marked undone (hidden from lists)
-- ---------------------------------------------------------------------------
create or replace function public.undo_collection_activity(p_activity_id uuid)
returns uuid language plpgsql security definer set search_path = '' as $$
declare v_activity public.collection_activities%rowtype;
begin
  if auth.uid() is null then raise exception 'Authentication is required'; end if;
  select * into v_activity from public.collection_activities where id = p_activity_id for update;
  if v_activity.id is null then raise exception 'Collection activity was not found'; end if;
  if v_activity.undone_at is not null then raise exception 'This activity was already undone'; end if;
  if v_activity.created_by <> auth.uid() then
    raise exception 'Only the person who logged this activity can undo it';
  end if;
  update public.collection_activities set undone_at = now(), undone_by = auth.uid()
   where id = v_activity.id;
  insert into public.audit_events (organization_id, actor_id, action, record_type, record_id, payload)
  values (v_activity.organization_id, auth.uid(), 'collection_activity_undone', 'collection_activity',
    v_activity.id, jsonb_build_object('loan_id', v_activity.loan_id));
  return v_activity.id;
end $$;
revoke all on function public.undo_collection_activity(uuid) from public;
grant execute on function public.undo_collection_activity(uuid) to authenticated;

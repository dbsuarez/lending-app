-- Correct a payment's details (when it was received, method, reference)
-- without touching the money. Allocation never depends on these fields
-- (verify_payment pays the oldest unpaid installment first regardless of the
-- received date), so balances and installments stay exactly as they are.
-- Amount mistakes still go through reverse + record again.
--
-- Every correction keeps the previous values, the reason and who made it,
-- and can be undone by the same person while nothing changed after it.

create table if not exists public.payment_corrections (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations,
  payment_id uuid not null references public.payments,
  previous_values jsonb not null,
  new_values jsonb not null,
  reason text not null check (length(btrim(reason)) >= 3),
  created_by uuid not null references auth.users,
  created_at timestamptz not null default now(),
  undone_at timestamptz,
  undone_by uuid references auth.users
);

create index if not exists payment_corrections_payment_idx
  on public.payment_corrections (payment_id, created_at desc);

alter table public.payment_corrections enable row level security;

drop policy if exists members_read_payment_corrections on public.payment_corrections;
create policy members_read_payment_corrections on public.payment_corrections
  for select using (public.is_org_member(organization_id));

create or replace function public.correct_payment_details(
  p_payment_id uuid,
  p_received_at timestamptz,
  p_method text,
  p_reference text,
  p_reason text
) returns uuid
language plpgsql security definer set search_path = '' as $$
declare
  v_payment public.payments%rowtype;
  v_methods jsonb;
  v_method text;
  v_reference text;
  v_id uuid;
begin
  if auth.uid() is null then raise exception 'Authentication is required'; end if;
  select * into v_payment from public.payments where id = p_payment_id for update;
  if v_payment.id is null then raise exception 'Payment was not found'; end if;
  if not public.has_org_role(v_payment.organization_id, array['owner','manager']::public.app_role[]) then
    raise exception 'Owner or manager access is required';
  end if;
  if v_payment.status not in ('pending', 'verified') then
    raise exception 'Only pending or verified payments can be corrected';
  end if;
  if public._is_early_payoff_payment(v_payment.id) then
    raise exception 'An early payoff payment cannot be corrected; undo the payoff instead';
  end if;
  if length(btrim(coalesce(p_reason, ''))) < 3 then
    raise exception 'A clear reason is required';
  end if;
  if p_received_at is null or p_received_at > now() + interval '1 day' then
    raise exception 'The received date cannot be in the future';
  end if;

  v_method := coalesce(nullif(btrim(coalesce(p_method, '')), ''), v_payment.method);
  if v_method <> v_payment.method then
    select coalesce(operational_preferences->'payment_methods', '["Cash","GCash","AUB","MariBank"]'::jsonb)
      into v_methods from public.organizations where id = v_payment.organization_id;
    if not exists (select 1 from jsonb_array_elements_text(v_methods) m where m.value = v_method) then
      raise exception 'Unknown payment method';
    end if;
    -- Cash is verified on entry; switching to or from Cash would change who
    -- may verify it, so that still needs reverse + record again.
    if (lower(v_method) = 'cash') <> (lower(v_payment.method) = 'cash') then
      raise exception 'Cash and non-cash cannot be swapped; reverse the payment and record it again';
    end if;
  end if;
  v_reference := nullif(btrim(coalesce(p_reference, '')), '');

  if p_received_at = v_payment.received_at
     and v_method = v_payment.method
     and v_reference is not distinct from v_payment.reference then
    raise exception 'Nothing was changed';
  end if;

  insert into public.payment_corrections (
    organization_id, payment_id, previous_values, new_values, reason, created_by
  ) values (
    v_payment.organization_id, v_payment.id,
    jsonb_build_object('received_at', v_payment.received_at, 'method', v_payment.method, 'reference', v_payment.reference),
    jsonb_build_object('received_at', p_received_at, 'method', v_method, 'reference', v_reference),
    btrim(p_reason), auth.uid()
  ) returning id into v_id;

  update public.payments
     set received_at = p_received_at, method = v_method, reference = v_reference
   where id = v_payment.id;

  insert into public.audit_events (organization_id, actor_id, action, record_type, record_id, payload)
  values (v_payment.organization_id, auth.uid(), 'payment_corrected', 'payment', v_payment.id,
    jsonb_build_object(
      'loan_id', v_payment.loan_id,
      'correction_id', v_id,
      'reason', btrim(p_reason),
      'previous_received_at', v_payment.received_at,
      'new_received_at', p_received_at,
      'previous_method', v_payment.method,
      'new_method', v_method,
      'previous_reference', v_payment.reference,
      'new_reference', v_reference));
  return v_id;
end $$;
revoke all on function public.correct_payment_details(uuid, timestamptz, text, text, text) from public;
grant execute on function public.correct_payment_details(uuid, timestamptz, text, text, text) to authenticated;

create or replace function public.undo_payment_correction(p_correction_id uuid)
returns uuid
language plpgsql security definer set search_path = '' as $$
declare
  v_correction public.payment_corrections%rowtype;
  v_payment public.payments%rowtype;
begin
  if auth.uid() is null then raise exception 'Authentication is required'; end if;
  select * into v_correction from public.payment_corrections where id = p_correction_id for update;
  if v_correction.id is null then raise exception 'Correction was not found'; end if;
  if v_correction.undone_at is not null then raise exception 'This correction was already undone'; end if;
  if v_correction.created_by <> auth.uid() then
    raise exception 'Only the person who made this correction can undo it';
  end if;
  select * into v_payment from public.payments where id = v_correction.payment_id for update;
  if v_payment.status not in ('pending', 'verified') then
    raise exception 'The payment changed after this correction; undo is no longer available';
  end if;
  if exists (
    select 1 from public.payment_corrections c
    where c.payment_id = v_correction.payment_id and c.undone_at is null
      and c.created_at > v_correction.created_at
  ) or v_payment.received_at <> (v_correction.new_values->>'received_at')::timestamptz
    or v_payment.method <> v_correction.new_values->>'method'
    or v_payment.reference is distinct from v_correction.new_values->>'reference' then
    raise exception 'The payment changed after this correction; undo is no longer available';
  end if;

  update public.payments
     set received_at = (v_correction.previous_values->>'received_at')::timestamptz,
         method = v_correction.previous_values->>'method',
         reference = v_correction.previous_values->>'reference'
   where id = v_payment.id;
  update public.payment_corrections set undone_at = now(), undone_by = auth.uid()
   where id = v_correction.id;
  insert into public.audit_events (organization_id, actor_id, action, record_type, record_id, payload)
  values (v_correction.organization_id, auth.uid(), 'payment_correction_undone', 'payment', v_payment.id,
    jsonb_build_object('loan_id', v_payment.loan_id, 'correction_id', v_correction.id));
  return v_correction.id;
end $$;
revoke all on function public.undo_payment_correction(uuid) from public;
grant execute on function public.undo_payment_correction(uuid) to authenticated;

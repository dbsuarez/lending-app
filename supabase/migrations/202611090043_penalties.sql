-- Penalties (owner's rules, 2026-11-09):
--   * Modes: none (default), fixed amount, percentage of the overdue
--     installment, manual (owner adds charges by hand).
--   * Automatic charges: on due date + grace days (default 3), then at every
--     payday cutoff while the installment's principal/interest is unpaid.
--   * Payments apply to the oldest installment first: penalty, interest,
--     principal.
--   * Never retroactive: a loan's policy is fixed while it is a draft;
--     existing loans keep "none".
-- A charge is added to its installment (penalty_centavos and
-- scheduled_centavos) and to the loan total, so every balance, report,
-- backup check and the customer page include it without further changes.

alter table public.installments add column if not exists penalty_centavos bigint not null default 0;

create table if not exists public.penalty_charges (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations,
  loan_id uuid not null references public.loans,
  installment_id uuid not null references public.installments on delete cascade,
  charge_date date not null,
  amount_centavos bigint not null check (amount_centavos > 0),
  source text not null check (source in ('automatic', 'manual')),
  note text,
  created_by uuid references auth.users,
  created_at timestamptz not null default now(),
  waived_at timestamptz,
  waived_by uuid references auth.users,
  waive_reason text
);
create unique index if not exists penalty_charges_automatic_once
  on public.penalty_charges (installment_id, charge_date) where source = 'automatic';
create index if not exists penalty_charges_loan_idx on public.penalty_charges (loan_id);
alter table public.penalty_charges enable row level security;
drop policy if exists members_read_penalty_charges on public.penalty_charges;
create policy members_read_penalty_charges on public.penalty_charges
  for select using (public.is_org_member(organization_id));

-- Validates a policy object: {"mode", "amount_centavos"?, "rate_basis_points"?, "grace_days"?}.
create or replace function public._clean_penalty_policy(p jsonb)
returns jsonb language plpgsql immutable set search_path = '' as $$
declare v_mode text := coalesce(p->>'mode', 'none'); v_grace int := coalesce((p->>'grace_days')::int, 3);
begin
  if v_mode not in ('none', 'fixed', 'percentage', 'manual') then raise exception 'Unknown penalty type'; end if;
  if v_grace < 0 or v_grace > 60 then raise exception 'Grace days must be between 0 and 60'; end if;
  if v_mode = 'fixed' and coalesce((p->>'amount_centavos')::bigint, 0) <= 0 then
    raise exception 'Enter the fixed penalty amount';
  end if;
  if v_mode = 'percentage' and coalesce((p->>'rate_basis_points')::int, 0) <= 0 then
    raise exception 'Enter the penalty percentage';
  end if;
  return jsonb_strip_nulls(jsonb_build_object(
    'mode', v_mode, 'grace_days', v_grace,
    'amount_centavos', case when v_mode = 'fixed' then (p->>'amount_centavos')::bigint end,
    'rate_basis_points', case when v_mode = 'percentage' then (p->>'rate_basis_points')::int end));
end $$;

-- A draft loan's penalty policy (fixed once released).
create or replace function public.set_loan_penalty_policy(p_loan_id uuid, p_policy jsonb)
returns void language plpgsql security definer set search_path = '' as $$
declare v_loan public.loans%rowtype; v_clean jsonb := public._clean_penalty_policy(p_policy);
begin
  select * into v_loan from public.loans where id = p_loan_id for update;
  if v_loan.id is null then raise exception 'Loan was not found'; end if;
  if not public.has_org_role(v_loan.organization_id, array['owner','manager']::public.app_role[]) then
    raise exception 'Owner or manager access is required';
  end if;
  if v_loan.status <> 'draft' then raise exception 'The penalty policy can only be set while the loan is a draft'; end if;
  update public.loans set terms_snapshot = terms_snapshot || jsonb_build_object('penalty_policy', v_clean)
   where id = p_loan_id;
end $$;
revoke all on function public.set_loan_penalty_policy(uuid, jsonb) from public;
grant execute on function public.set_loan_penalty_policy(uuid, jsonb) to authenticated;

-- Adds a charge to its installment and the loan total.
create or replace function public._apply_penalty(p_installment_id uuid, p_amount bigint)
returns void language sql security definer set search_path = '' as $$
  update public.installments set penalty_centavos = penalty_centavos + p_amount,
    scheduled_centavos = scheduled_centavos + p_amount where id = p_installment_id;
  update public.loans set total_centavos = total_centavos + p_amount
   where id = (select loan_id from public.installments where id = p_installment_id);
$$;
revoke all on function public._apply_penalty(uuid, bigint) from public;

-- Charges every automatic penalty due up to p_as_of. Idempotent.
create or replace function public._assess_penalties(p_loan_id uuid, p_as_of date)
returns integer language plpgsql security definer set search_path = '' as $$
declare
  v_loan public.loans%rowtype; v_policy jsonb; v_mode text; v_grace int; v_fixed bigint; v_rate int;
  v_pattern int[]; v_i record; v_d date; v_unpaid bigint; v_amount bigint; v_count int := 0; v_total bigint := 0;
begin
  select * into v_loan from public.loans where id = p_loan_id for update;
  if v_loan.id is null or v_loan.status <> 'active' then return 0; end if;
  v_policy := v_loan.terms_snapshot->'penalty_policy';
  if jsonb_typeof(v_policy) is distinct from 'object' then return 0; end if;
  v_mode := v_policy->>'mode';
  if v_mode not in ('fixed', 'percentage') then return 0; end if;
  v_grace := coalesce((v_policy->>'grace_days')::int, 3);
  v_fixed := (v_policy->>'amount_centavos')::bigint;
  v_rate := (v_policy->>'rate_basis_points')::int;
  select coalesce(array_agg(x::int), array[15, 30]) into v_pattern
    from jsonb_array_elements_text(coalesce(v_loan.terms_snapshot->'payday_pattern', '[]'::jsonb)) x;

  for v_i in select * from public.installments where loan_id = p_loan_id order by due_date, sequence for update loop
    for v_d in
      select d from (
        select (v_i.due_date + v_grace) as d
        union
        select least(date_trunc('month', m)::date + (day - 1),
                     (date_trunc('month', m) + interval '1 month - 1 day')::date)
          from generate_series(date_trunc('month', v_i.due_date + v_grace), date_trunc('month', p_as_of), interval '1 month') m,
               unnest(v_pattern) day
      ) s where d >= v_i.due_date + v_grace and d <= p_as_of order by d
    loop
      select greatest(v_i.principal_centavos + v_i.interest_centavos
               - coalesce(sum(a.principal_centavos + a.interest_centavos), 0), 0)
        into v_unpaid
        from public.payment_allocations a join public.payments p on p.id = a.payment_id
       where a.installment_id = v_i.id and p.status = 'verified';
      exit when v_unpaid <= 0;
      continue when exists (select 1 from public.penalty_charges c
                             where c.installment_id = v_i.id and c.charge_date = v_d and c.source = 'automatic');
      v_amount := case v_mode when 'fixed' then v_fixed else round(v_unpaid * v_rate / 10000.0)::bigint end;
      continue when v_amount <= 0;
      insert into public.penalty_charges (organization_id, loan_id, installment_id, charge_date, amount_centavos, source)
      values (v_loan.organization_id, p_loan_id, v_i.id, v_d, v_amount, 'automatic');
      perform public._apply_penalty(v_i.id, v_amount);
      v_count := v_count + 1; v_total := v_total + v_amount;
    end loop;
  end loop;
  if v_count > 0 then
    insert into public.audit_events (organization_id, actor_id, action, record_type, record_id, payload)
    values (v_loan.organization_id, auth.uid(), 'penalties_charged', 'loan', p_loan_id,
      jsonb_build_object('count', v_count, 'amount_centavos', v_total, 'as_of', p_as_of));
  end if;
  return v_count;
end $$;
revoke all on function public._assess_penalties(uuid, date) from public;

-- Brings penalties up to date (today, Manila) for one loan or all of the
-- caller's active loans. Called by the app when loans load.
create or replace function public.assess_penalties(p_loan_id uuid default null)
returns integer language plpgsql security definer set search_path = '' as $$
declare v_org uuid; v_loan record; v_count int := 0; v_today date := (now() at time zone 'Asia/Manila')::date;
begin
  if auth.uid() is null then raise exception 'Authentication is required'; end if;
  select organization_id into v_org from public.organization_members
   where user_id = auth.uid() and status = 'active' order by organization_id limit 1;
  if v_org is null then raise exception 'Organization membership is required'; end if;
  for v_loan in
    select id from public.loans
     where organization_id = v_org and status = 'active'
       and (p_loan_id is null or id = p_loan_id)
       and terms_snapshot->'penalty_policy'->>'mode' in ('fixed', 'percentage')
  loop
    v_count := v_count + public._assess_penalties(v_loan.id, v_today);
  end loop;
  return v_count;
end $$;
revoke all on function public.assess_penalties(uuid) from public;
grant execute on function public.assess_penalties(uuid) to authenticated;

create or replace function public.add_penalty_charge(p_installment_id uuid, p_amount_centavos bigint, p_note text)
returns uuid language plpgsql security definer set search_path = '' as $$
declare v_i public.installments%rowtype; v_loan public.loans%rowtype; v_id uuid;
begin
  select * into v_i from public.installments where id = p_installment_id for update;
  if v_i.id is null then raise exception 'Installment was not found'; end if;
  select * into v_loan from public.loans where id = v_i.loan_id for update;
  if not public.has_org_role(v_loan.organization_id, array['owner','manager']::public.app_role[]) then
    raise exception 'Owner or manager access is required';
  end if;
  if v_loan.status <> 'active' then raise exception 'Penalties apply only to active loans'; end if;
  if coalesce(v_loan.terms_snapshot->'penalty_policy'->>'mode', 'none') = 'none' then
    raise exception 'This loan was made without penalties';
  end if;
  if p_amount_centavos is null or p_amount_centavos <= 0 then raise exception 'Enter a penalty amount'; end if;
  if length(btrim(coalesce(p_note, ''))) < 3 then raise exception 'Enter a short reason (kept in the history)'; end if;
  insert into public.penalty_charges (organization_id, loan_id, installment_id, charge_date, amount_centavos, source, note, created_by)
  values (v_loan.organization_id, v_loan.id, v_i.id, (now() at time zone 'Asia/Manila')::date, p_amount_centavos, 'manual', btrim(p_note), auth.uid())
  returning id into v_id;
  perform public._apply_penalty(v_i.id, p_amount_centavos);
  insert into public.audit_events (organization_id, actor_id, action, record_type, record_id, payload)
  values (v_loan.organization_id, auth.uid(), 'penalty_added', 'loan', v_loan.id,
    jsonb_build_object('charge_id', v_id, 'installment', v_i.sequence, 'amount_centavos', p_amount_centavos, 'note', btrim(p_note)));
  return v_id;
end $$;
revoke all on function public.add_penalty_charge(uuid, bigint, text) from public;
grant execute on function public.add_penalty_charge(uuid, bigint, text) to authenticated;

create or replace function public.waive_penalty_charge(p_charge_id uuid, p_reason text)
returns void language plpgsql security definer set search_path = '' as $$
declare v_c public.penalty_charges%rowtype; v_i public.installments%rowtype; v_paid bigint;
begin
  select * into v_c from public.penalty_charges where id = p_charge_id for update;
  if v_c.id is null then raise exception 'Penalty was not found'; end if;
  if not public.has_org_role(v_c.organization_id, array['owner','manager']::public.app_role[]) then
    raise exception 'Owner or manager access is required';
  end if;
  if v_c.waived_at is not null then raise exception 'This penalty was already waived'; end if;
  if length(btrim(coalesce(p_reason, ''))) < 3 then raise exception 'Enter a short reason (kept in the history)'; end if;
  select * into v_i from public.installments where id = v_c.installment_id for update;
  select coalesce(sum(a.penalty_centavos), 0) into v_paid
    from public.payment_allocations a join public.payments p on p.id = a.payment_id
   where a.installment_id = v_i.id and p.status = 'verified';
  if v_i.penalty_centavos - v_paid < v_c.amount_centavos then
    raise exception 'This penalty has already been paid; it cannot be waived';
  end if;
  update public.penalty_charges set waived_at = now(), waived_by = auth.uid(), waive_reason = btrim(p_reason)
   where id = p_charge_id;
  perform public._apply_penalty(v_i.id, -v_c.amount_centavos);
  insert into public.audit_events (organization_id, actor_id, action, record_type, record_id, payload)
  values (v_c.organization_id, auth.uid(), 'penalty_waived', 'loan', v_c.loan_id,
    jsonb_build_object('charge_id', p_charge_id, 'amount_centavos', v_c.amount_centavos, 'reason', btrim(p_reason)));
end $$;
revoke all on function public.waive_penalty_charge(uuid, text) from public;
grant execute on function public.waive_penalty_charge(uuid, text) to authenticated;

-- Payments: bring penalties up to the payment date, then apply oldest
-- installment first: penalty, interest, principal. Otherwise as 202611070021.
create or replace function public.verify_payment(p_payment_id uuid)
returns uuid language plpgsql security definer set search_path = '' as $$
declare
  v_payment public.payments%rowtype;
  v_installment record;
  v_remaining bigint;
  v_penalty bigint; v_interest bigint; v_principal bigint;
  v_paid_penalty bigint; v_paid_interest bigint; v_paid_principal bigint;
  v_total_outstanding bigint;
begin
  select * into v_payment from public.payments where id = p_payment_id for update;
  if v_payment.id is null then raise exception 'Payment was not found'; end if;
  if not public.has_org_role(
    v_payment.organization_id,
    case when v_payment.method = 'Cash'
      then array['owner','manager','collector']::public.app_role[]
      else array['owner','manager']::public.app_role[] end
  ) then
    raise exception 'Owner or manager access is required';
  end if;
  if v_payment.status <> 'pending' then raise exception 'Only a pending payment can be verified'; end if;

  perform 1 from public.loans where id = v_payment.loan_id for update;
  perform public._assess_penalties(v_payment.loan_id, (v_payment.received_at at time zone 'Asia/Manila')::date);
  v_remaining := v_payment.amount_centavos;
  for v_installment in
    select i.* from public.installments i where i.loan_id = v_payment.loan_id order by i.due_date, i.sequence for update
  loop
    select coalesce(sum(a.penalty_centavos),0), coalesce(sum(a.interest_centavos),0), coalesce(sum(a.principal_centavos),0)
      into v_paid_penalty, v_paid_interest, v_paid_principal
      from public.payment_allocations a join public.payments p on p.id = a.payment_id
      where a.installment_id = v_installment.id and p.status = 'verified';
    v_penalty := least(v_remaining, greatest(v_installment.penalty_centavos - v_paid_penalty, 0));
    v_remaining := v_remaining - v_penalty;
    v_interest := least(v_remaining, greatest(v_installment.interest_centavos - v_paid_interest, 0));
    v_remaining := v_remaining - v_interest;
    v_principal := least(v_remaining, greatest(v_installment.principal_centavos - v_paid_principal, 0));
    v_remaining := v_remaining - v_principal;
    if v_penalty + v_interest + v_principal > 0 then
      insert into public.payment_allocations (organization_id,payment_id,installment_id,principal_centavos,interest_centavos,penalty_centavos)
      values (v_payment.organization_id,v_payment.id,v_installment.id,v_principal,v_interest,v_penalty);
    end if;
    exit when v_remaining = 0;
  end loop;

  update public.payments set status = 'verified', verified_at = now(), verified_by = auth.uid(),
    unapplied_centavos = v_remaining where id = v_payment.id;
  select coalesce(sum(greatest(i.scheduled_centavos - coalesce(a.paid,0),0)),0)
    into v_total_outstanding
    from public.installments i
    left join (
      select pa.installment_id, sum(pa.principal_centavos + pa.interest_centavos + pa.penalty_centavos) paid
      from public.payment_allocations pa join public.payments p on p.id = pa.payment_id
      where p.loan_id = v_payment.loan_id and p.status = 'verified' group by pa.installment_id
    ) a on a.installment_id = i.id where i.loan_id = v_payment.loan_id;
  if v_total_outstanding = 0 then update public.loans set status = 'fully_paid' where id = v_payment.loan_id; end if;
  insert into public.audit_events (organization_id, actor_id, action, record_type, record_id, payload)
  values (v_payment.organization_id, auth.uid(), 'payment_verified', 'payment', v_payment.id,
    jsonb_build_object('allocated_centavos',v_payment.amount_centavos-v_remaining,'unapplied_centavos',v_remaining,'allocation_order','oldest_due_penalty_interest_principal'));
  return v_payment.id;
end $$;
revoke all on function public.verify_payment(uuid) from public;
grant execute on function public.verify_payment(uuid) to authenticated;

-- Early payoff includes unpaid penalties (paid first). Otherwise as 202611090042.
create or replace function public.early_payoff_quote(
  p_loan_id uuid, p_payoff_date date default current_date, p_mode text default 'waive_future'
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_loan public.loans%rowtype; v_principal bigint; v_interest bigint; v_penalty bigint; v_cutoff date;
begin
  if p_mode not in ('waive_future', 'current_month', 'all_interest') then
    raise exception 'Unknown payoff rule';
  end if;
  v_cutoff := public._payoff_interest_cutoff(p_payoff_date, p_mode);
  select * into v_loan from public.loans where id=p_loan_id;
  if v_loan.id is null or not public.is_org_member(v_loan.organization_id) then raise exception 'Loan was not found'; end if;
  if v_loan.status <> 'active' then raise exception 'Early payoff requires an active loan'; end if;
  perform public._assess_penalties(p_loan_id, p_payoff_date);
  select
    coalesce(sum(greatest(i.principal_centavos-coalesce(a.principal,0),0)),0),
    coalesce(sum(case when i.due_date<=v_cutoff then greatest(i.interest_centavos-coalesce(a.interest,0),0) else 0 end),0),
    coalesce(sum(greatest(i.penalty_centavos-coalesce(a.penalty,0),0)),0)
    into v_principal,v_interest,v_penalty
  from public.installments i left join (
    select pa.installment_id,sum(pa.principal_centavos) principal,sum(pa.interest_centavos) interest,sum(pa.penalty_centavos) penalty
    from public.payment_allocations pa join public.payments p on p.id=pa.payment_id
    where p.loan_id=p_loan_id and p.status='verified' group by pa.installment_id
  ) a on a.installment_id=i.id where i.loan_id=p_loan_id;
  return jsonb_build_object('principal_centavos',v_principal,'earned_interest_centavos',v_interest,
    'penalty_centavos',v_penalty,
    'payoff_centavos',v_principal+v_interest+v_penalty,'payoff_date',p_payoff_date,'mode',p_mode,
    'interest_through', case when v_cutoff = 'infinity'::date then null else v_cutoff end,
    'future_interest_waived', p_mode <> 'all_interest');
end $$;

create or replace function public.record_early_payoff(
  p_loan_id uuid, p_payoff_date date, p_method text, p_reference text,
  p_client_operation_id uuid, p_device_id text, p_mode text default 'waive_future'
) returns uuid language plpgsql security definer set search_path = '' as $$
declare
  v_loan public.loans%rowtype; v_quote jsonb; v_amount bigint; v_payment_id uuid;
  v_i record; v_paid_principal bigint; v_paid_interest bigint; v_paid_penalty bigint;
  v_principal bigint; v_interest bigint; v_penalty bigint; v_previous jsonb; v_cutoff date;
begin
  select * into v_loan from public.loans where id=p_loan_id for update;
  if v_loan.id is null or v_loan.status<>'active' then raise exception 'Early payoff requires an active loan'; end if;
  if not public.has_org_role(v_loan.organization_id,array['owner','manager']::public.app_role[]) then raise exception 'Owner or manager access is required'; end if;
  if p_method not in ('Cash','GCash','AUB','MariBank','PalPay') or p_client_operation_id is null or length(btrim(coalesce(p_device_id,'')))=0 then
    raise exception 'Complete payoff details are required';
  end if;
  select id into v_payment_id from public.payments where organization_id=v_loan.organization_id and client_operation_id=p_client_operation_id;
  if v_payment_id is not null then return v_payment_id; end if;
  v_quote := public.early_payoff_quote(p_loan_id,p_payoff_date,p_mode);
  v_cutoff := public._payoff_interest_cutoff(p_payoff_date, p_mode);
  v_amount := (v_quote->>'payoff_centavos')::bigint;
  if v_amount<=0 then raise exception 'No payoff balance remains'; end if;
  select * into v_loan from public.loans where id=p_loan_id;
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
    select coalesce(sum(pa.principal_centavos),0),coalesce(sum(pa.interest_centavos),0),coalesce(sum(pa.penalty_centavos),0)
      into v_paid_principal,v_paid_interest,v_paid_penalty from public.payment_allocations pa join public.payments p on p.id=pa.payment_id
      where pa.installment_id=v_i.id and p.status='verified';
    v_principal := greatest(v_i.principal_centavos-v_paid_principal,0);
    v_interest := case when v_i.due_date<=v_cutoff then greatest(v_i.interest_centavos-v_paid_interest,0) else 0 end;
    v_penalty := greatest(v_i.penalty_centavos-v_paid_penalty,0);
    if v_principal+v_interest+v_penalty>0 then
      insert into public.payment_allocations(organization_id,payment_id,installment_id,principal_centavos,interest_centavos,penalty_centavos)
      values(v_loan.organization_id,v_payment_id,v_i.id,v_principal,v_interest,v_penalty);
    end if;
    if v_i.due_date>v_cutoff then
      update public.installments set interest_centavos=v_paid_interest,
        scheduled_centavos=principal_centavos+v_paid_interest+penalty_centavos where id=v_i.id;
    end if;
  end loop;
  update public.loans set status='fully_paid', total_centavos=(
    select sum(scheduled_centavos) from public.installments where loan_id=p_loan_id
  ), terms_snapshot=terms_snapshot||jsonb_build_object('early_payoff_date',p_payoff_date,
       'early_payoff_mode',p_mode,'future_interest_waived',p_mode<>'all_interest')
  where id=p_loan_id;
  insert into public.audit_events(organization_id,actor_id,action,record_type,record_id,payload)
  values(v_loan.organization_id,auth.uid(),'loan_settled_early','loan',v_loan.id,
    v_quote||jsonb_build_object('payment_id',v_payment_id,'previous',v_previous));
  return v_payment_id;
end $$;

-- Restore a loan from a backup: penalty charges travel with the loan.
-- Otherwise as 202611090037.
-- Sections of a loan state, in the order they are inserted.
create or replace function public._loan_state(p_loan_id uuid)
returns jsonb language sql stable security definer set search_path = '' as $$
  select case when l.id is null then null else jsonb_build_object(
    'loan', to_jsonb(l),
    'installments', coalesce((select jsonb_agg(to_jsonb(x) order by x.id)
      from public.installments x where x.loan_id = l.id), '[]'::jsonb),
    'loan_disbursements', coalesce((select jsonb_agg(to_jsonb(x) order by x.id)
      from public.loan_disbursements x where x.loan_id = l.id), '[]'::jsonb),
    'payments', coalesce((select jsonb_agg(to_jsonb(x) order by x.id)
      from public.payments x where x.loan_id = l.id), '[]'::jsonb),
    'payment_allocations', coalesce((select jsonb_agg(to_jsonb(x) order by x.id)
      from public.payment_allocations x
      where x.payment_id in (select p.id from public.payments p where p.loan_id = l.id)), '[]'::jsonb),
    'payment_corrections', coalesce((select jsonb_agg(to_jsonb(x) order by x.id)
      from public.payment_corrections x
      where x.payment_id in (select p.id from public.payments p where p.loan_id = l.id)), '[]'::jsonb),
    'loan_amendments', coalesce((select jsonb_agg(to_jsonb(x) order by x.id)
      from public.loan_amendments x where x.loan_id = l.id), '[]'::jsonb),
    'collection_activities', coalesce((select jsonb_agg(to_jsonb(x) order by x.id)
      from public.collection_activities x where x.loan_id = l.id), '[]'::jsonb),
    'loan_share_links', coalesce((select jsonb_agg(to_jsonb(x) order by x.id)
      from public.loan_share_links x where x.loan_id = l.id), '[]'::jsonb),
    'penalty_charges', coalesce((select jsonb_agg(to_jsonb(x) order by x.id)
      from public.penalty_charges x where x.loan_id = l.id), '[]'::jsonb)
  ) end
  from (select 1) one left join public.loans l on l.id = p_loan_id
$$;
revoke all on function public._loan_state(uuid) from public;

-- Checks that a state only contains this loan's rows in this organization.
create or replace function public._assert_loan_state(p_loan_id uuid, p_org uuid, p_state jsonb)
returns void language plpgsql stable security definer set search_path = '' as $$
declare v_section text;
begin
  if p_state is null then return; end if;
  if jsonb_typeof(p_state) <> 'object' or p_state->'loan' is null then
    raise exception 'The backup data for this loan is incomplete';
  end if;
  if exists (select 1 from jsonb_object_keys(p_state) k where k not in (
      'loan','installments','loan_disbursements','payments','payment_allocations',
      'payment_corrections','loan_amendments','collection_activities','loan_share_links',
      'penalty_charges')) then
    raise exception 'The backup data for this loan has unknown parts';
  end if;
  if p_state->'loan'->>'id' is distinct from p_loan_id::text
     or p_state->'loan'->>'organization_id' is distinct from p_org::text then
    raise exception 'The backup data is for a different loan';
  end if;
  if not exists (select 1 from public.borrowers b
                 where b.id = (p_state->'loan'->>'borrower_id')::uuid and b.organization_id = p_org) then
    raise exception 'The borrower of this loan no longer exists';
  end if;
  foreach v_section in array array['installments','loan_disbursements','payments','payment_allocations',
      'payment_corrections','loan_amendments','collection_activities','loan_share_links','penalty_charges'] loop
    if jsonb_typeof(coalesce(p_state->v_section, '[]'::jsonb)) <> 'array' then
      raise exception 'The backup data for this loan is malformed (%)', v_section;
    end if;
    if exists (select 1 from jsonb_array_elements(coalesce(p_state->v_section, '[]'::jsonb)) e
               where e->>'organization_id' is distinct from p_org::text
                  or (v_section not in ('payment_allocations','payment_corrections')
                      and e->>'loan_id' is distinct from p_loan_id::text)) then
      raise exception 'The backup data contains records of another loan (%)', v_section;
    end if;
  end loop;
  if exists (select 1 from jsonb_array_elements(coalesce(p_state->'payment_allocations', '[]'::jsonb)) a
             where not exists (select 1 from jsonb_array_elements(coalesce(p_state->'payments', '[]'::jsonb)) p
                               where p->>'id' = a->>'payment_id')
                or not exists (select 1 from jsonb_array_elements(coalesce(p_state->'installments', '[]'::jsonb)) i
                               where i->>'id' = a->>'installment_id'))
     or exists (select 1 from jsonb_array_elements(coalesce(p_state->'payment_corrections', '[]'::jsonb)) c
                where not exists (select 1 from jsonb_array_elements(coalesce(p_state->'payments', '[]'::jsonb)) p
                                  where p->>'id' = c->>'payment_id'))
     or exists (select 1 from jsonb_array_elements(coalesce(p_state->'penalty_charges', '[]'::jsonb)) c
                where not exists (select 1 from jsonb_array_elements(coalesce(p_state->'installments', '[]'::jsonb)) i
                                  where i->>'id' = c->>'installment_id')) then
    raise exception 'The backup data for this loan is inconsistent';
  end if;
end $$;
revoke all on function public._assert_loan_state(uuid, uuid, jsonb) from public;

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
  insert into public.payments
    select * from jsonb_populate_recordset(null::public.payments, coalesce(p_state->'payments', '[]'::jsonb));
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



-- Customer status page: penalties brought up to date and shown.
-- Otherwise as 202611090041.
create or replace function public.get_shared_loan_status(p_token text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  target_link public.loan_share_links%rowtype;
  target_loan public.loans%rowtype;
  v_org public.organizations%rowtype;
  borrower_label text;
  v_today date := (now() at time zone 'Asia/Manila')::date;
  verified_paid bigint;
  pending_total bigint;
  v_outstanding bigint;
  v_past_due bigint;
  v_oldest_past date;
  v_next record;
  v_release record;
  schedule_json jsonb;
  payment_json jsonb;
begin
  if length(coalesce(p_token, '')) <> 64 then raise exception 'Link is invalid or revoked'; end if;
  select * into target_link from public.loan_share_links
  where token_hash = extensions.digest(p_token, 'sha256') and revoked_at is null;
  if target_link.id is null then raise exception 'Link is invalid or revoked'; end if;

  select * into target_loan from public.loans where id = target_link.loan_id;
  -- Penalties due up to today are charged before anything is shown.
  perform public._assess_penalties(target_loan.id, v_today);
  select * into target_loan from public.loans where id = target_link.loan_id;
  select * into v_org from public.organizations where id = target_loan.organization_id;
  select concat(b.first_name, ' ', left(b.last_name, 1), '.') into borrower_label
  from public.borrowers b where b.id = target_loan.borrower_id;
  select coalesce(sum(p.amount_centavos), 0) into verified_paid
  from public.payments p where p.loan_id = target_loan.id and p.status = 'verified';
  select coalesce(sum(p.amount_centavos), 0) into pending_total
  from public.payments p where p.loan_id = target_loan.id and p.status = 'pending';

  -- Per installment: verified payments only (as in the app and reports).
  create temporary table if not exists _share_inst (
    sequence int, due_date date, scheduled bigint, principal bigint, interest bigint, penalty bigint,
    paid bigint, paid_principal bigint, paid_interest bigint
  ) on commit drop;
  truncate _share_inst; -- (a WHERE-less DELETE is refused on API requests)
  insert into _share_inst
  select i.sequence, i.due_date, i.scheduled_centavos, i.principal_centavos, i.interest_centavos, i.penalty_centavos,
    coalesce(sum(a.principal_centavos + a.interest_centavos + a.penalty_centavos)
      filter (where p.status = 'verified'), 0),
    coalesce(sum(a.principal_centavos) filter (where p.status = 'verified'), 0),
    coalesce(sum(a.interest_centavos) filter (where p.status = 'verified'), 0)
  from public.installments i
  left join public.payment_allocations a on a.installment_id = i.id
  left join public.payments p on p.id = a.payment_id
  where i.loan_id = target_loan.id
  group by i.id;

  select coalesce(sum(greatest(scheduled - paid, 0)), 0),
         coalesce(sum(greatest(scheduled - paid, 0)) filter (where due_date < v_today), 0),
         min(due_date) filter (where due_date < v_today and paid < scheduled)
    into v_outstanding, v_past_due, v_oldest_past
  from _share_inst;
  select due_date, greatest(scheduled - paid, 0) as amount into v_next
  from _share_inst where due_date >= v_today and paid < scheduled order by due_date limit 1;


  select d.disbursed_on, d.amount_centavos into v_release
  from public.loan_disbursements d where d.loan_id = target_loan.id and d.voided_at is null
  order by d.created_at desc limit 1;

  select coalesce(jsonb_agg(jsonb_build_object(
      'sequence', sequence, 'due_date', due_date, 'scheduled_centavos', scheduled,
      'penalty_centavos', penalty,
      'paid_centavos', paid, 'outstanding_centavos', greatest(scheduled - paid, 0),
      'status', case
        when paid >= scheduled then 'paid'
        when due_date < v_today then 'overdue'
        when due_date = v_today then 'due_today'
        when paid > 0 then 'partial'
        else 'upcoming' end
    ) order by sequence), '[]'::jsonb) into schedule_json
  from _share_inst;

  select coalesce(jsonb_agg(row_data order by received_at desc), '[]'::jsonb) into payment_json
  from (
    select p.received_at, p.amount_centavos, p.status,
      -- Spreadsheet-import notes are internal; show a neutral word instead.
      case when p.method ilike 'legacy import' or p.method ilike '%import%' then 'Recorded'
           else p.method end as method,
      case when p.status = 'verified' then 'PR-' || upper(left(p.id::text, 8)) end as receipt_no,
      case when p.reference is null or p.reference ilike '%.xls%' or p.reference ilike 'imported from%'
             or length(regexp_replace(p.reference, '\s', '', 'g')) < 4 then null
           else right(regexp_replace(p.reference, '\s', '', 'g'), 4) end as reference_last4,
      case when p.status = 'verified' then (
        select coalesce(jsonb_agg(jsonb_build_object('sequence', i.sequence,
                 'amount_centavos', a.principal_centavos + a.interest_centavos + a.penalty_centavos)
               order by i.sequence), '[]'::jsonb)
        from public.payment_allocations a join public.installments i on i.id = a.installment_id
        where a.payment_id = p.id) end as applied
    from public.payments p
    where p.loan_id = target_loan.id and p.status in ('pending', 'verified')
  ) row_data;

  update public.loan_share_links set last_accessed_at = now() where id = target_link.id;
  return jsonb_build_object(
    -- Existing fields
    'borrower', borrower_label, 'loan_reference', 'LN-' || upper(left(target_loan.id::text, 8)),
    'loan_status', target_loan.status, 'principal_centavos', target_loan.principal_centavos,
    'total_centavos', target_loan.total_centavos, 'verified_paid_centavos', verified_paid,
    'pending_centavos', pending_total,
    'outstanding_centavos', v_outstanding,
    'schedule', schedule_json, 'payments', payment_json,
    -- New
    'today', v_today,
    'business', jsonb_build_object('name', v_org.name, 'phone', nullif(btrim(coalesce(v_org.phone, '')), ''),
                                   'email', nullif(btrim(coalesce(v_org.email, '')), '')),
    'terms', jsonb_build_object(
      'monthly_rate_basis_points', target_loan.monthly_rate_basis_points,
      'term_months', target_loan.term_months,
      'interest_centavos', target_loan.total_centavos - target_loan.principal_centavos,
      'installment_count', (select count(*) from _share_inst),
      'penalties', coalesce(target_loan.terms_snapshot->'penalty_policy'->>'mode', 'none'),
      'penalty_policy', case when jsonb_typeof(target_loan.terms_snapshot->'penalty_policy') = 'object'
        then target_loan.terms_snapshot->'penalty_policy' end,
      'penalties_charged_centavos', (select coalesce(sum(penalty), 0) from _share_inst)),
    'release', case when v_release.disbursed_on is null then null else
      jsonb_build_object('released_on', v_release.disbursed_on, 'amount_centavos', v_release.amount_centavos) end,
    'past_due_centavos', v_past_due,
    'days_past_due', case when v_oldest_past is null then 0 else v_today - v_oldest_past end,
    'next_due', case when v_next.due_date is null then null else
      jsonb_build_object('due_date', v_next.due_date, 'amount_centavos', v_next.amount) end,
    'amount_due_now_centavos', v_past_due + coalesce(case when v_next.due_date = v_today then v_next.amount end, 0)
  );
end $$;
revoke all on function public.get_shared_loan_status(text) from public;
grant execute on function public.get_shared_loan_status(text) to anon, authenticated;

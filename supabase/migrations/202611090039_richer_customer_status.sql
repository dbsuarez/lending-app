-- Customer status page: everything the borrower's PDFs show, for the
-- borrower only. Keeps every existing field (older pages keep working) and
-- adds: amount due now / past due / next due, per-installment still-owed and
-- due state, loan terms, the release, payoff amount today, business contacts,
-- and per-payment receipt details. Never exposes addresses, phone numbers of
-- the borrower, notes, late reasons, evidence, or full payment references.

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
  v_payoff bigint;
  v_release record;
  schedule_json jsonb;
  payment_json jsonb;
begin
  if length(coalesce(p_token, '')) <> 64 then raise exception 'Link is invalid or revoked'; end if;
  select * into target_link from public.loan_share_links
  where token_hash = extensions.digest(p_token, 'sha256') and revoked_at is null;
  if target_link.id is null then raise exception 'Link is invalid or revoked'; end if;

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
    sequence int, due_date date, scheduled bigint, principal bigint, interest bigint,
    paid bigint, paid_principal bigint, paid_interest bigint
  ) on commit drop;
  delete from _share_inst;
  insert into _share_inst
  select i.sequence, i.due_date, i.scheduled_centavos, i.principal_centavos, i.interest_centavos,
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

  -- Payoff today: unpaid principal + unpaid interest already due (future interest waived).
  if target_loan.status = 'active' then
    select coalesce(sum(greatest(principal - paid_principal, 0)), 0)
         + coalesce(sum(greatest(interest - paid_interest, 0)) filter (where due_date <= v_today), 0)
      into v_payoff from _share_inst;
  end if;

  select d.disbursed_on, d.amount_centavos into v_release
  from public.loan_disbursements d where d.loan_id = target_loan.id and d.voided_at is null
  order by d.created_at desc limit 1;

  select coalesce(jsonb_agg(jsonb_build_object(
      'sequence', sequence, 'due_date', due_date, 'scheduled_centavos', scheduled,
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
      'penalties', 'none',
      'early_payoff', 'future_interest_waived'),
    'release', case when v_release.disbursed_on is null then null else
      jsonb_build_object('released_on', v_release.disbursed_on, 'amount_centavos', v_release.amount_centavos) end,
    'past_due_centavos', v_past_due,
    'days_past_due', case when v_oldest_past is null then 0 else v_today - v_oldest_past end,
    'next_due', case when v_next.due_date is null then null else
      jsonb_build_object('due_date', v_next.due_date, 'amount_centavos', v_next.amount) end,
    'amount_due_now_centavos', v_past_due + coalesce(case when v_next.due_date = v_today then v_next.amount end, 0),
    'payoff_today_centavos', v_payoff
  );
end $$;
revoke all on function public.get_shared_loan_status(text) from public;
grant execute on function public.get_shared_loan_status(text) to anon, authenticated;

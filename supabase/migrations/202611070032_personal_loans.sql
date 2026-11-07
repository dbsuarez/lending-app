alter table public.loans
add column if not exists is_personal boolean not null default false;

create index if not exists loans_org_personal_status_idx
on public.loans (organization_id, is_personal, status);

create or replace function public.set_loan_personal(p_loan_id uuid, p_personal boolean)
returns void language plpgsql security definer set search_path = '' as $$
declare v_loan public.loans%rowtype;
begin
  select * into v_loan from public.loans where id=p_loan_id for update;
  if v_loan.id is null then raise exception 'Loan was not found'; end if;
  if not public.has_org_role(v_loan.organization_id,array['owner','manager']::public.app_role[]) then
    raise exception 'Owner or manager access is required';
  end if;
  update public.loans set is_personal=p_personal where id=p_loan_id;
  insert into public.audit_events(organization_id,actor_id,action,record_type,record_id,payload)
  values(v_loan.organization_id,auth.uid(),'loan_classification_changed','loan',p_loan_id,
    jsonb_build_object('is_personal',p_personal));
end $$;
revoke all on function public.set_loan_personal(uuid,boolean) from public;
grant execute on function public.set_loan_personal(uuid,boolean) to authenticated;

create or replace function public.organization_dashboard_summary(p_as_of date default current_date)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_org uuid; v_outstanding bigint; v_overdue bigint; v_overdue_count integer; v_due_today bigint; v_due_today_count integer;
begin
  select organization_id into v_org from public.organization_members
  where user_id=auth.uid() and status='active' order by organization_id limit 1;
  if v_org is null then raise exception 'Organization membership is required'; end if;
  with balances as (
    select i.id,i.due_date,greatest(i.scheduled_centavos-coalesce(sum(
      case when p.status='verified' then pa.principal_centavos+pa.interest_centavos+pa.penalty_centavos else 0 end),0),0) outstanding
    from public.installments i join public.loans l on l.id=i.loan_id and l.status='active' and not l.is_personal
    left join public.payment_allocations pa on pa.installment_id=i.id
    left join public.payments p on p.id=pa.payment_id
    where i.organization_id=v_org group by i.id,i.due_date,i.scheduled_centavos
  ) select coalesce(sum(outstanding),0),coalesce(sum(outstanding) filter(where due_date<p_as_of),0),
    count(*) filter(where due_date<p_as_of and outstanding>0),coalesce(sum(outstanding) filter(where due_date=p_as_of),0),
    count(*) filter(where due_date=p_as_of and outstanding>0)
  into v_outstanding,v_overdue,v_overdue_count,v_due_today,v_due_today_count from balances;
  return jsonb_build_object('as_of',p_as_of,'outstanding',v_outstanding,'overdue',v_overdue,
    'overdue_count',v_overdue_count,'due_today',v_due_today,'due_today_count',v_due_today_count);
end $$;

create or replace function public.organization_aging_report(p_as_of date default current_date)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_org uuid; v_current bigint; v_1_30 bigint; v_31_60 bigint; v_61_90 bigint; v_90_plus bigint;
begin
  select organization_id into v_org from public.organization_members
  where user_id=auth.uid() and status='active' order by organization_id limit 1;
  if v_org is null then raise exception 'Organization membership is required'; end if;
  with balances as (
    select i.due_date, greatest(i.scheduled_centavos-coalesce(sum(
      case when p.status='verified' then pa.principal_centavos+pa.interest_centavos+pa.penalty_centavos else 0 end
    ),0),0) outstanding
    from public.installments i
    join public.loans l on l.id=i.loan_id and l.status in ('active','fully_paid') and not l.is_personal
    left join public.payment_allocations pa on pa.installment_id=i.id
    left join public.payments p on p.id=pa.payment_id
    where i.organization_id=v_org group by i.id,i.due_date,i.scheduled_centavos
  ) select
    coalesce(sum(outstanding) filter(where due_date>=p_as_of),0),
    coalesce(sum(outstanding) filter(where p_as_of-due_date between 1 and 30),0),
    coalesce(sum(outstanding) filter(where p_as_of-due_date between 31 and 60),0),
    coalesce(sum(outstanding) filter(where p_as_of-due_date between 61 and 90),0),
    coalesce(sum(outstanding) filter(where p_as_of-due_date>90),0)
  into v_current,v_1_30,v_31_60,v_61_90,v_90_plus from balances;
  return jsonb_build_object('as_of',p_as_of,'current',v_current,'days_1_30',v_1_30,'days_31_60',v_31_60,
    'days_61_90',v_61_90,'days_90_plus',v_90_plus,'total',v_current+v_1_30+v_31_60+v_61_90+v_90_plus);
end $$;

revoke all on function public.organization_dashboard_summary(date) from public;
grant execute on function public.organization_dashboard_summary(date) to authenticated;
revoke all on function public.organization_aging_report(date) from public;
grant execute on function public.organization_aging_report(date) to authenticated;

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
    from public.installments i join public.loans l on l.id=i.loan_id and l.status='active'
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
revoke all on function public.organization_dashboard_summary(date) from public;
grant execute on function public.organization_dashboard_summary(date) to authenticated;

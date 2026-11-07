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
    join public.loans l on l.id=i.loan_id and l.status in ('active','fully_paid')
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
revoke all on function public.organization_aging_report(date) from public;
grant execute on function public.organization_aging_report(date) to authenticated;

create or replace function public.record_backup_verification(p_exported_at timestamptz, p_record_count integer)
returns uuid language plpgsql security definer set search_path = '' as $$
declare v_org uuid; v_id uuid := gen_random_uuid();
begin
  select organization_id into v_org from public.organization_members where user_id=auth.uid() and status='active' and role='owner' limit 1;
  if v_org is null then raise exception 'Owner access is required'; end if;
  insert into public.audit_events(organization_id,actor_id,action,record_type,record_id,payload)
  values(v_org,auth.uid(),'backup_export_verified','backup',v_id,jsonb_build_object('exported_at',p_exported_at,'record_count',p_record_count,'frequency','weekly','recovery_owner','owner'));
  return v_id;
end $$;
revoke all on function public.record_backup_verification(timestamptz,integer) from public;
grant execute on function public.record_backup_verification(timestamptz,integer) to authenticated;

create or replace function public.early_payoff_quote(p_loan_id uuid, p_payoff_date date default current_date)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_loan public.loans%rowtype; v_principal bigint; v_interest bigint;
begin
  select * into v_loan from public.loans where id=p_loan_id;
  if v_loan.id is null or not public.is_org_member(v_loan.organization_id) then raise exception 'Loan was not found'; end if;
  if v_loan.status <> 'active' then raise exception 'Early payoff requires an active loan'; end if;
  select
    coalesce(sum(greatest(i.principal_centavos-coalesce(a.principal,0),0)),0),
    coalesce(sum(case when i.due_date<=p_payoff_date then greatest(i.interest_centavos-coalesce(a.interest,0),0) else 0 end),0)
    into v_principal,v_interest
  from public.installments i left join (
    select pa.installment_id,sum(pa.principal_centavos) principal,sum(pa.interest_centavos) interest
    from public.payment_allocations pa join public.payments p on p.id=pa.payment_id
    where p.loan_id=p_loan_id and p.status='verified' group by pa.installment_id
  ) a on a.installment_id=i.id where i.loan_id=p_loan_id;
  return jsonb_build_object('principal_centavos',v_principal,'earned_interest_centavos',v_interest,
    'payoff_centavos',v_principal+v_interest,'payoff_date',p_payoff_date,'future_interest_waived',true);
end $$;
revoke all on function public.early_payoff_quote(uuid,date) from public;
grant execute on function public.early_payoff_quote(uuid,date) to authenticated;

create or replace function public.record_early_payoff(
  p_loan_id uuid, p_payoff_date date, p_method text, p_reference text,
  p_client_operation_id uuid, p_device_id text
) returns uuid language plpgsql security definer set search_path = '' as $$
declare
  v_loan public.loans%rowtype; v_quote jsonb; v_amount bigint; v_payment_id uuid;
  v_i record; v_paid_principal bigint; v_paid_interest bigint;
  v_principal bigint; v_interest bigint;
begin
  select * into v_loan from public.loans where id=p_loan_id for update;
  if v_loan.id is null or v_loan.status<>'active' then raise exception 'Early payoff requires an active loan'; end if;
  if not public.has_org_role(v_loan.organization_id,array['owner','manager']::public.app_role[]) then raise exception 'Owner or manager access is required'; end if;
  if p_method not in ('Cash','GCash','AUB','MariBank') or p_client_operation_id is null or length(btrim(coalesce(p_device_id,'')))=0 then
    raise exception 'Complete payoff details are required';
  end if;
  select id into v_payment_id from public.payments where organization_id=v_loan.organization_id and client_operation_id=p_client_operation_id;
  if v_payment_id is not null then return v_payment_id; end if;
  v_quote := public.early_payoff_quote(p_loan_id,p_payoff_date);
  v_amount := (v_quote->>'payoff_centavos')::bigint;
  if v_amount<=0 then raise exception 'No payoff balance remains'; end if;
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
  values(v_loan.organization_id,auth.uid(),'loan_settled_early','loan',v_loan.id,v_quote||jsonb_build_object('payment_id',v_payment_id));
  return v_payment_id;
end $$;
revoke all on function public.record_early_payoff(uuid,date,text,text,uuid,text) from public;
grant execute on function public.record_early_payoff(uuid,date,text,text,uuid,text) to authenticated;

create table public.loan_amendments (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations,
  loan_id uuid not null references public.loans,
  amendment_type text not null check (amendment_type in ('due_date','refinance')),
  reason text not null check (length(btrim(reason)) >= 3),
  consent_date date not null,
  previous_values jsonb not null,
  new_values jsonb not null,
  supporting_document_id uuid references public.loan_documents,
  client_operation_id uuid not null,
  created_by uuid not null references auth.users,
  created_at timestamptz not null default now(),
  unique (organization_id, client_operation_id)
);

create index loan_amendments_loan_created_idx
  on public.loan_amendments (loan_id, created_at desc);
alter table public.loan_amendments enable row level security;
create policy members_read_loan_amendments on public.loan_amendments
  for select using (public.is_org_member(organization_id));

create or replace function public.amend_installment_due_date(
  p_loan_id uuid, p_sequence integer, p_new_due_date date, p_reason text,
  p_consent_date date, p_supporting_document_id uuid, p_client_operation_id uuid
) returns uuid language plpgsql security definer set search_path = '' as $$
declare
  v_loan public.loans%rowtype; v_installment public.installments%rowtype;
  v_id uuid; v_allocated bigint;
begin
  select * into v_loan from public.loans where id=p_loan_id for update;
  if v_loan.id is null or v_loan.status <> 'active' then raise exception 'An active loan is required'; end if;
  if not public.has_org_role(v_loan.organization_id,array['owner','manager']::public.app_role[]) then raise exception 'Owner or manager access is required'; end if;
  if length(btrim(coalesce(p_reason,'')))<3 or p_consent_date is null or p_new_due_date is null or p_client_operation_id is null then raise exception 'Complete amendment details are required'; end if;
  select id into v_id from public.loan_amendments where organization_id=v_loan.organization_id and client_operation_id=p_client_operation_id;
  if v_id is not null then return v_id; end if;
  select * into v_installment from public.installments where loan_id=p_loan_id and sequence=p_sequence for update;
  if v_installment.id is null then raise exception 'Installment was not found'; end if;
  select coalesce(sum(pa.principal_centavos+pa.interest_centavos+pa.penalty_centavos),0)
    into v_allocated from public.payment_allocations pa join public.payments p on p.id=pa.payment_id
    where pa.installment_id=v_installment.id and p.status='verified';
  if v_allocated>0 then raise exception 'An installment with verified allocations cannot be amended'; end if;
  if exists(select 1 from public.installments i where i.loan_id=p_loan_id and i.sequence<p_sequence and i.due_date>=p_new_due_date) or
     exists(select 1 from public.installments i where i.loan_id=p_loan_id and i.sequence>p_sequence and i.due_date<=p_new_due_date)
  then raise exception 'The amended date must preserve schedule order'; end if;
  insert into public.loan_amendments(organization_id,loan_id,amendment_type,reason,consent_date,previous_values,new_values,supporting_document_id,client_operation_id,created_by)
  values(v_loan.organization_id,p_loan_id,'due_date',btrim(p_reason),p_consent_date,
    jsonb_build_object('sequence',p_sequence,'due_date',v_installment.due_date),
    jsonb_build_object('sequence',p_sequence,'due_date',p_new_due_date),p_supporting_document_id,p_client_operation_id,auth.uid()) returning id into v_id;
  update public.installments set due_date=p_new_due_date where id=v_installment.id;
  insert into public.audit_events(organization_id,actor_id,action,record_type,record_id,payload)
  values(v_loan.organization_id,auth.uid(),'loan_due_date_amended','loan',p_loan_id,jsonb_build_object('amendment_id',v_id,'sequence',p_sequence,'previous_due_date',v_installment.due_date,'new_due_date',p_new_due_date,'reason',btrim(p_reason),'consent_date',p_consent_date));
  return v_id;
end $$;
revoke all on function public.amend_installment_due_date(uuid,integer,date,text,date,uuid,uuid) from public;
grant execute on function public.amend_installment_due_date(uuid,integer,date,text,date,uuid,uuid) to authenticated;

create or replace function public.refinance_loan(
  p_source_loan_id uuid, p_principal_centavos bigint, p_monthly_rate_basis_points integer,
  p_term_months integer, p_installments jsonb, p_reason text, p_consent_date date,
  p_supporting_document_id uuid, p_client_operation_id uuid
) returns uuid language plpgsql security definer set search_path = '' as $$
declare
  v_source public.loans%rowtype; v_new_id uuid; v_total bigint; v_item jsonb; v_amendment_id uuid;
begin
  select * into v_source from public.loans where id=p_source_loan_id for update;
  if v_source.id is null or v_source.status<>'active' then raise exception 'An active source loan is required'; end if;
  if not public.has_org_role(v_source.organization_id,array['owner','manager']::public.app_role[]) then raise exception 'Owner or manager access is required'; end if;
  if p_principal_centavos<=0 or p_monthly_rate_basis_points<0 or p_term_months<=0 or jsonb_array_length(p_installments)=0 or length(btrim(coalesce(p_reason,'')))<3 or p_consent_date is null then raise exception 'Complete refinancing details are required'; end if;
  select loan_id into v_new_id from public.loan_amendments where organization_id=v_source.organization_id and client_operation_id=p_client_operation_id;
  if v_new_id is not null then return (select (new_values->>'new_loan_id')::uuid from public.loan_amendments where organization_id=v_source.organization_id and client_operation_id=p_client_operation_id); end if;
  select sum((x->>'scheduled_centavos')::bigint) into v_total from jsonb_array_elements(p_installments) x;
  insert into public.loans(organization_id,borrower_id,principal_centavos,monthly_rate_basis_points,term_months,total_centavos,status,terms_snapshot,created_by)
  values(v_source.organization_id,v_source.borrower_id,p_principal_centavos,p_monthly_rate_basis_points,p_term_months,v_total,'draft',jsonb_build_object('refinanced_from',v_source.id,'consent_date',p_consent_date),auth.uid()) returning id into v_new_id;
  for v_item in select * from jsonb_array_elements(p_installments) loop
    insert into public.installments(organization_id,loan_id,sequence,due_date,principal_centavos,interest_centavos,scheduled_centavos)
    values(v_source.organization_id,v_new_id,(v_item->>'sequence')::integer,(v_item->>'due_date')::date,(v_item->>'principal_centavos')::bigint,(v_item->>'interest_centavos')::bigint,(v_item->>'scheduled_centavos')::bigint);
  end loop;
  update public.loans set status='refinanced',terms_snapshot=terms_snapshot||jsonb_build_object('refinanced_to',v_new_id,'refinanced_on',p_consent_date) where id=v_source.id;
  insert into public.loan_amendments(organization_id,loan_id,amendment_type,reason,consent_date,previous_values,new_values,supporting_document_id,client_operation_id,created_by)
  values(v_source.organization_id,v_source.id,'refinance',btrim(p_reason),p_consent_date,to_jsonb(v_source),jsonb_build_object('new_loan_id',v_new_id,'principal_centavos',p_principal_centavos,'total_centavos',v_total,'monthly_rate_basis_points',p_monthly_rate_basis_points,'term_months',p_term_months),p_supporting_document_id,p_client_operation_id,auth.uid()) returning id into v_amendment_id;
  insert into public.audit_events(organization_id,actor_id,action,record_type,record_id,payload)
  values(v_source.organization_id,auth.uid(),'loan_refinanced','loan',v_source.id,jsonb_build_object('amendment_id',v_amendment_id,'new_loan_id',v_new_id,'reason',btrim(p_reason),'consent_date',p_consent_date));
  return v_new_id;
end $$;
revoke all on function public.refinance_loan(uuid,bigint,integer,integer,jsonb,text,date,uuid,uuid) from public;
grant execute on function public.refinance_loan(uuid,bigint,integer,integer,jsonb,text,date,uuid,uuid) to authenticated;

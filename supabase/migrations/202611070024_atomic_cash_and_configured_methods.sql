create or replace function public.record_pending_payment(
  p_loan_id uuid, p_amount_centavos bigint, p_received_at timestamptz,
  p_method text, p_reference text, p_client_operation_id uuid, p_device_id text
) returns uuid language plpgsql security definer set search_path = '' as $$
declare
  actor_id uuid := auth.uid(); target_loan public.loans%rowtype;
  existing_payment_id uuid; new_payment_id uuid; v_methods jsonb;
begin
  if actor_id is null then raise exception 'Authentication is required'; end if;
  select * into target_loan from public.loans where id=p_loan_id;
  if target_loan.id is null or target_loan.status<>'active' then raise exception 'Payments require an active loan'; end if;
  if not public.has_org_role(target_loan.organization_id,array['owner','manager','collector']::public.app_role[]) then raise exception 'Payment-entry access is required'; end if;
  select id into existing_payment_id from public.payments where organization_id=target_loan.organization_id and client_operation_id=p_client_operation_id;
  if existing_payment_id is not null then return existing_payment_id; end if;
  select coalesce(operational_preferences->'payment_methods','["Cash","GCash","AUB","MariBank"]'::jsonb)
    into v_methods from public.organizations where id=target_loan.organization_id;
  if p_amount_centavos<=0 or p_received_at is null or p_client_operation_id is null
    or length(btrim(coalesce(p_device_id,'')))=0
    or not exists(select 1 from jsonb_array_elements_text(v_methods) m where m.value=p_method) then
    raise exception 'Invalid payment details';
  end if;
  insert into public.payments(organization_id,loan_id,amount_centavos,received_at,method,reference,status,client_operation_id,device_id,created_by)
  values(target_loan.organization_id,target_loan.id,p_amount_centavos,p_received_at,p_method,nullif(btrim(coalesce(p_reference,'')),''),'pending',p_client_operation_id,btrim(p_device_id),actor_id)
  returning id into new_payment_id;
  insert into public.audit_events(organization_id,actor_id,action,record_type,record_id,payload)
  values(target_loan.organization_id,actor_id,'pending_payment_recorded','payment',new_payment_id,
    jsonb_build_object('loan_id',target_loan.id,'amount_centavos',p_amount_centavos,'client_operation_id',p_client_operation_id));
  if lower(p_method)='cash' then perform public.verify_payment(new_payment_id); end if;
  return new_payment_id;
end $$;
revoke all on function public.record_pending_payment(uuid,bigint,timestamptz,text,text,uuid,text) from public;
grant execute on function public.record_pending_payment(uuid,bigint,timestamptz,text,text,uuid,text) to authenticated;

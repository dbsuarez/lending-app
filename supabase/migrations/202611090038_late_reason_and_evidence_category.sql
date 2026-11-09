-- 1. Why a payment came after its due date (optional, recorded with the
--    payment and editable later).
-- 2. Changing the category of an uploaded evidence file.

alter table public.payments add column if not exists late_reason text;

-- Same as 202611070024 plus p_late_reason. The old 7-argument version is
-- dropped so existing callers (which pass 7 named arguments) resolve here.
drop function if exists public.record_pending_payment(uuid,bigint,timestamptz,text,text,uuid,text);
create or replace function public.record_pending_payment(
  p_loan_id uuid, p_amount_centavos bigint, p_received_at timestamptz,
  p_method text, p_reference text, p_client_operation_id uuid, p_device_id text,
  p_late_reason text default null
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
  insert into public.payments(organization_id,loan_id,amount_centavos,received_at,method,reference,status,client_operation_id,device_id,created_by,late_reason)
  values(target_loan.organization_id,target_loan.id,p_amount_centavos,p_received_at,p_method,nullif(btrim(coalesce(p_reference,'')),''),'pending',p_client_operation_id,btrim(p_device_id),actor_id,
    nullif(btrim(coalesce(p_late_reason,'')),''))
  returning id into new_payment_id;
  insert into public.audit_events(organization_id,actor_id,action,record_type,record_id,payload)
  values(target_loan.organization_id,actor_id,'pending_payment_recorded','payment',new_payment_id,
    jsonb_strip_nulls(jsonb_build_object('loan_id',target_loan.id,'amount_centavos',p_amount_centavos,
      'client_operation_id',p_client_operation_id,'late_reason',nullif(btrim(coalesce(p_late_reason,'')),''))));
  if lower(p_method)='cash' then perform public.verify_payment(new_payment_id); end if;
  return new_payment_id;
end $$;
revoke all on function public.record_pending_payment(uuid,bigint,timestamptz,text,text,uuid,text,text) from public;
grant execute on function public.record_pending_payment(uuid,bigint,timestamptz,text,text,uuid,text,text) to authenticated;

create or replace function public.set_payment_late_reason(p_payment_id uuid, p_reason text)
returns void language plpgsql security definer set search_path = '' as $$
declare v_payment public.payments%rowtype; v_reason text := nullif(btrim(coalesce(p_reason,'')),'');
begin
  if auth.uid() is null then raise exception 'Authentication is required'; end if;
  select * into v_payment from public.payments where id=p_payment_id for update;
  if v_payment.id is null then raise exception 'Payment was not found'; end if;
  if not public.has_org_role(v_payment.organization_id,array['owner','manager','collector']::public.app_role[]) then
    raise exception 'Payment-entry access is required';
  end if;
  if v_payment.late_reason is not distinct from v_reason then return; end if;
  update public.payments set late_reason=v_reason where id=p_payment_id;
  insert into public.audit_events(organization_id,actor_id,action,record_type,record_id,payload)
  values(v_payment.organization_id,auth.uid(),'payment_late_reason_set','payment',p_payment_id,
    jsonb_build_object('loan_id',v_payment.loan_id,'previous',v_payment.late_reason,'reason',v_reason));
end $$;
revoke all on function public.set_payment_late_reason(uuid,text) from public;
grant execute on function public.set_payment_late_reason(uuid,text) to authenticated;

-- New evidence category: the borrower's own explanation for paying late
-- and/or a promise to pay (e.g. a screenshot of their message).
alter table public.loan_documents drop constraint if exists loan_documents_document_type_check;
alter table public.loan_documents add constraint loan_documents_document_type_check
  check (document_type in ('disbursement_evidence','payment_evidence','late_payment_note',
                           'agreement','acknowledgment','other'));

create or replace function public.register_loan_document(
  p_loan_id uuid, p_document_type text, p_storage_path text,
  p_original_name text, p_mime_type text, p_size_bytes bigint
) returns uuid language plpgsql security definer set search_path = '' as $$
declare v_loan public.loans%rowtype; v_id uuid;
begin
  select * into v_loan from public.loans where id=p_loan_id;
  if v_loan.id is null or not public.has_org_role(v_loan.organization_id,array['owner','manager','collector']::public.app_role[]) then
    raise exception 'Loan document access is required';
  end if;
  if p_document_type not in ('disbursement_evidence','payment_evidence','late_payment_note','agreement','acknowledgment','other')
    or p_mime_type not in ('application/pdf','image/jpeg','image/png')
    or p_size_bytes <= 0 or p_size_bytes > 10485760
    or p_storage_path not like v_loan.organization_id::text || '/' || v_loan.id::text || '/%' then
    raise exception 'Invalid document metadata';
  end if;
  insert into public.loan_documents(organization_id,loan_id,document_type,storage_path,original_name,mime_type,size_bytes,created_by)
  values(v_loan.organization_id,v_loan.id,p_document_type,p_storage_path,btrim(p_original_name),p_mime_type,p_size_bytes,auth.uid()) returning id into v_id;
  insert into public.audit_events(organization_id,actor_id,action,record_type,record_id,payload)
  values(v_loan.organization_id,auth.uid(),'loan_document_registered','loan_document',v_id,jsonb_build_object('loan_id',v_loan.id,'document_type',p_document_type));
  return v_id;
end $$;
revoke all on function public.register_loan_document(uuid,text,text,text,text,bigint) from public;
grant execute on function public.register_loan_document(uuid,text,text,text,text,bigint) to authenticated;

create or replace function public.set_loan_document_type(p_document_id uuid, p_document_type text)
returns void language plpgsql security definer set search_path = '' as $$
declare v_doc public.loan_documents%rowtype;
begin
  if auth.uid() is null then raise exception 'Authentication is required'; end if;
  select * into v_doc from public.loan_documents where id=p_document_id for update;
  if v_doc.id is null then raise exception 'Document was not found'; end if;
  if not public.has_org_role(v_doc.organization_id,array['owner','manager','collector']::public.app_role[]) then
    raise exception 'Loan document access is required';
  end if;
  if p_document_type not in ('disbursement_evidence','payment_evidence','late_payment_note','agreement','acknowledgment','other') then
    raise exception 'Unknown document category';
  end if;
  if v_doc.document_type = p_document_type then return; end if;
  update public.loan_documents set document_type=p_document_type where id=p_document_id;
  insert into public.audit_events(organization_id,actor_id,action,record_type,record_id,payload)
  values(v_doc.organization_id,auth.uid(),'loan_document_recategorized','loan_document',p_document_id,
    jsonb_build_object('loan_id',v_doc.loan_id,'from',v_doc.document_type,'to',p_document_type));
end $$;
revoke all on function public.set_loan_document_type(uuid,text) from public;
grant execute on function public.set_loan_document_type(uuid,text) to authenticated;

alter table public.organizations
  add column if not exists policy_preferences jsonb not null default jsonb_build_object(
    'retention_years', 10,
    'consent_version', 'interim-v1',
    'backup_frequency', 'weekly',
    'backup_owner_role', 'owner',
    'evidence_max_bytes', 10485760,
    'legal_review_required', true
  );

alter table public.borrowers
  add column if not exists consent_given_at timestamptz,
  add column if not exists consent_version text,
  add column if not exists retention_until date;

alter table public.payments
  add column if not exists verified_at timestamptz,
  add column if not exists verified_by uuid references auth.users,
  add column if not exists reversed_at timestamptz,
  add column if not exists reversed_by uuid references auth.users,
  add column if not exists reversal_reason text,
  add column if not exists unapplied_centavos bigint not null default 0
    check (unapplied_centavos >= 0);

create table if not exists public.loan_documents (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id),
  loan_id uuid not null references public.loans(id),
  document_type text not null check (document_type in ('disbursement_evidence','payment_evidence','agreement','acknowledgment','other')),
  storage_path text not null,
  original_name text not null,
  mime_type text not null check (mime_type in ('application/pdf','image/jpeg','image/png')),
  size_bytes bigint not null check (size_bytes > 0 and size_bytes <= 10485760),
  created_by uuid not null references auth.users(id),
  created_at timestamptz not null default now(),
  unique (organization_id, storage_path)
);

alter table public.loan_documents enable row level security;
create policy members_read_loan_documents on public.loan_documents
  for select using (public.is_org_member(organization_id));

create table if not exists public.staff_invitations (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id),
  email text not null,
  role public.app_role not null,
  status text not null default 'pending' check (status in ('pending','accepted','revoked','expired')),
  invited_by uuid not null references auth.users(id),
  expires_at timestamptz not null default (now() + interval '7 days'),
  created_at timestamptz not null default now(),
  accepted_at timestamptz
);

create unique index if not exists staff_invitations_pending_email_idx
  on public.staff_invitations (organization_id, lower(email)) where status = 'pending';
alter table public.staff_invitations enable row level security;
create policy managers_read_staff_invitations on public.staff_invitations
  for select using (public.has_org_role(organization_id, array['owner','manager']::public.app_role[]));

create or replace function public.record_borrower_consent(p_borrower_id uuid)
returns uuid language plpgsql security definer set search_path = '' as $$
declare
  v_borrower public.borrowers%rowtype;
  v_version text;
  v_years integer;
begin
  select * into v_borrower from public.borrowers where id = p_borrower_id for update;
  if v_borrower.id is null or not public.has_org_role(v_borrower.organization_id, array['owner','manager','collector']::public.app_role[]) then
    raise exception 'Borrower access is required';
  end if;
  select coalesce(policy_preferences->>'consent_version','interim-v1'),
         coalesce((policy_preferences->>'retention_years')::integer,10)
    into v_version, v_years from public.organizations where id = v_borrower.organization_id;
  update public.borrowers set consent_given_at = now(), consent_version = v_version,
    retention_until = (current_date + make_interval(years => v_years))::date
    where id = v_borrower.id;
  insert into public.audit_events (organization_id, actor_id, action, record_type, record_id, payload)
  values (v_borrower.organization_id, auth.uid(), 'borrower_consent_recorded', 'borrower', v_borrower.id,
    jsonb_build_object('consent_version',v_version,'retention_years',v_years,'interim_policy',true));
  return v_borrower.id;
end $$;
revoke all on function public.record_borrower_consent(uuid) from public;
grant execute on function public.record_borrower_consent(uuid) to authenticated;

create or replace function public.verify_payment(p_payment_id uuid)
returns uuid language plpgsql security definer set search_path = '' as $$
declare
  v_payment public.payments%rowtype;
  v_installment record;
  v_remaining bigint;
  v_interest bigint;
  v_principal bigint;
  v_paid_interest bigint;
  v_paid_principal bigint;
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
  v_remaining := v_payment.amount_centavos;
  for v_installment in
    select i.* from public.installments i where i.loan_id = v_payment.loan_id order by i.due_date, i.sequence for update
  loop
    select coalesce(sum(a.interest_centavos),0), coalesce(sum(a.principal_centavos),0)
      into v_paid_interest, v_paid_principal
      from public.payment_allocations a join public.payments p on p.id = a.payment_id
      where a.installment_id = v_installment.id and p.status = 'verified';
    v_interest := least(v_remaining, greatest(v_installment.interest_centavos - v_paid_interest, 0));
    v_remaining := v_remaining - v_interest;
    v_principal := least(v_remaining, greatest(v_installment.principal_centavos - v_paid_principal, 0));
    v_remaining := v_remaining - v_principal;
    if v_interest + v_principal > 0 then
      insert into public.payment_allocations (organization_id,payment_id,installment_id,principal_centavos,interest_centavos,penalty_centavos)
      values (v_payment.organization_id,v_payment.id,v_installment.id,v_principal,v_interest,0);
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
    jsonb_build_object('allocated_centavos',v_payment.amount_centavos-v_remaining,'unapplied_centavos',v_remaining,'allocation_order','oldest_due_interest_principal'));
  return v_payment.id;
end $$;
revoke all on function public.verify_payment(uuid) from public;
grant execute on function public.verify_payment(uuid) to authenticated;

create or replace function public.reverse_payment(p_payment_id uuid, p_reason text)
returns uuid language plpgsql security definer set search_path = '' as $$
declare v_payment public.payments%rowtype;
begin
  select * into v_payment from public.payments where id = p_payment_id for update;
  if v_payment.id is null then raise exception 'Payment was not found'; end if;
  if not public.has_org_role(v_payment.organization_id, array['owner','manager']::public.app_role[]) then raise exception 'Owner or manager access is required'; end if;
  if v_payment.status <> 'verified' then raise exception 'Only a verified payment can be reversed'; end if;
  if length(btrim(coalesce(p_reason,''))) < 3 then raise exception 'A clear reversal reason is required'; end if;
  delete from public.payment_allocations where payment_id = v_payment.id;
  update public.payments set status = 'reversed', reversed_at = now(), reversed_by = auth.uid(),
    reversal_reason = btrim(p_reason), unapplied_centavos = 0 where id = v_payment.id;
  update public.loans set status = 'active' where id = v_payment.loan_id and status = 'fully_paid';
  insert into public.audit_events (organization_id, actor_id, action, record_type, record_id, payload)
  values (v_payment.organization_id, auth.uid(), 'payment_reversed', 'payment', v_payment.id,
    jsonb_build_object('reason',btrim(p_reason)));
  return v_payment.id;
end $$;
revoke all on function public.reverse_payment(uuid,text) from public;
grant execute on function public.reverse_payment(uuid,text) to authenticated;

create or replace function public.create_staff_invitation(p_organization_id uuid, p_email text, p_role public.app_role)
returns uuid language plpgsql security definer set search_path = '' as $$
declare v_id uuid; v_actor_role public.app_role;
begin
  select role into v_actor_role from public.organization_members where organization_id=p_organization_id and user_id=auth.uid() and status='active';
  if v_actor_role is null or v_actor_role not in ('owner','manager') then raise exception 'Owner or manager access is required'; end if;
  if v_actor_role='manager' and p_role not in ('collector','auditor') then raise exception 'Managers may invite collectors or auditors only'; end if;
  if length(btrim(coalesce(p_email,''))) < 5 then raise exception 'A valid email is required'; end if;
  insert into public.staff_invitations (organization_id,email,role,invited_by)
  values (p_organization_id,lower(btrim(p_email)),p_role,auth.uid()) returning id into v_id;
  insert into public.audit_events (organization_id,actor_id,action,record_type,record_id,payload)
  values (p_organization_id,auth.uid(),'staff_invitation_created','staff_invitation',v_id,jsonb_build_object('email',lower(btrim(p_email)),'role',p_role));
  return v_id;
end $$;
revoke all on function public.create_staff_invitation(uuid,text,public.app_role) from public;
grant execute on function public.create_staff_invitation(uuid,text,public.app_role) to authenticated;

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
  if p_document_type not in ('disbursement_evidence','payment_evidence','agreement','acknowledgment','other')
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

insert into storage.buckets (id,name,public,file_size_limit,allowed_mime_types)
values ('loan-evidence','loan-evidence',false,10485760,array['application/pdf','image/jpeg','image/png'])
on conflict (id) do update set public=false,file_size_limit=10485760,allowed_mime_types=excluded.allowed_mime_types;

create policy org_members_read_loan_evidence on storage.objects for select to authenticated
using (bucket_id='loan-evidence' and public.is_org_member((storage.foldername(name))[1]::uuid));
create policy org_staff_upload_loan_evidence on storage.objects for insert to authenticated
with check (bucket_id='loan-evidence' and public.has_org_role((storage.foldername(name))[1]::uuid,array['owner','manager','collector']::public.app_role[]));

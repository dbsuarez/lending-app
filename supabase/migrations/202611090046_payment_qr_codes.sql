create table public.payment_qr_codes (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  label text not null check (char_length(btrim(label)) between 1 and 60),
  storage_path text not null,
  mime_type text not null check (mime_type in ('image/png','image/jpeg')),
  enabled boolean not null default true,
  sort_order integer not null default 0 check (sort_order >= 0),
  created_by uuid not null references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (organization_id, storage_path)
);

create index payment_qr_codes_org_order_idx
  on public.payment_qr_codes (organization_id, sort_order, created_at);

alter table public.payment_qr_codes enable row level security;
create policy org_members_read_payment_qrs on public.payment_qr_codes
  for select to authenticated using (public.is_org_member(organization_id));
create policy org_managers_insert_payment_qrs on public.payment_qr_codes
  for insert to authenticated with check (
    created_by=auth.uid() and
    public.has_org_role(organization_id,array['owner','manager']::public.app_role[]) and
    storage_path like organization_id::text||'/%'
  );
create policy org_managers_update_payment_qrs on public.payment_qr_codes
  for update to authenticated using (
    public.has_org_role(organization_id,array['owner','manager']::public.app_role[])
  ) with check (
    public.has_org_role(organization_id,array['owner','manager']::public.app_role[]) and
    storage_path like organization_id::text||'/%'
  );
create policy org_managers_delete_payment_qrs on public.payment_qr_codes
  for delete to authenticated using (
    public.has_org_role(organization_id,array['owner','manager']::public.app_role[])
  );

create or replace function public.audit_payment_qr_change()
returns trigger language plpgsql security definer set search_path=public as $$
declare v_org uuid:=coalesce(new.organization_id,old.organization_id); v_id uuid:=coalesce(new.id,old.id);
begin
  if tg_op='INSERT' then new.updated_at=now();
  elsif tg_op='UPDATE' then new.updated_at=now();
  end if;
  insert into public.audit_events(organization_id,actor_id,action,record_type,record_id,payload)
  values(v_org,auth.uid(),'payment_qr_'||lower(tg_op),'payment_qr',v_id,
    case when tg_op='DELETE' then jsonb_build_object('label',old.label)
         when tg_op='INSERT' then jsonb_build_object('label',new.label,'enabled',new.enabled)
         else jsonb_build_object('before',jsonb_build_object('label',old.label,'enabled',old.enabled,'sort_order',old.sort_order),'after',jsonb_build_object('label',new.label,'enabled',new.enabled,'sort_order',new.sort_order)) end);
  return case when tg_op='DELETE' then old else new end;
end $$;
create trigger payment_qr_audit before insert or update or delete on public.payment_qr_codes
for each row execute function public.audit_payment_qr_change();

insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values('payment-qrs','payment-qrs',false,5242880,array['image/png','image/jpeg'])
on conflict(id) do update set public=false,file_size_limit=5242880,allowed_mime_types=excluded.allowed_mime_types;

create policy org_members_read_payment_qr_files on storage.objects for select to authenticated
using(bucket_id='payment-qrs' and public.is_org_member((storage.foldername(name))[1]::uuid));
create policy org_managers_insert_payment_qr_files on storage.objects for insert to authenticated
with check(bucket_id='payment-qrs' and public.has_org_role((storage.foldername(name))[1]::uuid,array['owner','manager']::public.app_role[]));
create policy org_managers_update_payment_qr_files on storage.objects for update to authenticated
using(bucket_id='payment-qrs' and public.has_org_role((storage.foldername(name))[1]::uuid,array['owner','manager']::public.app_role[]));
create policy org_managers_delete_payment_qr_files on storage.objects for delete to authenticated
using(bucket_id='payment-qrs' and public.has_org_role((storage.foldername(name))[1]::uuid,array['owner','manager']::public.app_role[]));

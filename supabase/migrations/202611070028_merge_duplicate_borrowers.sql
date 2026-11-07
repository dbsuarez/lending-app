create or replace function public.merge_duplicate_borrowers(
  p_keep_borrower_id uuid,
  p_merge_borrower_id uuid,
  p_reason text
) returns uuid language plpgsql security definer set search_path = '' as $$
declare
  v_keep public.borrowers%rowtype;
  v_merge public.borrowers%rowtype;
  v_loan_count integer;
begin
  if p_keep_borrower_id=p_merge_borrower_id then raise exception 'Choose two different borrowers'; end if;
  select * into v_keep from public.borrowers where id=p_keep_borrower_id for update;
  select * into v_merge from public.borrowers where id=p_merge_borrower_id for update;
  if v_keep.id is null or v_merge.id is null or v_keep.organization_id<>v_merge.organization_id then raise exception 'Borrowers were not found in the same organization'; end if;
  if not public.has_org_role(v_keep.organization_id,array['owner','manager']::public.app_role[]) then raise exception 'Owner or manager access is required'; end if;
  if length(btrim(coalesce(p_reason,'')))<3 then raise exception 'A merge reason is required'; end if;
  update public.loans set borrower_id=v_keep.id where borrower_id=v_merge.id;
  get diagnostics v_loan_count = row_count;
  update public.borrowers set
    phone=coalesce(nullif(phone,''),v_merge.phone),
    email=coalesce(nullif(email,''),v_merge.email),
    address=coalesce(nullif(address,''),v_merge.address),
    updated_at=now()
  where id=v_keep.id;
  update public.borrowers set archived_at=coalesce(archived_at,now()),updated_at=now() where id=v_merge.id;
  insert into public.audit_events(organization_id,actor_id,action,record_type,record_id,payload)
  values(v_keep.organization_id,auth.uid(),'borrowers_merged','borrower',v_keep.id,
    jsonb_build_object('merged_borrower_id',v_merge.id,'merged_name',concat_ws(' ',v_merge.first_name,v_merge.last_name),'loan_count',v_loan_count,'reason',btrim(p_reason)));
  return v_keep.id;
end $$;
revoke all on function public.merge_duplicate_borrowers(uuid,uuid,text) from public;
grant execute on function public.merge_duplicate_borrowers(uuid,uuid,text) to authenticated;

create or replace function public.update_collection_activity(
  p_activity_id uuid,
  p_activity_type text,
  p_outcome text,
  p_notes text default '',
  p_promised_on date default null,
  p_promised_amount_centavos bigint default null
)
returns void language plpgsql security definer set search_path = public as $$
declare v_activity public.collection_activities%rowtype; v_type text := lower(btrim(coalesce(p_activity_type,''))); v_outcome text := btrim(coalesce(p_outcome,''));
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  select * into v_activity from public.collection_activities where id=p_activity_id and undone_at is null for update;
  if not found then raise exception 'Collection activity not found'; end if;
  if not public.has_org_role(v_activity.organization_id,array['owner','manager','collector']::public.app_role[]) then raise exception 'Collection access required'; end if;
  if v_type not in ('call','sms','visit','email','promise') then raise exception 'Unsupported activity type'; end if;
  if char_length(v_outcome)<2 then raise exception 'Outcome is required'; end if;
  if v_type='promise' and (p_promised_on is null or coalesce(p_promised_amount_centavos,0)<=0) then raise exception 'Promise date and amount are required'; end if;
  update public.collection_activities set activity_type=v_type,outcome=v_outcome,notes=btrim(coalesce(p_notes,'')),promised_on=case when v_type='promise' then p_promised_on end,promised_amount_centavos=case when v_type='promise' then p_promised_amount_centavos end where id=p_activity_id;
  insert into public.audit_events(organization_id,actor_id,action,record_type,record_id,payload) values(v_activity.organization_id,auth.uid(),'collection_activity_updated','collection_activity',p_activity_id,jsonb_build_object('before',jsonb_build_object('type',v_activity.activity_type,'outcome',v_activity.outcome,'notes',v_activity.notes,'promised_on',v_activity.promised_on,'promised_amount_centavos',v_activity.promised_amount_centavos),'after',jsonb_build_object('type',v_type,'outcome',v_outcome,'notes',btrim(coalesce(p_notes,'')),'promised_on',case when v_type='promise' then p_promised_on end,'promised_amount_centavos',case when v_type='promise' then p_promised_amount_centavos end)));
end $$;

create or replace function public.delete_collection_activity(p_activity_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare v_activity public.collection_activities%rowtype;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  select * into v_activity from public.collection_activities where id=p_activity_id and undone_at is null for update;
  if not found then raise exception 'Collection activity not found'; end if;
  if not public.has_org_role(v_activity.organization_id,array['owner','manager']::public.app_role[]) then raise exception 'Owner or manager access is required'; end if;
  update public.collection_activities set undone_at=now(),undone_by=auth.uid() where id=p_activity_id;
  insert into public.audit_events(organization_id,actor_id,action,record_type,record_id,payload) values(v_activity.organization_id,auth.uid(),'collection_activity_deleted','collection_activity',p_activity_id,jsonb_build_object('loan_id',v_activity.loan_id,'type',v_activity.activity_type,'outcome',v_activity.outcome));
end $$;

revoke all on function public.update_collection_activity(uuid,text,text,text,date,bigint) from public;
grant execute on function public.update_collection_activity(uuid,text,text,text,date,bigint) to authenticated;
revoke all on function public.delete_collection_activity(uuid) from public;
grant execute on function public.delete_collection_activity(uuid) to authenticated;

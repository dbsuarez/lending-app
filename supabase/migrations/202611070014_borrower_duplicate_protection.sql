drop policy if exists staff_add_borrowers on public.borrowers;

create or replace function public.save_borrower(
  p_id uuid,
  p_first_name text,
  p_last_name text,
  p_phone text default null,
  p_email text default null,
  p_address text default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_org_id uuid;
  v_id uuid;
  v_first text := btrim(coalesce(p_first_name, ''));
  v_last text := btrim(coalesce(p_last_name, ''));
  v_phone text := nullif(btrim(coalesce(p_phone, '')), '');
  v_email text := nullif(lower(btrim(coalesce(p_email, ''))), '');
  v_phone_key text := regexp_replace(coalesce(p_phone, ''), '[^0-9]+', '', 'g');
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  if char_length(v_first) < 1 or char_length(v_last) < 1 then
    raise exception 'First and last name are required';
  end if;

  if p_id is null then
    select organization_id into v_org_id
    from public.organization_members
    where user_id = auth.uid() and status = 'active'
    order by case role when 'owner' then 1 when 'manager' then 2 when 'collector' then 3 else 4 end
    limit 1;
  else
    select organization_id into v_org_id from public.borrowers where id = p_id;
  end if;
  if v_org_id is null or not public.has_org_role(
    v_org_id, array['owner', 'manager', 'collector']::public.app_role[]
  ) then raise exception 'Borrower write access required'; end if;

  perform pg_advisory_xact_lock(hashtextextended(v_org_id::text || ':' || v_phone_key || ':' || coalesce(v_email, ''), 0));
  if exists (
    select 1 from public.borrowers b
    where b.organization_id = v_org_id
      and b.archived_at is null
      and b.id is distinct from p_id
      and (
        (char_length(v_phone_key) >= 7 and regexp_replace(coalesce(b.phone, ''), '[^0-9]+', '', 'g') = v_phone_key)
        or (v_email is not null and lower(coalesce(b.email, '')) = v_email)
      )
  ) then raise exception 'An active borrower with this phone or email already exists'; end if;

  if p_id is null then
    insert into public.borrowers (
      organization_id, first_name, last_name, phone, email, address, created_by
    ) values (
      v_org_id, v_first, v_last, v_phone, v_email,
      nullif(btrim(coalesce(p_address, '')), ''), auth.uid()
    ) returning id into v_id;
  else
    update public.borrowers set
      first_name = v_first, last_name = v_last, phone = v_phone, email = v_email,
      address = nullif(btrim(coalesce(p_address, '')), ''), updated_at = now()
    where id = p_id and organization_id = v_org_id
    returning id into v_id;
  end if;

  insert into public.audit_events (organization_id, actor_id, action, record_type, record_id, payload)
  values (v_org_id, auth.uid(), case when p_id is null then 'borrower_created' else 'borrower_updated' end,
    'borrower', v_id, jsonb_build_object('duplicate_keys_checked', true));
  return v_id;
end;
$$;

revoke all on function public.save_borrower(uuid, text, text, text, text, text) from public;
grant execute on function public.save_borrower(uuid, text, text, text, text, text) to authenticated;

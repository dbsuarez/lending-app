create or replace function public.get_shared_business_name(p_token text)
returns text language plpgsql security definer set search_path = '' as $$
declare v_name text;
begin
  if length(coalesce(p_token,''))<>64 then raise exception 'Link is invalid or expired'; end if;
  select o.name into v_name
  from public.loan_share_links l join public.organizations o on o.id=l.organization_id
  where l.token_hash=extensions.digest(p_token,'sha256') and l.revoked_at is null and l.expires_at>now();
  if v_name is null then raise exception 'Link is invalid or expired'; end if;
  return v_name;
end $$;
revoke all on function public.get_shared_business_name(text) from public;
grant execute on function public.get_shared_business_name(text) to anon,authenticated;

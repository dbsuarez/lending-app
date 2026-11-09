-- Private helper used by the shared-payment-qrs Edge Function. It reveals
-- enabled QR metadata only after validating a non-revoked customer link.
create or replace function public.get_shared_payment_qrs(p_token text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_organization_id uuid;
begin
  if length(coalesce(p_token, '')) <> 64 then
    raise exception 'Link is invalid or revoked';
  end if;

  select l.organization_id
  into v_organization_id
  from public.loan_share_links s
  join public.loans l on l.id = s.loan_id
  where s.token_hash = extensions.digest(p_token, 'sha256')
    and s.revoked_at is null;

  if v_organization_id is null then
    raise exception 'Link is invalid or revoked';
  end if;

  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'label', q.label,
      'storage_path', q.storage_path
    ) order by q.sort_order, q.created_at)
    from public.payment_qr_codes q
    where q.organization_id = v_organization_id
      and q.enabled
  ), '[]'::jsonb);
end
$$;

revoke all on function public.get_shared_payment_qrs(text) from public, anon, authenticated;
grant execute on function public.get_shared_payment_qrs(text) to service_role;

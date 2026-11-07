create or replace function public.reject_payment(
  p_payment_id uuid,
  p_reason text
) returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor_id uuid := auth.uid();
  target_payment public.payments%rowtype;
begin
  if actor_id is null then
    raise exception 'Authentication is required';
  end if;

  select *
    into target_payment
    from public.payments
   where id = p_payment_id
   for update;

  if target_payment.id is null then
    raise exception 'Payment was not found';
  end if;
  if not public.has_org_role(
    target_payment.organization_id,
    array['owner', 'manager']::public.app_role[]
  ) then
    raise exception 'Owner or manager access is required';
  end if;
  if target_payment.status <> 'pending' then
    raise exception 'Only a pending payment can be rejected';
  end if;
  if length(trim(coalesce(p_reason, ''))) < 3 then
    raise exception 'A rejection reason is required';
  end if;

  update public.payments
     set status = 'rejected'
   where id = target_payment.id;

  insert into public.audit_events (
    organization_id,
    actor_id,
    action,
    record_type,
    record_id,
    payload
  ) values (
    target_payment.organization_id,
    actor_id,
    'payment_rejected',
    'payment',
    target_payment.id,
    jsonb_build_object('reason', trim(p_reason))
  );

  return target_payment.id;
end
$$;

revoke all on function public.reject_payment(uuid, text) from public;
grant execute on function public.reject_payment(uuid, text) to authenticated;

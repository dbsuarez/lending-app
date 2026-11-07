-- One copyable customer link per loan.
--
-- Until now only the SHA-256 of a link token was stored, so an existing link
-- could never be shown again and every "Create link" made a new one. The
-- token is now also stored so owners/managers (the only roles that can read
-- loan_share_links, see managers_read_loan_share_links) can copy it again,
-- and creating a link returns the loan's existing active link instead of
-- making another. Older links have no stored token: they keep working but
-- cannot be copied; they can be revoked as before.

alter table public.loan_share_links add column if not exists token text;

-- At most one active, copyable link per loan (also guards concurrent taps).
create unique index if not exists loan_share_links_one_active_per_loan_idx
  on public.loan_share_links (loan_id)
  where revoked_at is null and token is not null;

create or replace function public.create_loan_share_link(
  p_loan_id uuid,
  p_expires_at timestamptz
) returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor_id uuid := auth.uid();
  target_loan public.loans%rowtype;
  existing public.loan_share_links%rowtype;
  raw_token text;
  new_link_id uuid;
begin
  if actor_id is null then raise exception 'Authentication is required'; end if;
  select * into target_loan from public.loans where id = p_loan_id for update;
  if target_loan.id is null then raise exception 'Loan was not found'; end if;
  if not public.has_org_role(target_loan.organization_id, array['owner', 'manager']::public.app_role[]) then
    raise exception 'Owner or manager access is required';
  end if;

  -- Reuse the loan's active copyable link if there is one.
  select * into existing from public.loan_share_links
   where loan_id = target_loan.id and revoked_at is null and token is not null
   order by created_at desc limit 1;
  if existing.id is not null then
    return jsonb_build_object('id', existing.id, 'token', existing.token, 'reused', true);
  end if;

  raw_token := encode(extensions.gen_random_bytes(32), 'hex');
  insert into public.loan_share_links (
    organization_id, loan_id, token_hash, token, expires_at, created_by
  ) values (
    target_loan.organization_id, target_loan.id,
    extensions.digest(raw_token, 'sha256'), raw_token,
    '9999-12-31 23:59:59+00'::timestamptz, actor_id
  ) returning id into new_link_id;

  insert into public.audit_events (
    organization_id, actor_id, action, record_type, record_id, payload
  ) values (
    target_loan.organization_id, actor_id, 'loan_share_link_created',
    'loan_share_link', new_link_id, jsonb_build_object('loan_id', target_loan.id)
  );

  return jsonb_build_object('id', new_link_id, 'token', raw_token, 'reused', false);
end
$$;

revoke all on function public.create_loan_share_link(uuid, timestamptz) from public;
grant execute on function public.create_loan_share_link(uuid, timestamptz) to authenticated;

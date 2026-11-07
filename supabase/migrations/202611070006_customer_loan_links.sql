create table public.loan_share_links (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations,
  loan_id uuid not null references public.loans,
  token_hash bytea not null unique,
  expires_at timestamptz not null,
  revoked_at timestamptz,
  last_accessed_at timestamptz,
  created_by uuid not null references auth.users,
  created_at timestamptz not null default now()
);

create index loan_share_links_loan_idx
  on public.loan_share_links (organization_id, loan_id, created_at desc);

alter table public.loan_share_links enable row level security;

create policy managers_read_loan_share_links
  on public.loan_share_links
  for select
  using (
    public.has_org_role(
      organization_id,
      array['owner', 'manager']::public.app_role[]
    )
  );

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
  raw_token text;
  new_link_id uuid;
begin
  if actor_id is null then
    raise exception 'Authentication is required';
  end if;

  select * into target_loan from public.loans where id = p_loan_id;
  if target_loan.id is null then
    raise exception 'Loan was not found';
  end if;
  if not public.has_org_role(
    target_loan.organization_id,
    array['owner', 'manager']::public.app_role[]
  ) then
    raise exception 'Owner or manager access is required';
  end if;
  if p_expires_at <= now() or p_expires_at > now() + interval '365 days' then
    raise exception 'Expiry must be within the next 365 days';
  end if;

  raw_token := encode(extensions.gen_random_bytes(32), 'hex');
  insert into public.loan_share_links (
    organization_id,
    loan_id,
    token_hash,
    expires_at,
    created_by
  ) values (
    target_loan.organization_id,
    target_loan.id,
    extensions.digest(raw_token, 'sha256'),
    p_expires_at,
    actor_id
  ) returning id into new_link_id;

  insert into public.audit_events (
    organization_id,
    actor_id,
    action,
    record_type,
    record_id,
    payload
  ) values (
    target_loan.organization_id,
    actor_id,
    'loan_share_link_created',
    'loan_share_link',
    new_link_id,
    jsonb_build_object('loan_id', target_loan.id, 'expires_at', p_expires_at)
  );

  return jsonb_build_object(
    'id', new_link_id,
    'token', raw_token,
    'expires_at', p_expires_at
  );
end
$$;

create or replace function public.get_shared_loan_status(
  p_token text
) returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  target_link public.loan_share_links%rowtype;
  target_loan public.loans%rowtype;
  borrower_label text;
  verified_paid bigint;
  pending_total bigint;
  schedule_json jsonb;
  payment_json jsonb;
begin
  if length(coalesce(p_token, '')) <> 64 then
    raise exception 'Link is invalid or expired';
  end if;

  select *
    into target_link
    from public.loan_share_links
   where token_hash = extensions.digest(p_token, 'sha256')
     and revoked_at is null
     and expires_at > now();
  if target_link.id is null then
    raise exception 'Link is invalid or expired';
  end if;

  select * into target_loan from public.loans where id = target_link.loan_id;
  select concat(b.first_name, ' ', left(b.last_name, 1), '.')
    into borrower_label
    from public.borrowers b
   where b.id = target_loan.borrower_id;

  select coalesce(sum(p.amount_centavos), 0)
    into verified_paid
    from public.payments p
   where p.loan_id = target_loan.id and p.status = 'verified';
  select coalesce(sum(p.amount_centavos), 0)
    into pending_total
    from public.payments p
   where p.loan_id = target_loan.id and p.status = 'pending';

  select coalesce(jsonb_agg(row_data order by sequence), '[]'::jsonb)
    into schedule_json
    from (
      select
        i.sequence,
        i.due_date,
        i.scheduled_centavos,
        coalesce(sum(a.principal_centavos + a.interest_centavos + a.penalty_centavos), 0) as paid_centavos,
        case
          when coalesce(sum(a.principal_centavos + a.interest_centavos + a.penalty_centavos), 0) >= i.scheduled_centavos then 'paid'
          when coalesce(sum(a.principal_centavos + a.interest_centavos + a.penalty_centavos), 0) > 0 then 'partial'
          when i.due_date < current_date then 'overdue'
          else 'upcoming'
        end as status
      from public.installments i
      left join public.payment_allocations a on a.installment_id = i.id
      where i.loan_id = target_loan.id
      group by i.id, i.sequence, i.due_date, i.scheduled_centavos
    ) row_data;

  select coalesce(jsonb_agg(row_data order by received_at desc), '[]'::jsonb)
    into payment_json
    from (
      select p.received_at, p.amount_centavos, p.method, p.status
      from public.payments p
      where p.loan_id = target_loan.id
        and p.status in ('pending', 'verified')
    ) row_data;

  update public.loan_share_links
     set last_accessed_at = now()
   where id = target_link.id;

  return jsonb_build_object(
    'borrower', borrower_label,
    'loan_reference', 'LN-' || upper(left(target_loan.id::text, 8)),
    'loan_status', target_loan.status,
    'principal_centavos', target_loan.principal_centavos,
    'total_centavos', target_loan.total_centavos,
    'verified_paid_centavos', verified_paid,
    'pending_centavos', pending_total,
    'outstanding_centavos', greatest(target_loan.total_centavos - verified_paid, 0),
    'schedule', schedule_json,
    'payments', payment_json,
    'expires_at', target_link.expires_at
  );
end
$$;

revoke all on function public.create_loan_share_link(uuid, timestamptz) from public;
grant execute on function public.create_loan_share_link(uuid, timestamptz) to authenticated;
revoke all on function public.get_shared_loan_status(text) from public;
grant execute on function public.get_shared_loan_status(text) to anon, authenticated;

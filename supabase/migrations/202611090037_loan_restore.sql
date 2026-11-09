-- Restore one loan from a backup (owner only), with a dry-run preview and an
-- undo. A loan's "state" is the loan row plus everything that belongs to it:
-- schedule, payments and their allocations and corrections, money releases,
-- amendments, collection notes and customer links. Uploaded documents are
-- never touched (their files live in storage).
--
-- The state can be null: restoring "null" removes a loan that did not exist
-- when the backup was made (e.g. a refinance draft made by mistake), and
-- restoring a state for a loan that no longer exists brings it back.

create table if not exists public.loan_restores (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations,
  loan_id uuid not null,              -- no FK: the loan may be removed
  previous_state jsonb,               -- null = the loan did not exist
  restored_state jsonb,               -- null = the loan was removed
  reason text not null,
  backup_exported_at timestamptz,
  client_operation_id uuid not null,
  created_by uuid not null references auth.users,
  created_at timestamptz not null default now(),
  undone_at timestamptz,
  undone_by uuid references auth.users,
  unique (organization_id, client_operation_id)
);
alter table public.loan_restores enable row level security;
drop policy if exists owners_read_loan_restores on public.loan_restores;
create policy owners_read_loan_restores on public.loan_restores
  for select using (public.has_org_role(organization_id, array['owner']::public.app_role[]));

-- Sections of a loan state, in the order they are inserted.
create or replace function public._loan_state(p_loan_id uuid)
returns jsonb language sql stable security definer set search_path = '' as $$
  select case when l.id is null then null else jsonb_build_object(
    'loan', to_jsonb(l),
    'installments', coalesce((select jsonb_agg(to_jsonb(x) order by x.id)
      from public.installments x where x.loan_id = l.id), '[]'::jsonb),
    'loan_disbursements', coalesce((select jsonb_agg(to_jsonb(x) order by x.id)
      from public.loan_disbursements x where x.loan_id = l.id), '[]'::jsonb),
    'payments', coalesce((select jsonb_agg(to_jsonb(x) order by x.id)
      from public.payments x where x.loan_id = l.id), '[]'::jsonb),
    'payment_allocations', coalesce((select jsonb_agg(to_jsonb(x) order by x.id)
      from public.payment_allocations x
      where x.payment_id in (select p.id from public.payments p where p.loan_id = l.id)), '[]'::jsonb),
    'payment_corrections', coalesce((select jsonb_agg(to_jsonb(x) order by x.id)
      from public.payment_corrections x
      where x.payment_id in (select p.id from public.payments p where p.loan_id = l.id)), '[]'::jsonb),
    'loan_amendments', coalesce((select jsonb_agg(to_jsonb(x) order by x.id)
      from public.loan_amendments x where x.loan_id = l.id), '[]'::jsonb),
    'collection_activities', coalesce((select jsonb_agg(to_jsonb(x) order by x.id)
      from public.collection_activities x where x.loan_id = l.id), '[]'::jsonb),
    'loan_share_links', coalesce((select jsonb_agg(to_jsonb(x) order by x.id)
      from public.loan_share_links x where x.loan_id = l.id), '[]'::jsonb)
  ) end
  from (select 1) one left join public.loans l on l.id = p_loan_id
$$;
revoke all on function public._loan_state(uuid) from public;

-- Checks that a state only contains this loan's rows in this organization.
create or replace function public._assert_loan_state(p_loan_id uuid, p_org uuid, p_state jsonb)
returns void language plpgsql stable security definer set search_path = '' as $$
declare v_section text;
begin
  if p_state is null then return; end if;
  if jsonb_typeof(p_state) <> 'object' or p_state->'loan' is null then
    raise exception 'The backup data for this loan is incomplete';
  end if;
  if exists (select 1 from jsonb_object_keys(p_state) k where k not in (
      'loan','installments','loan_disbursements','payments','payment_allocations',
      'payment_corrections','loan_amendments','collection_activities','loan_share_links')) then
    raise exception 'The backup data for this loan has unknown parts';
  end if;
  if p_state->'loan'->>'id' is distinct from p_loan_id::text
     or p_state->'loan'->>'organization_id' is distinct from p_org::text then
    raise exception 'The backup data is for a different loan';
  end if;
  if not exists (select 1 from public.borrowers b
                 where b.id = (p_state->'loan'->>'borrower_id')::uuid and b.organization_id = p_org) then
    raise exception 'The borrower of this loan no longer exists';
  end if;
  foreach v_section in array array['installments','loan_disbursements','payments','payment_allocations',
      'payment_corrections','loan_amendments','collection_activities','loan_share_links'] loop
    if jsonb_typeof(coalesce(p_state->v_section, '[]'::jsonb)) <> 'array' then
      raise exception 'The backup data for this loan is malformed (%)', v_section;
    end if;
    if exists (select 1 from jsonb_array_elements(coalesce(p_state->v_section, '[]'::jsonb)) e
               where e->>'organization_id' is distinct from p_org::text
                  or (v_section not in ('payment_allocations','payment_corrections')
                      and e->>'loan_id' is distinct from p_loan_id::text)) then
      raise exception 'The backup data contains records of another loan (%)', v_section;
    end if;
  end loop;
  if exists (select 1 from jsonb_array_elements(coalesce(p_state->'payment_allocations', '[]'::jsonb)) a
             where not exists (select 1 from jsonb_array_elements(coalesce(p_state->'payments', '[]'::jsonb)) p
                               where p->>'id' = a->>'payment_id')
                or not exists (select 1 from jsonb_array_elements(coalesce(p_state->'installments', '[]'::jsonb)) i
                               where i->>'id' = a->>'installment_id'))
     or exists (select 1 from jsonb_array_elements(coalesce(p_state->'payment_corrections', '[]'::jsonb)) c
                where not exists (select 1 from jsonb_array_elements(coalesce(p_state->'payments', '[]'::jsonb)) p
                                  where p->>'id' = c->>'payment_id')) then
    raise exception 'The backup data for this loan is inconsistent';
  end if;
end $$;
revoke all on function public._assert_loan_state(uuid, uuid, jsonb) from public;

-- Replaces everything about a loan with the given state (null = remove it).
create or replace function public._replace_loan_state(p_loan_id uuid, p_state jsonb)
returns void language plpgsql security definer set search_path = '' as $$
declare v_exists boolean;
begin
  v_exists := exists (select 1 from public.loans where id = p_loan_id);
  if v_exists then
    delete from public.payment_allocations
     where payment_id in (select id from public.payments where loan_id = p_loan_id)
        or installment_id in (select id from public.installments where loan_id = p_loan_id);
    delete from public.payment_corrections
     where payment_id in (select id from public.payments where loan_id = p_loan_id);
    delete from public.payments where loan_id = p_loan_id;
    delete from public.installments where loan_id = p_loan_id;
    delete from public.loan_disbursements where loan_id = p_loan_id;
    delete from public.loan_amendments where loan_id = p_loan_id;
    delete from public.collection_activities where loan_id = p_loan_id;
    delete from public.loan_share_links where loan_id = p_loan_id;
    if p_state is null then
      if exists (select 1 from public.loan_documents where loan_id = p_loan_id) then
        raise exception 'This loan has uploaded evidence, so it cannot be removed';
      end if;
      delete from public.loans where id = p_loan_id;
      return;
    end if;
    update public.loans l set
      borrower_id = s.borrower_id, principal_centavos = s.principal_centavos,
      monthly_rate_basis_points = s.monthly_rate_basis_points, term_months = s.term_months,
      total_centavos = s.total_centavos, status = s.status, terms_snapshot = s.terms_snapshot,
      created_by = s.created_by, created_at = s.created_at,
      client_operation_id = s.client_operation_id, is_personal = s.is_personal
    from jsonb_populate_record(null::public.loans, p_state->'loan') s
    where l.id = p_loan_id;
  elsif p_state is null then
    return;
  else
    insert into public.loans select * from jsonb_populate_record(null::public.loans, p_state->'loan');
  end if;
  insert into public.installments
    select * from jsonb_populate_recordset(null::public.installments, coalesce(p_state->'installments', '[]'::jsonb));
  insert into public.loan_disbursements
    select * from jsonb_populate_recordset(null::public.loan_disbursements, coalesce(p_state->'loan_disbursements', '[]'::jsonb));
  insert into public.payments
    select * from jsonb_populate_recordset(null::public.payments, coalesce(p_state->'payments', '[]'::jsonb));
  insert into public.payment_allocations
    select * from jsonb_populate_recordset(null::public.payment_allocations, coalesce(p_state->'payment_allocations', '[]'::jsonb));
  insert into public.payment_corrections
    select * from jsonb_populate_recordset(null::public.payment_corrections, coalesce(p_state->'payment_corrections', '[]'::jsonb));
  insert into public.loan_amendments
    select * from jsonb_populate_recordset(null::public.loan_amendments, coalesce(p_state->'loan_amendments', '[]'::jsonb));
  insert into public.collection_activities
    select * from jsonb_populate_recordset(null::public.collection_activities, coalesce(p_state->'collection_activities', '[]'::jsonb));
  insert into public.loan_share_links
    select * from jsonb_populate_recordset(null::public.loan_share_links, coalesce(p_state->'loan_share_links', '[]'::jsonb));
end $$;
revoke all on function public._replace_loan_state(uuid, jsonb) from public;

create or replace function public._loan_restore_org(p_loan_id uuid, p_state jsonb)
returns uuid language plpgsql stable security definer set search_path = '' as $$
declare v_org uuid;
begin
  if auth.uid() is null then raise exception 'Authentication is required'; end if;
  v_org := coalesce((select organization_id from public.loans where id = p_loan_id),
                    (p_state->'loan'->>'organization_id')::uuid);
  if v_org is null then raise exception 'Loan was not found'; end if;
  if not public.has_org_role(v_org, array['owner']::public.app_role[]) then
    raise exception 'Only the owner can restore from a backup';
  end if;
  return v_org;
end $$;
revoke all on function public._loan_restore_org(uuid, jsonb) from public;

-- Dry run: returns the loan as it is now and as it would be after the
-- restore (both read back from the database, so they compare exactly).
-- Nothing is changed.
create or replace function public.loan_restore_preview(p_loan_id uuid, p_state jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_org uuid; v_now jsonb; v_after jsonb;
begin
  p_state := nullif(p_state, 'null'::jsonb); -- JSON null = "not in the backup"
  v_org := public._loan_restore_org(p_loan_id, p_state);
  perform public._assert_loan_state(p_loan_id, v_org, p_state);
  v_now := public._loan_state(p_loan_id);
  begin
    perform public._replace_loan_state(p_loan_id, p_state);
    v_after := public._loan_state(p_loan_id);
    raise exception using errcode = 'P0099', message = 'preview only';
  exception when sqlstate 'P0099' then
    null; -- everything above is rolled back
  end;
  return jsonb_build_object('now', v_now, 'after', v_after);
end $$;
revoke all on function public.loan_restore_preview(uuid, jsonb) from public;
grant execute on function public.loan_restore_preview(uuid, jsonb) to authenticated;

create or replace function public.restore_loan(
  p_loan_id uuid, p_state jsonb, p_reason text, p_backup_exported_at timestamptz,
  p_client_operation_id uuid
) returns uuid language plpgsql security definer set search_path = '' as $$
declare v_org uuid; v_prev jsonb; v_new jsonb; v_id uuid;
begin
  p_state := nullif(p_state, 'null'::jsonb); -- JSON null = "not in the backup"
  v_org := public._loan_restore_org(p_loan_id, p_state);
  select id into v_id from public.loan_restores
   where organization_id = v_org and client_operation_id = p_client_operation_id;
  if v_id is not null then return v_id; end if;
  if length(btrim(coalesce(p_reason, ''))) < 3 then
    raise exception 'Enter a short reason (kept in the history)';
  end if;
  perform public._assert_loan_state(p_loan_id, v_org, p_state);
  perform 1 from public.loans where id = p_loan_id for update;
  v_prev := public._loan_state(p_loan_id);
  perform public._replace_loan_state(p_loan_id, p_state);
  v_new := public._loan_state(p_loan_id);
  if v_new is not distinct from v_prev then
    raise exception 'This loan already matches the backup; nothing to restore';
  end if;
  insert into public.loan_restores (organization_id, loan_id, previous_state, restored_state, reason,
    backup_exported_at, client_operation_id, created_by)
  values (v_org, p_loan_id, v_prev, v_new, btrim(p_reason), p_backup_exported_at,
    p_client_operation_id, auth.uid())
  returning id into v_id;
  insert into public.audit_events (organization_id, actor_id, action, record_type, record_id, payload)
  values (v_org, auth.uid(), 'loan_restored_from_backup', 'loan', p_loan_id,
    jsonb_build_object('restore_id', v_id, 'reason', btrim(p_reason),
      'backup_exported_at', p_backup_exported_at,
      'removed', v_new is null, 'recreated', v_prev is null));
  return v_id;
end $$;
revoke all on function public.restore_loan(uuid, jsonb, text, timestamptz, uuid) from public;
grant execute on function public.restore_loan(uuid, jsonb, text, timestamptz, uuid) to authenticated;

create or replace function public.undo_loan_restore(p_restore_id uuid)
returns uuid language plpgsql security definer set search_path = '' as $$
declare v_restore public.loan_restores%rowtype;
begin
  if auth.uid() is null then raise exception 'Authentication is required'; end if;
  select * into v_restore from public.loan_restores where id = p_restore_id for update;
  if v_restore.id is null then raise exception 'Restore was not found'; end if;
  if v_restore.undone_at is not null then raise exception 'This restore was already undone'; end if;
  if v_restore.created_by <> auth.uid() then
    raise exception 'Only the person who made this restore can undo it';
  end if;
  perform 1 from public.loans where id = v_restore.loan_id for update;
  if public._loan_state(v_restore.loan_id) is distinct from v_restore.restored_state then
    raise exception 'The loan changed after the restore; undo is no longer available';
  end if;
  perform public._replace_loan_state(v_restore.loan_id, v_restore.previous_state);
  update public.loan_restores set undone_at = now(), undone_by = auth.uid() where id = p_restore_id;
  insert into public.audit_events (organization_id, actor_id, action, record_type, record_id, payload)
  values (v_restore.organization_id, auth.uid(), 'loan_restore_undone', 'loan', v_restore.loan_id,
    jsonb_build_object('restore_id', p_restore_id));
  return p_restore_id;
end $$;
revoke all on function public.undo_loan_restore(uuid) from public;
grant execute on function public.undo_loan_restore(uuid) to authenticated;

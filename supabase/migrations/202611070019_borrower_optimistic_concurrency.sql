create or replace function public.update_borrower_if_current(
  p_id uuid, p_expected_updated_at timestamptz, p_first_name text, p_last_name text,
  p_phone text default null, p_email text default null, p_address text default null
)
returns uuid language plpgsql security definer set search_path = public as $$
declare v_current timestamptz; v_result uuid;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  select updated_at into v_current from public.borrowers where id = p_id for update;
  if not found then raise exception 'Borrower not found'; end if;
  if v_current is distinct from p_expected_updated_at then
    raise exception 'Borrower was changed on another device. Refresh before saving.' using errcode = '40001';
  end if;
  v_result := public.save_borrower(p_id, p_first_name, p_last_name, p_phone, p_email, p_address);
  return v_result;
end;
$$;
revoke all on function public.update_borrower_if_current(uuid, timestamptz, text, text, text, text, text) from public;
grant execute on function public.update_borrower_if_current(uuid, timestamptz, text, text, text, text, text) to authenticated;

update public.organizations
set operational_preferences = jsonb_set(
  operational_preferences,
  '{payment_methods}',
  case
    when coalesce(operational_preferences->'payment_methods', '[]'::jsonb) ? 'PalPay'
      then operational_preferences->'payment_methods'
    else coalesce(operational_preferences->'payment_methods', '[]'::jsonb) || '"PalPay"'::jsonb
  end,
  true
);

-- Keep the early-payoff validation aligned with the organization's configured
-- methods without duplicating the whole payoff transaction function.
do $$
declare
  function_sql text;
begin
  select pg_get_functiondef(
    'public.record_early_payoff(uuid,date,text,text,uuid,text)'::regprocedure
  ) into function_sql;
  function_sql := replace(
    function_sql,
    'p_method not in (''Cash'',''GCash'',''AUB'',''MariBank'')',
    'p_method not in (''Cash'',''GCash'',''AUB'',''MariBank'',''PalPay'')'
  );
  execute function_sql;
end
$$;

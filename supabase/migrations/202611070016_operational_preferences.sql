alter table public.organizations
  add column if not exists operational_preferences jsonb not null default
  '{"rate_presets":[3,6,10],"payday_presets":[[15,30],[5,20]],"payment_methods":["Cash","GCash","AUB","MariBank"]}'::jsonb;

alter table public.organizations add constraint operational_preferences_object
  check (jsonb_typeof(operational_preferences) = 'object');

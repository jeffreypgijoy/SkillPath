create table if not exists public.ai_usage (
  user_id uuid not null references auth.users (id) on delete cascade,
  window_start timestamptz not null,
  request_count integer not null default 0 check (request_count >= 0),
  primary key (user_id, window_start)
);

alter table public.ai_usage enable row level security;

create or replace function public.consume_ai_quota(p_user_id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_count integer;
  v_window timestamptz := date_trunc('hour', now());
begin
  if auth.uid() is null or auth.uid() <> p_user_id then
    raise exception 'Not authorized';
  end if;

  insert into public.ai_usage (user_id, window_start, request_count)
  values (p_user_id, v_window, 1)
  on conflict (user_id, window_start)
  do update set request_count = public.ai_usage.request_count + 1
  returning request_count into v_count;

  if v_count > 40 then
    raise exception 'Hourly AI request limit reached';
  end if;
  return true;
end;
$$;

revoke all on function public.consume_ai_quota(uuid) from public, anon;
grant execute on function public.consume_ai_quota(uuid) to authenticated;

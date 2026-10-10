create table if not exists public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  display_name text not null default '',
  field_of_study text not null default '',
  target_role text not null default '',
  target_salary text not null default '',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.app_state (
  user_id uuid primary key references auth.users (id) on delete cascade,
  state jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now()
);

create table if not exists public.chat_requests (
  id uuid primary key default gen_random_uuid(),
  requester_id uuid not null references public.profiles (id) on delete cascade,
  recipient_id uuid not null references public.profiles (id) on delete cascade,
  job_role text not null default '',
  status text not null default 'pending' check (status in ('pending', 'accepted', 'declined')),
  created_at timestamptz not null default now(),
  unique (requester_id, recipient_id),
  check (requester_id <> recipient_id)
);

create table if not exists public.chat_messages (
  id bigint generated always as identity primary key,
  request_id uuid not null references public.chat_requests (id) on delete cascade,
  sender_id uuid not null references public.profiles (id) on delete cascade,
  body text not null check (char_length(body) between 1 and 4000),
  created_at timestamptz not null default now()
);

create table if not exists public.forum_threads (
  id uuid primary key default gen_random_uuid(),
  author_id uuid not null references public.profiles (id) on delete cascade,
  title text not null check (char_length(title) between 1 and 200),
  body text not null default '',
  job_role text not null default '',
  created_at timestamptz not null default now()
);

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
security definer set search_path = ''
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

create or replace function public.create_profile_for_new_user()
returns trigger
language plpgsql
security definer set search_path = ''
as $$
begin
  insert into public.profiles (id, display_name)
  values (new.id, coalesce(new.raw_user_meta_data ->> 'display_name', ''));
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute procedure public.create_profile_for_new_user();

alter table public.profiles enable row level security;
alter table public.app_state enable row level security;
alter table public.chat_requests enable row level security;
alter table public.chat_messages enable row level security;
alter table public.forum_threads enable row level security;

create policy "Authenticated users can read career profiles"
  on public.profiles for select to authenticated using (true);
create policy "Users can update their own profile"
  on public.profiles for update to authenticated using (auth.uid() = id) with check (auth.uid() = id);

create policy "Users can read their own app state"
  on public.app_state for select to authenticated using (auth.uid() = user_id);
create policy "Users can create their own app state"
  on public.app_state for insert to authenticated with check (auth.uid() = user_id);
create policy "Users can update their own app state"
  on public.app_state for update to authenticated using (auth.uid() = user_id) with check (auth.uid() = user_id);

create policy "Chat participants can read requests"
  on public.chat_requests for select to authenticated using (auth.uid() in (requester_id, recipient_id));
create policy "Users can request a chat"
  on public.chat_requests for insert to authenticated with check (auth.uid() = requester_id and status = 'pending');
create policy "Recipients can respond to chat requests"
  on public.chat_requests for update to authenticated using (auth.uid() = recipient_id) with check (auth.uid() = recipient_id);

create policy "Chat participants can read messages"
  on public.chat_messages for select to authenticated using (
    exists (
      select 1 from public.chat_requests r
      where r.id = request_id and auth.uid() in (r.requester_id, r.recipient_id)
    )
  );
create policy "Participants can send messages in accepted chats"
  on public.chat_messages for insert to authenticated with check (
    auth.uid() = sender_id and exists (
      select 1 from public.chat_requests r
      where r.id = request_id and r.status = 'accepted'
        and auth.uid() in (r.requester_id, r.recipient_id)
    )
  );

create policy "Authenticated users can read forum threads"
  on public.forum_threads for select to authenticated using (true);
create policy "Users can create their own forum threads"
  on public.forum_threads for insert to authenticated with check (auth.uid() = author_id);

grant select (id, display_name, field_of_study, target_role, created_at) on public.profiles to authenticated;
grant update (display_name, field_of_study, target_role, target_salary, updated_at) on public.profiles to authenticated;
grant select, insert, update on public.app_state to authenticated;
grant select, insert (requester_id, recipient_id, job_role), update (status) on public.chat_requests to authenticated;
grant select, insert on public.chat_messages to authenticated;
grant select, insert on public.forum_threads to authenticated;

do $$
begin
  alter publication supabase_realtime add table public.chat_requests;
exception when duplicate_object then null;
end;
$$;

do $$
begin
  alter publication supabase_realtime add table public.chat_messages;
exception when duplicate_object then null;
end;
$$;

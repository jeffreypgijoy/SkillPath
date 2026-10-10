alter table public.profiles
  add column if not exists email text,
  add column if not exists role text not null default 'student';

update public.profiles p
set email = u.email
from auth.users u
where p.id = u.id and p.email is null;

alter table public.profiles
  alter column email set not null;

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'profiles_role_check'
      and conrelid = 'public.profiles'::regclass
  ) then
    alter table public.profiles
      add constraint profiles_role_check
      check (role in ('student', 'trainer', 'admin'));
  end if;
end;
$$;

create or replace function public.create_profile_for_new_user()
returns trigger
language plpgsql
security definer set search_path = ''
as $$
begin
  insert into public.profiles (id, email, display_name, role)
  values (
    new.id,
    coalesce(new.email, ''),
    coalesce(new.raw_user_meta_data ->> 'display_name', ''),
    'student'
  );
  return new;
end;
$$;

grant select (id, display_name, role, field_of_study, target_role, created_at)
  on public.profiles to authenticated;

create or replace function public.assign_profile_role(p_user_id uuid, p_role text)
returns void
language plpgsql
security definer set search_path = ''
as $$
begin
  if p_role not in ('student', 'trainer', 'admin') then
    raise exception 'Invalid account role';
  end if;

  if auth.uid() is null or auth.uid() = p_user_id then
    raise exception 'Not authorized to change this account role';
  end if;

  if not exists (
    select 1
    from public.profiles
    where id = auth.uid() and role = 'admin'
  ) then
    raise exception 'Only administrators can assign account roles';
  end if;

  update public.profiles
  set role = p_role, updated_at = now()
  where id = p_user_id;

  if not found then
    raise exception 'Profile not found';
  end if;
end;
$$;

revoke all on function public.assign_profile_role(uuid, text) from public, anon;
grant execute on function public.assign_profile_role(uuid, text) to authenticated;

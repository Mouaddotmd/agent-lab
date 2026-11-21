-- Agent Lab accounts, in the Supabase project behind AgentLabAuthURL. Run once in its SQL editor; safe to run again.
--
-- Who gets in:
--   settings.signup_mode = 'open'       anyone who signs in with Google is approved (the default)
--   settings.signup_mode = 'allowlist'  only emails in allowlist are approved; everyone else waits (status 'waitlist')
--   profiles.status                     approved / waitlist / blocked, per person; change it in the Table Editor
-- Agent Lab reads its status through agentlab_check_in, each time it opens and every six hours.
--
-- Nothing here can be read or changed from the app except your own profile (read only) and the check-in.

create table if not exists public.profiles (
  id            uuid primary key references auth.users(id) on delete cascade,
  email         text not null,
  name          text,
  avatar_url    text,
  status        text not null default 'approved' check (status in ('approved', 'waitlist', 'blocked')),
  created_at    timestamptz not null default now(),
  last_seen_at  timestamptz,
  app_version   text,
  os_version    text
);

create table if not exists public.settings (
  key   text primary key,
  value text not null
);
insert into public.settings (key, value) values ('signup_mode', 'open') on conflict (key) do nothing;

create table if not exists public.allowlist (
  email     text primary key,
  note      text,
  added_at  timestamptz not null default now()
);

alter table public.profiles  enable row level security;
alter table public.settings  enable row level security;
alter table public.allowlist enable row level security;

drop policy if exists "Read your own profile" on public.profiles;
create policy "Read your own profile" on public.profiles for select to authenticated using (id = (select auth.uid()));
-- No other policies: settings and allowlist are dashboard-only, and profiles change only through the functions below.

revoke all on public.settings, public.allowlist from anon, authenticated;
revoke insert, update, delete on public.profiles from anon, authenticated;

-- Whether a new or waiting person should be let in.
create or replace function public.agentlab_should_approve(p_email text) returns boolean
language sql stable security definer set search_path = '' as $$
  select coalesce((select value from public.settings where key = 'signup_mode'), 'open') = 'open'
      or exists (select 1 from public.allowlist a where lower(a.email) = lower(p_email));
$$;

-- A profile for every new account.
create or replace function public.agentlab_new_user() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  insert into public.profiles (id, email, name, avatar_url, status)
  values (new.id, coalesce(new.email, ''),
          coalesce(new.raw_user_meta_data ->> 'full_name', new.raw_user_meta_data ->> 'name'),
          new.raw_user_meta_data ->> 'avatar_url',
          case when public.agentlab_should_approve(coalesce(new.email, '')) then 'approved' else 'waitlist' end)
  on conflict (id) do nothing;
  return new;
end $$;

drop trigger if exists agentlab_on_new_user on auth.users;
create trigger agentlab_on_new_user after insert on auth.users for each row execute function public.agentlab_new_user();

-- Agent Lab's check-in: records the Mac's versions and returns {status, name}. Someone waiting who has since been let in
-- (added to the allowlist, or signups opened) is approved here.
create or replace function public.agentlab_check_in(p_app_version text, p_os_version text) returns json
language plpgsql security definer set search_path = '' as $$
declare
  me uuid := auth.uid();
  prof public.profiles;
begin
  if me is null then raise exception 'not signed in' using errcode = '28000'; end if;
  insert into public.profiles (id, email, name, avatar_url, status)
  select u.id, coalesce(u.email, ''), coalesce(u.raw_user_meta_data ->> 'full_name', u.raw_user_meta_data ->> 'name'),
         u.raw_user_meta_data ->> 'avatar_url',
         case when public.agentlab_should_approve(coalesce(u.email, '')) then 'approved' else 'waitlist' end
  from auth.users u where u.id = me
  on conflict (id) do nothing;
  update public.profiles p set status = 'approved'
   where p.id = me and p.status = 'waitlist' and public.agentlab_should_approve(p.email);
  update public.profiles p set last_seen_at = now(), app_version = left(p_app_version, 40), os_version = left(p_os_version, 40)
   where p.id = me returning * into prof;
  return json_build_object('status', prof.status, 'name', prof.name);
end $$;

revoke all on function public.agentlab_should_approve(text) from public, anon, authenticated;
revoke all on function public.agentlab_new_user() from public, anon, authenticated;
revoke all on function public.agentlab_check_in(text, text) from public, anon;
grant execute on function public.agentlab_check_in(text, text) to authenticated;

-- Deleting your account, from Agent Lab's Settings: removes the sign-in and (by cascade) the profile. Nothing else of yours
-- is kept here.
create or replace function public.agentlab_delete_account() returns void
language plpgsql security definer set search_path = '' as $$
begin
  if auth.uid() is null then raise exception 'not signed in' using errcode = '28000'; end if;
  delete from auth.users where id = auth.uid();
end $$;
revoke all on function public.agentlab_delete_account() from public, anon;
grant execute on function public.agentlab_delete_account() to authenticated;

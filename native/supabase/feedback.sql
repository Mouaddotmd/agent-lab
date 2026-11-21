-- Agent Lab feedback, in the same Supabase project as the accounts. Run once in its SQL editor; safe to run again.
--
-- A signed-in user writes a report in Agent Lab; it's stored here AND emailed to you, so you see every one in your inbox
-- (filtered to a Gmail label) without opening the dashboard. The app only calls agentlab_submit_feedback — it holds no
-- email key and can read nothing here.
--
-- Email is sent server-side through Web3Forms (free; no domain needed). Put your access key in the settings row below:
--   1. Go to https://web3forms.com, enter the email you want feedback at (your contact email), and copy the access key.
--   2. Run (in this SQL editor), with your key:
--        insert into public.settings (key, value) values ('feedback_access_key', 'YOUR-WEB3FORMS-KEY')
--          on conflict (key) do update set value = excluded.value;
-- Until a key is set, feedback is still stored here; it just isn't emailed.

create extension if not exists pg_net with schema extensions;

create table if not exists public.feedback (
  id           uuid primary key default gen_random_uuid(),
  user_id      uuid references auth.users(id) on delete set null,
  email        text,
  name         text,
  kind         text not null default 'feedback' check (kind in ('feedback', 'bug', 'idea')),
  message      text not null,
  app_version  text,
  os_version   text,
  created_at   timestamptz not null default now()
);

alter table public.feedback enable row level security;
-- Dashboard-only to read; the app writes only through the function below.
revoke all on public.feedback from anon, authenticated;

-- A signed-in person's report: stored, then emailed to you (best effort; storage never depends on the email).
create or replace function public.agentlab_submit_feedback(p_kind text, p_message text, p_app_version text, p_os_version text)
returns void
language plpgsql security definer set search_path = '' as $$
declare
  me uuid := auth.uid();
  u  auth.users;
  v_key text;
  row_email text;
  row_name  text;
begin
  if me is null then raise exception 'not signed in' using errcode = '28000'; end if;
  if coalesce(btrim(p_message), '') = '' then raise exception 'empty feedback'; end if;

  select * into u from auth.users where id = me;
  row_email := coalesce(u.email, '');
  row_name  := coalesce(u.raw_user_meta_data ->> 'full_name', u.raw_user_meta_data ->> 'name', '');

  insert into public.feedback (user_id, email, name, kind, message, app_version, os_version)
  values (me, row_email, row_name,
          case when p_kind in ('feedback', 'bug', 'idea') then p_kind else 'feedback' end,
          left(p_message, 8000), left(coalesce(p_app_version, ''), 40), left(coalesce(p_os_version, ''), 40));

  select s.value into v_key from public.settings s where s.key = 'feedback_access_key';
  if v_key is not null and btrim(v_key) <> '' then
    perform extensions.http_post(
      url     := 'https://api.web3forms.com/submit',
      headers := '{"Content-Type": "application/json"}'::jsonb,
      body    := jsonb_build_object(
        'access_key', v_key,
        'subject', '[Agent Lab feedback] ' ||
                   case when p_kind = 'bug' then 'Bug' when p_kind = 'idea' then 'Idea' else 'Feedback' end ||
                   ' from ' || coalesce(nullif(row_name, ''), nullif(row_email, ''), 'a tester'),
        'from_name', 'Agent Lab feedback',
        'replyto', row_email,
        'message', p_message ||
                   e'\n\n— ' || coalesce(nullif(row_name, ''), 'tester') || ' <' || row_email || '>' ||
                   e'\nAgent Lab ' || coalesce(p_app_version, '?') || ' · macOS ' || coalesce(p_os_version, '?')
      )
    );
  end if;
end $$;

revoke all on function public.agentlab_submit_feedback(text, text, text, text) from public, anon;
grant execute on function public.agentlab_submit_feedback(text, text, text, text) to authenticated;

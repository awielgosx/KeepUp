-- KeepUp — run this once in Supabase → SQL Editor.
--
-- BEFORE RUNNING: replace both CHANGE-ME values below with your own long
-- random passphrase (e.g. from a password manager). That passphrase is your
-- "Sync key": you paste it into the Mac app and the phone app. Without it,
-- nobody can read or write your items, even if they have your project URL
-- and anon key. Never commit the real value to the repo.

create table if not exists public.items (
  id          uuid primary key,
  title       text        not null default '',
  due         timestamptz,
  all_day     boolean     not null default false,
  place       text        not null default '',
  course      text        not null default '',
  kind        text        not null default 'todo',
  notes       text        not null default '',
  done        boolean     not null default false,
  deleted     boolean     not null default false,
  updated_at  timestamptz not null default now()
);

alter table public.items enable row level security;

drop policy if exists "keepup sync key" on public.items;
create policy "keepup sync key" on public.items
  for all to anon
  using      ((current_setting('request.headers', true)::json ->> 'x-keepup-key') = 'CHANGE-ME')
  with check ((current_setting('request.headers', true)::json ->> 'x-keepup-key') = 'CHANGE-ME');

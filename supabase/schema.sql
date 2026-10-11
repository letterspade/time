-- Letterspade Time: database schema, access rules, and realtime.
-- Run this once in the Supabase SQL editor (Database -> SQL Editor -> New query -> paste -> Run).

-- ---------- Tables ----------

create table if not exists public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  email text,
  full_name text,
  role text not null default 'member' check (role in ('admin', 'member')),
  approved boolean not null default false,
  hourly_pay numeric,
  created_at timestamptz not null default now()
);

create table if not exists public.clients (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  color text not null default '#C9789A',
  rate numeric,
  archived boolean not null default false,
  created_at timestamptz not null default now()
);

create table if not exists public.projects (
  id uuid primary key default gen_random_uuid(),
  client_id uuid not null references public.clients (id) on delete cascade,
  name text not null,
  archived boolean not null default false,
  created_at timestamptz not null default now()
);

create table if not exists public.entries (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references public.profiles (id) on delete cascade,
  client_id uuid references public.clients (id) on delete set null,
  project_id uuid references public.projects (id) on delete set null,
  note text not null default '',
  start_at timestamptz not null,
  end_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists entries_user_start on public.entries (user_id, start_at desc);
create index if not exists entries_start on public.entries (start_at desc);
create index if not exists projects_client on public.projects (client_id);

-- ---------- Helpers ----------

create or replace function public.is_approved()
returns boolean language sql stable security definer set search_path = public as $$
  select coalesce((select approved from public.profiles where id = auth.uid()), false);
$$;

create or replace function public.is_admin()
returns boolean language sql stable security definer set search_path = public as $$
  select coalesce((select role = 'admin' and approved from public.profiles where id = auth.uid()), false);
$$;

-- Every new sign-up gets a profile. The very first person becomes the approved admin;
-- everyone after that waits for an admin to approve them in the app.
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = public as $$
declare first_user boolean;
begin
  select count(*) = 0 into first_user from public.profiles;
  insert into public.profiles (id, email, full_name, role, approved)
  values (
    new.id,
    new.email,
    coalesce(new.raw_user_meta_data ->> 'full_name', ''),
    case when first_user then 'admin' else 'member' end,
    first_user
  );
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute procedure public.handle_new_user();

-- Members may edit their own name, but only admins may change role, approval, or pay.
create or replace function public.protect_profile_fields()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if not public.is_admin() then
    new.role := old.role;
    new.approved := old.approved;
    new.hourly_pay := old.hourly_pay;
    new.email := old.email;
  end if;
  return new;
end;
$$;

drop trigger if exists protect_profile_fields on public.profiles;
create trigger protect_profile_fields
  before update on public.profiles
  for each row execute procedure public.protect_profile_fields();

create or replace function public.touch_updated_at()
returns trigger language plpgsql as $$
begin new.updated_at := now(); return new; end;
$$;

drop trigger if exists entries_touch on public.entries;
create trigger entries_touch before update on public.entries
  for each row execute procedure public.touch_updated_at();

-- ---------- Row-level security ----------

alter table public.profiles enable row level security;
alter table public.clients  enable row level security;
alter table public.projects enable row level security;
alter table public.entries  enable row level security;

-- profiles: you can always see yourself; admins see everyone.
drop policy if exists "profiles read" on public.profiles;
create policy "profiles read" on public.profiles for select
  using (id = auth.uid() or public.is_admin());

drop policy if exists "profiles update" on public.profiles;
create policy "profiles update" on public.profiles for update
  using (id = auth.uid() or public.is_admin())
  with check (id = auth.uid() or public.is_admin());

-- clients and projects: shared by the whole approved team.
drop policy if exists "clients read" on public.clients;
create policy "clients read" on public.clients for select using (public.is_approved());
drop policy if exists "clients write" on public.clients;
create policy "clients write" on public.clients for all
  using (public.is_approved()) with check (public.is_approved());

drop policy if exists "projects read" on public.projects;
create policy "projects read" on public.projects for select using (public.is_approved());
drop policy if exists "projects write" on public.projects;
create policy "projects write" on public.projects for all
  using (public.is_approved()) with check (public.is_approved());

-- entries: your own, or everyone's if you are an admin.
drop policy if exists "entries read" on public.entries;
create policy "entries read" on public.entries for select
  using (public.is_approved() and (user_id = auth.uid() or public.is_admin()));

drop policy if exists "entries insert" on public.entries;
create policy "entries insert" on public.entries for insert
  with check (public.is_approved() and (user_id = auth.uid() or public.is_admin()));

drop policy if exists "entries update" on public.entries;
create policy "entries update" on public.entries for update
  using (public.is_approved() and (user_id = auth.uid() or public.is_admin()))
  with check (public.is_approved() and (user_id = auth.uid() or public.is_admin()));

drop policy if exists "entries delete" on public.entries;
create policy "entries delete" on public.entries for delete
  using (public.is_approved() and (user_id = auth.uid() or public.is_admin()));

-- ---------- Realtime ----------
-- Lets open apps see each other's changes live.

do $$
begin
  if not exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    create publication supabase_realtime;
  end if;
end $$;

alter publication supabase_realtime add table public.clients;
alter publication supabase_realtime add table public.projects;
alter publication supabase_realtime add table public.entries;
alter publication supabase_realtime add table public.profiles;

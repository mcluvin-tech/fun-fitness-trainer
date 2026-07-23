-- Profiles for trainer voice sync and account metadata
create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  display_name text,
  trainer_voice text default '',
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);

create table if not exists public.trainer_phrases (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  text text not null,
  tag text not null check (tag in ('morning', 'under_protein', 'crushed_it', 'cheat_meal', 'streak', 'general')),
  created_at timestamptz default now()
);

alter table public.profiles enable row level security;
alter table public.trainer_phrases enable row level security;

create policy "Users read own profile"
  on public.profiles for select
  using (auth.uid() = id);

create policy "Users insert own profile"
  on public.profiles for insert
  with check (auth.uid() = id);

create policy "Users update own profile"
  on public.profiles for update
  using (auth.uid() = id);

create policy "Users manage own phrases"
  on public.trainer_phrases for all
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

create or replace function public.handle_new_user()
returns trigger as $$
begin
  insert into public.profiles (id, display_name)
  values (new.id, coalesce(new.raw_user_meta_data->>'full_name', 'Athlete'));
  return new;
end;
$$ language plpgsql security definer;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute procedure public.handle_new_user();

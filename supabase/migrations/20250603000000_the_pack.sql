-- The Pack: minimal social — "friends" = users who share the same pack invite code.

create table if not exists public.packs (
  id uuid primary key default gen_random_uuid(),
  invite_code text not null unique,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz default now()
);

create table if not exists public.pack_members (
  pack_id uuid not null references public.packs(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  joined_at timestamptz default now(),
  primary key (pack_id, user_id)
);

create index if not exists pack_members_user_id_idx on public.pack_members(user_id);

create table if not exists public.pack_meal_posts (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  meal_name text not null,
  calories numeric not null default 0,
  protein_g numeric not null default 0,
  logged_at timestamptz not null default now(),
  created_at timestamptz default now()
);

create index if not exists pack_meal_posts_logged_at_idx on public.pack_meal_posts(logged_at desc);

alter table public.packs enable row level security;
alter table public.pack_members enable row level security;
alter table public.pack_meal_posts enable row level security;

-- Packs: members can read packs they belong to
create policy "pack_members read own packs"
  on public.packs for select
  using (
    exists (
      select 1 from public.pack_members m
      where m.pack_id = packs.id and m.user_id = auth.uid()
    )
  );

-- Pack membership: see everyone in your pack(s)
create policy "read pack members in shared packs"
  on public.pack_members for select
  using (
    pack_id in (
      select pack_id from public.pack_members where user_id = auth.uid()
    )
  );

create policy "insert own pack membership"
  on public.pack_members for insert
  with check (auth.uid() = user_id);

-- Meal posts: write own; read pack mates'
create policy "insert own pack meal posts"
  on public.pack_meal_posts for insert
  with check (auth.uid() = user_id);

create policy "read pack mate meal posts"
  on public.pack_meal_posts for select
  using (
    exists (
      select 1 from public.pack_members me
      join public.pack_members them on me.pack_id = them.pack_id
      where me.user_id = auth.uid()
        and them.user_id = pack_meal_posts.user_id
    )
  );

-- Pack mates can read each other's display names
create policy "read profiles of pack mates"
  on public.profiles for select
  using (
    id = auth.uid()
    or exists (
      select 1 from public.pack_members me
      join public.pack_members them on me.pack_id = them.pack_id
      where me.user_id = auth.uid() and them.user_id = profiles.id
    )
  );

-- Create your pack (6-char code) or return existing
create or replace function public.ensure_my_pack()
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  existing text;
  new_code text;
  pid uuid;
begin
  if auth.uid() is null then
    raise exception 'Not authenticated';
  end if;

  select p.invite_code into existing
  from public.pack_members m
  join public.packs p on p.id = m.pack_id
  where m.user_id = auth.uid()
  order by m.joined_at asc
  limit 1;

  if existing is not null then
    return existing;
  end if;

  loop
    new_code := upper(substr(md5(random()::text), 1, 6));
    exit when not exists (select 1 from public.packs where invite_code = new_code);
  end loop;

  insert into public.packs (invite_code, created_by)
  values (new_code, auth.uid())
  returning id into pid;

  insert into public.pack_members (pack_id, user_id)
  values (pid, auth.uid());

  return new_code;
end;
$$;

-- Join a friend's pack by invite code (they are in your feed once you share a pack)
create or replace function public.join_pack(invite text)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  pid uuid;
  code text;
begin
  if auth.uid() is null then
    raise exception 'Not authenticated';
  end if;

  code := upper(trim(invite));
  if length(code) < 4 then
    raise exception 'Invalid pack code';
  end if;

  select id into pid from public.packs where invite_code = code;
  if pid is null then
    raise exception 'Pack not found';
  end if;

  insert into public.pack_members (pack_id, user_id)
  values (pid, auth.uid())
  on conflict (pack_id, user_id) do nothing;

  return code;
end;
$$;

grant execute on function public.ensure_my_pack() to authenticated;
grant execute on function public.join_pack(text) to authenticated;

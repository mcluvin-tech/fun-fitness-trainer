-- Challenge a Friend: one invite connects two accounts for a later rivalry.
-- Stores no body weight, progress photos, calories, or food logs.
-- Pending invites expire 7 days after creation.
-- The 7-day competition clock starts only when the invite is accepted.

create table if not exists public.friend_challenges (
  id uuid primary key default gen_random_uuid(),
  inviter_user_id uuid not null references auth.users(id) on delete cascade,
  invitee_user_id uuid references auth.users(id) on delete set null,
  invite_token text not null unique,
  status text not null default 'pending' check (status in ('pending', 'accepted', 'expired', 'cancelled')),
  created_at timestamptz not null default now(),
  accepted_at timestamptz,
  starts_at timestamptz,
  ends_at timestamptz,
  expires_at timestamptz not null
);

create index if not exists friend_challenges_inviter_idx
  on public.friend_challenges (inviter_user_id, status);

create index if not exists friend_challenges_invitee_idx
  on public.friend_challenges (invitee_user_id);

-- One open invite per person. Repeated "Send Challenge" taps reuse it.
create unique index if not exists friend_challenges_one_pending_per_inviter
  on public.friend_challenges (inviter_user_id)
  where status = 'pending';

alter table public.friend_challenges enable row level security;

revoke all on table public.friend_challenges from public, anon, authenticated;

create or replace function public.create_friend_challenge()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  rec public.friend_challenges%rowtype;
  new_token text;
  expired_ids uuid[] := '{}';
  did_create boolean := false;
begin
  if auth.uid() is null then
    raise exception 'not_authenticated';
  end if;

  with expired as (
    update public.friend_challenges
    set status = 'expired'
    where inviter_user_id = auth.uid()
      and status = 'pending'
      and expires_at <= now()
    returning id
  )
  select coalesce(array_agg(id), '{}') into expired_ids from expired;

  select * into rec
  from public.friend_challenges
  where inviter_user_id = auth.uid()
    and status = 'pending'
    and expires_at > now()
  order by created_at desc
  limit 1;

  if found then
    return jsonb_build_object(
      'id', rec.id,
      'invite_token', rec.invite_token,
      'status', rec.status,
      'is_inviter', true,
      'created', false,
      'created_at', rec.created_at,
      'expires_at', rec.expires_at,
      'expired_ids', to_jsonb(expired_ids)
    );
  end if;

  for _attempt in 1..5 loop
    new_token := replace(gen_random_uuid()::text, '-', '');
    begin
      insert into public.friend_challenges (
        inviter_user_id, invite_token, status, expires_at
      ) values (
        auth.uid(), new_token, 'pending', now() + interval '7 days'
      )
      returning * into rec;
      did_create := true;
      exit;
    exception
      when unique_violation then
        select * into rec
        from public.friend_challenges
        where inviter_user_id = auth.uid()
          and status = 'pending'
          and expires_at > now()
        order by created_at desc
        limit 1;
        if found then
          return jsonb_build_object(
            'id', rec.id,
            'invite_token', rec.invite_token,
            'status', rec.status,
            'is_inviter', true,
            'created', false,
            'created_at', rec.created_at,
            'expires_at', rec.expires_at,
            'expired_ids', to_jsonb(expired_ids)
          );
        end if;
    end;
  end loop;

  if not did_create then
    raise exception 'unavailable';
  end if;

  return jsonb_build_object(
    'id', rec.id,
    'invite_token', rec.invite_token,
    'status', rec.status,
    'is_inviter', true,
    'created', true,
    'created_at', rec.created_at,
    'expires_at', rec.expires_at,
    'expired_ids', to_jsonb(expired_ids)
  );
end;
$$;

create or replace function public.get_friend_challenge(token text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  rec public.friend_challenges%rowtype;
  clean text := trim(token);
  inviter_name text;
  opponent_name text;
  just_expired boolean := false;
  viewer uuid := auth.uid();
begin
  if clean is null or clean !~ '^[A-Za-z0-9]{16,80}$' then
    return jsonb_build_object('found', false);
  end if;

  select * into rec
  from public.friend_challenges
  where invite_token = clean;

  if not found then
    return jsonb_build_object('found', false);
  end if;

  if rec.status = 'pending' and rec.expires_at <= now() then
    update public.friend_challenges
    set status = 'expired'
    where id = rec.id
      and status = 'pending';
    rec.status := 'expired';
    just_expired := true;
  end if;

  select display_name into inviter_name
  from public.profiles
  where id = rec.inviter_user_id;

  if viewer is not null
     and viewer = rec.inviter_user_id
     and rec.invitee_user_id is not null then
    select display_name into opponent_name
    from public.profiles
    where id = rec.invitee_user_id;
  end if;

  return jsonb_build_object(
    'found', true,
    'id', rec.id,
    'invite_token', case when viewer = rec.inviter_user_id then rec.invite_token else null end,
    'status', rec.status,
    'inviter_display_name', inviter_name,
    'opponent_display_name', opponent_name,
    'is_own_invite', viewer is not null and viewer = rec.inviter_user_id,
    'is_invitee', viewer is not null and viewer = rec.invitee_user_id,
    'is_inviter', viewer is not null and viewer = rec.inviter_user_id,
    'created_at', rec.created_at,
    'accepted_at', rec.accepted_at,
    'starts_at', rec.starts_at,
    'ends_at', rec.ends_at,
    'expires_at', rec.expires_at,
    'just_expired', just_expired
  );
end;
$$;

create or replace function public.accept_friend_challenge(token text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  rec public.friend_challenges%rowtype;
  clean text := trim(token);
  inviter_name text;
  fresh boolean := false;
begin
  if auth.uid() is null then
    raise exception 'not_authenticated';
  end if;

  if clean is null or clean !~ '^[A-Za-z0-9]{16,80}$' then
    raise exception 'invalid_invite';
  end if;

  select * into rec
  from public.friend_challenges
  where invite_token = clean
  for update;

  if not found then
    raise exception 'invalid_invite';
  end if;

  if rec.inviter_user_id = auth.uid() then
    raise exception 'own_invite';
  end if;

  if rec.status = 'cancelled' then
    raise exception 'cancelled_invite';
  end if;

  if rec.status = 'expired' or (rec.status = 'pending' and rec.expires_at <= now()) then
    update public.friend_challenges
    set status = 'expired'
    where id = rec.id
      and status = 'pending';
    raise exception 'expired_invite';
  end if;

  if rec.status = 'accepted' then
    if rec.invitee_user_id is distinct from auth.uid() then
      raise exception 'already_accepted';
    end if;
  elsif rec.status = 'pending' then
    update public.friend_challenges
    set
      invitee_user_id = auth.uid(),
      status = 'accepted',
      accepted_at = now(),
      starts_at = now(),
      ends_at = now() + interval '7 days'
    where id = rec.id
      and status = 'pending'
    returning * into rec;

    if not found then
      select * into rec
      from public.friend_challenges
      where invite_token = clean;
      if not found or rec.invitee_user_id is distinct from auth.uid() then
        raise exception 'already_accepted';
      end if;
    else
      fresh := true;
    end if;
  else
    raise exception 'invalid_invite';
  end if;

  select display_name into inviter_name
  from public.profiles
  where id = rec.inviter_user_id;

  return jsonb_build_object(
    'found', true,
    'id', rec.id,
    'status', rec.status,
    'newly_accepted', fresh,
    'inviter_display_name', inviter_name,
    'is_own_invite', false,
    'is_invitee', true,
    'is_inviter', false,
    'created_at', rec.created_at,
    'accepted_at', rec.accepted_at,
    'starts_at', rec.starts_at,
    'ends_at', rec.ends_at,
    'expires_at', rec.expires_at
  );
end;
$$;

create or replace function public.list_my_friend_challenges()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  expired_ids uuid[] := '{}';
  result jsonb;
begin
  if auth.uid() is null then
    raise exception 'not_authenticated';
  end if;

  with expired as (
    update public.friend_challenges
    set status = 'expired'
    where inviter_user_id = auth.uid()
      and status = 'pending'
      and expires_at <= now()
    returning id
  )
  select coalesce(array_agg(id), '{}') into expired_ids from expired;

  select coalesce(jsonb_agg(jsonb_build_object(
    'id', c.id,
    'invite_token', case when c.inviter_user_id = auth.uid() then c.invite_token else null end,
    'status', c.status,
    'is_inviter', c.inviter_user_id = auth.uid(),
    'is_invitee', c.invitee_user_id = auth.uid(),
    'opponent_display_name', case
      when c.inviter_user_id = auth.uid() then invitee.display_name
      else inviter.display_name
    end,
    'created_at', c.created_at,
    'accepted_at', c.accepted_at,
    'starts_at', c.starts_at,
    'ends_at', c.ends_at,
    'expires_at', c.expires_at,
    'just_expired', c.id = any(expired_ids)
  ) order by c.created_at desc), '[]'::jsonb)
  into result
  from public.friend_challenges c
  left join public.profiles inviter on inviter.id = c.inviter_user_id
  left join public.profiles invitee on invitee.id = c.invitee_user_id
  where c.inviter_user_id = auth.uid()
     or c.invitee_user_id = auth.uid();

  return result;
end;
$$;

revoke all on function public.create_friend_challenge() from public;
revoke all on function public.get_friend_challenge(text) from public;
revoke all on function public.accept_friend_challenge(text) from public;
revoke all on function public.list_my_friend_challenges() from public;

grant execute on function public.create_friend_challenge() to authenticated;
grant execute on function public.get_friend_challenge(text) to anon, authenticated;
grant execute on function public.accept_friend_challenge(text) to authenticated;
grant execute on function public.list_my_friend_challenges() to authenticated;

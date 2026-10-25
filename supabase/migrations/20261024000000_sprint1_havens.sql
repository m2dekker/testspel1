-- =====================================================================
-- Blackwake Isles – Sprint 1: profiles, islands, havens, buildings
--
-- Security model ("the server is the referee"):
--   * RLS is enabled on every table. Players can only SELECT their own rows.
--   * There are NO insert/update/delete policies for players.
--   * Every game action is a SECURITY DEFINER function (RPC) that checks
--     the rules and then writes.
--
-- Resource model ("lazy settlement"):
--   * A haven stores resource amounts + resources_updated_at.
--   * settle_haven() adds production for the time that has passed and
--     completes finished constructions in the order they finished.
--   * It runs before every action and every read, so offline progress
--     needs no background job.
-- =====================================================================

-- ---------------------------------------------------------------------
-- Game data: building catalogue
-- ---------------------------------------------------------------------

create table public.building_types (
  id                 text primary key,
  name               text not null,
  description        text not null,
  buildable          boolean not null default true,  -- false = pre-built only
  max_level          int not null default 10,
  base_cost_timber   int not null,                   -- cost of level 1
  base_cost_gold     int not null default 0,
  cost_growth        numeric not null default 1.6,   -- cost multiplier per level
  base_build_seconds int not null,                   -- build time of level 1
  time_growth        numeric not null default 1.5,   -- time multiplier per level
  produces           text check (produces in ('timber', 'luxury', 'gold')),
  base_rate          numeric not null default 0,     -- units per hour, per level
  storage_per_level  int not null default 0,         -- extra storage per level
  sort_order         int not null default 0
);

insert into public.building_types
  (id, name, description, buildable, base_cost_timber, base_cost_gold, cost_growth,
   base_build_seconds, time_growth, produces, base_rate, storage_per_level, sort_order)
values
  ('captains_quarters', 'Captain''s Quarters',
   'The heart of your haven. Idle crew loaf about here and earn a little gold.',
   false, 150, 50, 1.7, 30, 1.6, 'gold', 30, 0, 0),
  ('lumber_camp', 'Lumber Camp',
   'Fells palms and hardwood. Every ship and building starts with timber.',
   true, 60, 0, 1.6, 15, 1.5, 'timber', 300, 0, 1),
  ('plantation', 'Plantation',
   'Grows or mines this island''s luxury good. Other islands will want it.',
   true, 100, 20, 1.6, 20, 1.5, 'luxury', 120, 0, 2),
  ('warehouse', 'Warehouse',
   'Stores more goods. Anything past capacity rots on the dock.',
   true, 80, 0, 1.6, 20, 1.5, null, 0, 1500, 3);

-- Base storage every haven has without a warehouse.
create function public.base_storage() returns int
language sql immutable as $$ select 1500 $$;

-- Number of building plots in a haven (slot 0 is the Captain's Quarters).
create function public.haven_plots() returns int
language sql immutable as $$ select 8 $$;

-- Cost to build level p_level (1 = placing the building).
create function public.building_cost(p_type text, p_level int,
                                     out timber int, out gold int)
language sql stable as $$
  select ceil(bt.base_cost_timber * power(bt.cost_growth, p_level - 1))::int,
         ceil(bt.base_cost_gold   * power(bt.cost_growth, p_level - 1))::int
  from public.building_types bt
  where bt.id = p_type
$$;

-- Seconds needed to build level p_level.
create function public.build_seconds(p_type text, p_level int) returns int
language sql stable as $$
  select ceil(bt.base_build_seconds * power(bt.time_growth, p_level - 1))::int
  from public.building_types bt
  where bt.id = p_type
$$;

-- ---------------------------------------------------------------------
-- World and player tables
-- ---------------------------------------------------------------------

create table public.profiles (
  id         uuid primary key references auth.users (id) on delete cascade,
  username   text not null unique,
  created_at timestamptz not null default now(),
  last_login timestamptz
);

create table public.islands (
  id              bigint generated always as identity primary key,
  name            text not null unique,
  x               int not null,   -- world map position (used for travel later)
  y               int not null,
  luxury_resource text not null check (luxury_resource in ('rum', 'spice', 'iron', 'silk')),
  max_slots       int not null default 8
);

create table public.havens (
  id                   bigint generated always as identity primary key,
  player_id            uuid not null references public.profiles (id) on delete cascade,
  island_id            bigint not null references public.islands (id),
  island_slot          int not null,
  name                 text not null,
  is_capital           boolean not null default true,
  -- resources (numeric so fractional production is never lost)
  timber               numeric(16, 4) not null default 300,
  rum                  numeric(16, 4) not null default 0,
  spice                numeric(16, 4) not null default 0,
  iron                 numeric(16, 4) not null default 0,
  silk                 numeric(16, 4) not null default 0,
  gold                 numeric(16, 4) not null default 100,
  resources_updated_at timestamptz not null default now(),
  created_at           timestamptz not null default now(),
  unique (island_id, island_slot)
);

create index havens_player_idx on public.havens (player_id);

create table public.buildings (
  id                  bigint generated always as identity primary key,
  haven_id            bigint not null references public.havens (id) on delete cascade,
  type                text not null references public.building_types (id),
  slot                int not null check (slot >= 0 and slot < 8),
  level               int not null default 0,  -- 0 while the first construction runs
  upgrade_finishes_at timestamptz,             -- null when no construction is running
  created_at          timestamptz not null default now(),
  unique (haven_id, slot),
  unique (haven_id, type)                      -- one of each building per haven
);

-- ---------------------------------------------------------------------
-- Row Level Security: read-only, own data
-- ---------------------------------------------------------------------

alter table public.building_types enable row level security;
alter table public.profiles       enable row level security;
alter table public.islands        enable row level security;
alter table public.havens         enable row level security;
alter table public.buildings      enable row level security;

create policy "building types are public"
  on public.building_types for select to anon, authenticated using (true);

create policy "profiles are visible to players"
  on public.profiles for select to authenticated using (true);

create policy "islands are visible to players"
  on public.islands for select to authenticated using (true);

create policy "players see their own havens"
  on public.havens for select to authenticated
  using (player_id = auth.uid());

create policy "players see buildings in their own havens"
  on public.buildings for select to authenticated
  using (exists (select 1 from public.havens h
                 where h.id = buildings.haven_id and h.player_id = auth.uid()));

-- ---------------------------------------------------------------------
-- Profiles are created automatically when someone signs up
-- ---------------------------------------------------------------------

create function public.handle_new_user() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  base_name text;
  candidate text;
begin
  base_name := coalesce(nullif(new.raw_user_meta_data ->> 'username', ''),
                        split_part(coalesce(new.email, 'captain'), '@', 1));
  base_name := left(regexp_replace(base_name, '[^A-Za-z0-9_]', '', 'g'), 20);
  if base_name = '' then base_name := 'captain'; end if;

  candidate := base_name;
  while exists (select 1 from public.profiles where username = candidate) loop
    candidate := base_name || (1000 + floor(random() * 9000))::int;
  end loop;

  insert into public.profiles (id, username) values (new.id, candidate)
  on conflict (id) do nothing;
  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- ---------------------------------------------------------------------
-- Production
-- ---------------------------------------------------------------------

-- Production per hour and storage capacity, from completed building levels.
create function public.haven_rates(p_haven bigint,
                                   out timber numeric, out luxury numeric,
                                   out gold numeric, out capacity numeric)
language sql stable as $$
  select
    coalesce(sum(bt.base_rate * b.level) filter (where bt.produces = 'timber'), 0),
    coalesce(sum(bt.base_rate * b.level) filter (where bt.produces = 'luxury'), 0),
    coalesce(sum(bt.base_rate * b.level) filter (where bt.produces = 'gold'), 0),
    public.base_storage() + coalesce(sum(bt.storage_per_level * b.level), 0)
  from public.buildings b
  join public.building_types bt on bt.id = b.type
  where b.haven_id = p_haven and b.level > 0
$$;

-- Add production between p_from and p_to, using the current building levels.
-- Goods are capped at storage capacity (but never reduced). Gold has no cap.
create function public.apply_production(p_haven bigint, p_from timestamptz, p_to timestamptz)
returns void
language plpgsql as $$
declare
  r     record;
  hours numeric;
  lux   text;
begin
  hours := extract(epoch from (p_to - p_from)) / 3600.0;
  if hours <= 0 then return; end if;

  select * into r from public.haven_rates(p_haven);
  select i.luxury_resource into lux
  from public.havens h join public.islands i on i.id = h.island_id
  where h.id = p_haven;

  update public.havens set
    timber = greatest(timber, least(r.capacity, timber + r.timber * hours)),
    rum    = case when lux = 'rum'   then greatest(rum,   least(r.capacity, rum   + r.luxury * hours)) else rum   end,
    spice  = case when lux = 'spice' then greatest(spice, least(r.capacity, spice + r.luxury * hours)) else spice end,
    iron   = case when lux = 'iron'  then greatest(iron,  least(r.capacity, iron  + r.luxury * hours)) else iron  end,
    silk   = case when lux = 'silk'  then greatest(silk,  least(r.capacity, silk  + r.luxury * hours)) else silk  end,
    gold   = gold + r.gold * hours
  where id = p_haven;
end;
$$;

-- Bring a haven up to date: production in segments, completing each
-- construction at the moment it finished, so new levels count from then.
create function public.settle_haven(p_haven bigint) returns void
language plpgsql as $$
declare
  now_ts  timestamptz := now();
  cursor_ts timestamptz;
  next_b  record;
begin
  select resources_updated_at into cursor_ts
  from public.havens where id = p_haven for update;

  loop
    select b.id, b.upgrade_finishes_at into next_b
    from public.buildings b
    where b.haven_id = p_haven
      and b.upgrade_finishes_at is not null
      and b.upgrade_finishes_at <= now_ts
    order by b.upgrade_finishes_at
    limit 1;

    exit when next_b.id is null;

    perform public.apply_production(p_haven, cursor_ts, greatest(cursor_ts, next_b.upgrade_finishes_at));
    cursor_ts := greatest(cursor_ts, next_b.upgrade_finishes_at);

    update public.buildings
    set level = level + 1, upgrade_finishes_at = null
    where id = next_b.id;
  end loop;

  perform public.apply_production(p_haven, cursor_ts, now_ts);
  update public.havens set resources_updated_at = now_ts where id = p_haven;
end;
$$;

-- ---------------------------------------------------------------------
-- Helpers for the RPCs
-- ---------------------------------------------------------------------

-- The calling player's capital haven id (or an error).
create function public.my_capital() returns bigint
language plpgsql stable security definer set search_path = public as $$
declare
  hid bigint;
begin
  if auth.uid() is null then
    raise exception 'You need to be logged in.';
  end if;
  select id into hid from public.havens
  where player_id = auth.uid() and is_capital
  order by id limit 1;
  if hid is null then
    raise exception 'You don''t have a haven yet.';
  end if;
  return hid;
end;
$$;

-- Pay a cost from a haven, or raise a readable error.
create function public.pay(p_haven bigint, p_timber int, p_gold int) returns void
language plpgsql as $$
declare
  h record;
begin
  select timber, gold into h from public.havens where id = p_haven;
  if h.timber < p_timber then
    raise exception 'Not enough timber (need %, have %).', p_timber, floor(h.timber);
  end if;
  if h.gold < p_gold then
    raise exception 'Not enough gold (need %, have %).', p_gold, floor(h.gold);
  end if;
  update public.havens
  set timber = timber - p_timber, gold = gold - p_gold
  where id = p_haven;
end;
$$;

-- Raise an error if a construction is already running (one build queue).
create function public.require_free_queue(p_haven bigint) returns void
language plpgsql as $$
begin
  if exists (select 1 from public.buildings
             where haven_id = p_haven and upgrade_finishes_at is not null) then
    raise exception 'Your builders are busy. Wait for the current construction to finish.';
  end if;
end;
$$;

-- Everything the client needs to draw the haven, as JSON.
create function public.haven_state(p_haven bigint) returns jsonb
language sql stable as $$
  select jsonb_build_object(
    'server_time', now(),
    'plots', public.haven_plots(),
    'haven', jsonb_build_object(
      'id', h.id,
      'name', h.name,
      'island', jsonb_build_object('id', i.id, 'name', i.name, 'x', i.x, 'y', i.y,
                                   'luxury', i.luxury_resource)
    ),
    'resources', jsonb_build_object(
      'timber', h.timber, 'rum', h.rum, 'spice', h.spice,
      'iron', h.iron, 'silk', h.silk, 'gold', h.gold
    ),
    'rates', (select jsonb_build_object('timber', r.timber, 'luxury', r.luxury,
                                        'gold', r.gold, 'capacity', r.capacity)
              from public.haven_rates(h.id) r),
    'buildings', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', b.id,
        'type', b.type,
        'slot', b.slot,
        'level', b.level,
        'upgrade_finishes_at', b.upgrade_finishes_at,
        'max_level', bt.max_level,
        -- what level + 1 costs, takes and produces (null at max level).
        -- While a construction runs, this describes the level being built.
        'next', case when b.level < bt.max_level then
          jsonb_build_object(
            'level', b.level + 1,
            'cost', to_jsonb(public.building_cost(b.type, b.level + 1)),
            'seconds', public.build_seconds(b.type, b.level + 1),
            'rate', bt.base_rate * (b.level + 1),
            'storage', bt.storage_per_level * (b.level + 1))
        end
      ) order by b.slot)
      from public.buildings b
      join public.building_types bt on bt.id = b.type
      where b.haven_id = h.id), '[]'::jsonb),
    'catalogue', (
      select jsonb_agg(jsonb_build_object(
        'id', bt.id,
        'name', bt.name,
        'description', bt.description,
        'buildable', bt.buildable,
        'produces', bt.produces,
        'base_rate', bt.base_rate,
        'storage_per_level', bt.storage_per_level,
        'cost', to_jsonb(public.building_cost(bt.id, 1)),
        'seconds', public.build_seconds(bt.id, 1)
      ) order by bt.sort_order)
      from public.building_types bt)
  )
  from public.havens h
  join public.islands i on i.id = h.island_id
  where h.id = p_haven
$$;

-- ---------------------------------------------------------------------
-- RPCs (the only way players change anything)
-- ---------------------------------------------------------------------

-- Called after login. Makes sure the player has a profile and a haven,
-- and returns the haven state. Safe to call every time.
create function public.start_game() returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  uid      uuid := auth.uid();
  uname    text;
  hid      bigint;
  isl      record;
  free_slot int;
  attempt  int := 0;
begin
  if uid is null then
    raise exception 'You need to be logged in.';
  end if;

  -- Profile (normally created by the signup trigger; this covers older users).
  if not exists (select 1 from public.profiles where id = uid) then
    insert into public.profiles (id, username)
    values (uid, 'captain' || (1000 + floor(random() * 9000))::int)
    on conflict do nothing;
  end if;
  update public.profiles set last_login = now() where id = uid
  returning username into uname;

  select id into hid from public.havens where player_id = uid and is_capital limit 1;

  -- New player: find a free spot on the least crowded island.
  while hid is null loop
    attempt := attempt + 1;
    if attempt > 5 then
      raise exception 'Could not find room for your haven. Please try again.';
    end if;

    select i.id, i.max_slots into isl
    from public.islands i
    left join public.havens h on h.island_id = i.id
    group by i.id
    having count(h.id) < i.max_slots
    order by count(h.id), random()
    limit 1;

    -- Every island is full: chart a new one.
    if isl.id is null then
      insert into public.islands (name, x, y, luxury_resource)
      values ('Uncharted Cay ' || (select count(*) + 1 from public.islands),
              floor(random() * 100)::int, floor(random() * 100)::int,
              (array['rum', 'spice', 'iron', 'silk'])[1 + floor(random() * 4)::int])
      returning id, max_slots into isl;
    end if;

    select s into free_slot
    from generate_series(0, isl.max_slots - 1) s
    where not exists (select 1 from public.havens
                      where island_id = isl.id and island_slot = s)
    order by s limit 1;

    begin
      insert into public.havens (player_id, island_id, island_slot, name)
      values (uid, isl.id, free_slot, uname || '''s Haven')
      returning id into hid;
    exception when unique_violation then
      hid := null;  -- someone took the slot at the same moment; try again
    end;
  end loop;

  -- Every haven starts with a level 1 Captain's Quarters on plot 0.
  insert into public.buildings (haven_id, type, slot, level)
  values (hid, 'captains_quarters', 0, 1)
  on conflict do nothing;

  perform public.settle_haven(hid);
  return public.haven_state(hid);
end;
$$;

-- Current state of the player's haven (settled up to now).
create function public.get_my_haven() returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  hid bigint := public.my_capital();
begin
  perform public.settle_haven(hid);
  return public.haven_state(hid);
end;
$$;

-- Place a new building on an empty plot. Starts construction to level 1.
create function public.place_building(p_type text, p_slot int) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  hid  bigint := public.my_capital();
  bt   public.building_types;
  cost record;
begin
  perform public.settle_haven(hid);

  select * into bt from public.building_types where id = p_type;
  if bt.id is null or not bt.buildable then
    raise exception 'That building can''t be built.';
  end if;
  if p_slot < 1 or p_slot >= public.haven_plots() then
    raise exception 'That plot doesn''t exist.';
  end if;
  if exists (select 1 from public.buildings where haven_id = hid and slot = p_slot) then
    raise exception 'That plot is already taken.';
  end if;
  if exists (select 1 from public.buildings where haven_id = hid and type = p_type) then
    raise exception 'You already have a %.', bt.name;
  end if;
  perform public.require_free_queue(hid);

  select * into cost from public.building_cost(p_type, 1);
  perform public.pay(hid, cost.timber, cost.gold);

  insert into public.buildings (haven_id, type, slot, level, upgrade_finishes_at)
  values (hid, p_type, p_slot, 0,
          now() + make_interval(secs => public.build_seconds(p_type, 1)));

  return public.haven_state(hid);
end;
$$;

-- Upgrade an existing building by one level.
create function public.upgrade_building(p_building bigint) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  hid  bigint := public.my_capital();
  b    record;
  cost record;
begin
  perform public.settle_haven(hid);

  select b2.*, bt.max_level, bt.name into b
  from public.buildings b2
  join public.building_types bt on bt.id = b2.type
  where b2.id = p_building and b2.haven_id = hid;

  if b.id is null then
    raise exception 'That building isn''t in your haven.';
  end if;
  if b.upgrade_finishes_at is not null then
    raise exception 'The % is already being built.', b.name;
  end if;
  if b.level >= b.max_level then
    raise exception 'The % is already at the highest level.', b.name;
  end if;
  perform public.require_free_queue(hid);

  select * into cost from public.building_cost(b.type, b.level + 1);
  perform public.pay(hid, cost.timber, cost.gold);

  update public.buildings
  set upgrade_finishes_at = now() + make_interval(secs => public.build_seconds(b.type, b.level + 1))
  where id = p_building;

  return public.haven_state(hid);
end;
$$;

-- ---------------------------------------------------------------------
-- Function permissions: only the four RPCs are callable by players
-- ---------------------------------------------------------------------

revoke execute on all functions in schema public from public, anon, authenticated;

grant execute on function public.start_game()                to authenticated;
grant execute on function public.get_my_haven()              to authenticated;
grant execute on function public.place_building(text, int)   to authenticated;
grant execute on function public.upgrade_building(bigint)    to authenticated;

-- ---------------------------------------------------------------------
-- Seed: the starting archipelago
-- ---------------------------------------------------------------------

insert into public.islands (name, x, y, luxury_resource) values
  ('Blackwake Cay',     12, 18, 'rum'),
  ('Saltbone Key',      27,  9, 'spice'),
  ('Hangman''s Reef',   41, 22, 'iron'),
  ('Isla de Seda',      58, 14, 'silk'),
  ('Grogmoor',          73, 27, 'rum'),
  ('Cinnamon Shoals',   86, 11, 'spice'),
  ('Anvil Rock',        18, 44, 'iron'),
  ('Silkwater Isle',    35, 51, 'silk'),
  ('Rumrunner''s Rest', 52, 39, 'rum'),
  ('Pepperhook',        67, 55, 'spice'),
  ('Ironjaw Atoll',     82, 47, 'iron'),
  ('Lantern Cove',      23, 73, 'silk'),
  ('Barrelhead',        44, 81, 'rum'),
  ('Clove Point',       61, 76, 'spice'),
  ('Cannonfire Isle',   78, 88, 'iron'),
  ('Mistveil',          91, 69, 'silk');

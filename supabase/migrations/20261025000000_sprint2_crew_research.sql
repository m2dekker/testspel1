-- =====================================================================
-- Blackwake Isles – Sprint 2: crew, jobs, Tavern, Academy, research,
-- island neighbours.
--
-- Production model (replaces the fixed per-level rates of Sprint 1):
--   * The Captain's Quarters houses crew (crew_per_level × level).
--   * Crew grows linearly up to that cap (base + Tavern growth per hour).
--   * Crew assigned to a building works there: output = workers × worker_rate.
--     Building level sets the number of jobs (workers_per_level × level).
--   * Idle crew earn gold. Because crew grows during a settlement segment,
--     idle gold is integrated exactly over that growth.
-- =====================================================================

-- ---------------------------------------------------------------------
-- Game constants
-- ---------------------------------------------------------------------

-- Crew arriving per hour without a Tavern.
create function public.base_crew_growth() returns numeric
language sql immutable as $$ select 12::numeric $$;

-- Gold per hour earned by each idle crew member (before research bonuses).
create function public.gold_per_idle_crew() returns numeric
language sql immutable as $$ select 4::numeric $$;

-- ---------------------------------------------------------------------
-- Building catalogue: new columns and buildings
-- ---------------------------------------------------------------------

-- 'gold' is no longer produced by a building; 'research' is new.
alter table public.building_types drop constraint building_types_produces_check;

alter table public.building_types
  add column worker_rate       numeric not null default 0,  -- output per worker per hour
  add column workers_per_level int     not null default 0,  -- jobs per level
  add column crew_per_level    int     not null default 0,  -- housing per level
  add column growth_per_level  numeric not null default 0;  -- extra crew per hour per level

-- The Captain's Quarters no longer makes gold itself; idle crew do.
update public.building_types set produces = null, crew_per_level = 20
where id = 'captains_quarters';
update public.building_types set worker_rate = 40, workers_per_level = 8
where id = 'lumber_camp';
update public.building_types set worker_rate = 15, workers_per_level = 6
where id = 'plantation';

update public.building_types set description =
  'The heart of your haven. Houses your crew. Crew without a job earn gold.'
where id = 'captains_quarters';

insert into public.building_types
  (id, name, description, buildable, base_cost_timber, base_cost_gold, cost_growth,
   base_build_seconds, time_growth, produces, worker_rate, workers_per_level,
   growth_per_level, sort_order)
values
  ('tavern', 'Tavern',
   'Grog, songs and gossip. A lively tavern draws new crew to your haven faster.',
   true, 120, 40, 1.6, 25, 1.5, null, 0, 0, 12, 4),
  ('academy', 'Academy',
   'Scholars study charts and ledgers here and produce research points.',
   true, 150, 50, 1.6, 30, 1.5, 'research', 10, 6, 0, 5);

alter table public.building_types
  add constraint building_types_produces_check
  check (produces in ('timber', 'luxury', 'research'));

-- base_rate was the Sprint 1 fixed rate per level; production now comes from workers.
alter table public.building_types drop column base_rate;

-- ---------------------------------------------------------------------
-- Crew and research on havens, workers on buildings
-- ---------------------------------------------------------------------

alter table public.havens
  add column crew            numeric(12, 4) not null default 6,
  add column research_points numeric(14, 4) not null default 0;

alter table public.buildings
  add column workers int not null default 0 check (workers >= 0);

-- ---------------------------------------------------------------------
-- Research
-- ---------------------------------------------------------------------

create table public.techs (
  id           text primary key,
  tree         text not null check (tree in ('economy', 'seafaring', 'warfare', 'intrigue')),
  name         text not null,
  description  text not null,
  cost         int not null,                       -- research points
  requires     text references public.techs (id),  -- must be researched first
  effect       text not null check (effect in
                 ('timber_bonus', 'luxury_bonus', 'storage_bonus', 'idle_gold_bonus')),
  effect_value numeric not null,                    -- e.g. 0.2 = +20%
  sort_order   int not null default 0
);

create table public.player_techs (
  player_id     uuid not null references public.profiles (id) on delete cascade,
  tech_id       text not null references public.techs (id),
  researched_at timestamptz not null default now(),
  primary key (player_id, tech_id)
);

alter table public.techs        enable row level security;
alter table public.player_techs enable row level security;

create policy "techs are public"
  on public.techs for select to anon, authenticated using (true);

create policy "players see their own research"
  on public.player_techs for select to authenticated
  using (player_id = auth.uid());

insert into public.techs (id, tree, name, description, cost, requires, effect, effect_value, sort_order) values
  ('sharpened_axes', 'economy', 'Sharpened Axes',
   'Lumberjacks fell trees 20% faster.', 20, null, 'timber_bonus', 0.2, 1),
  ('bonded_warehouses', 'economy', 'Bonded Warehouses',
   'Stack the crates higher: 50% more storage.', 60, 'sharpened_axes', 'storage_bonus', 0.5, 2),
  ('plantation_overseers', 'economy', 'Plantation Overseers',
   'Plantations produce 20% more.', 120, 'bonded_warehouses', 'luxury_bonus', 0.2, 3),
  ('ships_ledger', 'economy', 'Ship''s Ledger',
   'Idle crew earn 50% more gold.', 240, 'plantation_overseers', 'idle_gold_bonus', 0.5, 4);

-- Sum of a research bonus for a player (0 when nothing is researched).
create function public.tech_bonus(p_player uuid, p_effect text) returns numeric
language sql stable as $$
  select coalesce(sum(t.effect_value), 0)
  from public.player_techs pt
  join public.techs t on t.id = pt.tech_id
  where pt.player_id = p_player and t.effect = p_effect
$$;

-- ---------------------------------------------------------------------
-- Production (replaces the Sprint 1 versions)
-- ---------------------------------------------------------------------

drop function public.haven_rates(bigint);

-- Per-hour rates and caps of a haven, from finished buildings, workers and research.
create function public.haven_rates(p_haven bigint,
                                   out timber numeric, out luxury numeric,
                                   out research numeric, out gold_per_idle numeric,
                                   out crew_cap numeric, out crew_growth numeric,
                                   out assigned numeric, out capacity numeric)
language plpgsql stable as $$
declare
  pid uuid;
begin
  select player_id into pid from public.havens where id = p_haven;

  select
    coalesce(sum(b.workers * bt.worker_rate) filter (where bt.produces = 'timber'), 0),
    coalesce(sum(b.workers * bt.worker_rate) filter (where bt.produces = 'luxury'), 0),
    coalesce(sum(b.workers * bt.worker_rate) filter (where bt.produces = 'research'), 0),
    coalesce(sum(bt.crew_per_level * b.level), 0),
    public.base_crew_growth() + coalesce(sum(bt.growth_per_level * b.level), 0),
    coalesce(sum(b.workers), 0),
    public.base_storage() + coalesce(sum(bt.storage_per_level * b.level), 0)
  into timber, luxury, research, crew_cap, crew_growth, assigned, capacity
  from public.buildings b
  join public.building_types bt on bt.id = b.type
  where b.haven_id = p_haven and b.level > 0;

  timber        := timber   * (1 + public.tech_bonus(pid, 'timber_bonus'));
  luxury        := luxury   * (1 + public.tech_bonus(pid, 'luxury_bonus'));
  capacity      := capacity * (1 + public.tech_bonus(pid, 'storage_bonus'));
  gold_per_idle := public.gold_per_idle_crew() * (1 + public.tech_bonus(pid, 'idle_gold_bonus'));
end;
$$;

-- Add production between p_from and p_to, using the current buildings.
create or replace function public.apply_production(p_haven bigint, p_from timestamptz, p_to timestamptz)
returns void
language plpgsql as $$
declare
  r          record;
  hours      numeric;
  lux        text;
  crew_now   numeric;
  crew_end   numeric;
  crew_hours numeric;  -- integral of crew over the segment (crew × hours)
  t_cap      numeric;
begin
  hours := extract(epoch from (p_to - p_from)) / 3600.0;
  if hours <= 0 then return; end if;

  select * into r from public.haven_rates(p_haven);
  select h.crew, i.luxury_resource into crew_now, lux
  from public.havens h join public.islands i on i.id = h.island_id
  where h.id = p_haven;

  -- Crew grows linearly until it reaches the cap.
  if crew_now >= r.crew_cap or r.crew_growth <= 0 then
    crew_end   := crew_now;
    crew_hours := crew_now * hours;
  else
    t_cap := (r.crew_cap - crew_now) / r.crew_growth;
    if hours <= t_cap then
      crew_end   := crew_now + r.crew_growth * hours;
      crew_hours := (crew_now + crew_end) / 2 * hours;
    else
      crew_end   := r.crew_cap;
      crew_hours := (crew_now + r.crew_cap) / 2 * t_cap + r.crew_cap * (hours - t_cap);
    end if;
  end if;

  update public.havens set
    timber = greatest(timber, least(r.capacity, timber + r.timber * hours)),
    rum    = case when lux = 'rum'   then greatest(rum,   least(r.capacity, rum   + r.luxury * hours)) else rum   end,
    spice  = case when lux = 'spice' then greatest(spice, least(r.capacity, spice + r.luxury * hours)) else spice end,
    iron   = case when lux = 'iron'  then greatest(iron,  least(r.capacity, iron  + r.luxury * hours)) else iron  end,
    silk   = case when lux = 'silk'  then greatest(silk,  least(r.capacity, silk  + r.luxury * hours)) else silk  end,
    research_points = research_points + r.research * hours,
    -- idle crew-hours = all crew-hours minus the hours worked
    gold   = gold + r.gold_per_idle * greatest(0, crew_hours - r.assigned * hours),
    crew   = crew_end
  where id = p_haven;
end;
$$;

-- What one level of a building gives (for display).
create function public.building_effect(p_type text, p_level int) returns jsonb
language sql stable as $$
  select jsonb_build_object(
    'produces',    bt.produces,
    'worker_rate', bt.worker_rate,
    'workers',     bt.workers_per_level * p_level,
    'crew_cap',    bt.crew_per_level * p_level,
    'growth',      bt.growth_per_level * p_level,
    'storage',     bt.storage_per_level * p_level)
  from public.building_types bt
  where bt.id = p_type
$$;

-- Everything the client needs to draw the haven, as JSON.
create or replace function public.haven_state(p_haven bigint) returns jsonb
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
    'rates', jsonb_build_object('timber', r.timber, 'luxury', r.luxury,
                                'research', r.research, 'capacity', r.capacity),
    'crew', jsonb_build_object('amount', h.crew, 'cap', r.crew_cap,
                               'growth', r.crew_growth, 'assigned', r.assigned,
                               'gold_per_idle', r.gold_per_idle),
    'research_points', h.research_points,
    'buildings', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', b.id,
        'type', b.type,
        'slot', b.slot,
        'level', b.level,
        'workers', b.workers,
        'upgrade_finishes_at', b.upgrade_finishes_at,
        'max_level', bt.max_level,
        'effect', public.building_effect(b.type, b.level),
        -- level + 1: what it costs, takes and gives (null at max level).
        -- While a construction runs, this describes the level being built.
        'next', case when b.level < bt.max_level then
          jsonb_build_object(
            'level', b.level + 1,
            'cost', to_jsonb(public.building_cost(b.type, b.level + 1)),
            'seconds', public.build_seconds(b.type, b.level + 1),
            'effect', public.building_effect(b.type, b.level + 1))
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
        'cost', to_jsonb(public.building_cost(bt.id, 1)),
        'seconds', public.build_seconds(bt.id, 1),
        'effect', public.building_effect(bt.id, 1)
      ) order by bt.sort_order)
      from public.building_types bt),
    'techs', (
      select jsonb_agg(jsonb_build_object(
        'id', t.id,
        'tree', t.tree,
        'name', t.name,
        'description', t.description,
        'cost', t.cost,
        'requires', t.requires,
        'researched', exists (select 1 from public.player_techs pt
                              where pt.player_id = h.player_id and pt.tech_id = t.id)
      ) order by t.sort_order)
      from public.techs t)
  )
  from public.havens h
  join public.islands i on i.id = h.island_id
  cross join lateral public.haven_rates(h.id) r
  where h.id = p_haven
$$;

-- ---------------------------------------------------------------------
-- New RPCs
-- ---------------------------------------------------------------------

-- Set how many crew work at a building.
create function public.assign_workers(p_building bigint, p_workers int) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  hid    bigint := public.my_capital();
  b      record;
  others int;
  crew   numeric;
begin
  perform public.settle_haven(hid);

  select b2.*, bt.name, bt.workers_per_level into b
  from public.buildings b2
  join public.building_types bt on bt.id = b2.type
  where b2.id = p_building and b2.haven_id = hid;

  if b.id is null then
    raise exception 'That building isn''t in your haven.';
  end if;
  if b.workers_per_level = 0 then
    raise exception 'Nobody can work at the %.', b.name;
  end if;
  if b.level = 0 then
    raise exception 'The % isn''t finished yet.', b.name;
  end if;
  if p_workers < 0 or p_workers > b.workers_per_level * b.level then
    raise exception 'The % has jobs for % crew.', b.name, b.workers_per_level * b.level;
  end if;

  select coalesce(sum(workers), 0) into others
  from public.buildings where haven_id = hid and id <> p_building;
  select h.crew into crew from public.havens h where h.id = hid;

  if others + p_workers > floor(crew) then
    raise exception 'Not enough crew (% free).', greatest(0, floor(crew)::int - others);
  end if;

  update public.buildings set workers = p_workers where id = p_building;
  return public.haven_state(hid);
end;
$$;

-- Spend research points on a tech.
create function public.research_tech(p_tech text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  hid    bigint := public.my_capital();
  t      public.techs;
  points numeric;
begin
  perform public.settle_haven(hid);

  select * into t from public.techs where id = p_tech;
  if t.id is null then
    raise exception 'Unknown research.';
  end if;
  if exists (select 1 from public.player_techs where player_id = auth.uid() and tech_id = p_tech) then
    raise exception 'You already know %.', t.name;
  end if;
  if t.requires is not null and not exists (
       select 1 from public.player_techs where player_id = auth.uid() and tech_id = t.requires) then
    raise exception 'Research % first.', (select name from public.techs where id = t.requires);
  end if;

  select research_points into points from public.havens where id = hid;
  if points < t.cost then
    raise exception 'Not enough research points (need %, have %).', t.cost, floor(points);
  end if;

  update public.havens set research_points = research_points - t.cost where id = hid;
  insert into public.player_techs (player_id, tech_id) values (auth.uid(), p_tech);
  return public.haven_state(hid);
end;
$$;

-- The havens on the player's island: only name and captain, nothing else.
create function public.island_neighbours() returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  hid bigint := public.my_capital();
begin
  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'haven', h.name,
      'captain', p.username,
      'slot', h.island_slot,
      'is_you', h.player_id = auth.uid()
    ) order by h.island_slot)
    from public.havens h
    join public.profiles p on p.id = h.player_id
    where h.island_id = (select island_id from public.havens where id = hid)
  ), '[]'::jsonb);
end;
$$;

-- ---------------------------------------------------------------------
-- Function permissions: only the RPCs are callable by players
-- ---------------------------------------------------------------------

revoke execute on all functions in schema public from public, anon, authenticated;

grant execute on function public.start_game()                    to authenticated;
grant execute on function public.get_my_haven()                  to authenticated;
grant execute on function public.place_building(text, int)       to authenticated;
grant execute on function public.upgrade_building(bigint)        to authenticated;
grant execute on function public.assign_workers(bigint, int)     to authenticated;
grant execute on function public.research_tech(text)             to authenticated;
grant execute on function public.island_neighbours()             to authenticated;

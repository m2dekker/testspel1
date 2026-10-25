-- Plays through the haven rules as real players and checks the results.
-- Every statement runs in its own transaction, so now() moves forward.
-- "Time travel" is done by shifting stored timestamps into the past as admin.

\set QUIET on
\set ON_ERROR_STOP on

-- Shift Anne's haven one hour (or any interval) into the past.
create function pg_temp.time_passes(p_player uuid, p_by interval) returns void
language sql as $$
  update public.havens set resources_updated_at = resources_updated_at - p_by
  where player_id = p_player;
  update public.buildings set upgrade_finishes_at = upgrade_finishes_at - p_by
  where upgrade_finishes_at is not null
    and haven_id in (select id from public.havens where player_id = p_player);
$$;

-- Two players sign up.
insert into auth.users (id, email, raw_user_meta_data) values
  ('00000000-0000-0000-0000-00000000000a', 'anne@example.com', '{"username": "AnneBonny"}'),
  ('00000000-0000-0000-0000-00000000000b', 'mary@example.com', '{}');

do $$ begin
  assert (select username from profiles where id = '00000000-0000-0000-0000-00000000000a') = 'AnneBonny',
    'profile uses the username from sign-up metadata';
  assert (select username from profiles where id = '00000000-0000-0000-0000-00000000000b') = 'mary',
    'profile falls back to the email name';
end $$;

-- ---------- Anne starts the game ----------
set role authenticated;
set request.jwt.claims = '{"sub": "00000000-0000-0000-0000-00000000000a"}';

do $$
declare s jsonb := start_game(); s2 jsonb := start_game();
begin
  assert s -> 'haven' ->> 'id' = s2 -> 'haven' ->> 'id', 'start_game is idempotent';
  assert s -> 'haven' ->> 'name' = 'AnneBonny''s Haven', 'haven is named after the player';
  assert jsonb_array_length(s -> 'buildings') = 1, 'haven starts with one building';
  assert s -> 'buildings' -> 0 ->> 'type' = 'captains_quarters', 'starting building is the Captain''s Quarters';
  assert (s -> 'resources' ->> 'timber')::numeric = 300, 'starting timber';
  assert (s -> 'crew' ->> 'amount')::numeric between 6 and 6.01, 'starting crew';
  assert (s -> 'crew' ->> 'cap')::numeric = 20, 'Captain''s Quarters level 1 houses 20';
  assert jsonb_array_length(s -> 'catalogue') = 6, 'catalogue lists 6 building types';
  assert jsonb_array_length(s -> 'techs') = 4, 'four Economy techs';
end $$;

-- Players cannot write to tables directly.
do $$ begin
  begin
    update havens set timber = 999999;
    assert (select timber from havens limit 1) < 999999, 'direct updates change nothing (RLS)';
  end;
  begin
    insert into buildings (haven_id, type, slot, level) values ((select id from havens limit 1), 'warehouse', 5, 10);
    assert false, 'direct inserts must fail';
  exception when insufficient_privilege then null;
  end;
  begin
    insert into player_techs (player_id, tech_id) values (auth.uid(), 'ships_ledger');
    assert false, 'players cannot grant themselves research';
  exception when insufficient_privilege then null;
  end;
end $$;

-- Internal functions are not callable by players.
do $$ begin
  begin
    perform settle_haven(1);
    assert false, 'settle_haven must not be callable';
  exception when insufficient_privilege then null;
  end;
end $$;

-- Place a lumber camp.
do $$
declare s jsonb := place_building('lumber_camp', 1);
begin
  assert (s -> 'resources' ->> 'timber')::numeric between 240 and 240.1, 'lumber camp costs 60 timber';
  assert s -> 'buildings' -> 1 ->> 'level' = '0', 'new building starts at level 0';
  assert s -> 'buildings' -> 1 ->> 'upgrade_finishes_at' is not null, 'construction timer is running';
end $$;

-- Rules are enforced.
do $$ begin
  begin perform place_building('warehouse', 2); assert false, 'second construction must fail';
  exception when raise_exception then
    assert sqlerrm like 'Your builders are busy%', 'busy message: ' || sqlerrm;
  end;
  begin perform place_building('captains_quarters', 3); assert false, 'pre-built only';
  exception when raise_exception then null; end;
  begin perform place_building('warehouse', 0); assert false, 'plot 0 is reserved';
  exception when raise_exception then null; end;
  begin perform place_building('warehouse', 8); assert false, 'plot 8 does not exist';
  exception when raise_exception then null; end;
  begin perform assign_workers((select id from buildings where type = 'lumber_camp'), 2);
    assert false, 'no workers before the building is finished';
  exception when raise_exception then
    assert sqlerrm like '%isn''t finished yet%', 'unfinished message: ' || sqlerrm;
  end;
end $$;

-- ---------- Mary cannot see Anne's haven ----------
set request.jwt.claims = '{"sub": "00000000-0000-0000-0000-00000000000b"}';
do $$
declare s jsonb := start_game();
begin
  assert (select count(*) from havens) = 1, 'Mary only sees her own haven';
  assert (select count(*) from buildings) = 1, 'Mary only sees her own buildings';
  begin
    perform upgrade_building((select min(id) from buildings b where b.type = 'lumber_camp'));
    assert false, 'upgrading someone else''s building must fail';
  exception when raise_exception then null; end;
end $$;

-- ---------- One hour passes (Anne is offline, nobody works yet) ----------
reset role;
select pg_temp.time_passes('00000000-0000-0000-0000-00000000000a', interval '1 hour');

set role authenticated;
set request.jwt.claims = '{"sub": "00000000-0000-0000-0000-00000000000a"}';
do $$
declare s jsonb := get_my_haven(); g numeric; c numeric;
begin
  g := (s -> 'resources' ->> 'gold')::numeric;
  c := (s -> 'crew' ->> 'amount')::numeric;
  assert s -> 'buildings' -> 1 ->> 'level' = '1', 'lumber camp finished while offline';
  assert s -> 'buildings' -> 1 ->> 'upgrade_finishes_at' is null, 'timer cleared';
  assert (s -> 'resources' ->> 'timber')::numeric between 240 and 240.1, 'no timber without workers';
  -- Crew grows 12/h: 6 → 18. Average crew 12 for one hour, all idle: 12 × 4 gold.
  assert c between 18 and 18.01, 'crew grew offline: ' || c;
  assert g between 147.9 and 148.1, 'idle crew earned gold offline: ' || g;
  assert (s -> 'buildings' -> 1 -> 'next' -> 'cost' ->> 'timber')::int = 96, 'level 2 costs 60 × 1.6';
  assert (s -> 'buildings' -> 1 -> 'effect' ->> 'workers')::int = 8, 'level 1 has 8 jobs';
end $$;

-- Put 8 crew to work at the lumber camp.
do $$
declare s jsonb;
begin
  begin perform assign_workers((select id from buildings where type = 'lumber_camp'), 9);
    assert false, 'only 8 jobs at level 1';
  exception when raise_exception then
    assert sqlerrm like '%has jobs for 8 crew%', 'jobs message: ' || sqlerrm;
  end;
  begin perform assign_workers((select id from buildings where type = 'captains_quarters'), 1);
    assert false, 'nobody works at the Captain''s Quarters';
  exception when raise_exception then null; end;

  s := assign_workers((select id from buildings where type = 'lumber_camp'), 8);
  assert (s -> 'rates' ->> 'timber')::numeric = 320, '8 workers × 40 timber';
  assert (s -> 'crew' ->> 'assigned')::numeric = 8, 'assigned crew is reported';
end $$;

-- Another hour: timber from workers, crew reaches the cap, only idle crew earn gold.
reset role;
select pg_temp.time_passes('00000000-0000-0000-0000-00000000000a', interval '1 hour');

set role authenticated;
do $$
declare s jsonb := get_my_haven(); t numeric; g numeric;
begin
  t := (s -> 'resources' ->> 'timber')::numeric;
  g := (s -> 'resources' ->> 'gold')::numeric;
  assert t between 240 + 319.9 and 240 + 320.1, 'timber from workers: ' || t;
  assert (s -> 'crew' ->> 'amount')::numeric = 20, 'crew stops at the housing cap';
  -- crew-hours: (18+20)/2 × 1/6 h + 20 × 5/6 h = 19.833; minus 8 worked → 11.833 × 4 gold.
  assert g between 148 + 47.2 and 148 + 47.5, 'gold only from idle crew: ' || g;
end $$;

-- Upgrade the lumber camp, then build a plantation after it.
do $$
declare s jsonb := upgrade_building((select id from buildings where type = 'lumber_camp'));
begin
  assert s -> 'buildings' -> 1 ->> 'upgrade_finishes_at' is not null, 'upgrade timer started';
  assert (s -> 'rates' ->> 'timber')::numeric = 320, 'workers keep working during an upgrade';
end $$;

reset role;
update buildings set upgrade_finishes_at = now() - interval '1 second'
where upgrade_finishes_at is not null;

set role authenticated;
do $$
declare s jsonb := place_building('plantation', 2);
begin
  assert s -> 'buildings' -> 1 ->> 'level' = '2', 'upgrade completed before the next build';
  assert (s -> 'buildings' -> 1 -> 'effect' ->> 'workers')::int = 16, 'level 2 has 16 jobs';
  assert jsonb_array_length(s -> 'buildings') = 3, 'plantation placed';
end $$;

-- ---------- Storage cap ----------
reset role;
update havens set timber = 1490, resources_updated_at = now() - interval '1 hour'
where player_id = '00000000-0000-0000-0000-00000000000a';

set role authenticated;
do $$
declare s jsonb := get_my_haven();
begin
  assert (s -> 'resources' ->> 'timber')::numeric = 1500, 'timber is capped at storage';
end $$;

-- ---------- Anonymous visitors can't play ----------
set role anon;
set request.jwt.claims = '';
do $$ begin
  begin perform start_game(); assert false, 'anon must not start a game';
  exception when insufficient_privilege then null; end;
end $$;

reset role;
\echo 'Haven rules: all tests passed.'

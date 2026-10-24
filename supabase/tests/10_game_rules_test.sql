-- Plays through the Sprint 1 rules as real players and checks the results.
-- Every statement runs in its own transaction, so now() moves forward.
-- "Time travel" is done by shifting stored timestamps into the past as admin.

\set QUIET on
\set ON_ERROR_STOP on

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
  assert jsonb_array_length(s -> 'catalogue') = 4, 'catalogue lists 4 building types';
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
    -- Mary has no lumber camp; Anne's id must be rejected.
    assert false, 'upgrading someone else''s building must fail';
  exception when raise_exception then null; end;
end $$;

-- ---------- One hour passes (Anne is offline) ----------
reset role;
update havens set resources_updated_at = resources_updated_at - interval '1 hour'
where player_id = '00000000-0000-0000-0000-00000000000a';
update buildings set upgrade_finishes_at = upgrade_finishes_at - interval '1 hour'
where upgrade_finishes_at is not null
  and haven_id = (select id from havens where player_id = '00000000-0000-0000-0000-00000000000a');

set role authenticated;
set request.jwt.claims = '{"sub": "00000000-0000-0000-0000-00000000000a"}';
do $$
declare s jsonb := get_my_haven(); t numeric; g numeric;
begin
  t := (s -> 'resources' ->> 'timber')::numeric;
  g := (s -> 'resources' ->> 'gold')::numeric;
  assert s -> 'buildings' -> 1 ->> 'level' = '1', 'lumber camp finished while offline';
  assert s -> 'buildings' -> 1 ->> 'upgrade_finishes_at' is null, 'timer cleared';
  -- Lumber camp finished 15 s into the hour: 300/h for ~59m45s ≈ 298.75 timber.
  assert t between 240 + 298 and 240 + 300, 'timber produced offline: ' || t;
  -- Captain's Quarters: 30 gold/h for the full hour.
  assert g between 129.9 and 130.1, 'gold produced offline: ' || g;
  assert (s -> 'rates' ->> 'timber')::numeric = 300, 'timber rate';
  assert (s -> 'buildings' -> 1 -> 'next' -> 'cost' ->> 'timber')::int = 96, 'level 2 costs 60 × 1.6';
end $$;

-- Upgrade the lumber camp and build a plantation after it.
do $$
declare s jsonb;
begin
  s := upgrade_building((select id from buildings where type = 'lumber_camp'));
  assert s -> 'buildings' -> 1 ->> 'upgrade_finishes_at' is not null, 'upgrade timer started';
end $$;

reset role;
update buildings set upgrade_finishes_at = now() - interval '1 second'
where upgrade_finishes_at is not null;

set role authenticated;
set request.jwt.claims = '{"sub": "00000000-0000-0000-0000-00000000000a"}';
do $$
declare s jsonb := place_building('plantation', 2);
begin
  assert s -> 'buildings' -> 1 ->> 'level' = '2', 'upgrade completed before the next build';
  assert (s -> 'rates' ->> 'timber')::numeric = 600, 'level 2 doubles timber output';
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
\echo 'All database tests passed.'

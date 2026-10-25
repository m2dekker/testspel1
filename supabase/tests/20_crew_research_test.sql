-- Sprint 2: crew limits, Tavern, Academy, research and island neighbours.

\set QUIET on
\set ON_ERROR_STOP on

create function pg_temp.time_passes(p_player uuid, p_by interval) returns void
language sql as $$
  update public.havens set resources_updated_at = resources_updated_at - p_by
  where player_id = p_player;
  update public.buildings set upgrade_finishes_at = upgrade_finishes_at - p_by
  where upgrade_finishes_at is not null
    and haven_id in (select id from public.havens where player_id = p_player);
$$;

-- Finish whatever Jack is building, right now.
create function pg_temp.finish_build() returns void
language sql as $$
  update public.buildings set upgrade_finishes_at = now() - interval '1 second'
  where upgrade_finishes_at is not null
    and haven_id in (select id from public.havens
                     where player_id = '00000000-0000-0000-0000-00000000000c');
$$;

insert into auth.users (id, email, raw_user_meta_data) values
  ('00000000-0000-0000-0000-00000000000c', 'jack@example.com', '{"username": "CalicoJack"}');

set role authenticated;
set request.jwt.claims = '{"sub": "00000000-0000-0000-0000-00000000000c"}';
do $$ begin perform start_game(); perform place_building('lumber_camp', 1); end $$;
reset role; select pg_temp.finish_build(); set role authenticated;
do $$ begin perform place_building('academy', 2); end $$;
reset role; select pg_temp.finish_build(); set role authenticated;

-- ---------- Crew limits ----------
do $$
declare s jsonb;
begin
  s := assign_workers((select id from buildings where type = 'lumber_camp'), 6);
  begin
    perform assign_workers((select id from buildings where type = 'academy'), 1);
    assert false, 'cannot assign more crew than you have';
  exception when raise_exception then
    assert sqlerrm = 'Not enough crew (0 free).', 'crew message: ' || sqlerrm;
  end;
  -- Moving crew: take them off the camp, put them in the academy.
  perform assign_workers((select id from buildings where type = 'lumber_camp'), 0);
  s := assign_workers((select id from buildings where type = 'academy'), 6);
  assert (s -> 'rates' ->> 'research')::numeric = 60, '6 scholars × 10 research';
  assert (s -> 'rates' ->> 'timber')::numeric = 0, 'camp is empty now';
end $$;

-- ---------- Research rules ----------
do $$ begin
  begin perform research_tech('bonded_warehouses'); assert false, 'tech order';
  exception when raise_exception then
    assert sqlerrm = 'Research Sharpened Axes first.', 'order message: ' || sqlerrm;
  end;
  begin perform research_tech('sharpened_axes'); assert false, 'needs points';
  exception when raise_exception then
    assert sqlerrm like 'Not enough research points%', 'points message: ' || sqlerrm;
  end;
  begin perform research_tech('treasure_maps'); assert false, 'unknown tech';
  exception when raise_exception then null; end;
end $$;

reset role;
select pg_temp.time_passes('00000000-0000-0000-0000-00000000000c', interval '1 hour');
set role authenticated;

do $$
declare s jsonb := get_my_haven(); p numeric;
begin
  p := (s -> 'research_points')::numeric;
  assert p between 59.9 and 60.1, 'scholars produced research offline: ' || p;

  s := research_tech('sharpened_axes');
  assert (s -> 'research_points')::numeric between 39.9 and 40.1, 'tech cost 20 points';
  assert (select (t ->> 'researched')::boolean from jsonb_array_elements(s -> 'techs') t
          where t ->> 'id' = 'sharpened_axes'), 'tech shows as researched';

  begin perform research_tech('sharpened_axes'); assert false, 'no double research';
  exception when raise_exception then
    assert sqlerrm = 'You already know Sharpened Axes.', 'double message: ' || sqlerrm;
  end;

  -- Bonus applies: move scholars back to the camp. 6 × 40 × 1.2 = 288.
  perform assign_workers((select id from buildings where type = 'academy'), 0);
  s := assign_workers((select id from buildings where type = 'lumber_camp'), 6);
  assert (s -> 'rates' ->> 'timber')::numeric = 288, 'Sharpened Axes gives +20% timber';
end $$;

-- Give Jack plenty of points and research the rest of the tree.
reset role;
update havens set research_points = 1000
where player_id = '00000000-0000-0000-0000-00000000000c';
set role authenticated;

do $$
declare s jsonb;
begin
  perform research_tech('bonded_warehouses');
  perform research_tech('plantation_overseers');
  s := research_tech('ships_ledger');
  assert (s -> 'rates' ->> 'capacity')::numeric = 2250, 'Bonded Warehouses gives +50% storage';
  assert (s -> 'crew' ->> 'gold_per_idle')::numeric = 6, 'Ship''s Ledger gives +50% idle gold';
  assert (s -> 'research_points')::numeric between 579.9 and 580.1, '1000 − 60 − 120 − 240';
end $$;

-- ---------- Tavern ----------
reset role;
update havens set timber = 500, gold = 500
where player_id = '00000000-0000-0000-0000-00000000000c';
set role authenticated;
do $$ begin perform place_building('tavern', 3); end $$;
reset role; select pg_temp.finish_build(); set role authenticated;
do $$
declare s jsonb := get_my_haven();
begin
  assert (s -> 'crew' ->> 'growth')::numeric = 24, 'Tavern level 1 adds 12 crew per hour';
end $$;

-- ---------- Neighbours ----------
-- Put Anne's and Mary's havens on Jack's island (admin), then ask as Jack.
reset role;
update havens set island_id = (select island_id from havens where player_id = '00000000-0000-0000-0000-00000000000c'),
                  island_slot = 6
where player_id = '00000000-0000-0000-0000-00000000000a';
update havens set island_id = (select island_id from havens where player_id = '00000000-0000-0000-0000-00000000000c'),
                  island_slot = 7
where player_id = '00000000-0000-0000-0000-00000000000b';
set role authenticated;

do $$
declare n jsonb := island_neighbours(); keys text[];
begin
  assert jsonb_array_length(n) = 3, 'three havens on the island';
  assert (select count(*) from jsonb_array_elements(n) e where (e ->> 'is_you')::boolean) = 1,
    'exactly one haven is yours';
  assert exists (select 1 from jsonb_array_elements(n) e where e ->> 'captain' = 'AnneBonny'),
    'Anne is a neighbour';
  select array_agg(k order by k) into keys from jsonb_object_keys(n -> 0) k;
  assert keys = array['captain', 'haven', 'is_you', 'slot'], 'neighbours reveal only name and captain';
  -- Tables still only show Jack's own haven.
  assert (select count(*) from havens) = 1, 'RLS still hides other havens';
end $$;

reset role;
\echo 'Crew and research: all tests passed.'

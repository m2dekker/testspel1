import 'dart:math';

import 'package:blackwake_isles/features/haven/data/demo_game_backend.dart';
import 'package:blackwake_isles/features/haven/domain/models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

// These mirror supabase/tests/10_game_rules_test.sql, so the offline demo
// and the real server play by the same rules.
void main() {
  late DateTime now;
  late SharedPreferences prefs;
  late DemoGameBackend backend;

  setUp(() async {
    SharedPreferences.setMockInitialValues({
      DemoGameBackend.captainKey: 'AnneBonny',
    });
    prefs = await SharedPreferences.getInstance();
    now = DateTime.utc(2026, 10, 24, 12);
    backend = DemoGameBackend(prefs, clock: () => now, random: Random(1));
  });

  test('a new player gets a haven with a Captain\'s Quarters', () async {
    final s = await backend.startGame();
    final again = await backend.startGame();

    expect(s.name, 'AnneBonny\'s Haven');
    expect(again.havenId, s.havenId);
    expect(s.buildings.single.type, 'captains_quarters');
    expect(s.resources[Resource.timber], 300);
    expect(s.catalogue, hasLength(4));
  });

  test('placing a building costs resources and starts a timer', () async {
    await backend.startGame();
    final s = await backend.placeBuilding('lumber_camp', 1);

    expect(s.resources[Resource.timber], 240);
    final camp = s.buildingAt(1)!;
    expect(camp.level, 0);
    expect(camp.finishesAt, now.add(const Duration(seconds: 15)));
  });

  test('rules are enforced with the same messages as the server', () async {
    await backend.startGame();
    await backend.placeBuilding('lumber_camp', 1);

    Future<String> error(Future<Object?> f) => f.then(
      (_) => 'no error',
      onError: (Object e) => (e as GameException).message,
    );

    expect(
      await error(backend.placeBuilding('warehouse', 2)),
      startsWith('Your builders are busy'),
    );
    expect(
      await error(backend.placeBuilding('captains_quarters', 3)),
      'That building can\'t be built.',
    );
    expect(
      await error(backend.placeBuilding('warehouse', 0)),
      'That plot doesn\'t exist.',
    );
    expect(
      await error(backend.placeBuilding('warehouse', 8)),
      'That plot doesn\'t exist.',
    );
  });

  test(
    'production continues offline and constructions finish on time',
    () async {
      await backend.startGame();
      await backend.placeBuilding('lumber_camp', 1);

      now = now.add(const Duration(hours: 1));
      final s = await backend.fetchHaven();

      expect(s.buildingAt(1)!.level, 1);
      expect(s.buildingAt(1)!.finishesAt, isNull);
      // Lumber camp finished 15 s into the hour: 300/h for 59m45s = 298.75.
      expect(s.resources[Resource.timber], closeTo(240 + 298.75, 0.01));
      expect(s.resources[Resource.gold], closeTo(130, 0.01));
      expect(s.timberRate, 300);
      expect(s.buildingAt(1)!.next!.cost.timber, 96);
    },
  );

  test('upgrades double production and storage is capped', () async {
    await backend.startGame();
    await backend.placeBuilding('lumber_camp', 1);
    now = now.add(const Duration(hours: 1));
    final camp = (await backend.fetchHaven()).buildingAt(1)!;
    await backend.upgradeBuilding(camp.id);

    now = now.add(const Duration(minutes: 1));
    final s = await backend.placeBuilding('plantation', 2);
    expect(s.buildingAt(1)!.level, 2);
    expect(s.timberRate, 600);

    now = now.add(const Duration(hours: 10));
    final full = await backend.fetchHaven();
    expect(full.resources[Resource.timber], 1500);
    expect(full.resources[full.island.luxury], greaterThan(0));
  });

  test('progress is saved between sessions', () async {
    await backend.startGame();
    await backend.placeBuilding('warehouse', 3);

    final reopened = DemoGameBackend(prefs, clock: () => now);
    final s = await reopened.fetchHaven();
    expect(s.buildingAt(3)!.type, 'warehouse');
  });
}

import 'dart:math';

import 'package:blackwake_isles/features/haven/data/demo_game_backend.dart';
import 'package:blackwake_isles/features/haven/domain/models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

// These mirror supabase/tests/*_test.sql, so the offline demo and the real
// server play by the same rules.
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

  Future<String> error(Future<Object?> f) => f.then(
    (_) => 'no error',
    onError: (Object e) => (e as GameException).message,
  );

  /// Builds [type] on [slot] and lets the construction finish.
  Future<HavenState> buildNow(String type, int slot) async {
    final s = await backend.placeBuilding(type, slot);
    now = s.buildingAt(slot)!.finishesAt!;
    return backend.fetchHaven();
  }

  group('haven rules', () {
    test('a new player gets a haven with a Captain\'s Quarters', () async {
      final s = await backend.startGame();
      final again = await backend.startGame();

      expect(s.name, 'AnneBonny\'s Haven');
      expect(again.havenId, s.havenId);
      expect(s.buildings.single.type, 'captains_quarters');
      expect(s.resources[Resource.timber], 300);
      expect(s.crew.amount, 6);
      expect(s.crew.cap, 20);
      expect(s.catalogue, hasLength(6));
      expect(s.techs, hasLength(4));
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
      final s = await backend.placeBuilding('lumber_camp', 1);

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
      expect(
        await error(backend.assignWorkers(s.buildingAt(1)!.id, 2)),
        contains('isn\'t finished yet'),
      );
    });

    test('crew grows and idle crew earn gold while offline', () async {
      await backend.startGame();
      await backend.placeBuilding('lumber_camp', 1);

      now = now.add(const Duration(hours: 1));
      final s = await backend.fetchHaven();

      expect(s.buildingAt(1)!.level, 1);
      expect(s.resources[Resource.timber], 240); // nobody works yet
      // Crew grows 12/h: 6 → 18. Average 12 idle crew for an hour × 4 gold.
      expect(s.crew.amount, closeTo(18, 0.001));
      expect(s.resources[Resource.gold], closeTo(148, 0.01));
      expect(s.buildingAt(1)!.next!.cost.timber, 96);
      expect(s.buildingAt(1)!.effect.workers, 8);
    });

    test('workers produce, crew caps, only idle crew earn gold', () async {
      await backend.startGame();
      await backend.placeBuilding('lumber_camp', 1);
      now = now.add(const Duration(hours: 1));
      final camp = (await backend.fetchHaven()).buildingAt(1)!;

      expect(
        await error(backend.assignWorkers(camp.id, 9)),
        'The Lumber Camp has jobs for 8 crew.',
      );
      expect(
        await error(backend.assignWorkers(1, 1)),
        'Nobody can work at the Captain\'s Quarters.',
      );

      var s = await backend.assignWorkers(camp.id, 8);
      expect(s.timberRate, 320);
      expect(s.crew.assigned, 8);

      now = now.add(const Duration(hours: 1));
      s = await backend.fetchHaven();
      expect(s.resources[Resource.timber], closeTo(240 + 320, 0.01));
      expect(s.crew.amount, 20);
      // (18+20)/2 × 1/6 h + 20 × 5/6 h = 19.833 crew-hours; 8 worked.
      expect(s.resources[Resource.gold], closeTo(148 + 4 * 11.8333, 0.01));
    });

    test('upgrades add jobs and storage is capped', () async {
      await backend.startGame();
      await backend.placeBuilding('lumber_camp', 1);
      now = now.add(const Duration(hours: 1));
      final camp = (await backend.fetchHaven()).buildingAt(1)!;
      await backend.assignWorkers(camp.id, 8);
      final upgrading = await backend.upgradeBuilding(camp.id);
      expect(upgrading.timberRate, 320, reason: 'workers keep working');

      now = now.add(const Duration(minutes: 1));
      final s = await backend.placeBuilding('plantation', 2);
      expect(s.buildingAt(1)!.level, 2);
      expect(s.buildingAt(1)!.effect.workers, 16);

      now = now.add(const Duration(hours: 10));
      expect((await backend.fetchHaven()).resources[Resource.timber], 1500);
    });

    test('progress is saved between sessions', () async {
      await backend.startGame();
      await backend.placeBuilding('warehouse', 3);

      final reopened = DemoGameBackend(prefs, clock: () => now);
      final s = await reopened.fetchHaven();
      expect(s.buildingAt(3)!.type, 'warehouse');
    });
  });

  group('crew and research', () {
    late int camp, academy;

    setUp(() async {
      await backend.startGame();
      camp = (await buildNow('lumber_camp', 1)).buildingAt(1)!.id;
      academy = (await buildNow('academy', 2)).buildingAt(2)!.id;
    });

    test('cannot assign more crew than the haven has', () async {
      await backend.assignWorkers(camp, 6);
      expect(
        await error(backend.assignWorkers(academy, 1)),
        'Not enough crew (0 free).',
      );

      await backend.assignWorkers(camp, 0);
      final s = await backend.assignWorkers(academy, 6);
      expect(s.researchRate, 60);
      expect(s.timberRate, 0);
    });

    test('techs are unlocked in order and need points', () async {
      expect(
        await error(backend.research('bonded_warehouses')),
        'Research Sharpened Axes first.',
      );
      expect(
        await error(backend.research('sharpened_axes')),
        startsWith('Not enough research points'),
      );
      expect(
        await error(backend.research('treasure_maps')),
        'Unknown research.',
      );
    });

    test('research bonuses apply', () async {
      await backend.assignWorkers(academy, 6);
      now = now.add(const Duration(hours: 1));
      var s = await backend.fetchHaven();
      expect(s.researchPoints, closeTo(60, 0.01));

      s = await backend.research('sharpened_axes');
      expect(s.researchPoints, closeTo(40, 0.01));
      expect(s.techById('sharpened_axes').researched, isTrue);
      expect(
        await error(backend.research('sharpened_axes')),
        'You already know Sharpened Axes.',
      );

      await backend.assignWorkers(academy, 0);
      s = await backend.assignWorkers(camp, 6);
      expect(s.timberRate, closeTo(288, 0.001)); // 6 × 40 × 1.2

      // Plenty of time for the rest of the tree.
      await backend.assignWorkers(camp, 0);
      await backend.assignWorkers(academy, 6);
      now = now.add(const Duration(hours: 10));
      await backend.research('bonded_warehouses');
      await backend.research('plantation_overseers');
      s = await backend.research('ships_ledger');
      expect(s.capacity, 2250);
      expect(s.crew.goldPerIdle, 6);
    });

    test('a tavern makes crew arrive faster', () async {
      await backend.assignWorkers(camp, 6);
      now = now.add(const Duration(hours: 5)); // gather timber and gold
      final s = await buildNow('tavern', 3);
      expect(s.crew.growth, 24);
    });

    test('alone on the island in the demo', () async {
      final n = await backend.neighbours();
      expect(n.single.isYou, isTrue);
    });
  });
}

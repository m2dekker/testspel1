import 'package:blackwake_isles/features/haven/domain/models.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _effect({
  String? produces,
  double rate = 0,
  int workers = 0,
  int crewCap = 0,
}) => {
  'produces': produces,
  'worker_rate': rate,
  'workers': workers,
  'crew_cap': crewCap,
  'growth': 0,
  'storage': 0,
};

Map<String, dynamic> _json({
  double timber = 100,
  double capacity = 1500,
  double crew = 10,
  double cap = 20,
  int assigned = 4,
}) => {
  'server_time': '2026-10-24T12:00:00Z',
  'plots': 8,
  'haven': {
    'id': 7,
    'name': 'Test Haven',
    'island': {
      'id': 1,
      'name': 'Blackwake Cay',
      'x': 12,
      'y': 18,
      'luxury': 'rum',
    },
  },
  'resources': {
    'timber': timber,
    'rum': 0,
    'spice': 0,
    'iron': 0,
    'silk': 0,
    'gold': 100,
  },
  'rates': {'timber': 360, 'luxury': 120, 'research': 30, 'capacity': capacity},
  'crew': {
    'amount': crew,
    'cap': cap,
    'growth': 12,
    'assigned': assigned,
    'gold_per_idle': 4,
  },
  'research_points': 50,
  'buildings': [
    {
      'id': 1,
      'type': 'captains_quarters',
      'slot': 0,
      'level': 1,
      'workers': 0,
      'upgrade_finishes_at': null,
      'max_level': 10,
      'effect': _effect(crewCap: 20),
      'next': {
        'level': 2,
        'cost': {'timber': 255, 'gold': 85},
        'seconds': 48,
        'effect': _effect(crewCap: 40),
      },
    },
  ],
  'catalogue': [
    {
      'id': 'lumber_camp',
      'name': 'Lumber Camp',
      'description': 'Fells palms.',
      'buildable': true,
      'cost': {'timber': 60, 'gold': 0},
      'seconds': 15,
      'effect': _effect(produces: 'timber', rate: 40, workers: 8),
    },
  ],
  'techs': [
    {
      'id': 'a',
      'tree': 'economy',
      'name': 'A',
      'description': 'First.',
      'cost': 20,
      'requires': null,
      'researched': true,
    },
    {
      'id': 'b',
      'tree': 'economy',
      'name': 'B',
      'description': 'Second.',
      'cost': 60,
      'requires': 'a',
      'researched': false,
    },
    {
      'id': 'c',
      'tree': 'economy',
      'name': 'C',
      'description': 'Third.',
      'cost': 120,
      'requires': 'b',
      'researched': false,
    },
  ],
};

void main() {
  final received = DateTime.utc(2026, 10, 24, 12);

  test('parses the haven_state JSON', () {
    final s = HavenState.fromJson(_json(), receivedAt: received);
    expect(s.name, 'Test Haven');
    expect(s.island.luxury, Resource.rum);
    expect(s.buildings.single.next!.cost.timber, 255);
    expect(s.buildings.single.next!.effect.crewCap, 40);
    expect(s.catalogue.single.effect.workers, 8);
    expect(s.crew.assigned, 4);
    expect(s.researchPoints, 50);
  });

  test('resources count up locally between server responses', () {
    final s = HavenState.fromJson(_json(), receivedAt: received);
    final tenMinutes = s.serverTime.add(const Duration(minutes: 10));

    expect(s.amountAt(Resource.timber, tenMinutes), closeTo(160, 0.001));
    expect(s.amountAt(Resource.rum, tenMinutes), closeTo(20, 0.001));
    expect(s.amountAt(Resource.spice, tenMinutes), 0);
    expect(s.researchAt(tenMinutes), closeTo(55, 0.001));
  });

  test('crew grows to the cap and gold follows idle crew exactly', () {
    final s = HavenState.fromJson(_json(), receivedAt: received);
    final oneHour = s.serverTime.add(const Duration(hours: 1));

    // 10 → 20 at 12/h takes 50 minutes.
    expect(s.crewAt(oneHour), 20);
    expect(s.idleCrew(oneHour), 16);
    // crew-hours: (10+20)/2 × 5/6 + 20 × 1/6 = 15.833; minus 4 worked = 11.833.
    expect(
      s.amountAt(Resource.gold, oneHour),
      closeTo(100 + 4 * 11.8333, 0.01),
    );
  });

  test('goods stop at storage capacity, gold does not', () {
    final s = HavenState.fromJson(_json(timber: 1490), receivedAt: received);
    final later = s.serverTime.add(const Duration(hours: 5));

    expect(s.amountAt(Resource.timber, later), 1500);
    expect(s.amountAt(Resource.gold, later), greaterThan(300));
  });

  test('techs unlock in order', () {
    final s = HavenState.fromJson(_json(), receivedAt: received);
    expect(s.isUnlocked(s.techById('a')), isFalse); // already researched
    expect(s.isUnlocked(s.techById('b')), isTrue);
    expect(s.isUnlocked(s.techById('c')), isFalse);
  });

  test('server time is estimated from the local clock', () {
    final s = HavenState.fromJson(
      _json(),
      receivedAt: received.add(const Duration(seconds: 5)),
    );
    final localNow = received.add(const Duration(seconds: 65));
    expect(s.serverNow(localNow), s.serverTime.add(const Duration(minutes: 1)));
  });
}

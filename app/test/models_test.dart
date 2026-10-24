import 'package:blackwake_isles/features/haven/domain/models.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _json({double timber = 100, double capacity = 1500}) => {
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
  'rates': {'timber': 360, 'luxury': 120, 'gold': 30, 'capacity': capacity},
  'buildings': [
    {
      'id': 1,
      'type': 'captains_quarters',
      'slot': 0,
      'level': 1,
      'upgrade_finishes_at': null,
      'max_level': 10,
      'next': {
        'level': 2,
        'cost': {'timber': 255, 'gold': 85},
        'seconds': 48,
        'rate': 60,
        'storage': 0,
      },
    },
  ],
  'catalogue': [
    {
      'id': 'lumber_camp',
      'name': 'Lumber Camp',
      'description': 'Fells palms.',
      'buildable': true,
      'produces': 'timber',
      'base_rate': 300,
      'storage_per_level': 0,
      'cost': {'timber': 60, 'gold': 0},
      'seconds': 15,
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
    expect(s.catalogue.single.cost.timber, 60);
  });

  test('resources count up locally between server responses', () {
    final s = HavenState.fromJson(_json(), receivedAt: received);
    final tenMinutes = s.serverTime.add(const Duration(minutes: 10));

    expect(
      s.amountAt(Resource.timber, tenMinutes),
      closeTo(160, 0.001),
    ); // 360/h
    expect(
      s.amountAt(Resource.rum, tenMinutes),
      closeTo(20, 0.001),
    ); // island luxury
    expect(s.amountAt(Resource.spice, tenMinutes), 0); // not produced here
    expect(s.amountAt(Resource.gold, tenMinutes), closeTo(105, 0.001));
  });

  test('goods stop at storage capacity, gold does not', () {
    final s = HavenState.fromJson(_json(timber: 1490), receivedAt: received);
    final later = s.serverTime.add(const Duration(hours: 5));

    expect(s.amountAt(Resource.timber, later), 1500);
    expect(s.amountAt(Resource.gold, later), closeTo(250, 0.001));
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

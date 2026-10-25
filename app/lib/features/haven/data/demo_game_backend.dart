import 'dart:convert';
import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

import '../domain/models.dart';
import 'game_backend.dart';

/// Offline demo: runs the game rules on the device and saves the haven in
/// local storage. Used when no Supabase project is configured (for example in
/// a quick preview).
///
/// KEEP IN SYNC with supabase/migrations/. The rules, numbers and error
/// messages here mirror the SQL functions one to one, [_stateJson] returns the
/// same JSON shape as `haven_state()`, and test/demo_game_backend_test.dart
/// mirrors the SQL tests.
class DemoGameBackend implements GameBackend {
  DemoGameBackend(this._prefs, {DateTime Function()? clock, Random? random})
    : _clock = clock ?? DateTime.now,
      _random = random ?? Random();

  final SharedPreferences _prefs;
  final DateTime Function() _clock;
  final Random _random;

  static const storageKey = 'blackwake_demo_haven_v1';

  /// Name used for the demo haven (set by the demo login).
  static const captainKey = 'blackwake_demo_captain';

  // Mirrors haven_plots(), base_storage(), base_crew_growth(), gold_per_idle_crew().
  static const _plots = 8;
  static const _baseStorage = 1500;
  static const _baseCrewGrowth = 12.0;
  static const _goldPerIdleCrew = 4.0;

  // Mirrors the building_types rows.
  static const _types = <_Type>[
    _Type(
      'captains_quarters',
      'Captain\'s Quarters',
      'The heart of your haven. Houses your crew. Crew without a job earn gold.',
      buildable: false,
      timber: 150,
      gold: 50,
      costGrowth: 1.7,
      seconds: 30,
      timeGrowth: 1.6,
      crewPerLevel: 20,
    ),
    _Type(
      'lumber_camp',
      'Lumber Camp',
      'Fells palms and hardwood. Every ship and building starts with timber.',
      timber: 60,
      seconds: 15,
      produces: 'timber',
      workerRate: 40,
      workersPerLevel: 8,
    ),
    _Type(
      'plantation',
      'Plantation',
      'Grows or mines this island\'s luxury good. Other islands will want it.',
      timber: 100,
      gold: 20,
      seconds: 20,
      produces: 'luxury',
      workerRate: 15,
      workersPerLevel: 6,
    ),
    _Type(
      'warehouse',
      'Warehouse',
      'Stores more goods. Anything past capacity rots on the dock.',
      timber: 80,
      seconds: 20,
      storage: 1500,
    ),
    _Type(
      'tavern',
      'Tavern',
      'Grog, songs and gossip. A lively tavern draws new crew to your haven faster.',
      timber: 120,
      gold: 40,
      seconds: 25,
      growthPerLevel: 12,
    ),
    _Type(
      'academy',
      'Academy',
      'Scholars study charts and ledgers here and produce research points.',
      timber: 150,
      gold: 50,
      seconds: 30,
      produces: 'research',
      workerRate: 10,
      workersPerLevel: 6,
    ),
  ];

  // Mirrors the techs rows.
  static const _techs = <_Tech>[
    _Tech(
      'sharpened_axes',
      'Sharpened Axes',
      'Lumberjacks fell trees 20% faster.',
      20,
      null,
      'timber_bonus',
      0.2,
    ),
    _Tech(
      'bonded_warehouses',
      'Bonded Warehouses',
      'Stack the crates higher: 50% more storage.',
      60,
      'sharpened_axes',
      'storage_bonus',
      0.5,
    ),
    _Tech(
      'plantation_overseers',
      'Plantation Overseers',
      'Plantations produce 20% more.',
      120,
      'bonded_warehouses',
      'luxury_bonus',
      0.2,
    ),
    _Tech(
      'ships_ledger',
      'Ship\'s Ledger',
      'Idle crew earn 50% more gold.',
      240,
      'plantation_overseers',
      'idle_gold_bonus',
      0.5,
    ),
  ];

  // A few islands from the seeded archipelago.
  static const _islands = [
    {'id': 1, 'name': 'Blackwake Cay', 'x': 12, 'y': 18, 'luxury': 'rum'},
    {'id': 2, 'name': 'Saltbone Key', 'x': 27, 'y': 9, 'luxury': 'spice'},
    {'id': 3, 'name': 'Hangman\'s Reef', 'x': 41, 'y': 22, 'luxury': 'iron'},
    {'id': 4, 'name': 'Isla de Seda', 'x': 58, 'y': 14, 'luxury': 'silk'},
  ];

  // ------------------------------------------------------------------ API

  @override
  Future<HavenState> startGame() async {
    var save = _load();
    if (save == null) {
      final captain = _prefs.getString(captainKey) ?? 'Captain';
      save = _Save(
        name: '$captain\'s Haven',
        island: Map<String, dynamic>.from(
          _islands[_random.nextInt(_islands.length)],
        ),
        resources: {
          'timber': 300,
          'rum': 0,
          'spice': 0,
          'iron': 0,
          'silk': 0,
          'gold': 100,
        },
        crew: 6,
        researchPoints: 0,
        techs: {},
        updatedAt: _clock(),
        buildings: [_B(id: 1, type: 'captains_quarters', slot: 0, level: 1)],
        nextId: 2,
      );
    }
    return _commit(save);
  }

  @override
  Future<HavenState> fetchHaven() async => _commit(_require());

  @override
  Future<HavenState> placeBuilding(String typeId, int slot) async {
    final save = _require();
    _settle(save);

    final type = _typeOrNull(typeId);
    if (type == null || !type.buildable) {
      throw GameException('That building can\'t be built.');
    }
    if (slot < 1 || slot >= _plots) {
      throw GameException('That plot doesn\'t exist.');
    }
    if (save.buildings.any((b) => b.slot == slot)) {
      throw GameException('That plot is already taken.');
    }
    if (save.buildings.any((b) => b.type == typeId)) {
      throw GameException('You already have a ${type.name}.');
    }
    _requireFreeQueue(save);
    _pay(save, type.cost(1));

    save.buildings.add(
      _B(
        id: save.nextId++,
        type: typeId,
        slot: slot,
        level: 0,
        finishesAt: _clock().add(Duration(seconds: type.buildSeconds(1))),
      ),
    );
    return _commit(save, settle: false);
  }

  @override
  Future<HavenState> upgradeBuilding(int buildingId) async {
    final save = _require();
    _settle(save);

    final b = save.buildings.where((b) => b.id == buildingId).firstOrNull;
    if (b == null) throw GameException('That building isn\'t in your haven.');
    final type = _typeOrNull(b.type)!;
    if (b.finishesAt != null) {
      throw GameException('The ${type.name} is already being built.');
    }
    if (b.level >= type.maxLevel) {
      throw GameException('The ${type.name} is already at the highest level.');
    }
    _requireFreeQueue(save);
    _pay(save, type.cost(b.level + 1));

    b.finishesAt = _clock().add(
      Duration(seconds: type.buildSeconds(b.level + 1)),
    );
    return _commit(save, settle: false);
  }

  /// Mirrors assign_workers().
  @override
  Future<HavenState> assignWorkers(int buildingId, int workers) async {
    final save = _require();
    _settle(save);

    final b = save.buildings.where((b) => b.id == buildingId).firstOrNull;
    if (b == null) throw GameException('That building isn\'t in your haven.');
    final type = _typeOrNull(b.type)!;
    if (type.workersPerLevel == 0) {
      throw GameException('Nobody can work at the ${type.name}.');
    }
    if (b.level == 0) {
      throw GameException('The ${type.name} isn\'t finished yet.');
    }
    final jobs = type.workersPerLevel * b.level;
    if (workers < 0 || workers > jobs) {
      throw GameException('The ${type.name} has jobs for $jobs crew.');
    }
    final others = save.buildings
        .where((o) => o.id != buildingId)
        .fold<int>(0, (sum, o) => sum + o.workers);
    if (others + workers > save.crew.floor()) {
      throw GameException(
        'Not enough crew (${max(0, save.crew.floor() - others)} free).',
      );
    }

    b.workers = workers;
    return _commit(save, settle: false);
  }

  /// Mirrors research_tech().
  @override
  Future<HavenState> research(String techId) async {
    final save = _require();
    _settle(save);

    final t = _techs.where((t) => t.id == techId).firstOrNull;
    if (t == null) throw GameException('Unknown research.');
    if (save.techs.contains(techId)) {
      throw GameException('You already know ${t.name}.');
    }
    if (t.requires != null && !save.techs.contains(t.requires)) {
      final req = _techs.firstWhere((r) => r.id == t.requires);
      throw GameException('Research ${req.name} first.');
    }
    if (save.researchPoints < t.cost) {
      throw GameException(
        'Not enough research points (need ${t.cost}, have ${save.researchPoints.floor()}).',
      );
    }

    save.researchPoints -= t.cost;
    save.techs.add(techId);
    return _commit(save, settle: false);
  }

  /// In the offline demo you are alone on your island.
  @override
  Future<List<Neighbour>> neighbours() async {
    final save = _require();
    return [
      Neighbour(
        haven: save.name,
        captain: _prefs.getString(captainKey) ?? 'Captain',
        slot: 0,
        isYou: true,
      ),
    ];
  }

  // ---------------------------------------------------------------- rules

  /// Mirrors settle_haven(): production in segments, completing each
  /// construction at the moment it finished.
  void _settle(_Save s) {
    final now = _clock();
    var cursor = s.updatedAt;
    while (true) {
      final due =
          s.buildings
              .where((b) => b.finishesAt != null && !b.finishesAt!.isAfter(now))
              .toList()
            ..sort((a, b) => a.finishesAt!.compareTo(b.finishesAt!));
      if (due.isEmpty) break;
      final b = due.first;
      final end = b.finishesAt!.isAfter(cursor) ? b.finishesAt! : cursor;
      _produce(s, cursor, end);
      cursor = end;
      b.level += 1;
      b.finishesAt = null;
    }
    _produce(s, cursor, now);
    s.updatedAt = now;
  }

  /// Mirrors apply_production().
  void _produce(_Save s, DateTime from, DateTime to) {
    final hours = to.difference(from).inMicroseconds / 3600e6;
    if (hours <= 0) return;
    final r = _rates(s);
    final lux = s.island['luxury'] as String;

    // Crew grows linearly until it reaches the cap.
    final crewNow = s.crew;
    double crewEnd, crewHours;
    if (crewNow >= r.crewCap || r.crewGrowth <= 0) {
      crewEnd = crewNow;
      crewHours = crewNow * hours;
    } else {
      final tCap = (r.crewCap - crewNow) / r.crewGrowth;
      if (hours <= tCap) {
        crewEnd = crewNow + r.crewGrowth * hours;
        crewHours = (crewNow + crewEnd) / 2 * hours;
      } else {
        crewEnd = r.crewCap;
        crewHours =
            (crewNow + r.crewCap) / 2 * tCap + r.crewCap * (hours - tCap);
      }
    }

    double fill(double cur, double add) => max(cur, min(r.capacity, cur + add));
    s.resources['timber'] = fill(s.resources['timber']!, r.timber * hours);
    s.resources[lux] = fill(s.resources[lux]!, r.luxury * hours);
    s.researchPoints += r.research * hours;
    s.resources['gold'] =
        s.resources['gold']! +
        r.goldPerIdle * max(0, crewHours - r.assigned * hours);
    s.crew = crewEnd;
  }

  double _bonus(_Save s, String effect) => _techs
      .where((t) => t.effect == effect && s.techs.contains(t.id))
      .fold(0.0, (sum, t) => sum + t.value);

  /// Mirrors haven_rates().
  _Rates _rates(_Save s) {
    var timber = 0.0, luxury = 0.0, research = 0.0;
    var crewCap = 0.0, crewGrowth = _baseCrewGrowth;
    var assigned = 0, storage = _baseStorage.toDouble();
    for (final b in s.buildings.where((b) => b.level > 0)) {
      final t = _typeOrNull(b.type)!;
      final output = b.workers * t.workerRate;
      switch (t.produces) {
        case 'timber':
          timber += output;
        case 'luxury':
          luxury += output;
        case 'research':
          research += output;
      }
      crewCap += t.crewPerLevel * b.level;
      crewGrowth += t.growthPerLevel * b.level;
      assigned += b.workers;
      storage += t.storage * b.level;
    }
    return _Rates(
      timber: timber * (1 + _bonus(s, 'timber_bonus')),
      luxury: luxury * (1 + _bonus(s, 'luxury_bonus')),
      research: research,
      goldPerIdle: _goldPerIdleCrew * (1 + _bonus(s, 'idle_gold_bonus')),
      crewCap: crewCap,
      crewGrowth: crewGrowth,
      assigned: assigned,
      capacity: storage * (1 + _bonus(s, 'storage_bonus')),
    );
  }

  void _requireFreeQueue(_Save s) {
    if (s.buildings.any((b) => b.finishesAt != null)) {
      throw GameException(
        'Your builders are busy. Wait for the current construction to finish.',
      );
    }
  }

  void _pay(_Save s, Cost cost) {
    final timber = s.resources['timber']!, gold = s.resources['gold']!;
    if (timber < cost.timber) {
      throw GameException(
        'Not enough timber (need ${cost.timber}, have ${timber.floor()}).',
      );
    }
    if (gold < cost.gold) {
      throw GameException(
        'Not enough gold (need ${cost.gold}, have ${gold.floor()}).',
      );
    }
    s.resources['timber'] = timber - cost.timber;
    s.resources['gold'] = gold - cost.gold;
  }

  // -------------------------------------------------------------- storage

  _Type? _typeOrNull(String id) => _types.where((t) => t.id == id).firstOrNull;

  _Save? _load() {
    final raw = _prefs.getString(storageKey);
    if (raw == null) return null;
    return _Save.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  _Save _require() {
    final save = _load();
    if (save == null) throw GameException('You don\'t have a haven yet.');
    return save;
  }

  Future<HavenState> _commit(_Save save, {bool settle = true}) async {
    if (settle) _settle(save);
    await _prefs.setString(storageKey, jsonEncode(save.toJson()));
    return HavenState.fromJson(_stateJson(save));
  }

  /// Mirrors haven_state().
  Map<String, dynamic> _stateJson(_Save s) {
    final r = _rates(s);
    Map<String, dynamic> cost(Cost c) => {'timber': c.timber, 'gold': c.gold};
    return {
      'server_time': _clock().toUtc().toIso8601String(),
      'plots': _plots,
      'haven': {'id': 1, 'name': s.name, 'island': s.island},
      'resources': s.resources,
      'rates': {
        'timber': r.timber,
        'luxury': r.luxury,
        'research': r.research,
        'capacity': r.capacity,
      },
      'crew': {
        'amount': s.crew,
        'cap': r.crewCap,
        'growth': r.crewGrowth,
        'assigned': r.assigned,
        'gold_per_idle': r.goldPerIdle,
      },
      'research_points': s.researchPoints,
      'buildings': [
        for (final b in [
          ...s.buildings,
        ]..sort((a, b) => a.slot.compareTo(b.slot)))
          () {
            final t = _typeOrNull(b.type)!;
            return {
              'id': b.id,
              'type': b.type,
              'slot': b.slot,
              'level': b.level,
              'workers': b.workers,
              'upgrade_finishes_at': b.finishesAt?.toUtc().toIso8601String(),
              'max_level': t.maxLevel,
              'effect': t.effect(b.level),
              'next': b.level < t.maxLevel
                  ? {
                      'level': b.level + 1,
                      'cost': cost(t.cost(b.level + 1)),
                      'seconds': t.buildSeconds(b.level + 1),
                      'effect': t.effect(b.level + 1),
                    }
                  : null,
            };
          }(),
      ],
      'catalogue': [
        for (final t in _types)
          {
            'id': t.id,
            'name': t.name,
            'description': t.description,
            'buildable': t.buildable,
            'cost': cost(t.cost(1)),
            'seconds': t.buildSeconds(1),
            'effect': t.effect(1),
          },
      ],
      'techs': [
        for (final t in _techs)
          {
            'id': t.id,
            'tree': 'economy',
            'name': t.name,
            'description': t.description,
            'cost': t.cost,
            'requires': t.requires,
            'researched': s.techs.contains(t.id),
          },
      ],
    };
  }
}

// ------------------------------------------------------------------ helpers

class _Type {
  const _Type(
    this.id,
    this.name,
    this.description, {
    this.buildable = true,
    required this.timber,
    this.gold = 0,
    this.costGrowth = 1.6,
    required this.seconds,
    this.timeGrowth = 1.5,
    this.produces,
    this.workerRate = 0,
    this.workersPerLevel = 0,
    this.crewPerLevel = 0,
    this.growthPerLevel = 0,
    this.storage = 0,
  });

  final String id, name, description;
  final bool buildable;
  final int timber, gold, seconds, storage, workersPerLevel, crewPerLevel;
  final double costGrowth, timeGrowth, workerRate, growthPerLevel;
  final String? produces;
  int get maxLevel => 10;

  // The small epsilon keeps 60 × 1.6 = 96.000000000001 from rounding up to 97,
  // matching Postgres' exact numeric math.
  static int _ceil(num v) => (v - 1e-6).ceil();

  /// Mirrors building_cost().
  Cost cost(int level) => Cost(
    timber: _ceil(timber * pow(costGrowth, level - 1)),
    gold: _ceil(gold * pow(costGrowth, level - 1)),
  );

  /// Mirrors build_seconds().
  int buildSeconds(int level) => _ceil(seconds * pow(timeGrowth, level - 1));

  /// Mirrors building_effect().
  Map<String, dynamic> effect(int level) => {
    'produces': produces,
    'worker_rate': workerRate,
    'workers': workersPerLevel * level,
    'crew_cap': crewPerLevel * level,
    'growth': growthPerLevel * level,
    'storage': storage * level,
  };
}

class _Tech {
  const _Tech(
    this.id,
    this.name,
    this.description,
    this.cost,
    this.requires,
    this.effect,
    this.value,
  );

  final String id, name, description, effect;
  final int cost;
  final String? requires;
  final double value;
}

class _Rates {
  _Rates({
    required this.timber,
    required this.luxury,
    required this.research,
    required this.goldPerIdle,
    required this.crewCap,
    required this.crewGrowth,
    required this.assigned,
    required this.capacity,
  });

  final double timber, luxury, research, goldPerIdle, crewCap, crewGrowth;
  final double capacity;
  final int assigned;
}

class _B {
  _B({
    required this.id,
    required this.type,
    required this.slot,
    required this.level,
    this.workers = 0,
    this.finishesAt,
  });

  final int id;
  final String type;
  final int slot;
  int level;
  int workers;
  DateTime? finishesAt;

  Map<String, dynamic> toJson() => {
    'id': id,
    'type': type,
    'slot': slot,
    'level': level,
    'workers': workers,
    'finishesAt': finishesAt?.toIso8601String(),
  };

  factory _B.fromJson(Map<String, dynamic> j) => _B(
    id: j['id'] as int,
    type: j['type'] as String,
    slot: j['slot'] as int,
    level: j['level'] as int,
    workers: (j['workers'] as int?) ?? 0, // saves from Sprint 1 have no workers
    finishesAt: j['finishesAt'] == null
        ? null
        : DateTime.parse(j['finishesAt'] as String),
  );
}

class _Save {
  _Save({
    required this.name,
    required this.island,
    required this.resources,
    required this.crew,
    required this.researchPoints,
    required this.techs,
    required this.updatedAt,
    required this.buildings,
    required this.nextId,
  });

  final String name;
  final Map<String, dynamic> island;
  final Map<String, double> resources;
  double crew;
  double researchPoints;
  final Set<String> techs;
  DateTime updatedAt;
  final List<_B> buildings;
  int nextId;

  Map<String, dynamic> toJson() => {
    'name': name,
    'island': island,
    'resources': resources,
    'crew': crew,
    'researchPoints': researchPoints,
    'techs': techs.toList(),
    'updatedAt': updatedAt.toIso8601String(),
    'buildings': [for (final b in buildings) b.toJson()],
    'nextId': nextId,
  };

  // Fields added in Sprint 2 fall back to the starting values for old saves.
  factory _Save.fromJson(Map<String, dynamic> j) => _Save(
    name: j['name'] as String,
    island: Map<String, dynamic>.from(j['island'] as Map),
    resources: {
      for (final e in (j['resources'] as Map).entries)
        e.key as String: (e.value as num).toDouble(),
    },
    crew: (j['crew'] as num?)?.toDouble() ?? 6,
    researchPoints: (j['researchPoints'] as num?)?.toDouble() ?? 0,
    techs: {for (final t in (j['techs'] as List?) ?? const []) t as String},
    updatedAt: DateTime.parse(j['updatedAt'] as String),
    buildings: [
      for (final b in j['buildings'] as List)
        _B.fromJson(Map<String, dynamic>.from(b as Map)),
    ],
    nextId: j['nextId'] as int,
  );
}

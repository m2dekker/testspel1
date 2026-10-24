// Plain data classes for the haven screen.
//
// They are parsed from the JSON returned by the `haven_state()` database
// function (see supabase/migrations). The demo backend produces the same JSON,
// so both backends share this parsing code.

enum Resource { timber, rum, spice, iron, silk, gold }

Resource resourceFromName(String name) =>
    Resource.values.firstWhere((r) => r.name == name);

/// A price in timber and gold.
class Cost {
  const Cost({required this.timber, required this.gold});

  final int timber;
  final int gold;

  factory Cost.fromJson(Map<String, dynamic> json) => Cost(
    timber: (json['timber'] as num).toInt(),
    gold: (json['gold'] as num).toInt(),
  );
}

/// A building from the catalogue (what can be built).
class BuildingType {
  const BuildingType({
    required this.id,
    required this.name,
    required this.description,
    required this.buildable,
    required this.produces,
    required this.baseRate,
    required this.storagePerLevel,
    required this.cost,
    required this.seconds,
  });

  final String id;
  final String name;
  final String description;

  /// False for buildings every haven starts with (Captain's Quarters).
  final bool buildable;

  /// 'timber', 'luxury', 'gold' or null.
  final String? produces;

  /// Units per hour per level.
  final double baseRate;
  final int storagePerLevel;

  /// Cost and build time of level 1.
  final Cost cost;
  final int seconds;

  factory BuildingType.fromJson(Map<String, dynamic> json) => BuildingType(
    id: json['id'] as String,
    name: json['name'] as String,
    description: json['description'] as String,
    buildable: json['buildable'] as bool,
    produces: json['produces'] as String?,
    baseRate: (json['base_rate'] as num).toDouble(),
    storagePerLevel: (json['storage_per_level'] as num).toInt(),
    cost: Cost.fromJson(json['cost'] as Map<String, dynamic>),
    seconds: (json['seconds'] as num).toInt(),
  );
}

/// What the next level of a building costs and gives.
class NextLevel {
  const NextLevel({
    required this.level,
    required this.cost,
    required this.seconds,
    required this.rate,
    required this.storage,
  });

  final int level;
  final Cost cost;
  final int seconds;
  final double rate;
  final int storage;

  factory NextLevel.fromJson(Map<String, dynamic> json) => NextLevel(
    level: (json['level'] as num).toInt(),
    cost: Cost.fromJson(json['cost'] as Map<String, dynamic>),
    seconds: (json['seconds'] as num).toInt(),
    rate: (json['rate'] as num).toDouble(),
    storage: (json['storage'] as num).toInt(),
  );
}

/// A building standing (or being built) in the haven.
class Building {
  const Building({
    required this.id,
    required this.type,
    required this.slot,
    required this.level,
    required this.finishesAt,
    required this.maxLevel,
    required this.next,
  });

  final int id;
  final String type;
  final int slot;

  /// 0 while the first construction is still running.
  final int level;

  /// When the running construction finishes (server time), or null.
  final DateTime? finishesAt;
  final int maxLevel;
  final NextLevel? next;

  bool get isConstructing => finishesAt != null;

  factory Building.fromJson(Map<String, dynamic> json) => Building(
    id: (json['id'] as num).toInt(),
    type: json['type'] as String,
    slot: (json['slot'] as num).toInt(),
    level: (json['level'] as num).toInt(),
    finishesAt: json['upgrade_finishes_at'] == null
        ? null
        : DateTime.parse(json['upgrade_finishes_at'] as String),
    maxLevel: (json['max_level'] as num).toInt(),
    next: json['next'] == null
        ? null
        : NextLevel.fromJson(json['next'] as Map<String, dynamic>),
  );
}

class Island {
  const Island({
    required this.id,
    required this.name,
    required this.x,
    required this.y,
    required this.luxury,
  });

  final int id;
  final String name;
  final int x;
  final int y;

  /// The luxury good this island's plantation produces.
  final Resource luxury;

  factory Island.fromJson(Map<String, dynamic> json) => Island(
    id: (json['id'] as num).toInt(),
    name: json['name'] as String,
    x: (json['x'] as num).toInt(),
    y: (json['y'] as num).toInt(),
    luxury: resourceFromName(json['luxury'] as String),
  );
}

/// Everything the haven screen shows, as of one server response.
class HavenState {
  HavenState({
    required this.serverTime,
    required this.receivedAt,
    required this.plots,
    required this.havenId,
    required this.name,
    required this.island,
    required this.resources,
    required this.timberRate,
    required this.luxuryRate,
    required this.goldRate,
    required this.capacity,
    required this.buildings,
    required this.catalogue,
  });

  /// Server clock when this state was produced, and local clock when it arrived.
  final DateTime serverTime;
  final DateTime receivedAt;

  final int plots;
  final int havenId;
  final String name;
  final Island island;

  /// Resource amounts at [serverTime].
  final Map<Resource, double> resources;

  /// Production per hour.
  final double timberRate;
  final double luxuryRate;
  final double goldRate;

  /// Storage cap for every resource except gold.
  final double capacity;

  final List<Building> buildings;
  final List<BuildingType> catalogue;

  factory HavenState.fromJson(
    Map<String, dynamic> json, {
    DateTime? receivedAt,
  }) {
    final haven = json['haven'] as Map<String, dynamic>;
    final res = json['resources'] as Map<String, dynamic>;
    final rates = json['rates'] as Map<String, dynamic>;
    return HavenState(
      serverTime: DateTime.parse(json['server_time'] as String),
      receivedAt: receivedAt ?? DateTime.now(),
      plots: (json['plots'] as num).toInt(),
      havenId: (haven['id'] as num).toInt(),
      name: haven['name'] as String,
      island: Island.fromJson(haven['island'] as Map<String, dynamic>),
      resources: {
        for (final r in Resource.values) r: (res[r.name] as num).toDouble(),
      },
      timberRate: (rates['timber'] as num).toDouble(),
      luxuryRate: (rates['luxury'] as num).toDouble(),
      goldRate: (rates['gold'] as num).toDouble(),
      capacity: (rates['capacity'] as num).toDouble(),
      buildings: [
        for (final b in json['buildings'] as List)
          Building.fromJson(b as Map<String, dynamic>),
      ],
      catalogue: [
        for (final t in json['catalogue'] as List)
          BuildingType.fromJson(t as Map<String, dynamic>),
      ],
    );
  }

  /// Current server time, estimated from the local clock.
  DateTime serverNow([DateTime? localNow]) =>
      serverTime.add((localNow ?? DateTime.now()).difference(receivedAt));

  /// Production per hour of one resource.
  double ratePerHour(Resource r) => switch (r) {
    Resource.timber => timberRate,
    Resource.gold => goldRate,
    _ => r == island.luxury ? luxuryRate : 0,
  };

  /// Resource amount at a moment in server time (local interpolation between
  /// server responses). Goods stop at [capacity]; gold has no cap.
  double amountAt(Resource r, DateTime at) {
    final start = resources[r]!;
    final hours = at.difference(serverTime).inMilliseconds / 3600000.0;
    if (hours <= 0) return start;
    final grown = start + ratePerHour(r) * hours;
    if (r == Resource.gold) return grown;
    if (start >= capacity) return start;
    return grown > capacity ? capacity : grown;
  }

  bool canAfford(Cost cost, DateTime at) =>
      amountAt(Resource.timber, at) >= cost.timber &&
      amountAt(Resource.gold, at) >= cost.gold;

  Building? buildingAt(int slot) {
    for (final b in buildings) {
      if (b.slot == slot) return b;
    }
    return null;
  }

  BuildingType typeOf(String id) => catalogue.firstWhere((t) => t.id == id);

  bool hasBuilt(String typeId) => buildings.any((b) => b.type == typeId);

  /// The construction currently running (one build queue).
  Building? get constructing {
    for (final b in buildings) {
      if (b.isConstructing) return b;
    }
    return null;
  }
}

/// A rule the server refused, with a message for the player.
class GameException implements Exception {
  GameException(this.message);

  final String message;

  @override
  String toString() => message;
}

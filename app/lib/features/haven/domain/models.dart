// Plain data classes for the haven screen.
//
// They are parsed from the JSON returned by the `haven_state()` database
// function (see supabase/migrations). The demo backend produces the same JSON,
// so both backends share this parsing code.

enum Resource { timber, rum, spice, iron, silk, gold }

Resource resourceFromName(String name) =>
    Resource.values.firstWhere((r) => r.name == name);

double _d(Object? v) => (v as num).toDouble();
int _i(Object? v) => (v as num).toInt();

/// A price in timber and gold.
class Cost {
  const Cost({required this.timber, required this.gold});

  final int timber;
  final int gold;

  factory Cost.fromJson(Map<String, dynamic> json) =>
      Cost(timber: _i(json['timber']), gold: _i(json['gold']));
}

/// What one level of a building gives. Only the relevant fields are non-zero.
class BuildingEffect {
  const BuildingEffect({
    required this.produces,
    required this.workerRate,
    required this.workers,
    required this.crewCap,
    required this.growth,
    required this.storage,
  });

  /// 'timber', 'luxury', 'research' or null.
  final String? produces;

  /// Output per worker per hour.
  final double workerRate;

  /// Number of jobs.
  final int workers;

  /// Crew housed.
  final int crewCap;

  /// Extra crew arriving per hour.
  final double growth;

  /// Extra storage per good.
  final int storage;

  factory BuildingEffect.fromJson(Map<String, dynamic> json) => BuildingEffect(
    produces: json['produces'] as String?,
    workerRate: _d(json['worker_rate']),
    workers: _i(json['workers']),
    crewCap: _i(json['crew_cap']),
    growth: _d(json['growth']),
    storage: _i(json['storage']),
  );
}

/// A building from the catalogue (what can be built).
class BuildingType {
  const BuildingType({
    required this.id,
    required this.name,
    required this.description,
    required this.buildable,
    required this.cost,
    required this.seconds,
    required this.effect,
  });

  final String id;
  final String name;
  final String description;

  /// False for buildings every haven starts with (Captain's Quarters).
  final bool buildable;

  /// Cost, build time and effect of level 1.
  final Cost cost;
  final int seconds;
  final BuildingEffect effect;

  factory BuildingType.fromJson(Map<String, dynamic> json) => BuildingType(
    id: json['id'] as String,
    name: json['name'] as String,
    description: json['description'] as String,
    buildable: json['buildable'] as bool,
    cost: Cost.fromJson(json['cost'] as Map<String, dynamic>),
    seconds: _i(json['seconds']),
    effect: BuildingEffect.fromJson(json['effect'] as Map<String, dynamic>),
  );
}

/// What the next level of a building costs and gives.
class NextLevel {
  const NextLevel({
    required this.level,
    required this.cost,
    required this.seconds,
    required this.effect,
  });

  final int level;
  final Cost cost;
  final int seconds;
  final BuildingEffect effect;

  factory NextLevel.fromJson(Map<String, dynamic> json) => NextLevel(
    level: _i(json['level']),
    cost: Cost.fromJson(json['cost'] as Map<String, dynamic>),
    seconds: _i(json['seconds']),
    effect: BuildingEffect.fromJson(json['effect'] as Map<String, dynamic>),
  );
}

/// A building standing (or being built) in the haven.
class Building {
  const Building({
    required this.id,
    required this.type,
    required this.slot,
    required this.level,
    required this.workers,
    required this.finishesAt,
    required this.maxLevel,
    required this.effect,
    required this.next,
  });

  final int id;
  final String type;
  final int slot;

  /// 0 while the first construction is still running.
  final int level;

  /// Crew working here.
  final int workers;

  /// When the running construction finishes (server time), or null.
  final DateTime? finishesAt;
  final int maxLevel;

  /// What the current level gives.
  final BuildingEffect effect;
  final NextLevel? next;

  bool get isConstructing => finishesAt != null;

  /// True if crew can be put to work here.
  bool get hasJobs => effect.workers > 0;

  factory Building.fromJson(Map<String, dynamic> json) => Building(
    id: _i(json['id']),
    type: json['type'] as String,
    slot: _i(json['slot']),
    level: _i(json['level']),
    workers: _i(json['workers']),
    finishesAt: json['upgrade_finishes_at'] == null
        ? null
        : DateTime.parse(json['upgrade_finishes_at'] as String),
    maxLevel: _i(json['max_level']),
    effect: BuildingEffect.fromJson(json['effect'] as Map<String, dynamic>),
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
    id: _i(json['id']),
    name: json['name'] as String,
    x: _i(json['x']),
    y: _i(json['y']),
    luxury: resourceFromName(json['luxury'] as String),
  );
}

/// The haven's crew at one moment.
class Crew {
  const Crew({
    required this.amount,
    required this.cap,
    required this.growth,
    required this.assigned,
    required this.goldPerIdle,
  });

  /// Total crew (fractional: someone is always on the way).
  final double amount;

  /// Housing from the Captain's Quarters.
  final double cap;

  /// Crew arriving per hour while below the cap.
  final double growth;

  /// Crew with a job.
  final int assigned;

  /// Gold per hour from each idle crew member.
  final double goldPerIdle;

  factory Crew.fromJson(Map<String, dynamic> json) => Crew(
    amount: _d(json['amount']),
    cap: _d(json['cap']),
    growth: _d(json['growth']),
    assigned: _i(json['assigned']),
    goldPerIdle: _d(json['gold_per_idle']),
  );
}

/// A research topic.
class Tech {
  const Tech({
    required this.id,
    required this.tree,
    required this.name,
    required this.description,
    required this.cost,
    required this.requires,
    required this.researched,
  });

  final String id;
  final String tree;
  final String name;
  final String description;
  final int cost;
  final String? requires;
  final bool researched;

  factory Tech.fromJson(Map<String, dynamic> json) => Tech(
    id: json['id'] as String,
    tree: json['tree'] as String,
    name: json['name'] as String,
    description: json['description'] as String,
    cost: _i(json['cost']),
    requires: json['requires'] as String?,
    researched: json['researched'] as bool,
  );
}

/// Another haven on the same island.
class Neighbour {
  const Neighbour({
    required this.haven,
    required this.captain,
    required this.slot,
    required this.isYou,
  });

  final String haven;
  final String captain;
  final int slot;
  final bool isYou;

  factory Neighbour.fromJson(Map<String, dynamic> json) => Neighbour(
    haven: json['haven'] as String,
    captain: json['captain'] as String,
    slot: _i(json['slot']),
    isYou: json['is_you'] as bool,
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
    required this.researchRate,
    required this.capacity,
    required this.crew,
    required this.researchPoints,
    required this.buildings,
    required this.catalogue,
    required this.techs,
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

  /// Production per hour (research bonuses already included).
  final double timberRate;
  final double luxuryRate;
  final double researchRate;

  /// Storage cap for every resource except gold.
  final double capacity;

  final Crew crew;
  final double researchPoints;

  final List<Building> buildings;
  final List<BuildingType> catalogue;
  final List<Tech> techs;

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
      plots: _i(json['plots']),
      havenId: _i(haven['id']),
      name: haven['name'] as String,
      island: Island.fromJson(haven['island'] as Map<String, dynamic>),
      resources: {for (final r in Resource.values) r: _d(res[r.name])},
      timberRate: _d(rates['timber']),
      luxuryRate: _d(rates['luxury']),
      researchRate: _d(rates['research']),
      capacity: _d(rates['capacity']),
      crew: Crew.fromJson(json['crew'] as Map<String, dynamic>),
      researchPoints: _d(json['research_points']),
      buildings: [
        for (final b in json['buildings'] as List)
          Building.fromJson(b as Map<String, dynamic>),
      ],
      catalogue: [
        for (final t in json['catalogue'] as List)
          BuildingType.fromJson(t as Map<String, dynamic>),
      ],
      techs: [
        for (final t in json['techs'] as List)
          Tech.fromJson(t as Map<String, dynamic>),
      ],
    );
  }

  /// Current server time, estimated from the local clock.
  DateTime serverNow([DateTime? localNow]) =>
      serverTime.add((localNow ?? DateTime.now()).difference(receivedAt));

  double _hoursSince(DateTime at) {
    final h = at.difference(serverTime).inMilliseconds / 3600000.0;
    return h > 0 ? h : 0;
  }

  // ---- crew ----

  /// Crew at a moment: grows linearly until the cap (like the server).
  double crewAt(DateTime at) {
    final c = crew;
    if (c.amount >= c.cap) return c.amount;
    final grown = c.amount + c.growth * _hoursSince(at);
    return grown > c.cap ? c.cap : grown;
  }

  /// Whole crew members without a job right now.
  int idleCrew(DateTime at) {
    final idle = crewAt(at).floor() - crew.assigned;
    return idle < 0 ? 0 : idle;
  }

  /// Integral of crew over time since [serverTime] (crew × hours), matching
  /// the server's apply_production().
  double _crewHours(double hours) {
    final c = crew;
    if (c.amount >= c.cap || c.growth <= 0) return c.amount * hours;
    final tCap = (c.cap - c.amount) / c.growth;
    if (hours <= tCap) {
      return (c.amount + (c.amount + c.growth * hours)) / 2 * hours;
    }
    return (c.amount + c.cap) / 2 * tCap + c.cap * (hours - tCap);
  }

  // ---- resources ----

  /// Production per hour of one resource right now.
  double ratePerHour(Resource r, [DateTime? at]) => switch (r) {
    Resource.timber => timberRate,
    Resource.gold =>
      crew.goldPerIdle *
          ((at == null ? crew.amount : crewAt(at)) - crew.assigned).clamp(
            0,
            double.infinity,
          ),
    _ => r == island.luxury ? luxuryRate : 0,
  };

  /// Resource amount at a moment in server time (local interpolation between
  /// server responses). Goods stop at [capacity]; gold has no cap.
  double amountAt(Resource r, DateTime at) {
    final start = resources[r]!;
    final hours = _hoursSince(at);
    if (hours == 0) return start;
    if (r == Resource.gold) {
      final idleHours = _crewHours(hours) - crew.assigned * hours;
      return start + crew.goldPerIdle * (idleHours > 0 ? idleHours : 0);
    }
    final grown = start + ratePerHour(r) * hours;
    if (start >= capacity) return start;
    return grown > capacity ? capacity : grown;
  }

  double researchAt(DateTime at) =>
      researchPoints + researchRate * _hoursSince(at);

  bool canAfford(Cost cost, DateTime at) =>
      amountAt(Resource.timber, at) >= cost.timber &&
      amountAt(Resource.gold, at) >= cost.gold;

  // ---- buildings ----

  Building? buildingAt(int slot) {
    for (final b in buildings) {
      if (b.slot == slot) return b;
    }
    return null;
  }

  Building? buildingOfType(String typeId) {
    for (final b in buildings) {
      if (b.type == typeId) return b;
    }
    return null;
  }

  BuildingType typeOf(String id) => catalogue.firstWhere((t) => t.id == id);

  bool hasBuilt(String typeId) => buildingOfType(typeId) != null;

  /// The construction currently running (one build queue).
  Building? get constructing {
    for (final b in buildings) {
      if (b.isConstructing) return b;
    }
    return null;
  }

  // ---- research ----

  Tech techById(String id) => techs.firstWhere((t) => t.id == id);

  /// Researchable now (prerequisite done), ignoring points.
  bool isUnlocked(Tech t) =>
      !t.researched && (t.requires == null || techById(t.requires!).researched);
}

/// A rule the server refused, with a message for the player.
class GameException implements Exception {
  GameException(this.message);

  final String message;

  @override
  String toString() => message;
}

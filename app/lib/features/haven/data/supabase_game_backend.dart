import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/models.dart';
import 'game_backend.dart';

/// Talks to the game rules in Postgres (supabase/migrations) through RPCs.
class SupabaseGameBackend implements GameBackend {
  SupabaseGameBackend(this._client);

  final SupabaseClient _client;

  Future<dynamic> _rpc(String fn, [Map<String, dynamic>? params]) async {
    try {
      return await _client.rpc(fn, params: params);
    } on PostgrestException catch (e) {
      // Rule violations come back as readable messages from `raise exception`.
      throw GameException(e.message);
    }
  }

  Future<HavenState> _state(String fn, [Map<String, dynamic>? params]) async {
    final json = await _rpc(fn, params);
    return HavenState.fromJson(Map<String, dynamic>.from(json as Map));
  }

  @override
  Future<HavenState> startGame() => _state('start_game');

  @override
  Future<HavenState> fetchHaven() => _state('get_my_haven');

  @override
  Future<HavenState> placeBuilding(String typeId, int slot) =>
      _state('place_building', {'p_type': typeId, 'p_slot': slot});

  @override
  Future<HavenState> upgradeBuilding(int buildingId) =>
      _state('upgrade_building', {'p_building': buildingId});

  @override
  Future<HavenState> assignWorkers(int buildingId, int workers) => _state(
    'assign_workers',
    {'p_building': buildingId, 'p_workers': workers},
  );

  @override
  Future<HavenState> research(String techId) =>
      _state('research_tech', {'p_tech': techId});

  @override
  Future<List<Neighbour>> neighbours() async {
    final json = await _rpc('island_neighbours') as List;
    return [
      for (final n in json)
        Neighbour.fromJson(Map<String, dynamic>.from(n as Map)),
    ];
  }
}

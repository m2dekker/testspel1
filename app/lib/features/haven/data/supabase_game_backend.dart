import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/models.dart';
import 'game_backend.dart';

/// Talks to the game rules in Postgres (supabase/migrations) through RPCs.
class SupabaseGameBackend implements GameBackend {
  SupabaseGameBackend(this._client);

  final SupabaseClient _client;

  Future<HavenState> _call(String fn, [Map<String, dynamic>? params]) async {
    try {
      final json = await _client.rpc(fn, params: params);
      return HavenState.fromJson(Map<String, dynamic>.from(json as Map));
    } on PostgrestException catch (e) {
      // Rule violations come back as readable messages from `raise exception`.
      throw GameException(e.message);
    }
  }

  @override
  Future<HavenState> startGame() => _call('start_game');

  @override
  Future<HavenState> fetchHaven() => _call('get_my_haven');

  @override
  Future<HavenState> placeBuilding(String typeId, int slot) =>
      _call('place_building', {'p_type': typeId, 'p_slot': slot});

  @override
  Future<HavenState> upgradeBuilding(int buildingId) =>
      _call('upgrade_building', {'p_building': buildingId});
}

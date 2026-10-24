import '../domain/models.dart';

/// Everything the haven screen can ask the game server to do.
///
/// Every call returns the full, up-to-date haven state, so the client never
/// has to work out the results of an action itself.
abstract class GameBackend {
  /// Makes sure the player has a haven (creating one on first login).
  Future<HavenState> startGame();

  /// Current state of the player's haven.
  Future<HavenState> fetchHaven();

  /// Start building [typeId] on an empty plot.
  Future<HavenState> placeBuilding(String typeId, int slot);

  /// Start upgrading a building by one level.
  Future<HavenState> upgradeBuilding(int buildingId);
}

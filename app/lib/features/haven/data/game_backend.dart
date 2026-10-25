import '../domain/models.dart';

/// Everything the haven screen can ask the game server to do.
///
/// Every action returns the full, up-to-date haven state, so the client never
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

  /// Set how many crew work at a building.
  Future<HavenState> assignWorkers(int buildingId, int workers);

  /// Spend research points on a tech.
  Future<HavenState> research(String techId);

  /// The havens on the player's island (name and captain only).
  Future<List<Neighbour>> neighbours();
}

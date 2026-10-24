import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';
import '../domain/models.dart';

/// Ticks twice a second so resource numbers and timers can count up locally.
final clockProvider = StreamProvider.autoDispose<DateTime>(
  (ref) =>
      Stream.periodic(const Duration(milliseconds: 500), (_) => DateTime.now()),
);

/// The player's haven, as last reported by the server.
///
/// Between server responses the UI interpolates resources with
/// [HavenState.amountAt]. When a construction finishes, the controller
/// refetches so the new building level (and production rate) shows up.
final havenControllerProvider =
    AsyncNotifierProvider.autoDispose<HavenController, HavenState>(
      HavenController.new,
    );

class HavenController extends AsyncNotifier<HavenState> {
  Timer? _completionTimer;

  @override
  Future<HavenState> build() async {
    ref.onDispose(() => _completionTimer?.cancel());
    final haven = await ref.read(gameBackendProvider).startGame();
    _scheduleCompletion(haven);
    return haven;
  }

  /// Starts building [typeId] on [slot]. Returns an error message, or null.
  Future<String?> place(String typeId, int slot) =>
      _run(() => ref.read(gameBackendProvider).placeBuilding(typeId, slot));

  /// Starts upgrading a building. Returns an error message, or null.
  Future<String?> upgrade(int buildingId) =>
      _run(() => ref.read(gameBackendProvider).upgradeBuilding(buildingId));

  /// Gets the latest state (for example when the app comes back to the front).
  Future<void> refresh() async {
    await _run(() => ref.read(gameBackendProvider).fetchHaven());
  }

  Future<String?> _run(Future<HavenState> Function() action) async {
    try {
      final haven = await action();
      if (!ref.mounted) return null;
      state = AsyncData(haven);
      _scheduleCompletion(haven);
      return null;
    } on GameException catch (e) {
      return e.message;
    } catch (e) {
      return 'The tide went out on that one. Check your connection and try again.';
    }
  }

  /// Refetch shortly after the running construction finishes.
  void _scheduleCompletion(HavenState haven) {
    _completionTimer?.cancel();
    final finishes = haven.constructing?.finishesAt;
    if (finishes == null) return;
    var wait =
        finishes.difference(haven.serverNow()) +
        const Duration(milliseconds: 600);
    if (wait.isNegative) wait = Duration.zero;
    _completionTimer = Timer(wait, refresh);
  }
}

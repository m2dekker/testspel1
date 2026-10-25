import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';
import '../../../core/theme.dart';
import '../../auth/data/auth_service.dart';
import '../application/haven_controller.dart';
import '../domain/models.dart';
import 'look.dart';
import 'widgets/build_sheet.dart';
import 'widgets/building_sheet.dart';
import 'widgets/neighbours_sheet.dart';
import 'widgets/plot_tile.dart';
import 'widgets/resource_bar.dart';

/// The player's haven: resources on top, building plots on the island,
/// and the current construction at the bottom.
class HavenScreen extends ConsumerStatefulWidget {
  const HavenScreen({super.key});

  @override
  ConsumerState<HavenScreen> createState() => _HavenScreenState();
}

class _HavenScreenState extends ConsumerState<HavenScreen> {
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    // Coming back to the app: fetch what happened while it was closed.
    _lifecycle = AppLifecycleListener(
      onResume: () => ref.read(havenControllerProvider.notifier).refresh(),
    );
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final haven = ref.watch(havenControllerProvider);

    return Scaffold(
      appBar: AppBar(
        title: haven.value == null
            ? const Text('Blackwake Isles')
            : InkWell(
                // Tap the island name to see who else lives here.
                onTap: () => showModalBottomSheet<void>(
                  context: context,
                  builder: (_) => NeighboursSheet(island: haven.value!.island),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      haven.value!.name,
                      style: const TextStyle(fontSize: 18),
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Flexible(
                          child: Text(
                            '${haven.value!.island.name} · ${resourceLabel(haven.value!.island.luxury)} island',
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 12,
                              color: BwColors.parchmentDark,
                            ),
                          ),
                        ),
                        const Icon(
                          Icons.expand_more,
                          size: 16,
                          color: BwColors.parchmentDark,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
        actions: const [_HavenMenu()],
      ),
      body: switch (haven) {
        AsyncData(:final value) => _HavenView(haven: value),
        AsyncError(:final error) => _ErrorView(
          message: error is GameException
              ? error.message
              : 'Could not reach your haven.',
          onRetry: () => ref.invalidate(havenControllerProvider),
        ),
        _ => const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(color: BwColors.gold),
              SizedBox(height: 16),
              Text(
                'Charting your haven…',
                style: TextStyle(color: BwColors.parchment),
              ),
            ],
          ),
        ),
      },
    );
  }
}

class _HavenView extends ConsumerWidget {
  const _HavenView({required this.haven});

  final HavenState haven;

  void _openPlot(BuildContext context, int slot) {
    final building = haven.buildingAt(slot);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => building == null
          ? BuildSheet(slot: slot)
          : BuildingSheet(buildingId: building.id),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(clockProvider);
    final now = haven.serverNow();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ResourceBar(haven: haven),
        Expanded(
          child: Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [BwColors.sea, BwColors.deepSea],
              ),
            ),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 520),
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: BwColors.sand,
                      borderRadius: BorderRadius.circular(36),
                      border: Border.all(color: BwColors.jungle, width: 8),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x55000000),
                          blurRadius: 18,
                          offset: Offset(0, 8),
                        ),
                      ],
                    ),
                    child: GridView.count(
                      crossAxisCount: 2,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      mainAxisSpacing: 12,
                      crossAxisSpacing: 12,
                      childAspectRatio: 1.25,
                      children: [
                        for (var slot = 0; slot < haven.plots; slot++)
                          PlotTile(
                            haven: haven,
                            slot: slot,
                            now: now,
                            onTap: () => _openPlot(context, slot),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        _QueueStrip(haven: haven, now: now),
      ],
    );
  }
}

/// Bottom strip: what the builders are doing.
class _QueueStrip extends StatelessWidget {
  const _QueueStrip({required this.haven, required this.now});

  final HavenState haven;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final b = haven.constructing;
    final text = b == null
        ? 'Builders are idle. Tap an empty plot to build.'
        : '${haven.typeOf(b.type).name} → level ${b.level + 1} · '
              '${formatDuration(b.finishesAt!.difference(now))}';

    return Container(
      color: BwColors.wood,
      padding: EdgeInsets.fromLTRB(
        16,
        12,
        16,
        12 + MediaQuery.paddingOf(context).bottom,
      ),
      child: Row(
        children: [
          Icon(
            b == null ? Icons.handyman_outlined : Icons.construction,
            color: BwColors.gold,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(color: BwColors.parchment),
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: BwColors.parchment),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: 200,
              child: FilledButton(
                onPressed: onRetry,
                child: const Text('Try again'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HavenMenu extends ConsumerWidget {
  const _HavenMenu();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authServiceProvider);
    return PopupMenuButton<String>(
      tooltip: 'Menu',
      onSelected: (value) async {
        switch ((value, auth)) {
          case ('signout', SupabaseAuthService a):
            await a.signOut();
          case ('signout', DemoAuthService a):
            await a.signOut();
          case ('abandon', DemoAuthService a):
            await a.abandonHaven();
        }
      },
      itemBuilder: (_) => [
        PopupMenuItem(
          enabled: false,
          child: Text('Captain ${auth.user?.name ?? ''}'),
        ),
        const PopupMenuItem(value: 'signout', child: Text('Sign out')),
        if (auth.isDemo)
          const PopupMenuItem(
            value: 'abandon',
            child: Text('Start a new demo haven'),
          ),
      ],
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme.dart';
import '../../application/haven_controller.dart';
import '../../domain/models.dart';
import '../look.dart';
import 'cost_row.dart';
import 'research_sheet.dart';

/// Bottom sheet for a building: what it does now, its crew, and its next level.
class BuildingSheet extends ConsumerWidget {
  const BuildingSheet({super.key, required this.buildingId});

  final int buildingId;

  /// Runs an action and shows its error, if any. The messenger is looked up
  /// before waiting, so the context is never used across the async gap.
  Future<void> _act(
    BuildContext context,
    Future<String?> Function() action,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final error = await action();
    if (error != null) {
      messenger.showSnackBar(SnackBar(content: Text(error)));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(clockProvider);
    final haven = ref.watch(havenControllerProvider).value;
    final building = haven?.buildings
        .where((b) => b.id == buildingId)
        .firstOrNull;
    if (haven == null || building == null) return const SizedBox.shrink();

    final type = haven.typeOf(building.type);
    final now = haven.serverNow();
    final next = building.next;
    final busyElsewhere =
        haven.constructing != null && !building.isConstructing;
    final luxury = haven.island.luxury;
    final current = building.level > 0
        ? effectLines(building.effect, luxury)
        : const <String>[];

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      builder: (context, scroll) => ListView(
        controller: scroll,
        padding: EdgeInsets.fromLTRB(
          16,
          0,
          16,
          16 + MediaQuery.paddingOf(context).bottom,
        ),
        children: [
          Row(
            children: [
              Icon(buildingIcon(type.id), color: BwColors.wood, size: 30),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  type.name,
                  style: Theme.of(context).textTheme.titleLarge
                      ?.copyWith(color: BwColors.ink),
                ),
              ),
              Text(
                building.level == 0
                    ? 'Under construction'
                    : 'Level ${building.level}',
                style: const TextStyle(color: BwColors.woodLight),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(type.description, style: const TextStyle(color: BwColors.ink)),
          for (final line in current) ...[
            const SizedBox(height: 4),
            Text(
              line,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                color: BwColors.ink,
              ),
            ),
          ],

          // ---- crew at work ----
          if (building.hasJobs && building.level > 0) ...[
            const Divider(height: 28),
            _WorkersControl(
              haven: haven,
              building: building,
              now: now,
              onChange: (n) async => _act(
                context,
                () => ref
                    .read(havenControllerProvider.notifier)
                    .assign(building.id, n),
              ),
            ),
          ],

          // ---- research ----
          if (type.id == 'academy' && building.level > 0) ...[
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () => showModalBottomSheet<void>(
                context: context,
                isScrollControlled: true,
                builder: (_) => const ResearchSheet(),
              ),
              icon: const Icon(researchIcon),
              label: Text('Research · ${haven.researchAt(now).floor()} points'),
            ),
          ],

          const Divider(height: 28),

          // ---- next level ----
          if (building.isConstructing && next != null) ...[
            Text(
              'Building level ${next.level}',
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                color: BwColors.ink,
              ),
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value:
                    (1 -
                            building.finishesAt!
                                    .difference(now)
                                    .inMilliseconds /
                                (next.seconds * 1000))
                        .clamp(0.0, 1.0),
                minHeight: 10,
                color: BwColors.gold,
                backgroundColor: BwColors.parchmentDark,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '${formatDuration(building.finishesAt!.difference(now))} left',
              style: const TextStyle(color: BwColors.woodLight),
            ),
          ] else if (next != null) ...[
            Text(
              'Level ${next.level}',
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                color: BwColors.ink,
              ),
            ),
            for (final line in effectLines(next.effect, luxury)) ...[
              const SizedBox(height: 4),
              Text(line, style: const TextStyle(color: BwColors.ink)),
            ],
            const SizedBox(height: 8),
            CostRow(
              cost: next.cost,
              seconds: next.seconds,
              haven: haven,
              now: now,
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: busyElsewhere || !haven.canAfford(next.cost, now)
                  ? null
                  : () async => _act(
                      context,
                      () => ref
                          .read(havenControllerProvider.notifier)
                          .upgrade(building.id),
                    ),
              child: Text(
                busyElsewhere
                    ? 'Builders busy'
                    : haven.canAfford(next.cost, now)
                    ? 'Upgrade to level ${next.level}'
                    : 'Not enough resources',
              ),
            ),
          ] else
            const Text(
              'This building is at its highest level.',
              style: TextStyle(color: BwColors.woodLight),
            ),
        ],
      ),
    );
  }
}

/// "Crew at work: 4 / 8" with −, + and "All" buttons.
class _WorkersControl extends StatelessWidget {
  const _WorkersControl({
    required this.haven,
    required this.building,
    required this.now,
    required this.onChange,
  });

  final HavenState haven;
  final Building building;
  final DateTime now;
  final ValueChanged<int> onChange;

  @override
  Widget build(BuildContext context) {
    final jobs = building.effect.workers;
    final idle = haven.idleCrew(now);
    final most = (building.workers + idle).clamp(0, jobs);
    final rate = building.effect.workerRate.round();
    final product = productName(building.effect.produces, haven.island.luxury);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Icon(crewIcon, color: BwColors.wood),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Crew at work: ${building.workers} / $jobs',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  color: BwColors.ink,
                ),
              ),
            ),
            IconButton.outlined(
              tooltip: 'One fewer',
              onPressed: building.workers > 0
                  ? () => onChange(building.workers - 1)
                  : null,
              icon: const Icon(Icons.remove),
            ),
            const SizedBox(width: 6),
            IconButton.outlined(
              tooltip: 'One more',
              onPressed: building.workers < most
                  ? () => onChange(building.workers + 1)
                  : null,
              icon: const Icon(Icons.add),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          'Each worker makes $rate $product per hour. '
          '$idle idle crew in the haven, earning gold.',
          style: const TextStyle(color: BwColors.woodLight),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: building.workers > 0 ? () => onChange(0) : null,
                child: const Text('None'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton(
                onPressed: building.workers < most
                    ? () => onChange(most)
                    : null,
                child: Text('Fill ($most)'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

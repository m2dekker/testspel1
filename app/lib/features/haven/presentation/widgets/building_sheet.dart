import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme.dart';
import '../../application/haven_controller.dart';
import '../look.dart';
import 'cost_row.dart';

/// Bottom sheet for a building: what it does now, and its next level.
class BuildingSheet extends ConsumerWidget {
  const BuildingSheet({super.key, required this.buildingId});

  final int buildingId;

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
    final current = productionText(
      type.produces,
      type.baseRate * building.level,
      haven.island.luxury,
      storage: type.storagePerLevel * building.level,
    );

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
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
            if (building.level > 0 && current.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                'Now: $current',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  color: BwColors.ink,
                ),
              ),
            ],
            const Divider(height: 28),
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
              const SizedBox(height: 4),
              Text(
                productionText(
                  type.produces,
                  next.rate,
                  haven.island.luxury,
                  storage: next.storage,
                ),
                style: const TextStyle(color: BwColors.ink),
              ),
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
                    : () async {
                        final error = await ref
                            .read(havenControllerProvider.notifier)
                            .upgrade(building.id);
                        if (error != null && context.mounted) {
                          ScaffoldMessenger.of(context)
                              .showSnackBar(SnackBar(content: Text(error)));
                        }
                      },
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
      ),
    );
  }
}

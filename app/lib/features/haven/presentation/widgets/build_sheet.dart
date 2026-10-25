import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme.dart';
import '../../application/haven_controller.dart';
import '../../domain/models.dart';
import '../look.dart';
import 'cost_row.dart';

/// Bottom sheet listing the buildings that can go on an empty plot.
class BuildSheet extends ConsumerWidget {
  const BuildSheet({super.key, required this.slot});

  final int slot;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(clockProvider);
    final haven = ref.watch(havenControllerProvider).value;
    if (haven == null) return const SizedBox.shrink();
    final now = haven.serverNow();
    final busy = haven.constructing;
    // One of each building per haven, so only show what isn't built yet.
    final options = haven.catalogue
        .where((t) => t.buildable && !haven.hasBuilt(t.id))
        .toList();

    // Draggable and scrollable, so every option is reachable on small phones.
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.75,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      builder: (context, scrollController) => ListView(
        controller: scrollController,
        padding: EdgeInsets.fromLTRB(
          16,
          0,
          16,
          16 + MediaQuery.paddingOf(context).bottom,
        ),
        children: [
          Text(
            'Build on plot ${slot + 1}',
            style: Theme.of(context).textTheme.titleLarge
                ?.copyWith(color: BwColors.ink),
          ),
          if (busy != null) ...[
            const SizedBox(height: 6),
            Text(
              'Your builders are working on the ${haven.typeOf(busy.type).name}. '
              'You can start something new when they finish.',
              style: const TextStyle(color: BwColors.woodLight),
            ),
          ],
          const SizedBox(height: 12),
          if (options.isEmpty)
            const Text(
              'You have built everything available for now. Upgrade your buildings to grow.',
              style: TextStyle(color: BwColors.woodLight),
            ),
          for (final type in options)
            _BuildOption(
              type: type,
              haven: haven,
              now: now,
              busy: busy != null,
              onBuild: () async {
                final error = await ref
                    .read(havenControllerProvider.notifier)
                    .place(type.id, slot);
                if (!context.mounted) return;
                if (error == null) {
                  Navigator.of(context).pop();
                } else {
                  ScaffoldMessenger.of(context)
                      .showSnackBar(SnackBar(content: Text(error)));
                }
              },
            ),
        ],
      ),
    );
  }
}

class _BuildOption extends StatelessWidget {
  const _BuildOption({
    required this.type,
    required this.haven,
    required this.now,
    required this.busy,
    required this.onBuild,
  });

  final BuildingType type;
  final HavenState haven;
  final DateTime now;
  final bool busy;
  final VoidCallback onBuild;

  @override
  Widget build(BuildContext context) {
    final affordable = haven.canAfford(type.cost, now);
    final effect = effectLines(type.effect, haven.island.luxury).join(' · ');

    final String label;
    if (busy) {
      label = 'Builders busy';
    } else if (!affordable) {
      label = 'Not enough resources';
    } else {
      label = 'Build';
    }

    return Card(
      color: Colors.white.withValues(alpha: 0.55),
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: BwColors.parchmentDark),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(buildingIcon(type.id), color: BwColors.wood),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    type.name,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: BwColors.ink,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              type.id == 'plantation'
                  ? '${type.description} Here it produces ${resourceLabel(haven.island.luxury).toLowerCase()}.'
                  : type.description,
              style: const TextStyle(color: BwColors.ink),
            ),
            if (effect.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                effect,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  color: BwColors.woodLight,
                ),
              ),
            ],
            const SizedBox(height: 8),
            CostRow(
              cost: type.cost,
              seconds: type.seconds,
              haven: haven,
              now: now,
            ),
            const SizedBox(height: 10),
            FilledButton(
              onPressed: busy || !affordable ? null : onBuild,
              child: Text(label),
            ),
          ],
        ),
      ),
    );
  }
}

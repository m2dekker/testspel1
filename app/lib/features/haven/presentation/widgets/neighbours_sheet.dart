import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/providers.dart';
import '../../../../core/theme.dart';
import '../../application/haven_controller.dart';
import '../../domain/models.dart';
import '../look.dart';

/// Who else lives on this island. Only names: no resources or buildings.
class NeighboursSheet extends ConsumerWidget {
  const NeighboursSheet({super.key, required this.island});

  final Island island;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final neighbours = ref.watch(neighboursProvider);
    final isDemo = ref.watch(authServiceProvider).isDemo;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              island.name,
              style: Theme.of(context).textTheme.titleLarge
                  ?.copyWith(color: BwColors.ink),
            ),
            Text(
              '${resourceLabel(island.luxury)} island · position ${island.x}, ${island.y}',
              style: const TextStyle(color: BwColors.woodLight),
            ),
            const SizedBox(height: 12),
            switch (neighbours) {
              AsyncData(:final value) => Column(
                children: [
                  for (final n in value)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(
                        n.isYou ? Icons.flag : Icons.flag_outlined,
                        color: BwColors.wood,
                      ),
                      title: Text(
                        n.haven,
                        style: const TextStyle(color: BwColors.ink),
                      ),
                      subtitle: Text(
                        n.isYou ? 'You' : 'Captain ${n.captain}',
                        style: const TextStyle(color: BwColors.woodLight),
                      ),
                    ),
                  if (value.length <= 1)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        isDemo
                            ? 'In the offline demo you are alone on the island. '
                                  'Connect Supabase to share it with other captains.'
                            : 'No other captains here yet. New players settle on '
                                  'the least crowded island.',
                        style: const TextStyle(color: BwColors.woodLight),
                      ),
                    ),
                ],
              ),
              AsyncError() => const Text(
                'Could not look across the island. Try again in a moment.',
                style: TextStyle(color: BwColors.danger),
              ),
              _ => const Padding(
                padding: EdgeInsets.all(16),
                child: Center(
                  child: CircularProgressIndicator(color: BwColors.gold),
                ),
              ),
            },
          ],
        ),
      ),
    );
  }
}

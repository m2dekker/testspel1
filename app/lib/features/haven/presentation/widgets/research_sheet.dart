import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme.dart';
import '../../application/haven_controller.dart';
import '../../domain/models.dart';
import '../look.dart';

/// The Economy research tree: four techs, unlocked in order.
class ResearchSheet extends ConsumerWidget {
  const ResearchSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(clockProvider);
    final haven = ref.watch(havenControllerProvider).value;
    if (haven == null) return const SizedBox.shrink();
    final now = haven.serverNow();
    final points = haven.researchAt(now);

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.75,
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
          Text(
            'Research: Economy',
            style: Theme.of(context).textTheme.titleLarge
                ?.copyWith(color: BwColors.ink),
          ),
          const SizedBox(height: 4),
          Text(
            '${points.floor()} research points'
            '${haven.researchRate > 0 ? ' · +${haven.researchRate.round()} per hour' : ' · put scholars to work in the Academy'}',
            style: const TextStyle(color: BwColors.woodLight),
          ),
          const SizedBox(height: 12),
          for (final tech in haven.techs)
            _TechCard(
              tech: tech,
              haven: haven,
              points: points,
              onResearch: () async {
                final error = await ref
                    .read(havenControllerProvider.notifier)
                    .research(tech.id);
                if (error != null && context.mounted) {
                  ScaffoldMessenger.of(context)
                      .showSnackBar(SnackBar(content: Text(error)));
                }
              },
            ),
          const SizedBox(height: 4),
          const Text(
            'Seafaring, Warfare and Intrigue arrive with ships and combat.',
            style: TextStyle(color: BwColors.woodLight, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _TechCard extends StatelessWidget {
  const _TechCard({
    required this.tech,
    required this.haven,
    required this.points,
    required this.onResearch,
  });

  final Tech tech;
  final HavenState haven;
  final double points;
  final VoidCallback onResearch;

  @override
  Widget build(BuildContext context) {
    final unlocked = haven.isUnlocked(tech);
    final affordable = points >= tech.cost;

    final Widget action;
    if (tech.researched) {
      action = const Row(
        children: [
          Icon(Icons.check_circle, color: BwColors.jungle),
          SizedBox(width: 6),
          Text(
            'Researched',
            style: TextStyle(
              color: BwColors.jungle,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      );
    } else if (!unlocked) {
      action = Text(
        'Needs ${haven.techById(tech.requires!).name} first',
        style: const TextStyle(color: BwColors.woodLight),
      );
    } else {
      action = FilledButton(
        onPressed: affordable ? onResearch : null,
        child: Text(
          affordable
              ? 'Research · ${tech.cost} points'
              : 'Needs ${tech.cost} points',
        ),
      );
    }

    return Card(
      color: Colors.white.withValues(alpha: tech.researched ? 0.3 : 0.55),
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: unlocked ? BwColors.gold : BwColors.parchmentDark,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(
                  tech.researched || unlocked ? researchIcon : Icons.lock,
                  color: BwColors.wood,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    tech.name,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: BwColors.ink,
                    ),
                  ),
                ),
                Text(
                  '${tech.cost} pts',
                  style: const TextStyle(color: BwColors.woodLight),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(tech.description, style: const TextStyle(color: BwColors.ink)),
            const SizedBox(height: 10),
            action,
          ],
        ),
      ),
    );
  }
}

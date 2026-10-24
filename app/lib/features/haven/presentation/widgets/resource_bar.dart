import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme.dart';
import '../../application/haven_controller.dart';
import '../../domain/models.dart';
import '../look.dart';

/// The resource strip at the top of the haven. Rebuilds on every clock tick
/// and counts up locally using the production rates from the server.
class ResourceBar extends ConsumerWidget {
  const ResourceBar({super.key, required this.haven});

  final HavenState haven;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(clockProvider);
    final now = haven.serverNow();

    // Timber, this island's luxury, then gold. Other luxuries show once owned.
    final shown = [
      Resource.timber,
      haven.island.luxury,
      for (final r in [
        Resource.rum,
        Resource.spice,
        Resource.iron,
        Resource.silk,
      ])
        if (r != haven.island.luxury && haven.resources[r]! > 0) r,
      Resource.gold,
    ];

    return Container(
      color: BwColors.woodLight,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final r in shown)
                _ResourceChip(
                  resource: r,
                  amount: haven.amountAt(r, now),
                  rate: haven.ratePerHour(r),
                  full:
                      r != Resource.gold &&
                      haven.amountAt(r, now) >= haven.capacity,
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Storage ${haven.capacity.round()} per good',
            style: const TextStyle(color: BwColors.parchmentDark, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _ResourceChip extends StatelessWidget {
  const _ResourceChip({
    required this.resource,
    required this.amount,
    required this.rate,
    required this.full,
  });

  final Resource resource;
  final double amount;
  final double rate;
  final bool full;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label:
          '${resourceLabel(resource)}: ${amount.floor()}'
          '${rate > 0 ? ', plus ${rate.round()} per hour' : ''}${full ? ', storage full' : ''}',
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: BwColors.parchment,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: full ? BwColors.danger : BwColors.gold,
            width: 1.5,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(resourceIcon(resource), size: 18, color: BwColors.wood),
            const SizedBox(width: 6),
            Text(
              '${amount.floor()}',
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                color: BwColors.ink,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
            if (rate > 0) ...[
              const SizedBox(width: 4),
              Text(
                full ? 'full' : '+${rate.round()}/h',
                style: TextStyle(
                  fontSize: 11,
                  color: full ? BwColors.danger : BwColors.woodLight,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

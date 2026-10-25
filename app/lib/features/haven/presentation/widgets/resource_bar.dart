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

    final crew = haven.crewAt(now);
    final crewFull = crew >= haven.crew.cap;
    final hasAcademy = haven.hasBuilt('academy');

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
                _Chip(
                  icon: resourceIcon(r),
                  label: resourceLabel(r),
                  value: '${haven.amountAt(r, now).floor()}',
                  rate: haven.ratePerHour(r, now),
                  full:
                      r != Resource.gold &&
                      haven.amountAt(r, now) >= haven.capacity,
                ),
              _Chip(
                icon: crewIcon,
                label: 'Crew',
                value: '${crew.floor()}/${haven.crew.cap.round()}',
                rate: crewFull ? 0 : haven.crew.growth,
                note: '${haven.idleCrew(now)} idle',
              ),
              if (hasAcademy)
                _Chip(
                  icon: researchIcon,
                  label: 'Research points',
                  value: '${haven.researchAt(now).floor()}',
                  rate: haven.researchRate,
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

class _Chip extends StatelessWidget {
  const _Chip({
    required this.icon,
    required this.label,
    required this.value,
    required this.rate,
    this.full = false,
    this.note,
  });

  final IconData icon;
  final String label;
  final String value;
  final double rate;
  final bool full;
  final String? note;

  @override
  Widget build(BuildContext context) {
    final extra = full
        ? 'full'
        : rate > 0
        ? '+${rate.round()}/h'
        : null;
    return Semantics(
      label:
          '$label: $value'
          '${rate > 0 && !full ? ', plus ${rate.round()} per hour' : ''}'
          '${full ? ', storage full' : ''}'
          '${note != null ? ', $note' : ''}',
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
            Icon(icon, size: 18, color: BwColors.wood),
            const SizedBox(width: 6),
            Text(
              value,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                color: BwColors.ink,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
            if (extra != null) ...[
              const SizedBox(width: 4),
              Text(
                extra,
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

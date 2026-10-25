import 'package:flutter/material.dart';

import '../../../../core/theme.dart';
import '../../domain/models.dart';
import '../look.dart';

/// One building plot in the haven: empty, under construction or built.
class PlotTile extends StatelessWidget {
  const PlotTile({
    super.key,
    required this.haven,
    required this.slot,
    required this.now,
    required this.onTap,
  });

  final HavenState haven;
  final int slot;
  final DateTime now;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final building = haven.buildingAt(slot);
    return Material(
      color: building == null ? Colors.transparent : BwColors.parchment,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: building == null
            ? const _EmptyPlot()
            : _BuiltPlot(haven: haven, building: building, now: now),
      ),
    );
  }
}

class _EmptyPlot extends StatelessWidget {
  const _EmptyPlot();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Empty plot. Build here.',
      excludeSemantics: true,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: BwColors.wood.withValues(alpha: 0.35),
            width: 2,
          ),
          color: BwColors.jungle.withValues(alpha: 0.18),
        ),
        child: const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.add_circle_outline,
                color: BwColors.woodLight,
                size: 28,
              ),
              SizedBox(height: 4),
              Text(
                'Build',
                style: TextStyle(
                  color: BwColors.woodLight,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BuiltPlot extends StatelessWidget {
  const _BuiltPlot({
    required this.haven,
    required this.building,
    required this.now,
  });

  final HavenState haven;
  final Building building;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final type = haven.typeOf(building.type);
    final finishes = building.finishesAt;
    final remaining = finishes?.difference(now);
    final total = building.next?.seconds ?? 1;
    final progress = remaining == null
        ? 1.0
        : (1 - remaining.inMilliseconds / (total * 1000)).clamp(0.0, 1.0);

    final status = building.level == 0
        ? 'Building… ${formatDuration(remaining ?? Duration.zero)}'
        : finishes != null
        ? 'Lv ${building.level} → ${building.level + 1} · ${formatDuration(remaining!)}'
        : building.hasJobs
        ? 'Lv ${building.level} · ${building.workers}/${building.effect.workers} crew'
        : 'Level ${building.level}';

    return Semantics(
      button: true,
      label: '${type.name}, $status',
      excludeSemantics: true,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: BwColors.wood, width: 2),
        ),
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  buildingIcon(building.type),
                  color: BwColors.wood,
                  size: 26,
                ),
                const Spacer(),
                if (building.level > 0)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: BwColors.gold,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '${building.level}',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        color: BwColors.ink,
                      ),
                    ),
                  ),
              ],
            ),
            const Spacer(),
            Text(
              type.name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                color: BwColors.ink,
                height: 1.15,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              status,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, color: BwColors.woodLight),
            ),
            if (finishes != null) ...[
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: progress,
                  minHeight: 6,
                  color: BwColors.gold,
                  backgroundColor: BwColors.parchmentDark,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

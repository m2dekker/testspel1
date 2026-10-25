import 'package:flutter/material.dart';

import '../../../../core/theme.dart';
import '../../domain/models.dart';
import '../look.dart';

/// A cost and a build time, with amounts the player can't afford in red.
class CostRow extends StatelessWidget {
  const CostRow({
    super.key,
    required this.cost,
    required this.seconds,
    required this.haven,
    required this.now,
  });

  final Cost cost;
  final int seconds;
  final HavenState haven;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    Widget item(IconData icon, String text, {bool short = false}) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          icon,
          size: 16,
          color: short ? BwColors.danger : BwColors.woodLight,
        ),
        const SizedBox(width: 3),
        Text(
          text,
          style: TextStyle(
            color: short ? BwColors.danger : BwColors.ink,
            fontWeight: short ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ],
    );

    return Wrap(
      spacing: 14,
      runSpacing: 4,
      children: [
        if (cost.timber > 0)
          item(
            resourceIcon(Resource.timber),
            '${cost.timber}',
            short: haven.amountAt(Resource.timber, now) < cost.timber,
          ),
        if (cost.gold > 0)
          item(
            resourceIcon(Resource.gold),
            '${cost.gold}',
            short: haven.amountAt(Resource.gold, now) < cost.gold,
          ),
        item(Icons.schedule, formatDuration(Duration(seconds: seconds))),
      ],
    );
  }
}

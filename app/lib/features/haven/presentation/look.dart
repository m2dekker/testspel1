import 'package:flutter/material.dart';

import '../domain/models.dart';

/// Placeholder art: Material icons and labels for resources and buildings.
/// Swap these for real sprites once the art arrives.

IconData resourceIcon(Resource r) => switch (r) {
  Resource.timber => Icons.forest,
  Resource.rum => Icons.local_bar,
  Resource.spice => Icons.local_florist,
  Resource.iron => Icons.hardware,
  Resource.silk => Icons.texture,
  Resource.gold => Icons.paid,
};

const crewIcon = Icons.groups;
const researchIcon = Icons.auto_stories;

String resourceLabel(Resource r) => switch (r) {
  Resource.timber => 'Timber',
  Resource.rum => 'Rum',
  Resource.spice => 'Spice',
  Resource.iron => 'Iron',
  Resource.silk => 'Silk',
  Resource.gold => 'Gold',
};

IconData buildingIcon(String type) => switch (type) {
  'captains_quarters' => Icons.flag,
  'lumber_camp' => Icons.carpenter,
  'plantation' => Icons.agriculture,
  'warehouse' => Icons.warehouse,
  'tavern' => Icons.sports_bar,
  'academy' => Icons.school,
  _ => Icons.home_work,
};

/// "1m 05s", "45s", "2h 03m".
String formatDuration(Duration d) {
  if (d.isNegative) d = Duration.zero;
  final h = d.inHours, m = d.inMinutes % 60, s = d.inSeconds % 60;
  if (h > 0) return '${h}h ${m.toString().padLeft(2, '0')}m';
  if (m > 0) return '${m}m ${s.toString().padLeft(2, '0')}s';
  return '${s}s';
}

/// Name of what a building produces, e.g. "timber", "spice", "research".
String productName(String? produces, Resource luxury) => switch (produces) {
  'timber' => 'timber',
  'luxury' => resourceLabel(luxury).toLowerCase(),
  'research' => 'research',
  _ => '',
};

/// What one level of a building gives, in short lines, e.g.
/// ["8 jobs · 40 timber/h each"] or ["Houses 20 crew"].
List<String> effectLines(BuildingEffect e, Resource luxury) => [
  if (e.workers > 0)
    '${e.workers} jobs · ${e.workerRate.round()} '
        '${productName(e.produces, luxury)}/h each',
  if (e.crewCap > 0) 'Houses ${e.crewCap} crew',
  if (e.growth > 0) '+${e.growth.round()} crew arriving per hour',
  if (e.storage > 0) '+${e.storage} storage',
];

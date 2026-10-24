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

/// What a building produces, in words, e.g. "+300 timber / hour".
String productionText(
  String? produces,
  double perHour,
  Resource luxury, {
  int storage = 0,
}) {
  final n = perHour.round();
  return switch (produces) {
    'timber' => '+$n timber / hour',
    'luxury' => '+$n ${resourceLabel(luxury).toLowerCase()} / hour',
    'gold' => '+$n gold / hour',
    _ => storage > 0 ? '+$storage storage' : '',
  };
}

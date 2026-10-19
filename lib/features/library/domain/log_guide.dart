import 'package:flutter/material.dart';

import '../../../core/domain/load_types.dart';
import 'exercise_info.dart';

/// How to enter the weight for one exercise: a one-line rule, what it means, and whether the bar / sled / carriage is counted.
/// Every exercise gets one: its load type (your override from the logger's "Weight steps…", else the classification) decides.
class LogGuide {
  const LogGuide({required this.type, required this.headline, required this.detail, required this.includes, required this.unilateral});
  final LoadType type;
  final String headline;
  final String detail;

  /// Whether the bar / sled / lever's own weight is part of the number.
  final String includes;
  final bool unilateral;
}

final RegExp _unilateral = RegExp(r'one[- ]arm|single[- ]arm|one[- ]leg|single[- ]leg|one[- ]hand|single[- ]hand|unilateral|alternating|\bsingle\b', caseSensitive: false);

bool isUnilateralName(String name) => _unilateral.hasMatch(name);

/// [bodyweightLoaded]: an exercise whose dataset equipment says nothing but whose load is bodyweight plus an optional added weight (hyperextensions).
LogGuide logGuideFor({required String name, required String? equipment, bool assisted = false, LoadType? override, double barWeight = 20, bool bodyweightLoaded = false}) {
  var type = override ?? classifyLoad(name: name, equipment: equipment, assisted: assisted);
  if (override == null && type == LoadType.other && bodyweightLoaded) type = LoadType.bodyweight;
  final one = isUnilateralName(name);
  final bar = barWeight == barWeight.roundToDouble() ? barWeight.round().toString() : barWeight.toString();
  switch (type) {
    case LoadType.assisted:
      return LogGuide(
        type: type,
        unilateral: one,
        headline: 'Log the assistance as negative',
        detail: 'Enter −30 when the machine takes 30 kg off your bodyweight; 0 means unassisted. Less assistance is a heavier lift.',
        includes: 'Your bodyweight is added automatically for ranks; you only log the assistance.',
      );
    case LoadType.dumbbell:
      return LogGuide(
        type: type,
        unilateral: one,
        headline: 'Log the weight of ONE dumbbell',
        detail: one ? 'One side at a time: the dumbbell in your working hand.' : 'Two dumbbells of 20 kg is logged as 20, not 40.',
        includes: 'Just the dumbbell: nothing else is added.',
      );
    case LoadType.plateBothSides:
      return LogGuide(
        type: type,
        unilateral: one,
        headline: one ? 'Log the weight for one side' : 'Log total plates on both sides',
        detail: one ? 'The plates on the machine while you train one side.' : 'Add up the plates on the left and the right: 2 × 20 kg plates is logged as 40.',
        includes: 'Plates only: the sled or carriage’s own weight is not counted.',
      );
    case LoadType.plateOneSide:
      return LogGuide(
        type: type,
        unilateral: one,
        headline: 'Log total plates on the sleeve',
        detail: 'This machine has a single loading sleeve or horn: add up everything on it.',
        includes: 'Plates only: the lever or arm’s own weight is not counted.',
      );
    case LoadType.stack:
      return LogGuide(
        type: type,
        unilateral: one,
        headline: one ? 'Log the weight for one side' : 'Log the stack weight',
        detail: one ? 'The stack weight (the number at the pin) while you train one side.' : 'The number at the pin on the weight stack or cable.',
        includes: 'Just the stack: handles, ropes and bars are not counted.',
      );
    case LoadType.barbell:
      return LogGuide(
        type: type,
        unilateral: one,
        headline: 'Log the total weight on the bar',
        detail: 'Both sides’ plates plus the bar: a 20 kg bar with 2 × 20 kg plates is logged as 60.',
        includes: 'The bar ($bar kg) is included.',
      );
    case LoadType.kettlebell:
      return LogGuide(
        type: type,
        unilateral: one,
        headline: 'Log the weight of the kettlebell',
        detail: one ? 'One side at a time.' : 'The weight stamped on the kettlebell.',
        includes: 'Just the kettlebell.',
      );
    case LoadType.bodyweight:
      return LogGuide(
        type: type,
        unilateral: one,
        headline: 'Log only the weight you add',
        detail: 'Leave it at 0 for plain bodyweight; add a belt, vest or held plate as kilos.',
        includes: 'Your bodyweight is added automatically for ranks; it is not part of the number.',
      );
    case LoadType.other:
      return LogGuide(
        type: type,
        unilateral: one,
        headline: one ? 'Log the weight for one side' : 'Log the total weight you move',
        detail: 'No equipment is listed for this exercise: log whatever load you add, and 0 for none. Set its load type from the workout menu (Weight steps…) for exact steps.',
        includes: 'Only what you add.',
      );
  }
}

/// One equipment tile on the exercise page.
typedef EquipmentTile = ({IconData icon, String label});

/// The kit an exercise needs: its dataset equipment plus what the name implies (a bench, a Smith machine, a rope).
List<EquipmentTile> equipmentTiles(ExerciseInfo e) {
  final out = <EquipmentTile>[];
  void add(IconData icon, String label) {
    if (!out.any((t) => t.label == label)) out.add((icon: icon, label: label));
  }

  final name = e.name.toLowerCase();
  switch ((e.equipment ?? '').toLowerCase()) {
    case 'barbell':
      add(Icons.linear_scale_rounded, 'Barbell');
    case 'e-z curl bar':
      add(Icons.linear_scale_rounded, 'EZ bar');
    case 'dumbbell':
      add(Icons.fitness_center_rounded, 'Dumbbells');
    case 'kettlebells':
      add(Icons.sports_gymnastics_rounded, 'Kettlebell');
    case 'cable':
      add(Icons.cable_rounded, 'Cable');
    case 'machine':
      add(Icons.precision_manufacturing_rounded, name.contains('smith') ? 'Smith machine' : 'Machine');
    case 'bands':
      add(Icons.gesture_rounded, 'Resistance band');
    case 'body only':
      add(Icons.accessibility_new_rounded, 'Bodyweight');
    case 'medicine ball':
      add(Icons.sports_basketball_rounded, 'Medicine ball');
    case 'exercise ball':
      add(Icons.circle_outlined, 'Exercise ball');
    case 'foam roll':
      add(Icons.horizontal_distribute_rounded, 'Foam roller');
    default:
      if (e.equipment == null || e.equipment == 'other') add(Icons.help_outline_rounded, 'No equipment listed');
  }
  if (name.contains('smith')) add(Icons.precision_manufacturing_rounded, 'Smith machine');
  if (RegExp(r'bench|incline|decline|preacher|lying|supine|chest[- ]supported|seated').hasMatch(name) && (e.equipment ?? '') != 'machine') {
    add(Icons.weekend_rounded, name.contains('preacher') ? 'Preacher bench' : 'Bench');
  }
  if (name.contains('rope')) add(Icons.gesture_rounded, 'Rope');
  if (RegExp(r'pull[- ]?up|chin[- ]?up|hanging').hasMatch(name) && !name.contains('assisted')) add(Icons.unfold_more_rounded, 'Pull-up bar');
  if (RegExp(r'\bdip\b|dips').hasMatch(name) && !name.contains('assisted') && (e.equipment ?? '') != 'machine') add(Icons.unfold_more_rounded, 'Dip bars');
  return out;
}

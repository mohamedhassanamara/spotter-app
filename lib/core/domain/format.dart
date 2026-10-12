import 'package:intl/intl.dart';

final _grouped = NumberFormat('#,##0', 'en_US');

/// Working volume: whole kg with thousands separators below 10,000 kg, tonnes with one decimal from there.
/// Used everywhere volume is shown.
String formatVolume(double kg) {
  if (kg.abs() < 10000) return '${_grouped.format(kg.round())} kg';
  return '${(kg / 1000).toStringAsFixed(1)} t';
}

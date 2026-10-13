import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/domain/gym.dart';
import '../../../core/theme/app_theme.dart';
import '../../coach/domain/suggestion_engine.dart';

enum KeypadField { kg, reps }

/// The cell the keypad is editing.
class KeypadTarget {
  const KeypadTarget(this.setId, this.field);
  final int setId;
  final KeypadField field;

  @override
  bool operator ==(Object other) => other is KeypadTarget && other.setId == setId && other.field == field;

  @override
  int get hashCode => Object.hash(setId, field);
}

/// Text being typed into a KG/REPS cell. Pure, so the keypad rules are unit-testable.
class KeypadBuffer {
  KeypadBuffer({required this.field, this.text = ''});

  final KeypadField field;
  String text;

  bool get isEmpty => text.isEmpty || text == '-';

  double? get value => isEmpty ? null : double.tryParse(text);

  void digit(String d) {
    if (field == KeypadField.reps && text.replaceAll('-', '').length >= 3) return;
    if (field == KeypadField.kg) {
      final dot = text.indexOf('.');
      if (dot >= 0 && text.length - dot > 2) return; // two decimals at most (1.25 plates)
    }
    text = text == '0' ? d : '$text$d';
  }

  void dot() {
    if (field == KeypadField.reps || text.contains('.')) return;
    text = isEmpty ? '${text == '-' ? '-' : ''}0.' : '$text.';
  }

  void backspace() {
    if (text.isNotEmpty) text = text.substring(0, text.length - 1);
  }

  /// ± one increment (kg) or one rep, starting from what's typed or [fallback] (the cell's value).
  /// ± on the keypad: reps by one; kg to the next / previous weight that exists ([grid]), else by
  /// [increment].
  void step(int direction, {required double increment, required double fallback, WeightGrid? grid}) {
    final base = value ?? fallback;
    if (field != KeypadField.kg) return set((base + direction).clamp(0, 999).toDouble());
    final g = grid == null ? null : (direction > 0 ? grid.next(base) : grid.previous(base));
    set(g ?? base + direction * increment);
  }

  void set(double v) {
    text = field == KeypadField.kg ? formatPlain(v) : '${v.round()}';
  }

  void toggleSign() {
    if (field != KeypadField.kg) return;
    text = text.startsWith('-') ? text.substring(1) : '-$text';
  }

  /// Exact value for storage: kg as typed (no display rounding).
  static String formatPlain(double v) {
    if (v == v.roundToDouble()) return v.toStringAsFixed(0);
    return v.toStringAsFixed(2).replaceFirst(RegExp(r'0+$'), '');
  }
}

/// Liftoff-style number pad for KG/REPS: digits, decimal point, backspace, ± equipment increment,
/// Copy (PREV or the set above), +/− sign for assisted lifts, NEXT (KG → REPS → next set) and hide.
class WorkoutKeypad extends StatelessWidget {
  const WorkoutKeypad({
    super.key,
    required this.field,
    required this.increment,
    required this.signToggle,
    required this.onDigit,
    required this.onDot,
    required this.onBackspace,
    required this.onStep,
    required this.onCopy,
    required this.onSign,
    required this.onNext,
    required this.onHide,
  });

  final KeypadField field;
  final double increment;
  final bool signToggle;
  final ValueChanged<String> onDigit;
  final VoidCallback onDot;
  final VoidCallback onBackspace;
  final ValueChanged<int> onStep;
  final VoidCallback onCopy;
  final VoidCallback onSign;
  final VoidCallback onNext;
  final VoidCallback onHide;

  @override
  Widget build(BuildContext context) {
    final inc = field == KeypadField.kg ? formatKg(increment) : '1';
    Widget key(String label, VoidCallback? onTap, {Key? k, bool accent = false, IconData? icon, bool dim = false}) => Expanded(
          child: Padding(
            padding: const EdgeInsets.all(3),
            child: Material(
              color: accent ? AppColors.primary : (dim ? AppColors.surfaceHigh : AppColors.surfaceTop),
              borderRadius: BorderRadius.circular(10),
              child: InkWell(
                key: k,
                borderRadius: BorderRadius.circular(10),
                onTap: onTap == null
                    ? null
                    : () {
                        HapticFeedback.selectionClick();
                        onTap();
                      },
                child: SizedBox(
                  height: 48,
                  child: Center(
                    child: icon != null
                        ? Icon(icon, color: accent ? const Color(0xFF06210F) : AppColors.textPrimary)
                        : Text(
                            label,
                            style: TextStyle(
                              fontFamily: AppType.display,
                              fontWeight: FontWeight.w700,
                              fontSize: label.length > 2 ? 15 : 22,
                              color: onTap == null ? AppColors.textTertiary : (accent ? const Color(0xFF06210F) : AppColors.textPrimary),
                            ),
                          ),
                  ),
                ),
              ),
            ),
          ),
        );
    Widget digit(String d) => key(d, () => onDigit(d), k: ValueKey('key-$d'));

    return Container(
      key: const ValueKey('workout-keypad'),
      color: AppColors.surface,
      padding: const EdgeInsets.fromLTRB(6, 6, 6, 4),
      child: SafeArea(
        top: false,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 3,
              child: Column(children: [
                Row(children: [digit('1'), digit('2'), digit('3')]),
                Row(children: [digit('4'), digit('5'), digit('6')]),
                Row(children: [digit('7'), digit('8'), digit('9')]),
                Row(children: [
                  key('.', field == KeypadField.kg ? onDot : null, k: const ValueKey('key-dot')),
                  digit('0'),
                  key('', onBackspace, icon: Icons.backspace_outlined, k: const ValueKey('key-backspace')),
                ]),
              ]),
            ),
            Expanded(
              flex: 2,
              child: Column(children: [
                Row(children: [
                  key('−$inc', () => onStep(-1), k: const ValueKey('key-minus-inc'), dim: true),
                  key('+$inc', () => onStep(1), k: const ValueKey('key-plus-inc'), dim: true),
                ]),
                Row(children: [
                  key('Copy', onCopy, k: const ValueKey('key-copy'), dim: true),
                  key('+/−', signToggle && field == KeypadField.kg ? onSign : null, k: const ValueKey('key-sign'), dim: true),
                ]),
                Row(children: [key('NEXT', onNext, k: const ValueKey('key-next'), accent: true)]),
                Row(children: [key('', onHide, icon: Icons.keyboard_hide_rounded, k: const ValueKey('key-hide'), dim: true)]),
              ]),
            ),
          ],
        ),
      ),
    );
  }
}

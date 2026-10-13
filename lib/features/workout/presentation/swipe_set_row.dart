import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';

/// iOS-style row gestures: swipe left reveals a red Delete action (a full swipe deletes at once, like Mail),
/// swipe right past a short distance fires [onSwipeRight] (complete the set) and springs back.
/// Only horizontal drags are claimed, so the page still scrolls vertically.
class SwipeSetRow extends StatefulWidget {
  const SwipeSetRow({super.key, required this.id, required this.child, required this.onDelete, this.onSwipeRight});

  final int id;
  final Widget child;
  final Future<void> Function() onDelete;
  final VoidCallback? onSwipeRight;

  @override
  State<SwipeSetRow> createState() => _SwipeSetRowState();
}

class _SwipeSetRowState extends State<SwipeSetRow> with SingleTickerProviderStateMixin {
  static const double _reveal = 88;
  late final AnimationController _c;
  double _width = 320;
  bool _busy = false;

  double get _dx => _c.value;

  @override
  void initState() {
    super.initState();
    _c = AnimationController.unbounded(vsync: this, duration: const Duration(milliseconds: 180));
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  Future<void> _animateTo(double target) async {
    await _c.animateTo(target, curve: Curves.easeOut);
  }

  void _onUpdate(DragUpdateDetails d) {
    if (_busy) return;
    // Left is negative; right travel is limited (it only triggers an action).
    _c.value = (_c.value + d.delta.dx).clamp(-_width, 90.0);
  }

  Future<void> _onEnd(DragEndDetails d) async {
    if (_busy) return;
    final v = d.primaryVelocity ?? 0;
    if (_dx <= -_width * 0.6 || (v < -1200 && _dx < -_reveal)) {
      _busy = true;
      await _animateTo(-_width);
      await widget.onDelete();
      if (mounted) {
        _c.value = 0;
        _busy = false;
      }
    } else if (_dx <= -_reveal * 0.5) {
      await _animateTo(-_reveal);
    } else if (_dx >= 56 && widget.onSwipeRight != null) {
      widget.onSwipeRight!();
      await _animateTo(0);
    } else {
      await _animateTo(0);
    }
  }

  Future<void> _tapDelete() async {
    if (_busy) return;
    _busy = true;
    await _animateTo(-_width);
    await widget.onDelete();
    if (mounted) {
      _c.value = 0;
      _busy = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, box) {
      _width = box.maxWidth;
      return GestureDetector(
        key: ValueKey('swipe-row-${widget.id}'),
        behavior: HitTestBehavior.translucent,
        onHorizontalDragUpdate: _onUpdate,
        onHorizontalDragEnd: _onEnd,
        child: ClipRect(
          child: AnimatedBuilder(
            animation: _c,
            builder: (context, child) {
              final dx = _dx;
              return Stack(children: [
                if (dx < 0)
                  Positioned.fill(
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: Container(
                        width: -dx,
                        margin: const EdgeInsets.symmetric(vertical: 2),
                        decoration: BoxDecoration(color: AppColors.danger, borderRadius: BorderRadius.circular(8)),
                        child: InkWell(
                          key: ValueKey('swipe-delete-${widget.id}'),
                          onTap: _tapDelete,
                          child: OverflowBox(
                            alignment: Alignment.center,
                            minWidth: 0,
                            maxWidth: _reveal,
                            child: const Column(mainAxisSize: MainAxisSize.min, children: [
                              Icon(Icons.delete_outline_rounded, color: Colors.white, size: 20),
                              Text('Delete', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700)),
                            ]),
                          ),
                        ),
                      ),
                    ),
                  ),
                if (dx > 0)
                  Positioned.fill(
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Container(
                        width: dx,
                        margin: const EdgeInsets.symmetric(vertical: 2),
                        decoration: BoxDecoration(color: AppColors.primary, borderRadius: BorderRadius.circular(8)),
                        child: const ClipRect(child: OverflowBox(alignment: Alignment.center, minWidth: 0, maxWidth: 40, child: Icon(Icons.check_rounded, color: Color(0xFF06210F)))),
                      ),
                    ),
                  ),
                Transform.translate(offset: Offset(dx, 0), child: child),
              ]);
            },
            child: widget.child,
          ),
        ),
      );
    });
  }
}

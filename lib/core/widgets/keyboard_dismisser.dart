import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// App-wide: the software keyboard goes away when you tap anywhere outside the text field that has it, or
/// start scrolling a list (dismiss on drag). Wrap the app once, above the navigator.
///
/// Taps are told apart from drags by their travel, and "outside" means outside the whole field (its decoration,
/// clear button and all), so tapping a field's own icons never drops the keyboard.
class KeyboardDismisser extends StatefulWidget {
  const KeyboardDismisser({super.key, required this.child});
  final Widget child;

  @override
  State<KeyboardDismisser> createState() => _KeyboardDismisserState();
}

class _KeyboardDismisserState extends State<KeyboardDismisser> {
  Offset? _down;

  /// The text field that has the focus now, if any.
  static EditableTextState? _focusedEditable() {
    final ctx = FocusManager.instance.primaryFocus?.context;
    if (ctx == null) return null;
    if (ctx is StatefulElement && ctx.state is EditableTextState) return ctx.state as EditableTextState;
    return ctx.findAncestorStateOfType<EditableTextState>();
  }

  /// Screen rect of the whole field: its InputDecorator when it has one, else the editable text.
  static Rect? _fieldRect(EditableTextState editable) {
    RenderBox? box;
    editable.context.visitAncestorElements((e) {
      if (e.widget is InputDecorator) {
        box = e.renderObject as RenderBox?;
        return false;
      }
      return true;
    });
    box ??= editable.context.findRenderObject() as RenderBox?;
    if (box == null || !box!.hasSize || !box!.attached) return null;
    return box!.localToGlobal(Offset.zero) & box!.size;
  }

  void _onPointerUp(PointerUpEvent e) {
    final down = _down;
    _down = null;
    if (down == null || (e.position - down).distance > kTouchSlop) return; // a drag, not a tap
    final editable = _focusedEditable();
    if (editable == null) return;
    final rect = _fieldRect(editable);
    if (rect != null && rect.inflate(2).contains(e.position)) return;
    FocusManager.instance.primaryFocus?.unfocus();
  }

  bool _onScroll(ScrollNotification n) {
    // A finger dragging a list (not the text field's own scrolling) puts the keyboard away.
    if (n is ScrollStartNotification && n.dragDetails != null) {
      final editable = _focusedEditable();
      final inField = n.context?.findAncestorStateOfType<EditableTextState>() != null;
      if (editable != null && !inField) FocusManager.instance.primaryFocus?.unfocus();
    }
    return false;
  }

  @override
  Widget build(BuildContext context) => NotificationListener<ScrollNotification>(
        onNotification: _onScroll,
        child: Listener(
          behavior: HitTestBehavior.translucent,
          onPointerDown: (e) => _down = e.position,
          onPointerUp: _onPointerUp,
          onPointerCancel: (_) => _down = null,
          child: widget.child,
        ),
      );
}

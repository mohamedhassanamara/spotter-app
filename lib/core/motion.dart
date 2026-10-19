import 'package:flutter/material.dart';

/// True when the person asked the system for less motion (iOS Reduce Motion): every animation in the app then jumps to its end.
bool reduceMotion(BuildContext context) => MediaQuery.maybeDisableAnimationsOf(context) ?? false;

/// [d], or zero under Reduce Motion.
Duration motion(BuildContext context, Duration d) => reduceMotion(context) ? Duration.zero : d;

/// Fade + slide-up entrance for list items, [index] x 40 ms apart (capped at 10 so a long list never waits). Plays once, when the item is first built.
class FadeSlideIn extends StatelessWidget {
  const FadeSlideIn({super.key, required this.index, required this.child});
  final int index;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (reduceMotion(context)) return child;
    final delay = index.clamp(0, 10) * 40;
    final total = delay + 280;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: total),
      builder: (context, v, child) {
        final t = Curves.easeOutCubic.transform(((v * total - delay) / 280).clamp(0.0, 1.0));
        return Opacity(opacity: t, child: Transform.translate(offset: Offset(0, (1 - t) * 14), child: child));
      },
      child: child,
    );
  }
}

/// Page transitions of the platform, skipped under Reduce Motion.
class ReduceMotionTransitions extends PageTransitionsBuilder {
  const ReduceMotionTransitions(this.inner);
  final PageTransitionsBuilder inner;

  @override
  Widget buildTransitions<T>(PageRoute<T> route, BuildContext context, Animation<double> animation, Animation<double> secondaryAnimation, Widget child) =>
      reduceMotion(context) ? child : inner.buildTransitions<T>(route, context, animation, secondaryAnimation, child);
}

/// The bottom-bar tabs: every branch keeps its state (like an IndexedStack) and the tab you switch to fades in.
class FadeBranches extends StatefulWidget {
  const FadeBranches({super.key, required this.currentIndex, required this.children});
  final int currentIndex;
  final List<Widget> children;

  @override
  State<FadeBranches> createState() => _FadeBranchesState();
}

class _FadeBranchesState extends State<FadeBranches> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 180), value: 1);

  @override
  void didUpdateWidget(FadeBranches old) {
    super.didUpdateWidget(old);
    if (old.currentIndex != widget.currentIndex && !reduceMotion(context)) _c.forward(from: 0);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Stack(
        fit: StackFit.expand,
        children: [
          for (var i = 0; i < widget.children.length; i++)
            Offstage(
              offstage: i != widget.currentIndex,
              child: TickerMode(
                enabled: i == widget.currentIndex,
                // The same widget chain for every tab, so a tab keeps its state when it is hidden.
                child: FadeTransition(opacity: i == widget.currentIndex ? _c : const AlwaysStoppedAnimation<double>(1), child: widget.children[i]),
              ),
            ),
        ],
      );
}

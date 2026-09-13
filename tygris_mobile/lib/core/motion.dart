import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/services.dart';

/// Spring physics tokens — real mass/stiffness/damping simulations, not
/// duration-based curves. Use via [AppSpring.drive] with an
/// AnimationController, or reach for the simpler [PressableScale] /
/// [SpringEntry] widgets below for the common cases.
class AppSpring {
  AppSpring._();

  /// Snappy, slightly bouncy — buttons, chips, toggles.
  static const snappy = SpringDescription(mass: 1, stiffness: 380, damping: 24);

  /// Weightier settle — cards entering, sheets rising.
  static const settle = SpringDescription(mass: 1, stiffness: 220, damping: 26);

  /// Gentle, gliding — large surfaces, hero elements.
  static const gentle = SpringDescription(mass: 1.1, stiffness: 140, damping: 22);

  static Future<void> drive(
    AnimationController controller,
    SpringDescription spring, {
    double from = 0,
    double to = 1,
    double velocity = 0,
  }) {
    controller.value = from;
    return controller
        .animateWith(SpringSimulation(spring, from, to, velocity))
        .orCancel
        .catchError((_) {});
  }
}

/// Wraps [child] with a tactile press response: scale-down on tap-down via
/// a spring simulation (not a fixed-duration tween) plus a paired haptic
/// tick, mirroring the "haptic + spring visual response fire together"
/// recipe for a premium native feel. Use for any primary tappable surface
/// — cards, list rows, icon buttons — in place of bare InkWell/GestureDetector.
class PressableScale extends StatefulWidget {
  const PressableScale({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.scaleDown = 0.965,
    this.haptic = true,
    this.borderRadius,
  });

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final double scaleDown;
  final bool haptic;
  final BorderRadius? borderRadius;

  @override
  State<PressableScale> createState() => _PressableScaleState();
}

class _PressableScaleState extends State<PressableScale>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    lowerBound: 0,
    upperBound: 1,
    value: 0,
  );

  late final Animation<double> _scale = _controller.drive(
    Tween(begin: 1.0, end: widget.scaleDown),
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDown(TapDownDetails _) {
    if (widget.onTap == null && widget.onLongPress == null) return;
    AppSpring.drive(_controller, AppSpring.snappy, from: _controller.value, to: 1);
  }

  void _onUp([TapUpDetails? _]) {
    AppSpring.drive(_controller, AppSpring.snappy, from: _controller.value, to: 0);
  }

  void _handleTap() {
    if (widget.onTap == null) return;
    if (widget.haptic) HapticFeedback.lightImpact();
    widget.onTap!();
  }

  void _handleLongPress() {
    if (widget.onLongPress == null) return;
    if (widget.haptic) HapticFeedback.mediumImpact();
    widget.onLongPress!();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: _onDown,
      onTapUp: _onUp,
      onTapCancel: _onUp,
      onTap: widget.onTap == null ? null : _handleTap,
      onLongPress: widget.onLongPress == null ? null : _handleLongPress,
      child: AnimatedBuilder(
        animation: _scale,
        builder: (context, child) =>
            Transform.scale(scale: _scale.value, child: child),
        child: widget.child,
      ),
    );
  }
}

/// Heavy fade-up entrance for a single element — the scroll-interpolation
/// choreography from the design bible, minus a blur pass (BackdropFilter on
/// scrolling content is a known Flutter perf trap; opacity+translate alone
/// reads as "heavy" entrance without the repaint cost).
class SpringEntry extends StatefulWidget {
  const SpringEntry({
    super.key,
    required this.child,
    this.delay = Duration.zero,
    this.offset = 28,
  });

  final Widget child;
  final Duration delay;
  final double offset;

  @override
  State<SpringEntry> createState() => _SpringEntryState();
}

class _SpringEntryState extends State<SpringEntry>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller =
      AnimationController(vsync: this, value: 0);

  @override
  void initState() {
    super.initState();
    Future.delayed(widget.delay, () {
      if (!mounted) return;
      AppSpring.drive(_controller, AppSpring.settle, from: 0, to: 1);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final t = _controller.value.clamp(0.0, 1.0);
        return Opacity(
          opacity: t,
          child: Transform.translate(
            offset: Offset(0, widget.offset * (1 - t)),
            child: child,
          ),
        );
      },
      child: widget.child,
    );
  }
}

/// Staggered delay helper for lists of [SpringEntry] — caps the total stagger
/// so a long list doesn't take seconds to finish appearing.
Duration staggerDelay(int index, {int cap = 8, int msPerItem = 45}) {
  return Duration(milliseconds: msPerItem * index.clamp(0, cap));
}

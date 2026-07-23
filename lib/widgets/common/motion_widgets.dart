import 'package:flutter/material.dart';

/// Fade + slide entrance — use for staggered list/card reveals.
class FadeSlideIn extends StatefulWidget {
  const FadeSlideIn({
    super.key,
    required this.child,
    this.delay = Duration.zero,
    this.duration = const Duration(milliseconds: 520),
    this.offset = const Offset(0, 0.04),
    this.curve = Curves.easeOutCubic,
  });

  final Widget child;
  final Duration delay;
  final Duration duration;
  final Offset offset;
  final Curve curve;

  @override
  State<FadeSlideIn> createState() => _FadeSlideInState();
}

class _FadeSlideInState extends State<FadeSlideIn>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fade;
  late final Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: widget.duration);
    _fade = CurvedAnimation(parent: _controller, curve: widget.curve);
    _slide = Tween<Offset>(begin: widget.offset, end: Offset.zero).animate(
      CurvedAnimation(parent: _controller, curve: widget.curve),
    );
    Future<void>.delayed(widget.delay, () {
      if (mounted) _controller.forward();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fade,
      child: SlideTransition(position: _slide, child: widget.child),
    );
  }
}

/// Staggers [children] with incremental delay.
class StaggerColumn extends StatelessWidget {
  const StaggerColumn({
    super.key,
    required this.children,
    this.interval = const Duration(milliseconds: 70),
    this.itemDuration = const Duration(milliseconds: 520),
    this.crossAxisAlignment = CrossAxisAlignment.start,
  });

  final List<Widget> children;
  final Duration interval;
  final Duration itemDuration;
  final CrossAxisAlignment crossAxisAlignment;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: crossAxisAlignment,
      children: [
        for (var i = 0; i < children.length; i++)
          FadeSlideIn(
            delay: interval * i,
            duration: itemDuration,
            child: children[i],
          ),
      ],
    );
  }
}

/// Gentle pulsing glow for accent elements.
class PulseGlow extends StatefulWidget {
  const PulseGlow({
    super.key,
    required this.child,
    required this.color,
    this.minOpacity = 0.04,
    this.maxOpacity = 0.14,
  });

  final Widget child;
  final Color color;
  final double minOpacity;
  final double maxOpacity;

  @override
  State<PulseGlow> createState() => _PulseGlowState();
}

class _PulseGlowState extends State<PulseGlow> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    )..repeat(reverse: true);
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
        final t = widget.minOpacity +
            (widget.maxOpacity - widget.minOpacity) * _controller.value;
        return Container(
          decoration: BoxDecoration(
            boxShadow: [
              BoxShadow(
                color: widget.color.withValues(alpha: t),
                blurRadius: 28,
                spreadRadius: 4,
              ),
            ],
          ),
          child: child,
        );
      },
      child: widget.child,
    );
  }
}

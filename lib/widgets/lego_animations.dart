import 'package:flutter/material.dart';

/// A wrapper that adds a "lego piece snapping into place" effect.
/// It uses a staggered delay and an elastic overshoot scale animation.
class LegoPop extends StatefulWidget {
  final Widget child;
  final int index;
  final Duration delay;

  const LegoPop({
    super.key,
    required this.child,
    this.index = 0,
    this.delay = const Duration(milliseconds: 50),
  });

  @override
  State<LegoPop> createState() => _LegoPopState();
}

class _LegoPopState extends State<LegoPop> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  late Animation<double> _opacityAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400), // Speed up from 600ms
    );

    _scaleAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: Curves.elasticOut,
      ),
    );

    _opacityAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.0, 0.5, curve: Curves.easeOut),
      ),
    );

    Future.delayed(const Duration(milliseconds: 30) * widget.index, () { // Speed up delay from 50ms
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
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Opacity(
          opacity: _opacityAnimation.value,
          child: Transform.scale(
            scale: _scaleAnimation.value,
            child: child,
          ),
        );
      },
      child: widget.child,
    );
  }
}

/// A wrapper that makes any button feel "springy" when pressed.
class SpringyButton extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  const SpringyButton({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
  });

  @override
  State<SpringyButton> createState() => _SpringyButtonState();
}

class _SpringyButtonState extends State<SpringyButton> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 100),
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: 0.92).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => _controller.forward(),
      onTapUp: (_) => _controller.reverse(),
      onTapCancel: () => _controller.reverse(),
      onTap: widget.onTap,
      onLongPress: widget.onLongPress,
      child: ScaleTransition(
        scale: _scaleAnimation,
        child: widget.child,
      ),
    );
  }
}

/// A custom transition that simulates a "rebuilding" effect.
class LegoBuildTransition extends StatelessWidget {
  final Animation<double> animation;
  final Widget child;

  const LegoBuildTransition({
    super.key,
    required this.animation,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      builder: (context, child) {
        // The Lego build effect involves pieces scaling and dropping in.
        // We'll simulate this with a staggered-like scale and translate.
        final value = animation.value;
        final scale = Curves.elasticOut.transform(value).clamp(0.0, 1.0);
        final opacity = Curves.easeIn.transform(value);
        final offset = (1.0 - value) * 50.0;

        return Opacity(
          opacity: opacity,
          child: Transform.translate(
            offset: Offset(0, offset),
            child: Transform.scale(
              scale: scale,
              child: child,
            ),
          ),
        );
      },
      child: child,
    );
  }
}

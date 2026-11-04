import 'dart:async';

import 'package:flutter/material.dart';

class FrontBackHeatmapFade extends StatefulWidget {
  final Widget front;
  final Widget back;

  const FrontBackHeatmapFade({
    super.key,
    required this.front,
    required this.back,
  });

  @override
  State<FrontBackHeatmapFade> createState() => _FrontBackHeatmapFadeState();
}

class _FrontBackHeatmapFadeState extends State<FrontBackHeatmapFade> {
  static const _fadeDuration = Duration(milliseconds: 1200);
  static const _faceDuration = Duration(seconds: 5);

  late final Timer _timer;
  bool _showFront = true;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(_faceDuration, (_) {
      if (mounted) setState(() => _showFront = !_showFront);
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedCrossFade(
        firstChild: widget.front,
        secondChild: widget.back,
        crossFadeState:
            _showFront ? CrossFadeState.showFirst : CrossFadeState.showSecond,
        duration: _fadeDuration,
        firstCurve: Curves.easeInOut,
        secondCurve: Curves.easeInOut,
        sizeCurve: Curves.linear,
      );
}

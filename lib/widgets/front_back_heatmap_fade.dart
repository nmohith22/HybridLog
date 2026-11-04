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
  static const _fadeDuration = Duration(milliseconds: 600);
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
  Widget build(BuildContext context) => Stack(
        alignment: Alignment.center,
        children: [
          AnimatedOpacity(
            opacity: _showFront ? 1 : 0,
            duration: _fadeDuration,
            curve: Curves.easeInOut,
            child: IgnorePointer(ignoring: !_showFront, child: widget.front),
          ),
          AnimatedOpacity(
            opacity: _showFront ? 0 : 1,
            duration: _fadeDuration,
            curve: Curves.easeInOut,
            child: IgnorePointer(ignoring: _showFront, child: widget.back),
          ),
        ],
      );
}

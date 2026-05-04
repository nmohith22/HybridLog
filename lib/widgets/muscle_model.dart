import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

class MuscleModel extends StatelessWidget {
  final List<String> activatedMuscles;
  final bool isFront;
  final double height;
  final Color? baseColor;
  final Color? highlightColor;

  const MuscleModel({
    super.key,
    required this.activatedMuscles,
    this.isFront = true,
    this.height = 200,
    this.baseColor,
    this.highlightColor,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final effectiveBaseColor = baseColor ?? theme.colorScheme.surfaceContainerHighest;
    final effectiveHighlightColor = highlightColor ?? theme.colorScheme.primary;

    return SizedBox(
      height: height,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Base Body Layer
          SvgPicture.asset(
            isFront ? 'assets/body_front_base.svg' : 'assets/body_back_base.svg',
            colorFilter: ColorFilter.mode(effectiveBaseColor, BlendMode.srcIn),
            fit: BoxFit.contain,
          ),
          
          // Activated Muscles Layers
          ...activatedMuscles.map((muscle) {
            final assetPath = isFront ? 'assets/front_$muscle.svg' : 'assets/back_$muscle.svg';
            return SvgPicture.asset(
              assetPath,
              colorFilter: ColorFilter.mode(effectiveHighlightColor, BlendMode.srcIn),
              fit: BoxFit.contain,
              // If the asset doesn't exist, it will just show nothing or log an error.
              // We could add a check here if we wanted to be safer.
            );
          }),
        ],
      ),
    );
  }
}

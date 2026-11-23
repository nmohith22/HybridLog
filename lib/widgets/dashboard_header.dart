import 'package:flutter/material.dart';
import 'lego_animations.dart';

class DashboardHeader extends StatelessWidget {
  final String title;
  final VoidCallback onSettings;
  final VoidCallback? onNavigate;
  final bool running;
  final Key? navigationKey;
  final Key? settingsKey;

  const DashboardHeader({
    super.key,
    required this.title,
    required this.onSettings,
    this.onNavigate,
    this.running = false,
    this.navigationKey,
    this.settingsKey,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget action(Key? key, String label, IconData icon, VoidCallback onTap) =>
        Tooltip(
          message: label,
          child: Semantics(
            button: true,
            child: SpringyButton(
              key: key,
              onTap: onTap,
              child: Container(
                width: 48,
                height: 48,
                decoration: ShapeDecoration(
                  color: theme.colorScheme.surface,
                  shape: CircleBorder(
                      side:
                          BorderSide(color: theme.colorScheme.outlineVariant)),
                ),
                child: Icon(icon, size: 22, color: theme.colorScheme.onSurface),
              ),
            ),
          ),
        );
    return Row(children: [
      Expanded(
          child: Semantics(
              header: true,
              child: Text(title, style: theme.textTheme.headlineMedium))),
      const SizedBox(width: 8),
      action(settingsKey, 'Settings', Icons.tune_rounded, onSettings),
      if (onNavigate != null) ...[
        const SizedBox(width: 8),
        action(
            navigationKey,
            running ? 'Go to workouts' : 'Go to running log',
            running ? Icons.chevron_right_rounded : Icons.chevron_left_rounded,
            onNavigate!),
      ],
    ]);
  }
}

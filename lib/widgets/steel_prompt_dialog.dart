import 'package:flutter/material.dart';

import '../services/theme_service.dart';

class SteelPromptDialog extends StatelessWidget {
  const SteelPromptDialog({super.key});

  static Future<String?> show(BuildContext context) => showDialog<String>(
        context: context,
        builder: (_) => const SteelPromptDialog(),
      );

  @override
  Widget build(BuildContext context) {
    final theme = ThemeService().getResolvedTheme(context);
    const prompts = [
      (
        'plan',
        Icons.fitness_center,
        'Build a workout',
        'Use my recent training and equipment.',
      ),
      (
        'log',
        Icons.edit_note,
        'Log a workout',
        'Turn my notes into a draft I can review.',
      ),
      (
        'history',
        Icons.manage_search,
        'Ask about my history',
        'Find past workouts, exercises, or weights.',
      ),
      (
        'recap',
        Icons.insights,
        'Summarize my week',
        'Review my training and progress.',
      ),
    ];

    return Dialog(
      backgroundColor: theme.card,
      insetPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 500),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(children: [
                Icon(Icons.auto_awesome, color: theme.accent),
                const SizedBox(width: 10),
                Expanded(
                  child: Text('Steel',
                      style: TextStyle(
                          color: theme.text,
                          fontSize: 19,
                          fontWeight: FontWeight.bold)),
                ),
                IconButton(
                  tooltip: 'Close',
                  onPressed: () => Navigator.pop(context),
                  icon: Icon(Icons.close, color: theme.subText),
                ),
              ]),
              Align(
                alignment: Alignment.centerLeft,
                child: Container(
                  constraints: const BoxConstraints(maxWidth: 360),
                  padding: const EdgeInsets.all(13),
                  decoration: BoxDecoration(
                    color: theme.background,
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(4),
                      topRight: Radius.circular(16),
                      bottomLeft: Radius.circular(16),
                      bottomRight: Radius.circular(16),
                    ),
                  ),
                  child: Text(
                    'Hey, what would you like help with? Choose a prompt to get started.',
                    style: TextStyle(color: theme.text, fontSize: 13),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text('SUGGESTED PROMPTS',
                  style: TextStyle(
                      color: theme.subText,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1)),
              const SizedBox(height: 8),
              ...prompts.map((prompt) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Material(
                      color: theme.background,
                      borderRadius: BorderRadius.circular(14),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(14),
                        onTap: () => Navigator.pop(context, prompt.$1),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 13, vertical: 11),
                          child: Row(children: [
                            Icon(prompt.$2, color: theme.accent, size: 20),
                            const SizedBox(width: 11),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(prompt.$3,
                                      style: TextStyle(
                                          color: theme.text,
                                          fontWeight: FontWeight.w600,
                                          fontSize: 13)),
                                  const SizedBox(height: 2),
                                  Text(prompt.$4,
                                      style: TextStyle(
                                          color: theme.subText, fontSize: 11)),
                                ],
                              ),
                            ),
                            Icon(Icons.arrow_forward_ios,
                                color: theme.subText, size: 13),
                          ]),
                        ),
                      ),
                    ),
                  )),
              const SizedBox(height: 3),
              Text('Your workout data stays on this device.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: theme.subText, fontSize: 10)),
            ],
          ),
        ),
      ),
    );
  }
}

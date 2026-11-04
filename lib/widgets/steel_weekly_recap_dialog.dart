import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../services/steel_insights_service.dart';
import '../services/theme_service.dart';

class SteelWeeklyRecapDialog extends StatefulWidget {
  const SteelWeeklyRecapDialog({super.key});

  @override
  State<SteelWeeklyRecapDialog> createState() => _SteelWeeklyRecapDialogState();
}

class _SteelWeeklyRecapDialogState extends State<SteelWeeklyRecapDialog> {
  WeeklyTrainingRecap? _recap;
  String? _error;
  AppTheme get _theme => ThemeService().getResolvedTheme(context);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final recap = await SteelInsightsService.weeklyRecap();
      if (mounted) setState(() => _recap = recap);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'I couldn’t prepare this week’s recap.');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = _theme;
    final recap = _recap;
    final end = recap?.weekStart.add(const Duration(days: 6));
    return AlertDialog(
      backgroundColor: theme.card,
      title: Text('Weekly training recap', style: TextStyle(color: theme.text)),
      content: SizedBox(
        width: 460,
        child: recap == null
            ? _error == null
                ? const Center(child: CircularProgressIndicator())
                : Text(_error!, style: TextStyle(color: theme.subText))
            : SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '${DateFormat('MMM d').format(recap.weekStart)} – ${DateFormat('MMM d').format(end!)}',
                      style: TextStyle(color: theme.subText, fontSize: 12),
                    ),
                    const SizedBox(height: 8),
                    Text(recap.recap,
                        style: TextStyle(
                            color: theme.text,
                            fontSize: 15,
                            fontWeight: FontWeight.w500)),
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _stat('${recap.workouts}', 'workouts', theme),
                        _stat('${recap.exercises}', 'exercises', theme),
                        _stat('${recap.sets}', 'sets', theme),
                        _stat('${recap.reps}', 'reps', theme),
                        if (recap.volume > 0)
                          _stat('${recap.volume.round()}', 'lb-reps', theme),
                      ],
                    ),
                    if (recap.mostTrainedMuscles.isNotEmpty) ...[
                      const SizedBox(height: 14),
                      Text('MOST TRAINED',
                          style: TextStyle(
                              color: theme.subText,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1)),
                      const SizedBox(height: 4),
                      Text(
                        recap.mostTrainedMuscles
                            .map((entry) => entry.key.replaceAll('_', ' '))
                            .join(' · '),
                        style: TextStyle(color: theme.text, fontSize: 13),
                      ),
                    ],
                    if (recap.comparedExercises > 0) ...[
                      const SizedBox(height: 8),
                      Text(
                        '${recap.improvedExercises} of ${recap.comparedExercises} repeated exercises increased in top logged weight versus last week.',
                        style: TextStyle(color: theme.subText, fontSize: 12),
                      ),
                    ],
                  ],
                ),
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text('Close', style: TextStyle(color: theme.subText)),
        ),
      ],
    );
  }

  Widget _stat(String value, String label, AppTheme theme) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
            color: theme.background, borderRadius: BorderRadius.circular(10)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(value,
                style: TextStyle(
                    color: theme.text,
                    fontSize: 16,
                    fontWeight: FontWeight.bold)),
            Text(label, style: TextStyle(color: theme.subText, fontSize: 10)),
          ],
        ),
      );
}

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../services/needle_workout_service.dart';
import '../services/steel_insights_service.dart';
import '../services/theme_service.dart';
import '../utils/weight_reps_format.dart';

class SteelHistoryQuestionDialog extends StatefulWidget {
  const SteelHistoryQuestionDialog({super.key});

  @override
  State<SteelHistoryQuestionDialog> createState() =>
      _SteelHistoryQuestionDialogState();
}

class _SteelHistoryQuestionDialogState
    extends State<SteelHistoryQuestionDialog> {
  final _question = TextEditingController();
  bool _working = false;
  int _loaded = 0;
  int _total = -1;
  WorkoutHistoryAnswer? _result;
  String? _error;

  AppTheme get _theme => ThemeService().getResolvedTheme(context);

  @override
  void dispose() {
    _question.dispose();
    super.dispose();
  }

  Future<void> _ask() async {
    if (_working || _question.text.trim().isEmpty) return;
    setState(() {
      _working = true;
      _error = null;
      _result = null;
      _loaded = 0;
      _total = -1;
    });
    try {
      await NeedleWorkoutService.ensureReady(onProgress: (loaded, total) {
        if (mounted)
          setState(() {
            _loaded = loaded;
            _total = total;
          });
      });
      final result =
          await SteelInsightsService.askWorkoutHistory(_question.text.trim());
      if (mounted) setState(() => _result = result);
    } catch (error) {
      if (mounted)
        setState(() => _error = error is FormatException
            ? error.message.toString()
            : 'I couldn’t search your workout history. Try a more specific exercise name.');
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = _theme;
    return AlertDialog(
      backgroundColor: theme.card,
      title:
          Text('Ask my workout history', style: TextStyle(color: theme.text)),
      content: SizedBox(
        width: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
                'Steel answers from logged workouts on this device and shows the matching sessions below.',
                style: TextStyle(color: theme.subText, fontSize: 12)),
            const SizedBox(height: 10),
            TextField(
              controller: _question,
              enabled: !_working,
              onChanged: (_) => setState(() {}),
              style: TextStyle(color: theme.text),
              decoration: InputDecoration(
                hintText: 'What did I squat last time?',
                hintStyle: TextStyle(color: theme.subText),
                filled: true,
                fillColor: theme.background,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none),
              ),
              onSubmitted: (_) => _ask(),
            ),
            if (_working) ...[
              const SizedBox(height: 12),
              LinearProgressIndicator(
                value: _total > 0 ? (_loaded / _total).clamp(0, 1) : null,
                color: theme.accent,
                backgroundColor: theme.background,
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(_error!,
                  style: TextStyle(color: theme.accent, fontSize: 12)),
            ],
            if (_result != null) ...[
              const SizedBox(height: 12),
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(_result!.answer,
                          style: TextStyle(color: theme.text, fontSize: 14)),
                      const SizedBox(height: 12),
                      ..._result!.sources.take(12).map((workout) => Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                  color: theme.background,
                                  borderRadius: BorderRadius.circular(10)),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(DateFormat('EEE, MMM d, yyyy')
                                      .format(workout.date)),
                                  ...workout.exercises
                                      .where((exercise) => _result!
                                          .exerciseNames
                                          .contains(exercise.exerciseName))
                                      .map((exercise) => Text(
                                            '${exercise.exerciseName}: ${exercise.sets.map((set) => formatWeightReps(set.weight, set.reps)).join(', ')}',
                                            style: TextStyle(
                                                color: theme.subText,
                                                fontSize: 11),
                                          )),
                                ],
                              ),
                            ),
                          )),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: _working ? null : () => Navigator.pop(context),
            child: Text('Close', style: TextStyle(color: theme.subText))),
        FilledButton(
          onPressed: _working || _question.text.trim().isEmpty ? null : _ask,
          style: FilledButton.styleFrom(backgroundColor: theme.accent),
          child: Text('Ask Steel', style: TextStyle(color: theme.background)),
        ),
      ],
    );
  }
}

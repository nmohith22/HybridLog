import 'package:flutter/material.dart';
import 'package:isar/isar.dart';

import '../models/fitness_schema.dart';
import '../services/database_service.dart';
import '../services/needle_workout_service.dart';
import '../services/theme_service.dart';

class SteelLogDraftDialog extends StatefulWidget {
  const SteelLogDraftDialog({super.key});

  @override
  State<SteelLogDraftDialog> createState() => _SteelLogDraftDialogState();
}

class _SteelLogDraftDialogState extends State<SteelLogDraftDialog> {
  final _request = TextEditingController();
  bool _working = false;
  int _loaded = 0;
  int _total = -1;
  String? _error;

  AppTheme get _theme => ThemeService().getResolvedTheme(context);

  @override
  void dispose() {
    _request.dispose();
    super.dispose();
  }

  Future<void> _createDraft() async {
    if (_working || _request.text.trim().isEmpty) return;
    setState(() {
      _working = true;
      _error = null;
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
      await NeedleWorkoutService.resetConversation();
      final db = await DatabaseService().database;
      final exercises = await db.exercises.where().sortByName().findAll();
      final draft = await NeedleWorkoutService.parseWorkoutLog(
          _request.text.trim(), exercises);
      if (mounted) Navigator.of(context).pop(draft);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _working = false;
        _error = error is FormatException
            ? error.message.toString()
            : error.toString().contains('UnsupportedError')
                ? 'Steel needs a supported ARM Android device. You can still enter sets in the usual logger.'
                : 'I couldn’t read that workout yet. Include an exercise name and the weight and reps for each set.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = _theme;
    return AlertDialog(
      backgroundColor: theme.card,
      title:
          Text('Log a workout with Steel', style: TextStyle(color: theme.text)),
      content: SizedBox(
        width: 460,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
                'Describe one exercise and its sets. Steel will prepare a draft; nothing is saved until you review it in the logger.',
                style: TextStyle(color: theme.subText, fontSize: 13)),
            const SizedBox(height: 12),
            TextField(
              controller: _request,
              minLines: 2,
              maxLines: 4,
              enabled: !_working,
              style: TextStyle(color: theme.text),
              decoration: InputDecoration(
                hintText: 'Bench press, 135 pounds: 10, 9, 8',
                hintStyle: TextStyle(color: theme.subText),
                filled: true,
                fillColor: theme.background,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none),
              ),
              onChanged: (_) => setState(() {}),
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
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _working ? null : () => Navigator.pop(context),
          child: Text('Cancel', style: TextStyle(color: theme.subText)),
        ),
        FilledButton(
          onPressed:
              _working || _request.text.trim().isEmpty ? null : _createDraft,
          style: FilledButton.styleFrom(backgroundColor: theme.accent),
          child:
              Text('Review draft', style: TextStyle(color: theme.background)),
        ),
      ],
    );
  }
}

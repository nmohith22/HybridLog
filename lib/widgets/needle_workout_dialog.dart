import 'package:flutter/material.dart';
import 'package:isar/isar.dart';

import '../models/fitness_schema.dart';
import '../services/database_service.dart';
import '../services/needle_workout_service.dart';
import '../services/theme_service.dart';
import 'needle_data_dialog.dart';

class NeedleWorkoutDialog extends StatefulWidget {
  final Map<String, double> fatigue;
  final VoidCallback? onDataChanged;

  const NeedleWorkoutDialog({
    super.key,
    required this.fatigue,
    this.onDataChanged,
  });

  @override
  State<NeedleWorkoutDialog> createState() => _NeedleWorkoutDialogState();
}

class _NeedleWorkoutDialogState extends State<NeedleWorkoutDialog> {
  static const _splits = [
    'Push',
    'Pull',
    'Legs',
    'Upper',
    'Lower',
    'Fullbody',
    'Shoulders',
    'Arms',
    'Shoulders and Arms',
    'Back',
    'Chest',
    'Chest and Back',
    'Posterior',
    'Anterior',
  ];

  final _folderController = TextEditingController();
  final _selectedSplits = <String>{'Fullbody'};
  final _unavailable = <String>{};
  List<Exercise> _plan = [];
  bool _includeNew = true;
  bool _working = false;
  int _received = 0;
  int _total = -1;
  String? _error;

  AppTheme get _theme => ThemeService().getResolvedTheme(context);

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _folderController.text = 'Steel Workout ${now.month}/${now.day}';
  }

  @override
  void dispose() {
    _folderController.dispose();
    super.dispose();
  }

  Future<void> _generate({bool revise = false}) async {
    if (_selectedSplits.isEmpty || _working) return;
    setState(() {
      _working = true;
      _error = null;
      _received = 0;
      _total = -1;
    });
    try {
      await NeedleWorkoutService.ensureReady(onProgress: (received, total) {
        if (mounted)
          setState(() {
            _received = received;
            _total = total;
          });
      });
      if (!revise) await NeedleWorkoutService.resetConversation();
      final db = await DatabaseService().database;
      final exercises = await db.exercises.where().findAll();
      final history = await db.dailyWorkouts.where().sortByDateDesc().findAll();
      final plan = await NeedleWorkoutService.generate(
        exercises: exercises,
        history: history,
        splits: _selectedSplits.toList(),
        includeNewExercises: _includeNew,
        fatigue: widget.fatigue,
        unavailable: _unavailable,
        currentPlan: revise ? _plan : const [],
      );
      if (!mounted) return;
      setState(() {
        _plan = plan;
        _working = false;
        _unavailable.clear();
      });
      if (plan.isEmpty)
        setState(() => _error =
            'Steel couldn’t find enough matching exercises. Try another workout focus or include new exercises.');
    } catch (error) {
      if (mounted)
        setState(() {
          _working = false;
          _error = error.toString().contains('UnsupportedError')
              ? 'Steel needs a supported ARM Android device. Your workout data is still available in HybridLog.'
              : 'I couldn’t put together that plan. Try another workout focus or check your exercise library.';
        });
    }
  }

  Future<void> _save() async {
    final folderName = _folderController.text.trim();
    if (folderName.isEmpty || _plan.isEmpty) return;
    final db = await DatabaseService().database;
    await db.writeTxn(() async {
      final folder =
          await db.workoutFolders.filter().nameEqualTo(folderName).findFirst();
      if (folder == null)
        await db.workoutFolders.put(WorkoutFolder()..name = folderName);
      for (final exercise in _plan) {
        if (!exercise.folderNames.contains(folderName)) {
          exercise.folderNames = [...exercise.folderNames, folderName];
        }
        exercise.folderName = folderName;
        exercise.isFavorite = true;
        await db.exercises.put(exercise);
      }
    });
    if (mounted) Navigator.of(context).pop(folderName);
  }

  String _equipment(String name) {
    final value = name.toLowerCase();
    if (value.contains('cable')) return 'Cable machine';
    if (value.contains('machine') ||
        value.contains('pec deck') ||
        value.contains('smith')) return 'Weight machine';
    if (value.contains('barbell') ||
        value.contains('deadlift') ||
        value.contains('squat')) return 'Barbell';
    if (value.contains('dumbbell')) return 'Dumbbells';
    if (value.contains('bench')) return 'Bench';
    if (value.contains('pull-up') || value.contains('chin-up'))
      return 'Pull-up bar';
    return 'Equipment / movement';
  }

  @override
  Widget build(BuildContext context) {
    final theme = _theme;
    return Dialog(
      backgroundColor: theme.card,
      insetPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 540, maxHeight: 700),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(children: [
                Icon(Icons.auto_awesome, color: theme.accent),
                const SizedBox(width: 10),
                Expanded(
                    child: Text('Steel Workout Planner',
                        style: TextStyle(
                            color: theme.text,
                            fontSize: 19,
                            fontWeight: FontWeight.bold))),
                IconButton(
                    onPressed: _working ? null : () => Navigator.pop(context),
                    icon: Icon(Icons.close, color: theme.subText)),
              ]),
              Text(
                  'Steel uses the included Needle3 model to plan workouts on this device.',
                  style: TextStyle(color: theme.subText, fontSize: 12)),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  onPressed: _working
                      ? null
                      : () => showDialog<void>(
                            context: context,
                            builder: (_) => NeedleDataDialog(
                              onChanged: widget.onDataChanged,
                            ),
                          ),
                  icon: const Icon(Icons.storage_outlined, size: 16),
                  label: const Text('Manage app data with Steel'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: theme.accent,
                    side: BorderSide(color: theme.accent.withValues(alpha: .6)),
                    textStyle: const TextStyle(fontSize: 12),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              if (_working)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  child: Column(children: [
                    LinearProgressIndicator(
                        value: _total > 0
                            ? (_received / _total).clamp(0, 1)
                            : null,
                        color: theme.accent,
                        backgroundColor: theme.background),
                    const SizedBox(height: 9),
                    Text(
                        _received == 0
                            ? 'Getting Steel ready…'
                            : 'Steel is putting together your workout…',
                        style: TextStyle(color: theme.subText, fontSize: 12)),
                  ]),
                )
              else
                Flexible(
                  child: SingleChildScrollView(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('WORKOUT FOCUS',
                              style: TextStyle(
                                  color: theme.subText,
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 1)),
                          const SizedBox(height: 8),
                          Wrap(
                              spacing: 7,
                              runSpacing: 6,
                              children: _splits.map((split) {
                                final selected =
                                    _selectedSplits.contains(split);
                                return FilterChip(
                                  label: Text(split,
                                      style: TextStyle(
                                          color: selected
                                              ? theme.background
                                              : theme.text,
                                          fontSize: 12)),
                                  selected: selected,
                                  selectedColor: theme.accent,
                                  backgroundColor: theme.background,
                                  showCheckmark: false,
                                  onSelected: (value) => setState(() {
                                    _plan.clear();
                                    _unavailable.clear();
                                    if (split == 'Fullbody' && value) {
                                      _selectedSplits
                                        ..clear()
                                        ..add(split);
                                    } else {
                                      _selectedSplits.remove('Fullbody');
                                      if (value)
                                        _selectedSplits.add(split);
                                      else
                                        _selectedSplits.remove(split);
                                    }
                                  }),
                                );
                              }).toList()),
                          SwitchListTile.adaptive(
                            contentPadding: EdgeInsets.zero,
                            activeThumbColor: theme.accent,
                            title: Text('Include exercises I haven’t tried',
                                style:
                                    TextStyle(color: theme.text, fontSize: 13)),
                            subtitle: Text(
                                'Adds up to a couple of new movements when they fit.',
                                style: TextStyle(
                                    color: theme.subText, fontSize: 11)),
                            value: _includeNew,
                            onChanged: (value) => setState(() {
                              _includeNew = value;
                              _plan.clear();
                              _unavailable.clear();
                            }),
                          ),
                          if (_error != null)
                            Padding(
                                padding: const EdgeInsets.only(bottom: 10),
                                child: Text(_error!,
                                    style: TextStyle(
                                        color: theme.accent, fontSize: 12))),
                          if (_plan.isNotEmpty) ...[
                            const SizedBox(height: 6),
                            Text(
                                'DRAFT · TAP “UNAVAILABLE” IF YOU LACK THE EQUIPMENT',
                                style: TextStyle(
                                    color: theme.subText,
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold)),
                            const SizedBox(height: 6),
                            ..._plan.map((exercise) {
                              final unavailable =
                                  _unavailable.contains(exercise.name);
                              return Container(
                                margin: const EdgeInsets.only(bottom: 6),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 8),
                                decoration: BoxDecoration(
                                    color: theme.background,
                                    borderRadius: BorderRadius.circular(12)),
                                child: Row(children: [
                                  Expanded(
                                      child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                        Text(exercise.name,
                                            style: TextStyle(
                                                color: unavailable
                                                    ? theme.subText
                                                    : theme.text,
                                                fontWeight: FontWeight.w600,
                                                decoration: unavailable
                                                    ? TextDecoration.lineThrough
                                                    : null)),
                                        Text(_equipment(exercise.name),
                                            style: TextStyle(
                                                color: theme.subText,
                                                fontSize: 10)),
                                      ])),
                                  TextButton(
                                    onPressed: () => setState(() => unavailable
                                        ? _unavailable.remove(exercise.name)
                                        : _unavailable.add(exercise.name)),
                                    child: Text(
                                        unavailable ? 'Marked' : 'Unavailable',
                                        style: TextStyle(
                                            color: unavailable
                                                ? theme.accent
                                                : theme.subText,
                                            fontSize: 11)),
                                  ),
                                ]),
                              );
                            }),
                            TextField(
                              controller: _folderController,
                              style: TextStyle(color: theme.text),
                              decoration: InputDecoration(
                                  labelText: 'Favorite folder name',
                                  labelStyle: TextStyle(color: theme.subText),
                                  enabledBorder: UnderlineInputBorder(
                                      borderSide: BorderSide(
                                          color: theme.subText
                                              .withValues(alpha: .4))),
                                  focusedBorder: UnderlineInputBorder(
                                      borderSide:
                                          BorderSide(color: theme.accent))),
                            ),
                          ],
                        ]),
                  ),
                ),
              const SizedBox(height: 8),
              Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                TextButton(
                    onPressed: _working ? null : () => Navigator.pop(context),
                    child:
                        Text('Cancel', style: TextStyle(color: theme.subText))),
                if (_plan.isNotEmpty && _unavailable.isNotEmpty)
                  TextButton(
                      onPressed:
                          _working ? null : () => _generate(revise: true),
                      child: Text('Revise plan',
                          style: TextStyle(
                              color: theme.accent,
                              fontWeight: FontWeight.bold))),
                if (_plan.isEmpty)
                  FilledButton(
                      onPressed: _working || _selectedSplits.isEmpty
                          ? null
                          : _generate,
                      style:
                          FilledButton.styleFrom(backgroundColor: theme.accent),
                      child: Text('Generate',
                          style: TextStyle(color: theme.background)))
                else
                  FilledButton(
                      onPressed:
                          _working || _folderController.text.trim().isEmpty
                              ? null
                              : _save,
                      style:
                          FilledButton.styleFrom(backgroundColor: theme.accent),
                      child: Text('Save to favorites',
                          style: TextStyle(color: theme.background))),
              ]),
            ],
          ),
        ),
      ),
    );
  }
}

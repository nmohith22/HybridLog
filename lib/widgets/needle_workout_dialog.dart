import 'package:flutter/material.dart';
import 'package:isar/isar.dart';

import '../models/fitness_schema.dart';
import '../services/database_service.dart';
import '../services/equipment_profile_service.dart';
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
  final _unavailableEquipment = <String>{};
  List<Exercise> _plan = [];
  int _planningStep = 0;
  bool _includeNew = true;
  bool _working = false;
  bool _equipmentLoaded = false;
  int _received = 0;
  int _total = -1;
  String? _error;

  AppTheme get _theme => ThemeService().getResolvedTheme(context);

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _folderController.text = 'Steel Workout ${now.month}/${now.day}';
    _loadEquipmentProfile();
  }

  Future<void> _loadEquipmentProfile() async {
    try {
      final unavailable = await EquipmentProfileService.loadUnavailable();
      if (mounted) _unavailableEquipment.addAll(unavailable);
    } catch (_) {
      // Keep planning available if local preferences cannot be read.
    } finally {
      if (mounted) setState(() => _equipmentLoaded = true);
    }
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
        unavailableEquipment: _unavailableEquipment,
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
    final categories = EquipmentProfileService.categoriesForExercise(name);
    return categories.isEmpty ? 'Equipment / movement' : categories.join(' + ');
  }

  Future<void> _editEquipmentProfile() async {
    final unavailable = Set<String>.from(_unavailableEquipment);
    final result = await showDialog<Set<String>>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: _theme.card,
          title:
              Text('Equipment profile', style: TextStyle(color: _theme.text)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Turn off equipment you cannot use. Steel will remember this on this device and use it in future plans.',
                  style: TextStyle(color: _theme.subText),
                ),
                const SizedBox(height: 8),
                ...EquipmentProfileService.categories
                    .map((category) => SwitchListTile.adaptive(
                          contentPadding: EdgeInsets.zero,
                          activeThumbColor: _theme.accent,
                          title: Text(category,
                              style:
                                  TextStyle(color: _theme.text, fontSize: 13)),
                          value: !unavailable.contains(category),
                          onChanged: (available) => setDialogState(() {
                            if (available) {
                              unavailable.remove(category);
                            } else {
                              unavailable.add(category);
                            }
                          }),
                        )),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text('Cancel', style: TextStyle(color: _theme.subText)),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: _theme.accent),
              onPressed: () => Navigator.pop(dialogContext, unavailable),
              child: Text('Save profile',
                  style: TextStyle(color: _theme.background)),
            ),
          ],
        ),
      ),
    );
    if (result == null) return;
    try {
      await EquipmentProfileService.saveUnavailable(result);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content:
                Text('Could not save the equipment profile on this device.')));
      }
    }
    if (mounted) {
      setState(() {
        _unavailableEquipment
          ..clear()
          ..addAll(result);
        _plan.clear();
      });
    }
  }

  Widget _chatBubble(AppTheme theme, String text, {bool user = false}) => Align(
        alignment: user ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: BoxDecoration(
            color:
                user ? theme.accent.withValues(alpha: .14) : theme.background,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Text(text, style: TextStyle(color: theme.text, fontSize: 12)),
        ),
      );

  Widget _buildPlanningFlow(AppTheme theme) {
    final focus = _selectedSplits.join(', ');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _chatBubble(theme,
            'I’ll ask a few quick questions, then use your recent workouts to make a draft. These choices stay within this planning flow.'),
        if (_planningStep > 0)
          _chatBubble(theme, 'Workout focus: $focus', user: true),
        if (_planningStep > 1)
          _chatBubble(
            theme,
            _includeNew
                ? 'Open to new exercises: yes'
                : 'Open to new exercises: no',
            user: true,
          ),
        const SizedBox(height: 4),
        Text(
          'STEP ${_planningStep + 1} OF 3',
          style: TextStyle(
            color: theme.subText,
            fontSize: 10,
            fontWeight: FontWeight.bold,
            letterSpacing: 1,
          ),
        ),
        const SizedBox(height: 6),
        if (_planningStep == 0) ...[
          _chatBubble(
              theme, 'What would you like to train? Select one or more.'),
          Wrap(
            spacing: 7,
            runSpacing: 6,
            children: _splits.map((split) {
              final selected = _selectedSplits.contains(split);
              return ChoiceChip(
                label: Text(split,
                    style: TextStyle(
                        color: selected ? theme.background : theme.text,
                        fontSize: 12)),
                selected: selected,
                selectedColor: theme.accent,
                backgroundColor: theme.background,
                showCheckmark: false,
                onSelected: (value) => setState(() {
                  if (split == 'Fullbody' && value) {
                    _selectedSplits
                      ..clear()
                      ..add(split);
                  } else {
                    _selectedSplits.remove('Fullbody');
                    if (value) {
                      _selectedSplits.add(split);
                    } else {
                      _selectedSplits.remove(split);
                    }
                  }
                }),
              );
            }).toList(),
          ),
        ] else if (_planningStep == 1) ...[
          _chatBubble(theme,
              'Would you like to try exercises you haven’t done before?'),
          Wrap(
            spacing: 8,
            children: [
              ChoiceChip(
                label: const Text('Use familiar exercises'),
                selected: !_includeNew,
                onSelected: (_) => setState(() => _includeNew = false),
                selectedColor: theme.accent,
                backgroundColor: theme.background,
                labelStyle: TextStyle(
                    color: !_includeNew ? theme.background : theme.text),
                showCheckmark: false,
              ),
              ChoiceChip(
                label: const Text('Include new exercises'),
                selected: _includeNew,
                onSelected: (_) => setState(() => _includeNew = true),
                selectedColor: theme.accent,
                backgroundColor: theme.background,
                labelStyle: TextStyle(
                    color: _includeNew ? theme.background : theme.text),
                showCheckmark: false,
              ),
            ],
          ),
        ] else ...[
          _chatBubble(theme, 'Any equipment you don’t have access to?'),
          Text(
            'I’ll use the equipment profile saved on this device. You can update it here before I build the plan.',
            style: TextStyle(color: theme.subText, fontSize: 11),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: _editEquipmentProfile,
              icon: const Icon(Icons.fitness_center, size: 16),
              label: Text(_unavailableEquipment.isEmpty
                  ? 'Review equipment profile'
                  : '${_unavailableEquipment.length} limits saved'),
              style: OutlinedButton.styleFrom(
                foregroundColor: theme.accent,
                side: BorderSide(color: theme.accent.withValues(alpha: .5)),
                textStyle: const TextStyle(fontSize: 12),
              ),
            ),
          ),
        ],
      ],
    );
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
                          if (_plan.isEmpty) _buildPlanningFlow(theme),
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
                if (_plan.isEmpty && _planningStep > 0)
                  TextButton(
                    onPressed:
                        _working ? null : () => setState(() => _planningStep--),
                    child: Text('Back', style: TextStyle(color: theme.subText)),
                  ),
                if (_plan.isEmpty && _planningStep < 2)
                  FilledButton(
                      onPressed: _working || _selectedSplits.isEmpty
                          ? null
                          : () => setState(() => _planningStep++),
                      style:
                          FilledButton.styleFrom(backgroundColor: theme.accent),
                      child: Text('Continue',
                          style: TextStyle(color: theme.background))),
                if (_plan.isEmpty && _planningStep == 2)
                  FilledButton(
                      onPressed: _working ||
                              !_equipmentLoaded ||
                              _selectedSplits.isEmpty
                          ? null
                          : _generate,
                      style:
                          FilledButton.styleFrom(backgroundColor: theme.accent),
                      child: Text(
                          _equipmentLoaded
                              ? 'Build my workout'
                              : 'Loading profile',
                          style: TextStyle(color: theme.background))),
                if (_plan.isNotEmpty)
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

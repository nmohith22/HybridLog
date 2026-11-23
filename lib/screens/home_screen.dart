import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:isar/isar.dart';
import '../models/fitness_schema.dart';
import '../services/database_service.dart';
import '../services/exercise_seed.dart';
import '../services/widget_service.dart';
import '../services/theme_service.dart';
import '../widgets/theme_picker_widget.dart';
import '../widgets/dashboard_header.dart';
import 'package:intl/intl.dart';
import '../widgets/lego_animations.dart';
import 'exercise_history_screen.dart';
import '../services/recovery_predictor.dart';
import '../services/progression_service.dart';
import '../widgets/needle_workout_dialog.dart';
import '../widgets/front_back_heatmap_fade.dart';
import '../widgets/steel_chat_dialog.dart';
import '../services/tutorial_service.dart';
import '../utils/weight_reps_format.dart';
import '../services/muscle_fatigue_service.dart';
import '../widgets/set_sequence_editor.dart';

// --- HELPER: MARQUEE TEXT ---
class MarqueeText extends StatefulWidget {
  final String text;
  final TextStyle style;
  const MarqueeText({super.key, required this.text, required this.style});

  @override
  State<MarqueeText> createState() => _MarqueeTextState();
}

class _MarqueeTextState extends State<MarqueeText> {
  late ScrollController _scrollController;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController(onAttach: (position) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _startScrolling(position));
    });
  }

  Future<void> _startScrolling(ScrollPosition position) async {
    while (mounted && _scrollController.positions.contains(position)) {
      await Future.delayed(const Duration(seconds: 1));
      if (!mounted || !_scrollController.positions.contains(position)) return;
      final distance = (position.maxScrollExtent + position.viewportDimension) / 2;
      await position.animateTo(distance, duration: Duration(milliseconds: (distance * 30).round()), curve: Curves.linear);
      if (!mounted || !_scrollController.positions.contains(position)) return;
      position.jumpTo(0);
    }
  }

  @override
  void dispose() { _scrollController.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    // If under 30 chars, make it slightly smaller to fit better if it's long but not "marquee-long"
    TextStyle effectiveStyle = widget.text.length > 18 && widget.text.length < 30 
        ? widget.style.copyWith(fontSize: widget.style.fontSize! - 2) 
        : widget.style;

    if (widget.text.length <= 18) return Text(widget.text, style: effectiveStyle, maxLines: 1, overflow: TextOverflow.ellipsis);
    return LayoutBuilder(builder: (context, bounds) {
      final measure = TextPainter(
        text: TextSpan(text: widget.text, style: DefaultTextStyle.of(context).style.merge(effectiveStyle)),
        textDirection: Directionality.of(context),
        textScaler: MediaQuery.textScalerOf(context),
        maxLines: 1,
      )..layout();
      final fits = measure.width <= bounds.maxWidth;
      measure.dispose();
      final label = Text(widget.text, style: effectiveStyle, maxLines: 1);
      if (fits) return label;
      return IgnorePointer(child: SingleChildScrollView(controller: _scrollController,
        scrollDirection: Axis.horizontal, physics: const NeverScrollableScrollPhysics(),
        child: Row(children: [label, const SizedBox(width: 40), ExcludeSemantics(child: label), const SizedBox(width: 40)])));
    });
  }
}

// --- HELPER: SCALING CARD ---
class ScalingCard extends StatelessWidget {
  final Widget child;
  final double scrollOffset;
  final double itemPosition;
  final double viewportHeight;
  final double baseOffset;
  final bool enabled;

  const ScalingCard({super.key, required this.child, required this.scrollOffset, required this.itemPosition, required this.viewportHeight, this.baseOffset = 0, this.enabled = true});

  @override
  Widget build(BuildContext context) {
    if (!enabled) return child;

    // Calculate position relative to the top of the viewport
    final double pos = itemPosition - (scrollOffset + baseOffset);
    double scale = 1.0;
    
    // EXTREME TOP: Trigger only when moving behind the search bar/header
    // We want it to start minimizing when it's about half behind (pos = -40)
    if (pos < -40) {
      scale = 1.0 - ((pos + 40).abs() / 150).clamp(0.0, 0.25);
    } 
    // EXTREME BOTTOM: Trigger only when hitting the bottom navigation area
    // Adjusted threshold from 220 down to 140 to account for smaller nav bar.
    else if (pos > viewportHeight - 140) {
      scale = 1.0 - ((pos - (viewportHeight - 140)) / 150).clamp(0.0, 0.25);
    }
    
    return Transform.scale(
      scale: scale, 
      alignment: pos < 0 ? Alignment.bottomCenter : Alignment.topCenter, // Vanish into the edge
      child: child,
    );
  }
}

class HomeScreen extends StatefulWidget {
  final VoidCallback? onNavigateToRunning;
  const HomeScreen({super.key, this.onNavigateToRunning});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final DraggableScrollableController _sheetController = DraggableScrollableController();
  final ScrollController _mainScrollController = ScrollController();
  final ScrollController _libraryScrollController = ScrollController();
  final TextEditingController _searchController = TextEditingController();
  
  Map<String, double> _muscleIntensities = {}; 
  Map<DateTime, Map<String, double>> _recentMuscleWork = {};
  String _searchQuery = "";
  List<String> _selectedMuscles = [];
  String? _selectedManufacturer;
  String _selectedSort = 'a-z';
  double _sheetSize = 0.05;
  int _selectedHistoryYear = DateTime.now().year;

  // Cached Futures to prevent infinite loading loops
  Future<List<Exercise>>? _exercisesFuture;
  Future<Map<String, List<Exercise>>>? _favoritesFuture;
  Future<List<DailyWorkout>>? _historyFuture;

  Color get bgDarkPurple => ThemeService().getResolvedTheme(context).background;
  Color get cardPurple => ThemeService().getResolvedTheme(context).card;
  Color get accentRed => ThemeService().getResolvedTheme(context).accent;

  final GlobalKey _createFolderKey = GlobalKey();
  final GlobalKey _exerciseCardKey = GlobalKey();
  final GlobalKey _appDrawerKey = GlobalKey();
  final GlobalKey _historyTabKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this); 
    _sheetController.addListener(() { 
      if (mounted) {
        setState(() => _sheetSize = _sheetController.size); 
      }
    });

    TutorialService.createFolderKey = _createFolderKey;
    TutorialService.exerciseCardKey = _exerciseCardKey;
    TutorialService.appDrawerKey = _appDrawerKey;
    TutorialService.historyTabKey = _historyTabKey;

    _initializeData();
    _mainScrollController.addListener(() { if (mounted) setState(() {}); });
    _libraryScrollController.addListener(() { if (mounted) setState(() {}); });
  }

  Future<void> _initializeData() async {
    final db = await DatabaseService().database;
    // --- TERMINOLOGY MIGRATION ---
    await db.writeTxn(() async {
      // 1. Update master Exercise dictionary
      final allExercises = await db.exercises.where().findAll();
      for (var ex in allExercises) {
        bool changed = false;
        // Migrate folderName
        if (ex.folderName != null && !ex.folderNames.contains(ex.folderName!)) {
          ex.folderNames = List.from(ex.folderNames)..add(ex.folderName!);
          changed = true;
        }
        // Migrate targetMuscle
        if (ex.targetMuscles.isEmpty) {
          ex.targetMuscles = [ex.targetMuscle];
          changed = true;
        }

        if (ex.targetMuscle.contains('shoulder')) {
          ex.targetMuscle = ex.targetMuscle.replaceAll('shoulder', 'deltoids');
          ex.targetMuscles = ex.targetMuscles.map((m) => m.replaceAll('shoulder', 'deltoids')).toList();
          changed = true;
        } else if (ex.targetMuscle.endsWith('deltoid')) {
          ex.targetMuscle = '${ex.targetMuscle}s';
          ex.targetMuscles = ex.targetMuscles.map((m) => m.endsWith('deltoid') ? '${m}s' : m).toList();
          changed = true;
        }
        ex.secondaryMuscles = ex.secondaryMuscles.map((m) {
          if (m.contains('shoulder')) {
            changed = true;
            return m.replaceAll('shoulder', 'deltoids');
          } else if (m.endsWith('deltoid')) {
            changed = true;
            return '${m}s';
          }
          return m;
        }).toList();
        if (changed) await db.exercises.put(ex);
      }
      // 2. Update existing DailyWorkout logs
      final allWorkouts = await db.dailyWorkouts.where().findAll();
      for (var workout in allWorkouts) {
        bool workoutChanged = false;
        for (var log in workout.exercises) {
          if (log.targetMuscles.isEmpty && log.targetMuscle != null) {
            log.targetMuscles = [log.targetMuscle!];
            workoutChanged = true;
          }
          if (log.targetMuscle != null && (log.targetMuscle!.contains('shoulder') || log.targetMuscle!.endsWith('deltoid'))) {
            log.targetMuscle = log.targetMuscle!.replaceAll('shoulder', 'deltoids');
            if (!log.targetMuscle!.endsWith('s')) log.targetMuscle = '${log.targetMuscle}s';
            log.targetMuscles = log.targetMuscles.map((m) {
              String newM = m.replaceAll('shoulder', 'deltoids');
              if (!newM.endsWith('s')) newM = '${newM}s';
              return newM;
            }).toList();
            workoutChanged = true;
          }
          log.secondaryMuscles = log.secondaryMuscles.map((m) {
            if (m.contains('shoulder') || m.endsWith('deltoid')) {
              workoutChanged = true;
              String newM = m.replaceAll('shoulder', 'deltoids');
              if (!newM.endsWith('s')) newM = '${newM}s';
              return newM;
            }
            return m;
          }).toList();
        }
        if (workoutChanged) await db.dailyWorkouts.put(workout);
      }
    });

    // Non-blocking widget update
    WidgetService.updateRunningWidget().catchError((e) => debugPrint('Widget update error: $e'));
    
    // Synchronize seed exercises to update muscles and manufacturers without losing favorites/folders
    await db.writeTxn(() async {
      for (var exData in initialExercises) {
        final existing = await db.exercises.filter().nameEqualTo(exData['name']!).findFirst();
        if (existing != null) {
          final newPrimary = exData['primary']!;
          final newSecondary = List<String>.from(exData['secondary'] ?? []);
          bool needsUpdate = existing.targetMuscle != newPrimary ||
              existing.targetMuscles.isEmpty ||
              existing.targetMuscles.first != newPrimary ||
              existing.secondaryMuscles.length != newSecondary.length ||
              !existing.secondaryMuscles.every((m) => newSecondary.contains(m));
          if (needsUpdate) {
            existing.targetMuscle = newPrimary;
            existing.targetMuscles = [newPrimary];
            existing.secondaryMuscles = newSecondary;
            await db.exercises.put(existing);
          }
        } else {
          final newEx = Exercise()
            ..name = exData['name']!
            ..targetMuscle = exData['primary']!
            ..targetMuscles = [exData['primary']!]
            ..secondaryMuscles = List<String>.from(exData['secondary'] ?? [])
            ..isFavorite = false;
          await db.exercises.put(newEx);
        }
      }
    });
    _loadRecentMuscles();
    _refreshData();
  }

  void _refreshData() {
    if (!mounted) return;
    setState(() {
      _exercisesFuture = _getFilteredExercises();
      _favoritesFuture = _loadGroupedFavorites();
      _historyFuture = DatabaseService().database.then((db) => db.dailyWorkouts.where().sortByDateDesc().findAll());
    });
  }

  Future<void> _loadRecentMuscles() async {
    final db = await DatabaseService().database;
    final now = DateTime.now();
    final workouts = await db.dailyWorkouts.filter()
        .dateBetween(now.subtract(MuscleFatigueService.window), now).findAll();
    final sessions = <DateTime, Map<String, double>>{};
    for (final workout in workouts) {
      final day = sessions.putIfAbsent(workout.date, () => {});
      for (final entry in MuscleFatigueService.workoutLoad(workout).entries) {
        day.update(entry.key, (value) => value + entry.value, ifAbsent: () => entry.value);
      }
    }
    if (mounted) setState(() {
      _recentMuscleWork = sessions;
      _muscleIntensities = MuscleFatigueService.recentLoad(sessions, now)
          .map((muscle, load) => MapEntry(muscle, load.clamp(0.0, 1.0)));
    });
  }

  Color _getIntensityColor(double intensity) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    if (isDark) {
      if (intensity < 0.2) return Colors.blueAccent.withOpacity(0.5); 
      if (intensity < 0.5) return Color.lerp(Colors.blueAccent, Colors.deepPurple, (intensity - 0.2) * 3.33)!;
      return Color.lerp(Colors.deepPurple, Colors.redAccent, (intensity - 0.5) * 2)!;
    } else {
      // Light Mode: Green -> Yellow/Orange -> Dark Orange
      if (intensity < 0.2) return const Color(0xFF81C784).withOpacity(0.8); // Light Green
      if (intensity < 0.5) return Color.lerp(const Color(0xFF81C784), const Color(0xFFFFB74D), (intensity - 0.2) * 3.33)!;
      return Color.lerp(const Color(0xFFFFB74D), const Color(0xFFE65100), (intensity - 0.5) * 2)!;
    }
  }

  @override
  void dispose() { _tabController.dispose(); _sheetController.dispose(); _mainScrollController.dispose(); _libraryScrollController.dispose(); _searchController.dispose(); super.dispose(); }

  Future<void> _openLoggingSheet(Exercise exercise, {DailyWorkout? editWorkout, int? editExIndex, DateTime? targetDate, ProgressionSuggestion? progression, List<SetLog>? draftSets}) async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = cardPurple;
    final textColor = Theme.of(context).colorScheme.onSurface;

    double defaultWeight = progression?.weight ?? 0.0;
    int defaultReps = progression?.reps ?? 10;
    if (draftSets != null && draftSets.isNotEmpty) {
      defaultWeight = draftSets.first.weight;
      defaultReps = draftSets.first.reps;
    }
    if (editWorkout == null && progression == null && draftSets == null) {
      try {
        final db = await DatabaseService().database;
        final lastWorkout = await db.dailyWorkouts
            .filter()
            .exercisesElement((q) => q.exerciseNameEqualTo(exercise.name).or()
                .setsElement((set) => set.subSetsElement(
                    (step) => step.exerciseNameEqualTo(exercise.name))))
            .sortByDateDesc()
            .findFirst();
        if (lastWorkout != null) {
          final loggedExs = lastWorkout.trainingExercises.where((e) => e.exerciseName == exercise.name);
          final sets = loggedExs.expand((e) => e.sets).where((set) => set.reps > 0).toList();
          if (sets.isNotEmpty) {
            defaultWeight = sets.map((s) => s.weight).reduce((curr, next) => curr < next ? curr : next);
            defaultReps = sets.last.reps;
          }
        }
      } catch (e) {
        debugPrint("Error fetching last workout weight: $e");
      }
    }

    List<SetLog> currentSets;
    if (editWorkout != null && editExIndex != null) {
      final existingEx = editWorkout.exercises[editExIndex];
      currentSets = existingEx.sets.map((set) => set.editableCopy()).toList();
    } else if (draftSets != null) {
      currentSets = draftSets.map((set) => set.editableCopy()).toList();
    } else { currentSets = [SetLog()..reps = defaultReps..weight = defaultWeight]; }

    if (!mounted) return;
    var logDate = targetDate;
    final mainMuscles = exercise.targetMuscles.isNotEmpty ? exercise.targetMuscles : [exercise.targetMuscle];
    final weightHint = defaultWeight % 1 == 0 ? defaultWeight.toInt().toString() : defaultWeight.toString();
    final repsHint = defaultReps.toString();

    showModalBottomSheet(
      context: context, backgroundColor: bgColor, isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (context) {
        return StatefulBuilder(builder: (context, setModalState) {
          return Padding(
            padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
              child: Column(
              mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(exercise.name, style: TextStyle(color: textColor, fontSize: 24, fontWeight: FontWeight.bold, letterSpacing: -0.5)),
                    Text('Primary: ${mainMuscles.map((m) => m.replaceAll('_', ' ')).join(', ').toUpperCase()}', style: TextStyle(color: accentRed, fontSize: 14, fontWeight: FontWeight.w600)),
                    if (draftSets != null)
                      const Text('STEEL DRAFT · REVIEW SETS BEFORE SAVING', style: TextStyle(color: Colors.grey, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 0.7)),
                  ])),
                  Column(children: [
                    if (editWorkout == null) IconButton(tooltip: logDate == null ? 'Log date' : DateFormat.yMMMd().format(logDate!), iconSize: 28, onPressed: () async {
                      final picked = await showDatePicker(context: context, initialDate: logDate ?? DateTime.now(), firstDate: DateTime(2000), lastDate: DateTime.now());
                      if (picked != null && context.mounted) setModalState(() => logDate = picked);
                    }, icon: const Icon(Icons.calendar_today, color: Colors.grey)),
                    IconButton(iconSize: 28, onPressed: () {
                      Navigator.pop(context);
                      Navigator.push<ProgressionSuggestion>(this.context, MaterialPageRoute(builder: (context) => ExerciseHistoryScreen(exercise: exercise))).then((target) {
                        if (target != null && mounted) _openLoggingSheet(exercise, progression: target);
                      });
                    }, icon: const Icon(Icons.history, color: Colors.blueAccent)),
                    IconButton(icon: const Icon(Icons.add_circle, color: Colors.deepOrange, size: 32), onPressed: () => setModalState(() => currentSets.add(SetLog()..reps = defaultReps..weight = defaultWeight))),
                  ])
                ]),
                const SizedBox(height: 16),
                ...List.generate(currentSets.length, (index) => Dismissible(
                  key: ObjectKey(currentSets[index]),
                  direction: DismissDirection.startToEnd,
                  onDismissed: (_) => setModalState(() => currentSets.removeAt(index)),
                  background: Container(alignment: Alignment.centerLeft, padding: const EdgeInsets.only(left: 20), color: Colors.red.withOpacity(0.2), child: const Icon(Icons.delete, color: Colors.red)),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6.0),
                    child: Column(
                      children: [
                        Row(children: [
                          Expanded(flex: 1, child: Text('${index + 1}', style: TextStyle(color: textColor, fontSize: 18, fontWeight: FontWeight.bold))),
                          Expanded(flex: 2, child: Padding(padding: const EdgeInsets.symmetric(horizontal: 8.0), child: TextFormField(initialValue: currentSets[index].weight == defaultWeight && editWorkout == null && progression == null && draftSets == null ? '' : (currentSets[index].weight % 1 == 0 ? currentSets[index].weight.toInt().toString() : currentSets[index].weight.toString()), keyboardType: const TextInputType.numberWithOptions(decimal: true), inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'(^\d*\.?\d*)'))], style: TextStyle(color: textColor, fontWeight: FontWeight.bold), decoration: InputDecoration(filled: true, fillColor: isDark ? bgDarkPurple : Colors.grey[100], hintText: weightHint, hintStyle: const TextStyle(color: Colors.grey), suffixText: 'lbs', suffixStyle: const TextStyle(color: Colors.grey, fontSize: 14), border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none)), onChanged: (v) => currentSets[index].weight = double.tryParse(v) ?? 0.0))),
                          Expanded(flex: 2, child: Padding(padding: const EdgeInsets.symmetric(horizontal: 8.0), child: TextFormField(initialValue: currentSets[index].reps == defaultReps && editWorkout == null && progression == null && draftSets == null ? '' : currentSets[index].reps.toString(), keyboardType: TextInputType.number, inputFormatters: [FilteringTextInputFormatter.digitsOnly], style: TextStyle(color: textColor, fontWeight: FontWeight.bold), decoration: InputDecoration(filled: true, fillColor: isDark ? bgDarkPurple : Colors.grey[100], hintText: repsHint, hintStyle: const TextStyle(color: Colors.grey), border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none)), onChanged: (v) => currentSets[index].reps = int.tryParse(v) ?? 0))),
                        ]),
                        SetSequenceEditor(
                          set: currentSets[index],
                          onChanged: () => setModalState(() {}),
                          chooseExercise: () => _pickSupersetExercise(context, exercise.name),
                        ),
                      ],
                    ),
                  ),
                )),
                const SizedBox(height: 24),
                Row(children: [
                  if (editWorkout != null) Expanded(child: Padding(padding: const EdgeInsets.only(right: 8.0), child: OutlinedButton(style: OutlinedButton.styleFrom(side: const BorderSide(color: Colors.grey), padding: const EdgeInsets.symmetric(vertical: 16), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))), onPressed: () async {
                    final db = await DatabaseService().database; await db.writeTxn(() async { editWorkout.exercises = List.from(editWorkout.exercises)..removeAt(editExIndex!); if (editWorkout.exercises.isEmpty) await db.dailyWorkouts.delete(editWorkout.id); else await db.dailyWorkouts.put(editWorkout); });
                    _loadRecentMuscles(); Navigator.pop(context); _refreshData();
                  }, child: const Text('Delete', style: TextStyle(color: Colors.grey, fontSize: 16, fontWeight: FontWeight.bold))))),
                  Expanded(flex: 2, child: ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: accentRed, padding: const EdgeInsets.symmetric(vertical: 16), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))), onPressed: () async {
                    final db = await DatabaseService().database;
                    if (editWorkout != null && editExIndex != null) { await db.writeTxn(() async { editWorkout.exercises[editExIndex].sets = currentSets; editWorkout.exercises = List.from(editWorkout.exercises); await db.dailyWorkouts.put(editWorkout); }); }
                    else { final finalDate = logDate ?? DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day); await db.writeTxn(() async {
                      var dailyLog = await db.dailyWorkouts.filter().dateEqualTo(finalDate).findFirst(); dailyLog ??= DailyWorkout()..date = finalDate;
                      final loggedEx = LoggedExercise()
                        ..exerciseName = exercise.name
                        ..targetMuscle = exercise.targetMuscle
                        ..targetMuscles = exercise.targetMuscles.isNotEmpty ? exercise.targetMuscles : [exercise.targetMuscle]
                        ..secondaryMuscles = exercise.secondaryMuscles
                        ..sets = currentSets;
                      dailyLog.exercises = List.from(dailyLog.exercises)..add(loggedEx); await db.dailyWorkouts.put(dailyLog);
                    }); }
                    _loadRecentMuscles(); Navigator.pop(context); _refreshData(); 
                  }, child: Text(editWorkout != null ? 'Update Log' : (draftSets != null ? 'Save reviewed log' : 'Log Workout'), style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)))),
                ]),
                const SizedBox(height: 24),
              ],
              ),
            ),
          );
        });
      }
    );
  }

  Future<Exercise?> _pickSupersetExercise(BuildContext sheet, String baseName) async {
    final db = await DatabaseService().database;
    final exercises = await db.exercises.where().sortByName().findAll();
    if (!sheet.mounted) return null;
    var query = '';
    return showDialog<Exercise>(context: sheet, builder: (context) =>
      StatefulBuilder(builder: (context, update) {
        final matches = exercises.where((exercise) =>
            exercise.name != baseName && exercise.name.toLowerCase().contains(query)).toList();
        return AlertDialog(
          title: const Text('Choose a superset exercise'),
          content: SizedBox(width: 360, height: MediaQuery.sizeOf(context).height * .34,
            child: Column(children: [
              TextField(decoration: const InputDecoration(labelText: 'Find an exercise'),
                onChanged: (value) => update(() => query = value.trim().toLowerCase())),
              Expanded(child: matches.isEmpty
                ? const Center(child: Text('No matching exercises.'))
                : ListView.builder(itemCount: matches.length, itemBuilder: (context, index) =>
                  ListTile(title: Text(matches[index].name), onTap: () => Navigator.pop(context, matches[index])))),
            ]),
          ),
          actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel'))],
        );
      }),
    );
  }

  bool _isFrontMuscle(String muscle) {
    const backMuscles = ['lats', 'lower_back', 'traps', 'back_deltoids', 'triceps', 'glutes', 'hamstrings', 'calves', 'tricep_long_head'];
    return !backMuscles.contains(muscle);
  }

  String? _parseManufacturer(String fullName) {
    if (fullName.contains(' | ')) {
      return fullName.split(' | ').first;
    }
    if (fullName.startsWith("Hammer Strength ")) {
      return "Hammer Strength";
    }
    if (fullName.startsWith("Life Fitness ")) {
      return "Life Fitness";
    }
    if (fullName.startsWith("Hoist Roc-it ")) {
      return "Hoist Roc-it";
    }
    return null;
  }

  Widget _buildExerciseCard(Exercise ex, {
    bool showDate = false,
    DateTime? date,
    VoidCallback? onTap,
    List<SetLog>? sets,
    int? index,
    double? scrollOffset,
    double? viewportHeight,
    double baseOffset = 0,
    bool useScaling = true,
  }) {
    final mainMuscles = ex.targetMuscles.isNotEmpty ? ex.targetMuscles : [ex.targetMuscle];
    final isFront = mainMuscles.isNotEmpty ? _isFrontMuscle(mainMuscles.first) : true;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colors = Theme.of(context).colorScheme;
    final cardColor = colors.surface;
    final textColor = colors.onSurface;
    final secondaryTextColor = colors.onSurfaceVariant;
    final previewBg = colors.surfaceContainerHighest;

    final cardContent = KeyedSubtree(
      key: index == 0 ? _exerciseCardKey : null,
      child: SpringyButton(
        onTap: onTap ?? () => _openLoggingSheet(ex),
        onLongPress: () => _showFolderAssignmentDialog(ex),
        child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        constraints: const BoxConstraints(minHeight: 100),
        decoration: BoxDecoration(
          color: cardColor,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: isDark ? Colors.white.withOpacity(0.02) : Colors.black.withOpacity(0.05)),
          boxShadow: isDark ? [] : [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 4))],
        ),
        child: Row(
          children: [
            // Muscle Preview
            Container(
              width: 56,
              height: 76,
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: previewBg,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  SvgPicture.asset(
                    isFront ? 'assets/body_front_base.svg' : 'assets/body_back_base.svg',
                    colorFilter: ColorFilter.mode(isDark ? Colors.grey[800]! : Colors.grey[300]!, BlendMode.srcIn),
                  ),
                  // Secondary muscles first so main muscles render on top
                  ...ex.secondaryMuscles.where((m) => _isFrontMuscle(m) == isFront).map((m) => SvgPicture.asset(
                        isFront ? 'assets/front_$m.svg' : 'assets/back_$m.svg',
                        colorFilter: ColorFilter.mode(accentRed.withOpacity(0.4), BlendMode.srcIn),
                      )),
                  ...mainMuscles.where((m) => _isFrontMuscle(m) == isFront).map((m) => SvgPicture.asset(
                        isFront ? 'assets/front_$m.svg' : 'assets/back_$m.svg',
                        colorFilter: ColorFilter.mode(accentRed, BlendMode.srcIn),
                      )),
                ],
              ),
            ),
            // Exercise Info
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    FormattedExerciseName(
                      fullName: ex.name,
                      style: TextStyle(color: textColor, fontSize: 18, fontWeight: FontWeight.bold, letterSpacing: -0.5),
                      secondaryColor: secondaryTextColor,
                    ),
                    const SizedBox(height: 4),
                    if (sets != null && sets.isNotEmpty)
                      Text(
                        sets.map((s) => formatWeightReps(s.weight, s.reps)).join(', '),
                        style: TextStyle(color: secondaryTextColor, fontSize: 13, fontWeight: FontWeight.w500),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      )
                    else
                      Text(
                        mainMuscles.map((m) => m.replaceAll('_', ' ')).join(', ').toUpperCase(),
                        style: TextStyle(color: accentRed.withOpacity(0.8), fontSize: 12, fontWeight: FontWeight.w600, letterSpacing: 1.0),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
            ),
            if (sets == null)
              IconButton(
                tooltip: ex.isFavorite ? 'Remove from favorites' : 'Add to favorites',
                icon: Icon(ex.isFavorite ? Icons.star : Icons.star_border, color: ex.isFavorite ? accentRed : (isDark ? Colors.grey[700] : Colors.grey[400])),
                onPressed: () async {
                  final db = await DatabaseService().database;
                  await db.writeTxn(() async {
                    ex.isFavorite = !ex.isFavorite;
                    await db.exercises.put(ex);
                  });
                  _refreshData();
                },
              )
            else
              const Icon(Icons.edit, color: Colors.grey, size: 18),
          ],
        ),
      ),
    ));

    if (index != null && scrollOffset != null && viewportHeight != null) {
      return ScalingCard(
        scrollOffset: scrollOffset,
        itemPosition: baseOffset + (index * 116.0),
        viewportHeight: viewportHeight,
        baseOffset: baseOffset,
        enabled: useScaling,
        child: LegoPop(index: index, child: cardContent),
      );
    }
    return LegoPop(index: index ?? 0, child: cardContent);
  }

  void _showFolderAssignmentDialog(Exercise ex) async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final db = await DatabaseService().database;
    final folders = await db.workoutFolders.where().sortByName().findAll();
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (context) {
        TextEditingController newFolderController = TextEditingController();
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: cardPurple,
              title: Text('Assign to Folders', style: TextStyle(color: Theme.of(context).colorScheme.onSurface)),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: accentRed,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        minimumSize: const Size(double.infinity, 50),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: () {
                        Navigator.pop(context);
                        Navigator.push<ProgressionSuggestion>(this.context, MaterialPageRoute(builder: (context) => ExerciseHistoryScreen(exercise: ex))).then((target) {
                          if (target != null && mounted) _openLoggingSheet(ex, progression: target);
                        });
                      },
                      icon: const Icon(Icons.analytics, color: Colors.white),
                      label: const Text('Detailed View', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                    ),
                    const SizedBox(height: 24),
                    if (folders.isNotEmpty) ...[
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'EXISTING FOLDERS',
                          style: TextStyle(
                            color: isDark ? Colors.grey : Colors.grey[600],
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1.0,
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      ...folders.map((f) {
                        final isAssigned = ex.folderNames.contains(f.name);
                        return ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(
                            isAssigned ? Icons.folder : Icons.folder_open_outlined,
                            color: isAssigned ? accentRed : Colors.grey,
                            size: 20,
                          ),
                          title: Text(
                            f.name,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.onSurface,
                              fontSize: 14,
                              fontWeight: isAssigned ? FontWeight.bold : FontWeight.normal,
                            ),
                          ),
                          trailing: isAssigned
                              ? const Icon(Icons.check, color: Colors.deepOrange, size: 18)
                              : null,
                          onTap: () async {
                            await db.writeTxn(() async {
                              if (isAssigned) {
                                ex.folderNames = List.from(ex.folderNames)..remove(f.name);
                              } else {
                                ex.folderNames = List.from(ex.folderNames)..add(f.name);
                                ex.isFavorite = true;
                              }
                              // Backwards compatibility fallback:
                              ex.folderName = ex.folderNames.isNotEmpty ? ex.folderNames.first : null;
                              await db.exercises.put(ex);
                            });
                            setDialogState(() {});
                            _refreshData();
                          },
                        );
                      }),
                      const Divider(),
                    ],
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.folder_delete_outlined, color: Colors.grey, size: 20),
                      title: Text(
                        'Uncategorized',
                        style: TextStyle(
                          color: isDark ? Colors.grey : Colors.grey[600],
                          fontSize: 14,
                        ),
                      ),
                      trailing: ex.folderNames.isEmpty
                          ? const Icon(Icons.check, color: Colors.deepOrange, size: 18)
                          : null,
                      onTap: () async {
                        await db.writeTxn(() async {
                          ex.folderNames = [];
                          ex.folderName = null;
                          await db.exercises.put(ex);
                        });
                        setDialogState(() {});
                        _refreshData();
                      },
                    ),
                    const SizedBox(height: 16),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'CREATE NEW',
                        style: TextStyle(
                          color: isDark ? Colors.grey : Colors.grey[600],
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.0,
                        ),
                      ),
                    ),
                    TextField(
                      controller: newFolderController,
                      onChanged: (v) => setDialogState((){}),
                      style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontSize: 14),
                      decoration: InputDecoration(
                        hintText: 'New Folder Name',
                        hintStyle: const TextStyle(color: Colors.grey, fontSize: 14),
                        enabledBorder: UnderlineInputBorder(
                          borderSide: BorderSide(color: isDark ? Colors.white10 : Colors.black12),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Close', style: TextStyle(color: Colors.grey)),
                ),
                TextButton(
                  onPressed: newFolderController.text.isEmpty ? null : () async {
                    if (newFolderController.text.isNotEmpty) {
                      final newF = newFolderController.text;
                      await db.writeTxn(() async {
                        final existingFolder = await db.workoutFolders.filter().nameEqualTo(newF).findFirst();
                        if (existingFolder == null) {
                          final f = WorkoutFolder()..name = newF;
                          await db.workoutFolders.put(f);
                        }
                        if (!ex.folderNames.contains(newF)) {
                          ex.folderNames = List.from(ex.folderNames)..add(newF);
                          ex.isFavorite = true;
                          ex.folderName = ex.folderNames.first;
                        }
                        await db.exercises.put(ex);
                      });
                      newFolderController.clear();
                      // Reload folders list
                      final updatedFolders = await db.workoutFolders.where().sortByName().findAll();
                      setDialogState(() {
                        folders.clear();
                        folders.addAll(updatedFolders);
                      });
                      _refreshData();
                    }
                  },
                  child: Text('Create & Add', style: TextStyle(color: newFolderController.text.isEmpty ? Colors.grey : Colors.deepOrange, fontWeight: FontWeight.bold)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showCreateFolderDialog() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    TextEditingController folderController = TextEditingController();
    showDialog(context: context, builder: (context) => AlertDialog(backgroundColor: cardPurple, title: Text('Create New Folder', style: TextStyle(color: Theme.of(context).colorScheme.onSurface)), content: TextField(controller: folderController, autofocus: true, style: TextStyle(color: Theme.of(context).colorScheme.onSurface), decoration: InputDecoration(hintText: 'e.g., Push Day, Leg Day', hintStyle: const TextStyle(color: Colors.grey), enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: isDark ? Colors.grey : Colors.grey[300]!)))), actions: [
      TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel', style: TextStyle(color: Colors.grey))),
      TextButton(onPressed: () async { if (folderController.text.isNotEmpty) { final db = await DatabaseService().database; await db.writeTxn(() async { final f = WorkoutFolder()..name = folderController.text; await db.workoutFolders.put(f); }); Navigator.pop(context); _refreshData(); ScaffoldMessenger.of(context).showSnackBar(SnackBar(backgroundColor: cardPurple, content: Text('Folder "${folderController.text}" created persistently!', style: TextStyle(color: isDark ? Colors.white : Colors.black)))); } }, child: const Text('Create', style: TextStyle(color: Colors.deepOrange))),
    ]));
  }

  Widget _buildAllExercisesTab(ScrollController controller) {
    final vh = MediaQuery.of(context).size.height;
    final so = _libraryScrollController.hasClients ? _libraryScrollController.offset : 0.0;
    final colors = Theme.of(context).colorScheme;

    return Column(children: [
      Padding(padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0), child: Row(children: [
        Expanded(child: TextField(controller: _searchController, onChanged: (v) { _searchQuery = v; _refreshData(); },
          decoration: InputDecoration(hintText: 'Find an exercise', prefixIcon: const Icon(Icons.search),
            fillColor: colors.surfaceContainerHighest, border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none)))),
        const SizedBox(width: 8),
        IconButton(
          tooltip: 'Filter exercises',
          icon: Icon(
            Icons.filter_list, 
            color: (_selectedMuscles.isEmpty && _selectedManufacturer == null && _selectedSort == 'a-z') 
                ? Colors.grey 
                : accentRed
          ), 
          onPressed: _showFilterDialog,
        ),
        const SizedBox(width: 4),
        IconButton(tooltip: 'Add exercise', onPressed: _showAddCustomExerciseDialog, icon: Icon(Icons.add, color: colors.primary)),
      ])),
      Expanded(child: FutureBuilder<List<Exercise>>(future: _exercisesFuture, builder: (context, snapshot) { 
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator()); 
        final exercises = snapshot.data!; 
        // Accurate viewport height for the drawer ListView
        final drawerListViewHeight = vh * 0.8 - 60;
        return ListView.builder(controller: _libraryScrollController, physics: const ClampingScrollPhysics(), itemCount: exercises.length, itemBuilder: (context, index) => _buildExerciseCard(exercises[index], index: index, scrollOffset: so, viewportHeight: drawerListViewHeight, baseOffset: 0)); 
      })),
    ]);
  }

  void _showAddCustomExerciseDialog() {
    final nameController = TextEditingController();
    final manufacturerController = TextEditingController();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    List<String> selectedTargetMuscles = [];
    List<String> selectedSecondaryMuscles = [];
    const allMuscles = ['chest', 'abs', 'obliques', 'front_deltoids', 'side_deltoids', 'back_deltoids', 'biceps', 'triceps', 'lats', 'lower_back', 'traps', 'quads', 'hamstrings', 'glutes', 'calves'];

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => AlertDialog(
          backgroundColor: cardPurple,
          title: Text('Add Custom Exercise', style: TextStyle(color: Theme.of(context).colorScheme.onSurface)),
          content: SizedBox(
            width: MediaQuery.of(context).size.width * 0.9,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: nameController,
                    onChanged: (_) => setModalState(() {}),
                    style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
                    decoration: InputDecoration(
                      hintText: "Exercise Name",
                      hintStyle: const TextStyle(color: Colors.grey),
                      enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: isDark ? Colors.white10 : Colors.black12)),
                    ),
                  ),
                  const SizedBox(height: 24),
                  const Text("MANUFACTURER (OPTIONAL)", style: TextStyle(color: Colors.grey, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
                  const SizedBox(height: 8),
                  TextField(
                    controller: manufacturerController,
                    style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
                    decoration: InputDecoration(
                      hintText: "e.g., Rogue, Life Fitness",
                      hintStyle: const TextStyle(color: Colors.grey),
                      enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: isDark ? Colors.white10 : Colors.black12)),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: ['Life Fitness', 'Hammer Strength', 'Hoist Roc-it'].map((m) {
                      return GestureDetector(
                        onTap: () {
                          manufacturerController.text = m;
                        },
                        child: Chip(
                          label: Text(
                            m,
                            style: TextStyle(
                              color: isDark ? Colors.grey[300] : Colors.black87,
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          backgroundColor: isDark ? bgDarkPurple : Colors.grey[200],
                          side: BorderSide.none,
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 24),
                  const Text("SELECT TARGET MUSCLES (MAIN)", style: TextStyle(color: Colors.grey, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: allMuscles.map((m) {
                      final isSelected = selectedTargetMuscles.contains(m);
                      return GestureDetector(
                        onTap: () => setModalState(() {
                          if (isSelected) {
                            selectedTargetMuscles.remove(m);
                          } else {
                            selectedTargetMuscles.add(m);
                            selectedSecondaryMuscles.remove(m);
                          }
                        }),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: isSelected ? accentRed : (isDark ? bgDarkPurple : Colors.grey[100]),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            m.replaceAll('_', ' ').toUpperCase(),
                            style: TextStyle(color: isSelected ? Colors.white : Colors.grey, fontSize: 10, fontWeight: FontWeight.bold),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 24),
                  const Text("SELECT SECONDARY MUSCLES", style: TextStyle(color: Colors.grey, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: allMuscles.map((m) {
                      final isSelected = selectedSecondaryMuscles.contains(m);
                      return GestureDetector(
                        onTap: () => setModalState(() {
                          if (isSelected) {
                            selectedSecondaryMuscles.remove(m);
                          } else {
                            selectedSecondaryMuscles.add(m);
                            selectedTargetMuscles.remove(m);
                          }
                        }),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: isSelected ? Colors.orange : (isDark ? bgDarkPurple : Colors.grey[100]),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            m.replaceAll('_', ' ').toUpperCase(),
                            style: TextStyle(color: isSelected ? Colors.white : Colors.grey, fontSize: 10, fontWeight: FontWeight.bold),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                  if (selectedTargetMuscles.isNotEmpty || selectedSecondaryMuscles.isNotEmpty) ...[
                    const SizedBox(height: 24),
                    const Text('Estimated muscle loading', style: TextStyle(fontWeight: FontWeight.w600)),
                    Text(MuscleFatigueService.profileSummary(MuscleFatigueService.muscleWeights(
                        nameController.text, selectedTargetMuscles, selectedSecondaryMuscles))),
                    const SizedBox(height: 8),
                    Container(
                      height: 150,
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(color: isDark ? bgDarkPurple : Colors.grey[100], borderRadius: BorderRadius.circular(16)),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          Expanded(
                            child: Stack(
                              alignment: Alignment.center,
                              children: [
                                SvgPicture.asset(
                                  'assets/body_front_base.svg',
                                  colorFilter: ColorFilter.mode(Color.lerp(cardPurple, Theme.of(context).colorScheme.onSurface, .24)!, BlendMode.srcIn),
                                ),
                                ...selectedSecondaryMuscles.where((m) => _isFrontMuscle(m)).map((m) => SvgPicture.asset(
                                  'assets/front_$m.svg',
                                  colorFilter: ColorFilter.mode(Colors.orange.withOpacity(0.8), BlendMode.srcIn),
                                )),
                                ...selectedTargetMuscles.where((m) => _isFrontMuscle(m)).map((m) => SvgPicture.asset(
                                  'assets/front_$m.svg',
                                  colorFilter: ColorFilter.mode(accentRed, BlendMode.srcIn),
                                )),
                              ],
                            ),
                          ),
                          Expanded(
                            child: Stack(
                              alignment: Alignment.center,
                              children: [
                                SvgPicture.asset(
                                  'assets/body_back_base.svg',
                                  colorFilter: ColorFilter.mode(isDark ? cardPurple : Colors.grey[300]!, BlendMode.srcIn),
                                ),
                                ...selectedSecondaryMuscles.where((m) => !_isFrontMuscle(m)).map((m) => SvgPicture.asset(
                                  'assets/back_$m.svg',
                                  colorFilter: ColorFilter.mode(Colors.orange.withOpacity(0.8), BlendMode.srcIn),
                                )),
                                ...selectedTargetMuscles.where((m) => !_isFrontMuscle(m)).map((m) => SvgPicture.asset(
                                  'assets/back_$m.svg',
                                  colorFilter: ColorFilter.mode(accentRed, BlendMode.srcIn),
                                )),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel", style: TextStyle(color: Colors.grey))),
            TextButton(
              onPressed: () async {
                if (nameController.text.isNotEmpty && selectedTargetMuscles.isNotEmpty) {
                  final db = await DatabaseService().database;
                  final manufacturerText = manufacturerController.text.trim();
                  final fullName = manufacturerText.isNotEmpty 
                      ? "$manufacturerText | ${nameController.text.trim()}" 
                      : nameController.text.trim();
                  await db.writeTxn(() async {
                    final ex = Exercise()
                      ..name = fullName
                      ..targetMuscle = selectedTargetMuscles.first
                      ..targetMuscles = selectedTargetMuscles
                      ..secondaryMuscles = selectedSecondaryMuscles
                      ..isFavorite = false;
                    await db.exercises.put(ex);
                  });
                  if (mounted) Navigator.pop(context);
                  _refreshData();
                }
              },
              child: const Text("Save", style: TextStyle(color: Colors.deepOrange, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  Future<List<Exercise>> _getFilteredExercises() async {
    final db = await DatabaseService().database;
    List<Exercise> results = await db.exercises.where().findAll();
    
    // Apply search filter
    if (_searchQuery.isNotEmpty) {
      results = results.where((ex) => ex.name.toLowerCase().contains(_searchQuery.toLowerCase())).toList();
    }
    
    // Apply manufacturer filter
    if (_selectedManufacturer != null) {
      results = results.where((ex) => ex.name.toLowerCase().contains(_selectedManufacturer!.toLowerCase())).toList();
    }
    
    // Apply target muscle filter
    if (_selectedMuscles.isNotEmpty) {
      results = results.where((ex) {
        final mains = ex.targetMuscles.isNotEmpty ? ex.targetMuscles : [ex.targetMuscle];
        return mains.any((m) => _selectedMuscles.contains(m));
      }).toList();
    }

    // Apply sorting
    if (_selectedSort == 'a-z') {
      results.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    } else if (_selectedSort == 'z-a') {
      results.sort((a, b) => b.name.toLowerCase().compareTo(a.name.toLowerCase()));
    } else if (_selectedSort == 'most-recent') {
      try {
        final workouts = await db.dailyWorkouts.where().sortByDateDesc().findAll();
        final Map<String, DateTime> lastLoggedMap = {};
        for (var w in workouts) {
          for (var ex in w.exercises) {
            if (ex.exerciseName != null) {
              lastLoggedMap.putIfAbsent(ex.exerciseName!, () => w.date);
            }
          }
        }
        results.sort((a, b) {
          final dateA = lastLoggedMap[a.name];
          final dateB = lastLoggedMap[b.name];
          if (dateA == null && dateB == null) return a.name.toLowerCase().compareTo(b.name.toLowerCase());
          if (dateA == null) return 1;
          if (dateB == null) return -1;
          return dateB.compareTo(dateA);
        });
      } catch (e) {
        debugPrint("Error sorting by most recent: $e");
        results.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      }
    }

    return results;
  }

  void _showFilterDialog() async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    const allMuscles = [
      'chest', 'abs', 'obliques', 'front_deltoids', 'side_deltoids', 
      'back_deltoids', 'biceps', 'triceps', 'lats', 'lower_back', 
      'traps', 'quads', 'hamstrings', 'glutes', 'calves'
    ];

    // Dynamically retrieve all unique manufacturers present in the database
    List<String> sortedManufacturers;
    try {
      final db = await DatabaseService().database;
      final exercises = await db.exercises.where().findAll();
      final manufacturers = <String>{};
      for (var ex in exercises) {
        final m = _parseManufacturer(ex.name);
        if (m != null) manufacturers.add(m);
      }
      sortedManufacturers = manufacturers.toList()..sort();
    } catch (e) {
      debugPrint("Error loading manufacturers: $e");
      sortedManufacturers = ['Life Fitness', 'Hammer Strength', 'Hoist Roc-it'];
    }

    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      backgroundColor: cardPurple,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setFilterState) {
            return DraggableScrollableSheet(
              initialChildSize: 0.65,
              minChildSize: 0.4,
              maxChildSize: 0.9,
              expand: false,
              builder: (context, scrollController) {
                return SingleChildScrollView(
                  controller: scrollController,
                  padding: const EdgeInsets.all(24.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            "Filters & Sorting",
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.onSurface,
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                              letterSpacing: -0.5,
                            ),
                          ),
                          TextButton(
                            onPressed: () {
                              setFilterState(() {
                                _selectedMuscles = [];
                                _selectedManufacturer = null;
                                _selectedSort = 'a-z';
                              });
                              _refreshData();
                            },
                            child: Text(
                              "Reset All",
                              style: TextStyle(
                                color: accentRed,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const Divider(height: 24, thickness: 1),
                      Text(
                        "SORT BY",
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.0,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          ChoiceChip(
                            label: const Text("A-Z"),
                            selected: _selectedSort == 'a-z',
                            onSelected: (selected) {
                              if (selected) {
                                setFilterState(() => _selectedSort = 'a-z');
                                _refreshData();
                              }
                            },
                            selectedColor: accentRed,
                            backgroundColor: isDark ? bgDarkPurple : Colors.grey[100],
                            side: BorderSide.none,
                            labelStyle: TextStyle(color: _selectedSort == 'a-z' ? Colors.white : (isDark ? Colors.grey : Colors.black87), fontSize: 10, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(width: 8),
                          ChoiceChip(
                            label: const Text("Z-A"),
                            selected: _selectedSort == 'z-a',
                            onSelected: (selected) {
                              if (selected) {
                                setFilterState(() => _selectedSort = 'z-a');
                                _refreshData();
                              }
                            },
                            selectedColor: accentRed,
                            backgroundColor: isDark ? bgDarkPurple : Colors.grey[100],
                            side: BorderSide.none,
                            labelStyle: TextStyle(color: _selectedSort == 'z-a' ? Colors.white : (isDark ? Colors.grey : Colors.black87), fontSize: 10, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(width: 8),
                          ChoiceChip(
                            label: const Text("MOST RECENT"),
                            selected: _selectedSort == 'most-recent',
                            onSelected: (selected) {
                              if (selected) {
                                setFilterState(() => _selectedSort = 'most-recent');
                                _refreshData();
                              }
                            },
                            selectedColor: accentRed,
                            backgroundColor: isDark ? bgDarkPurple : Colors.grey[100],
                            side: BorderSide.none,
                            labelStyle: TextStyle(color: _selectedSort == 'most-recent' ? Colors.white : (isDark ? Colors.grey : Colors.black87), fontSize: 10, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      Text(
                        "MANUFACTURER",
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.0,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: sortedManufacturers.map((m) {
                          final isSelected = _selectedManufacturer == m;
                          return ChoiceChip(
                            label: Text(m.toUpperCase()),
                            selected: isSelected,
                            onSelected: (selected) {
                              setFilterState(() {
                                _selectedManufacturer = selected ? m : null;
                              });
                              _refreshData();
                            },
                            selectedColor: accentRed,
                            backgroundColor: isDark ? bgDarkPurple : Colors.grey[100],
                            side: BorderSide.none,
                            labelStyle: TextStyle(
                              color: isSelected 
                                  ? Colors.white 
                                  : (isDark ? Colors.grey : Colors.black87),
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 24),
                      Text(
                        "TARGET MUSCLE",
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.0,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: allMuscles.map((muscle) {
                          bool isSelected = _selectedMuscles.contains(muscle);
                          return FilterChip(
                            label: Text(
                              muscle.replaceAll('_', ' ').toUpperCase(),
                              style: TextStyle(
                                color: isSelected ? Colors.white : Colors.grey,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            selected: isSelected,
                            onSelected: (selected) {
                              setFilterState(() {
                                if (selected) {
                                  _selectedMuscles.add(muscle);
                                } else {
                                  _selectedMuscles.remove(muscle);
                                }
                              });
                              _refreshData();
                            },
                            selectedColor: accentRed,
                            backgroundColor: isDark ? bgDarkPurple : Colors.grey[100],
                            checkmarkColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 32),
                    ],
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  void _showSettingsDialog() => showTrainingSettings(context,
      onImported: _initializeData);

  @override
  Widget build(BuildContext context) {
    final vh = MediaQuery.of(context).size.height;
    final so = _mainScrollController.hasClients ? _mainScrollController.offset : 0.0;
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Stack(children: [
        CustomScrollView(controller: _mainScrollController, slivers: [
          SliverToBoxAdapter(child: SafeArea(child: Padding(padding: const EdgeInsets.all(16.0), child: Column(children: [
            DashboardHeader(title: 'Workouts', onSettings: _showSettingsDialog, onNavigate: widget.onNavigateToRunning),
            const SizedBox(height: 20),
            Container(
              decoration: BoxDecoration(color: colors.surface, borderRadius: BorderRadius.circular(20),
                border: Border.all(color: colors.outlineVariant)),
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Weekly breakdown', style: theme.textTheme.titleLarge),
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(child: _buildMasterModel(isFront: true)),
                  _buildIntensityLegend(),
                  Expanded(child: _buildMasterModel(isFront: false)),
                ]),
              ]),
            ),
          ])))),
          SliverToBoxAdapter(child: Padding(padding: const EdgeInsets.fromLTRB(16, 8, 8, 8), child: Row(children: [
            Expanded(child: Text('Favorites', style: theme.textTheme.titleLarge)),
            SpringyButton(
              onTap: _showAIGeneratorDialog,
              child: Semantics(button: true, label: 'Ask Steel', excludeSemantics: true,
                child: Container(
                  constraints: const BoxConstraints(minHeight: 48),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(color: colors.surface, borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: colors.outlineVariant)),
                  child: Row(children: [Icon(Icons.auto_awesome, color: colors.primary, size: 18),
                    const SizedBox(width: 8), Text('Steel', style: theme.textTheme.labelLarge)]),
                )),
            ),
            IconButton(key: _createFolderKey, tooltip: 'Create folder', onPressed: _showCreateFolderDialog,
              icon: Icon(Icons.create_new_folder_outlined, color: colors.onSurfaceVariant)),
          ]))),
          _buildMainScreenFavorites(so, vh),
          const SliverToBoxAdapter(child: SizedBox(height: 150)),
        ]),
        DraggableScrollableSheet(
          controller: _sheetController, initialChildSize: 0.05, minChildSize: 0.05, maxChildSize: 0.95, snap: true,
          builder: (context, scrollController) {
            return Container(
              decoration: BoxDecoration(
                color: theme.scaffoldBackgroundColor,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: .14), blurRadius: 16, offset: const Offset(0, -3))],
                border: Border.all(color: colors.outlineVariant),
              ),
              child: ListView(controller: scrollController, padding: EdgeInsets.zero, physics: const ClampingScrollPhysics(), children: [
                GestureDetector(key: _appDrawerKey, onTap: () { if (_sheetSize < 0.5) _sheetController.animateTo(0.95, duration: const Duration(milliseconds: 300), curve: Curves.easeOut); else _sheetController.animateTo(0.05, duration: const Duration(milliseconds: 300), curve: Curves.easeIn); }, child: Container(width: double.infinity, padding: const EdgeInsets.symmetric(vertical: 8), color: Colors.transparent, child: Center(child: AnimatedRotation(duration: const Duration(milliseconds: 200), turns: _sheetSize > 0.5 ? 0.5 : 0.0, child: Icon(Icons.keyboard_arrow_up, color: colors.onSurfaceVariant, size: 24))))),
                if (_sheetSize > 0.15) ...[
                  TabBar(
                    controller: _tabController,
                    indicatorColor: accentRed,
                    labelColor: accentRed,
                    unselectedLabelColor: colors.onSurfaceVariant,
                    dividerColor: Colors.transparent,
                    indicatorWeight: 3,
                    tabs: [
                      Tab(key: _historyTabKey, child: Semantics(label: 'All Workouts', child: const Icon(Icons.calendar_month, size: 28))),
                      Tab(child: Semantics(label: 'Exercises', child: const Icon(Icons.fitness_center, size: 28))),
                    ],
                  ),
                  const SizedBox(height: 8),
                  SizedBox(height: MediaQuery.of(context).size.height * 0.8, child: TabBarView(controller: _tabController, children: [_buildHistoryTab(scrollController), _buildAllExercisesTab(scrollController)])),
                ],
              ]),
            );
          },
        ),
      ]),
    );
  }

  Widget _buildIntensityLegend() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final fatiguedColor = isDark ? Colors.redAccent : const Color(0xFFE65100);
    final recoveryColor = isDark ? Colors.blueAccent.withOpacity(0.5) : const Color(0xFF2E7D32);
    
    return Column(
      children: [
        Text('Fatigued', style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant)),
        const SizedBox(height: 8),
        Container(
          width: 8,
          height: 120,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(4),
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                fatiguedColor, // High
                isDark ? Colors.deepPurple : const Color(0xFFFFB74D), // Med
                recoveryColor, // Low
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text('Recovered', style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant)),
      ],
    );
  }

  Widget _buildMasterModel({required bool isFront}) {
    // Defines which muscles to show for each view
    final muscles = isFront 
      ? ['chest', 'abs', 'obliques', 'front_deltoids', 'side_deltoids', 'biceps', 'bicep_long_head', 'bicep_short_head', 'quads']
      : ['lats', 'lower_back', 'traps', 'back_deltoids', 'triceps', 'tricep_long_head', 'glutes', 'hamstrings', 'calves'];

    return GestureDetector(
      onTap: _showRecoveryPredictorDialog,
      child: Column(
        children: [
          SizedBox(
            height: 180, // Slightly shorter to fit legend
            width: 110,
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Base Body
                SvgPicture.asset(
                  isFront ? 'assets/body_front_base.svg' : 'assets/body_back_base.svg',
                  colorFilter: ColorFilter.mode(Color.lerp(cardPurple, Theme.of(context).colorScheme.onSurface, .24)!, BlendMode.srcIn),
                ),
                // Muscle Layers
                ...muscles.map((muscle) {
                  final intensity = _muscleIntensities[muscle] ?? 0.0;
                  if (intensity <= 0) return const SizedBox.shrink();
                  
                  // Map logical muscle name to asset path
                  final assetName = isFront ? 'front_$muscle' : 'back_$muscle';
                  return SvgPicture.asset(
                    'assets/$assetName.svg',
                    colorFilter: ColorFilter.mode(_getIntensityColor(intensity), BlendMode.srcIn),
                  );
                }),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Text(
            isFront ? 'Front' : 'Back',
            style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }

  void _showRecoveryPredictorDialog() {
    
    // Sort muscles by fatigue
    final sortedMuscles = _muscleIntensities.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
      
    showModalBottomSheet(
      context: context,
      backgroundColor: cardPurple,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text("Recovery Predictor", style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontSize: 22, fontWeight: FontWeight.bold, letterSpacing: -0.5)),
              const SizedBox(height: 8),
              Text("Estimated time until muscle groups are fully recovered.", style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 14)),
              const SizedBox(height: 24),
              if (sortedMuscles.isEmpty || sortedMuscles.every((m) => m.value < 0.1))
                Center(child: Text("All muscles fully recovered!", style: TextStyle(color: accentRed, fontWeight: FontWeight.bold)))
              else
                ...sortedMuscles.take(6).map((entry) {
                  final days = RecoveryPredictor.calculateDaysToRecovery(_recentMuscleWork, entry.key, DateTime.now());
                  final timeStr = RecoveryPredictor.formatRecoveryTime(days);
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12.0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(entry.key.replaceAll('_', ' ').toUpperCase(), style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontWeight: FontWeight.bold, fontSize: 14)),
                        Text(timeStr, style: TextStyle(color: days > 0 ? accentRed : Colors.green, fontWeight: FontWeight.bold, fontSize: 14)),
                      ],
                    ),
                  );
                }),
              const SizedBox(height: 16),
            ],
          ),
        );
      },
    );
  }

  Future<void> _showAIGeneratorDialog() async {
    final result = await showDialog<SteelChatDialogResult>(
      context: context,
      builder: (_) => SteelChatDialog(onDataChanged: () {
        _refreshData();
        _loadRecentMuscles();
      }),
    );
    if (!mounted || result == null) return;
    if (result.openPlanner) {
      _showWorkoutPlannerDialog();
    } else if (result.draft != null) {
      await _openLoggingSheet(result.draft!.exercise,
          draftSets: result.draft!.sets);
    }
  }

  void _showWorkoutPlannerDialog() {
    showDialog<String>(
      context: context,
      builder: (_) => NeedleWorkoutDialog(
        fatigue: _muscleIntensities,
        onDataChanged: () {
          _refreshData();
          _loadRecentMuscles();
        },
      ),
    ).then((folderName) {
      if (folderName == null || !mounted) return;
      _refreshData();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Saved $folderName to favorites.')),
      );
    });
  }

  Widget _buildMainScreenFavorites(double scrollOffset, double viewportHeight) {
    final colors = Theme.of(context).colorScheme;
    return FutureBuilder<Map<String, List<Exercise>>>(
      future: _favoritesFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting && _favoritesFuture == null) return const SliverToBoxAdapter(child: Center(child: CircularProgressIndicator()));
        if (!snapshot.hasData) return const SliverToBoxAdapter(child: Center(child: CircularProgressIndicator()));
        
        final grouped = snapshot.data!;
        final folders = grouped.keys.toList()..sort();

        if (folders.isEmpty) {
          return SliverToBoxAdapter(
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: colors.surface, borderRadius: BorderRadius.circular(16)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Long-press a library exercise to add it to a favorites folder.',
                    style: TextStyle(color: colors.onSurfaceVariant)),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  icon: const Icon(Icons.fitness_center, size: 18),
                  label: const Text('Browse exercises'),
                  onPressed: () {
                    _tabController.animateTo(1);
                    _sheetController.animateTo(.95, duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
                  },
                ),
              ]),
            ),
          );
        }

        int folderIndex = 0;
        int totalExerciseIndex = 0;
        return SliverMainAxisGroup(
          slivers: folders.map((folder) {
            final exercises = grouped[folder]!;
            return SliverToBoxAdapter(
              child: LegoPop(
                index: folderIndex++,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: ExpansionTile(
                    initiallyExpanded: false,
                    backgroundColor: colors.surface,
                    collapsedBackgroundColor: colors.surface,
                    tilePadding: const EdgeInsets.symmetric(horizontal: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    collapsedShape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    leading: Icon(Icons.folder_outlined, color: colors.primary, size: 24),
                    title: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(child: Text(folder, style: TextStyle(color: colors.onSurface, fontWeight: FontWeight.w600, fontSize: 16))),
                        IconButton(
                          tooltip: 'Delete folder',
                          icon: Icon(Icons.delete_outline, size: 18, color: colors.onSurfaceVariant),
                          onPressed: () => _deleteFolder(folder),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                        ),
                      ],
                    ),
                    children: exercises.isEmpty 
                      ? [Padding(padding: const EdgeInsets.all(16.0), child: Text("Long-press an exercise in the library to add it here.", style: TextStyle(color: colors.onSurfaceVariant, fontSize: 13)))]
                      : exercises.map((ex) => _buildExerciseCard(
                          ex, 
                          index: totalExerciseIndex++, 
                          scrollOffset: scrollOffset, 
                          viewportHeight: viewportHeight, 
                          baseOffset: 400,
                          useScaling: false,
                        )).toList(),
                  ),
                ),
              ),
            );
          }).toList(),
        );
      },
    );
  }

  void _deleteFolder(String folderName) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: cardPurple,
        title: Text("Delete Folder?"),
        content: Text("Are you sure you want to delete '$folderName'? Exercises inside will not be deleted, but they will be removed from this folder."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel", style: TextStyle(color: Colors.grey))),
          TextButton(
            onPressed: () async {
              final db = await DatabaseService().database;
              await db.writeTxn(() async {
                await db.workoutFolders.filter().nameEqualTo(folderName).deleteAll();
                final exercisesInFolder = await db.exercises.filter().folderNamesElementEqualTo(folderName).findAll();
                for (var ex in exercisesInFolder) {
                  ex.folderNames = List.from(ex.folderNames)..remove(folderName);
                  ex.folderName = ex.folderNames.isNotEmpty ? ex.folderNames.first : null;
                  if (ex.folderNames.isEmpty) {
                    ex.isFavorite = false; // Optionally unfavorite if no folders remain
                  }
                  await db.exercises.put(ex);
                }
              });
              if (mounted) {
                Navigator.pop(context);
                _refreshData();
              }
            }, 
            child: const Text("Delete", style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold))
          ),
        ]
      )
    );
  }

  Future<Map<String, List<Exercise>>> _loadGroupedFavorites() async {
    final db = await DatabaseService().database;
    final folders = await db.workoutFolders.where().sortByName().findAll();
    final favorites = await db.exercises.filter().isFavoriteEqualTo(true).sortByName().findAll();
    
    Map<String, List<Exercise>> grouped = {for (var f in folders) f.name: []};
    for (var ex in favorites) {
      if (ex.folderNames.isNotEmpty) {
        for (var folderName in ex.folderNames) {
          grouped.putIfAbsent(folderName, () => []).add(ex);
        }
      }
    }
    return grouped;
  }

  void _showHistoryYearPicker() async {
    final db = await DatabaseService().database;
    final allWorkouts = await db.dailyWorkouts.where().findAll();
    Set<int> availableYears = allWorkouts.map((w) => w.date.year).toSet();
    availableYears.add(DateTime.now().year);
    
    List<int> sortedYears = availableYears.toList()..sort((a, b) => b.compareTo(a));

    if (!mounted) return;


    showModalBottomSheet(
      context: context,
      backgroundColor: cardPurple,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                "Select Year",
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurface,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                height: 200,
                child: ListView.builder(
                  itemCount: sortedYears.length,
                  itemBuilder: (context, index) {
                    final year = sortedYears[index];
                    final isSelected = year == _selectedHistoryYear;
                    return ListTile(
                      title: Text(
                        '$year',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: isSelected ? accentRed : (Theme.of(context).colorScheme.onSurface),
                          fontSize: 20,
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                        ),
                      ),
                      onTap: () {
                        setState(() {
                          _selectedHistoryYear = year;
                        });
                        _refreshData();
                        Navigator.pop(context);
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _showWorkoutDetailsModal(DailyWorkout workout) {
    final bgColor = cardPurple;
    final textColor = Theme.of(context).colorScheme.onSurface;
    final weekdays = ['', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
    final weekday = weekdays[workout.date.weekday];
    final dateStr = '${workout.date.month.toString().padLeft(2, '0')}/${workout.date.day.toString().padLeft(2, '0')}';
    
    showModalBottomSheet(
      context: context,
      backgroundColor: bgColor,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom,
                left: 20,
                right: 20,
                top: 24,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            weekday.toUpperCase(),
                            style: TextStyle(
                              color: accentRed,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1.2,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            dateStr,
                            style: TextStyle(
                              color: textColor,
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                              letterSpacing: -0.5,
                            ),
                          ),
                        ],
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, color: Colors.grey, size: 24),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  const Divider(color: Colors.black12, height: 1),
                  const SizedBox(height: 16),
                  ConstrainedBox(
                    constraints: BoxConstraints(
                      maxHeight: MediaQuery.of(context).size.height * 0.5,
                    ),
                    child: SingleChildScrollView(
                      child: Column(
                        children: workout.exercises.asMap().entries.map((entry) {
                          int exIndex = entry.key;
                          LoggedExercise log = entry.value;
                          final tempEx = Exercise()
                            ..name = log.exerciseName ?? "Unknown"
                            ..targetMuscle = log.targetMuscle ?? "chest"
                            ..targetMuscles = log.targetMuscles.isNotEmpty ? log.targetMuscles : [log.targetMuscle ?? "chest"]
                            ..secondaryMuscles = log.secondaryMuscles;
                          return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            _buildExerciseCard(
                              tempEx,
                              showDate: false,
                              onTap: () {
                                Navigator.pop(context);
                                _openLoggingSheet(tempEx, editWorkout: workout, editExIndex: exIndex);
                              },
                              sets: log.sets,
                            ),
                            for (final (index, set) in log.sets.indexed)
                              if (set.sequence.isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.fromLTRB(24, 0, 16, 8),
                                  child: Text([
                                    'Set ${index + 1} · ${formatWeightReps(set.weight, set.reps)}',
                                    ...set.sequence.map(formatSetStep),
                                  ].join('\n'), style: Theme.of(context).textTheme.bodySmall),
                                ),
                          ]);
                        }).toList(),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            );
          },
        );
      },
    );
  }

  static const _sessionFrontMuscles = [
    'chest', 'abs', 'obliques', 'front_deltoids', 'side_deltoids',
    'biceps', 'bicep_long_head', 'bicep_short_head', 'quads',
  ];
  static const _sessionBackMuscles = [
    'lats', 'lower_back', 'traps', 'back_deltoids', 'triceps',
    'tricep_long_head', 'glutes', 'hamstrings', 'calves',
  ];

  Widget _buildWorkoutMuscleIcon(DailyWorkout workout, bool isDark) {
    final volumes = MuscleFatigueService.workoutLoad(workout);
    final peak = volumes.values.fold(0.15, (a, b) => a > b ? a : b);
    List<String> topMuscles(List<String> muscles) => muscles
      .where((muscle) => (volumes[muscle] ?? 0) > 0)
      .toList()
      ..sort((a, b) => (volumes[b] ?? 0).compareTo(volumes[a] ?? 0));

    Widget faceHeatmap({required bool isFront, required List<String> muscles}) {
      final shownMuscles = muscles.take(5).toList();
      final face = isFront ? 'Front' : 'Back';
      return Semantics(
        label: '$face muscle heatmap',
        child: Stack(
          alignment: Alignment.center,
          children: [
            SvgPicture.asset(
              isFront ? 'assets/body_front_base.svg' : 'assets/body_back_base.svg',
              colorFilter: ColorFilter.mode(isDark ? Colors.white24 : const Color(0xFFC9C5C2), BlendMode.srcIn),
            ),
            ...shownMuscles.map((muscle) => SvgPicture.asset(
              isFront ? 'assets/front_$muscle.svg' : 'assets/back_$muscle.svg',
              colorFilter: ColorFilter.mode(_getIntensityColor((volumes[muscle]! / peak).clamp(0.02, 1)), BlendMode.srcIn),
            )),
            Positioned(
              bottom: 0,
              child: Text(face.toUpperCase(), style: TextStyle(color: isDark ? Colors.white54 : Colors.black45, fontSize: 6, fontWeight: FontWeight.bold, letterSpacing: 0.7)),
            ),
          ],
        ),
      );
    }

    final frontMuscles = topMuscles(_sessionFrontMuscles);
    final backMuscles = topMuscles(_sessionBackMuscles);
    String summary(List<String> muscles) => muscles.take(5)
      .map((muscle) => muscle.replaceAll('_', ' '))
      .join(', ');
    final hasMuscles = frontMuscles.isNotEmpty || backMuscles.isNotEmpty;

    return Tooltip(
      message: hasMuscles
          ? 'Front: ${summary(frontMuscles)}\nBack: ${summary(backMuscles)}'
          : 'No muscle detail logged',
      child: Container(
        width: 54,
        height: 70,
        padding: const EdgeInsets.all(5),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: isDark ? Colors.white.withValues(alpha: 0.06) : Colors.black.withValues(alpha: 0.05)),
        ),
        child: FrontBackHeatmapFade(
          front: faceHeatmap(isFront: true, muscles: frontMuscles),
          back: faceHeatmap(isFront: false, muscles: backMuscles),
        ),
      ),
    );
  }

  Widget _buildHistoryTab(ScrollController controller) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return FutureBuilder<List<DailyWorkout>>(
      future: _historyFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting && _historyFuture == null) {
          return const Center(child: CircularProgressIndicator());
        }
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        
        final workouts = snapshot.data!
            .where((w) => w.date.year == _selectedHistoryYear)
            .toList()
          ..sort((a, b) => b.date.compareTo(a.date));
        
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(children: [
                Expanded(child: Text('All workouts', style: theme.textTheme.titleLarge)),
                TextButton.icon(onPressed: _showHistoryYearPicker, icon: const Icon(Icons.expand_more),
                  label: Text('$_selectedHistoryYear')),
              ]),
            ),
            Expanded(
              child: workouts.isEmpty
                  ? Center(
                      child: Text(
                        "No history for $_selectedHistoryYear.",
                        style: TextStyle(color: colors.onSurfaceVariant),
                      ),
                    )
                  : ListView.builder(
                      controller: controller,
                      physics: const ClampingScrollPhysics(),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      itemCount: workouts.length,
                      itemBuilder: (context, index) {
                        final workout = workouts[index];
                        final dateStr = DateFormat('EEEE, MMM d').format(workout.date);
                        final exCount = workout.exercises.length;
                        return Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          child: SpringyButton(
                            onTap: () => _showWorkoutDetailsModal(workout),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                              decoration: BoxDecoration(color: colors.surface, borderRadius: BorderRadius.circular(18),
                                border: Border.all(color: colors.outlineVariant)),
                              child: Row(children: [
                                _buildWorkoutMuscleIcon(workout, isDark),
                                const SizedBox(width: 16),
                                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                  Text(dateStr, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
                                  const SizedBox(height: 4),
                                  Text('$exCount ${exCount == 1 ? "exercise" : "exercises"}', style: TextStyle(color: colors.onSurfaceVariant)),
                                ])),
                                Icon(Icons.chevron_right_rounded, color: colors.onSurfaceVariant),
                              ]),
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        );
      },
    );
  }
}

class FormattedExerciseName extends StatelessWidget {
  final String fullName;
  final TextStyle style;
  final Color secondaryColor;

  const FormattedExerciseName({
    super.key,
    required this.fullName,
    required this.style,
    required this.secondaryColor,
  });

  @override
  Widget build(BuildContext context) {
    String name = fullName;
    String? manufacturer;
    String? detail;

    // Detect manufacturer prefixes
    if (name.startsWith("Hammer Strength ")) {
      manufacturer = "Hammer Strength";
      name = name.replaceFirst("Hammer Strength ", "");
    } else if (name.startsWith("Life Fitness ")) {
      manufacturer = "Life Fitness";
      name = name.replaceFirst("Life Fitness ", "");
    } else if (name.startsWith("Hoist Roc-it ")) {
      manufacturer = "Hoist Roc-it";
      name = name.replaceFirst("Hoist Roc-it ", "");
    }

    // Detect parenthesis details at the end
    final parenIndex = name.indexOf('(');
    if (parenIndex != -1 && name.endsWith(')')) {
      detail = name.substring(parenIndex + 1, name.length - 1);
      name = name.substring(0, parenIndex).trim();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (manufacturer != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 2.0),
            child: Text(
              manufacturer.toUpperCase(),
              style: TextStyle(
                color: secondaryColor,
                fontSize: 9,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.0,
              ),
            ),
          ),
        MarqueeText(text: name, style: style),
        if (detail != null)
          Padding(
            padding: const EdgeInsets.only(top: 2.0),
            child: Text(
              detail,
              style: TextStyle(
                color: secondaryColor,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
      ],
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:isar/isar.dart';
import '../models/fitness_schema.dart';
import '../services/database_service.dart';
import '../services/exercise_seed.dart';
import '../services/data_backup_service.dart';
import '../services/widget_service.dart';
import '../main.dart';
import '../widgets/lego_animations.dart';

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
    _scrollController = ScrollController();
    if (widget.text.length > 18) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _startScrolling());
    }
  }

  void _startScrolling() async {
    while (mounted && _scrollController.hasClients) {
      await Future.delayed(const Duration(seconds: 1)); // Shorter delay
      if (!mounted || !_scrollController.hasClients) return;
      double maxExtent = _scrollController.position.maxScrollExtent;
      double distance = maxExtent / 2;
      // Faster duration (30ms per pixel instead of 40ms)
      await _scrollController.animateTo(distance, duration: Duration(milliseconds: (distance * 30).toInt()), curve: Curves.linear);
      if (!mounted || !_scrollController.hasClients) return;
      _scrollController.jumpTo(0);
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
    return IgnorePointer(child: SingleChildScrollView(controller: _scrollController, scrollDirection: Axis.horizontal, physics: const NeverScrollableScrollPhysics(), child: Row(children: [Text(widget.text, style: effectiveStyle, maxLines: 1), const SizedBox(width: 40), Text(widget.text, style: effectiveStyle, maxLines: 1), const SizedBox(width: 40)])));
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

  final Color bgDarkPurple = const Color(0xFF120E15);
  final Color cardPurple = const Color(0xFF1A1523);
  final Color accentRed = const Color(0xFFD93846);

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this); 
    _initializeData();
    _sheetController.addListener(() { if (mounted) setState(() => _sheetSize = _sheetController.size); });
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

  // Sub-muscle to parent roll-up mapping. Volume from sub-muscles
  // is added to the parent so the body SVG heatmap lights up correctly.
  static const _subMuscleParent = {
    'bicep_short_head': 'biceps',
    'bicep_long_head': 'biceps',
    'tricep_long_head': 'triceps',
    'forearm': 'biceps', // forearm work generally accompanies bicep loading
    'upper_back': 'traps',
    'adductors': 'glutes',
  };

  // Fatigue thresholds in **volume-load units** (weight × reps summed over
  // the 7-day window). These represent the weekly volume-load at which a
  // muscle group reaches 100 % fatigue on the heatmap.
  //
  // Calibration notes (real-world sanity checks):
  //   • Large muscles (chest/quads/lats) — 4 exercises × 3 sets × 10 reps × 135 lb ≈ 16 200 lb·reps
  //   • Medium muscles (biceps/delts)   — 3 exercises × 3 sets × 12 reps × 40 lb  ≈  4 320 lb·reps
  //   • Small / isolation muscles       — 2 exercises × 3 sets × 15 reps × 25 lb  ≈  2 250 lb·reps
  //   • Bodyweight fallback weight used when weight == 0 is 25 lb.
  static const _fatigueThresholds = {
    // Large compound groups
    'chest': 14000.0, 'quads': 16000.0, 'lats': 14000.0,
    'lower_back': 12000.0, 'hamstrings': 10000.0,
    // Medium groups
    'biceps': 4000.0, 'triceps': 5000.0,
    'front_deltoids': 5000.0, 'side_deltoids': 3500.0, 'back_deltoids': 3000.0,
    'glutes': 10000.0, 'traps': 5000.0,
    // Small / isolation groups
    'abs': 3000.0, 'obliques': 2500.0, 'calves': 4000.0,
    'bicep_short_head': 2000.0, 'bicep_long_head': 2000.0,
    'tricep_long_head': 2500.0, 'forearm': 2000.0,
    'adductors': 3000.0, 'upper_back': 4000.0,
  };

  // Bodyweight stand-in when weight is logged as 0 (bodyweight exercises).
  static const double _bodyweightFallback = 25.0;

  Future<void> _loadRecentMuscles() async {
    final db = await DatabaseService().database;
    final now = DateTime.now();
    final sevenDaysAgo = now.subtract(const Duration(days: 7));
    final recentWorkouts = await db.dailyWorkouts.filter().dateGreaterThan(sevenDaysAgo).findAll();

    Map<String, double> muscleVolumes = {};

    void addVolume(String muscle, double amount) {
      muscleVolumes[muscle] = (muscleVolumes[muscle] ?? 0) + amount;
      // Roll up to parent group so the body SVG parent layer also lights up.
      final parent = _subMuscleParent[muscle];
      if (parent != null) {
        muscleVolumes[parent] = (muscleVolumes[parent] ?? 0) + amount;
      }
    }

    for (var workout in recentWorkouts) {
      // Time-decay: sessions today count at 100%, sessions 7 days ago at ~30%.
      final daysAgo = now.difference(workout.date).inHours / 24.0;
      final decayFactor = (1.0 - (daysAgo / 10.0)).clamp(0.3, 1.0);

      for (var log in workout.exercises) {
        // Compute volume-load per set: weight × reps.
        // For bodyweight exercises (weight == 0), use a fallback value.
        double exerciseVolumeLoad = 0.0;
        int totalSets = log.sets.length;
        for (var s in log.sets) {
          final effectiveWeight = s.weight > 0 ? s.weight : _bodyweightFallback;
          exerciseVolumeLoad += effectiveWeight * s.reps;
        }

        // High-rep endurance bonus: sets above 20 reps per set are
        // disproportionately fatiguing. Apply a 1.15× multiplier.
        if (totalSets > 0) {
          final avgRepsPerSet = log.sets.fold(0, (sum, s) => sum + s.reps) / totalSets;
          if (avgRepsPerSet > 20) {
            exerciseVolumeLoad *= 1.15;
          }
        }

        // Multi-set fatigue bonus: more sets = more cumulative fatigue.
        // 1–2 sets = 1.0×, 3 sets = 1.05×, 4 sets = 1.10×, 5+ = 1.15×.
        if (totalSets >= 5) exerciseVolumeLoad *= 1.15;
        else if (totalSets >= 4) exerciseVolumeLoad *= 1.10;
        else if (totalSets >= 3) exerciseVolumeLoad *= 1.05;

        // Apply time decay.
        exerciseVolumeLoad *= decayFactor;

        // Distribute to primary muscles (full credit).
        final mains = log.targetMuscles.isNotEmpty
            ? log.targetMuscles
            : (log.targetMuscle != null ? [log.targetMuscle!] : <String>[]);
        for (var main in mains) {
          addVolume(main, exerciseVolumeLoad);
        }
        // Secondary muscles receive 40% of the volume-load.
        for (var sec in log.secondaryMuscles) {
          addVolume(sec, exerciseVolumeLoad * 0.4);
        }
      }
    }

    // Convert raw volume-load to 0.0–1.0 intensity via per-muscle thresholds.
    const defaultThreshold = 3000.0;
    Map<String, double> intensities = {};
    muscleVolumes.forEach((muscle, volume) {
      final threshold = _fatigueThresholds[muscle] ?? defaultThreshold;
      intensities[muscle] = (volume / threshold).clamp(0.0, 1.0);
    });

    if (mounted) setState(() => _muscleIntensities = intensities);
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

  Future<void> _openLoggingSheet(Exercise exercise, {DailyWorkout? editWorkout, int? editExIndex, DateTime? targetDate}) async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? cardPurple : Colors.white;
    final textColor = isDark ? Colors.white : Colors.black87;

    double defaultWeight = 0.0;
    if (editWorkout == null) {
      try {
        final db = await DatabaseService().database;
        final lastWorkout = await db.dailyWorkouts
            .filter()
            .exercisesElement((q) => q.exerciseNameEqualTo(exercise.name))
            .sortByDateDesc()
            .findFirst();
        if (lastWorkout != null) {
          final loggedExs = lastWorkout.exercises.where((e) => e.exerciseName == exercise.name);
          final weights = loggedExs.expand((e) => e.sets).map((s) => s.weight).toList();
          if (weights.isNotEmpty) {
            defaultWeight = weights.reduce((curr, next) => curr < next ? curr : next);
          }
        }
      } catch (e) {
        debugPrint("Error fetching last workout weight: $e");
      }
    }

    List<SetLog> currentSets;
    if (editWorkout != null && editExIndex != null) {
      final existingEx = editWorkout.exercises[editExIndex];
      currentSets = existingEx.sets.map((s) => SetLog()..reps = s.reps..weight = s.weight).toList();
    } else { currentSets = [SetLog()..reps = 10..weight = defaultWeight]; }

    final mainMuscles = exercise.targetMuscles.isNotEmpty ? exercise.targetMuscles : [exercise.targetMuscle];
    final weightHint = defaultWeight % 1 == 0 ? defaultWeight.toInt().toString() : defaultWeight.toString();

    showModalBottomSheet(
      context: context, backgroundColor: bgColor, isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (context) {
        return StatefulBuilder(builder: (context, setModalState) {
          return Padding(
            padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom, left: 24, right: 24, top: 24),
            child: Column(
              mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(exercise.name, style: TextStyle(color: textColor, fontSize: 24, fontWeight: FontWeight.bold, letterSpacing: -0.5)),
                    Text('Primary: ${mainMuscles.map((m) => m.replaceAll('_', ' ')).join(', ').toUpperCase()}', style: TextStyle(color: accentRed, fontSize: 14, fontWeight: FontWeight.w600)),
                  ])),
                  Column(children: [
                    IconButton(iconSize: 28, onPressed: () async {
                      final picked = await showDatePicker(context: context, initialDate: DateTime.now(), firstDate: DateTime(2000), lastDate: DateTime.now());
                      if (picked != null) { Navigator.pop(context); _openLoggingSheet(exercise, targetDate: picked); }
                    }, icon: const Icon(Icons.calendar_today, color: Colors.grey)),
                    IconButton(icon: const Icon(Icons.add_circle, color: Colors.deepOrange, size: 32), onPressed: () => setModalState(() => currentSets.add(SetLog()..reps = 10..weight = defaultWeight))),
                  ])
                ]),
                const SizedBox(height: 16),
                ...List.generate(currentSets.length, (index) => Dismissible(
                  key: ValueKey('set_${index}_${currentSets.length}'),
                  direction: DismissDirection.startToEnd,
                  onDismissed: (_) => setModalState(() => currentSets.removeAt(index)),
                  background: Container(alignment: Alignment.centerLeft, padding: const EdgeInsets.only(left: 20), color: Colors.red.withOpacity(0.2), child: const Icon(Icons.delete, color: Colors.red)),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6.0),
                    child: Row(children: [
                      Expanded(flex: 1, child: Text('${index + 1}', style: TextStyle(color: textColor, fontSize: 18, fontWeight: FontWeight.bold))),
                      Expanded(flex: 2, child: Padding(padding: const EdgeInsets.symmetric(horizontal: 8.0), child: TextFormField(initialValue: currentSets[index].weight == defaultWeight && editWorkout == null ? '' : (currentSets[index].weight % 1 == 0 ? currentSets[index].weight.toInt().toString() : currentSets[index].weight.toString()), keyboardType: const TextInputType.numberWithOptions(decimal: true), inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'(^\d*\.?\d*)'))], style: TextStyle(color: textColor, fontWeight: FontWeight.bold), decoration: InputDecoration(filled: true, fillColor: isDark ? bgDarkPurple : Colors.grey[100], hintText: weightHint, hintStyle: const TextStyle(color: Colors.grey), suffixText: 'lbs', suffixStyle: const TextStyle(color: Colors.grey, fontSize: 14), border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none)), onChanged: (v) => currentSets[index].weight = double.tryParse(v) ?? 0.0))),
                      Expanded(flex: 2, child: Padding(padding: const EdgeInsets.symmetric(horizontal: 8.0), child: TextFormField(initialValue: currentSets[index].reps == 10 && editWorkout == null ? '' : currentSets[index].reps.toString(), keyboardType: TextInputType.number, inputFormatters: [FilteringTextInputFormatter.digitsOnly], style: TextStyle(color: textColor, fontWeight: FontWeight.bold), decoration: InputDecoration(filled: true, fillColor: isDark ? bgDarkPurple : Colors.grey[100], hintText: '10', hintStyle: const TextStyle(color: Colors.grey), border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none)), onChanged: (v) => currentSets[index].reps = int.tryParse(v) ?? 0))),
                    ]),
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
                    else { final finalDate = targetDate ?? DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day); await db.writeTxn(() async {
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
                  }, child: Text(editWorkout != null ? 'Update Log' : 'Log Workout', style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)))),
                ]),
                const SizedBox(height: 24),
              ],
            ),
          );
        });
      }
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
    final cardColor = isDark ? cardPurple : Colors.white;
    final textColor = isDark ? Colors.white : Colors.black87;
    final secondaryTextColor = isDark ? Colors.grey[400] : Colors.grey[600];
    final previewBg = isDark ? bgDarkPurple.withOpacity(0.5) : Colors.grey[100];

    final cardContent = SpringyButton(
      onTap: onTap ?? () => _openLoggingSheet(ex),
      onLongPress: () => _showFolderAssignmentDialog(ex),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        padding: const EdgeInsets.only(right: 16),
        height: 100,
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
              width: 100,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: previewBg,
                borderRadius: const BorderRadius.horizontal(left: Radius.circular(20)),
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
                padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    FormattedExerciseName(
                      fullName: ex.name,
                      style: TextStyle(color: textColor, fontSize: 18, fontWeight: FontWeight.bold, letterSpacing: -0.5),
                      secondaryColor: secondaryTextColor ?? Colors.grey,
                    ),
                    const SizedBox(height: 4),
                    if (sets != null && sets.isNotEmpty)
                      Text(
                        sets.map((s) => '${s.reps}x${s.weight.toInt()}').join(', '),
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
    );

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
              backgroundColor: isDark ? cardPurple : Colors.white,
              title: Text('Assign to Folders', style: TextStyle(color: isDark ? Colors.white : Colors.black87)),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
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
                              color: isDark ? Colors.white : Colors.black87,
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
                                ex.folderNames.remove(f.name);
                              } else {
                                ex.folderNames.add(f.name);
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
                      const Divider(color: Colors.black12),
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
                          ex.folderNames.clear();
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
                      style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontSize: 14),
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
                  onPressed: () async {
                    if (newFolderController.text.isNotEmpty) {
                      final newF = newFolderController.text;
                      await db.writeTxn(() async {
                        final existingFolder = await db.workoutFolders.filter().nameEqualTo(newF).findFirst();
                        if (existingFolder == null) {
                          final f = WorkoutFolder()..name = newF;
                          await db.workoutFolders.put(f);
                        }
                        if (!ex.folderNames.contains(newF)) {
                          ex.folderNames.add(newF);
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
                  child: const Text('Create & Add', style: TextStyle(color: Colors.deepOrange, fontWeight: FontWeight.bold)),
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
    showDialog(context: context, builder: (context) => AlertDialog(backgroundColor: isDark ? cardPurple : Colors.white, title: Text('Create New Folder', style: TextStyle(color: isDark ? Colors.white : Colors.black87)), content: TextField(controller: folderController, autofocus: true, style: TextStyle(color: isDark ? Colors.white : Colors.black87), decoration: InputDecoration(hintText: 'e.g., Push Day, Leg Day', hintStyle: const TextStyle(color: Colors.grey), enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: isDark ? Colors.grey : Colors.grey[300]!)))), actions: [
      TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel', style: TextStyle(color: Colors.grey))),
      TextButton(onPressed: () async { if (folderController.text.isNotEmpty) { final db = await DatabaseService().database; await db.writeTxn(() async { final f = WorkoutFolder()..name = folderController.text; await db.workoutFolders.put(f); }); Navigator.pop(context); _refreshData(); ScaffoldMessenger.of(context).showSnackBar(SnackBar(backgroundColor: isDark ? cardPurple : Colors.white, content: Text('Folder "${folderController.text}" created persistently!', style: TextStyle(color: isDark ? Colors.white : Colors.black)))); } }, child: const Text('Create', style: TextStyle(color: Colors.deepOrange))),
    ]));
  }

  Widget _buildAllExercisesTab(ScrollController controller) {
    final vh = MediaQuery.of(context).size.height;
    final so = _libraryScrollController.hasClients ? _libraryScrollController.offset : 0.0;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Column(children: [
      Padding(padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0), child: Row(children: [
        Expanded(child: TextField(controller: _searchController, style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontSize: 14), onChanged: (v) { _searchQuery = v; _refreshData(); }, decoration: InputDecoration(hintText: "Search library...", hintStyle: TextStyle(color: isDark ? Colors.grey[600] : Colors.grey[400]), prefixIcon: const Icon(Icons.search, color: Colors.grey, size: 20), filled: true, fillColor: isDark ? cardPurple : Colors.grey[100], contentPadding: const EdgeInsets.symmetric(vertical: 0), border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none)))),
        const SizedBox(width: 8),
        IconButton(
          icon: Icon(
            Icons.filter_list, 
            color: (_selectedMuscles.isEmpty && _selectedManufacturer == null && _selectedSort == 'a-z') 
                ? Colors.grey 
                : accentRed
          ), 
          onPressed: _showFilterDialog,
        ),
        const SizedBox(width: 4),
        TextButton(onPressed: _showAddCustomExerciseDialog, child: Text("+ Add", style: TextStyle(color: accentRed, fontWeight: FontWeight.bold))),
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
          backgroundColor: isDark ? cardPurple : Colors.white,
          title: Text('Add Custom Exercise', style: TextStyle(color: isDark ? Colors.white : Colors.black87)),
          content: SizedBox(
            width: MediaQuery.of(context).size.width * 0.9,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: nameController,
                    style: TextStyle(color: isDark ? Colors.white : Colors.black87),
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
                    style: TextStyle(color: isDark ? Colors.white : Colors.black87),
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
                    const Text("PREVIEW", style: TextStyle(color: Colors.grey, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
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
                                  colorFilter: ColorFilter.mode(isDark ? cardPurple : Colors.grey[300]!, BlendMode.srcIn),
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
      backgroundColor: isDark ? cardPurple : Colors.white,
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
                              color: isDark ? Colors.white : Colors.black87,
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
                          color: isDark ? Colors.grey[400] : Colors.grey[700],
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
                          color: isDark ? Colors.grey[400] : Colors.grey[700],
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
                          color: isDark ? Colors.grey[400] : Colors.grey[700],
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

  void _showSettingsDialog() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: isDark ? cardPurple : Colors.white,
        title: Text('Settings', style: TextStyle(color: isDark ? Colors.white : Colors.black)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(isDark ? Icons.light_mode : Icons.dark_mode, color: Colors.grey),
              title: Text(isDark ? 'Switch to Light Mode' : 'Switch to Dark Mode', style: TextStyle(color: isDark ? Colors.white : Colors.black87)),
              onTap: () {
                Navigator.pop(context);
                WorkoutApp.of(context)?.toggleTheme();
              },
            ),
            const Divider(color: Colors.black12),
            ListTile(
              leading: const Icon(Icons.upload, color: Colors.grey),
              title: Text('Export Data', style: TextStyle(color: isDark ? Colors.white : Colors.black87)),
              onTap: () async {
                Navigator.pop(context);
                final error = await DataBackupService.exportData();
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(backgroundColor: isDark ? cardPurple : Colors.white, content: Text(error ?? 'Data exported successfully', style: TextStyle(color: isDark ? Colors.white : Colors.black))),
                  );
                }
              },
            ),
            ListTile(
              leading: const Icon(Icons.download, color: Colors.grey),
              title: Text('Import Data', style: TextStyle(color: isDark ? Colors.white : Colors.black87)),
              onTap: () async {
                Navigator.pop(context);
                final error = await DataBackupService.importData();
                if (error == null) {
                  _initializeData();
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Data imported successfully')),
                    );
                  }
                } else {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(backgroundColor: Colors.red, content: Text('Import failed: $error', style: const TextStyle(color: Colors.white))),
                    );
                  }
                }
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close', style: TextStyle(color: Colors.grey)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final vh = MediaQuery.of(context).size.height;
    final so = _mainScrollController.hasClients ? _mainScrollController.offset : 0.0;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Stack(children: [
        CustomScrollView(controller: _mainScrollController, slivers: [
          SliverToBoxAdapter(child: SafeArea(child: Padding(padding: const EdgeInsets.all(16.0), child: Column(children: [
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              if (widget.onNavigateToRunning != null)
                SpringyButton(
                  onTap: widget.onNavigateToRunning,
                  child: const Icon(Icons.chevron_left, color: Colors.grey, size: 28),
                )
              else
                const SizedBox(width: 28), 
              Text('Weekly Breakdown', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w600, color: isDark ? Colors.white : Colors.black, letterSpacing: -0.5)), 
              const SizedBox(width: 28), 
            ]),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween, 
              children: [
                _buildMasterModel(isFront: true),
                _buildIntensityLegend(),
                _buildMasterModel(isFront: false),
              ]
            ),
          ])))),
          SliverToBoxAdapter(child: Padding(padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0), child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text('FAVORITES', style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontSize: 18, fontWeight: FontWeight.bold, letterSpacing: 1.0)), 
            SpringyButton(onTap: _showCreateFolderDialog, child: Icon(Icons.create_new_folder, color: isDark ? Colors.grey : Colors.black54, size: 20)),
          ]))),
          _buildMainScreenFavorites(so, vh),
          const SliverToBoxAdapter(child: SizedBox(height: 150)),
        ]),
        DraggableScrollableSheet(
          controller: _sheetController, initialChildSize: 0.05, minChildSize: 0.05, maxChildSize: 0.95, snap: true,
          builder: (context, scrollController) {
            return Container(
              decoration: BoxDecoration(
                color: isDark ? bgDarkPurple : Colors.white, 
                borderRadius: const BorderRadius.vertical(top: Radius.circular(32)), 
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(isDark ? 0.8 : 0.1), blurRadius: 30, offset: const Offset(0, -10))], 
                border: Border.all(color: isDark ? Colors.white.withOpacity(0.05) : Colors.black.withOpacity(0.05), width: 1)
              ),
              child: ListView(controller: scrollController, padding: EdgeInsets.zero, physics: const ClampingScrollPhysics(), children: [
                GestureDetector(onTap: () { if (_sheetSize < 0.5) _sheetController.animateTo(0.95, duration: const Duration(milliseconds: 300), curve: Curves.easeOut); else _sheetController.animateTo(0.05, duration: const Duration(milliseconds: 300), curve: Curves.easeIn); }, child: Container(width: double.infinity, padding: const EdgeInsets.symmetric(vertical: 8), color: Colors.transparent, child: Center(child: AnimatedRotation(duration: const Duration(milliseconds: 200), turns: _sheetSize > 0.5 ? 0.5 : 0.0, child: Icon(Icons.keyboard_arrow_up, color: isDark ? Colors.grey : Colors.black45, size: 24))))),
                if (_sheetSize > 0.15) ...[
                  TabBar(controller: _tabController, indicatorColor: accentRed, labelColor: accentRed, unselectedLabelColor: isDark ? Colors.grey[700] : Colors.grey[400], dividerColor: Colors.transparent, indicatorWeight: 3, tabs: const [Tab(icon: Icon(Icons.fitness_center, size: 28)), Tab(icon: Icon(Icons.history, size: 28))]),
                  const SizedBox(height: 8),
                  SizedBox(height: MediaQuery.of(context).size.height * 0.8, child: TabBarView(controller: _tabController, children: [_buildAllExercisesTab(scrollController), _buildHistoryTab(scrollController)])),
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
        Text("FATIGUED", style: TextStyle(fontSize: 7, fontWeight: FontWeight.bold, color: fatiguedColor, letterSpacing: 1.0)),
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
        Text("RECOVERY", style: TextStyle(fontSize: 7, fontWeight: FontWeight.bold, color: recoveryColor, letterSpacing: 1.0)),
      ],
    );
  }

  Widget _buildMasterModel({required bool isFront}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    // Defines which muscles to show for each view
    final muscles = isFront 
      ? ['chest', 'abs', 'obliques', 'front_deltoids', 'side_deltoids', 'biceps', 'bicep_long_head', 'bicep_short_head', 'quads']
      : ['lats', 'lower_back', 'traps', 'back_deltoids', 'triceps', 'tricep_long_head', 'glutes', 'hamstrings', 'calves'];

    return Column(
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
                colorFilter: ColorFilter.mode(isDark ? cardPurple : Colors.grey[300]!, BlendMode.srcIn),
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
          isFront ? "FRONT" : "BACK",
          style: TextStyle(color: isDark ? Colors.grey[700] : Colors.grey[400], fontSize: 9, fontWeight: FontWeight.bold, letterSpacing: 1.2),
        ),
      ],
    );
  }

  Widget _buildMainScreenFavorites(double scrollOffset, double viewportHeight) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return FutureBuilder<Map<String, List<Exercise>>>(
      future: _favoritesFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting && _favoritesFuture == null) return const SliverToBoxAdapter(child: Center(child: CircularProgressIndicator()));
        if (!snapshot.hasData) return const SliverToBoxAdapter(child: Center(child: CircularProgressIndicator()));
        
        final grouped = snapshot.data!;
        final folders = grouped.keys.toList()
          ..sort((a, b) => a == "Uncategorized" ? 1 : (b == "Uncategorized" ? -1 : a.compareTo(b)));

        if (folders.isEmpty) {
          return SliverToBoxAdapter(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(32.0),
                child: Text("Star exercises in the library to see them here.", style: TextStyle(color: Colors.grey[700], fontSize: 14)),
              ),
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
                child: Theme(
                  data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                  child: ExpansionTile(
                    initiallyExpanded: false,
                    backgroundColor: isDark ? Colors.transparent : Colors.grey[50],
                    leading: Icon(folder == "Uncategorized" ? Icons.folder_open : Icons.folder, color: accentRed.withOpacity(0.5), size: 20),
                    title: Text(folder.toUpperCase(), style: TextStyle(color: accentRed, fontWeight: FontWeight.bold, letterSpacing: 1.2, fontSize: 13)),
                    children: exercises.isEmpty 
                      ? [Padding(padding: const EdgeInsets.all(16.0), child: Text("Empty Folder. Long-press an exercise to move it here.", style: TextStyle(color: Colors.grey[800], fontSize: 11, fontStyle: FontStyle.italic)))]
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

  Future<Map<String, List<Exercise>>> _loadGroupedFavorites() async {
    final db = await DatabaseService().database;
    final folders = await db.workoutFolders.where().sortByName().findAll();
    final favorites = await db.exercises.filter().isFavoriteEqualTo(true).sortByName().findAll();
    
    Map<String, List<Exercise>> grouped = {for (var f in folders) f.name: []};
    for (var ex in favorites) {
      if (ex.folderNames.isEmpty) {
        grouped.putIfAbsent("Uncategorized", () => []).add(ex);
      } else {
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

    final isDark = Theme.of(context).brightness == Brightness.dark;

    showModalBottomSheet(
      context: context,
      backgroundColor: isDark ? cardPurple : Colors.white,
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
                  color: isDark ? Colors.white : Colors.black87,
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
                          color: isSelected ? accentRed : (isDark ? Colors.white : Colors.black87),
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? cardPurple : Colors.white;
    final textColor = isDark ? Colors.white : Colors.black87;
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
                          return _buildExerciseCard(
                            tempEx,
                            showDate: false,
                            onTap: () {
                              Navigator.pop(context);
                              _openLoggingSheet(tempEx, editWorkout: workout, editExIndex: exIndex);
                            },
                            sets: log.sets,
                          );
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

  Widget _buildHistoryTab(ScrollController controller) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final weekdays = ['', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
    
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
            Row(
              children: [
                GestureDetector(
                  onTap: _showHistoryYearPicker,
                  behavior: HitTestBehavior.opaque,
                  child: Padding(
                    padding: const EdgeInsets.only(left: 16.0, top: 12.0, bottom: 8.0),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '$_selectedHistoryYear',
                          style: TextStyle(
                            color: isDark ? Colors.white : Colors.black87,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(width: 4),
                        const Icon(Icons.keyboard_arrow_down, color: Colors.grey, size: 16),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            Expanded(
              child: workouts.isEmpty
                  ? Center(
                      child: Text(
                        "No history for $_selectedHistoryYear.",
                        style: TextStyle(color: isDark ? Colors.grey[700] : Colors.grey[400]),
                      ),
                    )
                  : ListView.builder(
                      controller: controller,
                      physics: const ClampingScrollPhysics(),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      itemCount: workouts.length,
                      itemBuilder: (context, index) {
                        final workout = workouts[index];
                        final dateStr = '${workout.date.month.toString().padLeft(2, '0')}/${workout.date.day.toString().padLeft(2, '0')}';
                        final dayOfWeek = weekdays[workout.date.weekday];
                        final exCount = workout.exercises.length;
                        
                        return Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          child: SpringyButton(
                            onTap: () => _showWorkoutDetailsModal(workout),
                            child: Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: isDark ? cardPurple : Colors.white,
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: isDark 
                                      ? Colors.white.withOpacity(0.02) 
                                      : Colors.black.withOpacity(0.05),
                                ),
                                boxShadow: isDark
                                    ? []
                                    : [
                                        BoxShadow(
                                          color: Colors.black.withOpacity(0.03),
                                          blurRadius: 8,
                                          offset: const Offset(0, 3),
                                        ),
                                      ],
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        dayOfWeek.toUpperCase(),
                                        style: TextStyle(
                                          color: accentRed,
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold,
                                          letterSpacing: 1.0,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        dateStr,
                                        style: TextStyle(
                                          color: isDark ? Colors.white : Colors.black87,
                                          fontSize: 20,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ],
                                  ),
                                  Row(
                                    children: [
                                      Text(
                                        '$exCount ${exCount == 1 ? "EXERCISE" : "EXERCISES"}',
                                        style: TextStyle(
                                          color: isDark ? Colors.grey[500] : Colors.grey[600],
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      const Icon(
                                        Icons.chevron_right,
                                        color: Colors.grey,
                                        size: 20,
                                      ),
                                    ],
                                  ),
                                ],
                              ),
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
              style: const TextStyle(
                color: Color(0xFFC05545), // Muted red/terracotta accent color
                fontSize: 9,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.0,
              ),
            ),
          ),
        MarqueeText(
          text: name,
          style: style,
        ),
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

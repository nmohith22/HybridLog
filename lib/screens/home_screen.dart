import 'package:flutter/material.dart';
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
  double _sheetSize = 0.05;

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
        if (ex.targetMuscle.contains('shoulder')) {
          ex.targetMuscle = ex.targetMuscle.replaceAll('shoulder', 'deltoids');
          changed = true;
        } else if (ex.targetMuscle.endsWith('deltoid')) {
          ex.targetMuscle = '${ex.targetMuscle}s';
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
          if (log.targetMuscle != null && (log.targetMuscle!.contains('shoulder') || log.targetMuscle!.endsWith('deltoid'))) {
            log.targetMuscle = log.targetMuscle!.replaceAll('shoulder', 'deltoids');
            if (!log.targetMuscle!.endsWith('s')) log.targetMuscle = '${log.targetMuscle}s';
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
    
    // Improved seeding check: count total exercises, if significantly less than seed, re-seed.
    final count = await db.exercises.count();
    if (count < initialExercises.length) {
      await db.writeTxn(() async {
        for (var exData in initialExercises) {
          final existing = await db.exercises.filter().nameEqualTo(exData['name']!).findFirst();
          if (existing != null) {
            existing.targetMuscle = exData['primary']!;
            existing.secondaryMuscles = List<String>.from(exData['secondary'] ?? []);
            await db.exercises.put(existing);
          } else {
            final newEx = Exercise()..name = exData['name']!..targetMuscle = exData['primary']!..secondaryMuscles = List<String>.from(exData['secondary'] ?? [])..isFavorite = false;
            await db.exercises.put(newEx);
          }
        }
      });
    }
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
    final sevenDaysAgo = DateTime.now().subtract(const Duration(days: 7));
    final recentWorkouts = await db.dailyWorkouts.filter().dateGreaterThan(sevenDaysAgo).findAll();
    Map<String, double> muscleVolumes = {}; 
    for (var workout in recentWorkouts) {
      for (var log in workout.exercises) {
        int reps = log.sets.fold(0, (sum, s) => sum + s.reps);
        if (log.targetMuscle != null) muscleVolumes[log.targetMuscle!] = (muscleVolumes[log.targetMuscle!] ?? 0) + reps;
        for (var sec in log.secondaryMuscles) muscleVolumes[sec] = (muscleVolumes[sec] ?? 0) + (reps * 0.5);
      }
    }
    const largeMuscles = ['chest', 'quads', 'lats', 'lower_back', 'abs', 'obliques', 'hamstrings'];
    const mediumMuscles = ['biceps', 'triceps', 'front_deltoids', 'side_deltoids', 'back_deltoids', 'glutes', 'traps'];
    Map<String, double> intensities = {};
    muscleVolumes.forEach((muscle, volume) {
      double threshold = 20.0; 
      if (largeMuscles.contains(muscle)) threshold = 48.0; 
      else if (mediumMuscles.contains(muscle)) threshold = 32.0;
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

  void _openLoggingSheet(Exercise exercise, {DailyWorkout? editWorkout, int? editExIndex, DateTime? targetDate}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? cardPurple : Colors.white;
    final textColor = isDark ? Colors.white : Colors.black87;

    List<SetLog> currentSets;
    if (editWorkout != null && editExIndex != null) {
      final existingEx = editWorkout.exercises[editExIndex];
      currentSets = existingEx.sets.map((s) => SetLog()..reps = s.reps..weight = s.weight).toList();
    } else { currentSets = [SetLog()..reps = 10..weight = 0.0]; }

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
                    Text('Primary: ${exercise.targetMuscle.replaceAll('_', ' ').toUpperCase()}', style: TextStyle(color: accentRed, fontSize: 14, fontWeight: FontWeight.w600)),
                  ])),
                  Column(children: [
                    IconButton(iconSize: 28, onPressed: () async {
                      final picked = await showDatePicker(context: context, initialDate: DateTime.now(), firstDate: DateTime(2000), lastDate: DateTime.now());
                      if (picked != null) { Navigator.pop(context); _openLoggingSheet(exercise, targetDate: picked); }
                    }, icon: const Icon(Icons.calendar_today, color: Colors.grey)),
                    IconButton(icon: const Icon(Icons.add_circle, color: Colors.deepOrange, size: 32), onPressed: () => setModalState(() => currentSets.add(SetLog()..reps = 10..weight = 0.0))),
                  ])
                ]),
                const SizedBox(height: 16),
                ...List.generate(currentSets.length, (index) => Dismissible(
                  key: UniqueKey(),
                  direction: DismissDirection.startToEnd,
                  onDismissed: (_) => setModalState(() => currentSets.removeAt(index)),
                  background: Container(alignment: Alignment.centerLeft, padding: const EdgeInsets.only(left: 20), color: Colors.red.withOpacity(0.2), child: const Icon(Icons.delete, color: Colors.red)),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6.0),
                    child: Row(children: [
                      Expanded(flex: 1, child: Text('${index + 1}', style: TextStyle(color: textColor, fontSize: 18, fontWeight: FontWeight.bold))),
                      Expanded(flex: 2, child: Padding(padding: const EdgeInsets.symmetric(horizontal: 8.0), child: TextFormField(initialValue: currentSets[index].weight == 0 ? '' : currentSets[index].weight.toString(), keyboardType: TextInputType.number, style: TextStyle(color: textColor, fontWeight: FontWeight.bold), decoration: InputDecoration(filled: true, fillColor: isDark ? bgDarkPurple : Colors.grey[100], border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none)), onChanged: (v) => currentSets[index].weight = double.tryParse(v) ?? 0.0))),
                      Expanded(flex: 2, child: Padding(padding: const EdgeInsets.symmetric(horizontal: 8.0), child: TextFormField(initialValue: currentSets[index].reps == 10 && editWorkout == null ? '' : currentSets[index].reps.toString(), keyboardType: TextInputType.number, style: TextStyle(color: textColor, fontWeight: FontWeight.bold), decoration: InputDecoration(filled: true, fillColor: isDark ? bgDarkPurple : Colors.grey[100], hintText: '10', hintStyle: const TextStyle(color: Colors.grey), border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none)), onChanged: (v) => currentSets[index].reps = int.tryParse(v) ?? 0))),
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
                      final loggedEx = LoggedExercise()..exerciseName = exercise.name..targetMuscle = exercise.targetMuscle..secondaryMuscles = exercise.secondaryMuscles..sets = currentSets;
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
    final isFront = _isFrontMuscle(ex.targetMuscle);
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
                  SvgPicture.asset(
                    isFront ? 'assets/front_${ex.targetMuscle}.svg' : 'assets/back_${ex.targetMuscle}.svg',
                    colorFilter: ColorFilter.mode(accentRed, BlendMode.srcIn),
                  ),
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
                    MarqueeText(
                      text: ex.name,
                      style: TextStyle(color: textColor, fontSize: 18, fontWeight: FontWeight.bold, letterSpacing: -0.5),
                    ),
                    const SizedBox(height: 2),
                    if (sets != null && sets.isNotEmpty)
                      Text(
                        sets.map((s) => '${s.reps}x${s.weight.toInt()}').join(', '),
                        style: TextStyle(color: secondaryTextColor, fontSize: 13, fontWeight: FontWeight.w500),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      )
                    else
                      Text(
                        ex.targetMuscle.replaceAll('_', ' ').toUpperCase(),
                        style: TextStyle(color: accentRed.withOpacity(0.8), fontSize: 12, fontWeight: FontWeight.w600, letterSpacing: 1.0),
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
    showDialog(context: context, builder: (context) {
      TextEditingController newFolderController = TextEditingController();
      return AlertDialog(
        backgroundColor: isDark ? cardPurple : Colors.white, 
        title: Text('Move to Folder', style: TextStyle(color: isDark ? Colors.white : Colors.black87)),
        content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
          if (folders.isNotEmpty) ...[
            Align(alignment: Alignment.centerLeft, child: Text('EXISTING FOLDERS', style: TextStyle(color: isDark ? Colors.grey : Colors.grey[600], fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1.0))),
            const SizedBox(height: 8),
            ...folders.map((f) => ListTile(contentPadding: EdgeInsets.zero, leading: const Icon(Icons.folder, color: Colors.grey, size: 20), title: Text(f.name, style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontSize: 14)), trailing: ex.folderName == f.name ? const Icon(Icons.check, color: Colors.deepOrange, size: 18) : null, onTap: () async { await db.writeTxn(() async { ex.folderName = f.name; ex.isFavorite = true; await db.exercises.put(ex); }); Navigator.pop(context); _refreshData(); })),
            const Divider(color: Colors.black12),
          ],
          ListTile(contentPadding: EdgeInsets.zero, leading: const Icon(Icons.folder_open, color: Colors.grey, size: 20), title: Text('Uncategorized', style: TextStyle(color: isDark ? Colors.grey : Colors.grey[600], fontSize: 14)), onTap: () async { await db.writeTxn(() async { ex.folderName = null; await db.exercises.put(ex); }); Navigator.pop(context); _refreshData(); }),
          const SizedBox(height: 16), Align(alignment: Alignment.centerLeft, child: Text('CREATE NEW', style: TextStyle(color: isDark ? Colors.grey : Colors.grey[600], fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1.0))),
          TextField(controller: newFolderController, style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontSize: 14), decoration: InputDecoration(hintText: 'New Folder Name', hintStyle: const TextStyle(color: Colors.grey, fontSize: 14), enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: isDark ? Colors.white10 : Colors.black12)))),
        ])),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel', style: TextStyle(color: Colors.grey))),
          TextButton(onPressed: () async { if (newFolderController.text.isNotEmpty) { final newF = newFolderController.text; await db.writeTxn(() async { final f = WorkoutFolder()..name = newF; await db.workoutFolders.put(f); ex.folderName = newF; ex.isFavorite = true; await db.exercises.put(ex); }); Navigator.pop(context); _refreshData(); } }, child: const Text('Move', style: TextStyle(color: Colors.deepOrange, fontWeight: FontWeight.bold))),
        ],
      );
    });
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
        IconButton(icon: Icon(Icons.filter_list, color: _selectedMuscles.isEmpty ? Colors.grey : accentRed), onPressed: _showFilterDialog),
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    String? selectedMuscle;
    const allMuscles = ['chest', 'abs', 'obliques', 'front_deltoids', 'side_deltoids', 'back_deltoids', 'biceps', 'triceps', 'lats', 'lower_back', 'traps', 'quads', 'hamstrings', 'glutes', 'calves'];

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => AlertDialog(
          backgroundColor: isDark ? cardPurple : Colors.white,
          title: Text('Add Custom Exercise', style: TextStyle(color: isDark ? Colors.white : Colors.black87)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
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
                const Align(alignment: Alignment.centerLeft, child: Text("SELECT TARGET MUSCLE", style: TextStyle(color: Colors.grey, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1.2))),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: allMuscles.map((m) {
                    final isSelected = selectedMuscle == m;
                    return GestureDetector(
                      onTap: () => setModalState(() => selectedMuscle = m),
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
                if (selectedMuscle != null) ...[
                  const SizedBox(height: 24),
                  const Align(alignment: Alignment.centerLeft, child: Text("PREVIEW", style: TextStyle(color: Colors.grey, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1.2))),
                  const SizedBox(height: 8),
                  Container(
                    height: 120,
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(color: isDark ? bgDarkPurple : Colors.grey[100], borderRadius: BorderRadius.circular(16)),
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        SvgPicture.asset(
                          _isFrontMuscle(selectedMuscle!) ? 'assets/body_front_base.svg' : 'assets/body_back_base.svg',
                          colorFilter: ColorFilter.mode(isDark ? cardPurple : Colors.grey[300]!, BlendMode.srcIn),
                        ),
                        SvgPicture.asset(
                          _isFrontMuscle(selectedMuscle!) ? 'assets/front_$selectedMuscle.svg' : 'assets/back_$selectedMuscle.svg',
                          colorFilter: ColorFilter.mode(accentRed, BlendMode.srcIn),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel", style: TextStyle(color: Colors.grey))),
            TextButton(
              onPressed: () async {
                if (nameController.text.isNotEmpty && selectedMuscle != null) {
                  final db = await DatabaseService().database;
                  await db.writeTxn(() async {
                    final ex = Exercise()
                      ..name = nameController.text
                      ..targetMuscle = selectedMuscle!
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
    List<Exercise> results = await db.exercises.where().sortByName().findAll();
    if (_searchQuery.isNotEmpty) results = results.where((ex) => ex.name.toLowerCase().contains(_searchQuery.toLowerCase())).toList();
    if (_selectedMuscles.isNotEmpty) results = results.where((ex) => _selectedMuscles.contains(ex.targetMuscle)).toList();
    return results;
  }

  void _showFilterDialog() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    const allMuscles = ['chest', 'abs', 'obliques', 'front_deltoids', 'side_deltoids', 'back_deltoids', 'biceps', 'triceps', 'lats', 'lower_back', 'traps', 'quads', 'hamstrings', 'glutes', 'calves'];
    showModalBottomSheet(context: context, backgroundColor: isDark ? cardPurple : Colors.white, shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))), builder: (context) {
      return StatefulBuilder(builder: (context, setFilterState) {
        return Padding(padding: const EdgeInsets.all(24.0), child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text("Filter by Muscle", style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontSize: 20, fontWeight: FontWeight.bold)), TextButton(onPressed: () { setFilterState(() => _selectedMuscles = []); _refreshData(); }, child: Text("Clear All", style: TextStyle(color: accentRed)))]),
          const SizedBox(height: 16),
          Wrap(spacing: 8, runSpacing: 8, children: allMuscles.map((muscle) { bool isSelected = _selectedMuscles.contains(muscle); return FilterChip(label: Text(muscle.replaceAll('_', ' ').toUpperCase(), style: TextStyle(color: isSelected ? Colors.white : Colors.grey, fontSize: 10, fontWeight: FontWeight.bold)), selected: isSelected, onSelected: (selected) { setFilterState(() { if (selected) _selectedMuscles.add(muscle); else _selectedMuscles.remove(muscle); }); _refreshData(); }, selectedColor: accentRed, backgroundColor: isDark ? bgDarkPurple : Colors.grey[100], checkmarkColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))); }).toList()),
          const SizedBox(height: 32),
        ]));
      });
    });
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
                  child: Icon(Icons.chevron_right, color: accentRed.withOpacity(0.3), size: 24),
                )
              else
                const SizedBox(width: 24), 
              Text('Weekly Breakdown', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w600, color: isDark ? Colors.white : Colors.black, letterSpacing: -0.5)), 
              SpringyButton(onTap: _showSettingsDialog, child: Icon(Icons.settings, color: isDark ? Colors.grey : Colors.black54, size: 22)),
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
      final folder = ex.folderName ?? "Uncategorized";
      grouped.putIfAbsent(folder, () => []).add(ex);
    }
    return grouped;
  }

  Widget _buildHistoryTab(ScrollController controller) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return FutureBuilder<List<DailyWorkout>>(
      future: _historyFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting && _historyFuture == null) return const Center(child: CircularProgressIndicator());
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        final workouts = snapshot.data!;
        if (workouts.isEmpty) return Center(child: Text("No history yet.", style: TextStyle(color: Colors.grey[700])));
        
        // Group by Year and Month for collapsible view
        Map<int, Map<int, List<DailyWorkout>>> grouped = {};
        for (var w in workouts) {
          grouped.putIfAbsent(w.date.year, () => {}).putIfAbsent(w.date.month, () => []).add(w);
        }
        final years = grouped.keys.toList()..sort((a, b) => b.compareTo(a));

        return ListView.builder(controller: controller, physics: const ClampingScrollPhysics(), itemCount: years.length, itemBuilder: (context, yIdx) {
          int year = years[yIdx];
          final months = grouped[year]!.keys.toList()..sort((a, b) => b.compareTo(a));
          return ExpansionTile(
            initiallyExpanded: yIdx == 0,
            title: Text('$year', style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontWeight: FontWeight.bold)),
            children: months.map((month) {
              final days = grouped[year]![month]!;
              return ExpansionTile(
                title: Text(['', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'][month], style: TextStyle(color: accentRed, fontWeight: FontWeight.w600)),
                children: days.map((workout) {
                  return ExpansionTile(
                    title: Text('${workout.date.month}/${workout.date.day}', style: TextStyle(color: isDark ? Colors.grey : Colors.grey[600], fontSize: 14)),
                    trailing: Text('${workout.exercises.length} Exs', style: TextStyle(color: isDark ? Colors.grey : Colors.grey[600], fontSize: 12)),
                    children: workout.exercises.asMap().entries.map((entry) {
                      int exIndex = entry.key; LoggedExercise log = entry.value;
                      final tempEx = Exercise()..name = log.exerciseName ?? "Unknown"..targetMuscle = log.targetMuscle ?? "chest"..secondaryMuscles = log.secondaryMuscles;
                      return _buildExerciseCard(tempEx, showDate: false, onTap: () => _openLoggingSheet(tempEx, editWorkout: workout, editExIndex: exIndex), sets: log.sets);
                    }).toList(),
                  );
                }).toList(),
              );
            }).toList(),
          );
        });
      },
    );
  }
}

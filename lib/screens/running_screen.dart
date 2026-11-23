import 'dart:async';

import 'package:flutter/material.dart';
import 'package:isar/isar.dart';
import '../services/database_service.dart';
import '../models/fitness_schema.dart';
import '../widgets/yearly_heatmap_calendar.dart';
import '../widgets/running_block_graph.dart';
import '../widgets/dashboard_header.dart';
import '../widgets/lego_animations.dart';
import '../widgets/theme_picker_widget.dart';
import '../services/tutorial_service.dart';
import '../widgets/weather_advice_widget.dart';

class RunningScreen extends StatefulWidget {
  final VoidCallback? onNavigateToWorkout;
  const RunningScreen({super.key, this.onNavigateToWorkout});

  @override
  State<RunningScreen> createState() => _RunningScreenState();
}

class _RunningScreenState extends State<RunningScreen> {
  int _yearlyTotal = 0;
  int _selectedYear = DateTime.now().year;
  bool _isGraphInteracting = false;
  StreamSubscription<void>? _runningLogSubscription;

  final GlobalKey _runningGraphKey = GlobalKey();
  final GlobalKey _runningYearlyHistoryKey = GlobalKey();
  final GlobalKey _swipeNavKey = GlobalKey();
  final GlobalKey _settingsKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _calculateYearlyTotal();
    _runningLogSubscription = DatabaseService().watchRunningLogs().listen(
      (_) => _calculateYearlyTotal(),
      onError: (Object error) => debugPrint('Running log refresh failed: $error'),
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkTutorial();
    });
  }

  @override
  void dispose() {
    _runningLogSubscription?.cancel();
    super.dispose();
  }

  Future<void> _checkTutorial() async {
    bool hasSeen = await TutorialService.hasSeenTutorial();
    if (!hasSeen && mounted) {
      TutorialService.showMainTutorial(
        context: context,
        runningGraphKey: _runningGraphKey,
        runningYearlyHistoryKey: _runningYearlyHistoryKey,
        settingsKey: _settingsKey,
        swipeNavKey: _swipeNavKey,
        onNavigateToWorkout: widget.onNavigateToWorkout ?? () {},
        onFinish: () async {
          await TutorialService.markTutorialSeen();
          if (widget.onNavigateToWorkout != null) {
            widget.onNavigateToWorkout!();
            Future.delayed(const Duration(milliseconds: 600), () async {
              if (TutorialService.createFolderKey?.currentContext != null) {
                bool hasSeenWorkout = await TutorialService.hasSeenWorkoutTutorial();
                if (!hasSeenWorkout) {
                  TutorialService.showWorkoutTutorial(
                    context: TutorialService.createFolderKey!.currentContext!,
                    createFolderKey: TutorialService.createFolderKey!,
                    exerciseCardKey: TutorialService.exerciseCardKey!,
                    appDrawerKey: TutorialService.appDrawerKey!,
                    historyTabKey: TutorialService.historyTabKey!,
                    onFinish: () async {
                      await TutorialService.markWorkoutTutorialSeen();
                    }
                  );
                }
              }
            });
          }
        }
      );
    }
  }


  void _showSettingsDialog() => showTrainingSettings(context,
      onImported: _calculateYearlyTotal, onReplayTutorial: () async {
        await TutorialService.resetTutorial();
        if (mounted) await _checkTutorial();
      });

  Future<void> _calculateYearlyTotal() async {
    final db = await DatabaseService().database;
    final startOfYear = DateTime(_selectedYear, 1, 1);
    final endOfYear = DateTime(_selectedYear, 12, 31, 23, 59, 59);
    
    final logs = await db.runningLogs.filter()
        .dateBetween(startOfYear, endOfYear)
        .findAll();
        
    if (mounted) {
      setState(() {
        _yearlyTotal = logs.fold(0, (sum, log) => sum + log.miles);
      });
    }
  }

  void _showYearPicker() async {
    final db = await DatabaseService().database;
    final allLogs = await db.runningLogs.where().findAll();
    Set<int> availableYears = allLogs.map((l) => l.date.year).toSet();
    availableYears.add(DateTime.now().year); 
    
    List<int> sortedYears = availableYears.toList()..sort((a, b) => b.compareTo(a));

    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (context) {
        final theme = Theme.of(context);
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text("Select Year", style: TextStyle(color: theme.colorScheme.onSurface, fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              SizedBox(
                height: 200,
                child: ListView.builder(
                  itemCount: sortedYears.length,
                  itemBuilder: (context, index) {
                    final year = sortedYears[index];
                    final isSelected = year == _selectedYear;
                    return ListTile(
                      title: Text('$year', textAlign: TextAlign.center, style: TextStyle(color: isSelected ? theme.colorScheme.primary : theme.colorScheme.onSurface, fontSize: 20, fontWeight: isSelected ? FontWeight.bold : FontWeight.normal)),
                      onTap: () {
                        setState(() {
                          _selectedYear = year;
                        });
                        _calculateYearlyTotal();
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Scaffold(
          backgroundColor: Theme.of(context).scaffoldBackgroundColor,
          body: SafeArea(
            child: SingleChildScrollView(
              physics: _isGraphInteracting ? const NeverScrollableScrollPhysics() : const BouncingScrollPhysics(),
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  DashboardHeader(
                    title: 'Running',
                    running: true,
                    onNavigate: widget.onNavigateToWorkout,
                    onSettings: _showSettingsDialog,
                    navigationKey: _swipeNavKey,
                    settingsKey: _settingsKey,
                  ),
                  const SizedBox(height: 20),
                  Material(
                    color: colors.surface,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                    clipBehavior: Clip.antiAlias,
                    child: ListTile(
                      onTap: _showYearPicker,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                      title: Text('Distance in $_selectedYear', style: theme.textTheme.labelLarge),
                      subtitle: Text('$_yearlyTotal mi', style: theme.textTheme.headlineMedium),
                      trailing: Icon(Icons.expand_more, color: colors.onSurfaceVariant),
                    ),
                  ),
                  const SizedBox(height: 16),
                  LegoPop(
                    index: 0,
                    child: Container(
                      key: _runningGraphKey,
                      child: RunningBlockGraph(
                      dbService: DatabaseService(),
                      onInteractionChanged: (isInteracting) {
                        setState(() => _isGraphInteracting = isInteracting);
                      },
                    ),
                    ),
                  ),
                  
                  const SizedBox(height: 24),

                  const LegoPop(index: 1, child: WeatherAdviceWidget()),

                  const SizedBox(height: 24),

                  LegoPop(
                    index: 2,
                    child: Container(
                      key: _runningYearlyHistoryKey,
                      child: YearlyHeatmapCalendar(
                        dbService: DatabaseService(),
                        selectedYear: _selectedYear,
                        onYearChanged: (year) {
                          setState(() {
                            _selectedYear = year;
                          });
                          _calculateYearlyTotal();
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: 40), 
                ],
              ),
            ),
          ),
        );
  }
}

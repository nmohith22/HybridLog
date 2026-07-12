import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:isar/isar.dart';
import 'package:intl/intl.dart';
import '../models/fitness_schema.dart';
import '../services/database_service.dart';
import '../services/theme_service.dart';

class ExerciseHistoryScreen extends StatefulWidget {
  final Exercise exercise;
  const ExerciseHistoryScreen({super.key, required this.exercise});

  @override
  State<ExerciseHistoryScreen> createState() => _ExerciseHistoryScreenState();
}

class _ExerciseHistoryScreenState extends State<ExerciseHistoryScreen> {
  List<DailyWorkout> _history = [];
  bool _isLoading = true;
  int _selectedLineIndex = -1;

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    final db = await DatabaseService().database;
    final workouts = await db.dailyWorkouts
        .filter()
        .exercisesElement((q) => q.exerciseNameEqualTo(widget.exercise.name))
        .sortByDate()
        .findAll();

    if (mounted) {
      setState(() {
        _history = workouts;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = ThemeService().getResolvedTheme(context);
    final isDark = theme.isDark;
    final textColor = theme.text;
    final bgColor = theme.background;
    final cardColor = theme.card;

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: bgColor,
        elevation: 0,
        iconTheme: IconThemeData(color: textColor),
        title: Text('${widget.exercise.name} History', style: TextStyle(color: textColor, fontWeight: FontWeight.bold)),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _history.isEmpty
              ? Center(child: Text("No history yet.", style: TextStyle(color: theme.subText)))
              : Column(
                  children: [
                    _buildChart(theme),
                    _buildMetrics(theme),
                    Expanded(
                      child: ListView.builder(
                        itemCount: _history.length,
                        itemBuilder: (context, index) {
                          // Reverse the list for display so newest is on top
                          final workout = _history[_history.length - 1 - index];
                          final loggedEx = workout.exercises.firstWhere((e) => e.exerciseName == widget.exercise.name);
                          
                          return Container(
                            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: cardColor,
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  DateFormat('EEEE, MMM d, yyyy').format(workout.date),
                                  style: TextStyle(color: textColor, fontWeight: FontWeight.bold, fontSize: 16),
                                ),
                                const SizedBox(height: 8),
                                ...loggedEx.sets.asMap().entries.map((entry) {
                                  final setIdx = entry.key;
                                  final s = entry.value;
                                  return Padding(
                                    padding: const EdgeInsets.symmetric(vertical: 4.0),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Text('Set ${setIdx + 1}: ', style: TextStyle(color: theme.subText, fontWeight: FontWeight.bold)),
                                            Text('${s.weight} lbs x ${s.reps} reps', style: TextStyle(color: textColor)),
                                          ],
                                        ),
                                        if (s.subSets.isNotEmpty)
                                          Padding(
                                            padding: const EdgeInsets.only(left: 16.0, top: 4.0),
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: s.subSets.map((sub) => Text('Drop: ${sub.weight} lbs x ${sub.reps} reps', style: TextStyle(color: theme.accent, fontSize: 12))).toList(),
                                            ),
                                          ),
                                        if (s.restPauseSeconds != null)
                                          Padding(
                                            padding: const EdgeInsets.only(left: 16.0, top: 2.0),
                                            child: Text('Rest pause: ${s.restPauseSeconds}s', style: const TextStyle(color: Colors.orange, fontSize: 12)),
                                          )
                                      ],
                                    ),
                                  );
                                }),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
    );
  }

  Widget _buildChart(AppTheme theme) {
    if (_history.length < 2) {
      return Padding(
        padding: const EdgeInsets.all(16.0),
        child: Text("Not enough data for chart.", style: TextStyle(color: theme.subText)),
      );
    }

    List<FlSpot> weightSpots = [];
    List<FlSpot> repsSpots = [];

    for (int i = 0; i < _history.length; i++) {
      final workout = _history[i];
      final loggedEx = workout.exercises.firstWhere((e) => e.exerciseName == widget.exercise.name);
      
      double maxWeight = 0;
      int totalReps = 0;
      for (var s in loggedEx.sets) {
        if (s.weight > maxWeight) maxWeight = s.weight;
        totalReps += s.reps;
        for (var sub in s.subSets) {
          if (sub.weight > maxWeight) maxWeight = sub.weight;
          totalReps += sub.reps;
        }
      }

      weightSpots.add(FlSpot(i.toDouble(), maxWeight));
      repsSpots.add(FlSpot(i.toDouble(), totalReps.toDouble()));
    }

    final showWeight = _selectedLineIndex == -1 || _selectedLineIndex == 0;
    final showReps = _selectedLineIndex == -1 || _selectedLineIndex == 1;

    final weightLine = LineChartBarData(
      spots: weightSpots,
      isCurved: true,
      color: theme.accent,
      barWidth: 3,
      dotData: FlDotData(
        show: true,
        getDotPainter: (spot, percent, barData, index) => FlDotCirclePainter(radius: 4, color: theme.accent, strokeWidth: 2, strokeColor: theme.card),
      ),
      showingIndicators: [weightSpots.length - 1],
    );

    final repsLine = LineChartBarData(
      spots: repsSpots,
      isCurved: true,
      color: Colors.blueAccent,
      barWidth: 3,
      dotData: FlDotData(
        show: true,
        getDotPainter: (spot, percent, barData, index) => FlDotCirclePainter(radius: 4, color: Colors.blueAccent, strokeWidth: 2, strokeColor: theme.card),
      ),
      showingIndicators: [repsSpots.length - 1],
    );

    return Container(
      height: 250,
      padding: const EdgeInsets.all(16),
      margin: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.card,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              GestureDetector(
                onTap: () => setState(() => _selectedLineIndex = _selectedLineIndex == 0 ? -1 : 0),
                child: Row(
                  children: [
                    Container(width: 12, height: 12, color: theme.accent.withOpacity(showWeight ? 1.0 : 0.3)),
                    const SizedBox(width: 4),
                    Text('Max Weight', style: TextStyle(color: theme.text.withOpacity(showWeight ? 1.0 : 0.3), fontSize: 12, fontWeight: showWeight ? FontWeight.bold : FontWeight.normal)),
                  ]
                ),
              ),
              const SizedBox(width: 16),
              GestureDetector(
                onTap: () => setState(() => _selectedLineIndex = _selectedLineIndex == 1 ? -1 : 1),
                child: Row(
                  children: [
                    Container(width: 12, height: 12, color: Colors.blueAccent.withOpacity(showReps ? 1.0 : 0.3)),
                    const SizedBox(width: 4),
                    Text('Total Reps', style: TextStyle(color: theme.text.withOpacity(showReps ? 1.0 : 0.3), fontSize: 12, fontWeight: showReps ? FontWeight.bold : FontWeight.normal)),
                  ]
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            child: LineChart(
              LineChartData(
                lineTouchData: LineTouchData(
                  enabled: true,
                  touchTooltipData: LineTouchTooltipData(
                    getTooltipColor: (touchedSpot) => theme.background.withOpacity(0.8),
                    getTooltipItems: (touchedSpots) {
                      return touchedSpots.map((spot) {
                        final isWeight = spot.bar.color == theme.accent;
                        return LineTooltipItem(
                          '${spot.y.toInt()}${isWeight ? ' lbs' : ' reps'}',
                          TextStyle(color: isWeight ? theme.accent : Colors.blueAccent, fontWeight: FontWeight.bold),
                        );
                      }).toList();
                    },
                  ),
                ),
                gridData: FlGridData(show: false),
                titlesData: FlTitlesData(
                  bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  rightTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: _selectedLineIndex == 1,
                      reservedSize: 30,
                      getTitlesWidget: (value, meta) => Text(value.toInt().toString(), style: const TextStyle(color: Colors.blueAccent, fontSize: 10)),
                    ),
                  ),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: _selectedLineIndex == 0,
                      reservedSize: 40,
                      getTitlesWidget: (value, meta) => Text('${value.toInt()} lb', style: TextStyle(color: theme.accent, fontSize: 10)),
                    ),
                  ),
                ),
                borderData: FlBorderData(show: false),
                lineBarsData: [
                  if (showWeight) weightLine,
                  if (showReps) repsLine,
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMetrics(AppTheme theme) {
    if (_history.isEmpty) return const SizedBox.shrink();

    int totalWorkouts = _history.length;
    double maxWeightEver = 0;
    int maxRepsInWorkout = 0;
    double estimated1RM = 0;

    for (var workout in _history) {
      final loggedEx = workout.exercises.firstWhere((e) => e.exerciseName == widget.exercise.name);
      int workoutReps = 0;
      for (var s in loggedEx.sets) {
        workoutReps += s.reps;
        if (s.weight > maxWeightEver) maxWeightEver = s.weight;
        
        // Epley formula: 1RM = w * (1 + r/30)
        double current1RM = s.weight * (1 + s.reps / 30.0);
        if (current1RM > estimated1RM) estimated1RM = current1RM;

        for (var sub in s.subSets) {
          workoutReps += sub.reps;
          if (sub.weight > maxWeightEver) maxWeightEver = sub.weight;
          
          double currentSub1RM = sub.weight * (1 + sub.reps / 30.0);
          if (currentSub1RM > estimated1RM) estimated1RM = currentSub1RM;
        }
      }
      if (workoutReps > maxRepsInWorkout) maxRepsInWorkout = workoutReps;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      child: GridView.count(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        crossAxisCount: 2,
        childAspectRatio: 2.5,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
        children: [
          _metricCard('Total Workouts', totalWorkouts.toString(), theme),
          _metricCard('Max Weight', '${maxWeightEver.toInt()} lbs', theme),
          _metricCard('Max Reps/Session', maxRepsInWorkout.toString(), theme),
          _metricCard('Est. 1RM', '${estimated1RM.toInt()} lbs', theme),
        ],
      ),
    );
  }

  Widget _metricCard(String title, String value, AppTheme theme) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.subText.withOpacity(0.1)),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: TextStyle(color: theme.subText, fontSize: 12, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text(value, style: TextStyle(color: theme.text, fontSize: 18, fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }
}

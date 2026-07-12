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
              Container(width: 12, height: 12, color: theme.accent),
              const SizedBox(width: 4),
              Text('Max Weight', style: TextStyle(color: theme.text, fontSize: 12)),
              const SizedBox(width: 16),
              Container(width: 12, height: 12, color: Colors.blueAccent),
              const SizedBox(width: 4),
              Text('Total Reps', style: TextStyle(color: theme.text, fontSize: 12)),
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            child: LineChart(
              LineChartData(
                gridData: FlGridData(show: false),
                titlesData: FlTitlesData(
                  bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                ),
                borderData: FlBorderData(show: false),
                lineBarsData: [
                  LineChartBarData(
                    spots: weightSpots,
                    isCurved: true,
                    color: theme.accent,
                    barWidth: 3,
                    dotData: FlDotData(show: true),
                  ),
                  LineChartBarData(
                    spots: repsSpots,
                    isCurved: true,
                    color: Colors.blueAccent,
                    barWidth: 3,
                    dotData: FlDotData(show: true),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

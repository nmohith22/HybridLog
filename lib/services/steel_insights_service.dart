import 'dart:convert';

import 'package:isar/isar.dart';

import '../models/fitness_schema.dart';
import 'database_service.dart';
import 'needle_workout_service.dart';

class WorkoutHistoryAnswer {
  final String answer;
  final List<String> exerciseNames;
  final List<DailyWorkout> sources;

  const WorkoutHistoryAnswer({
    required this.answer,
    required this.exerciseNames,
    required this.sources,
  });
}

class WeeklyTrainingRecap {
  final DateTime weekStart;
  final int workouts;
  final int exercises;
  final int sets;
  final int reps;
  final double volume;
  final List<MapEntry<String, double>> mostTrainedMuscles;
  final int improvedExercises;
  final int comparedExercises;
  final String recap;

  const WeeklyTrainingRecap({
    required this.weekStart,
    required this.workouts,
    required this.exercises,
    required this.sets,
    required this.reps,
    required this.volume,
    required this.mostTrainedMuscles,
    required this.improvedExercises,
    required this.comparedExercises,
    required this.recap,
  });
}

class SteelInsightsService {
  static Future<WorkoutHistoryAnswer> askWorkoutHistory(String question) async {
    if (question.trim().length > 300) {
      throw const FormatException('Keep the question under 300 characters.');
    }
    final normalizedQuestion = _normalize(question);
    if (normalizedQuestion.isEmpty) {
      throw const FormatException('Enter a question about a logged workout.');
    }
    final db = await DatabaseService().database;
    final workouts = await db.dailyWorkouts.where().sortByDateDesc().findAll();
    final names = workouts
        .expand((workout) => workout.exercises)
        .map((exercise) => exercise.exerciseName)
        .whereType<String>()
        .toSet();
    final matchedNames = names.where((name) {
      final normalizedName = _normalize(name);
      if (normalizedQuestion.contains(normalizedName)) return true;
      final nameWords =
          normalizedName.split(' ').where((word) => word.length >= 4);
      final questionWords = normalizedQuestion.split(' ').toSet();
      return nameWords.any((word) => questionWords.contains(word));
    }).toSet();
    if (matchedNames.isEmpty) {
      throw const FormatException(
          'I could not match an exercise in your workout history. Try its logged name.');
    }

    final sources = workouts
        .where((workout) => workout.exercises
            .any((exercise) => matchedNames.contains(exercise.exerciseName)))
        .take(30)
        .toList();
    final evidence = sources
        .map((workout) => {
              'date': workout.date.toIso8601String(),
              'exercises': workout.exercises
                  .where((exercise) =>
                      matchedNames.contains(exercise.exerciseName))
                  .map((exercise) => {
                        'name': exercise.exerciseName,
                        'sets': exercise.sets
                            .map((set) => {
                                  'weight_lbs': set.weight,
                                  'reps': set.reps,
                                })
                            .toList(),
                      })
                  .toList(),
            })
        .toList();
    await NeedleWorkoutService.resetConversation();
    final raw = await NeedleWorkoutService.completeLocally(jsonEncode({
      'task':
          'Answer the user using only these local workout records. Keep it to at most three short sentences. Do not invent dates, weights, reps, or workouts. If several exercise variations match, say so clearly.',
      'question': question,
      'records': evidence,
    }));
    final answer = raw.trim().isEmpty || raw.contains('function_calls')
        ? 'I found ${sources.length} matching workout session${sources.length == 1 ? '' : 's'}. The dates and logged sets are listed below.'
        : raw.trim();
    return WorkoutHistoryAnswer(
      answer: answer,
      exerciseNames: List.unmodifiable(matchedNames),
      sources: List.unmodifiable(sources),
    );
  }

  static Future<WeeklyTrainingRecap> weeklyRecap() async {
    final db = await DatabaseService().database;
    final all = await db.dailyWorkouts.where().sortByDateDesc().findAll();
    final today = DateTime.now();
    final currentStart = DateTime(today.year, today.month, today.day)
        .subtract(Duration(days: today.weekday - 1));
    final nextStart = currentStart.add(const Duration(days: 7));
    final previousStart = currentStart.subtract(const Duration(days: 7));
    bool inRange(DailyWorkout workout, DateTime start, DateTime end) =>
        !workout.date.isBefore(start) && workout.date.isBefore(end);
    final current = all
        .where((workout) => inRange(workout, currentStart, nextStart))
        .toList();
    final previous = all
        .where((workout) => inRange(workout, previousStart, currentStart))
        .toList();

    var exerciseCount = 0;
    var setCount = 0;
    var reps = 0;
    var volume = 0.0;
    final muscles = <String, double>{};
    final currentMax = <String, double>{};
    final previousMax = <String, double>{};
    void calculate(List<DailyWorkout> workouts,
        {bool countCurrent = false, Map<String, double>? maxima}) {
      for (final workout in workouts) {
        for (final exercise in workout.exercises) {
          exerciseCount += countCurrent ? 1 : 0;
          var exerciseVolume = 0.0;
          for (final set in exercise.sets) {
            setCount += countCurrent ? 1 : 0;
            reps += countCurrent ? set.reps : 0;
            final setVolume = set.weight * set.reps;
            volume += countCurrent ? setVolume : 0;
            exerciseVolume += setVolume;
            for (final subSet in set.subSets) {
              setCount += countCurrent ? 1 : 0;
              reps += countCurrent ? subSet.reps : 0;
              final subVolume = subSet.weight * subSet.reps;
              volume += countCurrent ? subVolume : 0;
              exerciseVolume += subVolume;
            }
            if (maxima != null &&
                set.weight > (maxima[exercise.exerciseName] ?? 0)) {
              maxima[exercise.exerciseName ?? ''] = set.weight;
            }
          }
          if (countCurrent) {
            final targets = exercise.targetMuscles.isNotEmpty
                ? exercise.targetMuscles
                : (exercise.targetMuscle == null
                    ? <String>[]
                    : [exercise.targetMuscle!]);
            for (final muscle in targets) {
              muscles[muscle] = (muscles[muscle] ?? 0) +
                  (targets.isEmpty
                      ? exerciseVolume
                      : exerciseVolume / targets.length);
            }
            for (final muscle in exercise.secondaryMuscles) {
              muscles[muscle] = (muscles[muscle] ?? 0) + exerciseVolume * .4;
            }
          }
        }
      }
    }

    calculate(current, countCurrent: true, maxima: currentMax);
    calculate(previous, maxima: previousMax);
    final comparable = currentMax.keys
        .where((name) => name.isNotEmpty && previousMax.containsKey(name))
        .toList();
    final improved = comparable
        .where((name) => currentMax[name]! > previousMax[name]!)
        .length;
    final topMuscles = muscles.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final leading = topMuscles.take(3).toList();

    var recap =
        'You logged ${current.length} workout${current.length == 1 ? '' : 's'} this week.';
    if (current.isNotEmpty) {
      try {
        await NeedleWorkoutService.ensureReady(onProgress: (_, __) {});
        await NeedleWorkoutService.resetConversation();
        final raw = await NeedleWorkoutService.completeLocally(jsonEncode({
          'task':
              'Write a warm, specific training recap in no more than three short sentences. Use only these calculated facts. Do not diagnose muscle imbalance or make claims not supported by the numbers.',
          'facts': {
            'workouts': current.length,
            'exercises': exerciseCount,
            'sets_including_dropsets': setCount,
            'reps': reps,
            'volume_lbs_reps': volume.round(),
            'most_trained_muscles': leading
                .map((entry) =>
                    {'muscle': entry.key, 'volume': entry.value.round()})
                .toList(),
            'exercises_with_week_over_week_top_weight_increase': improved,
            'comparable_exercises': comparable.length,
          },
        }));
        if (raw.trim().isNotEmpty && !raw.contains('function_calls'))
          recap = raw.trim();
      } catch (_) {
        recap =
            'You logged ${current.length} workouts, $exerciseCount exercises, and $setCount sets this week. Your most trained areas were ${leading.map((entry) => entry.key.replaceAll('_', ' ')).join(', ')}.';
      }
    }

    return WeeklyTrainingRecap(
      weekStart: currentStart,
      workouts: current.length,
      exercises: exerciseCount,
      sets: setCount,
      reps: reps,
      volume: volume,
      mostTrainedMuscles: List.unmodifiable(leading),
      improvedExercises: improved,
      comparedExercises: comparable.length,
      recap: recap,
    );
  }

  static String _normalize(String value) => value
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9 ]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim()
      .split(' ')
      .map((word) => word.length > 4 && word.endsWith('s')
          ? word.substring(0, word.length - 1)
          : word)
      .join(' ');
}

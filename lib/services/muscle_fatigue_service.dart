import 'dart:math' as math;

import '../models/fitness_schema.dart';

class MuscleFatigueService {
  static const window = Duration(days: 7);

  // Parent silhouettes also cover the smaller regions drawn on top of them.
  static const _parent = {
    'bicep_short_head': 'biceps',
    'bicep_long_head': 'biceps',
    'tricep_long_head': 'triceps',
    'upper_back': 'traps',
  };

  static const _threshold = {
    'chest': 10000.0,
    'quads': 11500.0,
    'lats': 10000.0,
    'lower_back': 9000.0,
    'hamstrings': 7500.0,
    'glutes': 7500.0,
    'biceps': 3500.0,
    'triceps': 4000.0,
    'traps': 4500.0,
    'front_deltoids': 4000.0,
    'side_deltoids': 3200.0,
    'back_deltoids': 2800.0,
    'abs': 2800.0,
    'obliques': 2400.0,
    'calves': 3800.0,
    'bicep_short_head': 2200.0,
    'bicep_long_head': 2200.0,
    'tricep_long_head': 2500.0,
    'forearm': 2000.0,
    'adductors': 3000.0,
    'upper_back': 3700.0,
  };

  static String _muscleKey(String value) {
    final key = value.trim().toLowerCase().replaceAll(RegExp(r'[ -]+'), '_');
    return switch (key) {
      'lateral_deltoid' ||
      'lateral_deltoids' ||
      'side_deltoid' =>
        'side_deltoids',
      'front_deltoid' ||
      'anterior_deltoid' ||
      'anterior_deltoids' =>
        'front_deltoids',
      'back_deltoid' || 'rear_deltoid' || 'rear_deltoids' => 'back_deltoids',
      _ => key,
    };
  }

  static Map<String, double> exerciseWeights(Exercise exercise) =>
      muscleWeights(
          exercise.name,
          exercise.targetMuscles.isEmpty
              ? [exercise.targetMuscle]
              : exercise.targetMuscles,
          exercise.secondaryMuscles);

  static Map<String, double> muscleWeights(
      String name, Iterable<String> primary, Iterable<String> secondary) {
    final main = primary.map(_muscleKey).where((m) => m.isNotEmpty).toSet();
    final assistance = secondary
        .map(_muscleKey)
        .where((m) => m.isNotEmpty)
        .toSet()
        .difference(main);
    final movement = name
        .toLowerCase()
        .split(' | ')
        .last
        .replaceAll(RegExp(r'[^a-z0-9 ]'), ' ');
    final weights = <String, double>{
      for (final muscle in main) muscle: 1 / math.sqrt(main.length),
      for (final muscle in assistance)
        muscle: .30 / math.sqrt(assistance.length),
    };

    // ponytail: these are relative movement heuristics. Recorded effort and
    // individual calibration can replace these coefficients when available.
    final emphasis = switch (movement) {
      String s when RegExp(r'\bmuscle\s*up\b').hasMatch(s) => {
          'chest': .16,
          'lats': .85,
          'triceps': .55,
          'front_deltoids': .30
        },
      String s
          when RegExp(
                  r'\b(lateral|side)\b.*\braises?\b|\braises?\b.*\b(lateral|side)\b')
              .hasMatch(s) =>
        {'side_deltoids': 1.20, 'front_deltoids': .13, 'traps': .18},
      String s
          when s.contains('press') &&
              (s.contains('shoulder') ||
                  s.contains('overhead') ||
                  s.contains('military') ||
                  s.contains('arnold') ||
                  main.contains('front_deltoids') && !main.contains('chest')) =>
        {
          'front_deltoids': 1.05,
          'side_deltoids': .14,
          'back_deltoids': .07,
          'triceps': .40,
          'traps': .16
        },
      String s
          when s.contains('press') &&
              (s.contains('bench') ||
                  s.contains('chest') ||
                  s.contains('incline') ||
                  s.contains('decline')) =>
        {
          'chest': s.contains('close grip') ? .50 : 1.10,
          'front_deltoids': s.contains('incline') ? .52 : .28,
          'side_deltoids': .06,
          'triceps': s.contains('close grip') ? 1.0 : .42
        },
      _ => const <String, double>{},
    };
    for (final entry in emphasis.entries) {
      final muscle = entry.key;
      if (weights.containsKey(muscle)) {
        weights[muscle] = assistance.contains(muscle)
            ? math.min(.55, entry.value)
            : entry.value;
      }
    }
    return weights;
  }

  static String profileSummary(Map<String, double> weights) {
    final ranked = weights.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return ranked.map((entry) {
      final level = entry.value >= .65
          ? 'high'
          : entry.value >= .30
              ? 'moderate'
              : 'low';
      return '${entry.key.replaceAll('_', ' ')} ($level)';
    }).join(', ');
  }

  static double _effort(double weight, int reps) {
    if (reps <= 0 || !weight.isFinite || weight < 0) return 0;
    // Logged loads describe different machines and leverage. Compress their
    // range so a heavier stack does not overwhelm direct isolation work.
    final load = weight == 0 ? 25.0 : weight;
    return 50.0 * math.pow(load / 50, .55) * reps;
  }

  static Map<String, double> workoutLoad(DailyWorkout workout) {
    final load = <String, double>{};
    void add(double effort, Map<String, double> weights) {
      if (effort <= 0) return;
      final rolled = Map<String, double>.of(weights);
      for (final entry in weights.entries) {
        final parent = _parent[entry.key];
        if (parent != null)
          rolled[parent] = math.max(rolled[parent] ?? 0, entry.value);
      }
      for (final entry in rolled.entries) {
        load.update(entry.key, (value) => value + effort * entry.value,
            ifAbsent: () => effort * entry.value);
      }
    }

    for (final exercise in workout.exercises) {
      final primary = exercise.targetMuscles.isNotEmpty
          ? exercise.targetMuscles
          : [if (exercise.targetMuscle case final muscle?) muscle];
      final weights = muscleWeights(
          exercise.exerciseName ?? '', primary, exercise.secondaryMuscles);
      for (final set in exercise.sets) {
        add(_effort(set.weight, set.reps), weights);
        var precedingWeights = weights;
        var paused = false;
        for (final step in set.sequence) {
          if (step.exerciseName case final name?) {
            precedingWeights =
                muscleWeights(name, step.targetMuscles, step.secondaryMuscles);
            // Paired exercises earn local credit for their own work.
            add(_effort(step.weight, step.reps), precedingWeights);
            paused = false;
          } else if (step.pauseSeconds case final seconds?) {
            final density = 1 + .12 * (1 - (seconds / 60).clamp(0.0, 1.0));
            add(_effort(step.weight, step.reps) * density, precedingWeights);
            paused = true;
          } else {
            add(_effort(step.weight, step.reps) * (paused ? 1 : 1.15),
                precedingWeights);
            paused = false;
          }
        }
      }
    }
    return load.map((muscle, work) =>
        MapEntry(muscle, work / (_threshold[muscle] ?? 3500)));
  }

  static Map<String, double> recentLoad(
      Map<DateTime, Map<String, double>> sessions, DateTime now) {
    final load = <String, double>{};
    for (final entry in sessions.entries) {
      if (entry.key.isAfter(now)) continue;
      final age = now.difference(entry.key).inMinutes / window.inMinutes;
      if (age >= 1) continue;
      for (final muscle in entry.value.entries) {
        load.update(muscle.key, (value) => value + muscle.value * (1 - age),
            ifAbsent: () => muscle.value * (1 - age));
      }
    }
    return load;
  }
}

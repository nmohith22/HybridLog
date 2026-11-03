import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../models/fitness_schema.dart';

class NeedleWorkoutService {
  static const _channel = MethodChannel('hybridlog/needle');
  static const _modelUrl =
      'https://huggingface.co/Cactus-Compute/needle3/resolve/main/needle3.cact?download=true';
  static const _modelName = 'needle3.cact';
  static const _maxModelBytes = 60 * 1024 * 1024;
  static bool _initialized = false;

  static const splitMuscles = <String, List<String>>{
    'Push': ['chest', 'front_deltoids', 'side_deltoids', 'triceps'],
    'Pull': [
      'lats',
      'upper_back',
      'traps',
      'back_deltoids',
      'biceps',
      'lower_back',
      'forearm'
    ],
    'Legs': ['quads', 'hamstrings', 'glutes', 'calves', 'adductors'],
    'Upper': [
      'chest',
      'front_deltoids',
      'side_deltoids',
      'triceps',
      'lats',
      'upper_back',
      'traps',
      'back_deltoids',
      'biceps',
      'lower_back'
    ],
    'Lower': ['quads', 'hamstrings', 'glutes', 'calves', 'adductors'],
    'Fullbody': [],
    'Shoulders': ['front_deltoids', 'side_deltoids', 'back_deltoids'],
    'Arms': ['biceps', 'triceps', 'forearm'],
    'Shoulders and Arms': [
      'front_deltoids',
      'side_deltoids',
      'back_deltoids',
      'biceps',
      'triceps',
      'forearm'
    ],
    'Back': ['lats', 'upper_back', 'traps', 'back_deltoids', 'lower_back'],
    'Chest': ['chest'],
    'Chest and Back': [
      'chest',
      'lats',
      'upper_back',
      'traps',
      'back_deltoids',
      'lower_back'
    ],
    'Posterior': [
      'lats',
      'upper_back',
      'traps',
      'back_deltoids',
      'lower_back',
      'glutes',
      'hamstrings',
      'calves'
    ],
    'Anterior': [
      'chest',
      'abs',
      'obliques',
      'front_deltoids',
      'side_deltoids',
      'biceps',
      'quads'
    ],
  };

  static Future<bool> get isSupported async =>
      Platform.isAndroid &&
      await _channel.invokeMethod<bool>('isSupported') == true;

  static Future<void> ensureReady(
      {required void Function(int received, int total) onProgress}) async {
    if (_initialized) return;
    if (!await isSupported) {
      throw UnsupportedError(
          'On-device Needle3 currently requires an ARM Android phone or tablet.');
    }

    final directory = await getApplicationSupportDirectory();
    final model = File('${directory.path}/$_modelName');
    if (!await model.exists() || await model.length() < 10 * 1024 * 1024) {
      final temporary = File('${model.path}.download');
      if (await temporary.exists()) await temporary.delete();
      final client = http.Client();
      try {
        final response =
            await client.send(http.Request('GET', Uri.parse(_modelUrl)));
        if (response.statusCode != 200) {
          throw HttpException(
              'Needle3 model download failed (HTTP ${response.statusCode}).');
        }
        final total = response.contentLength ?? -1;
        if (total > _maxModelBytes)
          throw const FormatException('Unexpectedly large Needle3 model.');
        final sink = temporary.openWrite();
        var received = 0;
        try {
          await for (final chunk in response.stream) {
            received += chunk.length;
            if (received > _maxModelBytes)
              throw const FormatException(
                  'Needle3 model exceeds the download size limit.');
            sink.add(chunk);
            onProgress(received, total);
          }
          await sink.flush();
        } finally {
          await sink.close();
        }
        if (received < 10 * 1024 * 1024)
          throw const FormatException(
              'Downloaded Needle3 model is incomplete.');
        await temporary.rename(model.path);
      } catch (_) {
        if (await temporary.exists()) await temporary.delete();
        rethrow;
      } finally {
        client.close();
      }
    }

    final result = await _channel
        .invokeMethod<String>('initialize', {'modelPath': model.path});
    if (result != 'ok')
      throw StateError(result ?? 'Could not initialize Needle3.');
    _initialized = true;
  }

  static Future<void> resetConversation() =>
      _channel.invokeMethod<void>('reset');

  static Future<List<Exercise>> generate({
    required List<Exercise> exercises,
    required List<DailyWorkout> history,
    required List<String> splits,
    required bool includeNewExercises,
    required Map<String, double> fatigue,
    required Set<String> unavailable,
  }) async {
    final used = <String, int>{};
    final recent = history.toList()..sort((a, b) => b.date.compareTo(a.date));
    for (final workout in recent.take(20)) {
      for (final logged in workout.exercises) {
        final name = logged.exerciseName;
        if (name != null) used[name] = (used[name] ?? 0) + 1;
      }
    }

    final eligible = exercises.where((exercise) {
      final familiar = exercise.isFavorite ||
          exercise.folderNames.isNotEmpty ||
          (used[exercise.name] ?? 0) > 0;
      if (!includeNewExercises && !familiar) return false;
      if (unavailable.contains(exercise.name)) return false;
      return _matchesSplit(exercise, splits);
    }).toList();
    if (eligible.isEmpty) return const [];

    eligible.sort(
        (a, b) => _rank(b, used, fatigue).compareTo(_rank(a, used, fatigue)));
    final candidates = eligible.take(50).toList();
    final historySummary = recent
        .take(8)
        .map((workout) => {
              'date':
                  '${workout.date.year}-${workout.date.month.toString().padLeft(2, '0')}-${workout.date.day.toString().padLeft(2, '0')}',
              'exercises': workout.exercises
                  .map((e) => e.exerciseName)
                  .whereType<String>()
                  .take(12)
                  .toList(),
            })
        .toList();
    final candidateSummary = candidates
        .map((e) => {
              'name': e.name,
              'muscles':
                  (e.targetMuscles.isEmpty ? [e.targetMuscle] : e.targetMuscles)
                      .take(3)
                      .toList(),
              'used_before': (used[e.name] ?? 0) > 0,
            })
        .toList();
    final request = jsonEncode({
      'request':
          'Plan a ${splits.join(' and ')} workout with 4 to 8 distinct exercises. Use recent history to avoid repeating too much and avoid heavily fatigued muscles when practical. ${includeNewExercises ? 'Include up to two suitable exercises marked used_before=false.' : 'Use only exercises marked used_before=true.'} ${unavailable.isEmpty ? '' : 'The user says they cannot use this equipment/exercise: ${unavailable.join(', ')}. Replace those with suitable alternatives.'} Return 6 exercises when possible.',
      'recent_workouts': historySummary,
      'muscle_fatigue': fatigue.entries
          .where((entry) => entry.value >= 0.2)
          .map((entry) => {'muscle': entry.key, 'level': entry.value})
          .toList(),
      'unavailable': unavailable.toList(),
      'candidates': candidateSummary,
    });
    final raw =
        await _channel.invokeMethod<String>('complete', {'input': request});
    final chosenNames = _parseNames(raw ?? '');
    final byName = {
      for (final candidate in candidates) candidate.name: candidate
    };
    final selected = <Exercise>[];
    for (final name in chosenNames) {
      final exercise = byName[name];
      if (exercise != null &&
          !unavailable.contains(name) &&
          !selected.any((e) => e.name == name)) {
        selected.add(exercise);
      }
    }

    // The model can abstain when its small tool-calling model is uncertain.
    // Ponytail ceiling: ranked heuristics serve only as a local completion fallback; finer personalization can replace them later.
    if (selected.length < 4) {
      for (final exercise in candidates) {
        if (selected.length == 8) break;
        if (!unavailable.contains(exercise.name) &&
            !selected.any((e) => e.name == exercise.name))
          selected.add(exercise);
      }
    }
    return selected;
  }

  static bool _matchesSplit(Exercise exercise, List<String> splits) {
    if (splits.isEmpty || splits.contains('Fullbody')) return true;
    final muscles = splits
        .expand((split) => splitMuscles[split] ?? const <String>[])
        .toSet();
    final target = [
      ...exercise.targetMuscles,
      ...exercise.secondaryMuscles,
      exercise.targetMuscle
    ];
    return target.any((muscle) {
      final normalized = muscle.toLowerCase().replaceAll(' ', '_');
      return muscles.contains(normalized) ||
          muscles.contains(normalized.endsWith('s')
              ? normalized.substring(0, normalized.length - 1)
              : '${normalized}s');
    });
  }

  static double _rank(
      Exercise exercise, Map<String, int> used, Map<String, double> fatigue) {
    final targets = exercise.targetMuscles.isEmpty
        ? [exercise.targetMuscle]
        : exercise.targetMuscles;
    final strain = targets
        .map((muscle) => fatigue[muscle] ?? 0)
        .fold<double>(0, (a, b) => a > b ? a : b);
    final familiarity = (used[exercise.name] ?? 0) > 0
        ? 2.0
        : (exercise.isFavorite || exercise.folderNames.isNotEmpty ? 1.0 : 0.0);
    return familiarity - strain;
  }

  static List<String> _parseNames(String raw) {
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      final calls = decoded['function_calls'] as List<dynamic>? ?? const [];
      for (final call in calls) {
        if (call is! Map || call['name'] != 'select_exercises') continue;
        final arguments = call['arguments'];
        final parsed = arguments is String ? jsonDecode(arguments) : arguments;
        if (parsed is Map && parsed['exercise_names'] is List) {
          return (parsed['exercise_names'] as List)
              .whereType<String>()
              .toList();
        }
      }
    } catch (_) {
      return const [];
    }
    return const [];
  }
}

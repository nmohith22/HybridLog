import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:isar/isar.dart';
import 'package:path_provider/path_provider.dart';

import '../models/fitness_schema.dart';
import 'database_service.dart';
import 'widget_service.dart';

class NeedleDataAction {
  final String operation;
  final String recordType;
  final int? recordId;
  final Map<String, dynamic> record;
  final String summary;

  const NeedleDataAction({
    required this.operation,
    required this.recordType,
    required this.recordId,
    required this.record,
    required this.summary,
  });
}

class NeedleWorkoutService {
  static const _channel = MethodChannel('hybridlog/needle');
  static const _modelName = 'needle3.cact';
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
    final bundledModel = await rootBundle.load('assets/needle3.cact');
    final modelBytes = bundledModel.buffer.asUint8List(
      bundledModel.offsetInBytes,
      bundledModel.lengthInBytes,
    );
    if (modelBytes.length < 30 * 1024 * 1024) {
      throw const FormatException('The bundled Needle3 model is incomplete.');
    }
    if (!await model.exists() || await model.length() != modelBytes.length) {
      final temporary = File('${model.path}.tmp');
      await temporary.writeAsBytes(modelBytes, flush: true);
      if (await model.exists()) await model.delete();
      await temporary.rename(model.path);
    }
    onProgress(modelBytes.length, modelBytes.length);

    final result = await _channel
        .invokeMethod<String>('initialize', {'modelPath': model.path});
    if (result != 'ok')
      throw StateError(result ?? 'Could not initialize Needle3.');
    _initialized = true;
  }

  static Future<void> resetConversation() =>
      _channel.invokeMethod<void>('reset');

  static Future<NeedleDataAction> proposeDataAction(String userRequest) async {
    final db = await DatabaseService().database;
    final exercises = await db.exercises.where().sortByName().findAll();
    final folders = await db.workoutFolders.where().sortByName().findAll();
    final workouts = await db.dailyWorkouts.where().sortByDateDesc().findAll();
    final runs = await db.runningLogs.where().sortByDateDesc().findAll();
    final request = jsonEncode({
      'user_request': userRequest,
      'record_shapes': {
        'exercise': {
          'name': 'text',
          'target_muscle': 'text',
          'target_muscles': ['text'],
          'secondary_muscles': ['text'],
          'is_favorite': 'boolean',
          'folder_names': ['text'],
        },
        'folder': {'name': 'text'},
        'workout': {
          'date': 'ISO-8601 date',
          'exercises': [
            {
              'name': 'exercise name',
              'target_muscle': 'text',
              'target_muscles': ['text'],
              'secondary_muscles': ['text'],
              'sets': [
                {
                  'reps': 'integer',
                  'weight': 'number',
                  'rest_pause_seconds': 'integer or null',
                  'sub_sets': [
                    {'reps': 'integer', 'weight': 'number'}
                  ],
                }
              ],
            }
          ],
        },
        'run': {'date': 'ISO-8601 date', 'miles': 'integer'},
      },
      'local_data_snapshot': {
        'exercises': exercises
            .map((item) => {
                  'id': item.id,
                  'name': item.name,
                  'target_muscle': item.targetMuscle,
                  'target_muscles': item.targetMuscles,
                  'secondary_muscles': item.secondaryMuscles,
                  'is_favorite': item.isFavorite,
                  'folder_names': item.folderNames,
                })
            .toList(),
        'folders':
            folders.map((item) => {'id': item.id, 'name': item.name}).toList(),
        'recent_workouts': workouts
            .take(40)
            .map((item) => {
                  'id': item.id,
                  'date': item.date.toIso8601String(),
                  'exercises': item.exercises
                      .map((exercise) => exercise.exerciseName)
                      .whereType<String>()
                      .toList(),
                })
            .toList(),
        'recent_runs': runs
            .take(40)
            .map((item) => {
                  'id': item.id,
                  'date': item.date.toIso8601String(),
                  'miles': item.miles,
                })
            .toList(),
      },
    });
    final raw =
        await _channel.invokeMethod<String>('complete', {'input': request});
    final action = _parseDataAction(raw ?? '');
    return _verifyDataAction(db, action);
  }

  static Future<void> applyApprovedDataAction(NeedleDataAction action) async {
    if (action.operation == 'read') {
      throw StateError('Read operations do not change stored data.');
    }
    final db = await DatabaseService().database;
    await db.writeTxn(() async {
      switch (action.recordType) {
        case 'exercise':
          if (action.operation == 'create') {
            final exercise = _exerciseFrom(action.record);
            if (await db.exercises
                    .filter()
                    .nameEqualTo(exercise.name)
                    .findFirst() !=
                null) {
              throw StateError(
                  'An exercise named "${exercise.name}" already exists.');
            }
            await db.exercises.put(exercise);
            return;
          }
          final existing = await db.exercises.get(_requiredId(action));
          if (existing == null)
            throw StateError('The selected exercise no longer exists.');
          if (action.operation == 'delete') {
            await db.exercises.delete(existing.id);
          } else {
            final updated = _exerciseFrom(action.record, existing: existing);
            final duplicate = await db.exercises
                .filter()
                .nameEqualTo(updated.name)
                .findFirst();
            if (duplicate != null && duplicate.id != existing.id) {
              throw StateError(
                  'An exercise named "${updated.name}" already exists.');
            }
            await db.exercises.put(updated);
          }
        case 'folder':
          if (action.operation == 'create') {
            final name = _recordString(action.record, 'name');
            if (await db.workoutFolders
                    .filter()
                    .nameEqualTo(name)
                    .findFirst() !=
                null) {
              throw StateError('A folder named "$name" already exists.');
            }
            await db.workoutFolders.put(WorkoutFolder()..name = name);
            return;
          }
          final folder = await db.workoutFolders.get(_requiredId(action));
          if (folder == null)
            throw StateError('The selected folder no longer exists.');
          if (action.operation == 'delete') {
            await db.workoutFolders.delete(folder.id);
            final exercises = await db.exercises.where().findAll();
            for (final exercise in exercises) {
              if (!exercise.folderNames.contains(folder.name)) continue;
              exercise.folderNames = List.of(exercise.folderNames)
                ..remove(folder.name);
              exercise.folderName = exercise.folderNames.firstOrNull;
              exercise.isFavorite = exercise.folderNames.isNotEmpty;
              await db.exercises.put(exercise);
            }
          } else {
            final name = _recordString(action.record, 'name');
            final duplicate =
                await db.workoutFolders.filter().nameEqualTo(name).findFirst();
            if (duplicate != null && duplicate.id != folder.id) {
              throw StateError('A folder named "$name" already exists.');
            }
            final oldName = folder.name;
            folder.name = name;
            await db.workoutFolders.put(folder);
            if (oldName != name) {
              final exercises = await db.exercises.where().findAll();
              for (final exercise in exercises) {
                if (!exercise.folderNames.contains(oldName)) continue;
                exercise.folderNames = exercise.folderNames
                    .map((item) => item == oldName ? name : item)
                    .toList();
                exercise.folderName = exercise.folderNames.firstOrNull;
                await db.exercises.put(exercise);
              }
            }
          }
        case 'workout':
          if (action.operation == 'create') {
            await db.dailyWorkouts.put(_workoutFrom(action.record));
            return;
          }
          final workout = await db.dailyWorkouts.get(_requiredId(action));
          if (workout == null)
            throw StateError('The selected workout no longer exists.');
          if (action.operation == 'delete') {
            await db.dailyWorkouts.delete(workout.id);
          } else {
            await db.dailyWorkouts
                .put(_workoutFrom(action.record, existing: workout));
          }
        case 'run':
          if (action.operation == 'create') {
            await db.runningLogs.put(_runFrom(action.record));
            return;
          }
          final run = await db.runningLogs.get(_requiredId(action));
          if (run == null)
            throw StateError('The selected run no longer exists.');
          if (action.operation == 'delete') {
            await db.runningLogs.delete(run.id);
          } else {
            await db.runningLogs.put(_runFrom(action.record, existing: run));
          }
        default:
          throw StateError('Unsupported data type.');
      }
    });
    if (action.recordType == 'run') await WidgetService.updateRunningWidget();
  }

  static Future<NeedleDataAction> _verifyDataAction(
      Isar db, NeedleDataAction action) async {
    if (action.operation == 'read') return action;
    final id = action.recordId;
    final record = action.record;
    String summary;
    switch (action.recordType) {
      case 'exercise':
        final existing = id == null ? null : await db.exercises.get(id);
        if (action.operation != 'create' && existing == null) {
          throw const FormatException(
              'Needle selected an exercise that no longer exists.');
        }
        final proposed = action.operation == 'delete'
            ? existing!
            : _exerciseFrom(record, existing: existing);
        summary = switch (action.operation) {
          'create' =>
            'Create exercise "${proposed.name}" (${proposed.targetMuscle}).',
          'update' =>
            'Update exercise "${existing!.name}" to "${proposed.name}" (${proposed.targetMuscle}).',
          _ =>
            'Delete exercise "${existing!.name}" from the library. Workout history will remain.',
        };
      case 'folder':
        final existing = id == null ? null : await db.workoutFolders.get(id);
        if (action.operation != 'create' && existing == null) {
          throw const FormatException(
              'Needle selected a folder that no longer exists.');
        }
        final name = action.operation == 'delete'
            ? existing!.name
            : _recordString(record, 'name', fallback: existing?.name);
        summary = switch (action.operation) {
          'create' => 'Create favorites folder "$name".',
          'update' => 'Rename folder "${existing!.name}" to "$name".',
          _ =>
            'Delete folder "$name". Its exercises stay in the library; exercises with no other favorite folder will be unfavorited.',
        };
      case 'workout':
        final existing = id == null ? null : await db.dailyWorkouts.get(id);
        if (action.operation != 'create' && existing == null) {
          throw const FormatException(
              'Needle selected a workout that no longer exists.');
        }
        final proposed = action.operation == 'delete'
            ? existing!
            : _workoutFrom(record, existing: existing);
        final names = proposed.exercises
            .map((item) => item.exerciseName)
            .whereType<String>()
            .join(', ');
        summary = switch (action.operation) {
          'create' =>
            'Create workout for ${_dateLabel(proposed.date)}: $names.',
          'update' =>
            'Update workout from ${_dateLabel(existing!.date)} to ${_dateLabel(proposed.date)}: $names.',
          _ =>
            'Delete workout from ${_dateLabel(existing!.date)}. This removes its session history.',
        };
      case 'run':
        final existing = id == null ? null : await db.runningLogs.get(id);
        if (action.operation != 'create' && existing == null) {
          throw const FormatException(
              'Needle selected a run that no longer exists.');
        }
        final proposed = action.operation == 'delete'
            ? existing!
            : _runFrom(record, existing: existing);
        summary = switch (action.operation) {
          'create' =>
            'Create ${proposed.miles}-mile run for ${_dateLabel(proposed.date)}.',
          'update' =>
            'Update run from ${existing!.miles} to ${proposed.miles} miles on ${_dateLabel(proposed.date)}.',
          _ =>
            'Delete ${existing!.miles}-mile run from ${_dateLabel(existing.date)}.',
        };
      default:
        throw const FormatException(
            'Needle proposed an unsupported data type.');
    }
    return NeedleDataAction(
      operation: action.operation,
      recordType: action.recordType,
      recordId: action.recordId,
      record: action.record,
      summary: summary,
    );
  }

  static String _dateLabel(DateTime date) =>
      '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

  static NeedleDataAction _parseDataAction(String raw) {
    final decoded = jsonDecode(raw);
    if (decoded is! Map)
      throw const FormatException('Needle3 returned an invalid action.');
    final calls = decoded['function_calls'];
    if (calls is! List)
      throw const FormatException('Needle3 did not propose a data action.');
    for (final call in calls) {
      if (call is! Map || call['name'] != 'manage_data') continue;
      final arguments = call['arguments'];
      final parsed = arguments is String ? jsonDecode(arguments) : arguments;
      if (parsed is! Map) break;
      final operation = parsed['operation'];
      final recordType = parsed['record_type'];
      final summary = parsed['summary'];
      if (!const ['create', 'read', 'update', 'delete'].contains(operation) ||
          !const ['exercise', 'folder', 'workout', 'run']
              .contains(recordType) ||
          summary is! String ||
          summary.trim().isEmpty ||
          summary.length > 500) {
        break;
      }
      final idValue = parsed['record_id'];
      final id = idValue is int && idValue > 0 ? idValue : null;
      final record = parsed['record'];
      if (record != null && record is! Map) break;
      if (operation != 'create' && operation != 'read' && id == null) break;
      if ((operation == 'create' || operation == 'update') && record == null)
        break;
      return NeedleDataAction(
        operation: operation as String,
        recordType: recordType as String,
        recordId: id,
        record: record == null ? const {} : Map<String, dynamic>.from(record),
        summary: summary.trim(),
      );
    }
    throw const FormatException(
        'Needle3 could not form a safe data action. Try a more specific request.');
  }

  static int _requiredId(NeedleDataAction action) =>
      action.recordId ?? (throw const FormatException('Missing record ID.'));

  static Exercise _exerciseFrom(Map<String, dynamic> record,
      {Exercise? existing}) {
    final exercise = Exercise()..id = existing?.id ?? Isar.autoIncrement;
    exercise.name = _recordString(record, 'name', fallback: existing?.name);
    exercise.targetMuscle = _recordString(record, 'target_muscle',
        fallback: existing?.targetMuscle);
    exercise.targetMuscles = _stringList(record['target_muscles'],
        existing?.targetMuscles ?? [exercise.targetMuscle]);
    exercise.secondaryMuscles = _stringList(
        record['secondary_muscles'], existing?.secondaryMuscles ?? const []);
    exercise.isFavorite = record['is_favorite'] is bool
        ? record['is_favorite'] as bool
        : existing?.isFavorite ?? false;
    exercise.folderNames =
        _stringList(record['folder_names'], existing?.folderNames ?? const []);
    exercise.folderName = exercise.folderNames.firstOrNull;
    return exercise;
  }

  static DailyWorkout _workoutFrom(Map<String, dynamic> record,
      {DailyWorkout? existing}) {
    final date = record['date'] == null && existing != null
        ? existing.date
        : _recordDate(record, 'date');
    final exercises = record['exercises'] == null && existing != null
        ? existing.exercises
        : _loggedExercises(record['exercises']);
    return (DailyWorkout()..id = existing?.id ?? Isar.autoIncrement)
      ..date = date
      ..exercises = exercises;
  }

  static RunningLog _runFrom(Map<String, dynamic> record,
          {RunningLog? existing}) =>
      (RunningLog()..id = existing?.id ?? Isar.autoIncrement)
        ..date = record['date'] == null && existing != null
            ? existing.date
            : _recordDate(record, 'date')
        ..miles = record['miles'] == null && existing != null
            ? existing.miles
            : _boundedInt(record['miles'], 'miles', 0, 1000000);

  static List<LoggedExercise> _loggedExercises(Object? value) {
    if (value is! List || value.length > 100)
      throw const FormatException('Workout exercises must be a list.');
    return value.map((item) {
      final data = _recordMap(item, 'workout exercise');
      final logged = LoggedExercise()
        ..exerciseName = _recordString(data, 'name')
        ..targetMuscle = data['target_muscle'] is String
            ? data['target_muscle'] as String
            : null
        ..targetMuscles = _stringList(data['target_muscles'], const [])
        ..secondaryMuscles = _stringList(data['secondary_muscles'], const []);
      final sets = data['sets'] ?? const [];
      if (sets is! List || sets.length > 100)
        throw const FormatException('Workout sets must be a list.');
      logged.sets = sets.map((item) {
        final set = _recordMap(item, 'set');
        final subsets = set['sub_sets'] ?? const [];
        if (subsets is! List || subsets.length > 100)
          throw const FormatException('Dropsets must be a list.');
        final rest = set['rest_pause_seconds'];
        if (rest != null &&
            _boundedInt(rest, 'rest_pause_seconds', 0, 60) != rest) {
          throw const FormatException('Invalid rest pause.');
        }
        return SetLog()
          ..reps = _boundedInt(set['reps'], 'reps', 0, 10000)
          ..weight = _boundedDouble(set['weight'], 'weight', 1000000)
          ..restPauseSeconds = rest == null
              ? null
              : _boundedInt(rest, 'rest_pause_seconds', 0, 60)
          ..subSets = subsets.map((subsetValue) {
            final subset = _recordMap(subsetValue, 'dropset');
            return SubSetLog()
              ..reps = _boundedInt(subset['reps'], 'reps', 0, 10000)
              ..weight = _boundedDouble(subset['weight'], 'weight', 1000000);
          }).toList();
      }).toList();
      return logged;
    }).toList();
  }

  static DateTime _recordDate(Map<String, dynamic> record, String key) {
    final value = record[key];
    if (value is String) {
      final date = DateTime.tryParse(value);
      if (date != null) return date;
    }
    throw FormatException('A valid $key is required.');
  }

  static String _recordString(Map<String, dynamic> record, String key,
      {String? fallback}) {
    final value = record[key] ?? fallback;
    if (value is String && value.trim().isNotEmpty && value.length <= 300)
      return value.trim();
    throw FormatException('A valid $key is required.');
  }

  static Map<String, dynamic> _recordMap(Object? value, String field) {
    if (value is Map && value.keys.every((key) => key is String))
      return Map<String, dynamic>.from(value);
    throw FormatException('$field must be an object.');
  }

  static List<String> _stringList(Object? value, List<String> fallback) {
    if (value == null) return List.of(fallback);
    if (value is! List ||
        value.length > 100 ||
        value.any((item) => item is! String || item.length > 100)) {
      throw const FormatException('Expected a list of short text values.');
    }
    return value.cast<String>();
  }

  static int _boundedInt(
      Object? value, String field, int minimum, int maximum) {
    if (value is num &&
        value.isFinite &&
        value == value.roundToDouble() &&
        value >= minimum &&
        value <= maximum) return value.toInt();
    throw FormatException('$field is outside the supported range.');
  }

  static double _boundedDouble(Object? value, String field, double maximum) {
    if (value is num && value.isFinite && value >= 0 && value <= maximum)
      return value.toDouble();
    throw FormatException('$field is outside the supported range.');
  }

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

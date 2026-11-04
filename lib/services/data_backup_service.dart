import 'dart:convert';
import 'dart:io' show File;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
import 'package:isar/isar.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../models/fitness_schema.dart';
import 'database_service.dart';
import 'equipment_profile_service.dart';
import 'theme_service.dart';
import 'widget_service.dart';

class DataBackupService {
  static const _format = 'HybridLog';
  static const _version = 3;
  static const _maxImportBytes = 50 * 1024 * 1024;

  static Future<String?> exportData() async {
    if (kIsWeb) return 'Not supported on web';
    try {
      final db = await DatabaseService().database;
      final exercises = await db.exercises.where().findAll();
      final workouts =
          await db.dailyWorkouts.where().sortByDateDesc().findAll();
      final runs = await db.runningLogs.where().sortByDateDesc().findAll();
      final folders = await db.workoutFolders.where().sortByName().findAll();
      final unavailableEquipment =
          await EquipmentProfileService.loadUnavailable();

      final backup = {
        'format': _format,
        'version': _version,
        'exportedAt': DateTime.now().toUtc().toIso8601String(),
        'themeId': ThemeService().currentThemeId,
        'unavailableEquipment': unavailableEquipment.toList()..sort(),
        'exercises': exercises
            .map((exercise) => {
                  'name': exercise.name,
                  'targetMuscle': exercise.targetMuscle,
                  'targetMuscles': exercise.targetMuscles,
                  'secondaryMuscles': exercise.secondaryMuscles,
                  'isFavorite': exercise.isFavorite,
                  'folderName': exercise.folderName,
                  'folderNames': exercise.folderNames,
                })
            .toList(),
        'workouts': workouts
            .map((workout) => {
                  'date': workout.date.toIso8601String(),
                  'exercises': workout.exercises
                      .map((exercise) => {
                            'exerciseName': exercise.exerciseName,
                            'targetMuscle': exercise.targetMuscle,
                            'targetMuscles': exercise.targetMuscles,
                            'secondaryMuscles': exercise.secondaryMuscles,
                            'sets': exercise.sets
                                .map((set) => {
                                      'reps': set.reps,
                                      'weight': set.weight,
                                      'restPauseSeconds': set.restPauseSeconds,
                                      'subSets': set.subSets
                                          .map((subSet) => {
                                                'reps': subSet.reps,
                                                'weight': subSet.weight,
                                              })
                                          .toList(),
                                    })
                                .toList(),
                          })
                      .toList(),
                })
            .toList(),
        'runs': runs
            .map((run) =>
                {'date': run.date.toIso8601String(), 'miles': run.miles})
            .toList(),
        'folders': folders.map((folder) => {'name': folder.name}).toList(),
      };

      final tempDir = await getTemporaryDirectory();
      final file = File(
          '${tempDir.path}/hybridlog_backup_${DateTime.now().millisecondsSinceEpoch}.json');
      await file.writeAsString(jsonEncode(backup), flush: true);
      final result = await Share.shareXFiles(
        [XFile(file.path)],
        text: 'HybridLog backup. This file contains workout and running data.',
      );
      if (result.status == ShareResultStatus.success) return null;
      return 'Share cancelled or failed';
    } catch (error) {
      debugPrint('Export Error: $error');
      return error.toString();
    }
  }

  static Future<String?> importData() async {
    if (kIsWeb) return 'Not supported on web';
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
      );
      if (result == null || result.files.single.path == null) {
        return 'No file selected';
      }

      final file = File(result.files.single.path!);
      if (await file.length() > _maxImportBytes) {
        return 'Backup file is too large';
      }
      final decoded = jsonDecode(await file.readAsString());
      final backup = _asMap(decoded, 'backup');
      final format = backup['format'];
      if (format != null && format != _format) {
        throw const FormatException('This is not a HybridLog backup.');
      }
      final version = _integer(backup['version'] ?? 1, 'version');
      if (version < 1 || version > _version) {
        throw FormatException('Unsupported backup version: $version.');
      }

      final folders = _readFolders(backup);
      final exercises = _readExercises(backup);
      final workouts = _readWorkouts(backup);
      final runs = _readRuns(backup);
      final themeId = backup['themeId'] == null
          ? null
          : _string(backup['themeId'], 'themeId');
      final unavailableEquipment = backup.containsKey('unavailableEquipment')
          ? _readEquipment(backup['unavailableEquipment'])
          : null;
      if (themeId != null &&
          !ThemeService().themes.any((theme) => theme.id == themeId)) {
        throw const FormatException('Backup contains an unknown theme.');
      }

      final db = await DatabaseService().database;
      await db.writeTxn(() async {
        for (final folder in folders) {
          final existing = await db.workoutFolders
              .filter()
              .nameEqualTo(folder.name)
              .findFirst();
          if (existing == null) await db.workoutFolders.put(folder);
        }

        for (final imported in exercises) {
          final existing = await db.exercises
              .filter()
              .nameEqualTo(imported.name)
              .findFirst();
          if (existing == null) {
            await db.exercises.put(imported);
          } else {
            existing.targetMuscle = imported.targetMuscle;
            existing.targetMuscles = imported.targetMuscles;
            existing.secondaryMuscles = imported.secondaryMuscles;
            existing.isFavorite = imported.isFavorite;
            existing.folderName = imported.folderName;
            existing.folderNames = imported.folderNames;
            await db.exercises.put(existing);
          }
        }

        for (final imported in workouts) {
          final existing = await db.dailyWorkouts
              .filter()
              .dateEqualTo(imported.date)
              .findFirst();
          if (existing == null) {
            await db.dailyWorkouts.put(imported);
          } else {
            existing.exercises =
                _mergeLoggedExercises(existing.exercises, imported.exercises);
            await db.dailyWorkouts.put(existing);
          }
        }

        for (final imported in runs) {
          final existing = await db.runningLogs
              .filter()
              .dateEqualTo(imported.date)
              .findFirst();
          if (existing == null) {
            await db.runningLogs.put(imported);
          } else {
            existing.miles = imported.miles;
            await db.runningLogs.put(existing);
          }
        }
      });

      if (themeId != null) await ThemeService().setTheme(themeId);
      if (unavailableEquipment != null) {
        await EquipmentProfileService.saveUnavailable(unavailableEquipment);
      }
      await WidgetService.updateRunningWidget();
      return null;
    } catch (error) {
      debugPrint('Import Error: $error');
      return error.toString();
    }
  }

  static List<WorkoutFolder> _readFolders(Map<String, dynamic> backup) =>
      _list(backup['folders'], 'folders')
          .map((value) => WorkoutFolder()
            ..name = _string(_asMap(value, 'folder')['name'], 'folder.name'))
          .toList();

  static Set<String> _readEquipment(Object? value) {
    final items = _stringList(value, 'unavailableEquipment', const []);
    if (items
        .any((item) => !EquipmentProfileService.categories.contains(item))) {
      throw const FormatException('Backup contains an unknown equipment type.');
    }
    return items.toSet();
  }

  static List<Exercise> _readExercises(Map<String, dynamic> backup) =>
      _list(backup['exercises'], 'exercises').map((value) {
        final data = _asMap(value, 'exercise');
        final name = _string(data['name'], 'exercise.name');
        final primary = _string(data['targetMuscle'], 'exercise.targetMuscle');
        final folderName =
            _optionalString(data['folderName'], 'exercise.folderName');
        return Exercise()
          ..name = name
          ..targetMuscle = primary
          ..targetMuscles = _stringList(
              data['targetMuscles'], 'exercise.targetMuscles', [primary])
          ..secondaryMuscles = _stringList(
              data['secondaryMuscles'], 'exercise.secondaryMuscles', const [])
          ..isFavorite =
              _optionalBool(data['isFavorite'], 'exercise.isFavorite') ?? false
          ..folderName = folderName
          ..folderNames = _stringList(
              data['folderNames'],
              'exercise.folderNames',
              folderName == null ? const [] : [folderName]);
      }).toList();

  static List<DailyWorkout> _readWorkouts(Map<String, dynamic> backup) =>
      _list(backup['workouts'], 'workouts').map((value) {
        final data = _asMap(value, 'workout');
        final workout = DailyWorkout()
          ..date = _date(data['date'], 'workout.date');
        workout.exercises =
            _list(data['exercises'], 'workout.exercises').map((exerciseValue) {
          final exercise = _asMap(exerciseValue, 'workout exercise');
          final target = _optionalString(
              exercise['targetMuscle'], 'workout exercise.targetMuscle');
          final logged = LoggedExercise()
            ..exerciseName = _optionalString(
                exercise['exerciseName'], 'workout exercise.exerciseName')
            ..targetMuscle = target
            ..targetMuscles = _stringList(
                exercise['targetMuscles'],
                'workout exercise.targetMuscles',
                target == null ? const [] : [target])
            ..secondaryMuscles = _stringList(exercise['secondaryMuscles'],
                'workout exercise.secondaryMuscles', const [])
            ..sets = _list(exercise['sets'], 'workout exercise.sets')
                .map(_readSet)
                .toList();
          return logged;
        }).toList();
        return workout;
      }).toList();

  static SetLog _readSet(Object? value) {
    final data = _asMap(value, 'set');
    final restPause = data['restPauseSeconds'] == null
        ? null
        : _integer(data['restPauseSeconds'], 'set.restPauseSeconds');
    if (restPause != null && (restPause < 0 || restPause > 60)) {
      throw const FormatException(
          'set.restPauseSeconds must be between 0 and 60.');
    }
    return SetLog()
      ..reps = _boundedInteger(data['reps'], 'set.reps', 0, 10000)
      ..weight = _boundedNumber(data['weight'], 'set.weight', 1000000)
      ..restPauseSeconds = restPause
      ..subSets = _list(data['subSets'], 'set.subSets').map((value) {
        final subSet = _asMap(value, 'subset');
        return SubSetLog()
          ..reps = _boundedInteger(subSet['reps'], 'subset.reps', 0, 10000)
          ..weight = _boundedNumber(subSet['weight'], 'subset.weight', 1000000);
      }).toList();
  }

  static List<RunningLog> _readRuns(Map<String, dynamic> backup) =>
      _list(backup['runs'], 'runs').map((value) {
        final data = _asMap(value, 'run');
        return RunningLog()
          ..date = _date(data['date'], 'run.date')
          ..miles = _boundedInteger(data['miles'], 'run.miles', 0, 1000000);
      }).toList();

  static List<LoggedExercise> _mergeLoggedExercises(
      List<LoggedExercise> current, List<LoggedExercise> imported) {
    final merged = List<LoggedExercise>.from(current);
    final positionsByName = <String, List<int>>{};
    for (var i = 0; i < merged.length; i++) {
      final name = merged[i].exerciseName;
      if (name != null) positionsByName.putIfAbsent(name, () => []).add(i);
    }
    final importedOccurrences = <String, int>{};
    for (final exercise in imported) {
      final name = exercise.exerciseName;
      if (name == null) {
        merged.add(exercise);
        continue;
      }
      final occurrence = importedOccurrences.update(name, (value) => value + 1,
          ifAbsent: () => 0);
      final positions = positionsByName.putIfAbsent(name, () => []);
      if (occurrence < positions.length) {
        merged[positions[occurrence]] = exercise;
      } else {
        positions.add(merged.length);
        merged.add(exercise);
      }
    }
    return merged;
  }

  static Map<String, dynamic> _asMap(Object? value, String field) {
    if (value is Map && value.keys.every((key) => key is String)) {
      return Map<String, dynamic>.from(value);
    }
    throw FormatException('$field must be an object.');
  }

  static List<dynamic> _list(Object? value, String field) {
    if (value == null) return const [];
    if (value is List) return value;
    throw FormatException('$field must be a list.');
  }

  static String _string(Object? value, String field) {
    if (value is String && value.trim().isNotEmpty && value.length <= 300) {
      return value;
    }
    throw FormatException('$field must be a non-empty string.');
  }

  static String? _optionalString(Object? value, String field) {
    if (value == null) return null;
    if (value is String && value.length <= 300) return value;
    throw FormatException('$field must be a string or null.');
  }

  static List<String> _stringList(
      Object? value, String field, List<String> fallback) {
    if (value == null) return List<String>.from(fallback);
    if (value is! List || value.any((item) => item is! String)) {
      throw FormatException('$field must contain strings.');
    }
    return List<String>.from(value);
  }

  static bool? _optionalBool(Object? value, String field) {
    if (value == null) return null;
    if (value is bool) return value;
    throw FormatException('$field must be a boolean.');
  }

  static int _integer(Object? value, String field) {
    if (value is int) return value;
    if (value is num && value.isFinite && value == value.roundToDouble()) {
      return value.toInt();
    }
    throw FormatException('$field must be an integer.');
  }

  static double _number(Object? value, String field) {
    if (value is num && value.isFinite && value >= 0) return value.toDouble();
    throw FormatException('$field must be a non-negative number.');
  }

  static int _boundedInteger(
      Object? value, String field, int minimum, int maximum) {
    final parsed = _integer(value, field);
    if (parsed < minimum || parsed > maximum) {
      throw FormatException('$field is outside the supported range.');
    }
    return parsed;
  }

  static double _boundedNumber(Object? value, String field, double maximum) {
    final parsed = _number(value, field);
    if (parsed > maximum) {
      throw FormatException('$field is outside the supported range.');
    }
    return parsed;
  }

  static DateTime _date(Object? value, String field) {
    if (value is String) {
      final parsed = DateTime.tryParse(value);
      if (parsed != null) return parsed;
    }
    throw FormatException('$field must be a valid date.');
  }
}

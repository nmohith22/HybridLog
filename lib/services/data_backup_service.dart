import 'dart:convert';
import 'dart:io' show File;
import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
import 'package:file_picker/file_picker.dart';
import 'package:isar/isar.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../models/fitness_schema.dart';
import 'database_service.dart';

class DataBackupService {
  static Future<String?> exportData() async {
    if (kIsWeb) return 'Not supported on web';
    try {
      final db = await DatabaseService().database;
      
      final exercises = await db.exercises.where().findAll();
      final workouts = await db.dailyWorkouts.where().findAll();
      final runs = await db.runningLogs.where().findAll();
      final folders = await db.workoutFolders.where().findAll();

      final backup = {
        'exercises': exercises.map((e) => {
          'name': e.name,
          'targetMuscle': e.targetMuscle,
          'targetMuscles': e.targetMuscles,
          'secondaryMuscles': e.secondaryMuscles,
          'isFavorite': e.isFavorite,
          'folderName': e.folderName,
          'folderNames': e.folderNames,
        }).toList(),
        'workouts': workouts.map((w) => {
          'date': w.date.toIso8601String(),
          'exercises': w.exercises.map((le) => {
            'exerciseName': le.exerciseName,
            'targetMuscle': le.targetMuscle,
            'targetMuscles': le.targetMuscles,
            'secondaryMuscles': le.secondaryMuscles,
            'sets': le.sets.map((s) => {
              'reps': s.reps,
              'weight': s.weight,
            }).toList(),
          }).toList(),
        }).toList(),
        'runs': runs.map((r) => {
          'date': r.date.toIso8601String(),
          'miles': r.miles,
        }).toList(),
        'folders': folders.map((f) => {
          'name': f.name,
        }).toList(),
      };

      final jsonString = jsonEncode(backup);
      final tempDir = await getTemporaryDirectory();
      final file = File('${tempDir.path}/workout_backup_${DateTime.now().millisecondsSinceEpoch}.json');
      await file.writeAsString(jsonString);

      final result = await Share.shareXFiles([XFile(file.path)], text: 'Workout App Data Backup');
      if (result.status == ShareResultStatus.success) return null; // Success
      return 'Share cancelled or failed';
    } catch (e) {
      debugPrint('Export Error: $e');
      return e.toString();
    }
  }

  static Future<String?> importData() async {
    if (kIsWeb) return 'Not supported on web';
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
      );

      if (result == null || result.files.single.path == null) return 'No file selected';

      final file = File(result.files.single.path!);
      final jsonString = await file.readAsString();
      final backup = jsonDecode(jsonString) as Map<String, dynamic>;

      final db = await DatabaseService().database;

      await db.writeTxn(() async {
        if (backup['folders'] != null) {
          for (var f in backup['folders']) {
            final existing = await db.workoutFolders.filter().nameEqualTo(f['name']).findFirst();
            if (existing == null) {
              final newF = WorkoutFolder()..name = f['name'];
              await db.workoutFolders.put(newF);
            }
          }
        }

        if (backup['exercises'] != null) {
          for (var e in backup['exercises']) {
            final existing = await db.exercises.filter().nameEqualTo(e['name']).findFirst();
            if (existing != null) {
              existing.targetMuscle = e['targetMuscle'];
              existing.targetMuscles = List<String>.from(e['targetMuscles'] ?? (e['targetMuscle'] != null ? [e['targetMuscle']] : []));
              existing.secondaryMuscles = List<String>.from(e['secondaryMuscles'] ?? []);
              existing.isFavorite = e['isFavorite'] ?? false;
              existing.folderName = e['folderName'];
              existing.folderNames = List<String>.from(e['folderNames'] ?? (e['folderName'] != null ? [e['folderName']] : []));
              await db.exercises.put(existing);
            } else {
              final newEx = Exercise()
                ..name = e['name']
                ..targetMuscle = e['targetMuscle']
                ..targetMuscles = List<String>.from(e['targetMuscles'] ?? (e['targetMuscle'] != null ? [e['targetMuscle']] : []))
                ..secondaryMuscles = List<String>.from(e['secondaryMuscles'] ?? [])
                ..isFavorite = e['isFavorite'] ?? false
                ..folderName = e['folderName']
                ..folderNames = List<String>.from(e['folderNames'] ?? (e['folderName'] != null ? [e['folderName']] : []));
              await db.exercises.put(newEx);
            }
          }
        }

        if (backup['workouts'] != null) {
          for (var w in backup['workouts']) {
            final date = DateTime.parse(w['date']);
            var dailyLog = await db.dailyWorkouts.filter().dateEqualTo(date).findFirst();
            dailyLog ??= DailyWorkout()..date = date;

            final List<LoggedExercise> importedExs = [];
            for (var le in w['exercises']) {
              final loggedEx = LoggedExercise()
                ..exerciseName = le['exerciseName']
                ..targetMuscle = le['targetMuscle']
                ..targetMuscles = List<String>.from(le['targetMuscles'] ?? (le['targetMuscle'] != null ? [le['targetMuscle']] : []))
                ..secondaryMuscles = List<String>.from(le['secondaryMuscles'] ?? [])
                ..sets = (le['sets'] as List).map((s) => SetLog()
                  ..reps = s['reps']
                  ..weight = s['weight'].toDouble()
                ).toList();
              importedExs.add(loggedEx);
            }
            dailyLog.exercises = importedExs;
            await db.dailyWorkouts.put(dailyLog);
          }
        }

        if (backup['runs'] != null) {
          for (var r in backup['runs']) {
            final date = DateTime.parse(r['date']);
            var runLog = await db.runningLogs.filter().dateEqualTo(date).findFirst();
            if (runLog != null) {
              runLog.miles = r['miles'];
              await db.runningLogs.put(runLog);
            } else {
              final newRun = RunningLog()
                ..date = date
                ..miles = r['miles'];
              await db.runningLogs.put(newRun);
            }
          }
        }
      });

      return null; // Success
    } catch (e) {
      debugPrint('Import Error: $e');
      return e.toString();
    }
  }
}

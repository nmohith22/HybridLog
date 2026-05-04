import 'package:isar/isar.dart';
import 'package:path_provider/path_provider.dart';
import '../models/fitness_schema.dart';
import 'package:flutter/foundation.dart';

class DatabaseService {
  static final DatabaseService _instance = DatabaseService._internal();
  factory DatabaseService() => _instance;
  DatabaseService._internal();

  Isar? _db;
  Future<Isar>? _initFuture;

  Future<Isar> get database async {
    if (_db != null) return _db!;
    _initFuture ??= _openDatabase();
    return _initFuture!;
  }

  Future<Isar> _openDatabase() async {
    final existing = Isar.getInstance();
    if (existing != null) {
      _db = existing;
      return _db!;
    }
    
    String? directory;
    if (!kIsWeb) {
      final dir = await getApplicationDocumentsDirectory();
      directory = dir.path;
    }

    _db = await Isar.open(
      [ExerciseSchema, DailyWorkoutSchema, RunningLogSchema, WorkoutFolderSchema],
      directory: directory ?? '',
      inspector: kDebugMode,
    );
    return _db!;
  }

  Future<void> saveRunningBlock(DateTime date, int additionalMiles) async {
    final isar = await database;
    final normalizedDate = DateTime(date.year, date.month, date.day);
    
    await isar.writeTxn(() async {
      var log = await isar.runningLogs.filter().dateEqualTo(normalizedDate).findFirst();
      log ??= RunningLog()..date = normalizedDate..miles = 0;
      log.miles += additionalMiles;
      if (log.miles < 0) log.miles = 0; 
      await isar.runningLogs.put(log);
    });
  }

  Future<List<RunningLog>> getRunningLogsForWeek(DateTime startOfWeek) async {
    final isar = await database;
    final endOfWeek = startOfWeek.add(const Duration(days: 6, hours: 23, minutes: 59));
    return await isar.runningLogs.filter().dateBetween(startOfWeek, endOfWeek).findAll();
  }

  Future<List<RunningLog>> getRunningLogsForDateRange(DateTime start, DateTime end) async {
    final isar = await database;
    return await isar.runningLogs.filter().dateBetween(start, end).findAll();
  }

  Stream<void> watchRunningLogs() async* {
    final isar = await database;
    yield* isar.runningLogs.watchLazy();
  }
  }
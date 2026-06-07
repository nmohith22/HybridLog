import 'package:isar/isar.dart';

part 'fitness_schema.g.dart';

// The Master Exercise Dictionary
@collection
class Exercise {
  Id id = Isar.autoIncrement;
  @Index(unique: true, replace: true)
  late String name;
  late String targetMuscle; // Primary muscle (fallback/first)
  List<String> targetMuscles = []; // Multiple main muscles
  List<String> secondaryMuscles = []; // Secondary muscles hit
  bool isFavorite = false;
  String? folderName; // Fallback/first folder
  List<String> folderNames = []; // Multiple folders
}

// A single Set (e.g., 10 reps at 135 lbs)
@embedded
class SetLog {
  int reps = 0;
  double weight = 0.0;
}

// An exercise performed on a specific day
@embedded
class LoggedExercise {
  String? exerciseName;
  String? targetMuscle;
  List<String> targetMuscles = [];
  List<String> secondaryMuscles = [];
  List<SetLog> sets = [];
}

// The History Tab: A specific day's workout
@collection
class DailyWorkout {
  Id id = Isar.autoIncrement;
  @Index()
  late DateTime date;
  List<LoggedExercise> exercises = [];
}

@collection
class RunningLog {
  Id id = Isar.autoIncrement;
  @Index()
  late DateTime date;
  late int miles;
}

@collection
class WorkoutFolder {
  Id id = Isar.autoIncrement;
  @Index(unique: true, replace: true)
  late String name;
}
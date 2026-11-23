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

// Ordered continuation of a main set. Legacy entries represent dropsets.
@embedded
class SubSetLog {
  int reps = 0;
  double weight = 0.0;
  int? pauseSeconds;
  String? exerciseName;
  List<String> targetMuscles = [];
  List<String> secondaryMuscles = [];
}

// A single Set (e.g., 10 reps at 135 lbs)
@embedded
class SetLog {
  int reps = 0;
  double weight = 0.0;
  List<SubSetLog> subSets = [];
  int? restPauseSeconds; // Legacy pause after all dropsets.
}

extension SetSequence on SetLog {
  Iterable<SubSetLog> get sequence sync* {
    yield* subSets;
    if (restPauseSeconds case final seconds?) {
      yield SubSetLog()..pauseSeconds = seconds;
    }
  }

  SetLog editableCopy() => SetLog()
    ..reps = reps
    ..weight = weight
    ..subSets = sequence
        .map((step) => SubSetLog()
          ..reps = step.reps
          ..weight = step.weight
          ..pauseSeconds = step.pauseSeconds
          ..exerciseName = step.exerciseName
          ..targetMuscles = step.targetMuscles.toList()
          ..secondaryMuscles = step.secondaryMuscles.toList())
        .toList();
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

extension WorkoutExerciseSets on DailyWorkout {
  // Project paired sets under the exercise that performed the work.
  Iterable<LoggedExercise> get trainingExercises sync* {
    for (final exercise in exercises) {
      if (!exercise.sets
          .any((set) => set.subSets.any((step) => step.exerciseName != null))) {
        yield exercise;
        continue;
      }
      final base = LoggedExercise()
        ..exerciseName = exercise.exerciseName
        ..targetMuscle = exercise.targetMuscle
        ..targetMuscles = exercise.targetMuscles
        ..secondaryMuscles = exercise.secondaryMuscles;
      final paired = <LoggedExercise>[];
      for (final set in exercise.sets) {
        var work = SetLog()
          ..weight = set.weight
          ..reps = set.reps;
        base.sets.add(work);
        for (final step in set.sequence) {
          if (step.exerciseName case final name?) {
            work = SetLog()
              ..weight = step.weight
              ..reps = step.reps;
            paired.add(LoggedExercise()
              ..exerciseName = name
              ..targetMuscles = step.targetMuscles
              ..secondaryMuscles = step.secondaryMuscles
              ..sets = [work]);
          } else {
            work.subSets.add(step);
          }
        }
      }
      yield base;
      yield* paired;
    }
  }
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

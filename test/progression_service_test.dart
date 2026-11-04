import 'package:flutter_test/flutter_test.dart';
import 'package:workout_app/models/fitness_schema.dart';
import 'package:workout_app/services/progression_service.dart';

DailyWorkout workout(DateTime date, List<(double, int)> sets) => DailyWorkout()
  ..date = date
  ..exercises = [
    LoggedExercise()
      ..exerciseName = 'Bench Press'
      ..sets = sets
          .map((set) => SetLog()
            ..weight = set.$1
            ..reps = set.$2)
          .toList(),
  ];

void main() {
  test('adds a small load after all latest sets reach twelve reps', () {
    final suggestion = ProgressionService.suggestNextTarget('Bench Press', [
      workout(DateTime(2026, 10, 1), [(100, 12), (100, 12), (100, 12)]),
    ]);

    expect(suggestion?.weight, 102.5);
    expect(suggestion?.reps, 8);
    expect(suggestion?.supportingSessions, hasLength(1));
  });

  test('holds load and adds one rep before the top of the range', () {
    final suggestion = ProgressionService.suggestNextTarget('Bench Press', [
      workout(DateTime(2026, 10, 1), [(100, 10), (100, 9), (100, 8)]),
    ]);

    expect(suggestion?.weight, 100);
    expect(suggestion?.reps, 11);
  });

  test('adds reps for bodyweight exercises instead of adding a load', () {
    final suggestion = ProgressionService.suggestNextTarget('Bench Press', [
      workout(DateTime(2026, 10, 1), [(0, 15), (0, 14)]),
    ]);

    expect(suggestion?.weight, 0);
    expect(suggestion?.reps, 16);
  });
}

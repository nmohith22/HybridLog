import 'package:flutter_test/flutter_test.dart';
import 'package:workout_app/models/fitness_schema.dart';
import 'package:workout_app/services/equipment_profile_service.dart';
import 'package:workout_app/services/needle_workout_service.dart';

void main() {
  final benchPress = Exercise()
    ..name = 'Bench Press'
    ..targetMuscle = 'chest';

  test('accepts a valid draft only when exercise and sets match', () {
    final draft = NeedleWorkoutService.parseWorkoutLogResponse(
      '{"exercise_name":"bench press","sets":[{"weight":135,"reps":10},{"weight":135,"reps":9}]}',
      [benchPress],
    );

    expect(draft.exercise, benchPress);
    expect(draft.sets.map((set) => set.reps), [10, 9]);
    expect(draft.sets.first.weight, 135);
  });

  test('rejects unknown exercises and invalid set values', () {
    expect(
      () => NeedleWorkoutService.parseWorkoutLogResponse(
        '{"exercise_name":"Squat","sets":[{"weight":135,"reps":10}]}',
        [benchPress],
      ),
      throwsFormatException,
    );
    expect(
      () => NeedleWorkoutService.parseWorkoutLogResponse(
        '{"exercise_name":"Bench Press","sets":[{"weight":-1,"reps":10}]}',
        [benchPress],
      ),
      throwsFormatException,
    );
  });

  test('accepts a single create proposal as a draft without applying it', () {
    final draft = NeedleWorkoutService.parseWorkoutLogResponse(
      '{"function_calls":[{"name":"manage_data","arguments":{"operation":"create","record_type":"workout","record":{"exercises":[{"name":"Bench Press","sets":[{"weight":135,"reps":10}]}]}}}]}',
      [benchPress],
    );

    expect(draft.exercise, benchPress);
    expect(draft.sets.single.reps, 10);
  });

  test('maps common equipment names to saved profile categories', () {
    expect(EquipmentProfileService.categoriesForExercise('Barbell Row'),
        ['Barbell']);
    expect(EquipmentProfileService.categoriesForExercise('Barbell Bench Press'),
        ['Barbell', 'Bench']);
    expect(EquipmentProfileService.categoriesForExercise('Cable Fly'),
        ['Cable machine']);
    expect(EquipmentProfileService.categoriesForExercise('Push-up'), isEmpty);
  });
}

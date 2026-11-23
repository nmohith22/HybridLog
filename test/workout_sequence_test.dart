import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:workout_app/models/fitness_schema.dart';
import 'package:workout_app/services/exercise_seed.dart';
import 'package:workout_app/services/muscle_fatigue_service.dart';
import 'package:workout_app/services/recovery_predictor.dart';
import 'package:workout_app/widgets/set_sequence_editor.dart';

void main() {
  final now = DateTime(2026, 11, 22, 12);
  DailyWorkout workout(
          String name, List<String> main, List<String> secondary, double weight,
          {List<SubSetLog> steps = const [], int? legacyPause}) =>
      DailyWorkout()
        ..date = now
        ..exercises = [
          LoggedExercise()
            ..exerciseName = name
            ..targetMuscles = main
            ..secondaryMuscles = secondary
            ..sets = [
              SetLog()
                ..reps = 10
                ..weight = weight
                ..subSets = steps
                ..restPauseSeconds = legacyPause,
            ],
        ];

  test('movement weights distinguish direct work and assistance', () {
    double load(String name, String muscle, double weight) {
      final seed =
          initialExercises.firstWhere((entry) => entry['name'] == name);
      return MuscleFatigueService.workoutLoad(workout(
          name,
          [seed['primary'] as String],
          List<String>.from(seed['secondary']),
          weight))[muscle]!;
    }

    expect(load('Barbell Bench Press', 'chest', 135),
        greaterThan(load('Bar Muscle-up', 'chest', 0)));
    expect(load('Dumbbell Lateral Raise', 'side_deltoids', 20),
        greaterThan(load('Hoist Roc-it Shoulder Press', 'side_deltoids', 95)));
    expect(load('Hoist Roc-it Shoulder Press', 'front_deltoids', 95),
        greaterThan(load('Hoist Roc-it Shoulder Press', 'side_deltoids', 95)));
    final custom = MuscleFatigueService.muscleWeights(
      'My cable movement',
      ['chest', 'chest'],
      ['chest', 'triceps'],
    );
    expect(custom, {'chest': 1.0, 'triceps': .30});
    for (final entry in initialExercises) {
      final profile = MuscleFatigueService.muscleWeights(
          entry['name'] as String,
          [entry['primary'] as String],
          List<String>.from(entry['secondary']));
      expect(profile.values.every((weight) => weight.isFinite && weight > 0),
          isTrue);
    }
  });

  test('sequence counts performed work for the correct muscle and decays', () {
    Map<String, double> load(List<SubSetLog> steps, {int? legacyPause}) =>
        MuscleFatigueService.workoutLoad(
          workout('Bench Press', ['chest'], [], 135,
              steps: steps, legacyPause: legacyPause),
        );

    final base = load([]);
    expect(load([], legacyPause: 15), base);
    final drop = SubSetLog()
      ..reps = 5
      ..weight = 95;
    final short = SubSetLog()
      ..pauseSeconds = 10
      ..reps = 4
      ..weight = 95;
    final long = SubSetLog()
      ..pauseSeconds = 60
      ..reps = 4
      ..weight = 95;
    final paired = SubSetLog()
      ..exerciseName = 'Dumbbell Row'
      ..targetMuscles = ['lats']
      ..weight = 35
      ..reps = 10;
    expect(load([drop])['chest'], greaterThan(base['chest']!));
    expect(load([drop, short])['chest'],
        greaterThan(load([drop, long])['chest']!));
    expect(load([drop, paired, short])['chest'], load([drop])['chest']);
    expect(load([drop, paired, short])['lats'],
        greaterThan(load([drop, paired])['lats']!));
    expect(
        load([short, drop])['chest'], lessThan(load([drop, short])['chest']!));

    final sessions = {
      now: {'chest': .4}
    };
    expect(MuscleFatigueService.recentLoad(sessions, now), {'chest': .4});
    expect(
        MuscleFatigueService.recentLoad(
            sessions, now.add(const Duration(days: 7))),
        isEmpty);
    expect(
        RecoveryPredictor.calculateDaysToRecovery(sessions, 'chest', now), 3.5);
  });

  testWidgets('set editor keeps new steps in order across an edit',
      (tester) async {
    final legacy = SetLog()
      ..weight = 90
      ..restPauseSeconds = 12;
    final set = legacy.editableCopy();
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: SingleChildScrollView(
      child: StatefulBuilder(
          builder: (context, update) => SetSequenceEditor(
                set: set,
                onChanged: () => update(() {}),
                chooseExercise: () async => Exercise()
                  ..name = 'Row'
                  ..targetMuscle = 'lats',
              )),
    ))));
    for (final button in [
      'Add dropset',
      'Add rest-pause',
      'Add superset',
      'Add dropset'
    ]) {
      final action = find.text(button);
      await tester.ensureVisible(action);
      await tester.tap(action);
      await tester.pumpAndSettle();
    }
    expect(set.sequence.map((step) => (step.exerciseName, step.pauseSeconds)),
        [(null, 12), (null, null), (null, 15), ('Row', null), (null, null)]);
    final copy = set.editableCopy();
    expect(copy.subSets[3].targetMuscles, ['lats']);
    expect(copy.subSets[2].pauseSeconds, 15);
    expect(tester.takeException(), isNull);
  });
}

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:workout_app/models/fitness_schema.dart';
import 'package:workout_app/services/needle_workout_service.dart';
import 'package:workout_app/services/steel_chat_service.dart';
import 'package:workout_app/widgets/steel_chat_dialog.dart';

void main() {
  testWidgets('Steel opens a chat composer with suggested prompts',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => showDialog<void>(
              context: context,
              builder: (_) => SteelChatDialog(onDataChanged: () {}),
            ),
            child: const Text('Open Steel'),
          ),
        ),
      ),
    ));

    await tester.tap(find.text('Open Steel'));
    await tester.pumpAndSettle();

    expect(find.byType(TextField), findsOneWidget);
    expect(find.text('Ask Steel anything…'), findsOneWidget);
    expect(find.text('Build a workout'), findsOneWidget);
    expect(find.text('Log a workout'), findsOneWidget);
  });

  test('local retrieval puts matching workout records first', () {
    final squat = SteelLocalDocument(
      kind: 'workout',
      label: '2026-11-02 · Barbell squat',
      date: DateTime(2026, 11, 2),
      searchableText: 'Barbell squat quads 2026-11-02',
      evidence: const {'kind': 'workout', 'date': '2026-11-02'},
    );
    final press = SteelLocalDocument(
      kind: 'workout',
      label: '2026-11-01 · Bench press',
      date: DateTime(2026, 11, 1),
      searchableText: 'Bench press chest 2026-11-01',
      evidence: const {'kind': 'workout', 'date': '2026-11-01'},
    );

    final results = SteelChatService.rankDocuments(
      'What did I squat last time?',
      [press, squat],
    );

    expect(results.first, same(squat));
  });

  test('workout draft parser accepts Needle draft tool calls', () {
    final squat = Exercise()
      ..id = 1
      ..name = 'Barbell Squat'
      ..targetMuscle = 'quads';
    final response = jsonEncode({
      'function_calls': [
        {
          'name': 'draft_workout_log',
          'arguments': jsonEncode({
            'exercise_name': 'Barbell Squat',
            'sets': [
              {'weight': 135, 'reps': 10},
              {'weight': 135, 'reps': 9},
            ],
          }),
        },
      ],
    });

    final draft =
        NeedleWorkoutService.parseWorkoutLogResponse(response, [squat]);

    expect(draft.exercise.name, 'Barbell Squat');
    expect(draft.sets.map((set) => (set.weight, set.reps)),
        [(135.0, 10), (135.0, 9)]);
  });
}
